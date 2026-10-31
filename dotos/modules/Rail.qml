import QtQuick
import QtQuick.Layouts
import Quickshell
import "." as App
import "../ui" as Ui

/**
 * The rail: the five areas (VISION.md §6), as Teams, Slack and Discord put theirs. An icon with
 * its name under it, the selected one filled with the accent bar beside it, a red count for what
 * needs you and a dot for news. Extensions, settings and you at the bottom. Ctrl 1…5.
 */
Rectangle {
    id: root
    implicitWidth: 68
    color: App.Console.bg

    /// [count, alert] per area: alert is red (needs you), else a quiet dot for news
    function badge(key) {
        switch (key) {
            case "activity": return [App.Store.overdue + App.Store.dueToday + App.Store.needsYou.length, App.Store.overdue > 0 || App.Store.needsYou.length > 0];
            case "chat": return [App.Team.unreadTotal, App.Team.unreadTotal > 0];
            case "work": return [App.Store.inbox, false];
            case "code": return [App.Store.projects.filter(p => p.health === "attention").length, true];
            default: return [0, false];
        }
    }

    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: App.Console.rule }

    component RailButton: Item {
        id: btn
        property string icon: ""
        property string label: ""
        property bool selected: false
        property int count: 0
        property bool alert: false
        property string tip: ""
        signal clicked
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 60
        implicitHeight: btn.label ? 54 : 40

        Rectangle {
            anchors { left: parent.left; leftMargin: -4; verticalCenter: parent.verticalCenter }
            width: 3; height: btn.selected ? 24 : hov.hovered ? 10 : 0
            radius: 1.5
            color: App.Console.data
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: btn.selected ? Qt.alpha(App.Console.data, 0.14) : hov.hovered ? Qt.alpha(App.Console.text, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Column {
            anchors.centerIn: parent
            spacing: 2
            Ui.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: btn.icon
                size: 22
                filled: btn.selected
                color: btn.selected ? App.Console.data : hov.hovered ? App.Console.text : App.Console.dim
            }
            Text {
                visible: btn.label.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: btn.label
                color: btn.selected ? App.Console.text : App.Console.dim
                font.pixelSize: 11
                font.weight: btn.selected ? Font.DemiBold : Font.Normal
            }
        }
        // the count, as Teams puts it on the icon's corner
        Rectangle {
            visible: btn.count > 0
            x: parent.width / 2 + 4
            height: 16; width: btn.alert ? Math.max(16, cText.implicitWidth + 8) : 8
            radius: 8
            y: btn.alert ? (btn.label ? 4 : 2) : (btn.label ? 8 : 6)
            color: btn.alert ? App.Console.crit : App.Console.data
            border.width: 2; border.color: App.Console.bg
            Text { id: cText; visible: btn.alert; anchors.centerIn: parent; text: btn.count > 99 ? "99+" : btn.count; color: "white"; font.pixelSize: 10; font.weight: Font.Bold }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
        Ui.Tip { visible: hov.hovered && btn.tip.length > 0; delay: 400; x: parent.width + 10; y: (parent.height - height) / 2; text: btn.tip }
    }

    ColumnLayout {
        anchors { fill: parent; topMargin: 10; bottomMargin: 10; leftMargin: 4; rightMargin: 4 }
        spacing: 4

        // the app: its icon, the command palette on a click (as Linear's workspace button)
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 40; implicitHeight: 40
            Layout.bottomMargin: 8
            Image { anchors.fill: parent; anchors.margins: 4; source: Quickshell.iconPath("dotos", true); sourceSize: Qt.size(64, 64); smooth: true }
            HoverHandler { id: logoHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: App.Nav.action("palette") }
            Ui.Tip { visible: logoHov.hovered; delay: 400; x: parent.width + 14; y: (parent.height - height) / 2; text: qsTr("Search and commands  (Ctrl K)") }
        }

        Repeater {
            model: App.Nav.areas
            delegate: RailButton {
                required property var modelData
                required property int index
                readonly property var b: root.badge(modelData.key)
                icon: modelData.icon
                label: modelData.label
                selected: App.Nav.area === modelData.key
                count: b[0]
                alert: b[1]
                tip: modelData.label + "  (Ctrl " + (index + 1) + ")"
                onClicked: App.Nav.goArea(modelData.key)
            }
        }

        Item { Layout.fillHeight: true }

        RailButton {
            icon: "extension"
            selected: App.Nav.page === "extensions"
            count: App.Store.extensions.filter(e => !e.last_ok).length
            alert: true
            tip: qsTr("Extensions")
            onClicked: App.Nav.go("extensions")
        }
        RailButton {
            icon: "settings"
            selected: App.Nav.page === "settings"
            tip: qsTr("Settings  (Ctrl ,)")
            onClicked: App.Nav.go("settings")
        }
        // you, as Discord and Teams show it: your initial, a green dot when the team sees you
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            implicitWidth: 36; implicitHeight: 36
            readonly property string who: App.Team.meName || App.Team.me || Quickshell.env("USER") || "?"
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.hsla((parent.who.charCodeAt(0) * 37 % 360) / 360, 0.42, 0.42, 1)
                Text { anchors.centerIn: parent; text: parent.parent.who.charAt(0).toUpperCase(); color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold }
            }
            Rectangle {
                anchors { right: parent.right; bottom: parent.bottom; margins: -1 }
                width: 12; height: 12; radius: 6
                color: App.Console.ok
                border.width: 2; border.color: App.Console.bg
            }
            HoverHandler { id: meHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: App.Nav.goArea("chat") }
            Ui.Tip { visible: meHov.hovered; delay: 400; x: parent.width + 14; y: (parent.height - height) / 2; text: (App.Team.meName || "") + (App.Team.me ? "  @" + App.Team.me : "") }
        }
    }
}
