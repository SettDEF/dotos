// A tag, as a pill. Notion and Obsidian both render tags this way and it is
// most of why a list of them reads as metadata rather than as more sentence.
//
// Sized off the token scale so a chip in Kalends matches one in Dotos.
import QtQuick
import "." as Ui

Rectangle {
    id: chip

    property string text: ""
    /// Tint the pill towards a role — a tag's own colour, a priority, a state.
    property color accent: Ui.Appearance.onSurfaceVariant
    /// Filled reads as a state you are in; outlined as a label on a thing.
    property bool filled: false
    property bool interactive: false
    /// the accent, lifted towards white when it is too dark to read on a dark panel
    readonly property color ink: {
        const lum = c => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        const a = chip.accent, l = lum(a);
        return lum(Ui.Appearance.surfaceContainerLow) < 0.3 && l < 0.32 ? Qt.tint(a, Qt.rgba(1, 1, 1, 0.55 - l)) : a;
    }

    signal clicked

    implicitWidth: label.implicitWidth + Ui.Appearance.space.normal * 2
    implicitHeight: label.implicitHeight + Ui.Appearance.space.tiny
    radius: Ui.Appearance.rounding.full

    color: chip.filled
        ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b,
                  hov.hovered && chip.interactive ? 0.28 : 0.18)
        : hov.hovered && chip.interactive
            ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, Ui.Appearance.state.hover)
            : "transparent"
    border.width: chip.filled ? 0 : 1
    border.color: Qt.rgba(chip.ink.r, chip.ink.g, chip.ink.b, 0.35)

    Behavior on color {
        ColorAnimation { duration: Ui.Appearance.motion.fast }
    }

    HoverHandler {
        id: hov
        enabled: chip.interactive
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: chip.interactive
        onTapped: chip.clicked()
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        font.family: Ui.Appearance.font.family
        font.pixelSize: Ui.Appearance.font.smallest
        color: chip.ink
        opacity: chip.filled ? 1 : Ui.Appearance.state.muted
    }
}
