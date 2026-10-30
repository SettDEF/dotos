//! Reading what a person typed.
//!
//! Not iCalendar, but shared for the same reason: "tomorrow" and "1h30m" must
//! mean exactly the same thing in `kalends add` and `dotos add`, and two
//! copies of a date parser is how they stop meaning the same thing.

use chrono::{Duration, NaiveDate, NaiveDateTime};
use crate::ics;

/// The value after `--name`, if it is there.
pub fn flag(args: &[String], name: &str) -> Option<String> {
    let i = args.iter().position(|a| a == name)?;
    args.get(i + 1).cloned()
}

pub fn has(args: &[String], name: &str) -> bool { args.iter().any(|a| a == name) }

/// 'today', 'tomorrow', 'YYYY-MM-DD'. Deliberately not natural language:
/// guessing what "next friday" means is how calendars book the wrong day.
pub fn parse_date(v: &str) -> Option<NaiveDate> {
    match v.trim().to_ascii_lowercase().as_str() {
        "today" => Some(ics::today()),
        "tomorrow" => Some(ics::today() + Duration::days(1)),
        "yesterday" => Some(ics::today() - Duration::days(1)),
        other => NaiveDate::parse_from_str(other, "%Y-%m-%d").ok(),
    }
}

pub fn parse_when(v: &str) -> Option<NaiveDateTime> {
    let v = v.trim();
    if let Some(d) = parse_date(v) {
        return d.and_hms_opt(0, 0, 0);
    }
    if let Ok(dt) = NaiveDateTime::parse_from_str(v, "%Y-%m-%d %H:%M") { return Some(dt); }
    if let Ok(dt) = NaiveDateTime::parse_from_str(v, "%Y-%m-%dT%H:%M") { return Some(dt); }
    // Bare HH:MM means today.
    if let Ok(t) = chrono::NaiveTime::parse_from_str(v, "%H:%M") {
        return Some(NaiveDateTime::new(ics::today(), t));
    }
    // 'today 14:00' / 'tomorrow 9:30'
    let (head, tail) = v.split_once(' ')?;
    let d = parse_date(head)?;
    let t = chrono::NaiveTime::parse_from_str(tail, "%H:%M").ok()?;
    Some(NaiveDateTime::new(d, t))
}

/// '90m', '2h', '1h30m'
pub fn parse_duration(v: &str) -> Option<Duration> {
    let v = v.trim().to_ascii_lowercase();
    let mut total = 0i64;
    let mut num = String::new();
    let mut saw_unit = false;
    for ch in v.chars() {
        if ch.is_ascii_digit() { num.push(ch); continue; }
        let n: i64 = num.parse().ok()?;
        num.clear();
        saw_unit = true;
        match ch {
            'h' => total += n * 60,
            'm' => total += n,
            'd' => total += n * 60 * 24,
            _ => return None,
        }
    }
    if !num.is_empty() && !saw_unit { total += num.parse::<i64>().ok()?; }
    if total <= 0 { return None; }
    Some(Duration::minutes(total))
}
