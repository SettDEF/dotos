//! dotos — a task list for the ii desktop.
//!
//! One binary: the CLI you type, and the JSON the QML app reads. Tasks are
//! VTODO in a vdir, which is why they reach a phone without anyone writing a
//! phone app — every CalDAV client already reads them.

use chrono::{Duration, NaiveDate, Timelike};
use icalcore::cli::{flag, has, parse_date, parse_when};
use icalcore::store::{Layout, Store};
use icalcore::todo::{Importance, Status, Todo};
use icalcore::{ics, store};

mod agents;
mod capture;
mod commands;
mod diff;
mod ext;
mod git_remote;
mod gitview;
mod graph;
mod layout;
mod link;
mod lua;
mod habits;
mod insight;
mod log;
mod model;
mod ops;
mod pages;
mod paths;
mod plan;
mod projects;
mod query;
mod recurrence;
mod tags;
mod lan;
mod thread_agent;
mod threads;
mod timew;

/// Dotos' own corner of the disk. Kalends names a different one; the library
/// itself knows only the vdir layout.
pub(crate) const DOTOS: Layout = Layout {
    env_var: "DOTOS_HOME",
    app_dir: "dotos",
    sub_dir: "lists",
};

const COMPLETIONS_BASH: &str = r#"# bash completions for dotos
_dotos() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="add done undone edit rm lists status where capture state set sub track stop tracked undo log projects git tag diff project-check agents page journal habits ext snapshot serve plan review find stale week snooze parse export import backup commands completions"
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
}
complete -F _dotos dotos
"#;

const COMPLETIONS_ZSH: &str = r#"#compdef dotos
_dotos() {
    local -a commands
    commands=(
        'add:add a task'
        'done:tick it'
        'undone:untick it'
        'edit:change one'
        'rm:delete'
        'list:open tasks'
        'status:store health'
        'capture:add from one line'
        'state:change state'
        'set:set fields'
        'tag:custom tags'
        'diff:what changed'
        'git:remote git'
        'plan:the day plan'
        'find:search'
        'help:show help'
    )
    _describe 'command' commands
}
compdef _dotos dotos
"#;

const COMPLETIONS_FISH: &str = r#"# fish completions for dotos
complete -c dotos -f -a "add done undone edit rm list status capture state set tag diff git plan find help"
"#;

const DEFAULT_LIST: &str = "personal";

/// Flags that consume the next argument, so that value is never mistaken
/// for a flag of our own.
const VALUE_FLAGS: &[&str] = &[
    "--due", "--pri", "--list", "--note", "--title", "--tag",
    "--on", "--by", "--task", "--project", "--per-week", "--icon",
    "--days", "--hours", "--format", "--date",
];

const TEAM_HELP: &str = "\
dotos — a team on your network (no server, no account)

Add a friend:
  1. once per computer:   dotos me --handle caesar --name Caesar
  2. one person:          dotos lan init \"Our team\"
                          dotos lan code            send the code to the friend
  3. each friend:         dotos lan join CODE
  4. keep Dotos open, or: dotos serve               finds the others, syncs every 20 s

Team:
  dotos team                  the people met so far (me first)
  dotos lan status            the team and its peers;  dotos lan sync  syncs now
  dotos lan share LIST        share a task list (both sides);  unshare LIST stops
  dotos lan leave             leave the team

Talking (ITEM: a task id, project:NAME, page:ID):
  dotos say ITEM TEXT…        a message; @anna mentions, @claude asks your agent,
                              @claude@anna asks the agent on Anna's computer
  dotos thread ITEM           the conversation;  dotos threads  counts per item
  dotos voice ITEM FILE.ogg   a voice message
  dotos task-from ITEM MSG    a message becomes a task (its @mention does it)
  dotos decide ITEM MSG       mark a message as the decision
  dotos catchup [--mark]      what others said since you last looked
  dotos news                  what would notify you now (mentions, assigned)

More: docs/teams.md
";

const USAGE: &str = "\
dotos — tasks

  dotos                       what is due today, and what is overdue
  dotos list [--all]          open tasks; --all includes finished ones
  dotos add TITLE [options]   add a task
  dotos done ID               tick it
  dotos undone ID             untick it
  dotos edit ID [options]     change one
  dotos rm ID                 delete
  dotos lists                 lists and their counts
  dotos status                store health, counts, what is next
  dotos where                 where the store lives

v2
  dotos capture LINE          one line: title @fri 14:00 !high #tag ~30m +project /list >state
  dotos state ID STATE        inbox todo doing waiting done cancelled  [--on WHAT]
  dotos set ID key=value …    title notes project estimate parent waiting due
                              priority tags list link+ link-
  dotos sub ID LINE           a subtask, same syntax as capture
  dotos track ID | stop       timewarrior, tagged dotos:<uid>
  dotos tracked ID            seconds tracked on a task, ever
  dotos undo [--by ai] [--dry]  undo the last change (anyone's, or one author's); --dry only says what
  dotos log [N] [--task ID]   the change log
  dotos projects              projects under the roots, with git state
  dotos git ...               remote git: PRs, issues, branches, commits, CI
  dotos tag ...               custom tags: add, edit, rm, list, spinweb
  dotos diff [--json] [--working] [--agents] [--file PATH] [--since TS]
                              what changed: tasks, files, agent activity
  dotos project-check P LINE [on|off]   tick a line of a project's TASKS.md
  dotos agents                AI sessions (the shell's ai-activity hooks)
  dotos page new TITLE        a page;  page check ID LINE [on|off];  pages
  dotos journal               today's journal page (made on first use)
  dotos habits                habit add NAME [--per-week N] | habit check NAME [DAY] | habit rm NAME
  dotos ext                   ext run|enable|disable ID;  ext set ID KEY VALUE
  dotos snapshot [--no-git]   everything the window shows, as JSON
  dotos serve                 background: sources on schedule, reminders

planning
  dotos plan [--date D] [--hours N]   the day, fitted to its estimates and what is left of the workday
  dotos review [--days N]     how estimates held up against tracked time
  dotos find WORDS            tasks, pages, journal and the change log
  dotos stale [--days N]      projects drifting: old uncommitted work, open lists nobody touches (default 14 days)
  dotos week [--stdout]       the week in review, as a page
  dotos snooze ID [WHEN]      push the due date (default tomorrow)
  dotos agents reconcile [--dry] [--close]   cards still doing for a finished agent session
  dotos parse LINE            what capture would make of a line (JSON)
  dotos export [--format ics|json|md] [FILE]   all tasks
  dotos import FILE.ics [--list NAME]
  dotos backup                commit the store to its git history
  dotos commands [--json]     the command table every frontend (palette, TUI) renders
  dotos graph [--tags] [--docs] [--work] [--layout] [--insight]   notes (and tasks, AI sessions, commits) as points, links as lines (JSON)
  dotos link A B              link two of its points as their kinds mean it: page:ID task:UID project:P tag:T missing:TITLE
  dotos stats [--days N]      the numbers behind the Insights charts (JSON)
  dotos list --ready          only what can be started now

add options
  --due WHEN       'today', 'tomorrow', 'YYYY-MM-DD',
                   'YYYY-MM-DD HH:MM', 'HH:MM'
  --pri LEVEL      high, normal or low
  --list NAME      list to put it in                  (default: personal)
  --note TEXT      a longer description
  --tag TEXT       comma-separated tags

edit options
  the add options above, plus
  --title TEXT     rename
  --clear-due      drop the due date
  --clear-note     drop the description
  --clear-tags     drop the tags

list options
  --all            include finished tasks
  --list NAME      only this list

  dotos help team             adding a friend, sharing, talking, agents on the network
  --json           machine-readable output
";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    // dotos help team, dotos team --help, dotos lan --help
    if matches!(args.iter().map(String::as_str).collect::<Vec<_>>()[..], ["help", "team" | "teams" | "lan", ..] | ["team" | "lan", "--help" | "-h", ..] | ["lan"]) {
        print!("{TEAM_HELP}");
        return;
    }
    if args.first().map(|a| a == "-h" || a == "--help").unwrap_or(false) {
        print!("{USAGE}");
        return;
    }
    // --json is stripped positionally, not by matching every occurrence: a
    // blanket filter also removes it when it is a flag's VALUE, so
    // `add "x" --note "--json"` would lose the note and switch output at once.
    let mut json = false;
    let mut rest: Vec<String> = Vec::with_capacity(args.len());
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--json" {
            json = true;
            i += 1;
            continue;
        }
        rest.push(a.clone());
        if a.starts_with("--") && VALUE_FLAGS.contains(&a.as_str()) {
            if let Some(v) = args.get(i + 1) {
                rest.push(v.clone());
                i += 2;
                continue;
            }
        }
        i += 1;
    }

    let store = Store::open(DOTOS);
    crate::lua::run_init();
    // No arguments at all is the question the app exists to answer.
    let cmd = rest.first().map(|s| s.as_str()).unwrap_or("now");

    let code = match cmd {
        "now" => cmd_now(&store, json),
        "list" | "ls" => cmd_list(&store, &rest, json),
        "add" => cmd_add(&store, &rest, json),
        "done" => cmd_mark(&store, &rest, true, json),
        "undone" => cmd_mark(&store, &rest, false, json),
        "edit" => cmd_edit(&store, &rest, json),
        "rm" | "remove" | "delete" => cmd_rm(&store, &rest, json),
        "lists" => cmd_lists(&store, json),
        "status" => cmd_status(&store, json),
        "where" => {
            println!("{}", store::path_display(&store.root));
            0
        }
        // ── v2 ──
        // `--help` once became a task called "--help": flags are never title words
        "capture" | "c" if rest.iter().any(|a| a == "--help" || a == "-h") => usage_err("capture LINE [--note TEXT]"),
        "capture" | "c" => done(ops::capture(&store, &words_without_flags(&rest[1..]).join(" "), flag(&rest, "--note").as_deref(), json, DEFAULT_LIST)),
        "state" | "mv" => match (rest.get(1), rest.get(2)) {
            (Some(id), Some(s)) => done(ops::set_state(&store, id, s, flag(&rest, "--on").as_deref(), json)),
            _ => usage_err("state ID STATE [--on WHAT]"),
        },
        // Teams 1 (docs/teams.md): who you are, and the conversation on an item
        "me" => {
            let (n, h, c) = (flag(&rest, "--name"), flag(&rest, "--handle"), flag(&rest, "--color"));
            let got = if n.is_some() || h.is_some() || c.is_some() { threads::set_me(n, h, c) } else { Ok(threads::me()) };
            match got {
                Ok(m) => { if json { println!("{}", serde_json::to_string(&m).unwrap_or_default()); } else { println!("{} (@{})", m.name, m.handle); } 0 }
                Err(e) => { eprintln!("dotos: {e}"); 1 }
            }
        }
        "thread" => match rest.get(1) {
            Some(it) => {
                let item = thread_item(&store, it);
                let msgs = threads::read(&item);
                if json {
                    // a recording goes out as a file to play, not as its base64
                    let v: Vec<serde_json::Value> = msgs.iter().map(|m| { let mut v = serde_json::to_value(m).unwrap_or_default(); if let Some(p) = threads::voice_file(m) { v["audio"] = serde_json::json!(p.to_string_lossy()); } v }).collect();
                    println!("{}", serde_json::Value::Array(v));
                }
                else if msgs.is_empty() { println!("No messages on {item}. dotos say {it} \"…\" starts one."); }
                else { for m in &msgs { println!("{}  {}  {}", chrono::DateTime::from_timestamp(m.ts, 0).map(|d| d.with_timezone(&chrono::Local).format("%d %b %H:%M").to_string()).unwrap_or_default(), if m.name.is_empty() { &m.author } else { &m.name }, m.text); } }
                0
            }
            None => usage_err("thread ITEM   (a task id, project:NAME, page:ID)"),
        },
        // Teams 1b: the team on the local network (lan.rs)
        "lan" => {
            let pj = |v: serde_json::Value| { println!("{}", if json { v.to_string() } else { serde_json::to_string_pretty(&v).unwrap_or_default() }); 0 };
            let name = rest.get(3).cloned().unwrap_or_else(|| "team".into());
            match rest.get(1).map(String::as_str) {
                Some("init") => match lan::init(rest.get(2).map(String::as_str).unwrap_or("team")) { Ok(t) => { println!("team {} made. On the other machine:\n  dotos lan join {}", t.name, t.code()); 0 } Err(e) => { eprintln!("dotos: {e}"); 1 } },
                Some("join") => match rest.get(2) { Some(c) => match lan::join(c, &name) { Ok(t) => { println!("joined {} ({}). dotos serve (or dotos lan serve) keeps it in sync.", t.name, t.id()); 0 } Err(e) => { eprintln!("dotos: {e}"); 1 } }, None => usage_err("lan join CODE [NAME]") },
                Some("code") => match lan::team() { Some(t) => { println!("dotos lan join {}", t.code()); 0 } None => { eprintln!("dotos: not in a team (dotos lan init)"); 1 } },
                Some("leave") => match lan::leave() { Ok(()) => { println!("left the team (threads stay here)"); 0 } Err(e) => { eprintln!("dotos: {e}"); 1 } },
                Some("status") => pj(serde_json::json!({ "team": lan::team().map(|t| serde_json::json!({ "name": t.name, "id": t.id() })), "peers": lan::peers(), "shared": lan::shared() })),
                Some("sync") => { let given: Vec<String> = rest.windows(2).filter(|w| w[0] == "--peer").map(|w| w[1].clone()).collect(); match lan::sync_once(&given) { Ok(v) => pj(v), Err(e) => { eprintln!("dotos: {e}"); 1 } } }
                Some("share") | Some("unshare") => match rest.get(2) {
                    Some(l) => match lan::share(l, rest.get(1).map(String::as_str) == Some("share")) { Ok(v) => { println!("shared lists: {}", if v.is_empty() { "none".into() } else { v.join(", ") }); 0 } Err(e) => { eprintln!("dotos: {e}"); 1 } },
                    None => usage_err("lan share|unshare LIST"),
                },
                Some("serve") => match lan::run() { Ok(()) => 0, Err(e) => { eprintln!("dotos: {e}"); 1 } },
                _ => usage_err("lan init [NAME] | join CODE | code | status | sync [--peer HOST:PORT] | serve | share LIST | unshare LIST | leave"),
            }
        }
        // Teams 2: a message becomes a task (linked both ways); whoever it @mentions does it
        "task-from" => match (rest.get(1), rest.get(2)) {
            (Some(it), Some(mid)) => {
                let item = thread_item(&store, it);
                match task_from_message(&item, mid, rest.get(3).map(String::as_str)) {
                    Ok(v) => { if json { println!("{v}"); } else { println!("task {} from the message", v["uid"].as_str().unwrap_or("").get(..8).unwrap_or("")); } 0 }
                    Err(e) => { eprintln!("dotos: {e}"); 1 }
                }
            }
            _ => usage_err("task-from ITEM MSG-ID [TITLE]"),
        },
        "agent-run" => match (rest.get(1), rest.get(2)) {
            (Some(it), Some(mid)) => match thread_agent::run(&store, it, mid) { Ok(()) => 0, Err(e) => { eprintln!("dotos: {e}"); 1 } },
            _ => usage_err("agent-run ITEM MSG-ID"),
        },
        // Teams 4: a message marked as what was decided; the task shows it on top, the thread says so
        "decide" => match (rest.get(1), rest.get(2)) {
            (Some(it), Some(mid)) => {
                let item = thread_item(&store, it);
                let Some(m) = threads::read(&item).into_iter().find(|m| m.id == *mid || m.id.starts_with(mid.as_str())) else { eprintln!("dotos: no such message"); return std::process::exit(1) };
                let Some(uid) = item.strip_prefix("task:") else { eprintln!("dotos: decisions are kept on tasks"); return std::process::exit(1) };
                match ops::set_fields(&store, uid, &[format!("decision={} {}", m.id, m.text)], false) {
                    Ok(()) => { let _ = threads::say(&item, &format!("✔ decided: {}", m.text), Some(m.id.clone()), None); println!("decided"); 0 }
                    Err(e) => { eprintln!("dotos: {e}"); 1 }
                }
            }
            _ => usage_err("decide ITEM MSG-ID"),
        },
        // what dotos serve would notify now (@mentions of me, tasks assigned to me), once
        // Teams 5: what others said since the last catch-up, per task (--mark: read now; --hours N)
        "catchup" => {
            let mark = rest.iter().any(|a| a == "--mark");
            let since = rest.iter().position(|a| a == "--hours").and_then(|i| rest.get(i + 1)).and_then(|h| h.parse::<i64>().ok()).map(|h| {
                std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0) - h * 3600
            });
            let groups = threads::catchup(since, mark);
            let title = |item: &str| match item.strip_prefix("task:") {
                Some(uid) => ops::find(&store, uid).map(|t| t.summary).unwrap_or_else(|_| item.to_string()),
                None => item.split_once(':').map(|x| x.1).unwrap_or(item).to_string(),
            };
            if json {
                let v: Vec<serde_json::Value> = groups.iter().map(|(item, ms)| serde_json::json!({ "item": item, "title": title(item), "count": ms.len(), "decided": ms.iter().any(|m| m.text.starts_with("✔ decided")), "messages": ms })).collect();
                println!("{}", serde_json::Value::Array(v));
            } else if groups.is_empty() {
                println!("nothing new");
            } else {
                for (item, ms) in &groups {
                    println!("{}  ({} new)", title(item), ms.len());
                    for m in ms.iter().rev().take(3).rev() {
                        println!("  {}: {}", if m.name.is_empty() { &m.author } else { &m.name }, m.text.lines().next().unwrap_or(""));
                    }
                }
            }
            0
        }
        // the team's people (me first), and the agents one can @mention
        "team" => {
            let people = threads::people();
            if json {
                let agents: Vec<String> = std::iter::once("claude".to_string()).chain(people.iter().map(|p| format!("claude@{}", p.handle))).collect();
                println!("{}", serde_json::json!({ "people": people, "agents": agents }));
            } else {
                for p in &people { println!("@{}  {}", p.handle, p.name); }
            }
            0
        }
        "news" => {
            let mine: Vec<(String, String, String)> = store.load_todos().into_iter().filter(|t| t.is_open()).map(|t| (t.uid.clone(), t.summary.clone(), model::get(&t, "ASSIGNEE").unwrap_or_default())).collect();
            for (title, body, item) in threads::news(&mine) { println!("{title}: {body}  ({item})"); }
            0
        }
        "threads" => { println!("{}", serde_json::Value::Object(threads::counts())); 0 }
        // Teams: a voice message (an Ogg file, e.g. recorded by the window's mic button)
        "voice" => match (rest.get(1), rest.get(2)) {
            (Some(it), Some(f)) => {
                let item = thread_item(&store, it);
                match threads::voice(&item, std::path::Path::new(f), flag(&rest, "--reply")) {
                    Ok(m) => { if json { println!("{}", serde_json::to_string(&m).unwrap_or_default()); } else { println!("voice message on {item}"); } 0 }
                    Err(e) => { eprintln!("dotos: {e}"); 1 }
                }
            }
            _ => usage_err("voice ITEM FILE.ogg [--reply ID]"),
        },
        "say" => match rest.get(1) {
            Some(it) => {
                let item = thread_item(&store, it);
                let words: Vec<&str> = rest[2..].iter().map(String::as_str).filter(|a| !a.starts_with("--")).collect();
                let reply = flag(&rest, "--reply");
                let author = flag(&rest, "--as").map(|a| (a.clone(), a));
                // --reply ID and --as WHO take a value: those words are not the message
                let skip: Vec<String> = [flag(&rest, "--reply"), flag(&rest, "--as")].into_iter().flatten().collect();
                let text = words.into_iter().filter(|w| !skip.iter().any(|s| s == w)).collect::<Vec<_>>().join(" ");
                if text.trim().is_empty() { usage_err("say ITEM TEXT… [--reply ID] [--as agent:ID]") } else { match threads::say(&item, &text, reply, author) {
                    Ok(m) => { thread_agent::dispatch(&item, &m); if json { println!("{}", serde_json::to_string(&m).unwrap_or_default()); } else { println!("said on {item}"); } 0 }
                    Err(e) => { eprintln!("dotos: {e}"); 1 }
                }
                }
            }
            None => usage_err("say ITEM TEXT… [--reply ID] [--as agent:ID]"),
        },
        "set" => match rest.get(1) {
            Some(id) => done(ops::set_fields(&store, id, &rest[2..], json)),
            None => usage_err("set ID key=value …"),
        },
        "sub" => match rest.get(1) {
            Some(id) => done(ops::subtask(&store, id, &rest[2..].join(" "), json)),
            None => usage_err("sub PARENT-ID LINE"),
        },
        "track" => match rest.get(1) {
            Some(id) => done(ops::track(&store, id)),
            None => usage_err("track ID"),
        },
        "stop" => done(timew::stop()),
        "tracked" => match rest.get(1) {
            Some(id) => match store.find_todo_by_prefix(&store.load_todos(), id) {
                Ok(t) => { println!("{}", timew::total_for(&t.uid)); 0 }
                Err(e) => { eprintln!("dotos: {e}"); 1 }
            },
            None => usage_err("tracked ID"),
        },
        "undo" => match log::undo(&store, flag(&rest, "--by").as_deref(), has(&rest, "--dry")) {
            Ok(m) => { println!("{m}"); store.reindex(); 0 }
            Err(e) => { eprintln!("dotos undo: {e}"); 1 }
        },
        "commands" => {
            let t = commands::table();
            if json { println!("{}", serde_json::to_string(&t).unwrap_or_default()); }
            else { for c in t { println!("{:<10} {}", c["name"].as_str().unwrap_or(""), c["help"].as_str().unwrap_or("")); } }
            0
        }
        "plan" => {
            let date = flag(&rest, "--date").and_then(|d| capture::date(&d, ops::today())).unwrap_or_else(ops::today);
            done(plan::plan(&store, date, flag(&rest, "--hours").and_then(|h| h.parse().ok()), json))
        }
        "review" => done(plan::review(&store, flag(&rest, "--days").and_then(|d| d.parse().ok()).unwrap_or(30), json)),
        "find" | "search" => done(plan::find(&store, &words_without_flags(&rest[1..]).join(" "), json)),
        "stale" => done(plan::stale(&store, flag(&rest, "--days").and_then(|d| d.parse().ok()).unwrap_or(14), json)),
        "graph" => {
            // --from FILE: a graph given (tests, other tools), else the notes'
            let mut g = match flag(&rest, "--from").and_then(|f| std::fs::read_to_string(f).ok()).and_then(|t| serde_json::from_str(&t).ok()) {
                Some(g) => g,
                None => graph::build(has(&rest, "--tags"), has(&rest, "--docs")),
            };
            // --work: tasks, AI sessions and commits too
            if has(&rest, "--work") {
                graph::add_work(&mut g, &store);
            }
            // --insight: communities (a group on each point) and the health report
            if has(&rest, "--insight") {
                let texts = pages::all().into_iter().filter_map(|p| Some((p.id.clone(), std::fs::read_to_string(pages::path_of(&p.id)).ok()?))).collect();
                insight::add(&mut g, &texts);
            }
            // --layout: each point a place to start from (x, y), so the window only fine-tunes
            if has(&rest, "--layout") {
                layout::place(&mut g, &Default::default(), 300);
            }
            println!("{g}");
            0
        }
        // link two things the graph shows (page:, task:, project:, tag:, missing:), as their kinds mean it
        "link" => match (rest.get(1), rest.get(2)) {
            (Some(a), Some(b)) => match link::link(&store, a, b) {
                Ok(what) => { if json { println!("{}", serde_json::json!({ "ok": true, "what": what })) } else { println!("{what}") } 0 }
                Err(e) => { eprintln!("dotos link: {e}"); 1 }
            },
            _ => usage_err("link KIND:REF KIND:REF   (page:loom task:UID project:loom tag:idea missing:Title)"),
        },
        "stats" => { println!("{}", plan::stats(&store, flag(&rest, "--days").and_then(|d| d.parse().ok()).unwrap_or(30))); 0 }
        "week" => done(plan::week(&store, has(&rest, "--stdout"))),
        "snooze" => match rest.get(1) {
            Some(id) => done(ops::snooze(&store, id, rest.get(2).map(String::as_str).unwrap_or("tomorrow"), json)),
            None => usage_err("snooze ID [WHEN]"),
        },
        "parse" => {
            println!("{}", serde_json::to_string(&capture::parse(&words_without_flags(&rest[1..]).join(" "), ops::today())).unwrap_or_default());
            0
        }
        "export" => done(plan::export(&store, &flag(&rest, "--format").unwrap_or_else(|| "ics".into()),
            rest.get(1).filter(|a| !a.starts_with("--")).map(String::as_str))),
        "import" => match rest.get(1) {
            Some(f) => match plan::import(&store, f, &flag(&rest, "--list").unwrap_or_else(|| DEFAULT_LIST.into())) {
                Ok(m) => { println!("{m}"); 0 }
                Err(e) => { eprintln!("dotos import: {e}"); 1 }
            },
            None => usage_err("import FILE.ics [--list NAME]"),
        },
        "backup" => match plan::backup() {
            Ok(m) => { println!("{m}"); 0 }
            Err(e) => { eprintln!("dotos backup: {e}"); 1 }
        },
        "log" => {
            let n = rest.get(1).and_then(|s| s.parse().ok()).unwrap_or(30);
            let entries = match flag(&rest, "--task") { Some(id) => log::of(&id, n), None => log::read(n) };
            if json { println!("{}", serde_json::to_string(&entries).unwrap_or_default()); }
            else {
                for e in entries {
                    let t = chrono::DateTime::from_timestamp(e["t"].as_i64().unwrap_or(0), 0)
                        .map(|d| d.with_timezone(&chrono::Local).format("%d %b %H:%M").to_string()).unwrap_or_default();
                    println!("{t}  {:<8} {:<7} {}{}", e["who"].as_str().unwrap_or(""), e["op"].as_str().unwrap_or(""),
                        e["title"].as_str().unwrap_or(""), if e["undone"] == true { "  (undone)" } else { "" });
                }
            }
            0
        }
        "git" => match rest.get(1).map(String::as_str) {
            Some("connect") => {
                let provider = rest.get(2).cloned().unwrap_or_default();
                let host = flag(&rest, "--host").unwrap_or_default();
                let token = flag(&rest, "--token").unwrap_or_default();
                let user = flag(&rest, "--user").unwrap_or_default();
                if provider.is_empty() || token.is_empty() {
                    usage_err("git connect PROVIDER --token TOKEN [--host HOST] [--user USER]")
                } else {
                    let mut auth = git_remote::AuthStore::load();
                    let id = format!("{}:{}", provider, if user.is_empty() { "default" } else { &user });
                    auth.accounts.push(git_remote::Account {
                        id: id.clone(),
                        provider: provider.clone(),
                        host: if host.is_empty() { match provider.as_str() {
                            "github" => "github.com".to_string(),
                            "gitlab" => "gitlab.com".to_string(),
                            "bitbucket" => "bitbucket.org".to_string(),
                            _ => host.clone(),
                        } } else { host },
                        user: if user.is_empty() { "default".to_string() } else { user },
                        token,
                    });
                    if auth.default_account.is_none() {
                        auth.default_account = Some(id);
                    }
                    match auth.save() {
                        Ok(()) => { println!("Connected {} account", provider); 0 }
                        Err(e) => { eprintln!("dotos git: {e}"); 1 }
                    }
                }
            }
            Some("disconnect") => {
                let id = rest.get(2).cloned().unwrap_or_default();
                if id.is_empty() {
                    usage_err("git disconnect ACCOUNT-ID")
                } else {
                    let mut auth = git_remote::AuthStore::load();
                    auth.accounts.retain(|a| a.id != id);
                    if auth.default_account.as_deref() == Some(&id) {
                        auth.default_account = auth.accounts.first().map(|a| a.id.clone());
                    }
                    match auth.save() {
                        Ok(()) => { println!("Disconnected {}", id); 0 }
                        Err(e) => { eprintln!("dotos git: {e}"); 1 }
                    }
                }
            }
            Some("accounts") => {
                let auth = git_remote::AuthStore::load();
                if json {
                    println!("{}", serde_json::to_string(&auth.accounts).unwrap_or_default());
                } else {
                    if auth.accounts.is_empty() {
                        println!("No git accounts connected. Use 'dotos git connect'.");
                    } else {
                        for a in &auth.accounts {
                            let marker = if auth.default_account.as_deref() == Some(&a.id) { "*" } else { " " };
                            println!("{} {}  {}@{}  (token: {}...)", marker, a.id, a.user, a.host, &a.token[..a.token.len().min(8)]);
                        }
                    }
                }
                0
            }
            Some("remote") | Some("status") => {
                let name = rest.get(2).cloned().unwrap_or_default();
                let dir = if name.is_empty() {
                    std::env::current_dir().unwrap_or_default()
                } else if name.contains('/') {
                    std::path::PathBuf::from(&name)
                } else {
                    match projects::find(&name) {
                        Some(d) => d,
                        None => { eprintln!("dotos git: no project '{}'", name); std::process::exit(2) }
                    }
                };
                let status = git_remote::project_remote_status(&dir);
                if json {
                    println!("{}", serde_json::to_string(&status).unwrap_or_default());
                } else {
                    println!("{}", serde_json::to_string_pretty(&status).unwrap_or_default());
                }
                0
            }
            Some("detect") => {
                let name = rest.get(2).cloned().unwrap_or_default();
                let dir = if name.is_empty() {
                    std::env::current_dir().unwrap_or_default()
                } else {
                    match projects::find(&name) {
                        Some(d) => d,
                        None => { eprintln!("dotos git: no project '{}'", name); std::process::exit(2) }
                    }
                };
                match git_remote::detect_remote(&dir) {
                    Some(r) => {
                        if json {
                            println!("{}", serde_json::to_string(&r).unwrap_or_default());
                        } else {
                            println!("Provider: {}", r.provider.name());
                            println!("Host:     {}", r.host);
                            println!("Owner:    {}", r.owner);
                            println!("Repo:     {}", r.repo);
                            println!("URL:      {}", r.url);
                        }
                        0
                    }
                    None => { eprintln!("dotos git: no remote detected"); 1 }
                }
            }
            // local git for the Changes page (gitview.rs), always JSON
            Some(v @ ("repos" | "changes" | "diff" | "log" | "show" | "cat" | "tree" | "commit" | "push" | "pull")) => {
                let repo = flag(&rest, "--repo");
                let r = if v == "repos" {
                    Ok(gitview::repos())
                } else {
                    gitview::resolve(repo.as_deref()).and_then(|dir| match v {
                        "changes" => gitview::changes(&dir),
                        "diff" => gitview::diff(&dir, flag(&rest, "--rev").as_deref(), flag(&rest, "--file").as_deref()),
                        "log" => gitview::log(&dir, flag(&rest, "-n").and_then(|n| n.parse().ok()).unwrap_or(100), flag(&rest, "--file").as_deref()),
                        "show" => gitview::show(&dir, &rest.get(2).cloned().unwrap_or_else(|| "HEAD".into())),
                        "cat" => gitview::cat(&dir, &rest.get(2).cloned().unwrap_or_default(), flag(&rest, "--rev").as_deref()),
                        // commit -m MSG [--repo R] [-- FILE…]
                        "commit" => gitview::commit(&dir, &flag(&rest, "-m").unwrap_or_default(), &rest.iter().position(|a| a == "--").map(|i| rest[i + 1..].to_vec()).unwrap_or_default()),
                        "push" => gitview::sync(&dir, true),
                        "pull" => gitview::sync(&dir, false),
                        _ => gitview::tree(&dir),
                    })
                };
                match r {
                    Ok(v) => { println!("{v}"); 0 }
                    Err(e) => { println!("{}", serde_json::json!({ "error": e })); eprintln!("dotos git {v}: {e}"); 1 }
                }
            }
            _ => {
                eprintln!("usage: dotos git connect|disconnect|accounts|remote|detect|repos|changes|diff|log|show|cat|tree ...");
                2
            }
        },
        "tag" => match rest.get(1).map(String::as_str) {
            Some("add" | "new" | "create") => {
                let name = rest.get(2).cloned().unwrap_or_default();
                if name.is_empty() {
                    usage_err("tag add NAME [--color HEX] [--icon NAME] [--pri LEVEL] [--note TEXT]")
                } else {
                    let color = flag(&rest, "--color").unwrap_or_default();
                    let icon = flag(&rest, "--icon").unwrap_or_default();
                    let pri = flag(&rest, "--pri").unwrap_or_default();
                    let note = flag(&rest, "--note").unwrap_or_default();
                    match tags::add(&name, &color, &icon, &pri, &note) {
                        Ok(t) => { if json { println!("{}", serde_json::to_string(&t).unwrap_or_default()); } else { println!("Added tag {} ({})", t.name, t.color); } 0 }
                        Err(e) => { eprintln!("dotos tag: {e}"); 1 }
                    }
                }
            }
            Some("edit" | "set") => {
                let name = rest.get(2).cloned().unwrap_or_default();
                if name.is_empty() {
                    usage_err("tag edit NAME [--color HEX] [--icon NAME] [--pri LEVEL] [--note TEXT]")
                } else {
                    let color = flag(&rest, "--color");
                    let icon = flag(&rest, "--icon");
                    let pri = flag(&rest, "--pri");
                    let note = flag(&rest, "--note");
                    match tags::edit(&name, color.as_deref(), icon.as_deref(), pri.as_deref(), note.as_deref()) {
                        Ok(t) => { if json { println!("{}", serde_json::to_string(&t).unwrap_or_default()); } else { println!("Updated tag {}", t.name); } 0 }
                        Err(e) => { eprintln!("dotos tag: {e}"); 1 }
                    }
                }
            }
            Some("rm" | "remove" | "delete") => {
                let name = rest.get(2).cloned().unwrap_or_default();
                if name.is_empty() {
                    usage_err("tag rm NAME")
                } else {
                    match tags::remove(&name) {
                        Ok(()) => { println!("Removed tag {}", name); 0 }
                        Err(e) => { eprintln!("dotos tag: {e}"); 1 }
                    }
                }
            }
            Some("list" | "ls" | "") | None => {
                let tags = tags::list();
                if json {
                    println!("{}", serde_json::to_string(&tags).unwrap_or_default());
                } else {
                    if tags.is_empty() {
                        println!("No custom tags. 'dotos tag add NAME' creates one.");
                    } else {
                        for t in &tags {
                            println!("  {:<16} {}  {}  {}", t.name, t.color, t.icon, t.priority);
                        }
                    }
                }
                0
            }
            Some("spinweb") => {
                println!("{}", serde_json::to_string(&tags::spinweb()).unwrap_or_default());
                0
            }
            _ => {
                let name = rest.get(1).cloned().unwrap_or_default();
                match tags::find(&name) {
                    Some(t) => { if json { println!("{}", serde_json::to_string(&t).unwrap_or_default()); } else { println!("{}  {}  {}  {}", t.name, t.color, t.icon, t.priority); } 0 }
                    None => { eprintln!("dotos tag: no tag '{}'", name); 1 }
                }
            }
        },
        "projects" => {
            let v: Vec<_> = projects::discover().iter().map(|d| projects::load(d, true)).collect();
            if json { println!("{}", serde_json::to_string(&v).unwrap_or_default()); }
            else { for p in v { println!("{:<20} {}", p.name, p.git.map(|g| format!("{} · {} dirty · ↑{}", g.branch, g.dirty, g.ahead)).unwrap_or_default()); } }
            0
        }
        "project-check" => match (rest.get(1).and_then(|n| projects::find(n)), rest.get(2).and_then(|l| l.parse().ok())) {
            (Some(dir), Some(line)) => done(projects::toggle_doc_task(&dir, line, rest.get(3).map_or(true, |s| s != "off"))),
            _ => usage_err("project-check PROJECT LINE [on|off]"),
        },
        "agents" if rest.get(1).map(String::as_str) == Some("reconcile") => {
            match plan::reconcile(&store, has(&rest, "--dry"), has(&rest, "--close")) {
                Ok(v) if v.is_empty() => { println!("no stale agent cards"); 0 }
                Ok(v) => { for t in v { println!("{} {t}", if has(&rest, "--dry") { "would park" } else if has(&rest, "--close") { "closed" } else { "parked" }); } 0 }
                Err(e) => { eprintln!("dotos agents: {e}"); 1 }
            }
        }
        // dotos agents actions ID [--task UID]: what a session did, newest last (one card's part with --task)
        "agents" if rest.get(1).map(String::as_str) == Some("actions") => {
            let mut acts = match rest.get(2) { Some(id) => agents::actions(id), None => { usage_err("agents actions SESSION-ID [--task UID]"); Vec::new() } };
            if let Some(t) = flag(&rest, "--task") {
                acts.retain(|a| a["task"].as_str() == Some(t.as_str()));
            }
            println!("{}", serde_json::to_string(&serde_json::json!({ "actions": acts, "summary": agents::summary(&acts), "files": agents::touched(&acts).into_iter().map(|(p, k, n, t)| serde_json::json!({ "path": p, "kind": k, "times": n, "task": t })).collect::<Vec<_>>() })).unwrap_or_default());
            0
        }
        "agents" => { println!("{}", serde_json::to_string_pretty(&agents::list_all()).unwrap_or_default()); 0 }
        "pages" => { println!("{}", serde_json::to_string(&pages::all()).unwrap_or_default()); 0 }
        "page" => match rest.get(1).map(String::as_str) {
            Some("new") => match pages::create(&words_without_flags(&rest[2..]).join(" "),
                    &flag(&rest, "--project").unwrap_or_default(), &flag(&rest, "--tag").unwrap_or_default()) {
                Ok(p) => { println!("{}", p.display()); 0 }
                Err(e) => { eprintln!("dotos page: {e}"); 1 }
            },
            Some("check") => match (rest.get(2), rest.get(3).and_then(|l| l.parse().ok())) {
                (Some(id), Some(line)) => done(pages::toggle(id, line, rest.get(4).map_or(true, |s| s != "off"))),
                _ => usage_err("page check PAGE-ID LINE [on|off]"),
            },
            _ => usage_err("page new TITLE [--project P] [--tag a,b] | page check PAGE-ID LINE [on|off]"),
        },
        "journal" => {
            let todos = store.load_todos();
            let today = ops::today();
            let agenda: Vec<String> = todos.iter().filter(|t| t.is_open() && t.due_date().is_some_and(|d| d <= today)).map(|t| t.summary.clone()).collect();
            match pages::journal_today(&agenda, &[]) {
                Ok(p) => { println!("{}", p.display()); 0 }
                Err(e) => { eprintln!("dotos journal: {e}"); 1 }
            }
        }
        "habits" => { println!("{}", serde_json::to_string(&habits::views()).unwrap_or_default()); 0 }
        "habit" => match (rest.get(1).map(String::as_str), rest.get(2)) {
            (Some("add"), Some(name)) => done(habits::add(name, flag(&rest, "--per-week").and_then(|n| n.parse().ok()).unwrap_or(7), &flag(&rest, "--icon").unwrap_or_default())),
            (Some("rm"), Some(name)) => done(habits::remove(name)),
            (Some("check"), Some(name)) => {
                let day = rest.get(3).filter(|s| !s.starts_with("--")).and_then(|d| capture::date(d, ops::today())).unwrap_or_else(ops::today);
                match habits::toggle(name, day) { Ok(on) => { println!("{name}: {}", if on { "done" } else { "not done" }); 0 } Err(e) => { eprintln!("dotos habit: {e}"); 1 } }
            }
            _ => usage_err("habit add NAME [--per-week N] [--icon NAME] | habit check NAME [DAY] | habit rm NAME"),
        },
        "ext" => match (rest.get(1).map(String::as_str), rest.get(2)) {
            (None | Some("list"), _) => { println!("{}", serde_json::to_string_pretty(&ext::list()).unwrap_or_default()); 0 }
            (Some("run"), Some(id)) => match ext::list().into_iter().find(|e| e.id == *id) {
                Some(e) if e.kind == "source" => match ops::sync_source(&store, &e) { Ok(m) => { println!("{m}"); 0 } Err(m) => { eprintln!("dotos ext: {m}"); 1 } },
                Some(_) => usage_err("only source extensions run on demand"),
                None => usage_err("no such extension"),
            },
            (Some("enable"), Some(id)) => done(ext::set_enabled(id, true)),
            (Some("disable"), Some(id)) => done(ext::set_enabled(id, false)),
            (Some("set"), Some(id)) => match (rest.get(3), rest.get(4)) {
                (Some(k), Some(v)) => done(ext::set_option(id, k, v)),
                _ => usage_err("ext set ID KEY VALUE"),
            },
            _ => usage_err("ext [list] | ext run ID | ext enable|disable ID | ext set ID KEY VALUE"),
        },
        "snapshot" => { println!("{}", ops::snapshot(&store, !has(&rest, "--no-git"))); 0 }
        "completions" => match rest.get(1).map(String::as_str) {
            Some("bash") => { print!("{}", COMPLETIONS_BASH); 0 }
            Some("zsh") => { print!("{}", COMPLETIONS_ZSH); 0 }
            Some("fish") => { print!("{}", COMPLETIONS_FISH); 0 }
            _ => usage_err("completions bash|zsh|fish"),
        },
        "diff" => {
            let since_ts = flag(&rest, "--since").and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            let format = if json { "json" } else { "text" };
            if has(&rest, "--working") {
                println!("{}", serde_json::to_string_pretty(&diff::working_now()).unwrap_or_default());
                0
            } else if has(&rest, "--agents") {
                println!("{}", serde_json::to_string_pretty(&diff::agent_work_summary()).unwrap_or_default());
                0
            } else if let Some(path) = flag(&rest, "--file") {
                match diff::file_diff(&path) {
                    Ok(d) => { print!("{}", d); 0 }
                    Err(e) => { eprintln!("dotos diff: {}", e); 1 }
                }
            } else {
                let changes = diff::since(since_ts);
                print!("{}", diff::render(&changes, format));
                0
            }
        }
        "query" => query::run(&rest[1..]),
        "lua" => lua::run(&rest[1..]),
        "serve" => ops::serve(&store),
        other => {
            eprintln!("dotos: no command '{other}'\n");
            print!("{USAGE}");
            2
        }
    };

    // Writes do not maintain the bounds index, and a sync writes into the vdir
    // without going through this binary at all. Re-indexing here makes
    // .index.json change exactly when the store's contents changed, which is
    // what the window watches to notice an edit made anywhere else.
    if code == 0 && matches!(cmd, "add" | "done" | "undone" | "edit" | "rm" | "remove" | "delete") {
        store.reindex();
    }
    std::process::exit(code);
}

// ── showing tasks ───────────────────────────────────────────────────────────

/// Where a task belongs in the list. The order of the variants is the order
/// the groups print in, which is also the order they matter in.
#[derive(PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
enum Group {
    Overdue,
    Today,
    Tomorrow,
    ThisWeek,
    Later,
    NoDate,
}

impl Group {
    fn of(t: &Todo, today: NaiveDate) -> Group {
        match t.due_date() {
            None => Group::NoDate,
            Some(d) if d < today => Group::Overdue,
            Some(d) if d == today => Group::Today,
            Some(d) if d == today + Duration::days(1) => Group::Tomorrow,
            Some(d) if d <= today + Duration::days(7) => Group::ThisWeek,
            Some(_) => Group::Later,
        }
    }
    fn label(self) -> &'static str {
        match self {
            Group::Overdue => "Overdue",
            Group::Today => "Today",
            Group::Tomorrow => "Tomorrow",
            Group::ThisWeek => "This week",
            Group::Later => "Later",
            Group::NoDate => "Someday",
        }
    }
}

fn short_id(uid: &str) -> String {
    uid.chars().take(8).collect()
}

/// The due column: a date only when it adds something the group heading has
/// not already said, and a time only when the task actually has one.
fn due_label(t: &Todo, group: Group) -> String {
    let Some(due) = t.due else { return String::new() };
    let timed = !t.due_all_day && (due.hour() != 0 || due.minute() != 0);
    match (group, timed) {
        (Group::Today | Group::Tomorrow, true) => due.format("%H:%M").to_string(),
        (Group::Today | Group::Tomorrow, false) => String::new(),
        (_, true) => due.format("%a %-d %b %H:%M").to_string(),
        (_, false) => due.format("%a %-d %b").to_string(),
    }
}

fn mark(t: &Todo) -> &'static str {
    match t.status {
        Status::Completed => "[x]",
        Status::Cancelled => "[-]",
        Status::InProcess => "[~]",
        Status::NeedsAction => "[ ]",
    }
}

fn print_groups(todos: &[Todo], today: NaiveDate, show_list: bool) {
    let mut current: Option<Group> = None;
    for t in todos {
        let g = Group::of(t, today);
        if current != Some(g) {
            println!("\n{}", g.label());
            current = Some(g);
        }
        let due = due_label(t, g);
        let pri = match t.importance() {
            Importance::High => "!",
            _ => " ",
        };
        // The list only earns a column when there is more than one; tags
        // always follow it, so the two views never label the same task
        // differently.
        let mut tail = String::new();
        if show_list {
            // Padded only when something follows, so no row ends in spaces.
            if t.categories.is_empty() { tail.push_str(&format!("   {}", t.list)); }
            else { tail.push_str(&format!("   {:<10}", t.list)); }
        }
        if !t.categories.is_empty() { tail.push_str(&format!("   {}", t.categories.join(", "))); }
        println!(
            "  {} {}{:<10} {:<34} {}{}",
            mark(t),
            pri,
            due,
            t.summary,
            short_id(&t.uid),
            tail
        );
    }
}

fn cmd_now(store: &Store, json: bool) -> i32 {
    let today = ics::today();
    let due_now: Vec<Todo> = store
        .load_todos()
        .into_iter()
        .filter(|t| t.is_open() && t.due_date().map(|d| d <= today).unwrap_or(false))
        .collect();

    if json {
        println!("{}", serde_json::to_string(&due_now).unwrap_or_else(|_| "[]".into()));
        return 0;
    }
    if due_now.is_empty() {
        println!("Nothing due. 'dotos list' for everything else.");
        return 0;
    }
    print_groups(&due_now, today, store.calendars().len() > 1);
    println!();
    0
}

fn cmd_list(store: &Store, args: &[String], json: bool) -> i32 {
    let today = ics::today();
    let all = has(args, "--all");
    let only = flag(args, "--list");

    let todos: Vec<Todo> = store
        .load_todos()
        .into_iter()
        .filter(|t| all || t.is_open())
        .filter(|t| only.as_ref().map(|l| &t.list == l).unwrap_or(true))
        .collect();
    let todos: Vec<Todo> = if has(args, "--ready") {
        let every = store.load_todos();
        todos.into_iter().filter(|t| plan::is_ready(t, &every)).collect()
    } else {
        todos
    };

    if json {
        println!("{}", serde_json::to_string(&todos).unwrap_or_else(|_| "[]".into()));
        return 0;
    }
    if todos.is_empty() {
        println!("No tasks. 'dotos add \"something\"' starts one.");
        return 0;
    }
    print_groups(&todos, today, only.is_none() && store.calendars().len() > 1);
    println!();
    0
}

// ── changing them ───────────────────────────────────────────────────────────

/// Reads --due/--pri/--note/--tag onto a task. Shared by add and edit so the
/// two can never drift on what a flag means.
fn apply_options(t: &mut Todo, args: &[String]) -> Result<(), String> {
    if let Some(v) = flag(args, "--due") {
        let when = parse_when(&v).ok_or_else(|| format!("cannot read --due '{v}'"))?;
        // A bare date is a day, not midnight: a task due "Wednesday" is not
        // late at 00:01 on Wednesday.
        t.due_all_day = parse_date(&v).is_some();
        t.due = Some(when);
    }
    if let Some(v) = flag(args, "--pri") {
        let i = Importance::parse(&v)
            .ok_or_else(|| format!("--pri takes high, normal or low, not '{v}'"))?;
        t.set_importance(i);
    }
    if let Some(v) = flag(args, "--note") {
        t.description = v;
    }
    if let Some(v) = flag(args, "--tag") {
        t.categories = v
            .split(',')
            .map(|c| c.trim().to_string())
            .filter(|c| !c.is_empty())
            .collect();
    }
    Ok(())
}

fn cmd_add(store: &Store, args: &[String], json: bool) -> i32 {
    let Some(title) = args.get(1).filter(|t| !t.starts_with("--")) else {
        eprintln!("dotos add: needs a title");
        return 2;
    };
    let list = flag(args, "--list").unwrap_or_else(|| DEFAULT_LIST.to_string());
    let mut t = Todo::new(title, &list, &store::new_uid("dotos"));
    if let Err(e) = apply_options(&mut t, args) {
        eprintln!("dotos add: {e}");
        return 2;
    }

    match store.save_todo(&t) {
        Ok(path) => {
            crate::ops::after_change("add", &t, None);
            if json {
                println!("{}", serde_json::to_string(&t).unwrap_or_default());
            } else {
                println!("Added  {}  {}", short_id(&t.uid), t.summary);
                eprintln!("  {}", store::path_display(&path));
            }
            0
        }
        Err(e) => {
            eprintln!("dotos add: {e}");
            1
        }
    }
}

fn cmd_mark(store: &Store, args: &[String], done: bool, json: bool) -> i32 {
    let verb = if done { "done" } else { "undone" };
    let Some(prefix) = args.get(1) else {
        eprintln!("dotos {verb}: needs a task id");
        return 2;
    };
    let todos = store.load_todos();
    let found = match store.find_todo_by_prefix(&todos, prefix) {
        Ok(t) => t.clone(),
        Err(e) => {
            eprintln!("dotos {verb}: {e}");
            return 2;
        }
    };

    let before = found.clone();
    let mut t = found;
    if done {
        // through the model, so a repeating task moves on instead of closing
        model::set_state(&mut t, model::State::Done);
    } else {
        t.reopen();
    }
    match store.save_todo(&t) {
        Ok(_) => {
            crate::ops::after_change("state", &t, Some(&before));
            if json {
                println!("{}", serde_json::to_string(&t).unwrap_or_default());
            } else {
                println!("{} {}  {}", mark(&t), short_id(&t.uid), t.summary);
            }
            0
        }
        Err(e) => {
            eprintln!("dotos {verb}: {e}");
            1
        }
    }
}

fn cmd_edit(store: &Store, args: &[String], json: bool) -> i32 {
    let Some(prefix) = args.get(1) else {
        eprintln!("dotos edit: needs a task id");
        return 2;
    };
    let todos = store.load_todos();
    let found = match store.find_todo_by_prefix(&todos, prefix) {
        Ok(t) => t.clone(),
        Err(e) => {
            eprintln!("dotos edit: {e}");
            return 2;
        }
    };

    let before = found.clone();
    let mut t = found;
    if let Some(v) = flag(args, "--title") {
        t.summary = v;
    }
    if let Err(e) = apply_options(&mut t, args) {
        eprintln!("dotos edit: {e}");
        return 2;
    }
    if has(args, "--clear-due") {
        t.due = None;
        t.due_all_day = false;
    }
    if has(args, "--clear-note") {
        t.description.clear();
    }
    if has(args, "--clear-tags") {
        t.categories.clear();
    }

    // Moving a task between lists means a new file in a new directory, so the
    // old one has to go or it would exist twice with one uid.
    let moved_from = flag(args, "--list").filter(|l| *l != t.list);
    if let Some(new_list) = moved_from {
        let old = t.clone();
        t.list = new_list;
        if let Err(e) = store.delete_todo(&old) {
            eprintln!("dotos edit: {e}");
            return 1;
        }
    }

    match store.save_todo(&t) {
        Ok(_) => {
            crate::ops::after_change("edit", &t, Some(&before));
            if json {
                println!("{}", serde_json::to_string(&t).unwrap_or_default());
            } else {
                println!("Edited {}  {}", short_id(&t.uid), t.summary);
            }
            0
        }
        Err(e) => {
            eprintln!("dotos edit: {e}");
            1
        }
    }
}

fn cmd_rm(store: &Store, args: &[String], json: bool) -> i32 {
    let Some(prefix) = args.get(1) else {
        eprintln!("dotos rm: needs a task id");
        return 2;
    };
    let todos = store.load_todos();
    let found = match store.find_todo_by_prefix(&todos, prefix) {
        Ok(t) => t.clone(),
        Err(e) => {
            eprintln!("dotos rm: {e}");
            return 2;
        }
    };
    match store.delete_todo(&found) {
        Ok(()) => {
            crate::ops::after_change("rm", &found, Some(&found));
            if json {
                println!("{}", serde_json::to_string(&found).unwrap_or_default());
            } else {
                println!("Deleted {}  {}", short_id(&found.uid), found.summary);
            }
            0
        }
        Err(e) => {
            eprintln!("dotos rm: {e}");
            1
        }
    }
}

// ── the store itself ────────────────────────────────────────────────────────

fn cmd_lists(store: &Store, json: bool) -> i32 {
    let all = store.load_todos();
    let lists = store.calendars();
    if json {
        let rows: Vec<_> = lists
            .iter()
            .map(|l| {
                let mine: Vec<&Todo> = all.iter().filter(|t| t.list == l.name).collect();
                serde_json::json!({
                    "name": l.name,
                    "path": store::path_display(&l.path),
                    "open": mine.iter().filter(|t| t.is_open()).count(),
                    "total": mine.len(),
                })
            })
            .collect();
        println!("{}", serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()));
        return 0;
    }
    if lists.is_empty() {
        println!("No lists yet — 'dotos add' makes one.");
        return 0;
    }
    for l in lists {
        let mine: Vec<&Todo> = all.iter().filter(|t| t.list == l.name).collect();
        let open = mine.iter().filter(|t| t.is_open()).count();
        println!(
            "  {:<16} {:>4} open  {:>4} total   {}",
            l.name,
            open,
            mine.len(),
            store::path_display(&l.path)
        );
    }
    0
}

fn cmd_status(store: &Store, json: bool) -> i32 {
    let today = ics::today();
    let all = store.load_todos();
    let open: Vec<&Todo> = all.iter().filter(|t| t.is_open()).collect();
    let overdue = open.iter().filter(|t| t.is_overdue(today)).count();
    let due_today = open
        .iter()
        .filter(|t| t.due_date() == Some(today))
        .count();
    let next = open.iter().filter(|t| t.due.is_some()).min_by_key(|t| t.due);

    if json {
        println!(
            "{}",
            serde_json::json!({
                "root": store::path_display(&store.root),
                "lists": store.calendars().len(),
                "total": all.len(),
                "open": open.len(),
                "overdue": overdue,
                "due_today": due_today,
                "next": next.map(|t| serde_json::json!({
                    "uid": t.uid, "summary": t.summary, "due": t.due,
                })),
            })
        );
        return 0;
    }
    println!("store      {}", store::path_display(&store.root));
    println!("lists      {}", store.calendars().len());
    println!(
        "tasks      {} open of {} ({} overdue, {} due today)",
        open.len(),
        all.len(),
        overdue,
        due_today
    );
    match next {
        Some(t) => println!(
            "next       {}  {}",
            t.due
                .map(|d| d.format("%a %-d %b").to_string())
                .unwrap_or_default(),
            t.summary
        ),
        None => println!("next       nothing with a due date"),
    }
    0
}

fn done(r: Result<(), String>) -> i32 {
    match r {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("dotos: {e}");
            1
        }
    }
}

fn usage_err(u: &str) -> i32 {
    eprintln!("usage: dotos {u}");
    2
}

/// Positional words only: drops each `--flag` and, for value flags, its value.
fn words_without_flags(args: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let mut skip = false;
    for a in args {
        if skip {
            skip = false;
            continue;
        }
        if a.starts_with("--") {
            skip = VALUE_FLAGS.contains(&a.as_str());
            continue;
        }
        out.push(a.clone());
    }
    out
}

/// A thread's item from what was typed: project:/page: as they are, a task id (or its first
/// characters) as task:<the full uid>, so the CLI and the window write the same thread.
fn thread_item(store: &Store, s: &str) -> String {
    if s.contains(':') {
        return s.to_string();
    }
    ops::find(store, s).map(|t| format!("task:{}", t.uid)).unwrap_or_else(|_| format!("task:{s}"))
}

/// `dotos task-from`: the message's text (or TITLE) as a new task in the thread's project, linked
/// to the message and the item; its first @mention is the assignee; the thread says so.
fn task_from_message(item: &str, mid: &str, title: Option<&str>) -> Result<serde_json::Value, String> {
    let msgs = threads::read(item);
    let m = msgs.iter().find(|m| m.id == mid || m.id.starts_with(mid)).ok_or("no such message in that thread")?;
    let me = std::env::current_exe().map_err(|e| e.to_string())?;
    let text = title.map(String::from).unwrap_or_else(|| {
        // the message without the @handles, as a title
        m.text.split_whitespace().filter(|w| !w.starts_with('@')).collect::<Vec<_>>().join(" ")
    });
    if text.trim().is_empty() {
        return Err("the message has no words for a title (give one: dotos task-from ITEM ID TITLE)".into());
    }
    // capture parses @dates, !priority …: the title goes in as typed, but quoted words stay words
    let out = std::process::Command::new(&me).args(["capture", &text, "--json"]).output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).map_err(|e| e.to_string())?;
    let uid = v["uid"].as_str().ok_or("capture gave no uid")?.to_string();
    let mut fields = vec![format!("link+=msg:{item}/{}", m.id)];
    if item.starts_with("task:") {
        // and to the task it was said on
        fields.push(format!("link+={item}"));
    }
    if let Some(who) = m.mentions.first() {
        fields.push(format!("assignee={who}"));
    }
    if let Some(p) = item.strip_prefix("project:") {
        fields.push(format!("project={p}"));
    }
    let mut args = vec!["set".to_string(), uid.get(..8).unwrap_or(&uid).to_string()];
    args.extend(fields);
    let set = std::process::Command::new(&me).args(&args).output().map_err(|e| e.to_string())?;
    if !set.status.success() {
        return Err(String::from_utf8_lossy(&set.stderr).trim().to_string());
    }
    let who = m.mentions.first().map(|w| format!(" for @{w}")).unwrap_or_default();
    let _ = threads::say(item, &format!("→ new task{who}: {}", text.trim()), Some(m.id.clone()), None);
    Ok(serde_json::json!({ "uid": uid, "title": text.trim(), "assignee": m.mentions.first() }))
}
