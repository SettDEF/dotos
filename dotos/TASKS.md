# Dotos — tasks

Open work lives here, not in chat. See PLAN.md for why any of it.

## Now
- [x] M0: extract icalcore from kalendsd (ics, store, recur) — done; a cargo
      workspace at desktop/, kalends/kalendsd depends on icalcore, 34 tests
- [x] M1: VTODO read/write; add, list, done, undone, rm, edit, lists, status,
      where, --json — dotosd built and installed, 16 VTODO tests
- [ ] M1a: `dotos import`/`export`, to match the Kalends surface
- [x] Settings panel — showFinished (persisted) and defaultList (which finally
      makes `add --list` reachable from the window), plus the store paths from
      `dotos where`. Settings.qml mirrors Kalends'.

## Next
- [x] M2: the window — `dotos.qml`, one list grouped by overdue / today /
      tomorrow / this week / later / someday, one-line capture with
      `@due !priority #tag`. Installed as a desktop entry.
- [~] M3: ticking, unticking and deleting work from the window; editing a
      title in place does not yet (`Store.rename` exists, no UI for it).
- [ ] M4: recurrence (repeating chores; completing one advances the series)

## Later
- [ ] M5: sync — add the collection to Kalends' vdirsyncer config
- [ ] M6: replace the shell's 91-line JSON To Do singleton

## Explicitly not doing
Note editor, nested pages, backlinks, graph view, user-defined databases,
boards, Gantt, collaboration. A note on a task is the DESCRIPTION field.
See PLAN.md 1b for the reasoning.

## Blocked on a decision
- ~~One binary or two?~~ Two: `kalends` and `dotos`, sharing icalcore.
- ~~Priority direction?~~ Stored as RFC numbers (1 highest), shown and typed
  as high/normal/low.
- Replace the shell's To Do tab or keep both? Replacing needs a one-time
  migration of its existing JSON.
- Wait for Kalends M5 to land before starting Dotos M5? Debugging two syncing
  stores at once is worse than one.

## Teams (docs/teams.md: the conversation lives in the work)
- [~] Teams 1: threads on tasks — people (`dotos me`), a thread per task (`dotos thread`, `dotos say`, data/threads/*.jsonl) and the Conversation in the inspector, live: done; carried between people: next (LAN first, then a Matrix room per project)
- [x] Teams 1b: LAN sync — `dotos lan init|join|code|status|sync|serve|leave`; UDP broadcast discovery (47821), TCP 47820, HMAC proof of the team key, threads merged by id; runs inside `dotos serve`. Not yet encrypted (LAN only)
- [x] Teams 2: message → task (`dotos task-from ITEM MSG`, the panel's add_task button on a message): linked both ways, the first @mention is the assignee (X-DOTOS-ASSIGNEE, `dotos set ID assignee=…`, @chip on rows), the thread says "→ new task"
- [x] Teams 3: `@claude` (or `@agent`) in a thread: "on it", then Claude Code headless (`claude -p`) in the task's project folder with the task + last 20 messages; its answer posted as agent:claude replying to the ask. Read-only tools by default; config.json "agent_mode": "edit" allows edits. Agents' and LAN-merged messages never start one (thread_agent.rs)
- [ ] Teams 4: decisions marked on messages, notifications (mention, assigned, blocked freed, due), shared CalDAV lists
- [ ] Teams 5: catch-up summary per project, voice notes, threads on page blocks and agent actions
