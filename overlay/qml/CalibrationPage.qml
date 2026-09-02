import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var armada
    property var theme
    property var controllerState: ({})
    property var capture: ({})
    property string sessionToken: "armada-overlay-calibration"
    property string statusText: ""
    property bool sessionActive: false
    property bool recording: false
    property bool resetPending: false
    property int focusIndex: 0
    property var rows: []

    readonly property var captureNames: ["left_x", "left_y", "right_x", "right_y", "left_trigger", "right_trigger"]

    function control(name) { return (controllerState.controls || {})[name] || {}; }
    function number(value, fallback) {
        var result = Number(value);
        return Number.isFinite(result) ? result : fallback;
    }
    function value(name) { return number(control(name).value, 0); }
    function normalized(name) {
        var item = control(name);
        var minimum = number(item.min, -32768);
        var maximum = number(item.max, 32767);
        var current = value(name);
        var side = current < 0 ? Math.abs(minimum) : maximum;
        return side ? Math.max(-1, Math.min(1, current / side)) : 0;
    }
    function progress(name) {
        var item = control(name);
        var minimum = number(item.min, 0);
        var maximum = number(item.max, 1);
        return maximum === minimum ? 0 : Math.max(0, Math.min(1, (value(name) - minimum) / (maximum - minimum)));
    }
    function clone(valueToCopy) { return JSON.parse(JSON.stringify(valueToCopy)); }
    function requestSucceeded(reply) { return reply.ok && (!reply.result || reply.result.ok !== false); }
    function refreshState() {
        var reply = armada.call("get_controller_state");
        if (reply.ok) {
            controllerState = reply.result || {};
            if (recording) capture = updateCapture(capture);
        } else {
            statusText = reply.error;
        }
    }
    function beginSession() {
        var reply = armada.call("begin_calibration_session", {token: sessionToken});
        sessionActive = requestSucceeded(reply);
        if (!sessionActive) statusText = reply.error || "Calibration session unavailable";
        refreshState();
    }
    function endSession() {
        if (!sessionActive) return;
        armada.call("end_calibration_session", {token: sessionToken});
        sessionActive = false;
    }
    function makeCapture() {
        var next = {};
        captureNames.forEach(function(name) {
            var current = value(name);
            var item = control(name);
            next[name] = {
                center: current,
                min: current,
                max: current,
                range: number(item.max, 0) - number(item.min, 0)
            };
        });
        return next;
    }
    function updateCapture(previous) {
        var next = clone(previous || makeCapture());
        Object.keys(next).forEach(function(name) {
            var current = value(name);
            next[name].min = Math.min(number(next[name].min, current), current);
            next[name].max = Math.max(number(next[name].max, current), current);
        });
        return next;
    }
    function startCapture() {
        capture = makeCapture();
        recording = true;
        resetPending = false;
        statusText = "Move both sticks in full circles and fully press both triggers";
    }
    function saveCapture() {
        if (!recording || !Object.keys(capture).length) return;
        var reply = armada.call("save_calibration", {capture: capture});
        if (reply.ok) {
            recording = false;
            capture = {};
            controllerState = reply.result || controllerState;
            statusText = "Calibration saved";
        } else {
            statusText = reply.error;
        }
    }
    function resetDefaults() {
        if (!resetPending) {
            resetPending = true;
            statusText = "Press A again to reset calibration";
            return;
        }
        var reply = armada.call("reset_calibration");
        resetPending = false;
        if (reply.ok) {
            controllerState = reply.result || controllerState;
            statusText = "Calibration reset";
        } else {
            statusText = reply.error;
        }
    }
    function handleAction(action) {
        var row = rows[focusIndex];
        if (action !== "accept" || row !== resetRow) resetPending = false;
        if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
        else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
        else if (action === "accept") {
            if (row === captureRow) recording ? saveCapture() : startCapture();
            else if (row === resetRow) resetDefaults();
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }

    Component.onCompleted: {
        rows = [captureRow, resetRow];
        beginSession();
        poll.start();
    }
    Component.onDestruction: {
        poll.stop();
        endSession();
    }

    Timer {
        id: poll
        interval: 100
        repeat: true
        onTriggered: root.refreshState()
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        Column {
            width: root.width
            spacing: theme.spacing
            Text { text: "Calibration"; color: theme.text; font.pixelSize: theme.pageTitleSize }
            Text {
                text: !controllerState.supported ? (controllerState.reason || "Controller unavailable")
                    : recording ? "Recording live range…" : "Live controller response"
                color: theme.muted
                font.pixelSize: theme.bodySize
                wrapMode: Text.WordWrap
                width: parent.width
            }
            Row {
                width: parent.width
                spacing: theme.spacing
                Item {
                    width: (parent.width - parent.spacing) / 2
                    height: 150
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Left stick"; color: theme.text; font.pixelSize: theme.bodySize }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(132, parent.width)
                        height: width
                        color: theme.row
                        border.color: theme.panelRaised
                        border.width: theme.borderWidth
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: theme.panelRaised }
                        Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: 1; color: theme.panelRaised }
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            x: parent.width / 2 + root.normalized("left_x") * parent.width * 0.44 - width / 2
                            y: parent.height / 2 + root.normalized("left_y") * parent.height * 0.44 - height / 2
                            color: theme.accent
                            border.color: theme.text
                            border.width: 2
                        }
                    }
                }
                Item {
                    width: (parent.width - parent.spacing) / 2
                    height: 150
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Right stick"; color: theme.text; font.pixelSize: theme.bodySize }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(132, parent.width)
                        height: width
                        color: theme.row
                        border.color: theme.panelRaised
                        border.width: theme.borderWidth
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: theme.panelRaised }
                        Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: 1; color: theme.panelRaised }
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            x: parent.width / 2 + root.normalized("right_x") * parent.width * 0.44 - width / 2
                            y: parent.height / 2 + root.normalized("right_y") * parent.height * 0.44 - height / 2
                            color: theme.accent
                            border.color: theme.text
                            border.width: 2
                        }
                    }
                }
            }
            Row {
                width: parent.width
                spacing: theme.spacing
                Repeater {
                    model: [{label: "LT", name: "left_trigger"}, {label: "RT", name: "right_trigger"}]
                    delegate: Column {
                        width: (root.width - root.theme.spacing) / 2
                        spacing: 4
                        Text { text: modelData.label; color: theme.text; font.pixelSize: theme.bodySize }
                        Rectangle {
                            width: parent.width
                            height: 12
                            color: theme.row
                            border.color: theme.panelRaised
                            border.width: theme.borderWidth
                            Rectangle { width: parent.width * root.progress(modelData.name); height: parent.height; color: theme.accent }
                        }
                    }
                }
            }
            FocusRow {
                id: captureRow
                width: parent.width
                title: recording ? "Save calibration" : "Start calibration"
                value: recording ? "A" : "A"
                theme: root.theme
                onActivated: recording ? root.saveCapture() : root.startCapture()
            }
            FocusRow { id: resetRow; width: parent.width; title: "Reset to defaults"; value: "A"; theme: root.theme; onActivated: root.resetDefaults() }
            Text { text: root.statusText; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
        }
    }
}
