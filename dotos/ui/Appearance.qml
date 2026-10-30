pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Material 3 roles for the app.
 *
 * Primary source is kdeglobals — the same file Dolphin and every other KDE
 * app reads — so this window is the same colour as the rest of the desktop
 * rather than merely the same palette. tinct rewrites both kdeglobals and
 * quickshell's colors.json, but not always in the same pass: colors.json has
 * been seen hours stale against kdeglobals, which showed up as this app
 * disagreeing with Dolphin. colors.json is kept only as a fallback.
 */
Singleton {
    id: root

    readonly property string configHome:
        Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string stateHome:
        Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")

    property var kde: ({})          // "Section/Key" -> "#rrggbb"
    property var m3: ({})           // colors.json fallback
    property var shellFonts: ({})

    function kdeCol(section, key) { return root.kde[section + "/" + key]; }
    /// The shell's palette (colors.json — what quickshell, Rodded and quarry use)
    /// first, so this window matches the apps next to it; kdeglobals second.
    function pick(section, key, m3key, fallback) {
        return root.m3[m3key] ?? root.kdeCol(section, key) ?? fallback;
    }

    readonly property color background:  pick("Colors:Window", "BackgroundNormal", "background", "#1d1d1e")
    readonly property color textOnBackground: pick("Colors:Window", "ForegroundNormal", "on_background", "#e2e2e2")
    readonly property color surfaceContainer: pick("Colors:Button", "BackgroundNormal", "surface_container", "#2a2a2a")
    readonly property color surfaceContainerHigh: pick("Colors:Button", "BackgroundAlternate", "surface_container_high", "#474747")
    readonly property color surfaceContainerHighest: pick("Colors:Button", "BackgroundAlternate", "surface_container_highest", "#505050")
    readonly property color surfaceContainerLow: pick("Colors:Window", "BackgroundNormal", "surface_container_low", "#202020")
    readonly property color onSurface:   pick("Colors:Window", "ForegroundNormal", "on_surface", "#e2e2e2")
    readonly property color onSurfaceVariant: pick("Colors:Header", "ForegroundNormal", "on_surface_variant", "#c6c6c6")
    readonly property color outlineVariant: pick("Colors:Window", "ForegroundInactive", "outline_variant", "#919191")
    readonly property color primary:     pick("Colors:Selection", "BackgroundNormal", "primary", "#faa8f2")
    readonly property color textOnPrimary:   pick("Colors:Selection", "ForegroundNormal", "on_primary", "#541355")
    readonly property color secondaryContainer: pick("Colors:Button", "BackgroundAlternate", "secondary_container", "#474747")
    readonly property color onSecondaryContainer: pick("Colors:Button", "ForegroundNormal", "on_secondary_container", "#e2e2e2")
    readonly property color error:       pick("Colors:Window", "ForegroundNegative", "error", "#ffb3b4")

    // ── Spacing ──────────────────────────────────────────────────────────
    // Sized from what the two apps already use, not invented: 6 and 8 dominate,
    // 4 and 12 next, 2 for hairlines. Naming them stops the next component
    // picking 9 or 11 and quietly breaking the rhythm.
    readonly property QtObject space: QtObject {
        readonly property int hair: 2
        readonly property int tiny: 4
        readonly property int small: 6
        readonly property int normal: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int huge: 24
    }

    // ── Separation (glass edges, no flat separator rules) ──
    // The old skin drew rule/ruleStrong/grid lines at 7–14% alpha.
    // This skin drops them: the glass surface edges are the only separation.
    readonly property string rule:        "transparent"
    readonly property string ruleStrong:  "transparent"
    readonly property string grid:        "transparent"
    readonly property string hairline:    "transparent"
    /// A thin glass edge — the new separator.
    readonly property string glassEdge: "inset 0 0 0 1px rgba(255,255,255,0.07)"

    // ── Motion ───────────────────────────────────────────────────────────
    // 120ms is already the de facto hover duration in both apps; the rest
    // extend around it. Anything slower than `slow` reads as lag, not polish.
    readonly property QtObject motion: QtObject {
        readonly property int instant: 90
        readonly property int fast: 120
        readonly property int normal: 160
        readonly property int slow: 240
        /// Material 3 standard easing, as a bezier for Behavior blocks.
        readonly property var standardCurve: [0.2, 0.0, 0.0, 1.0]
        readonly property var decelCurve: [0.05, 0.7, 0.1, 1.0]
    }

    // ── State layers ─────────────────────────────────────────────────────
    // Material 3's state-layer opacities. Hardcoding these per component is
    // how a hover ends up darker in one window than the other.
    readonly property QtObject state: QtObject {
        readonly property real hover: 0.08
        readonly property real focus: 0.10
        readonly property real pressed: 0.12
        readonly property real dragged: 0.16
        /// Text and icons that are present but not actionable.
        readonly property real disabled: 0.38
        /// Secondary text that should recede without disappearing.
        readonly property real muted: 0.62
    }

    // ── Depth ────────────────────────────────────────────────────────────
    // A popup needs to sit above the thing it came from, and a scrim needs to
    // be the same darkness everywhere.
    readonly property QtObject depth: QtObject {
        readonly property real scrim: 0.45
        readonly property int shadowSmall: 8
        readonly property int shadowNormal: 16
        readonly property int shadowLarge: 28
    }

    readonly property QtObject font: QtObject {
        readonly property int smallest: 10
        readonly property int smaller: 12
        readonly property int small: 15
        readonly property int normal: 16
        readonly property int larger: 19
        readonly property int huge: 22
        readonly property string family: root.shellFonts.main ?? "sans-serif"
        readonly property string mono: root.shellFonts.monospace ?? "monospace"
    }
    readonly property QtObject rounding: QtObject {
        readonly property int small: 12
        readonly property int normal: 17
        readonly property int large: 23
        readonly property int full: 9999
    }

    /// Minimal INI reader: only [Colors:*] sections, only key=value lines.
    function parseKde(text) {
        const out = ({});
        let section = "";
        for (const raw of String(text ?? "").split("\n")) {
            const line = raw.trim();
            if (line.length === 0 || line.startsWith("#")) continue;
            if (line.startsWith("[")) {
                // "[Colors:Header][Inactive]" — take the first group only.
                const end = line.indexOf("]");
                section = end > 0 ? line.slice(1, end) : "";
                // Inactive/Disabled variants would overwrite the base role.
                if (line.indexOf("][") >= 0) section = "";
                continue;
            }
            if (!section.startsWith("Colors:")) continue;
            const eq = line.indexOf("=");
            if (eq < 0) continue;
            out[section + "/" + line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
        }
        return out;
    }

    FileView {
        id: kdeFile
        path: root.configHome + "/kdeglobals"
        watchChanges: true
        onFileChanged: kdeFile.reload()
        onLoaded: root.kde = root.parseKde(kdeFile.text())
    }
    FileView {
        id: m3File
        path: root.stateHome + "/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: m3File.reload()
        onLoaded: {
            try { root.m3 = JSON.parse(m3File.text()) ?? ({}); }
            catch (e) { root.m3 = ({}); }
        }
    }
    FileView {
        id: shellConfigFile
        path: root.configHome + "/illogical-impulse/config.json"
        watchChanges: true
        onFileChanged: shellConfigFile.reload()
        onLoaded: {
            try { root.shellFonts = (JSON.parse(shellConfigFile.text()) ?? {}).appearance?.fonts ?? ({}); }
            catch (e) { root.shellFonts = ({}); }
        }
    }
    Component.onCompleted: {
        kdeFile.reload();
        m3File.reload();
        shellConfigFile.reload();
    }
}
