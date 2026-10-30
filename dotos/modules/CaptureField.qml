import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "." as App
import "../ui" as Ui

/**
 * One line, a whole task: `Call dentist @fri 14:00 !high #health ~30m +safemap`.
 * As you type, the parts it understood show as chips under the field, so a
 * typo in a date is visible before Enter, not after. The real parsing is the
 * CLI's (dotos capture); this preview only mirrors its token rules.
 */
Rectangle {
    id: root
    property string placeholder: qsTr("New task…  title @fri 14:00 !high #tag ~30m +project *weekly")
    /// appended to every line (a project page adds "+name")
    property string suffix: ""
    property alias text: field.text
    signal added(var task)

    function take() { field.forceActiveFocus(); }

    implicitHeight: 44 + (chips.visible ? chips.implicitHeight + 6 : 0)
    radius: Ui.Appearance.rounding.normal
    color: App.Console.panelAlt
    border.width: field.activeFocus ? 1 : 0
    border.color: App.Console.data

    // what the CLI made of the line (dotos parse), so a date shows as the day it resolves to
    property var parsed: null
    property string parsedFor: ""
    Timer {
        id: parseTimer
        interval: 160
        onTriggered: {
            if (field.text.trim().length < 2) { root.parsed = null; return; }
            if (parseProc.running) { parseTimer.restart(); return; }
            parseProc.asked = field.text;
            parseProc.command = [App.Store.bin, "parse", field.text];
            parseProc.running = true;
        }
    }
    Process {
        id: parseProc
        property string asked: ""
        stdout: StdioCollector { onStreamFinished: { try { root.parsed = JSON.parse(text); root.parsedFor = parseProc.asked; } catch (e) {} } }
    }

    readonly property var tokens: root.parsed && root.parsedFor === field.text ? root.fromParsed(root.parsed) : root.typedTokens
    function fromParsed(p) {
        const out = [];
        if (p.due) {
            const d = new Date(p.due);
            out.push({ icon: "event", text: Qt.formatDateTime(d, p.due_time ? "ddd d MMM HH:mm" : "ddd d MMM"), tone: App.Console.data });
        }
        if (p.importance) out.push({ icon: "flag", text: p.importance, tone: p.importance === "high" ? App.Console.crit : App.Console.dim });
        for (const t of p.tags ?? []) out.push({ icon: "sell", text: t, tone: App.Console.dim });
        if (p.estimate_min) out.push({ icon: "timer", text: App.Store.dur(p.estimate_min * 60), tone: App.Console.dim });
        if (p.repeat) out.push({ icon: "repeat", text: App.Store.repeatLabel({ repeat: p.repeat, repeat_after: p.repeat_after }), tone: App.Console.data });
        if (p.project) out.push({ icon: "deployed_code", text: p.project, tone: App.Store.colorOf(p.project) });
        if (p.list) out.push({ icon: "list", text: p.list, tone: App.Store.colorOf(p.list) });
        if (p.state) out.push({ icon: App.Store.stateIcon(p.state), text: p.state, tone: App.Store.stateColor(p.state) });
        return out;
    }
    // instant, before the CLI answers: the same token rules, unresolved
    readonly property var typedTokens: {
        const out = [];
        const words = field.text.split(/\s+/).filter(w => w.length > 1);
        for (let i = 0; i < words.length; i++) {
            const w = words[i];
            const c = w[0], v = w.slice(1);
            if (c === "@") {
                const next = words[i + 1] ?? "";
                const time = /^\d{1,2}:\d{2}$/.test(next) ? " " + next : "";
                out.push({ icon: "event", text: v + time, tone: App.Console.data });
            } else if (c === "!" && /^(high|h|1|normal|n|2|low|l|3|!)?$/i.test(v)) {
                out.push({ icon: "flag", text: v || "high", tone: /^(high|h|1|!)?$/i.test(v) ? App.Console.crit : App.Console.dim });
            } else if (c === "#") out.push({ icon: "sell", text: v, tone: App.Console.dim });
            else if (c === "~" && /^\d+[hmd]?(\d+m)?$/i.test(v)) out.push({ icon: "timer", text: v, tone: App.Console.dim });
            else if (c === "+" && !/^\d/.test(v)) out.push({ icon: "deployed_code", text: v, tone: App.Store.colorOf(v) });
            else if (c === "/" && !v.includes("/")) out.push({ icon: "list", text: v, tone: App.Store.colorOf(v) });
            else if (c === "*" && v.length) out.push({ icon: "repeat", text: v, tone: App.Console.data });
            else if (c === ">") out.push({ icon: App.Store.stateIcon(v), text: v, tone: App.Store.stateColor(v) });
        }
        return out;
    }

    function commit() {
        const line = (field.text + " " + root.suffix).trim();
        if (!field.text.trim()) return;
        App.Store.capture(line, out => { try { root.added(JSON.parse(out)); } catch (e) {} });
        field.text = "";
        root.parsed = null;
    }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 14; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
        spacing: 2
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 8
            Ui.Icon { text: "add_task"; size: 18; color: field.activeFocus ? App.Console.data : App.Console.faint }
            TextField {
                ContextMenu.menu: Ui.TextMenu { target: field }
                id: field
                Layout.fillWidth: true
                placeholderText: root.placeholder
                placeholderTextColor: App.Console.faint
                background: null
                color: App.Console.text
                font.family: App.Console.sans
                font.pixelSize: 15
                selectByMouse: true
                onTextChanged: parseTimer.restart()
                onAccepted: root.commit()
                Keys.onEscapePressed: { if (text.length) text = ""; else focus = false; }
            }
            Ui.IconButton {
                visible: field.text.trim().length > 0
                implicitWidth: 30; implicitHeight: 30
                icon: "keyboard_return"
                tooltip: qsTr("Add  (Enter)")
                onClicked: root.commit()
            }
        }
        Flow {
            id: chips
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: root.tokens.length > 0
            spacing: 6
            Repeater {
                model: root.tokens
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + 14
                    implicitHeight: 22
                    radius: 11
                    color: Qt.alpha(modelData.tone, 0.14)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 4
                        Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; size: 13; color: modelData.tone }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; font.family: App.Console.mono; font.pixelSize: 11; color: modelData.tone }
                    }
                }
            }
        }
    }
}
