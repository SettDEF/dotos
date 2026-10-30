import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "." as App
import "../ui" as Ui

/**
 * A task's right-click menu: what can be done with it, each with its key (the row's own keys).
 */
Popup {
    id: menu
    required property var task
    /// the AI sessions working on it
    property var sessions: []
    signal rename()
    signal toggleOpen()

    padding: 6
    width: 240
    background: Rectangle { radius: 10; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }

    readonly property bool done: menu.task.state === "done" || menu.task.state === "cancelled"
    readonly property bool timing: App.Store.active?.uid === menu.task.uid
    readonly property var items: [
        { icon: "unfold_more", text: qsTr("Open / close"), key: "Enter", run: () => menu.toggleOpen() },
        { icon: "terminal", text: qsTr("Open session"), key: "s", on: menu.sessions.length > 0, run: () => App.Store.jump(menu.sessions[0]) },
        { icon: menu.timing ? "stop" : "play_arrow", text: menu.timing ? qsTr("Stop the timer") : qsTr("Start the timer"), key: "t", on: !menu.done, run: () => menu.timing ? App.Store.stop() : App.Store.track(menu.task.uid) },
        { icon: "pending", text: qsTr("Doing"), key: "d", on: !menu.done && menu.task.state !== "doing", run: () => App.Store.setState(menu.task.uid, "doing") },
        { icon: "check", text: menu.done ? qsTr("Not done") : qsTr("Done"), key: "x", run: () => App.Store.toggleDone(menu.task) },
        { icon: "edit", text: qsTr("Rename"), key: "r", on: !menu.done, run: () => menu.rename() },
        { icon: "content_copy", text: qsTr("Copy the title"), key: "y", run: () => Quickshell.clipboardText = menu.task.title }
    ]

    contentItem: ColumnLayout {
        spacing: 2
        Repeater {
            model: menu.items
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: modelData.on ?? true
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 7
                color: on && mh.hovered ? Qt.alpha(App.Console.text, 0.08) : "transparent"
                opacity: on ? 1 : 0.4
                HoverHandler { id: mh; enabled: parent.on }
                TapHandler { enabled: parent.on; onTapped: { menu.close(); parent.modelData.run(); } }
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 10
                    Ui.Icon { text: modelData.icon; size: 16; color: App.Console.dim }
                    Text { Layout.fillWidth: true; text: modelData.text; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                    Text { text: modelData.key; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                }
            }
        }
    }
}
