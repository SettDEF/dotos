//! Which projects Dotos takes on, and how (CLI.md §6).
//!
//! Found is not taken on: a folder under a root is *discovered*; it is *tracked* (its tasks, its
//! page, its git state) by the mode or by `dotos project track`; `ignored` patterns are never
//! looked at. Each project has options (git, github, todos, sync, share, agents, notify, pin, …),
//! any key at all, so extensions can keep their own. Where an option comes from, lowest first:
//! the built-in default, the repo's `.dotos.toml` (the team's defaults for it), this machine's
//! `projects.json` (yours: it wins, so `git=off` stays off whatever the repo says).
//!
//! projects.json: { "mode": "all|ask|manual", "tracked": [names], "ignored": [globs],
//!                  "settings": { name: { key: value } } }

use crate::paths;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// The options every project has, their default and the values they take ("" = any).
pub const KEYS: &[(&str, &str, &str)] = &[
    ("git", "on", "on off"),
    ("github", "on", "on off"),
    ("todos", "on", "on off"),
    ("sync", "off", "on off"),
    ("share", "off", ""),
    ("agents", "ask", "allow ask deny"),
    ("notify", "all", "all mentions none"),
    ("pin", "off", "on off"),
    ("color", "", ""),
    ("alias", "", ""),
];

pub const MODES: &[&str] = &["all", "ask", "manual"];

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Conf {
    /// all: every discovered project is tracked (Dotos before this) · ask: new ones wait for
    /// `track` · manual: only what was tracked
    #[serde(default = "default_mode")]
    pub mode: String,
    #[serde(default)]
    pub tracked: Vec<String>,
    /// names or paths, `*` matches anything (`*-wt-*`, `node_modules`, `~/old/*`)
    #[serde(default)]
    pub ignored: Vec<String>,
    #[serde(default)]
    pub settings: BTreeMap<String, BTreeMap<String, String>>,
}

fn default_mode() -> String {
    "all".into()
}

pub fn file() -> PathBuf {
    paths::config_dir().join("projects.json")
}

pub fn load() -> Conf {
    let mut c: Conf = std::fs::read_to_string(file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    if !MODES.contains(&c.mode.as_str()) {
        c.mode = default_mode();
    }
    c
}

pub fn save(c: &Conf) -> std::io::Result<()> {
    std::fs::create_dir_all(paths::config_dir())?;
    std::fs::write(file(), serde_json::to_string_pretty(c).unwrap_or_default())
}

/// `*` matches any run of characters; no other specials.
pub fn glob(pat: &str, s: &str) -> bool {
    let parts: Vec<&str> = pat.split('*').collect();
    if parts.len() == 1 {
        return pat == s;
    }
    let mut rest = s;
    for (i, p) in parts.iter().enumerate() {
        if i == 0 {
            match rest.strip_prefix(p) { Some(r) => rest = r, None => return false }
        } else if i == parts.len() - 1 {
            return rest.ends_with(p);
        } else {
            match rest.find(p) { Some(at) => rest = &rest[at + p.len()..], None => return false }
        }
    }
    true
}

fn name_of(dir: &Path) -> String {
    dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()
}

impl Conf {
    pub fn is_ignored(&self, dir: &Path) -> bool {
        let (name, path) = (name_of(dir), dir.to_string_lossy().to_string());
        self.ignored.iter().any(|p| { let p = paths::expand(p).to_string_lossy().to_string(); glob(&p, &name) || glob(&p, &path) })
    }

    pub fn is_tracked(&self, dir: &Path) -> bool {
        if self.is_ignored(dir) {
            return false;
        }
        let name = name_of(dir);
        self.mode == "all" || self.tracked.iter().any(|t| t.eq_ignore_ascii_case(&name))
    }

    /// An option's value and where it came from: "default", ".dotos.toml" or "projects.json".
    pub fn get(&self, dir: &Path, key: &str) -> (String, &'static str) {
        let name = name_of(dir);
        if let Some(v) = self.settings.get(&name).and_then(|m| m.get(key)) {
            return (v.clone(), "projects.json");
        }
        if let Some(v) = repo_file(dir).remove(key) {
            return (v, ".dotos.toml");
        }
        (KEYS.iter().find(|k| k.0 == key).map(|k| k.1).unwrap_or("").to_string(), "default")
    }

    pub fn on(&self, dir: &Path, key: &str) -> bool {
        matches!(self.get(dir, key).0.as_str(), "on" | "true" | "yes" | "allow" | "all")
    }
}

/// The repo's `.dotos.toml`: flat `key = value` lines (strings quoted or not), `#` comments,
/// `[section]` lines skipped. Enough for a project's options without a TOML parser.
pub fn repo_file(dir: &Path) -> BTreeMap<String, String> {
    let mut m = BTreeMap::new();
    let Ok(text) = std::fs::read_to_string(dir.join(".dotos.toml")) else { return m };
    for line in text.lines() {
        let l = line.split(" #").next().unwrap_or("").trim();
        if l.is_empty() || l.starts_with('#') || l.starts_with('[') {
            continue;
        }
        if let Some((k, v)) = l.split_once('=') {
            let v = v.trim().trim_matches('"').trim_matches('\'');
            m.insert(k.trim().to_string(), v.to_string());
        }
    }
    m
}

/// A known key's value checked against what it takes; any other key is free (extensions').
pub fn check(key: &str, value: &str) -> Result<(), String> {
    match KEYS.iter().find(|k| k.0 == key) {
        Some((_, _, choices)) if !choices.is_empty() && !choices.split(' ').any(|c| c == value) => {
            Err(format!("{key} takes {}", choices.replace(' ', ", ")))
        }
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn globs() {
        assert!(glob("*-wt-*", "dotos-wt-cli"));
        assert!(!glob("*-wt-*", "dotos"));
        assert!(glob("node_modules", "node_modules"));
        assert!(glob("old*", "oldstuff") && glob("*.bak", "a.bak") && !glob("*.bak", "a.bak2"));
    }

    #[test]
    fn modes_and_ignores() {
        let mut c = Conf { mode: "manual".into(), tracked: vec!["Loom".into()], ignored: vec!["*-old".into()], ..Default::default() };
        assert!(c.is_tracked(Path::new("/p/loom")));
        assert!(!c.is_tracked(Path::new("/p/zash")));
        c.mode = "all".into();
        assert!(c.is_tracked(Path::new("/p/zash")));
        assert!(!c.is_tracked(Path::new("/p/zash-old")));
    }

    #[test]
    fn checks_known_keys_only() {
        assert!(check("git", "off").is_ok());
        assert!(check("git", "maybe").is_err());
        assert!(check("my-extension-key", "anything").is_ok());
    }
}
