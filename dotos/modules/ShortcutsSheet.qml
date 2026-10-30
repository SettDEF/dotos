import QtQuick
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/** Every key the window answers to, grouped. `shortcuts` comes from dotos.qml, the one list the key handler also reads. */
App.Sheet {
    id: sheet
    title: qsTr("Keyboard shortcuts")
    icon: "keyboard"
    maxWidth: 520
    property var shortcuts: []

    Repeater {
        model: [...new Set(sheet.shortcuts.map(s => s.group))]
        delegate: ColumnLayout {
            id: grp
            required property string modelData
            Layout.fillWidth: true
            spacing: 2
            App.Label { text: grp.modelData; Layout.bottomMargin: 4 }
            Repeater {
                model: sheet.shortcuts.filter(s => s.group === grp.modelData)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        font.family: App.Console.sans
                        font.pixelSize: 15
                        color: App.Console.text
                    }
                    Repeater {
                        model: modelData.keys
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: Math.max(26, keyText.implicitWidth + 14)
                            implicitHeight: 24
                            radius: 6
                            color: App.Console.panel
                            border.width: 1
                            border.color: App.Console.ruleStrong
                            Text {
                                id: keyText
                                anchors.centerIn: parent
                                text: modelData
                                font.family: App.Console.mono
                                font.pixelSize: 12
                                color: App.Console.text
                            }
                        }
                    }
                }
            }
            Item { implicitHeight: 6 }
        }
    }
}
