import QtQuick
import "." as App

// A switch, the same as Vitals' option switches.
Rectangle {
    id: root
    property bool on: false
    signal toggled(bool on)
    implicitWidth: 40; implicitHeight: 22; radius: 11
    color: root.on ? App.Console.data : Qt.alpha(App.Console.text, 0.14)
    Behavior on color { ColorAnimation { duration: 140 } }
    Rectangle {
        width: 16; height: 16; radius: 8; y: 3
        x: root.on ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: 140 } }
        color: root.on ? App.Console.onData : App.Console.dim
    }
    TapHandler { onTapped: root.toggled(!root.on) }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
