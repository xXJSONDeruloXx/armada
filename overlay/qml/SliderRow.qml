import QtQuick
import QtQuick.Controls

Item {
    id: root
    property string title
    property string description: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string valueText: Math.round(value) + ""
    property var theme
    property bool selected: false
    signal activated
    signal focused
    signal valueEdited(real value)
    onActivated: activate()

    width: parent ? parent.width : 0
    height: theme.rowHeight + (description ? 16 : 0)

    function adjust(direction) {
        var next = Math.max(root.from, Math.min(root.to, root.value + direction * root.stepSize));
        slider.value = next;
        root.valueEdited(next);
    }
    function activate() { slider.forceActiveFocus(); }

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
        anchors.right: slider.left
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: root.title; color: root.theme.text; font.pixelSize: root.theme.bodySize; elide: Text.ElideRight; width: parent.width }
        Text { visible: root.description !== ""; text: root.description; color: root.theme.muted; font.pixelSize: root.theme.bodySize - 3; elide: Text.ElideRight; width: parent.width }
    }
    Slider {
        id: slider
        anchors.right: valueLabel.left
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(260, Math.max(170, parent.width * 0.38))
        from: root.from
        to: root.to
        stepSize: root.stepSize
        value: root.value
        enabled: root.enabled
        onMoved: root.valueEdited(value)
    }
    Text {
        id: valueLabel
        anchors.right: parent.right
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        text: root.valueText
        color: root.theme.text
        font.pixelSize: root.theme.bodySize
        horizontalAlignment: Text.AlignRight
    }
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(0, parent.width - slider.width - valueLabel.width - root.theme.spacing * 3)
        onClicked: { root.focused(); root.activated(); }
    }
}
