# Dotos

Work, AI agents, life and knowledge in one window — and one CLI behind it.
*Started as todos with the t and d swapped; outgrew it.*

    ./install.sh            build, install, launcher entry, background service
    dotos-gui               the window (or Dotos in the launcher)
    dotos                   what is due today, from a terminal

## What it holds

| | Stored as | Why |
|---|---|---|
| Tasks | `VTODO` in `~/.local/share/dotos/lists/` | your phone reads them through the calendar sync |
| Pages, journal | markdown in `~/.local/share/dotos/pages`, `/journal` | readable by any editor; `- [ ]` lines are tasks |
| Projects | your folders under the project roots | the folder is the project; git and `TASKS.md` read live |
| Agents | the shell's ai-activity hooks | which Claude chat is working, needs you, finished |
| Time | timewarrior, tagged `dotos:<uid>` | already installed, driven from Neovim too |
| Habits | `~/.local/share/dotos/habits.json` | days done, streaks, weekly targets |
| Every change | `~/.local/state/dotos/events.jsonl` | who did it (you, an extension, the AI) — and undo |

Task fields a phone has no slot for (state, estimate, project, links,
origin, parent) live in `X-DOTOS-*` properties that other clients keep.

## The window

Vitals' layout, our look: a sidebar (Home · Inbox · Projects · Agents ·
Tasks · Board · Habits · Journal · Pages · History · Extensions · Settings),
one page at a time, a status bar with the running timer and the agents.
Everything goes through the CLI, so the window, the terminal, Neovim and the
extensions can never disagree. Keys: `?` in the window.

## Capture — one line, everywhere

    dotos capture "Call dentist @fri 14:00 !high #health ~30m +vane /work >waiting"

`@when` (today, fri, 20.10, +3d, 2026-10-20, then an optional HH:MM) ·
`!high` · `#tag` · `~30m` estimate · `+project` · `/list` · `>state`.
Anything that does not parse stays in the title.

The same line works wherever you are:

- **Super+R** anywhere on the desktop: a quick-capture popup (the tokens
  light up as you type) with the next six tasks under it — tick one, start
  its timer. `qs -c ii ipc call dotos add "…"` from scripts.
- **The bar**: the running timer, or the next task, with overdue/today
  counts. Click to capture, right click for this window, hover for the list.
- **The shell's To Do** (sidebar, desktop widget, clock popup) *is* Dotos —
  the old JSON list was moved in once (`todo.json.migrated`).
- **Neovim**: `<leader>oo` the list (x tick · d doing · s timer · e rename ·
  p priority · D delete · Enter details), `<leader>oa` add, `<leader>oc` a
  task from the cursor line or selection linked to file:line, `<leader>op`
  this project's tasks, `<leader>oj` today's journal, `<leader>os` stop.

## Extensions

Executable files in `~/.config/dotos/extensions/`, any language, described
by their header (`# @name`, `# @kind source|action|view`, `# @every`, `# @on`,
`# @option KEY TYPE DEFAULT "Label"`) — the same contract as Vitals' probes.
Shipped: **TODO comments** and **GitHub** (sources, off until you switch them
on), **Timer follows the task** (action). `dotos serve` runs the sources on
their schedule and sends reminders; the installer sets it up as a user
service.

## Teams

Share tasks and talk on them with people on your network, no server: see
[docs/teams.md](docs/teams.md#using-it-a-team-on-your-network-how-to) for adding a friend.

## The CLI

`dotos --help` lists everything. The v2 commands: `capture`, `state`, `set`,
`sub`, `track`/`stop`, `undo`, `log`, `projects`, `agents`, `page`,
`journal`, `habit`, `ext`, `snapshot`, `serve`. `--json` everywhere.

Parsing and storage come from [`icalcore`](../icalcore), shared with
[Kalends](../kalends). RETHINK.md is the plan this came from.
