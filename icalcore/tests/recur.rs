//! RRULE expansion. The failures worth guarding are the quiet ones: a series
//! that drifts to the wrong day and then stays there, or one that never ends.

use chrono::NaiveDate;
use icalcore::{ics, recur};

fn ev(start: &str, rrule: &str) -> ics::Event {
    let src = format!(
        "BEGIN:VEVENT\r\nUID:a\r\nDTSTART:{start}\r\nRRULE:{rrule}\r\nEND:VEVENT\r\n");
    ics::parse(&src, "personal").remove(0)
}
fn d(y: i32, m: u32, day: u32) -> NaiveDate { NaiveDate::from_ymd_opt(y, m, day).unwrap() }
fn days(e: &ics::Event, from: NaiveDate, to: NaiveDate) -> Vec<NaiveDate> {
    recur::expand(e, from, to).iter().map(|o| o.start.date()).collect()
}

#[test]
fn daily_with_interval() {
    let e = ev("20260601T090000", "FREQ=DAILY;INTERVAL=3");
    assert_eq!(days(&e, d(2026, 6, 1), d(2026, 6, 10)),
               vec![d(2026,6,1), d(2026,6,4), d(2026,6,7), d(2026,6,10)]);
}

#[test]
fn weekly_byday_hits_both_days() {
    let e = ev("20260601T090000", "FREQ=WEEKLY;BYDAY=MO,WE");
    assert_eq!(days(&e, d(2026, 6, 1), d(2026, 6, 10)),
               vec![d(2026,6,1), d(2026,6,3), d(2026,6,8), d(2026,6,10)]);
}

#[test]
fn monthly_on_the_31st_does_not_collapse_to_the_28th() {
    // Stepping from the previous occurrence clamps 31 Jan to 28 Feb and then
    // never recovers — the series silently becomes "the 28th, forever".
    // Stepping from the anchor is what keeps March on the 31st.
    let e = ev("20260131T090000", "FREQ=MONTHLY");
    let got = days(&e, d(2026, 1, 1), d(2026, 5, 31));
    assert!(got.contains(&d(2026, 3, 31)), "{got:?}");
    assert!(got.contains(&d(2026, 5, 31)), "{got:?}");
}

#[test]
fn monthly_by_ordinal_weekday() {
    // "the third Tuesday of the month"
    let e = ev("20260120T090000", "FREQ=MONTHLY;BYDAY=3TU");
    let got = days(&e, d(2026, 1, 1), d(2026, 3, 31));
    assert_eq!(got, vec![d(2026,1,20), d(2026,2,17), d(2026,3,17)], "{got:?}");
}

#[test]
fn count_stops_the_series() {
    let e = ev("20260601T090000", "FREQ=DAILY;COUNT=3");
    assert_eq!(days(&e, d(2026, 6, 1), d(2026, 6, 30)).len(), 3);
}

#[test]
fn until_stops_the_series() {
    let e = ev("20260601T090000", "FREQ=DAILY;UNTIL=20260604T000000Z");
    let got = days(&e, d(2026, 6, 1), d(2026, 6, 30));
    assert!(got.iter().all(|x| *x <= d(2026, 6, 4)), "{got:?}");
    assert!(got.contains(&d(2026, 6, 3)), "{got:?}");
}

#[test]
fn yearly_repeats_on_the_date() {
    let e = ev("20260315T090000", "FREQ=YEARLY");
    assert_eq!(days(&e, d(2026, 1, 1), d(2029, 12, 31)),
               vec![d(2026,3,15), d(2027,3,15), d(2028,3,15), d(2029,3,15)]);
}

#[test]
fn exdate_removes_one_occurrence() {
    let src = "BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260601T090000\r\n\
               RRULE:FREQ=DAILY\r\nEXDATE:20260603T090000\r\nEND:VEVENT\r\n";
    let e = ics::parse(src, "personal").remove(0);
    let got = days(&e, d(2026, 6, 1), d(2026, 6, 5));
    assert!(!got.contains(&d(2026, 6, 3)), "{got:?}");
    assert_eq!(got.len(), 4, "{got:?}");
}

#[test]
fn an_endless_rule_over_a_huge_range_still_returns() {
    // No COUNT, no UNTIL, ten years asked for: must terminate, not hang.
    let e = ev("20200101T090000", "FREQ=DAILY");
    let got = days(&e, d(2020, 1, 1), d(2030, 1, 1));
    assert!(!got.is_empty());
    assert!(got.len() <= 2000, "capped, got {}", got.len());
}

#[test]
fn occurrences_keep_the_original_duration_and_time() {
    let src = "BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260601T093000\r\nDTEND:20260601T101500\r\n\
               RRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\n";
    let e = ics::parse(src, "personal").remove(0);
    for occ in recur::expand(&e, d(2026, 6, 1), d(2026, 6, 30)) {
        assert_eq!(occ.duration_minutes(), 45);
        assert_eq!(occ.start.time(), e.start.time());
    }
}

#[test]
fn a_rule_we_cannot_parse_keeps_the_event_rather_than_dropping_it() {
    // Losing an event to an unsupported rule is worse than showing it once.
    let e = ev("20260601T090000", "FREQ=HOURLY");
    assert_eq!(recur::expand(&e, d(2026, 6, 1), d(2026, 6, 2)).len(), 1);
}

#[test]
fn a_plain_event_outside_the_range_is_not_returned() {
    let src = "BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260601T090000\r\nEND:VEVENT\r\n";
    let e = ics::parse(src, "personal").remove(0);
    assert!(recur::expand(&e, d(2026, 7, 1), d(2026, 7, 31)).is_empty());
    assert_eq!(recur::expand(&e, d(2026, 6, 1), d(2026, 6, 30)).len(), 1);
}
