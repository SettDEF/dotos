//! Time tracking through timewarrior — already installed, already driven
//! from Neovim; Dotos tags what it starts so time can be tied back to a task.
//!
//!   timew start "dotos:<uid>" "<list>" "+<project>" "<title>"
//!
//! The tag `dotos:<uid>` is the link; the others make `timew summary` readable
//! on its own, without Dotos.

use chrono::{DateTime, Local, NaiveDateTime, TimeZone, Utc};
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::process::Command;

fn timew(args: &[&str]) -> Option<String> {
    let out = Command::new("timew").args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

fn ts(s: &str) -> Option<DateTime<Utc>> {
    NaiveDateTime::parse_from_str(s, "%Y%m%dT%H%M%SZ").ok().map(|n| Utc.from_utc_datetime(&n))
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct Active {
    pub uid: String,
    pub title: String,
    pub tags: Vec<String>,
    pub since: i64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct Summary {
    pub available: bool,
    pub active: Option<Active>,
    /// seconds today / this week, in total and per task uid / project
    pub today_s: i64,
    pub week_s: i64,
    pub by_task_week: HashMap<String, i64>,
    pub by_task_today: HashMap<String, i64>,
    pub by_project_week: HashMap<String, i64>,
}

fn entries(range: &str) -> Vec<Value> {
    // a range can be several words ("from 2026-10-01 to 2026-10-22"), a tag one word
    let mut args = vec!["export"];
    args.extend(range.split_whitespace());
    timew(&args).and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn dotos_uid(tags: &[String]) -> Option<String> {
    tags.iter().find_map(|t| t.strip_prefix("dotos:").map(String::from))
}

pub fn summary() -> Summary {
    let mut s = Summary::default();
    if Command::new("timew").arg("--version").output().is_err() {
        return s;
    }
    s.available = true;
    let now = Utc::now();
    let today0 = Local::now().date_naive().and_hms_opt(0, 0, 0)
        .and_then(|d| Local.from_local_datetime(&d).single()).map(|d| d.with_timezone(&Utc)).unwrap_or(now);
    for e in entries(":week") {
        let Some(start) = e["start"].as_str().and_then(ts) else { continue };
        let end = e["end"].as_str().and_then(ts);
        let tags: Vec<String> = e["tags"].as_array().map(|a| a.iter().filter_map(|t| t.as_str().map(String::from)).collect()).unwrap_or_default();
        let stop = end.unwrap_or(now);
        let secs = (stop - start).num_seconds().max(0);
        let today_secs = (stop - start.max(today0)).num_seconds().max(0);
        s.week_s += secs;
        s.today_s += today_secs;
        if let Some(uid) = dotos_uid(&tags) {
            *s.by_task_week.entry(uid.clone()).or_default() += secs;
            *s.by_task_today.entry(uid).or_default() += today_secs;
        }
        if let Some(p) = tags.iter().find_map(|t| t.strip_prefix('+')) {
            *s.by_project_week.entry(p.to_string()).or_default() += secs;
        }
        if end.is_none() {
            let title = tags.iter().find(|t| !t.starts_with("dotos:") && !t.starts_with('+') && t.contains(' ')).cloned()
                .or_else(|| tags.last().cloned()).unwrap_or_default();
            s.active = Some(Active { uid: dotos_uid(&tags).unwrap_or_default(), title, tags: tags.clone(), since: start.timestamp() });
        }
    }
    s
}

/// Total tracked on one task, ever.
pub fn total_for(uid: &str) -> i64 {
    let tag = format!("dotos:{uid}");
    let now = Utc::now();
    entries(&tag).iter().filter_map(|e| {
        let start = e["start"].as_str().and_then(ts)?;
        let end = e["end"].as_str().and_then(ts).unwrap_or(now);
        Some((end - start).num_seconds().max(0))
    }).sum()
}

pub fn start(uid: &str, title: &str, list: &str, project: &str) -> Result<(), String> {
    let id = format!("dotos:{uid}");
    let proj = format!("+{project}");
    let mut args = vec!["start", id.as_str()];
    if !list.is_empty() { args.push(list); }
    if !project.is_empty() { args.push(proj.as_str()); }
    if !title.is_empty() { args.push(title); }
    let out = Command::new("timew").args(&args).output().map_err(|e| format!("timew: {e}"))?;
    if out.status.success() { Ok(()) } else { Err(String::from_utf8_lossy(&out.stderr).trim().to_string()) }
}

pub fn stop() -> Result<(), String> {
    let out = Command::new("timew").arg("stop").output().map_err(|e| format!("timew: {e}"))?;
    // "There is no active time tracking." is not worth failing over
    if out.status.success() || String::from_utf8_lossy(&out.stderr).contains("no active") { Ok(()) }
    else { Err(String::from_utf8_lossy(&out.stderr).trim().to_string()) }
}

/// Seconds tracked per task uid over a timew range (":month", ":year", …).
pub fn tracked_by_task(range: &str) -> HashMap<String, i64> {
    let now = Utc::now();
    let mut out: HashMap<String, i64> = HashMap::new();
    for e in entries(range) {
        let Some(start) = e["start"].as_str().and_then(ts) else { continue };
        let end = e["end"].as_str().and_then(ts).unwrap_or(now);
        let tags: Vec<String> = e["tags"].as_array().map(|a| a.iter().filter_map(|t| t.as_str().map(String::from)).collect()).unwrap_or_default();
        if let Some(uid) = dotos_uid(&tags) {
            *out.entry(uid).or_default() += (end - start).num_seconds().max(0);
        }
    }
    out
}

/// Seconds tracked per local day and project (tag "+name", else "(none)") over the last `days` days.
pub fn per_day(days: i64) -> std::collections::BTreeMap<String, HashMap<String, i64>> {
    use chrono::{Duration, NaiveTime};
    let mut out: std::collections::BTreeMap<String, HashMap<String, i64>> = Default::default();
    let today = Local::now().date_naive();
    let from = today - Duration::days(days - 1);
    let range = format!("from {} to {}", from.format("%Y-%m-%d"), (today + Duration::days(1)).format("%Y-%m-%d"));
    let now = Utc::now();
    for e in entries(&range) {
        let Some(start) = e["start"].as_str().and_then(ts) else { continue };
        let end = e["end"].as_str().and_then(ts).unwrap_or(now);
        let tags: Vec<String> = e["tags"].as_array().map(|a| a.iter().filter_map(|t| t.as_str().map(String::from)).collect()).unwrap_or_default();
        let project = tags.iter().find_map(|t| t.strip_prefix('+')).unwrap_or("(none)").to_string();
        let (ls, le) = (start.with_timezone(&Local).naive_local(), end.with_timezone(&Local).naive_local());
        let mut d = ls.date();
        while d <= le.date() {
            let d0 = d.and_time(NaiveTime::MIN);
            let d1 = d0 + Duration::days(1);
            let secs = (le.min(d1) - ls.max(d0)).num_seconds();
            if secs > 0 && d >= from {
                *out.entry(d.format("%Y-%m-%d").to_string()).or_default().entry(project.clone()).or_default() += secs;
            }
            d += Duration::days(1);
        }
    }
    out
}
