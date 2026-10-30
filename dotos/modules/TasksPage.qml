import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * Tasks (and Inbox, the same page filtered to unsorted captures): a capture
 * line, the tasks grouped the way you choose, the inspector on the right.
 * Page tasks (checkboxes in notes) and project TASKS.md lines are not mixed
 * in here — they live on their page and their project.
 */
Item {
    id: page
    property string key: "tasks"
    property string tagFilter: ""   // comma-separated tag names, empty = all
    readonly property var allTags: {
        const set = new Set();
        const tasks = App.Store.tasks || [];
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            const tags = t.tags || t.categories || [];
            for (let j = 0; j < tags.length; j++) set.add(tags[j]);
        }
        return [...set].sort();
    }
    readonly property bool inbox: page.key === "inbox"
    /// the board is a view of this page (a toggle in the toolbar), not a page of its own
    readonly property bool board: !page.inbox && App.Prefs.tasksView === "board"

    readonly property var groupOrder: ({
        bucket: ["overdue", "today", "tomorrow", "week", "later", "someday", "done"],
        state: ["doing", "waiting", "inbox", "todo", "done", "cancelled"],
        priority: ["high", "normal", "low", ""]
    })
    function groupKey(t) {
        switch (App.Prefs.tasksGroup) {
            case "list": return t.list;
            case "project": return t.project || qsTr("no project");
            case "state": return t.state;
            case "priority": return t.state === "done" ? "done" : t.priority;
            default: return t.bucket;
        }
    }
    function groupLabel(g) {
        return ({ overdue: qsTr("Overdue"), today: qsTr("Today"), tomorrow: qsTr("Tomorrow"), week: qsTr("This week"), later: qsTr("Later"),
                  someday: qsTr("Someday"), done: qsTr("Done"), doing: qsTr("Doing"), waiting: qsTr("Waiting"), inbox: qsTr("Inbox"),
                  todo: qsTr("To do"), cancelled: qsTr("Cancelled"), high: qsTr("High priority"), normal: qsTr("Normal"), low: qsTr("Low"), "": qsTr("No priority") })[g] ?? g;
    }

    readonly property var filtered: {
        const q = App.Nav.search.trim().toLowerCase();
        return App.Store.tasks.filter(t => {
            if (t.parent && App.Store.task(t.parent)) return false;          // shown under their parent
            if (page.inbox && t.state !== "inbox") return false;
            const closed = t.state === "done" || t.state === "cancelled";
            if (closed && !App.Prefs.showDone && !q) return false;
            // tag filter (AND logic)
            if (page.tagFilter) {
                const wanted = page.tagFilter.split(",").map(s => s.trim()).filter(Boolean);
                const taskTags = (t.tags ?? t.categories ?? []);
                if (!wanted.every(w => taskTags.includes(w))) return false;
            }
            if (!q) return true;
            return (t.title + " " + t.notes + " " + t.tags.join(" ") + " " + t.project + " " + t.list).toLowerCase().includes(q);
        });
    }
    /// header rows and task rows, in display order
    readonly property var rows: {
        const groups = {};
        for (const t of page.filtered) (groups[page.groupKey(t)] = groups[page.groupKey(t)] ?? []).push(t);
        const order = page.groupOrder[App.Prefs.tasksGroup] ?? Object.keys(groups).sort();
        const keys = order.filter(k => groups[k]).concat(Object.keys(groups).filter(k => !order.includes(k)).sort());
        const out = [];
        for (const k of keys) {
            out.push({ header: true, key: k, label: page.groupLabel(k), n: groups[k].length });
            for (const t of groups[k]) {
                out.push({ header: false, task: t });
                for (const s of App.Store.subtasks(t.uid)) if (App.Prefs.showDone || s.state !== "done") out.push({ header: false, task: s });
            }
        }
        return out;
    }

    // the order j / k walk, and the list follows the selection
    onRowsChanged: App.Nav.order = page.rows.filter(r => !r.header).map(r => r.task.uid)
    Component.onCompleted: App.Nav.order = page.rows.filter(r => !r.header).map(r => r.task.uid)
    Component.onDestruction: App.Nav.order = []
    Connections {
        target: App.Nav
        function onAction(name) { if (name === "capture") capture.take(); }
        function onSelectedChanged() {
            const i = page.rows.findIndex(r => !r.header && r.task.uid === App.Nav.selected);
            if (i >= 0) list.positionViewAtIndex(i, ListView.Contain);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: page.inbox ? qsTr("Inbox") : qsTr("Tasks")
            subtitle: page.inbox ? qsTr("%1 to sort · captured, not yet planned").arg(App.Store.inbox)
                : qsTr("%1 open · %2 overdue · %3 today · %4 doing").arg(App.Store.open.length).arg(App.Store.overdue).arg(App.Store.dueToday).arg(App.Store.doing)

            RowLayout {
                spacing: 6
                Ui.SegmentedControl {
                    visible: !page.inbox
                    implicitWidth: 150
                    model: [{ key: "list", label: qsTr("List") }, { key: "board", label: qsTr("Board") }]
                    current: App.Prefs.tasksView
                    onPicked: k => App.Prefs.tasksView = k
                }
                Ui.SegmentedControl {
                    visible: !page.inbox && !page.board
                    implicitWidth: 300
                    model: [{ key: "bucket", label: qsTr("When") }, { key: "state", label: qsTr("State") }, { key: "project", label: qsTr("Project") }, { key: "list", label: qsTr("List") }]
                    current: App.Prefs.tasksGroup
                    onPicked: k => App.Prefs.tasksGroup = k
                }

                // Tags: one button like the others (not a row of small pills); a popup with every tag
                Rectangle {
                    id: tagBtn
                    visible: !page.inbox && !page.board && page.allTags.length > 0
                    readonly property var picked: page.tagFilter.split(",").map(s => s.trim()).filter(Boolean)
                    implicitWidth: tagRow.implicitWidth + 28; implicitHeight: 34; radius: 17
                    color: tagBtn.picked.length > 0 ? Qt.alpha(App.Console.data, 0.22) : (tagHover.hovered ? App.Console.panelAlt : App.Console.panel)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: tagHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: tagPop.opened ? tagPop.close() : tagPop.open() }
                    RowLayout {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 6
                        Ui.Icon { text: "sell"; size: 16; color: tagBtn.picked.length > 0 ? App.Console.data : App.Console.dim }
                        Text {
                            text: tagBtn.picked.length === 0 ? qsTr("Tags")
                                : tagBtn.picked.length === 1 ? "#" + tagBtn.picked[0]
                                : qsTr("%1 tags").arg(tagBtn.picked.length)
                            font.family: App.Console.sans; font.pixelSize: 14
                            color: tagBtn.picked.length > 0 ? App.Console.text : App.Console.dim
                        }
                        Ui.Icon { text: "expand_more"; size: 16; color: App.Console.dim }
                    }
                    Popup {
                        id: tagPop
                        y: tagBtn.height + 6
                        padding: 6
                        width: 220
                        height: Math.min(tagCol.implicitHeight + 12, 420)
                        background: Rectangle { radius: 10; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }
                        Flickable {
                            anchors.fill: parent
                            contentHeight: tagCol.implicitHeight
                            clip: true
                            ColumnLayout {
                                id: tagCol
                                width: parent.width
                                spacing: 1
                                Repeater {
                                    model: page.allTags
                                    delegate: Rectangle {
                                        id: tagItem
                                        required property var modelData
                                        readonly property string name: String(tagItem.modelData.name || tagItem.modelData)
                                        readonly property bool on: tagBtn.picked.includes(tagItem.name)
                                        Layout.fillWidth: true
                                        implicitHeight: 30; radius: 6
                                        color: itemHover.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                                        HoverHandler { id: itemHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: page.tagFilter = (tagItem.on ? tagBtn.picked.filter(n => n !== tagItem.name) : tagBtn.picked.concat(tagItem.name)).join(",")
                                        }
                                        RowLayout {
                                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                            spacing: 8
                                            Ui.Icon { text: tagItem.on ? "check_box" : "check_box_outline_blank"; size: 16; color: tagItem.on ? App.Console.data : App.Console.faint }
                                            Text { Layout.fillWidth: true; text: "#" + tagItem.name; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                            Text {
                                                text: (App.Store.tasks || []).filter(t => (t.tags || t.categories || []).includes(tagItem.name) && t.state !== "done").length
                                                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                                            }
                                        }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: App.Console.rule; visible: tagBtn.picked.length > 0 }
                                Rectangle {
                                    visible: tagBtn.picked.length > 0
                                    Layout.fillWidth: true
                                    implicitHeight: 30; radius: 6
                                    color: clearHover.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                                    HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { page.tagFilter = ""; tagPop.close(); } }
                                    Text { anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } text: qsTr("Clear the tag filter"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 8
                Ui.IconButton {
                    icon: App.Prefs.showDone ? "visibility" : "visibility_off"
                    active: App.Prefs.showDone
                    tooltip: App.Prefs.showDone ? qsTr("Hide finished") : qsTr("Show finished (last 14 days)")
                    onClicked: App.Prefs.showDone = !App.Prefs.showDone
                }

                Rectangle {
                    implicitWidth: 240; implicitHeight: 34; radius: 17
                    color: App.Console.panelAlt
                    border.width: search.activeFocus ? 1 : 0
                    border.color: App.Console.data
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                        Ui.Icon { text: "search"; size: 15; color: App.Console.faint }
                        TextField {
                            ContextMenu.menu: Ui.TextMenu { target: search }
                            id: search
                            Layout.fillWidth: true
                            text: App.Nav.search
                            placeholderText: qsTr("Filter tasks...")
                            placeholderTextColor: App.Console.faint
                            background: null
                            color: App.Console.text
                            font.family: App.Console.sans; font.pixelSize: 13
                            onTextChanged: App.Nav.search = text
                            Keys.onEscapePressed: { App.Nav.search = ""; focus = false; }
                            Connections { target: App.Nav; function onAction(n) { if (n === "search") search.forceActiveFocus(); } }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                App.CaptureField {
                    id: capture
                    Layout.fillWidth: true
                    suffix: page.inbox ? ">inbox" : ""
                    onAdded: t => { if (t?.uid) App.Nav.selected = t.uid; }
                }

                App.BoardPage {
                    visible: page.board
                    embedded: true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                ListView {
                    id: list
                    visible: !page.board
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    model: page.rows
                    delegate: Loader {
                        id: dl
                        required property var modelData
                        width: list.width
                        sourceComponent: dl.modelData.header ? headerC : rowC
                        Component {
                            id: headerC
                            Rectangle {
                                height: 32
                                width: list.width
                                color: Qt.alpha(App.Console.text, 0.04)
                                radius: 4
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    spacing: 8
                                    Text {
                                        text: dl.modelData.label
                                    font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                                    color: dl.modelData.key === "overdue" ? App.Console.crit : dl.modelData.key === "today" ? App.Console.data : App.Console.dim
                                }
                                Text { Layout.topMargin: 8; text: dl.modelData.n; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                                Item { Layout.fillWidth: true }
                            }
                            }
                        }
                        Component {
                            id: rowC
                            App.TaskRow { task: dl.modelData.task; showProject: App.Prefs.tasksGroup !== "project" }
                        }
                    }

                    // empty states that say what to do
                    Column {
                        anchors.centerIn: parent
                        visible: page.rows.length === 0 && App.Store.loaded
                        spacing: 8
                        Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: page.inbox ? "inbox" : "task_alt"; size: 40; color: App.Console.faint }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: App.Nav.search ? qsTr("Nothing matches “%1”").arg(App.Nav.search)
                                : page.inbox ? qsTr("Inbox zero. Capture with >inbox to sort later.") : qsTr("Nothing open. Type a task above.")
                            font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim
                        }
                    }
                }

            }

            App.TaskInspector {
                Layout.preferredWidth: Math.round(Math.max(360, Math.min(440, page.width * 0.34)))
                Layout.fillHeight: true
                visible: !!App.Store.task(App.Nav.selected)
            }
        }
    }
}
