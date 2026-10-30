//@ pragma UseQApplication
//@ pragma AppId dotos
// Dotos — work, agents, life and knowledge in one window.
// Run with: qs -p /mnt/storage/dev/projects/desktop/dotos/dotos.qml
//
// The window is a view onto the `dotos` CLI: it reads `dotos snapshot` and
// every change goes through `dotos …`, the same door the terminal, Neovim,
// extensions and the shell use. Same shape as Vitals: a sidebar over the page
// registry (modules/Nav.qml), one page at a time with its own toolbar, a
// status bar under it, our rounded themed look (modules/Console.qml).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "modules" as App
import "ui" as Ui

ShellRoot {
    id: appRoot
    readonly property var con: App.Console

    Component.onCompleted: {
        const start = Quickshell.env("DOTOS_PAGE");
        // `dotos-gui capture`: open on Home with the new-task line focused
        if (start === "capture") { App.Nav.go("home"); startCapture.start(); }
        else App.Nav.go(start || App.Prefs.startPage || "home");
    }
    Timer { id: startCapture; interval: 700; onTriggered: appRoot.run("capture") }

    Connections {
        target: App.Store
        function onSaid(text) { if (text) App.Nav.say(text); }
    }
    Connections {
        target: App.Nav
        function onAction(name) { appRoot.run(name); }
    }
    property bool _inRun: false
    function run(action) {
        if (appRoot._inRun) return;
        if (App.Nav.pages.some(p => p.key === action)) { App.Nav.go(action); stage.forceActiveFocus(); return; }
        switch (action) {
            case "capture":
                if (!["tasks", "inbox", "home", "project"].includes(App.Nav.page)) App.Nav.go("tasks");
                Qt.callLater(() => { appRoot._inRun = true; App.Nav.action("capture"); appRoot._inRun = false; });
                return;
            case "search":
                if (!["tasks", "inbox", "pages", "journal"].includes(App.Nav.page)) App.Nav.go("tasks");
                Qt.callLater(() => { appRoot._inRun = true; App.Nav.action("search"); appRoot._inRun = false; });
                return;
            case "undo": App.Store.undoLabel(out => App.Nav.say(out || qsTr("Undone"))); break;
            case "reload": App.Store.reload(true); App.Nav.say(qsTr("Reloaded")); break;
            case "journal-today": App.Store.journal(path => { const day = path.split("/").pop().replace(/\.md$/, ""); App.Nav.openPage("journal/" + day); }); break;
            case "stop": App.Store.stop(); break;
            case "shortcuts": case "about": App.Nav.sheet = action; break;
            case "sidebar": App.Prefs.sidebarCollapsed = !App.Prefs.sidebarCollapsed; break;
            case "data-folder": App.Store.openFolder(App.Store.dataDir); break;
            case "ext-folder": App.Store.openFolder(App.Store.configDir + "/extensions"); break;
            case "palette": palette.show(""); return;
            case "command": palette.show(":"); return;
            case "menu": moreMenu.toggle(); return;
            case "next-task": App.Nav.step(vimCount > 0 ? vimCount : 1); vimCount = 0; break;
            case "prev-task": App.Nav.step(vimCount > 0 ? -vimCount : -1); vimCount = 0; break;
            case "first-task": App.Nav.step(-100000); break;
            case "last-task": App.Nav.step(100000); break;
            case "done-selected": { const t = App.Store.task(App.Nav.selected); if (t) App.Store.toggleDone(t); break; }
            case "open-selected": if (App.Nav.selected) App.Nav.opened = App.Nav.opened === App.Nav.selected ? "" : App.Nav.selected; break;
            case "session-selected": { const t = App.Store.task(App.Nav.selected); const s = t ? App.Store.sessionsOf(t) : []; if (s.length) App.Store.jump(s[0]); break; }
            case "time-selected": if (App.Nav.selected) { if (App.Store.active?.uid === App.Nav.selected) App.Store.stop(); else App.Store.track(App.Nav.selected); } break;
            case "doing-selected": if (App.Nav.selected) App.Store.setState(App.Nav.selected, "doing"); break;
            case "rename-selected": if (App.Nav.selected) App.Nav.renaming = App.Nav.selected; break;
            case "copy-selected": { const t = App.Store.task(App.Nav.selected); if (t) { Quickshell.clipboardText = t.title; App.Nav.toast = qsTr("Copied"); } break; }
            case "delete-selected": if (App.Nav.selected) { App.Store.remove(App.Nav.selected); App.Nav.selected = ""; } break;
            case "escape":
                // closes one layer at a time and never quits (Ctrl Q does that)
                if (moreMenu.open) moreMenu.open = false;
                else if (palette.open) palette.close();
                else if (App.Nav.sheet !== "") App.Nav.sheet = "";
                else if (App.Nav.homeEditing) App.Nav.homeEditing = false;
                else if (App.Nav.selected !== "") App.Nav.selected = "";
                else if (App.Nav.search !== "") App.Nav.search = "";
                else if (App.Nav.page !== "home") App.Nav.go("home");
                break;
            case "quit": Qt.quit(); return;
        }
        stage.forceActiveFocus();
    }

    function key(k, mods, label, group, action, keys) {
        return { label, group, action, keys, match: (e, m) => e.key === k && m === (mods ?? 0) };
    }

    /// Default shortcuts (can be overridden by ~/.config/dotos/gui.json "keybinds")
    readonly property var defaultShortcuts: [
        key(Qt.Key_1, 0, qsTr("Home"), qsTr("Go to"), "home", ["1"]),
        key(Qt.Key_2, 0, qsTr("Inbox"), qsTr("Go to"), "inbox", ["2"]),
        key(Qt.Key_3, 0, qsTr("Projects"), qsTr("Go to"), "projects", ["3"]),
        key(Qt.Key_4, 0, qsTr("Agents"), qsTr("Go to"), "agents", ["4"]),
        key(Qt.Key_5, 0, qsTr("Tasks"), qsTr("Go to"), "tasks", ["5"]),
        key(Qt.Key_6, 0, qsTr("Board"), qsTr("Go to"), "board", ["6"]),
        key(Qt.Key_7, 0, qsTr("Habits"), qsTr("Go to"), "habits", ["7"]),
        key(Qt.Key_8, 0, qsTr("Journal"), qsTr("Go to"), "journal", ["8"]),
        key(Qt.Key_9, 0, qsTr("Pages"), qsTr("Go to"), "pages", ["9"]),
        key(Qt.Key_K, Qt.ControlModifier, qsTr("Jump to anything · commands"), qsTr("Window"), "palette", ["Ctrl", "K"]),
        key(Qt.Key_Colon, Qt.ShiftModifier, qsTr("Command line"), qsTr("Window"), "command", [":"]),
        key(Qt.Key_0, 0, qsTr("Plan the day"), qsTr("Go to"), "plan", ["0"]),
        key(Qt.Key_G, Qt.ControlModifier, qsTr("Link graph"), qsTr("Go to"), "graph", ["Ctrl", "G"]),
        key(Qt.Key_H, Qt.ControlModifier, qsTr("History"), qsTr("Go to"), "history", ["Ctrl", "H"]),
        key(Qt.Key_E, Qt.ControlModifier, qsTr("Extensions"), qsTr("Go to"), "extensions", ["Ctrl", "E"]),
        key(Qt.Key_Comma, Qt.ControlModifier, qsTr("Settings"), qsTr("Go to"), "settings", ["Ctrl", ","]),
        key(Qt.Key_N, Qt.ControlModifier, qsTr("New task"), qsTr("Tasks"), "capture", ["Ctrl", "N"]),
        key(Qt.Key_N, 0, qsTr("New task"), qsTr("Tasks"), "capture", ["N"]),
        key(Qt.Key_Slash, 0, qsTr("Filter"), qsTr("Tasks"), "search", ["/"]),
        key(Qt.Key_F, Qt.ControlModifier, qsTr("Filter"), qsTr("Tasks"), "search", ["Ctrl", "F"]),
        key(Qt.Key_J, 0, qsTr("Next task"), qsTr("Tasks"), "next-task", ["J"]),
        key(Qt.Key_K, 0, qsTr("Previous task"), qsTr("Tasks"), "prev-task", ["K"]),
        key(Qt.Key_Home, 0, qsTr("First task"), qsTr("Tasks"), "first-task", ["Home"]),
        key(Qt.Key_End, 0, qsTr("Last task"), qsTr("Tasks"), "last-task", ["End"]),
        key(Qt.Key_X, 0, qsTr("Tick the selected task"), qsTr("Tasks"), "done-selected", ["X"]),
        key(Qt.Key_Return, 0, qsTr("Open / close the selected task"), qsTr("Tasks"), "open-selected", ["Enter"]),
        key(Qt.Key_S, 0, qsTr("Open the selected task's AI session"), qsTr("Tasks"), "session-selected", ["S"]),
        key(Qt.Key_T, 0, qsTr("Start / stop its timer"), qsTr("Tasks"), "time-selected", ["T"]),
        key(Qt.Key_D, 0, qsTr("Mark it doing"), qsTr("Tasks"), "doing-selected", ["D"]),
        key(Qt.Key_R, 0, qsTr("Rename it"), qsTr("Tasks"), "rename-selected", ["R"]),
        key(Qt.Key_Y, 0, qsTr("Copy its title"), qsTr("Tasks"), "copy-selected", ["Y"]),
        key(Qt.Key_Delete, 0, qsTr("Delete the selected task"), qsTr("Tasks"), "delete-selected", ["Del"]),
        key(Qt.Key_Z, Qt.ControlModifier, qsTr("Undo the last change"), qsTr("Tasks"), "undo", ["Ctrl", "Z"]),
        key(Qt.Key_J, Qt.ControlModifier, qsTr("Today's journal"), qsTr("Tasks"), "journal-today", ["Ctrl", "J"]),
        key(Qt.Key_Period, Qt.ControlModifier, qsTr("Stop the timer"), qsTr("Tasks"), "stop", ["Ctrl", "."]),
        key(Qt.Key_R, Qt.ControlModifier, qsTr("Reload everything"), qsTr("Window"), "reload", ["Ctrl", "R"]),
        key(Qt.Key_B, Qt.ControlModifier, qsTr("Collapse / expand the sidebar"), qsTr("Window"), "sidebar", ["Ctrl", "B"]),
        key(Qt.Key_Question, Qt.ShiftModifier, qsTr("Keyboard shortcuts"), qsTr("Window"), "shortcuts", ["?"]),
        key(Qt.Key_F1, 0, qsTr("Keyboard shortcuts"), qsTr("Window"), "shortcuts", ["F1"]),
        key(Qt.Key_Escape, 0, qsTr("Close · clear · back"), qsTr("Window"), "escape", ["Esc"]),
        key(Qt.Key_Q, Qt.ControlModifier, qsTr("Quit"), qsTr("Window"), "quit", ["Ctrl", "Q"]),
        key(Qt.Key_C, Qt.ControlModifier, qsTr("Force quit"), qsTr("Window"), "quit", ["Ctrl", "C"])
    ]

    /// Build final shortcuts: defaults merged with user keybinds (key -> action)
    readonly property var shortcuts: {
        const user = App.Prefs.keybinds || {};
        const byAction = {};
        for (const s of appRoot.defaultShortcuts) byAction[s.action] = s;
        // Apply user overrides: key string like "ctrl+n" -> action name
        const keyToQt = {
            "esc": Qt.Key_Escape, "escape": Qt.Key_Escape, "enter": Qt.Key_Return, "return": Qt.Key_Return,
            "tab": Qt.Key_Tab, "space": Qt.Key_Space, "backspace": Qt.Key_Backspace, "delete": Qt.Key_Delete,
            "up": Qt.Key_Up, "down": Qt.Key_Down, "left": Qt.Key_Left, "right": Qt.Key_Right,
            "home": Qt.Key_Home, "end": Qt.Key_End, "pageup": Qt.Key_PageUp, "pagedown": Qt.Key_PageDown,
            "f1": Qt.Key_F1, "f2": Qt.Key_F2, "f3": Qt.Key_F3, "f4": Qt.Key_F4, "f5": Qt.Key_F5,
            "f6": Qt.Key_F6, "f7": Qt.Key_F7, "f8": Qt.Key_F8, "f9": Qt.Key_F9, "f10": Qt.Key_F10,
            "f11": Qt.Key_F11, "f12": Qt.Key_F12,
            "slash": Qt.Key_Slash, "question": Qt.Key_Question, "period": Qt.Key_Period, "comma": Qt.Key_Comma,
            "semicolon": Qt.Key_Semicolon, "colon": Qt.Key_Colon, "quote": Qt.Key_QuoteDbl, "apostrophe": Qt.Key_Apostrophe,
            "bracketleft": Qt.Key_BracketLeft, "bracketright": Qt.Key_BracketRight, "backslash": Qt.Key_Backslash,
            "minus": Qt.Key_Minus, "equal": Qt.Key_Equal, "grave": Qt.Key_QuoteLeft,
            "0": Qt.Key_0, "1": Qt.Key_1, "2": Qt.Key_2, "3": Qt.Key_3, "4": Qt.Key_4, "5": Qt.Key_5,
            "6": Qt.Key_6, "7": Qt.Key_7, "8": Qt.Key_8, "9": Qt.Key_9,
            "a": Qt.Key_A, "b": Qt.Key_B, "c": Qt.Key_C, "d": Qt.Key_D, "e": Qt.Key_E, "f": Qt.Key_F,
            "g": Qt.Key_G, "h": Qt.Key_H, "i": Qt.Key_I, "j": Qt.Key_J, "k": Qt.Key_K, "l": Qt.Key_L,
            "m": Qt.Key_M, "n": Qt.Key_N, "o": Qt.Key_O, "p": Qt.Key_P, "q": Qt.Key_Q, "r": Qt.Key_R,
            "s": Qt.Key_S, "t": Qt.Key_T, "u": Qt.Key_U, "v": Qt.Key_V, "w": Qt.Key_W, "x": Qt.Key_X,
            "y": Qt.Key_Y, "z": Qt.Key_Z
        };
        for (const [keyStr, action] of Object.entries(user)) {
            const parts = keyStr.toLowerCase().split("+");
            let mods = 0, keyName = parts.pop();
            for (const m of parts) {
                if (m === "ctrl" || m === "control") mods |= Qt.ControlModifier;
                else if (m === "shift") mods |= Qt.ShiftModifier;
                else if (m === "alt" || m === "meta") mods |= Qt.AltModifier;
            }
            const qtKey = keyToQt[keyName];
            if (qtKey !== undefined && byAction[action]) {
                            const base = byAction[action];
                            const updated = {};
                            for (const k in base) updated[k] = base[k];
                            updated.match = (e, m) => e.key === qtKey && m === mods;
                            updated.keys = parts.map(p => p.charAt(0).toUpperCase() + p.slice(1)).concat([keyName.charAt(0).toUpperCase() + keyName.slice(1)]);
                            byAction[action] = updated;
                        }
                    }
                    return Object.values(byAction);
                }

                function hintFor(action) {
                    const s = appRoot.shortcuts.find(x => x.action === action);
                    return s ? s.keys.join(" + ") : "";
                }

                readonly property var menuItems: [
                { icon: "search", label: qsTr("Jump to anything · commands"), hint: hintFor("palette"), action: "palette" },
                { icon: "add_task", label: qsTr("New task"), hint: hintFor("capture"), action: "capture" },
                { icon: "edit_note", label: qsTr("Today's journal"), hint: hintFor("journal-today"), action: "journal-today" },
                { icon: "undo", label: qsTr("Undo last change"), hint: hintFor("undo"), action: "undo" },
                { icon: "refresh", label: qsTr("Reload"), hint: hintFor("reload"), action: "reload" },
                { separator: true },
                { icon: "history", label: qsTr("History"), hint: hintFor("history"), action: "history" },
                { icon: "extension", label: qsTr("Extensions"), hint: hintFor("extensions"), action: "extensions" },
        { icon: "folder_open", label: qsTr("Open extensions folder"), hint: "", action: "ext-folder" },
        { icon: "folder", label: qsTr("Open data folder"), hint: "", action: "data-folder" },
        { separator: true },
        { icon: "settings", label: qsTr("Settings"), hint: "Ctrl ,", action: "settings" },
        { icon: App.Prefs.sidebarCollapsed ? "left_panel_open" : "left_panel_close", label: App.Prefs.sidebarCollapsed ? qsTr("Expand sidebar") : qsTr("Collapse sidebar"), hint: "Ctrl B", action: "sidebar" },
        { icon: "keyboard", label: qsTr("Keyboard shortcuts"), hint: "?", action: "shortcuts" },
        { icon: "info", label: qsTr("About Dotos"), hint: "", action: "about" }
    ]

    // the real window buttons, drawn by the compositor over our corner (ii-decor)
    Process {
        id: decor
        command: ["sh", "-c", "sleep 0.4; hyprctl iidecor integrate pid:$PPID overlay >/dev/null 2>&1 || true"]
    }
    Timer { interval: 200; running: win.visible; onTriggered: decor.running = true }

    // `qs ipc --pid N call dotos shot /tmp/x.png <view>` — a self-capture for
    // checking the look without a screen. <view>: a page key, "menu",
    // "sheet:shortcuts", "task:<uid>", "project:<name>", "page:<id>".
    Timer { id: shotScrollTimer; property real y: 0; interval: 350; onTriggered: App.Nav.shotScroll(y) }
    Timer {
        id: shotTimer
        property string path: ""
        interval: 700
        onTriggered: stage.grabToImage(r => r.saveToFile(shotTimer.path))
    }
    IpcHandler {
        target: "dotos"
        // a notification's Open: the item its message is on (task:UID, project:NAME, page:ID, agent:SESSION#N)
        function open(item: string): void {
            App.Nav.sheet = "";
            const i = item.indexOf(":");
            const kind = i > 0 ? item.slice(0, i) : "task";
            const rest = i > 0 ? item.slice(i + 1) : item;
            if (kind === "task") App.Nav.openTask(rest);
            else if (kind === "project") App.Nav.openProject(rest);
            else if (kind === "page") App.Nav.openPage(rest);
            else if (kind === "agent") { const [s, t] = rest.split("#"); App.Nav.openAgentTask(s, t ?? ""); }
        }
        function shot(path: string, view: string): void {
            App.Nav.sheet = "";
            moreMenu.open = false;
            palette.open = false;
            App.Nav.homeEditing = view === "home:edit";
            if (view === "home:edit") view = "home";
            if (view.startsWith("palette")) palette.show(view.slice(8));
            else if (view.startsWith("sheet:")) App.Nav.sheet = view.slice(6);
            else if (view === "menu") moreMenu.open = true;
            else if (view.startsWith("task:")) {
                const [uid, y] = view.slice(5).split("@");
                App.Nav.go("tasks");
                App.Nav.selected = uid === "first" ? (App.Store.tasks.find(t => t.title === "Graph lead")?.uid ?? App.Store.tasks.find(t => t.state !== "done")?.uid ?? "") : uid;
                if (y) { shotScrollTimer.y = parseFloat(y); shotScrollTimer.restart(); }
            }
            // a Home row opened below itself (its sessions): open:<uid>, or open:first (the first due one)
            // keys:Right,M,Enter … : the page's own keys pressed (tests), after it has loaded
            else if (view.startsWith("keys:")) {
                const names = view.slice(5).split(",");
                for (const k of names) {
                    const key = Qt["Key_" + k.trim()];
                    if (key !== undefined && pageLoader.item && typeof pageLoader.item.handleKey === "function") pageLoader.item.handleKey({ key, modifiers: 0 });
                }
            }
            // js:CODE  the harness only: CODE runs with p = the page (states a mouse would reach)
            else if (view.startsWith("js:") && pageLoader.item) (new Function("p", view.slice(3)))(pageLoader.item);
            else if (view.startsWith("open:")) { App.Nav.go("home"); const u = view.slice(5) === "first" ? (App.Store.tasks.find(t => t.state !== "done")?.uid ?? "") : view.slice(5); App.Nav.selected = u; App.Nav.opened = u; }
            else if (view.startsWith("project:")) App.Nav.openProject(view.slice(8));
            else if (view.startsWith("page:")) App.Nav.openPage(view.slice(5));
            else if (view.length > 0) {
                const at = view.indexOf("@");
                App.Nav.go(at > 0 ? view.slice(0, at) : view);
                if (at > 0) { shotScrollTimer.y = parseFloat(view.slice(at + 1)); shotScrollTimer.restart(); }
            }
            shotTimer.path = path;
            shotTimer.restart();
        }
        function go(view: string): void { App.Nav.go(view); }
    }

    FloatingWindow {
        // touchpad momentum for every list in the window (ui/Momentum.qml)
        Ui.MomentumInjector { root: parent }
        id: win
        title: "Dotos"
        minimumSize: Qt.size(820, 560)
        implicitWidth: App.Prefs.windowWidth
        implicitHeight: App.Prefs.windowHeight
        onWidthChanged: sizeSave.restart()
        onHeightChanged: sizeSave.restart()
        Timer {
            id: sizeSave
            interval: 800
            onTriggered: {
                if (win.width >= 820 && win.height >= 560) {
                    App.Prefs.windowWidth = Math.round(win.width);
                    App.Prefs.windowHeight = Math.round(win.height);
                }
            }
        }
        color: appRoot.con.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        Rectangle {
            id: stage
            anchors.fill: parent
            color: appRoot.con.bg
            focus: true
            property int vimCount: 0
            property string lastKey: ""
            Keys.onPressed: event => {
                // the page first: each list page moves with j/k, opens with Enter, has its letters (keynav.js);
                // what it does not take (digits, Ctrl keys) goes on to counts and the window's shortcuts
                if (pageLoader.item && typeof pageLoader.item.handleKey === "function" && pageLoader.item.handleKey(event)) { event.accepted = true; vimCount = 0; lastKey = ""; return; }
                // accumulate counts for vim-style (3j, 5k, etc.)
                if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))) {
                    vimCount = vimCount * 10 + (event.key - Qt.Key_0);
                    event.accepted = true;
                    return;
                }
                // gg: go to first task (vim-style)
                if (event.key === Qt.Key_G && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                    if (lastKey === "g") {
                        App.Nav.step(-100000);
                        lastKey = "";
                        vimCount = 0;
                        event.accepted = true;
                        return;
                    }
                    lastKey = "g";
                    event.accepted = true;
                    return;
                }
                lastKey = "";
                // the page first: a page with its own keys (the graph) takes the ones it uses
                if (pageLoader.item && typeof pageLoader.item.handleKey === "function" && pageLoader.item.handleKey(event)) { event.accepted = true; vimCount = 0; return; }
                const mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier);
                const hit = appRoot.shortcuts.find(s => s.match(event, mods));
                if (hit) { appRoot.run(hit.action); event.accepted = true; vimCount = 0; }
                else { vimCount = 0; }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                App.Sidebar { Layout.fillHeight: true }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    Loader {
                        id: pageLoader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property var entry: App.Nav.entry(App.Nav.page)
                        function load() {
                            const url = entry.ext ? entry.url : Qt.resolvedUrl("modules/" + entry.url);
                            pageLoader.setSource(url, { key: entry.key });
                        }
                        onEntryChanged: load()
                        Component.onCompleted: load()
                        // A view extension's page (its own view.qml) gets `dotos`: the
                        // palette, the store (tasks, projects, run the CLI), navigation
                        // and toasts — so it looks and acts like a page of this window.
                        onLoaded: if (entry.ext && item && ("dotos" in item)) item.dotos = {
                            palette: App.Console, store: App.Store, nav: App.Nav,
                            say: t => App.Nav.say(t),
                            openTask: uid => App.Nav.openTask(uid),
                            run: (args, then) => App.Store.run(args, "", then)
                        }
                    }

                    // status bar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 26
                        color: appRoot.con.panel
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: appRoot.con.rule }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            spacing: 14
                            Rectangle {
                                implicitWidth: 7; implicitHeight: 7; radius: 3.5
                                color: App.Store.error ? appRoot.con.crit : App.Store.loaded ? appRoot.con.ok : appRoot.con.faint
                            }
                            Text {
                                text: App.Store.error ? App.Store.error : App.Store.loaded ? qsTr("live · %1 tasks · %2 pages").arg(App.Store.tasks.length).arg(App.Store.pages.length) : qsTr("loading…")
                                font.family: appRoot.con.mono; font.pixelSize: 12; color: App.Store.error ? appRoot.con.crit : appRoot.con.dim
                                elide: Text.ElideRight
                                Layout.maximumWidth: 420
                            }
                            Text {
                                visible: !!App.Store.active
                                text: "● " + (App.Store.active?.title ?? "") + " · " + App.Store.dur((App.Store.now / 1000) - (App.Store.active?.since ?? 0))
                                font.family: appRoot.con.mono; font.pixelSize: 12; color: appRoot.con.data
                                elide: Text.ElideRight
                                Layout.maximumWidth: 360
                                TapHandler { onTapped: App.Store.stop() }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                            Text {
                                text: qsTr("%1 tracked today").arg(App.Store.dur(App.Store.time?.today_s))
                                font.family: appRoot.con.mono; font.pixelSize: 12; color: appRoot.con.faint
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: qsTr("%1 agents · %2 need you").arg(App.Store.liveAgents.length).arg(App.Store.needsYou.length)
                                font.family: appRoot.con.mono; font.pixelSize: 12
                                color: App.Store.needsYou.length > 0 ? appRoot.con.crit : appRoot.con.faint
                                TapHandler { onTapped: App.Nav.go("agents") }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                            Text {
                                text: "?"
                                font.family: appRoot.con.mono; font.pixelSize: 12; font.weight: Font.Bold; color: appRoot.con.faint
                                TapHandler { onTapped: appRoot.run("shortcuts") }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }

            App.Palette {
                id: palette
                onClosed: stage.forceActiveFocus()
            }
            App.MoreMenu {
                id: moreMenu
                items: appRoot.menuItems
                onPicked: action => appRoot.run(action)
            }
            App.ShortcutsSheet {
                open: App.Nav.sheet === "shortcuts"
                // the page's own keys first (each list page's keyHelp), then the window's
                shortcuts: (pageLoader.item?.keyHelp ?? []).map(k => ({ label: k[0], keys: k[1], group: qsTr("This page") })).concat(appRoot.shortcuts)
                onClosed: { App.Nav.sheet = ""; stage.forceActiveFocus(); }
            }
            App.Sheet {
                open: App.Nav.sheet === "about"
                title: qsTr("About Dotos")
                icon: "all_inclusive"
                maxWidth: 520
                onClosed: { App.Nav.sheet = ""; stage.forceActiveFocus(); }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Work, agents, life and knowledge in one place.\n\nTasks are VTODO files (your phone reads them through the calendar sync), pages are markdown, projects are your folders, time is timewarrior, agents come from the shell's hooks. Nothing lives only in this window: it is a view onto the dotos CLI, which the terminal, Neovim and the extensions use too.\n\nEvery change is logged with who made it — you, an extension or the AI — and can be undone (Ctrl Z, or History).")
                    font.family: appRoot.con.sans
                    font.pixelSize: 15
                    color: appRoot.con.dim
                    wrapMode: Text.Wrap
                    lineHeight: 1.2
                }
                Text {
                    text: `${App.Store.bin}\n${App.Store.snap?.store ?? ""}\n${App.Store.dataDir}`
                    font.family: appRoot.con.mono
                    font.pixelSize: 12
                    color: appRoot.con.faint
                }
            }

            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 44 }
                z: 200
                visible: opacity > 0
                opacity: App.Nav.toast.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                implicitWidth: Math.min(toastText.implicitWidth + 28, stage.width - 80)
                implicitHeight: 34
                radius: 17
                color: appRoot.con.text
                Text {
                    id: toastText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, stage.width - 108)
                    text: App.Nav.toast
                    elide: Text.ElideRight
                    font.family: appRoot.con.sans
                    font.pixelSize: 15
                    color: appRoot.con.bg
                }
            }
        }
    }
}
