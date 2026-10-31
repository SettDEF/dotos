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
 * own under the title, and wrap there, rather than squeezing the subtitle.
 */
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    /// the page's controls go straight into the wrapping row, so each one wraps on its own
    default property alias actions: tools.data
    readonly property Item menuButton: menuBtn

    Layout.fillWidth: true
    /// the controls' width in one line: each one's, and the gaps between
    readonly property real toolsWidth: {
        let w = 0;
        for (let i = 0; i < tools.children.length; i++) w += tools.children[i].implicitWidth + tools.spacing;
        return Math.max(0, w - tools.spacing);
    }
    // narrow: the controls go under the title instead of beside it, and wrap there if they must
    readonly property bool stacked: width < root.toolsWidth + 40 + 280
    implicitHeight: stacked ? 68 + Math.max(tools.height, 32) + 12 : 72

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

    // the ⋮ menu: at the pill's right, on the controls' first line
    Ui.IconButton {
        id: menuBtn
        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: root.stacked ? 68 : 28 }
        icon: "more_vert"
        tooltip: qsTr("Menu")
        onClicked: App.Nav.run("menu")
    }

    // beside the title, or on its own line when narrow (then it wraps)
    Flow {
        id: tools
        anchors.top: parent.top
        anchors.topMargin: root.stacked ? 68 : 28
        anchors.left: root.stacked ? parent.left : undefined
        anchors.leftMargin: 20
        anchors.right: root.stacked ? undefined : menuBtn.left
        anchors.rightMargin: 8
        width: root.stacked ? root.width - 20 - 40 : root.toolsWidth
        spacing: 8
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: App.Console.rule }
}
