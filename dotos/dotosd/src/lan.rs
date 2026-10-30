//! LAN sync (docs/teams.md, Teams 1b): Dotos on the same network share threads, no server.
//!
//! A team is a random key (config/team.json); `dotos lan code` shows it, `dotos lan join CODE`
//! takes it. Each Dotos listens on TCP (47820) and says where once every 20 s by UDP broadcast
//! (47821, only the team's id, never the key). A sync is one connection: both prove they hold
//! the key (HMAC over two nonces), then each sends its messages and keeps the union by id.
//! Authenticated, not yet encrypted: fine on a home or office network, not on a café's.

use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::{BufRead, BufReader, Write};
use std::net::{SocketAddr, TcpListener, TcpStream, UdpSocket};
use std::path::PathBuf;
use std::time::{Duration, Instant};

use crate::threads;

const TCP_PORT: u16 = 47820;
const UDP_PORT: u16 = 47821;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Team {
    pub name: String,
    /// 32 random bytes, hex
    pub key: String,
}

impl Team {
    /// What the network sees: a short hash of the key, so peers of another team are ignored.
    pub fn id(&self) -> String {
        let h = Sha256::digest(self.key.as_bytes());
        h.iter().take(6).map(|b| format!("{b:02x}")).collect()
    }
    /// The join code: the key in groups of eight, easy to read out.
    pub fn code(&self) -> String {
        self.key.as_bytes().chunks(8).map(|c| String::from_utf8_lossy(c).to_string()).collect::<Vec<_>>().join("-")
    }
}

fn team_file() -> PathBuf {
    crate::paths::config_dir().join("team.json")
}
fn peers_file() -> PathBuf {
    crate::paths::state_dir().join("lan-peers.json")
}

pub fn team() -> Option<Team> {
    std::fs::read_to_string(team_file()).ok().and_then(|s| serde_json::from_str(&s).ok())
}

fn save_team(t: &Team) -> Result<(), String> {
    std::fs::create_dir_all(crate::paths::config_dir()).map_err(|e| e.to_string())?;
    std::fs::write(team_file(), serde_json::to_string_pretty(t).unwrap_or_default()).map_err(|e| e.to_string())?;
    // the key is the team: only this user reads it
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(team_file(), std::fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

fn random_hex(n: usize) -> String {
    let mut b = vec![0u8; n];
    getrandom::getrandom(&mut b).expect("random bytes");
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// `dotos lan init [NAME]`: a new team, this machine its first member.
pub fn init(name: &str) -> Result<Team, String> {
    if team().is_some() {
        return Err("already in a team (dotos lan code shows its join code; dotos lan leave to start over)".into());
    }
    let t = Team { name: name.to_string(), key: random_hex(32) };
    save_team(&t)?;
    Ok(t)
}

/// `dotos lan join CODE [NAME]`
pub fn join(code: &str, name: &str) -> Result<Team, String> {
    let key: String = code.chars().filter(|c| c.is_ascii_hexdigit()).collect::<String>().to_lowercase();
    if key.len() != 64 {
        return Err("that is not a team code (64 hex digits, dashes allowed)".into());
    }
    let t = Team { name: name.to_string(), key };
    save_team(&t)?;
    Ok(t)
}

pub fn leave() -> Result<(), String> {
    std::fs::remove_file(team_file()).map_err(|e| e.to_string())
}

fn mac(key: &str, tag: &str, a: &str, b: &str) -> String {
    let mut m = <Hmac<Sha256> as Mac>::new_from_slice(key.as_bytes()).expect("any key length");
    m.update(tag.as_bytes());
    m.update(a.as_bytes());
    m.update(b.as_bytes());
    m.finalize().into_bytes().iter().map(|x| format!("{x:02x}")).collect()
}

fn send(s: &mut TcpStream, v: &Value) -> std::io::Result<()> {
    writeln!(s, "{v}")?;
    s.flush()
}
fn recv(r: &mut BufReader<TcpStream>) -> Result<Value, String> {
    let mut line = String::new();
    r.read_line(&mut line).map_err(|e| e.to_string())?;
    serde_json::from_str(&line).map_err(|_| "the peer said something that is not Dotos".to_string())
}

/// One sync as the caller: prove, send ours, take theirs. Returns how many messages were new here.
pub fn sync_with(addr: SocketAddr, t: &Team) -> Result<usize, String> {
    let mut s = TcpStream::connect_timeout(&addr, Duration::from_secs(3)).map_err(|e| format!("{addr}: {e}"))?;
    s.set_read_timeout(Some(Duration::from_secs(10))).ok();
    let mut r = BufReader::new(s.try_clone().map_err(|e| e.to_string())?);
    let n1 = random_hex(16);
    send(&mut s, &json!({ "team": t.id(), "nonce": n1 })).map_err(|e| e.to_string())?;
    let hello = recv(&mut r).map_err(|_| format!("{addr}: refused (a Dotos of another team, or not Dotos)"))?;
    let n2 = hello["nonce"].as_str().unwrap_or_default().to_string();
    if hello["mac"].as_str() != Some(mac(&t.key, "server", &n1, &n2).as_str()) {
        return Err(format!("{addr}: not in this team"));
    }
    send(&mut s, &json!({ "mac": mac(&t.key, "client", &n1, &n2) })).map_err(|e| e.to_string())?;
    send(&mut s, &json!({ "msgs": threads::all(), "lists": lists_payload(), "me": threads::me() })).map_err(|e| e.to_string())?;
    let theirs = recv(&mut r)?;
    let msgs: Vec<threads::Message> = serde_json::from_value(theirs["msgs"].clone()).unwrap_or_default();
    if let Ok(p) = serde_json::from_value::<threads::Me>(theirs["me"].clone()) { threads::meet(p); }
    let n = threads::merge(msgs) + merge_lists(&theirs["lists"]);
    if n > 0 { crate::thread_agent::dispatch_remote(); }
    Ok(n)
}

/// One sync as the one asked (a peer connected to us).
fn answer(s: TcpStream, t: &Team) -> Result<usize, String> {
    s.set_read_timeout(Some(Duration::from_secs(10))).ok();
    let mut w = s.try_clone().map_err(|e| e.to_string())?;
    let mut r = BufReader::new(s);
    let hello = recv(&mut r)?;
    if hello["team"].as_str() != Some(t.id().as_str()) {
        return Err("a peer of another team".into());
    }
    let n1 = hello["nonce"].as_str().unwrap_or_default().to_string();
    let n2 = random_hex(16);
    send(&mut w, &json!({ "nonce": n2, "mac": mac(&t.key, "server", &n1, &n2) })).map_err(|e| e.to_string())?;
    let proof = recv(&mut r)?;
    if proof["mac"].as_str() != Some(mac(&t.key, "client", &n1, &n2).as_str()) {
        return Err("a peer without the team key".into());
    }
    let theirs = recv(&mut r)?;
    let msgs: Vec<threads::Message> = serde_json::from_value(theirs["msgs"].clone()).unwrap_or_default();
    // ours as they were before theirs came in is enough: they have their own already
    send(&mut w, &json!({ "msgs": threads::all(), "lists": lists_payload(), "me": threads::me() })).map_err(|e| e.to_string())?;
    if let Ok(p) = serde_json::from_value::<threads::Me>(theirs["me"].clone()) { threads::meet(p); }
    let n = threads::merge(msgs) + merge_lists(&theirs["lists"]);
    if n > 0 { crate::thread_agent::dispatch_remote(); }
    Ok(n)
}

fn port() -> u16 {
    std::env::var("DOTOS_LAN_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(TCP_PORT)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Peer {
    pub addr: String,
    pub host: String,
    pub who: String,
    pub seen: i64,
}

pub fn peers() -> Vec<Peer> {
    std::fs::read_to_string(peers_file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

fn remember(p: Peer) {
    let mut all = peers();
    all.retain(|q| q.addr != p.addr);
    all.push(p);
    let _ = std::fs::create_dir_all(crate::paths::state_dir());
    let _ = std::fs::write(peers_file(), serde_json::to_string_pretty(&all).unwrap_or_default());
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname").map(|s| s.trim().to_string()).unwrap_or_else(|_| "dotos".into())
}

/// Listens for discovery broadcasts for `wait`; the team's peers found are remembered.
fn discover(t: &Team, wait: Duration, my_port: u16) -> Vec<SocketAddr> {
    let Ok(sock) = UdpSocket::bind(("0.0.0.0", UDP_PORT)) else { return Vec::new() };
    let _ = sock.set_read_timeout(Some(Duration::from_millis(300)));
    let end = Instant::now() + wait;
    let mut found = Vec::new();
    let mut buf = [0u8; 1024];
    while Instant::now() < end {
        let Ok((n, from)) = sock.recv_from(&mut buf) else { continue };
        let Ok(v) = serde_json::from_slice::<Value>(&buf[..n]) else { continue };
        if v["dotos"].as_str() != Some(t.id().as_str()) {
            continue;
        }
        let p = v["port"].as_u64().unwrap_or(TCP_PORT as u64) as u16;
        let addr = SocketAddr::new(from.ip(), p);
        // ourselves, heard back
        if v["host"].as_str() == Some(hostname().as_str()) && p == my_port {
            continue;
        }
        remember(Peer { addr: addr.to_string(), host: v["host"].as_str().unwrap_or("").into(), who: v["who"].as_str().unwrap_or("").into(), seen: now() });
        if !found.contains(&addr) {
            found.push(addr);
        }
    }
    found
}

fn announce(t: &Team, my_port: u16) {
    let Ok(sock) = UdpSocket::bind(("0.0.0.0", 0)) else { return };
    let _ = sock.set_broadcast(true);
    let msg = json!({ "dotos": t.id(), "port": my_port, "host": hostname(), "who": threads::me().handle }).to_string();
    let _ = sock.send_to(msg.as_bytes(), ("255.255.255.255", UDP_PORT));
}

/// `dotos lan sync [--peer HOST:PORT]…`: one round with the given peers, or with those that
/// announce themselves within a few seconds (and those seen in the last hour).
pub fn sync_once(given: &[String]) -> Result<Value, String> {
    let t = team().ok_or("not in a team: dotos lan init, or dotos lan join CODE")?;
    let mut addrs: Vec<SocketAddr> = given.iter().filter_map(|a| a.parse().ok()).collect();
    if addrs.is_empty() {
        addrs = discover(&t, Duration::from_secs(3), 0);
        for p in peers().into_iter().filter(|p| now() - p.seen < 3600) {
            if let Ok(a) = p.addr.parse::<SocketAddr>() {
                if !addrs.contains(&a) {
                    addrs.push(a);
                }
            }
        }
    }
    let mut results = Vec::new();
    for a in addrs {
        match sync_with(a, &t) {
            Ok(n) => results.push(json!({ "peer": a.to_string(), "new": n })),
            Err(e) => results.push(json!({ "peer": a.to_string(), "error": e })),
        }
    }
    Ok(json!({ "team": t.name, "id": t.id(), "peers": results }))
}

/// `dotos lan serve` (and inside `dotos serve`): answer peers, announce, sync every 30 s.
/// Runs until the process ends; returns at once when there is no team.
pub fn run() -> Result<(), String> {
    let t = team().ok_or("not in a team")?;
    let listener = TcpListener::bind(("0.0.0.0", port())).map_err(|e| format!("port {}: {e}", port()))?;
    let my_port = listener.local_addr().map(|a| a.port()).unwrap_or(port());
    eprintln!("dotos lan: team {} ({}) on port {my_port}", t.name, t.id());
    {
        let t = t.clone();
        std::thread::spawn(move || {
            for s in listener.incoming().flatten() {
                let t = t.clone();
                std::thread::spawn(move || match answer(s, &t) {
                    Ok(n) if n > 0 => eprintln!("dotos lan: {n} new from a peer"),
                    Ok(_) => {}
                    Err(e) => eprintln!("dotos lan: {e}"),
                });
            }
        });
    }
    // discovery: listen all the time (in its own thread), announce every 20 s, sync every 30 s
    {
        let t = t.clone();
        std::thread::spawn(move || loop {
            discover(&t, Duration::from_secs(60), my_port);
        });
    }
    let mut last_sync = Instant::now() - Duration::from_secs(60);
    loop {
        announce(&t, my_port);
        if last_sync.elapsed() >= Duration::from_secs(30) {
            last_sync = Instant::now();
            for p in peers().into_iter().filter(|p| now() - p.seen < 300) {
                if let Ok(a) = p.addr.parse() {
                    match sync_with(a, &t) {
                        Ok(n) if n > 0 => eprintln!("dotos lan: {n} new from {}", p.addr),
                        Ok(_) => {}
                        Err(e) => eprintln!("dotos lan: {e}"),
                    }
                }
            }
        }
        std::thread::sleep(Duration::from_secs(20));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_round_trip_and_ids_differ_by_key() {
        let t = Team { name: "a".into(), key: "ab".repeat(32) };
        let code = t.code();
        let back: String = code.chars().filter(|c| c.is_ascii_hexdigit()).collect();
        assert_eq!(back, t.key);
        let u = Team { name: "a".into(), key: "cd".repeat(32) };
        assert_ne!(t.id(), u.id());
        assert_eq!(t.id().len(), 12);
    }

    #[test]
    fn macs_depend_on_key_role_and_nonces() {
        let k = "k".repeat(64);
        assert_ne!(mac(&k, "server", "a", "b"), mac(&k, "client", "a", "b"));
        assert_ne!(mac(&k, "server", "a", "b"), mac(&k, "server", "a", "c"));
        assert_ne!(mac(&k, "server", "a", "b"), mac(&"j".repeat(64), "server", "a", "b"));
    }
}

// ── shared lists (Teams T8, no server): a task list both sides share travels with the threads ──
// One file per task; the newer file (by its modification time) wins. A task deleted on one side
// is not deleted on the other (no tombstones yet): mark it done instead.

fn shared_file() -> PathBuf {
    crate::paths::config_dir().join("shared-lists.json")
}

/// The task lists this Dotos shares with its team.
pub fn shared() -> Vec<String> {
    std::fs::read_to_string(shared_file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

pub fn share(list: &str, on: bool) -> Result<Vec<String>, String> {
    let store = icalcore::store::Store::open(crate::DOTOS);
    if on && !store.calendars().iter().any(|c| c.name == list) {
        return Err(format!("no list named {list}"));
    }
    let mut v = shared();
    v.retain(|l| l != list);
    if on {
        v.push(list.to_string());
    }
    std::fs::create_dir_all(crate::paths::config_dir()).map_err(|e| e.to_string())?;
    std::fs::write(shared_file(), serde_json::to_string(&v).unwrap_or_default()).map_err(|e| e.to_string())?;
    Ok(v)
}

/// What we send: each shared list's task files, with their modification times.
fn lists_payload() -> Value {
    let store = icalcore::store::Store::open(crate::DOTOS);
    let mine = shared();
    let mut out = serde_json::Map::new();
    for c in store.calendars().into_iter().filter(|c| mine.contains(&c.name)) {
        let files: Vec<Value> = std::fs::read_dir(&c.path).into_iter().flatten().flatten().filter(|e| e.path().extension().is_some_and(|x| x == "ics")).filter_map(|e| {
            let mtime = e.metadata().ok()?.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?.as_secs();
            Some(json!({ "file": e.file_name().to_string_lossy(), "mtime": mtime, "data": std::fs::read_to_string(e.path()).ok()? }))
        }).collect();
        out.insert(c.name, Value::Array(files));
    }
    Value::Object(out)
}

/// Their files into the lists we share too: new ones and newer ones. Returns how many changed.
fn merge_lists(v: &Value) -> usize {
    let store = icalcore::store::Store::open(crate::DOTOS);
    let mine = shared();
    let mut n = 0;
    for (list, files) in v.as_object().into_iter().flatten() {
        if !mine.contains(list) {
            continue;
        }
        let Some(c) = store.calendars().into_iter().find(|c| c.name == *list) else { continue };
        for f in files.as_array().into_iter().flatten() {
            let (Some(name), Some(mtime), Some(data)) = (f["file"].as_str(), f["mtime"].as_u64(), f["data"].as_str()) else { continue };
            // a file name only, never a path out of the list
            if name.contains('/') || name.starts_with('.') || !name.ends_with(".ics") || !data.contains("BEGIN:VTODO") {
                continue;
            }
            let path = c.path.join(name);
            let ours = std::fs::metadata(&path).ok().and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs());
            if ours.is_some_and(|o| o >= mtime) || std::fs::read_to_string(&path).ok().as_deref() == Some(data) {
                continue;
            }
            let old = std::fs::read_to_string(&path).ok().and_then(|s| icalcore::todo::parse(&s, list).into_iter().next());
            let tmp = c.path.join(format!(".{name}.lan"));
            if std::fs::write(&tmp, data).is_ok() && std::fs::rename(&tmp, &path).is_ok() {
                if let Ok(f) = std::fs::File::options().write(true).open(&path) {
                    let _ = f.set_modified(std::time::UNIX_EPOCH + Duration::from_secs(mtime));
                }
                // in the change log as the teammate's (History, the task's own history)
                if let Some(new) = icalcore::todo::parse(data, list).into_iter().next() {
                    let by = crate::model::get(&new, "BY").unwrap_or_else(|| "peer".into());
                    crate::log::record_as(&format!("team:{by}"), if old.is_some() { "edit" } else { "add" }, &new, old.as_ref());
                }
                n += 1;
            }
        }
    }
    if n > 0 {
        store.reindex();
    }
    n
}
