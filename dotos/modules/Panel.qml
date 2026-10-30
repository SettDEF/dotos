import QtQuick
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * A titled card: icon, title, a quiet note on the right (or controls in
 * `tools`), a rule, then the content. The building block of every page.
 */
Rectangle {
    id: root
    property string title: ""
    property string icon: ""
    property color iconColor: App.Console.data
    property string note: ""
    property bool padded: true
    /// the content fills the card (a chart); otherwise it sits at the top and the card may be taller
    property bool stretch: false
    default property alias content: body.data
    property alias tools: toolSlot.data
    signal noteClicked()

    radius: App.Console.radius
    color: App.Console.panel
    implicitHeight: col.implicitHeight + 24

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 12; leftMargin: 14; rightMargin: 14 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            visible: root.title.length > 0
            spacing: 8
            Ui.Icon { visible: root.icon.length > 0; text: root.icon; size: 18; color: root.iconColor }
            Text { text: root.title; font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
            Item { Layout.fillWidth: true }
            RowLayout { id: toolSlot; spacing: 4 }
            Text {
                visible: root.note.length > 0
                text: root.note
                font.family: App.Console.mono
                font.pixelSize: 12
                color: noteHov.hovered ? App.Console.text : App.Console.faint
                HoverHandler { id: noteHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.noteClicked() }
            }
        }
        // no flat separator rules: the glass edge is the only separation
        Rectangle { visible: root.title.length > 0; Layout.fillWidth: true; implicitHeight: 1; color: App.Console.rule }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: root.stretch
            spacing: 2
        }
        Item { visible: !root.stretch; Layout.fillHeight: true }
    }
}
