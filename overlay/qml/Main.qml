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
    property bool navigationActive: true
    property var pageTitles: ["Status", "Power", "Fans", "Games", "Compatibility", "Settings", "Calibration"]
    property var pageIcons: ["status.svg", "power.svg", "fans.svg", "games.svg", "compatibility.svg", "settings.svg", "calibration.svg"]
    property var pageComponents: [statusPage, powerPage, fansPage, gamePage, compatibilityPage, settingsPage, calibrationPage]

    function showPage(index) {
        pageIndex = index;
        navigation.currentIndex = index;
        stack.replace(pageComponents[index]);
    }

    function focusNavigation() {
        navigationActive = true;
        navigation.forceActiveFocus();
    }

    function movePage(direction) {
        showPage(Math.max(0, Math.min(pageTitles.length - 1, navigation.currentIndex + direction)));
    }

    function handleInput(action) {
        if (action === "guide")
            return;
        if (action === "back") {
            if (!navigationActive) {
                if (stack.currentItem && stack.currentItem.handleBack && stack.currentItem.handleBack())
                    return;
                focusNavigation();
                return;
            }
            if (stack.currentItem && stack.currentItem.handleBack && stack.currentItem.handleBack())
                return;
            if (pageIndex !== 0)
                showPage(0);
            else
                armada.hideOverlay();
            return;
        }
        if (action === "previous") {
            focusNavigation();
            movePage(-1);
            return;
        }
        if (action === "next") {
            focusNavigation();
            movePage(1);
            return;
        }
        if (navigationActive) {
            if (action === "up") movePage(-1);
            else if (action === "down") movePage(1);
            else if (action === "accept") navigationActive = false;
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
            width: Math.min(880, parent.width - 40)
            height: Math.min(760, parent.height - 32)
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
                    width: theme.navWidth
                    height: parent.height
                    model: root.pageTitles
                    currentIndex: root.pageIndex
                    focus: root.navigationActive
                    spacing: 4
                    delegate: FocusRow {
                        width: navigation.width
                        title: ""
                        value: ""
                        iconSource: "icons/" + root.pageIcons[index]
                        iconOnly: true
                        theme: root.uiTheme
                        selected: ListView.isCurrentItem
                        onActivated: { root.showPage(index); root.focusNavigation(); }
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
                Text { text: "API v1 · " + ((armada.config.cpuDeviceClass || "device unavailable")); color: theme.muted; font.pixelSize: theme.bodySize }
                Text { text: "Choose a page with D-pad and press A to open."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
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
            property bool resetPending: false
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
                if (action !== "accept" || row !== resetRow) resetPending = false;
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
                    if (!resetPending) {
                        resetPending = true;
                        status.text = "Press A again to reset this profile";
                    } else {
                        var defaults = ((draft.powerDefaults || {}).profiles || {})[profileRow.value];
                        if (defaults) {
                            var next = JSON.parse(JSON.stringify(draft));
                            next.power.profiles[profileRow.value] = JSON.parse(JSON.stringify(defaults));
                            draft = next;
                            status.text = "Reset; save to apply";
                        }
                        resetPending = false;
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
                Text { text: "Use left/right to adjust the focused row."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
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
                Text { text: "This page is being migrated from the Decky client."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
                FocusRow { width: parent.width; title: "Back to overview"; value: "A"; theme: root.uiTheme; onActivated: root.showPage(0) }
            }
        }
    }

    Component {
        id: settingsPage
        SettingsPage {
            armada: armada
            theme: root.uiTheme
            onOpenCalibration: root.showPage(6)
        }
    }

    Component {
        id: compatibilityPage
        CompatibilityPage {
            armada: armada
            theme: root.uiTheme
        }
    }

    Component {
        id: gamePage
        GamePage {
            armada: armada
            theme: root.uiTheme
        }
    }

    Component {
        id: calibrationPage
        CalibrationPage {
            armada: armada
            theme: root.uiTheme
        }
    }

    Component {
        id: fansPage
        Item {
            id: fans
            property var theme: root.uiTheme
            property var draft: ({})
            property int focusIndex: 0
            property int pointIndex: 0
            property bool dirty: false
            property bool deletePending: false
            property var rows: []

            function clone(value) { return JSON.parse(JSON.stringify(value)); }
            function curveNames() { return Object.keys(draft.fanCurves || {}).sort(); }
            function currentCurve() { return (draft.fanCurves || {})[curveRow.value] || {}; }
            function parse(text) {
                if (!text) return [];
                return text.split(",").map(function(item) {
                    var values = item.trim().split(":");
                    return {temp: Number(values[0]), pwm: Number(values[1])};
                }).filter(function(point) { return Number.isFinite(point.temp) && Number.isFinite(point.pwm); })
                  .sort(function(a, b) { return a.temp - b.temp; });
            }
            function format(points) {
                return points.slice().sort(function(a, b) { return a.temp - b.temp; })
                    .map(function(point) { return Math.round(point.temp) + ":" + Math.round(point.pwm); }).join(",");
            }
            function points() { return parse(currentCurve().curve); }
            function smoothingValue() {
                if (!draft.fanSettings) return "—";
                return Math.round(Number(draft.fanSettings.smoothing) * 100) + "%";
            }
            function setCurvePoints(nextPoints) {
                var next = clone(draft);
                next.fanCurves[curveRow.value].curve = format(nextPoints);
                draft = next;
                dirty = true;
                pointIndex = Math.min(pointIndex, Math.max(0, nextPoints.length - 1));
            }
            function adjustPoint(key, delta) {
                var nextPoints = points();
                if (!nextPoints.length) return;
                var point = nextPoints[Math.min(pointIndex, nextPoints.length - 1)];
                point[key] = Math.max(key === "temp" ? 0 : 0, Math.min(key === "temp" ? 120 : 255, point[key] + delta));
                setCurvePoints(nextPoints);
            }
            function setSetting(key, value) {
                var next = clone(draft);
                next.fanSettings[key] = value;
                draft = next;
                dirty = true;
            }
            function toggleFanStop() {
                var nextPoints = points();
                if (!nextPoints.length) return;
                var enabled = nextPoints[0].pwm !== 0;
                if (enabled) {
                    var stopTemp = 60;
                    nextPoints.forEach(function(point) { if (point.temp <= stopTemp) point.pwm = 0; });
                    if (nextPoints[0].temp > stopTemp) nextPoints.unshift({temp: stopTemp, pwm: 0});
                    else nextPoints[0].pwm = 0;
                    setSetting("min_pwm", 0);
                } else {
                    nextPoints.forEach(function(point) { if (point.pwm === 0) point.pwm = 128; });
                }
                setCurvePoints(nextPoints);
            }
            function addPoint() {
                var nextPoints = points();
                if (!nextPoints.length) nextPoints.push({temp: 60, pwm: 128});
                else if (nextPoints[nextPoints.length - 1].temp >= 120) return;
                else nextPoints.push({temp: Math.min(120, nextPoints[nextPoints.length - 1].temp + 10), pwm: nextPoints[nextPoints.length - 1].pwm});
                pointIndex = nextPoints.length - 1;
                setCurvePoints(nextPoints);
            }
            function removePoint() {
                var nextPoints = points();
                if (nextPoints.length <= 1) return;
                nextPoints.splice(Math.min(pointIndex, nextPoints.length - 1), 1);
                pointIndex = Math.max(0, pointIndex - 1);
                setCurvePoints(nextPoints);
            }
            function addCurve() {
                var names = curveNames();
                var name = "custom";
                var suffix = 1;
                while (names.indexOf(name) >= 0) name = "custom_" + suffix++;
                var next = clone(draft);
                next.fanCurves[name] = {label: "Custom " + (suffix - 1), curve: "60:128,80:200"};
                draft = next;
                curveRow.value = name;
                pointIndex = 0;
                dirty = true;
            }
            function deleteCurve() {
                if ((draft.factoryFanCurves || {})[curveRow.value]) {
                    fanStatus.text = "Factory curves cannot be deleted";
                    return;
                }
                var used = Object.keys(draft.profiles || {}).some(function(name) {
                    return draft.profiles[name].fan_curve === curveRow.value;
                });
                if (used) {
                    fanStatus.text = "Curve is in use by a power profile";
                    return;
                }
                if (!deletePending) {
                    deletePending = true;
                    fanStatus.text = "Press A again to delete this curve";
                    return;
                }
                var next = clone(draft);
                var remaining = {};
                Object.keys(next.fanCurves || {}).forEach(function(name) {
                    if (name !== curveRow.value) remaining[name] = next.fanCurves[name];
                });
                next.fanCurves = remaining;
                draft = next;
                curveRow.value = curveNames()[0] || "";
                pointIndex = 0;
                dirty = true;
                deletePending = false;
                fanStatus.text = "Deleted; save to apply";
            }
            function saveChanges() {
                var result = armada.call("save_fan_curves", {fanCurves: draft.fanCurves, fanSettings: draft.fanSettings});
                if (!result.ok) fanStatus.text = result.error;
                else { dirty = false; fanStatus.text = "Saved"; armada.refresh(); }
            }
            function discardDraft() { dirty = false; sync(); }
            function sync() {
                if (dirty) return;
                draft = clone(armada.fanState || {});
                var names = curveNames();
                if (names.indexOf(curveRow.value) < 0) curveRow.value = names[0] || "";
                pointIndex = Math.min(pointIndex, Math.max(0, points().length - 1));
                rows.forEach(function(item, index) { item.selected = index === focusIndex; });
            }
            function handleAction(action) {
                var row = rows[focusIndex];
                if (action !== "accept" || row !== deleteCurveRow) deletePending = false;
                if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
                else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
                else if (action === "left" || action === "right") {
                    var direction = action === "right" ? 1 : -1;
                    if (row === curveRow) {
                        var names = curveNames();
                        var current = names.indexOf(curveRow.value);
                        if (names.length) curveRow.value = names[(current + direction + names.length) % names.length];
                    } else if (row === pointRow) {
                        pointIndex = Math.max(0, Math.min(Math.max(0, points().length - 1), pointIndex + direction));
                    } else if (row === tempRow) adjustPoint("temp", direction);
                    else if (row === pwmRow) adjustPoint("pwm", direction * 5);
                    else if (row === rampUpRow) setSetting("ramp_up", Math.max(1, Math.min(255, Number(draft.fanSettings.ramp_up || 1) + direction)));
                    else if (row === rampDownRow) setSetting("ramp_down", Math.max(1, Math.min(255, Number(draft.fanSettings.ramp_down || 1) + direction)));
                    else if (row === smoothingRow) setSetting("smoothing", Math.max(0, Math.min(0.99, Number(draft.fanSettings.smoothing || 0) + direction * 0.05)));
                    else if (row === minPwmRow) setSetting("min_pwm", Math.max(0, Math.min(255, Number(draft.fanSettings.min_pwm || 0) + direction * 5)));
                } else if (action === "accept") {
                    if (row === addCurveRow) addCurve();
                    else if (row === deleteCurveRow) deleteCurve();
                    else if (row === addPointRow) addPoint();
                    else if (row === removePointRow) removePoint();
                    else if (row === fanStopRow) toggleFanStop();
                    else if (row === saveRow) saveChanges();
                    else if (row === revertRow) discardDraft();
                }
                rows.forEach(function(item, index) { item.selected = index === focusIndex; });
            }
            Connections { target: armada; function onFanStateChanged() { fans.sync(); } }
            Component.onCompleted: {
                rows = [curveRow, pointRow, tempRow, pwmRow, addPointRow, removePointRow, fanStopRow,
                    rampUpRow, rampDownRow, smoothingRow, minPwmRow, addCurveRow, deleteCurveRow, saveRow, revertRow];
                sync();
            }

            ScrollView {
                anchors.fill: parent
                clip: true
                Column {
                    width: fans.width
                    spacing: theme.spacing
                    Text { text: "Fan curves"; color: theme.text; font.pixelSize: theme.pageTitleSize }
                    Text { text: "Select a row; left/right adjusts it, A activates actions."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
                    FocusRow { id: curveRow; width: parent.width; title: "Curve"; value: ""; theme: fans.theme }
                    FocusRow { id: pointRow; width: parent.width; title: "Point"; value: (fans.points().length ? (fans.pointIndex + 1) + " / " + fans.points().length : "—"); theme: fans.theme }
                    FocusRow { id: tempRow; width: parent.width; title: "Point temperature"; value: fans.points().length ? fans.points()[fans.pointIndex].temp + " °C" : "—"; theme: fans.theme }
                    FocusRow { id: pwmRow; width: parent.width; title: "Point PWM"; value: fans.points().length ? fans.points()[fans.pointIndex].pwm : "—"; theme: fans.theme }
                    FocusRow { id: addPointRow; width: parent.width; title: "Add point"; value: "A"; theme: fans.theme }
                    FocusRow { id: removePointRow; width: parent.width; title: "Remove point"; value: "A"; theme: fans.theme }
                    FocusRow { id: fanStopRow; width: parent.width; title: "Fan stop"; value: fans.points().length && fans.points()[0].pwm === 0 ? "On" : "Off"; theme: fans.theme }
                    FocusRow { id: rampUpRow; width: parent.width; title: "Ramp up"; value: fans.draft.fanSettings ? fans.draft.fanSettings.ramp_up : "—"; theme: fans.theme }
                    FocusRow { id: rampDownRow; width: parent.width; title: "Ramp down"; value: fans.draft.fanSettings ? fans.draft.fanSettings.ramp_down : "—"; theme: fans.theme }
                    FocusRow { id: smoothingRow; width: parent.width; title: "Smoothing"; value: fans.smoothingValue(); theme: fans.theme }
                    FocusRow { id: minPwmRow; width: parent.width; title: "Minimum PWM"; value: fans.draft.fanSettings ? fans.draft.fanSettings.min_pwm : "—"; theme: fans.theme }
                    FocusRow { id: addCurveRow; width: parent.width; title: "Create curve"; value: "A"; theme: fans.theme }
                    FocusRow { id: deleteCurveRow; width: parent.width; title: "Delete curve"; value: "A"; theme: fans.theme }
                    FocusRow { id: saveRow; width: parent.width; title: fans.dirty ? "Save changes *" : "Save changes"; value: "A"; theme: fans.theme; onActivated: fans.saveChanges() }
                    FocusRow { id: revertRow; width: parent.width; title: "Revert changes"; value: "A"; theme: fans.theme; onActivated: fans.discardDraft() }
                    Text { id: fanStatus; color: theme.muted; text: ""; width: parent.width; wrapMode: Text.WordWrap }
                }
            }
        }
    }
}
