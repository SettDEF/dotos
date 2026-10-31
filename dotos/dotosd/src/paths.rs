//! Where Dotos keeps what is not a task file.
//!
//!   $XDG_CONFIG_HOME/dotos/config.json     settings (the window writes it too)
//!   $XDG_CONFIG_HOME/dotos/extensions/     extensions, one file or folder each
//!   $XDG_DATA_HOME/dotos/pages/            notes and pages (markdown)
//!   $XDG_DATA_HOME/dotos/journal/          one page per day
//!   $XDG_DATA_HOME/dotos/habits.json       habits and the days they were done
//!   $XDG_STATE_HOME/dotos/events.jsonl     the change log (undo, history, audit)
//!
//! DOTOS_HOME moves all of it under one folder, for tests and fixtures, the
//! same switch that moves the task store.

use std::path::PathBuf;

fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var(var)
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(fallback))
}

fn base(kind: &str, var: &str, fallback: &str) -> PathBuf {
    match std::env::var("DOTOS_HOME") {
        Ok(h) => PathBuf::from(h).join(kind),
        Err(_) => xdg(var, fallback).join("dotos"),
    }
}

pub fn config_dir() -> PathBuf { base("config", "XDG_CONFIG_HOME", ".config") }
pub fn data_dir() -> PathBuf { base("data", "XDG_DATA_HOME", ".local/share") }
pub fn state_dir() -> PathBuf { base("state", "XDG_STATE_HOME", ".local/state") }

pub fn config_file() -> PathBuf { config_dir().join("config.json") }
pub fn extensions_dir() -> PathBuf { config_dir().join("extensions") }
pub fn pages_dir() -> PathBuf { data_dir().join("pages") }
pub fn journal_dir() -> PathBuf { data_dir().join("journal") }
pub fn habits_file() -> PathBuf { data_dir().join("habits.json") }
pub fn events_file() -> PathBuf { state_dir().join("events.jsonl") }

/// The settings, read fresh each run: small, and the window may have just written them.
pub fn config() -> serde_json::Value {
    std::fs::read_to_string(config_file())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(serde_json::Value::Null)
}

/// Folders whose subfolders are projects. Default: $PROJECTS_DIR, then the usual places for
/// source trees, those that exist (only /mnt/storage/dev/projects was looked at, which is one
/// machine's data disk: elsewhere Projects and GitHub were empty).
pub fn project_roots() -> Vec<PathBuf> {
    let cfg = config();
    if let Some(a) = cfg["projectRoots"].as_array() {
        let v: Vec<PathBuf> = a.iter().filter_map(|x| x.as_str()).map(expand).collect();
        if !v.is_empty() {
            return v;
        }
    }
    let mut v: Vec<PathBuf> = std::env::var("PROJECTS_DIR").ok().filter(|s| !s.is_empty()).map(|s| expand(&s)).into_iter().collect();
    v.extend(["/mnt/storage/dev/projects", "~/.local/src", "~/projects", "~/src", "~/code", "~/dev"].iter().map(|p| expand(p)));
    let mut seen = std::collections::HashSet::new();
    v.retain(|p| p.is_dir() && seen.insert(std::fs::canonicalize(p).unwrap_or_else(|_| p.clone())));
    if v.is_empty() { vec![PathBuf::from("/mnt/storage/dev/projects")] } else { v }
}

/// Single folders that are projects themselves (not roots of projects).
pub fn project_extra() -> Vec<PathBuf> {
    let cfg = config();
    match cfg["projects"].as_array() {
        Some(a) => a.iter().filter_map(|x| x.as_str()).map(expand).collect(),
        None => vec![xdg("XDG_CONFIG_HOME", ".config").join("quickshell")],
    }
}

pub fn expand(p: &str) -> PathBuf {
    match p.strip_prefix("~/") {
        Some(rest) => PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(rest),
        None => PathBuf::from(p),
    }
}

pub fn write_atomic(path: &std::path::Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(d) = path.parent() {
        std::fs::create_dir_all(d)?;
    }
    let tmp = path.with_extension("tmp~");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(tmp, path)
}
