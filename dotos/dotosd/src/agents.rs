//! AI sessions, as the shell's ai-activity hooks recorded them.
//!
//! One JSON document per session in each source's directory:
//!   - QuickShell/Claude Code → `$XDG_RUNTIME_DIR/ai-activity` (`.json`, one per session)
//!   - Hermes                → `$HERMES_RUNTIME_DIR/hermes/active_sessions.json` (`.json`, list)
//!   - OpenClaw              → `$XDG_CONFIG_HOME/openclaw/agents/main/sessions` (`.jsonl`, one per session)
//!
//! Read-only here: Dotos shows agents and links tasks to them; it never writes
//! their state.

use serde_json::{json, Value};
use std::path::PathBuf;

/// One source of agent sessions: a directory holding one document per live
/// session, plus a parser that normalises each document into the common shape.
struct Source {
    name: &'static str,
    dir: PathBuf,
    ext: &'static str,
    parse: fn(Value) -> Vec<Value>,
}

/// Default agent sources (QuickShell/Claude, Hermes, OpenClaw).
fn sources() -> Vec<Source> {
    vec![
        Source {
            name: "QuickShell/Claude",
            dir: quickshell_dir(),
            ext: "json",
            parse: parse_quickshell,
        },
        Source {
            name: "Hermes",
            dir: hermes_dir(),
            ext: "json",
            parse: parse_hermes,
        },
        Source {
            name: "OpenClaw",
            dir: openclaw_dir(),
            ext: "jsonl",
            parse: parse_openclaw,
        },
    ]
}

fn quickshell_dir() -> PathBuf {
    if let Some(d) = std::env::var_os("DOTOS_AGENTS_DIR") {
        return PathBuf::from(d);
    }
    PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into())).join("ai-activity")
}

fn hermes_dir() -> PathBuf {
    let mut p = PathBuf::from(std::env::var("HERMES_RUNTIME_DIR").unwrap_or_else(|_| std::env::var("HOME").unwrap_or_default()));
    p.push(".hermes/runtime");
    p
}

fn openclaw_dir() -> PathBuf {
    let mut p = PathBuf::from(std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| std::env::var("HOME").unwrap_or_default()));
    p.push(".openclaw/agents/main/sessions");
    p
}

fn files_with_ext(dir: &PathBuf, ext: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(rd) = std::fs::read_dir(dir) {
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().map_or(false, |x| x.to_string_lossy() == ext) {
                out.push(p);
            }
        }
    }
    out
}

/// Normalises a QuickShell/Claude session: one `.json` file = one session.
fn parse_quickshell(v: Value) -> Vec<Value> {
    vec![v]
}

/// Hermes `active_sessions.json` → one session per `entries[]`.
fn parse_hermes(v: Value) -> Vec<Value> {
    let mut out = Vec::new();
    if let Some(entries) = v.get("entries").and_then(|e| e.as_array()) {
        for e in entries {
            let empty = serde_json::Map::new();
            let m = e.get("metadata").and_then(|m| m.as_object()).unwrap_or(&empty);
            let live = m
                .get("live_session_id")
                .and_then(|s| s.as_str())
                .unwrap_or("unknown");
            let started = e
                .get("started_at")
                .and_then(|s| s.as_u64())
                .unwrap_or(0);
            let updated = e
                .get("updated_at")
                .and_then(|s| s.as_u64())
                .unwrap_or(0);
            let surface = e
                .get("surface")
                .and_then(|s| s.as_str())
                .unwrap_or("cli");
            let state = if surface == "gateway" { "working" } else { "ready" };
            let session_id = live.to_string();
            out.push(json!({
                "id": live,
                "source": "hermes",
                "session": session_id,
                "cwd": "",
                "started": started,
                "updated": updated,
                "pid": e.get("pid").and_then(|p| p.as_u64()).unwrap_or(0),
                "tools": 0,
                "state": state,
                "last_tool": "",
                "prompt": "",
                "project": "",
                "message": "",
                "dotos_tasks": json!({}),
            }));
        }
    }
    out
}

/// OpenClaw `*.jsonl` → one session per file, state derived from events.
fn parse_openclaw(v: Value) -> Vec<Value> {
    let mut out = Vec::new();
    let mut sessions: Vec<(String, Value, u64, String)> = Vec::new();
    for line in v.as_str().unwrap_or("").lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Ok(ev) = serde_json::from_str::<Value>(line) {
            if let Some(t) = ev.get("type").and_then(|t| t.as_str()) {
                if t == "session" {
                    let id = ev
                        .get("id")
                        .and_then(|s| s.as_str())
                        .unwrap_or("unknown")
                        .to_string();
                    let cwd = ev
                        .get("cwd")
                        .and_then(|s| s.as_str())
                        .unwrap_or("")
                        .to_string();
                    let started = ev
                        .get("timestamp")
                        .and_then(|s| s.as_u64())
                        .unwrap_or(0);
                    sessions.push((format!("openclaw-{}", id), ev, started, cwd));
                }
            }
        }
    }
    for (id, first, started, cwd) in sessions {
        let mut state = "working";
        let mut has_error = false;
        if let Some(children) = first.get("children").and_then(|c| c.as_array()) {
            for ev in children {
                if ev.get("role").and_then(|r| r.as_str()) == Some("assistant") {
                    if ev
                        .get("stopReason")
                        .and_then(|s| s.as_str())
                        .unwrap_or("") == "error"
                    {
                        has_error = true;
                    }
                }
            }
        }
        if has_error {
            state = "ended";
        }
        out.push(json!({
            "id": id,
            "source": "openclaw",
            "session": id,
            "cwd": cwd,
            "started": started,
            "updated": started,
            "pid": 0,
            "tools": 0,
            "state": state,
            "last_tool": "",
            "prompt": "",
            "project": "",
            "message": "",
            "dotos_tasks": json!({}),
        }));
    }
    out
}

/// All agent sessions from every configured source, sorted newest first.
pub fn list_all() -> Vec<Value> {
    let mut out: Vec<Value> = Vec::new();
    for src in sources() {
        for p in files_with_ext(&src.dir, src.ext) {
            if let Ok(content) = std::fs::read_to_string(&p) {
                if let Ok(v) = serde_json::from_str::<Value>(&content) {
                    out.extend((src.parse)(v));
                }
            }
        }
    }
    // every running Claude Code: one with no session file yet (resumed, idle since a relogin, its
    // hook not run since) still counts, as "idle", until its hook writes the real one
    let known: std::collections::HashSet<u64> = out.iter().filter_map(|v| v["pid"].as_u64()).collect();
    out.extend(unreported_claudes(&known));
    // a Claude Code session's own task list (TaskCreate / TaskUpdate), as Claude keeps it
    for v in &mut out {
        if let Some(sid) = v["id"].as_str().and_then(|i| i.strip_prefix("claude-")) {
            let t = claude_tasks(sid);
            if !t.is_empty() {
                v["claude_tasks"] = Value::from(t);
            }
        }
    }
    out.sort_by_key(|v| std::cmp::Reverse(v["updated"].as_u64().unwrap_or(0)));
    out
}

/// QuickShell/Claude Code sessions only — kept for backward compatibility.
pub fn list() -> Vec<Value> {
    list_from(&quickshell_dir(), "json", parse_quickshell)
}

fn list_from(dir: &PathBuf, ext: &str, parse: fn(Value) -> Vec<Value>) -> Vec<Value> {
    let mut out: Vec<Value> = Vec::new();
    for p in files_with_ext(dir, ext) {
        if let Ok(content) = std::fs::read_to_string(&p) {
            if let Ok(v) = serde_json::from_str::<Value>(&content) {
                out.extend(parse(v));
            }
        }
    }
    // A session whose process is gone has ended, whatever the file says
    // (only when pid is known, so OpenClaw's pid:0 stays "working").
    for v in &mut out {
        if let Some(p) = v["pid"].as_u64() {
            if p > 0 && !std::path::Path::new(&format!("/proc/{p}")).exists() {
                v["state"] = Value::from("ended");
            }
        }
    }
    out.sort_by_key(|v| std::cmp::Reverse(v["updated"].as_u64().unwrap_or(0)));
    out
}

/// Sessions working inside `path` (a project folder), from **all** sources.
pub fn in_dir<'a>(all: &'a [Value], path: &str) -> Vec<&'a Value> {
    all.iter().filter(|a| a["cwd"].as_str().is_some_and(|c| c == path || c.starts_with(&format!("{path}/")))).collect()
}

/// `XDG_STATE_HOME/ai-activity/<id>.jsonl` — one JSON line per action, kept
/// across reboots, the same hook file the CLI writes to.
fn log_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".local/state"))
        .join("ai-activity")
}

/// A session's actions, oldest first (an empty list for one that logged none).
pub fn actions(id: &str) -> Vec<Value> {
    let id: String = id.trim_start_matches("agent:").chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-').collect();
    std::fs::read_to_string(log_dir().join(format!("{id}.jsonl"))).unwrap_or_default().lines().filter_map(|l| serde_json::from_str(l).ok()).collect()
}

/// The files a session changed, newest action last per file: (path, last kind, times, card it
/// was working on then). Reads are left out: they change nothing.
pub fn touched(acts: &[Value]) -> Vec<(String, String, usize, String)> {
    let mut out: Vec<(String, String, usize, String)> = Vec::new();
    for a in acts {
        let kind = a["kind"].as_str().unwrap_or("");
        if !matches!(kind, "write" | "create" | "edit" | "delete") || a["ok"] == false {
            continue;
        }
        let Some(p) = a["what"].as_str().filter(|p| !p.is_empty()) else { continue };
        let task = a["task"].as_str().unwrap_or("").to_string();
        match out.iter_mut().find(|x| x.0 == p) {
            Some(x) => {
                x.1 = kind.to_string();
                x.2 += 1;
                if !task.is_empty() {
                    x.3 = task;
                }
            }
            None => out.push((p.to_string(), kind.to_string(), 1, task)),
        }
    }
    out
}

/// Counts per kind and the failures, for a session's summary.
pub fn summary(acts: &[Value]) -> Value {
    let mut m = serde_json::Map::new();
    for a in acts {
        let k = a["kind"].as_str().unwrap_or("tool");
        let n = m.get(k).and_then(|v| v.as_u64()).unwrap_or(0) + 1;
        m.insert(k.to_string(), Value::from(n));
    }
    m.insert("failed".into(), Value::from(acts.iter().filter(|a| a["ok"] == false).count()));
    m.insert("total".into(), Value::from(acts.len()));
    Value::Object(m)
}

/// `~/.claude/tasks/<session>/<n>.json`: the session's tasks (id, subject, status pending |
/// in_progress | completed, activeForm, blockedBy), in their order.
pub fn claude_tasks(session: &str) -> Vec<Value> {
    let dir = PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".claude/tasks").join(session);
    let mut out: Vec<Value> = files_with_ext(&dir, "json")
        .into_iter()
        .filter_map(|p| serde_json::from_str::<Value>(&std::fs::read_to_string(p).ok()?).ok())
        .filter(|t| t["status"].as_str() != Some("deleted"))
        .map(|t| serde_json::json!({ "id": t["id"], "subject": t["subject"], "description": t["description"], "status": t["status"], "active": t["activeForm"], "blocked_by": t["blockedBy"] }))
        .collect();
    out.sort_by_key(|t| t["id"].as_str().and_then(|s| s.parse::<u64>().ok()).unwrap_or(u64::MAX));
    track(session, &mut out);
    out
}

/// What changed in a session's tasks since the last look (state/claude-tasks/<session>.json keeps
/// each task's status and when it last changed): each change goes to the log (History), and each
/// task gets `since`. The first look only remembers (a long session does not flood History).
fn track(session: &str, tasks: &mut [Value]) {
    let path = crate::paths::state_dir().join("claude-tasks").join(format!("{session}.json"));
    let first = !path.exists();
    let mut seen: serde_json::Map<String, Value> = std::fs::read_to_string(&path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let mut changed = first;
    for t in tasks.iter_mut() {
        let (Some(id), Some(status)) = (t["id"].as_str().map(String::from), t["status"].as_str().map(String::from)) else { continue };
        let subject = t["subject"].as_str().unwrap_or("").to_string();
        let was = seen.get(&id).and_then(|v| v["status"].as_str()).map(String::from);
        if was.as_deref() != Some(status.as_str()) {
            if !first {
                let op = match (was.as_deref(), status.as_str()) {
                    (_, "completed") => "done",
                    (_, "in_progress") => "start",
                    (None, _) => "new",
                    _ => "reopen",
                };
                crate::log::record_claude(op, session, &id, &subject);
            }
            seen.insert(id.clone(), serde_json::json!({ "status": status, "t": now }));
            changed = true;
        }
        t["since"] = seen.get(&id).map(|v| v["t"].clone()).unwrap_or(Value::Null);
    }
    if changed {
        if let Some(d) = path.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(&path, Value::Object(seen).to_string());
    }
}

/// Running `claude` processes (this user's) that no session file names, as agent entries.
fn unreported_claudes(known: &std::collections::HashSet<u64>) -> Vec<Value> {
    let Ok(rd) = std::fs::read_dir("/proc") else { return Vec::new() };
    let uid = std::fs::read_to_string("/proc/self/status").ok().and_then(|s| s.lines().find_map(|l| l.strip_prefix("Uid:")).and_then(|u| u.split_whitespace().next().map(String::from)));
    let boot = std::fs::read_to_string("/proc/stat").ok().and_then(|s| s.lines().find_map(|l| l.strip_prefix("btime ")).and_then(|v| v.trim().parse::<u64>().ok())).unwrap_or(0);
    let mut out = Vec::new();
    for e in rd.flatten() {
        let Some(pid) = e.file_name().to_str().and_then(|n| n.parse::<u64>().ok()) else { continue };
        if known.contains(&pid) {
            continue;
        }
        let Ok(comm) = std::fs::read_to_string(format!("/proc/{pid}/comm")) else { continue };
        if comm.trim() != "claude" {
            continue;
        }
        let status = std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap_or_default();
        if uid.as_deref() != status.lines().find_map(|l| l.strip_prefix("Uid:")).and_then(|u| u.split_whitespace().next()) {
            continue;
        }
        let cwd = std::fs::read_link(format!("/proc/{pid}/cwd")).map(|p| p.display().to_string()).unwrap_or_default();
        let env = std::fs::read(format!("/proc/{pid}/environ")).unwrap_or_default();
        let pane = env.split(|b| *b == 0).filter_map(|kv| std::str::from_utf8(kv).ok()).find_map(|kv| kv.strip_prefix("ZEIT_PANE=")).unwrap_or("").to_string();
        // started: field 22 of stat, in clock ticks after boot (100 a second here)
        let started = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok().and_then(|s| s.rsplit_once(')').and_then(|(_, r)| r.split_whitespace().nth(19).and_then(|v| v.parse::<u64>().ok()))).map(|t| boot + t / 100).unwrap_or(0);
        let project = std::path::Path::new(&cwd).file_name().map(|n| n.to_string_lossy().trim_start_matches('.').to_string()).unwrap_or_default();
        out.push(serde_json::json!({
            "id": format!("claude-pid-{pid}"),
            "source": "claude-code",
            "state": "idle",
            "pid": pid,
            "cwd": cwd,
            "project": project,
            "pane": pane,
            "prompt": "",
            "started": started,
            "updated": started,
            "tools": 0,
            "unreported": true,
        }));
    }
    out
}
