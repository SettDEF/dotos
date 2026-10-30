//! The change log: every change to a task, who made it, and what the task
//! was before — so any change can be undone, and an AI's or an extension's
//! edits can be told apart from yours.
//!
//! One JSON object per line in $XDG_STATE_HOME/dotos/events.jsonl:
//!   { "t": unix, "who": "user"|"ai"|"ext:<name>", "op": "add"|"edit"|"state"|"rm"|"undo",
//!     "uid", "title", "list", "before": "<VTODO text or null>", "undone": false }

use crate::paths;
use icalcore::store::Store;
use icalcore::todo::{self, Todo};
use serde_json::{json, Value};
use std::io::Write;

pub fn who() -> String {
    std::env::var("DOTOS_WHO").unwrap_or_else(|_| "user".into())
}

fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

pub fn record(op: &str, after: &Todo, before: Option<&Todo>) {
    record_as(&who(), op, after, before)
}

/// A change made by someone else (a teammate's, merged from LAN sync: "team:<handle>").
pub fn record_as(who: &str, op: &str, after: &Todo, before: Option<&Todo>) {
    let line = json!({
        "t": now(), "who": who, "op": op,
        "uid": after.uid, "title": after.summary, "list": after.list,
        "before": before.map(|b| todo::serialize(std::slice::from_ref(b), "dotos")),
    });
    let path = paths::events_file();
    if let Some(d) = path.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(f, "{line}");
    }
}

pub fn read(limit: usize) -> Vec<Value> {
    let text = std::fs::read_to_string(paths::events_file()).unwrap_or_default();
    let mut v: Vec<Value> = text.lines().rev().filter_map(|l| serde_json::from_str(l).ok()).take(limit).collect();
    v.reverse();
    v
}

/// History of one task, newest last.
pub fn of(uid: &str, limit: usize) -> Vec<Value> {
    let text = std::fs::read_to_string(paths::events_file()).unwrap_or_default();
    let mut v: Vec<Value> = text.lines().rev().filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .filter(|e| e["uid"] == uid).take(limit).collect();
    v.reverse();
    v
}

/// Undo the newest change not yet undone (optionally: only by `by`).
/// Returns a line describing what was undone.
pub fn undo(store: &Store, by: Option<&str>, dry: bool) -> Result<String, String> {
    let path = paths::events_file();
    let text = std::fs::read_to_string(&path).map_err(|_| "nothing to undo".to_string())?;
    let mut lines: Vec<Value> = text.lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
    let idx = lines.iter().rposition(|e| {
        // (an AI session's own task changes are only told, never undone here)
        e["op"] != "undo" && !e["op"].as_str().unwrap_or("").starts_with("claude:") && e["undone"] != true && by.map_or(true, |b| e["who"].as_str().unwrap_or("").starts_with(b))
    }).ok_or("nothing to undo")?;
    let e = lines[idx].clone();
    let uid = e["uid"].as_str().unwrap_or("");
    let list = e["list"].as_str().unwrap_or("personal");
    let todos = store.load_todos();
    let current = todos.iter().find(|t| t.uid == uid);
    if dry {
        return Ok(describe(&e, current, list));
    }
    match e["before"].as_str() {
        // it did not exist before: the change was an add → remove it
        None => {
            if let Some(t) = current {
                store.delete_todo(t).map_err(|x| x.to_string())?;
            }
        }
        Some(ics) => {
            let restored = todo::parse(ics, list).into_iter().next().ok_or("the log entry is damaged")?;
            if let Some(t) = current.filter(|t| t.list != restored.list) {
                store.delete_todo(t).map_err(|x| x.to_string())?;
            }
            store.save_todo(&restored).map_err(|x| x.to_string())?;
        }
    }
    lines[idx]["undone"] = json!(true);
    let mut out = String::new();
    for l in &lines {
        out.push_str(&l.to_string());
        out.push('\n');
    }
    out.push_str(&json!({ "t": now(), "who": who(), "op": "undo", "uid": uid, "title": e["title"], "list": list, "before": null, "undid": e["op"] }).to_string());
    out.push('\n');
    paths::write_atomic(&path, out.as_bytes()).map_err(|x| x.to_string())?;
    Ok(format!("undid {} of “{}”", e["op"].as_str().unwrap_or("?"), e["title"].as_str().unwrap_or(uid)))
}

/// What an undo would change, field by field, without touching anything.
fn describe(e: &Value, current: Option<&Todo>, list: &str) -> String {
    let title = e["title"].as_str().unwrap_or("?");
    let who = e["who"].as_str().unwrap_or("?");
    let head = format!("would undo {} by {who} on “{title}”", e["op"].as_str().unwrap_or("?"));
    let Some(ics) = e["before"].as_str() else {
        return format!("{head}: it was added then, so it would be deleted");
    };
    let Some(before) = todo::parse(ics, list).into_iter().next() else { return format!("{head} (log entry damaged)") };
    let Some(now) = current else { return format!("{head}: it was deleted, so it would come back") };
    let mut diff: Vec<String> = Vec::new();
    let mut field = |name: &str, a: String, b: String| if a != b { diff.push(format!("{name}: {a} → {b}")); };
    let day = |t: &Todo| t.due.map(|d| d.format("%Y-%m-%d %H:%M").to_string()).unwrap_or_else(|| "none".into());
    field("title", now.summary.clone(), before.summary.clone());
    field("due", day(now), day(&before));
    field("state", crate::model::state(now).name().into(), crate::model::state(&before).name().into());
    field("priority", now.importance().label().into(), before.importance().label().into());
    field("tags", now.categories.join(","), before.categories.join(","));
    field("list", now.list.clone(), before.list.clone());
    field("notes", now.description.chars().take(30).collect(), before.description.chars().take(30).collect());
    if diff.is_empty() { diff.push("nothing visible (extra fields only)".into()); }
    format!("{head}:\n  {}", diff.join("\n  "))
}

/// A change in a Claude Code session's own task list (created, started, done), told in the log so
/// History shows it: op "claude:new" | "claude:start" | "claude:done", uid "claude:<session>:<id>".
pub fn record_claude(op: &str, session: &str, id: &str, subject: &str) {
    let line = json!({
        "t": now(), "who": "ai", "op": format!("claude:{op}"),
        "uid": format!("claude:{session}:{id}"), "title": subject, "list": "claude", "before": null, "session": session,
    });
    let path = paths::events_file();
    if let Some(d) = path.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(f, "{line}");
    }
}
