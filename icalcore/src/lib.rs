//! iCalendar, once.
//!
//! Kalends and Dotos store the same thing — an iCalendar component in a vdir —
//! and differ only in which component and which directory. A second parser
//! would get its own bugs: this one has already shipped a silent one (TZID
//! dropped, every imported event hours wrong with no error). One copy, tested.

pub mod cli;
pub mod ics;
pub mod index;
pub mod recur;
pub mod store;
pub mod todo;

/// Warnings name whichever binary is running, not the library. Two callers
/// share this code; "kalends:" on a Dotos warning would send someone looking
/// in the wrong place.
pub fn warn(msg: &str) {
    let prog = std::env::args().next()
        .and_then(|a| std::path::Path::new(&a).file_name().map(|f| f.to_string_lossy().to_string()))
        .unwrap_or_else(|| "icalcore".to_string());
    eprintln!("{prog}: {msg}");
}
