pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as App

/**
 * The team's conversations and people (docs/teams.md, Teams 1–5), read through the dotos CLI and
 * nothing else: `threads` (each conversation with its count), `thread ITEM` (its last message, for
 * the list), `catchup` (what others said since the last catch-up: the unread and the mentions),
 * `team` (people and agents), `lan status` (peers and when each was last seen) and `me`. A change
 * (a message, marking read) goes through Store.run, the queue every change uses.
 */
Singleton {
    id: root

    property string me: ""               // our handle
    property string meName: ""
    property bool loaded: false          // the first read of the team has come back
    property bool hasTeam: false
    property string teamName: ""
    property var people: []              // { handle, name }
    property var agents: []              // "claude", "claude@anna"
    property var peers: []               // { who, host, seen }
    property var shared: []

    property var _counts: ({})           // item → { count, last, last_author }
    property var _last: ({})             // item → its last message (for the list's preview)
    property var _unread: ({})           // item → { count, mentions }
    property var _queue: []              // items whose last message is still to fetch

    // every conversation, newest first
    readonly property var items: {
        const out = [];
        for (const item in root._counts) {
            const c = root._counts[item];
            const u = root._unread[item] ?? { count: 0, mentions: 0 };
            const r = root.ref(item);
            out.push({ item, kind: r.kind, id: r.id, title: r.title, count: c.count, last: c.last,
                       unread: u.count, mentions: u.mentions, preview: root._last[item] ?? null });
        }
        return out.sort((a, b) => b.last - a.last);
    }
    readonly property int unreadTotal: root.items.reduce((n, i) => n + i.unread, 0)
    /// the agents that answer here: ours (plain "claude") and the ones on the others' machines
    readonly property var agentList: root.agents.filter(a => !root.isMine(a))
    /// who an @ can name: the other people, then the agents
    readonly property var mentionables: root.people.filter(p => p.handle !== root.me)
        .map(p => ({ handle: p.handle, label: p.name || p.handle, agent: false }))
        .concat(root.agentList.map(a => ({ handle: a, label: root.agentLabel(a), agent: true })))

    // ── reading ────────────────────────────────────────────────────────
    function refresh() { root._go(threadsProc); root._go(catchupProc); }
    function refreshAll() { root.refresh(); root._go(teamProc); root._go(lanProc); root._go(meProc); }
    function _go(p) { if (p.running) p.again = true; else p.running = true; }

    /// a CLI read that runs again when asked for while it runs
    component Read: Process {
        property bool again: false
        onExited: { if (again) { again = false; running = true; } }
    }
    Read {
        id: threadsProc
        command: [App.Store.bin, "threads", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root._counts = JSON.parse(text); root._previewsDue(); } catch (e) {}
            }
        }
    }
    Read {
        id: catchupProc
        command: [App.Store.bin, "catchup", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const me = root.me.toLowerCase(), u = {};
                    for (const g of JSON.parse(text))
                        u[g.item] = { count: g.count, mentions: g.messages.filter(m => (m.mentions ?? []).some(h => String(h).toLowerCase() === me)).length };
                    root._unread = u;
                } catch (e) {}
            }
        }
    }
    Read {
        id: teamProc
        command: [App.Store.bin, "team", "--json"]
        stdout: StdioCollector {
            onStreamFinished: { try { const t = JSON.parse(text); root.people = t.people ?? []; root.agents = t.agents ?? []; } catch (e) {} }
        }
    }
    Read {
        id: lanProc
        command: [App.Store.bin, "lan", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const l = JSON.parse(text);
                    root.peers = l.peers ?? [];
                    root.shared = l.shared ?? [];
                    root.hasTeam = !!(l.team && l.team.id);
                    root.teamName = l.team?.name ?? "";
                    root.loaded = true;
                } catch (e) {}
            }
        }
    }
    Read {
        id: meProc
        command: [App.Store.bin, "me", "--json"]
        stdout: StdioCollector {
            onStreamFinished: { try { const m = JSON.parse(text); root.me = m.handle ?? ""; root.meName = m.name ?? ""; root.refresh(); } catch (e) {} }
        }
    }

    // the last message of each conversation, fetched only when it moved on
    function _previewsDue() {
        const due = [];
        for (const item in root._counts) {
            const l = root._last[item];
            if (!l || l.ts !== root._counts[item].last) due.push(item);
        }
        root._queue = due;
        root._nextPreview();
    }
    function _nextPreview() {
        if (previewProc.running || root._queue.length === 0) return;
        const q = root._queue.slice();
        const item = q.shift();
        root._queue = q;
        previewProc.item = item;
        previewProc.command = [App.Store.bin, "thread", item, "--json"];
        previewProc.running = true;
    }
    Process {
        id: previewProc
        property string item: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const ms = JSON.parse(text);
                    if (ms.length) {
                        const l = Object.assign({}, root._last);
                        l[previewProc.item] = ms.reduce((a, m) => (m.ts >= a.ts ? m : a));
                        root._last = l;
                    }
                } catch (e) {}
            }
        }
        onExited: root._nextPreview()
    }

    // a fresh store (a message, a sync) reads the conversations again; the people and peers every 20 s
    Connections { target: App.Store; function onLastLoadChanged() { root.refresh(); } }
    Timer { interval: 20000; running: true; repeat: true; onTriggered: root.refreshAll() }
    Component.onCompleted: root.refreshAll()

    // ── writing ────────────────────────────────────────────────────────
    /// a message to a conversation: the same `dotos say` the terminal writes
    function say(item, text) { App.Store.run(["say", item, text]); }
    function markRead() { App.Store.run(["catchup", "--mark"], "", () => root.refresh()); }

    // ── who ────────────────────────────────────────────────────────────
    function isAgent(a) { return String(a).startsWith("agent:"); }
    function isMine(a) { const at = String(a).indexOf("@"); return at >= 0 && a.slice(at + 1) === root.me; }
    function agentLabel(a) { const at = String(a).indexOf("@"); return at < 0 ? qsTr("Claude here") : qsTr("Claude on %1").arg(String(a).slice(at + 1)); }
    /// a message's author as a name: an agent's without its "agent:"
    function nameOf(m) { const n = String(m?.name || m?.author || ""); return n.startsWith("agent:") ? n.slice(6) : n; }
    function seen(handle) {
        const h = String(handle).toLowerCase();
        let t = 0;
        for (const p of root.peers) if (String(p.who).toLowerCase() === h) t = Math.max(t, p.seen);
        return t;
    }
    /// seen in the last five minutes (the peers are heard every 20 s while Dotos runs)
    function online(handle) {
        if (String(handle).toLowerCase() === root.me.toLowerCase()) return true;
        const t = root.seen(handle);
        return t > 0 && App.Store.now / 1000 - t < 300;
    }
    function presence(handle) {
        if (String(handle).toLowerCase() === root.me.toLowerCase()) return qsTr("you");
        if (root.online(handle)) return qsTr("online");
        const t = root.seen(handle);
        return t > 0 ? qsTr("seen %1 ago").arg(root.ago(t)) : qsTr("not seen yet");
    }

    // ── what a conversation is ─────────────────────────────────────────
    /// the kind, id and title of an item: task:UID, project:NAME, page:ID
    function ref(item) {
        const i = String(item), c = i.indexOf(":");
        const kind = c > 0 ? i.slice(0, c) : "other", id = c > 0 ? i.slice(c + 1) : i;
        if (kind === "task") { const t = App.Store.task(id); return { kind, id, title: t?.title || qsTr("Task %1").arg(id.slice(0, 8)) }; }
        if (kind === "project") return { kind, id, title: id };
        if (kind === "page") { const p = App.Store.pages.find(x => x.id === id); return { kind, id, title: p?.title || id }; }
        return { kind, id, title: i };
    }
    function kindIcon(k) { return ({ task: "check_circle", project: "deployed_code", page: "description" })[k] ?? "chat_bubble"; }
    function kindLabel(k) { return ({ task: qsTr("Task"), project: qsTr("Project"), page: qsTr("Page") })[k] ?? qsTr("Conversation"); }
    function previewOf(it) {
        const p = it.preview;
        if (!p) return "";
        const who = p.author === root.me ? qsTr("You") : root.nameOf(p);
        return who + ": " + String(p.text).replace(/\s+/g, " ").trim();
    }

    // ── looks ──────────────────────────────────────────────────────────
    /// one colour per person, from the handle (the same rule the chat uses)
    function tone(s) {
        let h = 0;
        for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) % 360;
        return Qt.hsla(h / 360, 0.5, 0.66, 1);
    }
    function hex(c) { const h = v => Math.round(v * 255).toString(16).padStart(2, "0"); return "#" + h(c.r) + h(c.g) + h(c.b); }
    /// the text as rich text: escaped, lines kept, @names in the accent (ours brighter)
    function rich(t) {
        const esc = String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
        const me = root.me.toLowerCase();
        return esc.replace(/(^|[\s>])@([A-Za-z0-9_-]+(?:[.@][A-Za-z0-9_-]+)*)/g, (all, sp, h) => {
            const col = h.toLowerCase() === me ? root.hex(Qt.lighter(App.Console.data, 1.6)) : root.hex(Qt.lighter(App.Console.data, 1.25));
            return sp + '<font color="' + col + '"><b>@' + h + '</b></font>';
        });
    }
    function ago(ts) {
        const d = Math.max(0, Math.floor(App.Store.now / 1000 - ts));
        return d < 60 ? qsTr("now") : d < 3600 ? qsTr("%1m").arg(Math.floor(d / 60)) : d < 86400 ? qsTr("%1h").arg(Math.floor(d / 3600)) : qsTr("%1d").arg(Math.floor(d / 86400));
    }
    /// a conversation's time in the list: the clock today, "Yesterday", the weekday this week, else the date
    function when(ts) {
        const d = new Date(ts * 1000), now = new Date(App.Store.now);
        if (d.toDateString() === now.toDateString()) return Qt.formatDateTime(d, "HH:mm");
        if (d.toDateString() === new Date(now.getTime() - 86400000).toDateString()) return qsTr("Yesterday");
        if (now - d < 6 * 86400000) return Qt.formatDateTime(d, "ddd");
        return Qt.formatDateTime(d, "d MMM");
    }
    /// a message's time: the clock today, else the day and the clock
    function stamp(ts) {
        const d = new Date(ts * 1000), now = new Date(App.Store.now);
        return d.toDateString() === now.toDateString() ? Qt.formatDateTime(d, "HH:mm") : Qt.formatDateTime(d, "ddd d MMM HH:mm");
    }
    /// the day a divider in the conversation names
    function dayLabel(ts) {
        const d = new Date(ts * 1000), now = new Date(App.Store.now);
        if (d.toDateString() === now.toDateString()) return qsTr("Today");
        if (d.toDateString() === new Date(now.getTime() - 86400000).toDateString()) return qsTr("Yesterday");
        return Qt.formatDateTime(d, "dddd d MMMM");
    }
}
