import QtQuick
import QtQuick.Layouts
import "." as App

/**
 * One-of-N, as a single track with an indicator that slides.
 *
 * Not four buttons that each colour themselves: with per-segment fills, a
 * hover draws a second pill beside the selected one and the eye reads "two
 * selected" before it reads "two shades". One indicator cannot lie that way.
 *
 * `model` is a list of { key, label }. `current` is the selected key.
 */
Rectangle {
    id: root

    property var model: []
    property string current: ""
    signal picked(string key)

    implicitHeight: 28
    radius: App.Appearance.rounding.full
    // a quiet track: the segments sit on it, only the selected one is accent
    color: Qt.alpha(App.Appearance.onSurface, 0.06)

    Rectangle {
        id: indicator
        // Placed by whichever segment is selected, so the geometry comes from
        // the layout rather than from arithmetic that has to be kept in step.
        property real targetX: 0
        property real targetW: 0
        x: targetX
        width: targetW
        y: 2
        height: parent.height - 4
        radius: App.Appearance.rounding.full
        color: Qt.alpha(App.Appearance.primary, 0.2)
        visible: targetW > 0
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        id: row
        anchors { fill: parent; margins: 2 }
        spacing: 0

        Repeater {
            model: root.model
            delegate: Item {
                id: seg
                required property var modelData
                readonly property bool sel: root.current === modelData.key
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Re-placed on resize too, not just on selection, so the
                // indicator follows the window instead of being set once.
                function place() {
                    if (!seg.sel) return;
                    indicator.targetX = row.x + seg.x;
                    indicator.targetW = seg.width;
                }
                onSelChanged: place()
                onXChanged: place()
                onWidthChanged: place()
                Component.onCompleted: place()

                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.picked(seg.modelData.key) }

                Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: seg.modelData.label
                    font.family: App.Appearance.font.family
                    font.pixelSize: App.Appearance.font.smaller
                    font.weight: seg.sel ? Font.DemiBold : Font.Normal
                    // the selected label takes the accent; hover brightens the rest
                    color: seg.sel ? App.Appearance.primary
                         : hov.hovered ? App.Appearance.onSurface
                         : App.Appearance.onSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }
        }
    }
}
