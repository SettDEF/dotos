import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * The link graph: every markdown note a point, every [[link]] a line with an
 * arrowhead, as in Obsidian. Data is `dotos graph` (notes, journal days, the
 * projects they belong to, optionally tags and each project's docs; a link to
 * nothing is a hollow "unresolved" point). The layout is a force simulation
 * run here, and the points stay where you left them.
 *
 * Click a point: its details open on the right (excerpt, tags, what links to
 * it and what it links to). Double-click, or the Open button, opens the note.
 * Focus keeps only a note and its neighbours up to 1–3 links away. Drag a
 * point to move it, drag the background to pan, scroll or +/- to zoom.
 */
Item {
    id: page
    property string key: "graph"

    // what to show
    property bool showJournal: true
    property bool showProjects: true
    property bool showTags: false
    property bool showDocs: false
    property bool showMissing: true
    property bool showOrphans: true
    // the work: tasks, and the AI sessions and commits on them (dotos graph --work)
    property bool showTasks: true
    property bool showWork: true
    property bool showDone: false
    property bool showLabels: true
    property string colorBy: "kind"        // kind | group | tag | project
    property string search: ""
    property string focusId: ""
    property int depth: 1
    property string sel: ""                // the selected point's id

    // the graph
    property var nodes: []
    property var edges: []
    property var adj: []
    property var rawData: null
    property int frame: 0
    property real alpha: 0
    property int hover: -1
    property bool fitted: false

    // editing: Shift+drag from a point links it to the one you let go on, Shift+drag on empty
    // space picks every point in the box, Ctrl+click picks one more; double-click makes a note
    property int linkFrom: -1
    property var dragAt: null              // [x, y] on screen while linking or boxing
    property var boxStart: null
    property var multi: []                 // the picked points' ids
    readonly property var multiSet: { const s = {}; for (const id of page.multi) s[id] = true; return s; }
    property bool linkMany: false          // "Link to…": the next point clicked gets every picked one
    property var newAt: null               // [x, y] where the double-click asked for a note's name
    property var placeNew: null            // {id, x, y}: the note just made, put where it was asked for
    property var linkQueue: []
    property var linkSaid: []
    function refOf(n) { return (n.kind === "journal" ? "page" : n.kind) + ":" + n.ref; }
    function linkable(n) { return ["page", "journal", "task", "project", "tag", "missing"].includes(n.kind); }
    /// `dotos link` for each [from, to] in turn; the graph reloads after the last
    function runLinks(pairs) {
        page.linkQueue = page.linkQueue.concat(pairs.map(([a, b]) => [page.refOf(a), page.refOf(b)]));
        if (!linkProc.running) page.nextLink();
    }
    function nextLink() {
        if (page.linkQueue.length === 0) {
            const said = page.linkSaid;
            App.Nav.toast = said.length === 1 ? said[0] : said.length > 1 ? qsTr("%1 linked").arg(said.length) : "";
            page.linkSaid = [];
            page.reload();
            return;
        }
        const [a, b] = page.linkQueue[0];
        page.linkQueue = page.linkQueue.slice(1);
        linkProc.command = [App.Store.bin, "link", a, b];
        linkProc.running = true;
    }
    Process {
        id: linkProc
        stdout: StdioCollector { id: linkOut }
        stderr: StdioCollector { id: linkErr }
        onExited: code => {
            const said = code === 0 ? linkOut.text.trim().split("\n").pop() : linkErr.text.trim().replace(/^dotos link: /, "");
            if (said) page.linkSaid = page.linkSaid.concat([said]);
            page.nextLink();
        }
    }
    /// a new note named `title`; the graph opens on it
    function newNote(title) {
        if (!title.trim()) return;
        newProc.at = page.newAt ? [(page.newAt[0] - page.ox) / page.zoom, (page.newAt[1] - page.oy) / page.zoom] : null;
        newProc.command = [App.Store.bin, "page", "new", title.trim()];
        newProc.running = true;
    }
    Process {
        id: newProc
        property var at: null
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/\/pages\/(.+)\.md$/);
                if (!m) return;
                App.Nav.toast = qsTr("Note made");
                App.Nav.graphSel = "page:" + m[1];
                if (newProc.at) page.placeNew = { id: "page:" + m[1], x: newProc.at[0], y: newProc.at[1] };
                page.reload();
            }
        }
    }
    function pickInBox(a, b) {
        const [x0, x1] = [Math.min(a[0], b[0]), Math.max(a[0], b[0])], [y0, y1] = [Math.min(a[1], b[1]), Math.max(a[1], b[1])];
        const got = page.nodes.filter(n => { const [x, y] = page.screenOf(n); return x >= x0 && x <= x1 && y >= y0 && y <= y1; }).map(n => n.id);
        page.multi = [...new Set(page.multi.concat(got))];
    }
    function togglePick(id) { page.multi = page.multiSet[id] ? page.multi.filter(x => x !== id) : page.multi.concat([id]); }

    // the view
    property real zoom: 1
    property real ox: canvasBox.width / 2
    property real oy: canvasBox.height / 2

    readonly property int selIdx: page.sel ? page.nodes.findIndex(n => n.id === page.sel) : -1
    readonly property var selNode: page.selIdx >= 0 ? page.nodes[page.selIdx] : null

    function colorOfNode(n) {
        if (page.colorBy === "group" && n.kind !== "missing") return page.tint(n);
        switch (n.kind) {
            case "project": return App.Store.colorOf(n.label);
            case "tag": return App.Console.warn;
            case "journal": return page.colorBy === "kind" ? App.Console.faint : page.tint(n);
            case "doc": return App.Console.dim;
            // the work: tasks by state (done ones faint), AI sessions, commits
            case "task": return n.state === "done" || n.state === "cancelled" ? App.Console.faint : n.state === "doing" ? App.Console.ok : n.state === "waiting" ? App.Console.warn : (page.colorBy === "kind" ? App.Console.data2 : page.tint(n));
            case "agent": return n.state === "working" ? App.Console.ok : n.state === "ended" ? App.Console.faint : App.Console.warn;
            case "commit": return App.Console.dim;
            // files an agent changed: new ones and changes in the accent, deleted ones in red
            case "file": return n.state === "deleted" ? App.Console.crit : n.state === "created" ? App.Console.ok : App.Console.data2;
            case "missing": return "transparent";
            default: return page.tint(n);
        }
    }
    /// notes take their colour from the chosen key
    function tint(n) {
        if (page.colorBy === "group") return (page.groupSize[n.group] ?? 0) > 1 ? App.Store.colorOf("group " + n.group) : App.Console.dim;
        if (page.colorBy === "tag") return (n.tags ?? []).length ? App.Store.colorOf(n.tags[0]) : App.Console.dim;
        if (page.colorBy === "project") return n.project ? App.Store.colorOf(n.project) : App.Console.dim;
        return App.Console.data;
    }
    function radiusOf(n) { return (n.kind === "project" ? 6 : 4) + Math.min(10, Math.sqrt(n.deg) * 2.2); }
    function iconOf(kind) { return ({ page: "description", journal: "edit_note", project: "deployed_code", tag: "sell", doc: "article", missing: "help", task: "check_circle", agent: "smart_toy", commit: "commit", file: "draft" })[kind] ?? "description"; }

    // ── data ───────────────────────────────────────────────────────────
    function reload() { if (!graphProc.running) { graphProc.running = true; } else reloadTimer.restart(); }
    // a store change reloads the graph only while it is shown, at most every 5 s (agents change the store
    // every few seconds: each reload is a 250 ms process plus a rebuild); hidden, it catches up when shown
    property bool stale: false
    property real lastLoad: 0
    Timer { id: reloadTimer; interval: Math.max(400, 5000 - (Date.now() - page.lastLoad)); onTriggered: { if (page.visible) { page.stale = false; page.lastLoad = Date.now(); page.reload(); } else page.stale = true; } }
    Connections { target: App.Store; function onLastLoadChanged() { if (!reloadTimer.running) reloadTimer.start(); } }
    onVisibleChanged: if (visible && page.stale) reloadTimer.restart()
    onShowTagsChanged: page.reload()
    onShowDocsChanged: page.reload()
    Component.onCompleted: page.reload()

    Process {
        id: graphProc
        command: [App.Store.bin, "graph", "--layout", "--work", "--insight"].concat(page.showTags ? ["--tags"] : [], page.showDocs ? ["--docs"] : [])
        stdout: StdioCollector { onStreamFinished: { try { page.rawData = JSON.parse(text); page.rebuild(); } catch (e) {} } }
    }
    onShowJournalChanged: page.rebuild()
    onShowProjectsChanged: page.rebuild()
    onShowMissingChanged: page.rebuild()
    onShowOrphansChanged: page.rebuild()
    onShowTasksChanged: page.rebuild()
    onShowDoneChanged: page.rebuild()
    onShowWorkChanged: page.rebuild()
    onFocusIdChanged: { page.fitted = false; page.handMoved = false; page.rebuild(); }
    onDepthChanged: { page.fitted = false; page.handMoved = false; page.rebuild(); }

    /// filter the raw data, keep the positions of points that were already there (or were saved)
    function rebuild() {
        if (!page.rawData) return;
        const old = {};
        for (const n of page.nodes) old[n.id] = n;
        let saved = {};
        try { saved = JSON.parse(App.Prefs.graphPos || "{}"); } catch (e) {}
        const keep = n => !(n.kind === "journal" && !page.showJournal) && !(n.kind === "project" && !page.showProjects && !page.showDocs)
            && !(n.kind === "missing" && !page.showMissing) && !(n.kind === "doc" && !page.showDocs) && !(n.kind === "tag" && !page.showTags) && !(page.asOf > 0 && (n.t ?? 0) > page.asOf) && !(n.kind === "task" && (!page.showTasks || (!page.showDone && (n.state === "done" || n.state === "cancelled")))) && !((n.kind === "agent" || n.kind === "commit" || n.kind === "file") && !page.showWork);
        let list = page.rawData.nodes.filter(keep);
        let ids = new Set(list.map(n => n.id));
        let es = page.rawData.edges.filter(e => ids.has(e.a) && ids.has(e.b));
        // focus: only the chosen note and what is within `depth` links of it
        if (page.focusId && ids.has(page.focusId)) {
            const near = new Set([page.focusId]);
            let frontier = [page.focusId];
            for (let d = 0; d < page.depth; d++) {
                const next = [];
                for (const e of es) {
                    if (near.has(e.a) && !near.has(e.b)) { near.add(e.b); next.push(e.b); }
                    if (near.has(e.b) && !near.has(e.a)) { near.add(e.a); next.push(e.a); }
                }
                frontier = next;
            }
            list = list.filter(n => near.has(n.id));
            ids = new Set(list.map(n => n.id));
            es = es.filter(e => ids.has(e.a) && ids.has(e.b));
        }
        if (!page.showOrphans && !page.focusId) {
            const linked = new Set();
            for (const e of es) { linked.add(e.a); linked.add(e.b); }
            list = list.filter(n => linked.has(n.id));
        }
        const idx = {};
        const out = list.map((n, i) => {
            idx[n.id] = i;
            const o = old[n.id], s = saved[n.id];
            // new points start where they were left, else on a spiral
            const a = i * 2.399963, r = 30 * Math.sqrt(i + 1);
            // where it was, else the place dotos laid it out at (graph --layout), else a spiral
            const p = o ? [o.x, o.y] : s ? s : (n.x !== undefined ? [n.x, n.y] : [r * Math.cos(a), r * Math.sin(a)]);
            return Object.assign({}, n, { i, x: p[0], y: p[1], vx: 0, vy: 0, fixed: false, pinned: page.pins.includes(n.id), deg: 0, isNew: !o && !s });
        });
        const edgesOut = [];
        const adj = out.map(() => []);
        for (const e of es) {
            const a = idx[e.a], b = idx[e.b];
            if (a === undefined || b === undefined) continue;
            edgesOut.push({ a, b, kind: e.kind });
            adj[a].push(b); adj[b].push(a);
            out[a].deg++; out[b].deg++;
        }
        // a cached place far from all its neighbours (left by another layout or a filter: a hub above, its
        // 300 tasks below, the lines between them a bundle across the view): placed beside them again
        for (const n of out) {
            if (n.isNew || adj[n.i].length === 0) continue;
            let mx = 0, my = 0;
            for (const j of adj[n.i]) { mx += out[j].x; my += out[j].y; }
            mx /= adj[n.i].length; my /= adj[n.i].length;
            if (Math.hypot(n.x - mx, n.y - my) > 700 && adj[n.i].length <= 3) n.isNew = true;
        }
        for (const n of out) if (n.isNew) {
            const nb = adj[n.i].find(j => !out[j].isNew);
            if (nb !== undefined) { n.x = out[nb].x + (Math.random() - 0.5) * 30; n.y = out[nb].y + (Math.random() - 0.5) * 30; }
        }
        page.hover = -1;
        page.nodes = out;
        page.edges = edgesOut;
        page.adj = adj;
        // the cached places hold: a few new points settle in beside their neighbours (gently, the rest
        // barely moves) instead of one new task re-running the whole layout and the view chasing it
        const newCount = out.filter(n => n.isNew).length;
        const fresh = newCount > Math.max(8, out.length * 0.2);
        const gs = {};
        for (const n of out) gs[n.group] = (gs[n.group] ?? 0) + 1;
        page.groupSize = gs;
        if (page.simulated) page.alpha = fresh ? 1 : newCount > 0 ? 0.3 : 0.15; else Qt.callLater(page.arrange);
        if (out.length === 0) page.fitted = true;
        else if (!page.fitted && !fresh) Qt.callLater(page.fit);
        if (App.Nav.graphSel) {
            const want = App.Nav.graphSel;
            App.Nav.graphSel = "";
            if (out.some(n => n.id === want)) page.sel = want;
        }
        // a note just made by double-click: where it was asked for
        if (page.placeNew) {
            const n = out.find(n => n.id === page.placeNew.id);
            if (n) { n.x = page.placeNew.x; n.y = page.placeNew.y; page.placeNew = null; }
        }
        if (!out.some(n => n.id === page.sel)) page.sel = "";
    }


    // ── layouts: force (the simulation), clusters (it, pulled into groups), or fixed places
    // the points glide to: radial (rings around the chosen point), tree (levels down from it),
    // time (left to right by when each was made, a lane per kind)
    property string layoutMode: "force"
    /// the Health panel (when no point is chosen), and what it shows (`graph --insight`)
    property bool showHealth: true
    readonly property var insight: page.rawData?.insight ?? null
    function rawNode(id) { return (page.rawData?.nodes ?? []).find(n => n.id === id) ?? null; }
    /// select a point, showing its kind first if it is hidden
    function showPoint(id) {
        const n = page.rawNode(id);
        if (!n) return;
        if (!page.nodes.some(x => x.id === id)) { page.showOrphans = true; if (n.kind === "journal") page.showJournal = true; }
        Qt.callLater(() => { page.sel = id; const m = page.nodes.find(x => x.id === id); if (m) page.reveal(m.i); });
    }
    readonly property bool simulated: page.layoutMode === "force" || page.layoutMode === "clusters"
    property var groupSize: ({})
    property real morphT: 1
    // (the mode itself, not `simulated`: that binding may not have caught up when this runs)
    onLayoutModeChanged: { if (page.layoutMode === "force" || page.layoutMode === "clusters") page.alpha = 1; else page.arrange(); }
    /// the point the rings and levels grow from: the selected one, else the best-linked
    function centreIdx() {
        if (page.selIdx >= 0) return page.selIdx;
        let best = 0;
        for (const n of page.nodes) if (n.deg > page.nodes[best].deg) best = n.i;
        return best;
    }
    /// breadth-first levels from `root`, then from each point still not reached (the biggest first)
    function levels(root) {
        const ns = page.nodes, depth = ns.map(() => -1), parent = ns.map(() => -1), trees = [];
        const starts = [root].concat(ns.map(n => n.i).sort((a, b) => ns[b].deg - ns[a].deg));
        for (const s of starts) {
            if (depth[s] >= 0) continue;
            const tree = [s];
            depth[s] = 0;
            for (let q = 0; q < tree.length; q++) {
                for (const j of page.adj[tree[q]]) if (depth[j] < 0) { depth[j] = depth[tree[q]] + 1; parent[j] = tree[q]; tree.push(j); }
            }
            trees.push(tree);
        }
        return { depth, parent, trees };
    }
    function arrange() {
        const ns = page.nodes;
        if (ns.length === 0 || page.layoutMode === "force" || page.layoutMode === "clusters") return;
        page.alpha = 0;
        const tgt = ns.map(n => [n.x, n.y]);
        if (page.layoutMode === "radial" || page.layoutMode === "tree") {
            const { depth, parent, trees } = page.levels(page.centreIdx());
            const pos = {};
            if (page.layoutMode === "radial") {
                // the main tree in rings; each ring ordered by its parents' angles; the rest on an outer ring
                const main = trees[0], rings = [];
                for (const i of main) (rings[depth[i]] = rings[depth[i]] ?? []).push(i);
                const ang = {};
                ang[main[0]] = 0; tgt[main[0]] = [0, 0];
                for (let d = 1; d < rings.length; d++) {
                    const ring = rings[d].sort((a, b) => ang[parent[a]] - ang[parent[b]]);
                    ring.forEach((i, k) => { ang[i] = (k + 0.5) / ring.length * Math.PI * 2; tgt[i] = [Math.cos(ang[i]) * 120 * d, Math.sin(ang[i]) * 120 * d]; });
                }
                const rest = [].concat(...trees.slice(1)), R = 120 * (rings.length + 0.6);
                rest.forEach((i, k) => { const a = (k + 0.5) / rest.length * Math.PI * 2; tgt[i] = [Math.cos(a) * R, Math.sin(a) * R]; });
            } else {
                // levels down the page, each in its parents' order; trees side by side
                let x0 = 0;
                for (const tree of trees) {
                    const rows = [];
                    for (const i of tree) (rows[depth[i]] = rows[depth[i]] ?? []).push(i);
                    const order = {};
                    let wide = 0;
                    rows.forEach((row, d) => {
                        row.sort((a, b) => (order[parent[a]] ?? 0) - (order[parent[b]] ?? 0));
                        row.forEach((i, k) => { order[i] = k; tgt[i] = [x0 + k * 96, d * 110]; });
                        wide = Math.max(wide, row.length);
                    });
                    // centre each row under the widest
                    rows.forEach(row => { const shift = (wide - row.length) * 48; for (const i of row) tgt[i][0] += shift; });
                    x0 += wide * 96 + 80;
                }
            }
        } else if (page.layoutMode === "time") {
            const lane = k => ({ project: 0, page: 1, journal: 1, doc: 1, missing: 1, task: 2, agent: 3, commit: 4 })[k] ?? 1;
            const ts = ns.map(n => n.t ?? 0).filter(t => t > 0), t0 = Math.min(...ts), t1 = Math.max(...ts), W = Math.max(900, ns.length * 14);
            // half real time, half the order they were made in: bursts still show, one busy day cannot pile up
            const order = ns.filter(n => n.t > 0).sort((a, b) => a.t - b.t || a.label.localeCompare(b.label)), rank = {};
            order.forEach((n, k) => rank[n.i] = order.length > 1 ? k / (order.length - 1) : 0.5);
            const used = {};
            for (const n of ns) {
                if (!(n.t > 0)) {
                    // no date: in a row after the dated ones
                    const k = used["undated" + lane(n.kind)] = (used["undated" + lane(n.kind)] ?? -1) + 1;
                    tgt[n.i] = [W + 140 + k * 40, lane(n.kind) * 150];
                    continue;
                }
                const x = ((t1 > t0 ? (n.t - t0) / (t1 - t0) : rank[n.i]) * 0.5 + rank[n.i] * 0.5) * W;
                // stack points that would sit on each other
                const key = lane(n.kind) + ":" + Math.round(x / 24);
                const k = used[key] = (used[key] ?? -1) + 1;
                tgt[n.i] = [x, lane(n.kind) * 150 + k * 22];
            }
        }
        page.morphFrom = ns.map(n => [n.x, n.y]);
        page.morphTo = tgt;
        // the camera travels with the points: from where it is to where the new layout fits
        page.camFrom = { zoom: page.zoom, ox: page.ox, oy: page.oy };
        page.camTo = page.viewFor(ns.map(n => tgt[n.i] || [n.x, n.y]));
        page.handMoved = false;
        page.morphT = 0;
    }
    property var morphFrom: []
    property var morphTo: []
    property var camFrom: null
    /// the view was moved by hand (pan, zoom, pinch): no automatic fit takes it back
    property bool handMoved: false
    property int steps: 0
    property var camTo: null
    Timer {
        interval: 16; repeat: true
        running: page.morphT < 1 && page.visible
        onTriggered: {
            page.morphT = Math.min(1, page.morphT + 0.05);
            const e = 1 - Math.pow(1 - page.morphT, 3);
            for (const n of page.nodes) {
                const a = page.morphFrom[n.i], b = page.morphTo[n.i];
                if (!a || !b) continue;
                n.x = a[0] + (b[0] - a[0]) * e; n.y = a[1] + (b[1] - a[1]) * e;
            }
            const c0 = page.camFrom, c1 = page.camTo;
            if (c0 && c1) {
                page.zoom = c0.zoom + (c1.zoom - c0.zoom) * e;
                page.ox = c0.ox + (c1.ox - c0.ox) * e;
                page.oy = c0.oy + (c1.oy - c0.oy) * e;
            }
            page.frame++;
            if (page.morphT >= 1) page.fitted = true;
        }
    }
    // ── the simulation ─────────────────────────────────────────────────
    function step() {
        const ns = page.nodes, es = page.edges, a = page.alpha;
        const n = ns.length;
        // the push between points, Barnes–Hut (far groups count as one)
        const root = page.quad(ns), out = [0, 0];
        for (let i = 0; i < n; i++) {
            const p = ns[i];
            out[0] = 0; out[1] = 0;
            page.push(root, i, p, 2400 * a, out);
            p.vx += out[0] - p.x * 0.012 * a; p.vy += out[1] - p.y * 0.012 * a;
        }
        // clusters: each point also pulled towards the middle of its group
        if (page.layoutMode === "clusters") {
            const c = {};
            for (const p of ns) { const g = c[p.group] = c[p.group] ?? [0, 0, 0]; g[0] += p.x; g[1] += p.y; g[2]++; }
            for (const p of ns) { const g = c[p.group]; if (g[2] < 2) continue; p.vx += (g[0] / g[2] - p.x) * 0.04 * a; p.vy += (g[1] / g[2] - p.y) * 0.04 * a; }
        }
        for (const e of es) {
            const p = ns[e.a], q = ns[e.b];
            const dx = q.x - p.x, dy = q.y - p.y;
            const d = Math.max(1, Math.sqrt(dx * dx + dy * dy));
            const len = e.kind === "link" ? 70 : 48;
            const f = (d - len) * 0.05 * a;
            const fx = dx / d * f, fy = dy / d * f;
            p.vx += fx; p.vy += fy; q.vx -= fx; q.vy -= fy;
        }
        for (const p of ns) {
            if (p.fixed || p.pinned) { p.vx = 0; p.vy = 0; continue; }
            p.vx *= 0.62; p.vy *= 0.62;
            // a speed limit: crowded points (300 tasks placed beside their project) push hard enough to fling a
            // hub thousands of units in one step and back the next: the line bundles and the chaos on load
            const sp = Math.hypot(p.vx, p.vy), lim = 6 + 40 * a;
            if (sp > lim) { p.vx *= lim / sp; p.vy *= lim / sp; }
            p.x += p.vx; p.y += p.vy;
        }
        page.alpha *= 0.97;
        page.frame++;
        // the view follows the layout while it settles (it keeps spreading after the first fit), until a hand moves it
        page.steps++;
        if (!page.handMoved && page.alpha < 0.35 && (page.steps % 8 === 0 || page.alpha <= 0.02)) page.fit();
        if (page.alpha <= 0.02) savePos.restart();
    }
    Timer { interval: 16; running: page.alpha > 0.02 && page.visible; repeat: true; onTriggered: page.step() }
    // the chosen point pulses a moment (a full redraw per beat), then rests
    property real pulseUntil: 0
    property bool pulsing: false
    Timer { interval: 50; running: page.pulsing && page.visible; repeat: true; onTriggered: { page.frame++; if (Date.now() > page.pulseUntil) page.pulsing = false; } }

    /// remember where the points are
    Timer {
        id: savePos
        interval: 600
        onTriggered: {
            let m = {};
            try { m = JSON.parse(App.Prefs.graphPos || "{}"); } catch (e) {}
            for (const n of page.nodes) m[n.id] = [Math.round(n.x * 10) / 10, Math.round(n.y * 10) / 10];
            App.Prefs.graphPos = JSON.stringify(m);
        }
    }

    /// the view (zoom, ox, oy) that shows all of `pts` ([x, y] each); null when there is nothing to show
    function viewFor(pts) {
        if (pts.length === 0 || canvasBox.width < 50) return null;
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (const p of pts) { x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]); }
        const w = Math.max(60, x1 - x0), h = Math.max(60, y1 - y0);
        // clear of the key hints on top (60 px) and the time bar and zoom buttons below (80 px)
        const top = 60, bottom = 80, side = 50;
        const z = Math.max(0.25, Math.min(3, Math.min((canvasBox.width - 2 * side) / w, (canvasBox.height - top - bottom) / h)));
        return { zoom: z, ox: canvasBox.width / 2 - (x0 + x1) / 2 * z, oy: top + (canvasBox.height - top - bottom) / 2 - (y0 + y1) / 2 * z };
    }
    function fit() {
        const v = page.viewFor(page.nodes.map(n => [n.x, n.y]));
        if (!v) return;
        page.zoom = v.zoom; page.ox = v.ox; page.oy = v.oy;
        page.fitted = true;
        page.handMoved = false;
        page.frame++;
    }
    function zoomBy(f) { page.zoomAt(page.zoom * f, canvasBox.width / 2, canvasBox.height / 2); }
    /// zoom to `z` keeping the point at (x, y) where it is
    function zoomAt(z, x, y) {
        z = Math.max(0.15, Math.min(5, z));
        if (z === page.zoom) return;
        const k = z / page.zoom;
        page.ox = x - (x - page.ox) * k;
        page.oy = y - (y - page.oy) * k;
        page.zoom = z;
        page.viewMoved();
    }
    /// the view moved by hand: it is the user's now (no fit snaps it back), and while the hand moves
    /// the last drawing is shifted and scaled on the GPU; the real drawing follows when it rests
    function viewMoved() {
        page.fitted = true;
        page.handMoved = true;
        settle.restart();
    }
    Timer { id: settle; interval: 120; onTriggered: page.frame++ }



    // ── moving around: pins, the path finder, keys, saved views ────────
    /// the points pinned in place (they stay where they were put; saved)
    property var pins: { try { return JSON.parse(App.Prefs.graphPins || "[]"); } catch (e) { return []; } }
    function togglePin(id) {
        const p = page.pins.includes(id) ? page.pins.filter(x => x !== id) : page.pins.concat([id]);
        App.Prefs.graphPins = JSON.stringify(p);
        for (const n of page.nodes) n.pinned = p.includes(n.id);
        page.frame++;
    }

    /// the path finder: from the marked point (m) to the selected one, the fewest links
    /// time travel: show the graph as it was then (unix seconds; 0: now)
    property real asOf: 0
    /// the time bar is shown on demand (its button), not over the graph all the time
    property bool showTime: false
    readonly property var tRange: { const ts = (page.rawData?.nodes ?? []).map(n => n.t ?? 0).filter(t => t > 0); return ts.length ? [Math.min(...ts), Math.max(...ts)] : [0, 0]; }
    readonly property real tMin: page.tRange[0]
    readonly property real tMax: page.tRange[1]
    onAsOfChanged: page.rebuild()

    property string mark: ""
    readonly property int markIdx: page.mark ? page.nodes.findIndex(n => n.id === page.mark) : -1
    property var pathNodes: []
    property var pathKeys: ({})
    onSelIdxChanged: { page.findPath(); page.pulseUntil = Date.now() + 2400; page.pulsing = page.selIdx >= 0; }
    onMarkIdxChanged: page.findPath()
    function findPath() {
        const a = page.markIdx, b = page.selIdx;
        page.pathNodes = []; page.pathKeys = {};
        if (a < 0 || b < 0 || a === b) { page.frame++; return; }
        const prev = new Array(page.nodes.length).fill(-1);
        const seen = new Array(page.nodes.length).fill(false);
        const queue = [a]; seen[a] = true;
        while (queue.length && !seen[b]) {
            const x = queue.shift();
            for (const y of page.adj[x]) if (!seen[y]) { seen[y] = true; prev[y] = x; queue.push(y); }
        }
        if (!seen[b]) { page.frame++; return; }
        const path = [b];
        while (path[0] !== a) path.unshift(prev[path[0]]);
        const keys = {};
        for (let i = 1; i < path.length; i++) { keys[path[i - 1] + "-" + path[i]] = true; keys[path[i] + "-" + path[i - 1]] = true; }
        page.pathNodes = path; page.pathKeys = keys;
        page.frame++;
    }

    /// arrows: to the neighbour that way (else the nearest point that way); none chosen: the middle one
    function moveDir(dx, dy) {
        const ns = page.nodes;
        if (ns.length === 0) return;
        if (page.selIdx < 0) {
            const cx = (canvasBox.width / 2 - page.ox) / page.zoom, cy = (canvasBox.height / 2 - page.oy) / page.zoom;
            let best = 0, bd = 1e18;
            for (const n of ns) { const d = (n.x - cx) ** 2 + (n.y - cy) ** 2; if (d < bd) { bd = d; best = n.i; } }
            page.sel = ns[best].id; page.reveal(best); return;
        }
        const from = ns[page.selIdx];
        const pick = list => {
            let best = -1, bs = 1e18;
            for (const j of list) {
                const q = ns[j], vx = q.x - from.x, vy = q.y - from.y, d = Math.hypot(vx, vy);
                if (d < 1) continue;
                const cos = (vx * dx + vy * dy) / d;
                if (cos < 0.4) continue;
                const s = d * (2 - cos);
                if (s < bs) { bs = s; best = j; }
            }
            return best;
        };
        let j = pick(page.adj[page.selIdx]);
        if (j < 0) j = pick(ns.map(n => n.i));
        if (j >= 0) { page.sel = ns[j].id; page.reveal(j); }
    }
    /// the view panned so a point is on screen (with a margin)
    function reveal(i) {
        const [x, y] = page.screenOf(page.nodes[i]), m = 80;
        if (x < m) page.ox += m - x; else if (x > canvasBox.width - m) page.ox -= x - (canvasBox.width - m);
        if (y < m) page.oy += m - y; else if (y > canvasBox.height - m) page.oy -= y - (canvasBox.height - m);
        page.frame++;
    }

    /// the graph's own keys (the window asks the page first); true: taken
    function handleKey(e) {
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return false;
        const n = page.selNode, shift = e.modifiers & Qt.ShiftModifier;
        const pan = 60;
        switch (e.key) {
            case Qt.Key_Left: if (shift) { page.ox += pan; page.frame++; } else page.moveDir(-1, 0); return true;
            case Qt.Key_Right: if (shift) { page.ox -= pan; page.frame++; } else page.moveDir(1, 0); return true;
            case Qt.Key_Up: if (shift) { page.oy += pan; page.frame++; } else page.moveDir(0, -1); return true;
            case Qt.Key_Down: if (shift) { page.oy -= pan; page.frame++; } else page.moveDir(0, 1); return true;
            case Qt.Key_Return: case Qt.Key_Enter: if (n) { page.open(n); return true; } return false;
            case Qt.Key_F: if (n) { page.focusId = page.focusId === n.id ? "" : n.id; return true; } return false;
            case Qt.Key_BracketLeft: page.depth = Math.max(1, page.depth - 1); return true;
            case Qt.Key_BracketRight: page.depth = Math.min(3, page.depth + 1); return true;
            case Qt.Key_P: if (n) { page.togglePin(n.id); return true; } return false;
            case Qt.Key_M: if (n) { page.mark = page.mark === n.id ? "" : n.id; return true; } return false;
            case Qt.Key_Plus: case Qt.Key_Equal: page.zoomBy(1.25); return true;
            case Qt.Key_Minus: page.zoomBy(1 / 1.25); return true;
            case Qt.Key_Z: page.fit(); return true;
            case Qt.Key_L: page.showLabels = !page.showLabels; return true;
            case Qt.Key_Space: if (page.simulated) page.alpha = 1; else page.arrange(); return true;
            case Qt.Key_Slash: graphSearch.forceActiveFocus(); return true;
            case Qt.Key_Escape:
                if (page.linkMany) { page.linkMany = false; return true; }
                if (page.multi.length) { page.multi = []; return true; }
                if (page.mark) { page.mark = ""; return true; }
                if (page.focusId) { page.focusId = ""; return true; }
                if (page.sel) { page.sel = ""; return true; }
                return false;
        }
        return false;
    }

    /// saved views: what is shown, how it is coloured, the focus and the camera, by name
    property var views: { try { return JSON.parse(App.Prefs.graphViews || "[]"); } catch (e) { return []; } }
    readonly property var viewKeys: ["showJournal", "showProjects", "showTags", "showDocs", "showMissing", "showOrphans", "showLabels", "showTasks", "showDone", "showWork", "colorBy", "layoutMode", "focusId", "depth", "zoom", "ox", "oy", "search"]
    function saveView(name) {
        name = String(name).trim();
        if (!name) return;
        const v = { name };
        for (const k of page.viewKeys) v[k] = page[k];
        App.Prefs.graphViews = JSON.stringify(page.views.filter(x => x.name !== name).concat([v]));
        App.Nav.say(qsTr("View “%1” saved").arg(name));
    }
    function applyView(v) {
        for (const k of page.viewKeys) if (v[k] !== undefined && k !== "zoom" && k !== "ox" && k !== "oy") page[k] = v[k];
        page.zoom = v.zoom ?? page.zoom; page.ox = v.ox ?? page.ox; page.oy = v.oy ?? page.oy;
        page.fitted = true; page.frame++;
    }
    function deleteView(name) { App.Prefs.graphViews = JSON.stringify(page.views.filter(x => x.name !== name)); }
    // ── drawing (one pass, gfx) ─────────────────────────────────────────
    /// a line's dashes by its kind: a link solid, an embed solid and thick, a project dashed,
    /// a tag dotted, blocked-by dashed in red, a subtask dotted
    function dashOf(kind) {
        return ({ project: [6, 4], tag: [1.5, 3], blocks: [5, 3], parent: [1.5, 3], agent: [3, 3], commit: [2, 2] })[kind] ?? [];
    }
    /// where a point is on screen, and how big
    function screenOf(n) { return [page.ox + n.x * page.zoom, page.oy + n.y * page.zoom]; }
    function sizeK() { return Math.max(0.7, Math.min(1.5, page.zoom)); }

    /// the point under (x, y) on screen, -1 for none (the topmost: the last drawn)
    function nodeAt(x, y) {
        const ns = page.nodes, k = page.sizeK();
        for (let i = ns.length - 1; i >= 0; i--) {
            const [sx, sy] = page.screenOf(ns[i]);
            const r = page.radiusOf(ns[i]) * k + 4;
            if ((x - sx) * (x - sx) + (y - sy) * (y - sy) <= r * r) return i;
        }
        return -1;
    }

    function draw(ctx, w, h) {
        ctx.reset();
        const ns = page.nodes, es = page.edges, z = page.zoom, k = page.sizeK();
        if (ns.length === 0) return;
        const hov = page.hover, sel = page.selIdx, far = z < 0.35;
        const txt = App.Console.text, acc = App.Console.data;
        const off = (x, y, m) => x < -m || y < -m || x > w + m || y > h + m;
        // the lines: the plain ones (not lit, no dash, no arrowhead) gathered into two paths, one stroke each
        const plainGroups = {};
        // the lines
        for (const e of es) {
            const a = ns[e.a], b = ns[e.b];
            const [ax, ay] = page.screenOf(a), [bx, by] = page.screenOf(b);
            if (!isFinite(ax + ay + bx + by)) continue;
            if ((ax < 0 && bx < 0) || (ay < 0 && by < 0) || (ax > w && bx > w) || (ay > h && by > h)) continue;
            const touch = i => e.a === i || e.b === i;
            // on the path from the mark to the selection: lit, thick
            const onPath = !!page.pathKeys[e.a + "-" + e.b];
            const lit = (hov >= 0 && touch(hov)) || (sel >= 0 && touch(sel));
            const faded = (hov >= 0 && !touch(hov)) || (page.q.length > 0 && !(page.matches(a) || page.matches(b)));
            ctx.globalAlpha = onPath ? 1 : lit ? 0.9 : faded ? 0.06 : (far ? 0.14 : 0.22);
            ctx.strokeStyle = onPath || lit ? acc : e.kind === "blocks" ? App.Console.crit : txt;
            ctx.lineWidth = onPath ? 3.2 : (lit ? 1.8 : 1) * (e.kind === "embed" ? 2 : 1);
            ctx.setLineDash(page.dashOf(e.kind));
            // curved edges: quadratic bezier with control point perpendicular to midpoint
            const mx = (ax + bx) / 2, my = (ay + by) / 2;
            const dx = bx - ax, dy = by - ay;
            const elen = Math.hypot(dx, dy);
            const nx = -dy / (elen || 1), ny = dx / (elen || 1);
            const curve = Math.min(elen * 0.12, 30);
            const cx = mx + nx * curve, cy = my + ny * curve;
            const arrow = (e.kind === "link" || e.kind === "embed" || e.kind === "blocks") && !far && z > 0.45 && elen > 30;
            if (!onPath && !lit && !arrow && e.kind !== "blocks") {
                const key = (faded ? "f:" : "n:") + page.dashOf(e.kind).join(",");
                (plainGroups[key] = plainGroups[key] ?? []).push(ax, ay, cx, cy, bx, by);
                continue;
            }
            ctx.beginPath(); ctx.moveTo(ax, ay); ctx.quadraticCurveTo(cx, cy, bx, by); ctx.stroke();
            // glow on lit edges: a wide faint stroke over it (shadowBlur is a software blur per frame: the lag)
            if (lit || onPath) {
                const w = ctx.lineWidth, al = ctx.globalAlpha;
                ctx.lineWidth = w * 4; ctx.globalAlpha = al * 0.18; ctx.stroke();
                ctx.lineWidth = w; ctx.globalAlpha = al;
            }
            // the arrowhead, just outside the point it points to
            const len = Math.hypot(bx - ax, by - ay);
            if ((e.kind === "link" || e.kind === "embed" || e.kind === "blocks") && !far && z > 0.45 && len > 30) {
                const ang = Math.atan2(by - ay, bx - ax), back = page.radiusOf(b) * k + 4;
                const tx = bx - Math.cos(ang) * back, ty = by - Math.sin(ang) * back;
                ctx.setLineDash([]);
                ctx.fillStyle = ctx.strokeStyle;
                ctx.globalAlpha = lit ? 0.95 : faded ? 0.08 : 0.4;
                ctx.beginPath();
                ctx.moveTo(tx, ty);
                ctx.lineTo(tx - Math.cos(ang - 0.45) * 7, ty - Math.sin(ang - 0.45) * 7);
                ctx.lineTo(tx - Math.cos(ang + 0.45) * 7, ty - Math.sin(ang + 0.45) * 7);
                ctx.closePath(); ctx.fill();
            }
        }
        ctx.setLineDash([]);
        for (const key in plainGroups) {
            const pts = plainGroups[key], dash = key.slice(2);
            ctx.globalAlpha = key[0] === "f" ? 0.06 : (far ? 0.14 : 0.22); ctx.strokeStyle = txt; ctx.lineWidth = 1;
            ctx.setLineDash(dash ? dash.split(",").map(Number) : []);
            ctx.beginPath();
            for (let i = 0; i < pts.length; i += 6) { ctx.moveTo(pts[i], pts[i + 1]); ctx.quadraticCurveTo(pts[i + 2], pts[i + 3], pts[i + 4], pts[i + 5]); }
            ctx.stroke();
        }
        ctx.setLineDash([]);
        // the points
        const nearOf = i => hov >= 0 && (hov === i || page.adj[hov].includes(i));
        for (const n of ns) {
            const [x, y] = page.screenOf(n), r = page.radiusOf(n) * k;
            if (off(x, y, r + 10)) continue;
            const near = nearOf(n.i), dim = (hov >= 0 && !near) || !page.matches(n);
            ctx.globalAlpha = dim ? 0.18 : 1;
            if (n.i === sel) {
                const pulse = 0.5 + 0.5 * Math.sin(Date.now() / 300);
                // a soft halo (a faint disc), then the ring
                ctx.fillStyle = acc; ctx.globalAlpha = (dim ? 0.18 : 1) * (0.12 + pulse * 0.08);
                ctx.beginPath(); ctx.arc(x, y, r + 14 + pulse * 4, 0, Math.PI * 2); ctx.fill();
                ctx.globalAlpha = dim ? 0.18 : 1;
                ctx.strokeStyle = acc; ctx.lineWidth = 2;
                ctx.beginPath(); ctx.arc(x, y, r + 6 + pulse * 3, 0, Math.PI * 2); ctx.stroke();
            }
            // picked (box or Ctrl+click): a ring in the warning colour
            if (page.multiSet[n.id]) {
                ctx.strokeStyle = App.Console.warn; ctx.lineWidth = 2;
                ctx.beginPath(); ctx.arc(x, y, r + 4, 0, Math.PI * 2); ctx.stroke();
            }
            // the path's start (m): a dashed ring; a point on the path: a thin one
            if (n.i === page.markIdx) {
                ctx.strokeStyle = acc; ctx.lineWidth = 2; ctx.setLineDash([3, 3]);
                ctx.beginPath(); ctx.arc(x, y, r + 6, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]);
            } else if (page.pathNodes.includes(n.i) && n.i !== sel) {
                ctx.strokeStyle = acc; ctx.lineWidth = 1.5;
                ctx.beginPath(); ctx.arc(x, y, r + 4, 0, Math.PI * 2); ctx.stroke();
            }
            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
            if (n.kind === "missing") {
                ctx.strokeStyle = App.Console.faint; ctx.lineWidth = 1.5; ctx.stroke();
            } else {
                if (near || hov === n.i) {
                    // the halo of a lit point: a faint disc around it
                    const al = ctx.globalAlpha;
                    ctx.fillStyle = page.colorOfNode(n); ctx.globalAlpha = al * 0.22;
                    ctx.beginPath(); ctx.arc(x, y, r + 6, 0, Math.PI * 2); ctx.fill();
                    ctx.globalAlpha = al;
                    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
                }
                ctx.fillStyle = page.colorOfNode(n); ctx.fill();
                if (near || hov === n.i) { ctx.strokeStyle = txt; ctx.lineWidth = 2; ctx.stroke(); }
            }
            // pinned: a small dot on its top right
            if (n.pinned) {
                ctx.fillStyle = App.Console.warn;
                ctx.beginPath(); ctx.arc(x + r * 0.75, y - r * 0.75, 2.6, 0, Math.PI * 2); ctx.fill();
            }
        }
        // the labels: readable ones only (far away just the hubs), the most important first, and
        // none over another (a label that would overlap one already there is left out)
        // time: each lane's name at the left edge
        ctx.globalAlpha = 1;
        if (page.layoutMode === "time" && page.morphT >= 1) {
            ctx.font = "11px \"" + App.Console.mono + "\""; ctx.textAlign = "left"; ctx.textBaseline = "middle"; ctx.fillStyle = App.Console.faint;
            const names = [qsTr("projects"), qsTr("notes"), qsTr("tasks"), qsTr("AI sessions"), qsTr("commits")];
            names.forEach((t, l) => { const y = page.oy + l * 150 * z; if (y > 0 && y < h) ctx.fillText(t, 12, y - 14); });
        }
        // editing: the line being drawn to link (green over a point it can go to), the box being picked
        if (page.linkFrom >= 0 && page.dragAt) {
            const [ax, ay] = page.screenOf(ns[page.linkFrom]), to = hov >= 0 && hov !== page.linkFrom;
            ctx.strokeStyle = to ? App.Console.ok : txt; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
            const [bx, by] = to ? page.screenOf(ns[hov]) : page.dragAt;
            ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke(); ctx.setLineDash([]);
        }
        if (page.boxStart && page.dragAt) {
            const [x0, y0] = page.boxStart, [x1, y1] = page.dragAt;
            ctx.fillStyle = acc; ctx.globalAlpha = 0.08; ctx.fillRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
            ctx.globalAlpha = 0.8; ctx.strokeStyle = acc; ctx.lineWidth = 1; ctx.strokeRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
            ctx.globalAlpha = 1;
        }
        if (!page.showLabels) return;
        ctx.textAlign = "center"; ctx.textBaseline = "top";
        const want = [];
        for (const n of ns) {
            const [x, y] = page.screenOf(n);
            if (off(x, y, 80)) continue;
            const near = nearOf(n.i), isSel = n.i === sel, dim = (hov >= 0 && !near) || !page.matches(n);
            const show = far ? (n.deg >= 6 || isSel || near) : (z > 0.7 || near || isSel || n.deg >= 3 || (page.q && !dim));
            if (show) want.push({ n, x, y, near, isSel, dim, rank: (isSel ? 1e6 : 0) + (hov === n.i ? 5e5 : 0) + (near ? 1e5 : 0) + (dim ? 0 : 1e4) + n.deg });
        }
        want.sort((a, b) => b.rank - a.rank);
        const taken = [];
        for (const c of want) {
            const n = c.n, x = c.x, y = c.y, near = c.near, isSel = c.isSel, dim = c.dim;
            const r = page.radiusOf(n) * k;
            const lw = Math.min(28, n.label.length) * 6.6 + 4, top = y + r + (isSel ? 9 : 3);
            const box = [x - lw / 2, top, x + lw / 2, top + 15];
            if (taken.some(t => box[0] < t[2] && t[0] < box[2] && box[1] < t[3] && t[1] < box[3])) continue;
            taken.push(box);
            ctx.globalAlpha = dim ? 0.25 : 1;
            ctx.font = (isSel ? "600 " : "") + (n.kind === "tag" ? 11 : 12) + "px \"" + App.Console.sans + "\"";
            ctx.fillStyle = near || isSel || hov === n.i ? txt : App.Console.dim;
            const label = n.label.length > 28 ? n.label.slice(0, 27) + "…" : n.label;
            ctx.fillText(label, x, y + r + (isSel ? 9 : 3));
        }
    }

    // ── Barnes–Hut: the push between points in O(n log n) ──────────────
    function quad(ns) {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (const p of ns) { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y); }
        const root = { x0: x0 - 1, y0: y0 - 1, s: Math.max(x1 - x0, y1 - y0) + 2, m: 0, cx: 0, cy: 0, kids: null, one: -1 };
        const insert = (c, i, depth) => {
            const p = ns[i];
            c.cx = (c.cx * c.m + p.x) / (c.m + 1); c.cy = (c.cy * c.m + p.y) / (c.m + 1); c.m++;
            if (!c.kids && c.one < 0) { c.one = i; return; }
            if (!c.kids) {
                if (depth > 24) return;
                const hs = c.s / 2;
                c.kids = [0, 1, 2, 3].map(q => ({ x0: c.x0 + (q & 1) * hs, y0: c.y0 + (q >> 1) * hs, s: hs, m: 0, cx: 0, cy: 0, kids: null, one: -1 }));
                const j = c.one; c.one = -1;
                const qj = (ns[j].x >= c.x0 + hs ? 1 : 0) + (ns[j].y >= c.y0 + hs ? 2 : 0);
                insert(c.kids[qj], j, depth + 1);
            }
            const hs = c.s / 2;
            const q = (p.x >= c.x0 + hs ? 1 : 0) + (p.y >= c.y0 + hs ? 2 : 0);
            insert(c.kids[q], i, depth + 1);
        };
        for (let i = 0; i < ns.length; i++) insert(root, i, 0);
        return root;
    }
    function push(c, i, p, kf, out) {
        if (c.m === 0 || (c.one === i && !c.kids)) return;
        const dx = p.x - c.cx, dy = p.y - c.cy;
        const d2 = dx * dx + dy * dy;
        // theta 1.2: far groups count as one sooner (half the work of 0.8, the same picture)
        if (!c.kids || c.s * c.s < 1.44 * d2) {
            if (d2 > 160000 && !c.kids) return;
            const dd = Math.max(1, d2), f = kf * c.m / (dd + 200), d = Math.sqrt(dd);
            out[0] += dx / d * f; out[1] += dy / d * f;
            return;
        }
        for (const k of c.kids) page.push(k, i, p, kf, out);
    }
    function open(n) {
        switch (n.kind) {
            case "page": case "journal": App.Nav.openPage(n.ref); break;
            case "project": App.Nav.openProject(n.ref); break;
            case "doc": App.Store.edit(n.ref); break;
            case "tag": page.search = n.ref; break;
            case "task": App.Nav.selected = n.ref; App.Nav.go("tasks"); break;
            case "agent": App.Store.jump(App.Store.agents.find(a => a.id === n.ref)); break;
            // a commit: `git show` in a new zeit window, in the repo's folder (repo and hash as
            // arguments, never pasted into the shell text)
            case "commit": { const [repo, hash] = String(n.ref).split("@"); Quickshell.execDetached(["sh", "-c", 'd=$(ls -d /mnt/storage/dev/projects/*/"$1"/ /mnt/storage/dev/projects/"$1"/ 2>/dev/null | head -1); [ -n "$d" ] && exec "$HOME/.local/bin/zeit" new-window -c "$d" -- git -c core.pager="less -FRX" show "$2"', "show", repo, hash]); break; }
            // a file an agent changed: in the editor (a deleted one has nothing to open)
            case "file": if (n.state !== "deleted") App.Store.edit(n.ref); break;
            case "missing": App.Store.pageNew(n.ref, "", path => { const id = String(path).split("/").pop().replace(/\.md$/, ""); App.Nav.openPage(id); }); break;
        }
    }

    readonly property string q: page.search.trim().toLowerCase()
    function matches(n) { return page.q.length === 0 || n.label.toLowerCase().includes(page.q) || (n.tags ?? []).some(t => t.toLowerCase().includes(page.q)); }
    /// the points a point links to, and the points that link to it
    function outgoing(idx) { return page.edges.filter(e => e.a === idx && e.kind === "link").map(e => page.nodes[e.b]); }
    function incoming(idx) { return page.edges.filter(e => e.b === idx && e.kind === "link").map(e => page.nodes[e.a]); }

    /// what the colours mean now: [{ label, color }]
    readonly property var legend: {
        const seen = {}, out = [];
        const add = (label, color, hollow) => { if (!seen[label]) { seen[label] = 1; out.push({ label, color, hollow: !!hollow }); } };
        if (page.colorBy === "kind") {
            for (const n of page.nodes) add(n.kind === "page" ? qsTr("note") : n.kind === "missing" ? qsTr("unresolved link") : n.kind === "journal" ? qsTr("journal day") : n.kind === "doc" ? qsTr("project doc") : n.kind === "tag" ? qsTr("tag") : n.kind === "task" ? qsTr("task") : n.kind === "agent" ? qsTr("AI session") : n.kind === "commit" ? qsTr("commit") : n.kind === "file" ? (n.state === "deleted" ? qsTr("deleted file") : qsTr("changed file")) : qsTr("project"), n.kind === "missing" ? "transparent" : page.colorOfNode(n), n.kind === "missing");
        } else if (page.colorBy === "group") {
            // each group by its best-linked point: "Loom +12"
            const best = {};
            for (const n of page.nodes) if ((page.groupSize[n.group] ?? 0) > 1 && (!best[n.group] || n.deg > best[n.group].deg)) best[n.group] = n;
            for (const g of Object.keys(best).sort((a, b) => page.groupSize[b] - page.groupSize[a]).slice(0, 6)) add(best[g].label + "  +" + (page.groupSize[g] - 1), App.Store.colorOf("group " + g));
        } else {
            const count = {};
            for (const n of page.nodes) if (n.kind === "page" || n.kind === "journal") {
                const k = page.colorBy === "tag" ? (n.tags ?? [])[0] : n.project;
                if (k) count[k] = (count[k] ?? 0) + 1;
            }
            for (const k of Object.keys(count).sort((a, b) => count[b] - count[a]).slice(0, 6)) add(k, App.Store.colorOf(k));
        }
        return out.slice(0, 7);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Graph")
            subtitle: qsTr("%1 notes · %2 links%3").arg(page.nodes.filter(n => n.kind === "page" || n.kind === "journal").length)
                .arg(page.edges.filter(e => e.kind === "link" || e.kind === "embed").length)
                .arg(page.nodes.some(n => n.kind === "missing") ? qsTr(" · %1 unresolved").arg(page.nodes.filter(n => n.kind === "missing").length) : "")
                + (page.nodes.some(n => n.kind === "task") ? qsTr(" · %1 tasks").arg(page.nodes.filter(n => n.kind === "task").length) : "")
                + (page.nodes.some(n => n.kind === "agent") ? qsTr(" · %1 AI sessions").arg(page.nodes.filter(n => n.kind === "agent").length) : "")
            Rectangle {
                implicitWidth: 200; implicitHeight: 36; radius: 18
                color: App.Console.panelAlt
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    Ui.Icon { text: "search"; size: 17; color: App.Console.faint }
                    TextField {
                        ContextMenu.menu: Ui.TextMenu { target: graphSearch }
                        id: graphSearch
                        Layout.fillWidth: true
                        text: page.search
                        placeholderText: qsTr("Find a note")
                        placeholderTextColor: App.Console.faint
                        background: null; color: App.Console.text
                        font.family: App.Console.sans; font.pixelSize: 14
                        onTextChanged: page.search = text
                        Keys.onEscapePressed: { page.search = ""; focus = false; }
                    }
                }
            }
            Ui.IconButton { icon: "monitor_heart"; tooltip: page.showHealth ? qsTr("Hide the health panel") : qsTr("Health: links worth making, notes to write, notes alone"); onClicked: page.showHealth = !page.showHealth }
            Ui.IconButton { icon: "history"; tooltip: page.showTime ? qsTr("Hide time travel") : qsTr("Time travel: the graph as it was on a day"); onClicked: { page.showTime = !page.showTime; if (!page.showTime) page.asOf = 0; } }
            Ui.IconButton { icon: "play_arrow"; tooltip: qsTr("Re-run the layout"); onClicked: { if (page.simulated) page.alpha = 1; else page.arrange(); } }
        }

        // what is drawn, and how it is coloured
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            Layout.bottomMargin: 0
            spacing: 12
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Text { height: 24; verticalAlignment: Text.AlignVCenter; text: qsTr("Show"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                Repeater {
                    model: [
                        { k: "showJournal", l: qsTr("Journal") }, { k: "showProjects", l: qsTr("Projects") }, { k: "showTags", l: qsTr("Tags") },
                        { k: "showTasks", l: qsTr("Tasks") }, { k: "showDone", l: qsTr("Done tasks") }, { k: "showWork", l: qsTr("Sessions & commits") },
                        { k: "showDocs", l: qsTr("Project docs") }, { k: "showMissing", l: qsTr("Unresolved") }, { k: "showOrphans", l: qsTr("Orphans") }, { k: "showLabels", l: qsTr("Labels") }
                    ]
                    delegate: Ui.Chip {
                        required property var modelData
                        text: modelData.l
                        interactive: true
                        filled: page[modelData.k]
                        accent: page[modelData.k] ? App.Console.data : App.Console.dim
                        onClicked: page[modelData.k] = !page[modelData.k]
                    }
                }
            }
        }

        // saved views: a chip each (click: back to it, Shift+click: forget it); save the one now
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 6
            spacing: 12
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Text { height: 24; verticalAlignment: Text.AlignVCenter; text: qsTr("Views"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                Repeater {
                    model: page.views
                    delegate: Ui.Chip {
                        required property var modelData
                        text: modelData.name
                        interactive: true
                        accent: App.Console.data
                        TapHandler { acceptedModifiers: Qt.ShiftModifier; onTapped: page.deleteView(modelData.name) }
                        onClicked: page.applyView(modelData)
                    }
                }
                Ui.Chip { visible: !viewName.visible; text: qsTr("+ Save view"); interactive: true; accent: App.Console.dim; onClicked: { viewName.visible = true; viewName.forceActiveFocus(); } }
                TextField {
                    ContextMenu.menu: Ui.TextMenu { target: viewName }
                    id: viewName
                    visible: false
                    width: 180; height: 24
                    placeholderText: qsTr("Name, Enter to save")
                    font.family: App.Console.sans; font.pixelSize: 12
                    color: App.Console.text
                    background: Rectangle { radius: 12; color: App.Console.bg; border.width: 1; border.color: App.Console.data }
                    onAccepted: { page.saveView(text); text = ""; visible = false; }
                    Keys.onEscapePressed: { text = ""; visible = false; }
                    onActiveFocusChanged: if (!activeFocus) visible = false
                }
            }
            Text { text: qsTr("Layout"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
            Ui.SegmentedControl {
                implicitWidth: 360
                model: [{ key: "force", label: qsTr("Force") }, { key: "clusters", label: qsTr("Clusters") }, { key: "radial", label: qsTr("Radial") }, { key: "tree", label: qsTr("Tree") }, { key: "time", label: qsTr("Time") }]
                current: page.layoutMode
                onPicked: k => page.layoutMode = k
            }
            Text { text: qsTr("Colour"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
            Ui.SegmentedControl {
                implicitWidth: 300
                model: [{ key: "kind", label: qsTr("Kind") }, { key: "group", label: qsTr("Group") }, { key: "tag", label: qsTr("Tag") }, { key: "project", label: qsTr("Project") }]
                current: page.colorBy
                onPicked: k => page.colorBy = k
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 10
            spacing: 10

            Rectangle {
                id: canvasBox
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: App.Console.radius
                color: App.Console.panel
                clip: true
                // narrower (the details opened): the chosen point stays in view
                onWidthChanged: { if (!page.fitted) page.fit(); else if (page.selIdx >= 0) Qt.callLater(() => page.reveal(page.selIdx)); }

                // everything in one drawing pass (one item, not one per line and point): lines by
                // kind, arrowheads, points, labels; what is under the pointer is found by hit test
                Canvas {
                    id: gfx
                    anchors.fill: parent
                    renderTarget: Canvas.FramebufferObject
                    renderStrategy: Canvas.Cooperative
                    readonly property int tick: page.frame
                    onTickChanged: requestPaint()
                    // the view the drawing was made with; the transform maps it to the current one
                    property real pz: 1
                    property real pox: 0
                    property real poy: 0
                    readonly property real k: page.zoom / pz
                    transform: [
                        Scale { xScale: gfx.k; yScale: gfx.k },
                        Translate { x: page.ox - gfx.pox * gfx.k; y: page.oy - gfx.poy * gfx.k }
                    ]
                    Connections {
                        target: page
                        function onHoverChanged() { gfx.requestPaint(); }
                        function onSelChanged() { gfx.requestPaint(); }
                        function onQChanged() { gfx.requestPaint(); }
                        function onShowLabelsChanged() { gfx.requestPaint(); }
                        function onColorByChanged() { gfx.requestPaint(); }
                        function onMultiChanged() { gfx.requestPaint(); }
                    }
                    onPaint: {
                        pz = page.zoom; pox = page.ox; poy = page.oy;
                        page.draw(getContext("2d"), width, height);
                    }
                }

                // hover, select, drag a point, pan the background, double-click to open (on empty space: a new note);
                // Shift+drag links or box-picks, Ctrl+click picks
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    propagateComposedEvents: true
                    property real px: 0
                    property real py: 0
                    property bool moved: false
                    property int grab: -1
                    cursorShape: page.linkFrom >= 0 || page.linkMany ? Qt.CrossCursor : grab >= 0 || (pressed && grab < 0 && !page.boxStart) ? Qt.ClosedHandCursor : page.hover >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPositionChanged: m => {
                        if (!pressed) {
                            const h = page.nodeAt(m.x, m.y);
                            if (h !== page.hover) page.hover = h;
                            return;
                        }
                        if (Math.abs(m.x - px) + Math.abs(m.y - py) > 3) moved = true;
                        if (page.linkFrom >= 0 || page.boxStart) {
                            page.dragAt = [m.x, m.y];
                            if (page.linkFrom >= 0) page.hover = page.nodeAt(m.x, m.y);
                            page.frame++;
                            return;
                        }
                        if (grab >= 0) {
                            const nd = page.nodes[grab];
                            nd.x = (m.x - page.ox) / page.zoom;
                            nd.y = (m.y - page.oy) / page.zoom;
                            if (page.simulated) page.alpha = Math.max(page.alpha, 0.3);
                            page.frame++;
                        } else {
                            page.ox += m.x - px; page.oy += m.y - py;
                            page.viewMoved();
                        }
                        px = m.x; py = m.y;
                    }
                    onPressed: m => {
                        px = m.x; py = m.y; moved = false;
                        page.newAt = null;
                        const i = page.nodeAt(m.x, m.y);
                        // "Link to…": this point gets every picked one
                        if (page.linkMany) {
                            page.linkMany = false;
                            if (i >= 0) page.runLinks(page.multi.map(id => page.nodes.find(n => n.id === id)).filter(n => n && n.i !== i && page.linkable(n)).map(n => [n, page.nodes[i]]));
                            grab = -1;
                            return;
                        }
                        if (m.modifiers & Qt.ControlModifier) { if (i >= 0) page.togglePick(page.nodes[i].id); grab = -2; return; }
                        if (m.modifiers & Qt.ShiftModifier) {
                            if (i >= 0 && page.linkable(page.nodes[i])) page.linkFrom = i; else page.boxStart = [m.x, m.y];
                            page.dragAt = [m.x, m.y];
                            grab = -2;
                            return;
                        }
                        grab = i;
                        if (grab >= 0) page.nodes[grab].fixed = true;
                    }
                    onReleased: m => {
                        if (page.linkFrom >= 0) {
                            const to = page.nodeAt(m.x, m.y);
                            if (to >= 0 && to !== page.linkFrom) page.runLinks([[page.nodes[page.linkFrom], page.nodes[to]]]);
                            page.linkFrom = -1; page.dragAt = null; page.frame++;
                        } else if (page.boxStart) {
                            if (moved) page.pickInBox(page.boxStart, [m.x, m.y]);
                            page.boxStart = null; page.dragAt = null; page.frame++;
                        } else if (grab >= 0) {
                            page.nodes[grab].fixed = false;
                            if (!moved) page.sel = page.nodes[grab].id; else savePos.restart();
                        } else if (grab === -1 && !moved) { page.sel = ""; page.multi = []; }
                        grab = -1;
                    }
                    onDoubleClicked: m => {
                        const i = page.nodeAt(m.x, m.y);
                        if (i >= 0) page.open(page.nodes[i]);
                        else { page.newAt = [m.x, m.y]; newName.text = ""; newName.forceActiveFocus(); }
                    }
                    onExited: page.hover = -1
                }
                // two fingers on the touchpad move the graph; a mouse wheel (or Ctrl + scroll) zooms
                // around the cursor; a pinch zooms around the fingers (below)
                WheelHandler {
                    id: wheelHandler
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => {
                        e.accepted = true;
                        // a touchpad (pixel deltas) pans, unless Ctrl is held
                        if (!(e.modifiers & Qt.ControlModifier) && (e.pixelDelta.x !== 0 || e.pixelDelta.y !== 0)) {
                            page.ox += e.pixelDelta.x;
                            page.oy += e.pixelDelta.y;
                            page.viewMoved();
                            return;
                        }
                        const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.pixelDelta.y * 2;
                        if (d === 0) return;
                        page.zoomAt(page.zoom * Math.pow(1.0015, Math.max(-500, Math.min(500, d))), point.position.x, point.position.y);
                    }
                }
                // touchpad pinch (pointer-gestures) and two-finger touch: zoom around the fingers,
                // and follow them as they move
                PinchHandler {
                    id: pinch
                    target: null
                    property real lastScale: 1
                    property point lastAt: Qt.point(0, 0)
                    onActiveChanged: if (active) { lastScale = activeScale; lastAt = centroid.position; }
                    // scale and finger movement in one step: the point under the fingers stays under them
                    function follow() {
                        if (!active) return;
                        const c = centroid.position;
                        const z = Math.max(0.15, Math.min(5, page.zoom * activeScale / lastScale));
                        const k = z / page.zoom;
                        page.ox = c.x - (lastAt.x - page.ox) * k;
                        page.oy = c.y - (lastAt.y - page.oy) * k;
                        page.zoom = z;
                        lastScale = activeScale;
                        lastAt = c;
                        page.viewMoved();
                    }
                    onActiveScaleChanged: follow()
                    onCentroidChanged: follow()
                }

                // double-click on empty space: a name, Enter makes the note (Esc: never mind)
                Rectangle {
                    visible: !!page.newAt
                    x: Math.max(8, Math.min(parent.width - width - 8, (page.newAt?.[0] ?? 0) - width / 2))
                    y: Math.max(8, Math.min(parent.height - height - 8, (page.newAt?.[1] ?? 0) - height / 2))
                    width: 260; height: 38; radius: 19
                    color: Ui.Appearance.surfaceContainerHighest
                    border.width: 1; border.color: App.Console.data
                    TextField {
                        ContextMenu.menu: Ui.TextMenu { target: newName }
                        id: newName
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        placeholderText: qsTr("New note…  Enter makes it")
                        font.pixelSize: 13
                        color: App.Console.text
                        background: null
                        onAccepted: { page.newNote(text); page.newAt = null; }
                        Keys.onEscapePressed: page.newAt = null
                        onActiveFocusChanged: if (!activeFocus) page.newAt = null
                    }
                }

                // picked points: tag them all, link them all to one point, or let go
                Rectangle {
                    visible: page.multi.length > 0
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                    width: pickRow.implicitWidth + 24; height: 38; radius: 19
                    color: Ui.Appearance.surfaceContainerHighest
                    border.width: 1; border.color: page.linkMany ? App.Console.ok : App.Console.warn
                    RowLayout {
                        id: pickRow
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
                        spacing: 10
                        Text {
                            text: page.linkMany ? qsTr("click the point to link %1 to").arg(page.multi.length) : qsTr("%1 picked").arg(page.multi.length)
                            font.family: App.Console.mono; font.pixelSize: 11; color: page.linkMany ? App.Console.ok : App.Console.warn
                        }
                        TextField {
                            ContextMenu.menu: Ui.TextMenu { target: tagAll }
                            id: tagAll
                            visible: !page.linkMany
                            implicitWidth: 120; implicitHeight: 26
                            placeholderText: qsTr("#tag all")
                            font.pixelSize: 12; color: App.Console.text
                            background: Rectangle { radius: 13; color: App.Console.panelAlt }
                            leftPadding: 10
                            onAccepted: {
                                const tag = text.trim().replace(/^#/, "");
                                if (!tag) return;
                                const pick = page.nodes.filter(n => page.multiSet[n.id] && (n.kind === "page" || n.kind === "journal" || n.kind === "task"));
                                page.runLinks(pick.map(n => [n, { kind: "tag", ref: tag }]));
                                text = "";
                            }
                        }
                        Ui.Chip { visible: !page.linkMany; text: qsTr("Link to…"); interactive: true; filled: true; accent: App.Console.data; onClicked: page.linkMany = true }
                        Ui.Chip { text: page.linkMany ? qsTr("Cancel  Esc") : qsTr("Clear  Esc"); interactive: true; accent: App.Console.dim; onClicked: { if (page.linkMany) page.linkMany = false; else page.multi = []; } }
                    }
                }

                // the minimap: everything small, the part on screen framed; a click goes there
                Rectangle {
                    id: minimap
                    visible: page.nodes.length > 12
                    anchors { left: parent.left; top: parent.top; margins: 12 }
                    width: 170; height: 110; radius: 10
                    color: Qt.alpha(App.Console.bg, 0.75)
                    border.width: 1; border.color: App.Console.ruleStrong
                    property var box: [0, 0, 1, 1]
                    Canvas {
                        id: miniGfx
                        anchors { fill: parent; margins: 6 }
                        renderTarget: Canvas.FramebufferObject
                        readonly property int tick: page.frame
                        onTickChanged: if (minimap.visible) requestPaint()
                        onPaint: {
                            const ctx = getContext("2d"); ctx.reset();
                            const ns = page.nodes;
                            if (!ns.length) return;
                            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
                            for (const n of ns) { x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y); x1 = Math.max(x1, n.x); y1 = Math.max(y1, n.y); }
                            const s = Math.min(width / Math.max(1, x1 - x0), height / Math.max(1, y1 - y0));
                            minimap.box = [x0, y0, s, 0];
                            ctx.fillStyle = App.Console.dim;
                            for (const n of ns) ctx.fillRect((n.x - x0) * s - 0.75, (n.y - y0) * s - 0.75, 1.5, 1.5);
                            if (page.selNode) { ctx.fillStyle = App.Console.data; ctx.fillRect((page.selNode.x - x0) * s - 2, (page.selNode.y - y0) * s - 2, 4, 4); }
                            // what is on screen
                            const vx = (-page.ox / page.zoom - x0) * s, vy = (-page.oy / page.zoom - y0) * s;
                            ctx.strokeStyle = App.Console.data; ctx.lineWidth = 1;
                            // kept inside the minimap (when everything is on screen it frames all of it)
                            const vw = canvasBox.width / page.zoom * s, vh = canvasBox.height / page.zoom * s;
                            const fx = Math.max(0.5, vx), fy = Math.max(0.5, vy);
                            ctx.strokeRect(fx, fy, Math.min(width - 0.5, vx + vw) - fx, Math.min(height - 0.5, vy + vh) - fy);
                        }
                    }
                    MouseArea {
                        anchors.fill: miniGfx
                        function go(m) {
                            const [x0, y0, s] = minimap.box;
                            const wx = m.x / s + x0, wy = m.y / s + y0;
                            page.ox = canvasBox.width / 2 - wx * page.zoom; page.oy = canvasBox.height / 2 - wy * page.zoom;
                            page.frame++;
                        }
                        onPressed: m => go(m)
                        onPositionChanged: m => { if (pressed) go(m); }
                    }
                }

                // time travel: the graph as it was on a day (points made later hidden); play to watch it grow
                Rectangle {
                    id: timeBar
                    visible: page.showTime && page.tMax > page.tMin
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 12 }
                    width: Math.min(460, parent.width - 420); height: 38; radius: 19
                    color: Ui.Appearance.surfaceContainerHighest
                    border.width: 1; border.color: page.asOf > 0 ? App.Console.data : App.Console.ruleStrong
                    RowLayout {
                        anchors { fill: parent; leftMargin: 6; rightMargin: 14 }
                        spacing: 8
                        Ui.IconButton {
                            implicitWidth: 28; implicitHeight: 28
                            icon: playTimer.running ? "pause" : "play_arrow"
                            tooltip: playTimer.running ? qsTr("Stop") : qsTr("Watch it grow")
                            onClicked: { if (playTimer.running) playTimer.stop(); else { page.asOf = page.tMin; playTimer.start(); } }
                        }
                        Slider {
                            id: timeSlider
                            Layout.fillWidth: true
                            from: page.tMin; to: page.tMax
                            value: page.asOf > 0 ? page.asOf : page.tMax
                            onMoved: page.asOf = value >= page.tMax - 1 ? 0 : value
                            background: Rectangle {
                                x: timeSlider.leftPadding; y: timeSlider.topPadding + timeSlider.availableHeight / 2 - 2
                                width: timeSlider.availableWidth; height: 4; radius: 2; color: App.Console.rule
                                Rectangle { width: timeSlider.visualPosition * parent.width; height: 4; radius: 2; color: App.Console.data }
                            }
                            handle: Rectangle {
                                x: timeSlider.leftPadding + timeSlider.visualPosition * (timeSlider.availableWidth - width)
                                y: timeSlider.topPadding + timeSlider.availableHeight / 2 - 7
                                width: 14; height: 14; radius: 7; color: App.Console.data
                            }
                        }
                        Text {
                            text: page.asOf > 0 ? new Date(page.asOf * 1000).toLocaleDateString(Qt.locale(), "d MMM yyyy") : qsTr("now")
                            font.family: App.Console.mono; font.pixelSize: 11; color: page.asOf > 0 ? App.Console.data : App.Console.faint
                        }
                    }
                    Timer {
                        id: playTimer
                        interval: 60; repeat: true
                        onTriggered: {
                            const step = (page.tMax - page.tMin) / 150;
                            if (page.asOf + step >= page.tMax) { page.asOf = 0; stop(); } else page.asOf += step;
                        }
                    }
                }

                // zoom and fit
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                    implicitWidth: zoomRow.implicitWidth + 12; implicitHeight: 38; radius: 19
                    color: Ui.Appearance.surfaceContainerHighest
                    border.width: 1
                    border.color: App.Console.ruleStrong
                    RowLayout {
                        id: zoomRow
                        anchors.centerIn: parent
                        spacing: 2
                        Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "remove"; tooltip: qsTr("Zoom out"); onClicked: page.zoomBy(1 / 1.25) }
                        Text { Layout.preferredWidth: 38; horizontalAlignment: Text.AlignHCenter; text: Math.round(page.zoom * 100) + "%"; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.dim }
                        Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "add"; tooltip: qsTr("Zoom in"); onClicked: page.zoomBy(1.25) }
                        Rectangle { implicitWidth: 1; implicitHeight: 18; color: App.Console.rule }
                        Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "center_focus_strong"; tooltip: qsTr("Fit everything"); onClicked: page.fit() }
                    }
                }

                // what the colours mean
                Column {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
                    spacing: 4
                    Repeater {
                        model: page.legend
                        delegate: Row {
                            required property var modelData
                            spacing: 6
                            Rectangle { width: 9; height: 9; radius: 4.5; anchors.verticalCenter: parent.verticalCenter
                                color: modelData.hollow ? "transparent" : modelData.color; border.width: modelData.hollow ? 1.5 : 0; border.color: App.Console.faint }
                            Text { text: modelData.label; font.family: App.Console.sans; font.pixelSize: 11; color: App.Console.faint }
                        }
                    }
                }
                Text {
                    anchors { right: parent.right; top: parent.top; margins: 12 }
                    visible: page.nodes.length > 0 && page.multi.length === 0; horizontalAlignment: Text.AlignRight; lineHeight: 1.3
                    // beside the minimap, wrapped: one long line ran into it on a narrow canvas
                    width: parent.width - 24 - (minimap.visible ? minimap.width + 16 : 0)
                    wrapMode: Text.Wrap
                    text: qsTr("arrows move · Enter open · f focus · m path · p pin · / find · z fit") + "\n" + qsTr("Shift+drag link or pick · Ctrl+click pick · double-click a new note")
                    font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                }

                Column {
                    anchors.centerIn: parent
                    visible: page.nodes.length === 0 && page.rawData !== null
                    spacing: 8
                    Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "hub"; size: 40; color: App.Console.faint }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: page.focusId ? qsTr("That note has no links in range.") : qsTr("No notes to connect yet."); font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; visible: !page.focusId; text: qsTr("Notes are markdown files; write [[Another note]] in one to link them."); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        topPadding: 6
                        Ui.Chip { visible: !page.focusId; text: qsTr("New page"); interactive: true; accent: App.Console.data; filled: true; onClicked: App.Store.pageNew(qsTr("Untitled"), "", path => { const id = String(path).split("/").pop().replace(/\.md$/, ""); App.Nav.openPage(id); }) }
                        Ui.Chip { visible: !page.focusId; text: qsTr("Open Pages"); interactive: true; accent: App.Console.dim; onClicked: App.Nav.go("pages") }
                        Ui.Chip { visible: !!page.focusId; text: qsTr("Leave focus"); interactive: true; accent: App.Console.data; filled: true; onClicked: page.focusId = "" }
                    }
                }
            }

            // the health of the notes (no point chosen): links worth making, notes to write, notes alone, hubs
            Rectangle {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                visible: !page.selNode && page.showHealth && !!page.insight
                radius: App.Console.radius
                color: App.Console.panel
                Flickable {
                    anchors { fill: parent; margins: 14 }
                    contentHeight: health.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: health
                        width: parent.width
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Ui.Icon { text: "monitor_heart"; size: 20; color: App.Console.data }
                            Text { Layout.fillWidth: true; text: qsTr("Health"); font.family: App.Console.sans; font.pixelSize: 17; font.weight: Font.DemiBold; color: App.Console.text }
                            Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "close"; tooltip: qsTr("Close"); onClicked: page.showHealth = false }
                        }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: qsTr("%1 groups · %2 alone · %3 not written yet").arg((page.insight?.groups ?? 0)).arg((page.insight?.orphans ?? []).length).arg((page.insight?.missing ?? []).length)
                            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                        }

                        App.Label { text: qsTr("Links worth making"); Layout.topMargin: 6; visible: (page.insight?.suggest ?? []).length > 0 }
                        Repeater {
                            model: page.insight?.suggest ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: (page.rawNode(modelData.a)?.label ?? "") + "  →  " + (page.rawNode(modelData.b)?.label ?? ""); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.why; font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                }
                                Ui.Chip { text: qsTr("Link"); interactive: true; filled: true; accent: App.Console.ok; onClicked: page.runLinks([[page.rawNode(modelData.a), page.rawNode(modelData.b)]]) }
                            }
                        }

                        App.Label { text: qsTr("Not written yet"); Layout.topMargin: 6; visible: (page.insight?.missing ?? []).length > 0 }
                        Repeater {
                            model: page.insight?.missing ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.label; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: qsTr("linked from %1").arg(modelData.from.map(id => page.rawNode(id)?.label ?? id).join(", ")); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                }
                                Ui.Chip { text: qsTr("Make note"); interactive: true; filled: true; accent: App.Console.data; onClicked: page.newNote(modelData.label) }
                            }
                        }

                        App.Label { text: qsTr("Alone (no links)"); Layout.topMargin: 6; visible: (page.insight?.orphans ?? []).length > 0 }
                        Repeater {
                            model: (page.insight?.orphans ?? []).slice(0, 12)
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: page.rawNode(modelData)?.label ?? modelData; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                Ui.Chip { text: qsTr("Show"); interactive: true; accent: App.Console.data; onClicked: page.showPoint(modelData) }
                            }
                        }

                        App.Label { text: qsTr("Hubs"); Layout.topMargin: 6; visible: (page.insight?.hubs ?? []).length > 0 }
                        Repeater {
                            model: page.insight?.hubs ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: page.rawNode(modelData.id)?.label ?? modelData.id; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                Text { text: qsTr("%1 links").arg(modelData.links); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                Ui.Chip { text: qsTr("Show"); interactive: true; accent: App.Console.data; onClicked: page.showPoint(modelData.id) }
                            }
                        }
                        Text {
                            visible: (page.insight?.suggest ?? []).length + (page.insight?.missing ?? []).length + (page.insight?.orphans ?? []).length === 0
                            Layout.fillWidth: true; wrapMode: Text.Wrap; Layout.topMargin: 6
                            text: qsTr("Every note is linked, every link has its note. Nothing to do.")
                            font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
                        }
                    }
                }
            }

            // the selected point
            Rectangle {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                visible: !!page.selNode
                radius: App.Console.radius
                color: App.Console.panel
                Flickable {
                    anchors { fill: parent; margins: 14 }
                    contentHeight: detail.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: detail
                        width: parent.width
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 34; radius: 10
                                color: Qt.alpha(page.selNode && page.selNode.kind !== "missing" ? page.colorOfNode(page.selNode) : App.Console.faint, 0.2)
                                Ui.Icon { anchors.centerIn: parent; text: page.iconOf(page.selNode?.kind); size: 20; color: page.selNode && page.selNode.kind !== "missing" ? page.colorOfNode(page.selNode) : App.Console.faint }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { Layout.fillWidth: true; text: page.selNode?.label ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 17; font.weight: Font.DemiBold; color: App.Console.text }
                                Text { text: ({ page: qsTr("note"), journal: qsTr("journal day"), project: qsTr("project"), tag: qsTr("tag"), doc: qsTr("project doc"), missing: qsTr("unresolved link") })[page.selNode?.kind] ?? ""; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            }
                            Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "close"; onClicked: page.sel = "" }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 36; radius: 18
                                color: openHov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data
                                HoverHandler { id: openHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: page.open(page.selNode) }
                                Text { anchors.centerIn: parent; text: page.selNode?.kind === "missing" ? qsTr("Create the note") : qsTr("Open"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.onData }
                            }
                            Ui.Chip {
                                visible: page.selNode?.kind !== "tag"
                                text: page.focusId === page.sel ? qsTr("Leave focus") : qsTr("Focus")
                                interactive: true; accent: App.Console.data
                                onClicked: page.focusId = page.focusId === page.sel ? "" : page.sel
                            }
                        }
                        // pin it in place (p), start a path here (m)
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Ui.Chip {
                                text: page.pins.includes(page.sel) ? qsTr("Unpin  P") : qsTr("Pin  P")
                                interactive: true; accent: App.Console.warn; filled: page.pins.includes(page.sel)
                                onClicked: page.togglePin(page.sel)
                            }
                            Ui.Chip {
                                text: page.mark === page.sel ? qsTr("Path start  M") : page.mark ? qsTr("Path from here  M") : qsTr("Path from here  M")
                                interactive: true; accent: App.Console.data; filled: page.mark === page.sel
                                onClicked: page.mark = page.mark === page.sel ? "" : page.sel
                            }
                        }
                        // the path from the marked point to this one: its points in order
                        ColumnLayout {
                            visible: page.mark !== "" && page.mark !== page.sel
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: page.pathNodes.length ? (page.pathNodes.length === 2 ? qsTr("%1 link from “%2”") : qsTr("%1 links from “%2”")).arg(page.pathNodes.length - 1).arg(page.nodes[page.markIdx]?.label ?? "") : qsTr("No path from “%1”").arg(page.nodes[page.markIdx]?.label ?? "")
                                font.family: App.Console.mono; font.pixelSize: 11; color: page.pathNodes.length ? App.Console.data : App.Console.faint
                            }
                            Repeater {
                                model: page.pathNodes
                                delegate: Text {
                                    required property int modelData
                                    required property int index
                                    text: (index + 1) + ". " + (page.nodes[modelData]?.label ?? "")
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                    font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim
                                    // shown, not chosen (choosing it would change the path)
                                    TapHandler { onTapped: { page.hover = modelData; page.reveal(modelData); } }
                                }
                            }
                        }
                        // how far out the focus reaches
                        RowLayout {
                            visible: !!page.focusId
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: qsTr("Reach"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            Ui.SegmentedControl {
                                implicitWidth: 150
                                model: [{ key: "1", label: "1" }, { key: "2", label: "2" }, { key: "3", label: "3" }]
                                current: String(page.depth)
                                onPicked: k => page.depth = parseInt(k)
                            }
                            Text { text: qsTr("links away"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: (page.selNode?.tags ?? []).length > 0 || !!page.selNode?.project
                            Repeater {
                                model: (page.selNode?.tags ?? [])
                                delegate: Ui.Chip { required property string modelData; text: "#" + modelData; accent: App.Store.colorOf(modelData) }
                            }
                            Ui.Chip { visible: !!page.selNode?.project; text: "+" + (page.selNode?.project ?? ""); accent: App.Store.colorOf(page.selNode?.project) }
                        }
                        Text {
                            visible: (page.selNode?.excerpt ?? "").length > 0
                            Layout.fillWidth: true
                            text: page.selNode?.excerpt ?? ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 6
                            elide: Text.ElideRight
                            font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
                        }
                        Text {
                            visible: !!page.selNode && page.selNode.words > 0
                            text: qsTr("%1 words · changed %2").arg(page.selNode?.words ?? 0).arg(App.Store.ago(page.selNode?.modified))
                            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                        }

                        App.Label { text: qsTr("Linked from · %1").arg(page.incoming(page.selIdx).length); Layout.topMargin: 4 }
                        Repeater {
                            model: page.incoming(page.selIdx)
                            delegate: LinkRow { required property var modelData; node: modelData }
                        }
                        Text { visible: page.incoming(page.selIdx).length === 0; text: qsTr("Nothing links here yet."); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint }

                        App.Label { text: qsTr("Links to · %1").arg(page.outgoing(page.selIdx).length); Layout.topMargin: 4 }
                        Repeater {
                            model: page.outgoing(page.selIdx)
                            delegate: LinkRow { required property var modelData; node: modelData }
                        }
                        Text { visible: page.outgoing(page.selIdx).length === 0; text: qsTr("It links to nothing."); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint }
                    }
                }
            }
        }
    }

    /// one linked note in the details: click selects it
    component LinkRow: Rectangle {
        id: lr
        property var node
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: lHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
        HoverHandler { id: lHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: page.sel = lr.node.id }
        RowLayout {
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            spacing: 8
            Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 4.5; color: lr.node.kind === "missing" ? "transparent" : page.colorOfNode(lr.node); border.width: lr.node.kind === "missing" ? 1.5 : 0; border.color: App.Console.faint }
            Text { Layout.fillWidth: true; text: lr.node.label; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
        }
    }
}
