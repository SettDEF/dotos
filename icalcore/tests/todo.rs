//! VTODO. The tests worth having are the ones where a task would quietly
//! read as the wrong thing: done shown as open, a due date off by a zone,
//! another app's fields stripped on the way through.

use chrono::NaiveDate;
use icalcore::store::Store;
use icalcore::todo::{self, Importance, Status, Todo};
use std::fs;
use std::path::PathBuf;

fn wrap(body: &str) -> String {
    format!("BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\n{body}\r\nEND:VTODO\r\nEND:VCALENDAR\r\n")
}
fn d(y: i32, m: u32, day: u32) -> NaiveDate { NaiveDate::from_ymd_opt(y, m, day).unwrap() }

fn scratch(tag: &str) -> PathBuf {
    let n = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let dir = std::env::temp_dir().join(format!("icalcore-todo-{tag}-{}-{n}", std::process::id()));
    fs::create_dir_all(dir.join("lists")).unwrap();
    dir
}

#[test]
fn the_basics_parse() {
    let src = wrap("UID:t1\r\nSUMMARY:Pay the rent\r\nDUE;VALUE=DATE:20260701\r\n\
                    PRIORITY:1\r\nSTATUS:NEEDS-ACTION");
    let t = &todo::parse(&src, "home")[0];
    assert_eq!(t.summary, "Pay the rent");
    assert_eq!(t.list, "home");
    assert_eq!(t.due_date(), Some(d(2026, 7, 1)));
    assert!(t.due_all_day);
    assert_eq!(t.importance(), Importance::High);
    assert!(t.is_open());
}

#[test]
fn a_task_with_no_due_date_is_valid() {
    let t = &todo::parse(&wrap("UID:t1\r\nSUMMARY:Someday"), "home")[0];
    assert_eq!(t.due, None);
    assert!(t.is_open());
    assert!(!t.is_overdue(d(2026, 7, 1)));
}

#[test]
fn completed_without_a_percentage_still_reads_as_done() {
    // Plenty of clients write STATUS but not PERCENT-COMPLETE. Trusting only
    // the number would show a finished task as open.
    let t = &todo::parse(&wrap("UID:t1\r\nSUMMARY:Done\r\nSTATUS:COMPLETED"), "home")[0];
    assert!(!t.is_open());
    assert_eq!(t.percent, 100);
}

#[test]
fn cancelled_is_closed_not_open() {
    let t = &todo::parse(&wrap("UID:t1\r\nSUMMARY:Dropped\r\nSTATUS:CANCELLED"), "home")[0];
    assert!(!t.is_open());
}

#[test]
fn due_honours_tzid() {
    let src = wrap("UID:t1\r\nSUMMARY:Call\r\nDUE;TZID=America/New_York:20260615T140000");
    let t = &todo::parse(&src, "home")[0];
    let ny = "America/New_York".parse::<chrono_tz::Tz>().unwrap();
    let expected = chrono::TimeZone::from_local_datetime(
        &ny, &d(2026, 6, 15).and_hms_opt(14, 0, 0).unwrap(),
    ).earliest().unwrap().with_timezone(&chrono::Local).naive_local();
    assert_eq!(t.due, Some(expected));
}

#[test]
fn overdue_means_before_today_not_today() {
    let t = &todo::parse(&wrap("UID:t1\r\nSUMMARY:x\r\nDUE;VALUE=DATE:20260701"), "home")[0];
    assert!(!t.is_overdue(d(2026, 7, 1)));
    assert!(t.is_overdue(d(2026, 7, 2)));
}

#[test]
fn a_completed_task_is_never_overdue() {
    let src = wrap("UID:t1\r\nSUMMARY:x\r\nDUE;VALUE=DATE:20260101\r\nSTATUS:COMPLETED");
    let t = &todo::parse(&src, "home")[0];
    assert!(!t.is_overdue(d(2026, 7, 1)));
}

#[test]
fn priority_numbers_map_to_words_the_right_way_round() {
    // RFC 5545 has 1 as the HIGHEST, which is the trap.
    assert_eq!(Importance::from_number(1), Importance::High);
    assert_eq!(Importance::from_number(5), Importance::Normal);
    assert_eq!(Importance::from_number(9), Importance::Low);
    assert_eq!(Importance::from_number(0), Importance::Unset);
    assert_eq!(Importance::High.to_number(), 1);
    assert_eq!(Importance::parse("high"), Some(Importance::High));
    assert_eq!(Importance::parse("nonsense"), None);
}

#[test]
fn completing_sets_everything_a_reader_might_check() {
    let mut t = Todo::new("x", "home", "t1");
    t.complete(icalcore::ics::now_local());
    assert_eq!(t.status, Status::Completed);
    assert_eq!(t.percent, 100);
    assert!(t.completed.is_some());
    t.reopen();
    assert!(t.is_open());
    assert_eq!(t.percent, 0);
    assert!(t.completed.is_none());
}

#[test]
fn a_round_trip_keeps_every_field() {
    let src = wrap("UID:t1\r\nSUMMARY:Pay the rent\r\nDESCRIPTION:line one\\nline two\r\n\
                    DUE;VALUE=DATE:20260701\r\nPRIORITY:3\r\nPERCENT-COMPLETE:40\r\n\
                    STATUS:IN-PROCESS\r\nCATEGORIES:home,money\r\nRRULE:FREQ=MONTHLY");
    let first = todo::parse(&src, "home");
    let second = todo::parse(&todo::serialize(&first, "dotos"), "home");
    let (a, b) = (&first[0], &second[0]);
    assert_eq!(a.summary, b.summary);
    assert_eq!(a.description, b.description);
    assert_eq!(a.due, b.due);
    assert_eq!(a.due_all_day, b.due_all_day);
    assert_eq!(a.priority, b.priority);
    assert_eq!(a.percent, b.percent);
    assert_eq!(a.status, b.status);
    assert_eq!(a.categories, b.categories);
    assert_eq!(a.rrule, b.rrule);
}

#[test]
fn another_apps_fields_survive() {
    let src = wrap("UID:t1\r\nSUMMARY:x\r\nX-APPLE-SORT-ORDER:12\r\nRELATED-TO:parent-uid");
    let out = todo::serialize(&todo::parse(&src, "home"), "dotos");
    assert!(out.contains("X-APPLE-SORT-ORDER:12"), "{out}");
    assert!(out.contains("RELATED-TO:parent-uid"), "{out}");
}

#[test]
fn a_vtodo_without_uid_is_dropped() {
    assert!(todo::parse(&wrap("SUMMARY:Ghost"), "home").is_empty());
}

#[test]
fn events_and_tasks_in_one_file_do_not_bleed_into_each_other() {
    // vdir collections can hold both. Each parser must see only its own.
    let src = "BEGIN:VCALENDAR\r\n\
               BEGIN:VEVENT\r\nUID:e1\r\nSUMMARY:Meeting\r\nDTSTART:20260615T090000\r\nEND:VEVENT\r\n\
               BEGIN:VTODO\r\nUID:t1\r\nSUMMARY:Task\r\nEND:VTODO\r\n\
               END:VCALENDAR\r\n";
    let evs = icalcore::ics::parse(src, "home");
    let todos = todo::parse(src, "home");
    assert_eq!(evs.len(), 1);
    assert_eq!(evs[0].uid, "e1");
    assert_eq!(todos.len(), 1);
    assert_eq!(todos[0].uid, "t1");
}

#[test]
fn the_list_order_is_due_first_then_priority_then_stable() {
    let src = "BEGIN:VCALENDAR\r\n\
        BEGIN:VTODO\r\nUID:c\r\nSUMMARY:no date\r\nEND:VTODO\r\n\
        BEGIN:VTODO\r\nUID:a\r\nSUMMARY:soon\r\nDUE;VALUE=DATE:20260601\r\nEND:VTODO\r\n\
        BEGIN:VTODO\r\nUID:b\r\nSUMMARY:later\r\nDUE;VALUE=DATE:20260901\r\nEND:VTODO\r\n\
        BEGIN:VTODO\r\nUID:d\r\nSUMMARY:soon but urgent\r\nDUE;VALUE=DATE:20260601\r\n\
        PRIORITY:1\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
    let mut ts = todo::parse(src, "home");
    ts.sort_by_key(|t| t.sort_key());
    let order: Vec<&str> = ts.iter().map(|t| t.uid.as_str()).collect();
    assert_eq!(order, vec!["d", "a", "b", "c"], "{order:?}");
}

#[test]
fn a_task_saved_to_the_store_reads_back() {
    let base = scratch("save");
    let s = Store::at(base.join("lists"));
    let mut t = Todo::new("Pay the rent", "home", "t1");
    t.due = Some(d(2026, 7, 1).and_hms_opt(0, 0, 0).unwrap());
    t.due_all_day = true;
    t.set_importance(Importance::High);
    s.save_todo(&t).unwrap();

    let got = s.load_todos();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].summary, "Pay the rent");
    assert_eq!(got[0].list, "home");
    assert_eq!(got[0].importance(), Importance::High);
    assert_eq!(got[0].due_date(), Some(d(2026, 7, 1)));

    s.delete_todo(&got[0]).unwrap();
    assert!(s.load_todos().is_empty());
    fs::remove_dir_all(&base).ok();
}

#[test]
fn a_task_edited_by_hand_is_picked_up() {
    // The point of plain files: another editor, or a sync, changes them.
    let base = scratch("external");
    let s = Store::at(base.join("lists"));
    let path = s.save_todo(&Todo::new("Before", "home", "t1")).unwrap();
    let text = fs::read_to_string(&path).unwrap().replace("Before", "After");
    fs::write(&path, text).unwrap();
    assert_eq!(s.load_todos()[0].summary, "After");
    fs::remove_dir_all(&base).ok();
}
