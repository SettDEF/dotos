import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * The conversations, newest first: each one's kind, title, the last message, its time, and the
 * unread count (red when it holds a mention of us). Click or Up / Down (in the page) opens one.
 */
Rectangle {
    id: list
    property var items: []
    property string current: ""
    signal picked(string item)

    function reveal(i) { view.positionViewAtIndex(i, ListView.Contain); }

    color: App.Console.panel
    radius: App.Console.radius
    clip: true

    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.topMargin: 2
            spacing: 8
            Text { text: qsTr("Conversations"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.text }
            Item { Layout.fillWidth: true }
            Text { text: list.items.length; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
        }

        ListView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: list.items
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool sel: modelData.item === list.current
                readonly property color tint: App.Team.tone(modelData.item)
                width: ListView.view.width
                height: 62
                radius: App.Console.radiusSmall
                color: row.sel ? Qt.alpha(App.Console.data, 0.16) : rowHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: list.picked(row.modelData.item) }

                Rectangle {
                    visible: row.sel
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 3; height: 24; radius: 1.5
                    color: App.Console.data
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 10

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 36; implicitHeight: 36; radius: 11
                        color: Qt.alpha(row.tint, 0.18)
                        Ui.Icon {
                            anchors.centerIn: parent
                            text: App.Team.kindIcon(row.modelData.kind)
                            size: 19
                            color: row.tint
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                elide: Text.ElideRight
                                font.family: App.Console.sans
                                font.pixelSize: 14
                                font.weight: row.modelData.unread > 0 ? Font.DemiBold : Font.Medium
                                color: App.Console.text
                            }
                            Text {
                                text: App.Team.when(row.modelData.last)
                                font.family: App.Console.mono
                                font.pixelSize: 11
                                color: row.modelData.unread > 0 ? App.Console.data : App.Console.faint
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.preview ? App.Team.previewOf(row.modelData) : qsTr("…")
                                elide: Text.ElideRight
                                font.family: App.Console.sans
                                font.pixelSize: 12
                                color: row.modelData.unread > 0 ? App.Console.text : App.Console.dim
                                opacity: row.modelData.unread > 0 ? 0.9 : 0.8
                            }
                            Rectangle {
                                visible: row.modelData.unread > 0
                                implicitWidth: Math.max(18, badgeN.implicitWidth + 10)
                                implicitHeight: 18
                                radius: 9
                                color: row.modelData.mentions > 0 ? App.Console.crit : App.Console.data
                                Text {
                                    id: badgeN
                                    anchors.centerIn: parent
                                    text: row.modelData.unread
                                    font.family: App.Console.mono
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: row.modelData.mentions > 0 ? App.Console.bg : App.Console.onData
                                }
                            }
                        }
                    }
                }
            }

            Text {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                visible: list.items.length === 0
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: App.Team.loaded ? qsTr("No conversations yet. Messages on tasks, projects and pages show here.") : qsTr("Reading the team…")
                font.family: App.Console.sans
                font.pixelSize: 13
                color: App.Console.faint
            }
        }
    }
}
