//! Projects: the folders you work in, found rather than declared.
//!
//! A project is a folder under a project root (paths::project_roots) that has a .git,
//! a TASKS.md, a PLAN.md or a README — plus any folder listed in config.json "projects".
//! Found is not taken on (project_conf, CLI.md §6): `discover` gives the tracked ones,
//! `discover_all` everything found that is not ignored. Its tasks are the Dotos tasks
//! tagged +project and the open `- [ ]` lines of its TASKS.md; its health comes from git
//! (where its `git` option is on) and those.

use crate::paths;
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Default)]
pub struct Git {
    pub branch: String,
    pub ahead: u32,
    pub behind: u32,
    pub dirty: u32,
    /// days since the oldest uncommitted change was made (0 if clean)
    pub dirty_days: u32,
    pub last_hash: String,
    pub last_subject: String,
    pub last_time: i64,
    pub commits_week: u32,
    /// commits per day for the last 14 days, oldest first (the Projects sparkline)
    pub days14: Vec<u32>,
    /// git remote URL (empty if none)
    pub remote_url: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DocTask {
    pub line: usize,
    pub text: String,
    pub done: bool,
    pub section: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Project {
    pub name: String,
    pub path: String,
    pub git: Option<Git>,
    pub docs: Vec<String>,
    /// `- [ ]` / `- [x]` lines of TASKS.md (the file stays the truth for them)
    pub doc_tasks: Vec<DocTask>,
    pub doc_open: usize,
    pub modified: i64,
}

fn is_project(p: &Path) -> bool {
    ["/.git", "/TASKS.md", "/PLAN.md", "/README.md", "/Cargo.toml"].iter().any(|f| Path::new(&format!("{}{}", p.display(), f)).exists())
}

/// The projects Dotos has taken on (the mode, `track`, minus `ignored`).
pub fn discover() -> Vec<PathBuf> {
    let c = crate::project_conf::load();
    discover_all().into_iter().filter(|p| c.is_tracked(p)).collect()
}

/// Every project found under the roots that is not ignored, tracked or not.
pub fn discover_all() -> Vec<PathBuf> {
    let c = crate::project_conf::load();
    let mut out = Vec::new();
    for root in paths::project_roots() {
        if let Ok(rd) = std::fs::read_dir(&root) {
            for e in rd.flatten() {
                let p = e.path();
                let name = e.file_name().to_string_lossy().to_string();
                // a linked worktree (.git is a file) is a copy of a project, not one more
                if p.is_dir() && !name.starts_with('.') && is_project(&p) && !p.join(".git").is_file() && !c.is_ignored(&p) {
                    out.push(p);
                }
            }
        }
    }
    for p in paths::project_extra() {
        if p.is_dir() && !out.contains(&p) && !c.is_ignored(&p) {
            out.push(p);
        }
    }
    out.sort_by_key(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()).unwrap_or_default());
    out
}

fn git(dir: &Path, args: &[&str]) -> Option<String> {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn git_state(dir: &Path) -> Option<Git> {
    if !dir.join(".git").exists() {
        return None;
    }
    let status = git(dir, &["status", "--porcelain=v2", "--branch", "--untracked-files=normal"])?;
    let mut g = Git::default();
    let mut oldest = now();
    for l in status.lines() {
        if let Some(b) = l.strip_prefix("# branch.head ") {
            g.branch = b.to_string();
        } else if let Some(ab) = l.strip_prefix("# branch.ab ") {
            for part in ab.split_whitespace() {
                if let Some(n) = part.strip_prefix('+') { g.ahead = n.parse().unwrap_or(0); }
                if let Some(n) = part.strip_prefix('-') { g.behind = n.parse().unwrap_or(0); }
            }
        } else if !l.starts_with('#') {
            g.dirty += 1;
            if g.dirty <= 200 {
                // the path is the last field (for renames: "new\told")
                let file = l.rsplit(' ').next().unwrap_or("").split('\t').next().unwrap_or("");
                if let Ok(m) = std::fs::metadata(dir.join(file)).and_then(|m| m.modified()) {
                    if let Ok(t) = m.duration_since(std::time::UNIX_EPOCH) {
                        oldest = oldest.min(t.as_secs() as i64);
                    }
                }
            }
        }
    }
    if g.dirty > 0 {
        g.dirty_days = ((now() - oldest).max(0) / 86400) as u32;
    }
    if let Some(log) = git(dir, &["log", "-1", "--format=%h%x09%ct%x09%s"]) {
        let mut f = log.trim().splitn(3, '\t');
        g.last_hash = f.next().unwrap_or("").into();
        g.last_time = f.next().and_then(|t| t.parse().ok()).unwrap_or(0);
        g.last_subject = f.next().unwrap_or("").into();
    }
    // one log for both: the week's count and the 14-day histogram
    g.days14 = vec![0; 14];
    if let Some(out) = git(dir, &["log", "--since=14.days", "--format=%ct", "HEAD"]) {
        let now = now();
        for t in out.lines().filter_map(|l| l.trim().parse::<i64>().ok()) {
            let age = ((now - t).max(0) / 86400) as usize;
            if age < 14 { g.days14[13 - age] += 1; }
            if age < 7 { g.commits_week += 1; }
        }
    }
    if let Some(url) = git(dir, &["remote", "get-url", "origin"]) {
        g.remote_url = url.trim().to_string();
    }
    Some(g)
}

/// a checkbox line: `- [ ] text`, `* [ ]`, `1. [ ]` (numbered plans), `[~]` (half done, still open); its state and text
fn checkbox(t: &str) -> Option<(bool, &str)> {
    let rest = if let Some(r) = t.strip_prefix("- ").or_else(|| t.strip_prefix("* ")) { r } else {
        let n = t.find(". ")?;
        if n == 0 || n > 4 || !t[..n].chars().all(|c| c.is_ascii_digit()) { return None }
        &t[n + 2..]
    };
    let (done, r) = match rest.get(..4)? { "[ ] " | "[~] " => (false, &rest[4..]), "[x] " | "[X] " => (true, &rest[4..]), _ => return None };
    Some((done, r))
}

/// The checkbox lines, with the heading they sit under (lines in ``` code blocks left out).
pub fn doc_tasks(file: &Path) -> Vec<DocTask> {
    let text = std::fs::read_to_string(file).unwrap_or_default();
    let mut section = String::new();
    let mut out = Vec::new();
    let mut code = false;
    for (i, l) in text.lines().enumerate() {
        let t = l.trim_start();
        if t.starts_with("```") { code = !code; continue }
        if code { continue }
        if let Some(h) = t.strip_prefix('#') {
            section = h.trim_start_matches('#').trim().to_string();
            continue;
        }
        let Some((done, rest)) = checkbox(t) else { continue };
        out.push(DocTask { line: i + 1, text: rest.trim().to_string(), done, section: section.clone() });
    }
    out
}

pub fn load(dir: &Path, with_git: bool) -> Project {
    let name = dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let docs: Vec<String> = ["README.md", "PLAN.md", "TASKS.md", "RETHINK.md", "CHANGELOG.md"]
        .iter().filter(|f| dir.join(f).exists()).map(|f| f.to_string()).collect();
    let doc_tasks = doc_tasks(&dir.join("TASKS.md"));
    let modified = std::fs::metadata(dir).and_then(|m| m.modified()).ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs() as i64).unwrap_or(0);
    Project {
        name,
        path: dir.display().to_string(),
        git: if with_git && crate::project_conf::load().on(dir, "git") { git_state(dir) } else { None },
        doc_open: doc_tasks.iter().filter(|t| !t.done).count(),
        docs,
        doc_tasks,
        modified,
    }
}

pub fn find(name: &str) -> Option<PathBuf> {
    discover_all().into_iter().find(|p| p.file_name().is_some_and(|n| n.to_string_lossy().eq_ignore_ascii_case(name)))
}

/// Tick or untick line `line` of a project's TASKS.md.
pub fn toggle_doc_task(dir: &Path, line: usize, done: bool) -> Result<(), String> {
    let file = dir.join("TASKS.md");
    let text = std::fs::read_to_string(&file).map_err(|e| e.to_string())?;
    let mut lines: Vec<String> = text.lines().map(String::from).collect();
    let l = lines.get_mut(line.wrapping_sub(1)).ok_or("no such line")?;
    // any checkbox form (- * 1.), the box itself swapped; [~] counts as open
    match checkbox(l.trim_start()) {
        Some((d, _)) if d != done => {}
        _ => return Err("that line is not a checkbox in that state".into()),
    }
    let boxes: &[&str] = if done { &["[ ] ", "[~] "] } else { &["[x] ", "[X] "] };
    let at = boxes.iter().filter_map(|b| l.find(b)).min().ok_or("no box")?;
    l.replace_range(at..at + 4, if done { "[x] " } else { "[ ] " });
    let mut out = lines.join("\n");
    if text.ends_with('\n') {
        out.push('\n');
    }
    paths::write_atomic(&file, out.as_bytes()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod checkbox_tests {
    use super::*;
    #[test]
    fn numbered_half_done_and_code_blocks() {
        let d = std::env::temp_dir().join(format!("dotos-cb-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("TASKS.md");
        std::fs::write(&f, "## Plan\n1. [x] done one\n2. [~] half\n3. [ ] open\n- [ ] dash\n* [X] star done\n```\n- [ ] in code\n```\n").unwrap();
        let t = doc_tasks(&f);
        let open: Vec<&str> = t.iter().filter(|x| !x.done).map(|x| x.text.as_str()).collect();
        assert_eq!(open, ["half", "open", "dash"], "numbered, [~] and dash open; code left out");
        assert_eq!(t.len(), 5);
        toggle_doc_task(&d, 4, true).unwrap();
        assert!(std::fs::read_to_string(&f).unwrap().contains("3. [x] open"), "a numbered one ticks");
        std::fs::remove_dir_all(&d).ok();
    }
}
