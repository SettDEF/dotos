import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "." as App
import "../ui" as Ui

/**
 * Vitals' sidebar, with Dotos' sections: the name and what needs you at the
 * top, then Work · Life · Knowledge, extension pages, Settings at the bottom.
 * Every entry carries its live count. Collapses to an icon rail (Ctrl B).
 */
Rectangle {
    id: root
    readonly property bool collapsed: App.Prefs.sidebarCollapsed
    implicitWidth: root.collapsed ? 64 : 256
    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    color: App.Console.panel
    clip: true

    /// the number beside each entry, and whether it is a "look here" badge
    function count(key) {
        switch (key) {
            case "home": return { n: App.Store.overdue + App.Store.dueToday, alert: App.Store.overdue > 0 };
            case "inbox": return { n: App.Store.inbox, alert: false };
            case "projects": return { n: App.Store.projects.filter(p => p.health === "attention").length, alert: true };
            case "agents": return { n: App.Store.needsYou.length || App.Store.liveAgents.filter(a => a.state === "working").length, alert: App.Store.needsYou.length > 0 };
            case "tasks": return { n: App.Store.open.length, alert: false };
            case "habits": return { n: App.Store.habits.filter(h => !h.done_today && h.per_week >= 7).length, alert: false };
            case "pages": return { n: App.Store.pages.filter(p => p.kind === "page").length, alert: false };
            case "extensions": return { n: App.Store.extensions.filter(e => !e.last_ok).length, alert: true };
            default: return { n: 0, alert: false };
        }
    }

    component Entry: Rectangle {
        id: entry
        required property var page
        readonly property string hint: ({ home: "1", inbox: "2", projects: "3", agents: "4", tasks: "5", habits: "7", journal: "8", pages: "9", plan: "0", graph: "Ctrl G", settings: "Ctrl ," })[entry.page.key] ?? ""
        readonly property bool sel: App.Nav.page === entry.page.key || (entry.page.key === "projects" && App.Nav.page === "project")
        readonly property var c: root.count(entry.page.key)
        Layout.fillWidth: true
        implicitHeight: 34
        radius: Ui.Appearance.rounding.small
        color: entry.sel ? Qt.alpha(App.Console.data, 0.16)
            : hov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: App.Nav.go(entry.page.key) }
        Ui.Tip { visible: root.collapsed && hov.hovered; delay: 300; x: parent.width + 8; y: (parent.height - height) / 2; text: entry.c.n > 0 ? `${entry.page.label}  ·  ${entry.c.n}` : entry.page.label }

        Rectangle {
            visible: entry.sel
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 3; height: 18; radius: 1.5
            color: App.Console.data
        }
        RowLayout {
            anchors { fill: parent; leftMargin: root.collapsed ? 0 : 12; rightMargin: root.collapsed ? 0 : 10 }
            spacing: 10
            Item {
                Layout.fillWidth: root.collapsed
                implicitWidth: 18; implicitHeight: 18
                Ui.Icon {
                    anchors.centerIn: parent
                    text: entry.page.icon
                    size: 20
                    filled: entry.sel
                    color: entry.sel ? App.Console.data : App.Console.dim
                }
                Rectangle {
                    visible: root.collapsed && entry.c.alert && entry.c.n > 0
                    anchors { right: parent.right; top: parent.top; rightMargin: (parent.width - 18) / 2 - 3; topMargin: -3 }
                    width: 8; height: 8; radius: 4
                    color: App.Console.crit
                    border.width: 1.5
                    border.color: App.Console.panel
                }
            }
            Text {
                visible: !root.collapsed
                Layout.fillWidth: true
                text: entry.page.label
                font.family: App.Console.sans
                font.pixelSize: 14
                font.weight: entry.sel ? Font.DemiBold : Font.Normal
                color: entry.sel ? App.Console.text : App.Console.dim
                elide: Text.ElideRight
            }
            Rectangle {
                visible: !root.collapsed && entry.c.n > 0 && entry.c.alert
                implicitWidth: Math.max(20, badgeText.implicitWidth + 10)
                implicitHeight: 18
                radius: 9
                color: App.Console.crit
                Text { id: badgeText; anchors.centerIn: parent; text: entry.c.n; font.family: App.Console.mono; font.pixelSize: 11; font.weight: Font.DemiBold; color: App.Console.bg }
            }
            Text {
                visible: !root.collapsed && entry.c.n > 0 && !entry.c.alert && !hov.hovered
                text: entry.c.n
                font.family: App.Console.mono
                font.pixelSize: 12
                color: App.Console.faint
            }
            Text {
                visible: !root.collapsed && hov.hovered && entry.hint.length > 0
                text: entry.hint
                font.family: App.Console.mono
                font.pixelSize: 11
                color: App.Console.faint
            }
        }
    }

    // sections fold (as Notion's): which ones are folded, for this session
    property var folded: ({})
    function fold(key) { const f = Object.assign({}, root.folded); f[key] = !f[key]; root.folded = f; }

    // an icon tile in a row (the top and bottom rows): icon, a count badge, a tip
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string tip: ""
        property int n: 0
        property bool alert: false
        property bool sel: false
        signal hit()
        Layout.fillWidth: true
        implicitHeight: 38
        radius: Ui.Appearance.rounding.small
        color: tile.sel ? Qt.alpha(App.Console.data, 0.16) : tHov.hovered ? Qt.alpha(App.Console.text, 0.07) : Qt.alpha(App.Console.text, 0.03)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tile.hit() }
        Ui.Tip { visible: tHov.hovered; delay: 300; y: parent.height + 6; text: tile.n > 0 ? `${tile.tip}  ·  ${tile.n}` : tile.tip }
        Ui.Icon { anchors.centerIn: parent; text: tile.icon; size: 20; filled: tile.sel; color: tile.sel ? App.Console.data : App.Console.dim }
        Rectangle {
            visible: tile.n > 0
            anchors { right: parent.right; top: parent.top; margins: 4 }
            implicitWidth: Math.max(16, tn.implicitWidth + 8); implicitHeight: 16; radius: 8
            color: tile.alert ? App.Console.crit : Qt.alpha(App.Console.text, 0.12)
            Text { id: tn; anchors.centerIn: parent; text: tile.n; font.family: App.Console.mono; font.pixelSize: 10; font.weight: Font.DemiBold; color: tile.alert ? App.Console.bg : App.Console.dim }
        }
    }

    // a slim row under a section (a page, a project): an icon or a coloured dot, the name
    component Leaf: Rectangle {
        id: leaf
        property string icon: ""
        property color dot: "transparent"
        property string label: ""
        property string note: ""
        property bool sel: false
        signal hit()
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Ui.Appearance.rounding.small
        color: leaf.sel ? Qt.alpha(App.Console.data, 0.16) : lHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
        HoverHandler { id: lHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: leaf.hit() }
        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
            spacing: 9
            Item {
                implicitWidth: 16; implicitHeight: 16
                Ui.Icon { anchors.centerIn: parent; visible: leaf.icon.length > 0; text: leaf.icon; size: 16; color: leaf.sel ? App.Console.data : App.Console.faint }
                Rectangle { anchors.centerIn: parent; visible: leaf.icon.length === 0; width: 8; height: 8; radius: 4; color: leaf.dot }
            }
            Text { Layout.fillWidth: true; text: leaf.label; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: leaf.sel ? App.Console.text : App.Console.dim }
            Text { visible: leaf.note.length > 0; text: leaf.note; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
        }
    }

    // a cell of the footer: an icon, its count as a small badge, a tip above it
    component FootCell: Rectangle {
        id: fc
        required property var page
        readonly property var c: root.count(fc.page.key)
        readonly property bool sel: App.Nav.page === fc.page.key
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: fc.sel ? Qt.alpha(App.Console.data, 0.16) : fHov.hovered ? Qt.alpha(App.Console.text, 0.07) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: fHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: App.Nav.go(fc.page.key) }
        Ui.Tip { visible: fHov.hovered; delay: 300; y: -height - 6; text: fc.c.n > 0 ? `${fc.page.label}  ·  ${fc.c.n}` : fc.page.label }
        Ui.Icon {
            anchors.centerIn: parent
            text: fc.page.icon
            size: 17
            filled: fc.sel
            color: fc.sel ? App.Console.data : App.Console.dim
        }
        Rectangle {
            visible: fc.c.n > 0
            anchors { horizontalCenter: parent.horizontalCenter; horizontalCenterOffset: 8; verticalCenter: parent.verticalCenter; verticalCenterOffset: -6 }
            implicitWidth: Math.max(14, fcn.implicitWidth + 6); implicitHeight: 14; radius: 7
            color: fc.c.alert ? App.Console.crit : Qt.alpha(App.Console.text, 0.14)
            Text { id: fcn; anchors.centerIn: parent; text: fc.c.n; font.family: App.Console.mono; font.pixelSize: 9; font.weight: Font.DemiBold; color: fc.c.alert ? App.Console.bg : App.Console.dim }
        }
    }

    component Group: Item {
        id: grp
        property string label: ""
        /// the section's key for folding ("" cannot fold)
        property string key: ""
        /// a + on hover: makes a new one of what the section holds
        property var add: null
        readonly property bool shut: grp.key.length > 0 && !!root.folded[grp.key]
        Layout.fillWidth: true
        implicitHeight: root.collapsed ? 17 : 33
        HoverHandler { id: gHov; enabled: !root.collapsed && grp.key.length > 0; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !root.collapsed && grp.key.length > 0; onTapped: root.fold(grp.key) }
        RowLayout {
            visible: !root.collapsed
            anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 6; bottom: parent.bottom; bottomMargin: 2 }
            spacing: 2
            Ui.Icon {
                visible: grp.key.length > 0
                opacity: gHov.hovered || grp.shut ? 1 : 0
                text: grp.shut ? "chevron_right" : "expand_more"
                size: 14
                color: App.Console.faint
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            App.Label { Layout.fillWidth: true; text: grp.label; font.pixelSize: 12; color: gHov.hovered ? App.Console.dim : App.Console.faint }
            Ui.IconButton {
                visible: !!grp.add && gHov.hovered
                implicitWidth: 22; implicitHeight: 22
                icon: "add"
                tooltip: qsTr("New")
                onClicked: grp.add()
            }
        }
        Rectangle {
            visible: root.collapsed
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
            height: 1
            color: App.Console.rule
        }
    }

    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; margins: 10; topMargin: 14 }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.collapsed ? 0 : 6
            Layout.bottomMargin: 12
            spacing: 10
            Rectangle {
                Layout.alignment: root.collapsed ? Qt.AlignHCenter : Qt.AlignLeft
                // narrow, in the middle of the rail (the row's other parts are hidden then)
                Layout.leftMargin: root.collapsed ? Math.max(0, (root.implicitWidth - 20 - 34) / 2) : 0
                implicitWidth: 34; implicitHeight: 34; radius: 10
                readonly property color tone: App.Store.needsYou.length > 0 || App.Store.overdue > 0 ? App.Console.crit : App.Console.data
                // the app's own icon; narrow, a hover turns it into "expand"; a dot says when something needs you
                color: logoHov.hovered && root.collapsed ? Qt.alpha(App.Console.data, 0.2) : "transparent"
                Image { anchors.fill: parent; visible: !(root.collapsed && logoHov.hovered); source: Quickshell.iconPath("dotos", true); sourceSize: Qt.size(68, 68); smooth: true }
                Ui.Icon { anchors.fill: parent; visible: root.collapsed && logoHov.hovered; text: "left_panel_open"; size: 20; color: App.Console.data }
                Rectangle {
                    visible: parent.tone !== App.Console.data
                    anchors { right: parent.right; top: parent.top; margins: -1 }
                    width: 9; height: 9; radius: 4.5
                    color: parent.tone; border.width: 2; border.color: App.Console.bg
                }
                HoverHandler { id: logoHov; cursorShape: root.collapsed ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: root.collapsed; onTapped: App.Prefs.sidebarCollapsed = false }
                Ui.Tip { visible: root.collapsed && logoHov.hovered; x: parent.width + 8; y: (parent.height - height) / 2; text: qsTr("Expand sidebar  (Ctrl B)") }
            }
            ColumnLayout {
                visible: !root.collapsed
                Layout.fillWidth: true
                spacing: 0
                Text { text: "Dotos"; font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
                Text {
                    Layout.fillWidth: true
                    text: !App.Store.loaded ? qsTr("loading…")
                        : App.Store.needsYou.length > 0 ? qsTr("%n agent(s) need you", "", App.Store.needsYou.length)
                        : App.Store.overdue > 0 ? qsTr("%n overdue", "", App.Store.overdue)
                        : App.Store.dueToday > 0 ? qsTr("%n due today", "", App.Store.dueToday) : qsTr("all clear")
                    font.family: App.Console.sans
                    font.pixelSize: 12
                    color: App.Store.needsYou.length > 0 || App.Store.overdue > 0 ? App.Console.crit : App.Console.dim
                    elide: Text.ElideRight
                }
            }
            Ui.IconButton {
                visible: !root.collapsed
                implicitWidth: 28; implicitHeight: 28
                icon: "left_panel_close"
                tooltip: qsTr("Collapse sidebar  (Ctrl B)")
                onClicked: App.Prefs.sidebarCollapsed = true
            }
        }

        // the one main action, as in the sketch
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            implicitHeight: 40
            radius: Ui.Appearance.rounding.small
            color: newHov.hovered ? Qt.lighter(App.Console.data, 1.08) : App.Console.data
            HoverHandler { id: newHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: App.Nav.run("capture") }
            Ui.Tip { visible: root.collapsed && newHov.hovered; x: parent.width + 8; y: (parent.height - height) / 2; text: qsTr("New  (Ctrl N)") }
            RowLayout {
                anchors { fill: parent; leftMargin: root.collapsed ? 0 : 14; rightMargin: root.collapsed ? 0 : 12 }
                spacing: 8
                Ui.Icon { Layout.fillWidth: root.collapsed; text: "add"; size: 20; color: App.Console.onData }
                Text { visible: !root.collapsed; Layout.fillWidth: true; text: qsTr("New"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.onData }
                Text { visible: !root.collapsed; text: "Ctrl N"; font.family: App.Console.mono; font.pixelSize: 11; color: Qt.alpha(App.Console.onData, 0.7) }
            }
        }

        // the top entries side by side (Home, Inbox) with search: a row of tiles; narrow, the plain list
        RowLayout {
            visible: !root.collapsed
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 6
            Repeater {
                model: App.Nav.pages.filter(p => p.group === "")
                Tile {
                    required property var modelData
                    readonly property var c: root.count(modelData.key)
                    icon: modelData.icon; tip: modelData.label; n: c.n; alert: c.alert
                    sel: App.Nav.page === modelData.key
                    onHit: App.Nav.go(modelData.key)
                }
            }
            Tile { icon: "search"; tip: qsTr("Search  (Ctrl K)"); onHit: App.Nav.run("palette") }
            Tile { icon: "history"; tip: qsTr("History"); sel: App.Nav.page === "history"; onHit: App.Nav.go("history") }
        }
        Repeater { model: root.collapsed ? App.Nav.pages.filter(p => p.group === "") : []; Entry { required property var modelData; page: modelData } }

        // the sections scroll when they are more than the window holds
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: secs.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
            ColumnLayout {
                id: secs
                width: parent.width
                spacing: 2

                Group { label: qsTr("Work"); key: "work" }
                Repeater { model: root.folded.work ? [] : App.Nav.pages.filter(p => p.group === "work"); Entry { required property var modelData; page: modelData } }
                Group { label: qsTr("Life"); key: "life" }
                Repeater { model: root.folded.life ? [] : App.Nav.pages.filter(p => p.group === "life"); Entry { required property var modelData; page: modelData } }
                Group { label: qsTr("Knowledge"); key: "know" }
                Repeater { model: root.folded.know ? [] : App.Nav.pages.filter(p => p.group === "know"); Entry { required property var modelData; page: modelData } }

                // the pages themselves, as Notion lists them under the workspace
                Group {
                    visible: !root.collapsed && App.Store.pages.some(p => p.kind === "page")
                    label: qsTr("Pages"); key: "pagelist"
                    add: () => App.Nav.go("pages")
                }
                Repeater {
                    model: root.collapsed || root.folded.pagelist ? [] : App.Store.pages.filter(p => p.kind === "page").slice(0, 8)
                    Leaf {
                        required property var modelData
                        icon: "description"
                        label: modelData.title || modelData.id
                        sel: App.Nav.page === "pages" && App.Nav.pageId === modelData.id
                        onHit: App.Nav.openPage(modelData.id)
                    }
                }

                // the projects moving now (or needing you), each with its health colour
                Group {
                    visible: !root.collapsed && root.liveProjects.length > 0
                    label: qsTr("Active projects"); key: "projlist"
                }
                Repeater {
                    model: root.collapsed || root.folded.projlist ? [] : root.liveProjects
                    Leaf {
                        required property var modelData
                        dot: App.Store.healthColor(modelData.health)
                        label: modelData.name
                        note: modelData.git && modelData.git.dirty > 0 ? String(modelData.git.dirty) : ""
                        sel: App.Nav.page === "project" && App.Nav.project === modelData.name
                        onHit: App.Nav.openProject(modelData.name)
                    }
                }

                Item { implicitHeight: 10 }
                Repeater { model: App.Nav.pages.filter(p => p.group === "end" || p.group === "more" && root.count(p.key).alert && root.count(p.key).n > 0); Entry { required property var modelData; page: modelData } }
            }
        }

    }

    // the footer: the same 26 px band as the status bar under the page, on the
    // same line, so the two read as one footer across the window
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 26
        color: App.Console.panel
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: App.Console.rule }
        RowLayout {
            anchors { fill: parent; topMargin: 1 }
            spacing: 0
            Repeater {
                model: App.Nav.pages.filter(p => p.group === "foot" || p.key === "extensions")
                FootCell { required property var modelData; page: modelData }
            }
        }
    }

    /// the projects worth a line: needing you first, then the ones moving this week (at most 6)
    readonly property var liveProjects: App.Store.projects
        .filter(p => p.health === "attention" || p.health === "stale" || p.health === "active")
        .sort((a, b) => ({ attention: 0, stale: 1, active: 2 })[a.health] - ({ attention: 0, stale: 1, active: 2 })[b.health])
        .slice(0, 6)

    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: App.Console.rule }
}
