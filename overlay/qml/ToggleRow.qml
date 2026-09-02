import QtQuick
import QtQuick.Controls

Item {
    id: root
    property string title
    property string description: ""
    property bool checked: false
    property var theme
    property bool selected: false
    signal activated
    signal focused
    signal toggled(bool checked)
    onActivated: toggle()

    width: parent ? parent.width : 0
    height: theme.rowHeight + (description ? 16 : 0)

    function toggle() {
        toggleControl.checked = !toggleControl.checked;
        root.toggled(toggleControl.checked);
    }

    Rectangle {
        anchors.fill: parent
        radius: root.theme.radius
        color: root.selected ? root.theme.rowFocused : root.theme.row
        border.color: root.selected ? root.theme.accent : root.theme.transparent
        border.width: root.selected ? root.theme.borderWidth : 0
    }
    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.theme.spacing
        anchors.right: toggleControl.left
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: root.title; color: root.theme.text; font.pixelSize: root.theme.bodySize; elide: Text.ElideRight; width: parent.width }
        Text { visible: root.description !== ""; text: root.description; color: root.theme.muted; font.pixelSize: root.theme.bodySize - 3; elide: Text.ElideRight; width: parent.width }
    }
    Switch {
        id: toggleControl
        anchors.right: parent.right
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        enabled: root.enabled
        onClicked: root.toggled(checked)
    }
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(0, parent.width - toggleControl.width - root.theme.spacing * 2)
        onClicked: { root.focused(); root.activated(); }
    }
}
