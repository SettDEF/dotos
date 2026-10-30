//! dotos-tui: Dotos in a terminal. Reads `dotos snapshot`, changes things through the `dotos` CLI.

use anyhow::Result;
use crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyModifiers, MouseEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Clear, Paragraph, Wrap};
use ratatui::Terminal;
use serde::Deserialize;
use std::collections::HashMap;
use std::io;
use std::process::Command;
use std::time::{Duration, Instant};

// ---------- data (the snapshot's shape) ----------

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct Task {
    uid: String,
    title: String,
    state: String,
    bucket: String,
    list: String,
    project: String,
    tags: Vec<String>,
    priority: String,
    due: Option<String>,
    due_time: bool,
    estimate_min: u32,
    notes: String,
    overdue: bool,
    blocked: bool,
    waiting_on: String,
    origin: String,
    tracked_today_s: u64,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct Git {
    branch: String,
    dirty: u32,
    ahead: u32,
    behind: u32,
    last_subject: String,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct Project {
    name: String,
    path: String,
    health: String,
    open: u32,
    overdue: u32,
    agents: u32,
    agents_need_you: u32,
    git: Option<Git>,
    time_week_s: u64,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct ClaudeTask {
    subject: String,
    status: String,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct Agent {
    id: String,
    state: String,
    project: String,
    prompt: String,
    cwd: String,
    tools: u64,
    failed: u64,
    last_tool: String,
    updated: i64,
    claude_tasks: Vec<ClaudeTask>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct Snapshot {
    tasks: Vec<Task>,
    agents: Vec<Agent>,
    projects: Vec<Project>,
    today: String,
}

// ---------- theme (tinct's colours, overridable in tui.json) ----------

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct Theme {
    fg: String,
    accent: String,
    dim: String,
    warn: String,
    crit: String,
    ok: String,
    border: String,
    sel: String,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default)]
struct Config {
    theme: Theme,
    border_style: Option<String>,
    keys: HashMap<String, String>,
}

#[derive(Clone, Copy)]
struct Pal {
    fg: Color,
    accent: Color,
    dim: Color,
    warn: Color,
    crit: Color,
    ok: Color,
    border: Color,
    sel: Color,
}

fn hex(h: &str, or: Color) -> Color {
    let h = h.trim_start_matches('#');
    if h.len() != 6 {
        return or;
    }
    let p = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).ok();
    match (p(0), p(2), p(4)) {
        (Some(r), Some(g), Some(b)) => Color::Rgb(r, g, b),
        _ => or,
    }
}

fn palette(cfg: &Theme) -> Pal {
    let path = format!("{}/.local/state/quickshell/user/generated/colors.json", std::env::var("HOME").unwrap_or_default());
    let v: serde_json::Value = std::fs::read_to_string(path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    let t = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    let pick = |own: &str, tinct: String, or: Color| hex(if own.is_empty() { &tinct } else { own }, or);
    Pal {
        fg: pick(&cfg.fg, t("on_surface"), Color::Reset),
        accent: pick(&cfg.accent, t("primary"), Color::Cyan),
        dim: pick(&cfg.dim, t("on_surface_variant"), Color::DarkGray),
        warn: pick(&cfg.warn, t("tertiary"), Color::Yellow),
        crit: pick(&cfg.crit, t("error"), Color::Red),
        ok: pick(&cfg.ok, t("secondary"), Color::Green),
        border: pick(&cfg.border, t("outline_variant"), Color::DarkGray),
        sel: pick(&cfg.sel, t("surface_container_high"), Color::DarkGray),
    }
}

// ---------- pages, rows ----------

#[derive(Clone, Copy, PartialEq)]
enum Page {
    Today,
    Inbox,
    Tasks,
    Projects,
    Agents,
}

const PAGES: [(Page, &str); 5] = [(Page::Today, "Today"), (Page::Inbox, "Inbox"), (Page::Tasks, "Tasks"), (Page::Projects, "Projects"), (Page::Agents, "Agents")];

/// One line of the list: a group heading or an item (index into its page's data).
#[derive(Clone)]
enum Row {
    Head(&'static str, usize),
    Item(usize),
}

#[derive(Clone, PartialEq)]
enum Input {
    None,
    Capture,
    Edit(String),
    Filter,
    Command,
    Confirm(String),
}

struct App {
    snap: Snapshot,
    page: Page,
    /// the selected item, by its key (uid, project name, agent id): kept across reloads
    sel_key: String,
    scroll: usize,
    input: Input,
    buf: String,
    filter: String,
    show_done: bool,
    help: bool,
    msg: (String, Instant, bool),
    quit: bool,
    pal: Pal,
    borders: BorderType,
    keys: HashMap<String, String>,
    loaded: Instant,
    list_area: Rect,
}

const BUCKETS: [(&str, &str); 8] = [("doing", "Doing"), ("overdue", "Overdue"), ("today", "Today"), ("tomorrow", "Tomorrow"), ("week", "This week"), ("later", "Later"), ("someday", "Someday"), ("done", "Done")];

impl App {
    fn new() -> Self {
        let path = format!("{}/.config/dotos/tui.json", std::env::var("HOME").unwrap_or_default());
        let cfg: Config = std::fs::read_to_string(&path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
        let borders = match cfg.border_style.as_deref() {
            Some("plain") => BorderType::Plain,
            Some("double") => BorderType::Double,
            Some("thick") => BorderType::Thick,
            _ => BorderType::Rounded,
        };
        let mut a = App {
            snap: Snapshot::default(),
            page: Page::Today,
            sel_key: String::new(),
            scroll: 0,
            input: Input::None,
            buf: String::new(),
            filter: String::new(),
            show_done: false,
            help: false,
            msg: (String::new(), Instant::now(), false),
            quit: false,
            pal: palette(&cfg.theme),
            borders,
            keys: cfg.keys,
            loaded: Instant::now(),
            list_area: Rect::default(),
        };
        a.reload();
        a
    }

    fn reload(&mut self) {
        match dotos_json(&["snapshot"]) {
            Ok(s) => self.snap = s,
            Err(e) => self.say(format!("could not read dotos: {e}"), true),
        }
        self.loaded = Instant::now();
    }

    fn say(&mut self, m: String, err: bool) {
        self.msg = (m, Instant::now(), err);
    }

    fn matches(&self, t: &Task) -> bool {
        if self.filter.is_empty() {
            return true;
        }
        let f = self.filter.to_lowercase();
        t.title.to_lowercase().contains(&f) || t.project.to_lowercase().contains(&f) || t.tags.iter().any(|g| g.to_lowercase().contains(&f))
    }

    /// The tasks of a page, in bucket order.
    fn tasks(&self, page: Page) -> Vec<usize> {
        let mut v: Vec<usize> = (0..self.snap.tasks.len())
            .filter(|&i| {
                let t = &self.snap.tasks[i];
                let open = t.state != "done" && t.state != "cancelled";
                let on = match page {
                    Page::Today => open && (t.bucket == "overdue" || t.bucket == "today" || t.state == "doing"),
                    Page::Inbox => t.state == "inbox",
                    Page::Tasks => open || self.show_done,
                    _ => false,
                };
                on && self.matches(t)
            })
            .collect();
        let rank = |b: &str| BUCKETS.iter().position(|(k, _)| *k == b).unwrap_or(9);
        // by group, doing first inside one, then by due, then title
        v.sort_by(|&a, &b| {
            let (x, y) = (&self.snap.tasks[a], &self.snap.tasks[b]);
            rank(group(x, page)).cmp(&rank(group(y, page))).then((y.state == "doing").cmp(&(x.state == "doing"))).then(x.due.cmp(&y.due)).then(x.title.to_lowercase().cmp(&y.title.to_lowercase()))
        });
        v
    }

    fn rows(&self) -> Vec<Row> {
        match self.page {
            Page::Projects => {
                let mut v: Vec<usize> = (0..self.snap.projects.len()).filter(|&i| self.filter.is_empty() || self.snap.projects[i].name.to_lowercase().contains(&self.filter.to_lowercase())).collect();
                let rank = |h: &str| match h { "active" => 0, "quiet" => 1, _ => 2 };
                v.sort_by(|&a, &b| {
                    let (x, y) = (&self.snap.projects[a], &self.snap.projects[b]);
                    rank(&x.health).cmp(&rank(&y.health)).then(y.open.cmp(&x.open)).then(x.name.cmp(&y.name))
                });
                v.into_iter().map(Row::Item).collect()
            }
            Page::Agents => {
                let rank = |s: &str| match s { "ready" => 0, "working" => 1, _ => 2 };
                let mut v: Vec<usize> = (0..self.snap.agents.len()).collect();
                v.sort_by(|&a, &b| {
                    let (x, y) = (&self.snap.agents[a], &self.snap.agents[b]);
                    rank(&x.state).cmp(&rank(&y.state)).then(y.updated.cmp(&x.updated))
                });
                v.into_iter().map(Row::Item).collect()
            }
            p => {
                let mut out = Vec::new();
                let mut cur = "";
                for i in self.tasks(p) {
                    let b = group(&self.snap.tasks[i], p);
                    if b != cur && p != Page::Inbox {
                        let label = BUCKETS.iter().find(|(k, _)| *k == b).map(|(_, l)| *l).unwrap_or("Other");
                        let n = self.tasks(p).iter().filter(|&&j| group(&self.snap.tasks[j], p) == b).count();
                        out.push(Row::Head(label, n));
                        cur = b;
                    }
                    out.push(Row::Item(i));
                }
                out
            }
        }
    }

    fn key_of(&self, r: &Row) -> String {
        match (r, self.page) {
            (Row::Item(i), Page::Projects) => self.snap.projects[*i].name.clone(),
            (Row::Item(i), Page::Agents) => self.snap.agents[*i].id.clone(),
            (Row::Item(i), _) => self.snap.tasks[*i].uid.clone(),
            _ => String::new(),
        }
    }

    /// The selected row's position (the first item when the key is gone).
    fn sel_pos(&self, rows: &[Row]) -> Option<usize> {
        rows.iter().position(|r| matches!(r, Row::Item(_)) && self.key_of(r) == self.sel_key).or_else(|| rows.iter().position(|r| matches!(r, Row::Item(_))))
    }

    fn move_sel(&mut self, d: isize) {
        let rows = self.rows();
        let items: Vec<usize> = rows.iter().enumerate().filter(|(_, r)| matches!(r, Row::Item(_))).map(|(i, _)| i).collect();
        if items.is_empty() {
            return;
        }
        let cur = self.sel_pos(&rows).and_then(|p| items.iter().position(|&i| i == p)).unwrap_or(0) as isize;
        let next = (cur + d).clamp(0, items.len() as isize - 1) as usize;
        self.sel_key = self.key_of(&rows[items[next]]);
    }

    fn sel_task(&self) -> Option<Task> {
        if matches!(self.page, Page::Projects | Page::Agents) {
            return None;
        }
        self.snap.tasks.iter().find(|t| t.uid == self.sel_key).cloned()
    }

    fn set_page(&mut self, p: Page) {
        self.page = p;
        self.sel_key.clear();
        self.scroll = 0;
    }

    /// A dotos command; reloads and reports the result.
    fn run(&mut self, args: &[&str], ok: &str) {
        match Command::new("dotos").args(args).output() {
            Ok(o) if o.status.success() => {
                self.say(ok.to_string(), false);
                self.reload();
            }
            Ok(o) => {
                let e = String::from_utf8_lossy(&o.stderr).trim().to_string();
                let out = String::from_utf8_lossy(&o.stdout).trim().to_string();
                self.say(if e.is_empty() { out } else { e }, true);
            }
            Err(e) => self.say(format!("dotos: {e}"), true),
        }
    }
}

fn dotos_json(args: &[&str]) -> Result<Snapshot> {
    let out = Command::new("dotos").args(args).output()?;
    if !out.status.success() {
        anyhow::bail!("{}", String::from_utf8_lossy(&out.stderr).trim());
    }
    Ok(serde_json::from_slice(&out.stdout)?)
}

fn short(uid: &str) -> &str {
    &uid[..8.min(uid.len())]
}

// ---------- keys ----------

fn key_name(k: &KeyEvent) -> String {
    let base = match k.code {
        KeyCode::Char(c) => c.to_string(),
        KeyCode::Enter => "enter".into(),
        KeyCode::Esc => "esc".into(),
        KeyCode::Up => "up".into(),
        KeyCode::Down => "down".into(),
        KeyCode::Left => "left".into(),
        KeyCode::Right => "right".into(),
        KeyCode::Home => "home".into(),
        KeyCode::End => "end".into(),
        KeyCode::Tab => "tab".into(),
        KeyCode::BackTab => "backtab".into(),
        KeyCode::PageUp => "pageup".into(),
        KeyCode::PageDown => "pagedown".into(),
        KeyCode::Delete => "delete".into(),
        _ => String::new(),
    };
    if k.modifiers.contains(KeyModifiers::CONTROL) && !base.is_empty() {
        format!("ctrl+{}", base.to_lowercase())
    } else {
        base
    }
}

/// The action a key does: tui.json "keys" first ({"ctrl+n": "capture"}), then the defaults.
fn action(app: &App, k: &KeyEvent) -> &'static str {
    let n = key_name(k);
    if let Some(a) = app.keys.get(&n) {
        return ACTIONS.iter().find(|x| **x == a.as_str()).copied().unwrap_or("none");
    }
    match n.as_str() {
        "q" | "ctrl+c" => "quit",
        "j" | "down" => "down",
        "k" | "up" => "up",
        "g" | "home" => "top",
        "G" | "end" => "bottom",
        "ctrl+d" | "pagedown" => "pagedown",
        "ctrl+u" | "pageup" => "pageup",
        "tab" | "l" | "right" => "next_page",
        "backtab" | "h" | "left" => "prev_page",
        "1" => "page_today",
        "2" => "page_inbox",
        "3" => "page_tasks",
        "4" => "page_projects",
        "5" => "page_agents",
        "x" | "enter" | " " => "toggle",
        "s" => "start",
        "w" => "wait",
        "a" | "c" | "o" => "capture",
        "e" => "edit",
        "d" | "delete" => "delete",
        "t" => "track",
        "/" => "filter",
        ":" => "command",
        "D" => "show_done",
        "r" => "reload",
        "?" => "help",
        "esc" => "escape",
        _ => "none",
    }
}

const ACTIONS: [&str; 27] = ["quit", "down", "up", "top", "bottom", "pagedown", "pageup", "next_page", "prev_page", "page_today", "page_inbox", "page_tasks", "page_projects", "page_agents", "toggle", "start", "wait", "capture", "edit", "delete", "track", "filter", "command", "show_done", "reload", "help", "escape"];

fn on_key(app: &mut App, k: KeyEvent) {
    if app.help {
        app.help = false;
        return;
    }
    if app.input != Input::None {
        return on_input_key(app, k);
    }
    let page_ix = PAGES.iter().position(|(p, _)| *p == app.page).unwrap_or(0);
    match action(app, &k) {
        "quit" => app.quit = true,
        "down" => app.move_sel(1),
        "up" => app.move_sel(-1),
        "top" => app.move_sel(-100_000),
        "bottom" => app.move_sel(100_000),
        "pagedown" => app.move_sel((app.list_area.height / 2).max(1) as isize),
        "pageup" => app.move_sel(-((app.list_area.height / 2).max(1) as isize)),
        "next_page" => app.set_page(PAGES[(page_ix + 1) % PAGES.len()].0),
        "prev_page" => app.set_page(PAGES[(page_ix + PAGES.len() - 1) % PAGES.len()].0),
        "page_today" => app.set_page(Page::Today),
        "page_inbox" => app.set_page(Page::Inbox),
        "page_tasks" => app.set_page(Page::Tasks),
        "page_projects" => app.set_page(Page::Projects),
        "page_agents" => app.set_page(Page::Agents),
        "toggle" => {
            if let Some(t) = app.sel_task() {
                // the next row keeps the selection when this one leaves the view
                if t.state != "done" && !app.show_done {
                    app.move_sel(1);
                    if app.sel_key == t.uid {
                        app.move_sel(-1);
                    }
                }
                if t.state == "done" { app.run(&["undone", short(&t.uid)], &format!("reopened: {}", t.title)) } else { app.run(&["done", short(&t.uid)], &format!("done: {}", t.title)) }
            }
        }
        "start" => {
            if let Some(t) = app.sel_task() {
                let to = if t.state == "doing" { "todo" } else { "doing" };
                app.run(&["state", short(&t.uid), to], &format!("{to}: {}", t.title));
            }
        }
        "wait" => {
            if let Some(t) = app.sel_task() {
                let to = if t.state == "waiting" { "todo" } else { "waiting" };
                app.run(&["state", short(&t.uid), to], &format!("{to}: {}", t.title));
            }
        }
        "track" => {
            if let Some(t) = app.sel_task() {
                app.run(&["track", short(&t.uid)], &format!("tracking: {}", t.title));
            }
        }
        "capture" => {
            app.input = Input::Capture;
            app.buf.clear();
        }
        "edit" => {
            if let Some(t) = app.sel_task() {
                app.buf = t.title.clone();
                app.input = Input::Edit(t.uid);
            }
        }
        "delete" => {
            if let Some(t) = app.sel_task() {
                app.input = Input::Confirm(t.uid);
            }
        }
        "filter" => {
            app.input = Input::Filter;
            app.buf = app.filter.clone();
        }
        "command" => {
            app.input = Input::Command;
            app.buf.clear();
        }
        "show_done" => {
            app.show_done = !app.show_done;
            let m = if app.show_done { "showing finished tasks" } else { "finished tasks hidden" };
            app.say(m.into(), false);
        }
        "reload" => {
            app.reload();
            app.say("reloaded".into(), false);
        }
        "help" => app.help = true,
        "escape" => {
            app.filter.clear();
        }
        _ => {}
    }
}

fn on_input_key(app: &mut App, k: KeyEvent) {
    let input = app.input.clone();
    if let Input::Confirm(uid) = &input {
        app.input = Input::None;
        if matches!(k.code, KeyCode::Char('y') | KeyCode::Char('Y')) {
            let title = app.snap.tasks.iter().find(|t| &t.uid == uid).map(|t| t.title.clone()).unwrap_or_default();
            app.move_sel(1);
            if &app.sel_key == uid {
                app.move_sel(-1);
            }
            app.run(&["rm", short(uid)], &format!("deleted: {title}"));
        } else {
            app.say("kept".into(), false);
        }
        return;
    }
    match k.code {
        KeyCode::Esc => {
            app.input = Input::None;
            app.buf.clear();
        }
        KeyCode::Enter => {
            let line = app.buf.trim().to_string();
            app.input = Input::None;
            app.buf.clear();
            match input {
                Input::Capture if !line.is_empty() => app.run(&["capture", &line], &format!("added: {line}")),
                Input::Edit(uid) if !line.is_empty() => app.run(&["set", short(&uid), &format!("title={line}")], "renamed"),
                Input::Filter => {
                    app.filter = line;
                    app.sel_key.clear();
                }
                Input::Command if !line.is_empty() => {
                    let args: Vec<&str> = line.split_whitespace().collect();
                    match Command::new("dotos").args(&args).output() {
                        Ok(o) => {
                            let s = String::from_utf8_lossy(if o.status.success() { &o.stdout } else { &o.stderr }).trim().lines().last().unwrap_or("").to_string();
                            app.say(if s.is_empty() { format!("ran: dotos {line}") } else { s }, !o.status.success());
                            app.reload();
                        }
                        Err(e) => app.say(format!("dotos: {e}"), true),
                    }
                }
                _ => {}
            }
        }
        KeyCode::Backspace => {
            app.buf.pop();
            if app.input == Input::Filter {
                app.filter = app.buf.clone();
            }
        }
        KeyCode::Char('u') if k.modifiers.contains(KeyModifiers::CONTROL) => app.buf.clear(),
        KeyCode::Char('w') if k.modifiers.contains(KeyModifiers::CONTROL) => {
            let t = app.buf.trim_end().rfind(' ').map(|i| i + 1).unwrap_or(0);
            app.buf.truncate(t);
        }
        KeyCode::Char(c) => {
            app.buf.push(c);
            // the filter narrows as it is typed
            if app.input == Input::Filter {
                app.filter = app.buf.clone();
                app.sel_key.clear();
            }
        }
        _ => {}
    }
}

// ---------- drawing ----------

fn fmt_min(m: u32) -> String {
    match (m / 60, m % 60) {
        (0, m) => format!("{m}m"),
        (h, 0) => format!("{h}h"),
        (h, m) => format!("{h}h{m:02}"),
    }
}

/// A due date as short as its group allows: a time today, a weekday this week, a date after.
fn due_label(t: &Task) -> String {
    let Some(d) = t.due.as_deref() else { return String::new() };
    let Ok(dt) = chrono::NaiveDateTime::parse_from_str(d, "%Y-%m-%dT%H:%M:%S").or_else(|_| chrono::NaiveDate::parse_from_str(&d[..10.min(d.len())], "%Y-%m-%d").map(|x| x.and_hms_opt(0, 0, 0).unwrap_or_default())) else { return String::new() };
    let time = if t.due_time { dt.format(" %H:%M").to_string() } else { String::new() };
    match t.bucket.as_str() {
        "today" if t.due_time => dt.format("%H:%M").to_string(),
        "today" => String::new(),
        "tomorrow" => format!("tmrw{time}"),
        "week" => format!("{}{time}", dt.format("%a")),
        _ => format!("{}{time}", dt.format("%-d %b")),
    }
}

fn glyph(state: &str) -> &'static str {
    match state {
        "doing" => "◐",
        "waiting" => "◷",
        "done" => "●",
        "cancelled" => "✕",
        "inbox" => "◇",
        _ => "○",
    }
}

fn trunc(s: &str, w: usize) -> String {
    if s.chars().count() <= w {
        return s.to_string();
    }
    let mut o: String = s.chars().take(w.saturating_sub(1)).collect();
    o.push('…');
    o
}

fn ago(ts: i64) -> String {
    if ts <= 0 {
        return String::new();
    }
    let d = chrono::Utc::now().timestamp() - ts;
    match d {
        d if d < 60 => "now".into(),
        d if d < 3600 => format!("{}m", d / 60),
        d if d < 86400 => format!("{}h", d / 3600),
        d => format!("{}d", d / 86400),
    }
}

fn ui(f: &mut ratatui::Frame, app: &mut App) {
    let p = app.pal;
    let area = f.area();
    let v = Layout::default().direction(Direction::Vertical).constraints([Constraint::Length(1), Constraint::Length(1), Constraint::Min(1), Constraint::Length(1)]).split(area);

    // tabs, with counts; what needs you on the right
    let count = |pg: Page| -> usize {
        match pg {
            Page::Projects => app.snap.projects.len(),
            Page::Agents => app.snap.agents.iter().filter(|a| a.state != "finished").count(),
            _ => app.tasks(pg).len(),
        }
    };
    let mut tabs: Vec<Span> = vec![Span::styled(" dotos ", Style::default().fg(p.accent).add_modifier(Modifier::BOLD)), Span::raw(" ")];
    for (i, (pg, name)) in PAGES.iter().enumerate() {
        let on = *pg == app.page;
        let n = count(*pg);
        let st = if on { Style::default().fg(p.accent).add_modifier(Modifier::BOLD | Modifier::UNDERLINED) } else { Style::default().fg(p.dim) };
        tabs.push(Span::styled(format!("{} {name}", i + 1), st));
        if n > 0 {
            tabs.push(Span::styled(format!(" {n}"), Style::default().fg(if on { p.fg } else { p.dim })));
        }
        tabs.push(Span::raw("   "));
    }
    f.render_widget(Paragraph::new(Line::from(tabs)), v[0]);
    let overdue = app.snap.tasks.iter().filter(|t| t.bucket == "overdue").count();
    let need = app.snap.agents.iter().filter(|a| a.state == "ready").count();
    let mut right: Vec<Span> = Vec::new();
    if overdue > 0 {
        right.push(Span::styled(format!("{overdue} overdue"), Style::default().fg(p.crit)));
    }
    if need > 0 {
        if !right.is_empty() {
            right.push(Span::styled(" · ", Style::default().fg(p.dim)));
        }
        right.push(Span::styled(format!("{need} agent{} waiting", if need == 1 { "" } else { "s" }), Style::default().fg(p.warn)));
    }
    right.push(Span::raw(" "));
    f.render_widget(Paragraph::new(Line::from(right)).alignment(ratatui::layout::Alignment::Right), v[0]);

    // the filter, when one narrows the list
    let sub = if !app.filter.is_empty() {
        Line::from(vec![Span::styled(" filter ", Style::default().fg(p.dim)), Span::styled(app.filter.clone(), Style::default().fg(p.accent)), Span::styled("   Esc clears", Style::default().fg(p.dim))])
    } else {
        Line::from(Span::styled(format!(" {}", chrono::NaiveDate::parse_from_str(&app.snap.today, "%Y-%m-%d").map(|d| d.format("%A %-d %B").to_string()).unwrap_or_default()), Style::default().fg(p.dim)))
    };
    f.render_widget(Paragraph::new(sub), v[1]);

    // list | details (details only when there is room)
    let wide = area.width >= 100;
    let h = Layout::default().direction(Direction::Horizontal).constraints(if wide { vec![Constraint::Percentage(62), Constraint::Percentage(38)] } else { vec![Constraint::Percentage(100)] }).split(v[2]);
    draw_list(f, app, h[0]);
    if wide {
        draw_details(f, app, h[1]);
    }

    // the bottom line: an input, a message, or the keys
    let line = match &app.input {
        Input::Capture => Line::from(vec![Span::styled(" add ", Style::default().fg(p.accent).add_modifier(Modifier::BOLD)), Span::raw(app.buf.clone()), Span::styled("▏", Style::default().fg(p.accent)), Span::styled("   @fri 14:00 !high #tag ~30m +project", Style::default().fg(p.dim))]),
        Input::Edit(_) => Line::from(vec![Span::styled(" title ", Style::default().fg(p.accent).add_modifier(Modifier::BOLD)), Span::raw(app.buf.clone()), Span::styled("▏", Style::default().fg(p.accent))]),
        Input::Filter => Line::from(vec![Span::styled(" / ", Style::default().fg(p.accent).add_modifier(Modifier::BOLD)), Span::raw(app.buf.clone()), Span::styled("▏", Style::default().fg(p.accent))]),
        Input::Command => Line::from(vec![Span::styled(" :dotos ", Style::default().fg(p.accent).add_modifier(Modifier::BOLD)), Span::raw(app.buf.clone()), Span::styled("▏", Style::default().fg(p.accent))]),
        Input::Confirm(uid) => {
            let t = app.snap.tasks.iter().find(|t| &t.uid == uid).map(|t| t.title.clone()).unwrap_or_default();
            Line::from(vec![Span::styled(" delete ", Style::default().fg(p.crit).add_modifier(Modifier::BOLD)), Span::raw(trunc(&t, 60)), Span::styled("?  y yes · any other key keeps it", Style::default().fg(p.dim))])
        }
        Input::None if app.msg.1.elapsed() < Duration::from_secs(4) && !app.msg.0.is_empty() => Line::from(Span::styled(format!(" {}", app.msg.0), Style::default().fg(if app.msg.2 { p.crit } else { p.ok }))),
        Input::None => {
            let hint: &[(&str, &str)] = match app.page {
                Page::Projects | Page::Agents => &[("j/k", "move"), ("Tab", "page"), ("/", "filter"), ("r", "reload"), ("?", "help"), ("q", "quit")],
                _ => &[("x", "done"), ("s", "start"), ("a", "add"), ("e", "edit"), ("d", "delete"), ("/", "filter"), ("Tab", "page"), ("?", "help")],
            };
            let mut s: Vec<Span> = vec![Span::raw(" ")];
            for (k, what) in hint {
                s.push(Span::styled(*k, Style::default().fg(p.accent)));
                s.push(Span::styled(format!(" {what}   "), Style::default().fg(p.dim)));
            }
            Line::from(s)
        }
    };
    f.render_widget(Paragraph::new(line), v[3]);

    if app.help {
        draw_help(f, app);
    }
}

fn block<'a>(app: &App, title: &'a str) -> Block<'a> {
    Block::default().borders(Borders::ALL).border_type(app.borders).border_style(Style::default().fg(app.pal.border)).title(Span::styled(format!(" {title} "), Style::default().fg(app.pal.dim)))
}

fn draw_list(f: &mut ratatui::Frame, app: &mut App, area: Rect) {
    let p = app.pal;
    let title = PAGES.iter().find(|(pg, _)| *pg == app.page).map(|(_, n)| *n).unwrap_or("");
    let b = block(app, title);
    let inner = b.inner(area);
    f.render_widget(b, area);
    app.list_area = inner;
    let rows = app.rows();
    if rows.is_empty() {
        let empty = match app.page {
            _ if !app.filter.is_empty() => "Nothing matches the filter.",
            Page::Today => "Nothing due today. a adds a task.",
            Page::Inbox => "Inbox is empty.",
            Page::Agents => "No agent sessions.",
            _ => "Nothing here.",
        };
        f.render_widget(Paragraph::new(Span::styled(format!(" {empty}"), Style::default().fg(p.dim))), inner);
        return;
    }
    let sel = app.sel_pos(&rows).unwrap_or(0);
    if let Some(r) = rows.get(sel) {
        app.sel_key = app.key_of(r);
    }
    // keep the selection in view (a heading above it too)
    let hgt = inner.height as usize;
    if sel < app.scroll + 1 {
        app.scroll = sel.saturating_sub(1);
    }
    if sel >= app.scroll + hgt {
        app.scroll = sel + 1 - hgt;
    }
    let w = inner.width as usize;
    // the due and estimate columns only when a task on the page has one
    let cols = rows.iter().fold((false, false), |c, r| match (r, app.page) {
        (Row::Item(i), Page::Today | Page::Inbox | Page::Tasks) => (c.0 || !due_label(&app.snap.tasks[*i]).is_empty(), c.1 || app.snap.tasks[*i].estimate_min > 0),
        _ => c,
    });
    let mut lines: Vec<Line> = Vec::new();
    for (i, r) in rows.iter().enumerate().skip(app.scroll).take(hgt) {
        let on = i == sel;
        let bg = if on { Style::default().bg(p.sel) } else { Style::default() };
        let line = match r {
            Row::Head(label, n) => {
                let c = match *label { "Overdue" => p.crit, "Today" => p.accent, _ => p.dim };
                Line::from(vec![Span::styled(format!(" {label}"), Style::default().fg(c).add_modifier(Modifier::BOLD)), Span::styled(format!("  {n}"), Style::default().fg(p.dim))])
            }
            Row::Item(ix) => match app.page {
                Page::Projects => project_line(&app.snap.projects[*ix], w, p),
                Page::Agents => agent_line(&app.snap.agents[*ix], w, p),
                _ => task_line(&app.snap.tasks[*ix], w, p, cols),
            },
        };
        let line = if on { line.patch_style(bg) } else { line };
        // the selected row filled to the edge
        let pad = w.saturating_sub(line.width());
        let mut line = line;
        if on {
            line.spans.push(Span::styled(" ".repeat(pad), bg));
        }
        lines.push(line);
    }
    f.render_widget(Paragraph::new(lines), inner);
}

fn task_line(t: &Task, w: usize, p: Pal, cols: (bool, bool)) -> Line<'static> {
    let done = t.state == "done" || t.state == "cancelled";
    let gc = match t.state.as_str() {
        "doing" => p.accent,
        "waiting" => p.warn,
        "done" => p.ok,
        _ => p.dim,
    };
    // the right side: due, estimate, project (fixed widths so they line up)
    let due = due_label(t);
    let est = if t.estimate_min > 0 { fmt_min(t.estimate_min) } else { String::new() };
    let proj = if t.project.is_empty() { t.tags.first().map(|g| format!("#{g}")).unwrap_or_default() } else { format!("+{}", t.project) };
    let proj = trunc(&proj, 14);
    let right_w = if cols.0 { 10 } else { 0 } + if cols.1 { 6 } else { 0 } + 15;
    let title_w = w.saturating_sub(5 + right_w).max(8);
    let flag = if t.priority == "high" { "!" } else { " " };
    let title_style = if done { Style::default().fg(p.dim).add_modifier(Modifier::CROSSED_OUT) } else if t.blocked { Style::default().fg(p.dim) } else { Style::default().fg(p.fg) };
    let title = trunc(&t.title, title_w);
    let tw = title.chars().count();
    Line::from(vec![
        Span::styled(format!(" {} ", glyph(&t.state)), Style::default().fg(gc)),
        Span::styled(flag.to_string(), Style::default().fg(p.crit).add_modifier(Modifier::BOLD)),
        Span::styled(title, title_style),
        Span::raw(" ".repeat(title_w.saturating_sub(tw) + 1)),
        Span::styled(if cols.0 { format!("{due:>9} ") } else { String::new() }, Style::default().fg(if t.overdue { p.crit } else { p.dim })),
        Span::styled(if cols.1 { format!("{est:>5} ") } else { String::new() }, Style::default().fg(p.dim)),
        Span::styled(format!("{proj:<14} "), Style::default().fg(p.accent)),
    ])
}

fn project_line(pr: &Project, w: usize, p: Pal) -> Line<'static> {
    let (g, c) = match pr.health.as_str() {
        "active" => ("●", p.ok),
        "quiet" => ("○", p.dim),
        _ => ("◌", p.warn),
    };
    let git = pr.git.as_ref().map(|g| {
        let mut s = g.branch.clone();
        if g.dirty > 0 {
            s.push_str(&format!(" ±{}", g.dirty));
        }
        if g.ahead > 0 {
            s.push_str(&format!(" ↑{}", g.ahead));
        }
        s
    }).unwrap_or_default();
    let name_w = w.saturating_sub(4 + 9 + 9 + 18).max(8);
    let name = trunc(&pr.name, name_w);
    let nw = name.chars().count();
    Line::from(vec![
        Span::styled(format!(" {g} "), Style::default().fg(c)),
        Span::styled(name, Style::default().fg(p.fg)),
        Span::raw(" ".repeat(name_w.saturating_sub(nw) + 1)),
        Span::styled(format!("{:>8} ", if pr.open > 0 { format!("{} open", pr.open) } else { String::new() }), Style::default().fg(p.dim)),
        Span::styled(format!("{:>8} ", if pr.overdue > 0 { format!("{} late", pr.overdue) } else { String::new() }), Style::default().fg(p.crit)),
        Span::styled(format!("{:<17}", trunc(&git, 17)), Style::default().fg(p.dim)),
    ])
}

fn agent_line(a: &Agent, w: usize, p: Pal) -> Line<'static> {
    let (g, c, what) = match a.state.as_str() {
        "working" => ("◐", p.accent, "working"),
        "ready" => ("●", p.warn, "needs you"),
        _ => ("○", p.dim, "finished"),
    };
    let prompt = if a.prompt.trim().is_empty() { "(no prompt yet)".to_string() } else { a.prompt.replace('\n', " ") };
    let pw = w.saturating_sub(4 + 14 + 11 + 5).max(8);
    let pr = trunc(&prompt, pw);
    let n = pr.chars().count();
    Line::from(vec![
        Span::styled(format!(" {g} "), Style::default().fg(c)),
        Span::styled(format!("{:<13} ", trunc(&a.project, 13)), Style::default().fg(p.accent)),
        Span::styled(pr, Style::default().fg(if a.state == "finished" { p.dim } else { p.fg })),
        Span::raw(" ".repeat(pw.saturating_sub(n) + 1)),
        Span::styled(format!("{what:>10}"), Style::default().fg(c)),
        Span::styled(format!("{:>4}", ago(a.updated)), Style::default().fg(p.dim)),
    ])
}

fn kv(k: &str, v: String, p: Pal) -> Line<'static> {
    Line::from(vec![Span::styled(format!("{k:<10}"), Style::default().fg(p.dim)), Span::styled(v, Style::default().fg(p.fg))])
}

fn draw_details(f: &mut ratatui::Frame, app: &App, area: Rect) {
    let p = app.pal;
    let b = block(app, "Details");
    let inner = b.inner(area);
    f.render_widget(b, area);
    let mut l: Vec<Line> = Vec::new();
    match app.page {
        Page::Projects => {
            if let Some(pr) = app.snap.projects.iter().find(|x| x.name == app.sel_key) {
                l.push(Line::from(Span::styled(pr.name.clone(), Style::default().fg(p.fg).add_modifier(Modifier::BOLD))));
                l.push(Line::from(""));
                l.push(kv("path", pr.path.clone(), p));
                l.push(kv("health", pr.health.clone(), p));
                l.push(kv("open", format!("{} tasks, {} overdue", pr.open, pr.overdue), p));
                if pr.agents > 0 {
                    l.push(kv("agents", format!("{} ({} need you)", pr.agents, pr.agents_need_you), p));
                }
                if pr.time_week_s > 0 {
                    l.push(kv("this week", fmt_min((pr.time_week_s / 60) as u32), p));
                }
                if let Some(g) = &pr.git {
                    l.push(kv("branch", format!("{}  ±{} ↑{} ↓{}", g.branch, g.dirty, g.ahead, g.behind), p));
                    l.push(kv("last", g.last_subject.clone(), p));
                }
                let tasks: Vec<&Task> = app.snap.tasks.iter().filter(|t| t.project == pr.name && t.state != "done").collect();
                if !tasks.is_empty() {
                    l.push(Line::from(""));
                    l.push(Line::from(Span::styled("Open tasks", Style::default().fg(p.dim).add_modifier(Modifier::BOLD))));
                    for t in tasks.iter().take(12) {
                        l.push(Line::from(vec![Span::styled(format!("{} ", glyph(&t.state)), Style::default().fg(p.dim)), Span::raw(t.title.clone())]));
                    }
                }
            }
        }
        Page::Agents => {
            if let Some(a) = app.snap.agents.iter().find(|x| x.id == app.sel_key) {
                l.push(Line::from(Span::styled(a.prompt.replace('\n', " "), Style::default().fg(p.fg).add_modifier(Modifier::BOLD))));
                l.push(Line::from(""));
                l.push(kv("state", a.state.clone(), p));
                l.push(kv("project", a.project.clone(), p));
                l.push(kv("folder", a.cwd.clone(), p));
                l.push(kv("tools", format!("{} used, {} failed, last {}", a.tools, a.failed, a.last_tool), p));
                l.push(kv("updated", format!("{} ago", ago(a.updated)), p));
                if !a.claude_tasks.is_empty() {
                    l.push(Line::from(""));
                    l.push(Line::from(Span::styled("Its tasks", Style::default().fg(p.dim).add_modifier(Modifier::BOLD))));
                    for t in a.claude_tasks.iter().rev().take(14) {
                        let (g, c) = match t.status.as_str() { "completed" => ("●", p.ok), "in_progress" => ("◐", p.accent), _ => ("○", p.dim) };
                        l.push(Line::from(vec![Span::styled(format!("{g} "), Style::default().fg(c)), Span::raw(t.subject.clone())]));
                    }
                }
            }
        }
        _ => {
            if let Some(t) = app.sel_task() {
                l.push(Line::from(Span::styled(t.title.clone(), Style::default().fg(p.fg).add_modifier(Modifier::BOLD))));
                l.push(Line::from(""));
                l.push(kv("state", format!("{} {}", glyph(&t.state), t.state), p));
                if let Some(d) = &t.due {
                    l.push(Line::from(vec![Span::styled(format!("{:<10}", "due"), Style::default().fg(p.dim)), Span::styled(d.replace('T', " ").trim_end_matches(":00").to_string(), Style::default().fg(if t.overdue { p.crit } else { p.fg }))]));
                }
                if t.estimate_min > 0 {
                    l.push(kv("estimate", fmt_min(t.estimate_min), p));
                }
                if t.tracked_today_s > 0 {
                    l.push(kv("today", fmt_min((t.tracked_today_s / 60) as u32), p));
                }
                if !t.project.is_empty() {
                    l.push(kv("project", t.project.clone(), p));
                }
                l.push(kv("list", t.list.clone(), p));
                if !t.tags.is_empty() {
                    l.push(kv("tags", t.tags.iter().map(|g| format!("#{g}")).collect::<Vec<_>>().join(" "), p));
                }
                if !t.priority.is_empty() {
                    l.push(kv("priority", t.priority.clone(), p));
                }
                if !t.waiting_on.is_empty() {
                    l.push(kv("waiting on", t.waiting_on.clone(), p));
                }
                if t.blocked {
                    l.push(Line::from(Span::styled("blocked by another task", Style::default().fg(p.warn))));
                }
                l.push(kv("id", short(&t.uid).to_string(), p));
                if t.origin == "ai" {
                    l.push(kv("from", "an agent".into(), p));
                }
                if !t.notes.trim().is_empty() {
                    l.push(Line::from(""));
                    for n in t.notes.lines() {
                        l.push(Line::from(Span::styled(n.to_string(), Style::default().fg(p.fg))));
                    }
                }
            }
        }
    }
    f.render_widget(Paragraph::new(l).wrap(Wrap { trim: false }), Rect { x: inner.x + 1, width: inner.width.saturating_sub(2), ..inner });
}

fn draw_help(f: &mut ratatui::Frame, app: &App) {
    let p = app.pal;
    let rows: [(&str, &str); 18] = [
        ("j k  ↓ ↑", "move"),
        ("g G", "top, bottom"),
        ("Ctrl-d Ctrl-u", "half a page"),
        ("Tab  h l  1-5", "pages"),
        ("x  Enter", "done / reopen"),
        ("s", "start (doing) / stop"),
        ("w", "waiting / back"),
        ("t", "track time on it"),
        ("a", "add (capture line)"),
        ("e", "edit the title"),
        ("d", "delete (asks)"),
        ("/", "filter as you type"),
        ("Esc", "clear the filter"),
        ("D", "show finished tasks"),
        (":", "any dotos command"),
        ("r", "reload (also every 5 s)"),
        ("?", "this help"),
        ("q", "quit"),
    ];
    let w = 46u16.min(f.area().width);
    let h = (rows.len() as u16 + 4).min(f.area().height);
    let a = f.area();
    let r = Rect { x: a.x + (a.width.saturating_sub(w)) / 2, y: a.y + (a.height.saturating_sub(h)) / 2, width: w, height: h };
    f.render_widget(Clear, r);
    let b = block(app, "Keys");
    let inner = b.inner(r);
    f.render_widget(b, r);
    let mut l: Vec<Line> = rows.iter().map(|(k, v)| Line::from(vec![Span::styled(format!(" {k:<16}"), Style::default().fg(p.accent)), Span::styled(v.to_string(), Style::default().fg(p.fg))])).collect();
    l.push(Line::from(Span::styled(" keys: ~/.config/dotos/tui.json \"keys\"", Style::default().fg(p.dim))));
    f.render_widget(Paragraph::new(l), inner);
}

fn on_mouse(app: &mut App, kind: MouseEventKind, row: u16) {
    match kind {
        MouseEventKind::ScrollDown => app.move_sel(3),
        MouseEventKind::ScrollUp => app.move_sel(-3),
        MouseEventKind::Down(_) => {
            let a = app.list_area;
            if row >= a.y && row < a.y + a.height {
                let rows = app.rows();
                if let Some(r) = rows.get(app.scroll + (row - a.y) as usize) {
                    if matches!(r, Row::Item(_)) {
                        app.sel_key = app.key_of(r);
                    }
                }
            }
        }
        _ => {}
    }
}

fn main() -> Result<()> {
    if std::env::args().any(|a| a == "--help" || a == "-h") {
        println!("dotos-tui: Dotos in a terminal. ? inside shows the keys.");
        return Ok(());
    }
    let mut app = App::new();
    enable_raw_mode()?;
    let mut out = io::stdout();
    out.execute(EnterAlternateScreen)?;
    out.execute(EnableMouseCapture)?;
    // the terminal back to normal even when something panics
    let hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |i| {
        let _ = disable_raw_mode();
        let _ = io::stdout().execute(DisableMouseCapture);
        let _ = io::stdout().execute(LeaveAlternateScreen);
        hook(i);
    }));
    let mut term = Terminal::new(ratatui::backend::CrosstermBackend::new(out))?;
    while !app.quit {
        term.draw(|f| ui(f, &mut app))?;
        if event::poll(Duration::from_millis(500))? {
            match event::read()? {
                Event::Key(k) if k.kind == event::KeyEventKind::Press => on_key(&mut app, k),
                Event::Mouse(m) => on_mouse(&mut app, m.kind, m.row),
                _ => {}
            }
        } else if app.input == Input::None && app.loaded.elapsed() > Duration::from_secs(5) {
            // changes from the window, agents or the CLI show up by themselves
            app.reload();
        }
    }
    disable_raw_mode()?;
    term.backend_mut().execute(DisableMouseCapture)?;
    term.backend_mut().execute(LeaveAlternateScreen)?;
    Ok(())
}

/// A task's group: its due bucket; on Today what is being worked on comes first, as "Doing".
fn group(t: &Task, page: Page) -> &str {
    if page == Page::Today && t.state == "doing" && t.bucket != "overdue" {
        return "doing";
    }
    &t.bucket
}
