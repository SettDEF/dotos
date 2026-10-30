import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Tags: custom tag registry. Each tag has a name, color, icon, priority and
 * description. Usage counts come from the task list; the spinweb shows
 * co-occurrence across tasks.
 */
Item {
    id: page
    property string key: "tags"

    property var tags: []
    property bool loading: false
    property bool showCreate: false
    property string createPriVal: "normal"

    function loadTags() {
        page.loading = true;
        tagsProc.command = [App.Store.bin, "tag", "list", "--json"];
        tagsProc.running = true;
    }

    Process {
        id: tagsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.tags = JSON.parse(text) ?? []; } catch (e) { page.tags = []; }
                page.loading = false;
            }
        }
        stderr: StdioCollector { onStreamFinished: { page.loading = false; } }
    }

    Component.onCompleted: page.loadTags()

    // usage count per tag
    function usage(name) {
        return (App.Store.tasks ?? []).filter(t => (t.tags ?? t.categories ?? []).includes(name)).length;
    }

    // spinweb data: each tag is an axis, value = usage count normalized
    readonly property var spinwebData: {
        if (page.tags.length < 3) return [];
        const maxUsage = Math.max(1, ...page.tags.map(t => page.usage(t.name)));
        return page.tags.map(t => ({
            name: t.name,
            value: page.usage(t.name) / maxUsage,
            color: t.color || App.Console.data
        }));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Tags")
            subtitle: qsTr("%1 custom tags").arg(page.tags.length)
            Ui.IconButton { icon: "refresh"; tooltip: qsTr("Reload"); onClicked: page.loadTags() }
            Ui.IconButton { icon: "add"; tooltip: qsTr("New tag"); onClicked: page.showCreate = !page.showCreate }
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
                width: Math.min(parent.width - 28, 900)
                spacing: 12

                // Spinweb visualization
                App.Panel {
                    Layout.fillWidth: true
                    visible: page.spinwebData.length >= 3
                    title: qsTr("Spinweb")
                    icon: "radar"
                    note: qsTr("tag co-occurrence")
                    App.SpiderWebChart {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 260
                        tags: page.spinwebData
                        maxValue: 1.0
                    }
                }

                // Analytics panel
                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Analytics")
                    icon: "analytics"
                    note: qsTr("usage overview")
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        ColumnLayout {
                            spacing: 4
                            Text { text: qsTr("Most used"); font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.Medium; color: App.Console.dim }
                            Repeater {
                                model: page.tags.slice().sort((a, b) => page.usage(b.name) - page.usage(a.name)).slice(0, 5)
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: 6
                                    Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: modelData.color || App.Console.data }
                                    Text { text: modelData.name; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text }
                                    Text { text: qsTr("%1").arg(page.usage(modelData.name)); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                }
                            }
                        }
                        ColumnLayout {
                            spacing: 4
                            Text { text: qsTr("By priority"); font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.Medium; color: App.Console.dim }
                            Repeater {
                                model: ["critical", "high", "normal", "low"]
                                delegate: RowLayout {
                                    required property string modelData
                                    spacing: 6
                                    Text { text: modelData; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text }
                                    Text { text: qsTr("%1").arg(page.tags.filter(t => (t.priority || "normal") === modelData).length); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                }
                            }
                        }
                    }
                }

                // Create tag panel
                App.Panel {
                    Layout.fillWidth: true
                    visible: page.showCreate
                    title: qsTr("New tag")
                    icon: "add"
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            spacing: 8
                            Text { text: qsTr("Name"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim; Layout.preferredWidth: 80 }
                            TextField { id: createName; Layout.fillWidth: true; placeholderText: qsTr("tag name") }
                        }
                        RowLayout {
                            spacing: 8
                            Text { text: qsTr("Color"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim; Layout.preferredWidth: 80 }
                            TextField { id: createColor; Layout.fillWidth: true; placeholderText: qsTr("#hex color") }
                        }
                        RowLayout {
                            spacing: 8
                            Text { text: qsTr("Priority"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim; Layout.preferredWidth: 80 }
                            RowLayout {
                                spacing: 4
                                Repeater {
                                    model: ["normal", "low", "high", "critical"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        implicitWidth: 60; implicitHeight: 24; radius: 4
                                        color: createPriVal === modelData ? App.Console.data : App.Console.panel
                                        border.width: 1; border.color: App.Console.rule
                                        Text { anchors.centerIn: parent; text: modelData; font.family: App.Console.sans; font.pixelSize: 10; color: createPriVal === modelData ? "#fff" : App.Console.text }
                                        TapHandler { onTapped: createPriVal = modelData }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            spacing: 8
                            Text { text: qsTr("Description"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim; Layout.preferredWidth: 80 }
                            TextField { id: createDesc; Layout.fillWidth: true; placeholderText: qsTr("optional description") }
                        }
                        RowLayout {
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 70; implicitHeight: 28; radius: 6
                                color: cancelHov.hovered ? App.Console.panelAlt : App.Console.panel
                                border.width: 1; border.color: App.Console.rule
                                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text }
                                HoverHandler { id: cancelHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: page.showCreate = false }
                            }
                            Rectangle {
                                implicitWidth: 70; implicitHeight: 28; radius: 6
                                color: createHov.hovered ? App.Console.panelAlt : App.Console.panel
                                border.width: 1; border.color: App.Console.rule
                                Text { anchors.centerIn: parent; text: qsTr("Create"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text }
                                HoverHandler { id: createHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        Quickshell.execDetached([App.Store.bin, "tag", "add", createName.text, "--color", createColor.text || "#888888", "--pri", createPriVal, "--description", createDesc.text]);
                                        page.showCreate = false;
                                        Qt.callLater(() => page.loadTags());
                                    }
                                }
                            }
                        }
                    }
                }

                // Tag list
                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("All tags")
                    icon: "label"
                    note: page.loading ? qsTr("loading...") : qsTr("%1 tags").arg(page.tags.length)

                    Repeater {
                        model: page.tags
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 40
                            spacing: 10

                            Rectangle {
                                implicitWidth: 14; implicitHeight: 14; radius: 7
                                color: modelData.color || App.Console.data
                            }
                            Ui.Icon { text: modelData.icon || "label"; size: 16; color: App.Console.dim }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: modelData.name; font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.Medium; color: App.Console.text }
                                Text { visible: !!modelData.description; text: modelData.description || ""; font.family: App.Console.sans; font.pixelSize: 11; color: App.Console.faint; elide: Text.ElideRight }
                            }
                            App.Tag { text: modelData.priority || "normal"; tone: modelData.priority === "high" || modelData.priority === "critical" ? App.Console.warn : App.Console.dim }
                            Text { text: qsTr("%1 uses").arg(page.usage(modelData.name)); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            Ui.IconButton {
                                icon: "open_in_new"; implicitWidth: 26; implicitHeight: 26
                                tooltip: qsTr("Edit in terminal")
                                onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--", "sh", "-c", App.Store.bin + " tag edit " + modelData.name + "; read -p 'Press Enter...'"])
                            }
                        }
                    }

                    Text {
                        visible: page.tags.length === 0 && !page.loading
                        Layout.fillWidth: true
                        text: qsTr("No custom tags yet. Create one with 'dotos tag add <name> --color #hex --pri high'.")
                        font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
