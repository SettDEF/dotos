import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * One project's mission control: its numbers, its board, the TASKS.md lines
 * (ticked in the file itself), the agents working in its folder, its docs.
 * Buttons to act where the project lives: a terminal there, a new Claude
 * session there, the folder, a timer.
 */
Item {
    id: page
    property string key: "project"
    readonly property var p: App.Store.project(App.Nav.project)
    readonly property var agentsHere: page.p ? App.Store.agentsIn(page.p.path) : []
    readonly property var docOpen: (page.p?.doc_tasks ?? []).filter(t => !t.done)
    property var remoteData: null
    property bool remoteLoading: false
    // a project without a remote (only local git) shows no Remote card; another error shows itself
    readonly property bool noRemote: !!page.remoteData && page.remoteData.error === "no remote detected"
    readonly property string remoteError: page.remoteData?.error && !page.noRemote ? String(page.remoteData.error) : ""

    function loadRemote() {
        if (!page.p || remoteLoading) return;
        remoteLoading = true;
        remoteProc.command = [App.Store.bin, "git", "remote", page.p.name, "--json"];
        remoteProc.running = true;
    }

    Process {
        id: remoteProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.remoteData = JSON.parse(text); } catch (e) { page.remoteData = null; }
                page.remoteLoading = false;
            }
        }
        stderr: StdioCollector { onStreamFinished: { page.remoteLoading = false; } }
    }

    onPChanged: { page.remoteData = null; if (page.p) page.loadRemote(); }

    component Kpi: Rectangle {
        id: kpi
        property string label: ""
        property string value: ""
        property string sub: ""
        property color tone: App.Console.text
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 80
        radius: 14
        color: App.Console.panel
        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 1
            Text { text: kpi.label; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim }
            Text { text: kpi.value; font.family: App.Console.mono; font.pixelSize: 19; font.weight: Font.Medium; color: kpi.tone; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { visible: kpi.sub.length > 0; text: kpi.sub; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint; elide: Text.ElideRight; Layout.fillWidth: true }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: page.p?.name ?? qsTr("Project")
            subtitle: page.p ? page.p.path : qsTr("no project chosen")
            Ui.IconButton { icon: "arrow_back"; tooltip: qsTr("All projects"); onClicked: App.Nav.go("projects") }
            Ui.IconButton { icon: "terminal"; tooltip: qsTr("Terminal here"); onClicked: App.Store.terminalAt(page.p.path) }
            Ui.IconButton { icon: "smart_toy"; tooltip: qsTr("New Claude session here"); onClicked: Quickshell.execDetached(["wezterm", "start", "--always-new-process", "--cwd", page.p.path, "--", "claude"]) }
            Ui.IconButton { icon: "folder_open"; tooltip: qsTr("Open the folder"); onClicked: App.Store.openFolder(page.p.path) }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!page.p
            contentHeight: col.implicitHeight + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: col
                x: 14; y: 14
                width: parent.width - 28
                spacing: 12

                // a narrow window: the counts in two columns, the board scrolls sideways, the panels one under another
                readonly property bool narrow: width < 900
                GridLayout {
                    Layout.fillWidth: true
                    columns: col.narrow ? 2 : 5
                    columnSpacing: 10; rowSpacing: 10
                    Kpi { label: qsTr("Branch"); value: page.p?.git?.branch || "—"; sub: page.p?.git ? (page.p.git.ahead ? qsTr("↑%1 not pushed").arg(page.p.git.ahead) : qsTr("in sync")) : qsTr("no git") }
                    Kpi { label: qsTr("Uncommitted"); value: String(page.p?.git?.dirty ?? 0); sub: page.p?.git?.dirty ? qsTr("for %1 days").arg(page.p.git.dirty_days) : qsTr("clean"); tone: (page.p?.git?.dirty_days ?? 0) >= 3 ? App.Console.warn : App.Console.text }
                    Kpi { label: qsTr("Open tasks"); value: String(page.p?.open ?? 0); sub: qsTr("%1 overdue · %2 in TASKS.md").arg(page.p?.overdue ?? 0).arg(page.p?.doc_open ?? 0); tone: (page.p?.overdue ?? 0) > 0 ? App.Console.crit : App.Console.text }
                    Kpi { label: qsTr("Agents"); value: String(page.agentsHere.length); sub: page.agentsHere.some(a => a.state === "needs_you") ? qsTr("one waits for you") : qsTr("in this folder"); tone: page.agentsHere.some(a => a.state === "needs_you") ? App.Console.crit : App.Console.text }
                    Kpi { label: qsTr("This week"); value: App.Store.dur(page.p?.time_week_s); sub: qsTr("%1 commits").arg(page.p?.git?.commits_week ?? 0) }
                }

                Connections { target: App.Nav; function onAction(name) { if (name === "capture") projectCapture.take(); } }
                App.CaptureField {
                    id: projectCapture
                    Layout.fillWidth: true
                    placeholder: qsTr("New task in %1…").arg(page.p?.name ?? "")
                    suffix: page.p ? "+" + page.p.name : ""
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(320, page.height * 0.45)
                    clip: true
                    contentWidth: Math.max(width, 5 * 240)
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    App.BoardPage {
                        width: parent.width; height: parent.height
                        embedded: true
                        project: page.p?.name ?? "~"
                    }
                }

                // Remote git section: PRs, issues, branches, commits, CI
                App.Panel {
                    Layout.fillWidth: true
                    visible: !!page.remoteData && !page.noRemote
                    title: qsTr("Remote")
                    icon: "cloud"
                    note: page.remoteLoading ? qsTr("loading...") : (page.remoteData?.owner ? (page.remoteData.provider + " · " + page.remoteData.owner + "/" + page.remoteData.repo) : "")
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        App.Label { text: qsTr("Pull requests"); visible: (page.remoteData?.pull_requests ?? []).length > 0 }
                        Repeater {
                            model: page.remoteData?.pull_requests ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                spacing: 8
                                Ui.Icon { text: "merge"; size: 16; color: App.Console.data }
                                Text { Layout.fillWidth: true; text: "#" + modelData.number + " " + modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                App.Tag { text: modelData.state; tone: modelData.state === "open" ? App.Console.ok : App.Console.dim }
                                Text { text: modelData.author; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (modelData.url) Qt.openUrlExternally(modelData.url) }
                            }
                        }

                        App.Label { text: qsTr("Issues"); visible: (page.remoteData?.issues ?? []).length > 0; Layout.topMargin: 4 }
                        Repeater {
                            model: page.remoteData?.issues ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                spacing: 8
                                Ui.Icon { text: "error"; size: 16; color: App.Console.warn }
                                Text { Layout.fillWidth: true; text: "#" + modelData.number + " " + modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                App.Tag { text: modelData.state; tone: modelData.state === "open" ? App.Console.ok : App.Console.dim }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (modelData.url) Qt.openUrlExternally(modelData.url) }
                            }
                        }

                        App.Label { text: qsTr("Branches"); visible: (page.remoteData?.branches ?? []).length > 0; Layout.topMargin: 4 }
                        Repeater {
                            model: page.remoteData?.branches ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 24
                                spacing: 8
                                Ui.Icon { text: "fork_right"; size: 14; color: App.Console.data }
                                Text { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
                                App.Tag { text: modelData.protected ? "protected" : ""; visible: modelData.protected; tone: App.Console.warn }
                                Text { text: modelData.commit.substring(0, 7); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                            }
                        }

                        App.Label { text: qsTr("Commits"); visible: (page.remoteData?.commits ?? []).length > 0; Layout.topMargin: 4 }
                        Repeater {
                            model: page.remoteData?.commits ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                spacing: 8
                                Ui.Icon { text: "commit"; size: 14; color: App.Console.data }
                                Text { Layout.fillWidth: true; text: modelData.message; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text }
                                Text { text: modelData.author; font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                Text { text: modelData.hash.substring(0, 7); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (modelData.url) Qt.openUrlExternally(modelData.url) }
                            }
                        }

                        App.Label { text: qsTr("CI runs"); visible: (page.remoteData?.ci_runs ?? []).length > 0; Layout.topMargin: 4 }
                        Repeater {
                            model: page.remoteData?.ci_runs ?? []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                spacing: 8
                                Ui.Icon { text: "play_circle"; size: 14; color: modelData.conclusion === "success" ? App.Console.ok : (modelData.conclusion === "failure" ? App.Console.crit : App.Console.warn) }
                                Text { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.text }
                                App.Tag { text: modelData.conclusion || modelData.status; tone: modelData.conclusion === "success" ? App.Console.ok : (modelData.conclusion === "failure" ? App.Console.crit : App.Console.warn) }
                                Text { text: modelData.branch; font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (modelData.url) Qt.openUrlExternally(modelData.url) }
                            }
                        }
                        Text {
                            visible: !!page.remoteData && (page.remoteError.length > 0 || page.remoteData.authenticated === false)
                            Layout.fillWidth: true
                            text: page.remoteError.length > 0 ? qsTr("Could not read the remote: %1").arg(page.remoteError) : qsTr("Not authenticated - connect an account with 'dotos git connect' to see PRs and issues.")
                            font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.warn
                            wrapMode: Text.Wrap
                        }

                        Text {
                            visible: page.remoteLoading
                            text: qsTr("Loading remote data...")
                            font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
                        }
                    }
                }

                GridLayout {   // TASKS.md beside the agents and docs, or under each other in a narrow window
                    Layout.fillWidth: true
                    columns: col.narrow ? 1 : 2; columnSpacing: 12; rowSpacing: 12

                    App.Panel {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 3
                        Layout.alignment: Qt.AlignTop
                        title: "TASKS.md"
                        icon: "checklist"
                        note: page.docOpen.length ? qsTr("%1 open · edit").arg(page.docOpen.length) : qsTr("edit")
                        onNoteClicked: App.Store.edit(page.p.path + "/TASKS.md")
                        Repeater {
                            model: (page.p?.doc_tasks ?? []).filter(t => !t.done).slice(0, 14)
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                spacing: 10
                                Rectangle {
                                    implicitWidth: 16; implicitHeight: 16; radius: 5
                                    color: dHov.hovered ? Qt.alpha(App.Console.data, 0.25) : "transparent"
                                    border.width: 2; border.color: App.Console.data
                                    HoverHandler { id: dHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: App.Store.projectCheck(page.p.name, modelData.line, true) }
                                }
                                Text { Layout.fillWidth: true; text: modelData.text; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.text }
                                Text { text: modelData.section; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint; elide: Text.ElideRight; Layout.maximumWidth: 160 }
                            }
                        }
                        Text {
                            visible: (page.p?.doc_tasks ?? []).length === 0
                            text: qsTr("No TASKS.md in this project. Its - [ ] lines would show here.")
                            font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        App.Panel {
                            Layout.fillWidth: true
                            title: qsTr("Agents here")
                            icon: "smart_toy"
                            note: page.agentsHere.length ? "" : qsTr("none")
                            Repeater {
                                model: page.agentsHere
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    spacing: 8
                                    Ui.Icon { text: App.Store.agentIcon(modelData); size: 17; color: App.Store.agentColor(modelData) }
                                    Text { Layout.fillWidth: true; text: App.Store.clean(modelData.state === "needs_you" ? modelData.message : modelData.prompt) || modelData.state; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                    App.Tag { text: qsTr("Jump"); tone: App.Console.data; TapHandler { onTapped: App.Store.jump(modelData) } HoverHandler { cursorShape: Qt.PointingHandCursor } }
                                }
                            }
                        }
                        App.Panel {
                            Layout.fillWidth: true
                            title: qsTr("Docs")
                            icon: "description"
                            iconColor: App.Console.ok
                            Repeater {
                                model: page.p?.docs ?? []
                                delegate: Rectangle {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: 8
                                    color: docHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
                                    HoverHandler { id: docHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: App.Store.edit(page.p.path + "/" + modelData) }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 6 }
                                        Ui.Icon { text: "article"; size: 16; color: App.Console.dim }
                                        Text { text: modelData; font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text }
                                    }
                                }
                            }
                            Repeater {
                                model: App.Store.pages.filter(pg => pg.project.toLowerCase() === (page.p?.name ?? "").toLowerCase())
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: 8
                                    color: pgHov.hovered ? Qt.alpha(App.Console.text, 0.05) : "transparent"
                                    HoverHandler { id: pgHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: App.Nav.openPage(modelData.id) }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 6 }
                                        Ui.Icon { text: "sticky_note_2"; size: 16; color: App.Console.dim }
                                        Text { text: modelData.title; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: !!page.p?.git?.last_subject
                                text: qsTr("last commit: %1 %2 · %3").arg(page.p?.git?.last_hash ?? "").arg(page.p?.git?.last_subject ?? "").arg(App.Store.ago(page.p?.git?.last_time))
                                wrapMode: Text.Wrap
                                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: !page.p
            Layout.alignment: Qt.AlignCenter
            Layout.fillHeight: true
            text: qsTr("Pick a project on the Projects page.")
            font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim
        }
    }
}
