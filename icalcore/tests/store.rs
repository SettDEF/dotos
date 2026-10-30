//! The vdir and its bounds index. The index exists to avoid opening files
//! that cannot match a range — so the tests that matter are the ones proving
//! it never skips a file that *can*.

use chrono::NaiveDate;
use icalcore::{ics, store::Store};
use std::fs;
use std::path::PathBuf;

/// A throwaway store. No tempfile dependency for this — a unique directory
/// under the system temp dir is all the isolation these tests need.
fn scratch(tag: &str) -> PathBuf {
    let n = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let dir = std::env::temp_dir().join(format!("icalcore-{tag}-{}-{n}", std::process::id()));
    fs::create_dir_all(dir.join("calendars")).unwrap();
    dir
}

fn event(uid: &str, start: &str) -> ics::Event {
    let src = format!("BEGIN:VEVENT\r\nUID:{uid}\r\nSUMMARY:{uid}\r\n\
                       DTSTART:{start}\r\nEND:VEVENT\r\n");
    ics::parse(&src, "personal").remove(0)
}
fn d(y: i32, m: u32, day: u32) -> NaiveDate { NaiveDate::from_ymd_opt(y, m, day).unwrap() }

#[test]
fn a_saved_event_reads_back() {
    let base = scratch("save");
    let s = Store::at(base.join("calendars"));
    s.save(&event("one", "20260615T090000")).unwrap();

    let got = s.load();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].uid, "one");
    assert_eq!(got[0].calendar, "personal");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn one_file_per_event() {
    let base = scratch("vdir");
    let s = Store::at(base.join("calendars"));
    s.save(&event("one", "20260615T090000")).unwrap();
    s.save(&event("two", "20260616T090000")).unwrap();

    let files: Vec<_> = fs::read_dir(base.join("calendars/personal")).unwrap()
        .flatten().map(|e| e.file_name().to_string_lossy().to_string()).collect();
    assert_eq!(files.len(), 2, "{files:?}");
    assert!(files.iter().all(|f| f.ends_with(".ics")), "{files:?}");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn delete_removes_the_file() {
    let base = scratch("delete");
    let s = Store::at(base.join("calendars"));
    let ev = event("one", "20260615T090000");
    s.save(&ev).unwrap();
    s.delete(&ev).unwrap();
    assert!(s.load().is_empty());
    fs::remove_dir_all(&base).ok();
}

#[test]
fn a_range_query_returns_what_is_in_it_and_nothing_else() {
    let base = scratch("range");
    let s = Store::at(base.join("calendars"));
    s.save(&event("june", "20260615T090000")).unwrap();
    s.save(&event("december", "20261215T090000")).unwrap();

    let june = s.load_range(Some((d(2026, 6, 1), d(2026, 6, 30))));
    assert_eq!(june.len(), 1, "{:?}", june.iter().map(|e| &e.uid).collect::<Vec<_>>());
    assert_eq!(june[0].uid, "june");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn the_index_survives_a_second_pass_without_losing_events() {
    // The first pass builds the index; the second trusts it. A bug here shows
    // up as events vanishing on the second run, which is the worst kind.
    let base = scratch("index");
    let s = Store::at(base.join("calendars"));
    s.save(&event("june", "20260615T090000")).unwrap();

    let range = Some((d(2026, 6, 1), d(2026, 6, 30)));
    assert_eq!(s.load_range(range).len(), 1);
    assert!(base.join(".index.json").exists(), "index was not written");
    assert_eq!(s.load_range(range).len(), 1, "second pass lost it");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn editing_a_file_behind_the_index_is_noticed() {
    let base = scratch("stale");
    let s = Store::at(base.join("calendars"));
    s.save(&event("one", "20260615T090000")).unwrap();
    s.load_range(Some((d(2026, 6, 1), d(2026, 6, 30))));  // build the index

    // Same uid, a different month — as an external editor or a sync would.
    let moved = event("one", "20260915T090000");
    s.save(&moved).unwrap();

    let sept = s.load_range(Some((d(2026, 9, 1), d(2026, 9, 30))));
    assert_eq!(sept.len(), 1, "the index kept a stale span");
    let june = s.load_range(Some((d(2026, 6, 1), d(2026, 6, 30))));
    assert!(june.is_empty(), "the old span was still being trusted");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn a_recurring_file_is_never_skipped_by_the_index() {
    // A weekly event's own VEVENT sits in June; its occurrences reach December.
    // Skipping the file on its stored span would silently drop the whole series.
    let base = scratch("recurring");
    let s = Store::at(base.join("calendars"));
    let src = "BEGIN:VEVENT\r\nUID:weekly\r\nDTSTART:20260601T090000\r\n\
               RRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\n";
    s.save(&ics::parse(src, "personal").remove(0)).unwrap();
    s.load_range(Some((d(2026, 6, 1), d(2026, 6, 30))));  // build the index

    let december = s.load_range(Some((d(2026, 12, 1), d(2026, 12, 31))));
    assert_eq!(december.len(), 1, "the recurring file was skipped");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn a_multi_event_ics_file_is_read() {
    // Hand-made files and downloaded invitations hold many events in one file.
    let base = scratch("multi");
    fs::write(base.join("calendars/shared.ics"),
        "BEGIN:VCALENDAR\r\n\
         BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260615T090000\r\nEND:VEVENT\r\n\
         BEGIN:VEVENT\r\nUID:b\r\nDTSTART:20260616T090000\r\nEND:VEVENT\r\n\
         END:VCALENDAR\r\n").unwrap();
    let s = Store::at(base.join("calendars"));
    assert_eq!(s.load().len(), 2);
    assert_eq!(s.calendars().len(), 1);
    assert_eq!(s.calendars()[0].name, "shared");
    fs::remove_dir_all(&base).ok();
}

#[test]
fn find_by_prefix_refuses_an_ambiguous_one() {
    let base = scratch("prefix");
    let s = Store::at(base.join("calendars"));
    let evs = vec![event("abcd1", "20260615T090000"), event("abcd2", "20260616T090000")];
    assert!(s.find_by_prefix(&evs, "abcd").is_err());
    assert_eq!(s.find_by_prefix(&evs, "abcd1").unwrap().uid, "abcd1");
    assert!(s.find_by_prefix(&evs, "zzz").is_err());
    fs::remove_dir_all(&base).ok();
}

#[test]
fn an_empty_store_is_not_an_error() {
    let base = scratch("empty");
    let s = Store::at(base.join("calendars"));
    assert!(s.load().is_empty());
    assert!(s.calendars().is_empty());
    fs::remove_dir_all(&base).ok();
}
