import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * History: every change, who made it — you, an extension, the AI — and the
 * button that takes the newest one back. The log is also what makes an AI
 * or an extension safe to let loose: nothing it does is unaccountable.
 */
Item {
    id: page
    property string key: "history"
    property string who: "all"
    readonly property var entries: App.Store.log.slice().reverse()
        .filter(e => page.who === "all" || (page.who === "user" ? e.who === "user" : e.who !== "user"))
    // keys: j/k the change, Enter opens its task, u undoes the last
    property int cur: -1
    function isClaude(e) { return String(e.op ?? "").startsWith("claude:"); }
    readonly property var keyHelp: [[qsTr("Move"), ["j", "k"]], [qsTr("Open its task"), ["Enter"]], [qsTr("Undo the last"), ["u"]]]
    function handleKey(e) {
        const m = K.move(e, page.entries.length, page.cur);
        if (m >= 0) { page.cur = m; histList.positionViewAtIndex(m, ListView.Contain); return true; }
        if (K.isOpen(e) && page.cur >= 0) { const x = page.entries[page.cur]; if (page.isClaude(x)) App.Nav.openAgentTask("claude-" + x.session, x.uid.split(":").pop()); else if (App.Store.task(x.uid)) App.Nav.openTask(x.uid); return true; }
        if (K.plain(e) && e.key === Qt.Key_U) { App.Nav.run("undo"); return true; }
        return false;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        App.Toolbar {
            title: qsTr("History")
            subtitle: qsTr("the last %1 changes · undo takes back the newest one").arg(App.Store.log.length)
            Ui.SegmentedControl {
                implicitWidth: 340
                model: [{ key: "all", label: qsTr("Everyone") }, { key: "user", label: qsTr("You") }, { key: "other", label: qsTr("Extensions · AI") }]
                current: page.who
                onPicked: k => page.who = k
            }
            Rectangle {
                implicitWidth: uRow.implicitWidth + 26; implicitHeight: 36; radius: 18
                color: App.Console.panelAlt
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: App.Nav.run("undo") }
                Row {
                    id: uRow
                    anchors.centerIn: parent
                    spacing: 6
                    Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: "undo"; size: 18; color: App.Console.text }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Undo  Ctrl Z"); font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            radius: App.Console.radius
            color: App.Console.panel
            ListView {
                id: histList
                anchors { fill: parent; margins: 8 }
                clip: true
                model: page.entries
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 38
                    radius: 7
                    color: hHov.hovered || index === page.cur ? App.Console.panelAlt : (index % 2 ? Qt.alpha(App.Console.text, 0.025) : "transparent")
                    border.width: index === page.cur ? 1 : 0
                    border.color: App.Console.data
                    opacity: modelData.undone ? 0.5 : 1
                    HoverHandler { id: hHov; cursorShape: App.Store.task(modelData.uid) || page.isClaude(modelData) ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { onTapped: page.isClaude(modelData) ? App.Nav.openAgentTask("claude-" + modelData.session, modelData.uid.split(":").pop()) : App.Store.task(modelData.uid) && App.Nav.openTask(modelData.uid) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 14
                        Text { Layout.preferredWidth: 110; text: Qt.formatDateTime(new Date(modelData.t * 1000), "dd MMM HH:mm"); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                        Ui.Icon {
                            text: ({ add: "add_circle", edit: "edit", state: "swap_horiz", rm: "delete", undo: "undo", "claude:new": "add_task", "claude:start": "play_circle", "claude:done": "task_alt", "claude:reopen": "restart_alt" })[modelData.op] ?? "change_history"
                            size: 17
                            color: modelData.op === "rm" ? App.Console.crit : modelData.op === "undo" ? App.Console.warn : modelData.op === "claude:done" ? App.Console.ok : page.isClaude(modelData) ? App.Console.data : App.Console.dim
                        }
                        Text { Layout.preferredWidth: 60; text: page.isClaude(modelData) ? ({ "claude:new": qsTr("new"), "claude:start": qsTr("started"), "claude:done": qsTr("done"), "claude:reopen": qsTr("reopened") })[modelData.op] ?? modelData.op : modelData.op + (modelData.undid ? " " + modelData.undid : ""); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                        Text { Layout.fillWidth: true; text: modelData.title ?? modelData.uid; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; font.strikeout: !!modelData.undone; color: App.Console.text }
                        Text { text: modelData.list ?? ""; font.family: App.Console.mono; font.pixelSize: 11; color: App.Store.colorOf(modelData.list) }
                        App.Tag { text: modelData.who; tone: modelData.who === "user" ? App.Console.faint : modelData.who.startsWith("ai") ? App.Console.data : App.Console.warn }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: page.entries.length === 0
                    text: qsTr("No changes yet.")
                    font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim
                }
            }
        }
    }
}
