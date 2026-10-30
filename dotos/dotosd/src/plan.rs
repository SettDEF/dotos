//! What to do with the tasks beyond listing them: what is ready, how the day
//! fits, how estimates held up, what has gone stale, and the week in review.

use crate::{agents, model, ops, pages, paths, projects, timew};
use chrono::{Datelike, Duration, Local, NaiveDate};
use icalcore::store::Store;
use icalcore::todo::Todo;
use serde_json::{json, Value};

fn fmt_min(m: i64) -> String {
    let m = m.max(0);
    if m < 60 { format!("{m}m") } else if m % 60 == 0 { format!("{}h", m / 60) } else { format!("{}h{:02}", m / 60, m % 60) }
}

// ── dependencies ───────────────────────────────────────────────────────────

pub fn open_blockers<'a>(t: &Todo, all: &'a [Todo]) -> Vec<&'a Todo> {
    model::get_all(t, "BLOCKED").iter().filter_map(|u| all.iter().find(|x| &x.uid == u && x.is_open())).collect()
}

/// Open, triaged, not waiting, and nothing open in its way.
pub fn is_ready(t: &Todo, all: &[Todo]) -> bool {
    t.is_open()
        && matches!(model::state(t), model::State::Todo | model::State::Doing)
        && open_blockers(t, all).is_empty()
}

/// Would making `blocker` a blocker of `task` close a loop?
pub fn would_cycle(all: &[Todo], task: &str, blocker: &str) -> bool {
    let mut seen = std::collections::HashSet::new();
    let mut stack = vec![blocker.to_string()];
    while let Some(u) = stack.pop() {
        if u == task { return true; }
        if !seen.insert(u.clone()) { continue; }
        if let Some(t) = all.iter().find(|t| t.uid == u) { stack.extend(model::get_all(t, "BLOCKED")); }
    }
    false
}

// ── the day ────────────────────────────────────────────────────────────────

pub fn plan(store: &Store, date: NaiveDate, hours: Option<f64>, json_out: bool) -> Result<(), String> {
    let cfg = paths::config();
    let today = ops::today();
    let all = store.load_todos();
    let default_est = cfg["defaultEstimate"].as_i64().unwrap_or(30);
    let hours = hours.or(cfg["workHours"].as_f64()).unwrap_or(6.0);
    let tracked = if date == today { timew::summary().today_s / 60 } else { 0 };
    let capacity = ((hours * 60.0) as i64 - tracked).max(0);

    let mut cand: Vec<&Todo> = all.iter()
        .filter(|t| is_ready(t, &all) && (model::state(t) == model::State::Doing || t.due_date().is_some_and(|d| d <= date)))
        .collect();
    let rank = |t: &Todo| {
        let timed = !t.due_all_day && t.due.is_some_and(|d| d.date() == date);
        let pri = if t.priority == 0 { 5 } else { t.priority };
        // a hand-set order (dragged in the window) wins over the automatic one, within the untimed tasks
        let manual = model::get(t, "ORDER").and_then(|v| v.parse::<i64>().ok()).unwrap_or(i64::MAX);
        (model::state(t) != model::State::Doing, !timed, t.due.filter(|_| timed), manual, t.due_date().map_or(true, |d| d >= date), pri, t.summary.to_lowercase())
    };
    cand.sort_by_key(|t| rank(t));

    let (mut cum, mut unestimated) = (0i64, 0);
    let items: Vec<Value> = cand.iter().map(|t| {
        let e = model::get(t, "ESTIMATE").and_then(|v| v.parse::<i64>().ok()).filter(|e| *e > 0);
        if e.is_none() { unestimated += 1; }
        let est = e.unwrap_or(default_est);
        cum += est;
        let mut v = serde_json::to_value(model::view(t, today)).unwrap_or(Value::Null);
        v["est_min"] = json!(est);
        v["est_guess"] = json!(e.is_none());
        v["cum_min"] = json!(cum);
        v["fits"] = json!(cum <= capacity);
        v
    }).collect();
    let over = (cum - capacity).max(0);

    if json_out {
        println!("{}", json!({ "date": date.to_string(), "capacity_min": capacity, "tracked_min": tracked, "planned_min": cum,
            "over_min": over, "unestimated": unestimated, "work_start": cfg["workStart"].as_f64().unwrap_or(9.0), "hours": hours, "items": items }));
        return Ok(());
    }
    println!("{}  ·  room for {} ({} workday{})", date.format("%a %-d %b"), fmt_min(capacity), fmt_min((hours * 60.0) as i64),
        if tracked > 0 { format!(", {} already tracked", fmt_min(tracked)) } else { String::new() });
    if items.is_empty() { println!("  nothing ready for this day"); return Ok(()); }
    let mut marked = false;
    for it in &items {
        if !it["fits"].as_bool().unwrap_or(true) && !marked {
            println!("  ── over capacity: push or drop ──");
            marked = true;
        }
        println!("  {:>6} {:>5}{} {}", fmt_min(it["cum_min"].as_i64().unwrap_or(0)), fmt_min(it["est_min"].as_i64().unwrap_or(0)),
            if it["est_guess"] == true { "?" } else { " " }, it["title"].as_str().unwrap_or(""));
    }
    println!("planned {} of {}{}{}", fmt_min(cum), fmt_min(capacity),
        if over > 0 { format!(" — over by {}", fmt_min(over)) } else { String::new() },
        if unestimated > 0 { format!("   ({unestimated} without an estimate, counted as {default_est}m)") } else { String::new() });
    Ok(())
}

// ── how estimates held up ──────────────────────────────────────────────────

pub fn review(store: &Store, days: i64, json_out: bool) -> Result<(), String> {
    let cutoff = Local::now().naive_local() - Duration::days(days);
    let tracked = timew::tracked_by_task(":year");
    let rows: Vec<Value> = store.load_todos().iter()
        .filter(|t| !t.is_open() && t.completed.is_some_and(|c| c > cutoff))
        .filter_map(|t| {
            let est = model::get(t, "ESTIMATE").and_then(|v| v.parse::<i64>().ok()).filter(|e| *e > 0)?;
            let tr = *tracked.get(&t.uid)? / 60;
            (tr > 0).then(|| json!({ "uid": t.uid, "title": t.summary, "project": model::get(t, "PROJECT").unwrap_or_default(),
                "est_min": est, "tracked_min": tr, "ratio": tr as f64 / est as f64 }))
        }).collect();
    let (se, st) = rows.iter().fold((0, 0), |a, r| (a.0 + r["est_min"].as_i64().unwrap_or(0), a.1 + r["tracked_min"].as_i64().unwrap_or(0)));
    let mut ratios: Vec<f64> = rows.iter().filter_map(|r| r["ratio"].as_f64()).collect();
    ratios.sort_by(|a, b| a.total_cmp(b));
    let median = ratios.get(ratios.len() / 2).copied();
    let mut by_project: std::collections::BTreeMap<String, (i64, i64)> = Default::default();
    for r in &rows {
        let e = by_project.entry(r["project"].as_str().unwrap_or("").to_string()).or_default();
        e.0 += r["est_min"].as_i64().unwrap_or(0);
        e.1 += r["tracked_min"].as_i64().unwrap_or(0);
    }
    if json_out {
        println!("{}", json!({ "days": days, "tasks": rows, "est_min": se, "tracked_min": st, "median_ratio": median,
            "projects": by_project.iter().map(|(p, (e, t))| json!({ "project": p, "est_min": e, "tracked_min": t })).collect::<Vec<_>>() }));
        return Ok(());
    }
    if rows.is_empty() {
        println!("No finished task in the last {days} days has both an estimate (~30m) and tracked time.");
        return Ok(());
    }
    for r in &rows {
        println!("  {:>5} est  {:>5} real  {:>5.1}×  {}", fmt_min(r["est_min"].as_i64().unwrap_or(0)), fmt_min(r["tracked_min"].as_i64().unwrap_or(0)),
            r["ratio"].as_f64().unwrap_or(0.0), r["title"].as_str().unwrap_or(""));
    }
    println!("\n{} tasks · estimated {} · took {} · median {:.1}×", rows.len(), fmt_min(se), fmt_min(st), median.unwrap_or(1.0));
    for (p, (e, t)) in &by_project {
        if !p.is_empty() { println!("  +{p:<16} est {:>5}  real {:>5}", fmt_min(*e), fmt_min(*t)); }
    }
    if let Some(m) = median.filter(|m| *m > 1.25 || *m < 0.8) {
        println!("\nYour estimates run {} by about {:.0}% — multiply by {:.1} when planning.", if m > 1.0 { "short" } else { "long" }, (m - 1.0).abs() * 100.0, m);
    }
    Ok(())
}

// ── search ─────────────────────────────────────────────────────────────────

fn hit(hay: &str, words: &[String]) -> bool {
    let l = hay.to_lowercase();
    words.iter().all(|w| l.contains(w))
}

pub fn find(store: &Store, query: &str, json_out: bool) -> Result<(), String> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() { return Err("find WHAT".into()); }
    let today = ops::today();
    let tasks: Vec<Value> = store.load_todos().iter()
        .filter(|t| hit(&format!("{} {} {} {}", t.summary, t.description, t.categories.join(" "), model::get(t, "PROJECT").unwrap_or_default()), &words))
        .take(50).map(|t| serde_json::to_value(model::view(t, today)).unwrap_or(Value::Null)).collect();
    let pgs: Vec<Value> = pages::all().iter().filter_map(|p| {
        let body = std::fs::read_to_string(&p.path).unwrap_or_default();
        if !hit(&format!("{}\n{}", p.title, body), &words) { return None; }
        let line = body.lines().find(|l| hit(l, &words)).unwrap_or("").trim().chars().take(140).collect::<String>();
        Some(json!({ "id": p.id, "title": p.title, "kind": p.kind, "line": line }))
    }).take(50).collect();
    let events: Vec<Value> = crate::log::read(500).into_iter().rev().filter(|e| hit(e["title"].as_str().unwrap_or(""), &words)).take(10).collect();
    if json_out {
        println!("{}", json!({ "tasks": tasks, "pages": pgs, "log": events }));
        return Ok(());
    }
    for t in &tasks { println!("task    {}  {}", t["uid"].as_str().unwrap_or("").chars().take(8).collect::<String>(), t["title"].as_str().unwrap_or("")); }
    for p in &pgs { println!("{:<7} {}  {}", p["kind"].as_str().unwrap_or(""), p["id"].as_str().unwrap_or(""), p["line"].as_str().unwrap_or("")); }
    for e in &events { println!("log     {} {}", e["op"].as_str().unwrap_or(""), e["title"].as_str().unwrap_or("")); }
    if tasks.is_empty() && pgs.is_empty() && events.is_empty() { println!("nothing for “{query}”"); }
    Ok(())
}

// ── abandoned work ─────────────────────────────────────────────────────────

pub fn stale(store: &Store, days: i64, json_out: bool) -> Result<(), String> {
    let now = chrono::Utc::now().timestamp();
    let today = ops::today();
    let all = store.load_todos();
    let mut rows: Vec<Value> = Vec::new();
    for dir in projects::discover() {
        let p = projects::load(&dir, true);
        let mut why: Vec<String> = Vec::new();
        let mut score = 0;
        let idle = p.git.as_ref().filter(|g| g.last_time > 0).map(|g| (now - g.last_time).max(0) / 86400);
        if let Some(g) = &p.git {
            if g.dirty > 0 && g.dirty_days as i64 >= days {
                why.push(format!("{} files uncommitted for {} days", g.dirty, g.dirty_days));
                score += g.dirty_days as i64;
            }
            if p.doc_open > 0 && idle.is_some_and(|i| i >= days * 2) {
                why.push(format!("{} open lines in TASKS.md, no commit in {} days", p.doc_open, idle.unwrap_or(0)));
                score += idle.unwrap_or(0) / 2;
            }
        }
        let overdue = all.iter().filter(|t| t.is_overdue(today) && model::get(t, "PROJECT").is_some_and(|x| x.eq_ignore_ascii_case(&p.name))).count();
        if overdue > 0 {
            why.push(format!("{overdue} overdue task{}", if overdue == 1 { "" } else { "s" }));
            score += overdue as i64 * 3;
        }
        if !why.is_empty() {
            rows.push(json!({ "name": p.name, "path": p.path, "idle_days": idle, "reasons": why, "score": score }));
        }
    }
    rows.sort_by_key(|r| std::cmp::Reverse(r["score"].as_i64().unwrap_or(0)));
    if json_out { println!("{}", Value::Array(rows)); return Ok(()); }
    if rows.is_empty() { println!("Nothing stale (threshold {days} days)."); }
    for r in rows.iter().take(12) {
        println!("{:<20} {}", r["name"].as_str().unwrap_or(""),
            r["reasons"].as_array().map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(" · ")).unwrap_or_default());
    }
    Ok(())
}

// ── agent cards left behind ────────────────────────────────────────────────

/// Cards still "doing" for an agent session that is gone → back to todo
/// (or done, with `close`). Returns what it changed.
pub fn reconcile(store: &Store, dry: bool, close: bool) -> Result<Vec<String>, String> {
    let live: std::collections::HashSet<String> = agents::list_all().iter()
        .filter(|a| a["state"] != "ended").filter_map(|a| a["id"].as_str().map(String::from)).collect();
    let mut done = Vec::new();
    for t in store.load_todos() {
        if model::state(&t) != model::State::Doing { continue; }
        let ids: Vec<String> = model::get_all(&t, "LINK").into_iter().filter_map(|l| l.strip_prefix("agent:").map(String::from)).collect();
        if ids.is_empty() || ids.iter().any(|i| live.contains(i)) { continue; }
        done.push(t.summary.clone());
        if dry { continue; }
        std::env::set_var("DOTOS_WHO", "reconcile");
        ops::set_state(store, &t.uid, if close { "done" } else { "todo" }, None, false)?;
        std::env::remove_var("DOTOS_WHO");
    }
    Ok(done)
}

// ── the week ───────────────────────────────────────────────────────────────

pub fn week(store: &Store, stdout: bool) -> Result<(), String> {
    let today = ops::today();
    let monday = today - Duration::days(today.weekday().num_days_from_monday() as i64);
    let (from, to) = (monday.and_hms_opt(0, 0, 0).unwrap_or_default(), (monday + Duration::days(7)).and_hms_opt(0, 0, 0).unwrap_or_default());
    let all = store.load_todos();
    let finished: Vec<&Todo> = all.iter().filter(|t| t.completed.is_some_and(|c| c >= from && c < to)).collect();
    let slipped: Vec<&Todo> = all.iter().filter(|t| t.is_open() && t.due_date().is_some_and(|d| d >= monday && d < today)).collect();
    let time = timew::summary();
    let iso = today.iso_week();
    let title = format!("Week {} · {}", iso.week(), iso.year());
    let mut body = format!("# {title}\n\n{} – {}\n\n## Done ({})\n", monday.format("%-d %b"), (monday + Duration::days(6)).format("%-d %b"), finished.len());
    for t in &finished { body.push_str(&format!("- [x] {}\n", t.summary)); }
    body.push_str(&format!("\n## Slipped ({})\n", slipped.len()));
    for t in &slipped { body.push_str(&format!("- [ ] {} (due {})\n", t.summary, t.due_date().map(|d| d.format("%a").to_string()).unwrap_or_default())); }
    body.push_str(&format!("\n## Time\n{} tracked", fmt_min(time.week_s / 60)));
    let mut by: Vec<(&String, &i64)> = time.by_project_week.iter().collect();
    by.sort_by_key(|(_, s)| std::cmp::Reverse(**s));
    for (p, s) in by { body.push_str(&format!("\n- +{p}: {}", fmt_min(*s / 60))); }
    body.push_str("\n\n## Commits\n");
    for dir in projects::discover() {
        let p = projects::load(&dir, true);
        if let Some(g) = p.git.filter(|g| g.commits_week > 0) { body.push_str(&format!("- {}: {}\n", p.name, g.commits_week)); }
    }
    body.push_str("\n## Next week\n\n");
    if stdout { print!("{body}"); return Ok(()); }
    let path = paths::pages_dir().join(format!("weekly-{}-w{:02}.md", iso.year(), iso.week()));
    let text = format!("---\ntitle: {title}\ntags: weekly\n---\n{body}");
    // rewritten as the week goes on, but "Next week" is yours: keep what is under it
    let keep = std::fs::read_to_string(&path).ok().and_then(|old| old.split_once("## Next week\n").map(|(_, r)| r.to_string()));
    let text = match keep { Some(k) if !k.trim().is_empty() => format!("{}{k}", text.trim_end_matches('\n').to_string() + "\n\n"), _ => text };
    paths::write_atomic(&path, text.as_bytes()).map_err(|e| e.to_string())?;
    println!("{}", path.display());
    Ok(())
}

// ── in and out ─────────────────────────────────────────────────────────────

pub fn export(store: &Store, format: &str, file: Option<&str>) -> Result<(), String> {
    let all = store.load_todos();
    let text = match format {
        "ics" => icalcore::todo::serialize(&all, "dotos"),
        "json" => serde_json::to_string_pretty(&all.iter().map(|t| serde_json::to_value(model::view(t, ops::today())).unwrap_or(Value::Null)).collect::<Vec<_>>()).unwrap_or_default(),
        "md" => all.iter().map(|t| format!("- [{}] {}{}{}", if t.is_open() { " " } else { "x" }, t.summary,
            t.due.map(|d| format!("  @{}", d.format("%Y-%m-%d"))).unwrap_or_default(), t.categories.iter().map(|c| format!(" #{c}")).collect::<String>())).collect::<Vec<_>>().join("\n") + "\n",
        other => return Err(format!("export format: ics, json or md, not '{other}'")),
    };
    match file { Some(f) => std::fs::write(f, text).map_err(|e| e.to_string()), None => { print!("{text}"); Ok(()) } }
}

/// Reads an .ics file; tasks whose uid already exists are left alone.
pub fn import(store: &Store, file: &str, list: &str) -> Result<String, String> {
    let text = std::fs::read_to_string(file).map_err(|e| format!("{file}: {e}"))?;
    let have: std::collections::HashSet<String> = store.load_todos().into_iter().map(|t| t.uid).collect();
    let (mut added, mut skipped) = (0, 0);
    for t in icalcore::todo::parse(&text, list) {
        if have.contains(&t.uid) { skipped += 1; continue; }
        store.save_todo(&t).map_err(|e| e.to_string())?;
        ops::after_change("add", &t, None);
        added += 1;
    }
    store.reindex();
    Ok(format!("imported {added} tasks, {skipped} already there"))
}

/// The store, versioned: a git repo in the data folder, one commit per run that changed anything.
pub fn backup() -> Result<String, String> {
    let dir = paths::data_dir();
    let git = |args: &[&str]| std::process::Command::new("git").arg("-C").arg(&dir).args(args).output().map_err(|e| e.to_string());
    if !dir.join(".git").exists() {
        git(&["init", "-q"])?;
        let _ = std::fs::write(dir.join(".gitignore"), ".index.json\n*.tmp~\n");
    }
    git(&["add", "-A"])?;
    let dirty = git(&["status", "--porcelain"])?;
    if dirty.stdout.is_empty() { return Ok("nothing changed".into()); }
    let out = git(&["-c", "user.name=dotos", "-c", "user.email=dotos@localhost", "commit", "-q", "-m", &format!("dotos backup {}", Local::now().format("%Y-%m-%d %H:%M"))])?;
    if out.status.success() { Ok(format!("committed in {}", dir.display())) } else { Err(String::from_utf8_lossy(&out.stderr).trim().to_string()) }
}


// ── the numbers behind the Insights page ──────────────────────────────────

pub fn stats(store: &Store, days: i64) -> Value {
    let today = ops::today();
    let all = store.load_todos();
    // twice the period: the second half is the one before it, for comparison
    let total = days * 2;
    let labels_all: Vec<String> = (0..total).map(|i| (today - Duration::days(total - 1 - i)).format("%Y-%m-%d").to_string()).collect();
    let count = |pick: &dyn Fn(&Todo) -> Option<chrono::NaiveDateTime>| -> Vec<usize> {
        labels_all.iter().map(|l| all.iter().filter(|t| pick(t).is_some_and(|d| d.format("%Y-%m-%d").to_string() == *l)).count()).collect()
    };
    let done_all = count(&|t| if t.is_open() { None } else { t.completed });
    let created_all = count(&|t| t.created);
    let tracked_all = timew::per_day(total);
    let n = days as usize;
    let tracked: Vec<std::collections::HashMap<String, i64>> = labels_all.iter().map(|l| tracked_all.get(l).cloned().unwrap_or_default()).collect();
    let sum_tracked = |r: &[std::collections::HashMap<String, i64>]| -> i64 { r.iter().map(|d| d.values().sum::<i64>()).sum() };
    let (prev_t, cur_t) = tracked.split_at(n);

    let per_task = timew::tracked_by_task(":year");
    let cutoff = Local::now().naive_local() - Duration::days(days.max(90));
    let estimates: Vec<Value> = all.iter().filter(|t| !t.is_open() && t.completed.is_some_and(|c| c > cutoff)).filter_map(|t| {
        let est = model::get(t, "ESTIMATE").and_then(|v| v.parse::<i64>().ok()).filter(|e| *e > 0)?;
        let tr = *per_task.get(&t.uid)? / 60;
        (tr > 0).then(|| json!({ "title": t.summary, "project": model::get(t, "PROJECT").unwrap_or_default(), "est_min": est, "tracked_min": tr }))
    }).collect();

    // per project: time tracked in the period, tasks finished in it, and how the estimates held
    let start = (today - Duration::days(days - 1)).and_hms_opt(0, 0, 0).unwrap_or_default();
    let mut proj: std::collections::BTreeMap<String, (i64, i64, i64, i64)> = Default::default();   // tracked_s, done, est_min, real_min
    for d in cur_t { for (p, s) in d { proj.entry(p.clone()).or_default().0 += s; } }
    for t in all.iter().filter(|t| !t.is_open() && t.completed.is_some_and(|c| c >= start)) {
        proj.entry(model::get(t, "PROJECT").unwrap_or_else(|| "(none)".into())).or_default().1 += 1;
    }
    for e in &estimates {
        let p = e["project"].as_str().filter(|p| !p.is_empty()).unwrap_or("(none)").to_string();
        let r = proj.entry(p).or_default();
        r.2 += e["est_min"].as_i64().unwrap_or(0);
        r.3 += e["tracked_min"].as_i64().unwrap_or(0);
    }
    let mut projects: Vec<Value> = proj.into_iter().map(|(name, (ts, d, e, r))| json!({ "name": name, "tracked_s": ts, "done": d, "est_min": e, "real_min": r })).collect();
    projects.sort_by_key(|p| std::cmp::Reverse(p["tracked_s"].as_i64().unwrap_or(0)));

    let open = all.iter().filter(|t| t.is_open()).count();
    json!({
        "days": &labels_all[n..], "done": &done_all[n..], "created": &created_all[n..], "tracked": cur_t,
        "prev": { "done": done_all[..n].iter().sum::<usize>(), "created": created_all[..n].iter().sum::<usize>(), "tracked_s": sum_tracked(prev_t) },
        "projects": projects, "estimates": estimates, "open": open,
    })
}
