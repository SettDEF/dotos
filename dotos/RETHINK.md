# Dotos — the rethink (2026-10-16)

Dotos is no longer a task manager. Asked what it should be, the answer was
**all of it**: mission control for work · AI agent command center · life OS ·
knowledge base with tasks inside. One app, one core, four spaces. Tasks are
one kind of object among several, not the point.

Scale: at least Vitals' depth (Vitals ≈ 8,000 lines; Dotos today ≈ 1,950 —
and today's window is, in the user's words, one of the worst on the desktop).
Everything customizable, extensions everywhere.

---

## 1. The core: objects, links, one index

Everything is an **object**, everything can **link** to everything:

| Object | Stored as (files stay the truth) | Why that format |
|---|---|---|
| Task | VTODO in a vdir | syncs to the phone with Kalends' vdirsyncer |
| Note / page | Markdown + front-matter in a vault | readable anywhere, Obsidian-compatible, git-able |
| Project | auto-discovered (`~/dev/projects/*`) + a `.dotos.md` page | the folder *is* the project; no double bookkeeping |
| Agent job | live state from AiActivity (§4) + a log | |
| Goal, habit, journal day | Markdown pages with typed front-matter | |
| Event | Kalends (read via its CLI) | one calendar, not two |
| Time | timewarrior, tagged `dotos:<id>` | already installed, Neovim plugin exists |

**dotosd** (Rust daemon, systemd user service like vitals-watch) keeps a
SQLite **index** over all of it — full-text search, backlinks, queries,
"what links here" — rebuilt from the files at any time, so the index can never
be the only copy of anything. It runs extensions and AI jobs, keeps the
**event log** (every change, by whom: you, an extension, an AI — undoable),
and streams changes to the window, the shell and Neovim.

**Databases** (the Notion idea): any query over objects is a saved view —
table, board, calendar, gallery, timeline — with filters, grouping, sorting
and computed fields. "All open tasks in projects tagged #client, by due" is a
view, not a feature.

## 2. The window — spaces in one sidebar app

```
┌ sidebar ───────────┬ toolbar: breadcrumb · search (Ctrl+K: everything) · ⋮ ─────┐
│ ⌂ Home             │                                                          │
│ ── Work ──         │  Home = today: agenda (Kalends), due tasks, agents that  │
│ ▣ Projects   14    │  need you, focus block, habits, yesterday's review       │
│ ◐ Agents  2 · ●1   │                                                          │
│ ── Life ──         │                                                          │
│ ◎ Goals            │                                                          │
│ ✓ Tasks      27    │                                                          │
│ ↻ Habits     3/5   │                                                          │
│ ✎ Journal          │                                                          │
│ ── Knowledge ──    │                                                          │
│ ❐ Pages            │                                                          │
│ ⊞ Databases        ├──────────────────────────────── inspector / backlinks ───┤
│ ── Extensions ──   │                                                          │
└────────────────────┴──── status: synced · 1 timer · 2 agents working ─────────┘
```

Vitals' chrome reused: collapsible sidebar, ⋮ menu, command palette, keybinds
sheet, settings, extensions page. Every space is a **page registered like
Vitals' pages**, so extensions add spaces the same way.

### Work — mission control
A project page shows, live: its tasks and board · git (branch, dirty files,
ahead/behind, last commits) · running Claude sessions in that folder · build
and test status (from an extension) · time spent this week · its notes,
TASKS.md and PLAN.md rendered · deadlines on a timeline. The Projects view is
a grid of project cards with health at a glance ("3 tasks overdue · agent
needs you · uncommitted changes for 4 days").

### Agents — command center
Every AI job in one place: Claude Code sessions, the shell's AI sidebar,
ComfyUI on the nuke, the copilot assistant, local models. State per job
(*queued · working · needs you · finished · failed*), project, prompt,
elapsed, cost where known; **jump to it** (focus the terminal/tmux pane);
results collected for review. **Dispatch**: give a task to an agent from
Dotos — the task waits on the agent and comes back for review when it
finishes.

### Life — the life OS
Goals (yearly/quarterly) → projects → tasks. Habits with streaks. A daily
journal page created each morning, with the day's agenda, done tasks and
tracked time filled in. Weekly review: what moved each goal, what slipped.
Focus mode: one task, a timer (timewarrior), notifications held.

### Knowledge — Notion-like
Pages with blocks: text, headings, checklists that are **real tasks**, embedded
database views, links `[[...]]` with backlinks, code blocks. Daily notes.
Templates (meeting, project kickoff, bug). Everything searchable from Ctrl+K.

## 3. Extensions — everywhere, with options

One contract (Vitals' probe header: `# @option KEY TYPE DEFAULT "Label"`),
four kinds:

- **source** — brings objects in: GitHub issues/PRs, `TODO:` comments in
  projects, email flags, RSS, Kalends prep events
- **action** — runs on events (created, done, due, state, agent finished):
  start a timer, notify, open the project, dispatch to an agent, webhook
- **view/space** — new pages in the sidebar (QML), new database view types
- **agent adapter** — teaches the Agents space a new AI tool

## 4. New shell service: AiActivity.qml

Shell-wide (bar, dock, notifications, and Dotos' Agents space read it).
- **Claude Code** via its hooks (`SessionStart`, `UserPromptSubmit`,
  `Notification`, `Stop`, `SessionEnd`) writing one JSON per session to
  `$XDG_RUNTIME_DIR/ai-activity/` — exact state, not guessed
- **The ii AI sidebar** (`services/Ai.qml`)
- **Other tools** through adapters (ComfyUI queue API, copilot, …)
- bar chip `◐ 2 working · ● 1 needs you · ✓ 3 done`, a panel with jump-to,
  notifications per source, silent while gaming

## 5. AI throughout — every behaviour switchable

Settings → AI: provider/model per feature (keys from `~/.secure/apikeys`),
each feature on/off, editable prompts, auto-apply or review.
- capture → structured objects (a sentence, a chat, an email → tasks with
  subtasks, due, estimate; a meeting → note + tasks)
- dispatch tasks to agents (§2 Agents)
- morning plan / evening review / weekly review, from tasks + Kalends + time
- ask your workspace: "what did I do on vitals this week?" answered from the
  index and the event log, with links
- rule: the model proposes, you dispose; every AI change is logged and undoable

## 6. Front ends

- **Window** (QML, §2)
- **Shell**: AiActivity chip/panel, quick-capture popup (keybind), Home summary
  in the sidebar, running timer
- **Neovim** (nui.nvim, same structure as `lua/core/timewarrior/`): capture,
  task board, project page, `TODO:` → task with file:line, agent state of the
  project's sessions. Plus the **border fix**: floats are #211f21 on a
  transparent editor with a fixed #4a454d border (nui's falls back to black) →
  border = the float's own background lifted toward its text colour, all
  popup borders linked to it.
- **CLI**: `dotos` for everything (`dotos add`, `dotos q "<query>"`,
  `dotos agents`, `--json` everywhere)

## Milestones

| | | why this order |
|---|---|---|
| M0 | Neovim borders | small, visible at once |
| M1 | AiActivity service + Claude Code hooks + bar chip/panel | useful the same day, feeds Agents |
| M2 | core: object model, dotosd, SQLite index, event log, stream | everything stands on it |
| M3 | app shell: sidebar spaces, Ctrl+K palette, inspector, settings, extensions page | |
| M4 | Work: projects (discovery, git, sessions, docs) + Tasks v2 | |
| M5 | Agents space + dispatch | needs M1, M4 |
| M6 | Knowledge: pages, links/backlinks, databases & views, templates | |
| M7 | Life: home, goals, habits, journal, reviews, focus + timewarrior | |
| M8 | AI features | needs M2–M7 data |
| M9 | Neovim front end, shell capture popup | |
| M10 | extension packs, recurrence, sync polish | |

Open: the name. "Dotos" (todos, swapped) fits a task list; this is bigger.
Renaming is free until it is installed under the new scope — decide before M3.
