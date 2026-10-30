import QtQuick
import QtQuick.Layouts
import "." as App

// A group of settings as a card. Bare columns of rows read as one long list;
// the card edge is what lets you find the group before the row.
ColumnLayout {
    id: root
    property string title: ""
    property string footer: ""
    property int visibleRows: 0
    default property alias rows: holder.data

    Layout.fillWidth: true
    spacing: 0
    // A filter that leaves empty cards standing has not filtered anything.
    visible: root.visibleRows > 0

    property var watched: []

    function recount() {
        let n = 0;
        for (let i = 0; i < holder.children.length; i++)
            if (holder.children[i].wanted === true) n++;
        root.visibleRows = n;
    }
    // One keystroke changes every row, and that is one recount.
    function bump() { Qt.callLater(root.recount); }
    function rewatch() {
        const now = [];
        for (let i = 0; i < holder.children.length; i++) {
            const c = holder.children[i];
            now.push(c);
            // Counted from `wanted`, never `visible`: once the card hides,
            // every row reports invisible and the count could never recover.
            if (root.watched.indexOf(c) < 0 && c.wantedChanged)
                c.wantedChanged.connect(root.bump);
        }
        root.watched = now;
        root.bump();
    }
    Component.onCompleted: root.rewatch()

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.bottomMargin: 6
        visible: root.title.length > 0
        text: root.title
        font.family: App.Appearance.font.family
        font.pixelSize: App.Appearance.font.smallest
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        color: App.Appearance.onSurfaceVariant
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: holder.implicitHeight + 12
        radius: App.Appearance.rounding.normal
        color: App.Appearance.surfaceContainer

        ColumnLayout {
            id: holder
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
            spacing: 0
            onChildrenChanged: root.rewatch()
        }
    }

    // Outside the card: a sentence about the group is not a row you can press.
    Text {
        visible: root.footer.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.topMargin: 6
        text: root.footer
        font.family: App.Appearance.font.family
        font.pixelSize: App.Appearance.font.smaller
        color: App.Appearance.onSurfaceVariant
        wrapMode: Text.WordWrap
    }
}
