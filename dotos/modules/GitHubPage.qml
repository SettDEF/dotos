import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * GitHub: a repository as github.com shows it, through `gh` (already signed in on these
 * machines; it does everything the site does, as JSON). The repo picker lists your projects
 * with a GitHub remote, or takes owner/name. Tabs: Code (the README, the files; a file of a
 * local clone opens in zett, in the page), Issues, Pull requests, Actions, Commits, Branches.
 * Lists look like GitHub's: state icon, title, label pills, #n by who, when, comments.
 * A row opens beside the list with its body and comments; right click has what the site's
 * menus have (open, copy, check out, merge, close, reopen, comment, assign, re-run).
 */
Item {
    id: page
    property string key: "github"

    // ── which repository ─────────────────────────────────────────────────────
    /// "owner/name"
    property string repo: ""
    /// the local clone of it, if one of the projects is ("" when none)
    readonly property string localPath: {
        const p = page.localRepos.find(r => r.slug.toLowerCase() === page.repo.toLowerCase());
        return p ? p.path : "";
    }
    /// projects with a GitHub remote: [{ slug, path, name }]
    readonly property var localRepos: {
        const out = [];
        for (const p of App.Store.projects ?? []) {
            const m = /github\.com[:/]([^/\s]+)\/([^/\s]+?)(\.git)?$/.exec(p.git?.remote_url ?? "");
            if (m) out.push({ slug: m[1] + "/" + m[2], path: p.path, name: p.name });
        }
        return out;
    }
    /// the last one, else the open project's, else the first: once the preferences and the
    /// projects have loaded (both come after the page)
    function pick() {
        // the saved one first: wait for the preferences (they load after the window is up)
        if (page.repo || !(App.Prefs.loaded ?? true)) return;
        const fromProject = page.localRepos.find(r => r.name === App.Nav.project);
        page.repo = App.Prefs.githubRepo || (fromProject ?? page.localRepos[0])?.slug || "";
    }
    Component.onCompleted: page.pick()
    onLocalReposChanged: page.pick()
    // (Prefs.loaded: SettDEF/dotos#2; without it the page does not wait)
    Connections { target: App.Prefs; ignoreUnknownSignals: true; function onGithubRepoChanged() { page.pick(); } function onLoadedChanged() { page.pick(); } }
    onRepoChanged: { if (page.repo) App.Prefs.githubRepo = page.repo; page.selected = null; page.path = ""; page.readme = ""; page.refresh(); }

    // ── what is shown ────────────────────────────────────────────────────────
    property string tab: "pulls"            // code | issues | pulls | actions | commits | branches
    property string state: "open"           // open | closed (issues, pulls)
    property string filter: ""
    property var info: null                 // gh repo view
    property var issues: []
    property var pulls: []
    property var runs: []
    property var commits: []
    property var branches: []
    property var files: []                  // the folder at `path` (Code)
    property string path: ""
    property string readme: ""
    property string fileText: ""            // a file shown read-only (no local clone)
    property string fileName: ""
    property var selected: null             // the open issue / pull request (its list entry)
    property var detail: null               // gh issue/pr view of it
    property int busy: 0
    property string error: ""
    property string notice: ""
    property string cur: ""                 // keyboard: the row at hand (its number / id)
    property bool termOpen: false
    property real termHeight: 300

    onTabChanged: { page.selected = null; page.load(page.tab); }
    onStateChanged: page.load(page.tab)

    // ── gh ───────────────────────────────────────────────────────────────────
    /// runs `gh args…` (in `dir` when given); then(code, stdout, stderr)
    function gh(args, then, dir) {
        page.busy++;
        const p = ghCall.createObject(page, { command: ["gh"].concat(args), workingDirectory: dir || "", then: then });
        p.running = true;
    }
    Component {
        id: ghCall
        Process {
            id: proc
            property var then: null
            property int ends: 0
            property int code: 0
            function finish() {
                if (++proc.ends < 3) return;
                page.busy = Math.max(0, page.busy - 1);
                if (proc.then) proc.then(proc.code, out.text, err.text);
                proc.destroy();
            }
            stdout: StdioCollector { id: out; onStreamFinished: proc.finish() }
            stderr: StdioCollector { id: err; onStreamFinished: proc.finish() }
            onExited: code => { proc.code = code; proc.finish(); }
        }
    }
    /// gh's JSON, or `fallback` (the error said, once)
    function json(code, text, err, fallback) {
        if (code !== 0) { page.error = (err || "").trim().split("\n").pop() || qsTr("gh failed"); return fallback; }
        try { page.error = ""; return JSON.parse(text); } catch (e) { return fallback; }
    }
    /// an action: say what happened, then load the tab (and the open item) again
    function act(args, okText, dir) {
        page.gh(args, (code, out, err) => {
            page.notice = code === 0 ? okText : ((err || "").trim().split("\n").pop() || qsTr("failed"));
            page.load(page.tab);
            if (page.selected) page.open(page.selected);
        }, dir);
    }

    function refresh() {
        if (!page.repo) return;
        page.gh(["repo", "view", page.repo, "--json", "name,owner,description,stargazerCount,forkCount,watchers,isPrivate,isFork,defaultBranchRef,url,issues,pullRequests,homepageUrl"],
            (c, o, e) => page.info = page.json(c, o, e, null));
        // the counts in the tabs: both lists, whatever is shown
        page.load("issues"); page.load("pulls");
        if (page.tab !== "issues" && page.tab !== "pulls") page.load(page.tab);
    }
    function load(which) {
        if (!page.repo) return;
        const R = ["-R", page.repo];
        switch (which) {
        case "issues":
            page.gh(["issue", "list"].concat(R, ["--state", page.state, "-L", "100", "--json", "number,title,state,labels,author,createdAt,updatedAt,comments,assignees,url"]),
                (c, o, e) => page.issues = page.json(c, o, e, []));
            break;
        case "pulls":
            page.gh(["pr", "list"].concat(R, ["--state", page.state === "open" ? "open" : "closed", "-L", "100", "--json", "number,title,state,isDraft,labels,author,createdAt,updatedAt,comments,assignees,reviewDecision,statusCheckRollup,headRefName,baseRefName,url,mergedAt"]),
                (c, o, e) => page.pulls = page.json(c, o, e, []));
            break;
        case "actions":
            page.gh(["run", "list"].concat(R, ["-L", "40", "--json", "databaseId,displayTitle,workflowName,status,conclusion,headBranch,event,createdAt,url,number"]),
                (c, o, e) => page.runs = page.json(c, o, e, []));
            break;
        case "commits":
            page.gh(["api", "repos/" + page.repo + "/commits?per_page=50"], (c, o, e) => page.commits = page.json(c, o, e, []));
            break;
        case "branches":
            page.gh(["api", "repos/" + page.repo + "/branches?per_page=100"], (c, o, e) => page.branches = page.json(c, o, e, []));
            break;
        case "code":
            page.openPath(page.path);
            if (!page.readme) page.gh(["api", "repos/" + page.repo + "/readme", "-H", "Accept: application/vnd.github.raw"], (c, o) => page.readme = c === 0 ? o : "");
            break;
        }
    }
    function openPath(p) {
        page.path = p; page.fileText = ""; page.fileName = "";
        page.gh(["api", "repos/" + page.repo + "/contents/" + p], (c, o, e) => {
            const l = page.json(c, o, e, []);
            page.files = Array.isArray(l) ? l.sort((a, b) => (a.type === "dir" ? 0 : 1) - (b.type === "dir" ? 0 : 1) || a.name.localeCompare(b.name)) : [];
        });
    }
    /// a file: in zett when there is a clone here, else read-only from GitHub
    function openFile(f) {
        if (page.localPath) { page.zett(f.path); return; }
        page.fileName = f.path;
        page.gh(["api", "repos/" + page.repo + "/contents/" + f.path, "-H", "Accept: application/vnd.github.raw"], (c, o) => page.fileText = c === 0 ? o : qsTr("Could not read it."));
    }
    /// zett on `file` (relative to the clone), in the terminal under the page
    function zett(file) {
        if (!page.localPath) { page.notice = qsTr("No local clone of %1: clone it to edit in zett").arg(page.repo); return; }
        page.termOpen = true;
        Qt.callLater(() => terminal.send(App.Store.zett + " '" + String(file).replace(/'/g, "'\\''") + "'\r"));
    }
    function open(item) {
        page.selected = item;
        page.detail = null;
        const pr = page.tab === "pulls";
        const fields = pr ? "number,title,state,isDraft,body,author,createdAt,comments,reviews,labels,assignees,files,statusCheckRollup,mergeable,reviewDecision,headRefName,baseRefName,url,additions,deletions,commits"
                          : "number,title,state,body,author,createdAt,comments,labels,assignees,url";
        page.gh([pr ? "pr" : "issue", "view", String(item.number), "-R", page.repo, "--json", fields], (c, o, e) => page.detail = page.json(c, o, e, null));
    }

    // ── how things look ──────────────────────────────────────────────────────
    // states in Dotos' fixed state colours, not GitHub's (one design system: VISION.md §6)
    readonly property color green: App.Console.stateOpen
    readonly property color purple: App.Console.stateDone
    readonly property color red: App.Console.stateClosed
    readonly property color grey: App.Console.stateDraft
    function ago(iso) {
        const s = Math.max(0, (Date.now() - Date.parse(iso)) / 1000);
        if (s < 60) return qsTr("just now");
        if (s < 3600) return qsTr("%1 min ago").arg(Math.floor(s / 60));
        if (s < 86400) return qsTr("%1 h ago").arg(Math.floor(s / 3600));
        if (s < 86400 * 30) return qsTr("%1 days ago").arg(Math.floor(s / 86400));
        return new Date(Date.parse(iso)).toLocaleDateString(Qt.locale(), "d MMM yyyy");
    }
    /// [icon, colour] of an issue or pull request, as GitHub draws it
    function look(it) {
        if (page.tab === "pulls" || it.headRefName !== undefined) {
            if (it.state === "MERGED" || it.mergedAt) return ["merge", page.purple];
            if (it.state === "CLOSED") return ["close", page.red];
            if (it.isDraft) return ["edit_note", page.grey];
            return ["call_split", page.green];
        }
        return it.state === "CLOSED" ? ["check_circle", page.purple] : ["radio_button_checked", page.green];
    }
    /// a run's or a check's [icon, colour]
    function runLook(status, conclusion) {
        if (status && status !== "COMPLETED" && status !== "completed") return ["progress_activity", page.grey];
        switch ((conclusion || "").toLowerCase()) {
        case "success": return ["check_circle", page.green];
        case "failure": case "timed_out": case "startup_failure": return ["cancel", page.red];
        case "cancelled": case "skipped": case "neutral": return ["do_not_disturb_on", page.grey];
        }
        return ["pending", page.grey];
    }
    function checksOf(pr) {
        const l = pr.statusCheckRollup ?? [];
        if (!l.length) return null;
        const bad = l.filter(c => ["FAILURE", "ERROR", "TIMED_OUT"].includes(c.conclusion || c.state)).length;
        const wait = l.filter(c => c.status && c.status !== "COMPLETED").length;
        return bad ? ["cancel", page.red, qsTr("%1 of %2 checks failed").arg(bad).arg(l.length)]
             : wait ? ["progress_activity", page.grey, qsTr("%1 checks running").arg(wait)]
             : ["check", page.green, qsTr("All %1 checks passed").arg(l.length)];
    }

    readonly property var shown: {
        const q = page.filter.toLowerCase();
        const l = page.tab === "issues" ? page.issues : page.tab === "pulls" ? page.pulls : [];
        return q ? l.filter(i => (i.title + " #" + i.number + " " + (i.author?.login ?? "") + " " + (i.labels ?? []).map(x => x.name).join(" ")).toLowerCase().includes(q)) : l;
    }
    readonly property var tabs: [
        { key: "code", label: qsTr("Code"), icon: "code" },
        { key: "issues", label: qsTr("Issues"), icon: "radio_button_checked", count: page.state === "open" ? page.issues.length : -1 },
        { key: "pulls", label: qsTr("Pull requests"), icon: "call_split", count: page.state === "open" ? page.pulls.length : -1 },
        { key: "actions", label: qsTr("Actions"), icon: "play_circle" },
        { key: "commits", label: qsTr("Commits"), icon: "commit" },
        { key: "branches", label: qsTr("Branches"), icon: "account_tree" }
    ]

    // ── keys ────────────────────────────────────────────────────────────────
    readonly property var keyHelp: [[qsTr("Move"), ["j", "k"]], [qsTr("Open"), ["Enter"]], [qsTr("Tab"), ["h", "l"]], [qsTr("Open on GitHub"), ["o"]], [qsTr("Reload"), ["r"]], [qsTr("Filter"), ["/"]]]
    function handleKey(e) {
        const l = page.shown;
        const i = l.findIndex(x => String(x.number) === page.cur);
        const m = K.move(e, l.length, i);
        if (m >= 0) { page.cur = String(l[m].number); return true; }
        if (K.isOpen(e) && i >= 0) { page.open(l[i]); return true; }
        if (!K.plain(e)) return false;
        const d = K.side(e);
        if (d) { page.tab = K.cycle(page.tabs.map(t => t.key), page.tab, d); return true; }
        if (e.key === Qt.Key_O) { Qt.openUrlExternally(i >= 0 ? l[i].url : (page.info?.url ?? "")); return true; }
        if (e.key === Qt.Key_R) { page.refresh(); return true; }
        if (e.key === Qt.Key_Slash) { filterField.forceActiveFocus(); return true; }
        return false;
    }

    // ── the page ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // the repository, as GitHub's header: owner / name, visibility, the counts
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            color: App.Console.bg
            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 16 }
                spacing: 10
                Ui.Icon { text: page.info?.isFork ? "fork_right" : "book"; size: 20; color: App.Console.dim }
                Rectangle {
                    implicitWidth: repoRow.implicitWidth + 16
                    implicitHeight: 34
                    radius: 8
                    color: repoHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                    RowLayout {
                        id: repoRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text { text: page.repo ? page.repo.split("/")[0] : qsTr("Choose a repository"); color: App.Console.data; font.pixelSize: 18; font.family: App.Console.sans }
                        Text { visible: page.repo.length > 0; text: "/"; color: App.Console.faint; font.pixelSize: 18 }
                        Text { visible: page.repo.length > 0; text: page.repo.split("/")[1] ?? ""; color: App.Console.data; font.pixelSize: 18; font.weight: Font.DemiBold; font.family: App.Console.sans }
                        Ui.Icon { text: "expand_more"; size: 18; color: App.Console.dim }
                    }
                    HoverHandler { id: repoHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: picker.open() }
                }
                Rectangle {
                    visible: page.info !== null
                    implicitWidth: visText.implicitWidth + 16
                    implicitHeight: 22
                    radius: 11
                    color: "transparent"
                    border.width: 1
                    border.color: App.Console.ruleStrong
                    Text { id: visText; anchors.centerIn: parent; text: page.info?.isPrivate ? qsTr("Private") : qsTr("Public"); color: App.Console.dim; font.pixelSize: 11; font.weight: Font.Medium }
                }
                Text {
                    Layout.fillWidth: true
                    text: page.info?.description ?? ""
                    color: App.Console.dim
                    elide: Text.ElideRight
                    font.pixelSize: 13
                }
                Repeater {
                    model: [
                        { icon: "visibility", text: qsTr("Watch"), n: page.info?.watchers?.totalCount ?? 0, url: "" },
                        { icon: "fork_right", text: qsTr("Fork"), n: page.info?.forkCount ?? 0, url: "/fork" },
                        { icon: "star", text: qsTr("Star"), n: page.info?.stargazerCount ?? 0, url: "/stargazers" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        visible: page.info !== null
                        implicitWidth: cRow.implicitWidth + 20
                        implicitHeight: 30
                        radius: 7
                        color: cHov.hovered ? App.Console.panelAlt : App.Console.panel
                        border.width: 1
                        border.color: App.Console.ruleStrong
                        RowLayout {
                            id: cRow
                            anchors.centerIn: parent
                            spacing: 6
                            Ui.Icon { text: modelData.icon; size: 15; color: App.Console.dim }
                            Text { text: modelData.text; color: App.Console.text; font.pixelSize: 12; font.weight: Font.Medium }
                            Rectangle {
                                implicitWidth: nText.implicitWidth + 12; implicitHeight: 18; radius: 9
                                color: Qt.alpha(App.Console.text, 0.1)
                                Text { id: nText; anchors.centerIn: parent; text: modelData.n; color: App.Console.text; font.pixelSize: 11; font.weight: Font.DemiBold }
                            }
                        }
                        HoverHandler { id: cHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally((page.info?.url ?? "") + modelData.url) }
                    }
                }
                Ui.IconButton { icon: "refresh"; tooltip: qsTr("Reload (r)"); onClicked: page.refresh() }
                Ui.IconButton { icon: "open_in_new"; tooltip: qsTr("Open on GitHub (o)"); onClicked: Qt.openUrlExternally(page.info?.url ?? "") }
            }
        }

        // the tabs, underlined as on github.com
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            color: App.Console.bg
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: App.Console.rule }
            RowLayout {
                anchors { left: parent.left; leftMargin: 16; top: parent.top; bottom: parent.bottom }
                spacing: 2
                Repeater {
                    model: page.tabs
                    delegate: Item {
                        required property var modelData
                        readonly property bool on: page.tab === modelData.key
                        Layout.fillHeight: true
                        implicitWidth: tRow.implicitWidth + 24
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            height: 32; radius: 7
                            color: tHov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
                        }
                        RowLayout {
                            id: tRow
                            anchors.centerIn: parent
                            spacing: 7
                            Ui.Icon { text: modelData.icon; size: 17; color: on ? App.Console.text : App.Console.dim }
                            Text { text: modelData.label; color: App.Console.text; font.pixelSize: 13; font.weight: on ? Font.DemiBold : Font.Normal }
                            Rectangle {
                                visible: (modelData.count ?? -1) > 0
                                implicitWidth: tc.implicitWidth + 12; implicitHeight: 18; radius: 9
                                color: Qt.alpha(App.Console.text, 0.1)
                                Text { id: tc; anchors.centerIn: parent; text: modelData.count ?? ""; color: App.Console.text; font.pixelSize: 11; font.weight: Font.Medium }
                            }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 2; radius: 1
                            color: App.Console.data
                            visible: on
                        }
                        HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.tab = modelData.key }
                    }
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                text: page.busy > 0 ? qsTr("loading…") : page.error || page.notice
                color: page.error ? App.Console.crit : App.Console.faint
                font.pixelSize: 12
                elide: Text.ElideLeft
                width: Math.min(implicitWidth, 420)
            }
        }

        // the list, and the open one beside it
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: body.implicitHeight + 40
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: body
                    x: 20; y: 20
                    width: flick.width - 40
                    spacing: 14

                    // no repository yet
                    Text {
                        visible: !page.repo
                        Layout.fillWidth: true
                        Layout.topMargin: 80
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Choose a repository above: one of your projects, or owner/name.")
                        color: App.Console.dim; font.pixelSize: 14
                    }

                    // ── Issues / Pull requests: GitHub's box ──
                    Rectangle {
                        visible: page.repo && (page.tab === "issues" || page.tab === "pulls")
                        Layout.fillWidth: true
                        implicitHeight: listCol.implicitHeight
                        radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: App.Console.ruleStrong
                        clip: true
                        ColumnLayout {
                            id: listCol
                            width: parent.width
                            spacing: 0
                            // the box's header: open / closed, the filter
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 48
                                color: App.Console.panel
                                radius: 8
                                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 8; color: parent.color }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                                    spacing: 14
                                    Repeater {
                                        model: [["open", page.tab === "pulls" ? "call_split" : "radio_button_checked", qsTr("Open")], ["closed", "check", qsTr("Closed")]]
                                        delegate: RowLayout {
                                            required property var modelData
                                            spacing: 5
                                            Ui.Icon { text: modelData[1]; size: 16; color: page.state === modelData[0] ? App.Console.text : App.Console.dim }
                                            Text {
                                                text: modelData[2]
                                                color: page.state === modelData[0] ? App.Console.text : App.Console.dim
                                                font.pixelSize: 13; font.weight: page.state === modelData[0] ? Font.DemiBold : Font.Normal
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: page.state = modelData[0] }
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        implicitWidth: 260; implicitHeight: 30; radius: 7
                                        color: App.Console.bg
                                        border.width: 1; border.color: filterField.activeFocus ? App.Console.data : App.Console.ruleStrong
                                        RowLayout {
                                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                            spacing: 6
                                            Ui.Icon { text: "search"; size: 15; color: App.Console.faint }
                                            TextField {
                                                id: filterField
                                                Layout.fillWidth: true
                                                background: null
                                                padding: 0
                                                color: App.Console.text
                                                font.pixelSize: 12
                                                placeholderText: qsTr("Filter: title, #, author, label")
                                                placeholderTextColor: App.Console.faint
                                                text: page.filter
                                                onTextChanged: page.filter = text
                                                Keys.onEscapePressed: { text = ""; page.forceActiveFocus(); }
                                            }
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: page.shown
                                delegate: Rectangle {
                                    id: row
                                    required property var modelData
                                    required property int index
                                    readonly property var lk: page.look(modelData)
                                    readonly property bool sel: page.selected?.number === modelData.number
                                    Layout.fillWidth: true
                                    implicitHeight: rowCol.implicitHeight + 18
                                    color: sel ? Qt.alpha(App.Console.data, 0.12) : rHov.hovered || page.cur === String(modelData.number) ? Qt.alpha(App.Console.text, 0.04) : "transparent"
                                    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: App.Console.rule }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                        spacing: 10
                                        Ui.Icon { Layout.alignment: Qt.AlignTop; Layout.topMargin: 10; text: row.lk[0]; color: row.lk[1]; size: 17; filled: row.lk[0] === "check_circle" }
                                        ColumnLayout {
                                            id: rowCol
                                            Layout.fillWidth: true
                                            Layout.topMargin: 9
                                            spacing: 4
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Text { text: modelData.title; color: App.Console.text; font.pixelSize: 14; font.weight: Font.DemiBold; wrapMode: Text.Wrap; width: Math.min(implicitWidth, row.width - 160) }
                                                Repeater {
                                                    model: modelData.labels ?? []
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        readonly property color c: "#" + (modelData.color || "8b949e")
                                                        implicitWidth: lt.implicitWidth + 14; implicitHeight: 20; radius: 10
                                                        color: Qt.alpha(c, 0.18); border.width: 1; border.color: Qt.alpha(c, 0.5)
                                                        Text { id: lt; anchors.centerIn: parent; text: modelData.name; color: Qt.lighter(parent.c, 1.3); font.pixelSize: 11; font.weight: Font.Medium }
                                                    }
                                                }
                                            }
                                            Text {
                                                text: "#" + modelData.number + "  " + (modelData.state === "MERGED" || modelData.mergedAt ? qsTr("merged") : modelData.state === "CLOSED" ? qsTr("closed") : qsTr("opened"))
                                                      + " " + page.ago(modelData.mergedAt || modelData.createdAt) + " " + qsTr("by %1").arg(modelData.author?.login ?? "?")
                                                      + (modelData.headRefName ? "  ·  " + modelData.headRefName + " → " + modelData.baseRefName : "")
                                                      + (modelData.reviewDecision === "APPROVED" ? "  ·  " + qsTr("Approved") : modelData.reviewDecision === "CHANGES_REQUESTED" ? "  ·  " + qsTr("Changes requested") : "")
                                                color: App.Console.dim; font.pixelSize: 12
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Ui.Icon {
                                            readonly property var ch: modelData.headRefName !== undefined ? page.checksOf(modelData) : null
                                            visible: ch !== null
                                            text: ch ? ch[0] : ""; color: ch ? ch[1] : "transparent"; size: 16
                                            HoverHandler { id: chHov }
                                            Ui.Tip { visible: chHov.hovered; text: parent.ch ? parent.ch[2] : "" }
                                        }
                                        Repeater {
                                            model: (modelData.assignees ?? []).slice(0, 3)
                                            delegate: Rectangle {
                                                required property var modelData
                                                implicitWidth: 22; implicitHeight: 22; radius: 11
                                                color: Qt.hsla((modelData.login.charCodeAt(0) * 37 % 360) / 360, 0.45, 0.45, 1)
                                                Text { anchors.centerIn: parent; text: modelData.login.charAt(0).toUpperCase(); color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                            }
                                        }
                                        RowLayout {
                                            visible: (modelData.comments?.length ?? 0) > 0
                                            spacing: 3
                                            Ui.Icon { text: "chat_bubble"; size: 14; color: App.Console.dim }
                                            Text { text: modelData.comments?.length ?? 0; color: App.Console.dim; font.pixelSize: 12 }
                                        }
                                    }
                                    HoverHandler { id: rHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { page.cur = String(modelData.number); page.open(modelData); } }
                                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => itemMenu.popupFor(modelData, ev.position.x, ev.position.y, row) }
                                }
                            }
                            Text {
                                visible: page.shown.length === 0
                                Layout.fillWidth: true
                                Layout.margins: 40
                                horizontalAlignment: Text.AlignHCenter
                                text: page.busy > 0 ? qsTr("Loading…") : page.filter ? qsTr("Nothing matches.") : page.state === "open" ? qsTr("No open %1.").arg(page.tab === "pulls" ? qsTr("pull requests") : qsTr("issues")) : qsTr("Nothing closed yet.")
                                color: App.Console.dim; font.pixelSize: 14
                            }
                        }
                    }

                    // ── Code: the folder, then the README ──
                    Rectangle {
                        visible: page.repo && page.tab === "code"
                        Layout.fillWidth: true
                        implicitHeight: codeCol.implicitHeight
                        radius: 8
                        color: "transparent"
                        border.width: 1; border.color: App.Console.ruleStrong
                        clip: true
                        ColumnLayout {
                            id: codeCol
                            width: parent.width
                            spacing: 0
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                color: App.Console.panel
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                    spacing: 8
                                    Ui.Icon { text: "account_tree"; size: 16; color: App.Console.dim }
                                    Text { text: page.info?.defaultBranchRef?.name ?? ""; color: App.Console.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text {
                                        Layout.fillWidth: true
                                        text: page.repo.split("/")[1] + (page.path ? " / " + page.path.split("/").join(" / ") : "")
                                        color: App.Console.dim; font.pixelSize: 13; elide: Text.ElideMiddle
                                    }
                                    Text {
                                        text: page.localPath ? qsTr("Files open in zett") : qsTr("Read-only (no local clone)")
                                        color: App.Console.faint; font.pixelSize: 12
                                    }
                                }
                            }
                            Repeater {
                                model: (page.path ? [{ name: "..", type: "up", path: page.path.split("/").slice(0, -1).join("/") }] : []).concat(page.files)
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    color: fHov.hovered ? Qt.alpha(App.Console.text, 0.04) : "transparent"
                                    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: App.Console.rule }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                        spacing: 10
                                        Ui.Icon { text: modelData.type === "dir" ? "folder" : modelData.type === "up" ? "arrow_upward" : "description"; filled: modelData.type === "dir"; size: 17; color: modelData.type === "dir" ? App.Console.data : App.Console.dim }
                                        Text { Layout.fillWidth: true; text: modelData.name; color: App.Console.text; font.pixelSize: 13; elide: Text.ElideRight }
                                        Text { visible: modelData.type === "file"; text: modelData.size > 1024 ? Math.round(modelData.size / 1024) + " KB" : (modelData.size ?? 0) + " B"; color: App.Console.faint; font.pixelSize: 12 }
                                    }
                                    HoverHandler { id: fHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: modelData.type === "file" ? page.openFile(modelData) : page.openPath(modelData.path) }
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: ev => fileMenu.popupFor(modelData, ev.position.x, ev.position.y, parent)
                                    }
                                }
                            }
                        }
                    }
                    // a file from GitHub (no clone here)
                    Rectangle {
                        visible: page.tab === "code" && page.fileName.length > 0
                        Layout.fillWidth: true
                        implicitHeight: fileBody.implicitHeight + 56
                        radius: 8; color: "transparent"; border.width: 1; border.color: App.Console.ruleStrong
                        Text { x: 14; y: 12; text: page.fileName; color: App.Console.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Ui.IconButton { anchors { right: parent.right; top: parent.top; margins: 6 } icon: "close"; tooltip: qsTr("Close"); onClicked: page.fileName = "" }
                        Text {
                            id: fileBody
                            x: 14; y: 44; width: parent.width - 28
                            text: page.fileText
                            color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 12
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                        }
                    }
                    Rectangle {
                        visible: page.tab === "code" && page.readme.length > 0 && !page.path
                        Layout.fillWidth: true
                        implicitHeight: readmeText.implicitHeight + 64
                        radius: 8; color: "transparent"; border.width: 1; border.color: App.Console.ruleStrong
                        RowLayout {
                            x: 14; y: 12
                            spacing: 8
                            Ui.Icon { text: "menu_book"; size: 16; color: App.Console.dim }
                            Text { text: "README"; color: App.Console.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                        }
                        Text {
                            id: readmeText
                            x: 24; y: 48; width: parent.width - 48
                            text: page.readme
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            color: App.Console.text; font.pixelSize: 14
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }

                    // ── Actions, Commits, Branches: plain GitHub lists ──
                    Rectangle {
                        visible: page.repo && ["actions", "commits", "branches"].includes(page.tab)
                        Layout.fillWidth: true
                        implicitHeight: simpleCol.implicitHeight
                        radius: 8; color: "transparent"; border.width: 1; border.color: App.Console.ruleStrong
                        clip: true
                        ColumnLayout {
                            id: simpleCol
                            width: parent.width
                            spacing: 0
                            Repeater {
                                model: page.tab === "actions" ? page.runs.map(r => ({ id: r.databaseId, lk: page.runLook(r.status, r.conclusion), title: r.displayTitle, sub: r.workflowName + " #" + r.number + "  ·  " + r.event + "  ·  " + page.ago(r.createdAt), side: r.headBranch, url: r.url, kind: "run" }))
                                     : page.tab === "commits" ? page.commits.map(c => ({ id: c.sha, lk: ["commit", App.Console.dim], title: (c.commit?.message ?? "").split("\n")[0], sub: (c.author?.login ?? c.commit?.author?.name ?? "") + " " + qsTr("committed") + " " + page.ago(c.commit?.author?.date ?? ""), side: c.sha.slice(0, 7), url: c.html_url, kind: "commit" }))
                                     : page.branches.map(b => ({ id: b.name, lk: ["account_tree", b.name === page.info?.defaultBranchRef?.name ? page.green : App.Console.dim], title: b.name, sub: b.name === page.info?.defaultBranchRef?.name ? qsTr("default branch") : (b.protected ? qsTr("protected") : ""), side: b.commit?.sha?.slice(0, 7) ?? "", url: (page.info?.url ?? "") + "/tree/" + b.name, kind: "branch" }))
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 56
                                    color: sHov.hovered ? Qt.alpha(App.Console.text, 0.04) : "transparent"
                                    Rectangle { visible: index > 0; anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: App.Console.rule }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                        spacing: 10
                                        Ui.Icon { text: modelData.lk[0]; color: modelData.lk[1]; size: 17 }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Text { Layout.fillWidth: true; text: modelData.title; color: App.Console.text; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData.sub; color: App.Console.dim; font.pixelSize: 12; elide: Text.ElideRight }
                                        }
                                        Rectangle {
                                            visible: modelData.side.length > 0
                                            implicitWidth: sideText.implicitWidth + 14; implicitHeight: 22; radius: 6
                                            color: Qt.alpha(App.Console.data, 0.12)
                                            Text { id: sideText; anchors.centerIn: parent; text: modelData.side; color: App.Console.data; font.family: App.Console.mono; font.pixelSize: 11 }
                                        }
                                    }
                                    HoverHandler { id: sHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Qt.openUrlExternally(modelData.url) }
                                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => simpleMenu.popupFor(modelData, ev.position.x, ev.position.y, parent) }
                                }
                            }
                        }
                    }
                }
            }

            // ── the open issue / pull request ──
            Rectangle {
                visible: page.selected !== null
                Layout.fillHeight: true
                Layout.preferredWidth: Math.round(page.width * 0.46)
                color: App.Console.panel
                Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: App.Console.ruleStrong }
                Flickable {
                    anchors { fill: parent; leftMargin: 1; bottomMargin: composer.height }
                    clip: true
                    contentHeight: dCol.implicitHeight + 32
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        id: dCol
                        x: 20; y: 16
                        width: parent.width - 40
                        spacing: 12
                        readonly property var d: page.detail ?? page.selected ?? ({})
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: (dCol.d.title ?? "") + "  <font color='" + App.Console.dim + "'>#" + (dCol.d.number ?? "") + "</font>"
                                textFormat: Text.StyledText
                                color: App.Console.text; font.pixelSize: 19; font.weight: Font.DemiBold; wrapMode: Text.Wrap
                            }
                            Ui.IconButton { Layout.alignment: Qt.AlignTop; icon: "close"; tooltip: qsTr("Close the pane"); onClicked: page.selected = null }
                        }
                        RowLayout {
                            spacing: 8
                            Rectangle {
                                readonly property var lk: page.look(dCol.d)
                                implicitWidth: stRow.implicitWidth + 20; implicitHeight: 28; radius: 14
                                color: lk[1]
                                RowLayout {
                                    id: stRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Ui.Icon { text: parent.parent.lk[0]; size: 15; color: "white" }
                                    Text { text: dCol.d.state === "MERGED" ? qsTr("Merged") : dCol.d.state === "CLOSED" ? qsTr("Closed") : dCol.d.isDraft ? qsTr("Draft") : qsTr("Open"); color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "<b>" + (dCol.d.author?.login ?? "") + "</b> " + (dCol.d.headRefName ? qsTr("wants to merge %1 commits into <code>%2</code> from <code>%3</code>").arg(dCol.d.commits?.length ?? "?").arg(dCol.d.baseRefName).arg(dCol.d.headRefName) : qsTr("opened this %1").arg(page.ago(dCol.d.createdAt ?? "")))
                                textFormat: Text.StyledText
                                color: App.Console.dim; font.pixelSize: 12; wrapMode: Text.Wrap
                            }
                        }
                        // the checks of a pull request
                        Text {
                            readonly property var ch: dCol.d.headRefName !== undefined ? page.checksOf(dCol.d) : null
                            visible: ch !== null
                            text: ch ? ch[2] : ""
                            color: ch ? ch[1] : App.Console.dim
                            font.pixelSize: 12
                        }
                        // the opening post and every comment, as GitHub's timeline boxes
                        Repeater {
                            model: [{ author: dCol.d.author, createdAt: dCol.d.createdAt, body: dCol.d.body }].concat(dCol.d.comments ?? []).concat((dCol.d.reviews ?? []).filter(r => r.body))
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                visible: (modelData.body ?? "").length > 0 || modelData === undefined
                                implicitHeight: cBody.implicitHeight + 50
                                radius: 8
                                color: App.Console.bg
                                border.width: 1; border.color: App.Console.ruleStrong
                                Rectangle {
                                    width: parent.width; height: 36; radius: 8
                                    color: Qt.alpha(App.Console.text, 0.04)
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                        spacing: 8
                                        Rectangle {
                                            implicitWidth: 22; implicitHeight: 22; radius: 11
                                            color: Qt.hsla(((modelData.author?.login ?? "?").charCodeAt(0) * 37 % 360) / 360, 0.45, 0.45, 1)
                                            Text { anchors.centerIn: parent; text: (modelData.author?.login ?? "?").charAt(0).toUpperCase(); color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        }
                                        Text { text: "<b>" + (modelData.author?.login ?? "") + "</b>  " + page.ago(modelData.createdAt ?? modelData.submittedAt ?? ""); textFormat: Text.StyledText; color: App.Console.dim; font.pixelSize: 12 }
                                        Item { Layout.fillWidth: true }
                                        Text { visible: !!modelData.state; text: (modelData.state ?? "").replace("_", " ").toLowerCase(); color: App.Console.faint; font.pixelSize: 11 }
                                    }
                                }
                                Text {
                                    id: cBody
                                    x: 14; y: 44; width: parent.width - 28
                                    text: modelData.body ?? ""
                                    textFormat: Text.MarkdownText
                                    wrapMode: Text.Wrap
                                    color: App.Console.text; font.pixelSize: 13
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }
                        }
                        // the changed files of a pull request (right click: zett)
                        Text { visible: (dCol.d.files ?? []).length > 0; text: qsTr("Files changed (%1)  +%2 −%3").arg(dCol.d.files?.length ?? 0).arg(dCol.d.additions ?? 0).arg(dCol.d.deletions ?? 0); color: App.Console.text; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.topMargin: 6 }
                        Repeater {
                            model: dCol.d.files ?? []
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30; radius: 6
                                color: pfHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    spacing: 8
                                    Ui.Icon { text: "description"; size: 15; color: App.Console.dim }
                                    Text { Layout.fillWidth: true; text: modelData.path; color: App.Console.text; font.family: App.Console.mono; font.pixelSize: 12; elide: Text.ElideMiddle }
                                    Text { text: "+" + modelData.additions; color: page.green; font.family: App.Console.mono; font.pixelSize: 12 }
                                    Text { text: "−" + modelData.deletions; color: page.red; font.family: App.Console.mono; font.pixelSize: 12 }
                                }
                                HoverHandler { id: pfHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: page.localPath ? page.zett(modelData.path) : Qt.openUrlExternally(dCol.d.url + "/files") }
                                TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => fileMenu.popupFor({ type: "file", path: modelData.path, name: modelData.path }, ev.position.x, ev.position.y, parent) }
                            }
                        }
                    }
                }
                // the comment box, and the buttons GitHub has under it
                Rectangle {
                    id: composer
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 1 }
                    height: 132
                    color: App.Console.panelAlt
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 7; color: App.Console.bg
                            border.width: 1; border.color: commentField.activeFocus ? App.Console.data : App.Console.ruleStrong
                            ScrollView {
                                anchors { fill: parent; margins: 6 }
                                TextArea {
                                    id: commentField
                                    background: null
                                    wrapMode: TextEdit.Wrap
                                    color: App.Console.text
                                    font.pixelSize: 13
                                    placeholderText: qsTr("Leave a comment (Markdown)")
                                    placeholderTextColor: App.Console.faint
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            Repeater {
                                model: {
                                    const d = page.detail ?? page.selected;
                                    if (!d) return [];
                                    const pr = d.headRefName !== undefined, open = d.state === "OPEN";
                                    const l = [];
                                    if (open) l.push({ text: pr ? qsTr("Close pull request") : qsTr("Close issue"), run: () => confirm.ask(pr ? qsTr("Close pull request #%1?").arg(d.number) : qsTr("Close issue #%1?").arg(d.number), () => page.act([pr ? "pr" : "issue", "close", String(d.number), "-R", page.repo], qsTr("Closed #%1").arg(d.number))) });
                                    else if (d.state === "CLOSED") l.push({ text: qsTr("Reopen"), run: () => page.act([pr ? "pr" : "issue", "reopen", String(d.number), "-R", page.repo], qsTr("Reopened #%1").arg(d.number)) });
                                    if (pr && open && !d.isDraft) l.push({ text: qsTr("Squash and merge"), primary: true, run: () => confirm.ask(qsTr("Squash and merge #%1 into %2?").arg(d.number).arg(d.baseRefName), () => page.act(["pr", "merge", String(d.number), "-R", page.repo, "--squash"], qsTr("Merged #%1").arg(d.number))) });
                                    if (pr && open && d.isDraft) l.push({ text: qsTr("Ready for review"), run: () => page.act(["pr", "ready", String(d.number), "-R", page.repo], qsTr("#%1 is ready for review").arg(d.number)) });
                                    l.push({ text: qsTr("Comment"), primary: !pr || !open || d.isDraft, run: () => {
                                        if (!commentField.text.trim()) { commentField.forceActiveFocus(); return; }
                                        page.act([pr ? "pr" : "issue", "comment", String(d.number), "-R", page.repo, "--body", commentField.text], qsTr("Commented on #%1").arg(d.number));
                                        commentField.text = "";
                                    } });
                                    return l;
                                }
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: bText.implicitWidth + 24; implicitHeight: 32; radius: 7
                                    color: modelData.primary ? (bHov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data) : (bHov.hovered ? App.Console.panelAlt : App.Console.panel)
                                    border.width: 1; border.color: modelData.primary ? App.Console.data : App.Console.ruleStrong
                                    Text { id: bText; anchors.centerIn: parent; text: modelData.text; color: modelData.primary ? App.Console.onData : App.Console.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    HoverHandler { id: bHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: parent.modelData.run() }
                                }
                            }
                        }
                    }
                }
            }
        }

        // zett on a file of the local clone, under everything (as Changes does it)
        Rectangle {
            visible: page.termOpen
            Layout.fillWidth: true
            implicitHeight: 28
            color: App.Console.panel
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: App.Console.ruleStrong }
            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 6 }
                Ui.Icon { text: "edit_note"; size: 15; color: App.Console.dim }
                Text { Layout.fillWidth: true; text: qsTr("zett in %1").arg(page.localPath); color: App.Console.dim; font.pixelSize: 12; elide: Text.ElideMiddle }
                Ui.IconButton { icon: "close"; tooltip: qsTr("Hide zett (it keeps running)"); onClicked: page.termOpen = false }
            }
            MouseArea {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 6
                cursorShape: Qt.SizeVerCursor
                property real y0: 0
                onPressed: m => y0 = m.y
                onPositionChanged: m => page.termHeight = Math.max(160, Math.min(page.height - 200, page.termHeight - (m.y - y0)))
            }
        }
        App.TerminalView {
            id: terminal
            visible: page.termOpen
            dir: page.localPath
            Layout.fillWidth: true
            Layout.preferredHeight: page.termHeight
        }
    }

    // ── menus ────────────────────────────────────────────────────────────────
    /// a right-click menu: items [{ icon, text, run, on }]
    component RowMenu: Popup {
        id: m
        property var items: []
        function show(list, x, y, over) {
            m.items = list;
            const p = over.mapToItem(page, x, y);
            m.x = Math.min(p.x, page.width - m.width - 8);
            m.y = Math.min(p.y, page.height - m.implicitHeight - 8);
            m.open();
        }
        parent: page
        padding: 6
        width: 250
        background: Rectangle { radius: 10; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }
        contentItem: ColumnLayout {
            spacing: 2
            Repeater {
                model: m.items
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.on ?? true
                    readonly property bool sep: modelData.sep ?? false
                    Layout.fillWidth: true
                    implicitHeight: sep ? 9 : 32
                    radius: 7
                    color: !sep && on && mh.hovered ? (modelData.danger ? Qt.alpha(page.red, 0.18) : Qt.alpha(App.Console.text, 0.08)) : "transparent"
                    opacity: on ? 1 : 0.4
                    Rectangle { visible: parent.sep; anchors.centerIn: parent; width: parent.width - 12; height: 1; color: App.Console.ruleStrong }
                    HoverHandler { id: mh; enabled: parent.on && !parent.sep }
                    TapHandler { enabled: parent.on && !parent.sep; onTapped: { m.close(); parent.modelData.run(); } }
                    RowLayout {
                        visible: !parent.sep
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 10
                        Ui.Icon { text: modelData.icon ?? ""; size: 17; color: modelData.danger ? page.red : App.Console.dim }
                        Text { Layout.fillWidth: true; text: modelData.text ?? ""; color: modelData.danger ? page.red : App.Console.text; font.pixelSize: 13 }
                    }
                }
            }
        }
    }
    RowMenu {
        id: itemMenu
        function popupFor(it, x, y, over) {
            const pr = it.headRefName !== undefined, open = it.state === "OPEN", n = String(it.number), R = ["-R", page.repo];
            const kind = pr ? "pr" : "issue";
            itemMenu.show([
                { icon: "open_in_new", text: qsTr("Open on GitHub"), run: () => Qt.openUrlExternally(it.url) },
                { icon: "link", text: qsTr("Copy link"), run: () => { Quickshell.clipboardText = it.url; page.notice = qsTr("Link copied"); } },
                { icon: "tag", text: qsTr("Copy #%1").arg(n), run: () => Quickshell.clipboardText = "#" + n },
                { sep: true },
                { icon: "download", text: qsTr("Check out locally"), on: pr && page.localPath.length > 0, run: () => page.act(["pr", "checkout", n, "-R", page.repo], qsTr("Checked out #%1 in %2").arg(n).arg(page.localPath), page.localPath) },
                { icon: "merge", text: qsTr("Squash and merge…"), on: pr && open && !it.isDraft, run: () => confirm.ask(qsTr("Squash and merge #%1 into %2?").arg(n).arg(it.baseRefName), () => page.act(["pr", "merge", n, "--squash"].concat(R), qsTr("Merged #%1").arg(n))) },
                { icon: "call_merge", text: qsTr("Create a merge commit…"), on: pr && open && !it.isDraft, run: () => confirm.ask(qsTr("Merge #%1 into %2 with a merge commit?").arg(n).arg(it.baseRefName), () => page.act(["pr", "merge", n, "--merge"].concat(R), qsTr("Merged #%1").arg(n))) },
                { icon: "low_priority", text: qsTr("Rebase and merge…"), on: pr && open && !it.isDraft, run: () => confirm.ask(qsTr("Rebase and merge #%1 into %2?").arg(n).arg(it.baseRefName), () => page.act(["pr", "merge", n, "--rebase"].concat(R), qsTr("Merged #%1").arg(n))) },
                { icon: "rate_review", text: qsTr("Ready for review"), on: pr && open && !!it.isDraft, run: () => page.act(["pr", "ready", n].concat(R), qsTr("#%1 is ready for review").arg(n)) },
                { icon: "person_add", text: qsTr("Assign to me"), on: open, run: () => page.act([kind, "edit", n, "--add-assignee", "@me"].concat(R), qsTr("Assigned #%1 to you").arg(n)) },
                { icon: "chat", text: qsTr("Comment…"), run: () => { page.open(it); Qt.callLater(() => commentField.forceActiveFocus()); } },
                { sep: true },
                open ? { icon: "block", text: pr ? qsTr("Close pull request…") : qsTr("Close issue…"), danger: true, run: () => confirm.ask(qsTr("Close #%1?").arg(n), () => page.act([kind, "close", n].concat(R), qsTr("Closed #%1").arg(n))) }
                     : { icon: "replay", text: qsTr("Reopen"), on: it.state === "CLOSED", run: () => page.act([kind, "reopen", n].concat(R), qsTr("Reopened #%1").arg(n)) }
            ], x, y, over);
        }
    }
    RowMenu {
        id: fileMenu
        function popupFor(f, x, y, over) {
            const url = (page.info?.url ?? "") + "/" + (f.type === "dir" ? "tree" : "blob") + "/" + (page.info?.defaultBranchRef?.name ?? "HEAD") + "/" + f.path;
            fileMenu.show([
                { icon: "edit_note", text: qsTr("Edit in zett"), on: f.type === "file" && page.localPath.length > 0, run: () => page.zett(f.path) },
                { icon: "visibility", text: qsTr("View here"), on: f.type === "file", run: () => { const l = page.localPath; page.fileName = f.path; page.gh(["api", "repos/" + page.repo + "/contents/" + f.path, "-H", "Accept: application/vnd.github.raw"], (c, o) => page.fileText = c === 0 ? o : qsTr("Could not read it.")); } },
                { icon: "open_in_new", text: qsTr("Open on GitHub"), run: () => Qt.openUrlExternally(url) },
                { icon: "link", text: qsTr("Copy link"), run: () => Quickshell.clipboardText = url },
                { icon: "content_copy", text: qsTr("Copy path"), run: () => Quickshell.clipboardText = f.path },
                { icon: "folder_open", text: qsTr("Show in the file manager"), on: page.localPath.length > 0, run: () => Qt.openUrlExternally("file://" + page.localPath + "/" + f.path.split("/").slice(0, f.type === "dir" ? undefined : -1).join("/")) }
            ], x, y, over);
        }
    }
    RowMenu {
        id: simpleMenu
        function popupFor(r, x, y, over) {
            simpleMenu.show([
                { icon: "open_in_new", text: qsTr("Open on GitHub"), run: () => Qt.openUrlExternally(r.url) },
                { icon: "link", text: qsTr("Copy link"), run: () => Quickshell.clipboardText = r.url },
                { icon: "content_copy", text: r.kind === "commit" ? qsTr("Copy the SHA") : qsTr("Copy the name"), on: r.kind !== "run", run: () => Quickshell.clipboardText = r.id },
                { icon: "replay", text: qsTr("Re-run"), on: r.kind === "run", run: () => page.act(["run", "rerun", String(r.id), "-R", page.repo], qsTr("Re-running")) },
                { icon: "replay_circle_filled", text: qsTr("Re-run failed jobs"), on: r.kind === "run" && r.lk[1] === page.red, run: () => page.act(["run", "rerun", String(r.id), "--failed", "-R", page.repo], qsTr("Re-running the failed jobs")) },
                { icon: "download", text: qsTr("Check out"), on: r.kind === "branch" && page.localPath.length > 0, run: () => page.act(["repo", "sync", "--branch", r.id], qsTr("Synced %1").arg(r.id), page.localPath) },
                { icon: "call_split", text: qsTr("New pull request from it"), on: r.kind === "branch", run: () => Qt.openUrlExternally((page.info?.url ?? "") + "/compare/" + r.id + "?expand=1") }
            ], x, y, over);
        }
    }

    // a yes/no before anything that changes the repository for everyone
    Popup {
        id: confirm
        property string text: ""
        property var yes: null
        function ask(t, f) { confirm.text = t; confirm.yes = f; confirm.open(); }
        parent: page
        anchors.centerIn: parent
        modal: true
        padding: 18
        width: 380
        background: Rectangle { radius: 12; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }
        contentItem: ColumnLayout {
            spacing: 16
            Text { Layout.fillWidth: true; text: confirm.text; color: App.Console.text; font.pixelSize: 14; wrapMode: Text.Wrap }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 86; implicitHeight: 32; radius: 7
                    color: noHov.hovered ? App.Console.panel : "transparent"; border.width: 1; border.color: App.Console.ruleStrong
                    Text { anchors.centerIn: parent; text: qsTr("Cancel"); color: App.Console.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                    HoverHandler { id: noHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: confirm.close() }
                }
                Rectangle {
                    implicitWidth: 86; implicitHeight: 32; radius: 7
                    color: yesHov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data
                    Text { anchors.centerIn: parent; text: qsTr("Confirm"); color: App.Console.onData; font.pixelSize: 12; font.weight: Font.DemiBold }
                    HoverHandler { id: yesHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { confirm.close(); if (confirm.yes) confirm.yes(); } }
                }
            }
        }
    }

    // the repository picker: your projects with a GitHub remote, or owner/name
    Popup {
        id: picker
        parent: page
        x: 52; y: 54
        width: 380
        padding: 8
        onOpened: slugField.forceActiveFocus()
        background: Rectangle { radius: 10; color: App.Console.panelAlt; border.width: 1; border.color: App.Console.ruleStrong }
        contentItem: ColumnLayout {
            spacing: 4
            TextField {
                id: slugField
                Layout.fillWidth: true
                placeholderText: qsTr("owner/name, Enter opens it")
                color: App.Console.text
                placeholderTextColor: App.Console.faint
                background: Rectangle { radius: 7; color: App.Console.bg; border.width: 1; border.color: App.Console.ruleStrong }
                onAccepted: { if (/^[^/\s]+\/[^/\s]+$/.test(text.trim())) { page.repo = text.trim(); picker.close(); text = ""; } }
            }
            Text { text: qsTr("Your projects"); color: App.Console.faint; font.pixelSize: 11; Layout.topMargin: 6; Layout.leftMargin: 6 }
            Repeater {
                model: page.localRepos.filter(r => !slugField.text || r.slug.toLowerCase().includes(slugField.text.toLowerCase()))
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 34; radius: 7
                    color: pHov.hovered ? Qt.alpha(App.Console.text, 0.08) : modelData.slug === page.repo ? Qt.alpha(App.Console.data, 0.12) : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Ui.Icon { text: "book"; size: 16; color: App.Console.dim }
                        Text { Layout.fillWidth: true; text: modelData.slug; color: App.Console.text; font.pixelSize: 13; elide: Text.ElideRight }
                        Text { text: modelData.name; color: App.Console.faint; font.pixelSize: 11 }
                    }
                    HoverHandler { id: pHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { page.repo = modelData.slug; picker.close(); } }
                }
            }
        }
    }
}
