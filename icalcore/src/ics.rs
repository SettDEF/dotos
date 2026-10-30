//! A deliberately small iCalendar reader/writer: VEVENT only, the properties
//! this app actually stores.
//!
//! Not a general parser. It handles line unfolding, escaping, DATE vs
//! DATE-TIME and the UTC suffix, because those are the parts that silently
//! corrupt data if you get them wrong. Anything else is preserved verbatim in
//! `extra` so a round-trip through this app does not destroy properties
//! written by another calendar.

use chrono::{DateTime, Local, NaiveDate, NaiveDateTime, TimeZone};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub uid: String,
    pub calendar: String,
    pub summary: String,
    /// Local wall-clock start. All-day events use 00:00.
    pub start: NaiveDateTime,
    pub end: NaiveDateTime,
    pub all_day: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub location: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub rrule: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub extra: Vec<String>,
}

impl Event {
    pub fn duration_minutes(&self) -> i64 {
        (self.end - self.start).num_minutes().max(0)
    }
    /// Does this event touch the given day?
    pub fn on_day(&self, day: NaiveDate) -> bool {
        self.overlaps(day, day)
    }
    /// Does this event touch any day in [from, to]? All-day DTEND is
    /// exclusive, so the last day it actually occupies is the day before.
    pub fn overlaps(&self, from: NaiveDate, to: NaiveDate) -> bool {
        let s = self.start.date();
        let e = if self.all_day { self.end.date().pred_opt().unwrap_or(self.end.date()) } else { self.end.date() };
        s <= to && e >= from
    }
}

pub(crate) fn unescape(v: &str) -> String {
    v.replace("\\n", "\n").replace("\\N", "\n")
        .replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")
}
pub(crate) fn escape(v: &str) -> String {
    v.replace('\\', "\\\\").replace('\n', "\\n")
        .replace(',', "\\,").replace(';', "\\;")
}

/// RFC 5545 folds long lines; a continuation starts with a space or tab.
fn unfold(src: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for raw in src.lines() {
        let line = raw.trim_end_matches('\r');
        if (line.starts_with(' ') || line.starts_with('\t')) && !out.is_empty() {
            let last = out.last_mut().unwrap();
            last.push_str(&line[1..]);
        } else {
            out.push(line.to_string());
        }
    }
    out
}

pub(crate) fn fold(line: &str) -> String {
    // 75 octets is the limit; split on char boundaries to stay valid UTF-8.
    if line.len() <= 73 { return line.to_string(); }
    let mut out = String::new();
    let mut count = 0;
    for (i, ch) in line.char_indices() {
        if count >= 73 && i > 0 { out.push_str("\r\n "); count = 1; }
        out.push(ch);
        count += ch.len_utf8();
    }
    out
}

/// "20260926", "20260926T140000", "20260926T120000Z", or a wall-clock stamp
/// qualified by TZID. `tzid` is the TZID parameter if the property carried one.
///
/// Everything is stored as local wall-clock time, so a zoned stamp has to be
/// converted on the way in. Dropping TZID and reading the stamp as local is
/// how a 2pm New York meeting became 2pm Berlin — six hours wrong, silently.
pub(crate) fn parse_stamp(value: &str, is_date: bool, tzid: Option<&str>) -> Option<(NaiveDateTime, bool)> {
    let v = value.trim();
    if is_date || v.len() == 8 {
        let d = NaiveDate::parse_from_str(v, "%Y%m%d").ok()?;
        return Some((d.and_hms_opt(0, 0, 0)?, true));
    }
    if let Some(stripped) = v.strip_suffix('Z') {
        let naive = NaiveDateTime::parse_from_str(stripped, "%Y%m%dT%H%M%S").ok()?;
        // Stored as UTC; show it in the machine's zone.
        let utc = chrono::Utc.from_utc_datetime(&naive);
        return Some((utc.with_timezone(&Local).naive_local(), false));
    }
    let naive = NaiveDateTime::parse_from_str(v, "%Y%m%dT%H%M%S").ok()?;
    if let Some(zone) = tzid.and_then(parse_tzid) {
        // A DST gap or fold makes this ambiguous; take the earlier instant
        // rather than dropping the event.
        if let Some(zoned) = zone.from_local_datetime(&naive).earliest() {
            return Some((zoned.with_timezone(&Local).naive_local(), false));
        }
    }
    Some((naive, false))
}

/// TZID values are usually bare IANA names but may be quoted, and Microsoft
/// emits its own names which are not IANA and cannot be resolved here.
fn parse_tzid(raw: &str) -> Option<Tz> {
    let name = raw.trim().trim_matches('"');
    match name.parse::<Tz>() {
        Ok(tz) => Some(tz),
        Err(_) => {
            crate::warn(&format!("unknown time zone '{name}', reading the time as local"));
            None
        }
    }
}

pub(crate) fn fmt_stamp(dt: &NaiveDateTime, all_day: bool) -> String {
    if all_day { dt.format("%Y%m%d").to_string() }
    else {
        // Written as UTC so other clients read it unambiguously.
        match Local.from_local_datetime(dt).single() {
            Some(local) => local.with_timezone(&chrono::Utc).format("%Y%m%dT%H%M%SZ").to_string(),
            None => dt.format("%Y%m%dT%H%M%S").to_string(),
        }
    }
}

/// One property line, split into the parts every component cares about.
pub(crate) struct Prop {
    pub name: String,
    pub value: String,
    /// The property declared VALUE=DATE, so it is a day, not an instant.
    pub is_date: bool,
    /// DTSTART;TZID=America/New_York:... — the zone lives in the parameters.
    pub tzid: Option<String>,
    /// The line as written, for components that keep what they do not model.
    pub raw: String,
}

pub(crate) fn split_prop(line: &str) -> Option<Prop> {
    let colon = line.find(':')?;
    let (head, value) = line.split_at(colon);
    let mut parts = head.split(';');
    let name = parts.next().unwrap_or("").to_ascii_uppercase();
    let tzid = parts.find_map(|p| {
        let p = p.trim();
        (p.len() > 5 && p[..5].eq_ignore_ascii_case("TZID=")).then(|| p[5..].to_string())
    });
    Some(Prop {
        name,
        value: value[1..].to_string(),
        is_date: head.to_ascii_uppercase().contains("VALUE=DATE"),
        tzid,
        raw: line.to_string(),
    })
}

/// The property lines of each BEGIN:<kind> ... END:<kind> block.
///
/// One reader for VEVENT and VTODO: they are the same file format, and two
/// copies of the unfolding and block tracking would drift.
pub(crate) fn blocks(src: &str, kind: &str) -> Vec<Vec<String>> {
    let begin = format!("BEGIN:{kind}");
    let end = format!("END:{kind}");
    let mut out = Vec::new();
    let mut cur: Option<Vec<String>> = None;
    for line in unfold(src) {
        if line.eq_ignore_ascii_case(&begin) {
            // A nested BEGIN means the previous block never closed. Say so
            // rather than overwriting it — silently discarding half a file is
            // the opposite of the lossless round-trip this module promises.
            if cur.is_some() {
                crate::warn(&format!("a {kind} was not closed before the next one began; \
                                      the unterminated one was skipped"));
            }
            cur = Some(Vec::new());
            continue;
        }
        if line.eq_ignore_ascii_case(&end) {
            if let Some(b) = cur.take() { out.push(b); }
            continue;
        }
        if let Some(b) = cur.as_mut() { b.push(line); }
    }
    if cur.is_some() {
        crate::warn(&format!("a {kind} was never closed; it was skipped"));
    }
    out
}

pub fn parse(src: &str, calendar: &str) -> Vec<Event> {
    let mut events = Vec::new();
    for block in blocks(src, "VEVENT") {
        let mut ev = Event {
            uid: String::new(), calendar: calendar.to_string(), summary: String::new(),
            start: NaiveDateTime::MIN, end: NaiveDateTime::MIN, all_day: false,
            location: String::new(), description: String::new(),
            rrule: String::new(), extra: Vec::new(),
        };
        for line in block {
            let Some(p) = split_prop(&line) else { continue };
            match p.name.as_str() {
                "UID" => ev.uid = p.value,
                "SUMMARY" => ev.summary = unescape(&p.value),
                "LOCATION" => ev.location = unescape(&p.value),
                "DESCRIPTION" => ev.description = unescape(&p.value),
                "RRULE" => ev.rrule = p.value,
                "DTSTART" => if let Some((dt, ad)) = parse_stamp(&p.value, p.is_date, p.tzid.as_deref()) {
                    ev.start = dt; ev.all_day = ad;
                },
                "DTEND" => if let Some((dt, _)) = parse_stamp(&p.value, p.is_date, p.tzid.as_deref()) {
                    ev.end = dt;
                },
                // Keep anything we do not model, so a round-trip is lossless.
                _ => ev.extra.push(p.raw),
            }
        }
        if ev.end <= ev.start {
            ev.end = if ev.all_day { ev.start + chrono::Duration::days(1) }
                     else { ev.start + chrono::Duration::hours(1) };
        }
        if ev.uid.is_empty() {
            let what = if ev.summary.is_empty() { "(no summary)" } else { &ev.summary };
            crate::warn(&format!("skipped a VEVENT with no UID: {what}"));
            continue;
        }
        events.push(ev);
    }
    events
}

pub fn serialize(events: &[Event], prodid: &str) -> String {
    let mut out = format!("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//{prodid}//EN\r\n");
    for ev in events {
        out.push_str("BEGIN:VEVENT\r\n");
        let mut push = |l: String| { out.push_str(&fold(&l)); out.push_str("\r\n"); };
        push(format!("UID:{}", ev.uid));
        push(format!("SUMMARY:{}", escape(&ev.summary)));
        if ev.all_day {
            push(format!("DTSTART;VALUE=DATE:{}", fmt_stamp(&ev.start, true)));
            push(format!("DTEND;VALUE=DATE:{}", fmt_stamp(&ev.end, true)));
        } else {
            push(format!("DTSTART:{}", fmt_stamp(&ev.start, false)));
            push(format!("DTEND:{}", fmt_stamp(&ev.end, false)));
        }
        if !ev.location.is_empty() { push(format!("LOCATION:{}", escape(&ev.location))); }
        if !ev.description.is_empty() { push(format!("DESCRIPTION:{}", escape(&ev.description))); }
        if !ev.rrule.is_empty() { push(format!("RRULE:{}", ev.rrule)); }
        for line in &ev.extra { push(line.clone()); }
        out.push_str("END:VEVENT\r\n");
    }
    out.push_str("END:VCALENDAR\r\n");
    out
}

pub fn now_local() -> NaiveDateTime { Local::now().naive_local() }
pub fn today() -> NaiveDate { Local::now().date_naive() }
pub fn to_local(dt: DateTime<Local>) -> NaiveDateTime { dt.naive_local() }
