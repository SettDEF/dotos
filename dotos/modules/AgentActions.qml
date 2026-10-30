import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * What an AI session did, newest first: its commands, reads, writes, edits and deletes, each with
 * when, what and whether it went through (`dotos agents actions`). "This card" keeps the actions
 * made while the session worked on `taskUid`. A command opens to its full text and error; a
 * file opens in the editor.
 */
ColumnLayout {
    id: acts
    required property string sessionId
    property string taskUid: ""
    property bool onlyCard: taskUid !== ""
    property var info: ({ actions: [], summary: {}, files: [] })
    property int open: -1
    property int shown: 40
    spacing: 4

    function load() {
        if (!acts.sessionId || fetch.running) return;
        fetch.command = [App.Store.bin, "agents", "actions", acts.sessionId].concat(acts.onlyCard ? ["--task", acts.taskUid] : []);
        fetch.running = true;
    }
    onSessionIdChanged: load()
    onOnlyCardChanged: load()
    Component.onCompleted: load()
    // the session file changes with every tool call: the list follows
    Connections { target: App.Store; function onLastLoadChanged() { acts.load(); } }
    Process {
        id: fetch
        stdout: StdioCollector { onStreamFinished: { try { acts.info = JSON.parse(text); } catch (e) {} } }
    }

    function icon(k) {
        return ({ cmd: "terminal", read: "visibility", write: "save", create: "note_add", edit: "edit", delete: "delete", search: "search", web: "public", agent: "smart_toy", plan: "checklist" })[k] ?? "build";
    }
    function short(p) {
        const home = Quickshell.env("HOME") ?? "";
        return home && String(p).startsWith(home) ? "~" + String(p).slice(home.length) : String(p);
    }
    readonly property var list: (acts.info.actions ?? []).slice().reverse()
    readonly property var sum: acts.info.summary ?? {}

    // the counts at a glance, and whose part is shown
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [["cmd", qsTr("commands")], ["edit", qsTr("edits")], ["write", qsTr("writes")], ["create", qsTr("new")], ["delete", qsTr("deleted")], ["read", qsTr("reads")]].filter(k => (acts.sum[k[0]] ?? 0) > 0)
            delegate: Ui.Chip { required property var modelData; text: (acts.sum[modelData[0]] ?? 0) + " " + modelData[1] }
        }
        Ui.Chip { visible: (acts.sum.failed ?? 0) > 0; text: qsTr("%1 failed").arg(acts.sum.failed); accent: App.Console.crit }
        Ui.Chip {
            visible: acts.taskUid !== ""
            text: acts.onlyCard ? qsTr("this card") : qsTr("whole session")
            interactive: true
            accent: App.Console.data
            onClicked: acts.onlyCard = !acts.onlyCard
        }
    }
    Text {
        visible: acts.list.length === 0
        text: acts.onlyCard ? qsTr("nothing done for this card yet") : qsTr("no actions logged for this session")
        font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
    }
    Repeater {
        model: acts.list.slice(0, acts.shown)
        delegate: ColumnLayout {
            id: row
            required property var modelData
            required property int index
            readonly property bool failed: modelData.ok === false
            readonly property bool isFile: ["read", "write", "create", "edit", "delete"].includes(modelData.kind)
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: App.Store.ago(row.modelData.t); Layout.preferredWidth: 74; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                Ui.Icon { text: acts.icon(row.modelData.kind); size: 15; color: row.failed ? App.Console.crit : row.modelData.kind === "delete" ? App.Console.warn : App.Console.dim }
                Text {
                    Layout.fillWidth: true
                    text: row.isFile ? acts.short(row.modelData.what) : (row.modelData.detail && row.modelData.kind === "cmd" ? row.modelData.detail : row.modelData.what)
                    font.family: row.isFile || row.modelData.kind === "cmd" ? App.Console.mono : App.Console.sans
                    font.pixelSize: 12
                    font.strikeout: row.modelData.kind === "delete"
                    color: row.failed ? App.Console.crit : App.Console.text
                    elide: row.isFile ? Text.ElideMiddle : Text.ElideRight
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (row.isFile && row.modelData.kind !== "delete") App.Store.edit(row.modelData.what);
                            else acts.open = acts.open === row.index ? -1 : row.index;
                        }
                    }
                }
            }
            // a command opened: all of it, and what went wrong
            Rectangle {
                visible: acts.open === row.index
                Layout.fillWidth: true
                Layout.leftMargin: 82
                implicitHeight: full.implicitHeight + 12
                radius: 8
                color: App.Console.bg
                Text {
                    id: full
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                    text: row.modelData.what + (row.modelData.error ? "\n\n" + row.modelData.error : "")
                    wrapMode: Text.WrapAnywhere
                    font.family: App.Console.mono; font.pixelSize: 11
                    color: row.failed ? App.Console.crit : App.Console.dim
                }
            }
        }
    }
    Text {
        visible: acts.list.length > acts.shown
        text: qsTr("%1 more…").arg(acts.list.length - acts.shown)
        font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.data
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: acts.shown += 80 }
    }
}
