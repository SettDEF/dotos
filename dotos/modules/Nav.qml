pragma Singleton
import QtQuick
import Quickshell
import "." as App

/**
 * Where the window is, and the page registry — the same pattern as Vitals:
 * the sidebar, the shortcuts and the page host all read `pages`, and view
 * extensions add pages by being installed (their view.qml).
 */
Singleton {
    id: root

    property string page: "home"
    /// the conversation the Team page opens on (the Chat sidebar sets it)
    property string chat: ""
    property string search: ""
    property string sheet: ""          // "", "shortcuts", "about", "habit", "page"
    property string toast: ""
    property string selected: ""       // the task in the inspector
    property string opened: ""         // the task row opened below itself (its sessions, notes)
    property string renaming: ""       // the task row being renamed in place
    property string project: ""        // the project page shows this one
    property string pageId: ""         // the page (note) open in Pages
    property bool homeEditing: false   // Home is being arranged
    property string graphSel: ""       // the graph selects this point when it opens ("page:<id>")
    property var order: []             // the task uids the current page lists, top to bottom (j / k walk it)
    function step(d) {
        const o = root.order;
        if (o.length === 0) return;
        let i = o.indexOf(root.selected);
        i = i < 0 ? (d > 0 ? 0 : o.length - 1) : Math.max(0, Math.min(o.length - 1, i + d));
        root.selected = o[i];
    }
    signal action(string name)
    signal shotScroll(real y)          // the screenshot tool scrolls the current page (view "insights@600")
    function run(name) { root.action(name); }
    // the board is a view of Tasks now; its old key still works for shortcuts and launchers
    function go(key) {
        if (key === "board") { App.Prefs.tasksView = "board"; key = "tasks"; }
        root.page = key;
    }

    // ── the rail's areas (VISION.md §6; Teams' and Slack's rail, Linear's sidebar) ──
    /// each area: its rail entry, the page it opens first, its pages in the sidebar
    readonly property var areas: [
        { key: "activity", label: qsTr("Activity"), icon: "notifications", home: "home",     pages: ["home", "inbox", "history"] },
        { key: "chat",     label: qsTr("Chat"),     icon: "forum",         home: "team",     pages: ["team"] },
        { key: "work",     label: qsTr("Work"),     icon: "task_alt",      home: "tasks",    pages: ["tasks", "plan", "habits", "journal", "insights"] },
        { key: "code",     label: qsTr("Code"),     icon: "code",          home: "projects", pages: ["projects", "github", "changes", "agents"] },
        { key: "notes",    label: qsTr("Notes"),    icon: "menu_book",     home: "pages",    pages: ["pages", "graph", "tags"] }
    ]
    function areaOf(key) {
        if (key === "board") return "work";
        if (key === "project") return "code";
        if (key === "settings" || key === "extensions") return "";
        const a = root.areas.find(a => a.pages.includes(key));
        // an extension's page lives in Work, its sidebar lists them
        return a ? a.key : (root.pages.find(p => p.key === key)?.group === "ext" ? "work" : "activity");
    }
    readonly property string area: root.areaOf(root.page)
    /// the page last open in each area: the rail goes back to it, as a browser's tabs do
    property var lastIn: ({})
    onPageChanged: { if (root.area) { const m = Object.assign({}, root.lastIn); m[root.area] = root.page; root.lastIn = m; } }
    function goArea(key) {
        const a = root.areas.find(x => x.key === key);
        if (!a) return;
        // a second click on the area you are in goes to its first page
        root.go(root.area === key || !root.lastIn[key] ? a.home : root.lastIn[key]);
    }
    function openTask(uid) { root.selected = uid; if (!["tasks", "board", "project"].includes(root.page)) root.page = "tasks"; }
    function openProject(name) { root.project = name; root.page = "project"; }
    function openPage(id) { root.pageId = id; root.page = id.startsWith("journal/") ? "journal" : "pages"; }
    /// a chat on the Agents page, one of its own (Claude's) tasks opened there
    property string agent: ""
    property string agentTask: ""
    function openAgentTask(agentId, taskId) { root.agent = agentId; root.agentTask = taskId || ""; root.page = "agents"; }
    function say(text) { root.toast = text; toastTimer.restart(); }
    property Timer toastTimer: Timer { interval: 2200; onTriggered: root.toast = "" }

    // group: "" top · work · life · know · end · foot (pinned bottom)
    readonly property var builtIn: [
        { key: "home",       label: qsTr("Home"),       icon: "home",           group: "",     url: "HomePage.qml" },
        { key: "inbox",      label: qsTr("Inbox"),      icon: "inbox",          group: "",     url: "TasksPage.qml" },
        { key: "projects",   label: qsTr("Projects"),   icon: "deployed_code",  group: "work", url: "ProjectsPage.qml" },
        { key: "project",    label: qsTr("Project"),    icon: "folder_open",    group: "hidden", url: "ProjectPage.qml" },
        { key: "agents",     label: qsTr("Agents"),     icon: "smart_toy",      group: "work", url: "AgentsPage.qml" },
        { key: "team",       label: qsTr("Team"),       icon: "groups",         group: "work", url: "TeamPage.qml" },
        { key: "github",     label: qsTr("GitHub"),     icon: "code_blocks",            group: "work", url: "GitHubPage.qml" },
        { key: "tasks",      label: qsTr("Tasks"),      icon: "check_circle",   group: "life", url: "TasksPage.qml" },
        { key: "plan",       label: qsTr("Plan"),       icon: "event_available", group: "life", url: "PlanPage.qml" },
        { key: "board",      label: qsTr("Board"),      icon: "view_kanban",    group: "hidden", url: "BoardPage.qml" },
        { key: "insights",   label: qsTr("Insights"),   icon: "monitoring",     group: "life", url: "InsightsPage.qml" },
        { key: "habits",     label: qsTr("Habits"),     icon: "autorenew",      group: "life", url: "HabitsPage.qml" },
        { key: "journal",    label: qsTr("Journal"),    icon: "edit_note",      group: "life", url: "PagesPage.qml" },
        { key: "pages",      label: qsTr("Pages"),      icon: "description",    group: "know", url: "PagesPage.qml" },
        { key: "graph",      label: qsTr("Graph"),      icon: "hub",            group: "know", url: "GraphPage.qml" },
        { key: "tags",       label: qsTr("Tags"),       icon: "label",          group: "know", url: "TagsPage.qml" },
        { key: "changes",    label: qsTr("Changes"),    icon: "difference",     group: "know", url: "ChangesPage.qml" },
        { key: "history",    label: qsTr("History"),    icon: "history",        group: "more",  url: "HistoryPage.qml" },
        { key: "extensions", label: qsTr("Extensions"), icon: "extension",      group: "more",  url: "ExtensionsPage.qml" },
        { key: "settings",   label: qsTr("Settings"),   icon: "settings",       group: "foot", url: "SettingsPage.qml" }
    ]
    /// view extensions: a page each, loaded from the extension's own view.qml
    readonly property var extPages: App.Store.extensions.filter(e => e.kind === "view" && e.enabled && e.view_qml)
        .map(e => ({ key: "ext:" + e.id, label: e.name, icon: "extension", group: "end", url: "file://" + e.view_qml, ext: true }))
    readonly property var pages: root.builtIn.concat(root.extPages)
    function entry(key) { return root.pages.find(p => p.key === key) ?? root.pages[0]; }
}
