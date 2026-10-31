import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "." as App
import "../ui" as Ui

/**
 * The sidebar of the area the rail is on, as Linear's: the area's name and its "new", a search
 * row (Ctrl K), the area's pages with their counts, then what the area holds (lists, repositories,
 * conversations, recent pages). Only this area, so it never grows into one long list.
 * Ctrl B hides it; the rail stays.
 */
Rectangle {
    id: root
    readonly property bool collapsed: App.Prefs.sidebarCollapsed
    readonly property var area: App.Nav.areas.find(a => a.key === App.Nav.area) ?? null
    implicitWidth: root.collapsed ? 0 : 240
    visible: implicitWidth > 0
    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    color: App.Console.panel
    clip: true

    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: App.Console.rule }

    /// [count, alert] beside a page
    function count(key) {
        switch (key) {
            case "home": return [App.Store.overdue + App.Store.dueToday, App.Store.overdue > 0];
            case "inbox": return [App.Store.inbox, false];
            case "projects": return [App.Store.projects.filter(p => p.health === "attention").length, true];
            case "agents": return [App.Store.needsYou.length || App.Store.liveAgents.filter(a => a.state === "working").length, App.Store.needsYou.length > 0];
            case "tasks": return [App.Store.open.length, false];
            case "habits": return [App.Store.habits.filter(h => !h.done_today && h.per_week >= 7).length, false];
            case "pages": return [App.Store.pages.filter(p => p.kind === "page").length, false];
            case "team": return [App.Team.unreadTotal, App.Team.unreadTotal > 0];
            default: return [0, false];
        }
    }

    /// what "+" makes in this area
    readonly property var make: ({
        activity: { tip: qsTr("New task  (Ctrl N)"), run: () => App.Nav.action("capture") },
        work: { tip: qsTr("New task  (Ctrl N)"), run: () => App.Nav.action("capture") },
        notes: { tip: qsTr("New page"), run: () => App.Nav.sheet = "page" },
        code: { tip: qsTr("Take on a project"), run: () => App.Nav.go("projects") }
    })

    /// one row, as Linear's: icon, name, a count right-aligned and quiet (red when it needs you)
    component SideRow: Rectangle {
        id: row
        property string icon: ""
        property color iconColor: App.Console.dim
        property string text: ""
        property int count: 0
        property bool alert: false
        property bool selected: false
        property string trailing: ""
        signal clicked
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 6
        color: row.selected ? Qt.alpha(App.Console.data, 0.14) : rHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 9
            Ui.Icon { text: row.icon; size: 17; filled: row.selected; color: row.selected ? App.Console.data : row.iconColor }
            Text { Layout.fillWidth: true; text: row.text; color: row.selected ? App.Console.text : Qt.alpha(App.Console.text, 0.88); font.pixelSize: 13; font.weight: row.selected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
            Text { visible: row.trailing.length > 0; text: row.trailing; color: App.Console.faint; font.pixelSize: 11 }
            Rectangle {
                visible: row.count > 0
                implicitWidth: Math.max(18, nText.implicitWidth + 10); implicitHeight: 18; radius: 9
                color: row.alert ? App.Console.crit : "transparent"
                Text { id: nText; anchors.centerIn: parent; text: row.count; color: row.alert ? "white" : App.Console.faint; font.pixelSize: 11; font.weight: row.alert ? Font.Bold : Font.Normal }
            }
        }
        HoverHandler { id: rHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: row.clicked() }
    }

    component Section: Text {
        Layout.fillWidth: true
        Layout.topMargin: 14
        Layout.leftMargin: 8
        Layout.bottomMargin: 2
        color: App.Console.faint
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.4
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        width: 240

        // the area: its name, and its "new"
        Item {
            Layout.fillWidth: true
            implicitHeight: 56
            Text {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                text: root.area?.label ?? (App.Nav.page === "settings" ? qsTr("Settings") : qsTr("Extensions"))
                color: App.Console.text; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            SideRow {
                visible: !!root.make[App.Nav.area]
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                width: 30; implicitHeight: 30
                icon: "edit_square"
                onClicked: root.make[App.Nav.area].run()
            }
        }

        // search, as Linear's first row: the command palette
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 10; Layout.rightMargin: 10
            implicitHeight: 32
            radius: 7
            color: sHov.hovered ? App.Console.panelAlt : Qt.alpha(App.Console.text, 0.04)
            border.width: 1; border.color: App.Console.rule
            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                spacing: 8
                Ui.Icon { text: "search"; size: 16; color: App.Console.faint }
                Text { Layout.fillWidth: true; text: qsTr("Search"); color: App.Console.faint; font.pixelSize: 13 }
                Text { text: "Ctrl K"; color: App.Console.faint; font.pixelSize: 11; font.family: App.Console.mono }
            }
            HoverHandler { id: sHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: App.Nav.action("palette") }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            clip: true
            contentHeight: col.implicitHeight + 16
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: col
                x: 10; width: 220
                spacing: 1

                // the area's pages
                Repeater {
                    model: (root.area?.pages ?? []).map(k => App.Nav.pages.find(p => p.key === k)).filter(p => !!p)
                    delegate: SideRow {
                        required property var modelData
                        readonly property var c: root.count(modelData.key)
                        icon: modelData.icon
                        text: modelData.label
                        count: c[0]
                        alert: c[1]
                        selected: App.Nav.page === modelData.key || (modelData.key === "projects" && App.Nav.page === "project") || (modelData.key === "tasks" && App.Nav.page === "board")
                        onClicked: App.Nav.go(modelData.key)
                    }
                }

                // ── Work: the lists, and the extensions' pages ──
                Section { visible: App.Nav.area === "work" && App.Store.lists.length > 0; text: qsTr("LISTS") }
                Repeater {
                    model: App.Nav.area === "work" ? App.Store.lists : []
                    delegate: SideRow {
                        required property var modelData
                        icon: "list"
                        text: modelData.name
                        count: modelData.open
                        onClicked: App.Nav.go("tasks")
                    }
                }
                Section { visible: App.Nav.area === "work" && App.Nav.pages.some(p => p.group === "ext"); text: qsTr("EXTENSIONS") }
                Repeater {
                    model: App.Nav.area === "work" ? App.Nav.pages.filter(p => p.group === "ext") : []
                    delegate: SideRow {
                        required property var modelData
                        icon: modelData.icon
                        text: modelData.label
                        selected: App.Nav.page === modelData.key
                        onClicked: App.Nav.go(modelData.key)
                    }
                }

                // ── Code: the repositories you track, pinned first, then by last change ──
                Section { visible: App.Nav.area === "code" && App.Store.projects.length > 0; text: qsTr("REPOSITORIES") }
                Repeater {
                    model: App.Nav.area === "code"
                        ? App.Store.projects.slice().sort((a, b) => ((b.options?.pin === "on") - (a.options?.pin === "on")) || ((b.git?.last_time ?? 0) - (a.git?.last_time ?? 0))).slice(0, 12)
                        : []
                    delegate: SideRow {
                        required property var modelData
                        icon: modelData.options?.pin === "on" ? "push_pin" : "folder"
                        iconColor: modelData.health === "attention" ? App.Console.crit : modelData.health === "active" ? App.Console.ok : App.Console.dim
                        text: modelData.name
                        trailing: (modelData.git?.dirty ?? 0) > 0 ? "●" : ""
                        selected: App.Nav.page === "project" && App.Nav.project === modelData.name
                        onClicked: App.Nav.openProject(modelData.name)
                    }
                }

                // ── Chat: the conversations, as Slack's channels ──
                Section { visible: App.Nav.area === "chat" && App.Team.items.length > 0; text: qsTr("CONVERSATIONS") }
                Repeater {
                    model: App.Nav.area === "chat" ? App.Team.items.slice(0, 14) : []
                    delegate: SideRow {
                        required property var modelData
                        icon: modelData.kind === "task" ? "task_alt" : modelData.kind === "project" ? "deployed_code" : "tag"
                        text: modelData.title
                        count: modelData.unread
                        alert: modelData.mentions > 0
                        selected: App.Nav.page === "team" && App.Nav.chat === modelData.item
                        onClicked: { App.Nav.chat = modelData.item; App.Nav.go("team"); }
                    }
                }
                Section { visible: App.Nav.area === "chat" && App.Team.people.length > 0; text: qsTr("PEOPLE") }
                Repeater {
                    model: App.Nav.area === "chat" ? App.Team.people : []
                    delegate: SideRow {
                        required property var modelData
                        icon: "person"
                        text: (modelData.name || modelData.handle) + (modelData.handle === App.Team.me ? qsTr("  (you)") : "")
                        trailing: "@" + modelData.handle
                        onClicked: App.Nav.go("team")
                    }
                }

                // ── Notes: the pages changed last ──
                Section { visible: App.Nav.area === "notes" && App.Store.pages.length > 0; text: qsTr("RECENT") }
                Repeater {
                    model: App.Nav.area === "notes" ? App.Store.pages.filter(p => p.kind === "page").slice().sort((a, b) => (b.modified ?? 0) - (a.modified ?? 0)).slice(0, 10) : []
                    delegate: SideRow {
                        required property var modelData
                        icon: "description"
                        text: modelData.title || modelData.id
                        selected: App.Nav.page === "pages" && App.Nav.pageId === modelData.id
                        onClicked: App.Nav.openPage(modelData.id)
                    }
                }
            }
        }
    }
}
