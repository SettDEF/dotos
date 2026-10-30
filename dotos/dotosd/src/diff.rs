//! Diff / change tracking: git-like view of what changed, where agents worked,
//! and which tasks are currently in progress.
//!
//! Reads the events log, agent activity, and (optionally) git diffs to produce
//! a unified view of changes over time.

use crate::agents;
use crate::log;
use crate::paths;
use serde_json::{json, Value};
use std::collections::BTreeMap;

/// A single change entry: what changed, who, when, and the diff.
#[derive(Debug, Clone)]
pub struct Change {
    pub t: u64,
    pub who: String,
    pub kind: String,   // "task", "file", "agent", "project"
    pub id: String,
    pub title: String,
    pub op: String,      // "add", "edit", "state", "rm", "undo", "work"
    pub before: Option<String>,
    pub after: Option<String>,
    pub fields: Vec<(String, String, String)>, // (field, old, new)
}

/// Collect all changes since a given timestamp.
pub fn since(ts: u64) -> Vec<Change> {
    let mut changes = Vec::new();

    // 1. Task changes from events log
    let events = log::read(10000);
    for e in &events {
        let t = e["t"].as_u64().unwrap_or(0);
        if t < ts { continue; }
        let who = e["who"].as_str().unwrap_or("?").to_string();
        let op = e["op"].as_str().unwrap_or("?").to_string();
        let uid = e["uid"].as_str().unwrap_or("").to_string();
        let title = e["title"].as_str().unwrap_or("").to_string();

        // Compute field-level diff from before
        let mut fields = Vec::new();
        if let Some(before_ics) = e["before"].as_str() {
            // Parse before state and compare with current
            if let Some(current) = find_task(&uid) {
                // Compare fields
                let before_summary = extract_field(before_ics, "SUMMARY");
                if before_summary != current.summary {
                    fields.push(("title".into(), before_summary, current.summary.clone()));
                }
                let before_state = extract_field(before_ics, "STATUS");
                let current_state = crate::model::state(&current).name().to_string();
                if before_state != current_state {
                    fields.push(("state".into(), before_state, current_state));
                }
            }
        }

        changes.push(Change {
            t,
            who,
            kind: "task".into(),
            id: uid,
            title,
            op,
            before: e["before"].as_str().map(String::from),
            after: None,
            fields,
        });
    }

    // 2. Agent activity
    let agents_list = agents::list_all();
    for a in &agents_list {
        let updated = a["updated"].as_u64().unwrap_or(0);
        if updated < ts { continue; }
        let id = a["id"].as_str().unwrap_or("").to_string();
        let state = a["state"].as_str().unwrap_or("").to_string();
        let task = a["task"].as_str().unwrap_or("").to_string();
        let cwd = a["cwd"].as_str().unwrap_or("").to_string();
        let summary = a["summary"].as_str().unwrap_or("").to_string();

        changes.push(Change {
            t: updated,
            who: format!("agent:{}", id),
            kind: "agent".into(),
            id: id.clone(),
            title: summary,
            op: "work".into(),
            before: None,
            after: Some(cwd.clone()),
            fields: vec![
                ("state".into(), String::new(), state),
                ("task".into(), String::new(), task),
                ("cwd".into(), String::new(), cwd),
            ],
        });
    }

    // 3. Currently working tasks
    let store = match crate::ops::store() { Ok(s) => s, Err(_) => return changes };
    let todos = store.load_todos();
    for t in &todos {
        let state = crate::model::state(t).name().to_string();
        if state == "doing" {
            changes.push(Change {
                t: 0, // current
                who: "user".into(),
                kind: "task".into(),
                id: t.uid.clone(),
                title: t.summary.clone(),
                op: "working".into(),
                before: None,
                after: None,
                fields: vec![("state".into(), String::new(), "doing".into())],
            });
        }
    }

    changes.sort_by_key(|c| c.t);
    changes
}

/// Find a task by uid.
fn find_task(uid: &str) -> Option<icalcore::todo::Todo> {
    let store = crate::ops::store().ok()?;
    let todos = store.load_todos();
    todos.into_iter().find(|t| t.uid == uid)
}

/// Extract a field from ICS text.
fn extract_field(ics: &str, field: &str) -> String {
    for line in ics.lines() {
        if let Some(rest) = line.strip_prefix(&format!("{}:", field)) {
            return rest.to_string();
        }
        if let Some(rest) = line.strip_prefix(&format!("{};", field)) {
            // Handle parameters like STATUS;...
            if let Some(idx) = rest.find(':') {
                return rest[idx+1..].to_string();
            }
        }
    }
    String::new()
}

/// Render changes as a readable diff.
pub fn render(changes: &[Change], format: &str) -> String {
    if format == "json" {
        let arr: Vec<Value> = changes.iter().map(|c| {
            json!({
                "t": c.t,
                "who": c.who,
                "kind": c.kind,
                "id": c.id,
                "title": c.title,
                "op": c.op,
                "fields": c.fields.iter().map(|(f,o,n)| json!({"field": f, "old": o, "new": n})).collect::<Vec<_>>(),
            })
        }).collect();
        return serde_json::to_string_pretty(&json!({ "changes": arr, "count": arr.len() })).unwrap_or_default();
    }

    let mut out = String::new();
    let mut current_date = String::new();
    for c in changes {
        let dt = if c.t > 0 {
            chrono::DateTime::from_timestamp(c.t as i64, 0)
                .map(|d| d.format("%Y-%m-%d %H:%M").to_string())
                .unwrap_or_default()
        } else {
            "now".to_string()
        };
        let date_part = if c.t > 0 { &dt[..10] } else { "now" };
        if date_part != current_date {
            current_date = date_part.to_string();
            out.push_str(&format!("\n── {} ──\n", current_date));
        }

        let icon = match c.op.as_str() {
            "add" => "+",
            "rm" => "-",
            "state" | "working" => "~",
            "edit" => "·",
            "work" => "▶",
            "undo" => "↶",
            _ => " ",
        };

        let time_part = if dt.len() >= 16 { &dt[11..16] } else { dt.as_str() };
        out.push_str(&format!("  {} {} {}  {}  {}\n", icon, time_part, c.who, c.kind, c.title));

        for (field, old, new) in &c.fields {
            if !old.is_empty() || !new.is_empty() {
                if old.is_empty() {
                    out.push_str(&format!("      {} → {}\n", field, new));
                } else if new.is_empty() {
                    out.push_str(&format!("      {} (was: {})\n", field, old));
                } else {
                    out.push_str(&format!("      {}: {} → {}\n", field, old, new));
                }
            }
        }
    }

    if changes.is_empty() {
        out.push_str("  (no changes)\n");
    }

    out
}

/// Snapshot of currently working tasks and agents.
pub fn working_now() -> Value {
    let store = match crate::ops::store() { Ok(s) => s, Err(e) => return json!({"error": e}) };
    let todos = store.load_todos();

    let working_tasks: Vec<Value> = todos.iter()
        .filter(|t| crate::model::state(t).name() == "doing")
        .map(|t| json!({
            "uid": t.uid,
            "title": t.summary,
            "project": crate::model::get(t, "PROJECT").unwrap_or_default(),
            "list": t.list,
            "started": t.start.map(|d| d.format("%Y-%m-%d %H:%M").to_string()),
        }))
        .collect();

    let agents_list = agents::list_all();
    let active_agents: Vec<Value> = agents_list.iter()
        .filter(|a| a["state"].as_str() == Some("working") || a["state"].as_str() == Some("needs_you"))
        .map(|a| json!({
            "id": a["id"],
            "state": a["state"],
            "task": a["task"],
            "cwd": a["cwd"],
            "summary": a["summary"],
            "updated": a["updated"],
        }))
        .collect();

    json!({
        "working_tasks": working_tasks,
        "active_agents": active_agents,
        "working_count": working_tasks.len(),
        "agent_count": active_agents.len(),
    })
}

/// File-level diff: compare a file's current content with a saved snapshot.
pub fn file_diff(path: &str) -> Result<String, String> {
    let snapshot_dir = paths::state_dir().join("snapshots");
    let snapshot_path = snapshot_dir.join(path.replace('/', "_"));

    let current = std::fs::read_to_string(path)
        .map_err(|e| format!("cannot read {}: {}", path, e))?;

    if !snapshot_path.exists() {
        // First time: save snapshot, return "new file"
        std::fs::create_dir_all(&snapshot_dir).ok();
        std::fs::write(&snapshot_path, &current).ok();
        return Ok(format!("NEW FILE: {} ({} bytes)\n", path, current.len()));
    }

    let old = std::fs::read_to_string(&snapshot_path)
        .map_err(|e| format!("cannot read snapshot: {}", e))?;

    if old == current {
        return Ok(format!("NO CHANGES: {}\n", path));
    }

    // Simple line-based diff
    let old_lines: Vec<&str> = old.lines().collect();
    let new_lines: Vec<&str> = current.lines().collect();

    let mut out = format!("DIFF: {}\n", path);
    out.push_str(&format!("--- old ({} lines)\n", old_lines.len()));
    out.push_str(&format!("+++ new ({} lines)\n", new_lines.len()));

    // Use a simple LCS-based diff
    let diff = simple_diff(&old_lines, &new_lines);
    out.push_str(&diff);

    // Save new snapshot
    std::fs::write(&snapshot_path, &current).ok();

    Ok(out)
}

/// Simple line-based diff (not full Myers, but readable).
fn simple_diff(old: &[&str], new: &[&str]) -> String {
    let mut out = String::new();
    let mut i = 0;
    let mut j = 0;

    while i < old.len() || j < new.len() {
        if i < old.len() && j < new.len() && old[i] == new[j] {
            out.push_str(&format!("  {}\n", old[i]));
            i += 1;
            j += 1;
        } else if j < new.len() && (i >= old.len() || !old[i..].contains(&new[j])) {
            out.push_str(&format!("+ {}\n", new[j]));
            j += 1;
        } else if i < old.len() {
            out.push_str(&format!("- {}\n", old[i]));
            i += 1;
        } else {
            out.push_str(&format!("+ {}\n", new[j]));
            j += 1;
        }
    }

    out
}

/// Save a snapshot of a file for future diffing.
pub fn snapshot_file(path: &str) -> Result<(), String> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("cannot read {}: {}", path, e))?;
    let snapshot_dir = paths::state_dir().join("snapshots");
    std::fs::create_dir_all(&snapshot_dir).ok();
    let snapshot_path = snapshot_dir.join(path.replace('/', "_"));
    std::fs::write(&snapshot_path, &content)
        .map_err(|e| format!("cannot write snapshot: {}", e))?;
    Ok(())
}

/// List all tracked files (files that have snapshots).
pub fn tracked_files() -> Vec<String> {
    let snapshot_dir = paths::state_dir().join("snapshots");
    if !snapshot_dir.exists() { return Vec::new(); }
    std::fs::read_dir(&snapshot_dir)
        .map(|entries| {
            entries.filter_map(|e| e.ok())
                .map(|e| e.file_name().to_string_lossy().to_string().replace('_', "/"))
                .collect()
        })
        .unwrap_or_default()
}

/// Agent work summary: which files/paths agents touched, grouped by agent.
pub fn agent_work_summary() -> Value {
    let agents_list = agents::list_all();
    let mut by_agent: BTreeMap<String, Vec<Value>> = BTreeMap::new();

    for a in &agents_list {
        let id = a["id"].as_str().unwrap_or("").to_string();
        let actions = agents::actions(&id);
        let touched = agents::touched(&actions);

        let files: Vec<Value> = touched.iter().map(|(path, kind, count, task)| {
            json!({
                "path": path,
                "kind": kind,
                "times": count,
                "task": task,
            })
        }).collect();

        let state = a["state"].as_str().unwrap_or("").to_string();
        let summary = a["summary"].as_str().unwrap_or("").to_string();
        let cwd = a["cwd"].as_str().unwrap_or("").to_string();

        by_agent.insert(id.clone(), vec![json!({
            "state": state,
            "summary": summary,
            "cwd": cwd,
            "files": files,
            "action_count": actions.len(),
        })]);
    }

    let agents_json: Vec<Value> = by_agent.iter().map(|(id, info)| {
        json!({ "agent": id, "info": info })
    }).collect();

    json!({
        "agents": agents_json,
        "agent_count": agents_json.len(),
    })
}
