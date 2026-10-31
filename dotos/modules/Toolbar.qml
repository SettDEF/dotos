import QtQuick
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * A page's header: the title and a quiet subtitle on the left, the page's own
 * controls (default children) and the ⋮ menu on the right. One height for every
 * page, so switching pages does not make the content jump.
 *
 * The controls sit below the compositor's window-button pill (top-right corner,
 * 4..26 px), so the two never meet. Narrow, the controls take a line of their
 * own under the title rather than squeezing the subtitle to nothing.
 */
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    default property alias actions: slot.data
    readonly property Item menuButton: menuBtn

    Layout.fillWidth: true
    // narrow: the controls go under the title instead of beside it
    readonly property bool stacked: width < tools.implicitWidth + 280
    implicitHeight: stacked ? 112 : 72

    ColumnLayout {
        id: heading
        anchors { left: parent.left; top: parent.top; topMargin: 24; leftMargin: 20 }
        anchors.right: root.stacked ? parent.right : tools.left
        anchors.rightMargin: 16
        spacing: 2
        Text {
            Layout.fillWidth: true
            text: root.title
            font.family: App.Console.sans
            font.pixelSize: 20
            font.weight: Font.DemiBold
            color: App.Console.text
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle
            font.family: App.Console.sans
            font.pixelSize: 12
            color: App.Console.dim
            elide: Text.ElideRight
        }
    }

    // beside the title at the pill's right, or on its own line when narrow
    RowLayout {
        id: tools
        anchors.top: parent.top
        anchors.topMargin: root.stacked ? 68 : 28
        anchors.left: root.stacked ? parent.left : undefined
        anchors.leftMargin: 20
        anchors.right: root.stacked ? undefined : parent.right
        anchors.rightMargin: 12
        height: 32
        spacing: 8
        RowLayout { id: slot; spacing: 8 }
        Ui.IconButton {
            id: menuBtn
            icon: "more_vert"
            tooltip: qsTr("Menu")
            onClicked: App.Nav.run("menu")
        }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: App.Console.rule }
}
