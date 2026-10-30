//! Extensions — the same contract as Vitals' probes: an executable file in
//! $XDG_CONFIG_HOME/dotos/extensions/, any language, described by its header:
//!
//!   # @name    TODO comments
//!   # @about   Every `TODO:` in your projects becomes a task.
//!   # @kind    source                       source | action | view
//!   # @every   30m                          sources: how often `dotos serve` runs it
//!   # @on      added,done,state             actions: which events wake it
//!   # @option  ROOTS text "/mnt/storage/dev/projects" "Folders to scan"
//!
//! Options are stored in extensions/options/<file stem>.json (the window's
//! Extensions page edits them) and passed as DOTOS_OPT_<KEY>.
//! Disabled extensions are listed in config.json "disabledExtensions".
//!
//! source  prints one JSON object per line:
//!         {"key":"…","title":"…","notes":"…","due":"2026-10-20","url":"…","project":"…","list":"…","tags":["…"],"priority":"high"}
//!         Dotos keeps one task per key (origin ext:<name>:<key>). A task whose
//!         key is gone from a complete, successful run is closed — the source
//!         said it is no longer there (issue closed, TODO removed).
//! action  gets the event in DOTOS_EVENT and the task as JSON on stdin.
//! view    a folder with view.qml: the window adds it as a page.

use crate::paths;
use serde::Serialize;
use serde_json::Value;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Serialize)]
pub struct OptionDef {
    pub key: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub default: String,
    pub label: String,
    pub value: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct Ext {
    pub id: String,
    pub path: String,
    pub name: String,
    pub about: String,
    pub kind: String,
    pub every_min: u32,
    pub on: Vec<String>,
    pub options: Vec<OptionDef>,
    pub enabled: bool,
    pub view_qml: String,
    pub last_run: i64,
    pub last_ok: bool,
    pub last_msg: String,
}

/// `"a b" c "d e"` → [a b, c, d e]
fn words(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut q = false;
    for c in s.chars() {
        match c {
            '"' => q = !q,
            ' ' | '\t' if !q => {
                if !cur.is_empty() { out.push(std::mem::take(&mut cur)); }
            }
            _ => cur.push(c),
        }
    }
    if !cur.is_empty() { out.push(cur); }
    out
}

fn options_file(id: &str) -> PathBuf {
    paths::extensions_dir().join("options").join(format!("{id}.json"))
}

fn options_values(id: &str) -> serde_json::Map<String, Value> {
    std::fs::read_to_string(options_file(id)).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn state_file() -> PathBuf { paths::state_dir().join("extensions.json") }
fn run_state() -> serde_json::Map<String, Value> {
    std::fs::read_to_string(state_file()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}
fn save_run(id: &str, ok: bool, msg: &str) {
    let mut s = run_state();
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    s.insert(id.into(), serde_json::json!({ "t": now, "ok": ok, "msg": msg }));
    let _ = paths::write_atomic(&state_file(), Value::Object(s).to_string().as_bytes());
}

fn parse(path: &Path) -> Option<Ext> {
    let (script, view) = if path.is_dir() {
        let v = path.join("view.qml");
        let main = ["run", "main.sh", "main"].iter().map(|f| path.join(f)).find(|p| p.exists());
        (main, v.exists().then_some(v))
    } else {
        (Some(path.to_path_buf()), None)
    };
    let id = path.file_stem()?.to_string_lossy().to_string();
    let header = script.as_ref().and_then(|s| std::fs::read_to_string(s).ok())
        .or_else(|| view.as_ref().and_then(|v| std::fs::read_to_string(v).ok()))
        .unwrap_or_default();
    let values = options_values(&id);
    let mut e = Ext {
        id: id.clone(), path: path.display().to_string(), name: id.clone(), about: String::new(),
        kind: if view.is_some() { "view".into() } else { "action".into() },
        every_min: 60, on: vec![], options: vec![], enabled: true,
        view_qml: view.map(|v| v.display().to_string()).unwrap_or_default(),
        last_run: 0, last_ok: true, last_msg: String::new(),
    };
    for l in header.lines().take(60) {
        let t = l.trim_start_matches(|c| c == '#' || c == '/' || c == ' ' || c == '*');
        let Some(rest) = t.strip_prefix('@') else { continue };
        let (tag, val) = rest.split_once(char::is_whitespace).unwrap_or((rest, ""));
        let val = val.trim();
        match tag {
            "name" => e.name = val.into(),
            "about" => e.about = val.into(),
            "kind" => e.kind = val.to_lowercase(),
            "every" => e.every_min = crate::capture::minutes(val).unwrap_or(60).max(1),
            "on" => e.on = val.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect(),
            "option" => {
                let w = words(val);
                if w.len() >= 3 {
                    let key = w[0].clone();
                    let value = values.get(&key).cloned().unwrap_or_else(|| Value::String(w[2].clone()));
                    e.options.push(OptionDef { key, kind: w[1].clone(), default: w[2].clone(), label: w.get(3).cloned().unwrap_or_default(), value });
                }
            }
            _ => {}
        }
    }
    let disabled = paths::config()["disabledExtensions"].as_array().cloned().unwrap_or_default();
    e.enabled = !disabled.iter().any(|d| d.as_str() == Some(&id));
    if let Some(r) = run_state().get(&id) {
        e.last_run = r["t"].as_i64().unwrap_or(0);
        e.last_ok = r["ok"].as_bool().unwrap_or(true);
        e.last_msg = r["msg"].as_str().unwrap_or("").into();
    }
    Some(e)
}

pub fn list() -> Vec<Ext> {
    let mut out: Vec<Ext> = std::fs::read_dir(paths::extensions_dir()).into_iter().flatten().flatten()
        .map(|e| e.path())
        .filter(|p| {
            let n = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            !n.starts_with('.') && n != "options" && !n.ends_with('~') && !n.ends_with(".disabled")
        })
        .filter_map(|p| parse(&p))
        .collect();
    out.sort_by(|a, b| a.kind.cmp(&b.kind).then(a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    out
}

fn command_for(e: &Ext) -> Option<Command> {
    let p = PathBuf::from(&e.path);
    let script = if p.is_dir() { ["run", "main.sh", "main"].iter().map(|f| p.join(f)).find(|x| x.exists())? } else { p };
    let mut c = Command::new(script);
    for o in &e.options {
        let v = match &o.value { Value::String(s) => s.clone(), Value::Bool(b) => if *b { "1".into() } else { "0".into() }, x => x.to_string() };
        c.env(format!("DOTOS_OPT_{}", o.key.to_ascii_uppercase()), v);
    }
    c.env("DOTOS_BIN", std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_else(|_| "dotos".into()));
    Some(c)
}

/// Run a source: returns its items (or an error to show on the Extensions page).
pub fn run_source(e: &Ext) -> Result<Vec<Value>, String> {
    let mut c = command_for(e).ok_or("no executable in the extension")?;
    let out = c.stdin(Stdio::null()).output().map_err(|x| format!("could not start: {x}"))?;
    if !out.status.success() {
        let msg = String::from_utf8_lossy(&out.stderr).lines().last().unwrap_or("failed").to_string();
        save_run(&e.id, false, &msg);
        return Err(msg);
    }
    let items: Vec<Value> = String::from_utf8_lossy(&out.stdout).lines()
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .filter(|v| v["key"].is_string() && v["title"].is_string())
        .collect();
    save_run(&e.id, true, &format!("{} items", items.len()));
    Ok(items)
}

/// Wake the actions that listen to `event`, without waiting for them.
pub fn fire(event: &str, task_json: &Value) {
    for e in list().into_iter().filter(|e| e.enabled && e.kind == "action" && (e.on.is_empty() || e.on.iter().any(|o| o == event || o == "*"))) {
        let Some(mut c) = command_for(&e) else { continue };
        c.env("DOTOS_EVENT", event).env("DOTOS_UID", task_json["uid"].as_str().unwrap_or(""))
            .env("DOTOS_TITLE", task_json["title"].as_str().unwrap_or(""))
            .env("DOTOS_STATE", task_json["state"].as_str().unwrap_or(""))
            .env("DOTOS_PROJECT", task_json["project"].as_str().unwrap_or(""))
            .stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null());
        if let Ok(mut child) = c.spawn() {
            if let Some(mut si) = child.stdin.take() {
                let _ = si.write_all(task_json.to_string().as_bytes());
            }
            // reaped by the OS when we exit; actions must not hold the CLI up
            std::mem::forget(child);
        }
    }
}

pub fn set_option(id: &str, key: &str, value: &str) -> Result<(), String> {
    let mut m = options_values(id);
    let v = match value { "true" => Value::Bool(true), "false" => Value::Bool(false), s => s.parse::<f64>().map(Value::from).unwrap_or(Value::String(s.into())) };
    m.insert(key.into(), v);
    paths::write_atomic(&options_file(id), Value::Object(m).to_string().as_bytes()).map_err(|e| e.to_string())
}

pub fn set_enabled(id: &str, on: bool) -> Result<(), String> {
    let mut cfg = paths::config();
    if !cfg.is_object() { cfg = serde_json::json!({}); }
    let mut list: Vec<Value> = cfg["disabledExtensions"].as_array().cloned().unwrap_or_default();
    list.retain(|v| v.as_str() != Some(id));
    if !on { list.push(Value::String(id.into())); }
    cfg["disabledExtensions"] = Value::Array(list);
    paths::write_atomic(&paths::config_file(), serde_json::to_string_pretty(&cfg).unwrap_or_default().as_bytes()).map_err(|e| e.to_string())
}
