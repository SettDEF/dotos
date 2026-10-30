import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * The conversation on a task (`dotos thread` / `dotos say`, docs/teams.md Teams 1): who said
 * what, newest at the bottom, @mentions marked, an agent's messages with its icon. Enter sends;
 * it follows new messages while shown.
 */
ColumnLayout {
    id: th
    required property string item          // task:<uid>, project:<name>, page:<id>
    property var msgs: []
    /// what was decided (the task's X-DOTOS-DECISION), shown above the messages
    property string decision: ""
    spacing: 6

    function load() {
        if (!th.item || fetch.running) return;
        fetch.command = [App.Store.bin, "thread", th.item, "--json"];
        fetch.running = true;
    }
    onItemChanged: { th.msgs = []; load(); }
    Component.onCompleted: load()
    Connections { target: App.Store; function onLastLoadChanged() { th.load(); } }
    // another person or an agent may write meanwhile
    Timer { interval: 3000; repeat: true; running: th.visible && th.item !== ""; onTriggered: th.load() }
    Process {
        id: fetch
        stdout: StdioCollector { onStreamFinished: { try { th.msgs = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: send
        onExited: th.load()
    }
    // a message as a task of its own: linked both ways, its @mention does it (dotos task-from)
    Process { id: mk; onExited: { th.load(); App.Store.reload(); } }
    Process { id: dec; onExited: { th.load(); App.Store.reload(); } }
    function decide(id) {
        if (dec.running || !id || id === "pending") return;
        dec.command = [App.Store.bin, "decide", th.item, id];
        dec.running = true;
    }
    /// a quoted passage (a page's selected lines) put into the message box, to discuss it
    function quote(text) {
        field.text = String(text).trim().split("\n").map(l => "> " + l).join("\n") + "\n";
        field.forceActiveFocus();
        field.cursorPosition = field.text.length;
    }
    // voice messages: ffmpeg records the default mic to Ogg Opus (5 min at most), dotos voice sends it
    property string recFile: ""
    Process {
        id: rec
        onExited: if (th.recFile && th.item) { voiceSend.command = [App.Store.bin, "voice", th.item, th.recFile]; voiceSend.running = true; }
    }
    Process { id: voiceSend; onExited: { Quickshell.execDetached(["rm", "-f", th.recFile]); th.load(); } }
    function record() {
        if (!th.item || rec.running) return;
        th.recFile = Quickshell.env("XDG_RUNTIME_DIR") + "/dotos-voice-" + Date.now() + ".ogg";
        rec.command = ["ffmpeg", "-loglevel", "error", "-y", "-f", "pulse", "-i", "default", "-c:a", "libopus", "-b:a", "24k", "-t", "300", th.recFile];
        rec.running = true;
    }
    function makeTask(id) {
        if (mk.running || !id || id === "pending") return;
        mk.command = [App.Store.bin, "task-from", th.item, id];
        mk.running = true;
    }
    function say(text) {
        if (!text.trim() || send.running) return;
        send.command = [App.Store.bin, "say", th.item, text.trim()];
        send.running = true;
        // shown at once; the reload replaces it with the stored one
        th.msgs = th.msgs.concat([{ id: "pending", author: "", name: qsTr("you"), text: text.trim(), ts: Date.now() / 1000, pending: true }]);
    }

    function isAgent(a) { return String(a).startsWith("agent:"); }
    function tone(a) {
        // one colour per person, from the handle
        let h = 0;
        for (const c of String(a)) h = (h * 31 + c.charCodeAt(0)) % 360;
        return Qt.hsla(h / 360, 0.5, 0.62, 1);
    }
    function ago(ts) {
        const d = Math.max(0, Math.floor(App.Store.now / 1000 - ts));
        return d < 60 ? qsTr("now") : d < 3600 ? Math.floor(d / 60) + "m" : d < 86400 ? Math.floor(d / 3600) + "h" : Math.floor(d / 86400) + "d";
    }
    // @handles in the accent colour (the text itself is escaped first)
    function rich(t) {
        const esc = String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return esc.replace(/(^|\s)@([A-Za-z0-9_.-]+)/g, `$1<font color="#${String(Qt.lighter(App.Console.data, 1.7)).slice(-6)}"><b>@$2</b></font>`);
    }

    // the decision, on top: why it is done this way
    Rectangle {
        visible: th.decision.length > 0
        Layout.fillWidth: true
        implicitHeight: decRow.implicitHeight + 14
        radius: App.Console.radiusSmall
        color: Qt.alpha(App.Console.ok, 0.12)
        border.width: 1; border.color: Qt.alpha(App.Console.ok, 0.35)
        RowLayout {
            id: decRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
            spacing: 8
            Ui.Icon { text: "gavel"; size: 16; color: App.Console.ok; Layout.alignment: Qt.AlignTop }
            Text { Layout.fillWidth: true; text: th.decision; wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.DemiBold; color: App.Console.text }
        }
    }
    Text {
        visible: th.msgs.length === 0
        Layout.fillWidth: true
        text: qsTr("No messages yet. Write the first: @name mentions someone.")
        wrapMode: Text.Wrap
        font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
    }

    Repeater {
        model: th.msgs.slice(-30)
        delegate: RowLayout {
            id: msg
            required property var modelData
            readonly property string who: msg.modelData.name || msg.modelData.author
            HoverHandler { id: msgHover }
            Layout.fillWidth: true
            spacing: 8
            opacity: msg.modelData.pending ? 0.55 : 1
            // the avatar: an initial, or a robot for an agent
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 24; implicitHeight: 24; radius: 12
                color: th.isAgent(msg.modelData.author) ? Qt.alpha(App.Console.data, 0.35) : Qt.alpha(th.tone(msg.modelData.author), 0.25)
                Ui.Icon { anchors.centerIn: parent; visible: th.isAgent(msg.modelData.author); text: "smart_toy"; size: 15; color: App.Console.text }
                Text {
                    anchors.centerIn: parent
                    visible: !th.isAgent(msg.modelData.author)
                    text: msg.who.charAt(0).toUpperCase()
                    font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: th.tone(msg.modelData.author)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                RowLayout {
                    spacing: 6
                    Text { text: th.isAgent(msg.modelData.author) ? msg.who.replace(/^agent:/, "") : msg.who; font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.DemiBold; color: App.Console.text }
                    Text { text: th.ago(msg.modelData.ts); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                    Item { Layout.fillWidth: true }
                    // on hover: this message as a task
                    Ui.IconButton {
                        visible: msgHover.hovered && !msg.modelData.pending && th.item.startsWith("task:") && !String(msg.modelData.text).startsWith("✔ decided")
                        implicitWidth: 22; implicitHeight: 22
                        icon: "gavel"
                        tooltip: qsTr("Mark as the decision (shown on top of the task)")
                        onClicked: th.decide(msg.modelData.id)
                    }
                    Ui.IconButton {
                        visible: msgHover.hovered && !msg.modelData.pending && !String(msg.modelData.text).startsWith("→ new task")
                        implicitWidth: 22; implicitHeight: 22
                        icon: "add_task"
                        tooltip: qsTr("Make this a task (its @mention does it)")
                        onClicked: th.makeTask(msg.modelData.id)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: th.rich(msg.modelData.text)
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    font.family: App.Console.sans; font.pixelSize: 13
                    color: App.Console.text
                }
                // a voice message: play it
                Ui.Chip {
                    visible: !!msg.modelData.audio
                    text: qsTr("▶ Play")
                    interactive: true
                    accent: App.Console.data
                    onClicked: Quickshell.execDetached(["mpv", "--no-video", "--really-quiet", msg.modelData.audio])
                }
            }
        }
    }

    // @ suggestions: the team's people (from LAN sync) and the agents, local or on a teammate's machine
    property var team: ({ people: [], agents: ["claude"] })
    Process {
        id: teamProc
        command: [App.Store.bin, "team", "--json"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { th.team = JSON.parse(text); } catch (e) {} } }
    }
    // the @word being typed at the cursor ("" when none)
    readonly property var atWord: { const before = field.text.slice(0, field.cursorPosition); const m = before.match(/@([\w.@-]*)$/); return m ? m[1].toLowerCase() : null; }
    readonly property var suggestions: th.atWord === null ? [] : th.team.people.map(p => ({ handle: p.handle, label: p.name || p.handle, agent: false })).concat(th.team.agents.map(a => ({ handle: a, label: a === "claude" ? qsTr("Claude here") : qsTr("Claude on %1's machine").arg(a.split("@")[1]), agent: true }))).filter(s => s.handle.toLowerCase().startsWith(th.atWord)).slice(0, 6)
    function complete(handle) {
        const before = field.text.slice(0, field.cursorPosition).replace(/@[\w.@-]*$/, "@" + handle + " ");
        field.text = before + field.text.slice(field.cursorPosition);
        field.cursorPosition = before.length;
        field.forceActiveFocus();
    }
    Flow {
        visible: th.suggestions.length > 0 && field.activeFocus
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: th.suggestions
            delegate: Ui.Chip {
                required property var modelData
                text: "@" + modelData.handle + "  " + modelData.label
                interactive: true
                accent: modelData.agent ? App.Console.data : App.Console.ok
                onClicked: th.complete(modelData.handle)
            }
        }
    }
    // write: Enter sends, Shift+Enter is a new line
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: Math.max(34, field.implicitHeight + 10)
        radius: App.Console.radiusSmall
        color: App.Console.panelAlt
        border.width: 1
        border.color: field.activeFocus ? Qt.alpha(App.Console.data, 0.6) : App.Console.rule
        TextArea {
            ContextMenu.menu: Ui.TextMenu { target: field }
            id: field
            anchors { fill: parent; leftMargin: 6; rightMargin: 34 }
            placeholderText: th.item.startsWith("page:") ? qsTr("Write on this page…  @name mentions") : qsTr("Write on this task…  @name mentions")
            placeholderTextColor: App.Console.faint
            wrapMode: TextEdit.Wrap
            font.family: App.Console.sans; font.pixelSize: 13
            color: App.Console.text
            background: null
            Keys.onTabPressed: (e) => { if (th.suggestions.length) th.complete(th.suggestions[0].handle); else e.accepted = false; }
            Keys.onReturnPressed: (e) => {
                if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; }
                th.say(field.text); field.text = "";
            }
            Keys.onEscapePressed: field.focus = false
        }
        // an empty box: the mic records a voice message (click again to send it)
        Ui.IconButton {
            visible: field.text.trim().length === 0
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            implicitWidth: 26; implicitHeight: 26
            icon: rec.running ? "stop_circle" : "mic"
            tooltip: rec.running ? qsTr("Stop and send the voice message") : qsTr("Record a voice message")
            onClicked: rec.running ? rec.signal(2) : th.record()
        }
        Ui.IconButton {
            visible: field.text.trim().length > 0
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            implicitWidth: 26; implicitHeight: 26
            icon: "send"
            tooltip: qsTr("Send  (Enter)")
            enabled: field.text.trim().length > 0
            onClicked: { th.say(field.text); field.text = ""; }
        }
    }
}
