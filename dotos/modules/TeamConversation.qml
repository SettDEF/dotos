import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * The conversation open in the middle: its messages (`dotos thread ITEM --json`), grouped while
 * one person keeps talking, a divider for each day, @mentions marked, voice messages playable. The
 * box at the bottom writes through `dotos say` (Store.run): Enter sends, Shift+Enter is a new line,
 * Tab completes an @name, Esc leaves the box (the page takes the keys again).
 */
Rectangle {
    id: convo
    property var info: null          // the open conversation (an entry of Team.items), or null
    readonly property string item: convo.info ? convo.info.item : ""
    property var msgs: []
    property var pending: []         // what we sent, until the store has it
    property bool forceEnd: false    // a send scrolls to the newest
    property bool moved: false       // the reader scrolled up: arriving messages do not pull them down
    readonly property bool composing: field.activeFocus
    readonly property var rows: convo._rows(convo.msgs.concat(convo.pending))
    readonly property var atWord: {
        const m = field.text.slice(0, field.cursorPosition).match(/@([\w.@-]*)$/);
        return m ? m[1].toLowerCase() : null;
    }
    readonly property var suggestions: convo.atWord === null ? [] : App.Team.mentionables.filter(s => s.handle.toLowerCase().startsWith(convo.atWord)).slice(0, 6)
    property var _drafts: ({})
    property string _prev: ""
    signal leave()

    color: App.Console.panel
    radius: App.Console.radius
    clip: true

    function focusComposer() { if (convo.item) field.forceActiveFocus(); }

    onItemChanged: {
        if (convo._prev) convo._drafts[convo._prev] = field.text;
        convo._prev = convo.item;
        field.text = convo._drafts[convo.item] ?? "";
        convo.msgs = [];
        convo.pending = [];
        convo.moved = false;
        convo.load();
    }
    Component.onCompleted: convo.load()
    Connections { target: App.Store; function onLastLoadChanged() { convo.load(); } }
    Timer { interval: 10000; running: convo.item !== ""; repeat: true; onTriggered: convo.load() }

    function load() {
        if (!convo.item) return;
        if (fetch.running) { fetch.again = true; return; }
        fetch.forItem = convo.item;
        fetch.running = true;
    }
    Process {
        id: fetch
        property bool again: false
        property string forItem: ""
        command: [App.Store.bin, "thread", convo.item || "-", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (fetch.forItem !== convo.item) return;
                try {
                    const ms = JSON.parse(text);
                    const old = convo.msgs;
                    const same = ms.length === old.length && (ms.length === 0 || ms[ms.length - 1].id === old[old.length - 1].id);
                    if (!same) convo.msgs = ms;
                    // our sent line leaves the pending list once the store has it (or 30 s on)
                    convo.pending = convo.pending.filter(p => !ms.some(m => m.text === p.text && m.author === p.author) && Date.now() / 1000 - p.ts < 30);
                } catch (e) {}
            }
        }
        onExited: { if (fetch.again) { fetch.again = false; convo.load(); } }
    }

    // groups of consecutive messages from one author, with a divider for each day
    function _rows(list) {
        const out = [];
        let day = "", prev = null;
        for (const m of list) {
            const d = new Date(m.ts * 1000).toDateString();
            if (d !== day) { day = d; out.push({ kind: "day", label: App.Team.dayLabel(m.ts) }); prev = null; }
            const head = !prev || prev.author !== m.author || m.ts - prev.ts > 300;
            out.push({ kind: "msg", m, head });
            prev = m;
        }
        return out;
    }

    function send() {
        const text = field.text.trim();
        if (!text || !convo.item) return;
        field.text = "";
        convo._drafts[convo.item] = "";
        convo.pending = convo.pending.concat([{ id: "pending", author: App.Team.me, name: App.Team.meName || qsTr("you"), text, ts: Date.now() / 1000, pending: true }]);
        convo.forceEnd = true;
        App.Team.say(convo.item, text);
    }
    function complete(handle) {
        const before = field.text.slice(0, field.cursorPosition).replace(/@[\w.@-]*$/, "@" + handle + " ");
        field.text = before + field.text.slice(field.cursorPosition);
        field.cursorPosition = before.length;
    }
    function openItem() {
        const i = convo.info;
        if (!i) return;
        if (i.kind === "task") App.Nav.openTask(i.id);
        else if (i.kind === "project") App.Nav.openProject(i.id);
        else if (i.kind === "page") App.Nav.openPage(i.id);
    }
    readonly property bool canOpen: !!convo.info && ((convo.info.kind === "task" && App.Store.task(convo.info.id) !== null)
        || (convo.info.kind === "project" && App.Store.project(convo.info.id) !== null)
        || convo.info.kind === "page")

    // ── nothing open ──────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 380)
        visible: !convo.info
        spacing: 8
        Ui.Icon { Layout.alignment: Qt.AlignHCenter; text: "forum"; size: 40; color: App.Console.faint }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Pick a conversation")
            font.family: App.Console.sans; font.pixelSize: 16; font.weight: Font.DemiBold; color: App.Console.dim
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: qsTr("Up and Down move between them. A message starts one: dotos say ITEM TEXT, or write on a task.")
            font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!convo.info
        spacing: 0

        // the header: what the conversation is about
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 12
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            spacing: 10
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: 11
                color: Qt.alpha(App.Team.tone(convo.item), 0.18)
                Ui.Icon { anchors.centerIn: parent; text: App.Team.kindIcon(convo.info?.kind ?? ""); size: 19; color: App.Team.tone(convo.item) }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: convo.info?.title ?? ""
                    elide: Text.ElideRight
                    font.family: App.Console.sans; font.pixelSize: 16; font.weight: Font.DemiBold; color: App.Console.text
                }
                Text {
                    Layout.fillWidth: true
                    text: App.Team.kindLabel(convo.info?.kind ?? "") + "  ·  " + qsTr("%n message(s)", "", convo.info?.count ?? 0)
                    elide: Text.ElideRight
                    font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                }
            }
            Ui.IconButton {
                visible: convo.canOpen
                icon: "open_in_new"
                tooltip: convo.info?.kind === "task" ? qsTr("Open the task") : convo.info?.kind === "project" ? qsTr("Open the project") : qsTr("Open the page")
                onClicked: convo.openItem()
            }
        }

        // the messages
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: msgList
                anchors.fill: parent
                clip: true
                model: convo.rows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
                onCountChanged: {
                    if (convo.forceEnd || !convo.moved) Qt.callLater(() => msgList.positionViewAtEnd());
                    convo.forceEnd = false;
                }
                onMovementEnded: convo.moved = !atYEnd
                onFlickEnded: convo.moved = !atYEnd

                delegate: Item {
                    id: line
                    required property var modelData
                    readonly property var m: modelData.m ?? ({ text: "", author: "", name: "", ts: 0 })
                    readonly property bool mine: m.author === App.Team.me
                    width: ListView.view.width
                    height: col.implicitHeight

                    ColumnLayout {
                        id: col
                        anchors { left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18 }
                        spacing: 0

                        Text {
                            visible: line.modelData.kind === "day"
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            Layout.bottomMargin: 4
                            horizontalAlignment: Text.AlignHCenter
                            text: line.modelData.label ?? ""
                            font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.Medium
                            color: App.Console.faint
                        }

                        RowLayout {
                            visible: line.modelData.kind === "msg"
                            Layout.fillWidth: true
                            Layout.topMargin: line.modelData.head ? 12 : 1
                            spacing: 10

                            Item {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 32
                                implicitHeight: line.modelData.head ? 32 : 1
                                App.TeamAvatar {
                                    visible: !!line.modelData.head
                                    size: 32
                                    who: line.m.author
                                    label: App.Team.nameOf(line.m)
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    visible: !!line.modelData.head
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        text: App.Team.nameOf(line.m)
                                        font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                                        color: line.mine ? App.Console.data : App.Console.text
                                    }
                                    Text {
                                        text: App.Team.stamp(line.m.ts)
                                        font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: App.Team.rich(line.m.text)
                                    textFormat: Text.StyledText
                                    wrapMode: Text.Wrap
                                    font.family: App.Console.sans; font.pixelSize: 14
                                    color: App.Console.text
                                    opacity: line.m.pending ? 0.5 : 1
                                    lineHeight: 1.15
                                }
                                Ui.Chip {
                                    visible: !!line.m.audio
                                    text: qsTr("▶ Play voice message")
                                    interactive: true
                                    accent: App.Console.data
                                    onClicked: Quickshell.execDetached(["mpv", "--no-video", "--really-quiet", line.m.audio])
                                }
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: convo.rows.length === 0
                text: qsTr("No messages yet. Write the first: @name mentions someone.")
                font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint
            }
        }

        // completions for an @word being typed
        Flow {
            visible: convo.suggestions.length > 0 && field.activeFocus
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.topMargin: 6
            spacing: 6
            Repeater {
                model: convo.suggestions
                delegate: Ui.Chip {
                    required property var modelData
                    text: "@" + modelData.handle + "  " + modelData.label
                    interactive: true
                    accent: modelData.agent ? App.Console.data : App.Console.ok
                    onClicked: convo.complete(modelData.handle)
                }
            }
        }

        // the box: Enter sends, Shift+Enter a new line
        Rectangle {
            id: composer
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.topMargin: 8
            Layout.bottomMargin: 14
            Layout.preferredHeight: Math.min(150, Math.max(46, field.contentHeight + 22))
            radius: App.Console.radiusSmall
            color: App.Console.panelAlt
            border.width: 1
            border.color: field.activeFocus ? Qt.alpha(App.Console.data, 0.6) : "transparent"

            TextArea {
                id: field
                anchors.fill: parent
                leftPadding: 12; rightPadding: 44; topPadding: 11; bottomPadding: 11
                placeholderText: convo.info?.kind === "page" ? qsTr("Write on this page…  @name mentions")
                    : convo.info?.kind === "project" ? qsTr("Write on this project…  @name mentions")
                    : qsTr("Write on this task…  @name mentions")
                placeholderTextColor: App.Console.faint
                wrapMode: TextEdit.Wrap
                font.family: App.Console.sans; font.pixelSize: 14
                color: App.Console.text
                background: null
                ContextMenu.menu: Ui.TextMenu { target: field }
                Keys.onReturnPressed: (e) => {
                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; }
                    e.accepted = true;
                    convo.send();
                }
                Keys.onEnterPressed: (e) => {
                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; }
                    e.accepted = true;
                    convo.send();
                }
                Keys.onTabPressed: (e) => {
                    if (convo.suggestions.length) { e.accepted = true; convo.complete(convo.suggestions[0].handle); }
                    else e.accepted = false;
                }
                Keys.onEscapePressed: (e) => { e.accepted = true; convo.leave(); }
            }
            Ui.IconButton {
                visible: field.text.trim().length > 0
                anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                implicitWidth: 32; implicitHeight: 32
                icon: "send"
                tooltip: qsTr("Send  (Enter)")
                onClicked: convo.send()
            }
        }
    }
}
