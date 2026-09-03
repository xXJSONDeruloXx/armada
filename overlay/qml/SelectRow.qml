import QtQuick
import QtQuick.Controls

Item {
    id: root
    property string title
    property string description: ""
    property var options: []
    property string currentValue: ""
    property alias value: root.currentValue
    property var theme
    property var focusOwner
    property bool selected: false
    property bool popupOpen: false
    signal activated
    signal focused
    signal valueEdited(string value)
    onActivated: open()

    width: parent ? parent.width : 0
    height: theme.rowHeight + (description ? 16 : 0)

    function optionValue(item) { return item && item.data !== undefined ? String(item.data) : String(item); }
    function optionLabel(item) { return item && item.label !== undefined ? String(item.label) : optionValue(item); }
    function labels() { return options.map(optionLabel); }
    function indexForValue(value) {
        for (var index = 0; index < options.length; ++index)
            if (optionValue(options[index]) === String(value)) return index;
        return 0;
    }
    function adjust(direction) {
        if (!options.length) return;
        var next = (indexForValue(currentValue) + direction + options.length) % options.length;
        currentValue = optionValue(options[next]);
        valueEdited(currentValue);
    }
    function open() {
        if (!options.length) return;
        root.requestFocus();
        selector.forceActiveFocus();
        popupOpen = true;
        selector.popup.open();
    }
    function close() {
        selector.popup.close();
        popupOpen = false;
    }
    function handleAction(action) {
        if (!popupOpen) return false;
        if (action === "up" || action === "left") {
            adjust(-1);
            return true;
        }
        if (action === "down" || action === "right") {
            adjust(1);
            return true;
        }
        if (action === "accept" || action === "back") {
            close();
            return true;
        }
        return false;
    }
    function requestFocus() {
        if (focusOwner && focusOwner.setFocusedRow) focusOwner.setFocusedRow(root);
        else root.forceActiveFocus();
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
        anchors.right: selector.left
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            text: root.title
            color: root.theme.text
            font.pixelSize: root.theme.bodySize
            elide: Text.ElideRight
            width: parent.width
        }
        Text {
            visible: root.description !== ""
            text: root.description
            color: root.theme.muted
            font.pixelSize: root.theme.bodySize - 3
            elide: Text.ElideRight
            width: parent.width
        }
    }
    ComboBox {
        id: selector
        anchors.right: parent.right
        anchors.rightMargin: root.theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(260, Math.max(170, parent.width * 0.42))
        height: root.theme.rowHeight - 12
        enabled: root.enabled
        model: root.labels()
        currentIndex: root.indexForValue(root.currentValue)
        contentItem: Text {
            leftPadding: 10
            rightPadding: 28
            text: root.options.length ? root.optionLabel(root.options[root.indexForValue(root.currentValue)]) : root.currentValue
            color: root.theme.text
            font.pixelSize: root.theme.bodySize
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: root.theme.radius
            color: root.selected ? root.theme.panelRaised : root.theme.panel
            border.color: selector.activeFocus ? root.theme.accent : root.theme.panelRaised
            border.width: root.theme.borderWidth
        }
        onPressedChanged: if (pressed) root.requestFocus()
        onActivated: function(index) {
            root.currentValue = root.optionValue(root.options[index]);
            root.valueEdited(root.currentValue);
        }
    }
    Connections {
        target: selector.popup
        function onClosed() { root.popupOpen = false; }
    }
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(0, parent.width - selector.width - root.theme.spacing * 2)
        onClicked: { root.requestFocus(); root.focused(); root.activated(); }
    }
}
