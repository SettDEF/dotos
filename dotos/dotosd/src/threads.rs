//! Threads: the conversation on a task, project or page (docs/teams.md, Teams 1).
//!
//! One JSON-lines file per item under data/threads/, a message per line. This is the local
//! store and the cache: Matrix carries the same messages between people later, the files and
//! these commands stay. Who writes is `me` (config/me.json); an agent writes as `agent:<id>`.

use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Me {
    /// the handle people @mention ("anna")
    pub handle: String,
    /// shown on messages
    pub name: String,
    /// #rrggbb for the avatar dot
    #[serde(default)]
    pub color: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    /// task:<uid> | project:<name> | page:<id>
    pub item: String,
    /// a handle, or agent:<id>
    pub author: String,
    #[serde(default)]
    pub name: String,
    pub text: String,
    /// seconds since the epoch
    pub ts: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<String>,
    /// the @handles in the text
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mentions: Vec<String>,
    /// a voice message: the recording (Ogg Opus), base64, so it travels with the text over LAN sync
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub audio: String,
}

fn me_file() -> PathBuf {
    crate::paths::config_dir().join("me.json")
}

fn dir() -> PathBuf {
    crate::paths::data_dir().join("threads")
}

/// task:abc → task_abc.jsonl (an item key is safe as a file name once : and / are gone)
fn file(item: &str) -> PathBuf {
    let safe: String = item.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '.' { c } else { '_' }).collect();
    dir().join(format!("{safe}.jsonl"))
}

/// Who this is: me.json, else the login name.
pub fn me() -> Me {
    let stored: Option<Me> = std::fs::read_to_string(me_file()).ok().and_then(|s| serde_json::from_str(&s).ok());
    let login = std::env::var("USER").unwrap_or_else(|_| "me".into());
    let mut m = stored.unwrap_or_default();
    if m.handle.is_empty() {
        m.handle = login.clone();
    }
    if m.name.is_empty() {
        m.name = m.handle.clone();
    }
    m
}

/// `dotos me [--name N] [--handle H] [--color #hex]`
pub fn set_me(name: Option<String>, handle: Option<String>, color: Option<String>) -> std::io::Result<Me> {
    let mut m = me();
    if let Some(v) = name { m.name = v; }
    if let Some(v) = handle { m.handle = v.trim_start_matches('@').to_string(); }
    if let Some(v) = color { m.color = v; }
    std::fs::create_dir_all(crate::paths::config_dir())?;
    std::fs::write(me_file(), serde_json::to_string_pretty(&m).unwrap_or_default())?;
    Ok(m)
}

/// An item key from what the user typed: a bare task id is a task.
pub fn item_key(s: &str) -> String {
    if s.contains(':') { s.to_string() } else { format!("task:{s}") }
}

pub fn read(item: &str) -> Vec<Message> {
    let Ok(text) = std::fs::read_to_string(file(item)) else { return Vec::new() };
    let mut v: Vec<Message> = text.lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
    // in time order, whatever order a peer's messages arrived in
    v.sort_by_key(|m| m.ts);
    v
}

fn mentions(text: &str) -> Vec<String> {
    let mut v: Vec<String> = text
        .split(|c: char| c.is_whitespace() || matches!(c, ',' | '.' | '!' | '?' | ':' | ';' | '(' | ')'))
        .filter_map(|w| w.strip_prefix('@'))
        .filter(|h| !h.is_empty())
        .map(|h| h.to_lowercase())
        .collect();
    v.sort();
    v.dedup();
    v
}

/// A new message on an item, by `author` (None: me). Appended, never rewritten.
pub fn say(item: &str, text: &str, reply_to: Option<String>, author: Option<(String, String)>) -> std::io::Result<Message> {
    say_with(item, text, reply_to, author, String::new())
}

/// A voice message: the Ogg file's recording kept in the message, its length as the text.
pub fn voice(item: &str, ogg: &std::path::Path, reply_to: Option<String>) -> std::io::Result<Message> {
    use base64::Engine;
    let bytes = std::fs::read(ogg)?;
    if bytes.len() > 2_000_000 {
        return Err(std::io::Error::other("a voice message is at most ~2 MB (a few minutes)"));
    }
    let secs = std::process::Command::new("ffprobe").args(["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0"]).arg(ogg).output().ok().and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse::<f64>().ok()).unwrap_or(0.0);
    say_with(item, &format!("🎤 voice message · {}:{:02}", secs as u64 / 60, secs as u64 % 60), reply_to, None, base64::engine::general_purpose::STANDARD.encode(bytes))
}

/// Where a voice message's recording is played from (written out once, in the data dir).
pub fn voice_file(m: &Message) -> Option<PathBuf> {
    use base64::Engine;
    if m.audio.is_empty() {
        return None;
    }
    let p = crate::paths::data_dir().join("voice").join(format!("{}.ogg", m.id));
    if !p.exists() {
        let bytes = base64::engine::general_purpose::STANDARD.decode(&m.audio).ok()?;
        std::fs::create_dir_all(p.parent()?).ok()?;
        std::fs::write(&p, bytes).ok()?;
    }
    Some(p)
}

fn say_with(item: &str, text: &str, reply_to: Option<String>, author: Option<(String, String)>, audio: String) -> std::io::Result<Message> {
    let (author, name) = author.unwrap_or_else(|| {
        let m = me();
        (m.handle, m.name)
    });
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
    let msg = Message {
        id: format!("{now:x}{nanos:08x}"),
        item: item.to_string(),
        author,
        name,
        text: text.trim().to_string(),
        ts: now,
        reply_to,
        mentions: mentions(text),
        audio,
    };
    std::fs::create_dir_all(dir())?;
    let mut f = std::fs::OpenOptions::new().create(true).append(true).open(file(item))?;
    writeln!(f, "{}", serde_json::to_string(&msg).unwrap_or_default())?;
    Ok(msg)
}

/// Every message of every thread (what a LAN peer is sent).
pub fn all() -> Vec<Message> {
    let Ok(rd) = std::fs::read_dir(dir()) else { return Vec::new() };
    let mut out = Vec::new();
    for e in rd.flatten() {
        if let Ok(text) = std::fs::read_to_string(e.path()) {
            out.extend(text.lines().filter_map(|l| serde_json::from_str::<Message>(l).ok()));
        }
    }
    out
}

/// Messages from elsewhere (a peer) into their threads: the ones not here yet, in time order.
/// Returns how many were new. Ids are unique per author and time, so the union never conflicts.
pub fn merge(mut msgs: Vec<Message>) -> usize {
    msgs.sort_by_key(|m| m.ts);
    let mut new = 0;
    let mut known: std::collections::HashMap<String, std::collections::HashSet<String>> = Default::default();
    for m in msgs {
        if m.item.is_empty() || m.id.is_empty() {
            continue;
        }
        let ids = known.entry(m.item.clone()).or_insert_with(|| read(&m.item).into_iter().map(|x| x.id).collect());
        if !ids.insert(m.id.clone()) {
            continue;
        }
        if std::fs::create_dir_all(dir()).is_err() {
            break;
        }
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(file(&m.item)) {
            if writeln!(f, "{}", serde_json::to_string(&m).unwrap_or_default()).is_ok() {
                new += 1;
            }
        }
    }
    new
}

/// How many messages each item has, and when the last came: for badges on rows.
pub fn counts() -> serde_json::Map<String, serde_json::Value> {
    let mut out = serde_json::Map::new();
    let Ok(rd) = std::fs::read_dir(dir()) else { return out };
    for e in rd.flatten() {
        let Ok(text) = std::fs::read_to_string(e.path()) else { continue };
        let msgs: Vec<Message> = text.lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
        if let Some(last) = msgs.last() {
            out.insert(last.item.clone(), serde_json::json!({ "count": msgs.len(), "last": last.ts, "last_author": last.author }));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mentions_are_found_and_unique() {
        assert_eq!(mentions("@anna can you look? cc @Bob, @anna"), vec!["anna", "bob"]);
        assert!(mentions("mail me at x@y.z").is_empty());
    }

    #[test]
    fn item_keys() {
        assert_eq!(item_key("abc123"), "task:abc123");
        assert_eq!(item_key("project:loom"), "project:loom");
        assert_eq!(file("task:a/b").file_name().unwrap().to_string_lossy(), "task_a_b.jsonl");
    }
}

/// For `dotos serve`: messages that @mention me (from others, said here or merged from a peer) and
/// tasks newly assigned to me, since the last look. Remembered in state/threads-seen.json.
pub fn news(tasks: &[(String, String, String)]) -> Vec<(String, String, String)> {
    let me = me();
    let f = crate::paths::state_dir().join("threads-seen.json");
    let seen: serde_json::Value = std::fs::read_to_string(&f).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    let first = seen.is_null();
    let last = seen["ts"].as_i64().unwrap_or(0);
    let assigned: std::collections::HashSet<String> = seen["assigned"].as_array().map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect()).unwrap_or_default();
    let mut out = Vec::new();
    let mut newest = last;
    for m in all() {
        newest = newest.max(m.ts);
        if m.ts > last && m.author != me.handle && m.mentions.iter().any(|h| *h == me.handle.to_lowercase()) {
            // "Claude · Fix the build": who, and where; the text without the @me it starts with
            let who = display_name(&m);
            let place = match m.item.split_once(':') {
                Some(("task", uid)) => tasks.iter().find(|(u, _, _)| u == uid).map(|(_, t, _)| t.clone()).unwrap_or_else(|| "a task".into()),
                Some((_, rest)) => rest.split('#').next().unwrap_or(rest).to_string(),
                None => m.item.clone(),
            };
            let mut body = m.text.trim().to_string();
            let at = format!("@{}", me.handle.to_lowercase());
            while body.to_lowercase().starts_with(&at) { body = body[at.len()..].trim_start_matches([' ', ',', ':']).to_string(); }
            out.push((format!("{who} · {place}"), body, m.item.clone()));
        }
    }
    let mut now_assigned = Vec::new();
    for (uid, title, assignee) in tasks {
        if assignee.trim_start_matches('@').eq_ignore_ascii_case(&me.handle) {
            now_assigned.push(uid.clone());
            if !assigned.contains(uid) {
                out.push(("Assigned to you".into(), title.clone(), format!("task:{uid}")));
            }
        }
    }
    let _ = std::fs::create_dir_all(crate::paths::state_dir());
    let _ = std::fs::write(&f, serde_json::json!({ "ts": newest, "assigned": now_assigned }).to_string());
    // the first look only remembers: no flood of old news
    if first { Vec::new() } else { out }
}

/// Teams catch-up: messages by others since the last catch-up (or `since`), grouped per item,
/// newest item first. `mark` remembers now as read (state/catchup.json).
pub fn catchup(since: Option<i64>, mark: bool) -> Vec<(String, Vec<Message>)> {
    let me = me();
    let f = crate::paths::state_dir().join("catchup.json");
    let last = since.unwrap_or_else(|| std::fs::read_to_string(&f).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0));
    let mut by: std::collections::BTreeMap<String, Vec<Message>> = Default::default();
    let mut newest = last;
    for m in all() {
        newest = newest.max(m.ts);
        if m.ts > last && m.author != me.handle {
            by.entry(m.item.clone()).or_default().push(m);
        }
    }
    if mark {
        let _ = std::fs::create_dir_all(crate::paths::state_dir());
        let _ = std::fs::write(&f, newest.to_string());
    }
    let mut out: Vec<(String, Vec<Message>)> = by.into_iter().collect();
    out.sort_by_key(|(_, v)| std::cmp::Reverse(v.iter().map(|m| m.ts).max().unwrap_or(0)));
    out
}

// ── the team's people (learnt from LAN sync: each side says who it is) ──

fn people_file() -> PathBuf {
    crate::paths::state_dir().join("team-people.json")
}

/// Everyone met over LAN sync, and me, by handle.
pub fn people() -> Vec<Me> {
    let mut v: Vec<Me> = std::fs::read_to_string(people_file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    let me = me();
    v.retain(|p| p.handle != me.handle);
    v.insert(0, me);
    v
}

/// A teammate as their Dotos introduced itself.
pub fn meet(p: Me) {
    if p.handle.is_empty() || p.handle == me().handle || p.handle.contains(|c: char| c.is_whitespace() || c == '@') {
        return;
    }
    let mut v: Vec<Me> = std::fs::read_to_string(people_file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    v.retain(|x| x.handle != p.handle);
    v.push(p);
    let _ = std::fs::create_dir_all(crate::paths::state_dir());
    let _ = std::fs::write(people_file(), serde_json::to_string(&v).unwrap_or_default());
}

/// A message's author as people read it: agent:claude → Claude, agent:claude@anna → Claude (anna).
pub fn display_name(m: &Message) -> String {
    match m.author.strip_prefix("agent:") {
        Some(a) => {
            let (name, host) = a.split_once('@').map(|(n, h)| (n, Some(h))).unwrap_or((a, None));
            let mut n = name.to_string();
            if let Some(c) = n.get(..1) { n = c.to_uppercase() + &n[1..]; }
            match host { Some(h) => format!("{n} ({h})"), None => n }
        }
        None if !m.name.is_empty() => m.name.clone(),
        None => m.author.clone(),
    }
}
