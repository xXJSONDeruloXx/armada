import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: root
    visible: false
    color: theme.transparent
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    title: "Armada Control"

    Theme { id: theme }
    property var uiTheme: theme
    property int pageIndex: 0
    property var pageTitles: ["Status", "Power", "Fans", "Games", "Settings", "Calibration"]
    property var pageComponents: [statusPage, powerPage, placeholderPage, placeholderPage, placeholderPage, placeholderPage]

    function showPage(index) {
        pageIndex = index;
        navigation.currentIndex = index;
        stack.replace(pageComponents[index]);
    }

    function movePage(direction) {
        showPage(Math.max(0, Math.min(pageTitles.length - 1, navigation.currentIndex + direction)));
    }

    function handleInput(action) {
        if (action === "guide")
            return;
        if (action === "back") {
            if (pageIndex !== 0)
                showPage(0);
            else
                armada.hideOverlay();
            return;
        }
        if (action === "previous") {
            movePage(-1);
            return;
        }
        if (action === "next") {
            movePage(1);
            return;
        }
        if (stack.currentItem && stack.currentItem.handleAction)
            stack.currentItem.handleAction(action);
    }

    Connections {
        target: armada
        function onInputAction(action) { root.handleInput(action); }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(760, parent.width - 96)
            height: Math.min(680, parent.height - 72)
            color: theme.panel
            border.color: theme.panelRaised
            border.width: theme.borderWidth
            radius: theme.radius

            Row {
                anchors.fill: parent
                anchors.margins: theme.spacing
                spacing: theme.spacing

                ListView {
                    id: navigation
                    width: 112
                    height: parent.height
                    model: root.pageTitles
                    currentIndex: root.pageIndex
                    spacing: 4
                    delegate: FocusRow {
                        width: navigation.width
                        title: modelData
                        value: ""
                        theme: root.uiTheme
                        selected: ListView.isCurrentItem
                        onActivated: root.showPage(index)
                    }
                }

                StackView {
                    id: stack
                    width: parent.width - navigation.width - parent.spacing
                    height: parent.height
                    initialItem: statusPage
                    replaceEnter: Transition { PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: theme.replaceEnterMs } }
                    replaceExit: Transition { PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: theme.replaceExitMs } }
                }
            }
        }
    }

    Component {
        id: statusPage
        Item {
            property var controller: armada
            property var theme: root.uiTheme
            function handleAction(action) {
                if (action === "up") root.movePage(-1);
                else if (action === "down") root.movePage(1);
                else if (action === "accept") root.showPage(navigation.currentIndex);
            }
            Column {
                anchors.fill: parent
                spacing: theme.spacing
                Text { text: "Armada Control"; color: theme.text; font.pixelSize: theme.pageTitleSize }
                Text { text: "API v1 · " + ((armada.config.cpuDeviceClass || "device unavailable")); color: theme.muted }
                Text { text: "Choose a page with D-pad and press A to open."; color: theme.muted; wrapMode: Text.WordWrap; width: parent.width }
                Item { width: 1; height: 1 }
                FocusRow {
                    id: openPower
                    width: parent.width
                    title: "Power and fan controls"
                    value: "Open"
                    theme: root.uiTheme
                    onActivated: root.showPage(1)
                }
                FocusRow {
                    width: parent.width
                    title: "Refresh device state"
                    value: "A"
                    theme: root.uiTheme
                    onActivated: armada.refresh()
                }
            }
        }
    }

    Component {
        id: powerPage
        Item {
            id: power
            property var controller: armada
            property var theme: root.uiTheme
            property var draft: ({})
            property int focusIndex: 0
            property var rows: []

            function profiles() {
                return Object.keys((draft.power || {}).profiles || {});
            }
            function curves() {
                return Object.keys((draft.power || {}).fan_curves || {});
            }
            function underclocks() {
                return Object.keys((((draft.power || {}).underclocks || {})[draft.cpuDeviceClass] || {}));
            }
            function currentProfile() {
                return ((draft.power || {}).profiles || {})[profileRow.value] || {};
            }
            function setProfileField(key, value) {
                var next = JSON.parse(JSON.stringify(draft));
                next.power.profiles[profileRow.value][key] = value;
                draft = next;
            }
            function numberValue(key) {
                return Number(currentProfile()[key] || 0);
            }
            function adjustPercent(key, direction) {
                var value = Math.max(0, Math.min(1, numberValue(key) + direction * 0.05));
                setProfileField(key, value.toFixed(2));
            }
            function cycle(row, values, direction) {
                if (!values.length) return;
                var current = values.indexOf(row.value);
                row.value = values[(current + direction + values.length) % values.length];
            }
            function save() {
                var result = armada.call("save_power_config", {data: draft.power});
                if (!result.ok) status.text = result.error;
                else {
                    status.text = "Saved";
                    armada.refresh();
                }
            }
            function handleAction(action) {
                var row = rows[focusIndex];
                if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
                else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
                else if (action === "left" || action === "right") {
                    var direction = action === "right" ? 1 : -1;
                    if (row === profileRow) cycle(row, profiles(), direction);
                    else if (row === fanRow) { cycle(row, curves(), direction); setProfileField("fan_curve", row.value); }
                    else if (row === governorRow) { cycle(row, (draft.perf || {}).governors || [], direction); setProfileField("cpu_governor", row.value); }
                    else if (row === underclockRow) { cycle(row, underclocks(), direction); setProfileField("cpu_underclock", row.value); }
                    else if (row === cpuRow) adjustPercent("cpu_max", direction);
                    else if (row === gpuMinRow) adjustPercent("gpu_min", direction);
                    else if (row === gpuMaxRow) adjustPercent("gpu_max", direction);
                } else if (action === "accept" && row === saveRow) save();
                else if (action === "accept" && row === resetRow) {
                    var defaults = ((draft.powerDefaults || {}).profiles || {})[profileRow.value];
                    if (defaults) {
                        var next = JSON.parse(JSON.stringify(draft));
                        next.power.profiles[profileRow.value] = JSON.parse(JSON.stringify(defaults));
                        draft = next;
                    }
                }
                rows.forEach(function(item, index) { item.selected = index === focusIndex; });
            }
            function sync() {
                draft = JSON.parse(JSON.stringify(armada.config || {}));
                var names = profiles();
                profileRow.value = ((draft.power || {}).general || {}).default_profile || names[0] || "";
                fanRow.value = currentProfile().fan_curve || curves()[0] || "";
                governorRow.value = currentProfile().cpu_governor || "";
                underclockRow.value = currentProfile().cpu_underclock || underclocks()[0] || "";
                rows.forEach(function(item, index) { item.selected = index === focusIndex; });
            }
            Connections { target: armada; function onConfigChanged() { power.sync(); } }
            Component.onCompleted: {
                rows = [profileRow, fanRow, governorRow, underclockRow, cpuRow, gpuMinRow, gpuMaxRow, resetRow, saveRow];
                sync();
            }

            ScrollView {
                anchors.fill: parent
                clip: true
                Column {
                    width: power.width
                    spacing: theme.spacing
                    Text { id: header; text: "Power profile"; color: theme.text; font.pixelSize: theme.pageTitleSize }
                    Text { text: "Use left/right to adjust the focused row."; color: theme.muted; wrapMode: Text.WordWrap; width: parent.width }
                    FocusRow { id: profileRow; width: parent.width; title: "Profile"; value: ""; theme: power.theme }
                    FocusRow { id: fanRow; width: parent.width; title: "Fan curve"; value: ""; theme: power.theme }
                    FocusRow { id: governorRow; width: parent.width; title: "CPU governor"; value: ""; theme: power.theme }
                    FocusRow { id: underclockRow; width: parent.width; title: "CPU underclock"; value: ""; theme: power.theme }
                    FocusRow { id: cpuRow; width: parent.width; title: "CPU maximum"; value: Math.round(power.numberValue("cpu_max") * 100) + "%"; theme: power.theme }
                    FocusRow { id: gpuMinRow; width: parent.width; title: "GPU minimum"; value: Math.round(power.numberValue("gpu_min") * 100) + "%"; theme: power.theme }
                    FocusRow { id: gpuMaxRow; width: parent.width; title: "GPU maximum"; value: Math.round(power.numberValue("gpu_max") * 100) + "%"; theme: power.theme }
                    FocusRow { id: resetRow; width: parent.width; title: "Reset profile"; value: "A"; theme: power.theme }
                    FocusRow { id: saveRow; width: parent.width; title: "Save profile"; value: "A"; theme: power.theme; onActivated: power.save() }
                    Text { id: status; color: theme.muted; text: ""; width: parent.width; wrapMode: Text.WordWrap }
                    Text { text: "Temperature: " + (armada.fanState.currentTemp === undefined ? "—" : armada.fanState.currentTemp + " °C"); color: theme.muted }
                }
            }
        }
    }

    Component {
        id: placeholderPage
        Item {
            property var theme: root.uiTheme
            function handleAction(action) {
                if (action === "accept") root.showPage(0);
            }
            Column {
                anchors.fill: parent
                spacing: theme.spacing
                Text { text: "Armada Control"; color: theme.text; font.pixelSize: theme.pageTitleSize }
                Text { text: "This page is being migrated from the Decky client."; color: theme.muted; wrapMode: Text.WordWrap; width: parent.width }
                FocusRow { width: parent.width; title: "Back to overview"; value: "A"; theme: root.uiTheme; onActivated: root.showPage(0) }
            }
        }
    }
}
