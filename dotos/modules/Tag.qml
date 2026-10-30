import QtQuick
import "." as App

// A small mono pill: a tag, a due date, an estimate. `tone` colours the text
// and the outline; `filled` tints the inside too.
Rectangle {
    id: root
    property string text: ""
    property color tone: App.Console.dim
    property bool filled: false
    implicitWidth: label.implicitWidth + 14
    implicitHeight: 20
    radius: 10
    color: root.filled ? Qt.alpha(root.tone, 0.16) : "transparent"
    border.width: 1
    border.color: Qt.alpha(root.tone, root.filled ? 0 : 0.45)
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.family: App.Console.mono
        font.pixelSize: 11
        color: root.tone
    }
}
