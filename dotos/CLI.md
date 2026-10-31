# The dotos CLI, rethought (2026-10-31)

The CLI is the one way into Dotos: the window, the shell, the TUI, agents, scripts and teammates
all run `dotos …`. Today it is ~60 verbs in one `match` with flags parsed by hand, a separate
palette table, and projects that are all scanned whether you want them or not. This is what it
becomes: **every part extendable, every behaviour an option, nothing done to a project you did
not ask for.** VISION.md says what Dotos is; this says how its command line works.

---

## 1. Principles

1. **Noun, verb, target, flags**: `dotos project track loom --github off`. Predictable, so
   completion, help and the palette can be generated.
2. **The short forms stay**: `dotos add`, `dotos list`, `dotos done 3` keep working (they are
   aliases of `task add`, `task list`, `task done`). Nothing that uses Dotos today breaks.
3. **One schema** describes every command, argument and flag. Help, shell completion, the
   window's palette, the TUI and the docs are made from it, so they cannot disagree.
4. **Everything extendable at every level**: new commands, new verbs on old nouns, aliases,
   hooks on every event, output templates, whole areas (§5).
5. **Every behaviour is an option**, at the right level: built-in default → the repo's
   `.dotos.toml` (the team's defaults for it) → space → machine (yours) → the command's flags.
   Yours wins over the team's: a project you turned `git=off` stays off whatever the repo says.
6. **Nothing automatic you did not ask for**: discovery is not tracking, tracking is not
   syncing, syncing is not sharing (§6).
7. **Safe to try**: every command that changes something has `--dry-run`; everything is an
   event, so `dotos undo` works; anything that reaches other people or GitHub asks first
   (`--yes` skips).
8. **Machine-readable always**: `--json` everywhere, `--format` for the rest; stable exit codes.
9. **Fast on old laptops**: the CLI asks `dotos serve` when it runs (cache, no re-scan) and does
   the work itself when it does not.

## 2. Grammar

```
dotos [global flags] <noun> <verb> [target…] [flags]      the full form
dotos [global flags] <shortcut> [args…]                   add, list, done, now, …
dotos <name> …                                            an external command or alias (§5)
```

### Global flags (every command)

| Flag | What |
|---|---|
| `--json` · `--jsonl` | JSON (one value), JSON lines (streams, big lists) |
| `--format table\|tsv\|ids\|'{{title}} ({{due}})'` | output as a table, tab-separated, only ids, or a template |
| `--space NAME` | act in that space (dev team, company, personal) |
| `--as HANDLE` | act as an agent/teammate where allowed (agents use it; logged) |
| `--dry-run` · `-n` | say what would happen, change nothing |
| `--yes` · `-y` | no questions (scripts) |
| `--quiet` · `-q`, `--verbose` · `-v` | less, more |
| `--color auto\|always\|never` · `--no-pager` | |
| `--offline` | no network: no sync, no GitHub; read the cache |
| `--config KEY=VAL` | one option for this run only |
| `--profile` | time each step (for slow old laptops) |

Exit codes: `0` ok · `1` failed · `2` usage · `3` not found · `4` refused (permission,
confirmation) · `5` offline/unreachable · `10+` an extension's own.

## 3. Nouns and verbs

| Noun | Verbs | Short forms kept |
|---|---|---|
| `task` | `add` `list` `show` `done` `undone` `edit` `set` `state` `mv` `rm` `sub` `snooze` `link` `assign` `track` `stop` | `add` `list`/`ls` `done` `undone` `edit` `rm` `capture`/`c` `state` `set` `sub` `track` `stop` `snooze` |
| `list` | `list` `add` `rename` `rm` `share` `unshare` `members` | `lists` |
| `project` | `list` `show` `track` `untrack` `ignore` `set` `mode` `roots` `exclude` `scan` `open` (§6) | `projects` |
| `page` · `journal` · `habit` | `list` `show` `new` `edit` `rm` `link` | `pages` `page` `journal` `habits` `habit` |
| `chat` (threads) | `list` `show` `say` `reply` `react` `read` `unread` `mute` `pin` `dm` `channel` | `thread` `threads` `say` `voice` `decide` `task-from` `catchup` `news` |
| `team` · `people` · `me` | `list` `show` `invite` `join` `remove` `set` | `team` `me` |
| `space` | `list` `new` `switch` `rm` `set` | |
| `sync` | `status` `now` `pause` `resume` `transport add\|rm\|list` `log` | `lan` |
| `gh` (GitHub) | `prs` `issues` `reviews` `ci` `repo` `notifications` `link` | `git …` |
| `agent` | `list` `run` `stop` `allow` `deny` `log` | `agents` `agent-run` |
| `time` | `start` `stop` `report` `week` | `track` `stop` `tracked` `week` |
| `plan` · `review` · `standup` | the day; the week; what I did / will do | `plan` `review` `week` |
| `search` | across everything, with `--in tasks,chat,prs,pages` | `find`/`search` |
| `activity` | `list` `done` `snooze` `watch` | |
| `event` | `log` `show` `undo` `watch` (`--follow`) | `log` `undo` `diff` |
| `ext` · `alias` · `hook` · `command` | `list` `add` `rm` `enable` `disable` `new` (scaffold) `test` | `ext` `lua` |
| `config` | `get` `set` `unset` `list` `edit` `path` | |
| `doctor` | checks this machine, says what to fix (§8) | |
| `serve` · `tui` · `shell` | the daemon; the terminal UI; a REPL with completion | `serve` |
| `import` · `export` · `backup` | GitHub issues, Todoist, Linear, Obsidian, CSV, ICS, JSON | `import` `export` `backup` |
| `completion` · `help` · `commands` | shells' completion; help from the schema; the schema itself | `completions` `commands` |

## 4. Output and input

- **Tables by default** in a terminal, aligned, with colour; **JSON** when piped and asked.
- **Templates**: `dotos task list --format '{{id}}\t{{title}}\t{{due|relative}}'` (filters:
  `relative`, `date`, `upper`, `trunc 40`, `default "-"`).
- **Selectors** for targets wherever one is taken: an id, a title start (`"fix the"`),
  `@me`, `#tag`, `+project`, `last`, `-` (read ids from stdin), a saved query (`?urgent`).
  So `dotos task list --format ids ?urgent | dotos task done -` works.
- **Interactive pickers** when a target is missing and stdin is a terminal (fzf if installed,
  a built-in list otherwise); never when piped.

## 5. Extending it: six layers

| Layer | How | For |
|---|---|---|
| **1. External commands** | any `dotos-NAME` executable in `$PATH` or `~/.config/dotos/commands/` is `dotos NAME …` (as git and cargo do). It gets `DOTOS_*` env (store, space, me, json mode, serve's socket) and may print JSON. `dotos command new NAME --lang sh\|py\|lua\|rust` scaffolds one | anything, any language |
| **2. Verbs on any noun** | `dotos-task-archive` → `dotos task archive` | growing a noun |
| **3. Aliases** | `config.toml` `[alias] today = "task list --due today --mine"`, with `$1`/`$@`; `dotos alias add NAME "…"` | your own words |
| **4. Lua** | `init.lua`: `dotos.command{ name = "standup", args = {...}, run = function(a) … end }`; `dotos.on("task.done", fn)`; `dotos.format("compact", fn)` | quick logic without a file per command |
| **5. Hooks and events** | every change is an event (`task.added`, `project.tracked`, `chat.message`, `gh.pr.merged`, `sync.received`, …). Hooks run commands or Lua on them, filtered (`--where 'project=loom'`) | automation: "a merged PR closes its task" |
| **6. Extensions** (today's) | sources, actions, views (the window's pages) | feeding items in, new pages |

Every layer registers into **the schema** (`dotos commands --json`): name, help, arguments,
flags with types and choices, examples, which layer it comes from. Help, completion (bash,
zsh, fish), the window's palette and the TUI read it, so a new external command shows up
everywhere at once. A command that does not describe itself (`--dotos-schema`) still runs,
it just has no completion.

## 6. Projects: discovered → tracked → synced → shared

Today every folder under the roots is a project, and each is git-scanned on every refresh
(18 repos on the second laptop, none chosen). Now four separate steps, each an option:

| Step | Means | Command |
|---|---|---|
| **discovered** | found under a root (`.git`, `TASKS.md`, `PLAN.md`, README); nothing done to it | `dotos project list --discovered` |
| **tracked** | in Dotos: its tasks, its page, its git state | `dotos project track loom zash` |
| **synced** | its tasks and threads go to your other laptops | `dotos project set loom sync=on` |
| **shared** | with the team (in a space) | `dotos project set loom share=dev-team` |
| **ignored** | never shown, never scanned | `dotos project ignore '*-wt-*'` |

**How new ones are treated** (`dotos project mode`):
`all` (today's: every discovered project is tracked) · `ask` (listed as new, waits for
`track`) · `manual` (only what you track).

**Per project** (`dotos project set NAME key=value …`, or `.dotos.toml` in the repo,
committed for the whole team):

| Key | Values | |
|---|---|---|
| `git` | `on` `off` (later `slow`: every 10 min) | read git state |
| `github` | `on` `off` `prs,issues,ci` | which GitHub parts Dotos follows |
| `todos` | `on` `off` `TODO,FIXME` | TODO comments become tasks (the extension) |
| `sync` · `share` | `off` `on` / a space | §above |
| `agents` | `allow` `ask` `deny` | may agents work in it, open PRs |
| `notify` | `all` `mentions` `none` | its Activity |
| `pin` · `color` · `icon` · `alias` | | how it shows |
| `roots` · `exclude` | globs | sub-folders (monorepos) |

`dotos project roots add ~/work`, `dotos project exclude add 'node_modules' '*-wt-*'`,
`dotos project scan` (now), `dotos project show loom` (everything about it, with where each
value came from: default, machine, `.dotos.toml`, flag).

## 7. Configuration

`dotos config` over one model with layers (each value says where it came from):
built-in → the project's `.dotos.toml` (the team's) → the space → `~/.config/dotos/config.toml`
and `projects.json` (this machine, yours) → environment `DOTOS_*` → `--config K=V`. `config.json` stays readable and is
migrated on first write. `dotos config set projects.mode ask`, `dotos config get --origin`.

## 8. `dotos doctor`

Checks this machine and says, in plain words, what to do. Born from the second laptop:

- the project roots exist (no `/mnt/storage` on this machine); worktrees are not projects
- `gh` signed in, and as whom; your GitHub login set (`dotos me --github auto`)
- sync: team paired, transports reachable, peers seen, lists shared on *both* sides
- the window can find Quickshell, its modules (QtQuick.Pdf for zett), the icon theme
- `dotos serve` running; extensions' commands exist; Lua loads
- the store: readable, git history, last backup
- `--fix` applies the safe ones; `--json` for the window's own health page

## 9. Safety

`--dry-run` on every change; every change an event (`dotos undo`, `dotos event undo ID`);
confirmations for anything leaving the machine (GitHub, chat, sharing) unless `--yes`;
`--as` only for agents and only where the space allows (`agent allow`); agents never start
from a message unless the sender is allowed (the `@claude` problem, VISION.md §9).

## 10. Ideas this makes easy

- `dotos standup`: yesterday / today / blocked, from events, posted to a channel on `--post`
- `dotos focus 50m`: timer on the task, notifications off, the window in focus mode
- `dotos do "move all loom TODOs to next week"`: an agent turns words into commands, shown
  with `--dry-run` first
- `dotos watch` / `dotos event watch --follow`: a live feed in a terminal
- `dotos pick`: fzf over anything, prints the id (for scripts and shell keybinds)
- `dotos clip`: the clipboard becomes a task, a page or a message
- `dotos open loom`: its folder in zash, its repo page, its chat, with `--in zett|window|web`
- `dotos import github SettDEF/ii-dots --issues`: issues become linked tasks
- `dotos inbox`: Activity in the terminal, `j/k`, `d` done, `s` snooze
- `dotos report time --week --by project --format csv`
- `dotos digest --mail`: the week for someone who does not open Dotos
- `dotos share page NAME --space company`: one page to the office space
- `dotos shell`: a REPL with completion from the schema, history, `!` for the real shell

## 11. Order of work

1. **Projects** (§6): modes, track/untrack/ignore, per-project options, exclude globs;
   `projects` honours them; git scanned only where `git` is on. (First: asked for, and the
   old laptop pays for every scan.)
2. **The core**: noun-verb dispatch with the short forms as aliases, the schema
   (`commands --json`), global flags (`--format`, `--dry-run`, `--offline`), external
   commands (§5.1–2) and aliases (§5.3).
3. **`dotos doctor`**.
4. **Completion and help from the schema**; the window's palette from it.
5. Lua commands, hooks on events; output templates; selectors and pickers.
6. The new nouns as their parts land: `space`, `sync`, `activity`, `chat` (VISION.md order).

`main.rs`'s one big `match` moves into one module per noun (`cli/task.rs`, `cli/project.rs`,
…), each registering its verbs into the schema, as the steps above reach them.
