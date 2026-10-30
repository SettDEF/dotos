//! The command table: every verb the window's palette (and later a terminal UI,
//! and user scripts) can run, defined once here. A frontend renders this and
//! runs `dotos <args>` with `{id}` (the selected task) and `{arg}` (what was
//! typed) filled in — so the window, the terminal and a TUI cannot disagree.
//!
//!   arg: ""  none · "text" free text · "state" · "when" · "project" · "repeat" · "task"
//!   task: the command needs a selected task

use serde_json::{json, Value};

pub fn table() -> Vec<Value> {
    let c = |name: &str, help: &str, arg: &str, task: bool, args: &[&str]| json!({ "name": name, "help": help, "arg": arg, "task": task, "args": args });
    vec![
        c("capture", "add a task from one line", "text", false, &["capture", "{arg}"]),
        c("done", "tick the task", "", true, &["done", "{id}"]),
        c("undone", "untick the task", "", true, &["undone", "{id}"]),
        c("state", "inbox · todo · doing · waiting · done · cancelled", "state", true, &["state", "{id}", "{arg}"]),
        c("due", "set the due date (fri, +3d, 2026-11-01 14:00, none)", "when", true, &["set", "{id}", "due={arg}"]),
        c("snooze", "push the due date (default tomorrow)", "when", true, &["snooze", "{id}", "{arg}"]),
        c("move", "put the task in a project", "project", true, &["set", "{id}", "project={arg}"]),
        c("rename", "change the title", "text", true, &["set", "{id}", "title={arg}"]),
        c("estimate", "how long it takes (30m, 1h30m)", "text", true, &["set", "{id}", "estimate={arg}"]),
        c("repeat", "daily · weekly · 3d · mon,thu · +3d from completion · none", "repeat", true, &["set", "{id}", "repeat={arg}"]),
        c("blocked", "this task waits on another (id or title start)", "task", true, &["set", "{id}", "blocked+={arg}"]),
        c("unblock", "stop waiting on a task", "task", true, &["set", "{id}", "blocked-={arg}"]),
        c("sub", "add a subtask", "text", true, &["sub", "{id}", "{arg}"]),
        c("track", "start the timer on the task", "", true, &["track", "{id}"]),
        c("stop", "stop the timer", "", false, &["stop"]),
        c("delete", "delete the task (undo brings it back)", "", true, &["rm", "{id}"]),
        c("undo", "undo the last change", "", false, &["undo"]),
        c("reconcile", "park cards of finished agent sessions", "", false, &["agents", "reconcile"]),
        c("week", "write this week's review page", "", false, &["week"]),
        c("backup", "commit the store to its git history", "", false, &["backup"]),
        c("git", "remote git: PRs, issues, branches, commits, CI", "text", false, &["git", "{arg}"]),
        c("tag", "custom tags: add, edit, rm, list, spinweb", "text", false, &["tag", "{arg}"]),
        c("lua", "init.lua + hooks (on_capture, on_done, on_agent)", "text", false, &["lua", "{arg}"]),
        c("query", "saved queries: filter tasks by expression", "text", false, &["query", "{expr}"]),
        c("diff", "what changed: tasks, files, agent activity", "text", false, &["diff", "{arg}"]),
    ]
}
