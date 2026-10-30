//! The calendar store: a vdir per calendar.
//!
//! vdir means a directory per calendar holding one .ics per event — the
//! layout vdirsyncer and khal use. A single .ics holding many events is also
//! read, so hand-made files and downloaded invitations work, but writes
//! always go to vdir: per-event files make a concurrent sync collide on one
//! event instead of the whole calendar.

use crate::ics::{self, Event};
use crate::todo::{self, Todo};
use std::fs;
use std::io;
use chrono::NaiveDate;
use std::path::{Path, PathBuf};

pub struct Store {
    pub root: PathBuf,
    /// Goes into PRODID on every file this store writes.
    pub prodid: String,
}

/// Where a store lives. The library knows the vdir layout; it does not know
/// whose vdir it is, so the caller names the location. Kalends and Dotos keep
/// separate roots because a calendar and a task list are different things to
/// the user even when they are the same thing to the format.
#[derive(Debug, Clone, Copy)]
pub struct Layout {
    /// Overrides everything else — for tests, and for a second store.
    pub env_var: &'static str,
    /// Directory under XDG_DATA_HOME (or ~/.local/share).
    pub app_dir: &'static str,
    /// The collections directory inside it.
    pub sub_dir: &'static str,
}

#[derive(Debug, Clone)]
pub struct Calendar {
    pub name: String,
    pub path: PathBuf,
}

impl Store {
    pub fn open(layout: Layout) -> Store {
        let app = layout.app_dir;
        let base = std::env::var(layout.env_var).ok().map(PathBuf::from)
            .or_else(|| std::env::var("XDG_DATA_HOME").ok().map(|d| PathBuf::from(d).join(app)))
            .or_else(|| std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".local/share").join(app)))
            .unwrap_or_else(|| PathBuf::from(".").join(app));
        Store { root: base.join(layout.sub_dir), prodid: layout.app_dir.to_string() }
    }

    /// A store at an exact path, for tests and for anything that already
    /// knows where it wants to look.
    pub fn at(root: PathBuf) -> Store {
        Store { root, prodid: "icalcore".to_string() }
    }

    pub fn calendars(&self) -> Vec<Calendar> {
        let mut out = Vec::new();
        let Ok(entries) = fs::read_dir(&self.root) else { return out };
        for e in entries.flatten() {
            let path = e.path();
            let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
            if name.is_empty() { continue; }
            if path.is_dir() || path.extension().map(|x| x == "ics").unwrap_or(false) {
                out.push(Calendar { name, path });
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        out
    }

    /// Creates the default calendar the first time it is needed, so a fresh
    /// install can take an event without a setup step.
    pub fn ensure_calendar(&self, name: &str) -> io::Result<PathBuf> {
        let dir = self.root.join(name);
        fs::create_dir_all(&dir)?;
        Ok(dir)
    }

    /// One file per component, named by uid.
    fn item_path(&self, cal: &str, uid: &str) -> PathBuf {
        // The uid is ours and hex, so it is already a safe file name; guard
        // anyway in case one arrives from an imported file.
        let safe: String = uid.chars()
            .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
            .collect();
        self.root.join(cal).join(format!("{safe}.ics"))
    }

    /// Where the bounds index lives. Beside the collections, not inside one,
    /// so no other vdir tool mistakes it for calendar data.
    pub fn index_path(&self) -> PathBuf {
        self.root.parent().unwrap_or(&self.root).join(".index.json")
    }

    /// Every event in the store. Kept for commands that genuinely need all of
    /// it; anything with a date range should use `load_range`.
    pub fn load(&self) -> Vec<Event> {
        self.load_range(None)
    }

    /// Events that could fall in [from, to]. Files whose cached date span
    /// misses the range are skipped without being opened — that is the whole
    /// point of the index. Recurring files are always read, since a repeat
    /// can land far outside the span its own VEVENTs declare.
    pub fn load_range(&self, range: Option<(NaiveDate, NaiveDate)>) -> Vec<Event> {
        let idx_path = self.index_path();
        let mut idx = crate::index::Index::load(&idx_path);
        let mut events = Vec::new();
        let mut seen: Vec<PathBuf> = Vec::new();

        let consider = |path: &Path, cal: &str,
                            idx: &mut crate::index::Index,
                            out: &mut Vec<Event>| {
            let Some((mtime_ns, len)) = crate::index::stamp(path) else { return };

            if let Some(e) = idx.current(path, mtime_ns, len) {
                if let Some((from, to)) = range {
                    // Bounds can only exclude a file that does not recur.
                    let (f, t) = (crate::index::epoch_day(from), crate::index::epoch_day(to));
                    if !e.recurring && (e.last < f || e.first > t) { return; }
                }
            }

            let Ok(text) = fs::read_to_string(path) else { return };
            let parsed = ics::parse(&text, cal);
            let entry = if parsed.is_empty() {
                // A file with no VEVENT in it — a VTODO, or something this
                // parser does not model. Track it anyway, with a span that can
                // never exclude it: it is still read every time, exactly as
                // before, but now the index changes when it appears or goes,
                // which is what makes the index a usable "store changed"
                // signal for a task store as well as a calendar.
                crate::index::Entry { mtime_ns, len, first: 0, last: 0, recurring: true }
            } else {
                let first = crate::index::epoch_day(parsed.iter().map(|e| e.start.date()).min().unwrap());
                let last = crate::index::epoch_day(parsed.iter().map(|e| e.end.date()).max().unwrap());
                let recurring = parsed.iter().any(|e| !e.rrule.is_empty());
                crate::index::Entry { mtime_ns, len, first, last, recurring }
            };
            idx.put(path, entry);
            // The index decides which files to OPEN; this decides which events
            // to return. Without it a cold index yields the whole store and a
            // warm one yields the range — the same call, two answers.
            // A recurring event is kept regardless: its occurrences land
            // outside its own span, and only the caller's expander knows where.
            out.extend(parsed.into_iter().filter(|e| match range {
                None => true,
                Some((from, to)) => !e.rrule.is_empty() || e.overlaps(from, to),
            }));
        };

        for (path, collection) in self.files() {
            seen.push(path.clone());
            consider(&path, &collection, &mut idx, &mut events);
        }

        idx.retain_seen(&seen);
        idx.save(&idx_path);
        events.sort_by(|a, b| a.start.cmp(&b.start));
        events
    }

    /// Write via a temp file and rename, so a crash or a full disk cannot
    /// leave a half-written event behind.
    /// Re-reads the store so the bounds index matches what is on disk.
    ///
    /// Writes do not maintain the index, and neither does vdirsyncer, which
    /// drops files straight into the vdir. That leaves the index as the one
    /// file that changes only when the store's *contents* have changed — so
    /// anything watching for "the calendar changed" can watch it, instead of
    /// walking every collection on a timer.
    pub fn reindex(&self) {
        let _ = self.load();
    }

    pub fn save(&self, ev: &Event) -> io::Result<PathBuf> {
        self.ensure_calendar(&ev.calendar)?;
        let path = self.item_path(&ev.calendar, &ev.uid);
        let tmp = path.with_extension("ics.tmp");
        fs::write(&tmp, ics::serialize(std::slice::from_ref(ev), &self.prodid))?;
        fs::rename(&tmp, &path)?;
        Ok(path)
    }

    pub fn delete(&self, ev: &Event) -> io::Result<()> {
        let path = self.item_path(&ev.calendar, &ev.uid);
        if path.exists() { return fs::remove_file(path); }
        // Came from a single-file calendar: rewrite it without this event.
        let file = self.root.join(format!("{}.ics", ev.calendar));
        if file.exists() {
            let text = fs::read_to_string(&file)?;
            let kept: Vec<Event> = ics::parse(&text, &ev.calendar)
                .into_iter().filter(|e| e.uid != ev.uid).collect();
            let tmp = file.with_extension("ics.tmp");
            fs::write(&tmp, ics::serialize(&kept, &self.prodid))?;
            fs::rename(&tmp, &file)?;
        }
        Ok(())
    }

    pub fn find_by_prefix<'a>(&self, events: &'a [Event], prefix: &str) -> Result<&'a Event, String> {
        let hits: Vec<&Event> = events.iter().filter(|e| e.uid.starts_with(prefix)).collect();
        match hits.len() {
            0 => Err(format!("no event with id starting '{prefix}'")),
            1 => Ok(hits[0]),
            n => Err(format!("'{prefix}' matches {n} events; use more characters")),
        }
    }

    /// Every .ics file in the store, with the collection it belongs to.
    /// Events and tasks walk the same vdir; only what they parse differs.
    fn files(&self) -> Vec<(PathBuf, String)> {
        let mut out = Vec::new();
        for col in self.calendars() {
            if col.path.is_dir() {
                let Ok(entries) = fs::read_dir(&col.path) else { continue };
                for e in entries.flatten() {
                    let p = e.path();
                    if p.extension().map(|x| x != "ics").unwrap_or(true) { continue; }
                    out.push((p, col.name.clone()));
                }
            } else {
                out.push((col.path.clone(), col.name.clone()));
            }
        }
        out
    }

    /// Every task in the store, in the order a list should be read.
    ///
    /// No bounds index here, deliberately: the index answers "could this file
    /// hold a date in [from, to]", and a task list is nearly always asked for
    /// in full — most tasks have no due date at all, so there is nothing to
    /// index them by and nothing to skip.
    pub fn load_todos(&self) -> Vec<Todo> {
        let mut todos = Vec::new();
        for (path, list) in self.files() {
            let Ok(text) = fs::read_to_string(&path) else { continue };
            todos.extend(todo::parse(&text, &list));
        }
        todos.sort_by_key(|t| t.sort_key());
        todos
    }

    pub fn save_todo(&self, t: &Todo) -> io::Result<PathBuf> {
        self.ensure_calendar(&t.list)?;
        let path = self.item_path(&t.list, &t.uid);
        let tmp = path.with_extension("ics.tmp");
        fs::write(&tmp, todo::serialize(std::slice::from_ref(t), &self.prodid))?;
        fs::rename(&tmp, &path)?;
        Ok(path)
    }

    pub fn delete_todo(&self, t: &Todo) -> io::Result<()> {
        let path = self.item_path(&t.list, &t.uid);
        if path.exists() { return fs::remove_file(path); }
        // Came from a single-file list: rewrite it without this task.
        let file = self.root.join(format!("{}.ics", t.list));
        if file.exists() {
            let text = fs::read_to_string(&file)?;
            let kept: Vec<Todo> = todo::parse(&text, &t.list)
                .into_iter().filter(|x| x.uid != t.uid).collect();
            let tmp = file.with_extension("ics.tmp");
            fs::write(&tmp, todo::serialize(&kept, &self.prodid))?;
            fs::rename(&tmp, &file)?;
        }
        Ok(())
    }

    pub fn find_todo_by_prefix<'a>(&self, todos: &'a [Todo], prefix: &str) -> Result<&'a Todo, String> {
        let hits: Vec<&Todo> = todos.iter().filter(|t| t.uid.starts_with(prefix)).collect();
        match hits.len() {
            0 => Err(format!("no task with id starting '{prefix}'")),
            1 => Ok(hits[0]),
            n => Err(format!("'{prefix}' matches {n} tasks; use more characters")),
        }
    }
}

/// Nanoseconds FIRST. With seconds first, every event created in the same
/// second shared its leading characters, so the short id shown to the user —
/// and therefore `rm <prefix>` — could not tell them apart.
pub fn new_uid(tag: &str) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    format!("{:08x}{:x}-{tag}", now.subsec_nanos(), now.as_secs())
}

pub fn path_display(p: &Path) -> String { p.to_string_lossy().to_string() }
