import QtQuick
import Quickshell
import Quickshell.Io
import "." as App

/**
 * A real terminal inside Dotos: a zeit session (zash's shell, your prompt, zett runs in it) on
 * Dotos' own zeit server ("dotos", so your layout is never resized), drawn from `zeit view`'s
 * JSON frames. Colours are the wallpaper's (tinct's kitty theme, followed live).
 */
FocusScope {
    id: term
    /// the folder whose session it shows (one session per folder, kept while Dotos runs and after)
    property string dir: ""
    property string title: ""
    readonly property bool live: proc.running
    property int cols: 80
    property int rows: 24

    /// types `text` into the shell (a command line ends with "\r")
    function send(text) { term.write(term.bytes(text)); }
    function run(cmd) { term.send(cmd + "\r"); }

    // ── the session ──────────────────────────────────────────────────────────
    property var lines: []          // per row: its runs [text, fg, bg, flags]
    property var cursor: null
    property string shape: "block"

    Process {
        id: proc
        command: [Quickshell.env("DOTOS_ZEIT") || Quickshell.env("HOME") + "/.local/bin/zeit", "view", "-c", term.dir, "--cols", String(term.cols), "--rows", String(term.rows)]
        // its own server; and never "inside zeit" (Dotos may have been started from a pane)
        environment: ({ ZEIT_SERVER: Quickshell.env("DOTOS_ZEIT_SERVER") || "dotos", ZEIT: null, ZEIT_PANE: null, TMUX: null })
        stdinEnabled: true
        running: term.dir.length > 0 && term.visible
        stdout: SplitParser {
            onRead: line => {
                let f;
                try { f = JSON.parse(line); } catch (e) { return; }
                if (f.bye !== undefined) return;
                const ls = term.lines.length === f.rows ? term.lines.slice() : new Array(f.rows).fill([]);
                for (const [r, runs] of f.changed) ls[r] = runs;
                term.lines = ls;
                term.cursor = f.cursor;
                term.shape = f.shape;
                term.title = f.title;
                if (!term.ready) { term.ready = true; for (const h of term.pending) proc.write("k " + h + "\n"); term.pending = []; }
            }
        }
        onRunningChanged: if (!running) { term.lines = []; term.ready = false; }
    }
    // keys sent before zeit answered wait for its first frame
    property bool ready: false
    property var pending: []
    function write(hex) {
        if (!hex.length) return;
        if (proc.running && term.ready) proc.write("k " + hex + "\n");
        else { term.pending.push(hex); if (!proc.running && term.dir) proc.running = true; }
    }

    // the grid follows the size it has (zeit is told, once the size rests)
    FontMetrics { id: fm; font.family: App.Console.mono; font.pixelSize: 13 }
    readonly property real cw: Math.max(1, fm.averageCharacterWidth)
    readonly property real ch: Math.max(1, Math.ceil(fm.height))
    onWidthChanged: resize.restart()
    onHeightChanged: resize.restart()
    Timer {
        id: resize
        interval: 80
        onTriggered: {
            const c = Math.max(20, Math.floor((term.width - 12) / term.cw)), r = Math.max(4, Math.floor((term.height - 8) / term.ch));
            if (c === term.cols && r === term.rows) return;
            term.cols = c; term.rows = r;
            if (proc.running) proc.write("s " + c + " " + r + "\n");
        }
    }

    // ── colours: the wallpaper's terminal palette ────────────────────────────
    property var pal: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/terminal/kitty-theme.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const p = {};
            for (const l of text().split("\n")) {
                const m = l.match(/^(\w+)\s+(#[0-9a-fA-F]{6})/);
                if (m) p[m[1]] = m[2];
            }
            term.pal = p;
        }
    }
    readonly property color fg: pal.foreground || App.Console.text
    readonly property color bg: pal.background || App.Console.bg
    function idx(n) {
        if (n < 16) return term.pal["color" + n] || ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5", "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff"][n];
        if (n < 232) {
            const v = [0, 95, 135, 175, 215, 255], i = n - 16;
            return Qt.rgba(v[Math.floor(i / 36)] / 255, v[Math.floor(i / 6) % 6] / 255, v[i % 6] / 255, 1);
        }
        const g = (8 + (n - 232) * 10) / 255;
        return Qt.rgba(g, g, g, 1);
    }
    function col(c, dflt) { return !c ? dflt : c[0] === "#" ? c : term.idx(Number(c.slice(1))); }
    function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;"); }
    // a row as rich text: one span per run of one style
    function html(runs) {
        let s = "";
        for (const [t, f, b, fl] of runs) {
            let fc = term.col(f, term.fg), bc = b ? term.col(b, term.bg) : null;
            if (fl & 8) { const x = fc; fc = bc || term.bg; bc = x; }    // reverse
            let st = "color:" + fc + ";";
            if (bc) st += "background-color:" + bc + ";";
            if (fl & 1) st += "font-weight:bold;";
            if (fl & 2) st += "font-style:italic;";
            if (fl & 16) st += "opacity:0.6;";
            const deco = (fl & 4 ? "underline " : "") + (fl & 32 ? "line-through" : "");
            if (deco) st += "text-decoration:" + deco + ";";
            s += '<span style="' + st + '">' + term.esc(t) + "</span>";
        }
        return s;
    }

    // ── drawing ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: term.bg
        radius: App.Console.radiusSmall
        border.color: term.activeFocus ? App.Console.data : "transparent"
        border.width: 1
        Column {
            x: 6; y: 4
            Repeater {
                model: term.lines.length
                delegate: Text {
                    required property int index
                    height: term.ch
                    textFormat: Text.RichText
                    text: term.html(term.lines[index] || [])
                    font: fm.font
                    color: term.fg
                }
            }
        }
        Rectangle {
            visible: !!term.cursor && term.activeFocus
            x: 6 + (term.cursor ? term.cursor[0] : 0) * term.cw
            y: 4 + (term.cursor ? term.cursor[1] : 0) * term.ch + (term.shape === "underline" ? term.ch - 2 : 0)
            width: term.shape === "beam" ? 2 : term.cw
            height: term.shape === "underline" ? 2 : term.ch
            color: term.pal.cursor || App.Console.data
            opacity: term.shape === "block" ? 0.7 : 1
        }
        Text {
            anchors.centerIn: parent
            visible: !proc.running
            text: term.dir ? qsTr("Terminal stopped — click to start again") : qsTr("No folder")
            color: App.Console.dim; font.family: App.Console.sans; font.pixelSize: 13
        }
        TapHandler { onTapped: { term.forceActiveFocus(); if (!proc.running && term.dir) proc.running = true; } }
    }

    // ── keys → terminal bytes ────────────────────────────────────────────────
    // a string as UTF-8, in hex (QML's JavaScript has no TextEncoder)
    function bytes(s) {
        let h = "";
        const hex = b => (b < 16 ? "0" : "") + b.toString(16);
        for (const ch of s) {
            const c = ch.codePointAt(0);
            if (c < 0x80) h += hex(c);
            else if (c < 0x800) h += hex(0xc0 | c >> 6) + hex(0x80 | c & 63);
            else if (c < 0x10000) h += hex(0xe0 | c >> 12) + hex(0x80 | c >> 6 & 63) + hex(0x80 | c & 63);
            else h += hex(0xf0 | c >> 18) + hex(0x80 | c >> 12 & 63) + hex(0x80 | c >> 6 & 63) + hex(0x80 | c & 63);
        }
        return h;
    }
    Keys.onPressed: e => {
        const ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier, shift = e.modifiers & Qt.ShiftModifier;
        const csi = "\x1b[";
        const special = {
            [Qt.Key_Return]: "\r", [Qt.Key_Enter]: "\r", [Qt.Key_Backspace]: ctrl ? "\x17" : "\x7f", [Qt.Key_Tab]: "\t", [Qt.Key_Backtab]: csi + "Z",
            [Qt.Key_Escape]: "\x1b", [Qt.Key_Up]: csi + "A", [Qt.Key_Down]: csi + "B", [Qt.Key_Right]: csi + "C", [Qt.Key_Left]: csi + "D",
            [Qt.Key_Home]: csi + "H", [Qt.Key_End]: csi + "F", [Qt.Key_PageUp]: csi + "5~", [Qt.Key_PageDown]: csi + "6~",
            [Qt.Key_Delete]: csi + "3~", [Qt.Key_Insert]: csi + "2~",
            [Qt.Key_F1]: "\x1bOP", [Qt.Key_F2]: "\x1bOQ", [Qt.Key_F3]: "\x1bOR", [Qt.Key_F4]: "\x1bOS", [Qt.Key_F5]: csi + "15~",
            [Qt.Key_F6]: csi + "17~", [Qt.Key_F7]: csi + "18~", [Qt.Key_F8]: csi + "19~", [Qt.Key_F9]: csi + "20~", [Qt.Key_F10]: csi + "21~",
            [Qt.Key_F11]: csi + "23~", [Qt.Key_F12]: csi + "24~",
        };
        let s = special[e.key];
        // arrows with Ctrl/Shift/Alt: xterm's modifier form (CSI 1;m X)
        if (s && s.startsWith(csi) && s.length === 3 && (ctrl || alt || shift)) s = csi + "1;" + (1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0)) + s[2];
        if (!s && ctrl && shift && e.key === Qt.Key_V) { pasteProc.running = true; e.accepted = true; return; }
        if (!s && ctrl && e.key >= Qt.Key_A && e.key <= Qt.Key_Z) s = String.fromCharCode(e.key - Qt.Key_A + 1);
        else if (!s && ctrl && e.key === Qt.Key_Space) s = "\x00";
        else if (!s && ctrl && e.key === Qt.Key_BracketLeft) s = "\x1b";
        else if (!s) s = e.text;
        if (!s) return;
        if (alt && !s.startsWith("\x1b")) s = "\x1b" + s;
        term.write(term.bytes(s));
        e.accepted = true;
    }
    // Ctrl+Shift+V: the clipboard, bracketed as programs expect a paste
    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector { onStreamFinished: term.send("\x1b[200~" + text + "\x1b[201~") }
    }
}
