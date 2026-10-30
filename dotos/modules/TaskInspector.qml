import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * The selected task, all of it, editable where it stands: title, state,
 * when, priority, where it belongs, notes, subtasks, links, time and its
 * history. Every field saves on Enter / leaving it, through `dotos set`.
 */
Rectangle {
    id: insp
    readonly property var t: App.Store.task(App.Nav.selected)
    readonly property bool timing: !!insp.t && App.Store.active?.uid === insp.t.uid
    visible: !!insp.t
    radius: App.Console.radius
    color: App.Console.panel

    component Field: RowLayout {
        id: f
        property string label: ""
        property string value: ""
        property string placeholder: ""
        property string key: ""
        Layout.fillWidth: true
        spacing: 8
        Text { Layout.preferredWidth: 78; text: f.label; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
        TextField {
            id: textField1
            ContextMenu.menu: Ui.TextMenu { target: textField1 }
            Layout.fillWidth: true
            text: f.value
            placeholderText: f.placeholder
            placeholderTextColor: App.Console.faint
            font.family: App.Console.mono
            font.pixelSize: 13
            color: App.Console.text
            selectByMouse: true
            background: Rectangle { radius: 8; color: parent.activeFocus ? App.Console.bg : "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: App.Console.data }
            function save() { if (text !== f.value) App.Store.set(insp.t.uid, [f.key + "=" + text]); }
            onAccepted: { save(); focus = false; }
            onActiveFocusChanged: if (!activeFocus) save()
        }
    }

    Flickable {
        id: flick
        anchors { fill: parent; margins: 16 }
        contentHeight: col.implicitHeight
        clip: true
        // the screenshot tool scrolls the inspector too (view "task:UID@600")
        Connections { target: App.Nav; function onShotScroll(y) { flick.contentY = Math.min(y, Math.max(0, flick.contentHeight - flick.height)); } }
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: (insp.t?.list ?? "") + (insp.t?.origin && insp.t.origin !== "user" ? "  ·  from " + insp.t.origin.split(":").slice(0, 2).join(":") : "")
                    font.family: App.Console.mono; font.pixelSize: 12; color: App.Store.colorOf(insp.t?.list)
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "delete"; tooltip: qsTr("Delete  (Del)"); onClicked: { App.Store.remove(insp.t.uid); App.Nav.selected = ""; } }
                Ui.IconButton { implicitWidth: 28; implicitHeight: 28; icon: "close"; tooltip: qsTr("Close"); onClicked: App.Nav.selected = "" }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                App.StatusIndicator {
                    state: insp.t?.state ?? "todo"
                    size: 24
                }
                TextArea {
                    id: textField2
                    ContextMenu.menu: Ui.TextMenu { target: textField2 }
                    Layout.fillWidth: true
                    text: insp.t?.title ?? ""
                    wrapMode: TextEdit.Wrap
                    font.family: App.Console.sans
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    color: App.Console.text
                    background: null
                    padding: 0
                    Keys.onReturnPressed: focus = false
                    onActiveFocusChanged: if (!activeFocus && insp.t && text.trim() && text !== insp.t.title) App.Store.set(insp.t.uid, ["title=" + text.trim()])
                }
            }

            // state: one track, the current one lit
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: ["inbox", "todo", "doing", "waiting", "done"]
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool on: insp.t?.state === modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: on ? 90 : 40
                        implicitHeight: 30
                        radius: 15
                        Ui.Tip { visible: sHov.hovered && !on; text: modelData }
                        color: on ? Qt.alpha(App.Store.stateColor(modelData), 0.2) : sHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                        border.width: 1
                        border.color: on ? App.Store.stateColor(modelData) : App.Console.rule
                        HoverHandler { id: sHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.Store.setState(insp.t.uid, modelData) }
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: App.Store.stateIcon(modelData); size: 14; filled: on; color: on ? App.Store.stateColor(modelData) : App.Console.dim }
                            Text { visible: on || parent.parent.width > 74; anchors.verticalCenter: parent.verticalCenter; text: modelData; font.family: App.Console.sans; font.pixelSize: 12; color: on ? App.Console.text : App.Console.dim }
                        }
                    }
                }
            }

            // time
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 12
                color: insp.timing ? Qt.alpha(App.Console.data, 0.14) : App.Console.panelAlt
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: App.Store.dur(insp.t?.tracked_today_s) + qsTr(" today"); font.family: App.Console.mono; font.pixelSize: 14; color: App.Console.text }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: App.Store.dur(insp.t?.tracked_week_s) + qsTr(" this week") + (insp.t?.estimate_min ? qsTr(" · estimate %1").arg(App.Store.dur(insp.t.estimate_min * 60)) : ""); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.dim }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        implicitWidth: tRow.implicitWidth + 24
                        implicitHeight: 34
                        radius: 17
                        color: insp.timing ? App.Console.crit : App.Console.data
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: insp.timing ? App.Store.stop() : App.Store.track(insp.t.uid) }
                        Row {
                            id: tRow
                            anchors.centerIn: parent
                            spacing: 6
                            Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: insp.timing ? "stop" : "play_arrow"; filled: true; size: 18; color: App.Console.onData }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: insp.timing ? qsTr("Stop") : qsTr("Track"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.onData }
                        }
                    }
                }
            }

            Field { label: qsTr("Due"); key: "due"; value: insp.t?.due ? (insp.t.due_time ? insp.t.due.slice(0, 16).replace("T", " ") : insp.t.due.slice(0, 10)) : ""; placeholder: qsTr("fri · 2026-10-20 · +3d · today 14:00") }
            // push the date without typing it (`dotos snooze`)
            RowLayout {
                Layout.fillWidth: true
                visible: !!insp.t?.due || insp.t?.state === "todo" || insp.t?.state === "doing"
                spacing: 6
                Text { Layout.preferredWidth: 78; text: qsTr("Snooze"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                Repeater {
                    model: [{ l: qsTr("Tomorrow"), w: "tomorrow" }, { l: "+3d", w: "+3d" }, { l: qsTr("Monday"), w: "mon" }, { l: "+1w", w: "+1w" }]
                    delegate: Ui.Chip { required property var modelData; text: modelData.l; interactive: true; accent: App.Console.data; onClicked: App.Store.snooze(insp.t.uid, modelData.w) }
                }
                Item { Layout.fillWidth: true }
            }
            Field { label: qsTr("Repeat"); key: "repeat"; value: App.Store.repeatLabel(insp.t); placeholder: qsTr("daily · 3d · mon,thu · +3d from done · none") }
            Field { label: qsTr("Priority"); key: "priority"; value: insp.t?.priority ?? ""; placeholder: "high · normal · low" }
            Field { label: qsTr("Project"); key: "project"; value: insp.t?.project ?? ""; placeholder: qsTr("a folder under your projects") }
            Field { label: qsTr("List"); key: "list"; value: insp.t?.list ?? "" }
            Field { label: qsTr("Tags"); key: "tags"; value: (insp.t?.tags ?? []).join(", ") ; placeholder: "a, b" }
            Field { label: qsTr("Estimate"); key: "estimate"; value: insp.t?.estimate_min ? App.Store.dur(insp.t.estimate_min * 60).replace(" ", "") : ""; placeholder: "30m · 2h" }
            // blocked by other tasks: it stays out of the plan until they are done
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { Layout.preferredWidth: 78; text: qsTr("Blocked by"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                    TextField {
                        ContextMenu.menu: Ui.TextMenu { target: blockField }
                        id: blockField
                        Layout.fillWidth: true
                        placeholderText: qsTr("find a task it waits on…")
                        placeholderTextColor: App.Console.faint
                        font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text
                        selectByMouse: true
                        background: Rectangle { radius: 8; color: parent.activeFocus ? App.Console.bg : "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: App.Console.data }
                        Keys.onEscapePressed: { text = ""; focus = false; }
                    }
                }
                Repeater {
                    model: App.Store.blockedBy(insp.t?.uid ?? "")
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 86
                        Ui.Icon { text: modelData.state === "done" ? "check_circle" : "lock"; size: 14; color: modelData.state === "done" ? App.Console.ok : App.Console.warn }
                        Text { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text
                               HoverHandler { cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: App.Nav.selected = modelData.uid } }
                        Ui.IconButton { implicitWidth: 22; implicitHeight: 22; icon: "close"; onClicked: App.Store.set(insp.t.uid, ["blocked-=" + modelData.uid]) }
                    }
                }
                // matches while typing: a click makes it a blocker
                Repeater {
                    model: blockField.text.trim().length < 2 ? [] : App.Store.open.filter(x => x.uid !== insp.t?.uid && !(insp.t?.blocked_by ?? []).includes(x.uid)
                        && x.title.toLowerCase().includes(blockField.text.trim().toLowerCase())).slice(0, 4)
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 86
                        implicitHeight: 28; radius: 6
                        color: mHov.hovered ? Qt.alpha(App.Console.data, 0.16) : App.Console.panelAlt
                        HoverHandler { id: mHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { App.Store.set(insp.t.uid, ["blocked+=" + modelData.uid]); blockField.text = ""; blockField.focus = false; } }
                        Text { anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 8 } text: modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                    }
                }
            }
            Field { visible: insp.t?.state === "waiting"; label: qsTr("Waiting on"); key: "waiting"; value: insp.t?.waiting_on ?? ""; placeholder: qsTr("a person, an agent, a date") }

            // its corner of the graph: notes, project, subtasks, blockers, AI sessions, commits
            App.LocalGraph { Layout.fillWidth: true; Layout.topMargin: 4; nodeId: insp.t ? "task:" + insp.t.uid : "" }

            // spider-web (radar) of this task's tags: each axis is a tag, the value is how many
            // tasks share it — so a wide web means a well-connected tag, a narrow one a niche tag
            App.SpiderWebChart {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                Layout.topMargin: 8
                visible: (insp.t?.tags ?? insp.t?.categories ?? []).length >= 3
                tags: {
                    const t = insp.t;
                    if (!t) return [];
                    const tags = t.tags ?? t.categories ?? [];
                    const all = App.Store.tasks ?? [];
                    return tags.map(tag => ({
                        name: tag,
                        value: all.filter(x => (x.tags ?? x.categories ?? []).includes(tag)).length,
                        color: App.Store.colorOf(tag)
                    }));
                }
            }

            App.Label { text: qsTr("Notes"); Layout.topMargin: 4 }
            TextArea {
                id: textField3
                ContextMenu.menu: Ui.TextMenu { target: textField3 }
                Layout.fillWidth: true
                Layout.minimumHeight: 80
                text: insp.t?.notes ?? ""
                placeholderText: qsTr("Anything worth remembering…")
                placeholderTextColor: App.Console.faint
                wrapMode: TextEdit.Wrap
                font.family: App.Console.sans
                font.pixelSize: 14
                color: App.Console.text
                selectByMouse: true
                background: Rectangle { radius: 10; color: App.Console.bg; border.width: parent.activeFocus ? 1 : 0; border.color: App.Console.data }
                onActiveFocusChanged: if (!activeFocus && insp.t && text !== insp.t.notes) App.Store.set(insp.t.uid, ["notes=" + text.replace(/\n/g, "\\n")])
            }

            App.Label { text: qsTr("Subtasks"); Layout.topMargin: 4 }
            Repeater {
                model: App.Store.subtasks(insp.t?.uid ?? "")
                delegate: TaskRow { required property var modelData; Layout.fillWidth: true; task: modelData; compact: true; showProject: false }
            }
            TextField {
                id: textField4
                ContextMenu.menu: Ui.TextMenu { target: textField4 }
                Layout.fillWidth: true
                placeholderText: qsTr("Add a subtask…")
                placeholderTextColor: App.Console.faint
                font.family: App.Console.sans
                font.pixelSize: 14
                color: App.Console.text
                background: Rectangle { radius: 8; color: App.Console.panelAlt }
                onAccepted: { App.Store.sub(insp.t.uid, text); text = ""; }
            }

            App.Label { text: qsTr("Links"); Layout.topMargin: 4; visible: (insp.t?.links ?? []).length > 0 }
            Repeater {
                model: insp.t?.links ?? []
                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    Ui.Icon { text: modelData.startsWith("http") ? "link" : modelData.startsWith("agent:") ? "smart_toy" : "description"; size: 16; color: App.Console.dim }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.replace(/^file:\/\//, "")
                        font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.data
                        elide: Text.ElideMiddle
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.Store.openLink(modelData) }
                    }
                    Ui.IconButton { implicitWidth: 24; implicitHeight: 24; icon: "close"; onClicked: App.Store.set(insp.t.uid, ["link-=" + modelData]) }
                }
            }
            TextField {
                id: textField5
                ContextMenu.menu: Ui.TextMenu { target: textField5 }
                Layout.fillWidth: true
                placeholderText: qsTr("Add a link (url, /path/file:line)…")
                placeholderTextColor: App.Console.faint
                font.family: App.Console.mono
                font.pixelSize: 12
                color: App.Console.text
                background: Rectangle { radius: 8; color: App.Console.panelAlt }
                onAccepted: { if (text.trim()) App.Store.set(insp.t.uid, ["link+=" + text.trim()]); text = ""; }
            }

            // what the AI sessions on this card did: commands, files written and deleted
            Repeater {
                model: App.Store.sessionsOf(insp.t)
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 4
                    App.Label { text: qsTr("Agent activity · %1").arg(String(modelData.project ?? modelData.id)) }
                    App.AgentActions { Layout.fillWidth: true; sessionId: modelData.id; taskUid: insp.t?.uid ?? "" }
                }
            }

            App.Label { text: qsTr("Conversation"); Layout.topMargin: 4 }
            App.TaskThread { Layout.fillWidth: true; item: insp.t ? "task:" + insp.t.uid : ""; decision: insp.t?.decision ?? "" }

            App.Label { text: qsTr("History"); Layout.topMargin: 4 }
            Repeater {
                model: App.Store.log.filter(e => e.uid === insp.t?.uid).slice(-8).reverse()
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: App.Store.ago(modelData.t); Layout.preferredWidth: 80; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                    Text { text: modelData.op + (modelData.undone ? qsTr(" (undone)") : ""); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.dim }
                    Text { Layout.fillWidth: true; text: modelData.who; horizontalAlignment: Text.AlignRight; font.family: App.Console.mono; font.pixelSize: 11; color: modelData.who === "user" ? App.Console.faint : App.Console.warn }
                }
            }
            Text {
                visible: !!insp.t?.created
                text: qsTr("created %1").arg(String(insp.t?.created ?? "").replace("T", " ").slice(0, 16))
                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
            }
        }
    }
}
