import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "." as App
import "../ui" as Ui
import "keynav.js" as K

/**
 * The day as a timeline. Left: what to do next, then the hours with each task
 * as a block as tall as its estimate, placed around the meetings and the
 * tasks that have a fixed time. The day ends where what is left of your
 * workday ends (the hours already tracked today are gone), so what does not
 * fit says so. Right: the day in numbers, what does not fit, and tomorrow.
 * Hover a block to start the timer, tick it or push it a day; drag it to
 * change the order; click its estimate to step it (a "~" marks a guess).
 * The numbers come from `dotos plan`; the placement is done here.
 */
Item {
    id: page
    property string key: "plan"

    // ── which day, and what the CLI says about it ──────────────────────
    property int dayOffset: 0
    // keys: h/l the day before / after, t today
    readonly property var keyHelp: [[qsTr("Day before / after"), ["h", "l"]], [qsTr("Today"), ["t"]]]
    function handleKey(e) {
        const d = K.side(e);
        if (d) { page.dayOffset += d; return true; }
        if (K.plain(e) && e.key === Qt.Key_T) { page.dayOffset = 0; return true; }
        return false;
    }
    readonly property date base: new Date((App.Store.today || Qt.formatDate(new Date(), "yyyy-MM-dd")) + "T12:00:00")
    readonly property date day: new Date(page.base.getTime() + page.dayOffset * 86400000)
    readonly property string dayIso: Qt.formatDate(page.day, "yyyy-MM-dd")
    readonly property string nextIso: Qt.formatDate(new Date(page.day.getTime() + 86400000), "yyyy-MM-dd")
    readonly property real hours: App.Store.config?.workHours ?? 6
    property var plan: null
    property var tomorrow: null
    property var review: null
    property var agenda: []
    readonly property bool today: page.dayOffset === 0
    readonly property bool selected: !!App.Store.task(App.Nav.selected)

    function fmt(m) {
        m = Math.max(0, Math.round(m ?? 0));
        return m < 60 ? m + "m" : (m % 60 === 0 ? (m / 60) + "h" : Math.floor(m / 60) + "h" + String(m % 60).padStart(2, "0"));
    }
    function clock(m) { m = Math.round(m); return String(Math.floor(m / 60) % 24).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); }
    function minutesOf(iso) { return iso ? parseInt(String(iso).slice(11, 13)) * 60 + parseInt(String(iso).slice(14, 16)) : 0; }

    function reload() {
        if (planProc.running || tomProc.running) { reloadTimer.restart(); return; }
        planProc.running = true;
        tomProc.running = true;
    }
    onDayIsoChanged: page.reload()
    onHoursChanged: page.reload()
    Connections { target: App.Store; function onLastLoadChanged() { page.reload(); } }
    Timer { id: reloadTimer; interval: 300; onTriggered: page.reload() }
    Component.onCompleted: { page.reload(); reviewProc.running = true; agendaProc.running = true; }
    property int nowTick: 0
    Timer { interval: 60000; running: true; repeat: true; onTriggered: page.nowTick++ }

    Process {
        id: planProc
        command: [App.Store.bin, "plan", "--json", "--date", page.dayIso, "--hours", String(page.hours)]
        stdout: StdioCollector { onStreamFinished: { try { page.plan = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: tomProc
        command: [App.Store.bin, "plan", "--json", "--date", page.nextIso, "--hours", String(page.hours)]
        stdout: StdioCollector { onStreamFinished: { try { page.tomorrow = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: reviewProc
        command: [App.Store.bin, "review", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { page.review = JSON.parse(text); } catch (e) {} } }
    }
    // the calendar, from Kalends (today only: its agenda is asked for one day)
    Process {
        id: agendaProc
        command: [Quickshell.env("HOME") + "/.local/bin/kalends", "agenda", "--days", "1", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { page.agenda = JSON.parse(text) ?? []; } catch (e) { page.agenda = []; } } }
    }

    // ── placing the day ────────────────────────────────────────────────
    readonly property real workStart: (page.plan?.work_start ?? 9) * 60
    readonly property real nowMin: { page.nowTick; const d = new Date(App.Store.now); return d.getHours() * 60 + d.getMinutes(); }
    /// where the first task can start: now (rounded up), or the start of the workday
    readonly property real cursor0: page.today ? Math.max(page.workStart, Math.ceil(page.nowMin / 5) * 5) : page.workStart
    /// what is left of the day is what the CLI says is left: the hours already tracked are gone
    readonly property real dayEnd: page.cursor0 + (page.plan?.capacity_min ?? page.hours * 60)
    /// the first hour drawn
    readonly property real tlStart: page.today ? Math.max(page.workStart, Math.floor(page.nowMin / 60) * 60) : page.workStart
    readonly property int spanHours: Math.max(1, Math.ceil((page.dayEnd - page.tlStart) / 60))
    readonly property real hourH: Math.max(92, Math.min(120, (page.height - 260) / page.spanHours))
    readonly property real spanH: page.spanHours * page.hourH
    readonly property real gutter: 58

    readonly property var events: page.today ? page.agenda.filter(e => !e.all_day && e.start).map(e => {
        const s = page.minutesOf(e.start);
        const en = e.end ? page.minutesOf(e.end) : s + 60;
        return { title: e.summary ?? "", s, e: Math.max(en, s + 15), cal: e.calendar ?? "" };
    }) : []

    /// { blocks: [{ it, s, e, fixed }], over: [item] } — timed tasks stay where they are, the rest fill the gaps in order
    readonly property var placed: {
        const items = page.plan?.items ?? [];
        const blocks = [], over = [];
        const busy = page.events.map(e => [e.s, e.e]);
        const isFixed = it => it.due_time && String(it.due ?? "").slice(0, 10) === page.dayIso;
        for (const it of items.filter(isFixed)) {
            const s = page.minutesOf(it.due);
            blocks.push({ it, s, e: s + it.est_min, fixed: true });
            busy.push([s, s + it.est_min]);
        }
        let cur = page.cursor0;
        for (const it of items.filter(i => !isFixed(i))) {
            let s = cur, moved = true;
            while (moved) { moved = false; for (const [bs, be] of busy) if (s < be && s + it.est_min > bs) { s = be; moved = true; } }
            if (s + it.est_min > page.dayEnd) { over.push(it); continue; }
            blocks.push({ it, s, e: s + it.est_min, fixed: false });
            busy.push([s, s + it.est_min]);
            cur = s + it.est_min;
        }
        blocks.sort((a, b) => a.s - b.s);
        return { blocks, over };
    }
    readonly property var next: page.placed.blocks.length ? (page.placed.blocks.find(b => b.e > page.cursor0) ?? page.placed.blocks[0]) : null

    /// the day's plan by project, for the stacked bar: [{ name, min, color }]
    readonly property var split: {
        const m = {};
        for (const it of page.plan?.items ?? []) { const k = it.project || it.list || "—"; m[k] = (m[k] ?? 0) + it.est_min; }
        return Object.keys(m).sort((a, b) => m[b] - m[a]).map(k => ({ name: k, min: m[k], color: App.Store.colorOf(k) }));
    }
    readonly property int guessed: (page.plan?.items ?? []).filter(i => i.est_guess).length

    readonly property var estSteps: [15, 30, 45, 60, 90, 120, 180]
    function stepEstimate(it) {
        const i = page.estSteps.findIndex(v => v > it.est_min);
        App.Store.set(it.uid, ["estimate=" + page.estSteps[i < 0 ? 0 : i] + "m"]);
    }
    function setAllGuessed(min) { for (const it of (page.plan?.items ?? []).filter(i => i.est_guess)) App.Store.set(it.uid, ["estimate=" + min + "m"]); }

    /// after a drag: the new order of the untimed blocks, written as ORDER=10,20,30…
    function reorder(uid, centerMin) {
        const loose = page.placed.blocks.filter(b => !b.fixed && b.it.uid !== uid);
        let at = 0;
        for (const b of loose) if ((b.s + b.e) / 2 < centerMin) at++;
        const uids = loose.map(b => b.it.uid);
        uids.splice(at, 0, uid);
        uids.forEach((u, i) => App.Store.set(u, ["order=" + ((i + 1) * 10)]));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Plan")
            subtitle: page.plan ? qsTr("%1 · %2 planned of %3 left").arg(Qt.formatDate(page.day, "dddd d MMMM")).arg(page.fmt(page.plan.planned_min)).arg(page.fmt(page.plan.capacity_min)) : ""
            Ui.IconButton { icon: "chevron_left"; tooltip: qsTr("Previous day"); onClicked: page.dayOffset-- }
            Ui.IconButton { icon: "today"; tooltip: qsTr("Today"); active: page.dayOffset === 0; onClicked: page.dayOffset = 0 }
            Ui.IconButton { icon: "chevron_right"; tooltip: qsTr("Next day"); onClicked: page.dayOffset++ }
            Rectangle {
                implicitWidth: hrow.implicitWidth + 16; implicitHeight: 36; radius: 18
                color: App.Console.panelAlt
                RowLayout {
                    id: hrow
                    anchors.centerIn: parent
                    spacing: 4
                    Ui.IconButton { implicitWidth: 26; implicitHeight: 26; icon: "remove"; tooltip: qsTr("Shorter workday"); onClicked: App.Store.setConfig("workHours", Math.max(1, page.hours - 0.5)) }
                    Text { text: page.hours + qsTr(" h day"); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                    Ui.IconButton { implicitWidth: 26; implicitHeight: 26; icon: "add"; tooltip: qsTr("Longer workday"); onClicked: App.Store.setConfig("workHours", Math.min(16, page.hours + 0.5)) }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 14

            // ── the day, hour by hour ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 940
                Layout.fillHeight: true
                spacing: 10

                // what to do now
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 66
                    radius: App.Console.radius
                    color: App.Console.panel
                    visible: !!page.next
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                        spacing: 12
                        Rectangle { implicitWidth: 4; implicitHeight: 38; radius: 2; color: page.next ? App.Store.colorOf(page.next.it.project || page.next.it.list) : "transparent" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: page.today ? qsTr("Next up") : qsTr("First"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            Text { Layout.fillWidth: true; text: page.next?.it.title ?? ""; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 18; font.weight: Font.DemiBold; color: App.Console.text }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text { Layout.alignment: Qt.AlignRight; text: page.next ? page.clock(page.next.s) + " – " + page.clock(page.next.e) : ""; font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text }
                            Text { Layout.alignment: Qt.AlignRight; text: page.next ? page.fmt(page.next.it.est_min) + (page.next.it.est_guess ? " (a guess)" : "") : ""; font.family: App.Console.mono; font.pixelSize: 11; color: page.next?.it.est_guess ? App.Console.warn : App.Console.faint }
                        }
                        Rectangle {
                            implicitWidth: startRow.implicitWidth + 24; implicitHeight: 38; radius: 19
                            color: startHov.hovered ? Qt.lighter(App.Console.data, 1.1) : App.Console.data
                            HoverHandler { id: startHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: App.Store.track(page.next.it.uid) }
                            Row {
                                id: startRow
                                anchors.centerIn: parent
                                spacing: 5
                                Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: "play_arrow"; filled: true; size: 20; color: App.Console.onData }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Start"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.onData }
                            }
                        }
                        Ui.IconButton { icon: "check"; tooltip: qsTr("Done"); onClicked: App.Store.setState(page.next.it.uid, "done") }
                    }
                }

                // the timeline
                Flickable {
                    id: scroller
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: tl.height + 24
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Item {
                        id: tl
                        y: 12        // room for the first hour label
                        width: scroller.width - 8
                        height: page.spanH + 4
                        readonly property real laneW: tl.width - page.gutter - 4
                        readonly property bool hasEvents: page.events.length > 0
                        readonly property real taskW: tl.hasEvents ? tl.laneW * 0.7 : tl.laneW

                        // the hours
                        Repeater {
                            model: page.spanHours + 1
                            delegate: Item {
                                required property int index
                                y: index * page.hourH
                                width: tl.width
                                Text { x: 0; width: page.gutter - 12; y: -height / 2; horizontalAlignment: Text.AlignRight; text: page.clock(page.tlStart + index * 60); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                Rectangle { x: page.gutter; width: tl.width - page.gutter; height: 1; color: App.Console.grid }
                                Rectangle { visible: index < page.spanHours; x: page.gutter; y: page.hourH / 2; width: tl.width - page.gutter; height: 1; color: Qt.alpha(App.Console.text, 0.03) }
                            }
                        }
                        // after the end of what is left of the day
                        Rectangle {
                            visible: page.dayEnd < page.tlStart + page.spanHours * 60
                            x: page.gutter; width: tl.width - page.gutter
                            y: (page.dayEnd - page.tlStart) / 60 * page.hourH
                            height: page.spanH - y
                            color: Qt.alpha(App.Console.text, 0.03)
                            Text { anchors { left: parent.left; top: parent.top; margins: 8 } text: qsTr("end of the workday"); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                        }

                        // meetings: a lane of their own
                        Repeater {
                            model: page.events
                            delegate: Rectangle {
                                required property var modelData
                                readonly property real yTop: Math.max(0, (modelData.s - page.tlStart) / 60 * page.hourH)
                                readonly property real yBottom: Math.min(page.spanH, (modelData.e - page.tlStart) / 60 * page.hourH)
                                visible: yBottom > yTop
                                x: page.gutter + tl.taskW + 8
                                y: yTop + 1
                                width: tl.laneW - tl.taskW - 8
                                height: Math.max(26, yBottom - yTop - 2)
                                radius: 10
                                color: Qt.alpha(App.Store.colorOf(modelData.cal), 0.14)
                                border.width: 1
                                border.color: Qt.alpha(App.Store.colorOf(modelData.cal), 0.5)
                                clip: true
                                Column {
                                    anchors { fill: parent; margins: 8 }
                                    Text { width: parent.width; text: modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.DemiBold; color: App.Console.text }
                                    Text { text: page.clock(modelData.s) + " – " + page.clock(modelData.e); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.dim }
                                }
                            }
                        }

                        // the tasks
                        Repeater {
                            model: page.placed.blocks
                            delegate: Rectangle {
                                id: blk
                                required property var modelData
                                readonly property var it: blk.modelData.it
                                readonly property color tone: App.Store.colorOf(blk.it.project || blk.it.list)
                                readonly property bool sel: App.Nav.selected === blk.it.uid
                                // room for the time line under the title; tiny ones get one smaller line
                                readonly property bool tall: blk.height >= 40
                                readonly property bool tiny: blk.height < 30
                                property real dy: 0
                                property bool dragging: false
                                property bool editing: false
                                visible: blk.modelData.e > page.tlStart
                                x: page.gutter + 6
                                y: (blk.modelData.s - page.tlStart) / 60 * page.hourH + 2.5 + blk.dy
                                width: tl.taskW - 6
                                height: Math.max(24, (blk.modelData.e - blk.modelData.s) / 60 * page.hourH - 5)
                                z: blk.dragging ? 10 : 1
                                radius: blk.tiny ? 8 : 10
                                color: blk.sel ? Qt.alpha(blk.tone, 0.28) : bHov.hovered ? Qt.alpha(blk.tone, 0.2) : Qt.alpha(blk.tone, 0.13)
                                border.width: blk.dragging || blk.sel ? 1.5 : 1
                                border.color: Qt.alpha(blk.tone, blk.dragging || blk.sel ? 0.85 : 0.22)
                                Behavior on y { enabled: !blk.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 100 } }
                                clip: true

                                // the project's colour: a pill inside the rounded edge (a square bar stuck out of it)
                                Rectangle { x: 5; y: blk.tiny ? 5 : 7; width: 3; height: parent.height - 2 * y; radius: 1.5; color: blk.tone }
                                HoverHandler { id: bHov }
                                MouseArea {
                                    anchors.fill: parent
                                    preventStealing: true
                                    cursorShape: blk.modelData.fixed ? Qt.PointingHandCursor : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                    property real y0: 0
                                    onPressed: m => { y0 = mapToItem(tl, m.x, m.y).y; }
                                    onPositionChanged: m => {
                                        if (!pressed || blk.modelData.fixed) return;
                                        const d = mapToItem(tl, m.x, m.y).y - y0;
                                        if (Math.abs(d) > 5) blk.dragging = true;
                                        if (blk.dragging) blk.dy = d;
                                    }
                                    onReleased: {
                                        if (blk.dragging) {
                                            const center = page.tlStart + (blk.y + blk.height / 2) / page.hourH * 60;
                                            blk.dragging = false; blk.dy = 0;
                                            page.reorder(blk.it.uid, center);
                                        } else App.Nav.selected = blk.it.uid;
                                    }
                                    onDoubleClicked: blk.editing = true
                                }
                                ColumnLayout {
                                    // short blocks: centred; long ones: from the top
                                    anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 10 }
                                    y: blk.height < 64 ? (blk.height - height) / 2 : 8
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Ui.Icon { visible: blk.modelData.fixed; text: "lock_clock"; size: 15; color: App.Console.dim }
                                        Text { Layout.fillWidth: true; text: blk.it.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: blk.tiny ? 13 : 14; font.weight: Font.DemiBold; color: App.Console.text }
                                        Ui.Icon { visible: blk.it.priority === "high"; text: "flag"; filled: true; size: 14; color: App.Console.crit }
                                        // the estimate: click to step it; a guess is outlined, not filled
                                        Rectangle {
                                            visible: !blk.editing && !(bHov.hovered && !blk.dragging)
                                            implicitWidth: estT.implicitWidth + 12; implicitHeight: blk.tiny ? 18 : 20; radius: height / 2
                                            color: blk.it.est_guess ? "transparent" : Qt.alpha(App.Console.text, 0.07)
                                            border.width: blk.it.est_guess ? 1 : 0
                                            border.color: Qt.alpha(App.Console.warn, 0.45)
                                            Text { id: estT; anchors.centerIn: parent; text: (blk.it.est_guess ? "~" : "") + page.fmt(blk.it.est_min); font.family: App.Console.mono; font.pixelSize: 11; color: blk.it.est_guess ? App.Console.warn : App.Console.dim }
                                        }
                                        // actions, while the pointer is on it
                                        Row {
                                            visible: bHov.hovered && !blk.dragging && !blk.editing
                                            spacing: 2
                                            Rectangle {
                                                implicitWidth: estH.implicitWidth + 14; implicitHeight: 24; radius: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: eHov.hovered ? Qt.alpha(App.Console.warn, 0.3) : Qt.alpha(App.Console.text, 0.1)
                                                HoverHandler { id: eHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: page.stepEstimate(blk.it) }
                                                Text { id: estH; anchors.centerIn: parent; text: (blk.it.est_guess ? "~" : "") + page.fmt(blk.it.est_min); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
                                                Ui.Tip { visible: eHov.hovered; text: qsTr("Click to step the estimate  ·  double-click the block to type one") }
                                            }
                                            Ui.IconButton { implicitWidth: 26; implicitHeight: 26; icon: "play_arrow"; tooltip: qsTr("Start the timer"); onClicked: App.Store.track(blk.it.uid) }
                                            Ui.IconButton { implicitWidth: 26; implicitHeight: 26; icon: "check"; tooltip: qsTr("Done"); onClicked: App.Store.setState(blk.it.uid, "done") }
                                            Ui.IconButton { implicitWidth: 26; implicitHeight: 26; icon: "schedule"; tooltip: qsTr("Push to tomorrow"); onClicked: App.Store.snooze(blk.it.uid, "tomorrow") }
                                        }
                                        TextField {
                                            id: textField1
                                            ContextMenu.menu: Ui.TextMenu { target: textField1 }
                                            visible: blk.editing
                                            implicitWidth: 76; implicitHeight: 26
                                            text: page.fmt(blk.it.est_min)
                                            font.family: App.Console.mono; font.pixelSize: 12
                                            color: App.Console.text
                                            background: Rectangle { radius: 8; color: App.Console.bg; border.width: 1; border.color: App.Console.data }
                                            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                            onAccepted: { if (text.trim()) App.Store.set(blk.it.uid, ["estimate=" + text.trim()]); blk.editing = false; }
                                            onActiveFocusChanged: if (!activeFocus) blk.editing = false
                                            Keys.onEscapePressed: blk.editing = false
                                        }
                                    }
                                    RowLayout {
                                        visible: blk.tall
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Text { text: page.clock(blk.modelData.s) + " – " + page.clock(blk.modelData.e); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.dim }
                                        Text { visible: !!(blk.it.project); text: "+" + blk.it.project; font.family: App.Console.mono; font.pixelSize: 11; color: blk.tone }
                                        Item { Layout.fillWidth: true }
                                        Text { visible: blk.it.overdue; text: App.Store.dueLabel(blk.it); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.crit }
                                    }
                                }
                            }
                        }

                        // now
                        Item {
                            visible: page.today && page.nowMin >= page.tlStart && page.nowMin <= page.tlStart + page.spanHours * 60
                            y: (page.nowMin - page.tlStart) / 60 * page.hourH
                            width: tl.width
                            z: 20
                            Rectangle { x: page.gutter - 4; y: -1; width: tl.width - page.gutter + 4; height: 2; color: App.Console.crit }
                            Rectangle { x: page.gutter - 9; y: -5; width: 10; height: 10; radius: 5; color: App.Console.crit }
                            Text { x: 0; width: page.gutter - 14; y: -height / 2; horizontalAlignment: Text.AlignRight; text: page.clock(page.nowMin); font.family: App.Console.mono; font.pixelSize: 11; font.weight: Font.DemiBold; color: App.Console.crit }
                        }

                        // nothing to place
                        Column {
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: page.spanH * 0.25 }
                            visible: !!page.plan && page.placed.blocks.length === 0
                            spacing: 8
                            Ui.Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "event_available"; size: 40; color: App.Console.faint }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: page.placed.over.length ? qsTr("Nothing fits in what is left of today.") : qsTr("Nothing ready for this day."); font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; visible: !page.placed.over.length; text: qsTr("Capture one with a date and a size:  Call dentist @today ~30m"); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                            Ui.Chip { anchors.horizontalCenter: parent.horizontalCenter; visible: !page.placed.over.length; text: qsTr("Add a task  (Ctrl N)"); interactive: true; accent: App.Console.data; onClicked: App.Nav.run("capture") }
                        }
                    }
                }
            }

            // ── the day in numbers (or the selected task) ──
            Item {
                Layout.preferredWidth: Math.round(Math.max(330, Math.min(420, page.width * 0.3)))
                Layout.fillHeight: true

                App.TaskInspector {
                    anchors.fill: parent
                    visible: page.selected
                }

                Flickable {
                    anchors.fill: parent
                    visible: !page.selected
                    contentHeight: side.implicitHeight + 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ColumnLayout {
                        id: side
                        width: parent.width
                        spacing: 12

                        // today in numbers
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sumCol.implicitHeight + 28
                            radius: App.Console.radius
                            color: App.Console.panel
                            ColumnLayout {
                                id: sumCol
                                anchors { fill: parent; margins: 14 }
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: page.fmt(page.plan?.capacity_min); font.family: App.Console.mono; font.pixelSize: 30; font.weight: Font.DemiBold; color: App.Console.text }
                                    Text { Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 5; text: page.today ? qsTr("left today") : qsTr("available"); font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.dim }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        visible: !!page.plan
                                        implicitWidth: balT.implicitWidth + 16; implicitHeight: 24; radius: 12
                                        color: Qt.alpha((page.plan?.over_min ?? 0) > 0 ? App.Console.crit : App.Console.ok, 0.16)
                                        Text { id: balT; anchors.centerIn: parent; text: (page.plan?.over_min ?? 0) > 0 ? qsTr("%1 over").arg(page.fmt(page.plan.over_min)) : qsTr("%1 spare").arg(page.fmt((page.plan?.capacity_min ?? 0) - (page.plan?.planned_min ?? 0)))
                                            font.family: App.Console.mono; font.pixelSize: 12; font.weight: Font.DemiBold; color: (page.plan?.over_min ?? 0) > 0 ? App.Console.crit : App.Console.ok }
                                    }
                                }
                                // planned against what is left, by project; the line is where what is left ends
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 18
                                    Rectangle {
                                        visible: (page.plan?.over_min ?? 0) > 0
                                        x: parent.width * (page.plan?.capacity_min ?? 0) / splitBar.total - 1
                                        y: 0; width: 2; height: 18; radius: 1
                                        color: App.Console.text
                                        z: 2
                                    }
                                Row {
                                    id: splitBar
                                    y: 3
                                    width: parent.width
                                    height: 12
                                    spacing: 1
                                    readonly property real total: Math.max(1, Math.max(page.plan?.capacity_min ?? 0, page.plan?.planned_min ?? 0))
                                    Repeater {
                                        model: page.split
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: Math.max(2, splitBar.width * modelData.min / splitBar.total - 1)
                                            height: 12; radius: 4
                                            color: modelData.color
                                            HoverHandler { id: sbHov }
                                            Ui.Tip { visible: sbHov.hovered; title: modelData.name; rows: [{ name: qsTr("planned"), value: page.fmt(modelData.min) }] }
                                        }
                                    }
                                }
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 12
                                    rowSpacing: 3
                                    Text { text: qsTr("planned"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                    Text { Layout.alignment: Qt.AlignRight; text: page.fmt(page.plan?.planned_min); font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text }
                                    Text { text: qsTr("tracked so far"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                    Text { Layout.alignment: Qt.AlignRight; text: page.fmt(page.plan?.tracked_min); font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text }
                                    Text { text: qsTr("workday"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                    Text { Layout.alignment: Qt.AlignRight; text: page.hours + " h"; font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text }
                                    Text { visible: page.events.length > 0; text: qsTr("meetings"); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                    Text { visible: page.events.length > 0; Layout.alignment: Qt.AlignRight; text: page.events.length + " · " + page.fmt(page.events.reduce((a, e) => a + e.e - e.s, 0)); font.family: App.Console.mono; font.pixelSize: 13; color: App.Console.text }
                                }
                                // most estimates are guesses: set them all at once
                                ColumnLayout {
                                    visible: page.guessed > 0
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: App.Console.rule }
                                    Text { Layout.fillWidth: true; text: qsTr("%1 of these have no estimate yet (counted as 30m, marked ~).").arg(page.guessed); wrapMode: Text.Wrap; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.warn }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Repeater {
                                            model: [15, 30, 60, 90]
                                            delegate: Ui.Chip { required property int modelData; text: qsTr("all %1").arg(page.fmt(modelData)); interactive: true; accent: App.Console.warn; onClicked: page.setAllGuessed(modelData) }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: !!page.review && page.review.tasks.length >= 3 && page.review.median_ratio && Math.abs(page.review.median_ratio - 1) > 0.2
                                    text: qsTr("Your last %1 tasks took about %2× their estimate.").arg(page.review?.tasks.length ?? 0).arg((page.review?.median_ratio ?? 1).toFixed(1))
                                    wrapMode: Text.Wrap
                                    font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.faint
                                }
                            }
                        }

                        // what does not fit
                        Rectangle {
                            visible: page.placed.over.length > 0
                            Layout.fillWidth: true
                            implicitHeight: overCol.implicitHeight + 24
                            radius: App.Console.radius
                            color: Qt.alpha(App.Console.crit, 0.08)
                            border.width: 1
                            border.color: Qt.alpha(App.Console.crit, 0.35)
                            ColumnLayout {
                                id: overCol
                                anchors { fill: parent; margins: 12 }
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Ui.Icon { text: "warning"; size: 18; color: App.Console.crit }
                                    Text { text: qsTr("Does not fit today"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.text }
                                    Text { text: page.fmt(page.placed.over.reduce((a, i) => a + i.est_min, 0)); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.crit }
                                    Item { Layout.fillWidth: true }
                                }
                                Ui.Chip { text: qsTr("Push all to tomorrow"); interactive: true; accent: App.Console.crit; onClicked: { for (const o of page.placed.over) App.Store.snooze(o.uid, "tomorrow"); } }
                                Repeater {
                                    model: page.placed.over
                                    delegate: RowLayout {
                                        id: orow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        spacing: 8
                                        HoverHandler { id: oHov }
                                        Rectangle { implicitWidth: 4; implicitHeight: 18; radius: 2; color: App.Store.colorOf(orow.modelData.project || orow.modelData.list) }
                                        Text { Layout.fillWidth: true; text: orow.modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text
                                            HoverHandler { cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: App.Nav.selected = orow.modelData.uid } }
                                        Text { visible: !oHov.hovered; text: (orow.modelData.est_guess ? "~" : "") + page.fmt(orow.modelData.est_min); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                                        Ui.IconButton { visible: oHov.hovered; implicitWidth: 24; implicitHeight: 24; icon: "schedule"; tooltip: qsTr("Push to tomorrow"); onClicked: App.Store.snooze(orow.modelData.uid, "tomorrow") }
                                        Ui.IconButton { visible: oHov.hovered; implicitWidth: 24; implicitHeight: 24; icon: "check"; tooltip: qsTr("Done"); onClicked: App.Store.setState(orow.modelData.uid, "done") }
                                    }
                                }
                            }
                        }

                        // tomorrow
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: tomCol.implicitHeight + 24
                            radius: App.Console.radius
                            color: App.Console.panel
                            ColumnLayout {
                                id: tomCol
                                anchors { fill: parent; margins: 12 }
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Ui.Icon { text: "event"; size: 18; color: App.Console.data2 }
                                    Text { text: Qt.formatDate(new Date(page.day.getTime() + 86400000), "dddd"); font.family: App.Console.sans; font.pixelSize: 14; font.weight: Font.DemiBold; color: App.Console.text }
                                    Text { text: page.tomorrow ? qsTr("%1 · %2").arg(page.tomorrow.items.length).arg(page.fmt(page.tomorrow.planned_min)) : ""; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.faint }
                                    Item { Layout.fillWidth: true }
                                    Text { text: qsTr("open"); font.family: App.Console.mono; font.pixelSize: 12; color: tHov.hovered ? App.Console.text : App.Console.faint
                                        HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: page.dayOffset = page.dayOffset + 1 } }
                                }
                                Repeater {
                                    model: (page.tomorrow?.items ?? []).slice(0, 6)
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        spacing: 8
                                        Rectangle { implicitWidth: 4; implicitHeight: 16; radius: 2; color: App.Store.colorOf(modelData.project || modelData.list) }
                                        Text { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                        Text { text: page.fmt(modelData.est_min); font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.dim }
                                    }
                                }
                                Text { visible: !!page.tomorrow && page.tomorrow.items.length === 0; text: qsTr("Nothing planned yet."); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint }
                            }
                        }
                    }
                }

            }
        }
    }
}
