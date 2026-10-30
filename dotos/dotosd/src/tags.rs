//! Custom tags: a registry of tags with name, color, icon, priority.
//!
//! Tags are richer than the free-text categories on tasks. Each tag has
//! metadata (color, icon, priority) and can be linked to tasks, projects
//! and pages. The registry lives in ~/.local/share/dotos/tags.json.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tag {
    pub name: String,
    pub color: String,
    pub icon: String,
    pub priority: String,
    pub description: String,
    pub created: i64,
}

impl Tag {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            color: "#4ade80".to_string(),
            icon: "label".to_string(),
            priority: "normal".to_string(),
            description: String::new(),
            created: now(),
        }
    }
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn tags_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    let data = std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{}/.local/share", home));
    PathBuf::from(data).join("dotos").join("tags.json")
}

pub fn load() -> Vec<Tag> {
    let p = tags_path();
    if let Ok(text) = std::fs::read_to_string(&p) {
        serde_json::from_str(&text).unwrap_or_default()
    } else {
        Vec::new()
    }
}

pub fn save(tags: &[Tag]) -> Result<(), String> {
    let p = tags_path();
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(tags).map_err(|e| e.to_string())?;
    std::fs::write(&p, text).map_err(|e| e.to_string())
}

pub fn find(name: &str) -> Option<Tag> {
    load().into_iter().find(|t| t.name.eq_ignore_ascii_case(name))
}

pub fn add(name: &str, color: &str, icon: &str, priority: &str, description: &str) -> Result<Tag, String> {
    let mut tags = load();
    if tags.iter().any(|t| t.name.eq_ignore_ascii_case(name)) {
        return Err(format!("tag '{}' already exists", name));
    }
    let mut tag = Tag::new(name);
    if !color.is_empty() { tag.color = color.to_string(); }
    if !icon.is_empty() { tag.icon = icon.to_string(); }
    if !priority.is_empty() { tag.priority = priority.to_string(); }
    if !description.is_empty() { tag.description = description.to_string(); }
    tags.push(tag.clone());
    save(&tags)?;
    Ok(tag)
}

pub fn edit(name: &str, color: Option<&str>, icon: Option<&str>, priority: Option<&str>, description: Option<&str>) -> Result<Tag, String> {
    let mut tags = load();
    let tag = tags.iter_mut().find(|t| t.name.eq_ignore_ascii_case(name))
        .ok_or_else(|| format!("no tag '{}'", name))?;
    if let Some(c) = color { if !c.is_empty() { tag.color = c.to_string(); } }
    if let Some(i) = icon { if !i.is_empty() { tag.icon = i.to_string(); } }
    if let Some(p) = priority { if !p.is_empty() { tag.priority = p.to_string(); } }
    if let Some(d) = description { tag.description = d.to_string(); }
    let result = tag.clone();
    save(&tags)?;
    Ok(result)
}

pub fn remove(name: &str) -> Result<(), String> {
    let mut tags = load();
    let before = tags.len();
    tags.retain(|t| !t.name.eq_ignore_ascii_case(name));
    if tags.len() == before {
        return Err(format!("no tag '{}'", name));
    }
    save(&tags)
}

pub fn list() -> Vec<Tag> {
    load()
}

/// Spinweb: build a graph of tag relationships.
/// Nodes: tags + tasks that use them. Edges: task-tag links.
pub fn spinweb() -> Value {
    let tags = load();
    let mut nodes: Vec<Value> = Vec::new();
    let edges: Vec<Value> = Vec::new();

    for tag in &tags {
        nodes.push(serde_json::json!({
            "id": format!("tag:{}", tag.name.to_lowercase()),
            "label": format!("#{}", tag.name),
            "kind": "tag",
            "color": tag.color,
            "icon": tag.icon,
            "priority": tag.priority,
        }));
    }

    // Link tags to each other based on co-occurrence in tasks
    // (placeholder: actual implementation would read tasks)
    serde_json::json!({
        "nodes": nodes,
        "edges": edges,
        "type": "spinweb",
    })
}
