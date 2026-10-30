// A board of cards on a 12-column grid that the user can arrange: drag a card, pull any edge or
// corner to resize it, swap it for another kind, remove it, bring hidden ones back. Cards pack
// upward and make room for each other. Needs only the ui/ tokens, so it can be dropped into any
// of our quickshell apps.
//
//   Ui.ArrangeBoard {
//       defs: [{ id: "agents", title: "Agents", icon: "smart_toy", w: 8, h: 5, minW: 4, minH: 3, comp: agentsCard }, …]
//       defaultSpots: ({ agents: [0, 0], … })      // where "Reset" puts each card
//       saved: settings.layout                       // JSON the board gave you last time
//       isShown: id => settings.shown(id)            // is this kind of card on the board
//       isDefaultOn: id => true                      // is it on after "Reset"
//       editing: settings.arranging
//       style: "border"                              // "border" (the edge thickens) | "snap" (grid dots, corner dots)
//       onLayoutSaved: json => settings.layout = json
//       onCardToggled: (id, on) => settings.setShown(id, on)
//       onDoneRequested: settings.arranging = false
//       onStyleRequested: s => settings.style = s
//   }
//
// Each `comp` is a Component that fills its card (it gets the card's size).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "." as Ui

Item {
    id: root

    // ── what the host provides ─────────────────────────────────────────
    property var defs: []                      // [{ id, title, icon, w, h, minW, minH, comp }]
    property var defaultSpots: ({})            // id → [col, row]
    property string saved: ""                  // JSON [{ id, col, row, w, h }]
    property var isShown: id => true
    property var isDefaultOn: id => true
    property bool editing: false
    property string style: "border"
    property int cols: 12
    property int gap: 12
    property int cellH: 40
    property real pad: 18
    property bool showBar: true
    signal layoutSaved(string json)
    signal cardToggled(string id, bool on)
    signal doneRequested()
    signal styleRequested(string style)

    // ── state ──────────────────────────────────────────────────────────
    readonly property color accent: Ui.Appearance.primary
    readonly property real cellW: (board.width + root.gap) / root.cols
    readonly property real radius: Ui.Appearance.rounding.normal
    readonly property bool snap: root.style === "snap"
    property int bottomRows: 8
    property int swapIndex: -1
    // the card being moved or resized, and the slot it would land in (the ghost)
    property int activeIndex: -1
    property real ghostX: 0
    property real ghostY: 0
    property real ghostW: 0
    property real ghostH: 0
    // the widget gallery: tiles dragged from the popup onto the board
    property bool galleryOpen: false
    property var galleryMoved: null
    property var dragKind: null              // the def being dragged out of the gallery, or null
    property real dragX: 0                   // pointer, in this item's coordinates
    property real dragY: 0
    readonly property bool dropOver: root.dragKind !== null && !galleryPanel.contains(root.mapToItem(galleryPanel, root.dragX, root.dragY))
        && root.dragX > root.pad && root.dragX < root.width - root.pad && root.dragY > 0
    readonly property point dropCell: {
        // the cell under the pointer, with the dragged card's top-left near it
        const p = board.mapFromItem(root, root.dragX, root.dragY);
        const d = root.dragKind;
        if (!d) return Qt.point(0, 0);
        const col = Math.max(0, Math.min(root.cols - d.w, Math.round(p.x / root.cellW - d.w / 2)));
        const row = Math.max(0, Math.round(p.y / root.cellH - d.h / 2));
        return Qt.point(col, row);
    }
    onEditingChanged: if (!root.editing) { root.galleryOpen = false; root.dragKind = null; root.swapIndex = -1; }

    ListModel { id: lm }

    function defOf(id) { return root.defs.find(d => d.id === id) ?? null; }
    function updateGhost() {
        if (root.activeIndex < 0 || root.activeIndex >= lm.count) return;
        const o = lm.get(root.activeIndex);
        root.ghostX = o.col * root.cellW; root.ghostY = o.row * root.cellH;
        root.ghostW = o.w * root.cellW - root.gap; root.ghostH = o.h * root.cellH - root.gap;
    }
    function snapshot() {
        const a = [];
        for (let i = 0; i < lm.count; i++) { const o = lm.get(i); a.push({ i, id: o.cardId, col: o.col, row: o.row, w: o.w, h: o.h, on: root.isShown(o.cardId) }); }
        return a;
    }
    /// pack the shown cards: the one being moved keeps its place, the rest float up and drop below whatever is in their way
    function settle(a, prio) {
        const order = a.filter(o => o.on).sort((p, q) => p.i === prio ? -1 : q.i === prio ? 1 : (p.row - q.row) || (p.col - q.col));
        const placed = [];
        const hit = (o, row) => placed.some(p => o.col < p.col + p.w && o.col + o.w > p.col && row < p.row + p.h && row + o.h > p.row);
        for (const o of order) {
            let r = o.i === prio ? o.row : 0;
            while (hit(o, r)) r++;
            o.row = r;
            placed.push(o);
        }
    }
    function apply(a, quiet) {
        for (const o of a) {
            lm.setProperty(o.i, "col", o.col); lm.setProperty(o.i, "row", o.row);
            lm.setProperty(o.i, "w", o.w); lm.setProperty(o.i, "h", o.h);
        }
        root.bottomRows = Math.max(6, ...a.filter(o => o.on).map(o => o.row + o.h));
        root.updateGhost();
        // quiet: laid out from what is saved (or nothing yet), not changed by the user: nothing to save
        if (!quiet) saveTimer.restart();
    }
    /// pack again (the host switched a kind of card on or off)
    function repack() { if (lm.count) { const a = root.snapshot(); root.settle(a, -1); root.apply(a); } }
    function moveTo(index, col, row) {
        const a = root.snapshot(), o = a[index];
        const c = Math.max(0, Math.min(root.cols - o.w, col)), r = Math.max(0, row);
        if (c === o.col && r === o.row) return;
        o.col = c; o.row = r;
        root.settle(a, index);
        root.apply(a);
    }
    /// resize from any edge or corner (sx, sy: -1 left/top, 0 none, +1 right/bottom); r0 is the card's cells when the pull began, dx/dy the pull in cells
    function resizeEdges(index, sx, sy, r0, dx, dy) {
        const a = root.snapshot(), o = a[index], d = root.defOf(o.id);
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        let col = r0.col, row = r0.row, w = r0.w, h = r0.h;
        if (sx > 0) w = clamp(r0.w + dx, d.minW, root.cols - r0.col);
        if (sx < 0) { col = clamp(r0.col + dx, 0, r0.col + r0.w - d.minW); w = r0.w + (r0.col - col); }
        if (sy > 0) h = clamp(r0.h + dy, d.minH, 40);
        if (sy < 0) { row = clamp(r0.row + dy, 0, r0.row + r0.h - d.minH); h = r0.h + (r0.row - row); }
        if (col === o.col && row === o.row && w === o.w && h === o.h) return;
        o.col = col; o.row = row; o.w = w; o.h = h;
        root.settle(a, index);
        root.apply(a);
    }
    /// bring a kind onto the board at a chosen cell (a drop from the gallery): fresh default size, the others make room
    function addCardAt(id, col, row) {
        root.cardToggled(id, true);
        const a = root.snapshot();
        const o = a.find(x => x.id === id), d = root.defOf(id);
        if (!o || !d) return;
        o.w = d.w; o.h = d.h; o.on = true;
        o.col = Math.max(0, Math.min(root.cols - o.w, col));
        o.row = Math.max(0, row);
        root.settle(a, o.i);
        root.apply(a);
    }
    /// bring a hidden kind back, at the bottom
    function addCard(id) {
        root.cardToggled(id, true);
        const a = root.snapshot();
        for (const o of a) if (o.id === id) { o.row = 999; o.on = true; root.settle(a, o.i); }
        root.apply(a);
    }
    function removeCard(id) {
        root.cardToggled(id, false);
        const a = root.snapshot();
        for (const o of a) if (o.id === id) o.on = false;
        root.settle(a, -1);
        root.apply(a);
    }
    /// put another kind in this slot; if it is already on the board the two trade places
    function replaceCard(index, newId) {
        const old = lm.get(index).cardId;
        if (old === newId) return;
        let other = -1;
        for (let i = 0; i < lm.count; i++) if (lm.get(i).cardId === newId) other = i;
        if (other >= 0 && root.isShown(newId)) {
            lm.setProperty(index, "cardId", newId);
            lm.setProperty(other, "cardId", old);
        } else {
            root.cardToggled(old, false);
            root.cardToggled(newId, true);
            lm.setProperty(index, "cardId", newId);
        }
        // keep the slot big enough for what is now in it
        const a = root.snapshot(), d = root.defOf(newId);
        a[index].w = Math.min(Math.max(a[index].w, d.minW), root.cols - a[index].col);
        a[index].h = Math.max(a[index].h, d.minH);
        root.settle(a, index);
        root.apply(a);
    }
    function resetLayout(quiet) {
        lm.clear();
        for (const d of root.defs) lm.append({ cardId: d.id, col: 0, row: 999, w: d.w, h: d.h });
        for (let i = 0; i < lm.count; i++) {
            const s = root.defaultSpots[lm.get(i).cardId] ?? [0, 999];
            lm.setProperty(i, "col", s[0]); lm.setProperty(i, "row", s[1]);
        }
        for (const d of root.defs) root.cardToggled(d.id, root.isDefaultOn(d.id));
        const a = root.snapshot();
        root.settle(a, -1);
        root.apply(a, quiet);
    }
    function loadLayout() {
        lm.clear();
        let saved = [];
        try { saved = JSON.parse(root.saved || "[]"); } catch (e) {}
        for (const s of saved) {
            const d = root.defOf(s.id);
            let have = false;
            for (let i = 0; i < lm.count; i++) if (lm.get(i).cardId === s.id) have = true;
            if (d && !have) lm.append({ cardId: s.id, col: s.col, row: s.row, w: Math.max(d.minW, s.w), h: Math.max(d.minH, s.h) });
        }
        // kinds added since the layout was saved go at the bottom
        for (const d of root.defs) {
            let have = false;
            for (let i = 0; i < lm.count; i++) if (lm.get(i).cardId === d.id) have = true;
            if (!have) lm.append({ cardId: d.id, col: 0, row: 999, w: d.w, h: d.h });
        }
        // nothing saved (yet): the defaults on screen, and NOT saved, or they overwrite a layout still loading
        if (saved.length === 0) { root.resetLayout(true); return; }
        const a = root.snapshot();
        root.settle(a, -1);
        for (const o of a) { lm.setProperty(o.i, "col", o.col); lm.setProperty(o.i, "row", o.row); }
        root.bottomRows = Math.max(6, ...a.filter(o => o.on).map(o => o.row + o.h));
    }
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: {
            const out = [];
            for (let i = 0; i < lm.count; i++) { const o = lm.get(i); out.push({ id: o.cardId, col: o.col, row: o.row, w: o.w, h: o.h }); }
            root.lastSent = JSON.stringify(out);
            root.layoutSaved(root.lastSent);
        }
    }
    Component.onCompleted: root.loadLayout()
    // the saved layout arriving later (or changed on disk): taken, unless the user is arranging, or it is
    // our own save coming back
    property string lastSent: ""
    onSavedChanged: if (!root.editing && root.saved !== root.lastSent) root.loadLayout()

    // ── the board ──────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentHeight: board.height + root.pad * 2 + (root.editing && root.showBar ? 70 : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: board
            x: root.pad; y: root.pad
            width: parent.width - root.pad * 2
            height: root.bottomRows * root.cellH

            // snap style: the grid the cards land on
            Repeater {
                model: root.editing && root.snap ? (root.cols + 1) * (root.bottomRows + 2) : 0
                delegate: Rectangle {
                    required property int index
                    z: 0
                    x: (index % (root.cols + 1)) * root.cellW - root.gap / 2 - 1.5
                    y: Math.floor(index / (root.cols + 1)) * root.cellH - root.gap / 2 - 1.5
                    width: 3; height: 3; radius: 1.5
                    color: Qt.alpha(Ui.Appearance.onSurface, 0.22)
                }
            }

            // the slot a moved or resized card would land in; it glides from slot to slot
            Rectangle {
                z: 0
                visible: root.activeIndex >= 0
                x: root.ghostX; y: root.ghostY; width: root.ghostW; height: root.ghostH
                radius: root.radius + (root.snap ? 2 : 0)
                color: Qt.alpha(root.accent, 0.10)
                border.width: 1.5
                border.color: Qt.alpha(root.accent, 0.75)
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }

            // a widget being dragged in: where it would land
            Rectangle {
                z: 0
                visible: root.dropOver
                readonly property var d: root.dragKind
                x: root.dropCell.x * root.cellW; y: root.dropCell.y * root.cellH
                width: d ? d.w * root.cellW - root.gap : 0; height: d ? d.h * root.cellH - root.gap : 0
                radius: root.radius + (root.snap ? 2 : 0)
                color: Qt.alpha(root.accent, 0.12)
                border.width: 1.5
                border.color: Qt.alpha(root.accent, 0.8)
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }

            Repeater {
                model: lm
                delegate: Item {
                    id: cell
                    required property int index
                    required property string cardId
                    required property int col
                    required property int row
                    required property int w
                    required property int h
                    readonly property var def: root.defOf(cell.cardId)
                    readonly property bool hovered: cellHover.hovered
                    visible: root.isShown(cell.cardId)
                    property bool dragging: false
                    property bool _logged: false
                    property bool resizing: false
                    readonly property bool held: cell.dragging || cell.resizing
                    // while held, a card follows the pointer freely; the grid slot (and the ghost) snap
                    property real fx: 0
                    property real fy: 0
                    property real fw: 0
                    property real fh: 0
                    property var p0: Qt.point(0, 0)
                    property var r0: ({ col: 0, row: 0, w: 1, h: 1 })

                    x: cell.held ? cell.fx : cell.col * root.cellW
                    y: cell.held ? cell.fy : cell.row * root.cellH
                    width: cell.resizing ? cell.fw : cell.w * root.cellW - root.gap
                    height: cell.resizing ? cell.fh : cell.h * root.cellH - root.gap
                    z: cell.held ? 20 : cell.lifted ? 10 : 1
                    // picked up (or, in the snap style, reached for): a touch bigger, with a soft shadow
                    readonly property bool lifted: cell.held || (root.editing && root.snap && cell.hovered)
                    scale: cell.lifted ? (root.snap ? 1.02 : 1.012) : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on x { enabled: !cell.held; NumberAnimation { duration: 230; easing.type: Easing.OutQuart } }
                    Behavior on y { enabled: !cell.held; NumberAnimation { duration: 230; easing.type: Easing.OutQuart } }
                    Behavior on width { enabled: !cell.resizing; NumberAnimation { duration: 230; easing.type: Easing.OutQuart } }
                    Behavior on height { enabled: !cell.resizing; NumberAnimation { duration: 230; easing.type: Easing.OutQuart } }

                    Repeater {
                        model: 2
                        delegate: Rectangle {
                            required property int index
                            z: -1
                            anchors { fill: parent; margins: -(3 + index * 4); topMargin: -(3 + index * 4) + 6; bottomMargin: -(3 + index * 4) - 6 }
                            radius: root.radius + 3 + index * 4
                            color: "black"
                            opacity: cell.lifted ? (index === 0 ? 0.22 : 0.12) : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        clip: true
                        sourceComponent: cell.def ? cell.def.comp : null
                    }

                    // ── arranging ──
                    // the whole card is the grip: grab it anywhere to move it
                    MouseArea {
                        id: mover
                        visible: root.editing
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true      // the scrolling area must not take the drag over
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real offX: 0
                        property real offY: 0
                        onPressed: m => {
                            console.log("[arrange] press on", cell.cardId);
                            const p = mapToItem(board, m.x, m.y);
                            offX = p.x - cell.x; offY = p.y - cell.y;
                            cell.fx = cell.x; cell.fy = cell.y;
                            cell.dragging = true;
                            root.activeIndex = cell.index; root.updateGhost();
                        }
                        onPositionChanged: m => {
                            if (!pressed) return;
                            const p = mapToItem(board, m.x, m.y);
                            cell.fx = Math.max(0, Math.min(board.width - cell.width, p.x - offX));
                            cell.fy = Math.max(0, p.y - offY);
                            if (!cell._logged) { cell._logged = true; console.log("[arrange] moving", cell.cardId, "to", Math.round(cell.fx), Math.round(cell.fy)); }
                            root.moveTo(cell.index, Math.round(cell.fx / root.cellW), Math.round(cell.fy / root.cellH));
                        }
                        onReleased: { cell._logged = false; cell.dragging = false; root.activeIndex = -1; }
                        onCanceled: { console.log("[arrange] drag of", cell.cardId, "was taken over (cancelled)"); cell.dragging = false; root.activeIndex = -1; }
                    }
                    // the outline lights up while the card is hovered, moved or resized
                    Rectangle {
                        anchors.fill: parent
                        visible: root.editing
                        radius: root.radius
                        color: cell.dragging ? Qt.alpha(root.accent, 0.08) : "transparent"
                        border.width: root.snap ? 1 : 1.5
                        border.color: Qt.alpha(root.accent, cell.held || cell.hovered ? 0.9 : (root.snap ? 0.12 : 0.35))
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }
                    HoverHandler { id: cellHover; enabled: root.editing }
                    // snap style: the dashed landing slot around the card, a few pixels outside it
                    Shape {
                        id: slotShape
                        visible: root.editing && root.snap && (cell.hovered || cell.held)
                        z: 10
                        x: -6; y: -6
                        width: cell.width + 12; height: cell.height + 12
                        preferredRendererType: Shape.GeometryRenderer
                        ShapePath {
                            id: sp
                            readonly property real w: slotShape.width
                            readonly property real h: slotShape.height
                            readonly property real r: root.radius + 6
                            strokeColor: Qt.alpha(root.accent, 0.9)
                            strokeWidth: 1.5
                            strokeStyle: ShapePath.DashLine
                            dashPattern: [4, 3]
                            fillColor: "transparent"
                            startX: sp.r; startY: 0.75
                            PathLine { x: sp.w - sp.r; y: 0.75 }
                            PathArc { x: sp.w - 0.75; y: sp.r; radiusX: sp.r; radiusY: sp.r }
                            PathLine { x: sp.w - 0.75; y: sp.h - sp.r }
                            PathArc { x: sp.w - sp.r; y: sp.h - 0.75; radiusX: sp.r; radiusY: sp.r }
                            PathLine { x: sp.r; y: sp.h - 0.75 }
                            PathArc { x: 0.75; y: sp.h - sp.r; radiusX: sp.r; radiusY: sp.r }
                            PathLine { x: 0.75; y: sp.r }
                            PathArc { x: sp.r; y: 0.75; radiusX: sp.r; radiusY: sp.r }
                        }
                    }

                    // swap / remove: a small pill on the card's top edge, only while it is hovered
                    Rectangle {
                        visible: root.editing && cell.hovered && !cell.held
                        anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: -15 }
                        z: 60
                        implicitWidth: toolRow.implicitWidth + 8
                        implicitHeight: 30
                        radius: 15
                        color: Ui.Appearance.surfaceContainerHighest
                        border.width: 1
                        border.color: Ui.Appearance.outlineVariant
                        Row {
                            id: toolRow
                            anchors.centerIn: parent
                            spacing: 2
                            Ui.IconButton { implicitWidth: 24; implicitHeight: 24; icon: "swap_horiz"; tooltip: qsTr("Swap for another card"); onClicked: root.swapIndex = cell.index }
                            Ui.IconButton { implicitWidth: 24; implicitHeight: 24; icon: "close"; tooltip: qsTr("Remove"); onClicked: root.removeCard(cell.cardId) }
                        }
                    }

                    // eight grips: four edges and four corners, resizing from the opposite side
                    Repeater {
                        model: root.editing ? [{ sx: -1, sy: -1 }, { sx: 0, sy: -1 }, { sx: 1, sy: -1 }, { sx: 1, sy: 0 }, { sx: 1, sy: 1 }, { sx: 0, sy: 1 }, { sx: -1, sy: 1 }, { sx: -1, sy: 0 }] : []
                        delegate: Grip {
                            required property var modelData
                            card: cell
                            area: board
                            sx: modelData.sx
                            sy: modelData.sy
                            // the card's edges follow the pointer exactly; the grid slot (the ghost) snaps
                            onStarted: (px, py) => {
                                cell.fx = cell.x; cell.fy = cell.y; cell.fw = cell.width; cell.fh = cell.height;
                                cell.p0 = Qt.point(px, py);
                                cell.r0 = { col: cell.col, row: cell.row, w: cell.w, h: cell.h, x: cell.x, y: cell.y, pw: cell.width, ph: cell.height };
                                cell.resizing = true;
                                root.activeIndex = cell.index; root.updateGhost();
                            }
                            onMoved: (px, py) => {
                                const dx = px - cell.p0.x, dy = py - cell.p0.y, r = cell.r0, d = cell.def;
                                const minW = d.minW * root.cellW - root.gap, minH = d.minH * root.cellH - root.gap;
                                if (modelData.sx > 0) { cell.fx = r.x; cell.fw = Math.max(minW, Math.min(board.width - r.x, r.pw + dx)); }
                                else if (modelData.sx < 0) { const right = r.x + r.pw; cell.fx = Math.max(0, Math.min(right - minW, r.x + dx)); cell.fw = right - cell.fx; }
                                if (modelData.sy > 0) { cell.fy = r.y; cell.fh = Math.max(minH, r.ph + dy); }
                                else if (modelData.sy < 0) { const bottom = r.y + r.ph; cell.fy = Math.max(0, Math.min(bottom - minH, r.y + dy)); cell.fh = bottom - cell.fy; }
                                root.resizeEdges(cell.index, modelData.sx, modelData.sy, r, Math.round(dx / root.cellW), Math.round(dy / root.cellH));
                            }
                            onEnded: { cell.resizing = false; root.activeIndex = -1; }
                        }
                    }
                }
            }
        }
    }

    // ── arranging: a floating bar, so the cards keep their size and place ──
    Rectangle {
        id: bar
        visible: opacity > 0 && root.showBar
        opacity: root.editing ? 1 : 0
        z: 66
        // drag it by its header ("Arranging") out of the way; a double click puts it back
        property var moved: null
        x: bar.moved ? Math.max(8, Math.min(root.width - bar.width - 8, bar.moved.x)) : (root.width - bar.width) / 2
        y: bar.moved ? Math.max(8, Math.min(root.height - bar.height - 8, bar.moved.y)) : root.height - bar.height - 18
        width: Math.min(parent.width - 32, barRow.implicitWidth + 28)
        height: barRow.implicitHeight + 16
        radius: height / 2
        color: Ui.Appearance.surfaceContainerHighest
        border.width: 1
        border.color: Qt.alpha(Ui.Appearance.onSurface, 0.14)
        transform: Translate { y: root.editing ? 0 : 14; Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Rectangle { z: -1; anchors { fill: parent; margins: -4; topMargin: -1; bottomMargin: -7 } radius: height / 2; color: "black"; opacity: 0.25 }
        MouseArea {
            // the header strip: the grip, the icon and the title
            x: barRow.x - 8; y: 0
            width: barHeader.width + 16; height: bar.height
            preventStealing: true
            z: 5
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start
            property point origin
            onPressed: m => { start = mapToItem(root, m.x, m.y); origin = Qt.point(bar.x, bar.y); }
            onPositionChanged: m => {
                if (!pressed) return;
                const p = mapToItem(root, m.x, m.y);
                bar.moved = Qt.point(origin.x + p.x - start.x, origin.y + p.y - start.y);
            }
            onDoubleClicked: bar.moved = null
        }

        Row {
            id: barRow
            anchors.centerIn: parent
            spacing: 10
            Row {
                id: barHeader
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: "drag_indicator"; size: 18; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.7) }
                Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: "dashboard_customize"; size: 18; color: root.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Arranging")
                    font.family: Ui.Appearance.font.family; font.pixelSize: 14; font.weight: Font.DemiBold; color: Ui.Appearance.onSurface
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.width > 1180
                    text: qsTr("grab a card to move · pull an edge or corner to resize")
                    font.family: Ui.Appearance.font.family; font.pixelSize: 13; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.7)
                }
            }
            // the gallery of widgets to drag onto the board
            Ui.Chip {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("+ Widgets")
                interactive: true
                filled: root.galleryOpen
                accent: root.accent
                onClicked: root.galleryOpen = !root.galleryOpen
            }
            Ui.Chip { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Border"); interactive: true; filled: !root.snap; accent: root.accent; onClicked: root.styleRequested("border") }
            Ui.Chip { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Snap grid"); interactive: true; filled: root.snap; accent: root.accent; onClicked: root.styleRequested("snap") }
            Ui.Chip { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Reset"); interactive: true; accent: "#d8a54a"; onClicked: root.resetLayout() }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: doneRow.implicitWidth + 24; implicitHeight: 30; radius: 15
                color: doneHov.hovered ? Qt.lighter(root.accent, 1.1) : root.accent
                HoverHandler { id: doneHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.doneRequested() }
                Row {
                    id: doneRow
                    anchors.centerIn: parent
                    spacing: 6
                    Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: "check"; size: 16; color: Ui.Appearance.textOnPrimary }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Done"); font.family: Ui.Appearance.font.family; font.pixelSize: 14; font.weight: Font.DemiBold; color: Ui.Appearance.textOnPrimary }
                }
            }
        }
    }

    // ── the widget gallery: drag a tile onto the board ─────────────────
    Rectangle {
        id: galleryPanel
        z: 65
        visible: opacity > 0 && root.editing
        opacity: root.galleryOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        width: 290
        height: Math.min(root.height - 104, galleryHead.height + galleryList.contentHeight + 22)
        x: root.galleryMoved ? Math.max(8, Math.min(root.width - width - 8, root.galleryMoved.x)) : root.width - width - 18
        y: root.galleryMoved ? Math.max(8, Math.min(root.height - height - 8, root.galleryMoved.y)) : 18
        radius: Ui.Appearance.rounding.large
        color: Ui.Appearance.surfaceContainerHighest
        border.width: 1
        border.color: Qt.alpha(Ui.Appearance.onSurface, 0.14)
        Rectangle { z: -1; anchors { fill: parent; margins: -4; topMargin: -1; bottomMargin: -8 } radius: parent.radius + 4; color: "black"; opacity: 0.25 }

        // header: drag the popup by it, double click to put it back
        Item {
            id: galleryHead
            x: 0; y: 0; width: parent.width; height: 46
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point start
                property point origin
                onPressed: m => { start = mapToItem(root, m.x, m.y); origin = Qt.point(galleryPanel.x, galleryPanel.y); }
                onPositionChanged: m => { if (!pressed) return; const p = mapToItem(root, m.x, m.y); root.galleryMoved = Qt.point(origin.x + p.x - start.x, origin.y + p.y - start.y); }
                onDoubleClicked: root.galleryMoved = null
            }
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: "drag_indicator"; size: 18; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.7) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Widgets"); font.family: Ui.Appearance.font.family; font.pixelSize: 15; font.weight: Font.DemiBold; color: Ui.Appearance.onSurface }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("drag onto the board"); font.family: Ui.Appearance.font.family; font.pixelSize: 12; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.7) }
            }
            Ui.IconButton { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } implicitWidth: 28; implicitHeight: 28; icon: "close"; onClicked: root.galleryOpen = false }
        }

        ListView {
            id: galleryList
            anchors { left: parent.left; right: parent.right; top: galleryHead.bottom; bottom: parent.bottom; margins: 10; topMargin: 0 }
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.defs
            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property bool onBoard: root.isShown(tile.modelData.id)
                width: galleryList.width
                height: 64
                radius: 12
                color: tileMouse.containsMouse && !tile.onBoard ? Qt.alpha(root.accent, 0.14) : Ui.Appearance.surfaceContainerHigh
                opacity: tile.onBoard ? 0.5 : 1
                Behavior on color { ColorAnimation { duration: 100 } }
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
                    spacing: 12
                    Rectangle {
                        implicitWidth: 40; implicitHeight: 40; radius: 10
                        color: Qt.alpha(root.accent, 0.16)
                        Ui.Icon { anchors.centerIn: parent; text: tile.modelData.icon; size: 22; color: root.accent }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: tile.modelData.title; font.family: Ui.Appearance.font.family; font.pixelSize: 14; font.weight: Font.DemiBold; color: Ui.Appearance.onSurface; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: tile.onBoard ? qsTr("on the board") : qsTr("%1 × %2 cells").arg(tile.modelData.w).arg(tile.modelData.h); font.family: Ui.Appearance.font.mono; font.pixelSize: 11; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.7) }
                    }
                    Ui.Icon { visible: !tile.onBoard; text: "drag_pan"; size: 20; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.6) }
                }
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    enabled: !tile.onBoard
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property bool dragging: false
                    property point start
                    onPressed: m => { dragging = false; start = mapToItem(root, m.x, m.y); }
                    onPositionChanged: m => {
                        if (!pressed) return;
                        const p = mapToItem(root, m.x, m.y);
                        if (!dragging && Math.hypot(p.x - start.x, p.y - start.y) > 6) { dragging = true; root.dragKind = tile.modelData; }
                        if (dragging) { root.dragX = p.x; root.dragY = p.y; }
                    }
                    onReleased: {
                        if (dragging) {
                            if (root.dropOver) root.addCardAt(tile.modelData.id, root.dropCell.x, root.dropCell.y);
                            root.dragKind = null; dragging = false;
                        } else {
                            root.addCard(tile.modelData.id);          // a plain click: at the bottom
                        }
                    }
                    onCanceled: { root.dragKind = null; dragging = false; }
                }
            }
        }
    }

    // the dragged widget, following the pointer
    Rectangle {
        z: 95
        visible: root.dragKind !== null
        readonly property var d: root.dragKind
        width: d ? Math.min(d.w * root.cellW - root.gap, 360) : 0
        height: d ? Math.min(d.h * root.cellH - root.gap, 220) : 0
        x: root.dragX - width / 2
        y: root.dragY - 24
        radius: root.radius
        color: Qt.alpha(Ui.Appearance.surfaceContainer, 0.92)
        border.width: 2
        border.color: root.accent
        scale: 1.03
        Rectangle { z: -1; anchors { fill: parent; margins: -3; topMargin: 3; bottomMargin: -9 } radius: parent.radius + 3; color: "black"; opacity: 0.3 }
        Row {
            anchors { left: parent.left; top: parent.top; margins: 14 }
            spacing: 8
            Ui.Icon { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.d ? parent.parent.d.icon : ""; size: 18; color: root.accent }
            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.d ? parent.parent.d.title : ""; font.family: Ui.Appearance.font.family; font.pixelSize: 15; font.weight: Font.DemiBold; color: Ui.Appearance.onSurface }
        }
    }

    // ── swapping a card for another kind ───────────────────────────────
    Item {
        anchors.fill: parent
        visible: root.swapIndex >= 0
        z: 70
        Rectangle { anchors.fill: parent; color: Qt.alpha("black", 0.4); TapHandler { onTapped: root.swapIndex = -1 } }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(380, parent.width - 48)
            height: swapCol.implicitHeight + 24
            radius: Ui.Appearance.rounding.large
            color: Ui.Appearance.background
            border.width: 1
            border.color: Qt.alpha(Ui.Appearance.onSurface, 0.14)
            TapHandler {}
            ColumnLayout {
                id: swapCol
                anchors { fill: parent; margins: 12 }
                spacing: 2
                Text { Layout.margins: 6; text: qsTr("Put in this place"); font.family: Ui.Appearance.font.family; font.pixelSize: 15; font.weight: Font.DemiBold; color: Ui.Appearance.onSurface }
                Repeater {
                    model: root.defs
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: root.swapIndex >= 0 && root.swapIndex < lm.count && lm.get(root.swapIndex).cardId === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 8
                        color: current ? Qt.alpha(root.accent, 0.16) : sHov.hovered ? Qt.alpha(Ui.Appearance.onSurface, 0.06) : "transparent"
                        HoverHandler { id: sHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.replaceCard(root.swapIndex, modelData.id); root.swapIndex = -1; } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 10
                            Ui.Icon { text: modelData.icon; size: 18; color: current ? root.accent : Ui.Appearance.onSurfaceVariant }
                            Text { Layout.fillWidth: true; text: modelData.title; font.family: Ui.Appearance.font.family; font.pixelSize: 14; color: Ui.Appearance.onSurface }
                            Text { text: current ? qsTr("here") : root.isShown(modelData.id) ? qsTr("trades places") : ""; font.family: Ui.Appearance.font.mono; font.pixelSize: 11; color: Qt.alpha(Ui.Appearance.onSurfaceVariant, 0.6) }
                        }
                    }
                }
            }
        }
    }

    /// One piece of a card's border while arranging.
    ///  border style: the four straight edges and four rounded corners of the real border, inside the card; the piece
    ///                under the pointer thickens and shows its arrow.
    ///  snap style:   invisible strips on the edges (the cursor changes) and a dot on each corner that grows on hover.
    component Grip: Item {
        id: g
        required property var card
        required property Item area
        required property int sx        // -1 left · 0 · +1 right
        required property int sy        // -1 top  · 0 · +1 bottom
        signal started(real px, real py)
        signal moved(real px, real py)
        signal ended()

        readonly property bool corner: g.sx !== 0 && g.sy !== 0
        readonly property bool on: gm.containsMouse || gm.pressed
        readonly property real r: root.radius
        readonly property real thick: g.on ? 4 : 0
        readonly property string glyph: g.corner ? (g.sx === g.sy ? (g.sx < 0 ? "north_west" : "south_east") : (g.sx > 0 ? "north_east" : "south_west"))
            : (g.sx !== 0 ? "swap_horiz" : "swap_vert")

        visible: root.editing && width > 0 && height > 0
        z: g.on ? 40 : 25
        // border style: inside the card, on the border · snap style: straddling it
        readonly property real hit: root.snap ? 14 : 10
        // snap style: the grips sit on the dashed slot line, a few pixels outside the card
        readonly property real off: 6
        x: g.sx === 0 ? g.r : (root.snap ? (g.sx < 0 ? -g.off : g.card.width + g.off) - width / 2 : (g.sx < 0 ? 0 : g.card.width - width))
        y: g.sy === 0 ? g.r : (root.snap ? (g.sy < 0 ? -g.off : g.card.height + g.off) - height / 2 : (g.sy < 0 ? 0 : g.card.height - height))
        width: g.corner ? (root.snap ? 24 : g.r) : (g.sx !== 0 ? g.hit : Math.max(0, g.card.width - 2 * g.r))
        height: g.corner ? (root.snap ? 24 : g.r) : (g.sy !== 0 ? g.hit : Math.max(0, g.card.height - 2 * g.r))

        // ── border style ──
        Rectangle {
            visible: !root.snap && !g.corner
            x: g.sx > 0 ? parent.width - width : 0
            y: g.sy > 0 ? parent.height - height : 0
            width: g.sx !== 0 ? g.thick : parent.width
            height: g.sy !== 0 ? g.thick : parent.height
            radius: 2.5
            color: root.accent
            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on height { NumberAnimation { duration: 100 } }
        }
        Item {
            visible: !root.snap && g.corner
            anchors.fill: parent
            clip: true
            Rectangle {
                x: g.sx < 0 ? 0 : -g.r
                y: g.sy < 0 ? 0 : -g.r
                width: g.r * 2; height: g.r * 2
                radius: g.r
                color: "transparent"
                border.width: g.thick
                border.color: root.accent
                Behavior on border.width { NumberAnimation { duration: 100 } }
            }
        }
        Rectangle {
            visible: !root.snap && g.on
            width: 22; height: 22; radius: 11
            color: root.accent
            x: g.sx !== 0 ? (g.sx < 0 ? 7 : parent.width - width - 7) : (parent.width - width) / 2
            y: g.sy !== 0 ? (g.sy < 0 ? 7 : parent.height - height - 7) : (parent.height - height) / 2
            Ui.Icon { anchors.centerIn: parent; text: g.glyph; size: 14; color: Ui.Appearance.textOnPrimary }
        }

        // ── snap style ──
        Rectangle {
            visible: root.snap && g.corner
            anchors.centerIn: parent
            readonly property real d: g.on ? 24 : 20
            width: d; height: d; radius: d / 2
            color: root.accent
            // the two main corners show while the card is reached for or held; the others appear under the pointer
            opacity: g.on || ((g.card.hovered || g.card.held) && g.sx === g.sy) ? 1 : 0
            Behavior on width { NumberAnimation { duration: 110 } }
            Behavior on height { NumberAnimation { duration: 110 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Ui.Icon { anchors.centerIn: parent; visible: g.on; text: g.glyph; size: 13; color: Ui.Appearance.textOnPrimary }
        }
        Rectangle {
            visible: root.snap && !g.corner
            anchors.centerIn: parent
            width: g.sx !== 0 ? 4 : 34
            height: g.sx !== 0 ? 34 : 4
            radius: 2
            color: root.accent
            opacity: g.on ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            id: gm
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: g.corner ? (g.sx === g.sy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor) : (g.sx !== 0 ? Qt.SizeHorCursor : Qt.SizeVerCursor)
            onPressed: m => { const p = mapToItem(g.area, m.x, m.y); g.started(p.x, p.y); }
            onPositionChanged: m => { if (!pressed) return; const p = mapToItem(g.area, m.x, m.y); g.moved(p.x, p.y); }
            onReleased: g.ended()
            onCanceled: g.ended()
        }
    }
}
