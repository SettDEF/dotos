import QtQuick
import "." as App
import "../ui" as Ui

/**
 * A person's avatar: their initial on a colour of their own, or a robot for an agent. `dot` adds a
 * presence dot in the corner (1 online, 0 not), -1 for none.
 */
Item {
    id: av
    property string who: ""         // the handle, or agent:… for an agent
    property string label: ""       // the name the initial is taken from
    property int size: 30
    property int dot: -1
    readonly property bool agent: App.Team.isAgent(av.who)

    implicitWidth: av.size
    implicitHeight: av.size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: av.agent ? Qt.alpha(App.Console.data, 0.3) : Qt.alpha(App.Team.tone(av.who), 0.25)
    }
    Ui.Icon {
        anchors.centerIn: parent
        visible: av.agent
        text: "smart_toy"
        size: Math.round(av.size * 0.52)
        color: App.Console.text
    }
    Text {
        anchors.centerIn: parent
        visible: !av.agent
        text: (av.label || av.who).charAt(0).toUpperCase()
        font.family: App.Console.sans
        font.pixelSize: Math.round(av.size * 0.42)
        font.weight: Font.DemiBold
        color: App.Team.tone(av.who)
    }
    Rectangle {
        visible: av.dot >= 0
        width: Math.round(av.size * 0.3); height: width; radius: width / 2
        anchors { right: parent.right; bottom: parent.bottom }
        color: av.dot === 1 ? App.Console.ok : App.Console.faint
        border.width: 2
        border.color: App.Console.panel
    }
}
