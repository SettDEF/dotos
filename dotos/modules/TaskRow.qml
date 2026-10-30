import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * One task as a row: a check ring in its list's colour, the title (double
 * click renames in place), and what matters at a glance on the right — the
 * running timer, state, due, project, priority, estimate. Hover reveals the
 * quick actions; a click opens it in the inspector.
 */
Rectangle {
    id: row
    required property var task
    property bool showProject: true
    property bool compact: false
    readonly property bool sel: App.Nav.selected === row.task.uid
    readonly property bool done: row.task.state === "done" || row.task.state === "cancelled"
    readonly property bool timing: App.Store.active?.uid === row.task.uid
    readonly property int subs: App.Store.subtasks(row.task.uid).length
    readonly property int subsOpen: App.Store.subtasks(row.task.uid).filter(t => t.state !== "done" && t.state !== "cancelled").length
    readonly property bool renaming: App.Nav.renaming === row.task.uid
    /// opened below itself: its AI sessions and notes (a click on a selected row, or Enter)
    readonly property bool open: App.Nav.opened === row.task.uid
    readonly property var sessions: App.Store.sessionsOf(row.task)
    readonly property int headHeight: row.compact ? 34 : 40

    implicitHeight: row.headHeight + (row.open ? details.implicitHeight + 8 : 0)
    clip: true
    Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    radius: 8
    color: row.sel ? Qt.alpha(App.Console.data, 0.14) : hov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
    HoverHandler { id: hov }
    TapHandler {
        // the first click selects, the next opens it (or closes it)
        onTapped: {
            if (row.sel) App.Nav.opened = row.open ? "" : row.task.uid;
            else App.Nav.selected = row.task.uid;
        }
        onDoubleTapped: if (!row.done) App.Nav.renaming = row.task.uid
    }
    // right click: the task's own menu (not Qt's text menu)
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (ev) => {
            App.Nav.selected = row.task.uid;
            const p = row.mapFromItem(null, ev.scenePosition.x, ev.scenePosition.y);
            menu.x = Math.min(p.x, row.width - menu.width);
            menu.y = p.y;
            menu.open();
        }
    }
    App.TaskMenu {
        id: menu
        task: row.task
        sessions: row.sessions
        onRename: App.Nav.renaming = row.task.uid
        onToggleOpen: App.Nav.opened = row.open ? "" : row.task.uid
    }

    RowLayout {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8 + (row.task.parent ? 22 : 0); rightMargin: 8 }
        height: row.headHeight
        spacing: 10

        // status indicator (professional, animated)
        App.StatusIndicator {
            state: row.done ? "done"
                 : row.task.state === "doing" ? "doing"
                 : row.task.state === "waiting" ? "waiting"
                 : row.task.state === "cancelled" ? "cancelled"
                 : row.task.state === "blocked" ? "blocked"
                 : "todo"
            listColor: App.Store.colorOf(row.task.list)
            size: 20
            TapHandler { onTapped: App.Store.toggleDone(row.task) }
        }

        // title, or the rename field
        Text {
            visible: !row.renaming
            Layout.fillWidth: true
            text: row.task.title
            font.family: App.Console.sans
            font.pixelSize: 15
            font.strikeout: row.done
            color: row.done ? App.Console.faint : App.Console.text
            elide: Text.ElideRight
        }
        TextField {
            id: textField1
            visible: row.renaming
            Layout.fillWidth: true
            text: row.task.title
            font.family: App.Console.sans
            font.pixelSize: 15
            color: App.Console.text
            background: Rectangle { radius: 6; color: App.Console.bg; border.width: 1; border.color: App.Console.data }
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
            // its text menu only while renaming (hidden, it must never answer a right click)
            ContextMenu.menu: null
            onAccepted: { if (text.trim() && text !== row.task.title) App.Store.set(row.task.uid, ["title=" + text.trim()]); App.Nav.renaming = ""; }
            onActiveFocusChanged: if (!activeFocus && row.renaming) App.Nav.renaming = ""
            Keys.onEscapePressed: App.Nav.renaming = ""
        }

        // hover actions
        Ui.IconButton {
            visible: hov.hovered && !row.done && !row.renaming
            implicitWidth: 26; implicitHeight: 26
            icon: row.timing ? "stop" : "play_arrow"
            tooltip: row.timing ? qsTr("Stop the timer") : qsTr("Start the timer on this")
            onClicked: row.timing ? App.Store.stop() : App.Store.track(row.task.uid)
        }

        Tag { visible: row.timing; text: "● " + App.Store.dur(row.task.tracked_today_s); tone: App.Console.data; filled: true }
        Tag { visible: row.subs > 0; text: `${row.subs - row.subsOpen}/${row.subs}`; tone: App.Console.dim }
        Tag {
            visible: !row.done && ["inbox", "waiting", "doing"].includes(row.task.state) && !row.timing
            text: row.task.state === "waiting" && row.task.waiting_on ? "waiting · " + row.task.waiting_on : row.task.state
            tone: App.Store.stateColor(row.task.state)
        }
        Tag { visible: !row.done && !!row.task.blocked; text: qsTr("blocked"); tone: App.Console.warn }
        // who does it (Teams: assigned from a message, or dotos set ID assignee=…)
        Tag { visible: (row.task.assignee ?? "").length > 0; text: "@" + String(row.task.assignee ?? "").replace(/^agent:/, "🤖 "); tone: Qt.lighter(App.Console.data, 1.7) }
        Tag { visible: row.showProject && row.task.project.length > 0; text: "+" + row.task.project; tone: App.Store.colorOf(row.task.project) }
        Tag { visible: !row.compact && row.task.tags.length > 0; text: "#" + row.task.tags.join(" #"); tone: App.Console.faint }
        Ui.Icon { visible: row.task.priority === "high" && !row.done; text: "flag"; filled: true; size: 15; color: App.Console.crit }
        Text {
            visible: row.task.estimate_min > 0 && !row.compact
            text: App.Store.dur(row.task.estimate_min * 60)
            font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint
        }
        Text {
            visible: !!row.task.due
            Layout.preferredWidth: 92
            horizontalAlignment: Text.AlignRight
            text: App.Store.dueLabel(row.task)
            font.family: App.Console.mono
            font.pixelSize: 12
            color: row.task.overdue && !row.done ? App.Console.crit : row.task.bucket === "today" ? App.Console.data : App.Console.dim
        }
        Ui.Icon { visible: row.task.recurring; text: "repeat"; size: 14; color: App.Console.faint }
    }

    // opened: its AI sessions (Open session jumps to the terminal), its notes, quick actions
    ColumnLayout {
        id: details
        visible: row.open
        anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: 36 + (row.task.parent ? 22 : 0); rightMargin: 10 }
        spacing: 6
        Repeater {
            model: row.sessions
            delegate: RowLayout {
                id: srow
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: srow.modelData.state === "working" ? App.Console.data : srow.modelData.state === "ended" ? App.Console.faint : App.Console.warn }
                Text {
                    Layout.fillWidth: true
                    text: `${srow.modelData.project ?? ""} · ${srow.modelData.state ?? ""} · ${App.Store.ago(srow.modelData.updated)}` + (srow.modelData.prompt ? ` — “${srow.modelData.prompt}”` : "")
                    elide: Text.ElideRight
                    font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
                }
                Ui.Chip { text: qsTr("Open session  S"); interactive: srow.modelData.state !== "ended"; filled: true; accent: App.Console.data; onClicked: App.Store.jump(srow.modelData) }
            }
        }
        Text {
            visible: row.sessions.length === 0
            text: qsTr("No AI session works on this.")
            font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint
        }
        Text {
            visible: (row.task.notes ?? "").length > 0
            Layout.fillWidth: true
            text: row.task.notes ?? ""
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text
        }
        RowLayout {
            spacing: 6
            Ui.Chip { interactive: true; filled: true; accent: App.Console.data; text: row.timing ? qsTr("Stop  T") : qsTr("Timer  T"); visible: !row.done; onClicked: row.timing ? App.Store.stop() : App.Store.track(row.task.uid) }
            Ui.Chip { interactive: true; filled: true; accent: App.Console.data; text: qsTr("Doing  D"); visible: !row.done && row.task.state !== "doing"; onClicked: App.Store.setState(row.task.uid, "doing") }
            Ui.Chip { interactive: true; filled: true; accent: App.Console.data; text: qsTr("Open in Tasks"); onClicked: App.Nav.go("tasks") }
        }
    }
}
