import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * Habits: each with its last four weeks as a strip of days (click a day to
 * fix it), its streak, and this week against its target. Daily habits count
 * days in a row; "3 times a week" habits count weeks that met the target.
 */
Item {
    id: page
    property string key: "habits"
    property string newName: ""
    property int newPerWeek: 7
    // keys: j/k the habit, x (or Enter) ticks it for today
    property int cur: -1
    readonly property var keyHelp: [[qsTr("Move"), ["j", "k"]], [qsTr("Tick for today"), ["x"]]]
    function handleKey(e) {
        const hs = App.Store.habits;
        const m = K.move(e, hs.length, page.cur);
        if (m >= 0) { page.cur = m; return true; }
        if (page.cur >= 0 && page.cur < hs.length && (K.isOpen(e) || (K.plain(e) && e.key === Qt.Key_X))) { App.Store.habitCheck(hs[page.cur].name); return true; }
        return false;
    }

    function dayIso(back) {
        const d = new Date(App.Store.today + "T12:00:00");
        d.setDate(d.getDate() - back);
        return Qt.formatDateTime(d, "yyyy-MM-dd");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Habits")
            subtitle: App.Store.habits.length ? qsTr("%1 of %2 done today · best streak %3")
                .arg(App.Store.habits.filter(h => h.done_today).length).arg(App.Store.habits.length)
                .arg(Math.max(0, ...App.Store.habits.map(h => h.streak))) : qsTr("nothing tracked yet")
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: col
                x: 14; y: 14
                width: parent.width - 28
                spacing: 10

                // nothing yet: a few to start from
                Column {
                    Layout.fillWidth: true
                    Layout.topMargin: 70
                    visible: App.Store.habits.length === 0 && App.Store.loaded
                    spacing: 12
                    Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "autorenew"; size: 44; color: App.Console.faint }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Habits you want to keep"); font.family: App.Console.sans; font.pixelSize: 20; font.weight: Font.DemiBold; color: App.Console.text }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("One tap a day. A streak counts the days in a row, or the weeks you hit your target."); font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.dim }
                    Flow {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width - 40, 560)
                        spacing: 8
                        Repeater {
                            model: [
                                { n: qsTr("Read"), w: 7, i: "menu_book" }, { n: qsTr("Gym"), w: 3, i: "fitness_center" }, { n: qsTr("Walk"), w: 7, i: "directions_walk" },
                                { n: qsTr("Water"), w: 7, i: "water_drop" }, { n: qsTr("Stretch"), w: 5, i: "self_improvement" }, { n: qsTr("Meditate"), w: 7, i: "spa" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: sRow.implicitWidth + 24; implicitHeight: 38; radius: 19
                                color: sHov.hovered ? Qt.alpha(App.Console.data, 0.2) : App.Console.panel
                                HoverHandler { id: sHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: App.Store.habitAdd(modelData.n, modelData.w, modelData.i) }
                                Row {
                                    id: sRow
                                    anchors.centerIn: parent
                                    spacing: 7
                                    Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: modelData.i; size: 18; color: App.Console.data }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.n; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.w >= 7 ? qsTr("daily") : modelData.w + qsTr("× wk"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                }
                            }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("or type your own above"); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                }

                Repeater {
                    model: App.Store.habits
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 92
                        radius: App.Console.radius
                        color: index === page.cur ? App.Console.panelAlt : App.Console.panel
                        border.width: index === page.cur ? 2 : 0
                        border.color: App.Console.data
                        RowLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 16
                            // today's big check
                            Rectangle {
                                implicitWidth: 56; implicitHeight: 56; radius: 18
                                color: card.modelData.done_today ? App.Console.ok : tHov.hovered ? App.Console.panelAlt : Qt.alpha(App.Console.text, 0.05)
                                HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: App.Store.habitCheck(card.modelData.name) }
                                Ui.Icon { anchors.centerIn: parent; text: card.modelData.done_today ? "check" : card.modelData.icon; size: 26; filled: card.modelData.done_today; color: card.modelData.done_today ? App.Console.bg : App.Console.dim }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 300
                                Layout.maximumWidth: 300
                                spacing: 2
                                Text { text: card.modelData.name; font.family: App.Console.sans; font.pixelSize: 17; font.weight: Font.DemiBold; color: App.Console.text }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: card.modelData.per_week >= 7 ? qsTr("daily · %1 days in a row").arg(card.modelData.streak)
                                        : qsTr("%1× a week · %2 this week · %3 weeks met").arg(card.modelData.per_week).arg(card.modelData.this_week).arg(card.modelData.streak)
                                    font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim
                                }
                            }
                            // the last 28 days, oldest first
                            Row {
                                Layout.fillWidth: true
                                spacing: 3
                                Repeater {
                                    model: card.modelData.recent
                                    delegate: Rectangle {
                                        required property bool modelData
                                        required property int index
                                        readonly property int back: 27 - index
                                        width: 14; height: 30; radius: 4
                                        color: modelData ? App.Console.ok : dHov.hovered ? Qt.alpha(App.Console.text, 0.16) : Qt.alpha(App.Console.text, 0.07)
                                        border.width: back === 0 ? 1 : 0
                                        border.color: App.Console.data
                                        HoverHandler { id: dHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: App.Store.habitCheck(card.modelData.name, page.dayIso(back)) }
                                        Ui.Tip { visible: dHov.hovered; text: page.dayIso(back) }
                                    }
                                }
                            }
                            Ui.IconButton { icon: "delete"; tooltip: qsTr("Remove this habit"); onClicked: App.Store.habitRemove(card.modelData.name) }
                        }
                    }
                }

                // add one
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: App.Console.radius
                    color: App.Console.panel
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 10 }
                        spacing: 10
                        Ui.Icon { text: "add"; size: 20; color: App.Console.data }
                        TextField {
                            ContextMenu.menu: Ui.TextMenu { target: nameField }
                            id: nameField
                            Layout.fillWidth: true
                            placeholderText: qsTr("A new habit — read, gym, walk…")
                            placeholderTextColor: App.Console.faint
                            background: null
                            color: App.Console.text
                            font.family: App.Console.sans; font.pixelSize: 15
                            onAccepted: if (text.trim()) { App.Store.habitAdd(text.trim(), page.newPerWeek, "autorenew"); text = ""; }
                        }
                        Ui.SegmentedControl {
                            implicitWidth: 300
                            model: [{ key: "7", label: qsTr("Daily") }, { key: "5", label: qsTr("5× wk") }, { key: "3", label: qsTr("3× wk") }, { key: "1", label: qsTr("Weekly") }]
                            current: String(page.newPerWeek)
                            onPicked: k => page.newPerWeek = Number(k)
                        }
                    }
                }

            }
        }
    }
}
