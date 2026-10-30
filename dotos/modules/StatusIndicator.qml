import QtQuick
import "." as App
import "../ui" as Ui

/**
 * StatusIndicator: a professional, reusable circular status badge.
 *
 * States: todo, doing, waiting, done, cancelled, blocked
 * Each state has a distinct color, icon/shape, and subtle animation.
 * Designed to be consistent across all modules.
 */
Rectangle {
    id: root

    property string state: "todo"   // todo | doing | waiting | done | cancelled | blocked
    property color listColor: App.Console.data
    property real size: 20
    property bool animated: true

    implicitWidth: size
    implicitHeight: size
    radius: size / 2

    readonly property color stateColor: {
        switch (state) {
            case "done":       return App.Console.ok;
            case "doing":      return App.Console.warn;
            case "waiting":    return App.Console.data;
            case "cancelled":  return App.Console.crit;
            case "blocked":    return App.Console.warn;
            case "review":     return App.Console.data;
            case "overdue":    return App.Console.crit;
            case "stalled":    return App.Console.warn;
            case "archived":   return App.Console.faint;
            default:           return listColor;
        }
    }

    color: state === "done" ? Qt.alpha(stateColor, 0.95)
         : Qt.alpha(stateColor, 0.10)
    border.width: state === "done" ? 0 : 1.5
    border.color: stateColor
    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    // done: checkmark with subtle scale-in
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "done"
        text: "check"
        size: root.size * 0.7
        color: App.Console.bg
        scale: root.state === "done" ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
    }

    // doing: rotating arc (progress ring)
    Canvas {
        id: arcCanvas
        anchors.fill: parent
        anchors.margins: 3
        visible: root.state === "doing" && root.animated
        property real angle: 0
        onAngleChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var cx = width / 2, cy = height / 2, r = Math.min(width, height) / 2 - 1;
            ctx.beginPath();
            ctx.arc(cx, cy, r, root.angle, root.angle + Math.PI * 1.2);
            ctx.strokeStyle = root.stateColor;
            ctx.lineWidth = 2;
            ctx.lineCap = "round";
            ctx.stroke();
        }
        NumberAnimation on angle {
            running: root.state === "doing" && root.animated
            from: 0; to: Math.PI * 2
            duration: 1200
            loops: Animation.Infinite
            easing.type: Easing.Linear
        }
    }
    // doing: center dot
    Rectangle {
        visible: root.state === "doing"
        anchors.centerIn: parent
        width: root.size * 0.3; height: root.size * 0.3; radius: root.size * 0.15
        color: root.stateColor
    }

    // waiting: pulsing ring
    Rectangle {
        visible: root.state === "waiting"
        anchors.centerIn: parent
        width: root.size * 0.5; height: root.size * 0.5; radius: root.size * 0.25
        color: "transparent"
        border.width: 1.5
        border.color: root.stateColor
        SequentialAnimation on scale {
            running: root.state === "waiting" && root.animated
            loops: Animation.Infinite
            NumberAnimation { from: 0.8; to: 1.3; duration: 800; easing.type: Easing.OutCubic }
            NumberAnimation { from: 1.3; to: 0.8; duration: 800; easing.type: Easing.InCubic }
        }
        SequentialAnimation on opacity {
            running: root.state === "waiting" && root.animated
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.3; duration: 800; easing.type: Easing.OutCubic }
            NumberAnimation { from: 0.3; to: 1.0; duration: 800; easing.type: Easing.InCubic }
        }
    }

    // cancelled: X
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "cancelled"
        text: "close"
        size: root.size * 0.6
        color: root.stateColor
    }

    // blocked: lock icon
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "blocked"
        text: "lock"
        size: root.size * 0.55
        color: root.stateColor
    }

    // review: eye icon
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "review"
        text: "visibility"
        size: root.size * 0.55
        color: root.stateColor
    }

    // overdue: clock with exclamation
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "overdue"
        text: "schedule"
        size: root.size * 0.55
        color: root.stateColor
    }

    // stalled: pause icon
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "stalled"
        text: "pause"
        size: root.size * 0.5
        color: root.stateColor
    }

    // archived: archive icon
    Ui.Icon {
        anchors.centerIn: parent
        visible: root.state === "archived"
        text: "archive"
        size: root.size * 0.5
        color: root.stateColor
    }

    // todo: subtle inner dot on hover
    Rectangle {
        visible: root.state === "todo"
        anchors.centerIn: parent
        width: root.size * 0.25; height: root.size * 0.25; radius: root.size * 0.125
        color: Qt.alpha(root.stateColor, checkHov.hovered ? 0.6 : 0.0)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    HoverHandler { id: checkHov; cursorShape: Qt.PointingHandCursor }
}