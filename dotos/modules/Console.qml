pragma Singleton
import QtQuick
import Quickshell
import "../ui" as Ui

/**
 * Our look, carrying an instrument: the shell's Material roles and rounding
 * for every surface (so it retints with the wallpaper like the rest of the
 * desktop), and instrument habits for the data — monospace numbers, gridded
 * plots, dense tables, severity codes.
 *
 * Severity colours are the one fixed thing: a warning must not turn green
 * because the wallpaper did.
 */
Singleton {
    readonly property color bg: Ui.Appearance.background
    readonly property color panel: Ui.Appearance.surfaceContainer
    readonly property color panelAlt: Ui.Appearance.surfaceContainerHigh
    readonly property color rule: Qt.alpha(Ui.Appearance.onSurface, 0.08)
    readonly property color ruleStrong: Qt.alpha(Ui.Appearance.onSurface, 0.14)
    readonly property color grid: Qt.alpha(Ui.Appearance.onSurface, 0.07)
    readonly property color text: Ui.Appearance.onSurface
    readonly property color dim: Ui.Appearance.onSurfaceVariant
    readonly property color faint: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.6)
    readonly property color data: Ui.Appearance.primary
    readonly property color onData: Ui.Appearance.textOnPrimary
    readonly property color data2: Qt.alpha(Ui.Appearance.onSurface, 0.55)

    readonly property color ok: "#5fb98a"
    readonly property color warn: "#d8a54a"
    readonly property color crit: Ui.Appearance.error

    readonly property string mono: Ui.Appearance.font.mono
    readonly property string sans: Ui.Appearance.font.family
    readonly property int radius: Ui.Appearance.rounding.normal
    readonly property int radiusSmall: Ui.Appearance.rounding.small

    function severity(s) { return s === "Critical" ? crit : s === "Warn" ? warn : dim; }
    /// 0..1 load -> colour for heat cells: a primary ramp, then warn, then crit
    function heat(f) {
        if (f >= 0.9) return crit;
        if (f >= 0.7) return warn;
        return Qt.alpha(data, 0.12 + 0.75 * Math.max(0, f / 0.7));
    }
}
