import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var armada
    property var theme
    property var tools: []
    property var appTools: []
    property string appid: ""
    property string launchOptions: ""
    property string globalTool: ""
    property string currentTool: ""
    property string globalResolution: "Default"
    property string gameResolution: "Default"
    property string statusText: ""
    property int focusIndex: 0
    property var rows: []

    function result(reply) {
        return reply && reply.ok ? (reply.result || {}) : null;
    }
    function toolId(item) { return String(item && item.id !== undefined ? item.id : item); }
    function toolLabel(item) { return String(item && item.label !== undefined ? item.label : toolId(item)); }
    function toolText(id) {
        if (!id) return "Follow Steam";
        for (var i = 0; i < tools.length; ++i)
            if (toolId(tools[i]) === id) return toolLabel(tools[i]);
        for (var j = 0; j < appTools.length; ++j)
            if (toolId(appTools[j]) === id) return toolLabel(appTools[j]);
        return id;
    }
    function call(action, fields) {
        var reply = armada.steamCall(action, fields || {});
        if (!reply.ok) statusText = reply.error || "Steam settings unavailable";
        return reply;
    }
    function loadGlobal() {
        var reply = call("get_global_compat_tools");
        var data = result(reply);
        if (data) tools = data.tools || [];
        globalTool = String((((armada.config || {}).tweaks || {}).global || {}).windowsCompatTool || "proton-cachyos-11.0-arm64");
        reply = call("get_global_resolution");
        data = result(reply);
        if (data) globalResolution = String(data.value || "Default");
    }
    function loadGame() {
        appTools = [];
        currentTool = "";
        launchOptions = "";
        gameResolution = "Default";
        if (!/^\d+$/.test(appid)) {
            rebuildRows();
            return;
        }
        var reply = call("get_app_compat_tools", {appid: appid});
        var data = result(reply);
        if (data) appTools = data.tools || [];
        reply = call("get_compat_state", {appid: appid});
        data = result(reply);
        if (data) currentTool = String(data.tool || "");
        reply = call("get_launch_options", {appid: appid});
        data = result(reply);
        if (data) launchOptions = String(data.options || "");
        reply = call("get_resolution", {appid: appid});
        data = result(reply);
        if (data) gameResolution = String(data.value || "Default");
        rebuildRows();
    }
    function sync() {
        var game = (armada.config || {}).game || {};
        if (!appid && game.appid) appid = String(game.appid);
        loadGlobal();
        loadGame();
    }
    function rebuildRows() {
        rows = [targetRow, globalToolRow, autoApplyRow, globalResolutionRow];
        if (/^\d+$/.test(appid)) rows = rows.concat([appToolRow, gameResolutionRow, launchRow, saveLaunchRow, resetRow]);
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function cycle(row, values, direction) {
        if (!values.length) return;
        var current = values.indexOf(row.value);
        row.value = values[(current + direction + values.length) % values.length];
        if (row === globalToolRow) saveGlobalTool(row.value);
        else if (row === globalResolutionRow) saveGlobalResolution(row.value);
        else if (row === appToolRow) saveAppTool(row.value);
        else if (row === gameResolutionRow) saveGameResolution(row.value);
    }
    function saveGlobalTool(label) {
        var id = "";
        for (var i = 0; i < tools.length; ++i) if (toolLabel(tools[i]) === label) id = toolId(tools[i]);
        if (!id) id = label;
        var reply = call("set_global_compat_tool", {tool: id});
        if (!reply.ok) return;
        globalTool = id;
        var next = JSON.parse(JSON.stringify(armada.config || {}));
        next.tweaks.global.windowsCompatTool = id;
        reply = armada.call("save_tweaks", {data: next.tweaks});
        statusText = reply.ok ? "Saved" : (reply.error || "Save failed");
    }
    function saveGlobalResolution(value) {
        var reply = call("set_global_resolution", {value: value});
        if (reply.ok) { globalResolution = value; statusText = "Saved"; }
    }
    function saveAppTool(label) {
        if (!/^\d+$/.test(appid)) return;
        var id = label === "Use Default" ? globalTool : (label === "Follow Steam" ? "" : label);
        var reply = call("set_compat_tool", {appid: appid, tool: id});
        if (reply.ok) { currentTool = id; statusText = "Saved"; }
    }
    function saveGameResolution(value) {
        var reply = call("set_resolution", {appid: appid, value: value});
        if (reply.ok) { gameResolution = value; statusText = "Saved"; }
    }
    function saveLaunch() {
        if (!/^\d+$/.test(appid)) return;
        var reply = call("set_launch_options", {appid: appid, options: launchField.text});
        if (reply.ok) { launchOptions = launchField.text; statusText = "Saved"; }
    }
    function resetGame() {
        if (!/^\d+$/.test(appid)) return;
        var first = call("set_compat_tool", {appid: appid, tool: ""});
        var second = call("set_launch_options", {appid: appid, options: ""});
        var third = call("set_resolution", {appid: appid, value: "Default"});
        if (first.ok && second.ok && third.ok) { currentTool = ""; launchOptions = ""; gameResolution = "Default"; statusText = "Reset"; }
    }
    function handleAction(action) {
        var row = rows[focusIndex];
        if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
        else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
        else if (action === "left" || action === "right") {
            var direction = action === "right" ? 1 : -1;
            if (row === globalToolRow) cycle(row, tools.map(toolLabel), direction);
            else if (row === globalResolutionRow) cycle(row, ["Default", "Native", "1280x720", "960x540"], direction);
            else if (row === appToolRow) cycle(row, ["Use Default", "Follow Steam"].concat(appTools.map(toolLabel)), direction);
            else if (row === gameResolutionRow) cycle(row, ["Default", "Native", "1280x720", "960x540"], direction);
        } else if (action === "accept") {
            if (row === targetRow) { appidField.forceActiveFocus(); return; }
            if (row === autoApplyRow) {
                var next = JSON.parse(JSON.stringify(armada.config || {}));
                next.tweaks.global.autoApplyCompat = !Boolean(next.tweaks.global.autoApplyCompat);
                var saved = armada.call("save_tweaks", {data: next.tweaks});
                if (saved.ok) { armada.refresh(); statusText = "Saved"; }
            } else if (row === launchRow) launchField.forceActiveFocus();
            else if (row === saveLaunchRow) saveLaunch();
            else if (row === resetRow) resetGame();
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function handleBack() {
        if (appidField.activeFocus || launchField.activeFocus) { root.forceActiveFocus(); return true; }
        return false;
    }

    Connections { target: root.armada; function onConfigChanged() { root.rebuildRows(); } }
    Component.onCompleted: { rebuildRows(); sync(); }

    ScrollView {
        anchors.fill: parent
        clip: true
        Column {
            width: root.width
            spacing: root.theme.spacing
            Text { text: "Steam compatibility"; color: root.theme.text; font.pixelSize: root.theme.pageTitleSize }
            Text { text: "Private Steam settings are isolated behind a fixed-action bridge."; color: root.theme.muted; font.pixelSize: root.theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
            FocusRow { id: targetRow; width: parent.width; title: "Game AppID"; value: root.appid || "Default"; theme: root.theme }
            TextField { id: appidField; width: parent.width; text: root.appid; placeholderText: "Running or installed AppID"; onEditingFinished: { root.appid = text.trim(); root.loadGame(); } }
            FocusRow { id: globalToolRow; width: parent.width; title: "Default Proton"; value: root.toolText(root.globalTool); theme: root.theme }
            FocusRow { id: autoApplyRow; width: parent.width; title: "Apply to new games"; value: Boolean((((root.armada.config || {}).tweaks || {}).global || {}).autoApplyCompat) === false ? "Off" : "On"; theme: root.theme }
            FocusRow { id: globalResolutionRow; width: parent.width; title: "Default resolution"; value: root.globalResolution; theme: root.theme }
            FocusRow { id: appToolRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Compatibility tool"; value: root.currentTool ? root.toolText(root.currentTool) : "Follow Steam"; theme: root.theme }
            FocusRow { id: gameResolutionRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Game resolution"; value: root.gameResolution; theme: root.theme }
            FocusRow { id: launchRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Launch options"; value: root.launchOptions || "Empty"; theme: root.theme; onActivated: launchField.forceActiveFocus() }
            TextField { id: launchField; visible: /^\d+$/.test(root.appid); width: parent.width; text: root.launchOptions; placeholderText: "Steam launch options" }
            FocusRow { id: saveLaunchRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Save launch options"; value: "A"; theme: root.theme; onActivated: root.saveLaunch() }
            FocusRow { id: resetRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Reset game compatibility"; value: "A"; theme: root.theme; onActivated: root.resetGame() }
            Text { text: root.statusText; color: root.theme.muted; font.pixelSize: root.theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
        }
    }
}
