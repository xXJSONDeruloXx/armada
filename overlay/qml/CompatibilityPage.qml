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
    property bool resetAllPending: false

    function setFocusedRow(row) {
        var index = rows.indexOf(row);
        if (index < 0) return;
        focusIndex = index;
        rows.forEach(function(item, itemIndex) { item.selected = itemIndex === focusIndex; });
    }

    function result(reply) {
        return reply && reply.ok ? (reply.result || {}) : null;
    }
    function toolId(item) { return String(item && item.id !== undefined ? item.id : item); }
    function toolLabel(item) { return String(item && item.label !== undefined ? item.label : toolId(item)); }
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
        rows.push(resetAllRow);
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function saveGlobalTool(label) {
        var id = String(label || "");
        var oldTool = globalTool;
        globalTool = id;
        var next = JSON.parse(JSON.stringify(armada.config || {}));
        next.tweaks.global.windowsCompatTool = id;
        var reply = armada.call("save_tweaks", {data: next.tweaks});
        if (!reply.ok) { statusText = reply.error || "Save failed"; return; }
        var games = (armada.config.installedGames || []).filter(function(game) {
            return game && !game.nonSteam && /^\d+$/.test(String(game.appid || ""));
        });
        var mapped = armada.call("get_compat_mapped_appids", {tool: oldTool});
        var pinned = mapped.ok ? (mapped.result || []) : null;
        var migrated = call("migrate_compat", {games: games, old_tool: oldTool, new_tool: id, pinned: pinned});
        statusText = migrated.ok ? "Saved" : "Saved; existing pins were not migrated";
    }
    function saveGlobalResolution(value) {
        var reply = call("set_global_resolution", {value: value});
        if (reply.ok) { globalResolution = value; statusText = "Saved"; }
    }
    function saveAppTool(label) {
        if (!/^\d+$/.test(appid)) return;
        var id = label === "__default" ? globalTool : label;
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
        var reply = call("reset_game", {appid: appid, tool: globalTool});
        if (reply.ok) { statusText = "Reset to Armada defaults"; loadGame(); }
    }
    function resetAllGames() {
        if (!resetAllPending) {
            resetAllPending = true;
            statusText = "Press A again to reset Steam compatibility for all games";
            return;
        }
        resetAllPending = false;
        var games = (armada.config.installedGames || []).filter(function(game) { return game && /^\d+$/.test(String(game.appid || "")); });
        var failed = 0;
        games.forEach(function(game) {
            var id = String(game.appid);
            if (!call("reset_game", {appid: id, tool: globalTool}).ok) failed++;
        });
        armada.call("save_compat_applied", {appids: []});
        statusText = failed ? "Reset completed with errors" : "Reset " + games.length + " games";
        if (/^\d+$/.test(appid)) loadGame();
    }
    function handleAction(action) {
        var row = rows[focusIndex];
        if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
        else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
        else if (action === "left" || action === "right") {
            var direction = action === "right" ? 1 : -1;
            if (row === globalToolRow || row === globalResolutionRow || row === appToolRow || row === gameResolutionRow)
                row.adjust(direction);
        } else if (action === "accept") {
            if (row === globalToolRow || row === globalResolutionRow || row === appToolRow || row === gameResolutionRow) row.open();
            else if (row === targetRow) { appidField.forceActiveFocus(); return; }
            if (row === autoApplyRow) {
                row.toggle();
            } else if (row === launchRow) launchField.forceActiveFocus();
            else if (row === saveLaunchRow) saveLaunch();
            else if (row === resetRow) resetGame();
            else if (row === resetAllRow) resetAllGames();
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function handleBack() {
        if (appidField.activeFocus || launchField.activeFocus) { root.forceActiveFocus(); return true; }
        return false;
    }
    function saveAutoApply(enabled) {
        var next = JSON.parse(JSON.stringify(armada.config || {}));
        next.tweaks.global.autoApplyCompat = enabled;
        var saved = armada.call("save_tweaks", {data: next.tweaks});
        if (saved.ok) { armada.refresh(); statusText = "Saved"; }
        else statusText = saved.error || "Save failed";
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
            FocusRow { id: targetRow; width: parent.width; title: "Game AppID"; value: root.appid || "Default"; theme: root.theme; focusOwner: root }
            TextField { id: appidField; width: parent.width; text: root.appid; placeholderText: "Running or installed AppID"; onEditingFinished: { root.appid = text.trim(); root.loadGame(); } }
            SelectRow { id: globalToolRow; width: parent.width; title: "Default Proton"; options: root.tools; currentValue: root.globalTool; theme: root.theme; focusOwner: root; onValueEdited: root.saveGlobalTool(value) }
            ToggleRow { id: autoApplyRow; width: parent.width; title: "Apply to new games"; checked: Boolean((((root.armada.config || {}).tweaks || {}).global || {}).autoApplyCompat); theme: root.theme; focusOwner: root; onToggled: root.saveAutoApply(checked) }
            SelectRow { id: globalResolutionRow; width: parent.width; title: "Default resolution"; options: ["Default", "Native", "1280x720", "960x540"]; currentValue: root.globalResolution; theme: root.theme; focusOwner: root; onValueEdited: root.saveGlobalResolution(value) }
            SelectRow {
                id: appToolRow
                visible: /^\d+$/.test(root.appid)
                width: parent.width
                title: "Compatibility tool"
                options: [{data: "__default", label: "Use Default"}, {data: "", label: "Follow Steam"}].concat(root.appTools)
                currentValue: root.currentTool || ""
                theme: root.theme
                focusOwner: root
                onValueEdited: root.saveAppTool(value)
            }
            SelectRow { id: gameResolutionRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Game resolution"; options: ["Default", "Native", "1280x720", "960x540"]; currentValue: root.gameResolution; theme: root.theme; focusOwner: root; onValueEdited: root.saveGameResolution(value) }
            FocusRow { id: launchRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Launch options"; value: root.launchOptions || "Empty"; theme: root.theme; focusOwner: root; onActivated: launchField.forceActiveFocus() }
            TextField { id: launchField; visible: /^\d+$/.test(root.appid); width: parent.width; text: root.launchOptions; placeholderText: "Steam launch options" }
            FocusRow { id: saveLaunchRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Save launch options"; value: "A"; theme: root.theme; focusOwner: root; onActivated: root.saveLaunch() }
            FocusRow { id: resetRow; visible: /^\d+$/.test(root.appid); width: parent.width; title: "Reset game compatibility"; value: "A"; theme: root.theme; focusOwner: root; onActivated: root.resetGame() }
            FocusRow { id: resetAllRow; width: parent.width; title: "Reset all game compatibility"; value: "A"; theme: root.theme; focusOwner: root; onActivated: root.resetAllGames() }
            Text { text: root.statusText; color: root.theme.muted; font.pixelSize: root.theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
        }
    }
}
