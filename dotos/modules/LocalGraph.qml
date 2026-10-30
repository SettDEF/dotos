import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * A task's or note's own corner of the graph: it in the middle, what it is linked to around it
 * (notes, its project, subtasks, blockers, AI sessions, commits), each line drawn as the graph
 * draws that kind. A click on one opens it; "In the graph" opens the whole graph on it.
 */
ColumnLayout {
    id: lg
    /// "task:<uid>", "page:<id>" …, as `dotos graph --work` names its points
    property string nodeId: ""
    spacing: 6

    property var graph: null
    readonly property var me: (lg.graph?.nodes ?? []).find(n => n.id === lg.nodeId) ?? null
    /// the neighbours (at most 14, the linked ones first) and how each is linked
    readonly property var around: {
        if (!lg.graph || !lg.me) return [];
        const out = [], seen = {};
        for (const e of lg.graph.edges) {
            const other = e.a === lg.nodeId ? e.b : e.b === lg.nodeId ? e.a : null;
            if (!other || seen[other]) continue;
            const n = lg.graph.nodes.find(x => x.id === other);
            if (!n) continue;
            seen[other] = true;
            out.push({ n, kind: e.kind, out: e.a === lg.nodeId });
        }
        const rank = k => ({ link: 0, embed: 0, blocks: 1, parent: 2, agent: 3, project: 4, commit: 5, tag: 6 })[k] ?? 7;
        return out.sort((a, b) => rank(a.kind) - rank(b.kind)).slice(0, 14);
    }
    visible: lg.around.length > 0

    Process {
        id: load
        command: [App.Store.bin, "graph", "--work"]
        stdout: StdioCollector { onStreamFinished: { try { lg.graph = JSON.parse(text); } catch (e) {} } }
    }
    onNodeIdChanged: if (lg.nodeId && !load.running) load.running = true
    Component.onCompleted: if (lg.nodeId) load.running = true
    Connections { target: App.Store; function onLastLoadChanged() { if (lg.nodeId && !load.running) load.running = true; } }

    function colorOf(n) {
        switch (n.kind) {
            case "project": return App.Store.colorOf(n.label);
            case "task": return n.state === "doing" ? App.Console.ok : n.state === "done" ? App.Console.faint : App.Console.data2;
            case "agent": return n.state === "working" ? App.Console.ok : App.Console.faint;
            case "commit": return App.Console.dim;
            case "missing": return App.Console.faint;
            default: return App.Console.data;
        }
    }
    function open(n) {
        switch (n.kind) {
            case "page": case "journal": App.Nav.openPage(n.ref); break;
            case "task": App.Nav.openTask(n.ref); break;
            case "project": App.Nav.openProject(n.ref); break;
            case "agent": App.Store.jump(App.Store.agents.find(a => a.id === n.ref)); break;
            default: lg.toGraph(n.id);
        }
    }
    function toGraph(id) { App.Nav.graphSel = id; App.Nav.go("graph"); }

    RowLayout {
        Layout.fillWidth: true
        App.Label { text: qsTr("Connected"); Layout.fillWidth: true }
        Ui.Chip { text: qsTr("In the graph"); interactive: true; accent: App.Console.data; onClicked: lg.toGraph(lg.nodeId) }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 190
        radius: 10
        color: App.Console.panelAlt
        Canvas {
            id: c
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            property var spots: []
            readonly property var watch: [lg.around, width, height]
            onWatchChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d"); ctx.reset();
                const cx = width / 2, cy = height / 2, n = lg.around.length;
                const rx = width / 2 - 46, ry = height / 2 - 26;
                const spots = [];
                ctx.font = "11px \"" + App.Console.sans + "\""; ctx.textAlign = "center"; ctx.textBaseline = "top";
                for (let i = 0; i < n; i++) {
                    const a = -Math.PI / 2 + i * 2 * Math.PI / n, x = cx + Math.cos(a) * rx, y = cy + Math.sin(a) * ry;
                    const it = lg.around[i];
                    ctx.globalAlpha = 0.45;
                    ctx.strokeStyle = it.kind === "blocks" ? App.Console.crit : App.Console.text;
                    ctx.setLineDash(({ project: [6, 4], tag: [1.5, 3], blocks: [5, 3], parent: [1.5, 3], agent: [3, 3], commit: [2, 2] })[it.kind] ?? []);
                    ctx.lineWidth = it.kind === "embed" ? 2 : 1;
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(x, y); ctx.stroke();
                    ctx.setLineDash([]);
                    ctx.globalAlpha = 1;
                    ctx.fillStyle = lg.colorOf(it.n);
                    ctx.beginPath(); ctx.arc(x, y, 5, 0, Math.PI * 2);
                    // a note not written yet: a ring, as the big graph draws it
                    if (it.n.kind === "missing") { ctx.strokeStyle = lg.colorOf(it.n); ctx.lineWidth = 1.5; ctx.stroke(); } else ctx.fill();
                    ctx.fillStyle = App.Console.dim;
                    const label = it.n.label.length > 16 ? it.n.label.slice(0, 15) + "…" : it.n.label;
                    ctx.fillText(label, x, y + 7);
                    spots.push([x, y, it.n]);
                }
                ctx.fillStyle = App.Console.data;
                ctx.beginPath(); ctx.arc(cx, cy, 8, 0, Math.PI * 2); ctx.fill();
                c.spots = spots;
            }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            function hit(m) { return c.spots.find(s => (s[0] - m.x) ** 2 + (s[1] - m.y) ** 2 < 14 * 14); }
            cursorShape: hit({ x: mouseX, y: mouseY }) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: m => { const s = hit(m); if (s) lg.open(s[2]); }
        }
    }
}
