import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Home: the day at a glance, as a board of cards you arrange. What needs you
 * (agents first — a waiting agent blocks work), today's calendar, what is due,
 * the projects that need a look, habits, where the time went, the day's plan.
 * Every row opens the thing it shows.
 *
 * Arrange (the ✎ button): drag a card by its header, resize it from the
 * corner, swap it for another kind of card, remove it, add one back from the
 * tray. Cards sit on a 12-column grid; the others make room. The layout is
 * kept in gui.json (Prefs.homeLayout).
 */
Item {
    id: page
    property string key: "home"
    /// the "add for today" line inside the Due card (it lives in a card component, so the page keeps a handle)
    property var captureField: null

    // ── the board (the arranging itself is ui/ArrangeBoard.qml) ────────
    readonly property bool editing: App.Nav.homeEditing
    function shown(id) { return App.Prefs.cardShown(id); }
    // where "Reset" puts each card
    readonly property var defaultSpots: ({ agents: [0, 0], calendar: [8, 0], due: [0, 5], projects: [8, 5], habits: [0, 14], time: [6, 14], plan: [0, 18], insights: [6, 19], notes: [6, 24], changes: [2, 24] })

    /// every kind of card: its size on the grid (w × h cells), its minimum, its content
    readonly property var defs: [
        { id: "agents",   title: qsTr("Agents"),         icon: "smart_toy",      w: 8, h: 5,  minW: 4, minH: 3, comp: agentsCard },
        { id: "calendar", title: qsTr("Today's calendar"), icon: "calendar_month", w: 4, h: 5, minW: 3, minH: 3, comp: calendarCard },
        { id: "due",      title: qsTr("Due & doing"),    icon: "check_circle",   w: 8, h: 9,  minW: 4, minH: 4, comp: dueCard },
        { id: "projects", title: qsTr("Projects"),       icon: "deployed_code",  w: 4, h: 8,  minW: 3, minH: 3, comp: projectsCard },
        { id: "habits",   title: qsTr("Habits"),         icon: "autorenew",      w: 6, h: 4,  minW: 3, minH: 3, comp: habitsCard },
        { id: "time",     title: qsTr("Time this week"), icon: "schedule",       w: 6, h: 5,  minW: 3, minH: 3, comp: timeCard },
        { id: "plan",     title: qsTr("Day plan"),       icon: "event_available", w: 6, h: 7, minW: 4, minH: 4, comp: planCard },
        { id: "insights", title: qsTr("Last 14 days"),   icon: "monitoring",     w: 4, h: 5,  minW: 3, minH: 3, comp: insightsCard },
        { id: "notes",    title: qsTr("Recent notes"),   icon: "description",    w: 4, h: 6,  minW: 3, minH: 3, comp: notesCard },
        { id: "changes",  title: qsTr("Recent changes"),  icon: "history",        w: 4, h: 6,  minW: 3, minH: 3, comp: changesCard },
        { id: "catchup",  title: qsTr("Team catch-up"),  icon: "forum",          w: 4, h: 5,  minW: 3, minH: 3, comp: catchupCard },
        { id: "workout",  title: qsTr("Workout"),        icon: "fitness_center", w: 4, h: 5,  minW: 3, minH: 3, comp: workoutCard }
    ]

    // ── the data the cards share ───────────────────────────────────────
    // today's calendar, from Kalends (the same CLI the calendar app uses)
    property var agenda: []
    readonly property string kalends: Quickshell.env("HOME") + "/.local/bin/kalends"
    Process {
        id: agendaProc
        running: true
        command: [page.kalends, "agenda", "--days", "1", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { page.agenda = JSON.parse(text) ?? []; } catch (e) { page.agenda = []; } } }
    }
    Timer { interval: 300000; running: true; repeat: true; onTriggered: agendaProc.running = true }

    // the day plan and the last two weeks, from the CLI
    property var dayPlan: null
    property var recent: null
    Process {
        id: planProc
        command: [App.Store.bin, "plan", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { page.dayPlan = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: recentProc
        command: [App.Store.bin, "stats", "--days", "14"]
        stdout: StdioCollector { onStreamFinished: { try { page.recent = JSON.parse(text); } catch (e) {} } }
    }
    function refreshData() {
        if (page.shown("plan") && !planProc.running) planProc.running = true;
        if (page.shown("insights") && !recentProc.running) recentProc.running = true;
    }
    Timer { id: dataTimer; interval: 600; onTriggered: page.refreshData() }
    Connections { target: App.Store; function onLastLoadChanged() { dataTimer.restart(); } }
    Connections { target: App.Prefs; function onHomeCardsChanged() { dataTimer.restart(); } }
    Component.onCompleted: dataTimer.restart()

    readonly property var due: App.Store.open.filter(t => (t.bucket === "overdue" || t.bucket === "today" || t.state === "doing") && !t.parent)
        .sort((a, b) => (a.bucket === "overdue" ? 0 : 1) - (b.bucket === "overdue" ? 0 : 1) || (a.priority === "high" ? 0 : 1) - (b.priority === "high" ? 0 : 1))
    readonly property var attention: App.Store.projects.filter(p => p.health === "attention" || p.health === "stale" || p.agents > 0)
        .sort((a, b) => ({ attention: 0, stale: 1, active: 2, quiet: 3 })[a.health] - ({ attention: 0, stale: 1, active: 2, quiet: 3 })[b.health])
    readonly property string greeting: {
        const h = new Date(App.Store.now).getHours();
        return h < 5 ? qsTr("Good night") : h < 12 ? qsTr("Good morning") : h < 18 ? qsTr("Good afternoon") : qsTr("Good evening");
    }
    function fmtMin(m) { m = Math.max(0, Math.round(m ?? 0)); return m < 60 ? m + "m" : (m % 60 === 0 ? (m / 60) + "h" : Math.floor(m / 60) + "h" + String(m % 60).padStart(2, "0")); }

    Connections {
        target: App.Nav
        function onAction(name) { if (name === "capture") page.captureField?.take(); }
    }


    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: page.greeting
            subtitle: Qt.formatDateTime(new Date(App.Store.now), "dddd d MMMM") + " · "
                + qsTr("%1 due · %2 events · %3 agents working").arg(page.due.length).arg(page.agenda.length).arg(App.Store.liveAgents.filter(a => a.state === "working").length)
            Ui.IconButton { icon: "dashboard_customize"; active: page.editing; tooltip: page.editing ? qsTr("Done arranging") : qsTr("Arrange the cards"); onClicked: { App.Nav.homeEditing = !App.Nav.homeEditing; board.swapIndex = -1; } }
            Ui.IconButton { icon: "edit_note"; tooltip: qsTr("Today's journal  (Ctrl J)"); onClicked: App.Nav.run("journal-today") }
        }

        Ui.ArrangeBoard {
            id: board
            Layout.fillWidth: true
            Layout.fillHeight: true
            defs: page.defs
            defaultSpots: page.defaultSpots
            saved: App.Prefs.homeLayout
            isShown: id => App.Prefs.cardShown(id)
            isDefaultOn: id => !App.Prefs.optionalCards.includes(id)
            editing: page.editing
            style: App.Prefs.arrangeStyle
            onLayoutSaved: json => App.Prefs.homeLayout = json
            onCardToggled: (id, on) => App.Prefs.setCard(id, on)
            onDoneRequested: App.Nav.homeEditing = false
            onStyleRequested: s => App.Prefs.arrangeStyle = s
        }
    }
    // Settings can switch cards on and off: pack the board again
    Connections { target: App.Prefs; function onHomeCardsChanged() { board.repack(); } }

    // ── the cards ──────────────────────────────────────────────────────
    Component {
        id: agentsCard
        App.Panel {
            title: qsTr("Agents")
            icon: App.Store.needsYou.length ? "notifications_active" : "smart_toy"
            iconColor: App.Store.needsYou.length ? App.Console.crit : App.Console.data
            note: App.Store.liveAgents.length ? qsTr("%1 need you · %2 working").arg(App.Store.needsYou.length).arg(App.Store.liveAgents.filter(a => a.state === "working").length) : qsTr("none running")
            onNoteClicked: App.Nav.go("agents")
            Repeater {
                model: App.Store.liveAgents.slice(0, 6)
                delegate: AgentRow { required property var modelData; agent: modelData; Layout.fillWidth: true }
            }
            Text {
                visible: App.Store.liveAgents.length === 0
                text: qsTr("No AI chat is running. Claude Code sessions appear here as they start.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
        }
    }

    // Teams catch-up: what others said on tasks since the last look (dotos catchup)
    property var catchup: []
    Process {
        id: catchupProc
        command: [App.Store.bin, "catchup", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { page.catchup = JSON.parse(text); } catch (e) { page.catchup = []; } } }
    }
    Process { id: catchupMark; command: [App.Store.bin, "catchup", "--mark"]; onExited: catchupProc.running = true }
    Timer { interval: 30000; running: page.shown("catchup"); repeat: true; triggeredOnStart: true; onTriggered: if (!catchupProc.running) catchupProc.running = true }
    Component {
        id: catchupCard
        App.Panel {
            title: qsTr("Team catch-up")
            icon: "forum"
            iconColor: page.catchup.length ? App.Console.data : App.Console.dim
            note: page.catchup.length ? qsTr("mark read") : ""
            onNoteClicked: catchupMark.running = true
            Repeater {
                model: page.catchup.slice(0, 6)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Ui.Icon { text: modelData.decided ? "gavel" : "chat"; size: 16; color: modelData.decided ? App.Console.ok : App.Console.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                        Text { Layout.fillWidth: true; readonly property var last: modelData.messages[modelData.messages.length - 1]; text: (last.name || last.author) + ": " + last.text; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim }
                    }
                    App.Tag { text: String(modelData.count); tone: App.Console.data }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { const it = String(modelData.item); if (it.startsWith("task:")) App.Nav.openTask(it.slice(5)); else if (it.startsWith("page:")) App.Nav.openPage(it.slice(5)); else if (it.startsWith("agent:")) App.Nav.openAgentTask(it.slice(6).split("#")[0], it.split("#")[1]); } }
                }
            }
            Text {
                visible: page.catchup.length === 0
                text: qsTr("Nothing new from the team.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
        }
    }

    Component {
        id: calendarCard
        App.Panel {
            title: qsTr("Today")
            icon: "calendar_month"
            iconColor: App.Console.data2
            note: "Kalends"
            onNoteClicked: Quickshell.execDetached(["qs", "-p", "/mnt/storage/dev/projects/desktop/kalends/kalends.qml"])
            Repeater {
                model: page.agenda.slice(0, 8)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    spacing: 10
                    Text {
                        Layout.preferredWidth: 46
                        text: modelData.all_day ? qsTr("all day") : String(modelData.start ?? "").slice(11, 16)
                        font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim
                    }
                    Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: App.Store.colorOf(modelData.calendar) }
                    Text { Layout.fillWidth: true; text: modelData.summary ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                }
            }
            Text {
                visible: page.agenda.length === 0
                text: qsTr("Nothing on the calendar today.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
        }
    }

    Component {
        id: dueCard
        App.Panel {
            title: qsTr("Due & doing")
            icon: "check_circle"
            note: qsTr("%1 overdue · %2 today").arg(App.Store.overdue).arg(App.Store.dueToday)
            onNoteClicked: App.Nav.go("tasks")
            Repeater {
                model: page.due.slice(0, 9)
                delegate: App.TaskRow { required property var modelData; Layout.fillWidth: true; task: modelData; compact: true }
            }
            Text {
                visible: page.due.length === 0
                text: qsTr("Nothing due. A good day to start something.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
            App.CaptureField { id: capture; Component.onCompleted: page.captureField = capture; Layout.fillWidth: true; Layout.topMargin: 6; placeholder: qsTr("Add for today…  (Ctrl N)"); suffix: "@today" }
        }
    }

    Component {
        id: projectsCard
        App.Panel {
            title: qsTr("Projects")
            icon: "deployed_code"
            iconColor: App.Console.ok
            note: qsTr("all %1").arg(App.Store.projects.length)
            onNoteClicked: App.Nav.go("projects")
            Repeater {
                model: page.attention.slice(0, 8)
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 8
                    color: pHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
                    HoverHandler { id: pHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.Nav.openProject(modelData.name) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        spacing: 10
                        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: App.Store.healthColor(modelData.health) }
                        Text { Layout.preferredWidth: 90; text: modelData.name; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.dim
                            text: [
                                modelData.agents_need_you ? qsTr("agent waits") : modelData.agents ? qsTr("%1 agent").arg(modelData.agents) : "",
                                modelData.overdue ? qsTr("%1 overdue").arg(modelData.overdue) : "",
                                modelData.git?.dirty ? qsTr("%1 uncommitted · %2 d").arg(modelData.git.dirty).arg(modelData.git.dirty_days) : "",
                                modelData.open ? qsTr("%1 open").arg(modelData.open) : ""
                            ].filter(s => s).join(" · ")
                        }
                    }
                }
            }
            Text {
                visible: page.attention.length === 0
                text: qsTr("Every project is quiet.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
        }
    }

    Component {
        id: habitsCard
        App.Panel {
            title: qsTr("Habits")
            icon: "autorenew"
            note: App.Store.habits.length ? qsTr("%1 / %2 today").arg(App.Store.habits.filter(h => h.done_today).length).arg(App.Store.habits.length) : qsTr("add one")
            onNoteClicked: App.Nav.go("habits")
            Text {
                visible: App.Store.habits.length === 0
                text: qsTr("No habits yet. Add one on the Habits page — daily, or a few times a week.")
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: App.Store.habits
                    delegate: Rectangle {
                        required property var modelData
                        width: 92; height: 74
                        radius: 12
                        color: modelData.done_today ? Qt.alpha(App.Console.ok, 0.16) : hHov.hovered ? App.Console.panelAlt : Qt.alpha(App.Console.text, 0.04)
                        HoverHandler { id: hHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.Store.habitCheck(modelData.name) }
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.done_today ? "check_circle" : modelData.icon; filled: modelData.done_today; size: 20; color: modelData.done_today ? App.Console.ok : App.Console.dim }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text; width: 80; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.per_week >= 7 ? qsTr("%1 days").arg(modelData.streak) : qsTr("%1/%2 wk").arg(modelData.this_week).arg(modelData.per_week); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: timeCard
        App.Panel {
            id: timePanel
            title: qsTr("Time this week")
            icon: "schedule"
            iconColor: App.Console.data2
            note: App.Store.dur(App.Store.time?.week_s) + " · timewarrior"
            readonly property var byProject: Object.entries(App.Store.time?.by_project_week ?? {}).sort((a, b) => b[1] - a[1]).slice(0, 6)
            readonly property real most: Math.max(1, ...byProject.map(e => e[1]))
            Repeater {
                model: timePanel.byProject
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 26
                    spacing: 10
                    Text { Layout.preferredWidth: 90; text: modelData[0]; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6; radius: 3
                        color: Qt.alpha(App.Console.text, 0.08)
                        Rectangle { width: parent.width * modelData[1] / timePanel.most; height: 6; radius: 3; color: App.Store.colorOf(modelData[0]) }
                    }
                    Text { text: App.Store.dur(modelData[1]); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                }
            }
            Text {
                visible: !(App.Store.time?.week_s > 0)
                text: qsTr("Nothing tracked yet this week. ▶ on any task starts timewarrior.")
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
        }
    }

    // the day: what is next, and what follows, with a bar of what fits
    Component {
        id: planCard
        App.Panel {
            id: pc
            title: qsTr("Day plan")
            icon: "event_available"
            iconColor: (page.dayPlan?.over_min ?? 0) > 0 ? App.Console.crit : App.Console.ok
            note: page.dayPlan ? ((page.dayPlan.over_min > 0 ? qsTr("%1 over").arg(page.fmtMin(page.dayPlan.over_min)) : qsTr("%1 spare").arg(page.fmtMin(page.dayPlan.capacity_min - page.dayPlan.planned_min)))) : ""
            onNoteClicked: App.Nav.go("plan")
            /// where a task would start if you began now (meetings are on the Plan page)
            readonly property real cursor0: { const d = new Date(App.Store.now); return Math.max((page.dayPlan?.work_start ?? 9) * 60, Math.ceil((d.getHours() * 60 + d.getMinutes()) / 5) * 5); }
            function startOf(it) { return pc.cursor0 + it.cum_min - it.est_min; }
            function clock(m) { m = Math.round(m); return String(Math.floor(m / 60) % 24).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); }
            Row {
                id: pbar
                Layout.fillWidth: true
                Layout.preferredHeight: 10
                spacing: 1
                readonly property real total: Math.max(1, Math.max(page.dayPlan?.capacity_min ?? 0, page.dayPlan?.planned_min ?? 0))
                Repeater {
                    model: page.dayPlan?.items ?? []
                    delegate: Rectangle {
                        required property var modelData
                        width: Math.max(2, pbar.width * modelData.est_min / pbar.total - 1)
                        height: 10; radius: 3
                        color: modelData.fits ? App.Store.colorOf(modelData.project || modelData.list) : Qt.alpha(App.Console.crit, 0.7)
                        HoverHandler { id: pbHov }
                        Ui.Tip { visible: pbHov.hovered; y: -height - 6; title: modelData.title; rows: [{ name: qsTr("estimate"), value: (modelData.est_guess ? "~" : "") + page.fmtMin(modelData.est_min) }] }
                    }
                }
            }
            Repeater {
                model: (page.dayPlan?.items ?? []).slice(0, 7)
                delegate: Rectangle {
                    id: pr
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: pr.index === 0 ? 44 : 30
                    radius: 8
                    color: prHov.hovered ? Qt.alpha(App.Console.text, 0.06) : pr.index === 0 ? Qt.alpha(App.Console.data, 0.10) : "transparent"
                    HoverHandler { id: prHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.Nav.openTask(pr.modelData.uid) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                        spacing: 10
                        Text { Layout.preferredWidth: 40; text: pc.clock(pc.startOf(pr.modelData)); font.family: App.Console.mono; font.pixelSize: 12; color: pr.modelData.fits ? App.Console.dim : App.Console.crit }
                        Rectangle { implicitWidth: 4; implicitHeight: pr.index === 0 ? 24 : 16; radius: 2; color: App.Store.colorOf(pr.modelData.project || pr.modelData.list) }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { Layout.fillWidth: true; text: pr.modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: pr.index === 0 ? 15 : 14; font.weight: pr.index === 0 ? Font.DemiBold : Font.Normal; color: pr.modelData.fits ? App.Console.text : App.Console.dim }
                            Text { visible: pr.index === 0; text: qsTr("next up"); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.data }
                        }
                        Text { visible: !prHov.hovered; text: (pr.modelData.est_guess ? "~" : "") + page.fmtMin(pr.modelData.est_min); font.family: App.Console.mono; font.pixelSize: 12; color: pr.modelData.est_guess ? App.Console.warn : App.Console.dim }
                        Row {
                            visible: prHov.hovered
                            spacing: 2
                            Ui.IconButton { implicitWidth: 24; implicitHeight: 24; icon: "play_arrow"; tooltip: qsTr("Start the timer"); onClicked: App.Store.track(pr.modelData.uid) }
                            Ui.IconButton { implicitWidth: 24; implicitHeight: 24; icon: "check"; tooltip: qsTr("Done"); onClicked: App.Store.setState(pr.modelData.uid, "done") }
                        }
                    }
                }
            }
            Text {
                visible: (page.dayPlan?.items.length ?? 0) > 7
                text: qsTr("+ %1 more on the Plan page").arg((page.dayPlan?.items.length ?? 7) - 7)
                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
            }
            Text {
                visible: !!page.dayPlan && page.dayPlan.items.length === 0
                text: qsTr("Nothing ready for today.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
        }
    }

    // two weeks of finished tasks, as bars, against the two weeks before
    Component {
        id: insightsCard
        App.Panel {
            id: ip
            stretch: true
            title: qsTr("Last 14 days")
            icon: "monitoring"
            note: ip.total + qsTr(" finished")
            onNoteClicked: App.Nav.go("insights")
            readonly property var done: page.recent?.done ?? []
            readonly property var labels: page.recent?.days ?? []
            readonly property int total: ip.done.reduce((a, b) => a + b, 0)
            readonly property real most: Math.max(1, ...ip.done)
            readonly property int prev: page.recent?.prev?.done ?? 0
            readonly property int pct: ip.prev > 0 ? Math.round((ip.total - ip.prev) / ip.prev * 100) : 0
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: String(ip.total); font.family: App.Console.mono; font.pixelSize: 24; font.weight: Font.DemiBold; color: App.Console.text }
                Rectangle {
                    visible: ip.prev > 0
                    implicitWidth: pctT.implicitWidth + 12; implicitHeight: 20; radius: 10
                    color: Qt.alpha(ip.pct >= 0 ? App.Console.ok : App.Console.crit, 0.16)
                    Text { id: pctT; anchors.centerIn: parent; text: (ip.pct > 0 ? "+" : "") + ip.pct + "%"; font.family: App.Console.mono; font.pixelSize: 11; font.weight: Font.DemiBold; color: ip.pct >= 0 ? App.Console.ok : App.Console.crit }
                }
                Text { text: qsTr("vs the 14 days before"); visible: ip.prev > 0; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint }
                Item { Layout.fillWidth: true }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 40
                Row {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height
                    spacing: 3
                    Repeater {
                        model: ip.done
                        delegate: Item {
                            id: bar
                            required property int modelData
                            required property int index
                            readonly property bool isToday: bar.index === ip.done.length - 1
                            width: (parent.width - 3 * (ip.done.length - 1)) / Math.max(1, ip.done.length)
                            height: parent.height
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: bar.modelData > 0 ? Math.max(3, parent.height * bar.modelData / ip.most) : 2
                                radius: 2
                                color: bar.modelData > 0 ? (bar.isToday ? App.Console.text : App.Console.data) : App.Console.grid
                            }
                            HoverHandler { id: barHov }
                            Rectangle { anchors.fill: parent; color: Qt.alpha(App.Console.text, 0.06); visible: barHov.hovered; radius: 3 }
                            Ui.Tip { visible: barHov.hovered; y: -height - 6; title: Qt.formatDate(new Date((ip.labels[bar.index] ?? "") + "T12:00:00"), "ddd d MMM"); rows: [{ name: qsTr("finished"), value: String(bar.modelData) }] }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: ip.labels.length ? Qt.formatDate(new Date(ip.labels[0] + "T12:00:00"), "d MMM") : ""; font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                Item { Layout.fillWidth: true }
                Text { text: qsTr("%1 tracked today").arg(App.Store.dur(App.Store.time?.today_s)); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
            }
        }
    }

    // the workout card reads Sinew (the workout app) through its CLI; empty when it is not installed
    Component {
        id: changesCard
        App.Panel {
            title: qsTr("Recent changes")
            icon: "history"
            iconColor: App.Console.data
            note: qsTr("Changes")
            onNoteClicked: App.Nav.go("changes")
            App.RecentChanges {
                Layout.fillWidth: true
                Layout.fillHeight: true
                compact: true
                maxItems: 5
            }
        }
    }

    Component {
        id: workoutCard
        App.Panel {
            id: wp
            title: qsTr("Workout")
            icon: "fitness_center"
            property var sn: null
            readonly property string bin: Quickshell.env("HOME") + "/.local/bin/sinew"
            note: qsTr("open Sinew")
            onNoteClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/sinew-gui"])
            Process {
                id: sproc
                command: [wp.bin, "snapshot"]
                running: true
                stdout: StdioCollector { onStreamFinished: { try { wp.sn = JSON.parse(text); } catch (e) { wp.sn = null; } } }
            }
            Timer { interval: 60000; running: true; repeat: true; onTriggered: if (!sproc.running) sproc.running = true }
            Text {
                visible: !wp.sn
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: qsTr("Sinew is not installed. It logs lifting, bodyweight and cardio with a mannequin.")
                font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
            }
            Text {
                visible: !!wp.sn
                Layout.fillWidth: true
                text: wp.sn?.current ? qsTr("%1 running · %2 sets").arg(wp.sn.current.routine || qsTr("A session")).arg(wp.sn.current.sets)
                    : (wp.sn?.week?.this ?? 0) >= (wp.sn?.week?.target ?? 3) ? qsTr("Week done") : qsTr("%1 of %2 sessions this week").arg(wp.sn?.week?.this ?? 0).arg(wp.sn?.week?.target ?? 3)
                font.family: App.Console.sans; font.pixelSize: 16; font.weight: Font.DemiBold; color: App.Console.text
            }
            Row {
                visible: !!wp.sn
                spacing: 5
                Repeater {
                    model: wp.sn?.week?.days ?? []
                    delegate: Rectangle {
                        required property var modelData
                        width: 26; height: 26; radius: 8
                        color: modelData.n > 0 ? App.Console.data : Qt.alpha(App.Console.text, 0.08)
                        border.width: modelData.today ? 2 : 0; border.color: App.Console.text
                        Text { anchors.centerIn: parent; text: modelData.d; font.family: App.Console.mono; font.pixelSize: 11; color: modelData.n > 0 ? App.Console.onData : App.Console.faint }
                    }
                }
            }
            Text {
                visible: !!wp.sn && (wp.sn.sessions ?? []).length > 0
                Layout.fillWidth: true; elide: Text.ElideRight
                text: (wp.sn?.sessions ?? []).length > 0 ? qsTr("Last: %1 · %2").arg(wp.sn.sessions[0].routine || qsTr("Workout")).arg(App.Store.ago(wp.sn.sessions[0].start)) : ""
                font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim
            }
            Text {
                visible: !!wp.sn && (wp.sn.week?.streak ?? 0) > 0
                text: qsTr("%1 week streak").arg(wp.sn?.week?.streak ?? 0)
                font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint
            }
        }
    }

    Component {
        id: notesCard
        App.Panel {
            title: qsTr("Recent notes")
            icon: "description"
            note: qsTr("all %1").arg(App.Store.pages.length)
            onNoteClicked: App.Nav.go("pages")
            tools: Ui.IconButton { implicitWidth: 26; implicitHeight: 26; icon: "add"; tooltip: qsTr("New page"); onClicked: App.Store.pageNew(qsTr("Untitled"), "", path => App.Nav.openPage(String(path).split("/").pop().replace(/\.md$/, ""))) }
            Repeater {
                model: App.Store.pages.slice(0, 6)
                delegate: Rectangle {
                    id: nr
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: nr.modelData.excerpt ? 50 : 34
                    radius: 8
                    color: nHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
                    HoverHandler { id: nHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.Nav.openPage(nr.modelData.id) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 10
                        Ui.Icon { text: nr.modelData.kind === "journal" ? "edit_note" : "description"; size: 18; color: App.Console.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { Layout.fillWidth: true; text: nr.modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                            Text { visible: !!nr.modelData.excerpt; Layout.fillWidth: true; text: nr.modelData.excerpt ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint }
                        }
                        App.Tag { visible: !!nr.modelData.project; text: "+" + nr.modelData.project; tone: App.Store.colorOf(nr.modelData.project) }
                        Text { text: App.Store.ago(nr.modelData.modified); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                    }
                }
            }
            Column {
                visible: App.Store.pages.length === 0
                Layout.fillWidth: true
                spacing: 6
                Text { width: parent.width; text: qsTr("No notes yet. Pages are markdown; link them with [[Name]]."); wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint }
                Ui.Chip { text: qsTr("New page"); interactive: true; accent: App.Console.data; onClicked: App.Store.pageNew(qsTr("Untitled"), "", path => App.Nav.openPage(String(path).split("/").pop().replace(/\.md$/, ""))) }
            }
        }
    }

    component AgentRow: Rectangle {
        id: ar
        property var agent: ({})
        implicitHeight: 40
        radius: 8
        color: ar.agent.state === "needs_you" ? Qt.alpha(App.Console.crit, 0.10) : aHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
        HoverHandler { id: aHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: App.Store.jump(ar.agent) }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 10
            Ui.Icon { text: App.Store.agentIcon(ar.agent); filled: ar.agent.state === "needs_you"; size: 18; color: App.Store.agentColor(ar.agent) }
            Text { Layout.preferredWidth: 150; text: (ar.agent.source === "claude-code" ? "Claude" : ar.agent.source) + " · " + (ar.agent.project ?? ""); elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
            Text {
                Layout.fillWidth: true
                text: App.Store.clean(ar.agent.state === "needs_you" ? ar.agent.message : ar.agent.prompt)
                elide: Text.ElideRight
                font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
            }
            Text {
                text: ar.agent.state === "working" ? App.Store.dur((App.Store.now / 1000) - (ar.agent.turn_started ?? ar.agent.started ?? 0)) : App.Store.ago(ar.agent.updated)
                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
            }
            App.Tag { text: qsTr("Jump"); tone: aHov.hovered ? App.Console.data : App.Console.dim }
        }
    }
}
