import QtQuick

Item {
    id: root
    property string title
    property string value
    property var theme
    property url iconSource
    property bool iconOnly: false
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
        visible: !root.iconOnly
        anchors.left: parent.left
        anchors.leftMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: root.theme.text
        font.pixelSize: root.theme.bodySize
        elide: Text.ElideRight
    }
    Image {
        visible: root.iconSource.toString() !== ""
        anchors.centerIn: parent
        width: root.theme.iconSize
        height: root.theme.iconSize
        source: root.iconSource
        sourceSize: Qt.size(root.theme.iconSize, root.theme.iconSize)
        opacity: root.selected ? 1 : 0.72
        fillMode: Image.PreserveAspectFit
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.theme.muted
        font.pixelSize: root.theme.bodySize
        visible: !root.iconOnly
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
