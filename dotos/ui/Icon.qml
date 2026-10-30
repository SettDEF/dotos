import QtQuick
import "." as App

// Material Symbols. Bare Unicode glyphs (‹ › ⚙) have wildly different metrics
// and none of them sit on the same optical centre, which is what made the
// nav buttons look off.
Text {
    id: icon
    property real size: App.Appearance.font.normal
    property bool filled: false

    font.family: "Material Symbols Rounded"
    font.pixelSize: icon.size
    font.variableAxes: ({ "FILL": icon.filled ? 1 : 0 })
    // The glyph box is square and the baseline is not where you'd draw it, so
    // centre by the paint area, not the text origin.
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
    color: App.Appearance.onSurface
}
