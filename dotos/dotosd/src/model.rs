//! Task model v2, on top of VTODO.
//!
//! The file stays a plain VTODO, so a phone still reads every task. What a
//! phone has no field for lives in `X-DOTOS-*` properties, kept in the task's
//! `extra` lines — other clients carry them through untouched.
//!
//!   X-DOTOS-STATE     inbox | todo | doing | waiting   (open states; done and
//!                     cancelled are the standard STATUS)
//!   X-DOTOS-WAITING   on what: a person, "agent:<id>", a date
//!   X-DOTOS-ASSIGNEE  who does it: a handle (dotos me), or agent:<id>
//!   X-DOTOS-DECISION  the message that decided it: "<msg id> <text>" (dotos decide)
//!   X-DOTOS-ESTIMATE  minutes
//!   X-DOTOS-PROJECT   project name (a folder under the project roots)
//!   X-DOTOS-ORIGIN    who made it: "user", "ext:<name>:<key>", "page:<file>:<line>", "ai"
//!   X-DOTOS-LINK      one per link: url, file:line, agent:<id>, event:<uid>
//!   X-DOTOS-PARENT    uid of the parent task (subtasks)
//!   X-DOTOS-ORDER     manual order within its group
//!   X-DOTOS-BLOCKED   one per blocker: uid of a task that must finish first
//!   X-DOTOS-REPEAT    "done" = the next repeat counts from completion, not the schedule

use chrono::{Local, NaiveDate, NaiveDateTime};
use icalcore::todo::{Status, Todo};
use serde::Serialize;

pub fn get(t: &Todo, key: &str) -> Option<String> {
    let pre = format!("X-DOTOS-{key}:");
    t.extra.iter().find_map(|l| l.strip_prefix(&pre).map(|v| unescape(v)))
}

pub fn get_all(t: &Todo, key: &str) -> Vec<String> {
    let pre = format!("X-DOTOS-{key}:");
    t.extra.iter().filter_map(|l| l.strip_prefix(&pre).map(unescape)).collect()
}

pub fn set(t: &mut Todo, key: &str, value: Option<&str>) {
    let pre = format!("X-DOTOS-{key}:");
    t.extra.retain(|l| !l.starts_with(&pre));
    if let Some(v) = value.filter(|v| !v.is_empty()) {
        t.extra.push(format!("{pre}{}", escape(v)));
    }
}

pub fn set_all(t: &mut Todo, key: &str, values: &[String]) {
    let pre = format!("X-DOTOS-{key}:");
    t.extra.retain(|l| !l.starts_with(&pre));
    for v in values.iter().filter(|v| !v.is_empty()) {
        t.extra.push(format!("{pre}{}", escape(v)));
    }
}

fn escape(v: &str) -> String {
    v.replace('\\', "\\\\").replace('\n', "\\n").replace(',', "\\,").replace(';', "\\;")
}
fn unescape(v: &str) -> String {
    let mut out = String::new();
    let mut it = v.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.next() {
                Some('n') | Some('N') => out.push('\n'),
                Some(o) => out.push(o),
                None => {}
            }
        } else {
            out.push(c);
        }
    }
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Inbox,
    Todo,
    Doing,
    Waiting,
    Done,
    Cancelled,
}

impl State {
    pub fn parse(s: &str) -> Option<State> {
        Some(match s.trim().to_ascii_lowercase().as_str() {
            "inbox" | "i" => State::Inbox,
            "todo" | "t" | "open" => State::Todo,
            "doing" | "d" | "now" | "active" => State::Doing,
            "waiting" | "w" | "wait" | "blocked" => State::Waiting,
            "done" | "x" | "complete" | "completed" => State::Done,
            "cancelled" | "canceled" | "c" | "drop" => State::Cancelled,
            _ => return None,
        })
    }
    pub fn name(self) -> &'static str {
        match self {
            State::Inbox => "inbox",
            State::Todo => "todo",
            State::Doing => "doing",
            State::Waiting => "waiting",
            State::Done => "done",
            State::Cancelled => "cancelled",
        }
    }
}

pub fn state(t: &Todo) -> State {
    match t.status {
        Status::Completed => return State::Done,
        Status::Cancelled => return State::Cancelled,
        _ => {}
    }
    match get(t, "STATE").and_then(|s| State::parse(&s)) {
        Some(s @ (State::Inbox | State::Todo | State::Doing | State::Waiting)) => s,
        // tasks from before v2, or from a phone: in progress if the phone says
        // so, otherwise plain to-do
        _ if t.status == Status::InProcess => State::Doing,
        _ => State::Todo,
    }
}

pub fn set_state(t: &mut Todo, s: State) {
    let now = Local::now().naive_local();
    // a repeating task moves to its next date instead of closing
    if s == State::Done && crate::recurrence::advance(t) {
        set(t, "WAITING", None);
        return;
    }
    match s {
        State::Done => {
            t.complete(now);
            set(t, "STATE", None);
        }
        State::Cancelled => {
            t.status = Status::Cancelled;
            set(t, "STATE", None);
        }
        open => {
            if !t.is_open() {
                t.reopen();
            }
            t.status = if open == State::Doing { Status::InProcess } else { Status::NeedsAction };
            set(t, "STATE", Some(open.name()));
        }
    }
    if s != State::Waiting {
        set(t, "WAITING", None);
    }
}

/// What the window and the CLI's --json see: one flat object per task.
#[derive(Debug, Clone, Serialize)]
pub struct TaskView {
    pub uid: String,
    pub title: String,
    pub notes: String,
    pub list: String,
    pub project: String,
    pub state: State,
    pub waiting_on: String,
    /// who does it (X-DOTOS-ASSIGNEE): a handle, or agent:<id>
    pub assignee: String,
    /// what was decided in its conversation (X-DOTOS-DECISION, without the message id)
    pub decision: String,
    pub priority: &'static str,
    pub due: Option<String>,
    pub due_time: bool,
    pub start: Option<String>,
    pub estimate_min: u32,
    pub tags: Vec<String>,
    pub links: Vec<String>,
    pub parent: String,
    pub origin: String,
    pub created: Option<String>,
    pub completed: Option<String>,
    pub overdue: bool,
    /// overdue · today · tomorrow · week · later · someday · done
    pub bucket: &'static str,
    pub recurring: bool,
    /// RRULE of a repeating task, "" otherwise
    pub repeat: String,
    pub repeat_after: bool,
    /// uids this task waits on (open ones block it)
    pub blocked_by: Vec<String>,
}

fn iso(d: NaiveDateTime) -> String {
    d.format("%Y-%m-%dT%H:%M:%S").to_string()
}

pub fn bucket(t: &Todo, today: NaiveDate) -> &'static str {
    if !t.is_open() {
        return "done";
    }
    match t.due_date() {
        None => "someday",
        Some(d) if d < today => "overdue",
        Some(d) if d == today => "today",
        Some(d) if d == today.succ_opt().unwrap_or(today) => "tomorrow",
        Some(d) if (d - today).num_days() <= 7 => "week",
        _ => "later",
    }
}

pub fn view(t: &Todo, today: NaiveDate) -> TaskView {
    let st = state(t);
    TaskView {
        uid: t.uid.clone(),
        title: t.summary.clone(),
        notes: t.description.clone(),
        list: t.list.clone(),
        project: get(t, "PROJECT").unwrap_or_default(),
        state: st,
        waiting_on: get(t, "WAITING").unwrap_or_default(),
        assignee: get(t, "ASSIGNEE").unwrap_or_default(),
        decision: get(t, "DECISION").map(|d| d.split_once(' ').map(|(_, x)| x.to_string()).unwrap_or(d)).unwrap_or_default(),
        priority: t.importance().label(),
        due: t.due.map(iso),
        due_time: t.due.is_some() && !t.due_all_day,
        start: t.start.map(iso),
        estimate_min: get(t, "ESTIMATE").and_then(|v| v.parse().ok()).unwrap_or(0),
        tags: t.categories.clone(),
        links: get_all(t, "LINK"),
        parent: get(t, "PARENT").unwrap_or_default(),
        origin: get(t, "ORIGIN").unwrap_or_else(|| "user".into()),
        created: t.created.map(iso),
        completed: t.completed.map(iso),
        overdue: t.is_overdue(today),
        bucket: bucket(t, today),
        recurring: !t.rrule.is_empty(),
        repeat: t.rrule.clone(),
        repeat_after: get(t, "REPEAT").as_deref() == Some("done"),
        blocked_by: get_all(t, "BLOCKED"),
    }
}
