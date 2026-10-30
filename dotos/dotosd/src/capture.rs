//! One line in, a whole task out — the syntax shared by the window, the
//! shell's capture popup, Neovim and `dotos capture`:
//!
//!   Call dentist @fri 14:00 !high #health ~30m +safemap /work
//!
//!   @when     today · tomorrow · mon..sun (the next one; today counts) ·
//!             2026-10-20 · 20.10 · 20.10.2026 · +3d · +2w — then an optional HH:MM
//!   !level    !high !normal !low (also !1 !2 !3, and a bare "!" = high)
//!   #tag      any number
//!   ~time     estimate: ~30m ~2h ~1h30m
//!   +project  a project name (a folder under the project roots)
//!   /list     the list to put it in
//!   >state    >inbox >doing >waiting
//!   *repeat   *daily *weekly *monthly *yearly *weekdays *3d *2w *mon,thu — and
//!             *+3d counts from completion instead of the schedule
//!
//! Everything else is the title. A token that looks like syntax but does not
//! parse stays in the title, so "costs ~€5" is not silently eaten.

use chrono::{Datelike, Duration, NaiveDate, NaiveDateTime, NaiveTime};
use icalcore::todo::Importance;
use serde::Serialize;

#[derive(Debug, Default, Serialize)]
pub struct Parsed {
    pub title: String,
    pub due: Option<NaiveDateTime>,
    pub due_time: bool,
    pub importance: Option<&'static str>,
    pub tags: Vec<String>,
    pub estimate_min: Option<u32>,
    pub project: Option<String>,
    pub list: Option<String>,
    pub state: Option<String>,
    pub repeat: Option<String>,
    pub repeat_after: bool,
}

impl Parsed {
    pub fn importance(&self) -> Option<Importance> {
        self.importance.and_then(Importance::parse)
    }
}

fn weekday(s: &str) -> Option<u32> {
    let s = s.to_ascii_lowercase();
    let days = [
        ["mon", "monday", "mo", "montag"], ["tue", "tuesday", "di", "dienstag"],
        ["wed", "wednesday", "mi", "mittwoch"], ["thu", "thursday", "do", "donnerstag"],
        ["fri", "friday", "fr", "freitag"], ["sat", "saturday", "sa", "samstag"],
        ["sun", "sunday", "so", "sonntag"],
    ];
    days.iter().position(|names| names.contains(&s.as_str())).map(|i| i as u32)
}

pub fn date(s: &str, today: NaiveDate) -> Option<NaiveDate> {
    let l = s.to_ascii_lowercase();
    match l.as_str() {
        "today" | "heute" | "tod" => return Some(today),
        "tomorrow" | "morgen" | "tom" => return Some(today + Duration::days(1)),
        _ => {}
    }
    if let Some(w) = weekday(&l) {
        let diff = (w as i64 - today.weekday().num_days_from_monday() as i64).rem_euclid(7);
        return Some(today + Duration::days(diff));
    }
    if let Some(rest) = l.strip_prefix('+') {
        let (n, unit) = rest.split_at(rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len()));
        let n: i64 = n.parse().ok()?;
        return Some(match unit {
            "" | "d" => today + Duration::days(n),
            "w" => today + Duration::weeks(n),
            "m" => today.checked_add_months(chrono::Months::new(n as u32))?,
            _ => return None,
        });
    }
    if let Ok(d) = NaiveDate::parse_from_str(&l, "%Y-%m-%d") {
        return Some(d);
    }
    if let Ok(d) = NaiveDate::parse_from_str(&l, "%d.%m.%Y") {
        return Some(d);
    }
    // 20.10 → this year, or next year if that day has passed
    let parts: Vec<&str> = l.trim_end_matches('.').split('.').collect();
    if parts.len() == 2 {
        let (d, m): (u32, u32) = (parts[0].parse().ok()?, parts[1].parse().ok()?);
        let this = NaiveDate::from_ymd_opt(today.year(), m, d)?;
        return Some(if this < today { NaiveDate::from_ymd_opt(today.year() + 1, m, d)? } else { this });
    }
    None
}

fn time(s: &str) -> Option<NaiveTime> {
    NaiveTime::parse_from_str(s, "%H:%M").ok().or_else(|| {
        // 14h, 9am, 6pm
        let l = s.to_ascii_lowercase();
        let (num, add) = if let Some(n) = l.strip_suffix("pm") { (n, 12) } else if let Some(n) = l.strip_suffix("am") { (n, 0) } else { (l.strip_suffix('h')?, 0) };
        let h: u32 = num.parse().ok()?;
        NaiveTime::from_hms_opt(if add == 12 && h < 12 { h + 12 } else { h % 24 }, 0, 0)
    })
}

pub fn minutes(s: &str) -> Option<u32> {
    let l = s.to_ascii_lowercase();
    let (mut total, mut num) = (0u32, String::new());
    let mut any = false;
    for c in l.chars() {
        if c.is_ascii_digit() {
            num.push(c);
            continue;
        }
        let n: u32 = num.parse().ok()?;
        num.clear();
        total += match c { 'h' => n * 60, 'm' => n, 'd' => n * 60 * 8, _ => return None };
        any = true;
    }
    if !num.is_empty() {
        total += num.parse::<u32>().ok()?; // bare number = minutes
        any = true;
    }
    any.then_some(total)
}

pub fn parse(line: &str, today: NaiveDate) -> Parsed {
    let mut p = Parsed::default();
    let toks: Vec<&str> = line.split_whitespace().collect();
    let mut title: Vec<&str> = Vec::new();
    let mut i = 0;
    while i < toks.len() {
        let t = toks[i];
        let mut used = true;
        if let Some(v) = t.strip_prefix('@') {
            match date(v, today) {
                Some(d) => {
                    // an optional time right after: "@fri 14:00"
                    let tm = toks.get(i + 1).and_then(|n| time(n));
                    if tm.is_some() {
                        i += 1;
                    }
                    p.due_time = tm.is_some();
                    p.due = Some(d.and_time(tm.unwrap_or(NaiveTime::MIN)));
                }
                None => match time(v) {
                    // "@14:00" alone = today at that time
                    Some(tm) => {
                        p.due = Some(today.and_time(tm));
                        p.due_time = true;
                    }
                    None => used = false,
                },
            }
        } else if t == "!" {
            p.importance = Some("high");
        } else if let Some(v) = t.strip_prefix('!') {
            p.importance = match v.to_ascii_lowercase().as_str() {
                "high" | "h" | "1" | "!" => Some("high"),
                "normal" | "n" | "med" | "2" => Some("normal"),
                "low" | "l" | "3" => Some("low"),
                _ => {
                    used = false;
                    None
                }
            };
        } else if let Some(v) = t.strip_prefix('#').filter(|v| !v.is_empty()) {
            p.tags.push(v.to_string());
        } else if let Some(v) = t.strip_prefix('~') {
            match minutes(v) {
                Some(m) => p.estimate_min = Some(m),
                None => used = false,
            }
        } else if let Some(v) = t.strip_prefix('+').filter(|v| !v.is_empty() && !v.starts_with(|c: char| c.is_ascii_digit())) {
            p.project = Some(v.to_string());
        } else if let Some(v) = t.strip_prefix('/').filter(|v| !v.is_empty() && !v.contains('/')) {
            p.list = Some(v.to_string());
        } else if let Some((rule, after)) = t.strip_prefix('*').and_then(crate::recurrence::parse_token) {
            p.repeat = Some(rule);
            p.repeat_after = after;
        } else if let Some(v) = t.strip_prefix('>').filter(|v| crate::model::State::parse(v).is_some()) {
            p.state = Some(v.to_string());
        } else {
            used = false;
        }
        if !used {
            title.push(t);
        }
        i += 1;
    }
    p.title = title.join(" ");
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fri() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 10, 16).unwrap() // a Friday
    }

    #[test]
    fn full_line() {
        let p = parse("Call dentist @fri 14:00 !high #health ~30m +safemap /work", fri());
        assert_eq!(p.title, "Call dentist");
        assert_eq!(p.due, Some(fri().and_hms_opt(14, 0, 0).unwrap()));
        assert!(p.due_time);
        assert_eq!(p.importance, Some("high"));
        assert_eq!(p.tags, vec!["health"]);
        assert_eq!(p.estimate_min, Some(30));
        assert_eq!(p.project.as_deref(), Some("safemap"));
        assert_eq!(p.list.as_deref(), Some("work"));
    }

    #[test]
    fn weekday_is_next_occurrence_today_counts() {
        assert_eq!(parse("x @fri", fri()).due.unwrap().date(), fri());
        assert_eq!(parse("x @mon", fri()).due.unwrap().date(), NaiveDate::from_ymd_opt(2026, 10, 19).unwrap());
    }

    #[test]
    fn german_dates_and_relative() {
        assert_eq!(parse("x @20.10", fri()).due.unwrap().date(), NaiveDate::from_ymd_opt(2026, 10, 20).unwrap());
        assert_eq!(parse("x @01.02", fri()).due.unwrap().date(), NaiveDate::from_ymd_opt(2027, 2, 1).unwrap());
        assert_eq!(parse("x @+3d", fri()).due.unwrap().date(), NaiveDate::from_ymd_opt(2026, 10, 19).unwrap());
    }

    #[test]
    fn junk_stays_in_title() {
        let p = parse("costs ~€5 @someday !wow", fri());
        assert_eq!(p.title, "costs ~€5 @someday !wow");
        assert!(p.due.is_none() && p.importance.is_none() && p.estimate_min.is_none());
    }

    #[test]
    fn estimates() {
        assert_eq!(minutes("1h30m"), Some(90));
        assert_eq!(minutes("2h"), Some(120));
        assert_eq!(minutes("45"), Some(45));
        assert_eq!(minutes("x"), None);
    }
}
