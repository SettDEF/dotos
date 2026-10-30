# The todo block

Where the document layer meets VTODO. This is the load-bearing decision in
the whole design — get it wrong and either the phone story or the file story
breaks.

## Syntax

The four states already in use across the repos, which map 1:1 onto the four
`STATUS` values RFC 5545 defines for a VTODO:

| Markdown | `STATUS` |
|---|---|
| `- [ ]` | `NEEDS-ACTION` |
| `- [~]` | `IN-PROCESS` |
| `- [x]` | `COMPLETED` |
| `- [-]` | `CANCELLED` |

Metadata as trailing `key:value`, todo.txt style — greppable, and renders as
ordinary text anywhere markdown renders:

```markdown
- [~] Ship the block editor  due:2026-10-15 prio:2 +dotos ^01J8K2
```

| Token | VTODO field |
|---|---|
| `due:YYYY-MM-DD` | `DUE` |
| `prio:1..9` | `PRIORITY` |
| `+project` `#tag` | `CATEGORIES` |
| `^ULID` | `UID` — written on first sync, never by hand |
| indentation | `RELATED-TO;RELTYPE=PARENT` |

## One task, one home

The obvious design is bidirectional sync between a markdown checkbox and a
`.ics` file. Do not build that. Two writable copies of one record is a
merge problem, and merge problems are where this project would die.

Instead, **every task has exactly one owner**, decided by where it was
created:

**Page-owned.** Written in a page. The markdown line is the truth. dotos
projects it into the vdir so it reaches the phone, and accepts exactly one
field back: `STATUS`. Tick it off on your phone and the page updates. Edit
its *text* on the phone and the change is discarded on the next pass, with a
notice — not silently.

**List-owned.** Created in a list, as today. The `.ics` file is the truth,
fully editable from any CalDAV client, exactly as it already works. A page
can reference one with `![[^ULID]]`, rendered live and read-only.

That asymmetry is the whole trick. Round-tripping one enum is a solved
problem. Round-tripping free text is not.

## Why STATUS is safe to round-trip

It is a closed set of four values with no merge semantics — last write wins
is *correct*, not a compromise. There is no partial state, no concatenation,
no ordering question. Compare `SUMMARY`, where last-write-wins silently
destroys whichever edit came second.

`PERCENT-COMPLETE` is the same shape and can follow later if wanted.

## Indexing

The daemon watches the pages directory, parses checkbox lines, and maintains
the projection. Nothing in the UI parses markdown for tasks — one parser,
in Rust, beside the ics parser, for the same reason §2 gives for not writing
a second iCalendar parser.

"What is due today" queries the vdir, unchanged. That query does not know or
care that some of its rows originated in a page, which is the property that
keeps §1b's table true.

## Open

- **Deleting a page** orphans its projected VTODOs. Tombstone, or cascade?
- **A task moved between pages** keeps its ULID; the projection must follow
  rather than create a second copy.
- **Conflict notice** needs somewhere to appear that is not a modal.
