//! A bounds index for the store.
//!
//! Every command used to open, read and parse every .ics the calendar had
//! ever accumulated — 25k syscalls and ~100ms at 5,000 events, growing
//! forever, for a query that might cover one day. `next`, which a bar widget
//! is meant to poll, paid that too.
//!
//! Caching the parsed events instead was measured and rejected: the cache
//! reached 1.2MB at 5,000 events and deserialising it cost as much as parsing
//! the files it replaced. What this keeps is only each file's date span, which
//! is small enough to stay cheap — so a range query can skip a file outright
//! without reading it.
//!
//! Entries are keyed on (mtime, size); any change re-reads that one file, so
//! an external editor, vdirsyncer or a hand-edit is picked up. The index is
//! never trusted over the filesystem.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Bumped when the on-disk shape changes, so an old index is discarded
/// rather than deserialised into something subtly wrong.
const VERSION: u32 = 3;

#[derive(Serialize, Deserialize, Clone, PartialEq)]
pub struct Entry {
    /// Single-letter fields and epoch-day integers: at 5,000 files the
    /// readable shape made a 748KB index whose deserialisation cost more
    /// than the file reads it saved.
    #[serde(rename = "m")] pub mtime_ns: i128,
    #[serde(rename = "l")] pub len: u64,
    /// Earliest start and latest end across every VEVENT, as days from the
    /// Unix epoch.
    #[serde(rename = "f")] pub first: i32,
    #[serde(rename = "t")] pub last: i32,
    /// A recurring file can land on any date, so its bounds cannot be used
    /// to skip it. Tracked rather than guessed.
    #[serde(rename = "r")] pub recurring: bool,
}

/// Days from the Unix epoch — compact, and ordered the same as the date.
pub fn epoch_day(d: NaiveDate) -> i32 {
    (d - NaiveDate::from_ymd_opt(1970, 1, 1).unwrap()).num_days() as i32
}

#[derive(Serialize, Deserialize)]
pub struct Index {
    version: u32,
    files: HashMap<String, Entry>,
    #[serde(skip)]
    dirty: bool,
}

impl Default for Index {
    fn default() -> Self {
        Index { version: VERSION, files: HashMap::new(), dirty: false }
    }
}

pub fn stamp(path: &Path) -> Option<(i128, u64)> {
    let md = fs::metadata(path).ok()?;
    let mtime = md.modified().ok()?;
    let ns = match mtime.duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => d.as_nanos() as i128,
        Err(e) => -(e.duration().as_nanos() as i128),
    };
    Some((ns, md.len()))
}

impl Index {
    pub fn load(path: &Path) -> Index {
        let Ok(text) = fs::read_to_string(path) else { return Index::default() };
        match serde_json::from_str::<Index>(&text) {
            Ok(idx) if idx.version == VERSION => idx,
            _ => Index::default(),
        }
    }

    /// The cached entry for a file, if it is still current.
    pub fn current(&self, path: &Path, mtime_ns: i128, len: u64) -> Option<&Entry> {
        let e = self.files.get(path.to_string_lossy().as_ref())?;
        (e.mtime_ns == mtime_ns && e.len == len).then_some(e)
    }

    /// Only marks the index dirty when the entry actually changed. Reading
    /// re-derives an entry for every file it opens, so without this check a
    /// plain `kalends list` rewrote the index every time — which is a write
    /// on every command, and makes the file useless to watch for changes.
    pub fn put(&mut self, path: &Path, entry: Entry) {
        let key = path.to_string_lossy().to_string();
        if self.files.get(&key) == Some(&entry) { return; }
        self.files.insert(key, entry);
        self.dirty = true;
    }

    /// Drops entries for files that no longer exist, so a long-lived index
    /// does not grow past the store it describes.
    pub fn retain_seen(&mut self, seen: &[PathBuf]) {
        let keep: std::collections::HashSet<String> =
            seen.iter().map(|p| p.to_string_lossy().to_string()).collect();
        let before = self.files.len();
        self.files.retain(|k, _| keep.contains(k));
        if self.files.len() != before { self.dirty = true; }
    }

    /// Written only when something changed, and via a temp file so a killed
    /// process cannot leave a half-written index that later parses as valid.
    pub fn save(&self, path: &Path) {
        if !self.dirty { return; }
        let Some(dir) = path.parent() else { return };
        if fs::create_dir_all(dir).is_err() { return; }
        let Ok(text) = serde_json::to_string(self) else { return };
        let tmp = path.with_extension("tmp");
        if fs::write(&tmp, text).is_ok() {
            let _ = fs::rename(&tmp, path);
        }
    }
}
