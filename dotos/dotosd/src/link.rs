//! `dotos link A B`: link two things the graph shows, as the kinds mean it. A and B are
//! `page:<id>`, `task:<uid>`, `project:<name>`, `tag:<name>` or `missing:<title>`.
//!
//!   note → note      a [[link]] at the end of the first note
//!   task ↔ note      the note on the task (X-DOTOS-LINK)
//!   task → task      the second waits on the first (blocked by)
//!   any → project    it moves into that project
//!   any → tag        it gets the tag

use crate::{ops, pages};
use icalcore::store::Store;

fn split(s: &str) -> Result<(&str, &str), String> {
    s.split_once(':').filter(|(_, r)| !r.is_empty()).ok_or_else(|| format!("'{s}': expected kind:ref (page:, task:, project:, tag:, missing:)"))
}

/// A note's file with `key: value` set in its front matter (made when it has none).
fn set_front(text: &str, key: &str, value: &str) -> String {
    let line = format!("{key}: {value}");
    if let Some(rest) = text.strip_prefix("---\n") {
        if let Some(end) = rest.find("\n---") {
            let (head, tail) = rest.split_at(end);
            let mut lines: Vec<String> = head.lines().filter(|l| !l.starts_with(&format!("{key}:"))).map(String::from).collect();
            lines.push(line);
            return format!("---\n{}{tail}", lines.join("\n"));
        }
    }
    format!("---\n{line}\n---\n{text}")
}

fn page_edit(id: &str, f: impl FnOnce(&str) -> String) -> Result<(), String> {
    let path = pages::path_of(id);
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let out = f(&text);
    if out != text {
        crate::paths::write_atomic(&path, out.as_bytes()).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn page_of(id: &str) -> Result<pages::Page, String> {
    pages::all().into_iter().find(|p| p.id == id).ok_or_else(|| format!("no note '{id}'"))
}

/// What was done, in a line.
pub fn link(store: &Store, a: &str, b: &str) -> Result<String, String> {
    let ((ka, ra), (kb, rb)) = (split(a)?, split(b)?);
    match (ka, kb) {
        ("page", "page" | "missing") => {
            let title = if kb == "page" { page_of(rb)?.title } else { rb.to_string() };
            let p = page_of(ra)?;
            if p.links.iter().any(|l| l.eq_ignore_ascii_case(&title) || l == rb) {
                return Ok(format!("“{}” already links “{title}”", p.title));
            }
            page_edit(ra, |t| format!("{}\n[[{title}]]\n", t.trim_end()))?;
            Ok(format!("“{}” → [[{title}]]", p.title))
        }
        ("task", "page") | ("page", "task") => {
            let (uid, pid) = if ka == "task" { (ra, rb) } else { (rb, ra) };
            let path = pages::path_of(pid);
            ops::set_fields(store, uid, &[format!("link+={}", path.display())], false)?;
            Ok(format!("the task links “{}”", page_of(pid)?.title))
        }
        ("task", "task") => {
            ops::set_fields(store, rb, &[format!("blocked+={ra}")], false)?;
            Ok("the second task waits on the first".into())
        }
        (_, "project") | ("project", _) => {
            let ((k, r), name) = if kb == "project" { ((ka, ra), rb) } else { ((kb, rb), ra) };
            match k {
                "task" => ops::set_fields(store, r, &[format!("project={name}")], false)?,
                "page" => page_edit(r, |t| set_front(t, "project", name))?,
                _ => return Err(format!("a {k} cannot be in a project")),
            }
            Ok(format!("moved into +{name}"))
        }
        (_, "tag") | ("tag", _) => {
            let ((k, r), tag) = if kb == "tag" { ((ka, ra), rb) } else { ((kb, rb), ra) };
            let tag = tag.trim_start_matches('#');
            match k {
                "task" => {
                    let t = ops::find(store, r)?;
                    let mut tags = t.categories.clone();
                    if !tags.iter().any(|x| x.eq_ignore_ascii_case(tag)) { tags.push(tag.into()); }
                    ops::set_fields(store, r, &[format!("tags={}", tags.join(","))], false)?;
                }
                "page" => {
                    let mut tags = page_of(r)?.tags;
                    if !tags.iter().any(|x| x.eq_ignore_ascii_case(tag)) { tags.push(tag.into()); }
                    page_edit(r, |t| set_front(t, "tags", &tags.join(", ")))?;
                }
                _ => return Err(format!("a {k} cannot have tags")),
            }
            Ok(format!("tagged #{tag}"))
        }
        _ => Err(format!("cannot link a {ka} to a {kb}")),
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn front_matter_key_replaced_or_added() {
        let t = "---\ntitle: A\nproject: old\n---\n# A\n";
        assert_eq!(super::set_front(t, "project", "loom"), "---\ntitle: A\nproject: loom\n---\n# A\n");
        assert_eq!(super::set_front("# B\n", "tags", "x"), "---\ntags: x\n---\n# B\n");
    }
}
