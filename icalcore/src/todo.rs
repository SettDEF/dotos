//! VTODO — a task, in the same file format as an event.
//!
//! The properties here are the ones RFC 5545 defines for a task, which is
//! also the reason to store tasks this way at all: every CalDAV client on a
//! phone already reads them. Anything not modelled is kept verbatim in
//! `extra`, so a task edited here does not lose fields another app wrote.

use crate::ics::{blocks, escape, fmt_stamp, fold, parse_stamp, split_prop, unescape};
use chrono::{NaiveDate, NaiveDateTime};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Status {
    NeedsAction,
    InProcess,
    Completed,
    Cancelled,
}

impl Status {
    fn from_ical(v: &str) -> Status {
        match v.trim().to_ascii_uppercase().as_str() {
            "COMPLETED" => Status::Completed,
            "IN-PROCESS" => Status::InProcess,
            "CANCELLED" => Status::Cancelled,
            _ => Status::NeedsAction,
        }
    }
    fn to_ical(self) -> &'static str {
        match self {
            Status::NeedsAction => "NEEDS-ACTION",
            Status::InProcess => "IN-PROCESS",
            Status::Completed => "COMPLETED",
            Status::Cancelled => "CANCELLED",
        }
    }
    /// Still wants doing. Cancelled counts as closed, not open.
    pub fn is_open(self) -> bool {
        matches!(self, Status::NeedsAction | Status::InProcess)
    }
}

/// RFC 5545 numbers priority 1..9 with **1 as the highest**, which reads
/// backwards to everyone who has not read the RFC. The numbers are what gets
/// stored and synced; this is what gets shown.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Importance {
    High,
    Normal,
    Low,
    Unset,
}

impl Importance {
    pub fn from_number(n: u8) -> Importance {
        match n {
            0 => Importance::Unset,
            1..=4 => Importance::High,
            5 => Importance::Normal,
            _ => Importance::Low,
        }
    }
    pub fn to_number(self) -> u8 {
        match self {
            Importance::High => 1,
            Importance::Normal => 5,
            Importance::Low => 9,
            Importance::Unset => 0,
        }
    }
    pub fn parse(s: &str) -> Option<Importance> {
        match s.trim().to_ascii_lowercase().as_str() {
            "high" | "h" | "1" => Some(Importance::High),
            "normal" | "n" | "med" | "medium" | "5" => Some(Importance::Normal),
            "low" | "l" | "9" => Some(Importance::Low),
            "none" | "unset" | "0" => Some(Importance::Unset),
            _ => None,
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Importance::High => "high",
            Importance::Normal => "normal",
            Importance::Low => "low",
            Importance::Unset => "",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Todo {
    pub uid: String,
    /// The collection it lives in — the vdir directory name.
    pub list: String,
    pub summary: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
    /// When it is due. A task without one is perfectly valid.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due: Option<NaiveDateTime>,
    /// The due date is a day, not a time — DUE;VALUE=DATE.
    #[serde(default)]
    pub due_all_day: bool,
    /// When it can be started, if the writer said so.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start: Option<NaiveDateTime>,
    #[serde(default)]
    pub start_all_day: bool,
    /// 0 = unset, 1 = highest, 9 = lowest, as RFC 5545 has it.
    #[serde(default)]
    pub priority: u8,
    pub status: Status,
    #[serde(default)]
    pub percent: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed: Option<NaiveDateTime>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created: Option<NaiveDateTime>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub categories: Vec<String>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub rrule: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub extra: Vec<String>,
}

impl Todo {
    pub fn new(summary: &str, list: &str, uid: &str) -> Todo {
        Todo {
            uid: uid.to_string(),
            list: list.to_string(),
            summary: summary.to_string(),
            description: String::new(),
            due: None,
            due_all_day: false,
            start: None,
            start_all_day: false,
            priority: 0,
            status: Status::NeedsAction,
            percent: 0,
            completed: None,
            created: Some(crate::ics::now_local()),
            categories: Vec::new(),
            rrule: String::new(),
            extra: Vec::new(),
        }
    }

    pub fn importance(&self) -> Importance {
        Importance::from_number(self.priority)
    }
    pub fn set_importance(&mut self, i: Importance) {
        self.priority = i.to_number();
    }

    pub fn is_open(&self) -> bool {
        self.status.is_open()
    }

    pub fn due_date(&self) -> Option<NaiveDate> {
        self.due.map(|d| d.date())
    }

    /// Due before today and still open. A task due today is not overdue yet.
    pub fn is_overdue(&self, today: NaiveDate) -> bool {
        self.is_open() && self.due_date().map(|d| d < today).unwrap_or(false)
    }

    /// Tick it. PERCENT-COMPLETE and COMPLETED are set together because a
    /// client that reads one and not the other should still see it as done.
    pub fn complete(&mut self, at: NaiveDateTime) {
        self.status = Status::Completed;
        self.percent = 100;
        self.completed = Some(at);
    }

    pub fn reopen(&mut self) {
        self.status = Status::NeedsAction;
        self.percent = 0;
        self.completed = None;
    }

    /// The order a task list should be read in: what is due first, then what
    /// matters most, then alphabetically so the order never wobbles between
    /// runs. Tasks with no due date sort after the dated ones — they are not
    /// urgent by virtue of being undated.
    pub fn sort_key(&self) -> (u8, i64, u8, String) {
        let (bucket, when) = match self.due {
            Some(d) => (0u8, d.and_utc().timestamp()),
            None => (1u8, 0),
        };
        // Unset priority sorts with "normal", not above "high".
        let pri = if self.priority == 0 { 5 } else { self.priority };
        (bucket, when, pri, self.summary.to_lowercase())
    }
}

pub fn parse(src: &str, list: &str) -> Vec<Todo> {
    let mut todos = Vec::new();
    for block in blocks(src, "VTODO") {
        let mut t = Todo::new("", list, "");
        t.created = None;
        for line in block {
            let Some(p) = split_prop(&line) else { continue };
            match p.name.as_str() {
                "UID" => t.uid = p.value,
                "SUMMARY" => t.summary = unescape(&p.value),
                "DESCRIPTION" => t.description = unescape(&p.value),
                "STATUS" => t.status = Status::from_ical(&p.value),
                "RRULE" => t.rrule = p.value,
                "PRIORITY" => t.priority = p.value.trim().parse().unwrap_or(0).min(9),
                "PERCENT-COMPLETE" => t.percent = p.value.trim().parse().unwrap_or(0).min(100),
                "CATEGORIES" => t.categories.extend(
                    p.value.split(',').map(|c| unescape(c.trim())).filter(|c| !c.is_empty()),
                ),
                "DUE" => {
                    if let Some((dt, ad)) = parse_stamp(&p.value, p.is_date, p.tzid.as_deref()) {
                        t.due = Some(dt);
                        t.due_all_day = ad;
                    }
                }
                "DTSTART" => {
                    if let Some((dt, ad)) = parse_stamp(&p.value, p.is_date, p.tzid.as_deref()) {
                        t.start = Some(dt);
                        t.start_all_day = ad;
                    }
                }
                "COMPLETED" => {
                    t.completed = parse_stamp(&p.value, p.is_date, p.tzid.as_deref()).map(|(d, _)| d)
                }
                "CREATED" => {
                    t.created = parse_stamp(&p.value, p.is_date, p.tzid.as_deref()).map(|(d, _)| d)
                }
                _ => t.extra.push(p.raw),
            }
        }
        if t.uid.is_empty() {
            let what = if t.summary.is_empty() { "(no summary)" } else { &t.summary };
            crate::warn(&format!("skipped a VTODO with no UID: {what}"));
            continue;
        }
        // A file that says COMPLETED but carries no percentage still means
        // done; a reader that trusts only the number would show it as open.
        if t.status == Status::Completed && t.percent == 0 {
            t.percent = 100;
        }
        todos.push(t);
    }
    todos
}

pub fn serialize(todos: &[Todo], prodid: &str) -> String {
    let mut out = format!("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//{prodid}//EN\r\n");
    for t in todos {
        out.push_str("BEGIN:VTODO\r\n");
        let mut push = |l: String| {
            out.push_str(&fold(&l));
            out.push_str("\r\n");
        };
        push(format!("UID:{}", t.uid));
        push(format!("SUMMARY:{}", escape(&t.summary)));
        push(format!("STATUS:{}", t.status.to_ical()));
        if let Some(c) = t.created {
            push(format!("CREATED:{}", fmt_stamp(&c, false)));
        }
        if let Some(d) = t.due {
            if t.due_all_day {
                push(format!("DUE;VALUE=DATE:{}", fmt_stamp(&d, true)));
            } else {
                push(format!("DUE:{}", fmt_stamp(&d, false)));
            }
        }
        if let Some(s) = t.start {
            if t.start_all_day {
                push(format!("DTSTART;VALUE=DATE:{}", fmt_stamp(&s, true)));
            } else {
                push(format!("DTSTART:{}", fmt_stamp(&s, false)));
            }
        }
        if t.priority > 0 {
            push(format!("PRIORITY:{}", t.priority));
        }
        if t.percent > 0 {
            push(format!("PERCENT-COMPLETE:{}", t.percent));
        }
        if let Some(c) = t.completed {
            push(format!("COMPLETED:{}", fmt_stamp(&c, false)));
        }
        if !t.categories.is_empty() {
            let cats: Vec<String> = t.categories.iter().map(|c| escape(c)).collect();
            push(format!("CATEGORIES:{}", cats.join(",")));
        }
        if !t.description.is_empty() {
            push(format!("DESCRIPTION:{}", escape(&t.description)));
        }
        if !t.rrule.is_empty() {
            push(format!("RRULE:{}", t.rrule));
        }
        for line in &t.extra {
            push(line.clone());
        }
        out.push_str("END:VTODO\r\n");
    }
    out.push_str("END:VCALENDAR\r\n");
    out
}
