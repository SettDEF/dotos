import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * SpiderWeb (radar) chart: plots tag usage on radial axes.
 * Each axis is a tag, the polygon connects the values.
 */
Item {
    id: root
    property var tags: []
    property real maxValue: 1.0
    property real padding: 40
    property color gridColor: "#444444"
    property color axisColor: "#666666"
    property color fillColor: "#4ade80"
    property real fillOpacity: 0.25
    property color strokeColor: "#4ade80"
    property int levels: 5

    implicitWidth: 300
    implicitHeight: 300

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real radius: Math.min(width, height) / 2 - padding

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var n = root.tags.length;
            if (n < 3) return;

            for (var l = 1; l <= root.levels; l++) {
                var r = root.radius * (l / root.levels);
                ctx.beginPath();
                for (var i = 0; i < n; i++) {
                    var angle = (Math.PI * 2 * i / n) - Math.PI / 2;
                    var x = root.cx + r * Math.cos(angle);
                    var y = root.cy + r * Math.sin(angle);
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }
                ctx.closePath();
                ctx.strokeStyle = root.gridColor;
                ctx.lineWidth = 1;
                ctx.stroke();
            }

            for (var i = 0; i < n; i++) {
                var angle = (Math.PI * 2 * i / n) - Math.PI / 2;
                ctx.beginPath();
                ctx.moveTo(root.cx, root.cy);
                ctx.lineTo(root.cx + root.radius * Math.cos(angle), root.cy + root.radius * Math.sin(angle));
                ctx.strokeStyle = root.axisColor;
                ctx.lineWidth = 1;
                ctx.stroke();
            }

            ctx.font = "12px sans-serif";
            ctx.fillStyle = "#cccccc";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            for (var i = 0; i < n; i++) {
                var angle = (Math.PI * 2 * i / n) - Math.PI / 2;
                var labelR = root.radius + 15;
                var lx = root.cx + labelR * Math.cos(angle);
                var ly = root.cy + labelR * Math.sin(angle);
                var tag = root.tags[i];
                ctx.fillText(tag.name || "", lx, ly);
            }

            ctx.beginPath();
            for (var i = 0; i < n; i++) {
                var angle = (Math.PI * 2 * i / n) - Math.PI / 2;
                var val = (root.tags[i].value || 0) / root.maxValue;
                var r = root.radius * Math.min(1, Math.max(0, val));
                var x = root.cx + r * Math.cos(angle);
                var y = root.cy + r * Math.sin(angle);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(root.fillColor.r, root.fillColor.g, root.fillColor.b, root.fillOpacity);
            ctx.fill();
            ctx.strokeStyle = root.strokeColor;
            ctx.lineWidth = 2;
            ctx.stroke();

            for (var i = 0; i < n; i++) {
                var angle = (Math.PI * 2 * i / n) - Math.PI / 2;
                var val = (root.tags[i].value || 0) / root.maxValue;
                var r = root.radius * Math.min(1, Math.max(0, val));
                var x = root.cx + r * Math.cos(angle);
                var y = root.cy + r * Math.sin(angle);
                ctx.beginPath();
                ctx.arc(x, y, 4, 0, Math.PI * 2);
                ctx.fillStyle = root.tags[i].color || root.strokeColor;
                ctx.fill();
            }
        }

        Component.onCompleted: requestPaint()
    }

    onTagsChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
