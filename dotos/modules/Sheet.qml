import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * A dialog over the window: scrim, a card with an icon, a title, optional
 * header buttons and a close, and scrolling content. Esc or a click on the
 * scrim closes it. Content goes in as default children.
 */
Item {
    id: root
    property string title: ""
    property string icon: ""
    property bool open: false
    property real maxWidth: 620
    default property alias content: body.data
    property alias headerActions: actions.data
    signal closed()

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    z: 100

    function close() { root.open = false; root.closed(); }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("black", 0.45)
        TapHandler { onTapped: root.close() }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.maxWidth, parent.width - 48)
        height: Math.min(col.implicitHeight + 32, parent.height - 48)
        radius: Ui.Appearance.rounding.large
        color: App.Console.bg
        border.width: 1
        border.color: App.Console.rule
        scale: root.open ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        // swallow clicks so they do not reach the scrim
        TapHandler {}

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Ui.Icon { text: root.icon; size: 20; filled: true; color: App.Console.data }
                Text {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: App.Console.sans
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    color: App.Console.text
                    elide: Text.ElideRight
                }
                Row { id: actions; spacing: 6 }
                Ui.IconButton { icon: "close"; onClicked: root.close() }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: body.implicitHeight
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 10
                }
            }
        }
    }
}
