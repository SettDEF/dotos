//! Pages: markdown files with a little front-matter, in $XDG_DATA_HOME/dotos/pages.
//!
//!   ---
//!   title: safemap · data sources
//!   tags: research, safemap
//!   project: safemap
//!   ---
//!   text, [[links to other pages]], and checklists:
//!   - [ ] a checkbox here is a task: it shows in Tasks and on Home
//!
//! The file is the truth. Ticking a page task from the window rewrites that
//! one line, so the page stays plain markdown any editor can open.
//! The journal is the same thing, one page per day in journal/.

use crate::paths;
use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize)]
pub struct PageTask {
    pub line: usize,
    pub text: String,
    pub done: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct Page {
    pub id: String,
    pub path: String,
    pub title: String,
    pub tags: Vec<String>,
    pub project: String,
    pub kind: String,
    pub words: usize,
    pub links: Vec<String>,
    /// the links written as embeds (![[…]]), also in links
    pub embeds: Vec<String>,
    pub tasks: Vec<PageTask>,
    pub modified: i64,
    /// when the file was made (its birth time; else when it last changed)
    pub created: i64,
    pub excerpt: String,
}

fn front(text: &str) -> (Vec<(String, String)>, &str) {
    let Some(rest) = text.strip_prefix("---\n") else { return (vec![], text) };
    let Some(end) = rest.find("\n---") else { return (vec![], text) };
    let kv = rest[..end].lines().filter_map(|l| l.split_once(':')).map(|(k, v)| (k.trim().to_lowercase(), v.trim().to_string())).collect();
    let body = rest[end + 4..].trim_start_matches(|c| c == '-').trim_start_matches('\n');
    (kv, body)
}

pub fn parse(path: &Path, id: String, kind: &str) -> Option<Page> {
    let text = std::fs::read_to_string(path).ok()?;
    let (kv, body) = front(&text);
    let get = |k: &str| kv.iter().find(|(a, _)| a == k).map(|(_, v)| v.clone()).unwrap_or_default();
    let offset = text.len() - body.len();
    let first_body_line = text[..offset].lines().count();
    let mut tasks = Vec::new();
    let mut links = Vec::new();
    let mut embeds = Vec::new();
    for (i, l) in body.lines().enumerate() {
        let t = l.trim_start();
        if let Some(r) = t.strip_prefix("- [ ] ") {
            tasks.push(PageTask { line: first_body_line + i + 1, text: r.trim().into(), done: false });
        } else if let Some(r) = t.strip_prefix("- [x] ").or_else(|| t.strip_prefix("- [X] ")) {
            tasks.push(PageTask { line: first_body_line + i + 1, text: r.trim().into(), done: true });
        }
        let mut rest = l;
        while let Some(s) = rest.find("[[") {
            let after = &rest[s + 2..];
            if let Some(e) = after.find("]]") {
                if rest[..s].ends_with('!') {
                    embeds.push(after[..e].to_string());
                }
                links.push(after[..e].to_string());
                rest = &after[e + 2..];
            } else {
                break;
            }
        }
    }
    let title = Some(get("title")).filter(|t| !t.is_empty())
        .or_else(|| body.lines().find_map(|l| l.strip_prefix("# ").map(|s| s.trim().to_string())))
        .unwrap_or_else(|| id.rsplit('/').next().unwrap_or(&id).to_string());
    let excerpt: String = body.lines().map(str::trim)
        .find(|l| !l.is_empty() && !l.starts_with('#') && !l.starts_with("- ["))
        .unwrap_or("").chars().take(160).collect();
    let modified = std::fs::metadata(path).and_then(|m| m.modified()).ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs() as i64).unwrap_or(0);
    let created = std::fs::metadata(path).and_then(|m| m.created()).ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs() as i64).unwrap_or(modified);
    Some(Page {
        id,
        path: path.display().to_string(),
        title,
        tags: get("tags").split(',').map(|s| s.trim().trim_start_matches('#').to_string()).filter(|s| !s.is_empty()).collect(),
        project: get("project"),
        kind: kind.into(),
        words: body.split_whitespace().count(),
        links,
        embeds,
        tasks,
        modified,
        created,
        excerpt,
    })
}

fn walk(dir: &Path, base: &Path, kind: &str, prefix: &str, out: &mut Vec<Page>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            if !e.file_name().to_string_lossy().starts_with('.') {
                walk(&p, base, kind, prefix, out);
            }
        } else if p.extension().is_some_and(|x| x == "md") {
            let id = format!("{prefix}{}", p.strip_prefix(base).unwrap_or(&p).with_extension("").display());
            if let Some(pg) = parse(&p, id, kind) {
                out.push(pg);
            }
        }
    }
}

pub fn all() -> Vec<Page> {
    let mut out = Vec::new();
    walk(&paths::pages_dir(), &paths::pages_dir(), "page", "", &mut out);
    walk(&paths::journal_dir(), &paths::journal_dir(), "journal", "journal/", &mut out);
    out.sort_by_key(|p| std::cmp::Reverse(p.modified));
    out
}

pub fn path_of(id: &str) -> PathBuf {
    if let Some(day) = id.strip_prefix("journal/") {
        return paths::journal_dir().join(format!("{day}.md"));
    }
    paths::pages_dir().join(format!("{id}.md"))
}

pub fn create(title: &str, project: &str, tags: &str) -> std::io::Result<PathBuf> {
    let slug: String = title.to_lowercase().chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' }).collect::<String>()
        .split('-').filter(|s| !s.is_empty()).collect::<Vec<_>>().join("-");
    let slug = if slug.is_empty() { "untitled".into() } else { slug };
    let mut p = paths::pages_dir().join(format!("{slug}.md"));
    let mut n = 2;
    while p.exists() {
        p = paths::pages_dir().join(format!("{slug}-{n}.md"));
        n += 1;
    }
    let mut text = format!("---\ntitle: {title}\n");
    if !tags.is_empty() { text.push_str(&format!("tags: {tags}\n")); }
    if !project.is_empty() { text.push_str(&format!("project: {project}\n")); }
    text.push_str(&format!("---\n# {title}\n\n"));
    paths::write_atomic(&p, text.as_bytes())?;
    Ok(p)
}

/// Today's journal page, made from the template the first time it is asked for.
pub fn journal_today(agenda: &[String], done: &[String]) -> std::io::Result<PathBuf> {
    let day = chrono::Local::now().date_naive();
    let p = paths::journal_dir().join(format!("{}.md", day.format("%Y-%m-%d")));
    if p.exists() {
        return Ok(p);
    }
    let mut t = format!("---\ntitle: {}\ntags: journal\n---\n# {}\n\n", day.format("%A %-d %B %Y"), day.format("%A %-d %B"));
    t.push_str("## Plan\n");
    for a in agenda { t.push_str(&format!("- {a}\n")); }
    t.push_str("\n## Notes\n\n\n## Done\n");
    for d in done { t.push_str(&format!("- [x] {d}\n")); }
    paths::write_atomic(&p, t.as_bytes())?;
    Ok(p)
}

pub fn toggle(id: &str, line: usize, done: bool) -> Result<(), String> {
    let p = path_of(id);
    let text = std::fs::read_to_string(&p).map_err(|e| e.to_string())?;
    let mut lines: Vec<String> = text.lines().map(String::from).collect();
    let l = lines.get_mut(line.wrapping_sub(1)).ok_or("no such line")?;
    let (from, to) = if done { ("- [ ] ", "- [x] ") } else { ("- [x] ", "- [ ] ") };
    let alt = if done { "- [ ] " } else { "- [X] " };
    if l.contains(from) {
        *l = l.replacen(from, to, 1);
    } else if l.contains(alt) {
        *l = l.replacen(alt, to, 1);
    } else {
        return Err("that line is not a checkbox in that state".into());
    }
    let mut out = lines.join("\n");
    if text.ends_with('\n') { out.push('\n'); }
    paths::write_atomic(&p, out.as_bytes()).map_err(|e| e.to_string())
}
