//! The link graph: every markdown file as a point, every [[link]] as a line.
//!
//! Nodes: pages and journal days, the projects they belong to, and with the
//! flags the tags (--tags) and each project's own docs (--docs). A [[link]]
//! that points at nothing becomes a "missing" node, like Obsidian's
//! unresolved links — click one to make the page.

use crate::{pages, projects};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

fn key(s: &str) -> String {
    s.split('|').next().unwrap_or("").split('#').next().unwrap_or("").trim().to_lowercase()
}

pub fn build(with_tags: bool, with_docs: bool) -> Value {
    let pgs = pages::all();
    let mut nodes: Vec<Value> = Vec::new();
    let mut edges: Vec<Value> = Vec::new();
    let mut have: HashSet<String> = HashSet::new();
    let mut seen_edge: HashSet<(String, String)> = HashSet::new();

    // what a [[link]] can mean: the page's id, its file name, its title
    let mut resolve: HashMap<String, String> = HashMap::new();
    for p in &pgs {
        let node = format!("page:{}", p.id);
        for k in [p.id.to_lowercase(), p.id.rsplit('/').next().unwrap_or("").to_lowercase(), p.title.to_lowercase()] {
            resolve.entry(k).or_insert_with(|| node.clone());
        }
    }
    let mut edge = |a: &str, b: &str, kind: &str, edges: &mut Vec<Value>| {
        if a != b && seen_edge.insert((a.to_string(), b.to_string())) {
            edges.push(json!({ "a": a, "b": b, "kind": kind }));
        }
    };

    for p in &pgs {
        let id = format!("page:{}", p.id);
        have.insert(id.clone());
        nodes.push(json!({ "id": id, "ref": p.id, "label": p.title, "kind": p.kind, "tags": p.tags, "project": p.project, "words": p.words, "modified": p.modified, "t": p.created, "excerpt": p.excerpt }));
    }
    for p in &pgs {
        let from = format!("page:{}", p.id);
        for l in &p.links {
            let k = key(l);
            if k.is_empty() { continue; }
            let to = match resolve.get(&k) {
                Some(t) => t.clone(),
                None => {
                    let m = format!("missing:{k}");
                    if have.insert(m.clone()) {
                        nodes.push(json!({ "id": m, "ref": l.split('|').next().unwrap_or(l).split('#').next().unwrap_or(l).trim(), "label": l.split('|').next().unwrap_or(l).trim(), "kind": "missing", "tags": [], "project": "", "words": 0, "modified": 0 }));
                    }
                    m
                }
            };
            edge(&from, &to, if p.embeds.contains(l) { "embed" } else { "link" }, &mut edges);
        }
        if !p.project.is_empty() {
            let pr = format!("project:{}", p.project.to_lowercase());
            if have.insert(pr.clone()) {
                nodes.push(json!({ "id": pr, "ref": p.project, "label": p.project, "kind": "project", "tags": [], "project": p.project, "words": 0, "modified": 0 }));
            }
            edge(&from, &pr, "project", &mut edges);
        }
        if with_tags {
            for t in &p.tags {
                let tg = format!("tag:{}", t.to_lowercase());
                if have.insert(tg.clone()) {
                    nodes.push(json!({ "id": tg, "ref": t, "label": format!("#{t}"), "kind": "tag", "tags": [], "project": "", "words": 0, "modified": 0 }));
                }
                edge(&from, &tg, "tag", &mut edges);
            }
        }
    }
    if with_docs {
        for dir in projects::discover() {
            let pr = projects::load(&dir, false);
            if pr.docs.is_empty() { continue; }
            let id = format!("project:{}", pr.name.to_lowercase());
            if have.insert(id.clone()) {
                nodes.push(json!({ "id": id, "ref": pr.name, "label": pr.name, "kind": "project", "tags": [], "project": pr.name, "words": 0, "modified": pr.modified }));
            }
            for d in &pr.docs {
                let did = format!("doc:{}/{}", pr.path, d);
                nodes.push(json!({ "id": did, "ref": format!("{}/{}", pr.path, d), "label": d.trim_end_matches(".md"), "kind": "doc", "tags": [], "project": pr.name, "words": 0, "modified": 0 }));
                edge(&did, &id, "project", &mut edges);
            }
        }
    }
    json!({ "nodes": nodes, "edges": edges })
}

/// The work in the graph too (`--work`): tasks (open, and done in the last two weeks) as points,
/// linked to their project, their parent task, the tasks blocking them (blocks), the notes they
/// link, the AI sessions working on them (agent) and the commits made for them (git:repo@hash).
pub fn add_work(g: &mut Value, store: &icalcore::store::Store) {
    let todos = store.load_todos();
    let cutoff = chrono::Local::now().naive_local() - chrono::Duration::days(14);
    let agents = crate::agents::list_all();
    let pages_dir = crate::paths::data_dir().join("pages");
    let mut nodes: Vec<Value> = g["nodes"].as_array().cloned().unwrap_or_default();
    let mut edges: Vec<Value> = g["edges"].as_array().cloned().unwrap_or_default();
    let mut have: HashSet<String> = nodes.iter().filter_map(|n| n["id"].as_str().map(String::from)).collect();
    let mut seen_agents: HashSet<String> = HashSet::new();
    let add = |n: Value, nodes: &mut Vec<Value>, have: &mut HashSet<String>| {
        if let Some(id) = n["id"].as_str() {
            if have.insert(id.to_string()) {
                nodes.push(n);
            }
        }
    };
    let shown: Vec<&icalcore::todo::Todo> = todos.iter().filter(|t| t.is_open() || t.completed.is_none_or(|c| c > cutoff)).collect();
    let uids: HashSet<&str> = shown.iter().map(|t| t.uid.as_str()).collect();
    for t in &shown {
        let v = crate::model::view(t, crate::ops::today());
        let id = format!("task:{}", t.uid);
        // when it was made (time travel shows the graph as it was)
        let made = v.created.as_deref().and_then(|c| chrono::NaiveDateTime::parse_from_str(c, "%Y-%m-%dT%H:%M:%S").ok()).and_then(|d| d.and_local_timezone(chrono::Local).single()).map(|d| d.timestamp()).unwrap_or(0);
        let notes = v.notes.chars().take(220).collect::<String>();
        add(json!({ "id": id, "ref": t.uid, "label": v.title, "kind": "task", "state": format!("{:?}", v.state).to_lowercase(), "tags": v.tags, "project": v.project, "words": v.notes.split_whitespace().count(), "modified": 0, "excerpt": notes, "due": v.due, "t": made }), &mut nodes, &mut have);
        if !v.project.is_empty() {
            let pr = format!("project:{}", v.project.to_lowercase());
            add(json!({ "id": pr, "ref": v.project, "label": v.project, "kind": "project", "tags": [], "project": v.project, "words": 0, "modified": 0 }), &mut nodes, &mut have);
            edges.push(json!({ "a": id, "b": pr, "kind": "project" }));
        }
        if !v.parent.is_empty() && uids.contains(v.parent.as_str()) {
            edges.push(json!({ "a": id, "b": format!("task:{}", v.parent), "kind": "parent" }));
        }
        for b in &v.blocked_by {
            if uids.contains(b.as_str()) {
                edges.push(json!({ "a": format!("task:{b}"), "b": id, "kind": "blocks" }));
            }
        }
        for l in &v.links {
            if let Some(a) = l.strip_prefix("agent:") {
                let s = agents.iter().find(|s| s["id"] == a);
                let label = s.map(|s| format!("{} · {}", s["source"].as_str().unwrap_or("agent").replace("claude-code", "Claude"), s["project"].as_str().unwrap_or(""))).unwrap_or_else(|| "AI session".into());
                let acts = crate::agents::actions(a);
                let sum = crate::agents::summary(&acts);
                add(json!({ "id": l, "ref": a, "label": label, "kind": "agent", "state": s.and_then(|s| s["state"].as_str()).unwrap_or("ended"), "tags": [], "project": s.and_then(|s| s["project"].as_str()).unwrap_or(""), "words": 0, "modified": s.and_then(|s| s["updated"].as_u64()).unwrap_or(0), "excerpt": s.and_then(|s| s["prompt"].as_str()).unwrap_or(""), "t": s.and_then(|s| s["started"].as_u64()).unwrap_or(0), "actions": sum["total"], "failed": sum["failed"] }), &mut nodes, &mut have);
                edges.push(json!({ "a": l, "b": id, "kind": "agent" }));
                // the files it changed (once per session): to the session, and to the card it was
                // working on when it did; the newest 60
                if seen_agents.insert(l.clone()) {
                    let files = crate::agents::touched(&acts);
                    let skip = files.len().saturating_sub(60);
                    for (path, kind, times, task) in files.into_iter().skip(skip) {
                        let fid = format!("file:{path}");
                        let name = std::path::Path::new(&path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| path.clone());
                        let state = if kind == "delete" { "deleted" } else if kind == "create" { "created" } else { "changed" };
                        add(json!({ "id": fid, "ref": path, "label": name, "kind": "file", "state": state, "tags": [], "project": s.and_then(|s| s["project"].as_str()).unwrap_or(""), "words": times, "modified": 0, "excerpt": path }), &mut nodes, &mut have);
                        edges.push(json!({ "a": l, "b": fid, "kind": if kind == "delete" { "deleted" } else { "wrote" } }));
                        if !task.is_empty() && uids.contains(task.as_str()) {
                            edges.push(json!({ "a": format!("task:{task}"), "b": fid, "kind": "changed" }));
                        }
                    }
                }
            } else if let Some(c) = l.strip_prefix("git:") {
                let (repo, hash) = c.split_once('@').unwrap_or((c, ""));
                add(json!({ "id": l, "ref": c, "label": format!("{repo}@{}", &hash[..hash.len().min(7)]), "kind": "commit", "tags": [], "project": repo, "words": 0, "modified": 0, "t": made }), &mut nodes, &mut have);
                edges.push(json!({ "a": id, "b": l, "kind": "commit" }));
            } else if let Some(rel) = std::path::Path::new(l.trim_start_matches("file://")).strip_prefix(&pages_dir).ok() {
                // a note it links: page:<its id> (the path under pages/, without .md)
                let pid = rel.with_extension("").display().to_string();
                let pg = format!("page:{pid}");
                if have.contains(&pg) {
                    edges.push(json!({ "a": id, "b": pg, "kind": "link" }));
                }
            }
        }
    }
    g["nodes"] = Value::Array(nodes);
    g["edges"] = Value::Array(edges);
}
