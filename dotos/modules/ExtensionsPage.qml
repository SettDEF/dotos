import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui

/**
 * Extensions — sources that bring tasks in, actions that react to changes,
 * views that add pages. Each is a file in the extensions folder that
 * describes itself in its header; its options are edited here and handed to
 * it as DOTOS_OPT_*. The same contract as Vitals' probes.
 */
Item {
    id: page
    property string key: "extensions"
    readonly property var kinds: [
        { key: "source", label: qsTr("Sources"), about: qsTr("bring tasks in, and close them when they are gone"), icon: "download" },
        { key: "action", label: qsTr("Actions"), about: qsTr("run when a task is added, changes state or is done"), icon: "bolt" },
        { key: "view", label: qsTr("Views"), about: qsTr("add a page to the sidebar"), icon: "dashboard_customize" }
    ]

    component OptionRow: RowLayout {
        id: opt
        required property var ext
        required property var option
        readonly property var value: opt.option.value
        Layout.fillWidth: true
        spacing: 10
        Text { Layout.fillWidth: true; text: opt.option.label || opt.option.key; wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
        App.Toggle {
            visible: opt.option.type === "bool"
            on: opt.value === true || opt.value === "1" || opt.value === "true"
            onToggled: v => App.Store.extSet(opt.ext.id, opt.option.key, v)
        }
        Rectangle {
            visible: opt.option.type !== "bool"
            implicitWidth: opt.option.type === "text" ? 320 : 90
            implicitHeight: 30
            radius: 8
            color: Qt.alpha(App.Console.text, 0.06)
            border.width: optIn.activeFocus ? 1 : 0
            border.color: App.Console.data
            TextInput {
                id: optIn
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: Text.AlignVCenter
                text: String(opt.value ?? "")
                clip: true
                font.family: App.Console.mono
                font.pixelSize: 13
                color: App.Console.text
                selectByMouse: true
                onEditingFinished: if (text !== String(opt.value)) App.Store.extSet(opt.ext.id, opt.option.key, text)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        App.Toolbar {
            title: qsTr("Extensions")
            subtitle: qsTr("%1 installed · %2 on · folder: %3").arg(App.Store.extensions.length)
                .arg(App.Store.extensions.filter(e => e.enabled).length).arg(App.Store.configDir + "/extensions")
            Ui.IconButton { icon: "folder_open"; tooltip: qsTr("Open the extensions folder"); onClicked: App.Nav.run("ext-folder") }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: col
                x: 14; y: 14
                width: parent.width - 28
                spacing: 10

                Repeater {
                    model: page.kinds
                    delegate: ColumnLayout {
                        id: kind
                        required property var modelData
                        readonly property var items: App.Store.extensions.filter(e => e.kind === kind.modelData.key)
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 8
                            Ui.Icon { text: kind.modelData.icon; size: 18; color: App.Console.data }
                            Text { text: kind.modelData.label; font.family: App.Console.sans; font.pixelSize: 16; font.weight: Font.DemiBold; color: App.Console.text }
                            Text { text: "— " + kind.modelData.about; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                        }
                        Text {
                            visible: kind.items.length === 0
                            text: qsTr("None installed.")
                            font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
                        }
                        Repeater {
                            model: kind.items
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: cardCol.implicitHeight + 28
                                radius: App.Console.radius
                                color: App.Console.panel
                                opacity: card.modelData.enabled ? 1 : 0.7
                                ColumnLayout {
                                    id: cardCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text { text: card.modelData.name; font.family: App.Console.sans; font.pixelSize: 16; font.weight: Font.DemiBold; color: App.Console.text }
                                            Text { Layout.fillWidth: true; visible: card.modelData.about.length > 0; text: card.modelData.about; wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                        }
                                        App.Tag {
                                            visible: card.modelData.kind === "source"
                                            text: card.modelData.last_run ? (card.modelData.last_ok ? card.modelData.last_msg + " · " + App.Store.ago(card.modelData.last_run) : card.modelData.last_msg) : qsTr("every %1").arg(App.Store.dur(card.modelData.every_min * 60))
                                            tone: card.modelData.last_ok ? App.Console.dim : App.Console.crit
                                        }
                                        App.Tag { visible: card.modelData.kind === "action" && card.modelData.on.length > 0; text: qsTr("on ") + card.modelData.on.join(", "); tone: App.Console.dim }
                                        Ui.IconButton {
                                            visible: card.modelData.kind === "source" && card.modelData.enabled
                                            implicitWidth: 30; implicitHeight: 30
                                            icon: "play_arrow"
                                            tooltip: qsTr("Run now")
                                            onClicked: App.Store.extRun(card.modelData.id)
                                        }
                                        Ui.IconButton { implicitWidth: 30; implicitHeight: 30; icon: "edit"; tooltip: qsTr("Edit the script"); onClicked: App.Store.edit(card.modelData.path) }
                                        App.Toggle { on: card.modelData.enabled; onToggled: v => App.Store.extEnable(card.modelData.id, v) }
                                    }
                                    Rectangle { visible: card.modelData.options.length > 0; Layout.fillWidth: true; implicitHeight: 1; color: App.Console.ruleStrong }
                                    Repeater {
                                        model: card.modelData.options
                                        delegate: OptionRow { required property var modelData; ext: card.modelData; option: modelData }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    wrapMode: Text.Wrap
                    text: qsTr("Write your own: an executable file in the extensions folder, any language. Its header says what it is — # @name, # @about, # @kind source|action|view, # @every 30m, # @on done,added, # @option KEY TYPE DEFAULT \"Label\". A source prints one JSON task per line; an action gets the task on stdin. `dotos ext` lists them, `dotos ext run ID` runs a source now.")
                    font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint
                }
            }
        }
    }
}
