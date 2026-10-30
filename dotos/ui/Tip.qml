// A tooltip in the shell's popup style: a raised rounded surface with an
// outline, the title in the app font, values in mono and aligned. Plain
// `text` works as well; `rows` add "name … value" lines under a title.
//
//   Ui.Tip { visible: hov.hovered; text: "Collapse sidebar" }
//   Ui.Tip { visible: hov.hovered; title: "Fri 2 Oct"; rows: [{ name: "loom", value: "2h", color: c }] }
//
// It opens under its parent, centred; set x / y to put it elsewhere.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as Ui

ToolTip {
    id: tip

    property string title: ""
    /// [{ name, value, color }] — color is optional (a small dot)
    property var rows: []

    delay: 250
    timeout: -1
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? parent.height + 8 : 0
    leftPadding: 12
    rightPadding: 12
    topPadding: 8
    bottomPadding: 8

    background: Rectangle {
        radius: Ui.Appearance.rounding.small
        color: Ui.Appearance.surfaceContainerHighest
        border.width: 1
        border.color: Ui.Appearance.outlineVariant
    }

    contentItem: ColumnLayout {
        spacing: 4
        Text {
            visible: tip.title.length > 0
            text: tip.title
            font.family: Ui.Appearance.font.family
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Ui.Appearance.onSurface
        }
        Text {
            visible: tip.text.length > 0
            text: tip.text
            font.family: Ui.Appearance.font.family
            font.pixelSize: 13
            lineHeight: 1.2
            color: tip.title.length > 0 ? Ui.Appearance.onSurfaceVariant : Ui.Appearance.onSurface
        }
        Repeater {
            model: tip.rows
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    visible: !!modelData.color
                    implicitWidth: 8; implicitHeight: 8; radius: 2
                    color: modelData.color ?? "transparent"
                }
                Text {
                    text: modelData.name
                    font.family: Ui.Appearance.font.family
                    font.pixelSize: 12
                    color: Ui.Appearance.onSurfaceVariant
                }
                Item { Layout.fillWidth: true; Layout.minimumWidth: 14 }
                Text {
                    text: modelData.value
                    font.family: Ui.Appearance.font.mono
                    font.pixelSize: 12
                    color: Ui.Appearance.onSurface
                }
            }
        }
    }
}
