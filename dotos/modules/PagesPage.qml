import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * Pages and the journal: plain markdown files, edited here with autosave.
 * Checkboxes in a page are tasks (they show on Home and in its project);
 * [[links]] connect pages, and a page lists who links to it. The journal is
 * one page per day, made from a template the first time you open today.
 */
Item {
    id: page
    property string key: "pages"
    readonly property bool journal: page.key === "journal"
    property string filter: ""
    readonly property var list: App.Store.pages.filter(p => (page.journal ? p.kind === "journal" : p.kind === "page")
        && (!page.filter || (p.title + " " + p.tags.join(" ") + " " + p.project + " " + p.excerpt).toLowerCase().includes(page.filter.toLowerCase())))
        .sort((a, b) => page.journal ? b.id.localeCompare(a.id) : b.modified - a.modified)
    readonly property var current: App.Store.pages.find(p => p.id === App.Nav.pageId && (p.kind === "journal") === page.journal) ?? page.list[0] ?? null
    // keys: j/k the page, e edits it in zett, n a new one
    readonly property var keyHelp: [[qsTr("Move"), ["j", "k"]], [qsTr("Edit in zett"), ["e"]], [qsTr("New page"), ["n"]]]
    function handleKey(e) {
        const i = page.list.findIndex(p => p.id === page.current?.id);
        const m = K.move(e, page.list.length, i);
        if (m >= 0) { App.Nav.pageId = page.list[m].id; return true; }
        if (!K.plain(e)) return false;
        if ((e.key === Qt.Key_E || K.isOpen(e)) && page.current?.path) { App.Store.edit(page.current.path); return true; }
        if (e.key === Qt.Key_N && !page.journal) { App.Store.pageNew(qsTr("Untitled"), "", path => App.Nav.openPage(String(path).split("/").pop().replace(/\.md$/, ""))); return true; }
        return false;
    }
    readonly property var backlinks: page.current ? App.Store.pages.filter(p => p.links.some(l => l.toLowerCase() === page.current.title.toLowerCase() || l === page.current.id)) : []
    /// the column beside the editor with what this note is connected to (wide windows: on)
    property bool showConnected: width > 900

    Connections {
        target: App.Nav
        function onAction(name) { if (name === "search") search.forceActiveFocus(); }
    }

    // the open file: loaded once per page, saved shortly after typing stops
    property bool dirty: false
    FileView {
        id: file
        path: page.current?.path ?? ""
        watchChanges: true
        onFileChanged: if (!page.dirty) file.reload()
        onLoaded: { if (!page.dirty) editor.text = file.text(); }
    }
    Timer { id: saveTimer; interval: 700; onTriggered: { file.setText(editor.text); page.dirty = false; } }
    onCurrentChanged: { if (page.dirty) { file.setText(editor.text); page.dirty = false; } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: page.journal ? qsTr("Journal") : qsTr("Pages")
            subtitle: page.journal ? qsTr("%1 days written").arg(page.list.length) : qsTr("%1 pages · %2 open checkboxes").arg(page.list.length).arg(App.Store.pageTasks.length)
            Rectangle {
                implicitWidth: 196; implicitHeight: 28; radius: 14
                color: Qt.alpha(App.Console.text, 0.05)
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                    spacing: 6
                    Ui.Icon { text: "search"; size: 15; color: App.Console.faint }
                    TextField {
                        ContextMenu.menu: Ui.TextMenu { target: search }
                        id: search
                        Layout.fillWidth: true
                        placeholderText: qsTr("Find  ( / )")
                        placeholderTextColor: App.Console.faint
                        background: null
                        color: App.Console.text
                        font.family: App.Console.sans; font.pixelSize: 12
                        onTextChanged: page.filter = text
                    }
                }
            }
            Rectangle {
                implicitWidth: newRow.implicitWidth + 24; implicitHeight: 28; radius: 14
                color: App.Console.data
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: page.journal ? App.Nav.run("journal-today")
                        : App.Store.pageNew(qsTr("Untitled"), "", path => App.Nav.openPage(path.split("/pages/").pop().replace(/\.md$/, "")))
                }
                Row {
                    id: newRow
                    anchors.centerIn: parent
                    spacing: 6
                    Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: page.journal ? "today" : "note_add"; size: 16; color: App.Console.onData }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: page.journal ? qsTr("Today") : qsTr("New page"); font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.DemiBold; color: App.Console.onData }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 12

            // the list
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                radius: App.Console.radius
                color: App.Console.panel
                ListView {
                    anchors { fill: parent; margins: 6 }
                    clip: true
                    spacing: 2
                    model: page.list
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: page.current?.id === modelData.id
                        width: ListView.view.width
                        height: 58
                        radius: 10
                        color: on ? Qt.alpha(App.Console.data, 0.16) : lHov.hovered ? App.Console.panelAlt : "transparent"
                        HoverHandler { id: lHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.Nav.pageId = modelData.id }
                        ColumnLayout {
                            anchors { fill: parent; margins: 8; leftMargin: 10 }
                            spacing: 1
                            Text { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; font.weight: on ? Font.DemiBold : Font.Normal; color: App.Console.text }
                            Text {
                                Layout.fillWidth: true
                                text: [modelData.project ? "+" + modelData.project : "", modelData.tasks.filter(t => !t.done).length ? qsTr("%1 open").arg(modelData.tasks.filter(t => !t.done).length) : "", App.Store.ago(modelData.modified)].filter(s => s).join(" · ")
                                elide: Text.ElideRight
                                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: page.list.length === 0
                        width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: page.journal ? qsTr("No journal yet. “Today” starts one, filled with what is due.") : qsTr("No pages yet. Notes, plans, research — with checkboxes that become tasks.")
                        font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
                    }
                }
            }

            // nothing open yet
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !page.current
                radius: App.Console.radius
                color: App.Console.panel
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    width: Math.min(parent.width - 60, 420)
                    Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: page.journal ? "edit_note" : "description"; size: 44; color: App.Console.faint }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: page.journal ? qsTr("Start today's page") : qsTr("Write your first page")
                        font.family: App.Console.sans; font.pixelSize: 20; font.weight: Font.DemiBold; color: App.Console.text }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: page.journal ? qsTr("The page is made from what is due today, with room for notes and what you finished. One page a day, plain markdown.")
                            : qsTr("Notes, plans and research as plain markdown. A checkbox in a page becomes a task; [[Another note]] links two pages together.")
                        font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.dim }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: ctaRow.implicitWidth + 28; implicitHeight: 38; radius: 19
                        color: ctaHov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data
                        HoverHandler { id: ctaHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.journal ? App.Nav.run("journal-today") : App.Store.pageNew(qsTr("Untitled"), "", path => App.Nav.openPage(String(path).split("/").pop().replace(/\.md$/, ""))) }
                        Row {
                            id: ctaRow
                            anchors.centerIn: parent
                            spacing: 7
                            Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: page.journal ? "today" : "add"; size: 18; color: App.Console.onData }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: page.journal ? qsTr("Write today's page  (Ctrl J)") : qsTr("New page"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.onData }
                        }
                    }
                }
            }

            // the editor
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: App.Console.radius
                color: App.Console.panel
                visible: !!page.current
                ColumnLayout {
                    anchors { fill: parent; margins: 14 }
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { Layout.fillWidth: true; text: page.current?.title ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 19; font.weight: Font.DemiBold; color: App.Console.text }
                        Text { text: page.dirty ? qsTr("saving…") : qsTr("saved"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                        App.Tag { visible: !!page.current?.project; text: "+" + (page.current?.project ?? ""); tone: App.Store.colorOf(page.current?.project); TapHandler { onTapped: App.Nav.openProject(page.current.project) } }
                        Ui.IconButton { implicitWidth: 30; implicitHeight: 30; icon: "hub"; tooltip: page.showConnected ? qsTr("Hide what it is connected to") : qsTr("What it is connected to"); onClicked: page.showConnected = !page.showConnected }
                        Ui.IconButton { implicitWidth: 30; implicitHeight: 30; icon: "open_in_new"; tooltip: qsTr("Open in your editor"); onClicked: App.Store.edit(page.current.path) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            TextArea {
                                ContextMenu.menu: Ui.TextMenu { target: editor }
                                id: editor
                                persistentSelection: true
                                wrapMode: TextEdit.Wrap
                                font.family: App.Console.mono
                                font.pixelSize: 14
                                color: App.Console.text
                                selectByMouse: true
                                background: Rectangle { radius: 10; color: App.Console.bg }
                                padding: 14
                                onTextChanged: if (activeFocus) { page.dirty = true; saveTimer.restart(); }
                            }
                        }
                        // its corner of the graph: notes linking here and from here, its tasks, its project
                        ColumnLayout {
                            visible: page.showConnected
                            Layout.preferredWidth: 300
                            Layout.maximumWidth: 300
                            Layout.alignment: Qt.AlignTop
                            spacing: 12
                            App.LocalGraph {
                                visible: around.length > 0
                                Layout.fillWidth: true
                                nodeId: page.current ? "page:" + page.current.id : ""
                            }
                            // Teams: the page's conversation; selected lines can be quoted into it
                            Ui.Chip {
                                visible: editor.selectedText.length > 0
                                text: qsTr("Discuss selection")
                                interactive: true
                                accent: App.Console.data
                                onClicked: pageThread.quote(editor.selectedText)
                            }
                            App.TaskThread { id: pageThread; Layout.fillWidth: true; item: page.current ? "page:" + page.current.id : "" }
                        }
                    }
                    // checkboxes and backlinks
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: (page.current?.tasks ?? []).filter(t => !t.done)
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: tRow.implicitWidth + 16; implicitHeight: 26; radius: 13
                                    color: cbHov.hovered ? Qt.alpha(App.Console.ok, 0.18) : Qt.alpha(App.Console.text, 0.05)
                                    HoverHandler { id: cbHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { page.dirty = false; App.Store.pageCheck(page.current.id, modelData.line, true); } }
                                    Row {
                                        id: tRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: cbHov.hovered ? "check_box" : "check_box_outline_blank"; size: 15; color: App.Console.ok }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text; width: Math.min(implicitWidth, 260); elide: Text.ElideRight }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            spacing: 6
                            Text { visible: page.backlinks.length > 0; text: qsTr("linked from"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            Repeater {
                                model: page.backlinks.slice(0, 4)
                                delegate: App.Tag { required property var modelData; text: modelData.title; tone: App.Console.data; TapHandler { onTapped: App.Nav.openPage(modelData.id) } }
                            }
                            Ui.Chip { text: qsTr("In the graph"); interactive: true; accent: App.Console.dim; onClicked: { App.Nav.graphSel = "page:" + page.current.id; App.Nav.go("graph"); } }
                        }
                    }
                }

            }
        }
    }
}
