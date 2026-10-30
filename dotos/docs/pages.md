# Pages

The document layer. Decided 2026-09-30, overturning part of PLAN.md §1b.

## What changed, and what did not

§1b argued that cloning Notion is how this becomes a five-year project that
never ships. That argument still holds and is not being thrown away. What
changed is the finding that drove it: a task list is *structurally* sparse.
A task is a title, a checkbox, a date and some tags — one row, ~48px. The
window measured **96% empty background** with a realistic store open, and no
amount of restyling moves that, because there is nothing else in the model to
draw.

So pages are added. But the table in §1b is the thing that must survive —
works with no account, data readable by other software, answers "what now"
unconfigured, reaches the phone with no app. Every decision below is chosen
to keep that table true.

## Storage: markdown files, not a block database

    ~/.local/share/dotos/pages/**/*.md      documents
    ~/.local/share/dotos/lists/**/*.ics     VTODO, as now

Markdown with YAML frontmatter. Not a proprietary block store, and this is
not a small point: "data readable by other software" is the row in §1b's
table we are proudest of, and a block database would make it false. A page
stays openable in Neovim with nothing installed.

The editor is block-based; the *file* is markdown. There is no serialisation
step to get wrong: a block holds its own raw markdown text, and the file is
those blocks joined with newlines. See [editor.md](editor.md).

Frontmatter carries only what markdown cannot express:

```yaml
---
uid: 01J8K2...          # ULID, stable across renames
created: 2026-09-30
tags: [dotos, design]
---
```

## Links

`[[page name]]`, Obsidian-compatible. Backlinks are derived by indexing, not
stored. Resolution is by filename first, then by `uid` for pages that moved.

## Block types, v1

Deliberately short. Each one is a thing that has to be styled, serialised,
parsed back and tested.

| Block | Markdown |
|---|---|
| heading 1–3 | `#`, `##`, `###` |
| paragraph | text, with **bold** *italic* `code` [links]() ==highlight== |
| todo | `- [ ]` / `[~]` / `[x]` / `[-]` — see [todo-block.md](todo-block.md) |
| bullet / ordered list | `-` / `1.` |
| code block | fenced, with language |
| quote | `>` |
| callout | `> [!note]` — Obsidian's syntax |
| divider | `---` |

Deferred, in this order when wanted: tables, images and embeds, toggles,
columns.

## Still deliberately not built

Unchanged from §1b, and worth restating because a document layer invites all
of it:

- databases with user-defined schemas and multiple views
- boards, timelines, Gantt charts
- collaboration, sharing, presence
- a graph view

The last one is cheap to add and adds nothing. Obsidian's graph is a
screensaver.

## What this costs

Most of the 1401 lines of QML. See [stack.md](stack.md).
