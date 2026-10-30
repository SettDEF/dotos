.pragma library
// Moving through a list by keyboard, the same on every page: j/k or ↓/↑ one step, g/G or
// Home/End to the ends, PageDown/PageUp ten. move() gives the new index, or -1 when the key is
// not a move (the page then tries its own letters, then the window its shortcuts).

function plain(e) {
    return !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
}

function move(e, n, i) {
    if (n <= 0 || !plain(e)) return -1;
    const shift = e.modifiers & Qt.ShiftModifier;
    switch (e.key) {
        case Qt.Key_J: case Qt.Key_Down: return Math.min(n - 1, i < 0 ? 0 : i + 1);
        case Qt.Key_K: case Qt.Key_Up: return Math.max(0, i < 0 ? 0 : i - 1);
        case Qt.Key_Home: return 0;
        case Qt.Key_End: return n - 1;
        case Qt.Key_G: return shift ? n - 1 : -1;
        case Qt.Key_PageDown: return Math.min(n - 1, Math.max(0, i) + 10);
        case Qt.Key_PageUp: return Math.max(0, i - 10);
    }
    return -1;
}

function isOpen(e) {
    return plain(e) && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_O);
}

// h/l or ←/→: -1 / +1 (days, tabs, filters); 0 when the key is neither
function side(e) {
    if (!plain(e)) return 0;
    if (e.key === Qt.Key_H || e.key === Qt.Key_Left) return -1;
    if (e.key === Qt.Key_L || e.key === Qt.Key_Right) return 1;
    return 0;
}

// the next key of a list of keys (filters, tabs), wrapping
function cycle(keys, cur, d) {
    const i = keys.indexOf(cur);
    return keys[(Math.max(0, i) + d + keys.length) % keys.length];
}
