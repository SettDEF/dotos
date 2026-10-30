import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * Agents: every AI chat the shell's hooks report — working, waiting for you,
 * finished — with where it runs and what it was asked. Click: the details;
 * Jump: its terminal. Tasks linked to a chat (link agent:<id>) are listed
 * with it, so "hand to an agent" and "come back to review" meet here.
 */
Item {
    id: page
    property string key: "agents"
    property string filter: "live"   // live | needs | working | finished | all
    property string pick: App.Nav.agent
    // the Claude task opened in the details (from History too: Nav.agentTask)
    property string openTask: App.Nav.agentTask
    property string sortBy: "state"      // state | project | tools | commits | age
    property bool sortDesc: false
    readonly property var stateRank: ({ needs_you: 0, working: 1, ready: 2, finished: 3, ended: 4 })
    function sortKey(a) {
        switch (page.sortBy) {
            case "project": return String(a.project ?? "").toLowerCase();
            case "tools": return a.tools ?? 0;
            case "commits": return (a.commits ?? []).length;
            case "age": return a.updated ?? 0;
            default: return (page.stateRank[a.state] ?? 9) * 1e10 - (a.updated ?? 0);
        }
    }
    function sortBy_(k) { if (page.sortBy === k) page.sortDesc = !page.sortDesc; else { page.sortBy = k; page.sortDesc = k === "tools" || k === "commits" || k === "age"; } }
    readonly property var list: page.base.slice().sort((a, b) => { const x = page.sortKey(a), y = page.sortKey(b); return (x < y ? -1 : x > y ? 1 : 0) * (page.sortDesc ? -1 : 1); })
    readonly property var base: App.Store.agents.filter(a =>
        page.filter === "all" ? true
        : page.filter === "needs" ? a.state === "needs_you"
        : page.filter === "working" ? a.state === "working"
        : page.filter === "finished" ? a.state === "finished"
        : a.state !== "ended")
    readonly property var sel: App.Store.agents.find(a => a.id === page.pick) ?? page.list[0] ?? null
    readonly property var linked: page.sel ? App.Store.tasks.filter(t => t.links.includes("agent:" + page.sel.id)) : []
    // the card a chat works on now (the hooks record it as it moves one to doing), and a card by id
    function cardOf(a) { return a?.task ? App.Store.tasks.find(t => String(t.uid).startsWith(a.task)) ?? null : null; }
    readonly property var onCard: page.cardOf(page.sel)
    // keys: j/k the chat, Enter jumps to its terminal, h/l the filter
    readonly property var keyHelp: [[qsTr("Move"), ["j", "k"]], [qsTr("Jump to its terminal"), ["Enter"]], [qsTr("Filter"), ["h", "l"]]]
    function handleKey(e) {
        const i = page.list.findIndex(a => a.id === page.pick);
        const m = K.move(e, page.list.length, i);
        if (m >= 0) { page.pick = page.list[m].id; agentList.positionViewAtIndex(m, ListView.Contain); return true; }
        if (K.isOpen(e) && page.sel) { App.Store.jump(page.sel); return true; }
        const d = K.side(e);
        if (d) { page.filter = K.cycle(["live", "needs", "working", "finished", "all"], page.filter, d); return true; }
        return false;
    }
    /// the selected chat's own task list, and what a chat is doing now (its task in progress)
    readonly property var selTasks: page.sel?.claude_tasks ?? []
    function doingOf(a) { const t = (a?.claude_tasks ?? []).find(x => x.status === "in_progress"); return t ? (t.active || t.subject) : ""; }
    readonly property var commits: (page.sel?.commits ?? []).slice().reverse()

    /// a column title that sorts by its column; an arrow shows the order
    component Head: Item {
        id: h
        property string text: ""
        property string key: ""
        property bool alignRight: false
        readonly property bool on: page.sortBy === h.key
        implicitHeight: 24
        Row {
            anchors { verticalCenter: parent.verticalCenter; right: h.alignRight ? parent.right : undefined; left: h.alignRight ? undefined : parent.left }
            spacing: 3
            App.Label { text: h.text; color: h.on || hh.hovered ? App.Console.text : App.Console.faint }
            Ui.Icon { visible: h.on; anchors.verticalCenter: parent.verticalCenter; text: page.sortDesc ? "arrow_downward" : "arrow_upward"; size: 12; color: App.Console.data }
        }
        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: page.sortBy_(h.key) }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Agents")
            subtitle: qsTr("%1 running · %2 need you · %3 working · from the Claude Code hooks")
                .arg(App.Store.liveAgents.length).arg(App.Store.needsYou.length).arg(App.Store.liveAgents.filter(a => a.state === "working").length)
            Ui.SegmentedControl {
                implicitWidth: 380
                model: [{ key: "live", label: qsTr("Running") }, { key: "needs", label: qsTr("Needs you") }, { key: "working", label: qsTr("Working") }, { key: "finished", label: qsTr("Finished") }, { key: "all", label: qsTr("All") }]
                current: page.filter
                onPicked: k => page.filter = k
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 12

            Rectangle {
                id: tableBox
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: App.Console.radius
                color: App.Console.panel
                /// the tool and commit counts need room; below this the task text matters more
                readonly property bool roomy: tableBox.width > 700

                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10; Layout.rightMargin: 10
                        implicitHeight: 30
                        spacing: 12
                        Item { implicitWidth: 18 }
                        Head { text: qsTr("State"); key: "state"; Layout.preferredWidth: 90 }
                        Head { text: qsTr("Project"); key: "project"; Layout.preferredWidth: 120 }
                        App.Label { text: qsTr("Doing"); Layout.fillWidth: true }
                        Head { visible: tableBox.roomy; text: qsTr("Tools"); key: "tools"; Layout.preferredWidth: 48; alignRight: true }
                        Head { visible: tableBox.roomy; text: qsTr("Commits"); key: "commits"; Layout.preferredWidth: 62; alignRight: true }
                        Head { text: qsTr("For"); key: "age"; Layout.preferredWidth: 70; alignRight: true }
                        Item { implicitWidth: 52 }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: App.Console.ruleStrong }
                    ListView {
                        id: agentList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: page.list
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool on: page.sel?.id === modelData.id
                            width: ListView.view.width
                            height: 38
                            radius: 7
                            color: on ? Qt.alpha(App.Console.data, 0.16) : rHov.hovered ? App.Console.panelAlt : (index % 2 ? Qt.alpha(App.Console.text, 0.025) : "transparent")
                            HoverHandler { id: rHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.pick = modelData.id; onDoubleTapped: App.Store.jump(modelData) }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 12
                                Ui.Icon { text: App.Store.agentIcon(modelData); filled: modelData.state === "needs_you"; size: 18; color: App.Store.agentColor(modelData) }
                                Text { Layout.preferredWidth: 90; text: modelData.state.replace("_", " "); font.family: App.Console.mono; font.pixelSize: 12; color: App.Store.agentColor(modelData) }
                                Text { Layout.preferredWidth: 120; text: modelData.project ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                                Text {
                                    Layout.fillWidth: true
                                    // waiting: the question; else the card it is on, else what it was asked
                                    text: modelData.state === "needs_you" ? App.Store.clean(modelData.message) : page.cardOf(modelData) ? "▸ " + page.cardOf(modelData).title : page.doingOf(modelData) ? "▸ " + page.doingOf(modelData) : modelData.unreported ? qsTr("idle · no activity reported since it started (%1)").arg(modelData.cwd ?? "") : App.Store.clean(modelData.prompt)
                                    elide: Text.ElideRight
                                    font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
                                }
                                // Claude's own task list: done of all
                                Text { visible: tableBox.roomy; Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; text: (modelData.claude_tasks ?? []).length ? (modelData.claude_tasks.filter(t => t.status === "completed").length + "/" + modelData.claude_tasks.length) : "·"; font.family: App.Console.mono; font.pixelSize: 12; color: (modelData.claude_tasks ?? []).length ? App.Console.ok : App.Console.faint }
                                Text { visible: tableBox.roomy; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight; text: modelData.tools ?? 0; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                                Text { visible: tableBox.roomy; Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight; text: (modelData.commits ?? []).length || "·"; font.family: App.Console.mono; font.pixelSize: 12; color: (modelData.commits ?? []).length ? App.Console.data : App.Console.faint }
                                Text {
                                    Layout.preferredWidth: 70
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.state === "working" ? App.Store.dur((App.Store.now / 1000) - (modelData.turn_started ?? modelData.started ?? 0)) : App.Store.ago(modelData.updated)
                                    font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint
                                }
                                App.Tag { text: qsTr("Jump"); tone: rHov.hovered ? App.Console.data : App.Console.dim; TapHandler { onTapped: App.Store.jump(modelData) } }
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            visible: page.list.length === 0
                            spacing: 8
                            Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "smart_toy"; size: 40; color: App.Console.faint }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: page.filter === "needs" ? qsTr("Nobody is waiting for you.") : qsTr("No chats here. Claude Code sessions appear as they start.")
                                font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim
                            }
                        }
                    }
                }
            }

            // the selected chat
            Rectangle {
                visible: !!page.sel
                Layout.preferredWidth: Math.round(Math.max(290, Math.min(360, page.width * 0.28)))
                Layout.fillHeight: true
                radius: App.Console.radius
                color: App.Console.panel
                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 10
                    Text { text: (page.sel?.source === "claude-code" ? "Claude" : page.sel?.source ?? "") + " · " + (page.sel?.project ?? ""); font.family: App.Console.mono; font.pixelSize: 17; font.weight: Font.DemiBold; color: App.Console.text; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: [page.sel?.tmux_pane ? "tmux " + page.sel.tmux_pane : "", page.sel?.pid ? "pid " + page.sel.pid : ""].filter(s => s).join(" · "); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                    Rectangle {
                        visible: page.sel?.state === "needs_you"
                        Layout.fillWidth: true
                        implicitHeight: needText.implicitHeight + 24
                        radius: 12
                        color: Qt.alpha(App.Console.crit, 0.12)
                        Text { id: needText; anchors { fill: parent; margins: 12 } text: page.sel?.message ?? ""; wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.crit }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40; radius: 20
                        color: App.Console.data
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.Store.jump(page.sel) }
                        Text { anchors.centerIn: parent; text: qsTr("Jump to the terminal"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.onData }
                    }
                    // the session's own task list (TaskCreate / TaskUpdate, read from ~/.claude/tasks)
                    App.Label { visible: page.selTasks.length > 0; text: qsTr("Claude's tasks  %1/%2").arg(page.selTasks.filter(t => t.status === "completed").length).arg(page.selTasks.length) }
                    Rectangle {
                        visible: page.selTasks.length > 0
                        Layout.fillWidth: true
                        implicitHeight: 4; radius: 2
                        color: Qt.alpha(App.Console.text, 0.08)
                        Rectangle { height: parent.height; radius: 2; color: App.Console.ok; width: parent.width * page.selTasks.filter(t => t.status === "completed").length / Math.max(1, page.selTasks.length) }
                    }
                    Flickable {
                        visible: page.selTasks.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(420, taskCol.implicitHeight)
                        contentHeight: taskCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ColumnLayout {
                            id: taskCol
                            width: parent.width
                            spacing: 2
                            Repeater {
                                // doing first, then open, then done
                                model: page.selTasks.slice().sort((a, b) => ({ in_progress: 0, pending: 1, completed: 2 })[a.status] - ({ in_progress: 0, pending: 1, completed: 2 })[b.status])
                                // a task: a row to click (opens it here: what it is, since when, what blocks it, actions)
                                Rectangle {
                                    id: ct
                                    required property var modelData
                                    readonly property bool open: page.openTask === modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: ctCol.implicitHeight + 10
                                    radius: App.Console.radiusSmall
                                    color: ct.open ? App.Console.panelAlt : ctHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                                    HoverHandler { id: ctHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: page.openTask = ct.open ? "" : ct.modelData.id }
                                    ColumnLayout {
                                        id: ctCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5; leftMargin: 6; rightMargin: 6 }
                                        spacing: 6
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Ui.Icon {
                                                text: ct.modelData.status === "completed" ? "check_circle" : ct.modelData.status === "in_progress" ? "play_circle" : "radio_button_unchecked"
                                                filled: ct.modelData.status !== "pending"
                                                size: 16
                                                color: ct.modelData.status === "completed" ? App.Console.ok : ct.modelData.status === "in_progress" ? App.Console.data : App.Console.faint
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: ct.modelData.status === "in_progress" && ct.modelData.active ? ct.modelData.active : ct.modelData.subject
                                                elide: ct.open ? Text.ElideNone : Text.ElideRight
                                                wrapMode: ct.open ? Text.Wrap : Text.NoWrap
                                                font.family: App.Console.sans; font.pixelSize: 13
                                                font.strikeout: ct.modelData.status === "completed"
                                                color: ct.modelData.status === "completed" ? App.Console.faint : App.Console.text
                                            }
                                            Text { visible: !!ct.modelData.since; text: ct.modelData.since ? App.Store.ago(ct.modelData.since) : ""; font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                        }
                                        // opened: the whole of it
                                        Text {
                                            visible: ct.open && !!ct.modelData.description
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 24
                                            text: ct.modelData.description ?? ""
                                            wrapMode: Text.Wrap
                                            font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim
                                        }
                                        Text {
                                            visible: ct.open && (ct.modelData.blocked_by ?? []).length > 0
                                            Layout.leftMargin: 24
                                            text: qsTr("waits for #%1").arg((ct.modelData.blocked_by ?? []).join(", #"))
                                            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.warn
                                        }
                                        RowLayout {
                                            visible: ct.open
                                            Layout.leftMargin: 24
                                            spacing: 6
                                            App.Tag { text: "#" + ct.modelData.id + " · " + ({ pending: qsTr("open"), in_progress: qsTr("doing"), completed: qsTr("done") })[ct.modelData.status]; tone: App.Console.faint }
                                            Item { Layout.fillWidth: true }
                                            Ui.IconButton { icon: "add_task"; tooltip: qsTr("Track it as a Dotos task"); onClicked: App.Store.capture(ct.modelData.subject + (page.sel?.project ? " +" + page.sel.project : "")) }
                                            Ui.IconButton { icon: "content_copy"; tooltip: qsTr("Copy"); onClicked: Quickshell.execDetached(["wl-copy", ct.modelData.subject + (ct.modelData.description ? "\n\n" + ct.modelData.description : "")]) }
                                            Ui.IconButton { icon: "terminal"; tooltip: qsTr("Jump to the terminal"); onClicked: App.Store.jump(page.sel) }
                                        }
                                        // Teams: a conversation on what the agent does here
                                        App.TaskThread {
                                            visible: ct.open
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 24
                                            item: ct.open && page.sel ? "agent:" + page.sel.id + "#" + ct.modelData.id : ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                    App.Label { text: qsTr("Working on"); visible: !!page.onCard }
                    Loader {
                        active: !!page.onCard
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: App.TaskRow { task: page.onCard; compact: true }
                    }
                    App.Label { text: qsTr("Last prompt") }
                    Text { Layout.fillWidth: true; text: App.Store.clean(page.sel?.prompt) || "—"; wrapMode: Text.Wrap; maximumLineCount: 6; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                    GridLayout {
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 4
                        App.Label { text: qsTr("Folder") }
                        Text { Layout.fillWidth: true; text: page.sel?.cwd ?? ""; elide: Text.ElideMiddle; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
                        App.Label { text: qsTr("Tool calls") }
                        Text { text: String(page.sel?.tools ?? 0) + (page.sel?.last_tool ? " · last " + page.sel.last_tool : ""); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
                        App.Label { text: qsTr("Started") }
                        Text { text: App.Store.ago(page.sel?.started); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
                        App.Label { text: qsTr("Updated") }
                        Text { text: App.Store.ago(page.sel?.updated); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
                    }
                    App.Label { text: qsTr("Commits · %1").arg(page.commits.length); Layout.topMargin: 6; visible: page.commits.length > 0 }
                    Repeater {
                        model: page.commits.slice(0, 6)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: modelData.hash; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.data }
                            Text { text: modelData.repo; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                            Text { Layout.fillWidth: true; text: modelData.msg; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                            Text { text: App.Store.ago(modelData.t); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                        }
                    }
                    App.Label { text: qsTr("Linked tasks"); Layout.topMargin: 6 }
                    Repeater {
                        model: page.linked
                        delegate: App.TaskRow { required property var modelData; Layout.fillWidth: true; task: modelData; compact: true }
                    }
                    Text {
                        visible: page.linked.length === 0
                        Layout.fillWidth: true
                        text: qsTr("No task points at this chat. Give one the link agent:%1 to wait on it.").arg(page.sel?.id ?? "")
                        wrapMode: Text.Wrap
                        font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint
                    }
                    Item { Layout.fillHeight: true }

                }
            }
        }
    }
}
