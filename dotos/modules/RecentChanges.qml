import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * RecentChanges: a compact, embeddable card showing what changed recently —
 * tasks added/edited/done, agent activity, and tasks in progress right now.
 * Drop into any page to make the changes tab functionality visible everywhere.
 */
Item {
    id: root

    property int maxItems: 5
    property var changes: []
    property var working: null
    property bool loading: false
    property bool compact: false
    property int prevCount: 0
    property bool flashing: false

    function load() {
        root.loading = true;
        changesProc.command = [App.Store.bin, "diff", "--json"];
        changesProc.running = true;
        workingProc.command = [App.Store.bin, "diff", "--working"];
        workingProc.running = true;
    }

    Process {
        id: changesProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const newChanges = (d.changes || []).filter(c => (c.title || c.id || "").trim().length > 0).slice(0, root.maxItems);
                    if (newChanges.length > root.prevCount && root.prevCount > 0) {
                        root.flashing = true;
                        flashTimer.restart();
                    }
                    root.prevCount = newChanges.length;
                    root.changes = newChanges;
                } catch (e) { root.changes = []; }
                root.loading = false;
            }
        }
        stderr: StdioCollector { onStreamFinished: { root.loading = false; } }
    }

    Process {
        id: workingProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.working = JSON.parse(text); } catch (e) { root.working = null; }
            }
        }
    }

    Component.onCompleted: root.load()

    Timer {
        id: flashTimer
        interval: 500
        onTriggered: root.flashing = false
    }

    // auto-refresh to catch new changes quickly
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.load()
    }

    Rectangle {
        id: flashOverlay
        anchors.fill: parent
        color: root.flashing ? Qt.alpha(App.Console.data, 0.08) : "transparent"
        border.width: root.flashing ? 2 : 0
        border.color: Qt.alpha(App.Console.data, 0.6)
        radius: 4
        Behavior on border.width { NumberAnimation { duration: 150 } }
        z: -1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.compact ? 4 : 8

        // Working now
        RowLayout {
            visible: !root.compact && root.working && (root.working.in_progress ?? []).length > 0
            spacing: 6
            Ui.Icon { text: "play_circle"; size: 14; color: App.Console.ok }
            Text {
                text: qsTr("%1 task%2 in progress").arg((root.working?.working_tasks ?? []).length).arg((root.working?.working_tasks ?? []).length === 1 ? "" : "s")
                font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text
            }
        }

        // Recent changes list
        Repeater {
            model: root.changes
            delegate: RowLayout {
                required property var modelData
                spacing: 6
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 6; implicitHeight: 6; radius: 3
                    color: {
                        const op = modelData.op ?? modelData.kind ?? "";
                        if (op.includes("done") || op.includes("complete")) return App.Console.ok;
                        if (op.includes("add") || op.includes("create")) return App.Console.data;
                        if (op.includes("edit") || op.includes("update")) return App.Console.warn;
                        return App.Console.dim;
                    }
                }
                Text {
                    text: modelData.title ?? modelData.summary ?? modelData.op ?? "change"
                    font.family: App.Console.sans; font.pixelSize: root.compact ? 11 : 12
                    color: App.Console.text
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    visible: !root.compact
                    text: modelData.t ? new Date(modelData.t * 1000).toLocaleTimeString() : ""
                    font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint
                }
            }
        }

        Text {
            visible: root.changes.length === 0 && !root.loading
            text: qsTr("No recent changes")
            font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
        }

        Text {
            visible: root.loading
            text: qsTr("Loading...")
            font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
        }
    }
}