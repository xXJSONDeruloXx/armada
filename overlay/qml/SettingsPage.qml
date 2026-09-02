import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var armada
    property var theme
    property var rgb: ({})
    property string statusText: ""
    property int focusIndex: 0
    property var rows: []
    signal openCalibration

    function setFocusedRow(row) {
        var index = rows.indexOf(row);
        if (index < 0) return;
        focusIndex = index;
        rows.forEach(function(item, itemIndex) { item.selected = itemIndex === focusIndex; });
    }

    function options(key) { return armada.config[key] || []; }
    function optionValue(item) { return item && item.data !== undefined ? item.data : String(item); }
    function optionLabel(item) { return item && item.label !== undefined ? item.label : optionValue(item); }
    function currentOption(key, fallback) { return armada.config[key] || fallback; }
    function cycle(key, action, direction) {
        var values = options(key).map(optionValue);
        if (!values.length) return;
        var current = values.indexOf(currentOption(key, values[0]));
        var next = values[(current + direction + values.length) % values.length];
        var reply = armada.call(action, {value: next});
        if (!reply.ok) statusText = reply.error;
        else { statusText = "Saved"; armada.refresh(); }
    }
    function setChoice(key, action, value) {
        var reply = armada.call(action, {value: value});
        if (!reply.ok) statusText = reply.error;
        else { statusText = "Saved"; armada.refresh(); }
    }
    function setToggle(action, checked) {
        var reply = armada.call(action, {enabled: checked});
        if (!reply.ok) statusText = reply.error;
        else { statusText = "Saved"; armada.refresh(); }
    }
    function toggle(key, action) {
        var next = !Boolean(armada.config[key]);
        var reply = armada.call(action, {enabled: next});
        if (!reply.ok) statusText = reply.error;
        else { statusText = "Saved"; armada.refresh(); }
    }
    function rgbColor(hue) {
        var section = Math.floor((hue % 360) / 60);
        var value = ((hue % 60) / 60) * 255;
        function channel(valueToFormat) { return Math.round(valueToFormat).toString(16).padStart(2, "0").toUpperCase(); }
        var rising = channel(value);
        var falling = channel(255 - value);
        if (section === 0) return "FF" + rising + "00";
        if (section === 1) return falling + "FF00";
        if (section === 2) return "00FF" + rising;
        if (section === 3) return "00" + falling + "FF";
        if (section === 4) return rising + "00FF";
        return "FF00" + falling;
    }
    function rgbHue(color) {
        var red = parseInt(String(color || "000000").slice(0, 2), 16) / 255;
        var green = parseInt(String(color || "000000").slice(2, 4), 16) / 255;
        var blue = parseInt(String(color || "000000").slice(4, 6), 16) / 255;
        var maximum = Math.max(red, green, blue);
        var difference = maximum - Math.min(red, green, blue);
        if (!difference) return 0;
        var hue = maximum === red ? (green - blue) / difference
            : maximum === green ? 2 + (blue - red) / difference : 4 + (red - green) / difference;
        return Math.round((hue * 60 + 360) % 360);
    }
    function setRgb(patch) {
        var next = JSON.parse(JSON.stringify(rgb || {}));
        Object.keys(patch).forEach(function(key) { next[key] = patch[key]; });
        var reply = armada.call("set_rgb", {enabled: Boolean(next.enabled), color: String(next.color || "FFFFFF"), brightness: Number(next.brightness || 0)});
        if (!reply.ok) statusText = reply.error;
        else { rgb = reply.result || next; statusText = "Saved"; }
    }
    function handleAction(action) {
        var row = rows[focusIndex];
        if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
        else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
        else if (action === "left" || action === "right") {
            var direction = action === "right" ? 1 : -1;
            if (row === controllerRow) cycle("controllerType", "set_controller_type", direction);
            else if (row === sleepRow) cycle("sleepMode", "set_sleep_mode", direction);
            else if (row === desktopRow) cycle("desktopMode", "set_desktop_mode", direction);
            else if (row === rgbBrightnessRow && rgb.enabled) setRgb({brightness: Math.max(0, Math.min(100, Number(rgb.brightness || 0) + direction * 5))});
            else if (row === rgbHueRow && rgb.enabled) setRgb({color: rgbColor((rgbHue(rgb.color) + direction + 360) % 360)});
        } else if (action === "accept") {
            if (row === controllerRow || row === sleepRow || row === desktopRow) row.open();
            else if (row === rgbBrightnessRow || row === rgbHueRow) row.activate();
            else if (row === calibrationRow) openCalibration();
            else if (row === sshRow) toggle("sshEnabled", "set_ssh_enabled");
            else if (row === mtpRow) toggle("mtpEnabled", "set_mtp_enabled");
            else if (row === ablRow) toggle("ablAutoEnabled", "set_abl_auto_enabled");
            else if (row === rgbEnabledRow && rgb) setRgb({enabled: !Boolean(rgb.enabled)});
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function rebuildRows() {
        rows = [controllerRow, calibrationRow, sshRow, osRow, ablVersionRow];
        if (options("sleepModes").length > 1) rows.push(sleepRow);
        if (options("desktopModes").length > 1) rows.push(desktopRow);
        rows.push(mtpRow, ablRow);
        if (armada.config.rgbSupported && rgb && Object.keys(rgb).length) rows.push(rgbEnabledRow, rgbBrightnessRow, rgbHueRow);
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function loadRgb() {
        if (!armada.config.rgbSupported) return;
        var reply = armada.call("get_rgb");
        if (reply.ok && reply.result) rgb = reply.result;
        rebuildRows();
    }
    Connections { target: armada; function onConfigChanged() { root.rebuildRows(); root.loadRgb(); } }
    Component.onCompleted: { rebuildRows(); loadRgb(); }

    ScrollView {
        anchors.fill: parent
        clip: true
        Column {
            width: root.width
            spacing: theme.spacing
            Text { text: "Settings"; color: theme.text; font.pixelSize: theme.pageTitleSize }
            Text { text: "Controller, system, and experimental controls"; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
            SelectRow {
                id: controllerRow
                width: parent.width
                title: "Emulation"
                options: root.options("controllerTypes")
                currentValue: root.armada.config.controllerType || "deck-uhid"
                theme: root.theme
                focusOwner: root
                onValueEdited: root.setChoice("controllerType", "set_controller_type", value)
            }
            FocusRow { id: calibrationRow; width: parent.width; title: "Launch calibration"; value: "A"; theme: root.theme; onActivated: root.openCalibration() }
            ToggleRow { id: sshRow; width: parent.width; title: "Enable SSH"; checked: Boolean(armada.config.sshEnabled); theme: root.theme; focusOwner: root; onToggled: root.setToggle("set_ssh_enabled", checked) }
            FocusRow { id: osRow; width: parent.width; title: "OS version"; value: armada.config.osVersion || "unknown"; theme: root.theme }
            FocusRow { id: ablVersionRow; width: parent.width; title: "ABL version"; value: armada.config.ablVersion || "unknown"; theme: root.theme }
            SelectRow {
                id: sleepRow
                visible: root.options("sleepModes").length > 1
                width: parent.width
                title: "Sleep mode"
                options: root.options("sleepModes")
                currentValue: root.armada.config.sleepMode || "fake"
                theme: root.theme
                focusOwner: root
                onValueEdited: root.setChoice("sleepMode", "set_sleep_mode", value)
            }
            SelectRow {
                id: desktopRow
                visible: root.options("desktopModes").length > 1
                width: parent.width
                title: "Desktop mode"
                options: root.options("desktopModes")
                currentValue: root.armada.config.desktopMode || "desktop"
                theme: root.theme
                focusOwner: root
                onValueEdited: root.setChoice("desktopMode", "set_desktop_mode", value)
            }
            ToggleRow { id: mtpRow; width: parent.width; title: "USB file transfer"; checked: Boolean(armada.config.mtpEnabled); theme: root.theme; focusOwner: root; onToggled: root.setToggle("set_mtp_enabled", checked) }
            ToggleRow { id: ablRow; width: parent.width; title: "Automatic ABL updates"; checked: Boolean(armada.config.ablAutoEnabled); theme: root.theme; focusOwner: root; onToggled: root.setToggle("set_abl_auto_enabled", checked) }
            ToggleRow { id: rgbEnabledRow; width: parent.width; title: "RGB lighting"; checked: Boolean(rgb.enabled); theme: root.theme; focusOwner: root; onToggled: root.setRgb({enabled: checked}) }
            SliderRow {
                id: rgbBrightnessRow
                width: parent.width
                title: "RGB brightness"
                from: 0
                to: 100
                value: Number(rgb.brightness || 0)
                valueText: Math.round(value) + "%"
                enabled: Boolean(rgb.enabled)
                theme: root.theme
                focusOwner: root
                onValueEdited: root.setRgb({brightness: Math.round(value)})
            }
            SliderRow {
                id: rgbHueRow
                width: parent.width
                title: "RGB color"
                from: 0
                to: 359
                value: root.rgb.color ? root.rgbHue(root.rgb.color) : 0
                valueText: Math.round(value) + "°"
                enabled: Boolean(rgb.enabled)
                theme: root.theme
                focusOwner: root
                onValueEdited: root.setRgb({color: root.rgbColor(Math.round(value))})
            }
            Text { text: root.statusText; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
        }
    }
}
