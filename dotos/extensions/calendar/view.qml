// @name    Calendar
// @about   Your Kalends events and your Dotos tasks on one timeline: the next two weeks, day by day, with a line to add an event. Needs the kalends CLI.
// @kind    view
//
// A view extension: Dotos shows this file as a page and hands it `dotos`
// (palette, store, nav, run). Events come from the same `kalends` CLI the
// terminal and the Kalends window use; tasks from Dotos itself.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: page
    property string key: ""
    property var dotos: null
    readonly property var pal: dotos?.palette ?? null
    readonly property int days: 14

    function iso(d) { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; }
    function addDays(n) { const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() + n); return d; }
    readonly property string from: page.iso(page.addDays(0))
    readonly property string to: page.iso(page.addDays(page.days))

    // ── events: kalends, refreshed when the page opens and every few minutes ──
    property var events: []
    property string error: ""
    Process {
        id: list
        command: ["sh", "-c", "PATH=$HOME/.local/bin:$PATH exec kalends list --from \"$1\" --to \"$2\" --json", "sh", page.from, page.to]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.events = JSON.parse(this.text || "[]"); page.error = ""; }
                catch (e) { page.error = qsTr("kalends answered something that is not JSON"); }
            }
        }
        onExited: code => { if (code !== 0) page.error = qsTr("kalends is not installed, or failed (%1)").arg(code); }
    }
    function reload() { list.running = false; list.running = true; }
    Component.onCompleted: page.reload()
    Timer { interval: 5 * 60 * 1000; running: true; repeat: true; onTriggered: page.reload() }

    Process {
        id: adder
        stdout: StdioCollector { onStreamFinished: if (page.dotos) page.dotos.say(qsTr("Added to the calendar")) }
        onExited: code => { if (code !== 0 && page.dotos) page.dotos.say(qsTr("kalends could not add it (%1)").arg(code)); page.reload(); }
    }
    /// "Dentist @fri 14:00" style is Dotos' capture; here: "Title @YYYY-MM-DD HH:MM", "@today 18:00", "@tomorrow" — kalends' --at
    function add(line) {
        const m = String(line).match(/^(.*?)\s*@(.+)$/);
        const title = (m ? m[1] : line).trim();
        if (!title) return;
        const args = ["kalends", "add", title];
        if (m) args.push("--at", m[2].trim());
        adder.command = ["sh", "-c", "PATH=$HOME/.local/bin:$PATH exec \"$@\"", "sh"].concat(args);
        adder.running = true;
    }

    // ── the merged timeline ──
    readonly property var timeline: {
        const out = [];
        const tasks = page.dotos?.store?.open ?? [];
        for (let i = 0; i <= page.days; i++) {
            const day = page.iso(page.addDays(i));
            const ev = page.events.filter(e => {
                const s = String(e.start).slice(0, 10);
                const end = String(e.end ?? e.start).slice(0, 10);
                return e.all_day ? (s <= day && day < end) || s === day : s === day;
            });
            const due = tasks.filter(t => String(t.due ?? "").slice(0, 10) === day);
            if (ev.length || due.length || i === 0) out.push({ day, ev, due, i });
        }
        return out;
    }

    Rectangle { anchors.fill: parent; color: page.pal?.bg ?? "#141218" }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: !!page.pal

        // the same toolbar shape as Dotos' own pages
        Item {
            Layout.fillWidth: true
            implicitHeight: 70
            ColumnLayout {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 120 }
                spacing: 0
                Text { text: qsTr("Calendar"); font.family: page.pal?.sans ?? ""; font.pixelSize: 22; font.weight: Font.DemiBold; color: page.pal?.text ?? "white" }
                Text {
                    Layout.fillWidth: true
                    text: {
                        if (page.error) return page.error;
                        const e = page.timeline.reduce((n, d) => n + d.ev.length, 0), t = page.timeline.reduce((n, d) => n + d.due.length, 0);
                        return (e === 1 ? qsTr("1 event") : qsTr("%1 events").arg(e)) + " · " + (t === 1 ? qsTr("1 task due") : qsTr("%1 tasks due").arg(t)) + " · " + qsTr("next two weeks");
                    }
                    elide: Text.ElideRight
                    font.family: page.pal?.mono ?? ""; font.pixelSize: 12
                    color: page.error ? (page.pal?.crit ?? "red") : (page.pal?.dim ?? "grey")
                }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: page.pal?.rule ?? "#22ffffff" }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: col
                x: 24; y: 18
                width: Math.min(860, flick.width - 48)
                spacing: 14

                // one line to add an event
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 20
                    color: page.pal?.panel ?? "#222"
                    border.width: 1
                    border.color: addField.activeFocus ? Qt.alpha(page.pal?.data ?? "white", 0.7) : (page.pal?.rule ?? "#22ffffff")
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                        spacing: 10
                        Text { text: "+"; font.pixelSize: 18; color: page.pal?.data ?? "white" }
                        TextInput {
                            id: addField
                            Layout.fillWidth: true
                            clip: true
                            font.family: page.pal?.sans ?? ""; font.pixelSize: 15
                            color: page.pal?.text ?? "white"
                            onAccepted: { page.add(text); text = ""; }
                            Text {
                                visible: addField.text.length === 0
                                text: qsTr("New event — Dentist @tomorrow 14:00 · Trip @2026-11-20")
                                font: addField.font
                                color: page.pal?.faint ?? "grey"
                            }
                        }
                    }
                }

                Repeater {
                    model: page.timeline
                    delegate: RowLayout {
                        id: dayRow
                        required property var modelData
                        readonly property date d: new Date(modelData.day + "T12:00:00")
                        readonly property bool isToday: modelData.i === 0
                        Layout.fillWidth: true
                        spacing: 18
                        ColumnLayout {
                            Layout.preferredWidth: 64
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            Text { text: dayRow.isToday ? qsTr("Today") : Qt.formatDate(dayRow.d, "ddd"); font.family: page.pal.sans; font.pixelSize: 12; color: dayRow.isToday ? page.pal.data : page.pal.dim }
                            Text { text: Qt.formatDate(dayRow.d, "d"); font.family: page.pal.sans; font.pixelSize: 26; font.weight: Font.DemiBold; color: dayRow.isToday ? page.pal.data : page.pal.text }
                            Text { text: Qt.formatDate(dayRow.d, "MMM"); font.family: page.pal.mono; font.pixelSize: 11; color: page.pal.faint }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: dayCol.implicitHeight + 22
                            radius: page.pal.radius
                            color: page.pal.panel
                            ColumnLayout {
                                id: dayCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11; leftMargin: 14 }
                                spacing: 6
                                Text {
                                    visible: dayRow.modelData.ev.length === 0 && dayRow.modelData.due.length === 0
                                    text: qsTr("Nothing today — a free day")
                                    font.family: page.pal.sans; font.pixelSize: 13; color: page.pal.faint
                                }
                                // events: a time and a coloured bar, like Kalends
                                Repeater {
                                    model: dayRow.modelData.ev
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Rectangle { implicitWidth: 4; implicitHeight: 26; radius: 2; color: page.pal.data }
                                        Text {
                                            Layout.preferredWidth: 92
                                            text: modelData.all_day ? qsTr("all day") : String(modelData.start).slice(11, 16) + (modelData.end ? " – " + String(modelData.end).slice(11, 16) : "")
                                            font.family: page.pal.mono; font.pixelSize: 12; color: page.pal.dim
                                        }
                                        Text { Layout.fillWidth: true; text: modelData.summary ?? ""; elide: Text.ElideRight; font.family: page.pal.sans; font.pixelSize: 15; color: page.pal.text }
                                        Text { text: modelData.calendar ?? ""; font.family: page.pal.mono; font.pixelSize: 11; color: page.pal.faint }
                                    }
                                }
                                // tasks due that day: tick them here
                                Repeater {
                                    model: dayRow.modelData.due
                                    delegate: RowLayout {
                                        id: task
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Rectangle {
                                            implicitWidth: 18; implicitHeight: 18; radius: 9
                                            color: "transparent"; border.width: 1.5; border.color: page.pal.dim
                                            TapHandler { onTapped: page.dotos.store.toggleDone(task.modelData) }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        }
                                        Text {
                                            Layout.preferredWidth: 78
                                            text: String(task.modelData.due ?? "").length > 10 ? String(task.modelData.due).slice(11, 16) : qsTr("due")
                                            font.family: page.pal.mono; font.pixelSize: 12; color: page.pal.dim
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: task.modelData.title
                                            elide: Text.ElideRight
                                            font.family: page.pal.sans; font.pixelSize: 15; color: page.pal.text
                                            TapHandler { onTapped: page.dotos.openTask(task.modelData.uid) }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        }
                                        Text { text: qsTr("task"); font.family: page.pal.mono; font.pixelSize: 11; color: page.pal.faint }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
