// The right-click menu of a text field, in the app's look (Qt 6.9+ gives every field a plain one).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as Ui

Menu {
    id: menu
    /// the TextField / TextArea it edits
    required property Item target

    padding: 6
    background: Rectangle {
        implicitWidth: 210
        radius: Appearance.rounding.normal
        color: Appearance.surfaceContainerHigh
        border.width: 1
        border.color: Qt.alpha(Appearance.onSurface, 0.08)
    }

    component Entry: MenuItem {
        id: it
        property string glyph
        property string keys
        implicitHeight: 32
        leftPadding: 10; rightPadding: 10
        contentItem: RowLayout {
            spacing: 10
            opacity: it.enabled ? 1 : 0.38
            Ui.Icon { text: it.glyph; size: 16; color: Appearance.onSurfaceVariant }
            Text { Layout.fillWidth: true; text: it.text; font.family: Appearance.font.family; font.pixelSize: 13; color: Appearance.onSurface }
            Text { text: it.keys; font.family: Appearance.font.family; font.pixelSize: 11; color: Appearance.onSurfaceVariant }
        }
        background: Rectangle {
            radius: Appearance.rounding.small ?? 8
            color: it.highlighted && it.enabled ? Qt.alpha(Appearance.onSurface, 0.08) : "transparent"
        }
    }
    component Line: MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Qt.alpha(Appearance.onSurface, 0.08) }
    }

    Entry { text: qsTr("Undo"); glyph: "undo"; keys: "Ctrl Z"; enabled: menu.target.canUndo; onTriggered: menu.target.undo() }
    Entry { text: qsTr("Redo"); glyph: "redo"; keys: "Ctrl ⇧ Z"; enabled: menu.target.canRedo; onTriggered: menu.target.redo() }
    Line {}
    Entry { text: qsTr("Cut"); glyph: "content_cut"; keys: "Ctrl X"; enabled: menu.target.selectedText.length > 0 && !menu.target.readOnly; onTriggered: menu.target.cut() }
    Entry { text: qsTr("Copy"); glyph: "content_copy"; keys: "Ctrl C"; enabled: menu.target.selectedText.length > 0; onTriggered: menu.target.copy() }
    Entry { text: qsTr("Paste"); glyph: "content_paste"; keys: "Ctrl V"; enabled: menu.target.canPaste; onTriggered: menu.target.paste() }
    Line {}
    Entry { text: qsTr("Select all"); glyph: "select_all"; keys: "Ctrl A"; enabled: menu.target.length > 0; onTriggered: menu.target.selectAll() }
}
