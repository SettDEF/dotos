import QtQuick
import "." as App

// A round icon button. The glyph is centred by anchors on a square box, so
// every button in a row lines up regardless of which symbol it carries.
Rectangle {
    id: btn
    property string icon: ""
    property string tooltip: ""
    property bool active: false
    signal clicked

    implicitWidth: 32
    implicitHeight: 32
    radius: width / 2
    // quiet at rest: a fill only on hover and press, so a row of them reads as icons, not as buttons
    color: btn.active ? Qt.alpha(App.Appearance.primary, 0.2)
         : tap.pressed ? Qt.alpha(App.Appearance.onSurface, 0.12)
         : hov.hovered ? Qt.alpha(App.Appearance.onSurface, 0.08)
         : "transparent"
    Behavior on color { ColorAnimation { duration: 140 } }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: btn.clicked() }

    App.Icon {
        anchors.fill: parent
        text: btn.icon
        size: 18
        filled: btn.active
        color: btn.active ? App.Appearance.primary
             : hov.hovered ? App.Appearance.onSurface
             : App.Appearance.onSurfaceVariant
    }
}
