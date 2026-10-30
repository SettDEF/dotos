import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Ctrl K: one box for everything. Type to jump to a page, task, project,
 * agent or note. Start with ":" for commands — `:due fri`, `:state doing`,
 * `:move loom`, `:blocked <task>` — acting on the selected task. The commands
 * come from `dotos commands --json`, the table a terminal UI renders too; each
 * one runs the same `dotos …` call the rest of the window makes.
 */
Item {
    id: root
    property bool open: false
    signal closed()

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    z: 110

    property var commands: []
    property int index: 0
    readonly property string query: input.text
    readonly property bool cmdMode: root.query.startsWith(":")

    function show(prefix) {
        root.open = true;
        input.text = prefix ?? "";
        root.index = 0;
        input.forceActiveFocus();
        if (root.commands.length === 0) cmdProc.running = true;
    }
    function close() { root.open = false; root.closed(); }

    Process {
        id: cmdProc
        command: [App.Store.bin, "commands", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { root.commands = JSON.parse(text); } catch (e) {} } }
    }

    function score(q, s) {
        q = q.toLowerCase(); s = String(s).toLowerCase();
        if (!q) return 1;
        const at = s.indexOf(q);
        if (at >= 0) return 100 - at - s.length * 0.1;
        let qi = 0, sc = 0, last = -2;
        for (let k = 0; k < s.length && qi < q.length; k++)
            if (s[k] === q[qi]) { sc += k === last + 1 ? 5 : 1; last = k; qi++; }
        return qi === q.length ? sc : 0;
    }

    readonly property var selectedTask: App.Store.task(App.Nav.selected)

    /// run one table command, filling {id} and {arg}
    function runCommand(c, arg) {
        if (c.task && !root.selectedTask) { App.Nav.say(qsTr("Select a task first")); return; }
        if (c.arg && c.arg !== "task" && !String(arg).trim() && c.arg !== "when") { App.Nav.say(qsTr("“%1” needs a value").arg(c.name)); return; }
        const id = root.selectedTask?.uid ?? "";
        const argv = c.args.map(a => a.replace("{id}", id).replace("{arg}", arg));
        App.Store.run(argv, c.name === "undo" ? "" : qsTr("Done: %1").arg(c.name), c.name === "undo" ? out => App.Nav.say(out) : null);
        root.close();
    }

    readonly property var suggestions: ({
        state: ["inbox", "todo", "doing", "waiting", "done", "cancelled"],
        when: ["today", "tomorrow", "mon", "fri", "+3d", "+1w", "none"],
        repeat: ["daily", "weekly", "monthly", "weekdays", "mon,thu", "3d", "+3d", "none"]
    })

    /// rows: { icon, title, sub, tone, run }
    readonly property var rows: {
        const out = [];
        const q = root.query;
        if (root.cmdMode) {
            const body = q.slice(1);
            const sp = body.indexOf(" ");
            const name = (sp < 0 ? body : body.slice(0, sp)).toLowerCase();
            const arg = sp < 0 ? "" : body.slice(sp + 1);
            const exact = root.commands.find(c => c.name === name);
            const ctx = root.selectedTask ? qsTr("on “%1”").arg(root.selectedTask.title) : qsTr("no task selected");
            if (exact && sp >= 0) {
                const label = exact.name + (arg ? " " + arg : "");
                out.push({ icon: "keyboard_return", title: ":" + label, sub: exact.help + (exact.task ? "  ·  " + ctx : ""), tone: App.Console.data, run: () => root.runCommand(exact, arg) });
                const a = arg.toLowerCase();
                let pool = [];
                if (exact.arg === "project") pool = App.Store.projects.map(p => ({ t: p.name, v: p.name }));
                else if (exact.arg === "task") pool = App.Store.open.filter(x => x.uid !== root.selectedTask?.uid).map(x => ({ t: x.title, v: x.uid }));
                else if (root.suggestions[exact.arg]) pool = root.suggestions[exact.arg].map(s => ({ t: s, v: s }));
                for (const p of pool.filter(p => !a || p.t.toLowerCase().includes(a)).slice(0, 7))
                    out.push({ icon: "chevron_right", title: p.t, sub: "", tone: App.Console.dim, fill: ":" + exact.name + " " + p.t, run: () => root.runCommand(exact, p.v) });
            } else {
                for (const c of root.commands.filter(c => !name || c.name.startsWith(name)).slice(0, 12))
                    out.push({ icon: c.arg ? "terminal" : "bolt", title: ":" + c.name + (c.arg ? " <" + c.arg + ">" : ""), sub: c.help, tone: c.task && !root.selectedTask ? App.Console.faint : App.Console.dim,
                               fill: c.arg ? ":" + c.name + " " : "", run: c.arg ? () => { input.text = ":" + c.name + " "; input.forceActiveFocus(); } : () => root.runCommand(c, "") });
            }
            return out;
        }

        const scored = [];
        const add = (s, row) => { if (s > 0) scored.push({ s, row }); };
        for (const p of App.Nav.pages.filter(p => p.group !== "hidden").concat([{ key: "board", label: qsTr("Board"), icon: "view_kanban" }]))
            add(root.score(q, p.label) + 20, { icon: p.icon, title: p.label, sub: qsTr("go to"), tone: App.Console.dim, run: () => { App.Nav.go(p.key); root.close(); } });
        for (const c of root.commands.filter(c => !c.task && !c.arg))
            add(root.score(q, c.name + " " + c.help) + 10, { icon: "bolt", title: c.name, sub: c.help, tone: App.Console.dim, run: () => root.runCommand(c, "") });
        if (q.length > 0) {
            for (const t of App.Store.open) add(root.score(q, t.title + " " + t.project + " " + t.tags.join(" ")),
                { icon: App.Store.stateIcon(t.state), title: t.title, sub: [t.project && "+" + t.project, App.Store.dueLabel(t)].filter(x => x).join("  ·  "), tone: App.Store.stateColor(t.state), run: () => { App.Nav.openTask(t.uid); root.close(); } });
            for (const p of App.Store.projects) add(root.score(q, p.name) + 5, { icon: "deployed_code", title: p.name, sub: qsTr("project"), tone: App.Store.healthColor(p.health), run: () => { App.Nav.openProject(p.name); root.close(); } });
            for (const a of App.Store.liveAgents) add(root.score(q, (a.project ?? "") + " " + App.Store.clean(a.prompt)) - 5,
                { icon: App.Store.agentIcon(a), title: a.project ?? a.id, sub: App.Store.clean(a.prompt).slice(0, 80), tone: App.Store.agentColor(a), run: () => { App.Store.jump(a); root.close(); } });
            for (const p of App.Store.pages) add(root.score(q, p.title) - 2, { icon: "description", title: p.title, sub: p.kind, tone: App.Console.dim, run: () => { App.Nav.openPage(p.id); root.close(); } });
        }
        scored.sort((a, b) => b.s - a.s);
        return scored.slice(0, 12).map(x => x.row);
    }
    onRowsChanged: root.index = 0

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("black", 0.45)
        TapHandler { onTapped: root.close() }
    }

    Rectangle {
        id: card
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Math.min(90, parent.height * 0.12) }
        width: Math.min(660, parent.width - 48)
        height: Math.min(col.implicitHeight, parent.height - 120)
        radius: Ui.Appearance.rounding.large
        color: App.Console.bg
        border.width: 1
        border.color: App.Console.ruleStrong
        TapHandler {}

        ColumnLayout {
            id: col
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                Layout.bottomMargin: 10
                spacing: 10
                Ui.Icon { text: root.cmdMode ? "terminal" : "search"; size: 20; color: App.Console.data }
                TextField {
                    ContextMenu.menu: Ui.TextMenu { target: input }
                    id: input
                    Layout.fillWidth: true
                    placeholderText: qsTr("Jump to anything…   or  :  for commands")
                    placeholderTextColor: App.Console.faint
                    background: null
                    color: App.Console.text
                    font.family: root.cmdMode ? App.Console.mono : App.Console.sans
                    font.pixelSize: 17
                    selectByMouse: true
                    Keys.onEscapePressed: root.close()
                    Keys.onDownPressed: root.index = Math.min(root.rows.length - 1, root.index + 1)
                    Keys.onUpPressed: root.index = Math.max(0, root.index - 1)
                    Keys.onTabPressed: event => { const r = root.rows[root.index]; if (r?.fill) { text = r.fill; cursorPosition = text.length; } event.accepted = true; }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) { root.index = Math.min(root.rows.length - 1, root.index + 1); event.accepted = true; }
                        else if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) { root.index = Math.max(0, root.index - 1); event.accepted = true; }
                        else if (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier) { root.index = Math.min(root.rows.length - 1, root.index + 1); event.accepted = true; }
                        else if (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier) { root.index = Math.max(0, root.index - 1); event.accepted = true; }
                    }
                    onAccepted: root.rows[root.index]?.run()
                }
                Text { text: "Esc"; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: App.Console.rule; visible: root.rows.length > 0 }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 8 * 44)
                visible: root.rows.length > 0
                clip: true
                model: root.rows
                currentIndex: root.index
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    id: r
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 44
                    color: r.index === root.index ? Qt.alpha(App.Console.data, 0.16) : rowHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
                    HoverHandler { id: rowHov; onHoveredChanged: if (hovered) root.index = r.index }
                    TapHandler { onTapped: r.modelData.run() }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 12
                        Ui.Icon { text: r.modelData.icon; size: 18; color: r.modelData.tone }
                        Text {
                            text: r.modelData.title
                            Layout.maximumWidth: card.width * 0.55
                            elide: Text.ElideRight
                            font.family: root.cmdMode ? App.Console.mono : App.Console.sans
                            font.pixelSize: 15
                            color: App.Console.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: r.modelData.sub
                            elide: Text.ElideRight
                            font.family: App.Console.sans
                            font.pixelSize: 13
                            color: App.Console.faint
                        }
                        Text { visible: r.index === root.index && !!r.modelData.fill; text: "Tab"; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                    }
                }
            }
            Text {
                visible: root.rows.length === 0 && root.query.length > 0
                Layout.margins: 18
                text: root.cmdMode ? qsTr("No such command. Clear the colon to search.") : qsTr("Nothing matches “%1”").arg(root.query)
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.dim
            }
            // the footer says what the commands will act on
            Rectangle {
                visible: root.cmdMode
                Layout.fillWidth: true
                implicitHeight: 30
                color: App.Console.panel
                Text {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 16 }
                    text: root.selectedTask ? qsTr("acting on  “%1”").arg(root.selectedTask.title) : qsTr("no task selected — open one first for task commands")
                    elide: Text.ElideRight
                    font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim
                }
            }
        }
    }
}
