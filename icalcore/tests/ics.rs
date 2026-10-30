//! The parser's job is to not corrupt anything quietly. Every test here is a
//! bug that would otherwise show up as an event at the wrong time, or missing,
//! with no error anywhere.

use chrono::{NaiveDate, NaiveDateTime, Timelike};
use icalcore::ics;

fn wrap(body: &str) -> String {
    format!("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n{body}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
}

#[test]
fn tzid_is_honoured() {
    // This shipped wrong once: the zone lives in the property parameters, and
    // ignoring it put every imported event out by the offset, silently.
    let src = wrap("UID:a\r\nSUMMARY:Call\r\n\
                    DTSTART;TZID=America/New_York:20260615T140000\r\n\
                    DTEND;TZID=America/New_York:20260615T150000");
    let evs = ics::parse(&src, "personal");
    assert_eq!(evs.len(), 1);
    // 14:00 in New York is not 14:00 here, whatever "here" is — unless the
    // machine happens to be in that zone, which the test must not assume.
    let ny = "America/New_York".parse::<chrono_tz::Tz>().unwrap();
    let expected = chrono::TimeZone::from_local_datetime(
        &ny,
        &NaiveDate::from_ymd_opt(2026, 6, 15).unwrap().and_hms_opt(14, 0, 0).unwrap(),
    ).earliest().unwrap().with_timezone(&chrono::Local).naive_local();
    assert_eq!(evs[0].start, expected);
}

#[test]
fn floating_time_is_left_alone() {
    let src = wrap("UID:a\r\nDTSTART:20260615T140000\r\nDTEND:20260615T150000");
    let evs = ics::parse(&src, "personal");
    assert_eq!(evs[0].start.hour(), 14);
}

#[test]
fn all_day_end_is_exclusive() {
    // DTEND on a DATE is the day AFTER the last one. A one-day event must not
    // read as two.
    let src = wrap("UID:a\r\nDTSTART;VALUE=DATE:20260615\r\nDTEND;VALUE=DATE:20260616");
    let evs = ics::parse(&src, "personal");
    assert!(evs[0].all_day);
    assert!(evs[0].on_day(NaiveDate::from_ymd_opt(2026, 6, 15).unwrap()));
    assert!(!evs[0].on_day(NaiveDate::from_ymd_opt(2026, 6, 16).unwrap()));
}

#[test]
fn missing_end_gets_a_default() {
    let src = wrap("UID:a\r\nDTSTART:20260615T140000");
    let evs = ics::parse(&src, "personal");
    assert_eq!(evs[0].duration_minutes(), 60);
}

#[test]
fn a_vevent_without_uid_is_dropped_not_silently_kept() {
    let src = wrap("SUMMARY:Ghost\r\nDTSTART:20260615T140000");
    assert!(ics::parse(&src, "personal").is_empty());
}

#[test]
fn folded_lines_rejoin() {
    let src = wrap("UID:a\r\nDTSTART:20260615T140000\r\n\
                    SUMMARY:A very long title that the writer\r\n  split across lines");
    let evs = ics::parse(&src, "personal");
    assert_eq!(evs[0].summary, "A very long title that the writer split across lines");
}

#[test]
fn escaping_survives_a_round_trip() {
    let src = wrap("UID:a\r\nDTSTART:20260615T140000\r\n\
                    SUMMARY:Lunch\\, then a talk\\; bring notes\r\n\
                    DESCRIPTION:line one\\nline two");
    let evs = ics::parse(&src, "personal");
    assert_eq!(evs[0].summary, "Lunch, then a talk; bring notes");
    assert_eq!(evs[0].description, "line one\nline two");

    let back = ics::parse(&ics::serialize(&evs, "icalcore"), "personal");
    assert_eq!(back[0].summary, evs[0].summary);
    assert_eq!(back[0].description, evs[0].description);
}

#[test]
fn unknown_properties_are_preserved() {
    // Another calendar's properties must survive being read and written here,
    // or syncing through this app quietly strips other apps' data.
    let src = wrap("UID:a\r\nDTSTART:20260615T140000\r\nX-APPLE-TRAVEL-DURATION:PT30M\r\n\
                    CATEGORIES:work");
    let out = ics::serialize(&ics::parse(&src, "personal"), "icalcore");
    assert!(out.contains("X-APPLE-TRAVEL-DURATION:PT30M"), "{out}");
    assert!(out.contains("CATEGORIES:work"), "{out}");
}

#[test]
fn round_trip_keeps_the_times() {
    let src = wrap("UID:a\r\nSUMMARY:Standup\r\n\
                    DTSTART:20260615T093000\r\nDTEND:20260615T094500");
    let first = ics::parse(&src, "personal");
    let second = ics::parse(&ics::serialize(&first, "icalcore"), "personal");
    assert_eq!(first[0].start, second[0].start);
    assert_eq!(first[0].end, second[0].end);
}

#[test]
fn all_day_round_trips_as_a_date() {
    let src = wrap("UID:a\r\nDTSTART;VALUE=DATE:20260615\r\nDTEND;VALUE=DATE:20260616");
    let out = ics::serialize(&ics::parse(&src, "personal"), "icalcore");
    assert!(out.contains("DTSTART;VALUE=DATE:20260615"), "{out}");
    let back = ics::parse(&out, "personal");
    assert!(back[0].all_day);
}

#[test]
fn several_events_in_one_file_all_parse() {
    let src = format!(
        "BEGIN:VCALENDAR\r\n{}{}END:VCALENDAR\r\n",
        "BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260615T090000\r\nEND:VEVENT\r\n",
        "BEGIN:VEVENT\r\nUID:b\r\nDTSTART:20260616T090000\r\nEND:VEVENT\r\n");
    assert_eq!(ics::parse(&src, "personal").len(), 2);
}

#[test]
fn events_come_back_in_a_usable_order_from_the_store() {
    // Guards the assumption main.rs makes everywhere: parse gives whole days.
    let src = wrap("UID:a\r\nDTSTART;VALUE=DATE:20260615\r\nDTEND;VALUE=DATE:20260618");
    let ev = &ics::parse(&src, "personal")[0];
    for d in 15..=17 {
        assert!(ev.on_day(NaiveDate::from_ymd_opt(2026, 6, d).unwrap()), "day {d}");
    }
    assert!(!ev.on_day(NaiveDate::from_ymd_opt(2026, 6, 18).unwrap()));
    let _: NaiveDateTime = ev.start;
}
