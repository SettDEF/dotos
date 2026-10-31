//! The v2 commands: everything beyond add/done/edit/rm, plus what has to
//! happen after any change (log it, wake the actions, re-index).

use crate::{agents, capture, ext, habits, log, model, pages, paths, projects, timew};
use chrono::{Datelike, Local, NaiveDate, Timelike};
use icalcore::store::{self, Store};
use icalcore::todo::Todo;
use serde_json::{json, Value};

/// Open the default store.
pub fn store() -> Result<Store, String> {
    Ok(Store::open(crate::DOTOS))
}

pub fn today() -> NaiveDate {
    Local::now().date_naive()
}

fn task_json(t: &Todo) -> Value {
    serde_json::to_value(model::view(t, today())).unwrap_or(Value::Null)
}

/// Log, then wake the action extensions. Every write path calls this.
pub fn after_change(op: &str, t: &Todo, before: Option<&Todo>) {
    log::record(op, t, before);
    let event = match op {
        "add" => "added",
        "rm" => "removed",
        "state" => match model::state(t) {
            model::State::Done => "done",
            model::State::Cancelled => "cancelled",
            _ if before.is_some_and(|b| !b.is_open()) => "reopened",
            _ => "state",
        },
        _ => "edited",
    };
    if std::env::var("DOTOS_NO_ACTIONS").is_err() {
        ext::fire(event, &task_json(t));
    }
    // init.lua hooks: on_capture, on_done, on_state_change (and on_agent via agents)
    let hook = match op {
        "add" => Some("on_capture"),
        "state" if model::state(t) == model::State::Done => Some("on_done"),
        "state" => Some("on_state_change"),
        _ => None,
    };
    if let Some(h) = hook {
        crate::lua::fire_hook(h, &serde_json::to_string(&task_json(t)).unwrap_or_default());
    }
}

fn save(store: &Store, op: &str, t: &Todo, before: Option<&Todo>) -> Result<(), String> {
    // in a team: who changed it last travels with the task (X-DOTOS-BY), so peers can tell
    let mut by = t.clone();
    if crate::lan::team().is_some() && crate::log::who() == "user" {
        crate::model::set(&mut by, "BY", Some(&crate::threads::me().handle));
    }
    let t = &by;
    if let Some(b) = before.filter(|b| b.list != t.list) {
        store.delete_todo(b).map_err(|e| e.to_string())?;
    }
    store.save_todo(t).map_err(|e| e.to_string())?;
    after_change(op, t, before);
    store.reindex();
    Ok(())
}

pub(crate) fn find(store: &Store, prefix: &str) -> Result<Todo, String> {
    let todos = store.load_todos();
    store.find_todo_by_prefix(&todos, prefix).cloned()
}

fn print(json_out: bool, v: &Value, line: &str) {
    if json_out { println!("{v}"); } else { println!("{line}"); }
}

// ── capture ────────────────────────────────────────────────────────────────

pub fn capture(store: &Store, line: &str, note: Option<&str>, json_out: bool, default_list: &str) -> Result<(), String> {
    let p = capture::parse(line, today());
    if p.title.trim().is_empty() {
        return Err("nothing to add: the line is only options".into());
    }
    let list = p.list.clone().unwrap_or_else(|| {
        paths::config()["defaultList"].as_str().map(String::from).unwrap_or_else(|| default_list.to_string())
    });
    let mut t = Todo::new(&p.title, &list, &store::new_uid("dotos"));
    if let Some(d) = p.due {
        t.due = Some(d);
        t.due_all_day = !p.due_time;
    }
    if let Some(i) = p.importance() { t.set_importance(i); }
    t.categories = p.tags.clone();
    if let Some(n) = note.filter(|n| !n.trim().is_empty()) { t.description = n.to_string(); }
    if let Some(m) = p.estimate_min { model::set(&mut t, "ESTIMATE", Some(&m.to_string())); }
    if let Some(r) = &p.repeat {
        t.rrule = r.clone();
        if p.repeat_after { model::set(&mut t, "REPEAT", Some("done")); }
    }
    if let Some(pr) = &p.project { model::set(&mut t, "PROJECT", Some(pr)); }
    let origin = std::env::var("DOTOS_WHO").unwrap_or_else(|_| "user".into());
    model::set(&mut t, "ORIGIN", Some(&origin));
    let st = p.state.as_deref().and_then(model::State::parse)
        .unwrap_or(if paths::config()["captureToInbox"].as_bool().unwrap_or(false) { model::State::Inbox } else { model::State::Todo });
    model::set_state(&mut t, st);
    save(store, "add", &t, None)?;
    print(json_out, &task_json(&t), &format!("Added  {}", t.summary));
    Ok(())
}

// ── single-task changes ────────────────────────────────────────────────────

pub fn set_state(store: &Store, id: &str, state: &str, waiting_on: Option<&str>, json_out: bool) -> Result<(), String> {
    let before = find(store, id)?;
    let s = model::State::parse(state).ok_or_else(|| format!("no state '{state}' (inbox todo doing waiting done cancelled)"))?;
    let mut t = before.clone();
    model::set_state(&mut t, s);
    if s == model::State::Waiting {
        model::set(&mut t, "WAITING", waiting_on);
    }
    save(store, "state", &t, Some(&before))?;
    // doing → the timer follows, if that is switched on
    let cfg = paths::config();
    if cfg["trackOnDoing"].as_bool().unwrap_or(false) {
        if s == model::State::Doing {
            let _ = timew::start(&t.uid, &t.summary, &t.list, &model::get(&t, "PROJECT").unwrap_or_default());
        } else if timew::summary().active.is_some_and(|a| a.uid == t.uid) {
            let _ = timew::stop();
        }
    }
    print(json_out, &task_json(&t), &format!("{}  {}", s.name(), t.summary));
    Ok(())
}

/// `dotos set ID key=value …` — the v2 fields the old `edit` has no flag for.
pub fn set_fields(store: &Store, id: &str, pairs: &[String], json_out: bool) -> Result<(), String> {
    let before = find(store, id)?;
    let mut t = before.clone();
    for p in pairs {
        let (k, v) = p.split_once('=').ok_or_else(|| format!("expected key=value, got '{p}'"))?;
        match k {
            "title" => t.summary = v.into(),
            "notes" | "note" => t.description = v.replace("\\n", "\n"),
            "project" => model::set(&mut t, "PROJECT", Some(v)),
            "estimate" => model::set(&mut t, "ESTIMATE", capture::minutes(v).map(|m| m.to_string()).as_deref()),
            "parent" => model::set(&mut t, "PARENT", Some(v)),
            "waiting" => model::set(&mut t, "WAITING", Some(v)),
            "decision" => model::set(&mut t, "DECISION", if v.is_empty() { None } else { Some(v) }),
            "assignee" | "assign" => model::set(&mut t, "ASSIGNEE", if v.is_empty() { None } else { Some(v.trim_start_matches('@')) }),
            "order" => model::set(&mut t, "ORDER", Some(v)),
            "list" => t.list = v.into(),
            "priority" | "pri" => t.set_importance(icalcore::todo::Importance::parse(v).ok_or("priority: high, normal, low, none")?),
            "tags" => t.categories = v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect(),
            "due" => {
                if v.is_empty() {
                    t.due = None;
                    t.due_all_day = false;
                } else {
                    let p = capture::parse(&format!("x @{v}"), today());
                    let d = p.due.ok_or_else(|| format!("cannot read due '{v}'"))?;
                    t.due = Some(d);
                    t.due_all_day = !p.due_time;
                }
            }
            "blocked+" | "blocked" => {
                let b = find(store, v)?;
                if b.uid == t.uid || crate::plan::would_cycle(&store.load_todos(), &t.uid, &b.uid) {
                    return Err(format!("“{}” cannot wait on “{}”: that would loop", t.summary, b.summary));
                }
                let mut l = model::get_all(&t, "BLOCKED");
                if !l.contains(&b.uid) { l.push(b.uid); }
                model::set_all(&mut t, "BLOCKED", &l);
            }
            "blocked-" => {
                let b = find(store, v).map(|b| b.uid).unwrap_or_else(|_| v.to_string());
                let l: Vec<String> = model::get_all(&t, "BLOCKED").into_iter().filter(|x| *x != b).collect();
                model::set_all(&mut t, "BLOCKED", &l);
            }
            "repeat" => match v {
                "" | "none" | "off" => { t.rrule.clear(); model::set(&mut t, "REPEAT", None); }
                _ => {
                    let (rule, after) = crate::recurrence::parse_token(v).ok_or_else(|| format!("cannot read repeat '{v}' (daily, weekly, 3d, mon,thu, +3d …)"))?;
                    t.rrule = rule;
                    model::set(&mut t, "REPEAT", after.then_some("done"));
                }
            },
            "link+" => {
                let mut l = model::get_all(&t, "LINK");
                if !l.iter().any(|x| x == v) { l.push(v.into()); }
                model::set_all(&mut t, "LINK", &l);
            }
            "link-" => {
                let l: Vec<String> = model::get_all(&t, "LINK").into_iter().filter(|x| x != v).collect();
                model::set_all(&mut t, "LINK", &l);
            }
            other => return Err(format!("unknown field '{other}'")),
        }
    }
    save(store, "edit", &t, Some(&before))?;
    print(json_out, &task_json(&t), &format!("Edited {}", t.summary));
    Ok(())
}

/// Push the due date out: "tomorrow", "fri", "+3d", "14:00" (today, later), "2026-11-01".
pub fn snooze(store: &Store, id: &str, when: &str, json_out: bool) -> Result<(), String> {
    let before = find(store, id)?;
    let p = capture::parse(&format!("x @{when}"), today());
    let mut due = p.due.ok_or_else(|| format!("cannot read '{when}'"))?;
    // a bare date keeps the task's own time of day; a bare time keeps its day
    if !p.due_time {
        if let Some(old) = before.due.filter(|_| !before.due_all_day) { due = due.date().and_time(old.time()); }
    }
    let mut t = before.clone();
    t.due = Some(due);
    t.due_all_day = if p.due_time { false } else { before.due_all_day || before.due.is_none() };
    save(store, "edit", &t, Some(&before))?;
    print(json_out, &task_json(&t), &format!("Snoozed to {}  {}", due.format("%a %-d %b %H:%M"), t.summary));
    Ok(())
}

pub fn subtask(store: &Store, parent: &str, line: &str, json_out: bool) -> Result<(), String> {
    let p = find(store, parent)?;
    let mut sub = capture::parse(line, today());
    if sub.project.is_none() { sub.project = model::get(&p, "PROJECT"); }
    let mut t = Todo::new(&sub.title, &p.list, &store::new_uid("dotos"));
    if let Some(d) = sub.due { t.due = Some(d); t.due_all_day = !sub.due_time; }
    if let Some(i) = sub.importance() { t.set_importance(i); }
    t.categories = sub.tags;
    // inherit parent tags
    for tag in &p.categories {
        if !t.categories.contains(tag) { t.categories.push(tag.clone()); }
    }
    if let Some(pr) = sub.project { model::set(&mut t, "PROJECT", Some(&pr)); }
    model::set(&mut t, "PARENT", Some(&p.uid));
    save(store, "add", &t, None)?;
    print(json_out, &task_json(&t), &format!("Added  {}  (under {})", t.summary, p.summary));
    Ok(())
}

// ── time ───────────────────────────────────────────────────────────────────

pub fn track(store: &Store, id: &str) -> Result<(), String> {
    let t = find(store, id)?;
    timew::start(&t.uid, &t.summary, &t.list, &model::get(&t, "PROJECT").unwrap_or_default())?;
    if model::state(&t) != model::State::Doing && t.is_open() {
        let before = t.clone();
        let mut d = t.clone();
        model::set_state(&mut d, model::State::Doing);
        save(store, "state", &d, Some(&before))?;
    }
    println!("Tracking  {}", t.summary);
    Ok(())
}

// ── extensions: syncing sources ────────────────────────────────────────────

/// Run one source and reconcile its items with the tasks it made before.
pub fn sync_source(store: &Store, e: &ext::Ext) -> Result<String, String> {
    let items = ext::run_source(e)?;
    let prefix = format!("ext:{}:", e.id);
    let who = format!("ext:{}", e.id);
    std::env::set_var("DOTOS_WHO", &who);
    let todos = store.load_todos();
    let mine: Vec<&Todo> = todos.iter().filter(|t| model::get(t, "ORIGIN").is_some_and(|o| o.starts_with(&prefix))).collect();
    let (mut added, mut updated, mut closed) = (0, 0, 0);
    let mut seen = std::collections::HashSet::new();
    for it in &items {
        let key = it["key"].as_str().unwrap_or("");
        let origin = format!("{prefix}{key}");
        seen.insert(origin.clone());
        let existing = mine.iter().find(|t| model::get(t, "ORIGIN").as_deref() == Some(origin.as_str()));
        let mut t = match existing {
            Some(t) => (*t).clone(),
            None => {
                let list = it["list"].as_str().map(String::from)
                    .or_else(|| paths::config()["defaultList"].as_str().map(String::from)).unwrap_or_else(|| "personal".into());
                let mut n = Todo::new(it["title"].as_str().unwrap_or(""), &list, &store::new_uid("dotos"));
                model::set(&mut n, "ORIGIN", Some(&origin));
                n
            }
        };
        let before = t.clone();
        t.summary = it["title"].as_str().unwrap_or(&t.summary).to_string();
        if let Some(n) = it["notes"].as_str() { t.description = n.into(); }
        if let Some(p) = it["project"].as_str() { model::set(&mut t, "PROJECT", Some(p)); }
        if let Some(tags) = it["tags"].as_array() { t.categories = tags.iter().filter_map(|x| x.as_str().map(String::from)).collect(); }
        if let Some(pr) = it["priority"].as_str().and_then(icalcore::todo::Importance::parse) { t.set_importance(pr); }
        if let Some(d) = it["due"].as_str() {
            let p = capture::parse(&format!("x @{d}"), today());
            if let Some(due) = p.due { t.due = Some(due); t.due_all_day = !p.due_time; }
        }
        if let Some(u) = it["url"].as_str() {
            let mut l = model::get_all(&t, "LINK");
            if !l.iter().any(|x| x == u) { l.push(u.into()); }
            model::set_all(&mut t, "LINK", &l);
        }
        match existing {
            None => { store.save_todo(&t).map_err(|e| e.to_string())?; after_change("add", &t, None); added += 1; }
            Some(_) if serde_json::to_string(&t).ok() != serde_json::to_string(&before).ok() => {
                store.save_todo(&t).map_err(|e| e.to_string())?; after_change("edit", &t, Some(&before)); updated += 1;
            }
            _ => {}
        }
    }
    for t in mine.iter().filter(|t| t.is_open() && !seen.contains(&model::get(t, "ORIGIN").unwrap_or_default())) {
        let before = (*t).clone();
        let mut d = (*t).clone();
        model::set_state(&mut d, model::State::Done);
        store.save_todo(&d).map_err(|e| e.to_string())?;
        after_change("state", &d, Some(&before));
        closed += 1;
    }
    std::env::remove_var("DOTOS_WHO");
    store.reindex();
    Ok(format!("{}: {} items · {added} new · {updated} changed · {closed} closed", e.name, items.len()))
}

// ── the daemon ─────────────────────────────────────────────────────────────

/// A reminder with Done and Snooze buttons; the click runs the same CLI call the window does.
/// Its own thread: notify-send waits until the notification is dismissed.
fn notify(uid: &str, title: &str, body: &str, urgency: &str) {
    let (uid, title, body, urgency) = (uid.to_string(), title.to_string(), body.to_string(), urgency.to_string());
    std::thread::spawn(move || {
        let out = std::process::Command::new("notify-send")
            .args(["-a", "Dotos", "-i", "dotos", "-u", &urgency, "-t", "30000", "-A", "done=Done", "-A", "snooze=Snooze 1h", &title, &body])
            .output();
        let me = std::env::current_exe().unwrap_or_else(|_| "dotos".into());
        match out.as_ref().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).as_deref() {
            Ok("done") => { let _ = std::process::Command::new(&me).args(["done", &uid]).status(); }
            Ok("snooze") => {
                let later = (Local::now() + chrono::Duration::hours(1)).format("%H:%M").to_string();
                let _ = std::process::Command::new(&me).args(["snooze", &uid, &later]).status();
            }
            _ => {}
        }
    });
}

/// `dotos serve`: run sources on their schedule, remind about due tasks.
pub fn serve(store: &Store) -> ! {
    // in a team: the LAN sync beside the reminders (lan.rs; nothing when there is no team)
    if crate::lan::team().is_some() {
        std::thread::spawn(|| if let Err(e) = crate::lan::run() { eprintln!("dotos serve: lan: {e}"); });
    }
    let state = paths::state_dir().join("serve.json");
    loop {
        let mut st: Value = std::fs::read_to_string(&state).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(json!({}));
        let now = Local::now();
        let epoch = now.timestamp();

        for e in ext::list().into_iter().filter(|e| e.enabled && e.kind == "source") {
            if epoch - e.last_run >= e.every_min as i64 * 60 {
                if let Err(msg) = sync_source(store, &e) {
                    eprintln!("dotos serve: {}: {msg}", e.id);
                }
            }
        }

        // reminders: timed tasks 15 min before; all-day ones once, at the
        // morning hour (default 9), when due today or overdue
        let morning = paths::config()["remindHour"].as_u64().unwrap_or(9) as u32;
        let quiet = std::path::Path::new(&format!("{}/gamemode.active", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())).exists();
        let today = today();
        let mut reminded = st["reminded"].as_object().cloned().unwrap_or_default();
        for t in store.load_todos().iter().filter(|t| t.is_open()) {
            let Some(due) = t.due else { continue };
            let key = format!("{}@{}", t.uid, due);
            if reminded.contains_key(&key) { continue; }
            let fire = if t.due_all_day {
                due.date() <= today && now.hour() >= morning
            } else {
                let mins = (due - now.naive_local()).num_minutes();
                (0..=15).contains(&mins) || (mins < 0 && due.date() == today)
            };
            if fire && !quiet {
                let when = if t.due_all_day { if due.date() < today { "overdue".to_string() } else { "due today".into() } } else { format!("at {}", due.format("%H:%M")) };
                notify(&t.uid, &t.summary, &when, if due.date() < today { "normal" } else { "low" });
                reminded.insert(key, json!(epoch));
            }
        }
        // housekeeping, each at most once a day: park cards of finished agent sessions,
        // this week's review page (Mondays), and a git commit of the store when asked for
        let day = today.to_string();
        if st["housekeeping"].as_str() != Some(day.as_str()) {
            std::env::set_var("DOTOS_WHO", "dotos");
            if let Err(e) = crate::plan::reconcile(store, false, false) { eprintln!("dotos serve: reconcile: {e}"); }
            if now.weekday() == chrono::Weekday::Mon || !paths::pages_dir().join(format!("weekly-{}-w{:02}.md", today.iso_week().year(), today.iso_week().week())).exists() {
                let _ = crate::plan::week(store, false);
            }
            if paths::config()["autoBackup"].as_bool().unwrap_or(false) { let _ = crate::plan::backup(); }
            std::env::remove_var("DOTOS_WHO");
            st["housekeeping"] = json!(day);
        }
        // forget reminders older than two weeks
        reminded.retain(|_, v| epoch - v.as_i64().unwrap_or(0) < 14 * 86400);
        st["reminded"] = Value::Object(reminded);
        let _ = paths::write_atomic(&state, st.to_string().as_bytes());
        // Teams: @mentions of me and tasks assigned to me (also from LAN peers) as notifications
        let mine: Vec<(String, String, String)> = store.load_todos().into_iter().filter(|t| t.is_open()).map(|t| (t.uid.clone(), t.summary.clone(), model::get(&t, "ASSIGNEE").unwrap_or_default())).collect();
        crate::thread_agent::dispatch_remote();
        for (title, body, item) in crate::threads::news(&mine) {
            notify_message(&item, &title, &body);
        }
        std::thread::sleep(std::time::Duration::from_secs(20));
    }
}

// ── the snapshot the window reads ──────────────────────────────────────────

pub fn snapshot(store: &Store, with_git: bool) -> Value {
    let today = today();
    let todos = store.load_todos();
    let cutoff = Local::now().naive_local() - chrono::Duration::days(14);
    let time = timew::summary();
    let agents = agents::list_all();
    let mut tasks: Vec<Value> = todos.iter()
        .filter(|t| t.is_open() || t.completed.map_or(true, |c| c > cutoff))
        .map(|t| {
            let mut v = task_json(t);
            v["tracked_week_s"] = json!(time.by_task_week.get(&t.uid).copied().unwrap_or(0));
            v["tracked_today_s"] = json!(time.by_task_today.get(&t.uid).copied().unwrap_or(0));
            v["blocked"] = json!(!crate::plan::open_blockers(t, &todos).is_empty());
            v["ready"] = json!(crate::plan::is_ready(t, &todos));
            v
        })
        .collect();
    tasks.sort_by(|a, b| {
        let k = |v: &Value| (v["state"] == "done" || v["state"] == "cancelled", v["due"].as_str().unwrap_or("9999").to_string(), v["title"].as_str().unwrap_or("").to_lowercase());
        k(a).cmp(&k(b))
    });

    let mut lists: std::collections::BTreeMap<String, (usize, usize)> = Default::default();
    for t in &todos {
        let e = lists.entry(t.list.clone()).or_default();
        if t.is_open() { e.0 += 1 } else { e.1 += 1 }
    }
    for c in store.calendars() {
        lists.entry(c.name).or_default();
    }

    let pconf = crate::project_conf::load();
    let projects: Vec<Value> = projects::discover().iter().map(|dir| {
        let p = projects::load(dir, with_git);
        let open: Vec<&Todo> = todos.iter().filter(|t| t.is_open() && model::get(t, "PROJECT").is_some_and(|x| x.eq_ignore_ascii_case(&p.name))).collect();
        let overdue = open.iter().filter(|t| t.is_overdue(today)).count();
        let ag: Vec<&Value> = agents::in_dir(&agents, &p.path).into_iter().filter(|a| a["state"] != "ended").collect();
        let needs = ag.iter().filter(|a| a["state"] == "needs_you").count();
        let mut v = serde_json::to_value(&p).unwrap_or(Value::Null);
        v["open"] = json!(open.len());
        v["overdue"] = json!(overdue);
        v["agents"] = json!(ag.len());
        v["agents_need_you"] = json!(needs);
        v["time_week_s"] = json!(time.by_project_week.get(&p.name).copied().unwrap_or(0));
        // one word for the card's dot: attention > stale > active > quiet
        // stale = changes left lying in a project you have been working on
        // (committed in the last two weeks); old dirt in a dormant repo is just quiet
        let recent = p.git.as_ref().is_some_and(|g| chrono::Utc::now().timestamp() - g.last_time < 14 * 86400);
        let dirty_days = p.git.as_ref().map_or(0, |g| if g.dirty > 0 { g.dirty_days } else { 0 });
        v["options"] = json!(crate::project_conf::KEYS.iter().map(|(k, _, _)| (k.to_string(), json!(pconf.get(dir, k).0))).collect::<serde_json::Map<_, _>>());
        v["health"] = json!(if needs > 0 || overdue > 0 { "attention" } else if dirty_days >= 3 && recent { "stale" }
            else if !ag.is_empty() || p.git.as_ref().is_some_and(|g| g.commits_week > 0) { "active" } else { "quiet" });
        v
    }).collect();

    let pages = pages::all();
    let page_tasks: Vec<Value> = pages.iter().flat_map(|pg| pg.tasks.iter().filter(|t| !t.done).map(move |t| json!({
        "page": pg.id, "page_title": pg.title, "line": t.line, "text": t.text, "project": pg.project,
    }))).collect();

    json!({
        "today": today.format("%Y-%m-%d").to_string(),
        "now": Local::now().timestamp(),
        "tasks": tasks,
        "lists": lists.iter().map(|(n, (o, d))| json!({ "name": n, "open": o, "done": d })).collect::<Vec<_>>(),
        "projects": projects,
        // which projects Dotos takes on (the Projects page lets you choose: CLI.md §6)
        "project_mode": pconf.mode.clone(),
        "new_projects": projects::discover_all().iter().filter(|d| !pconf.is_tracked(d))
            .map(|d| json!({ "name": d.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(), "path": d.to_string_lossy() }))
            .collect::<Vec<_>>(),
        "agents": agents,
        "time": time,
        "pages": pages,
        "page_tasks": page_tasks,
        "habits": habits::views(),
        "extensions": ext::list(),
        "log": log::read(40),
        "store": store::path_display(&store.root),
        "config": paths::config(),
    })
}

/// A team message (a mention, an assignment): Open (and a click on it) shows Dotos at the
/// conversation it is in, starting the window when it is not running.
fn notify_message(item: &str, title: &str, body: &str) {
    let (item, title, body) = (item.to_string(), title.to_string(), body.to_string());
    std::thread::spawn(move || {
        let out = std::process::Command::new("notify-send")
            .args(["-a", "Dotos", "-i", "dotos", "-u", "normal", "-t", "30000", "-A", "default=Open", &title, &body])
            .output();
        if !matches!(out.as_ref().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).as_deref(), Ok("open") | Ok("default")) {
            return;
        }
        let home = std::env::var("HOME").unwrap_or_default();
        let qml = format!("{home}/.local/share/dotos-app/gui/dotos.qml");
        let qs = if std::path::Path::new("/usr/bin/qs").exists() { "/usr/bin/qs" } else { "qs" };
        // running: ask it; not running: start it, then ask once it listens
        let ask = || std::process::Command::new(qs).args(["-p", &qml, "ipc", "call", "dotos", "open", &item]).output().is_ok_and(|o| o.status.success());
        if !ask() {
            let _ = std::process::Command::new(format!("{home}/.local/bin/dotos-gui")).spawn();
            for _ in 0..40 {
                std::thread::sleep(std::time::Duration::from_millis(250));
                if ask() { break; }
            }
        }
        // to the front (loom and Hyprland both take this)
        let _ = std::process::Command::new("hyprctl").args(["dispatch", "focuswindow", "class:dotos"]).output();
    });
}
