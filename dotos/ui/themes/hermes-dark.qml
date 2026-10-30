// theme/hermes-dark.qml
// A Hermes skin, written in the same tinct role language the zash (terminal),
// zeit (tmux) and zett (QML) projects read.
//
// Surfaces: translucent glass, not flat panels.
// Separators: none — the only edges are the glass surfaces themselves.
// Motion: 120ms feel, soft shadows, depth through opacity.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../ui" as Ui

Singleton {
    id: root

    // ── The tinct palette (copy of hermes-dark.toml → JSON) ──
    // In practice these get loaded from the .toml via the tinct CLI.
    property var tinct: {
        "bg0_h": "#111316", "bg0": "#161A1E", "bg0_s": "#1C2227",
        "bg1": "#1F252B", "bg2": "#262D36", "bg3": "#2E3740", "bg4": "#38414C",
        "bg0_a": "#161A1E", "bg1_a": "#1F252B", "bg2_a": "#262D36",
        "bg3_a": "#2E3740", "bg4_a": "#38414C",
        "fg0": "#EDF1F3", "fg1": "#E8ECEF", "fg2": "#D7DCE0", "fg3": "#C3CBD3",
        "fg4": "#9AABB4", "gray": "#6B7681",
        "accent": "#82A8C0", "accent_h": "#9BB4D0", "onAccent": "#1A232B",
        "primary": "#6E93AC", "secondary": "#6E93AC", "tertiary": "#82A8C0",
        "error": "#C96A6A", "success": "#6E9B7A", "warn": "#C9A26A", "info": "#6E93AC"
    }

    // ── Glass surfaces (the core of the zash/zeit/zett look) ──
    function glass(base, opacity, blur) {
        return {
            color: root.tinct[base],
            opacity: opacity,     // 0..1 — translucent, never flat
            blur: blur,           // 8..24 — frosted glass (when supported)
            radius: 16,           // rounded corners (the zash radius)
            shadow: "0 2 8 rgba(0,0,0,0.35), 0 1 4 rgba(0,0,0,0.2)"
        };
    }

    // ── The six glass layers (from the tinct roles) ──
    readonly property var sBase:    root.glass("bg0_a", 0.92, 10)  // the frosted sheet behind panels
    readonly property var sLow:     root.glass("bg0_s", 0.85, 8)   // lower glass
    readonly property var sContainer: root.glass("bg1", 0.90, 6)   // standard panel
    readonly property var sHigh:    root.glass("bg2", 0.94, 4)     // raised surface
    readonly property var sHighest: root.glass("bg3", 0.96, 2)     // the top layer
    readonly property var sDim:     root.glass("bg0_a", 0.70, 0)   // dim glass, no blur

    // ── Text (no separator rules anywhere) ──
    readonly property color textHull:  root.tinct.fg1        // main text
    readonly property color textFaint: root.tinct.fg3        // faded text
    readonly property color textDim:   root.tinct.fg4        // barely-there
    readonly property color textRule:  "transparent"         // ← no separator rules

    // ── Accent (the one colour that does work) ──
    readonly property color accent:    root.tinct.accent
    readonly property color accentHover: root.tinct.accent_h
    readonly property color onAccent:  root.tinct.onAccent

    // ── Semantic (muted, never loud) ──
    readonly property color primary:    root.tinct.primary
    readonly property color onPrimary:  root.tinct.textHull
    readonly property color error:      root.tinct.error
    readonly property color success:    root.tinct.success
    readonly property color warn:       root.tinct.warn
    readonly property color info:       root.tinct.info
    readonly property color data:       root.tinct.primary

    // ── Depth (for shadows that give the glass its relief) ──
    readonly property var depth: {
        scrim: 0.35,          // the modal scrim
        shadowSmall: 6,
        shadowNormal: 12,
        shadowLarge: 20
    };

    // ── Motion (120ms feel, the zash cursor-animation pace) ──
    readonly property var motion: {
        instant: 90,
        fast:    120,
        normal:  160,
        slow:    240,
        standardCurve: [0.2, 0.0, 0.0, 1.0],
        decelCurve:    [0.05, 0.7, 0.1, 1.0]
    };

    // ── Fonts (from the shell config) ──
    readonly property string mono: "MonaspiceNe Nerd Font"
    readonly property string sans: "Google Sans Flex"

    // ── Rounding (the zash radius system) ──
    readonly property var rounding: {
        none: 0,
        small: 6,
        normal: 12,
        large: 16,
        full: 9999
    };

    // ── Helpers ──
    function lighten(hex, amt) {
        // minimal hex lightener: scale toward white
        var r = parseInt(hex.slice(1,3),16), g = parseInt(hex.slice(3,5),16), b = parseInt(hex.slice(5,7),16);
        r = Math.min(255, Math.round(r + (255 - r) * amt));
        g = Math.min(255, Math.round(g + (255 - g) * amt));
        b = Math.min(255, Math.round(b + (255 - b) * amt));
        return "#" + [r,g,b].map(c => c.toString(16).padStart(2,"0")).join("");
    }

    function darken(hex, amt) {
        var r = parseInt(hex.slice(1,3),16), g = parseInt(hex.slice(3,5),16), b = parseInt(hex.slice(5,7),16);
        r = Math.max(0, Math.round(r * (1 - amt)));
        g = Math.max(0, Math.round(g * (1 - amt)));
        b = Math.max(0, Math.round(b * (1 - amt)));
        return "#" + [r,g,b].map(c => c.toString(16).padStart(2,"0")).join("");
    }
}
