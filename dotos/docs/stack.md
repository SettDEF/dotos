# Stack

Decided 2026-09-30. Replaces the QML window described in PLAN.md §5.

## Why not QML

Two requirements settle it, neither of them aesthetic.

**Web support**, which was asked for outright. A QML window runs on this
desktop and nowhere else. A web front end runs in Tauri on the desktop *and*
in a browser, from one codebase, with the same Rust daemon behind both.

**Block editing.** Nested blocks, drag-reorder, slash commands, inline marks,
selection spanning blocks. QML has no rich text editing worth the name —
`TextArea` is not a document editor. Building this in QML means writing a
document engine from scratch, which is the same trap as writing a text view
for burin, and it is the specific trap PLAN.md §1b was written to avoid.

## The pieces

Vite and React, and as close to nothing else as the job allows.

| Layer | Choice | Why |
|---|---|---|
| Build | Vite | fast, unopinionated, no framework attached |
| Framework | React + TypeScript | |
| Shell | Tauri v2 | system webview, Rust backend, ~10 MB, also see burin |
| Markdown | `marked` or `markdown-it` | parsing only. Small, one job, and the edge cases are genuinely nasty |
| Editor engine | **none** | see [editor.md](editor.md) |
| Primitives | **none** | the three we need are a slash menu, a context menu and a dialog |
| Components | **none** | no MUI, Chakra, shadcn, Ant or BlockNote |
| Backend | dotosd + icalcore | unchanged, becomes the Tauri backend |

**Why no editor engine.** TipTap on ProseMirror was the earlier
recommendation and it is the right answer for a general document editor. It
is not needed here because the editing model changed: blocks are rendered
HTML until focused, and the focused one is a plain `<textarea>`. That removes
the problem ProseMirror exists to solve. The full reasoning, and what it
costs, is in [editor.md](editor.md) — including the one thing that would
force a rewrite onto ProseMirror, which is collaborative editing.

**Why no Radix.** A slash menu is a positioned list with arrow-key
navigation. Worth writing at that size; not worth a dependency and its
styling conventions.

**Markdown parsing is the exception**, and deliberately. Writing an inline
tokeniser that gets nested emphasis, escapes and link edge cases right is a
bad week with a long tail of bugs, and it is a pure function with a stable
interface — exactly the shape of thing a library should be.

The component-library line is the point. For a UI whose whole reason to exist
is that it looks like nothing else, a component library is an argument you
have on every single element.

## What happens to the existing code

**Kept, unchanged.** `icalcore`, `dotosd`, the vdir store, 50 tests, the
terminal surface in §4. This is the part nobody else has and none of it is
UI.

**Replaced.** Roughly 1400 lines of QML. `Store.qml` (328 lines) does not
port — its logic belongs in the daemon, which is where it should have been,
since the terminal surface needs it too.

**Salvaged as design, not code.** `ui/Appearance.qml` holds the token groups
and the kdeglobals-first colour sourcing, with the reasoning for both. Those
tokens become CSS custom properties; the reasoning carries over intact.

## Theming

Unchanged in intent: colours come from kdeglobals, with `colors.json` as
fallback, resolved in the daemon and handed to the front end as CSS custom
properties. A browser-hosted instance falls back to a shipped palette, since
it has no kdeglobals to read.

## The shared risk with burin

Both projects now rest on Tauri, so both rest on WebKitGTK. Task #59 measures
it for burin. The threshold matters less here — a block editor tolerates
latency that a code editor does not — but one spike answers both, and it
should run before either UI is built.
