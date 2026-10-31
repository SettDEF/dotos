//! The syntax in front of every command (CLI.md §2, §5): one way to type everything, before the
//! command table runs.
//!
//! - flags: `--due=fri` is `--due fri`; `-n` `-y` `-q` `-j` are `--dry-run` `--yes` `--quiet`
//!   `--json`; after `--` nothing is a flag
//! - aliases: config.json "aliases": { "today": "list --due today" }, `$1`… and `$@` filled in
//! - noun verb: `dotos task add …` is `dotos add …`, `dotos chat say …` is `dotos say …`; the short
//!   forms stay, `dotos task` alone lists its verbs
//! - your own commands: an unknown NAME runs `dotos-NAME` from ~/.config/dotos/commands or $PATH
//!   (any language; it gets DOTOS_BIN, DOTOS_JSON, DOTOS_CONFIG, DOTOS_DATA), as git and cargo do
//! - a typo gets "did you mean"

use crate::paths;
use std::path::PathBuf;

/// noun → [(verb, what it runs as, help)]. What it runs as is the existing command (its words go
/// first, the rest follows), so the full form and the short form are the same code.
pub const NOUNS: &[(&str, &str, &[(&str, &str, &str)])] = &[
    ("task", "tasks", &[
        ("add", "add", "add a task: TITLE [--due WHEN] [--pri P] [--list L] [--note N]"),
        ("capture", "capture", "add from one line: title @fri 14:00 !high #tag ~30m +project"),
        ("list", "list", "open tasks [--all] [--list L]"),
        ("ls", "list", ""),
        ("done", "done", "tick it: ID…"),
        ("undone", "undone", "untick it: ID…"),
        ("edit", "edit", "change one: ID [--title T] [--due WHEN] …"),
        ("set", "set", "set fields: ID key=value…"),
        ("state", "state", "inbox todo doing waiting done cancelled: ID STATE"),
        ("sub", "sub", "a subtask: ID LINE"),
        ("snooze", "snooze", "push the due date: ID [WHEN]"),
        ("link", "link", "link two items"),
        ("rm", "rm", "delete it: ID (undo brings it back)"),
        ("track", "track", "start the timer on it: ID"),
        ("search", "find", "find tasks: WORDS"),
    ]),
    ("chat", "conversations on tasks, projects and pages", &[
        ("list", "threads", "every conversation"),
        ("show", "thread", "one conversation: ITEM"),
        ("say", "say", "write: ITEM TEXT"),
        ("voice", "voice", "a voice message: ITEM FILE.ogg"),
        ("catchup", "catchup", "what others said since you last looked"),
        ("news", "news", "mentions and assignments for you"),
        ("decide", "decide", "mark a message as the decision: ITEM MSG"),
        ("task", "task-from", "a message becomes a task: ITEM MSG"),
    ]),
    ("time", "time tracking (timewarrior)", &[
        ("start", "track", "start on a task: ID"),
        ("stop", "stop", "stop the timer"),
        ("show", "tracked", "seconds tracked on a task: ID"),
        ("week", "week", "write this week's review page"),
    ]),
    ("event", "every change, by whom", &[
        ("log", "log", "the change log [N] [--task ID]"),
        ("undo", "undo", "undo the last change [--by ai] [--dry]"),
        ("diff", "diff", "what changed: tasks, files, agent activity"),
    ]),
    ("team", "the people and the network", &[
        ("list", "team", "the people met so far"),
        ("me", "me", "you: [--name N] [--handle H] [--github LOGIN|auto]"),
        ("lan", "lan", "pairing and sync on the network: init, invite, join, share"),
    ]),
];

/// Every command the table in main.rs knows (for "did you mean").
pub const COMMANDS: &[&str] = &[
    "now", "list", "ls", "add", "done", "undone", "edit", "rm", "lists", "status", "where", "capture", "state", "me", "thread",
    "lan", "task-from", "decide", "catchup", "team", "news", "threads", "voice", "say", "set", "sub", "track", "stop", "tracked",
    "undo", "commands", "plan", "review", "find", "search", "stale", "graph", "link", "stats", "week", "snooze", "parse", "export",
    "import", "backup", "log", "git", "tag", "projects", "project", "agents", "pages", "page", "journal", "habits", "habit", "ext",
    "snapshot", "completions", "diff", "query", "lua", "serve", "help",
];

pub enum Route {
    /// run the command table with these words
    Args(Vec<String>),
    /// done here (help printed, an external command ran): exit with this
    Exit(i32),
}

/// `--k=v` → `--k v`, short flags → long ones, up to `--`.
pub fn normalize(args: Vec<String>) -> Vec<String> {
    let mut out = Vec::with_capacity(args.len());
    let mut flags_done = false;
    for a in args {
        if flags_done {
            out.push(a);
            continue;
        }
        match a.as_str() {
            "--" => { flags_done = true; out.push(a); }
            "-n" => out.push("--dry-run".into()),
            "-y" => out.push("--yes".into()),
            "-q" => out.push("--quiet".into()),
            "-j" => out.push("--json".into()),
            s if s.starts_with("--") && s.contains('=') => {
                let (k, v) = s.split_once('=').unwrap();
                out.push(k.to_string());
                out.push(v.to_string());
            }
            _ => out.push(a),
        }
    }
    out
}

/// Words of an alias, quotes kept together ("a b" is one word).
fn split_words(s: &str) -> Vec<String> {
    let (mut out, mut cur, mut quote) = (Vec::new(), String::new(), None::<char>);
    for c in s.chars() {
        match (quote, c) {
            (Some(q), c) if c == q => quote = None,
            (Some(_), c) => cur.push(c),
            (None, '"' | '\'') => quote = Some(c),
            (None, c) if c.is_whitespace() => { if !cur.is_empty() { out.push(std::mem::take(&mut cur)); } }
            (None, c) => cur.push(c),
        }
    }
    if !cur.is_empty() { out.push(cur); }
    out
}

fn aliases() -> serde_json::Map<String, serde_json::Value> {
    paths::config()["aliases"].as_object().cloned().unwrap_or_default()
}

/// An alias's words, with `$1`… and `$@` filled from what followed it.
fn expand_alias(body: &str, rest: &[String]) -> Vec<String> {
    let mut used = false;
    let mut out = Vec::new();
    for w in split_words(body) {
        if w == "$@" {
            out.extend(rest.iter().cloned());
            used = true;
        } else if w.contains('$') {
            // $1… anywhere in a word (task:$1), the highest first so $1 does not eat $12
            let mut w2 = w.clone();
            for i in (1..=rest.len().max(9)).rev() {
                let k = format!("${i}");
                if w2.contains(&k) {
                    w2 = w2.replace(&k, rest.get(i - 1).map(String::as_str).unwrap_or(""));
                    used = true;
                }
            }
            if !w2.is_empty() { out.push(w2); }
        } else {
            out.push(w);
        }
    }
    // no $ in it: what followed goes after it
    if !used { out.extend(rest.iter().cloned()); }
    out
}

/// `dotos-NAME` in ~/.config/dotos/commands, then on $PATH.
pub fn external(name: &str) -> Option<PathBuf> {
    if name.is_empty() || name.contains('/') {
        return None;
    }
    let file = format!("dotos-{name}");
    let mut dirs = vec![paths::config_dir().join("commands")];
    dirs.extend(std::env::var_os("PATH").map(|p| std::env::split_paths(&p).collect::<Vec<_>>()).unwrap_or_default());
    dirs.into_iter().map(|d| d.join(&file)).find(|p| {
        use std::os::unix::fs::PermissionsExt;
        p.is_file() && p.metadata().map(|m| m.permissions().mode() & 0o111 != 0).unwrap_or(false)
    })
}

/// Every external command found (for help and "did you mean").
pub fn externals() -> Vec<String> {
    let mut dirs = vec![paths::config_dir().join("commands")];
    dirs.extend(std::env::var_os("PATH").map(|p| std::env::split_paths(&p).collect::<Vec<_>>()).unwrap_or_default());
    let mut v: Vec<String> = dirs.iter().filter_map(|d| std::fs::read_dir(d).ok()).flatten().flatten()
        .filter_map(|e| e.file_name().to_string_lossy().strip_prefix("dotos-").map(String::from))
        .filter(|n| external(n).is_some()).collect();
    v.sort();
    v.dedup();
    v
}

fn run_external(bin: &PathBuf, args: &[String], json: bool) -> i32 {
    let me = std::env::current_exe().map(|p| p.to_string_lossy().to_string()).unwrap_or_else(|_| "dotos".into());
    match std::process::Command::new(bin).args(args)
        .env("DOTOS_BIN", me)
        .env("DOTOS_JSON", if json { "1" } else { "0" })
        .env("DOTOS_CONFIG", paths::config_dir())
        .env("DOTOS_DATA", paths::data_dir())
        .status()
    {
        Ok(s) => s.code().unwrap_or(1),
        Err(e) => { eprintln!("dotos: {}: {e}", bin.display()); 1 }
    }
}

fn distance(a: &str, b: &str) -> usize {
    let (a, b): (Vec<char>, Vec<char>) = (a.chars().collect(), b.chars().collect());
    let mut row: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut prev = row[0];
        row[0] = i;
        for j in 1..=b.len() {
            let cur = row[j];
            row[j] = (row[j] + 1).min(row[j - 1] + 1).min(prev + usize::from(a[i - 1] != b[j - 1]));
            prev = cur;
        }
    }
    row[b.len()]
}

/// The closest of `known` to `word`, when close enough to be a typo.
pub fn suggest<'a>(word: &str, known: impl IntoIterator<Item = &'a str>) -> Option<&'a str> {
    known.into_iter().map(|k| (distance(word, k), k)).filter(|(d, k)| *d <= 2.min(k.len() / 2).max(1) || k.starts_with(word) && word.len() >= 3)
        // a tie goes to the length nearest the word (projetc: project, not projects)
        .min_by_key(|(d, k)| (*d, k.len().abs_diff(word.len()))).map(|(_, k)| k)
}

fn noun_help(noun: &str) -> String {
    let Some((n, about, verbs)) = NOUNS.iter().find(|n| n.0 == noun) else { return String::new() };
    let mut s = format!("dotos {n} — {about}\n\n");
    for (v, runs, help) in verbs.iter().filter(|v| !v.2.is_empty()) {
        s += &format!("  dotos {n} {v:<10} {help}{}\n", if runs != v { format!("   (= dotos {runs})") } else { String::new() });
    }
    s
}

/// The overview: `dotos help` with no topic.
pub fn overview() -> String {
    let mut s = String::from("dotos — tasks, chat, projects and agents for a team\n\n  dotos NOUN VERB …   (each short form works too: dotos add, dotos list, dotos done 3)\n\n");
    for (n, about, _) in NOUNS {
        s += &format!("  dotos {n:<8} {about}\n");
    }
    s += "  dotos project  which folders Dotos takes on, and how\n";
    let ext = externals();
    if !ext.is_empty() { s += &format!("\nyour commands: {}\n", ext.join(", ")); }
    let al = aliases();
    if !al.is_empty() { s += &format!("aliases: {}\n", al.keys().cloned().collect::<Vec<_>>().join(", ")); }
    s += "\n  dotos help NOUN · dotos NOUN --help · dotos --help (every short form)\n";
    s
}

pub fn route(args: Vec<String>, json: bool) -> Route {
    let mut args = normalize(args);
    // aliases first (an alias may name a noun verb), a few levels deep at most
    for _ in 0..5 {
        let Some(first) = args.first().cloned() else { break };
        if COMMANDS.contains(&first.as_str()) || NOUNS.iter().any(|n| n.0 == first) { break }
        match aliases().get(&first).and_then(|v| v.as_str()) {
            Some(body) => args = expand_alias(body, &args[1..]),
            None => break,
        }
    }
    let Some(first) = args.first().cloned() else { return Route::Args(args) };

    if first == "help" {
        match args.get(1).map(String::as_str) {
            None => { print!("{}", overview()); return Route::Exit(0) }
            Some(n) if NOUNS.iter().any(|x| x.0 == n) => { print!("{}", noun_help(n)); return Route::Exit(0) }
            _ => return Route::Args(args),
        }
    }

    if let Some((noun, _, verbs)) = NOUNS.iter().find(|n| n.0 == first) {
        let verb = args.get(1).map(String::as_str);
        // `dotos team` and `dotos team --json` stay the old command
        if *noun == "team" && verb.is_none_or(|v| v.starts_with('-')) {
            return Route::Args(args);
        }
        match verb {
            None | Some("--help") | Some("-h") | Some("help") => { print!("{}", noun_help(noun)); return Route::Exit(0) }
            Some(v) => match verbs.iter().find(|x| x.0 == v) {
                Some((_, runs, _)) => {
                    let mut out: Vec<String> = runs.split(' ').map(String::from).collect();
                    out.extend(args[2..].iter().cloned());
                    return Route::Args(out);
                }
                None => {
                    let hint = suggest(v, verbs.iter().map(|x| x.0)).map(|s| format!("did you mean `dotos {noun} {s}`?\n\n")).unwrap_or_default();
                    eprint!("dotos {noun}: no verb '{v}'. {hint}{}", noun_help(noun));
                    return Route::Exit(2);
                }
            },
        }
    }

    if !COMMANDS.contains(&first.as_str()) && !first.starts_with('-') {
        if let Some(bin) = external(&first) {
            return Route::Exit(run_external(&bin, &args[1..], json));
        }
        let ext = externals();
        let al = aliases();
        let known: Vec<&str> = COMMANDS.iter().copied().chain(NOUNS.iter().map(|n| n.0)).chain(ext.iter().map(String::as_str)).chain(al.keys().map(String::as_str)).collect();
        if let Some(s) = suggest(&first, known) {
            eprintln!("dotos: no command '{first}'. Did you mean `dotos {s}`?\n(dotos help lists everything)");
            return Route::Exit(2);
        }
    }
    Route::Args(args)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn v(s: &[&str]) -> Vec<String> { s.iter().map(|x| x.to_string()).collect() }

    #[test]
    fn flags_are_normalized_until_double_dash() {
        assert_eq!(normalize(v(&["add", "x", "--due=fri", "-n", "--", "--note=keep", "-n"])), v(&["add", "x", "--due", "fri", "--dry-run", "--", "--note=keep", "-n"]));
    }

    #[test]
    fn aliases_fill_in() {
        assert_eq!(expand_alias("list --due today", &v(&["--all"])), v(&["list", "--due", "today", "--all"]));
        assert_eq!(expand_alias("say task:$1 \"hello there\" $2", &v(&["abc", "!"])), v(&["say", "task:abc", "hello there", "!"]));
        assert_eq!(expand_alias("find $@ --all", &v(&["a", "b"])), v(&["find", "a", "b", "--all"]));
    }

    #[test]
    fn noun_verb_runs_the_short_form() {
        match route(v(&["task", "add", "buy milk", "--due=fri"]), false) {
            Route::Args(a) => assert_eq!(a, v(&["add", "buy milk", "--due", "fri"])),
            Route::Exit(_) => panic!("routed to exit"),
        }
        match route(v(&["time", "start", "3"]), false) {
            Route::Args(a) => assert_eq!(a, v(&["track", "3"])),
            Route::Exit(_) => panic!(),
        }
    }

    #[test]
    fn typos_are_caught() {
        assert_eq!(suggest("lsit", COMMANDS.iter().copied()), Some("list"));
        assert_eq!(suggest("projetc", COMMANDS.iter().copied()), Some("project"));
        assert_eq!(suggest("zzzzzz", COMMANDS.iter().copied()), None);
    }
}
