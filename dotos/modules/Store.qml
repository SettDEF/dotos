pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Everything the window shows comes from `dotos snapshot`, and every change
 * goes through the `dotos` CLI — the same door the terminal, Neovim and the
 * extensions use, so they can never disagree.
 *
 * Fresh without polling: inotify on the folders Dotos writes (the task
 * store, pages, journal, habits, the change log, extensions) and on the AI
 * hooks' folder. A burst of events (a sync, an agent's tool calls) reloads
 * once. The git state of projects is the slow part, so ordinary reloads skip
 * it (--no-git) and keep the last git reading; a full read runs every minute.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dotosHome: Quickshell.env("DOTOS_HOME") || ""
    readonly property string bin: Quickshell.env("DOTOS_BIN") || (root.home + "/.local/bin/dotos")
    readonly property string configDir: root.dotosHome ? root.dotosHome + "/config" : (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config") + "/dotos"
    readonly property string dataDir: root.dotosHome ? root.dotosHome + "/data" : (Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share") + "/dotos"
    readonly property string stateDir: root.dotosHome ? root.dotosHome + "/state" : (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/dotos"
    readonly property string agentsDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ai-activity"

    property var snap: null
    property bool loaded: false
    property string error: ""
    property real lastLoad: 0
    property var _git: ({})   // project name → last git reading

    readonly property var tasks: root.snap?.tasks ?? []
    readonly property var open: root.tasks.filter(t => t.state !== "done" && t.state !== "cancelled")
    readonly property var lists: root.snap?.lists ?? []
    readonly property var projects: root.snap?.projects ?? []
    /// found under the roots, not yet tracked or ignored (the Projects page offers them)
    readonly property var newProjects: root.snap?.new_projects ?? []
    /// all | ask | manual: how a newly found project is treated
    readonly property string projectMode: root.snap?.project_mode ?? "all"
    readonly property var agents: root.snap?.agents ?? []
    readonly property var liveAgents: root.agents.filter(a => a.state !== "ended")
    readonly property var needsYou: root.liveAgents.filter(a => a.state === "needs_you")
    readonly property var pages: root.snap?.pages ?? []
    readonly property var pageTasks: root.snap?.page_tasks ?? []
    readonly property var habits: root.snap?.habits ?? []
    readonly property var extensions: root.snap?.extensions ?? []
    readonly property var log: root.snap?.log ?? []
    readonly property var time: root.snap?.time ?? ({})
    readonly property var config: root.snap?.config ?? ({})
    readonly property string today: root.snap?.today ?? ""

    readonly property int overdue: root.open.filter(t => t.bucket === "overdue").length
    readonly property int dueToday: root.open.filter(t => t.bucket === "today").length
    readonly property int inbox: root.open.filter(t => t.state === "inbox").length
    readonly property int doing: root.open.filter(t => t.state === "doing").length
    readonly property int waiting: root.open.filter(t => t.state === "waiting").length
    readonly property var active: root.time?.active ?? null

    function task(uid) { return root.tasks.find(t => t.uid === uid) ?? null; }
    function subtasks(uid) { return root.tasks.filter(t => t.parent === uid); }
    function project(name) { return root.projects.find(p => p.name.toLowerCase() === String(name).toLowerCase()) ?? null; }
    function tasksOf(projectName) { return root.tasks.filter(t => t.project.toLowerCase() === String(projectName).toLowerCase()); }
    function agentsIn(path) { return root.liveAgents.filter(a => a.cwd === path || String(a.cwd ?? "").startsWith(path + "/")); }

    // ── loading ────────────────────────────────────────────────────────
    function reload(withGit) {
        if (withGit) root._wantGit = true;
        debounce.restart();
    }
    property bool _wantGit: true
    Timer {
        id: debounce
        interval: 250
        onTriggered: {
            if (snapProc.running) { debounce.restart(); return; }
            const git = root._wantGit;
            root._wantGit = false;
            snapProc.command = git ? [root.bin, "snapshot"] : [root.bin, "snapshot", "--no-git"];
            snapProc.running = true;
        }
    }
    Process {
        id: snapProc
        environment: ({ DOTOS_NO_ACTIONS: "1" })
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    // keep git readings across --no-git reloads
                    const g = Object.assign({}, root._git);
                    for (const p of s.projects ?? []) {
                        if (p.git) g[p.name] = p.git;
                        else if (g[p.name]) p.git = g[p.name];
                    }
                    root._git = g;
                    root.snap = s;
                    root.loaded = true;
                    root.error = "";
                    root.lastLoad = Date.now();
                } catch (e) {
                    if (text.trim().length === 0 && !root.loaded) root.error = qsTr("dotos did not answer — is it installed? (%1)").arg(root.bin);
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim().length > 0 && !root.loaded) root.error = text.trim().split("\n").pop() }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.reload(true) }
    // elapsed times and "in 5 min" labels
    property real now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    Process {
        id: watcher
        running: false
        command: ["sh", "-c", `mkdir -p "$1" "$2/pages" "$2/journal" "$3" "$4" "$5/extensions" && exec setpriv --pdeathsig TERM inotifywait -m -r -q -e close_write,moved_to,delete,create --format %w%f "$1" "$2" "$3" "$4" "$5" 2>/dev/null`,
            "watch", root.snap?.store ?? (root.dataDir + "/lists"), root.dataDir, root.stateDir, root.agentsDir, root.configDir]
        stdout: SplitParser {
            onRead: line => {
                // our own log/index writes still mean "the data changed"; only temp files are noise
                if (/\.tmp~?$|~$|\.swp$/.test(line)) return;
                root.reload(false);
            }
        }
        onExited: restartWatch.start()
    }
    Timer { id: restartWatch; interval: 3000; onTriggered: watcher.running = true }
    onLoadedChanged: if (root.loaded && !watcher.running) watcher.running = true

    Component.onCompleted: root.reload(true)

    // ── changes: one queue, in order ───────────────────────────────────
    signal said(string text)
    property var _queue: []
    function run(args, okText, then) {
        root._queue = root._queue.concat([{ args, okText: okText ?? "", then: then ?? null }]);
        if (!runner.running) root._next();
    }
    function _next() {
        if (root._queue.length === 0) return;
        const job = root._queue[0];
        runner.job = job;
        runner.command = [root.bin].concat(job.args);
        runner.running = true;
    }
    Process {
        id: runner
        property var job: null
        environment: ({ DOTOS_WHO: "user" })
        stdout: StdioCollector { id: runOut }
        stderr: StdioCollector { id: runErr }
        onExited: code => {
            const job = runner.job;
            root._queue = root._queue.slice(1);
            if (code === 0) {
                if (job?.okText) root.said(job.okText);
                if (job?.then) job.then(runOut.text.trim());
            } else {
                const msg = (runErr.text || "").trim().split("\n").pop() || qsTr("dotos failed (%1)").arg(code);
                root.said(msg.replace(/^dotos[^:]*: /, ""));
            }
            root.reload(false);
            root._next();
        }
    }

    function capture(line, then) { if (String(line).trim()) root.run(["capture", line, "--json"], qsTr("Added"), then); }
    function setState(uid, state, on) { root.run(on ? ["state", uid, state, "--on", on] : ["state", uid, state]); }
    /// An agent's prompt or message as words: tool markup (<task-notification>…) removed.
    function clean(t) { return String(t ?? "").replace(/<([a-z-]+)>[^<]*<\/\1>/g, " ").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim(); }
    function toggleDone(t) { root.setState(t.uid, t.state === "done" ? "todo" : "done"); }
    function set(uid, pairs, okText) { root.run(["set", uid].concat(pairs), okText ?? ""); }
    function sub(uid, line) { if (String(line).trim()) root.run(["sub", uid, line]); }
    function snooze(uid, when) { root.run(["snooze", uid, when], qsTr("Snoozed")); }
    function blockedBy(uid) { return (root.task(uid)?.blocked_by ?? []).map(u => root.task(u)).filter(t => t); }
    /// the RRULE as the words typed into capture: "2d", "mon,thu", "+3d" (from completion)
    function repeatLabel(t) {
        const r = String(t?.repeat ?? "");
        if (!r) return "";
        const get = k => (r.match(new RegExp(k + "=([^;]+)")) ?? [])[1] ?? "";
        const n = parseInt(get("INTERVAL") || "1"), f = get("FREQ"), by = get("BYDAY");
        const pre = t.repeat_after ? "+" : "";
        if (f === "WEEKLY" && by === "MO,TU,WE,TH,FR") return pre + "weekdays";
        if (f === "WEEKLY" && by) return pre + by.split(",").map(d => ({ MO: "mon", TU: "tue", WE: "wed", TH: "thu", FR: "fri", SA: "sat", SU: "sun" })[d] ?? d).join(",");
        const unit = ({ DAILY: "d", WEEKLY: "w", MONTHLY: "m", YEARLY: "y" })[f] ?? "";
        const word = ({ DAILY: "daily", WEEKLY: "weekly", MONTHLY: "monthly", YEARLY: "yearly" })[f] ?? r;
        return pre + (n > 1 ? n + unit : word);
    }
    function remove(uid) { root.run(["rm", uid], qsTr("Deleted — Ctrl Z brings it back")); }
    function track(uid) { root.run(["track", uid], qsTr("Timer started")); }
    function stop() { root.run(["stop"], qsTr("Timer stopped")); }
    function undo() { root.run(["undo"], ""); }
    function undoLabel(then) { root.run(["undo"], "", then); }
    function habitCheck(name, day) { root.run(day ? ["habit", "check", name, day] : ["habit", "check", name]); }
    function habitAdd(name, perWeek, icon) { root.run(["habit", "add", name, "--per-week", String(perWeek), "--icon", icon || "autorenew"], qsTr("Habit added")); }
    function habitRemove(name) { root.run(["habit", "rm", name], qsTr("Habit removed")); }
    function pageCheck(id, line, on) { root.run(["page", "check", id, String(line), on ? "on" : "off"]); }
    function projectCheck(name, line, on) { root.run(["project-check", name, String(line), on ? "on" : "off"]); }
    function pageNew(title, project, then) { root.run(["page", "new", title].concat(project ? ["--project", project] : []), qsTr("Page created"), then); }
    function journal(then) { root.run(["journal"], "", then); }
    function extEnable(id, on) { root.run(["ext", on ? "enable" : "disable", id]); }
    function extSet(id, key, value) { root.run(["ext", "set", id, key, String(value)]); }
    function extRun(id) { root.run(["ext", "run", id], "", out => root.said(out)); }

    /// config.json, the settings the CLI reads too (default list, reminders…)
    function setConfig(key, value) {
        const next = Object.assign({}, root.config && typeof root.config === "object" ? root.config : {});
        next[key] = value;
        cfgWriter.text = JSON.stringify(next, null, 2) + "\n";
        cfgWriter.command = ["sh", "-c", `mkdir -p "$1" && cat > "$1/config.json.tmp~" && mv "$1/config.json.tmp~" "$1/config.json"`, "w", root.configDir];
        cfgWriter.running = true;
    }
    Process {
        id: cfgWriter
        property string text: ""
        stdinEnabled: true
        onStarted: { cfgWriter.write(cfgWriter.text); cfgWriter.stdinEnabled = false; }
        onExited: { cfgWriter.stdinEnabled = true; root.reload(false); }
    }

    // ── opening things ─────────────────────────────────────────────────
    /// A file in zett (in a zash window, in the file's folder), at its line when the path ends in :N.
    /// Full paths: the compositor's PATH has no ~/.local/bin.
    readonly property string zash: root.home + "/.local/bin/zash"
    readonly property string zett: root.home + "/.local/bin/zett"
    function edit(path) {
        const p = String(path).replace(/^file:\/\//, "");
        const m = p.match(/^(.*?):(\d+)$/);
        const file = m ? m[1] : p, line = m ? m[2] : "";
        const dir = file.replace(/\/[^/]*$/, "") || "/";
        const q = s => "'" + s.replace(/'/g, "'\\''") + "'";
        Quickshell.execDetached([root.zash, "-d", dir, "-e", root.zett + " " + q(file) + (line ? " +" + line : "")]);
    }
    function openLink(link) {
        const l = String(link);
        if (l.startsWith("file://") || l.startsWith("/")) root.edit(l);
        else if (l.startsWith("agent:")) root.jump(root.agents.find(a => a.id === l.slice(6)));
        else Quickshell.execDetached(["xdg-open", l]);
    }
    /// The AI sessions working on a task (its agent: links), newest first.
    function sessionsOf(t) { return root.agents.filter(a => (t?.links ?? []).includes("agent:" + a.id)).sort((a, b) => (b.updated ?? 0) - (a.updated ?? 0)); }
    function openFolder(path) { Quickshell.execDetached(["xdg-open", path]); }
    function terminalAt(path) { Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--cwd", path]); }

    /// Bring an AI chat's terminal forward: its zeit pane in zash (the pane its process runs in,
    /// raised by `zeit jump`; the zash window is the one above the zeit client it answers), else
    /// its tmux pane, then WezTerm.
    readonly property string zeitJump: 'p=$(tr "\\0" "\\n" </proc/"$1"/environ 2>/dev/null | sed -n "s/^ZEIT_PANE=//p"); [ -n "$p" ] || exit 1; '
        + 'c=$("$HOME/.local/bin/zeit" jump -t "$p" 2>/dev/null) || exit 1; '
        + 'while [ -n "$c" ] && [ "$c" -gt 1 ] && [ "$(cat /proc/$c/comm 2>/dev/null)" != zash ]; do c=$(awk "{print \\$4}" /proc/$c/stat 2>/dev/null); done; '
        + '[ -n "$c" ] && [ "$c" -gt 1 ] && hyprctl dispatch "hl.dsp.focus({ window = \\"pid:$c\\" })" >/dev/null 2>&1; exit 0'
    function jump(a) {
        if (!a) return;
        const sock = String(a.tmux ?? "").split(",")[0];
        const pane = String(a.tmux_pane ?? "");
        let cmd = a.pid ? `sh -c '${root.zeitJump.replace(/'/g, "'\\''")}' jump ${Number(a.pid)} && exit 0; ` : "";
        if (sock && pane)
            cmd += `tmux -S '${sock}' switch-client -t '${pane}' 2>/dev/null; tmux -S '${sock}' select-window -t '${pane}' 2>/dev/null; tmux -S '${sock}' select-pane -t '${pane}' 2>/dev/null; `;
        cmd += "hyprctl dispatch 'hl.dsp.focus({ window = \"class:^(org.wezfurlong.wezterm)$\" })' >/dev/null 2>&1";
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // ── formatting ─────────────────────────────────────────────────────
    function dur(s) {
        s = Math.max(0, Math.round(s ?? 0));
        if (s < 60) return s > 0 ? `${s}s` : "0m";
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
        return h > 0 ? (m > 0 ? `${h}h ${m}m` : `${h}h`) : `${m}m`;
    }
    function ago(unix) {
        const d = Math.max(0, Math.floor((root.now / 1000) - (unix ?? 0)));
        if (d < 60) return qsTr("just now");
        if (d < 3600) return qsTr("%1 min ago").arg(Math.floor(d / 60));
        if (d < 86400) return qsTr("%1 h ago").arg(Math.floor(d / 3600));
        return qsTr("%1 d ago").arg(Math.floor(d / 86400));
    }
    /// "Fri 14:00", "today", "in 3 days", "2 days late"
    function dueLabel(t) {
        if (!t?.due) return "";
        const d = new Date(t.due);
        const t0 = new Date(root.today + "T00:00:00");
        const days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - t0) / 86400000);
        const time = t.due_time ? " " + Qt.formatDateTime(d, "HH:mm") : "";
        if (days === 0) return qsTr("today") + time;
        if (days === 1) return qsTr("tomorrow") + time;
        if (days === -1) return qsTr("yesterday");
        if (days < 0) return qsTr("%1 days late").arg(-days);
        if (days < 7) return Qt.formatDateTime(d, "ddd") + time;
        return Qt.formatDateTime(d, "d MMM") + time;
    }

    // ── colours ────────────────────────────────────────────────────────
    /// A colour per list or project, stepped round the hue wheel from the
    /// theme accent (the same rule Kalends uses for calendars).
    function colorOf(name) {
        const key = String(name ?? "");
        if (!key) return App.Console.dim;
        let h = 0;
        for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
        const p = Ui.Appearance.primary;
        const base = p.hslHue < 0 ? 0.8 : p.hslHue;
        return Qt.hsla((base + (h % 12) * 0.083) % 1, Math.max(0.45, p.hslSaturation), Math.min(0.78, Math.max(0.62, p.hslLightness)), 1);
    }
    function stateColor(s) {
        return s === "doing" ? App.Console.data : s === "waiting" ? App.Console.warn : s === "inbox" ? App.Console.dim
             : s === "done" ? App.Console.ok : s === "cancelled" ? App.Console.faint : App.Console.text;
    }
    function stateIcon(s) {
        return ({ inbox: "inbox", todo: "radio_button_unchecked", doing: "play_circle", waiting: "hourglass_top", done: "check_circle", cancelled: "cancel" })[s] ?? "circle";
    }
    function agentIcon(a) {
        return a.state === "needs_you" ? "pending" : a.state === "working" ? "progress_activity" : a.state === "finished" ? "task_alt" : a.state === "ready" ? "chat_bubble" : a.state === "idle" ? "pause_circle" : "stop_circle";
    }
    function agentColor(a) {
        return a.state === "needs_you" ? App.Console.crit : a.state === "working" ? App.Console.data : a.state === "finished" ? App.Console.ok : App.Console.faint;
    }
    function healthColor(h) {
        return h === "attention" ? App.Console.crit : h === "stale" ? App.Console.warn : h === "active" ? App.Console.ok : App.Console.faint;
    }
}
