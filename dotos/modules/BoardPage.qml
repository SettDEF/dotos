import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * The board: one column per state, cards you drag between them. Dropping a
 * card on a column is `dotos state <uid> <column>`. Filtered by project when
 * one is picked, so the same board serves the project page too.
 */
Item {
    id: page
    property string key: "board"
    /// "" = every project; the project page sets its own
    property string project: ""
    property bool embedded: false

    readonly property var columns: [
        { key: "inbox", label: qsTr("Inbox"), icon: "inbox" },
        { key: "todo", label: qsTr("To do"), icon: "radio_button_unchecked" },
        { key: "doing", label: qsTr("Doing"), icon: "play_circle" },
        { key: "waiting", label: qsTr("Waiting"), icon: "hourglass_top" },
        { key: "done", label: qsTr("Done"), icon: "check_circle" }
    ]
    readonly property var pool: App.Store.tasks.filter(t => !t.parent && t.state !== "cancelled"
        && (!page.project || t.project.toLowerCase() === page.project.toLowerCase()))
    function inColumn(k) {
        const list = page.pool.filter(t => t.state === k);
        // done: the latest first, and only the last 14 days (the snapshot's window)
        if (k === "done") return list.sort((a, b) => String(b.completed).localeCompare(String(a.completed))).slice(0, 30);
        return list.sort((a, b) => (a.priority === "high" ? 0 : 1) - (b.priority === "high" ? 0 : 1) || String(a.due ?? "9").localeCompare(String(b.due ?? "9")));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            visible: !page.embedded
            title: qsTr("Board")
            subtitle: qsTr("%1 doing · %2 waiting · drag a card to change its state").arg(App.Store.doing).arg(App.Store.waiting)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: page.embedded ? 0 : 14
            spacing: 10

            Repeater {
                model: page.columns
                delegate: Rectangle {
                    id: col
                    required property var modelData
                    readonly property var cards: page.inColumn(col.modelData.key)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: App.Console.radius
                    color: drop.containsDrag ? Qt.alpha(App.Store.stateColor(col.modelData.key), 0.10) : App.Console.panel
                    border.width: drop.containsDrag ? 1 : 0
                    border.color: App.Store.stateColor(col.modelData.key)

                    DropArea {
                        id: drop
                        anchors.fill: parent
                        keys: ["dotos-task"]
                        onDropped: d => { if (d.source && d.source.task && d.source.task.state !== col.modelData.key) App.Store.setState(d.source.task.uid, col.modelData.key); }
                    }

                    ColumnLayout {
                        anchors { fill: parent; margins: 8 }
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            spacing: 6
                            Ui.Icon { text: col.modelData.icon; size: 16; color: App.Store.stateColor(col.modelData.key) }
                            Text { text: col.modelData.label; font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.text }
                            Text { text: col.cards.length; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                            Item { Layout.fillWidth: true }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: col.cards
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Item {
                                id: holder
                                required property var modelData
                                width: ListView.view.width
                                height: card.height

                                Rectangle {
                                    id: card
                                    property var task: holder.modelData
                                    width: holder.width
                                    // the title (one to three lines) and, under it, the tags when there are any
                                    height: titleRow.implicitHeight + 18 + (cardCol.implicitHeight > 0 ? cardCol.implicitHeight + 6 : 0)
                                    radius: 10
                                    color: App.Nav.selected === card.task.uid ? Qt.alpha(App.Console.data, 0.18) : cHov.hovered ? App.Console.panelAlt : Qt.alpha(App.Console.text, 0.05)
                                    border.width: App.Store.active?.uid === card.task.uid ? 1 : 0
                                    border.color: App.Console.data
                                    opacity: card.task.state === "done" ? 0.6 : 1

                                    Drag.active: dragger.active
                                    Drag.keys: ["dotos-task"]
                                    Drag.source: card
                                    Drag.hotSpot.x: width / 2
                                    Drag.hotSpot.y: 12
                                    states: State {
                                        when: dragger.active
                                        ParentChange { target: card; parent: page }
                                        PropertyChanges { target: card; z: 100; opacity: 0.9 }
                                    }
                                    HoverHandler { id: cHov; cursorShape: dragger.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor }
                                    DragHandler {
                                        id: dragger
                                        onActiveChanged: if (!active) { card.Drag.drop(); card.x = 0; card.y = 0; }
                                    }
                                    TapHandler { onTapped: App.Nav.openTask(card.task.uid); onDoubleTapped: App.Store.toggleDone(card.task) }

                                    RowLayout {
                                        id: titleRow
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9; leftMargin: 11; rightMargin: 9 }
                                        spacing: 6
                                        App.StatusIndicator {
                                            state: card.task.state === "done" ? "done"
                                                 : card.task.state === "doing" ? "doing"
                                                 : card.task.state === "waiting" ? "waiting"
                                                 : card.task.state === "cancelled" ? "cancelled"
                                                 : "todo"
                                            listColor: App.Store.colorOf(card.task.list)
                                            size: 14
                                            TapHandler { onTapped: App.Store.toggleDone(card.task) }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: card.task.title
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                            font.family: App.Console.sans; font.pixelSize: 14
                                            font.strikeout: card.task.state === "done"
                                            color: App.Console.text
                                        }
                                    }
                                    ColumnLayout {
                                        id: cardCol
                                        anchors { left: parent.left; right: parent.right; top: titleRow.bottom; leftMargin: 11; rightMargin: 9; topMargin: 6 }
                                        spacing: 5
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            App.Tag { visible: !page.project && card.task.project.length > 0; text: "+" + card.task.project; tone: App.Store.colorOf(card.task.project) }
                                            App.Tag { visible: !!card.task.due; text: App.Store.dueLabel(card.task); tone: card.task.overdue ? App.Console.crit : App.Console.dim }
                                            App.Tag { visible: card.task.waiting_on.length > 0; text: card.task.waiting_on; tone: App.Console.warn }
                                            App.Tag { visible: App.Store.active?.uid === card.task.uid; text: "● " + App.Store.dur(card.task.tracked_today_s); tone: App.Console.data; filled: true }
                                            App.Tag { visible: card.task.estimate_min > 0; text: App.Store.dur(card.task.estimate_min * 60); tone: App.Console.faint }
                                            Ui.Icon { visible: card.task.priority === "high"; text: "flag"; filled: true; size: 14; color: App.Console.crit }
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: col.cards.length === 0
                                text: qsTr("drop here")
                                font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint
                            }
                        }
                    }
                }
            }

            App.TaskInspector {
                visible: !page.embedded && !!App.Store.task(App.Nav.selected)
                Layout.preferredWidth: 340
                Layout.fillHeight: true
            }
        }
    }
}
