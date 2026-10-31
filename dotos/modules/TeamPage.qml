import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * Team: the conversations (tasks, projects, pages, newest first) on the left, the one open in the
 * middle, the people and agents on the right. A view onto the dotos CLI: Team reads, and what is
 * written goes through `dotos say`. Up / Down (or j / k) move between the conversations, Enter
 * writes in the box, Esc leaves it.
 */
Item {
    id: page
    property string key: "team"
    property string current: ""
    readonly property var list: App.Team.items
    readonly property int cur: list.findIndex(i => i.item === page.current)
    readonly property var selected: page.cur >= 0 ? page.list[page.cur] : null
    readonly property var keyHelp: [[qsTr("Previous / next conversation"), ["↑", "↓"]], [qsTr("Write in it"), ["Enter"]],
        [qsTr("Leave the box"), ["Esc"]], [qsTr("New line in the box"), ["Shift", "Enter"]]]

    function pick(item) { page.current = item; }
    // while the box has the keys, they are typed, not the page's
    function handleKey(e) {
        if (convo.composing) return false;
        const m = K.move(e, page.list.length, page.cur);
        if (m >= 0) { page.pick(page.list[m].item); convs.reveal(m); return true; }
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && K.plain(e) && page.selected) { convo.focusComposer(); return true; }
        return false;
    }
    onListChanged: if (page.cur < 0 && page.list.length > 0) page.current = page.list[0].item;
    Component.onCompleted: { App.Team.refresh(); if (page.list.length > 0 && page.cur < 0) page.current = page.list[0].item; }

    // the page holds the keys when no box does (Esc in the box hands them back here)
    Item { id: sink; focus: true; width: 0; height: 0 }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Team")
            subtitle: !App.Team.loaded ? qsTr("reading the team…")
                : App.Team.hasTeam ? App.Team.teamName + "  ·  " + qsTr("%n conversation(s)", "", page.list.length)
                : qsTr("no team yet, so only this computer's messages")
            Ui.IconButton {
                visible: App.Team.unreadTotal > 0
                icon: "done_all"
                tooltip: qsTr("Mark everything read")
                onClicked: App.Team.markRead()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            spacing: 10

            App.TeamList {
                id: convs
                Layout.preferredWidth: page.width < 760 ? 240 : 300
                Layout.fillHeight: true
                items: page.list
                current: page.current
                onPicked: item => { page.pick(item); sink.forceActiveFocus(); }
            }
            App.TeamConversation {
                id: convo
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 300
                info: page.selected
                onLeave: sink.forceActiveFocus()
            }
            App.TeamPeople {
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                visible: page.width >= 900
            }
        }
    }
}
