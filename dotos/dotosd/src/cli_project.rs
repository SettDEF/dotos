//! `dotos project <verb>` (CLI.md §6): which folders Dotos takes on, and how.
//!
//!   list [--tracked|--discovered|--new|--ignored|--all]   (default: tracked)
//!   show NAME                      every option, and where its value came from
//!   track NAME|PATH…  ·  untrack NAME…
//!   ignore PATTERN…   ·  unignore PATTERN…      names or paths, `*` matches anything
//!   set NAME key=value…  ·  unset NAME key…      any key; known ones are checked
//!   mode [all|ask|manual]
//!   roots [add|rm PATH]
//!
//! Every verb that changes something takes --dry-run (says it, saves nothing).

use crate::{paths, project_conf as pc, projects};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

pub const USAGE: &str = "\
dotos project — which folders Dotos takes on, and how

  dotos project list [--tracked|--discovered|--new|--ignored|--all]
  dotos project show NAME
  dotos project track NAME|PATH…          take it on (its tasks, page, git state)
  dotos project untrack NAME…
  dotos project ignore PATTERN…           never look at it (*-old, node_modules, ~/tmp/*)
  dotos project unignore PATTERN…
  dotos project set NAME key=value…       git github todos sync share agents notify pin color alias, or any key
  dotos project unset NAME key…
  dotos project mode [all|ask|manual]     all: every project found · ask: new ones wait · manual: only tracked
  dotos project roots [add|rm PATH]       where projects are found

  --dry-run   say what would change, save nothing      --json   machine-readable
";

fn name_of(dir: &Path) -> String {
    dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()
}

fn state(c: &pc::Conf, dir: &Path) -> &'static str {
    if c.is_ignored(dir) { "ignored" } else if c.is_tracked(dir) { "tracked" } else { "new" }
}

/// A NAME among the found projects, or a PATH to a folder (also one outside the roots).
fn resolve(arg: &str) -> Option<PathBuf> {
    let p = paths::expand(arg);
    if arg.contains('/') && p.is_dir() {
        return std::fs::canonicalize(&p).ok().or(Some(p));
    }
    projects::find(arg)
}

fn row(c: &pc::Conf, dir: &Path) -> Value {
    let opts: serde_json::Map<String, Value> = pc::KEYS.iter().map(|(k, _, _)| (k.to_string(), json!(c.get(dir, k).0))).collect();
    json!({ "name": name_of(dir), "path": dir.to_string_lossy(), "state": state(c, dir), "options": opts })
}

fn save(c: &pc::Conf, dry: bool, said: &str) -> i32 {
    if dry {
        println!("would: {said} (--dry-run: nothing saved)");
        return 0;
    }
    match pc::save(c) {
        Ok(()) => { println!("{said}"); 0 }
        Err(e) => { eprintln!("dotos project: {e}"); 1 }
    }
}

/// config.json "projectRoots", started from what is used now so `add` keeps the defaults.
fn set_roots(f: impl FnOnce(&mut Vec<String>), dry: bool, said: &str) -> i32 {
    let mut cfg = paths::config();
    if !cfg.is_object() {
        cfg = json!({});
    }
    let mut roots: Vec<String> = cfg["projectRoots"].as_array().map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_else(|| paths::project_roots().iter().map(|p| p.to_string_lossy().to_string()).collect());
    f(&mut roots);
    if dry {
        println!("would: {said}: {} (--dry-run: nothing saved)", roots.join(", "));
        return 0;
    }
    cfg["projectRoots"] = json!(roots);
    let _ = std::fs::create_dir_all(paths::config_dir());
    match std::fs::write(paths::config_file(), serde_json::to_string_pretty(&cfg).unwrap_or_default()) {
        Ok(()) => { println!("{said}: {}", roots.join(", ")); 0 }
        Err(e) => { eprintln!("dotos project: {e}"); 1 }
    }
}

pub fn run(rest: &[String], json: bool) -> i32 {
    let dry = rest.iter().any(|a| a == "--dry-run" || a == "-n");
    let args: Vec<&str> = rest.iter().map(String::as_str).filter(|a| !a.starts_with('-')).collect();
    let has = |f: &str| rest.iter().any(|a| a == f);
    if has("--help") || has("-h") {
        print!("{USAGE}");
        return 0;
    }
    let mut c = pc::load();
    match args.first().copied() {
        None | Some("list") | Some("ls") => {
            let all: Vec<PathBuf> = projects::discover_all();
            let ignored: Vec<PathBuf> = if has("--ignored") || has("--all") {
                // ignored ones are not in discover_all: the roots' folders that match
                paths::project_roots().iter().filter_map(|r| std::fs::read_dir(r).ok()).flatten().flatten()
                    .map(|e| e.path()).filter(|p| p.is_dir() && c.is_ignored(p)).collect()
            } else { vec![] };
            let pick: Vec<&PathBuf> = if has("--all") { all.iter().chain(ignored.iter()).collect() }
                else if has("--ignored") { ignored.iter().collect() }
                else if has("--discovered") { all.iter().collect() }
                else if has("--new") { all.iter().filter(|d| !c.is_tracked(d)).collect() }
                else { all.iter().filter(|d| c.is_tracked(d)).collect() };
            if json {
                println!("{}", Value::Array(pick.iter().map(|d| row(&c, d)).collect()));
            } else if pick.is_empty() {
                println!("none (mode: {}; `dotos project list --discovered` shows what was found)", c.mode);
            } else {
                // a pipe that closes early (| head) ends the list, not the program
                use std::io::Write;
                let mut out = std::io::stdout().lock();
                for d in &pick {
                    // only what differs from the default: the rest is noise
                    let flags: Vec<String> = pc::KEYS.iter().filter_map(|(k, def, _)| { let v = c.get(d, k).0; (v != *def).then(|| format!("{k} {v}")) }).collect();
                    if writeln!(out, "{:<8} {:<20} {}{}", state(&c, d), name_of(d), d.display(), if flags.is_empty() { String::new() } else { format!("   ({})", flags.join(", ")) }).is_err() {
                        return 0;
                    }
                }
                if !has("--new") && c.mode == "ask" {
                    let n = all.iter().filter(|d| !c.is_tracked(d)).count();
                    if n > 0 { println!("\n{n} new: dotos project list --new, then dotos project track NAME"); }
                }
            }
            0
        }
        Some("show") => {
            let Some(dir) = args.get(1).and_then(|a| resolve(a)) else { eprintln!("dotos project show NAME"); return 3 };
            if json {
                let origin: serde_json::Map<String, Value> = pc::KEYS.iter().map(|(k, _, _)| (k.to_string(), json!(c.get(&dir, k).1))).collect();
                let mut v = row(&c, &dir);
                v["origin"] = Value::Object(origin);
                v["extra"] = json!(c.settings.get(&name_of(&dir)).map(|m| m.iter().filter(|(k, _)| !pc::KEYS.iter().any(|x| x.0 == k.as_str())).collect::<std::collections::BTreeMap<_, _>>()));
                println!("{v}");
                return 0;
            }
            println!("{}  ({})\n{}\n", name_of(&dir), state(&c, &dir), dir.display());
            for (k, _, choices) in pc::KEYS {
                let (v, from) = c.get(&dir, k);
                println!("  {:<8} {:<10} {:<14} {}", k, if v.is_empty() { "-" } else { &v }, from, choices);
            }
            if let Some(m) = c.settings.get(&name_of(&dir)) {
                for (k, v) in m.iter().filter(|(k, _)| !pc::KEYS.iter().any(|x| x.0 == k.as_str())) {
                    println!("  {:<8} {:<10} projects.json", k, v);
                }
            }
            0
        }
        Some("track") | Some("untrack") => {
            let on = args[0] == "track";
            let mut said = Vec::new();
            for a in &args[1..] {
                let Some(dir) = resolve(a) else { eprintln!("dotos project: no project '{a}' (dotos project list --discovered)"); return 3 };
                let name = name_of(&dir);
                c.tracked.retain(|t| !t.eq_ignore_ascii_case(&name));
                if on {
                    c.tracked.push(name.clone());
                    // a folder outside the roots is taken on by its path
                    if !projects::discover_all().contains(&dir) {
                        let mut cfg = paths::config();
                        if !cfg.is_object() { cfg = json!({}); }
                        let mut extra: Vec<Value> = cfg["projects"].as_array().cloned().unwrap_or_default();
                        if !extra.iter().any(|v| v.as_str() == Some(&dir.to_string_lossy())) { extra.push(json!(dir.to_string_lossy())); }
                        cfg["projects"] = Value::Array(extra);
                        if !dry { let _ = std::fs::write(paths::config_file(), serde_json::to_string_pretty(&cfg).unwrap_or_default()); }
                    }
                }
                said.push(name);
            }
            if said.is_empty() { eprintln!("dotos project {} NAME|PATH…", args[0]); return 2 }
            if !on && c.mode == "all" {
                eprintln!("note: mode is all, so every project found is tracked anyway; `dotos project mode manual` (or ignore it)");
            }
            save(&c, dry, &format!("{} {}", if on { "tracking" } else { "not tracking" }, said.join(", ")))
        }
        Some("ignore") | Some("unignore") | Some("exclude") => {
            let on = args[0] != "unignore";
            if args.len() < 2 { eprintln!("dotos project {} PATTERN…", args[0]); return 2 }
            for p in &args[1..] {
                c.ignored.retain(|x| x != p);
                if on { c.ignored.push(p.to_string()); }
            }
            save(&c, dry, &format!("{} {}", if on { "ignoring" } else { "no longer ignoring" }, args[1..].join(", ")))
        }
        Some("set") | Some("unset") => {
            let Some(dir) = args.get(1).and_then(|a| resolve(a)) else { eprintln!("dotos project {} NAME key…", args[0]); return 3 };
            let name = name_of(&dir);
            let m = c.settings.entry(name.clone()).or_default();
            let mut said = Vec::new();
            for kv in &args[2..] {
                if args[0] == "unset" {
                    m.remove(*kv);
                    said.push(format!("{kv} back to its default"));
                    continue;
                }
                let Some((k, v)) = kv.split_once('=') else { eprintln!("dotos project set NAME key=value… ('{kv}' has no =)"); return 2 };
                if let Err(e) = pc::check(k, v) { eprintln!("dotos project: {e}"); return 2 }
                m.insert(k.to_string(), v.to_string());
                said.push(format!("{k}={v}"));
            }
            if c.settings.get(&name).is_some_and(|m| m.is_empty()) { c.settings.remove(&name); }
            if said.is_empty() { eprintln!("dotos project {} NAME key…", args[0]); return 2 }
            save(&c, dry, &format!("{name}: {}", said.join(", ")))
        }
        Some("mode") => match args.get(1) {
            None => { println!("{}", c.mode); 0 }
            Some(m) if pc::MODES.contains(m) => { c.mode = m.to_string(); save(&c, dry, &format!("mode {m}")) }
            Some(m) => { eprintln!("dotos project mode: {m}? all, ask or manual"); 2 }
        },
        Some("roots") => match (args.get(1).copied(), args.get(2)) {
            (None, _) | (Some("list"), _) => { for r in paths::project_roots() { println!("{}", r.display()); } 0 }
            (Some("add"), Some(p)) => { let p = p.to_string(); set_roots(|r| if !r.contains(&p) { r.push(p.clone()) }, dry, "roots") }
            (Some("rm"), Some(p)) => { let p = p.to_string(); set_roots(|r| r.retain(|x| *x != p), dry, "roots") }
            _ => { eprintln!("dotos project roots [add|rm PATH]"); 2 }
        },
        Some("help") => { print!("{USAGE}"); 0 }
        Some(v) => { eprintln!("dotos project: no verb '{v}'\n\n{USAGE}"); 2 }
    }
}
