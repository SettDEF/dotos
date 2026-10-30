//! `dotos graph --insight`: what the graph says about the notes. Each point gets a `group` (its
//! community, by label propagation), and `insight` lists the orphans, the hubs, the links to notes
//! not written yet (and who makes them), and links worth making: a note that names another without
//! linking it, or two notes that link the same notes.

use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

/// Communities: each point takes the label most of its neighbours have, until nothing changes.
/// Deterministic (fixed order, ties to the smallest label), so the colours stay put between runs.
fn groups(n: usize, adj: &[Vec<usize>]) -> Vec<usize> {
    let mut label: Vec<usize> = (0..n).collect();
    for _ in 0..30 {
        let mut changed = false;
        for i in 0..n {
            if adj[i].is_empty() {
                continue;
            }
            let mut count: HashMap<usize, usize> = HashMap::new();
            for &j in &adj[i] {
                *count.entry(label[j]).or_default() += 1;
            }
            let best = count.iter().max_by(|a, b| a.1.cmp(b.1).then(b.0.cmp(a.0))).map(|(l, _)| *l).unwrap_or(label[i]);
            if best != label[i] {
                label[i] = best;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    // numbered by size, the biggest 0
    let mut size: HashMap<usize, usize> = HashMap::new();
    for &l in &label {
        *size.entry(l).or_default() += 1;
    }
    let mut order: Vec<usize> = size.keys().copied().collect();
    order.sort_by(|a, b| size[b].cmp(&size[a]).then(a.cmp(b)));
    let rank: HashMap<usize, usize> = order.iter().enumerate().map(|(r, l)| (*l, r)).collect();
    label.iter().map(|l| rank[l]).collect()
}

/// A note's text without its front matter.
fn body(t: &str) -> &str {
    t.strip_prefix("---\n").and_then(|r| r.find("\n---").map(|i| &r[i + 4..])).unwrap_or(t)
}

/// `t` names `w` as a word, not inside another word (as given: lowercase both for any case).
fn names(t: &str, w: &str) -> bool {
    let mut from = 0;
    while let Some(i) = t[from..].find(&w) {
        let s = from + i;
        let e = s + w.len();
        let before = t[..s].chars().next_back().is_none_or(|c| !c.is_alphanumeric());
        let after = t[e..].chars().next().is_none_or(|c| !c.is_alphanumeric());
        if before && after {
            return true;
        }
        from = e;
    }
    false
}

pub fn add(g: &mut Value, texts: &HashMap<String, String>) {
    let nodes = g["nodes"].as_array().cloned().unwrap_or_default();
    let edges = g["edges"].as_array().cloned().unwrap_or_default();
    let n = nodes.len();
    let index: HashMap<&str, usize> = nodes.iter().enumerate().filter_map(|(i, v)| Some((v["id"].as_str()?, i))).collect();
    let kind = |i: usize| nodes[i]["kind"].as_str().unwrap_or("");
    let is_note = |i: usize| matches!(kind(i), "page" | "journal");
    let mut adj = vec![Vec::new(); n];
    let mut linked: HashSet<(usize, usize)> = HashSet::new();
    let mut out_links = vec![HashSet::new(); n];
    for e in &edges {
        let (Some(&a), Some(&b)) = (e["a"].as_str().and_then(|s| index.get(s)), e["b"].as_str().and_then(|s| index.get(s))) else { continue };
        // tags and projects join everything they hold: they would make one big group
        if !matches!(e["kind"].as_str(), Some("tag") | Some("project")) {
            adj[a].push(b);
            adj[b].push(a);
        }
        linked.insert((a.min(b), a.max(b)));
        if matches!(e["kind"].as_str(), Some("link") | Some("embed")) {
            out_links[a].insert(b);
        }
    }
    let group = groups(n, &adj);
    let mut deg = vec![0usize; n];
    for &(a, b) in &linked {
        deg[a] += 1;
        deg[b] += 1;
    }

    let orphans: Vec<&Value> = (0..n).filter(|&i| is_note(i) && deg[i] == 0).map(|i| &nodes[i]["id"]).collect();
    let mut hubs: Vec<usize> = (0..n).filter(|&i| is_note(i) && deg[i] >= 3).collect();
    hubs.sort_by(|a, b| deg[*b].cmp(&deg[*a]));
    let hubs: Vec<Value> = hubs.iter().take(8).map(|&i| json!({ "id": nodes[i]["id"], "links": deg[i] })).collect();
    let missing: Vec<Value> = (0..n)
        .filter(|&i| kind(i) == "missing")
        .map(|i| json!({ "id": nodes[i]["id"], "label": nodes[i]["label"], "from": (0..n).filter(|&j| out_links[j].contains(&i)).map(|j| nodes[j]["id"].clone()).collect::<Vec<_>>() }))
        .collect();

    // links worth making, the surest first
    let mut suggest: Vec<(usize, Value)> = Vec::new();
    let notes: Vec<usize> = (0..n).filter(|&i| kind(i) == "page").collect();
    for &a in &notes {
        // the body only: front matter (project: loom) is not the note naming anything
        let Some(text) = nodes[a]["ref"].as_str().and_then(|r| texts.get(r)).map(|t| body(t)) else { continue };
        let lower = text.to_lowercase();
        for &b in &notes {
            let title = nodes[b]["label"].as_str().unwrap_or("");
            if a == b || title.chars().count() < 4 || linked.contains(&(a.min(b), a.max(b))) {
                continue;
            }
            // one word ("Page", "Loom"): only as written, so the plain word in a sentence is not it
            let named = if title.contains(' ') { names(&lower, &title.to_lowercase()) } else { names(text, title) };
            if named {
                suggest.push((100, json!({ "a": nodes[a]["id"], "b": nodes[b]["id"], "why": format!("names “{title}”") })));
            }
        }
    }
    for (x, &a) in notes.iter().enumerate() {
        for &b in &notes[x + 1..] {
            if linked.contains(&(a.min(b), a.max(b))) {
                continue;
            }
            let shared = out_links[a].intersection(&out_links[b]).count();
            if shared >= 2 {
                suggest.push((shared, json!({ "a": nodes[a]["id"], "b": nodes[b]["id"], "why": format!("both link {shared} of the same notes") })));
            }
        }
    }
    suggest.sort_by(|a, b| b.0.cmp(&a.0));
    // groups of two or more: a point on its own is not a community
    let mut sizes: HashMap<usize, usize> = HashMap::new();
    for &g in &group {
        *sizes.entry(g).or_default() += 1;
    }
    let groups_n = sizes.values().filter(|&&s| s > 1).count();

    if let Some(ns) = g["nodes"].as_array_mut() {
        for (i, v) in ns.iter_mut().enumerate() {
            v["group"] = json!(group[i]);
        }
    }
    g["insight"] = json!({
        "orphans": orphans, "hubs": hubs, "missing": missing,
        "suggest": suggest.into_iter().take(20).map(|s| s.1).collect::<Vec<_>>(),
        "groups": groups_n,
    });
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use std::collections::HashMap;

    #[test]
    fn groups_split_where_the_links_do() {
        // a-b-c tight, d-e tight, one thin bridge c-d
        let adj = vec![vec![1, 2], vec![0, 2], vec![0, 1, 3], vec![2, 4], vec![3]];
        let g = super::groups(5, &adj);
        assert_eq!(g[0], g[1]);
        assert_eq!(g[1], g[2]);
        assert_eq!(g[3], g[4]);
    }

    #[test]
    fn front_matter_is_not_the_note_naming_anything() {
        assert_eq!(super::body("---\nproject: loom\n---\n# A\n"), "\n# A\n");
        assert_eq!(super::body("no front"), "no front");
    }

    #[test]
    fn names_only_whole_words() {
        assert!(super::names("we use loom here", "loom"));
        assert!(!super::names("a loomy day", "loom"));
    }

    #[test]
    fn suggests_a_note_named_but_not_linked() {
        let mut g = json!({ "nodes": [
            { "id": "page:a", "ref": "a", "label": "Alpha", "kind": "page" },
            { "id": "page:b", "ref": "b", "label": "Bravo", "kind": "page" },
        ], "edges": [] });
        let texts = HashMap::from([("a".to_string(), "---\nproject: bravo\n---\nsee Bravo for more".to_string())]);
        super::add(&mut g, &texts);
        assert_eq!(g["insight"]["suggest"][0]["b"], "page:b");
        assert_eq!(g["insight"]["orphans"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn a_one_word_title_in_plain_lowercase_is_not_a_mention() {
        let mut g = json!({ "nodes": [
            { "id": "page:a", "ref": "a", "label": "Notes", "kind": "page" },
            { "id": "page:b", "ref": "b", "label": "Page", "kind": "page" },
        ], "edges": [] });
        let texts = HashMap::from([("a".to_string(), "one page of notes".to_string())]);
        super::add(&mut g, &texts);
        assert_eq!(g["insight"]["suggest"].as_array().unwrap().len(), 0);
    }
}
