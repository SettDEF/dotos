//! Saved queries as code: `dotos query 'due<7d'` filters tasks, `dotos query save name 'expr'`
//! persists named views into config.json "queries".

use crate::model;
use crate::ops;
use crate::paths;
use icalcore::todo::Todo;
use serde_json::{json, Value};

pub fn run(args: &[String]) -> i32 {
    if args.is_empty() {
        let cfg = paths::config();
        let qs = cfg["queries"].as_array().cloned().unwrap_or_default();
        if qs.is_empty() {
            println!("no saved queries");
            return 0;
        }
        for q in &qs {
            println!("{:<20} {}", q["name"].as_str().unwrap_or("?"), q["expr"].as_str().unwrap_or(""));
        }
        return 0;
    }
    match args[0].as_str() {
        "save" => {
            if args.len() < 3 { eprintln!("query save NAME EXPR"); return 2; }
            let name = &args[1];
            let expr = args[2..].join(" ");
            let mut cfg: Value = paths::config();
            if cfg.is_null() { cfg = json!({}); }
            let mut qs = cfg["queries"].as_array().cloned().unwrap_or_default();
            qs.retain(|q| q["name"].as_str() != Some(name));
            qs.push(json!({ "name": name, "expr": expr }));
            cfg["queries"] = json!(qs);
            if let Err(e) = paths::write_atomic(&paths::config_file(), serde_json::to_string_pretty(&cfg).unwrap_or_default().as_bytes()) {
                eprintln!("query: {e}"); return 1;
            }
            println!("saved query {name}: {expr}");
            0
        }
        "rm" => {
            if args.len() < 2 { eprintln!("query rm NAME"); return 2; }
            let name = &args[1];
            let mut cfg: Value = paths::config();
            if cfg.is_null() { cfg = json!({}); }
            let mut qs = cfg["queries"].as_array().cloned().unwrap_or_default();
            qs.retain(|q| q["name"].as_str() != Some(name));
            cfg["queries"] = json!(qs);
            if let Err(e) = paths::write_atomic(&paths::config_file(), serde_json::to_string_pretty(&cfg).unwrap_or_default().as_bytes()) {
                eprintln!("query: {e}"); return 1;
            }
            println!("removed query {name}");
            0
        }
        _ => {
            let raw = args.join(" ");
            let cfg = paths::config();
            let qs = cfg["queries"].as_array().cloned().unwrap_or_default();
            // "saved queries as code": a saved query's name can be used in
            // place of its expression, and names compose (space = AND, "or" = OR).
            let expr = if let Some(q) = qs.iter().find(|q| q["name"].as_str() == Some(raw.trim())) {
                q["expr"].as_str().unwrap_or(&raw).to_string()
            } else {
                raw.split_whitespace().map(|tok| {
                    qs.iter().find(|q| q["name"].as_str() == Some(tok))
                        .and_then(|q| q["expr"].as_str())
                        .unwrap_or(tok)
                        .to_string()
                }).collect::<Vec<_>>().join(" ")
            };
            let store = match ops::store() { Ok(s) => s, Err(e) => { eprintln!("query: {e}"); return 1; } };
            let _today = ops::today();
            let todos = store.load_todos();
            let mut count = 0;
            for t in &todos { if matches(t, &expr) { println!("{}  {}", t.uid.chars().take(8).collect::<String>(), t.summary); count += 1; } }
            if count == 0 { println!("no tasks match: {expr}"); }
            0
        }
    }
}

fn matches(t: &Todo, expr: &str) -> bool {
    let lower = expr.to_lowercase();
    // "or" composes alternatives; each alternative is an AND of its tokens.
    for alt in lower.split(" or ") {
        let parts: Vec<&str> = alt.split_whitespace().collect();
        if parts.is_empty() { continue; }
        let ok = parts.iter().all(|p| {
            if let Some((k, v)) = p.split_once('=') {
                let field = k.to_uppercase();
                let val = model::get(t, &field).unwrap_or_default().to_lowercase();
                return val.contains(&v.to_lowercase());
            }
            let haystack = format!("{} {} {}", t.summary, t.description, t.categories.join(" ")).to_lowercase();
            haystack.contains(p)
        });
        if ok { return true; }
    }
    false
}