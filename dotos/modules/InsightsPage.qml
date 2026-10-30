import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * Insights: what the last weeks of work actually looked like, from the
 * numbers `dotos stats` gathers — tasks finished per day (with a 7-day
 * average), time tracked per day by project, and how long tasks really took
 * against what was estimated. Gridded plots, mono numbers.
 */
Item {
    id: page
    property string key: "insights"
    property int days: 30
    property var stats: null

    function reload() { if (!statsProc.running) statsProc.running = true; else reloadTimer.restart(); }
    Timer { id: reloadTimer; interval: 500; onTriggered: page.reload() }
    onDaysChanged: page.reload()
    Component.onCompleted: page.reload()
    Connections { target: App.Store; function onLastLoadChanged() { reloadTimer.restart(); } }
    Process {
        id: statsProc
        command: [App.Store.bin, "stats", "--days", String(page.days)]
        stdout: StdioCollector { onStreamFinished: { try { page.stats = JSON.parse(text); } catch (e) {} } }
    }

    // ── what the charts and tiles read ─────────────────────────────────
    readonly property var labels: page.stats?.days ?? []
    readonly property var done: page.stats?.done ?? []
    readonly property var doneSeries: [{ name: qsTr("finished"), color: App.Console.data }]
    readonly property var doneValues: page.done.map(v => [v])
    readonly property var doneAvg: page.done.map((_, i) => { const w = page.done.slice(Math.max(0, i - 6), i + 1); return w.reduce((a, b) => a + b, 0) / w.length; })

    /// time per day: the five busiest projects, the rest as "other", in hours
    readonly property var projectTotals: {
        const t = {};
        for (const d of page.stats?.tracked ?? []) for (const p in d) t[p] = (t[p] ?? 0) + d[p];
        return Object.keys(t).sort((a, b) => t[b] - t[a]);
    }
    readonly property var topProjects: page.projectTotals.slice(0, 5)
    readonly property bool hasOther: page.projectTotals.length > 5
    readonly property var timeSeries: page.topProjects.map(p => ({ name: p === "(none)" ? qsTr("no project") : p, color: p === "(none)" ? App.Console.data2 : App.Store.colorOf(p) }))
        .concat(page.hasOther ? [{ name: qsTr("other"), color: App.Console.faint }] : [])
    readonly property var timeValues: (page.stats?.tracked ?? []).map(d => {
        const row = page.topProjects.map(p => (d[p] ?? 0) / 3600);
        if (page.hasOther) row.push(page.projectTotals.slice(5).reduce((a, p) => a + (d[p] ?? 0), 0) / 3600);
        return row;
    })
    readonly property real trackedHours: page.timeValues.reduce((a, d) => a + d.reduce((x, y) => x + y, 0), 0)

    /// "+12%" against the period before this one; null when there is nothing to compare
    function deltaOf(kind) {
        const p = page.stats?.prev;
        if (!p) return null;
        const cur = kind === "done" ? page.doneTotal : page.trackedHours * 3600;
        const prev = kind === "done" ? p.done : p.tracked_s;
        if (!prev) return cur > 0 ? { text: qsTr("new"), tone: App.Console.dim } : null;
        const pct = Math.round((cur - prev) / prev * 100);
        if (pct === 0) return { text: "±0%", tone: App.Console.dim };
        return { text: (pct > 0 ? "+" : "") + pct + "%", tone: kind === "done" ? (pct > 0 ? App.Console.ok : App.Console.crit) : App.Console.dim };
    }
    /// activity per day for the heatmap: finished tasks plus hours tracked
    readonly property var activity: page.labels.map((_, i) => (page.done[i] ?? 0) + (page.timeValues[i] ?? []).reduce((a, b) => a + b, 0))
    readonly property real activityMax: Math.max(1, ...page.activity)
    readonly property var projectRows: (page.stats?.projects ?? []).slice(0, 8)
    readonly property real projectMax: Math.max(1, ...page.projectRows.map(p => p.tracked_s))

    readonly property int doneTotal: page.done.reduce((a, b) => a + b, 0)
    readonly property int streak: {
        let n = 0, i = page.done.length - 1;
        if (i >= 0 && page.done[i] === 0) i--;      // today is not over yet
        for (; i >= 0 && page.done[i] > 0; i--) n++;
        return n;
    }
    readonly property int bestIndex: page.done.reduce((b, v, i, a) => v > a[b] ? i : b, 0)
    readonly property var estimates: page.stats?.estimates ?? []
    readonly property real ratio: {
        const r = page.estimates.map(e => e.tracked_min / e.est_min).sort((a, b) => a - b);
        return r.length ? r[Math.floor(r.length / 2)] : 0;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        App.Toolbar {
            title: qsTr("Insights")
            subtitle: page.stats ? qsTr("last %1 days · %2 finished · %3 tracked").arg(page.days).arg(page.doneTotal).arg(App.Store.dur(page.trackedHours * 3600)) : ""
            Ui.SegmentedControl {
                implicitWidth: 210
                model: [{ key: "14", label: "14 d" }, { key: "30", label: "30 d" }, { key: "90", label: "90 d" }]
                current: String(page.days)
                onPicked: k => page.days = parseInt(k)
            }
        }

        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            Connections { target: App.Nav; function onShotScroll(y) { scroller.contentY = Math.min(y, Math.max(0, scroller.contentHeight - scroller.height)); } }
            contentHeight: body.implicitHeight + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                x: 14; y: 14
                width: parent.width - 28
                spacing: 14

                // the numbers that matter, large
                GridLayout {
                    Layout.fillWidth: true
                    columns: width > 760 ? 4 : 2
                    columnSpacing: 10; rowSpacing: 10
                    Repeater {
                        model: [
                            { d: page.deltaOf("done"), v: String(page.doneTotal), l: qsTr("finished"), s: qsTr("%1 a day").arg((page.doneTotal / Math.max(1, page.days)).toFixed(1)) },
                            { d: page.deltaOf("tracked"), v: App.Store.dur(page.trackedHours * 3600), l: qsTr("tracked"), s: qsTr("%1 a day").arg(App.Store.dur(page.trackedHours * 3600 / Math.max(1, page.days))) },
                            { v: page.streak + (page.streak === 1 ? qsTr(" day") : qsTr(" days")), l: qsTr("streak"), s: qsTr("in a row, ending today") },
                            { v: page.ratio ? page.ratio.toFixed(1) + "×" : "—", l: qsTr("estimates"), s: page.ratio ? (page.ratio > 1.15 ? qsTr("takes longer than planned") : page.ratio < 0.87 ? qsTr("faster than planned") : qsTr("estimates hold")) : qsTr("add ~30m, track time") }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 92
                            radius: App.Console.radius
                            color: App.Console.panel
                            ColumnLayout {
                                anchors { fill: parent; margins: 14 }
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text { text: modelData.v; font.family: App.Console.mono; font.pixelSize: 26; font.weight: Font.DemiBold; color: App.Console.text }
                                    Rectangle {
                                        visible: !!modelData.d
                                        implicitWidth: dText.implicitWidth + 12; implicitHeight: 20; radius: 10
                                        color: Qt.alpha(modelData.d?.tone ?? "transparent", 0.16)
                                        Layout.alignment: Qt.AlignVCenter
                                        Text { id: dText; anchors.centerIn: parent; text: modelData.d?.text ?? ""; font.family: App.Console.mono; font.pixelSize: 11; font.weight: Font.DemiBold; color: modelData.d?.tone ?? App.Console.dim }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                Text { text: modelData.l; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim }
                                Text { Layout.fillWidth: true; text: modelData.s; elide: Text.ElideRight; font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            }
                        }
                    }
                }

                // time per day
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 290
                    radius: App.Console.radius
                    color: App.Console.panel
                    ColumnLayout {
                        anchors { fill: parent; margins: 14 }
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Time tracked per day"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
                            Item { Layout.fillWidth: true }
                            Row {
                                spacing: 12
                                Repeater {
                                    model: page.timeSeries
                                    delegate: Row {
                                        required property var modelData
                                        spacing: 5
                                        Rectangle { width: 9; height: 9; radius: 2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: modelData.name; font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim }
                                    }
                                }
                            }
                        }
                        BarChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            emptyText: qsTr("Nothing tracked in this period. ▶ on a task starts the timer.")
                            labels: page.labels
                            series: page.timeSeries
                            values: page.timeValues
                            fmt: v => v <= 0 ? "0" : v < 1 ? Math.round(v * 60) + "m" : (Math.round(v * 10) / 10) + "h"
                        }
                    }
                }

                // finished per day
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 250
                    radius: App.Console.radius
                    color: App.Console.panel
                    ColumnLayout {
                        anchors { fill: parent; margins: 14 }
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Tasks finished per day"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
                            Item { Layout.fillWidth: true }
                            Row { spacing: 5
                                Rectangle { width: 14; height: 2; color: App.Console.warn; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: qsTr("7-day average"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim } }
                        }
                        BarChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            minPeak: 4
                            emptyText: qsTr("No task finished in this period yet.")
                            labels: page.labels
                            series: page.doneSeries
                            values: page.doneValues
                            line: page.doneTotal > 0 ? page.doneAvg : []
                            fmt: v => Number.isInteger(v) ? String(v) : (Math.round(v * 10) / 10).toString()
                        }
                    }
                }

                // activity by day, and where the time went
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 5
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: 230
                        radius: App.Console.radius
                        color: App.Console.panel
                        ColumnLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: qsTr("Activity"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
                                Item { Layout.fillWidth: true }
                                Text { text: qsTr("finished + hours tracked, per day"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                            }
                            Item {
                                id: heat
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                readonly property int n: page.labels.length
                                readonly property int first: n > 0 ? (new Date(page.labels[0] + "T12:00:00").getDay() + 6) % 7 : 0   // Monday = 0
                                readonly property int cols: Math.max(1, Math.ceil((first + n) / 7))
                                readonly property real cell: Math.max(8, Math.min(26, (width - 34) / cols - 3, (height - 22) / 7 - 3))
                                Repeater {
                                    model: ["Mon", "Wed", "Fri"]
                                    delegate: Text { required property string modelData; required property int index
                                        x: 0; y: 18 + (index * 2) * (heat.cell + 3) + (heat.cell - height) / 2; text: modelData; font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                }
                                Repeater {
                                    model: heat.n
                                    delegate: Rectangle {
                                        id: hc
                                        required property int index
                                        readonly property int slot: hc.index + heat.first
                                        readonly property real v: page.activity[hc.index] ?? 0
                                        x: 34 + Math.floor(hc.slot / 7) * (heat.cell + 3)
                                        y: 18 + (hc.slot % 7) * (heat.cell + 3)
                                        width: heat.cell; height: heat.cell; radius: Math.min(5, heat.cell / 4)
                                        color: hc.v <= 0 ? App.Console.grid : Qt.alpha(App.Console.data, 0.2 + 0.8 * Math.min(1, hc.v / page.activityMax))
                                        border.width: page.labels[hc.index] === page.stats?.days[page.stats.days.length - 1] ? 1.5 : 0
                                        border.color: App.Console.text
                                        HoverHandler { id: hcHov }
                                        Ui.Tip {
                                            visible: hcHov.hovered
                                            y: -height - 6
                                            title: Qt.formatDate(new Date(page.labels[hc.index] + "T12:00:00"), "dddd d MMM")
                                            rows: [{ name: qsTr("finished"), value: String(page.done[hc.index] ?? 0) }, { name: qsTr("tracked"), value: App.Store.dur(((page.timeValues[hc.index] ?? []).reduce((a, b) => a + b, 0)) * 3600) }]
                                        }
                                    }
                                }
                                // a month label above the first column of each month
                                Repeater {
                                    model: heat.n
                                    delegate: Text {
                                        required property int index
                                        readonly property int slot: index + heat.first
                                        visible: (index === 0 || page.labels[index].slice(8) === "01") && slot % 7 < 6
                                        x: 34 + Math.floor(slot / 7) * (heat.cell + 3); y: 0
                                        text: Qt.formatDate(new Date(page.labels[index] + "T12:00:00"), "MMM")
                                        font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 6
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: 230
                        radius: App.Console.radius
                        color: App.Console.panel
                        ColumnLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 2
                            Text { text: qsTr("By project"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 10
                                Text { Layout.preferredWidth: 100; text: qsTr("project"); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                Text { Layout.fillWidth: true; text: qsTr("time"); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                Text { Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; text: qsTr("done"); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                                Text { Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; text: qsTr("est."); font.family: App.Console.mono; font.pixelSize: 10; color: App.Console.faint }
                            }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: App.Console.rule }
                            Repeater {
                                model: page.projectRows
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    spacing: 10
                                    RowLayout {
                                        Layout.preferredWidth: 100
                                        spacing: 6
                                        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: modelData.name === "(none)" ? App.Console.dim : App.Store.colorOf(modelData.name) }
                                        Text { Layout.fillWidth: true; text: modelData.name === "(none)" ? qsTr("no project") : modelData.name; elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.text }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 6; radius: 3
                                            color: Qt.alpha(App.Console.text, 0.07)
                                            Rectangle { width: parent.width * modelData.tracked_s / page.projectMax; height: 6; radius: 3; color: modelData.name === "(none)" ? App.Console.dim : App.Store.colorOf(modelData.name) }
                                        }
                                        Text { Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight; text: App.Store.dur(modelData.tracked_s); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.dim }
                                    }
                                    Text { Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; text: modelData.done || "·"; font.family: App.Console.mono; font.pixelSize: 11; color: modelData.done ? App.Console.text : App.Console.faint }
                                    Text {
                                        Layout.preferredWidth: 56
                                        horizontalAlignment: Text.AlignRight
                                        readonly property real ratio: modelData.est_min > 0 ? modelData.real_min / modelData.est_min : 0
                                        text: ratio ? ratio.toFixed(1) + "×" : "·"
                                        font.family: App.Console.mono; font.pixelSize: 11
                                        color: !ratio ? App.Console.faint : ratio > 1.3 ? App.Console.warn : ratio < 0.8 ? App.Console.ok : App.Console.text
                                    }
                                }
                            }
                            Text { visible: page.projectRows.length === 0; text: qsTr("Nothing tracked or finished in this period."); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // estimate against reality
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 360
                    radius: App.Console.radius
                    color: App.Console.panel
                    ColumnLayout {
                        anchors { fill: parent; margins: 14 }
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Estimated against real time"); font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
                            Item { Layout.fillWidth: true }
                            Text { text: qsTr("above the line = took longer"); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                        }
                        Item {
                            id: sc
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            readonly property real axisW: 46
                            readonly property real axisH: 22
                            readonly property real pw: width - axisW
                            readonly property real ph: height - axisH
                            readonly property real peak: {
                                const m = Math.max(30, Math.max.apply(null, page.estimates.map(e => Math.max(e.est_min, e.tracked_min)).concat([0])));
                                const raw = m / 4, mag = Math.pow(10, Math.floor(Math.log10(raw)));
                                return ([1, 2, 2.5, 5, 10].map(k => k * mag).find(s => s >= raw) ?? raw) * 4;
                            }
                            function m(v) { return v < 60 ? v + "m" : (Math.round(v / 6) / 10) + "h"; }
                            Repeater {
                                model: 5
                                delegate: Item {
                                    required property int index
                                    // horizontal grid + y labels
                                    Rectangle { x: sc.axisW; y: sc.ph - sc.ph * index / 4; width: sc.pw; height: 1; color: index === 0 ? App.Console.ruleStrong : App.Console.grid }
                                    Text { x: 0; y: sc.ph - sc.ph * index / 4 - height / 2; width: sc.axisW - 8; horizontalAlignment: Text.AlignRight; text: sc.m(sc.peak * index / 4); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                    // vertical grid + x labels
                                    Rectangle { x: sc.axisW + sc.pw * index / 4; y: 0; width: 1; height: sc.ph; color: App.Console.grid }
                                    Text { x: sc.axisW + sc.pw * index / 4 - width / 2; y: sc.ph + 5; text: sc.m(sc.peak * index / 4); font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint }
                                }
                            }
                            // the median: where your tasks actually land (the line y = ratio × x, up to the top or the right edge)
                            Rectangle {
                                visible: page.ratio > 0
                                readonly property real ex: sc.pw * Math.min(1, 1 / page.ratio)
                                readonly property real ey: sc.ph * Math.min(1, page.ratio)
                                x: sc.axisW; y: sc.ph - 1
                                width: Math.hypot(ex, ey)
                                height: 2
                                rotation: -Math.atan2(ey, ex) * 180 / Math.PI
                                transformOrigin: Item.Left
                                antialiasing: true
                                color: Qt.alpha(App.Console.warn, 0.85)
                            }
                            Text {
                                visible: page.ratio > 0
                                anchors { right: parent.right; top: parent.top; rightMargin: 6 }
                                text: qsTr("median %1×  ·  green: on estimate").arg(page.ratio.toFixed(1))
                                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.warn
                            }
                            // y = x: the estimate was right
                            Rectangle {
                                x: sc.axisW; y: sc.ph - 1
                                width: Math.hypot(sc.pw, sc.ph); height: 2
                                rotation: -Math.atan2(sc.ph, sc.pw) * 180 / Math.PI
                                transformOrigin: Item.Left
                                antialiasing: true
                                color: Qt.alpha(App.Console.ok, 0.55)
                            }
                            Repeater {
                                model: page.estimates
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 11; height: 11; radius: 5.5
                                    x: sc.axisW + sc.pw * modelData.est_min / sc.peak - 5.5
                                    y: sc.ph - sc.ph * modelData.tracked_min / sc.peak - 5.5
                                    color: Qt.alpha(modelData.project ? App.Store.colorOf(modelData.project) : App.Console.data, 0.8)
                                    border.width: dotHov.hovered ? 2 : 0; border.color: App.Console.text
                                    HoverHandler { id: dotHov }
                                    Ui.Tip { visible: dotHov.hovered; title: modelData.title; rows: [{ name: qsTr("estimated"), value: sc.m(modelData.est_min) }, { name: qsTr("took"), value: sc.m(modelData.tracked_min) }] }
                                }
                            }
                            Column {
                                anchors.centerIn: parent
                                visible: page.estimates.length === 0 && !!page.stats
                                spacing: 6
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Nothing to compare yet"); font.family: App.Console.sans; font.pixelSize: 15; color: App.Console.dim }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Finish a task that has an estimate (~30m) and tracked time."); font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.faint }
                            }
                        }
                    }
                }
            }
        }
    }
}
