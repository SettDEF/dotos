import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

/**
 * The team: its name, the people met (online when heard from in the last five minutes), the
 * agents that answer @claude here and on the others' machines. Without a team, how to make one.
 */
Rectangle {
    id: panel
    color: App.Console.panel
    radius: App.Console.radius
    clip: true

    readonly property int onlineCount: App.Team.people.filter(p => App.Team.online(p.handle)).length

    ColumnLayout {
        anchors { fill: parent; margins: 14 }
        spacing: 4

        Text { Layout.fillWidth: true; text: App.Team.hasTeam ? App.Team.teamName : qsTr("No team yet"); elide: Text.ElideRight; font.family: App.Console.sans; font.pixelSize: 15; font.weight: Font.DemiBold; color: App.Console.text }
        Text {
            Layout.fillWidth: true
            text: App.Team.hasTeam ? qsTr("%1 online · %n people", "", App.Team.people.length).arg(panel.onlineCount) : qsTr("make one on this network")
            elide: Text.ElideRight
            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
        }

        Text {
            visible: App.Team.hasTeam
            Layout.topMargin: 14
            text: qsTr("People")
            font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.Medium; color: App.Console.dim
        }
        Repeater {
            model: App.Team.hasTeam ? App.Team.people : []
            delegate: RowLayout {
                id: person
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                spacing: 10
                App.TeamAvatar {
                    who: person.modelData.handle
                    label: person.modelData.name || person.modelData.handle
                    size: 30
                    dot: App.Team.online(person.modelData.handle) ? 1 : 0
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: person.modelData.name || person.modelData.handle
                        elide: Text.ElideRight
                        font.family: App.Console.sans; font.pixelSize: 13; font.weight: Font.Medium; color: App.Console.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "@" + person.modelData.handle + "  ·  " + App.Team.presence(person.modelData.handle)
                        elide: Text.ElideRight
                        font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
                    }
                }
            }
        }

        Text {
            visible: App.Team.hasTeam
            Layout.topMargin: 14
            text: qsTr("Agents")
            font.family: App.Console.sans; font.pixelSize: 12; font.weight: Font.Medium; color: App.Console.dim
        }
        Repeater {
            model: App.Team.hasTeam ? App.Team.agentList : []
            delegate: RowLayout {
                id: agentRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                spacing: 10
                App.TeamAvatar { who: "agent:" + agentRow.modelData; label: "claude"; size: 26 }
                Text {
                    Layout.fillWidth: true
                    text: App.Team.agentLabel(agentRow.modelData)
                    elide: Text.ElideRight
                    font.family: App.Console.sans; font.pixelSize: 13; color: App.Console.dim
                }
            }
        }

        Item { Layout.fillHeight: true }

        // no team: the two commands that make one, shown and not run
        ColumnLayout {
            visible: !App.Team.hasTeam && App.Team.loaded
            Layout.fillWidth: true
            spacing: 6
            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: qsTr("Team messages reach the people on your network. Make the team once:"); font.family: App.Console.sans; font.pixelSize: 12; color: App.Console.dim }
            Text { Layout.fillWidth: true; text: 'dotos lan init "Our team"'; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
            Text { Layout.fillWidth: true; text: "dotos lan invite"; font.family: App.Console.mono; font.pixelSize: 12; color: App.Console.text }
        }
        Text {
            visible: App.Team.hasTeam
            Layout.fillWidth: true
            text: App.Team.shared.length === 0 ? qsTr("no lists shared") : qsTr("%n list(s) shared", "", App.Team.shared.length)
            font.family: App.Console.mono; font.pixelSize: 11; color: App.Console.faint
        }
    }
}
