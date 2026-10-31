import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Changes: the repos you and agents work in, as GitHub shows them. Left: a repo, then its
 * working-tree changes, its history (a commit's files) or all its files. Right: the selected
 * file's diff (unified or split, numbered, by hunk) or its text. Edit opens zett at the line,
 * Terminal a zash in the repo. Data: `dotos git repos|changes|diff|log|show|cat|tree`.
 */
Item {
    id: page
    property string key: "changes"

    property var repos: []
    property string repo: ""                  // its path
    property string tab: "changes"            // changes | history | files | remote
    property var files: []                    // what the left list shows (tab's files, or a commit's)
    property var commits: []
    property var commit: null                 // the open commit (history), its files in `files`
    property string sel: ""                   // the selected file's path
    property var fileDiff: null               // the selected file's diff (one file of `dotos git diff`)
    property var text: null                   // the selected file's text (`dotos git cat`)
    property string view: "diff"              // diff | file
    property bool split: false
    property string filter: ""
    property string error: ""
    property int busy: 0

    readonly property var repoInfo: repos.find(r => r.path === repo) || null
    readonly property string rev: commit ? commit.hash : ""
    readonly property var shown: {
        const f = page.filter.toLowerCase();
        return f.length === 0 ? page.files : page.files.filter(x => x.path.toLowerCase().includes(f));
    }

    // ── data ─────────────────────────────────────────────────────────────────
    function git(args, done) {
        const p = runner.createObject(page, { args: [App.Store.bin, "git"].concat(args), done: done });
        page.busy++;
        p.running = true;
    }
    Component {
        id: runner
        Process {
            id: proc
            property var done
            property var args
            command: args
            stdout: StdioCollector {
                onStreamFinished: {
                    page.busy--;
                    let v = null;
                    try { v = JSON.parse(text); } catch (e) { v = { error: qsTr("dotos git gave no answer") }; }
                    if (v && v.error) page.error = v.error; else { page.error = ""; proc.done(v); }
                    proc.destroy();
                }
            }
        }
    }

    function loadRepos() {
        git(["repos"], v => {
            page.repos = v;
            if (!page.repo && v.length > 0) page.openRepo(v[0].path);
        });
    }
    function openRepo(path) {
        page.repo = path;
        page.commit = null;
        page.sel = "";
        page.fileDiff = null;
        page.text = null;
        page.loadTab();
    }
    function loadTab() {
        const r = ["--repo", page.repo];
        if (page.tab === "changes") {
            git(["changes"].concat(r), v => { page.files = v.files; page.pickFirst(); });
        } else if (page.tab === "history") {
            if (page.commit) return;
            page.files = [];
            git(["log", "-n", "200"].concat(r), v => page.commits = v);
        } else if (page.tab === "remote") {
            page.sel = "";
            page.loadRemote();
        } else {
            git(["tree"].concat(r), v => { page.files = v.map(p => ({ path: p, status: "", add: 0, del: 0 })); });
        }
    }
    function openCommit(c) {
        page.commit = c;
        page.sel = "";
        git(["show", c.hash, "--repo", page.repo], v => {
            page.files = v.files.map(f => ({ path: f.path, from: f.from, status: f.status, add: f.add, del: f.del, diff: f }));
            page.commit = Object.assign({}, c, { message: v.message, email: v.email });
            page.pickFirst();
        });
    }
    function pickFirst() {
        if (page.files.length > 0 && !page.files.some(f => f.path === page.sel)) page.select(page.files[0].path);
        else if (page.sel) page.select(page.sel);
    }
    function select(path) {
        page.sel = path;
        const f = page.files.find(x => x.path === path);
        if (page.tab === "files") page.view = "file";
        if (page.view === "file") page.loadText();
        if (f && f.diff) { page.fileDiff = f.diff; return; }
        if (page.tab === "files") return;
        git(["diff", "--repo", page.repo, "--file", path], v => page.fileDiff = v.files.find(x => x.path === path) || v.files[0] || null);
    }
    function loadText() {
        const args = ["cat", page.sel, "--repo", page.repo];
        if (page.rev) args.push("--rev", page.rev);
        git(args, v => page.text = v);
    }
    function move(d) {
        const list = page.tab === "history" && !page.commit ? page.commits : page.shown;
        if (list.length === 0) return;
        if (page.tab === "history" && !page.commit) return;
        const i = Math.max(0, Math.min(list.length - 1, list.findIndex(x => x.path === page.sel) + d));
        page.select(list[i].path);
    }

    // the first changed line (to open zett there)
    function firstLine() {
        const h = page.fileDiff && page.fileDiff.hunks && page.fileDiff.hunks[0];
        if (!h) return 1;
        const l = h.lines.find(x => x.k === "+") || h.lines.find(x => x.n);
        return l && l.n ? l.n : 1;
    }
    // ── commit, pull, push ───────────────────────────────────────────────────
    property var excluded: ({})              // paths left out of the next commit
    readonly property int includedCount: page.files.filter(f => !page.excluded[f.path]).length
    property string notice: ""               // the last commit / push / pull result
    function toggleIncluded(path) {
        const e = Object.assign({}, page.excluded);
        if (e[path]) delete e[path]; else e[path] = true;
        page.excluded = e;
    }
    function doCommit() {
        const msg = msgField.text.trim();
        if (!msg || page.includedCount === 0) return;
        const all = Object.keys(page.excluded).length === 0;
        const args = ["commit", "--repo", page.repo, "-m", msg];
        if (!all) args.push("--", ...page.files.filter(f => !page.excluded[f.path]).map(f => f.path));
        git(args, v => {
            page.notice = qsTr("Committed %1 · %2").arg(v.short).arg(v.subject);
            msgField.text = "";
            page.excluded = {};
            page.loadRepos();
            page.loadTab();
        });
    }
    function sync(push) {
        page.notice = push ? qsTr("Pushing…") : qsTr("Pulling…");
        git([push ? "push" : "pull", "--repo", page.repo], v => {
            page.notice = (push ? qsTr("Pushed") : qsTr("Pulled")) + (v.text ? " · " + v.text.split("\n").pop() : "");
            page.loadRepos();
            page.loadTab();
        });
    }

    // ── the remote (GitHub, GitLab …): pull/merge requests, issues, CI, branches ──
    property var remote: null
    property bool remoteLoading: false
    function loadRemote() {
        page.remoteLoading = true;
        page.remote = null;
        const p = remoteRunner.createObject(page, { args: [App.Store.bin, "git", "remote", page.repo, "--json"] });
        p.running = true;
    }
    Component {
        id: remoteRunner
        Process {
            id: rproc
            property var args
            command: args
            stdout: StdioCollector {
                onStreamFinished: {
                    try { page.remote = JSON.parse(text); } catch (e) { page.remote = { error: qsTr("no answer") }; }
                    page.remoteLoading = false;
                    rproc.destroy();
                }
            }
        }
    }
    readonly property bool isLab: page.remote ? page.remote.provider === "gitlab" : false

    // zett and the shell run in the terminal below (the repo's own zeit session)
    property bool termOpen: false
    property real termHeight: 320
    function edit(line) {
        page.termOpen = true;
        const q = "'" + page.sel.replace(/'/g, "'\\''") + "'";
        terminalView.run("zett " + q + " +" + (line || page.firstLine()));
        terminalView.forceActiveFocus();
    }
    function terminal() {
        page.termOpen = !page.termOpen;
        if (page.termOpen) terminalView.forceActiveFocus(); else page.forceActiveFocus();
    }

    Component.onCompleted: page.loadRepos()

    // rows for the diff list: hunk headers and lines; split pairs removed/added runs side by side
    readonly property var rows: {
        const f = page.fileDiff;
        if (!f || !f.hunks) return [];
        const out = [];
        for (const h of f.hunks) {
            out.push({ t: "hunk", text: h.header });
            if (!page.split) {
                for (const l of h.lines) out.push({ t: "line", k: l.k, o: l.o, n: l.n, text: l.t });
                continue;
            }
            let i = 0;
            const ls = h.lines;
            while (i < ls.length) {
                if (ls[i].k === " " || ls[i].k === "\\") { out.push({ t: "pair", l: ls[i], r: ls[i].k === " " ? ls[i] : null }); i++; continue; }
                const del = [], add = [];
                while (i < ls.length && ls[i].k === "-") del.push(ls[i++]);
                while (i < ls.length && ls[i].k === "+") add.push(ls[i++]);
                for (let j = 0; j < Math.max(del.length, add.length); j++) out.push({ t: "pair", l: del[j] || null, r: add[j] || null });
            }
        }
        return out;
    }

    // ── keys ─────────────────────────────────────────────────────────────────
    focus: true
    // the window asks first (its focus stays on it); the page's own focus comes here too
    Keys.onPressed: e => { if (page.handleKey(e)) e.accepted = true; }
    readonly property var keyHelp: [[qsTr("Files"), ["j", "k"]], [qsTr("Tab"), ["[", "]"]], [qsTr("Repo"), [",", "."]], [qsTr("Split / unified"), ["s"]], [qsTr("Diff / file"), ["v"]], [qsTr("Edit in zett"), ["e"]], [qsTr("Terminal"), ["t"]], [qsTr("Commit message"), ["c"]], [qsTr("Push / pull"), ["P", "p"]], [qsTr("Filter"), ["/"]]]
    function handleKey(e) {
        if (filterField.activeFocus || msgField.activeFocus || terminalView.activeFocus) return false;
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return false;
        if (e.key === Qt.Key_J || e.key === Qt.Key_Down) page.move(1);
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) page.move(-1);
        else if (e.key === Qt.Key_S) page.split = !page.split;
        else if (e.key === Qt.Key_V) { page.view = page.view === "diff" ? "file" : "diff"; if (page.view === "file") page.loadText(); }
        else if (e.key === Qt.Key_E && page.sel) page.edit();
        else if (e.key === Qt.Key_T && page.repo) page.terminal();
        else if (e.key === Qt.Key_R) { page.loadRepos(); page.loadTab(); }
        else if (e.key === Qt.Key_Slash) filterField.forceActiveFocus();
        // [ ] the tab, , . the repo, c the commit message, P push, p pull
        else if (e.key === Qt.Key_BracketLeft || e.key === Qt.Key_BracketRight) { const ks = ["changes", "history", "files", "remote"]; page.tab = ks[(ks.indexOf(page.tab) + (e.key === Qt.Key_BracketRight ? 1 : 3)) % 4]; page.commit = null; page.view = page.tab === "files" ? "file" : "diff"; page.loadTab(); }
        else if ((e.key === Qt.Key_Comma || e.key === Qt.Key_Period) && page.repos.length) { const i = page.repos.findIndex(r => r.path === page.repo); page.openRepo(page.repos[(i + (e.key === Qt.Key_Period ? 1 : page.repos.length - 1)) % page.repos.length].path); }
        else if (e.key === Qt.Key_C && page.tab === "changes") msgField.forceActiveFocus();
        else if (e.key === Qt.Key_P) page.sync(!!(e.modifiers & Qt.ShiftModifier));
        else if (e.key === Qt.Key_Escape && page.commit) { page.commit = null; page.loadTab(); }
        else return false;
        return true;
    }

    // colours of the diff (GitHub's: a tint of the line, a stronger one in the gutter)
    readonly property color addBg: Qt.alpha(App.Console.ok, 0.12)
    readonly property color addGutter: Qt.alpha(App.Console.ok, 0.22)
    readonly property color delBg: Qt.alpha(App.Console.crit, 0.12)
    readonly property color delGutter: Qt.alpha(App.Console.crit, 0.22)
    readonly property color hunkBg: Qt.alpha(App.Console.data, 0.10)
    function count(n, one, many) { return n + " " + (n === 1 ? one : many); }
    function statusColor(s) { return s === "added" ? App.Console.ok : s === "deleted" ? App.Console.crit : s === "renamed" ? App.Console.data : App.Console.warn; }
    function statusLetter(s) { return s === "added" ? "A" : s === "deleted" ? "D" : s === "renamed" ? "R" : s ? "M" : ""; }
    function ago(t) {
        const s = Date.now() / 1000 - t;
        return s < 3600 ? qsTr("%1 min ago").arg(Math.max(1, Math.round(s / 60))) : s < 86400 ? qsTr("%1 h ago").arg(Math.round(s / 3600)) : qsTr("%1 d ago").arg(Math.round(s / 86400));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Changes")
            subtitle: page.repoInfo ? page.repoInfo.path + "  ·  " + page.repoInfo.branch : qsTr("your repos and what changed in them")
            Ui.IconButton { icon: "download"; tooltip: page.repoInfo && page.repoInfo.behind > 0 ? qsTr("Pull %1 commit(s)").arg(page.repoInfo.behind) : qsTr("Pull"); onClicked: page.sync(false) }
            Ui.IconButton { icon: "upload"; active: !!page.repoInfo && page.repoInfo.ahead > 0; tooltip: page.repoInfo && page.repoInfo.ahead > 0 ? qsTr("Push %1 commit(s)").arg(page.repoInfo.ahead) : qsTr("Push"); onClicked: page.sync(true) }
            Ui.IconButton { icon: "terminal"; tooltip: qsTr("Terminal in this repo (T)"); onClicked: page.terminal() }
            Ui.IconButton { icon: "refresh"; tooltip: qsTr("Reload (R)"); onClicked: { page.loadRepos(); page.loadTab(); } }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── left: repo, tabs, list ───────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                color: App.Console.panel
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    ComboBox {
                        id: repoBox
                        Layout.fillWidth: true
                        implicitHeight: 30
                        model: page.repos
                        textRole: "name"
                        currentIndex: page.repos.findIndex(r => r.path === page.repo)
                        onActivated: i => page.openRepo(page.repos[i].path)
                        font.family: App.Console.sans; font.pixelSize: 13
                        // the shell's own surface, not the default white box
                        background: Rectangle { radius: App.Console.radiusSmall; color: repoBox.hovered ? Qt.alpha(App.Console.text, 0.08) : Qt.alpha(App.Console.text, 0.05) }
                        contentItem: Text {
                            leftPadding: 10; rightPadding: 28
                            text: repoBox.displayText
                            font: repoBox.font
                            color: App.Console.text
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        indicator: Ui.Icon {
                            x: repoBox.width - width - 6; y: (repoBox.height - height) / 2
                            text: "expand_more"; size: 16; color: App.Console.dim
                        }
                        popup: Popup {
                            y: repoBox.height + 4
                            width: repoBox.width
                            padding: 4
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: repoBox.popup.visible ? repoBox.delegateModel : null
                                currentIndex: repoBox.highlightedIndex
                            }
                            background: Rectangle { radius: App.Console.radiusSmall; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }
                        }
                        delegate: ItemDelegate {
                            required property var modelData
                            width: repoBox.width
                            contentItem: RowLayout {
                                spacing: 8
                                Text { text: modelData.name; color: App.Console.text; font.family: App.Console.sans; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { visible: modelData.changed > 0; text: modelData.changed; color: App.Console.warn; font.family: App.Console.mono; font.pixelSize: 11 }
                                Text { text: modelData.branch; color: App.Console.dim; font.family: App.Console.mono; font.pixelSize: 11 }
                            }
                            background: Rectangle { color: highlighted ? App.Console.panelAlt : App.Console.panel }
                        }
                    }

                    Ui.SegmentedControl {
                        Layout.fillWidth: true
                        model: [
                            { key: "changes", label: page.repoInfo ? qsTr("Changes %1").arg(page.repoInfo.changed) : qsTr("Changes") },
                            { key: "history", label: qsTr("History") },
                            { key: "files", label: qsTr("Files") },
                            { key: "remote", label: page.isLab ? "GitLab" : page.remote && page.remote.provider === "github" ? "GitHub" : qsTr("Remote") }]
                        current: page.tab
                        onPicked: k => { page.tab = k; page.commit = null; page.view = k === "files" ? "file" : "diff"; page.loadTab(); }
                    }

                    // the open commit: back, its message
                    Rectangle {
                        visible: page.commit !== null
                        Layout.fillWidth: true
                        implicitHeight: commitCol.implicitHeight + 16
                        radius: App.Console.radiusSmall
                        color: App.Console.panelAlt
                        ColumnLayout {
                            id: commitCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 4
                            RowLayout {
                                Ui.IconButton { icon: "arrow_back"; tooltip: qsTr("Back to history (Esc)"); onClicked: { page.commit = null; page.loadTab(); } }
                                Text { text: page.commit ? page.commit.short : ""; color: App.Console.data; font.family: App.Console.mono; font.pixelSize: 12 }
                                Text { Layout.fillWidth: true; text: page.commit ? page.commit.author + " · " + page.ago(page.commit.time) : ""; color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 11; elide: Text.ElideRight }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: page.commit ? (page.commit.message || page.commit.subject) : ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 6
                                elide: Text.ElideRight
                                color: App.Console.text; font.family: App.Console.sans; font.pixelSize: 12
                            }
                        }
                    }

                    TextField {
                        ContextMenu.menu: Ui.TextMenu { target: filterField }
                        id: filterField
                        Layout.fillWidth: true
                        visible: !(page.tab === "history" && !page.commit) && page.tab !== "remote"
                        placeholderText: qsTr("Filter files  /")
                        placeholderTextColor: App.Console.faint
                        text: page.filter
                        onTextChanged: page.filter = text
                        Keys.onEscapePressed: { text = ""; page.forceActiveFocus(); }
                        font.family: App.Console.mono; font.pixelSize: 12
                        color: App.Console.text
                        leftPadding: 10; rightPadding: 10
                        implicitHeight: 28
                        background: Rectangle { radius: 14; color: Qt.alpha(App.Console.text, 0.05); border.width: filterField.activeFocus ? 1 : 0; border.color: App.Console.data }
                    }

                    // files
                    ListView {
                        id: fileList
                        visible: !(page.tab === "history" && !page.commit) && page.tab !== "remote"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: page.shown
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        currentIndex: page.shown.findIndex(f => f.path === page.sel)
                        highlightMoveDuration: 0
                        delegate: Rectangle {
                            id: fileRow
                            required property var modelData
                            readonly property bool on: modelData.path === page.sel
                            readonly property int slash: modelData.path.lastIndexOf("/")
                            width: fileList.width
                            height: 28
                            radius: App.Console.radiusSmall
                            color: on ? App.Console.panelAlt : hover.hovered ? Qt.alpha(App.Console.panelAlt, 0.5) : "transparent"
                            HoverHandler { id: hover }
                            TapHandler { onTapped: { page.select(fileRow.modelData.path); page.forceActiveFocus(); } }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                spacing: 6
                                // in the next commit or not (Changes only)
                                Rectangle {
                                    visible: page.tab === "changes"
                                    readonly property bool inc: !page.excluded[fileRow.modelData.path]
                                    width: 14; height: 14; radius: 3
                                    color: inc ? App.Console.data : "transparent"
                                    border.color: inc ? App.Console.data : App.Console.dim
                                    Text { anchors.centerIn: parent; visible: parent.inc; text: "✓"; color: App.Console.onData; font.pixelSize: 10; font.weight: Font.Bold }
                                    TapHandler { onTapped: page.toggleIncluded(fileRow.modelData.path) }
                                }
                                Text { visible: text.length > 0; text: page.statusLetter(fileRow.modelData.status); color: page.statusColor(fileRow.modelData.status); font.family: App.Console.mono; font.pixelSize: 11; font.weight: Font.Bold }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideLeft
                                    textFormat: Text.StyledText
                                    // the name bright, its folder quiet
                                    text: '<font color="' + App.Console.dim + '">' + fileRow.modelData.path.slice(0, fileRow.slash + 1) + '</font>' + fileRow.modelData.path.slice(fileRow.slash + 1)
                                    color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 12
                                }
                                Text { visible: fileRow.modelData.add > 0; text: "+" + fileRow.modelData.add; color: App.Console.ok; font.family: App.Console.mono; font.pixelSize: 11 }
                                Text { visible: fileRow.modelData.del > 0; text: "−" + fileRow.modelData.del; color: App.Console.crit; font.family: App.Console.mono; font.pixelSize: 11 }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: page.shown.length === 0 && page.busy === 0
                            text: page.tab === "changes" ? qsTr("Working tree clean") : qsTr("No files")
                            color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 13
                        }
                    }

                    // (the Remote tab shows its content on the right: the column keeps its top)
                    // where this branch stands against its upstream, and the two moves
                    ColumnLayout {
                        visible: page.tab === "remote" && !!page.repoInfo
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 8
                        RowLayout {
                            spacing: 8
                            Ui.Icon { text: "fork_right"; size: 18; color: App.Console.data }
                            Text { text: page.repoInfo ? page.repoInfo.branch : ""; color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 14; font.weight: Font.DemiBold }
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: !page.repoInfo ? "" : page.repoInfo.ahead === 0 && page.repoInfo.behind === 0 ? qsTr("Up to date with its upstream") : [page.repoInfo.ahead > 0 ? page.count(page.repoInfo.ahead, qsTr("commit"), qsTr("commits")) + qsTr(" to push") : "", page.repoInfo.behind > 0 ? page.count(page.repoInfo.behind, qsTr("commit"), qsTr("commits")) + qsTr(" to pull") : ""].filter(x => x).join(" · ")
                            color: page.repoInfo && (page.repoInfo.ahead > 0 || page.repoInfo.behind > 0) ? App.Console.warn : App.Console.dim
                            font.family: App.Console.sans; font.pixelSize: 13
                        }
                        Text {
                            visible: !!page.repoInfo && page.repoInfo.changed > 0
                            Layout.fillWidth: true
                            text: page.count(page.repoInfo ? page.repoInfo.changed : 0, qsTr("uncommitted change"), qsTr("uncommitted changes"))
                            color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 13
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Button { Layout.fillWidth: true; text: page.repoInfo && page.repoInfo.behind > 0 ? qsTr("Pull %1").arg(page.repoInfo.behind) : qsTr("Pull"); enabled: page.busy === 0; onClicked: page.sync(false) }
                            Button { Layout.fillWidth: true; text: page.repoInfo && page.repoInfo.ahead > 0 ? qsTr("Push %1").arg(page.repoInfo.ahead) : qsTr("Push"); enabled: page.busy === 0; highlighted: !!page.repoInfo && page.repoInfo.ahead > 0; onClicked: page.sync(true) }
                        }
                        Text {
                            visible: page.notice.length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: page.notice
                            color: App.Console.dim; font.family: App.Console.mono; font.pixelSize: 11
                        }
                    }
                    Item { visible: page.tab === "remote"; Layout.fillHeight: true }

                    // commit what is ticked, then push (as GitHub Desktop does it)
                    ColumnLayout {
                        visible: page.tab === "changes" && page.files.length > 0
                        Layout.fillWidth: true
                        spacing: 6
                        TextArea {
                            ContextMenu.menu: Ui.TextMenu { target: msgField }
                            id: msgField
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(56, Math.min(120, contentHeight + 16))
                            placeholderText: qsTr("Commit message (Ctrl+Enter commits)")
                            wrapMode: TextEdit.Wrap
                            color: App.Console.text
                            font.family: App.Console.sans; font.pixelSize: 13
                            background: Rectangle { radius: App.Console.radiusSmall; color: App.Console.bg; border.color: msgField.activeFocus ? App.Console.data : App.Console.rule }
                            Keys.onPressed: e => {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) { page.doCommit(); e.accepted = true; }
                                else if (e.key === Qt.Key_Escape) { page.forceActiveFocus(); e.accepted = true; }
                            }
                        }
                        Button {
                            Layout.fillWidth: true
                            enabled: msgField.text.trim().length > 0 && page.includedCount > 0 && page.busy === 0
                            text: qsTr("Commit %1 to %2").arg(page.count(page.includedCount, qsTr("file"), qsTr("files"))).arg(page.repoInfo ? page.repoInfo.branch : "")
                            onClicked: page.doCommit()
                        }
                    }

                    // commits
                    ListView {
                        id: commitList
                        visible: page.tab === "history" && !page.commit
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: page.commits
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: cRow
                            required property var modelData
                            width: commitList.width
                            height: 50
                            radius: App.Console.radiusSmall
                            color: cHover.hovered ? App.Console.panelAlt : "transparent"
                            HoverHandler { id: cHover }
                            TapHandler { onTapped: page.openCommit(cRow.modelData) }
                            ColumnLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 6; bottomMargin: 6 }
                                spacing: 2
                                Text { Layout.fillWidth: true; text: cRow.modelData.subject; elide: Text.ElideRight; color: App.Console.text; font.family: App.Console.sans; font.pixelSize: 13 }
                                RowLayout {
                                    spacing: 8
                                    Text { text: cRow.modelData.short; color: App.Console.data; font.family: App.Console.mono; font.pixelSize: 11 }
                                    Text { text: cRow.modelData.author + " · " + page.ago(cRow.modelData.time); color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "+" + cRow.modelData.add; color: App.Console.ok; font.family: App.Console.mono; font.pixelSize: 11 }
                                    Text { text: "−" + cRow.modelData.del; color: App.Console.crit; font.family: App.Console.mono; font.pixelSize: 11 }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: App.Console.rule }

            // ── right: the file ──────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // its header: path, counts, view switches, actions
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    color: App.Console.bg
                    visible: page.sel.length > 0
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: (page.fileDiff && page.fileDiff.from && page.view === "diff" ? page.fileDiff.from + "  →  " : "") + page.sel
                            elide: Text.ElideLeft
                            color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text { visible: page.view === "diff" && !!page.fileDiff; text: page.fileDiff ? "+" + page.fileDiff.add : ""; color: App.Console.ok; font.family: App.Console.mono; font.pixelSize: 12 }
                        Text { visible: page.view === "diff" && !!page.fileDiff; text: page.fileDiff ? "−" + page.fileDiff.del : ""; color: App.Console.crit; font.family: App.Console.mono; font.pixelSize: 12 }
                        Ui.SegmentedControl {
                            visible: page.tab !== "files"
                            implicitWidth: 150
                            model: [{ key: "diff", label: qsTr("Diff") }, { key: "file", label: qsTr("File") }]
                            current: page.view
                            onPicked: k => { page.view = k; if (k === "file") page.loadText(); }
                        }
                        Ui.SegmentedControl {
                            visible: page.view === "diff"
                            implicitWidth: 170
                            model: [{ key: "unified", label: qsTr("Unified") }, { key: "split", label: qsTr("Split") }]
                            current: page.split ? "split" : "unified"
                            onPicked: k => page.split = k === "split"
                        }
                        Ui.IconButton { icon: "content_copy"; tooltip: qsTr("Copy path"); onClicked: Quickshell.execDetached(["wl-copy", page.repo + "/" + page.sel]) }
                        Ui.IconButton { icon: "edit"; tooltip: qsTr("Edit in zett at the change (E)"); onClicked: page.edit() }
                    }
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: App.Console.rule }
                }

                // the diff
                ListView {
                    id: diffList
                    visible: page.view === "diff" && page.sel.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: page.rows
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    ScrollBar.horizontal: ScrollBar {}
                    contentWidth: Math.max(width, page.split ? width : 1400)
                    flickableDirection: Flickable.AutoFlickDirection
                    readonly property int gutter: 52
                    delegate: Item {
                        id: row
                        required property var modelData
                        width: diffList.contentWidth
                        height: 20

                        // a hunk header
                        Rectangle {
                            visible: row.modelData.t === "hunk"
                            anchors.fill: parent
                            color: page.hunkBg
                            Text { anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: diffList.gutter * 2 + 10 } text: row.modelData.text || ""; color: App.Console.data; font.family: App.Console.mono; font.pixelSize: 12 }
                        }

                        // a unified line: old no. | new no. | sign text
                        Row {
                            visible: row.modelData.t === "line"
                            anchors.fill: parent
                            readonly property string k: row.modelData.k || " "
                            Rectangle {
                                width: diffList.gutter; height: parent.height
                                color: parent.k === "+" ? page.addGutter : parent.k === "-" ? page.delGutter : "transparent"
                                Text { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: row.modelData.o ?? ""; color: App.Console.faint; font.family: App.Console.mono; font.pixelSize: 11 }
                            }
                            Rectangle {
                                width: diffList.gutter; height: parent.height
                                color: parent.k === "+" ? page.addGutter : parent.k === "-" ? page.delGutter : "transparent"
                                Text { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: row.modelData.n ?? ""; color: App.Console.faint; font.family: App.Console.mono; font.pixelSize: 11 }
                                TapHandler { onTapped: if (row.modelData.n) page.edit(row.modelData.n) }
                            }
                            Rectangle {
                                width: row.width - diffList.gutter * 2; height: parent.height
                                color: parent.k === "+" ? page.addBg : parent.k === "-" ? page.delBg : "transparent"
                                Text {
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    text: (row.modelData.k === "\\" ? "" : (row.modelData.k === " " ? "  " : row.modelData.k + " ")) + (row.modelData.text || "")
                                    color: row.modelData.k === "\\" ? App.Console.dim : App.Console.text
                                    font.family: App.Console.mono; font.pixelSize: 12
                                    textFormat: Text.PlainText
                                }
                            }
                        }

                        // a split line: old side | new side
                        Row {
                            visible: row.modelData.t === "pair"
                            anchors.fill: parent
                            Repeater {
                                model: [row.modelData.l, row.modelData.r]
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    readonly property var line: modelData
                                    readonly property bool changed: !!line && line.k !== " " && line.k !== "\\"
                                    readonly property color tint: !line ? Qt.alpha(App.Console.faint, 0.06) : !changed ? "transparent" : index === 0 ? page.delBg : page.addBg
                                    width: diffList.width / 2
                                    height: row.height
                                    Rectangle {
                                        width: diffList.gutter; height: parent.height
                                        color: parent.changed ? (parent.index === 0 ? page.delGutter : page.addGutter) : parent.tint
                                        Text { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: parent.parent.line ? (parent.parent.index === 0 ? parent.parent.line.o : parent.parent.line.n) ?? "" : ""; color: App.Console.faint; font.family: App.Console.mono; font.pixelSize: 11 }
                                    }
                                    Rectangle {
                                        width: parent.width - diffList.gutter; height: parent.height
                                        color: parent.tint
                                        clip: true
                                        Text {
                                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                            text: parent.parent.line ? parent.parent.line.t : ""
                                            color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 12
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: page.rows.length === 0 && page.busy === 0
                        text: page.fileDiff && page.fileDiff.binary ? qsTr("Binary file — no text to compare") : page.fileDiff && page.fileDiff.status === "renamed" ? qsTr("Renamed, content unchanged") : qsTr("No differences")
                        color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 13
                    }
                }

                // the file's text
                ListView {
                    id: textList
                    visible: page.view === "file" && page.sel.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: page.text && !page.text.binary ? page.text.lines : []
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    ScrollBar.horizontal: ScrollBar {}
                    contentWidth: Math.max(width, 1400)
                    flickableDirection: Flickable.AutoFlickDirection
                    delegate: Row {
                        id: tRow
                        required property var modelData
                        required property int index
                        height: 20
                        Rectangle {
                            width: 60; height: parent.height
                            color: "transparent"
                            Text { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: tRow.index + 1; color: App.Console.faint; font.family: App.Console.mono; font.pixelSize: 11 }
                            TapHandler { onTapped: page.edit(tRow.index + 1) }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: tRow.modelData; color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 12; textFormat: Text.PlainText }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !!page.text && (page.text.binary || page.text.lines.length === 0)
                        text: page.text && page.text.binary ? qsTr("Binary file (%1 bytes)").arg(page.text.size) : qsTr("Empty file")
                        color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 13
                    }
                }

                // the remote: its requests, issues, CI and branches, each opening in the browser
                Flickable {
                    id: remoteView
                    visible: page.tab === "remote"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: remoteCol.implicitHeight + 28
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    readonly property var r: page.remote
                    function open(url) { if (url) Qt.openUrlExternally(url); }
                    function when(s) { const t = Date.parse(s); return isNaN(t) ? (s || "") : page.ago(t / 1000); }
                    // one row of a section: icon and its colour, title, detail, the right side, where it opens
                    function rowOf(kind, d) {
                        const C = App.Console;
                        if (kind === "pr") return { icon: d.draft ? "draft" : "merge", tone: d.draft ? C.dim : C.ok, title: "#" + d.number + "  " + d.title,
                            detail: d.author + "  ·  " + d.branch + " → " + d.base + (d.review_state ? "  ·  " + d.review_state : "") + (d.comments ? "  ·  " + page.count(d.comments, qsTr("comment"), qsTr("comments")) : ""), right: when(d.updated), url: d.url };
                        if (kind === "ci") {
                            const r = d.conclusion || d.status, ok = r === "success", bad = r === "failure" || r === "failed";
                            return { icon: ok ? "check_circle" : bad ? "cancel" : "pending", tone: ok ? C.ok : bad ? C.crit : C.warn, title: d.name,
                                detail: d.branch + "  ·  " + r + (d.duration_s ? "  ·  " + Math.max(1, Math.round(d.duration_s / 60)) + " min" : ""), right: when(d.created), url: d.url };
                        }
                        if (kind === "issue") return { icon: "radio_button_unchecked", tone: C.ok, title: "#" + d.number + "  " + d.title,
                            detail: d.author + (d.labels && d.labels.length ? "  ·  " + d.labels.join(", ") : "") + (d.assignee ? "  ·  → " + d.assignee : ""), right: when(d.updated), url: d.url };
                        if (kind === "commit") return { icon: "commit", tone: C.data, title: (d.message || "").split("\n")[0], detail: (d.hash || "").slice(0, 7) + "  ·  " + d.author, right: when(d.date), url: d.url };
                        return { icon: d.protected ? "lock" : "fork_right", tone: C.data, title: d.name, detail: (d.commit || "").slice(0, 7), right: "", url: "" };
                    }
                    ColumnLayout {
                        id: remoteCol
                        x: 14; y: 14
                        width: remoteView.width - 28
                        spacing: 12

                        Text {
                            visible: page.remoteLoading || !remoteView.r || !!remoteView.r.error
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: page.remoteLoading ? qsTr("Asking %1…").arg(page.repoInfo ? page.repoInfo.name : "the remote") : remoteView.r && remoteView.r.error ? (remoteView.r.error === "no remote detected" ? qsTr("This repo has no remote (origin) yet.") : remoteView.r.error) : ""
                            color: remoteView.r && remoteView.r.error ? App.Console.crit : App.Console.dim
                            font.family: App.Console.sans; font.pixelSize: 13
                        }

                        // the repo on its host
                        RowLayout {
                            visible: !!remoteView.r && !remoteView.r.error && !page.remoteLoading
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: remoteView.r ? remoteView.r.owner + " / " + remoteView.r.repo : ""; color: App.Console.text; font.family: App.Console.sans; font.pixelSize: 17; font.weight: Font.DemiBold }
                            App.Tag { text: remoteView.r ? remoteView.r.host : ""; tone: App.Console.dim }
                            Item { Layout.fillWidth: true }
                            Button { text: page.isLab ? qsTr("Open on GitLab") : qsTr("Open on GitHub"); onClicked: remoteView.open(remoteView.r.url.replace(/\.git$/, "").replace(/^git@([^:]+):/, "https://$1/")) }
                        }
                        // what could not be fetched, and why
                        Repeater {
                            model: remoteView.r && remoteView.r.errors ? remoteView.r.errors : []
                            delegate: Text {
                                required property var modelData
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: modelData + (modelData.includes("401") ? qsTr("  — not signed in: run `gh auth login` (GitHub) or `glab auth login` (GitLab)") : "")
                                color: App.Console.warn; font.family: App.Console.mono; font.pixelSize: 12
                            }
                        }
                        Text {
                            visible: !!remoteView.r && !remoteView.r.error && !remoteView.r.authenticated
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: qsTr("No login for this host. `gh auth login` (GitHub) or `glab auth login` (GitLab) once, and Dotos uses it.")
                            color: App.Console.warn; font.family: App.Console.sans; font.pixelSize: 13
                        }

                        // the sections: a title with its count, then rows (each opens on the host)
                        Repeater {
                            model: [
                                { kind: "pr", title: page.isLab ? qsTr("Merge requests") : qsTr("Pull requests"), icon: "merge", key: "pull_requests", empty: page.isLab ? qsTr("No open merge requests") : qsTr("No open pull requests") },
                                { kind: "ci", title: qsTr("CI"), icon: "play_circle", key: "ci_runs", empty: qsTr("No CI runs") },
                                { kind: "issue", title: qsTr("Issues"), icon: "error", key: "issues", empty: qsTr("No open issues") },
                                { kind: "commit", title: qsTr("Latest on the remote"), icon: "history", key: "commits", empty: qsTr("No commits") },
                                { kind: "branch", title: qsTr("Branches"), icon: "account_tree", key: "branches", empty: qsTr("No branches") }]
                            delegate: App.Panel {
                                id: sec
                                required property var modelData
                                readonly property var rows: remoteView.r && remoteView.r[modelData.key] ? remoteView.r[modelData.key].slice(0, 15) : []
                                Layout.fillWidth: true
                                visible: !!remoteView.r && !remoteView.r.error && !page.remoteLoading
                                title: modelData.title
                                icon: modelData.icon
                                note: String(remoteView.r && remoteView.r[modelData.key] ? remoteView.r[modelData.key].length : 0)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { visible: sec.rows.length === 0; text: sec.modelData.empty; color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 13 }
                                    Repeater {
                                        model: sec.rows
                                        delegate: Rectangle {
                                            id: rr
                                            required property var modelData
                                            readonly property var v: remoteView.rowOf(sec.modelData.kind, modelData)
                                            Layout.fillWidth: true
                                            implicitHeight: 40
                                            radius: App.Console.radiusSmall
                                            color: rrHover.hovered ? App.Console.panelAlt : "transparent"
                                            HoverHandler { id: rrHover; cursorShape: rr.v.url ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                            TapHandler { onTapped: remoteView.open(rr.v.url) }
                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                spacing: 10
                                                Ui.Icon { text: rr.v.icon; size: 18; color: rr.v.tone }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    Text { Layout.fillWidth: true; text: rr.v.title; elide: Text.ElideRight; color: App.Console.text; font.family: App.Console.sans; font.pixelSize: 13 }
                                                    Text { Layout.fillWidth: true; visible: text.length > 0; text: rr.v.detail; elide: Text.ElideRight; color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 11 }
                                                }
                                                Text { text: rr.v.right; color: App.Console.dim; font.family: App.Console.mono; font.pixelSize: 11 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // nothing selected, or an error
                Item {
                    visible: page.sel.length === 0 && page.tab !== "remote"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 40, 520)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: page.error ? page.error : page.repos.length === 0 && page.busy === 0 ? qsTr("No git repos found in your projects or agent work.") : page.tab === "history" ? qsTr("Pick a commit to see what it changed.") : qsTr("Pick a file.")
                        color: page.error ? App.Console.crit : App.Console.dim
                        font.family: App.Console.sans; font.pixelSize: 13
                    }
                }

                // the terminal: a drag handle, then the repo's shell
                Rectangle {
                    visible: page.termOpen
                    Layout.fillWidth: true
                    implicitHeight: 28
                    color: App.Console.panel
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 6 }
                        spacing: 8
                        Text { text: "terminal"; color: App.Console.data; font.family: App.Console.mono; font.pixelSize: 11 }
                        Text { Layout.fillWidth: true; text: terminalView.title || page.repo; elide: Text.ElideLeft; color: App.Console.dim; font.family: App.Console.mono; font.pixelSize: 11 }
                        Ui.IconButton { icon: "close"; tooltip: qsTr("Hide the terminal (it keeps running)"); onClicked: page.terminal() }
                    }
                    // drag to make it taller or shorter
                    MouseArea {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 6
                        cursorShape: Qt.SizeVerCursor
                        property real y0: 0
                        onPressed: m => y0 = m.y
                        onPositionChanged: m => page.termHeight = Math.max(120, Math.min(page.height - 200, page.termHeight - (m.y - y0)))
                    }
                }
                App.TerminalView {
                    id: terminalView
                    visible: page.termOpen
                    dir: page.repo
                    Layout.fillWidth: true
                    Layout.preferredHeight: page.termHeight
                    Layout.margins: 6
                }

                // keys
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    color: App.Console.bg
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: (page.notice ? page.notice + "   ·   " : "") + qsTr("j/k files · [ ] tab · , . repo · s split · v diff/file · e zett · t terminal · c commit · P push · p pull · / filter") + (page.busy > 0 ? qsTr("   · loading…") : "")
                        color: App.Console.faint; font.family: App.Console.mono; font.pixelSize: 11
                    }
                }
            }
        }
    }
}
