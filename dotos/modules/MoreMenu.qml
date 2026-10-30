import QtQuick
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * The ⋮ menu: a column of entries dropped from its anchor's corner.
 * `items` = [{ icon, label, hint (shortcut), action, separator }]
 */
Item {
    id: root
    property var items: []
    property bool open: false
    property Item anchorItem: null
    signal picked(string action)

    anchors.fill: parent
    visible: root.open
    z: 90

    function toggle() { root.open = !root.open; }

    // click anywhere else closes it
    TapHandler { onTapped: root.open = false }

    Rectangle {
        id: menu
        // under its button, or the toolbar's ⋮ spot when none is given
        readonly property point at: root.anchorItem ? root.anchorItem.mapToItem(root, root.anchorItem.width, root.anchorItem.height) : Qt.point(root.width - 12, 64)
        x: Math.max(8, at.x - width)
        y: at.y + 6
        width: 310
        height: list.implicitHeight + 12
        radius: Ui.Appearance.rounding.small   // as Rodded's menus: small rounding, highest surface, outline
        color: Ui.Appearance.surfaceContainerHighest
        border.width: 1
        border.color: Ui.Appearance.outlineVariant
        TapHandler {}

        ColumnLayout {
            id: list
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 0
            Repeater {
                model: root.items
                delegate: Loader {
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: modelData.separator ? sep : entry
                    Component {
                        id: sep
                        Item {
                            implicitHeight: 9
                            Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: App.Console.rule }
                        }
                    }
                    Component {
                        id: entry
                        Rectangle {
                            implicitHeight: 40
                            radius: Ui.Appearance.rounding.small
                            color: hov.hovered ? Qt.alpha(App.Console.text, 0.08) : "transparent"
                            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.open = false;
                                    root.picked(modelData.action);
                                }
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 10
                                Ui.Icon { text: modelData.icon ?? ""; size: 20; color: App.Console.dim }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.family: App.Console.sans
                                    font.pixelSize: 15
                                    color: App.Console.text
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.hint ?? ""
                                    font.family: App.Console.mono
                                    font.pixelSize: 12
                                    color: App.Console.faint
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
