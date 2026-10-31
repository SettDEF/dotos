import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * Projects: every folder you work in, sorted by what it needs from you.
 * Found, not declared: anything under the project roots with a .git, a
 * TASKS.md, a PLAN.md or a README.
 *
 * Three sections: needs attention (a waiting agent, overdue tasks, changes
 * left for days), active this week (cards with a 14-day commit sparkline),
 * and the quiet rest as compact rows — 43 equal cards made the five that
 * matter as loud as the thirty that do not. The header counts filter.
 * Hover a project for terminal, Neovim, folder and a new task.
 */
Item {
    id: page
    property string key: "projects"
    property string filter: ""
    property string show: ""                // "" | attention | active | dirty | quiet
    property var selectedProject: null

    function dirty(p) { return (p.git?.dirty ?? 0) > 0; }
    function active(p) { return (p.git?.commits_week ?? 0) > 0 || (p.time_week_s ?? 0) > 0 || (p.agents ?? 0) > 0; }
    function needs(p) { return p.health === "attention" || p.health === "stale"; }
    /// the dot says which section it is in: needs you, active, quiet
    function tone(p) { return page.needs(p) ? App.Store.healthColor(p.health) : page.active(p) ? App.Console.ok : App.Console.faint; }
    function last(p) { return p.git?.last_time ?? p.modified ?? 0; }
    function hasRemote(p) { return (p.git?.remote_url ?? "").length > 0; }

    readonly property var all: {
        const q = page.filter.toLowerCase();
        const l = App.Store.projects.filter(p => !q || (p.name + " " + (p.git?.last_subject ?? "")).toLowerCase().includes(q));
        if (App.Prefs.projectsSort === "name") return l.sort((a, b) => a.name.localeCompare(b.name));
        return l.sort((a, b) => page.last(b) - page.last(a));
    }
    // ── keys: j/k through the projects as shown, Enter opens, e zett in it, h/l the filter, / search ──
    property string cur: ""
    readonly property var order: page.shown ?? page.attention.concat(page.activeOnes, page.quiet)
    /// the item at the keyboard's place in view (the page scrolls to it)
    function reveal(item) {
        const y = item.mapToItem(body, 0, 0).y;
        if (y < flick.contentY) flick.contentY = Math.max(0, y - 12);
        else if (y + item.height > flick.contentY + flick.height) flick.contentY = y + item.height - flick.height + 12;
    }
    readonly property var keyHelp: [[qsTr("Move"), ["j", "k"]], [qsTr("Open the project"), ["Enter"]], [qsTr("zett in it"), ["e"]], [qsTr("Filter"), ["h", "l"]], [qsTr("Search"), ["/"]]]
    function handleKey(e) {
        const i = page.order.findIndex(p => p.name === page.cur);
        const m = K.move(e, page.order.length, i);
        if (m >= 0) { page.cur = page.order[m].name; return true; }
        if (K.isOpen(e) && i >= 0) { App.Nav.openProject(page.cur); return true; }
        if (!K.plain(e)) return false;
        if (e.key === Qt.Key_E && i >= 0) { Quickshell.execDetached([App.Store.zash, "-d", page.order[i].path, "-e", App.Store.zett + " ."]); return true; }
        const d = K.side(e);
        if (d) { const ks = ["all", "attention", "active", "dirty", "quiet", "remote", "local"]; const k = K.cycle(ks, page.show || "all", d); page.show = k === "all" ? "" : k; return true; }
        if (e.key === Qt.Key_Slash) { searchField.forceActiveFocus(); return true; }
        return false;
    }
    readonly property var attention: page.all.filter(p => page.needs(p))
    readonly property var activeOnes: page.all.filter(p => !page.needs(p) && page.active(p))
    readonly property var quiet: page.all.filter(p => !page.needs(p) && !page.active(p))
    readonly property var shown: page.show === "attention" ? page.attention
        : page.show === "active" ? page.all.filter(p => page.active(p))
        : page.show === "dirty" ? page.all.filter(p => page.dirty(p))
        : page.show === "remote" ? page.all.filter(p => page.hasRemote(p))
        : page.show === "local" ? page.all.filter(p => !page.hasRemote(p))
        : page.show === "quiet" ? page.quiet : null

    function plural(n, one, many) { return n === 1 ? one.arg(n) : many.arg(n); }
    function days(n) { return n === 0 ? qsTr("today") : page.plural(n, qsTr("%1 day"), qsTr("%1 days")); }

    // ── pieces ─────────────────────────────────────────────────────────
    /// 14 days of commits, oldest left, today right
    component Spark: Row {
        id: spark
        property var days: []
        spacing: 2
        readonly property int peak: Math.max(1, ...spark.days)
        Repeater {
            model: spark.days
            delegate: Item {
                required property int modelData
                required property int index
                width: 5; height: 22
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: modelData > 0 ? Math.max(3, parent.height * modelData / spark.peak) : 2
                    radius: 1.5
                    color: modelData > 0 ? (index >= 7 ? App.Console.ok : Qt.alpha(App.Console.ok, 0.55)) : Qt.alpha(App.Console.text, 0.1)
                }
            }
        }
    }
    /// what a project needs, said plainly
    component Chips: Flow {
        id: chips
        property var p: null
        spacing: 5
        App.Tag { visible: (chips.p?.agents_need_you ?? 0) > 0; text: qsTr("an agent waits for you"); tone: App.Console.crit; filled: true }
        App.Tag { visible: (chips.p?.agents ?? 0) > 0 && !chips.p?.agents_need_you; text: page.plural(chips.p?.agents ?? 0, qsTr("%1 agent working"), qsTr("%1 agents working")); tone: App.Console.data; filled: true }
        App.Tag { visible: (chips.p?.overdue ?? 0) > 0; text: qsTr("%1 overdue").arg(chips.p?.overdue); tone: App.Console.crit }
        App.Tag { visible: (chips.p?.open ?? 0) > 0; text: page.plural(chips.p?.open ?? 0, qsTr("%1 open task"), qsTr("%1 open tasks")); tone: App.Console.dim }
        App.Tag { visible: (chips.p?.doc_open ?? 0) > 0; text: qsTr("%1 in TASKS.md").arg(chips.p?.doc_open); tone: App.Console.dim }
        App.Tag {
            visible: page.dirty(chips.p ?? {})
            text: page.plural(chips.p?.git?.dirty ?? 0, qsTr("%1 change"), qsTr("%1 changes")) + " · " + qsTr("oldest %1").arg(page.days(chips.p?.git?.dirty_days ?? 0))
            tone: (chips.p?.git?.dirty_days ?? 0) >= 3 ? App.Console.warn : App.Console.dim
        }
        App.Tag { visible: (chips.p?.git?.ahead ?? 0) > 0; text: qsTr("%1 to push").arg(chips.p?.git?.ahead); tone: (chips.p?.git?.ahead ?? 0) >= 10 ? App.Console.warn : App.Console.dim }
        App.Tag { visible: (chips.p?.git?.behind ?? 0) > 0; text: qsTr("%1 behind").arg(chips.p?.git?.behind); tone: App.Console.warn }
        App.Tag { visible: (chips.p?.time_week_s ?? 0) > 0; text: App.Store.dur(chips.p?.time_week_s ?? 0) + " " + qsTr("this week"); tone: App.Console.data }
    }
    /// terminal · Neovim · folder · new task, shown on hover
    component Actions: Row {
        id: acts
        property var p: null
        spacing: 2
        Repeater {
            model: [
                { icon: "terminal", tip: qsTr("Terminal here"), run: () => App.Store.terminalAt(acts.p.path) },
                { icon: "code", tip: qsTr("zett here"), run: () => Quickshell.execDetached([App.Store.zash, "-d", acts.p.path, "-e", App.Store.zett + " ."]) },
                { icon: "folder_open", tip: qsTr("Open the folder"), run: () => App.Store.openFolder(acts.p.path) },
                { icon: "add_task", tip: qsTr("New task in this project"), run: () => { App.Nav.openProject(acts.p.name); Qt.callLater(() => App.Nav.action("capture")); } },
                { icon: "tune", tip: qsTr("What Dotos does with it"), run: () => settings.show(acts.p) }
            ]
            delegate: Rectangle {
                required property var modelData
                width: 30; height: 30; radius: 15
                color: aHov.hovered ? App.Console.panelAlt : "transparent"
                Ui.Icon { anchors.centerIn: parent; text: modelData.icon; size: 17; color: aHov.hovered ? App.Console.text : App.Console.dim }
                HoverHandler { id: aHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: modelData.run() }
                Ui.Tip { visible: aHov.hovered; delay: 300; text: modelData.tip }
            }
        }
    }
    component Card: Rectangle {
        id: card
        property var p: null
        Layout.fillWidth: true
        Layout.fillHeight: true             // a row of cards shares one height
        Layout.alignment: Qt.AlignTop
        implicitHeight: cardCol.implicitHeight + 28
        radius: App.Console.radius
        color: cardHov.hovered || isCur ? App.Console.panelAlt : App.Console.panel
        // the keyboard's one (j/k): outlined and scrolled into view
        readonly property bool isCur: !!card.p && page.cur === card.p.name
        onIsCurChanged: if (isCur) page.reveal(card)
        border.width: isCur ? 2 : card.p?.health === "attention" ? 1 : 0
        border.color: isCur ? App.Console.data : Qt.alpha(App.Console.crit, 0.5)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: cardHov }
        TapHandler { onTapped: App.Nav.openProject(card.p.name) }
        ColumnLayout {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                // one height with or without the hover buttons (they are taller than the branch: the card grew)
                Layout.preferredHeight: 30
                spacing: 8
                Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 4.5; color: card.p ? page.tone(card.p) : App.Console.faint }
                Text { Layout.fillWidth: true; text: card.p?.name ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 16; font.weight: Font.DemiBold; color: App.Console.text }
                Actions { p: card.p; visible: cardHov.hovered }
                Text { visible: !cardHov.hovered && !!card.p?.git; text: card.p?.git?.branch ?? ""; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: card.p?.git?.last_subject ?? card.p?.path ?? ""
                        elide: Text.ElideRight
                        font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
                    }
                    Text {
                        text: card.p?.git?.last_time ? `${card.p.git.last_hash} · ${App.Store.ago(card.p.git.last_time)}` : qsTr("not a git repository")
                        font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                    }
                }
                ColumnLayout {
                    visible: !!card.p?.git
                    spacing: 2
                    Spark { Layout.alignment: Qt.AlignRight; days: card.p?.git?.days14 ?? [] }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: page.plural(card.p?.git?.commits_week ?? 0, qsTr("%1 commit this week"), qsTr("%1 commits this week"))
                        font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint
                    }
                }
            }
            Chips { Layout.fillWidth: true; p: card.p }
        }
    }
    component Row1: Rectangle {
        id: row
        property var p: null
        Layout.fillWidth: true
        implicitHeight: 40
        radius: App.Console.radiusSmall
        readonly property bool isCur: !!row.p && page.cur === row.p.name
        onIsCurChanged: if (isCur) page.reveal(row)
        color: rowHov.hovered || isCur ? App.Console.panelAlt : "transparent"
        border.width: isCur ? 1 : 0
        border.color: App.Console.data
        HoverHandler { id: rowHov }
        TapHandler { onTapped: App.Nav.openProject(row.p.name) }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
            spacing: 12
            Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 3.5; color: row.p ? page.tone(row.p) : App.Console.faint }
            Text { Layout.preferredWidth: 200; text: row.p?.name ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
            Text { Layout.fillWidth: true; text: row.p?.git?.last_subject ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint }
            App.Tag { visible: page.dirty(row.p ?? {}); text: page.plural(row.p?.git?.dirty ?? 0, qsTr("%1 change"), qsTr("%1 changes")); tone: (row.p?.git?.dirty_days ?? 0) >= 3 ? App.Console.warn : App.Console.dim }
            Actions { p: row.p; visible: rowHov.hovered }
            Text {
                visible: !rowHov.hovered
                Layout.preferredWidth: 90
                horizontalAlignment: Text.AlignRight
                text: row.p?.git?.last_time ? App.Store.ago(row.p.git.last_time) : App.Store.ago(row.p?.modified ?? 0)
                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
            }
        }
    }
    component Heading: RowLayout {
        property string text: ""
        property int count: 0
        property color tone: App.Console.dim
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 8
        Text { text: parent.text; font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.DemiBold; color: parent.tone }
        Text { text: parent.count; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: App.Console.rule }
    }
    /// a grid of cards that reflows by width
    component Cards: GridLayout {
        property var items: []
        Layout.fillWidth: true
        // empty: no height at all (a grid whose cards all left kept their height: a big gap over "Active")
        Layout.preferredHeight: items.length > 0 ? -1 : 0
        columns: Math.max(1, Math.floor(width / 340))
        columnSpacing: 12; rowSpacing: 12
        Repeater { model: parent.items; delegate: Card { required property var modelData; p: modelData } }
    }

    // ── the page ───────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Projects")
            subtitle: qsTr("%1 projects").arg(App.Store.projects.length)
            Ui.SegmentedControl {
                implicitWidth: 170
                model: [{ key: "recent", label: qsTr("Recent") }, { key: "name", label: qsTr("Name") }]
                current: App.Prefs.projectsSort === "name" ? "name" : "recent"
                onPicked: k => App.Prefs.projectsSort = k
            }
            Rectangle {
                implicitWidth: 220; implicitHeight: 36; radius: 18
                color: App.Console.panelAlt
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    Ui.Icon { text: "search"; size: 17; color: App.Console.faint }
                    TextField {
                        ContextMenu.menu: Ui.TextMenu { target: searchField }
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Find a project or commit")
                        placeholderTextColor: App.Console.faint
                        background: null
                        color: App.Console.text
                        font.family: App.Console.sans; font.pixelSize: 14
                        onTextChanged: page.filter = text
                    }
                }
            }
            Ui.IconButton { icon: "refresh"; tooltip: qsTr("Read git again"); onClicked: App.Store.reload(true) }
        }

        // the counts, as filters
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 20; Layout.rightMargin: 20; Layout.topMargin: 12
            spacing: 6
            Repeater {
                model: [
                    { key: "", label: qsTr("All"), n: page.all.length, tone: App.Console.dim },
                    { key: "attention", label: qsTr("Need you"), n: page.attention.length, tone: App.Console.crit },
                    { key: "active", label: qsTr("Active this week"), n: page.all.filter(p => page.active(p)).length, tone: App.Console.ok },
                    { key: "dirty", label: qsTr("Uncommitted"), n: page.all.filter(p => page.dirty(p)).length, tone: App.Console.warn },
                    { key: "quiet", label: qsTr("Quiet"), n: page.quiet.length, tone: App.Console.faint },
                    { key: "remote", label: qsTr("Has remote"), n: page.all.filter(p => page.hasRemote(p)).length, tone: App.Console.data },
                    { key: "local", label: qsTr("Local only"), n: page.all.filter(p => !page.hasRemote(p)).length, tone: App.Console.faint }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: page.show === modelData.key
                    implicitWidth: chipRow.implicitWidth + 24; implicitHeight: 30; radius: 15
                    color: sel ? Qt.alpha(modelData.tone, 0.2) : chipHov.hovered ? App.Console.panelAlt : App.Console.panel
                    border.width: sel ? 1 : 0; border.color: Qt.alpha(modelData.tone, 0.6)
                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle { visible: modelData.key !== ""; implicitWidth: 7; implicitHeight: 7; radius: 3.5; color: modelData.tone }
                        Text { text: modelData.label; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                        Text { text: modelData.n; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                    }
                    HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: page.show = (sel ? "" : modelData.key) }
                }
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: body
                x: 20; y: 12
                width: flick.width - 40
                spacing: 12

                // found, not decided: take it on or leave it (CLI.md §6, `dotos project`)
                Rectangle {
                    // always: it is where you choose how new folders are treated
                    Layout.fillWidth: true
                    implicitHeight: newCol.implicitHeight + 24
                    radius: App.Console.radius
                    color: App.Console.panel
                    border.width: 1; border.color: App.Console.rule
                    ColumnLayout {
                        id: newCol
                        x: 14; y: 12; width: parent.width - 28
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Ui.Icon { text: "travel_explore"; size: 18; color: App.Console.data }
                            Text {
                                Layout.fillWidth: true
                                text: App.Store.newProjects.length > 0 ? (App.Store.newProjects.length === 1 ? qsTr("1 new project found") : qsTr("%1 new projects found").arg(App.Store.newProjects.length)) : App.Store.projectMode === "all" ? qsTr("Every project found is taken on") : qsTr("Projects are taken on only when you choose")
                                color: App.Console.text; font.pixelSize: 14; font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                            }
                        }
                        // its own line: beside the title it ran over it on a half-width window
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: qsTr("New folders:"); color: App.Console.dim; font.pixelSize: 12 }
                            Ui.SegmentedControl {
                                implicitWidth: 210
                                model: [{ key: "all", label: qsTr("Take all") }, { key: "ask", label: qsTr("Ask") }, { key: "manual", label: qsTr("Manual") }]
                                current: App.Store.projectMode
                                onPicked: k => App.Store.run(["project", "mode", k], k === "all" ? qsTr("Every project found is taken on") : k === "ask" ? qsTr("New projects wait for you") : qsTr("Only projects you track"), () => App.Store.reload(true))
                            }
                        }
                        Text {
                            visible: App.Store.newProjects.length > 0
                            Layout.fillWidth: true
                            text: qsTr("Track one to see its tasks, page and git state here. Ignore hides it for good.")
                            color: App.Console.dim; font.pixelSize: 12; wrapMode: Text.Wrap
                        }
                        Flow {
                            visible: App.Store.newProjects.length > 0
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: App.Store.newProjects
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: npRow.implicitWidth + 16; implicitHeight: 34; radius: 17
                                    color: App.Console.bg; border.width: 1; border.color: App.Console.ruleStrong
                                    RowLayout {
                                        id: npRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Ui.Icon { text: "folder"; size: 15; color: App.Console.dim; Layout.leftMargin: 4 }
                                        Text { text: modelData.name; color: App.Console.text; font.pixelSize: 13; Layout.rightMargin: 4 }
                                        Repeater {
                                            model: [{ icon: "add", tip: qsTr("Track it"), args: ["project", "track", modelData.path], ok: qsTr("Tracking %1").arg(modelData.name) },
                                                    { icon: "visibility_off", tip: qsTr("Ignore it"), args: ["project", "ignore", modelData.name], ok: qsTr("Ignoring %1").arg(modelData.name) }]
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: 24; height: 24; radius: 12
                                                color: nbHov.hovered ? App.Console.panelAlt : "transparent"
                                                Ui.Icon { anchors.centerIn: parent; text: modelData.icon; size: 15; color: nbHov.hovered ? App.Console.text : App.Console.dim }
                                                HoverHandler { id: nbHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: App.Store.run(modelData.args, modelData.ok, () => App.Store.reload(true)) }
                                                Ui.Tip { visible: nbHov.hovered; delay: 300; text: modelData.tip }
                                            }
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                visible: App.Store.newProjects.length > 1
                                implicitWidth: allText.implicitWidth + 24; implicitHeight: 34; radius: 17
                                color: allHov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data
                                Text { id: allText; anchors.centerIn: parent; text: qsTr("Track all"); color: App.Console.onData; font.pixelSize: 13; font.weight: Font.DemiBold }
                                HoverHandler { id: allHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: App.Store.run(["project", "track"].concat(App.Store.newProjects.map(p => p.path)), qsTr("Tracking %1 projects").arg(App.Store.newProjects.length), () => App.Store.reload(true)) }
                            }
                        }
                    }
                }

                // a filter: everything it matches, as cards
                Cards { visible: page.shown !== null; items: page.shown ?? [] }

                // no filter: the three sections
                Heading { visible: page.shown === null && page.attention.length > 0; text: qsTr("Needs you"); count: page.attention.length; tone: App.Console.crit }
                Cards { visible: page.shown === null && page.attention.length > 0; items: page.shown === null ? page.attention : [] }
                Heading { visible: page.shown === null && page.activeOnes.length > 0; text: qsTr("Active this week"); count: page.activeOnes.length; tone: App.Console.ok }
                Cards { visible: page.shown === null && page.activeOnes.length > 0; items: page.shown === null ? page.activeOnes : [] }
                Heading { visible: page.shown === null && page.quiet.length > 0; text: qsTr("Quiet"); count: page.quiet.length }
                ColumnLayout {
                    visible: page.shown === null
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater { model: page.shown === null ? page.quiet : []; delegate: Row1 { required property var modelData; p: modelData } }
                }
                Text {
                    visible: page.all.length === 0
                    text: page.filter ? qsTr("No project matches “%1”.").arg(page.filter) : qsTr("No projects found under your project roots.")
                    font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.dim
                }

            }
        }
    }

    // what Dotos does with one project: `dotos project set NAME key=value` (CLI.md §6)
    Popup {
        id: settings
        property var p: null
        readonly property var opt: settings.p?.options ?? ({})
        function show(p) { settings.p = p; settings.open(); }
        function set(k, v) { App.Store.run(["project", "set", settings.p.name, k + "=" + v], qsTr("%1: %2 %3").arg(settings.p.name).arg(k).arg(v), () => App.Store.reload(true)); }
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 420
        padding: 18
        background: Rectangle { radius: 12; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }
        contentItem: ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Ui.Icon { text: "tune"; size: 18; color: App.Console.data }
                Text { Layout.fillWidth: true; text: settings.p?.name ?? ""; color: App.Console.text; font.pixelSize: 19; font.weight: Font.DemiBold; elide: Text.ElideRight }
            }
            Text { Layout.fillWidth: true; text: settings.p?.path ?? ""; color: App.Console.faint; font.pixelSize: 12; elide: Text.ElideMiddle }
            Repeater {
                model: [
                    { key: "git", label: qsTr("Git state"), note: qsTr("branch, changes, commits; off saves time on slow laptops") },
                    { key: "github", label: qsTr("GitHub"), note: qsTr("its pull requests, issues and CI in Dotos") },
                    { key: "todos", label: qsTr("TODO comments"), note: qsTr("TODO and FIXME lines become tasks") },
                    { key: "sync", label: qsTr("Sync to my laptops"), note: qsTr("its tasks and chats on your other machines") },
                    { key: "pin", label: qsTr("Pinned"), note: qsTr("first in lists") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: modelData.label; color: App.Console.text; font.pixelSize: 13 }
                        Text { Layout.fillWidth: true; text: modelData.note; color: App.Console.dim; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    App.Toggle { on: settings.opt[modelData.key] === "on"; onToggled: v => settings.set(modelData.key, v ? "on" : "off") }
                }
            }
            Repeater {
                model: [
                    { key: "agents", label: qsTr("Agents"), choices: [{ key: "allow", label: qsTr("Allow") }, { key: "ask", label: qsTr("Ask") }, { key: "deny", label: qsTr("Deny") }] },
                    { key: "notify", label: qsTr("Notify me"), choices: [{ key: "all", label: qsTr("All") }, { key: "mentions", label: qsTr("Mentions") }, { key: "none", label: qsTr("None") }] }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: modelData.label; color: App.Console.text; font.pixelSize: 13 }
                    Ui.SegmentedControl {
                        implicitWidth: 210
                        model: modelData.choices
                        current: settings.opt[modelData.key] ?? ""
                        onPicked: k => settings.set(modelData.key, k)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Text { Layout.fillWidth: true; text: qsTr("Or in a terminal: dotos project set %1 key=value").arg(settings.p?.name ?? ""); color: App.Console.faint; font.pixelSize: 11; font.family: App.Console.mono; elide: Text.ElideRight }
                Rectangle {
                    implicitWidth: unText.implicitWidth + 22; implicitHeight: 30; radius: 7
                    color: unHov.hovered ? Qt.alpha(App.Console.crit, 0.15) : "transparent"; border.width: 1; border.color: App.Console.ruleStrong
                    Text { id: unText; anchors.centerIn: parent; text: qsTr("Stop tracking"); color: App.Console.crit; font.pixelSize: 12; font.weight: Font.DemiBold }
                    HoverHandler { id: unHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const n = settings.p.name;
                            // in "all" mode untracking alone does nothing: it is ignored instead
                            App.Store.run(["project", App.Store.projectMode === "all" ? "ignore" : "untrack", n], qsTr("No longer tracking %1").arg(n), () => App.Store.reload(true));
                            settings.close();
                        }
                    }
                }
            }
        }
    }
}
