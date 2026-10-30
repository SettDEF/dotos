//! RRULE expansion.
//!
//! Occurrences are generated on the fly for a query range; nothing recurring
//! is ever written to disk. The CLI and every front-end therefore agree by
//! construction, because they all ask this one function.
//!
//! Times are naive local wall-clock, and that is deliberate for recurrence:
//! "standup at 09:00 every Monday" should stay at 09:00 after the clocks
//! change, not drift to 08:00. Naive arithmetic gives exactly that. An event
//! anchored to an absolute instant instead would need a per-event TZID, which
//! the store does not model.

use chrono::{Datelike, Duration, NaiveDate, NaiveDateTime, Weekday};
use crate::ics::Event;

/// A run-away RRULE (no COUNT, no UNTIL, a huge range) must not hang the
/// caller. Ranges asked for by the UI are weeks; a year of daily events is
/// 365. This is far above any honest query and far below a freeze.
const MAX_OCCURRENCES: usize = 2000;

#[derive(Debug, Clone, PartialEq)]
pub enum Freq { Daily, Weekly, Monthly, Yearly }

#[derive(Debug, Clone)]
pub struct Rrule {
    pub freq: Freq,
    pub interval: u32,
    pub count: Option<u32>,
    pub until: Option<NaiveDate>,
    /// (ordinal, weekday) — the ordinal is only meaningful for MONTHLY/YEARLY,
    /// as in "3TU" for the third Tuesday.
    pub byday: Vec<(Option<i32>, Weekday)>,
}

fn weekday(code: &str) -> Option<Weekday> {
    match code {
        "MO" => Some(Weekday::Mon), "TU" => Some(Weekday::Tue), "WE" => Some(Weekday::Wed),
        "TH" => Some(Weekday::Thu), "FR" => Some(Weekday::Fri), "SA" => Some(Weekday::Sat),
        "SU" => Some(Weekday::Sun), _ => None,
    }
}

/// "FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2;COUNT=10"
pub fn parse(rule: &str) -> Option<Rrule> {
    let mut freq = None;
    let mut interval = 1u32;
    let mut count = None;
    let mut until = None;
    let mut byday = Vec::new();

    for part in rule.split(';') {
        let (k, v) = part.split_once('=')?;
        match k.trim().to_ascii_uppercase().as_str() {
            "FREQ" => freq = match v.trim().to_ascii_uppercase().as_str() {
                "DAILY" => Some(Freq::Daily),
                "WEEKLY" => Some(Freq::Weekly),
                "MONTHLY" => Some(Freq::Monthly),
                "YEARLY" => Some(Freq::Yearly),
                other => { crate::warn(&format!("unsupported FREQ={other}")); return None; }
            },
            "INTERVAL" => interval = v.trim().parse().unwrap_or(1).max(1),
            "COUNT" => count = v.trim().parse().ok(),
            "UNTIL" => until = parse_until(v.trim()),
            "BYDAY" => for token in v.split(',') {
                let t = token.trim().to_ascii_uppercase();
                let (ord, code) = split_ordinal(&t);
                if let Some(w) = weekday(code) { byday.push((ord, w)); }
            },
            // BYMONTHDAY, BYSETPOS and friends are not modelled. Silently
            // ignoring them would produce plausible but wrong dates.
            "BYMONTHDAY" | "BYSETPOS" | "BYMONTH" | "BYWEEKNO" | "BYYEARDAY" => {
                crate::warn(&format!("{k} is not supported yet; occurrences may be wrong"));
            }
            _ => {}
        }
    }
    Some(Rrule { freq: freq?, interval, count, until, byday })
}

/// "3TU" -> (Some(3), "TU");  "-1FR" -> (Some(-1), "FR");  "MO" -> (None, "MO")
fn split_ordinal(token: &str) -> (Option<i32>, &str) {
    let split = token.find(|c: char| c.is_ascii_alphabetic()).unwrap_or(0);
    if split == 0 { return (None, token); }
    (token[..split].parse().ok(), &token[split..])
}

fn parse_until(v: &str) -> Option<NaiveDate> {
    let s = v.trim_end_matches('Z');
    if let Some((d, _)) = s.split_once('T') {
        return NaiveDate::parse_from_str(d, "%Y%m%d").ok();
    }
    NaiveDate::parse_from_str(s, "%Y%m%d").ok()
}

/// EXDATE lives in `extra`, since the parser keeps unmodelled properties
/// verbatim. Each can carry several comma-separated dates.
fn exdates(ev: &Event) -> Vec<NaiveDate> {
    let mut out = Vec::new();
    for line in &ev.extra {
        let upper = line.to_ascii_uppercase();
        if !upper.starts_with("EXDATE") { continue; }
        let Some((_, value)) = line.split_once(':') else { continue };
        for token in value.split(',') {
            let t = token.trim().trim_end_matches('Z');
            let date = t.split_once('T').map(|(d, _)| d).unwrap_or(t);
            if let Ok(d) = NaiveDate::parse_from_str(date, "%Y%m%d") { out.push(d); }
        }
    }
    out
}

fn nth_weekday(year: i32, month: u32, ord: i32, wd: Weekday) -> Option<NaiveDate> {
    if ord > 0 {
        let first = NaiveDate::from_ymd_opt(year, month, 1)?;
        let shift = (wd.num_days_from_monday() as i32
                   - first.weekday().num_days_from_monday() as i32).rem_euclid(7);
        let day = 1 + shift + (ord - 1) * 7;
        NaiveDate::from_ymd_opt(year, month, day as u32)
    } else {
        // -1FR is the last Friday of the month.
        let next = if month == 12 { NaiveDate::from_ymd_opt(year + 1, 1, 1)? }
                   else { NaiveDate::from_ymd_opt(year, month + 1, 1)? };
        let last = next.pred_opt()?;
        let back = (last.weekday().num_days_from_monday() as i32
                  - wd.num_days_from_monday() as i32).rem_euclid(7);
        last.checked_sub_signed(Duration::days((back + (-ord - 1) * 7) as i64))
    }
}

/// Every start date this rule produces that falls within [from, to].
/// `anchor` is the event's own DTSTART date — the series origin.
fn occurrence_dates(r: &Rrule, anchor: NaiveDate, from: NaiveDate, to: NaiveDate) -> Vec<NaiveDate> {
    let mut out = Vec::new();
    let mut emitted = 0u32;
    let hard_stop = r.until.unwrap_or(to).min(to);

    // Counting has to start from the anchor even when the query window starts
    // later, or COUNT would mean "n occurrences inside your view".
    let mut cursor = anchor;
    let mut guard = 0usize;
    // Monthly and yearly step from the ANCHOR, not from the previous cursor.
    // Stepping from the cursor means 31 Jan clamps to 28 Feb and then never
    // recovers: the series becomes the 28th forever. RFC 5545 anchors every
    // occurrence to DTSTART's day-of-month.
    let mut step = 0i32;

    while cursor <= hard_stop && guard < MAX_OCCURRENCES {
        guard += 1;
        let mut day_batch: Vec<NaiveDate> = Vec::new();

        match r.freq {
            Freq::Daily => day_batch.push(cursor),
            Freq::Weekly => {
                if r.byday.is_empty() {
                    day_batch.push(cursor);
                } else {
                    // The whole week the cursor sits in, Monday first.
                    let monday = cursor - Duration::days(
                        cursor.weekday().num_days_from_monday() as i64);
                    for (_, wd) in &r.byday {
                        let d = monday + Duration::days(wd.num_days_from_monday() as i64);
                        if d >= anchor { day_batch.push(d); }
                    }
                    day_batch.sort();
                }
            }
            Freq::Monthly | Freq::Yearly => {
                if r.byday.is_empty() {
                    day_batch.push(cursor);
                } else {
                    for (ord, wd) in &r.byday {
                        if let Some(d) = nth_weekday(cursor.year(), cursor.month(),
                                                     ord.unwrap_or(1), *wd) {
                            if d >= anchor { day_batch.push(d); }
                        }
                    }
                    day_batch.sort();
                }
            }
        }

        for d in day_batch {
            if let Some(n) = r.count { if emitted >= n { return out; } }
            if d > hard_stop { continue; }
            emitted += 1;
            if d >= from { out.push(d); }
        }

        step += 1;
        cursor = match r.freq {
            Freq::Daily => cursor + Duration::days(r.interval as i64),
            Freq::Weekly => cursor + Duration::weeks(r.interval as i64),
            Freq::Monthly => add_months(anchor, step * r.interval as i32),
            Freq::Yearly => add_months(anchor, step * 12 * r.interval as i32),
        };
    }
    out
}

/// Month arithmetic that clamps rather than overflowing: 31 Jan + 1 month is
/// 28/29 Feb, not an invalid date that silently drops the occurrence.
fn add_months(d: NaiveDate, months: i32) -> NaiveDate {
    let total = d.year() * 12 + d.month0() as i32 + months;
    let (y, m0) = (total.div_euclid(12), total.rem_euclid(12));
    let last = days_in_month(y, m0 as u32 + 1);
    NaiveDate::from_ymd_opt(y, m0 as u32 + 1, d.day().min(last)).unwrap_or(d)
}

fn days_in_month(y: i32, m: u32) -> u32 {
    let next = if m == 12 { NaiveDate::from_ymd_opt(y + 1, 1, 1) }
               else { NaiveDate::from_ymd_opt(y, m + 1, 1) };
    next.and_then(|n| n.pred_opt()).map(|d| d.day()).unwrap_or(28)
}

/// Expands one event into the occurrences that fall in [from, to].
/// A non-recurring event returns itself when it overlaps the range.
pub fn expand(ev: &Event, from: NaiveDate, to: NaiveDate) -> Vec<Event> {
    if ev.rrule.is_empty() {
        let mut d = from;
        while d <= to {
            if ev.on_day(d) { return vec![ev.clone()]; }
            d += Duration::days(1);
        }
        return Vec::new();
    }
    let Some(rule) = parse(&ev.rrule) else { return vec![ev.clone()] };

    let anchor = ev.start.date();
    let span = ev.end - ev.start;
    let skip = exdates(ev);
    let time = ev.start.time();

    occurrence_dates(&rule, anchor, from, to).into_iter()
        .filter(|d| !skip.contains(d))
        .map(|d| {
            let mut occ = ev.clone();
            occ.start = NaiveDateTime::new(d, time);
            occ.end = occ.start + span;
            occ
        })
        .collect()
}
