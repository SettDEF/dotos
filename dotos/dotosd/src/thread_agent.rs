//! Agents in the thread (docs/teams.md, Teams 3): `@claude …` in a thread starts Claude Code on the
//! item, headless, with the item and the conversation as context; its answer comes back as a
//! message by agent:claude, replying to the one that asked.
//!
//! Read-only by default (reading, searching, git log/status/diff): a chat line should not edit
//! files by itself. config.json "agent_mode": "edit" lets it edit (acceptEdits).

use crate::threads::{self, Message};
use std::process::{Command, Stdio};

/// The handles that start an agent when @mentioned.
const AGENTS: [&str; 2] = ["claude", "agent"];

/// After a message was said here (not merged from a peer): starts the agent it @mentions, in the
/// background. Agents' own messages never start one.
pub fn dispatch(item: &str, m: &Message) {
    let mine = format!("claude@{}", threads::me().handle.to_lowercase());
    if m.author.starts_with("agent:") || !m.mentions.iter().any(|h| AGENTS.contains(&h.as_str()) || *h == mine) {
        return;
    }
    answered(&m.id);
    let Ok(me) = std::env::current_exe() else { return };
    let agent = if m.mentions.contains(&mine) { format!("agent:claude@{}", threads::me().handle) } else { "agent:claude".to_string() };
    let _ = threads::say(item, "on it — reading the task and this thread …", Some(m.id.clone()), Some((agent.clone(), agent)));
    // its own process: the CLI that said the message returns at once
    let _ = Command::new(me)
        .args(["agent-run", item, &m.id])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

/// Messages from teammates (merged by LAN sync) that ask *my* agent: `@claude@<my handle>`.
/// Each is answered once (state/agent-answered.json); the first look only remembers.
pub fn dispatch_remote() {
    let f = crate::paths::state_dir().join("agent-answered.json");
    let first = !f.exists();
    let mine = format!("claude@{}", threads::me().handle.to_lowercase());
    let done = answered_set();
    for m in threads::all() {
        if done.contains(&m.id) || m.author.starts_with("agent:") || !m.mentions.contains(&mine) {
            continue;
        }
        if first {
            answered(&m.id);
        } else {
            dispatch(&m.item, &m);
        }
    }
    if first {
        let _ = std::fs::create_dir_all(crate::paths::state_dir());
        if !f.exists() {
            let _ = std::fs::write(&f, "[]");
        }
    }
}

fn answered_set() -> std::collections::HashSet<String> {
    std::fs::read_to_string(crate::paths::state_dir().join("agent-answered.json")).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

fn answered(id: &str) {
    let mut s = answered_set();
    if s.insert(id.to_string()) {
        let _ = std::fs::create_dir_all(crate::paths::state_dir());
        let _ = std::fs::write(crate::paths::state_dir().join("agent-answered.json"), serde_json::to_string(&s).unwrap_or_default());
    }
}

/// `dotos agent-run ITEM MSG`: runs the agent and posts what it says (or why it could not).
pub fn run(store: &icalcore::store::Store, item: &str, mid: &str) -> Result<(), String> {
    let msgs = threads::read(item);
    let ask = msgs.iter().find(|m| m.id == mid).ok_or("no such message")?.clone();
    // asked by a teammate as @claude@me: it answers as my agent, by name
    let me = threads::me();
    let agent = if ask.mentions.contains(&format!("claude@{}", me.handle.to_lowercase())) { format!("agent:claude@{}", me.handle) } else { "agent:claude".to_string() };
    let reply = |text: &str| threads::say(item, text, Some(ask.id.clone()), Some((agent.clone(), agent.clone())));

    // what it works on: the task (title, notes, project folder), or the project itself
    let mut about = String::new();
    let mut dir = std::env::var("HOME").map(std::path::PathBuf::from).unwrap_or_default();
    if let Some(uid) = item.strip_prefix("task:") {
        if let Ok(t) = crate::ops::find(store, uid) {
            let project = crate::model::get(&t, "PROJECT").unwrap_or_default();
            about = format!("The task: \"{}\"{}{}", t.summary, if project.is_empty() { String::new() } else { format!(" (project {project})") }, if t.description.trim().is_empty() { String::new() } else { format!("\nIts notes:\n{}", t.description.trim()) });
            if let Some(p) = crate::projects::find(&project) {
                dir = p;
            }
        }
    } else if let Some(a) = item.strip_prefix("agent:") {
        let (session, task) = a.split_once('#').unwrap_or((a, ""));
        about = format!("A task (#{task}) of the AI coding session {session}, as Dotos tracks it. Read the project's git log and status to see what that session did.");
    } else if let Some(id) = item.strip_prefix("page:") {
        let path = crate::pages::path_of(id);
        let text: String = std::fs::read_to_string(&path).unwrap_or_default().chars().take(6000).collect();
        about = format!("The page {} ({}):\n{}", id, path.display(), text);
    } else if let Some(p) = item.strip_prefix("project:") {
        about = format!("The project: {p}");
        if let Some(d) = crate::projects::find(p) {
            dir = d;
        }
    }
    let convo: Vec<String> = msgs.iter().rev().take(20).rev().filter(|m| !m.text.starts_with("on it —")).map(|m| format!("{}: {}", if m.name.is_empty() { &m.author } else { &m.name }, m.text)).collect();
    let prompt = format!(
        "You were @mentioned in a Dotos thread (a team's conversation on a task). Answer the last message, briefly, as a teammate would in chat: what you found or did, in a few sentences, no headings.\n\n{about}\n\nThe conversation so far:\n{}\n\nThe message to answer: {}",
        convo.join("\n"),
        ask.text
    );

    let edit = crate::paths::config().get("agent_mode").and_then(|v| v.as_str()) == Some("edit");
    let mut cmd = Command::new("claude");
    cmd.current_dir(&dir).arg("-p").arg(&prompt).args(["--output-format", "json"]);
    if edit {
        cmd.args(["--permission-mode", "acceptEdits"]);
    } else {
        cmd.args(["--allowedTools", "Read", "Grep", "Glob", "LS", "Bash(git log:*)", "Bash(git status:*)", "Bash(git diff:*)", "Bash(ls:*)"]);
    }
    cmd.stdin(Stdio::null());
    let out = match cmd.output() {
        Ok(o) => o,
        Err(e) => {
            let _ = reply(&format!("could not start Claude Code ({e}); is `claude` on the PATH?"));
            return Err(e.to_string());
        }
    };
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    let text = v["result"].as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from).unwrap_or_else(|| {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        format!("I could not finish this{}.", if err.is_empty() { String::new() } else { format!(": {}", err.lines().last().unwrap_or("")) })
    });
    reply(&text).map_err(|e| e.to_string())?;
    Ok(())
}
