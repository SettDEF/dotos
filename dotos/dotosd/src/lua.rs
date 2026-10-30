//! init.lua + hooks: load ~/.config/dotos/init.lua, run hooks on events.
//! Hooks: on_capture, on_done, on_agent, on_state_change.
//! Lua receives the event as a JSON string in DOTOS_EVENT env var.

use crate::paths;
use std::process::Command;

pub fn run_init() {
    let path = paths::config_dir().join("init.lua");
    if !path.exists() { return; }
    let _ = Command::new("lua")
        .arg(&path)
        .env("DOTOS_CONFIG_DIR", paths::config_dir().to_string_lossy().to_string())
        .env("DOTOS_DATA_DIR", paths::data_dir().to_string_lossy().to_string())
        .status();
}

pub fn fire_hook(hook: &str, payload: &str) {
    let path = paths::config_dir().join("init.lua");
    if !path.exists() { return; }
    let script = format!(r#"
local ok, init = pcall(dofile, "{path}")
if ok and type(init) == "table" and type(init["{hook}"]) == "function" then
    init["{hook}"](os.getenv("DOTOS_EVENT") or "")
end
"#, path = path.to_string_lossy().replace('\\', "\\\\").replace('"', "\\\""),
       hook = hook);
    let _ = Command::new("lua")
        .arg("-e")
        .arg(&script)
        .env("DOTOS_EVENT", payload)
        .status();
}

pub fn run(args: &[String]) -> i32 {
    if args.is_empty() {
        // run init.lua
        run_init();
        println!("init.lua executed (if present)");
        return 0;
    }
    match args[0].as_str() {
        "init" => { run_init(); 0 }
        "hook" => {
            if args.len() < 2 { eprintln!("lua hook NAME [payload]"); return 2; }
            let hook = &args[1];
            let payload = args.get(2).cloned().unwrap_or_default();
            fire_hook(hook, &payload);
            0
        }
        _ => { eprintln!("lua init|hook"); 2 }
    }
}