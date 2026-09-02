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
    property var backend: armada
    property string errorText: ""
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
        function onErrorMessage(message) { root.errorText = message; }
    }

    Rectangle {
        anchors.fill: parent
        color: theme.transparent

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(880, parent.width - 40)
            height: Math.min(760, parent.height - 32)
            color: theme.panel
            border.color: theme.panelRaised
            border.width: theme.borderWidth
            radius: theme.radius

            Item {
                anchors.fill: parent
                anchors.margins: theme.spacing

                ListView {
                    id: navigation
                    anchors.left: parent.left
                    anchors.top: parent.top
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
                        selected: ListView.isCurrentItem && root.navigationActive
                        inactiveSelected: ListView.isCurrentItem && !root.navigationActive
                        onActivated: { root.showPage(index); root.navigationActive = false; }
                    }
                }

                StackView {
                    id: stack
                    anchors.left: navigation.right
                    anchors.top: parent.top
                    width: parent.width - navigation.width - theme.spacing
                    height: parent.height
                    initialItem: statusPage
                    replaceEnter: Transition { PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: theme.replaceEnterMs } }
                    replaceExit: Transition { PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: theme.replaceExitMs } }
                }

                Rectangle {
                    anchors.left: stack.left
                    anchors.top: stack.top
                    anchors.right: stack.right
                    anchors.bottom: stack.bottom
                    z: 2
                    visible: root.navigationActive
                    color: theme.scrim
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: theme.spacing
                height: root.errorText ? theme.rowHeight - 12 : 0
                visible: root.errorText !== ""
                color: theme.errorPanel
                border.color: theme.error
                border.width: theme.borderWidth
                radius: theme.radius
                z: 3
                Text {
                    anchors.fill: parent
                    anchors.margins: theme.spacing
                    text: root.errorText
                    color: theme.text
                    font.pixelSize: theme.bodySize - 2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
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
            property string currentTemp: ""
            property int focusIndex: 0
            property bool resetPending: false
            property var rows: []

            function setFocusedRow(row) {
                var index = rows.indexOf(row);
                if (index < 0) return;
                focusIndex = index;
                rows.forEach(function(item, itemIndex) { item.selected = itemIndex === focusIndex; });
            }

            function profiles() {
                return Object.keys((draft.power || {}).profiles || {});
            }
            function curves() {
                return Object.keys((draft.power || {}).fan_curves || {});
            }
            function profileOptions() {
                return profiles().map(function(name) {
                    var profile = ((draft.power || {}).profiles || {})[name] || {};
                    return {data: name, label: profile.label || name};
                });
            }
            function curveOptions() {
                return curves().map(function(name) {
                    var curve = ((draft.power || {}).fan_curves || {})[name] || {};
                    return {data: name, label: curve.label || name};
                });
            }
            function governorOptions() {
                return ((draft.perf || {}).governors || []).map(function(name) { return {data: name, label: name}; });
            }
            function underclockOptions() {
                return underclocks().map(function(name) { return {data: name, label: name}; });
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
            function selectProfile(name) {
                profileRow.value = name;
                fanRow.value = currentProfile().fan_curve || curves()[0] || "";
                governorRow.value = currentProfile().cpu_governor || "";
                underclockRow.value = currentProfile().cpu_underclock || underclocks()[0] || "";
            }
            function numberValue(key) {
                return Number(currentProfile()[key] || 0);
            }
            function setGpuValue(key, value) {
                var next = JSON.parse(JSON.stringify(draft));
                var profile = next.power.profiles[profileRow.value];
                profile[key] = (Number(value) / 100).toFixed(2);
                if (key === "gpu_min" && Number(profile.gpu_min) > Number(profile.gpu_max || 0)) profile.gpu_max = profile.gpu_min;
                if (key === "gpu_max" && Number(profile.gpu_max) < Number(profile.gpu_min || 0)) profile.gpu_min = profile.gpu_max;
                draft = next;
            }
            function refreshTemperature() {
                var result = armada.call("get_current_temp");
                if (result.ok && result.result !== undefined && result.result !== null)
                    currentTemp = String(result.result);
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
                    if (row === profileRow || row === fanRow || row === governorRow || row === underclockRow || row === cpuRow || row === gpuMinRow || row === gpuMaxRow)
                        row.adjust(direction);
                } else if (action === "accept" && (row === profileRow || row === fanRow || row === governorRow || row === underclockRow)) row.open();
                else if (action === "accept" && (row === cpuRow || row === gpuMinRow || row === gpuMaxRow)) row.activate();
                else if (action === "accept" && row === saveRow) save();
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
                refreshTemperature();
                temperaturePoll.start();
            }
            Component.onDestruction: temperaturePoll.stop()
            Timer { id: temperaturePoll; interval: 1000; repeat: true; onTriggered: power.refreshTemperature() }

            ScrollView {
                anchors.fill: parent
                clip: true
                Column {
                    width: power.width
                    spacing: theme.spacing
                    Text { id: header; text: "Power profile"; color: theme.text; font.pixelSize: theme.pageTitleSize }
                Text { text: "Use left/right to adjust the focused row."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
                    SelectRow { id: profileRow; width: parent.width; title: "Profile"; options: power.profileOptions(); currentValue: ""; theme: power.theme; focusOwner: power; onValueEdited: power.selectProfile(value) }
                    SelectRow { id: fanRow; width: parent.width; title: "Fan curve"; options: power.curveOptions(); currentValue: ""; theme: power.theme; focusOwner: power; onValueEdited: power.setProfileField("fan_curve", value) }
                    SelectRow { id: governorRow; visible: power.governorOptions().length > 0; width: parent.width; title: "CPU governor"; options: power.governorOptions(); currentValue: ""; theme: power.theme; focusOwner: power; onValueEdited: power.setProfileField("cpu_governor", value) }
                    SelectRow { id: underclockRow; visible: power.underclockOptions().length > 0; width: parent.width; title: "CPU underclock"; options: power.underclockOptions(); currentValue: ""; theme: power.theme; focusOwner: power; onValueEdited: power.setProfileField("cpu_underclock", value) }
                    SliderRow { id: cpuRow; width: parent.width; title: "CPU maximum"; from: 35; to: 100; value: Math.round(power.numberValue("cpu_max") * 100); valueText: Math.round(value) + "%"; theme: power.theme; focusOwner: power; onValueEdited: power.setProfileField("cpu_max", (value / 100).toFixed(2)) }
                    SliderRow { id: gpuMinRow; width: parent.width; title: "GPU minimum"; from: 0; to: 100; value: Math.round(power.numberValue("gpu_min") * 100); valueText: Math.round(value) + "%"; theme: power.theme; focusOwner: power; onValueEdited: power.setGpuValue("gpu_min", value) }
                    SliderRow { id: gpuMaxRow; width: parent.width; title: "GPU maximum"; from: 35; to: 100; value: Math.round(power.numberValue("gpu_max") * 100); valueText: Math.round(value) + "%"; theme: power.theme; focusOwner: power; onValueEdited: power.setGpuValue("gpu_max", value) }
                    FocusRow { id: resetRow; width: parent.width; title: "Reset profile"; value: "A"; theme: power.theme; focusOwner: power }
                    FocusRow { id: saveRow; width: parent.width; title: "Save profile"; value: "A"; theme: power.theme; focusOwner: power; onActivated: power.save() }
                    Text { id: status; color: theme.muted; text: ""; width: parent.width; wrapMode: Text.WordWrap }
                    Text { text: "Temperature: " + (power.currentTemp || "—") + (power.currentTemp ? " °C" : ""); color: theme.muted }
                }
            }
        }
    }

    Component {
        id: settingsPage
        SettingsPage {
            armada: root.backend
            theme: root.uiTheme
            onOpenCalibration: root.showPage(6)
        }
    }

    Component {
        id: compatibilityPage
        CompatibilityPage {
            armada: root.backend
            theme: root.uiTheme
        }
    }

    Component {
        id: gamePage
        GamePage {
            armada: root.backend
            theme: root.uiTheme
        }
    }

    Component {
        id: calibrationPage
        CalibrationPage {
            armada: root.backend
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
            property string currentTemp: ""
            property var rows: []
            property bool resetPending: false
            property var preFanStopPoints: null
            property string preFanStopCurveName: ""
            property int preFanStopMinPwm: -1

            function setFocusedRow(row) {
                var index = rows.indexOf(row);
                if (index < 0) return;
                focusIndex = index;
                rows.forEach(function(item, itemIndex) { item.selected = itemIndex === focusIndex; });
            }

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
            function factoryCurve() { return (draft.factoryFanCurves || {})[curveRow.value] || null; }
            function belowMinPwm() {
                var minimum = Number((draft.fanSettings || {}).min_pwm || 0);
                return points().some(function(point) { return point.pwm < minimum; });
            }
            function fanStopEnabled() {
                var curvePoints = points();
                return curvePoints.length > 0 && curvePoints[0].pwm === 0;
            }
            function fanStopTemp() {
                var curvePoints = points();
                var end = 0;
                while (end < curvePoints.length && curvePoints[end].pwm === 0) end++;
                return end > 0 ? curvePoints[end - 1].temp : 60;
            }
            function restoreFanStopPoints(allPoints, runEnd) {
                if (runEnd <= 0) return allPoints;
                var zeroRun = allPoints.slice(0, runEnd);
                var rest = allPoints.slice(runEnd);
                var restorePwm = rest.length ? rest[0].pwm : 128;
                var restored = zeroRun.map(function(point) { return {temp: point.temp, pwm: restorePwm || 128}; });
                if (rest.length) return restored.concat(rest);
                var lastTemp = restored.length ? restored[restored.length - 1].temp : 60;
                return restored.concat([{temp: Math.min(120, lastTemp + 10), pwm: 128}]);
            }
            function buildFanStopPoints(stopTemp, allPoints) {
                var zeroed = allPoints.filter(function(point) { return point.temp <= stopTemp; })
                    .map(function(point) { return {temp: point.temp, pwm: 0}; });
                var above = allPoints.filter(function(point) { return point.temp > stopTemp; });
                var hasBoundary = zeroed.some(function(point) { return point.temp === stopTemp; });
                var zone = hasBoundary ? zeroed : zeroed.concat([{temp: stopTemp, pwm: 0}]);
                if (above.length) return zone.concat(above);
                var fallback = allPoints.length ? allPoints[allPoints.length - 1].pwm : 128;
                return zone.concat([{temp: Math.min(120, stopTemp + 10), pwm: fallback || 128}]);
            }
            function refreshTemperature() {
                var result = armada.call("get_current_temp");
                if (result.ok && result.result !== undefined && result.result !== null)
                    currentTemp = String(result.result);
                curveGraph.requestPaint();
            }
            function curveOptions() {
                return curveNames().map(function(name) {
                    var curve = (draft.fanCurves || {})[name] || {};
                    return {data: name, label: curve.label || name};
                });
            }
            function pointOptions() {
                return points().map(function(point, index) { return {data: String(index), label: "Point " + (index + 1)}; });
            }
            function setCurvePoints(nextPoints) {
                var next = clone(draft);
                next.fanCurves[curveRow.value].curve = format(nextPoints);
                draft = next;
                dirty = true;
                pointIndex = Math.min(pointIndex, Math.max(0, nextPoints.length - 1));
                rebuildRows();
            }
            function adjustPoint(key, delta) {
                var nextPoints = points();
                if (!nextPoints.length) return;
                var point = nextPoints[Math.min(pointIndex, nextPoints.length - 1)];
                point[key] = Math.max(key === "temp" ? 0 : 0, Math.min(key === "temp" ? 120 : 255, point[key] + delta));
                setCurvePoints(nextPoints);
            }
            function setPoint(key, value) {
                var nextPoints = points();
                if (!nextPoints.length) return;
                nextPoints[Math.min(pointIndex, nextPoints.length - 1)][key] = Number(value);
                setCurvePoints(nextPoints);
            }
            function setSetting(key, value) {
                var next = clone(draft);
                next.fanSettings[key] = value;
                draft = next;
                dirty = true;
                rebuildRows();
            }
            function fixMinPwm() {
                var curvePoints = points();
                if (!curvePoints.length) return;
                var minimum = Math.min.apply(null, curvePoints.map(function(point) { return point.pwm; }));
                setSetting("min_pwm", Math.max(0, Math.min(255, Math.round(minimum))));
                fanStatus.text = "Minimum PWM adjusted; save to apply";
            }
            function resetCurve() {
                if (!factoryCurve()) {
                    fanStatus.text = "No factory default for this curve";
                    return;
                }
                if (!resetPending) {
                    resetPending = true;
                    fanStatus.text = "Press A again to reset this curve";
                    return;
                }
                var next = clone(draft);
                next.fanCurves[curveRow.value] = clone(factoryCurve());
                draft = next;
                pointIndex = 0;
                resetPending = false;
                preFanStopPoints = null;
                preFanStopCurveName = "";
                preFanStopMinPwm = -1;
                dirty = true;
                fanStatus.text = "Curve reset; save to apply";
                rebuildRows();
            }
            function toggleFanStop(enabled) {
                var currentPoints = points();
                if (!currentPoints.length) return;
                var nextPoints;
                var next = clone(draft);
                if (enabled) {
                    preFanStopPoints = clone(currentPoints);
                    preFanStopCurveName = curveRow.value;
                    preFanStopMinPwm = Number((draft.fanSettings || {}).min_pwm || 0);
                    nextPoints = buildFanStopPoints(60, currentPoints);
                    next.fanSettings.min_pwm = 0;
                } else {
                    var cached = preFanStopCurveName === curveRow.value ? preFanStopPoints : null;
                    var zeroRun = 0;
                    while (zeroRun < currentPoints.length && currentPoints[zeroRun].pwm === 0) zeroRun++;
                    nextPoints = cached || restoreFanStopPoints(currentPoints, zeroRun);
                    var anotherCurveStops = Object.keys(next.fanCurves || {}).some(function(name) {
                        if (name === curveRow.value) return false;
                        var other = parse(next.fanCurves[name].curve);
                        return other.length > 0 && other[0].pwm === 0;
                    });
                    if (!anotherCurveStops && next.fanSettings)
                        next.fanSettings.min_pwm = preFanStopMinPwm >= 0 ? preFanStopMinPwm : Number((next.factoryFanSettings || {}).min_pwm || 0);
                    preFanStopPoints = null;
                    preFanStopCurveName = "";
                    preFanStopMinPwm = -1;
                }
                next.fanCurves[curveRow.value].curve = format(nextPoints);
                draft = next;
                dirty = true;
                rebuildRows();
            }
            function setFanStopTemp(value) {
                var stopTemp = Math.max(0, Math.min(120, Number(value)));
                var currentPoints = points();
                var zeroRun = 0;
                while (zeroRun < currentPoints.length && currentPoints[zeroRun].pwm === 0) zeroRun++;
                var base = preFanStopCurveName === curveRow.value && preFanStopPoints
                    ? clone(preFanStopPoints) : restoreFanStopPoints(currentPoints, zeroRun);
                setCurvePoints(buildFanStopPoints(stopTemp, base));
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
                rebuildRows();
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
                rebuildRows();
            }
            function rebuildRows() {
                var next = [curveRow, pointRow, tempRow, pwmRow];
                if (belowMinPwm()) next.push(fixMinPwmRow);
                next.push(addPointRow, removePointRow, fanStopRow,
                    fanStopTempRow, rampUpRow, rampDownRow, smoothingRow, minPwmRow, resetCurveRow,
                    addCurveRow, deleteCurveRow, saveRow, revertRow);
                rows = next;
                focusIndex = Math.min(focusIndex, Math.max(0, rows.length - 1));
                rows.forEach(function(item, index) { item.selected = index === focusIndex; });
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
                rebuildRows();
            }
            function handleAction(action) {
                var row = rows[focusIndex];
                if (action !== "accept" || row !== deleteCurveRow) deletePending = false;
                if (action !== "accept" || row !== resetCurveRow) resetPending = false;
                if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
                else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
                else if (action === "left" || action === "right") {
                    var direction = action === "right" ? 1 : -1;
                    if (row === curveRow || row === pointRow || row === tempRow || row === pwmRow || row === fanStopTempRow || row === rampUpRow || row === rampDownRow || row === smoothingRow || row === minPwmRow)
                        row.adjust(direction);
                } else if (action === "accept") {
                    if (row === curveRow || row === pointRow) row.open();
                    else if (row === tempRow || row === pwmRow || row === fanStopTempRow || row === rampUpRow || row === rampDownRow || row === smoothingRow || row === minPwmRow) row.activate();
                    else if (row === fixMinPwmRow) fixMinPwm();
                    else if (row === fanStopRow) row.toggle();
                    else if (row === addCurveRow) addCurve();
                    else if (row === deleteCurveRow) deleteCurve();
                    else if (row === resetCurveRow) resetCurve();
                    else if (row === addPointRow) addPoint();
                    else if (row === removePointRow) removePoint();
                    else if (row === saveRow) saveChanges();
                    else if (row === revertRow) discardDraft();
                }
                rows.forEach(function(item, index) { item.selected = index === focusIndex; });
            }
            onDraftChanged: if (curveGraph) curveGraph.requestPaint()
            onPointIndexChanged: if (curveGraph) curveGraph.requestPaint()
            onCurrentTempChanged: if (curveGraph) curveGraph.requestPaint()
            Connections { target: armada; function onFanStateChanged() { fans.sync(); } }
            Component.onCompleted: {
                sync();
                refreshTemperature();
                temperaturePoll.start();
            }
            Component.onDestruction: temperaturePoll.stop()
            Timer { id: temperaturePoll; interval: 1000; repeat: true; onTriggered: fans.refreshTemperature() }

            ScrollView {
                anchors.fill: parent
                clip: true
                Column {
                    width: fans.width
                    spacing: theme.spacing
                    Text { text: "Fan curves"; color: theme.text; font.pixelSize: theme.pageTitleSize }
                    Text { text: "Select a row; left/right adjusts it, A activates actions."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
                    Canvas {
                        id: curveGraph
                        width: parent.width
                        height: 220
                        antialiasing: true
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var left = 34;
                            var right = width - 12;
                            var top = 14;
                            var bottom = height - 28;
                            var plotWidth = Math.max(1, right - left);
                            var plotHeight = Math.max(1, bottom - top);
                            function xForTemp(value) { return left + Math.max(0, Math.min(120, value)) / 120 * plotWidth; }
                            function yForPwm(value) { return bottom - Math.max(0, Math.min(255, value)) / 255 * plotHeight; }
                            ctx.fillStyle = theme.panelRaised;
                            ctx.fillRect(left, top, plotWidth, plotHeight);
                            ctx.strokeStyle = theme.muted;
                            ctx.globalAlpha = 0.22;
                            ctx.lineWidth = 1;
                            for (var pwm = 0; pwm <= 255; pwm += 64) {
                                ctx.beginPath(); ctx.moveTo(left, yForPwm(pwm)); ctx.lineTo(right, yForPwm(pwm)); ctx.stroke();
                            }
                            for (var temp = 0; temp <= 120; temp += 20) {
                                ctx.beginPath(); ctx.moveTo(xForTemp(temp), top); ctx.lineTo(xForTemp(temp), bottom); ctx.stroke();
                            }
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = theme.muted;
                            ctx.font = "12px sans-serif";
                            ctx.fillText("255", 4, top + 4);
                            ctx.fillText("0", 20, bottom + 4);
                            ctx.fillText("0°C", left - 8, height - 6);
                            ctx.fillText("120°C", right - 34, height - 6);
                            var curvePoints = fans.points();
                            if (!curvePoints.length) {
                                ctx.fillStyle = theme.muted;
                                ctx.font = "16px sans-serif";
                                ctx.fillText("No curve points", left + 12, top + plotHeight / 2);
                                return;
                            }
                            ctx.strokeStyle = theme.accent;
                            ctx.lineWidth = 3;
                            ctx.beginPath();
                            curvePoints.forEach(function(point, index) {
                                var px = xForTemp(point.temp);
                                var py = yForPwm(point.pwm);
                                if (index === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                            });
                            ctx.stroke();
                            curvePoints.forEach(function(point, index) {
                                var px = xForTemp(point.temp);
                                var py = yForPwm(point.pwm);
                                ctx.fillStyle = index === fans.pointIndex ? theme.text : theme.accent;
                                ctx.beginPath(); ctx.arc(px, py, index === fans.pointIndex ? 7 : 5, 0, Math.PI * 2); ctx.fill();
                                if (index === fans.pointIndex) {
                                    ctx.strokeStyle = theme.accent;
                                    ctx.lineWidth = 2;
                                    ctx.stroke();
                                }
                            });
                            var liveTemp = Number(fans.currentTemp);
                            if (Number.isFinite(liveTemp)) {
                                var liveX = xForTemp(liveTemp);
                                ctx.strokeStyle = theme.error;
                                ctx.lineWidth = 2;
                                ctx.beginPath(); ctx.moveTo(liveX, top); ctx.lineTo(liveX, bottom); ctx.stroke();
                            }
                        }
                    }
                    Text { text: "Live temperature: " + (fans.currentTemp || "—") + (fans.currentTemp ? " °C" : ""); color: theme.muted; font.pixelSize: theme.bodySize - 2 }
                    SelectRow { id: curveRow; width: parent.width; title: "Curve"; options: fans.curveOptions(); currentValue: ""; theme: fans.theme; focusOwner: fans; onValueEdited: { pointIndex = 0; fans.resetPending = false; fans.rebuildRows(); } }
                    SelectRow { id: pointRow; width: parent.width; title: "Point"; options: fans.pointOptions(); currentValue: String(fans.pointIndex); theme: fans.theme; focusOwner: fans; onValueEdited: fans.pointIndex = Number(value) }
                    SliderRow { id: tempRow; width: parent.width; title: "Point temperature"; from: 0; to: 120; value: fans.points().length ? fans.points()[fans.pointIndex].temp : 0; valueText: Math.round(value) + " °C"; enabled: fans.points().length > 0; theme: fans.theme; focusOwner: fans; onValueEdited: fans.setPoint("temp", value) }
                    SliderRow { id: pwmRow; width: parent.width; title: "Point PWM"; from: 0; to: 255; stepSize: 5; value: fans.points().length ? fans.points()[fans.pointIndex].pwm : 0; valueText: Math.round(value); enabled: fans.points().length > 0; theme: fans.theme; focusOwner: fans; onValueEdited: fans.setPoint("pwm", value) }
                    FocusRow { id: fixMinPwmRow; width: parent.width; title: "Fix minimum PWM"; value: "A"; theme: fans.theme; focusOwner: fans; visible: fans.belowMinPwm(); onActivated: fans.fixMinPwm() }
                    FocusRow { id: addPointRow; width: parent.width; title: "Add point"; value: "A"; theme: fans.theme; focusOwner: fans }
                    FocusRow { id: removePointRow; width: parent.width; title: "Remove point"; value: "A"; theme: fans.theme; focusOwner: fans }
                    ToggleRow { id: fanStopRow; width: parent.width; title: "Fan stop"; checked: fans.fanStopEnabled(); theme: fans.theme; focusOwner: fans; onToggled: fans.toggleFanStop(checked) }
                    SliderRow { id: fanStopTempRow; width: parent.width; title: "Fan stop temperature"; from: 0; to: 120; value: fans.fanStopTemp(); valueText: Math.round(value) + " °C"; visible: fans.fanStopEnabled(); theme: fans.theme; focusOwner: fans; onValueEdited: fans.setFanStopTemp(value) }
                    SliderRow { id: rampUpRow; width: parent.width; title: "Ramp up"; from: 1; to: 255; value: Number(fans.draft.fanSettings ? fans.draft.fanSettings.ramp_up : 1); valueText: Math.round(value); theme: fans.theme; focusOwner: fans; onValueEdited: fans.setSetting("ramp_up", Math.round(value)) }
                    SliderRow { id: rampDownRow; width: parent.width; title: "Ramp down"; from: 1; to: 255; value: Number(fans.draft.fanSettings ? fans.draft.fanSettings.ramp_down : 1); valueText: Math.round(value); theme: fans.theme; focusOwner: fans; onValueEdited: fans.setSetting("ramp_down", Math.round(value)) }
                    SliderRow { id: smoothingRow; width: parent.width; title: "Smoothing"; from: 0; to: 99; value: Math.round(Number(fans.draft.fanSettings ? fans.draft.fanSettings.smoothing : 0) * 100); valueText: Math.round(value) + "%"; theme: fans.theme; focusOwner: fans; onValueEdited: fans.setSetting("smoothing", Math.round(value) / 100) }
                    SliderRow { id: minPwmRow; width: parent.width; title: "Minimum PWM"; from: 0; to: 255; stepSize: 5; value: Number(fans.draft.fanSettings ? fans.draft.fanSettings.min_pwm : 0); valueText: Math.round(value); theme: fans.theme; focusOwner: fans; onValueEdited: fans.setSetting("min_pwm", Math.round(value)) }
                    FocusRow { id: resetCurveRow; width: parent.width; title: "Reset curve to factory"; value: "A"; theme: fans.theme; focusOwner: fans; visible: fans.factoryCurve() !== null; onActivated: fans.resetCurve() }
                    FocusRow { id: addCurveRow; width: parent.width; title: "Create curve"; value: "A"; theme: fans.theme; focusOwner: fans }
                    FocusRow { id: deleteCurveRow; width: parent.width; title: "Delete curve"; value: "A"; theme: fans.theme; focusOwner: fans }
                    FocusRow { id: saveRow; width: parent.width; title: fans.dirty ? "Save changes *" : "Save changes"; value: "A"; theme: fans.theme; focusOwner: fans; onActivated: fans.saveChanges() }
                    FocusRow { id: revertRow; width: parent.width; title: "Revert changes"; value: "A"; theme: fans.theme; focusOwner: fans; onActivated: fans.discardDraft() }
                    Text { id: fanStatus; color: theme.muted; text: ""; width: parent.width; wrapMode: Text.WordWrap }
                }
            }
        }
    }
}
