# Dotos for teams: the conversation lives in the work

Plan, 2026-10-27. Replaces "collaboration: not doing" (TASKS.md, PLAN.md 1b) for this track.

## Why

Teams keep tasks in one tool and talk in another (Slack, Discord, mail). The two drift:
the decision is in chat, the task does not know it, the next person asks again. Todoist,
Linear and Notion bolt comments onto tasks; none makes the talk and the work one thing,
and none has AI agents working *inside* the conversation.

Dotos's edge: every task, project, page and agent session already has an id, a history
(Changes) and links. A thread is one more thing hanging off those ids, and agents
already report what they do (the ai-activity log). So:

- every item has its own thread, live;
- a message can become a task, a decision, or a job for an agent, and points back;
- an agent mentioned in a thread joins, works, and answers there with what it did.

## Pieces

| | what | where it lives |
|---|---|---|
| T1 | **People**: who you are, who is in a team (name, colour, avatar, handle) | `~/.config/dotos/me.json`; team members in the team's shared space |
| T2 | **Threads**: messages on a task / project / page block / agent action; replies, edits, reactions | per team: a Matrix room per project, one thread per item (below) |
| T3 | **Live**: new messages, typing, who is looking at an item ("Anna is here") | Matrix sync + presence |
| T4 | **Message → task**: select a message, it becomes a task linked both ways; `@name` in it assigns | X-DOTOS-LINK `msg:<room>/<event>` on the task; the message gets a reply "→ task" |
| T5 | **Decisions**: mark a message as the decision; the task shows it on top | a reaction/annotation on the message, cached on the task (X-DOTOS-DECISION) |
| T6 | **Agents in the thread**: `@claude …` in a thread starts (or resumes) an agent on that project with the thread as context; its actions stream back as a compact log; it asks there when it needs you | dotosd bridge between the room and the agent session (ai-activity already links sessions ↔ tasks) |
| T7 | **Assign + notify**: assignee on tasks, "Mine" view, notifications for mention / assigned / blocked freed / due | ATTENDEE/ORGANIZER on the VTODO (standard), the shell's notifications |
| T8 | **Shared lists**: a list on a team CalDAV server, so tasks themselves sync (and show on phones) | vdirsyncer (M5), a "shared" flag per list |
| T9 | **Catch-up**: "since you were away" per project: decisions, new tasks, agent results, from threads + Changes | generated on open, cached |
| T10 | **Voice notes**: hold to talk on an item, transcribed | the copilot backend's speech-to-text |

## Why Matrix underneath

Live chat needs a live server; building one is a product of its own. Matrix is open,
end-to-end encrypted, self-hostable (Synapse, Conduit) or free on matrix.org, has
threads, reactions, presence and voice, and every team member can also use Element on
the phone. Dotos is then a *client* that shows rooms as threads on items. Rejected: our
own server (years of work), Slack/Discord APIs (someone else's data, no self-hosting),
comments only in the VTODO (no live talk, conflicts on every reply).

Mapping: team = Matrix space; project = room; item thread = Matrix thread whose root
event carries `dotos.item: task:<uid> | page:<id>#<block> | agent:<id>/<action>`.
Messages stay in Matrix; Dotos keeps a local cache for search and offline reading.

## Order

1. **Threads on tasks** (T1, T2, T3 for one project room) — the inspector gets a thread;
   send, reply, live updates. Proves the Matrix client in Rust (matrix-sdk) in dotosd.
2. **Message → task, @mention assigns** (T4, T7 basic).
3. **Agents answer in the thread** (T6) — the part nobody else has.
4. Decisions (T5), notifications (T7 full), shared lists (T8).
5. Catch-up (T9), voice (T10), threads on page blocks and agent actions.

Done 2026-10-27 without a server: decisions (`dotos decide`), notifications (`dotos serve`, `dotos news`), shared lists over LAN sync (`dotos lan share LIST`; newer file wins, deletions do not travel yet), catch-up (`dotos catchup`, Home card), voice messages (mic in the message box, `dotos voice`; not live calls), conversations on pages (whole page, quoted selection) and on agent tasks.

Steps 1–3 are the first usable version: one team, one server, talk on tasks, agents in it.

## Open questions

- Hosted for the user's own team first, or matrix.org accounts? (a local Conduit is the
  fastest to test headless)
- Encryption from day one (matrix-sdk handles it; key backup UX is the hard part)
- The TUI and the phone: TUI gets threads read-only first; phones use Element.

## On the local network, no server (user, 2026-10-27)

A team in one office or home needs no Matrix server: Dotos instances find each other on the
LAN (mDNS, `_dotos._tcp`) and exchange what changed directly. Threads are append-only
message files (data/threads/*.jsonl, ids unique per author), so merging two copies is a
union by id — no conflicts. Tasks follow later the same way (field-level merge, see T8).
Pairing: a short code shown on one machine and typed on the other, which then trust each
other (a key pair each, messages signed). Matrix stays the way for teams that are not in
one place; both carry the same messages, the UI does not change.

Order: LAN sync of threads right after Teams 1 (it is the quickest way to two real people
talking), then Matrix for remote teams.

## Using it: a team on your network (how-to)

Everyone needs Dotos on a computer in the same network (home or office). No server, no account.

**1. Say who you are** (once per computer)

    dotos me --handle caesar --name Caesar

**2. Start a team and invite** (one person)

    dotos lan init "Our team"
    dotos lan code              # a long code: send it to the friend (chat, mail)

**3. Join** (each friend)

    dotos me --handle anna --name Anna
    dotos lan join <code>

**4. Keep in sync:** leave Dotos open or run `dotos serve` (it includes `dotos lan serve`).
The computers find each other by broadcast and sync every 20 s. `dotos lan status` shows the
team and the peers it met; `dotos lan sync` syncs now. `dotos team` lists the people.

**5. Share task lists** (optional; each side picks the same list)

    dotos lan share personal    # dotos lan unshare personal stops it

The newer change of a task wins; a deleted task does not disappear on the other side yet
(mark it done instead). History shows a teammate's change as `team:<handle>`.

**Talking.** Every task, project, page and agent task has a Conversation. `@anna` mentions
(she gets a notification), `@` shows the team's people as you type (Tab takes the first).
A message can become a task (its @mention is the assignee) or the decision (gavel button).
The mic in an empty message box records a voice message. `dotos catchup` (and the Home card
"Team catch-up") shows what others said since you last looked.

**Agents.** `@claude` runs Claude Code on your computer, on that task's project. `@claude@anna`
runs it on Anna's computer, in her copy of the project; the answer comes back as
`claude@anna`. Each request is answered once. Read-only unless `"agent_mode": "edit"` is in
`~/.config/dotos/config.json`.

**Leaving:** `dotos lan leave`. The key in `~/.config/dotos/team.json` is the team: whoever has
it is in. Traffic is authenticated but not encrypted, so use it on networks you trust.
