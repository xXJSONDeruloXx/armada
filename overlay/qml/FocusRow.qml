import QtQuick

Item {
    id: root
    property string title
    property string value
    property var theme
    property bool selected: activeFocus
    signal activated
    signal adjusted(int direction)
    width: parent ? parent.width : 0
    height: theme.rowHeight
    focus: true
    activeFocusOnTab: true

    Rectangle {
        anchors.fill: parent
        radius: root.theme.radius
        color: root.selected ? root.theme.rowFocused : root.theme.row
        border.color: root.selected ? root.theme.accent : root.theme.transparent
        border.width: root.selected ? root.theme.borderWidth : 0
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: root.theme.text
        elide: Text.ElideRight
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.theme.muted
        elide: Text.ElideLeft
    }
    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.forceActiveFocus();
            root.activated();
        }
    }
}
