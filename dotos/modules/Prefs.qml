pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The window's own preferences, in ~/.config/dotos/gui.json. What Dotos
 * itself does (default list, capture rules, reminders) is config.json,
 * which the CLI reads too — see Store.config / Store.setConfig.
 */
Singleton {
    id: root
    readonly property string dir: Quickshell.env("DOTOS_HOME")
        ? Quickshell.env("DOTOS_HOME") + "/config"
        : (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/dotos"

    property alias startPage: adapter.startPage
    property alias sidebarCollapsed: adapter.sidebarCollapsed
    property alias windowWidth: adapter.windowWidth
    property alias windowHeight: adapter.windowHeight
    property alias tasksGroup: adapter.tasksGroup
    property alias showDone: adapter.showDone
    property alias inspectorOpen: adapter.inspectorOpen
    property alias projectsSort: adapter.projectsSort
    property alias githubRepo: adapter.githubRepo
    property alias homeCards: adapter.homeCards
    property alias homeLayout: adapter.homeLayout
    property alias arrangeStyle: adapter.arrangeStyle
    property alias graphPos: adapter.graphPos
    property alias graphPins: adapter.graphPins
    property alias graphViews: adapter.graphViews
    property alias tasksView: adapter.tasksView
    property var keybinds: adapter.keybinds

    // cards that start switched off (the original six start on)
    readonly property var optionalCards: ["plan", "insights", "workout"]
    function cardShown(id) { const v = root.homeCards[id]; return v === undefined ? !root.optionalCards.includes(id) : v; }
    function setCard(id, on) {
        const next = Object.assign({}, root.homeCards);
        next[id] = on;
        root.homeCards = next;
    }

    FileView {
        path: root.dir + "/gui.json"
        watchChanges: true
        // read before any page is made: the Home board laid itself out before the file came, found no
        // layout, and saved the default over yours
        blockLoading: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: adapter
            property string startPage: "home"
            property bool sidebarCollapsed: false
            property int windowWidth: 1280
            property int windowHeight: 800
            property string tasksGroup: "bucket"   // bucket | list | project | state | priority
            property bool showDone: false
            property bool inspectorOpen: true
            property string projectsSort: "health" // health | name | recent
            property string githubRepo: ""         // the GitHub page's repository, owner/name
            property var homeCards: ({})
            property string homeLayout: ""            // JSON: [{ id, col, row, w, h }] on a 12-column grid
            property string arrangeStyle: "border"     // border | snap — how cards are grabbed while arranging
            property string graphPos: "{}"            // JSON { nodeId: [x, y] }: where the graph left its points
            property string graphPins: "[]"           // JSON [nodeId]: points pinned where they are
            property string graphViews: "[]"          // JSON [{ name, show…, colorBy, focusId, depth, zoom, ox, oy }]: saved graph views
            property string tasksView: "list"         // list | board
            property var keybinds: ({})               // key -> action map
        }
    }
}