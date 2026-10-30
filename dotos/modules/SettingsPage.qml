import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Settings. Two kinds, kept apart: what Dotos does (config.json — the CLI,
 * the background service and Neovim read it too) and how this window looks
 * (gui.json). Home's cards can be switched off here.
 */
Item {
    id: page
    property string key: "settings"

    property var gitAccounts: []
    property bool gitAccountsLoading: false
    property int tagCount: 0
    property var keybindEditorAction: ""

    /// Rectangle-based button (Ui.Button doesn't exist)
    component Button: Rectangle {
        property string text: ""
        property bool filled: true
        signal clicked
        implicitWidth: 80; implicitHeight: 28; radius: 6
        color: filled ? (hov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data)
            : (hov.hovered ? App.Console.panelAlt : App.Console.panel)
        border.width: filled ? 0 : 1
        border.color: App.Console.rule
        Text { anchors.centerIn: parent; text: parent.text; font.family: App.Console.sans; font.pixelSize: 13; color: filled ? App.Console.onData : App.Console.text }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
    }

    function loadGitAccounts() {
        page.gitAccountsLoading = true;
        gitAccountsProc.command = [App.Store.bin, "git", "accounts", "--json"];
        gitAccountsProc.running = true;
    }

    Process {
        id: gitAccountsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    page.gitAccounts = Array.isArray(d) ? d : (d.accounts || []);
                } catch (e) {
                    page.gitAccounts = [];
                }
                page.gitAccountsLoading = false;
            }
        }
        stderr: StdioCollector { onStreamFinished: { page.gitAccountsLoading = false; } }
    }

    Process {
        id: tagCountProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    page.tagCount = Array.isArray(d) ? d.length : (d.tags ? d.tags.length : 0);
                } catch (e) {
                    page.tagCount = 0;
                }
            }
        }
    }

    Component.onCompleted: {
        page.loadGitAccounts();
        tagCountProc.command = [App.Store.bin, "tag", "list", "--json"];
        tagCountProc.running = true;
    }

    component Row2: RowLayout {
        id: r
        property string label: ""
        property string hint: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { Layout.fillWidth: true; text: r.label; font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.text }
            Text { visible: r.hint.length > 0; Layout.fillWidth: true; text: r.hint; wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim }
        }
        RowLayout { id: slot }
    }
    component Input: Rectangle {
        id: inp
        property string value: ""
        property int fieldWidth: 220
        signal commit(string v)
        implicitWidth: inp.fieldWidth; implicitHeight: 32; radius: 8
        color: Qt.alpha(App.Console.text, 0.06)
        border.width: ti.activeFocus ? 1 : 0
        border.color: App.Console.data
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: Text.AlignVCenter
            text: inp.value
            clip: true
            font.family: App.Console.mono; font.pixelSize: 13
            color: App.Console.text
            selectByMouse: true
            onEditingFinished: if (text !== inp.value) inp.commit(text)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        App.Toolbar { title: qsTr("Settings"); subtitle: App.Store.configDir }

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
                width: Math.min(parent.width - 28, 860)
                spacing: 12

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Tasks")
                    icon: "check_circle"
                    note: "config.json"
                    Row2 {
                        label: qsTr("Default list")
                        hint: qsTr("Where a task goes when the line names no /list")
                        Input { value: App.Store.config.defaultList ?? "personal"; onCommit: v => App.Store.setConfig("defaultList", v) }
                    }
                    Row2 {
                        label: qsTr("Capture into the Inbox")
                        hint: qsTr("New tasks start as inbox (to sort later) instead of to-do")
                        App.Toggle { on: App.Store.config.captureToInbox === true; onToggled: v => App.Store.setConfig("captureToInbox", v) }
                    }
                    Row2 {
                        label: qsTr("Timer follows “doing”")
                        hint: qsTr("Moving a task to doing starts timewarrior on it; leaving doing stops it")
                        App.Toggle { on: App.Store.config.trackOnDoing === true; onToggled: v => App.Store.setConfig("trackOnDoing", v) }
                    }
                    Row2 {
                        label: qsTr("Morning reminder at")
                        hint: qsTr("All-day tasks due today or overdue are announced once, from this hour (dotos serve)")
                        Input { fieldWidth: 70; value: String(App.Store.config.remindHour ?? 9); onCommit: v => App.Store.setConfig("remindHour", Math.max(0, Math.min(23, Number(v) || 9))) }
                    }
                }

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Projects")
                    icon: "deployed_code"
                    note: "config.json"
                    Row2 {
                        label: qsTr("Project roots")
                        hint: qsTr("Every folder inside these is a project (comma separated)")
                        Input {
                            fieldWidth: 360
                            value: (App.Store.config.projectRoots ?? ["/mnt/storage/dev/projects"]).join(", ")
                            onCommit: v => App.Store.setConfig("projectRoots", v.split(",").map(s => s.trim()).filter(s => s))
                        }
                    }
                    Row2 {
                        label: qsTr("Single projects")
                        hint: qsTr("Folders that are projects themselves")
                        Input {
                            fieldWidth: 360
                            value: (App.Store.config.projects ?? ["~/.config/quickshell"]).join(", ")
                            onCommit: v => App.Store.setConfig("projects", v.split(",").map(s => s.trim()).filter(s => s))
                        }
                    }
                }

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Window")
                    icon: "web_asset"
                    note: "gui.json"
                    Row2 {
                        label: qsTr("Start on")
                        Ui.SegmentedControl {
                            implicitWidth: 300
                            model: [{ key: "home", label: qsTr("Home") }, { key: "tasks", label: qsTr("Tasks") }, { key: "projects", label: qsTr("Projects") }, { key: "board", label: qsTr("Board") }]
                            current: App.Prefs.startPage
                            onPicked: k => App.Prefs.startPage = k
                        }
                    }
                    Row2 {
                        label: qsTr("Collapsed sidebar")
                        App.Toggle { on: App.Prefs.sidebarCollapsed; onToggled: v => App.Prefs.sidebarCollapsed = v }
                    }
                    Row2 {
                        label: qsTr("Show finished tasks")
                        hint: qsTr("The last 14 days of them, greyed out")
                        App.Toggle { on: App.Prefs.showDone; onToggled: v => App.Prefs.showDone = v }
                    }
                }

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Keybinds")
                    icon: "keyboard"
                    note: "gui.json"
                    property var allActions: [
                        { action: "palette", label: qsTr("Jump to anything · commands"), group: qsTr("Window") },
                        { action: "command", label: qsTr("Command line"), group: qsTr("Window") },
                        { action: "home", label: qsTr("Home"), group: qsTr("Go to") },
                        { action: "inbox", label: qsTr("Inbox"), group: qsTr("Go to") },
                        { action: "projects", label: qsTr("Projects"), group: qsTr("Go to") },
                        { action: "agents", label: qsTr("Agents"), group: qsTr("Go to") },
                        { action: "tasks", label: qsTr("Tasks"), group: qsTr("Go to") },
                        { action: "plan", label: qsTr("Plan the day"), group: qsTr("Go to") },
                        { action: "graph", label: qsTr("Link graph"), group: qsTr("Go to") },
                        { action: "history", label: qsTr("History"), group: qsTr("Go to") },
                        { action: "extensions", label: qsTr("Extensions"), group: qsTr("Go to") },
                        { action: "settings", label: qsTr("Settings"), group: qsTr("Go to") },
                        { action: "capture", label: qsTr("New task"), group: qsTr("Tasks") },
                        { action: "search", label: qsTr("Filter"), group: qsTr("Tasks") },
                        { action: "next-task", label: qsTr("Next task"), group: qsTr("Tasks") },
                        { action: "prev-task", label: qsTr("Previous task"), group: qsTr("Tasks") },
                        { action: "first-task", label: qsTr("First task"), group: qsTr("Tasks") },
                        { action: "last-task", label: qsTr("Last task"), group: qsTr("Tasks") },
                        { action: "done-selected", label: qsTr("Tick the selected task"), group: qsTr("Tasks") },
                        { action: "open-selected", label: qsTr("Open / close the selected task"), group: qsTr("Tasks") },
                        { action: "session-selected", label: qsTr("Open the selected task's AI session"), group: qsTr("Tasks") },
                        { action: "time-selected", label: qsTr("Start / stop its timer"), group: qsTr("Tasks") },
                        { action: "doing-selected", label: qsTr("Mark it doing"), group: qsTr("Tasks") },
                        { action: "rename-selected", label: qsTr("Rename it"), group: qsTr("Tasks") },
                        { action: "copy-selected", label: qsTr("Copy its title"), group: qsTr("Tasks") },
                        { action: "delete-selected", label: qsTr("Delete the selected task"), group: qsTr("Tasks") },
                        { action: "undo", label: qsTr("Undo the last change"), group: qsTr("Tasks") },
                        { action: "journal-today", label: qsTr("Today's journal"), group: qsTr("Tasks") },
                        { action: "stop", label: qsTr("Stop the timer"), group: qsTr("Tasks") },
                        { action: "reload", label: qsTr("Reload everything"), group: qsTr("Window") },
                        { action: "sidebar", label: qsTr("Collapse / expand the sidebar"), group: qsTr("Window") },
                        { action: "shortcuts", label: qsTr("Keyboard shortcuts"), group: qsTr("Window") },
                        { action: "escape", label: qsTr("Close · clear · back"), group: qsTr("Window") },
                        { action: "quit", label: qsTr("Quit"), group: qsTr("Window") }
                    ]
                    property var sortedActions: {
                        const groups = {};
                        for (const a of (page.allActions || [])) {
                            if (!groups[a.group]) groups[a.group] = [];
                            groups[a.group].push(a);
                        }
                        const order = [qsTr("Window"), qsTr("Go to"), qsTr("Tasks")];
                        const out = [];
                        for (const g of order) if (groups[g]) out.push({ group: g, items: groups[g] });
                        for (const g of Object.keys(groups).sort()) if (!order.includes(g)) out.push({ group: g, items: groups[g] });
                        return out;
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: page.sortedActions
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: modelData.group; font.family: App.Console.sans; font.pixelSize: 11; font.weight: Font.DemiBold; color: App.Console.dim }
                                }
                                Repeater {
                                    model: modelData.items
                                    delegate: Row2 {
                                        required property var modelData
                                        label: modelData.label
                                        Input {
                                            fieldWidth: 120
                                            value: {
                                                const s = App.Prefs.keybinds ? Object.keys(App.Prefs.keybinds).find(k => App.Prefs.keybinds[k] === modelData.action) : "";
                                                return s ? s.replace("ctrl+", "Ctrl+").replace("shift+", "Shift+").replace("alt+", "Alt+") : "";
                                            }
                                            onCommit: v => {
                                                const kb = Object.assign({}, App.Prefs.keybinds || {});
                                                // Remove any existing binding for this action
                                                for (const [k, a] of Object.entries(kb)) if (a === modelData.action) delete kb[k];
                                                if (v.trim()) {
                                                    const norm = v.trim().toLowerCase().replace(/ctrl/g, "ctrl").replace(/shift/g, "shift").replace(/alt/g, "alt");
                                                    kb[norm] = modelData.action;
                                                }
                                                App.Prefs.keybinds = kb;
                                            }
                                            Keys.onEscapePressed: { forceActiveFocus(); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Home")
                    icon: "home"
                    Row2 {
                        label: qsTr("Arrange style")
                        hint: qsTr("How a card is grabbed while arranging Home. Border: the edge itself thickens. Snap grid: grid dots, a dot on each corner.")
                        Ui.SegmentedControl {
                            implicitWidth: 220
                            model: [{ key: "border", label: qsTr("Border") }, { key: "snap", label: qsTr("Snap grid") }]
                            current: App.Prefs.arrangeStyle
                            onPicked: k => App.Prefs.arrangeStyle = k
                        }
                    }
                    Repeater {
                        model: [{ id: "agents", label: qsTr("Agents") }, { id: "calendar", label: qsTr("Today's calendar") }, { id: "due", label: qsTr("Due & doing") },
                                { id: "projects", label: qsTr("Projects") }, { id: "habits", label: qsTr("Habits") }, { id: "time", label: qsTr("Time this week") },
                                { id: "plan", label: qsTr("Day plan") }, { id: "insights", label: qsTr("Last 14 days") }, { id: "notes", label: qsTr("Recent notes") }, { id: "workout", label: qsTr("Workout (Sinew)") }]
                        delegate: Row2 {
                            required property var modelData
                            label: modelData.label
                            App.Toggle { on: App.Prefs.cardShown(modelData.id); onToggled: v => App.Prefs.setCard(modelData.id, v) }
                        }
                    }
                }

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Where things are")
                    icon: "folder"
                    Repeater {
                        model: [[qsTr("Tasks (VTODO)"), App.Store.snap?.store ?? ""], [qsTr("Pages & journal"), App.Store.dataDir], [qsTr("Change log"), App.Store.stateDir + "/events.jsonl"],
                                [qsTr("Extensions"), App.Store.configDir + "/extensions"], [qsTr("CLI"), App.Store.bin]]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text { Layout.preferredWidth: 150; text: modelData[0]; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.dim }
                            Text {
                                Layout.fillWidth: true
                                text: modelData[1]
                                elide: Text.ElideMiddle
                                font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.data
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: App.Store.openFolder(modelData[1].replace(/\/[^/]+\.(jsonl|json)$/, "").replace(/\/dotos$/, "")) }
                            }
                        }
                    }
                }
                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Git accounts")
                    icon: "cloud"
                    note: "git-auth.json"

                    property var accounts: []
                    property bool loading: false

                    Row2 {
                        label: qsTr("Connected accounts")
                        hint: qsTr("GitHub, GitLab, Bitbucket Cloud, Bitbucket Server")
                        Text {
                            text: page.gitAccounts.length > 0
                                ? page.gitAccounts.map(a => (a.provider || a.id || "account")).join(", ")
                                : qsTr("None connected")
                            font.family: App.Console.sans
                            font.pixelSize: 13
                            color: page.gitAccounts.length > 0 ? App.Console.text : App.Console.dim
                        }
                    }

                    Row2 {
                        label: qsTr("Connect GitHub")
                        hint: qsTr("Opens a terminal to paste a personal access token")
                        Button { text: qsTr("Connect"); onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--", "sh", "-c", App.Store.bin + " git connect github; read -p 'Press Enter...'"]) }
                    }

                    Row2 {
                        label: qsTr("Connect GitLab")
                        hint: qsTr("Opens a terminal to paste a personal access token")
                        Button { text: qsTr("Connect"); onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--", "sh", "-c", App.Store.bin + " git connect gitlab; read -p 'Press Enter...'"]) }
                    }

                    Row2 {
                        label: qsTr("Disconnect all")
                        hint: qsTr("Removes all stored git credentials")
                        Button { text: qsTr("Disconnect"); onClicked: { Quickshell.execDetached([App.Store.bin, "git", "disconnect", "github"]); Quickshell.execDetached([App.Store.bin, "git", "disconnect", "gitlab"]); page.loadGitAccounts(); } }
                    }
                }

                App.Panel {
                    Layout.fillWidth: true
                    title: qsTr("Tags")
                    icon: "label"
                    note: "tags.json"

                    Row2 {
                        label: qsTr("Custom tags")
                        hint: qsTr("Tags with color, icon, priority. Used in tasks and spinweb visualization.")
                        Text {
                            text: page.tagCount > 0 ? page.tagCount + qsTr(" tags defined") : qsTr("No custom tags yet")
                            font.family: App.Console.sans
                            font.pixelSize: 13
                            color: page.tagCount > 0 ? App.Console.text : App.Console.dim
                        }
                    }

                    Row2 {
                        label: qsTr("Add tag")
                        hint: qsTr("name --color #hex --pri high|normal|low|critical --icon name")
                        Button { text: qsTr("Add"); onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--", "sh", "-c", "echo 'dotos tag add <name> --color #hex --pri high --icon label'; read -p 'Press Enter...'"]) }
                    }

                    Row2 {
                        label: qsTr("List tags")
                        Button { text: qsTr("List"); onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--", "sh", "-c", App.Store.bin + " tag list; read -p 'Press Enter...'"]) }
                    }

                    Row2 {
                        label: qsTr("Spinweb")
                        hint: qsTr("Spider-web graph of tag co-occurrence")
                        Button { text: qsTr("Show"); onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--", "sh", "-c", App.Store.bin + " tag spinweb | python3 -m json.tool; read -p 'Press Enter...'"]) }
                    }
                }
            }
        }
    }
}
