import QtQuick
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * A page's toolbar: title and subtitle on the left, the page's own controls
 * (default children) and the ⋮ menu on the right — in a row BELOW the
 * compositor's window-button pill, which sits in the top-right corner, so
 * the two never meet.
 */
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    default property alias actions: slot.data
    readonly property Item menuButton: menuBtn

    Layout.fillWidth: true
    // narrow: the controls go under the title instead of over it
    readonly property bool stacked: width < tools.implicitWidth + 240
    implicitHeight: stacked ? 70 + 40 : 70

    ColumnLayout {
        anchors { left: parent.left; right: root.stacked ? parent.right : tools.left; verticalCenter: root.stacked ? undefined : parent.verticalCenter; top: root.stacked ? parent.top : undefined; topMargin: 14; leftMargin: 20; rightMargin: root.stacked ? 120 : 16 }
        spacing: 0
        Text {
            Layout.fillWidth: true
            text: root.title
            font.family: App.Console.sans
            font.pixelSize: 22
            font.weight: Font.DemiBold
            color: App.Console.text
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle
            font.family: App.Console.mono
            font.pixelSize: 12
            color: App.Console.dim
            elide: Text.ElideRight
        }
    }

    // under the window-button pill (top 4 + 22 px tall)
    RowLayout {
        id: tools
        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: root.stacked ? 70 : 30 }
        height: 34
        spacing: 6
        RowLayout { id: slot; spacing: 6 }
        Ui.IconButton {
            id: menuBtn
            icon: "more_vert"
            tooltip: qsTr("Menu")
            onClicked: App.Nav.run("menu")
        }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: App.Console.rule }
}
