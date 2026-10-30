# The editing model

Decided 2026-09-30. This is what makes a block editor possible on Vite +
React with no editor engine.

## The trap being avoided

The obvious build is one `contenteditable` holding the whole document. Do
not. That is where the months go: selection spanning blocks, undo that
respects block boundaries, IME composition, paste normalisation from Word
and browsers, caret movement across nodes. Browsers disagree about all of it.
ProseMirror exists because this is genuinely hard, and rejecting ProseMirror
while building its problem is the worst of both.

## What we do instead: live preview, per block

Obsidian's model, and it removes `contenteditable` almost entirely.

**A block not being edited is rendered HTML.** A `<div>` with the markdown
already turned into elements.

**The block with the caret in it is a `<textarea>`** holding that block's raw
markdown text, auto-sized to its content.

Click a paragraph, it becomes its source. Click away, it renders. The
document is a React array of blocks and nothing more:

```ts
type Block = { id: string, kind: Kind, text: string }
```

No document tree, no transaction system, no schema. The file on disk is that
array joined with newlines, which is why the storage format stayed markdown.

## What this buys

- **Editing is a plain textarea.** IME, undo, caret movement, autocorrect and
  mobile keyboards are the browser's problem, and the browser is good at it.
- **Copy across blocks still works.** Unfocused blocks are ordinary rendered
  elements, so native selection spans them and copies as text.
- **Inline marks are free.** `**bold**` is just characters in the textarea,
  rendered on blur. No mark storage, no inline schema.
- **It is the Obsidian half of the pitch**, not an approximation of it.

## What it costs, honestly

- **No rich selection across blocks while editing.** Selecting from the
  middle of one block to the middle of another and typing over it is not
  available. Notion has a separate block-selection mode for exactly this
  reason, and so do we: Esc leaves the text, arrows and shift move whole
  blocks, which covers delete, indent and reorder.
- **Paste from rich sources degrades.** Pasting styled HTML from a browser
  gives text, not formatting, until an HTML-to-markdown step is written.
- **Collaborative editing is off the table.** It needs a CRDT over a real
  document model. If that is ever wanted, it is a rewrite onto ProseMirror,
  and that should be a decision taken deliberately rather than discovered.

## The keyboard work, which is the actual job

This is where the effort goes, and it is bounded:

| Key | Behaviour |
|---|---|
| `Enter` | split block at caret |
| `Backspace` at offset 0 | merge into previous, caret at the seam |
| `Up`/`Down` at first/last line | move caret to the adjacent block |
| `Tab` / `Shift-Tab` | indent, for lists and todos only |
| `/` at offset 0 | block-type menu |
| `Esc` | leave text, enter block selection |

Six behaviours. Each is testable without a browser, because each is a pure
function over `(blocks, caret, key)`. That is the property that makes this
a week rather than a season.
