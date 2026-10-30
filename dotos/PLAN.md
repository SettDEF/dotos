# Dotos — tasks for this desktop

*todos with the t and d swapped.*

A task list that lives in plain files, syncs to the phone beside the calendar,
and is equally usable from a terminal and a window. The sibling of Kalends,
sharing its store, its sync and most of its code.

---

## 1. Why this, and not the four alternatives

**The shell's own To Do tab** is 91 lines writing a JSON array to a file. No due
dates, no priorities, no recurrence, and — the one that matters — no sync. A
task written there is trapped on this machine. It is a scratchpad, and it has
been treated as one.

**Todoist / TickTick** sync well and are someone else's database. The data is
not on disk in a format that outlives the subscription.

**Taskwarrior** is genuinely good and genuinely local, and this is the closest
call. It loses on one point: its format is its own, so nothing else reads it.
A task in Taskwarrior cannot appear on a phone's calendar app without a bridge
that someone has to maintain. `VTODO` can.

**Obsidian / Notion** are knowledge bases whose task features are a side effect
of being document stores. Checkboxes in prose are not a task list you can ask
"what is due today".

The gap is narrow and real: **tasks that sync to the phone, in a standard
format, readable from a terminal, with no account.** `VTODO` in a vdir is
exactly that, and the machinery already exists — Kalends built it.

---


---

## 1b. "At least as good as Notion and Obsidian"

Worth being precise, because the honest answer is *not the same as them, and
better at the part that matters here.*

**What a clone would cost.** Obsidian is roughly a decade of work; Notion is a
company. Matching either feature-for-feature means arriving years late with a
worse version of something free. That is not a plan, it is a way to never
ship.

**What they are actually good at.** Obsidian: linked markdown notes you own.
Notion: structured databases with many views. Both are *document stores whose
task features are a side effect*. Neither can answer "what is due today"
without being configured into doing so first.

**What they are both bad at, and this is the opening:**

| | Notion | Obsidian | Dotos |
|---|---|---|---|
| Works with no account | no | yes | yes |
| Data readable by other software | no | markdown, but tasks are prose | **VTODO — every calendar app reads it** |
| Answers "what now" unconfigured | no | no | that is the entire UI |
| On your phone | its own app | its own app + paid sync | **any CalDAV client, already** |
| Usable from a terminal | no | no | first-class |

**Phone support is not a later milestone — it is a consequence of the format.**
This is the point worth understanding before anything is built. Because tasks
are stored as `VTODO` in a vdir and synced by CalDAV, they appear in whatever
task or calendar app the phone already has. There is no Dotos phone app to
write, and there never needs to be. Notion and Obsidian both require *their*
app; this requires none.

That is the bar to aim at: **not more features than Notion, but tasks that
outlive the app, reach the phone without an app, and answer the only question
a task list exists to answer.**

**What we deliberately do not build**, because it is how this becomes a
five-year project that never ships:

- a note editor — you have Neovim, and markdown files in a folder already *are*
  Obsidian's core value
- nested pages, wikis, backlinks, a graph view
- databases with user-defined schemas and multiple views
- boards, timelines, Gantt charts
- collaboration and sharing

If a note is ever wanted on a task, it is the `DESCRIPTION` field, which is
plain text and syncs. That is the whole answer.

> **Superseded in part, 2026-09-30.** The last two paragraphs no longer hold:
> pages are being built, and `DESCRIPTION` is not the whole answer. The rest
> of §1b stands — in particular the table, which every decision in
> [docs/pages.md](docs/pages.md) is chosen to keep true. See §1c.

## 1c. The flip: pages

§1b was right that cloning Notion is how this never ships, and that argument
is not withdrawn. What forced the change was a measurement rather than a
preference.

With a realistic store open at 1400x900, **96% of the window was empty
background.** Not a styling fault — restyling it twice did not move the
number. A task is a title, a checkbox, a date and some tags: one row, ~48px.
Three tasks is 290px of content in a 900px window. There is nothing else in
the model to draw.

Notion and Obsidian look full because a page is arbitrary nested content.
The richness is in the data model, not the CSS, and no UI work crosses that
gap.

So a document layer goes on top of the task store — **on top, not instead
of.** The rule for every decision that follows is that §1b's table stays
true: no account, files other software can read, "what now" answered
unconfigured, the phone reached with no app to install.

Three documents carry the design:

| | |
|---|---|
| [docs/pages.md](docs/pages.md) | storage, block types, what is still not built |
| [docs/todo-block.md](docs/todo-block.md) | the markdown-to-VTODO mapping, and why one task has one owner |
| [docs/editor.md](docs/editor.md) | live preview per block, and why no editor engine |
| [docs/stack.md](docs/stack.md) | React and Tauri, and what happens to the QML |

The UI in §5 is superseded by `docs/stack.md`.

## 2. Architecture

`VTODO` is an iCalendar component, like `VEVENT`. Same file format, same vdir
layout, same sync. The store Kalends already has can hold both.

That makes the central decision an easy one and an important one:

> **Do not write a second iCalendar parser.**

Kalends' parser has already had one silent-corruption bug found in it (TZID
discarded, events six hours wrong with no error). A second copy would get its
own bugs, differently, and the two would disagree.

    icalcore/          a library crate, extracted from kalendsd
      ics.rs           parse and serialise VEVENT and VTODO
      store.rs         the vdir, atomic writes, the bounds index
      recur.rs         RRULE expansion
    kalendsd/          events  — depends on icalcore
    dotosd/            tasks   — depends on icalcore
    dotos.qml          the window
    modules/           its QML

Extraction is the first milestone precisely because doing it later means
migrating two callers instead of one.

**Store.** Tasks go in their own vdir collections, beside the calendars:

    ~/.local/share/kalends/calendars/    VEVENT   (already exists)
    ~/.local/share/dotos/lists/          VTODO

Separate roots, because a task list and a calendar are different things to the
user even when they are the same thing to the format. vdirsyncer syncs both
from one config.

**What VTODO gives, that JSON did not:** DUE, PRIORITY, PERCENT-COMPLETE,
STATUS, CATEGORIES, RELATED-TO for subtasks, and RRULE for repeating chores —
all standard, all synced, all readable by any CalDAV client.

---

## 3. Milestones

Each is independently useful. None is a prerequisite for using the last.

**M0 — extract icalcore** *(no user-visible change)*
- move ics/store/recur out of kalendsd into a library crate
- kalendsd depends on it and behaves identically
- done when: every existing Kalends test still passes and `kalends` is
  byte-identical in behaviour

**M1 — the store and the terminal** *(no UI)*
- read/write VTODO: summary, due, priority, status, percent
- `add`, `list`, `done`, `rm`, `edit`, `--json`
- done when: a task added in the terminal survives a re-read and an external
  editor, and `dotos list` sorts sensibly by due date and priority

**M2 — the window**
- one list, grouped by due (overdue / today / this week / later / no date)
- quick capture, one line, the same shape Kalends uses
- done when: it shows a real list and matches `dotos list`

**M3 — editing and completion**
- tick, untick, edit in place, delete
- done when: the UI and the CLI can each modify what the other created

**M4 — recurrence**
- repeating chores via RRULE, reusing icalcore's expander
- completing one occurrence advances the series rather than ending it
- done when: a weekly bin-day task reappears after being ticked

**M5 — sync**
- the vdir is already the right shape; add the collection to Kalends'
  vdirsyncer config rather than writing a second one
- done when: a task added on the phone appears in `dotos list` within
  5 minutes, and one added here reaches the phone

**M6 — shell integration**
- replace the To Do tab's JSON singleton with this store
- the bar clock popup's To Do rows read from here
- due-today tasks join Kalends' reminder timer
- done when: closing the window does not stop a due reminder arriving

---

## 4. Terminal surface

    dotos                      what is due today, and what is overdue
    dotos list [--all]         open tasks; --all includes done
    dotos add TITLE [options]  add a task
    dotos done ID              tick it
    dotos undone ID            untick it
    dotos edit ID [options]    change one
    dotos rm ID                delete
    dotos lists                collections and their counts
    dotos status               store health, counts, last sync

    add/edit options
      --due WHEN       'today', 'tomorrow', 'fri', 'YYYY-MM-DD'
      --pri N          1 high, 5 normal, 9 low (RFC 5545 numbering)
      --list NAME      which collection
      --note TEXT      description
      --every RULE     'week', 'weekday', 'month' -> RRULE
      --json           machine-readable

Ids are uid prefixes, as in Kalends, so `dotos done 3f2a` works.

---

## 5. UI

One column, grouped by when it is due. Not a kanban, not a calendar — a list
that answers "what now" without being configured first.

- **Overdue** first, and visibly so. A task list that hides lateness is lying.
- **Today**, then **This week**, then **Later**, then **No date**.
- Ticking strikes through and fades, then moves out on the next load rather
  than vanishing under the cursor.
- Quick capture at the top: `Buy milk @fri !1` — due Friday, high priority.

Colours from kdeglobals, fonts from the desktop config, exactly as Kalends
does, so the two read as one suite.

---

## 6. Risks

| Risk | Answer |
|---|---|
| Two parsers drifting apart | M0 exists to prevent it; do not start M1 before it |
| Recurring completion semantics | RFC 5545 is ambiguous here. Pick "completing an occurrence creates the next" and write down why |
| VTODO support in phone apps varies | Test against the actual phone client before M5 is called done, not after |
| Scope creep toward Notion | Explicitly out: notes, nesting beyond one level, boards, tags-as-database |
| Another store to keep in sync | Reuse Kalends' bounds index rather than re-solving the full-rescan problem it already measured |

---

## 7. Decisions needed

1. **One binary or two?** `dotos` as its own command reads better than
   `kalends todo`, but two binaries means two argument parsers. Leaning two,
   sharing icalcore.
2. **Does the shell's To Do tab get replaced or kept alongside?** Replacing it
   means its existing JSON tasks need migrating — one-time, scriptable.
3. **Priority numbering.** RFC 5545 says 1 is highest, 9 lowest, which reads
   backwards to most people. Expose it as high/normal/low and store the
   numbers?
4. **Does this wait for Kalends M5?** Sync is one config either way, but
   debugging two syncing stores at once is worse than one.
