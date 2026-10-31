# Dotos — the vision (2026-10-31)

> **The private, fast workspace for small teams: chat, tasks, notes and code as one
> linked space, with AI agents working alongside the people.**

RETHINK.md made Dotos one app over linked objects (tasks, pages, projects, agent jobs) for one
person. This is the next step: **a team**. It keeps everything RETHINK decided (objects and
links, files as the truth, the index, the event log) and says what changes when several people
and several laptops share it.

---

## 1. Three rules every feature passes

| Rule | In practice |
|---|---|
| **Linked, with agents** | Every item (message, task, pull request, issue, page, project) links to every other, can be mentioned anywhere, and has its conversation. Agents take tasks, open pull requests, answer in chat. |
| **Fast on old laptops** | Native QML, no browser engine. Every screen feels instant on a 2013 i3 with 4 GB (the test machine), lists are `ListView`s, effects are the cheap kind (blur: xray). |
| **Private and self-owned** | Data on your machines; sync you choose (§4). Nothing passes a company's cloud unless the team picks that transport. |

A feature that breaks one of them is redesigned, not shipped.

## 2. Who it is for

**Small teams of 2–10**: a development team, and just as much a small company with people
who never open a terminal.

- **Spaces**, as Slack's workspaces: the dev team's space, the company's space; switched at the
  top of the rail. Each space has its people, its shared lists, its chats.
- **Code is an area you turn on** (per person, per space). Someone in the office sees
  Activity · Chat · Work · Notes; a developer also sees Code.
- **Plain words** in the window: "Request a review", never the command behind it.

## 3. What the team stops opening

| Instead of | Dotos | Must be |
|---|---|---|
| Teams, Slack, Discord | Chat | good enough to leave them |
| Jira, Linear, Todoist, Trello | Work | good enough to leave them |
| Notion, Obsidian | Notes | good enough to leave them |
| the GitHub website (daily work) | Code | the daily things: your PRs, reviews, issues, CI; the site for rare ones |

What none of them do, and is the reason for Dotos: **one Activity** across all of it, items
**linked** across all of it, **agents** inside it, on a **laptop from 2013**, **without a cloud**.

## 4. Sync: one event log, many transports

Every change is an **event** (RETHINK's event log, now shared): a message, a task edit, a link,
a read mark, a reaction. Each laptop keeps its store and an outbox/inbox of events; a transport
only carries them.

```
             ┌──────────── Dotos (every laptop) ────────────┐
             │  files + index  ←→  event log (outbox/inbox)   │
             └───────────────┬───────────────────────────────┘
                             │ the same events, any transport
       ┌─────────────────────┼─────────────────────┬──────────────────┐
  LAN, peer to peer     relay server           GitHub repo        later: Matrix,
  (today; offline)      (self-hosted, a VPS;   (no server of      Syncthing folders
                         works anywhere)        your own; slower)
```

- A team picks one or more; they mix (LAN in the office, the relay away from it).
- A laptop that was off **catches up** from the log: a message to someone offline arrives later,
  not never; read state is an event too, so "read" is the same on every laptop.
- Events are signed by their author; a transport cannot forge one.

## 5. Identity

One person, one identity across everything: the Dotos handle (`@karch6`), the GitHub login
(`karch6`), the name, the avatar. A mention, an assignment and a review request then mean the
same person whether they came from Chat, Work or GitHub. Kept in the space's team file, edited
in People.

## 6. The window

A **rail** on the far left switches area (as Teams, Slack, Discord, VS Code); the sidebar next
to it shows only that area; the main view is a list with its item beside it.

| Rail | Sidebar | Main view |
|---|---|---|
| **Activity** | All · Unread · Mentions · Review requests · Assigned · CI · Due · Agents · Done | one feed (Today / Yesterday / This week); the item opens beside it, answered in place; Snooze, Done |
| **Chat** | Pinned · Direct messages · Channels · Item threads · People | the conversation: grouped, replies in threads, reactions, files, voice, items as live cards |
| **Work** | Inbox · Today · Upcoming · All, **Mine / Team / All** · Lists · Projects · Personal (Habits, Journal, Plan, Insights) | List · Board · Plan · Calendar; the task beside it with links, assignee, time, its chat |
| **Code** | For you (my PRs, review requests, assigned issues, CI) · Repositories · Agents | a repository as GitHub shows it: Code (files in zett), Issues, Pull requests (diff review), Actions, Changes, Commits, Branches |
| **Notes** | Pages (tree, pinned) · Journal · Tags · Graph | the page; items as live cards; backlinks |

Everywhere: **Ctrl+K** finds anything and does anything; **Ctrl+1…5** switch area; right click
has what the item can do; at most **three columns**, so on a narrow window the list and the item
take turns instead of squeezing.

**One design system**: Dotos' tokens (colours, 8 px grid, radii, type) for every surface; a
service's colours (GitHub's green, purple, red) only for its states, never its chrome.

## 7. The data engine

`dotos serve` is the one process that talks to the outside (transports, GitHub, calendars,
agents), caches, and pushes changes to the window. The window never starts a program per click:
GitHub is polled with ETags inside the rate limit, Activity is computed once, every view reads
the same state.

## 8. Order of work

1. **Foundations**: identity (§5), design tokens (§6), the event log with a transport
   interface; LAN becomes its first transport.
2. **Relay server**, the second transport.
3. **The window's shell**: spaces, the rail, the five areas (Code optional), responsive columns.
4. **Activity**, then Chat (direct messages, channels, replies, reactions, read state), Work
   (Mine / Team), Code "For you", Notes.
5. **Links and agents** everywhere: issue → task, a merged PR closes its task, @claude with
   permissions (only people the space allows can start an agent).

## 9. Known problems this answers (2026-10-31, the second laptop)

- Chat only reached a laptop on the same network; nothing waited for one that was off (§4).
- Read state lived on one laptop (§4).
- `@caesar` in Dotos is `SettDEF` on GitHub; mentions and reviews could not meet (§5).
- Any `@claude` in a message started an agent run, from anyone paired (§8.5).
- Three visual styles side by side (the GitHub page's, Dotos', each agent's) (§6).
- One `gh` process per click on an old laptop, no cache (§7).
- A shared list had to be shared on both sides, and nothing said so: the tasks a teammate
  mentioned you in were invisible (§4: lists are events too).
