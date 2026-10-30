import QtQuick
import QtQuick.Layouts
import "." as App

/*
 * One setting: what it is, what it does, and what it is set to.
 *
 * Shape borrowed from quarry's settings — it can host a real control rather
 * than only a switch, it matches the search itself so no second list of names
 * can drift, and an unfinished setting says so instead of offering a dead
 * control.
 */
Rectangle {
    id: root
    property string label: ""
    property string description: ""
    property string value: ""
    property string terms: ""
    property bool available: true
    property string unavailableNote: "not wired up"
    property bool hasSwitch: false
    property bool checked: false
    property string filter: ""
    property bool shown: true

    readonly property bool matched: root.filter.length === 0
        || (root.label + " " + root.description + " " + root.terms + " " + root.value)
           .toLowerCase().indexOf(root.filter) >= 0
    readonly property bool wanted: root.shown && root.matched
    visible: root.wanted

    default property alias control: slot.data
    readonly property bool hasControl: slot.children.length > 0
    property bool interactive: !root.hasControl

    signal toggled(bool on)
    signal clicked

    Layout.fillWidth: true
    implicitHeight: Math.max(48, body.implicitHeight + 16)
    radius: App.Appearance.rounding.small
    color: (!root.available || !root.interactive) ? "transparent"
         : tap.pressed ? App.Appearance.surfaceContainerHigh
         : hov.hovered ? App.Appearance.surfaceContainerHigh
         : "transparent"
    Behavior on color { ColorAnimation { duration: 140 } }

    HoverHandler { id: hov; enabled: root.available && root.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        enabled: root.available && root.interactive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.hasSwitch ? root.toggled(!root.checked) : root.clicked()
    }

    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: root.label
                font.family: App.Appearance.font.family
                font.pixelSize: App.Appearance.font.small
                color: root.available ? App.Appearance.onSurface : App.Appearance.outlineVariant
                elide: Text.ElideRight
            }
            // Says what changes, not what the label already said.
            Text {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                font.family: App.Appearance.font.family
                font.pixelSize: App.Appearance.font.smaller
                color: App.Appearance.onSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }

        Text {
            visible: root.available && root.value.length > 0 && !root.hasSwitch
            text: root.value
            font.family: App.Appearance.font.mono
            font.pixelSize: App.Appearance.font.smaller
            color: App.Appearance.onSurfaceVariant
        }

        RowLayout {
            id: slot
            visible: root.available && root.hasControl
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
        }

        // Switch
        Rectangle {
            visible: root.available && root.hasSwitch
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 44; implicitHeight: 26
            radius: height / 2
            color: root.checked ? App.Appearance.primary : App.Appearance.surfaceContainerHigh
            Behavior on color { ColorAnimation { duration: 160 } }
            Rectangle {
                y: 4
                x: root.checked ? parent.width - width - 4 : 4
                implicitWidth: 18; implicitHeight: 18
                radius: height / 2
                color: root.checked ? App.Appearance.textOnPrimary : App.Appearance.onSurfaceVariant
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }

        // The honest marker: a label saying why, not a dead control.
        Rectangle {
            visible: !root.available
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: note.implicitWidth + 14
            implicitHeight: 22
            radius: height / 2
            color: App.Appearance.surfaceContainerHigh
            Text {
                id: note
                anchors.centerIn: parent
                text: root.unavailableNote
                font.family: App.Appearance.font.family
                font.pixelSize: App.Appearance.font.smallest
                color: App.Appearance.onSurfaceVariant
            }
        }
    }
}
