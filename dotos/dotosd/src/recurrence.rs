//! Repeating tasks: completing one moves its due date to the next occurrence
//! instead of closing it. The rule is a plain RRULE (a phone reads it), plus
//! X-DOTOS-REPEAT=done when the next one counts from completion, not the schedule.

use crate::model;
use chrono::{Datelike, Duration, Local, Months, NaiveDate, NaiveDateTime};
use icalcore::recur::{self, Freq};
use icalcore::todo::Todo;

/// "daily" · "weekly" · "3d" · "2w" · "mon,thu" · "weekdays" · "+3d" (from completion)
/// → (RRULE, counts from completion)
pub fn parse_token(v: &str) -> Option<(String, bool)> {
    let (v, after) = match v.strip_prefix('+') { Some(r) => (r, true), None => (v, false) };
    let l = v.to_ascii_lowercase();
    let rule = match l.as_str() {
        "daily" | "day" => "FREQ=DAILY".to_string(),
        "weekly" | "week" => "FREQ=WEEKLY".into(),
        "monthly" | "month" => "FREQ=MONTHLY".into(),
        "yearly" | "year" => "FREQ=YEARLY".into(),
        "weekdays" => "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR".into(),
        _ => {
            let digits = l.find(|c: char| !c.is_ascii_digit()).filter(|i| *i > 0);
            if let Some(i) = digits {
                let n: u32 = l[..i].parse().ok()?;
                let f = match &l[i..] { "d" => "DAILY", "w" => "WEEKLY", "m" => "MONTHLY", "y" => "YEARLY", _ => return None };
                if n == 0 { return None; }
                format!("FREQ={f};INTERVAL={n}")
            } else {
                let days: Option<Vec<&str>> = l.split(',').map(|d| match d {
                    "mon" => Some("MO"), "tue" => Some("TU"), "wed" => Some("WE"), "thu" => Some("TH"),
                    "fri" => Some("FR"), "sat" => Some("SA"), "sun" => Some("SU"), _ => None,
                }).collect();
                format!("FREQ=WEEKLY;BYDAY={}", days?.join(","))
            }
        }
    };
    Some((rule, after))
}

/// The occurrence after `from` (time of day kept). None when the rule has ended.
pub fn next(rule: &str, from: NaiveDateTime) -> Option<NaiveDateTime> {
    let r = recur::parse(rule)?;
    let d = from.date();
    let iv = r.interval.max(1);
    let nd: NaiveDate = match r.freq {
        Freq::Daily => d + Duration::days(iv as i64),
        Freq::Weekly if r.byday.is_empty() => d + Duration::weeks(iv as i64),
        Freq::Weekly => {
            let mut days: Vec<i64> = r.byday.iter().map(|(_, w)| w.num_days_from_monday() as i64).collect();
            days.sort_unstable();
            days.dedup();
            let cur = d.weekday().num_days_from_monday() as i64;
            match days.iter().find(|w| **w > cur) {
                Some(w) => d + Duration::days(w - cur),
                None => d - Duration::days(cur) + Duration::weeks(iv as i64) + Duration::days(days[0]),
            }
        }
        Freq::Monthly => d.checked_add_months(Months::new(iv))?,
        Freq::Yearly => d.checked_add_months(Months::new(12 * iv))?,
    };
    if r.until.is_some_and(|u| nd > u) { return None; }
    Some(nd.and_time(from.time()))
}

/// COUNT=n → COUNT=n-1; None when that was the last one.
fn tick_count(rule: &str) -> Option<String> {
    let mut out = Vec::new();
    for part in rule.split(';') {
        match part.strip_prefix("COUNT=").map(|n| n.trim().parse::<u32>()) {
            Some(Ok(n)) if n <= 1 => return None,
            Some(Ok(n)) => out.push(format!("COUNT={}", n - 1)),
            _ => out.push(part.to_string()),
        }
    }
    Some(out.join(";"))
}

/// Completing a repeating task: move it to its next occurrence and keep it open.
/// False when it does not repeat (or the series is over) and should simply close.
pub fn advance(t: &mut Todo) -> bool {
    let (Some(due), false) = (t.due, t.rrule.is_empty()) else { return false };
    let Some(rule) = tick_count(&t.rrule) else { return false };
    let now = Local::now().naive_local();
    let from_done = model::get(t, "REPEAT").as_deref() == Some("done");
    let mut cur = if from_done { now.date().and_time(due.time()) } else { due };
    let Some(mut n) = next(&rule, cur) else { return false };
    // a fixed schedule skips what has already passed, so completing a task
    // that is weeks late does not leave it overdue again
    for _ in 0..400 {
        if from_done || n.date() > now.date() { break; }
        cur = n;
        match next(&rule, cur) { Some(x) => n = x, None => return false }
    }
    t.due = Some(n);
    t.rrule = rule;
    t.reopen();
    model::set(t, "STATE", Some("todo"));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(y: i32, m: u32, d: u32) -> NaiveDateTime {
        NaiveDate::from_ymd_opt(y, m, d).unwrap().and_hms_opt(9, 0, 0).unwrap()
    }

    #[test]
    fn tokens() {
        assert_eq!(parse_token("daily"), Some(("FREQ=DAILY".into(), false)));
        assert_eq!(parse_token("+3d"), Some(("FREQ=DAILY;INTERVAL=3".into(), true)));
        assert_eq!(parse_token("mon,thu").unwrap().0, "FREQ=WEEKLY;BYDAY=MO,TH");
        assert_eq!(parse_token("soon"), None);
        assert_eq!(parse_token("0d"), None);
    }

    #[test]
    fn weekly_days_walk_the_week_then_jump() {
        // 2026-10-19 is a Monday
        assert_eq!(next("FREQ=WEEKLY;BYDAY=MO,TH", at(2026, 10, 19)), Some(at(2026, 10, 22)));
        assert_eq!(next("FREQ=WEEKLY;BYDAY=MO,TH", at(2026, 10, 22)), Some(at(2026, 10, 26)));
        assert_eq!(next("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO", at(2026, 10, 19)), Some(at(2026, 11, 2)));
    }

    #[test]
    fn monthly_clamps_and_until_ends() {
        assert_eq!(next("FREQ=MONTHLY", at(2026, 1, 31)), Some(at(2026, 2, 28)));
        assert_eq!(next("FREQ=DAILY;UNTIL=20261019", at(2026, 10, 19)), None);
    }

    #[test]
    fn count_runs_out() {
        assert_eq!(tick_count("FREQ=DAILY;COUNT=3").as_deref(), Some("FREQ=DAILY;COUNT=2"));
        assert_eq!(tick_count("FREQ=DAILY;COUNT=1"), None);
    }
}
