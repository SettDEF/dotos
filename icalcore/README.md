# icalcore

iCalendar parsing, vdir storage and RRULE expansion. Kalends (events) and
Dotos (tasks) both link it.

It exists because they store the same thing — an iCalendar component in a
vdir — and differ only in which component and which directory. A second parser
would get its own bugs: this one has already shipped a silent one (TZID in the
property parameters was dropped, so every imported event was hours wrong with
no error anywhere). One copy, with tests.

    ics.rs      parse and serialise; line folding, escaping, DATE vs DATE-TIME,
                TZID, and verbatim preservation of properties it does not model
    store.rs    the vdir: one file per component, atomic writes, the bounds index
    recur.rs    RRULE expansion — FREQ, INTERVAL, COUNT, UNTIL, BYDAY, EXDATE
    index.rs    cached date spans, so a range query opens only the files that
                could match

## Who it belongs to

The library knows the layout, not the location. Each app names its own:

```rust
const KALENDS: Layout = Layout {
    env_var: "KALENDS_HOME",
    app_dir: "kalends",
    sub_dir: "calendars",
};
let store = Store::open(KALENDS);
```

`app_dir` also becomes the PRODID of everything that store writes, and
warnings are printed under the running program's name — so a Dotos warning
never says "kalends".

## Tests

`cargo test -p icalcore`. Every test is a bug that would otherwise be silent:
an event at the wrong time, a series that drifts to the wrong day, a file the
index skipped.
