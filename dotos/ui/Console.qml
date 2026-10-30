pragma Singleton
import QtQuick
import Quickshell
import "../ui" as Ui

/**
 * Hermes Dark console look — no separator rules.
 *
 * The old skin drew rule/ruleStrong/grid lines at ~7–14% alpha of onSurface.
 * This skin drops them: the glass surface edges are the only separation.
 * Every panel is a translucent glass layer (the sBase/sLow/sContainer/sHigh
 * surfaces from themes/hermes-dark.qml), with soft shadows giving depth.
 *
 * Severity colours are the one fixed thing: a warning must not turn
 * green because the wallpaper did.
 */
Singleton {
    readonly property var t: Ui.Themes.HermesDark   // the skin

    readonly property color bg:            t.sBase.color
    readonly property color panel:         t.sContainer.color
    readonly property color panelAlt:      t.sHigh.color
    readonly property color panelTop:      t.sHighest.color
    readonly property color text:          t.textHull
    readonly property color dim:           t.textFaint
    readonly property color faint:         t.textDim
    readonly property color data:          t.data
    readonly property color onData:        t.onPrimary
    readonly property color accent:        t.accent
    readonly property color onAccent:      t.onAccent
    readonly property color ok:            t.success
    readonly property color warn:          t.warn
    readonly property color crit:          t.error

    readonly property string mono: t.mono
    readonly property string sans: t.sans

    // ── Rounding (the zash radius system) ──
    readonly property int radius:      t.rounding.normal
    readonly property int radiusSmall: t.rounding.small
    readonly property int radiusLarge: t.rounding.large
    readonly property int radiusFull:  t.rounding.full

    // ── Depth (soft shadows, no separator lines) ──
    readonly property string cardShadow: "0 2 8 rgba(0,0,0,0.30), 0 1 4 rgba(0,0,0,0.20)"
    readonly property string popShadow:  "0 4 12 rgba(0,0,0,0.35), 0 2 6 rgba(0,0,0,0.25)"
    readonly property string scrim:      "rgba(0,0,0,0.35)"   // modal dim

    // ── No separator rules anywhere ──
    readonly property color rule:        "transparent"
    readonly property color ruleStrong:  "transparent"
    readonly property color grid:        "transparent"
    readonly property string hairline:   "transparent"

    // ── Glass edges (the new separation) ──
    readonly property string glassEdge:
        "inset 0 0 0 1px rgba(255,255,255,0.06)"

    function severity(s) { return s === "Critical" ? crit : s === "Warn" ? warn : dim; }

    // ── Heat cells: a primary ramp, then warn, then crit ──
    function heat(f) {
        if (f >= 0.9) return crit;
        if (f >= 0.7) return warn;
        return Qt.alpha(t.primary, 0.12 + 0.75 * Math.max(0, f / 0.7));
    }

    // ── Glass panel builder: no flat surfaces, all translucent + shadow ──
    function glassPanel(extra) {
        var p = {
            color: t.sContainer,
            opacity: 0.90,
            radius: t.rounding.normal,
            shadow: t.cardShadow,
            border: t.glassEdge
        };
        for (var k in extra) p[k] = extra[k];
        return p;
    }
}
