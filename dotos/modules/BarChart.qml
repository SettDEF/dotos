import QtQuick
import QtQuick.Controls
import "." as App
import "../ui" as Ui

/**
 * A gridded bar chart in the instrument style: mono axis numbers, hairline
 * gridlines, stacked series, an optional line over the bars (a moving
 * average). values[day][series]; labels are ISO days. Hovering a day names
 * its numbers.
 */
Item {
    id: root
    property var labels: []
    property var series: []          // [{ name, color }]
    property var values: []          // values[day][series]
    property var line: []            // one number per day, or empty
    property var fmt: v => String(v)
    property int ticks: 4
    /// shown in the middle of the plot while every value is zero
    property string emptyText: ""
    /// the axis never shrinks below this, so an empty chart does not repeat "0"
    property real minPeak: 1

    readonly property int n: root.labels.length
    readonly property var totals: root.values.map(d => d.reduce((a, b) => a + b, 0))
    readonly property real peak: {
        const m = Math.max(root.minPeak, Math.max.apply(null, root.totals.concat(root.line.length ? root.line : [0])));
        const raw = m / root.ticks;
        const mag = Math.pow(10, Math.floor(Math.log10(raw)));
        const step = [1, 2, 2.5, 5, 10].map(k => k * mag).find(s => s >= raw) ?? raw;
        return step * root.ticks;
    }
    readonly property real axisW: 46
    readonly property real axisH: 22
    readonly property real plotW: root.width - root.axisW
    readonly property real plotH: root.height - root.axisH
    readonly property real slot: root.n > 0 ? root.plotW / root.n : 0

    Text {
        visible: root.emptyText.length > 0 && root.totals.every(t => t === 0)
        x: root.axisW; width: root.plotW; y: root.plotH / 2 - height / 2
        horizontalAlignment: Text.AlignHCenter
        text: root.emptyText
        font.family: App.Console.sans; font.pixelSize: 14; color: App.Console.faint
        z: 2
    }

    // gridlines and the y axis
    Repeater {
        model: root.ticks + 1
        delegate: Item {
            required property int index
            readonly property real v: root.peak * index / root.ticks
            y: root.plotH - root.plotH * index / root.ticks
            width: root.width
            Rectangle { x: root.axisW; width: root.plotW; height: 1; color: index === 0 ? App.Console.ruleStrong : App.Console.grid }
            Text {
                width: root.axisW - 8; y: -height / 2
                horizontalAlignment: Text.AlignRight
                text: root.fmt(parent.v)
                font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
            }
        }
    }

    // the x axis: a label about every sixth day
    Repeater {
        model: root.labels
        delegate: Text {
            required property string modelData
            required property int index
            readonly property int every: Math.max(1, Math.ceil(root.n / 6))
            visible: (root.n - 1 - index) % every === 0
            x: root.axisW + index * root.slot + root.slot / 2 - width / 2
            y: root.plotH + 5
            text: Qt.formatDate(new Date(modelData + "T12:00:00"), "d MMM")
            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
        }
    }

    // the bars
    Repeater {
        model: root.n
        delegate: Item {
            id: day
            required property int index
            x: root.axisW + index * root.slot
            width: root.slot
            height: root.plotH
            function below(s) { let t = 0; for (let k = 0; k < s; k++) t += ((root.values[day.index] ?? [])[k] ?? 0); return t; }
            Repeater {
                model: root.series.length
                delegate: Rectangle {
                    required property int index
                    readonly property real v: ((root.values[day.index] ?? [])[index] ?? 0)
                    visible: v > 0
                    x: Math.max(1, day.width * 0.12)
                    width: day.width - 2 * x
                    height: Math.max(1.5, v / root.peak * root.plotH)
                    y: root.plotH - (day.below(index) + v) / root.peak * root.plotH
                    color: root.series[index].color
                    radius: index === root.series.length - 1 ? 2 : 0
                }
            }
            Rectangle { anchors.fill: parent; color: Qt.alpha(App.Console.text, 0.05); visible: dayHov.hovered }
            HoverHandler { id: dayHov }
            Ui.Tip {
                visible: dayHov.hovered
                delay: 120
                y: -height - 6
                title: Qt.formatDate(new Date(root.labels[day.index] + "T12:00:00"), "dddd d MMM")
                rows: {
                    const vals = root.values[day.index] ?? [];
                    const out = root.series.map((s, k) => ({ name: s.name, value: root.fmt(vals[k] ?? 0), color: s.color, v: vals[k] ?? 0 })).filter(r => r.v > 0);
                    if (out.length === 0) return [{ name: qsTr("nothing"), value: "—" }];
                    if (out.length > 1) out.push({ name: qsTr("total"), value: root.fmt(root.totals[day.index] ?? 0) });
                    return out;
                }
            }
        }
    }

    // the line over them
    Repeater {
        model: root.line.length > 1 ? root.line.length - 1 : 0
        delegate: Rectangle {
            required property int index
            readonly property real ax: root.axisW + index * root.slot + root.slot / 2
            readonly property real ay: root.plotH - root.line[index] / root.peak * root.plotH
            readonly property real bx: ax + root.slot
            readonly property real by: root.plotH - root.line[index + 1] / root.peak * root.plotH
            x: ax; y: ay - 1
            width: Math.hypot(bx - ax, by - ay); height: 2
            rotation: Math.atan2(by - ay, bx - ax) * 180 / Math.PI
            transformOrigin: Item.Left
            antialiasing: true
            color: App.Console.warn
        }
    }
}
