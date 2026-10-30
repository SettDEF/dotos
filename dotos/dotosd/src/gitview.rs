//! Local git for the Changes page (GitHub-style): the repos you and agents work in, a working
//! tree's changed files, diffs parsed into files → hunks → numbered lines, history, commits, files.

use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Text files bigger than this are not sent whole (the viewer shows the start and says so).
const MAX_FILE: usize = 2 * 1024 * 1024;

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output().map_err(|e| format!("git: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// The repo a name points at: a project name, a path, or (none) the current folder; its top level.
pub fn resolve(name: Option<&str>) -> Result<PathBuf, String> {
    let dir = match name.filter(|n| !n.is_empty()) {
        Some(n) if n.contains('/') => PathBuf::from(n),
        Some(n) => crate::projects::find(n).ok_or_else(|| format!("no project '{n}'"))?,
        None => std::env::current_dir().map_err(|e| e.to_string())?,
    };
    let top = git(&dir, &["rev-parse", "--show-toplevel"]).map_err(|_| format!("{} is not in a git repo", dir.display()))?;
    Ok(PathBuf::from(top.trim()))
}

/// Every repo worth showing: the projects that are git repos, plus the ones agents touched files in.
/// Each with its branch, how far from upstream, changed-file count and last commit.
pub fn repos() -> Value {
    let mut dirs: Vec<PathBuf> = crate::projects::discover().into_iter().filter(|d| d.join(".git").exists()).collect();
    for a in crate::agents::list_all() {
        let Some(id) = a.get("id").and_then(Value::as_str) else { continue };
        for (path, ..) in crate::agents::touched(&crate::agents::actions(id)) {
            let p = Path::new(&path);
            let Some(parent) = p.parent() else { continue };
            if let Ok(top) = git(parent, &["rev-parse", "--show-toplevel"]) {
                let top = PathBuf::from(top.trim());
                if !dirs.contains(&top) {
                    dirs.push(top);
                }
            }
        }
    }
    let mut out: Vec<Value> = dirs.iter().filter_map(|d| repo_info(d).ok()).collect();
    // most recently worked on first
    out.sort_by_key(|r| std::cmp::Reverse(r["last"]["time"].as_i64().unwrap_or(0)));
    json!(out)
}

fn repo_info(dir: &Path) -> Result<Value, String> {
    let st = git(dir, &["status", "--porcelain=v2", "--branch"])?;
    let (mut branch, mut ahead, mut behind, mut changed) = (String::new(), 0i64, 0i64, 0usize);
    for l in st.lines() {
        if let Some(b) = l.strip_prefix("# branch.head ") {
            branch = b.to_string();
        } else if let Some(ab) = l.strip_prefix("# branch.ab ") {
            let mut it = ab.split_whitespace();
            ahead = it.next().and_then(|s| s.trim_start_matches('+').parse().ok()).unwrap_or(0);
            behind = it.next().and_then(|s| s.trim_start_matches('-').parse().ok()).unwrap_or(0);
        } else if !l.starts_with('#') {
            changed += 1;
        }
    }
    let last = git(dir, &["log", "-1", "--format=%h%x1f%ct%x1f%an%x1f%s"]).unwrap_or_default();
    let f: Vec<&str> = last.trim_end().split('\x1f').collect();
    Ok(json!({
        "name": dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(),
        "path": dir.display().to_string(),
        "branch": branch, "ahead": ahead, "behind": behind, "changed": changed,
        "last": { "hash": f.first().unwrap_or(&""), "time": f.get(1).and_then(|t| t.parse::<i64>().ok()).unwrap_or(0), "author": f.get(2).unwrap_or(&""), "subject": f.get(3).unwrap_or(&"") },
    }))
}

/// The working tree's changed files (staged and not, untracked too), each with +/- counts.
pub fn changes(dir: &Path) -> Result<Value, String> {
    let st = git(dir, &["status", "--porcelain=v1", "-z", "--untracked-files=all"])?;
    let mut counts = std::collections::HashMap::new();
    for args in [&["diff", "--numstat", "-z"][..], &["diff", "--cached", "--numstat", "-z"][..]] {
        for (path, a, d) in numstat(&git(dir, args).unwrap_or_default()) {
            let e = counts.entry(path).or_insert((0i64, 0i64));
            e.0 += a;
            e.1 += d;
        }
    }
    let mut files = Vec::new();
    let mut parts = st.split('\0').filter(|s| !s.is_empty());
    while let Some(e) = parts.next() {
        if e.len() < 4 {
            continue;
        }
        let (code, path) = (&e[..2], e[3..].to_string());
        // a rename names its old path next
        let from = if code.starts_with('R') || code.starts_with('C') { parts.next().map(str::to_string) } else { None };
        let status = match code {
            "??" => "added",
            c if c.contains('D') => "deleted",
            c if c.contains('A') => "added",
            c if c.contains('R') => "renamed",
            _ => "modified",
        };
        let (mut add, del) = counts.get(&path).copied().unwrap_or((0, 0));
        if code == "??" {
            add = std::fs::read(dir.join(&path)).map(|b| if b.contains(&0) { 0 } else { String::from_utf8_lossy(&b).lines().count() as i64 }).unwrap_or(0);
        }
        files.push(json!({ "path": path, "from": from, "status": status, "staged": !code.starts_with(' ') && code != "??", "add": add, "del": del }));
    }
    files.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    Ok(json!({ "repo": repo_info(dir)?, "files": files }))
}

fn numstat(s: &str) -> Vec<(String, i64, i64)> {
    s.split('\0').filter_map(|e| {
        let mut f = e.splitn(3, '\t');
        let a = f.next()?.trim().parse().unwrap_or(0);
        let d = f.next()?.parse().unwrap_or(0);
        Some((f.next()?.to_string(), a, d))
    }).collect()
}

/// A diff as files → hunks → lines, each line with its kind and old/new numbers.
/// `rev` none: the working tree against HEAD (untracked files shown as added); else that commit.
pub fn diff(dir: &Path, rev: Option<&str>, file: Option<&str>) -> Result<Value, String> {
    let mut args: Vec<&str> = match rev {
        Some(r) => vec!["show", "--format=", "-M", "--no-color", "--no-ext-diff", r],
        None => vec!["diff", "HEAD", "-M", "--no-color", "--no-ext-diff"],
    };
    if let Some(f) = file {
        args.extend(["--", f]);
    }
    // a repo with no commits yet: everything against the empty tree
    let text = match git(dir, &args) {
        Ok(t) => t,
        Err(_) if rev.is_none() => git(dir, &["diff", "--cached", "--no-color"]).unwrap_or_default(),
        Err(e) => return Err(e),
    };
    let mut files = parse(&text);
    if rev.is_none() {
        // untracked files are no part of `git diff`: shown as wholly added
        let untracked = git(dir, &["ls-files", "--others", "--exclude-standard", "-z"]).unwrap_or_default();
        for p in untracked.split('\0').filter(|p| !p.is_empty() && file.is_none_or(|f| f == *p)) {
            files.push(added_file(dir, p));
        }
    }
    Ok(json!({ "files": files }))
}

fn added_file(dir: &Path, path: &str) -> Value {
    let bytes = std::fs::read(dir.join(path)).unwrap_or_default();
    if bytes.contains(&0) {
        return json!({ "path": path, "status": "added", "binary": true, "add": 0, "del": 0, "hunks": [] });
    }
    let text = String::from_utf8_lossy(&bytes[..bytes.len().min(MAX_FILE)]).into_owned();
    let lines: Vec<Value> = text.lines().enumerate().map(|(i, l)| json!({ "k": "+", "o": null, "n": i + 1, "t": l })).collect();
    let n = lines.len();
    json!({ "path": path, "status": "added", "binary": false, "add": n, "del": 0, "hunks": [{ "header": format!("@@ -0,0 +1,{n} @@"), "lines": lines }] })
}

/// Unified diff text → files. Lines: k = "+", "-", " " (context) or "\\" (no newline note).
pub fn parse(text: &str) -> Vec<Value> {
    let mut files: Vec<Value> = Vec::new();
    let mut cur: Option<Value> = None;
    let (mut o, mut n) = (0i64, 0i64);
    let finish = |files: &mut Vec<Value>, cur: &mut Option<Value>| {
        if let Some(f) = cur.take() {
            files.push(f);
        }
    };
    for l in text.lines() {
        if let Some(rest) = l.strip_prefix("diff --git ") {
            finish(&mut files, &mut cur);
            // "a/x b/x": the b side (renames are corrected by the rename lines)
            let path = rest.rsplit_once(" b/").map(|(_, b)| b.to_string()).unwrap_or_default();
            cur = Some(json!({ "path": path, "from": null, "status": "modified", "binary": false, "add": 0, "del": 0, "hunks": [] }));
            continue;
        }
        let Some(f) = cur.as_mut() else { continue };
        if l.starts_with("new file") {
            f["status"] = json!("added");
        } else if l.starts_with("deleted file") {
            f["status"] = json!("deleted");
        } else if let Some(p) = l.strip_prefix("rename from ") {
            f["status"] = json!("renamed");
            f["from"] = json!(p);
        } else if let Some(p) = l.strip_prefix("rename to ") {
            f["path"] = json!(p);
        } else if l.starts_with("Binary files ") {
            f["binary"] = json!(true);
        } else if l.starts_with("@@") {
            // @@ -o,len +n,len @@ section
            let nums: Vec<i64> = l.split(' ').skip(1).take(2).map(|p| p[1..].split(',').next().and_then(|v| v.parse().ok()).unwrap_or(0)).collect();
            o = nums.first().copied().unwrap_or(0);
            n = nums.get(1).copied().unwrap_or(0);
            f["hunks"].as_array_mut().unwrap().push(json!({ "header": l, "lines": [] }));
        } else if let Some(h) = f["hunks"].as_array_mut().and_then(|h| h.last_mut()) {
            // inside a hunk every line is one of its lines (a "--- x" there is a removed "-- x")
            let (k, t) = l.split_at(l.len().min(1));
            let line = match k {
                "+" => {
                    n += 1;
                    json!({ "k": "+", "o": null, "n": n - 1, "t": t })
                }
                "-" => {
                    o += 1;
                    json!({ "k": "-", "o": o - 1, "n": null, "t": t })
                }
                "\\" => json!({ "k": "\\", "o": null, "n": null, "t": t.trim() }),
                _ => {
                    o += 1;
                    n += 1;
                    json!({ "k": " ", "o": o - 1, "n": n - 1, "t": t })
                }
            };
            h["lines"].as_array_mut().unwrap().push(line);
            match k {
                "+" => f["add"] = json!(f["add"].as_i64().unwrap_or(0) + 1),
                "-" => f["del"] = json!(f["del"].as_i64().unwrap_or(0) + 1),
                _ => {}
            }
        }
    }
    finish(&mut files, &mut cur);
    files
}

/// History: the last `n` commits (of `path` only, when given).
pub fn log(dir: &Path, n: usize, path: Option<&str>) -> Result<Value, String> {
    let count = format!("-{n}");
    let mut args = vec!["log", count.as_str(), "--format=%x1e%H%x1f%h%x1f%ct%x1f%an%x1f%s%x1f%P", "--shortstat"];
    if let Some(p) = path {
        args.extend(["--", p]);
    }
    let text = git(dir, &args)?;
    let commits: Vec<Value> = text.split('\x1e').filter_map(|c| {
        let c = c.trim_start_matches('\n');
        let (head, stat) = c.split_once('\n').unwrap_or((c, ""));
        let f: Vec<&str> = head.split('\x1f').collect();
        if f.len() < 5 {
            return None;
        }
        // " 3 files changed, 10 insertions(+), 2 deletions(-)"
        let num = |word: &str| stat.split(',').find(|s| s.contains(word)).and_then(|s| s.split_whitespace().next()?.parse::<i64>().ok()).unwrap_or(0);
        Some(json!({ "hash": f[0], "short": f[1], "time": f[2].parse::<i64>().unwrap_or(0), "author": f[3], "subject": f[4], "parents": f.get(5).map(|p| p.split_whitespace().count()).unwrap_or(0), "files": num("file"), "add": num("insertion"), "del": num("deletion") }))
    }).collect();
    Ok(json!(commits))
}

/// One commit: its message and author, and its diff.
pub fn show(dir: &Path, rev: &str) -> Result<Value, String> {
    let meta = git(dir, &["show", "-s", "--format=%H%x1f%h%x1f%ct%x1f%an%x1f%ae%x1f%B", rev])?;
    let f: Vec<&str> = meta.splitn(6, '\x1f').collect();
    let d = diff(dir, Some(rev), None)?;
    Ok(json!({ "hash": f.first(), "short": f.get(1), "time": f.get(2).and_then(|t| t.parse::<i64>().ok()), "author": f.get(3), "email": f.get(4), "message": f.get(5).map(|m| m.trim_end()), "files": d["files"] }))
}

/// A file's text with line numbers (at `rev`, else as it is on disk), or why it cannot be shown.
pub fn cat(dir: &Path, path: &str, rev: Option<&str>) -> Result<Value, String> {
    let bytes = match rev {
        Some(r) => Command::new("git").arg("-C").arg(dir).args(["show", &format!("{r}:{path}")]).output().map_err(|e| e.to_string())?.stdout,
        None => std::fs::read(dir.join(path)).map_err(|e| format!("{path}: {e}"))?,
    };
    if bytes.contains(&0) {
        return Ok(json!({ "path": path, "binary": true, "size": bytes.len(), "lines": [] }));
    }
    let cut = bytes.len() > MAX_FILE;
    let text = String::from_utf8_lossy(&bytes[..bytes.len().min(MAX_FILE)]).into_owned();
    Ok(json!({ "path": path, "binary": false, "size": bytes.len(), "truncated": cut, "lines": text.lines().collect::<Vec<_>>() }))
}

/// The repo's files (tracked and untracked, not ignored) for browsing.
pub fn tree(dir: &Path) -> Result<Value, String> {
    let text = git(dir, &["ls-files", "--cached", "--others", "--exclude-standard", "-z"])?;
    let mut files: Vec<&str> = text.split('\0').filter(|p| !p.is_empty()).collect();
    files.sort();
    files.dedup();
    Ok(json!(files))
}

#[cfg(test)]
mod tests {
    #[test]
    fn parses_numbers() {
        let d = "diff --git a/x.rs b/x.rs\nindex 1..2 100644\n--- a/x.rs\n+++ b/x.rs\n@@ -1,3 +1,4 @@ fn a\n one\n-two\n+zwei\n+drei\n three\n";
        let f = super::parse(d);
        assert_eq!(f.len(), 1);
        let l = &f[0]["hunks"][0]["lines"];
        assert_eq!((l[0]["k"].as_str(), l[0]["o"].as_i64(), l[0]["n"].as_i64()), (Some(" "), Some(1), Some(1)));
        assert_eq!((l[1]["k"].as_str(), l[1]["o"].as_i64()), (Some("-"), Some(2)));
        assert_eq!((l[2]["k"].as_str(), l[2]["n"].as_i64()), (Some("+"), Some(2)));
        assert_eq!((l[3]["k"].as_str(), l[3]["n"].as_i64()), (Some("+"), Some(3)));
        assert_eq!((l[4]["o"].as_i64(), l[4]["n"].as_i64()), (Some(3), Some(4)));
        assert_eq!((f[0]["add"].as_i64(), f[0]["del"].as_i64()), (Some(2), Some(1)));
    }
}

/// Commits `files` (all changes when empty) with `message`; returns the new commit.
pub fn commit(dir: &Path, message: &str, files: &[String]) -> Result<Value, String> {
    if message.trim().is_empty() {
        return Err("a commit needs a message".into());
    }
    let mut add = vec!["add", "-A", "--"];
    add.extend(files.iter().map(String::as_str));
    git(dir, &add)?;
    // only the chosen files: the rest stays as it was (unstaged)
    if !files.is_empty() {
        let staged = git(dir, &["diff", "--cached", "--name-only", "-z"])?;
        let others: Vec<&str> = staged.split('\0').filter(|p| !p.is_empty() && !files.iter().any(|f| f == p)).collect();
        if !others.is_empty() {
            let mut reset = vec!["reset", "-q", "--"];
            reset.extend(others);
            git(dir, &reset)?;
        }
    }
    git(dir, &["commit", "-q", "-m", message])?;
    let head = git(dir, &["log", "-1", "--format=%h%x1f%s"])?;
    let (h, s) = head.trim_end().split_once('\x1f').unwrap_or(("", ""));
    Ok(json!({ "short": h, "subject": s }))
}

/// `git push` / `git pull --ff-only` (the user's credentials: their helper, gh, ssh agent).
pub fn sync(dir: &Path, push: bool) -> Result<Value, String> {
    let out = Command::new("git").arg("-C").arg(dir).args(if push { &["push"][..] } else { &["pull", "--ff-only"][..] })
        .env("GIT_TERMINAL_PROMPT", "0").output().map_err(|e| e.to_string())?;
    let text = format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr)).trim().to_string();
    if !out.status.success() {
        return Err(text);
    }
    Ok(json!({ "ok": true, "text": text, "repo": repo_info(dir)? }))
}
