import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var armada
    property var theme
    property string selectedAppid: ""
    property var draftTweaks: ({global: {}, games: {}})
    property bool dirty: false
    property bool resetPending: false
    property bool restartPending: false
    property string statusText: ""
    property int focusIndex: 0
    property var rows: []
    property var fexKnobRows: []
    property var thunkRows: []

    readonly property var fexKnobs: [
        {key: "TSOEnabled", label: "TSO enabled"},
        {key: "X87ReducedPrecision", label: "X87 reduced precision"},
        {key: "Multiblock", label: "Multiblock"},
        {key: "VectorTSOEnabled", label: "Vector TSO enabled"},
        {key: "MemcpySetTSOEnabled", label: "Memcpy TSO enabled"},
        {key: "HalfBarrierTSOEnabled", label: "Half barrier TSO enabled"}
    ]
    readonly property var thunks: [
        {key: "Vulkan", label: "Host Vulkan"},
        {key: "GL", label: "Host OpenGL"},
        {key: "asound", label: "Host ALSA"},
        {key: "drm", label: "Host DRM"},
        {key: "WaylandClient", label: "Host Wayland"}
    ]

    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function games() {
        var result = [{appid: "", name: "Default"}];
        (armada.config.installedGames || []).forEach(function(game) {
            if (game && game.appid) result.push({appid: String(game.appid), name: game.name || ("App " + game.appid)});
        });
        result.sort(function(a, b) { return a.appid === "" ? -1 : a.name.localeCompare(b.name); });
        return result;
    }
    function targetName() {
        var match = games().filter(function(game) { return game.appid === selectedAppid; });
        return match.length ? match[0].name : "Default";
    }
    function ownSettings() {
        if (!selectedAppid) return draftTweaks.global || {};
        return (draftTweaks.games || {})[selectedAppid] || {};
    }
    function effective(key) {
        var own = ownSettings();
        if (Object.prototype.hasOwnProperty.call(own, key)) return own[key];
        return (draftTweaks.global || {})[key];
    }
    function setSetting(key, value) {
        var next = clone(draftTweaks);
        if (!next.global) next.global = {};
        var target = next.global;
        if (selectedAppid) {
            if (!next.games) next.games = {};
            if (!next.games[selectedAppid]) next.games[selectedAppid] = {name: targetName()};
            target = next.games[selectedAppid];
        }
        if (value === undefined) delete target[key];
        else target[key] = value;
        draftTweaks = next;
        dirty = true;
    }
    function fexProfiles() { return Object.keys(armada.config.fexProfiles || {}); }
    function fexLabel(id) {
        if (id === "custom") return "Custom";
        return (armada.config.fexProfiles || {})[id] ? armada.config.fexProfiles[id].label : (id || "Default");
    }
    function fexConfig() {
        var id = String(effective("fexProfile") || "default");
        if (id === "custom") return effective("fexConfig") || {};
        var profile = (armada.config.fexProfiles || {})[id] || (armada.config.fexProfiles || {}).default;
        return profile ? profile.config || {} : {};
    }
    function setFexProfile(id) {
        if (id === "custom") setSetting("fexConfig", clone(fexConfig()));
        setSetting("fexProfile", id);
    }
    function toggleFexKnob(key) {
        var next = clone(fexConfig());
        next[key] = next[key] === "1" ? "0" : "1";
        setSetting("fexProfile", "custom");
        setSetting("fexConfig", next);
    }
    function thunkValue(key) {
        var values = effective("thunks") || {};
        return values[key] !== false;
    }
    function toggleThunk(key) {
        var next = clone(effective("thunks") || {});
        next[key] = !thunkValue(key);
        setSetting("thunks", next);
    }
    function optionValues(key) {
        var result = ["default"];
        (armada.config.perf && armada.config.perf.corePresets || []).forEach(function(item) { result.push(item.data); });
        return result;
    }
    function optionLabel(key, value) {
        if (!value || value === "default") return "Default";
        var options = armada.config.perf && armada.config.perf.corePresets || [];
        var match = options.filter(function(item) { return item.data === value; });
        return match.length ? match[0].label : value;
    }
    function cycleOption(key, direction) {
        var values = optionValues(key);
        var current = String(effective(key) || "default");
        var index = values.indexOf(current);
        var next = values[(index + direction + values.length) % values.length];
        setSetting(key, next === "default" ? undefined : next);
    }
    function adjust(key, delta, minimum, maximum) {
        var current = Number(effective(key) || 0);
        setSetting(key, Math.max(minimum, Math.min(maximum, current + delta)));
    }
    function save() {
        var reply = armada.call("save_tweaks", {data: draftTweaks});
        if (!reply.ok) statusText = reply.error;
        else { dirty = false; statusText = "Saved"; armada.refresh(); }
    }
    function resetTarget() {
        if (!resetPending) {
            resetPending = true;
            statusText = selectedAppid ? "Press A again to reset this game" : "Press A again to reset all game profiles";
            return;
        }
        var next = clone(draftTweaks);
        if (selectedAppid) {
            if (next.games) delete next.games[selectedAppid];
        } else {
            next.games = {};
        }
        draftTweaks = next;
        dirty = true;
        resetPending = false;
        statusText = "Reset; save to apply";
    }
    function reapply() {
        if (dirty) save();
        var reply = armada.call("reapply_perf");
        statusText = reply.ok ? "Performance settings reapplied" : reply.error;
    }
    function restartGameMode() {
        if (!restartPending) {
            restartPending = true;
            statusText = "Press A again to restart Game Mode";
            return;
        }
        if (dirty) save();
        var reply = armada.call("restart_game_mode");
        restartPending = false;
        statusText = reply.ok ? "Game Mode restart requested" : reply.error;
    }
    function selectTarget(direction) {
        var values = games();
        var current = values.map(function(item) { return item.appid; }).indexOf(selectedAppid);
        selectedAppid = values[(current + direction + values.length) % values.length].appid;
        draftTweaks = clone(armada.config.tweaks || {global: {}, games: {}});
        dirty = false;
        resetPending = false;
        restartPending = false;
    }
    function sync() {
        if (dirty) return;
        draftTweaks = clone(armada.config.tweaks || {global: {}, games: {}});
        var values = games().map(function(item) { return item.appid; });
        if (values.indexOf(selectedAppid) < 0) selectedAppid = "";
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function handleAction(action) {
        var row = rows[focusIndex];
        if (action !== "accept" || row !== resetRow) resetPending = false;
        if (action !== "accept" || row !== restartRow) restartPending = false;
        if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
        else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
        else if (action === "left" || action === "right") {
            var direction = action === "right" ? 1 : -1;
            if (row === targetRow) selectTarget(direction);
            else if (row === fexRow) {
                var values = fexProfiles().concat(["custom"]);
                var current = values.indexOf(String(effective("fexProfile") || "default"));
                setFexProfile(values[(current + direction + values.length) % values.length]);
            } else if (fexKnobRows.indexOf(row) >= 0) toggleFexKnob(fexKnobs[fexKnobRows.indexOf(row)].key);
            else if (thunkRows.indexOf(row) >= 0) toggleThunk(thunks[thunkRows.indexOf(row)].key);
            else if (row === cpuCoresRow) cycleOption("cores", direction);
            else if (row === cpuTopologyRow) setSetting("wineTopology", effective("wineTopology") === false ? undefined : false);
            else if (row === niceRow) adjust("nice", direction, -20, 19);
            else if (row === gamescopeCoresRow) cycleOption("gamescopeCores", direction);
            else if (row === gamescopeNiceRow) adjust("gamescopeNice", direction, -20, 19);
            else if (row === gamescopeRealtimeRow) setSetting("gamescopeRr", !Boolean(effective("gamescopeRr")));
            else if (row === schedulerRow) {
                var schedulers = ["default"].concat((armada.config.perf && armada.config.perf.schedulers) || []);
                var currentScheduler = String(effective("scheduler") || "default");
                var schedulerIndex = schedulers.indexOf(currentScheduler);
                var nextScheduler = schedulers[(schedulerIndex + direction + schedulers.length) % schedulers.length];
                setSetting("scheduler", nextScheduler === "default" ? undefined : nextScheduler);
            }
        } else if (action === "accept") {
            if (row === reapplyRow) reapply();
            else if (row === restartRow) restartGameMode();
            else if (row === resetRow) resetTarget();
            else if (row === saveRow) save();
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function schedulerValue() { return String(effective("scheduler") || "default").toUpperCase(); }
    function boolValue(key) { return effective(key) === false ? "Off" : "On"; }

    Connections { target: armada; function onConfigChanged() { root.sync(); } }
    Component.onCompleted: {
        fexKnobRows = [fexTsoRow, fexX87Row, fexMultiblockRow, fexVectorRow, fexMemcpyRow, fexBarrierRow];
        thunkRows = [thunkVulkanRow, thunkGlRow, thunkAsoundRow, thunkDrmRow, thunkWaylandRow];
        rows = [targetRow, fexRow, fexTsoRow, fexX87Row, fexMultiblockRow, fexVectorRow, fexMemcpyRow,
            fexBarrierRow, thunkVulkanRow, thunkGlRow, thunkAsoundRow, thunkDrmRow, thunkWaylandRow,
            cpuCoresRow, cpuTopologyRow, niceRow, gamescopeCoresRow, gamescopeNiceRow,
            gamescopeRealtimeRow, schedulerRow, reapplyRow, restartRow, resetRow, saveRow];
        sync();
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        Column {
            width: root.width
            spacing: theme.spacing
            Text { text: "Game settings"; color: theme.text; font.pixelSize: theme.pageTitleSize }
            Text { text: "Armada launch, FEX, and performance settings"; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
            FocusRow { id: targetRow; width: parent.width; title: "Edit target"; value: root.targetName(); theme: root.theme }
            FocusRow { id: fexRow; width: parent.width; title: "FEX preset"; value: root.fexLabel(String(root.effective("fexProfile") || "default")); theme: root.theme }
            FocusRow { id: fexTsoRow; width: parent.width; title: "TSO enabled"; value: root.fexConfig().TSOEnabled === "1" ? "On" : "Off"; theme: root.theme }
            FocusRow { id: fexX87Row; width: parent.width; title: "X87 reduced precision"; value: root.fexConfig().X87ReducedPrecision === "1" ? "On" : "Off"; theme: root.theme }
            FocusRow { id: fexMultiblockRow; width: parent.width; title: "Multiblock"; value: root.fexConfig().Multiblock === "1" ? "On" : "Off"; theme: root.theme }
            FocusRow { id: fexVectorRow; width: parent.width; title: "Vector TSO enabled"; value: root.fexConfig().VectorTSOEnabled === "1" ? "On" : "Off"; theme: root.theme }
            FocusRow { id: fexMemcpyRow; width: parent.width; title: "Memcpy TSO enabled"; value: root.fexConfig().MemcpySetTSOEnabled === "1" ? "On" : "Off"; theme: root.theme }
            FocusRow { id: fexBarrierRow; width: parent.width; title: "Half barrier TSO"; value: root.fexConfig().HalfBarrierTSOEnabled === "1" ? "On" : "Off"; theme: root.theme }
            FocusRow { id: thunkVulkanRow; width: parent.width; title: "Host Vulkan"; value: root.thunkValue("Vulkan") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: thunkGlRow; width: parent.width; title: "Host OpenGL"; value: root.thunkValue("GL") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: thunkAsoundRow; width: parent.width; title: "Host ALSA"; value: root.thunkValue("asound") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: thunkDrmRow; width: parent.width; title: "Host DRM"; value: root.thunkValue("drm") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: thunkWaylandRow; width: parent.width; title: "Host Wayland"; value: root.thunkValue("WaylandClient") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: cpuCoresRow; width: parent.width; title: "Game CPU cores"; value: root.optionLabel("cores", effective("cores")); theme: root.theme }
            FocusRow { id: cpuTopologyRow; width: parent.width; title: "Wine CPU topology"; value: root.boolValue("wineTopology"); theme: root.theme }
            FocusRow { id: niceRow; width: parent.width; title: "Game priority"; value: String(effective("nice") === undefined ? 0 : effective("nice")); theme: root.theme }
            FocusRow { id: gamescopeCoresRow; width: parent.width; title: "Gamescope CPU cores"; value: root.optionLabel("gamescopeCores", effective("gamescopeCores")); theme: root.theme }
            FocusRow { id: gamescopeNiceRow; width: parent.width; title: "Gamescope priority"; value: String(effective("gamescopeNice") === undefined ? 0 : effective("gamescopeNice")); theme: root.theme }
            FocusRow { id: gamescopeRealtimeRow; width: parent.width; title: "Gamescope realtime"; value: effective("gamescopeRr") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: schedulerRow; width: parent.width; title: "CPU scheduler"; value: root.schedulerValue(); theme: root.theme }
            FocusRow { id: reapplyRow; width: parent.width; title: "Re-apply to running game"; value: "A"; theme: root.theme; onActivated: root.reapply() }
            FocusRow { id: restartRow; width: parent.width; title: "Restart Game Mode"; value: "A"; theme: root.theme; onActivated: root.restartGameMode() }
            FocusRow { id: resetRow; width: parent.width; title: root.selectedAppid ? "Reset game settings" : "Reset all game settings"; value: "A"; theme: root.theme; onActivated: root.resetTarget() }
            FocusRow { id: saveRow; width: parent.width; title: root.dirty ? "Save changes *" : "Save changes"; value: "A"; theme: root.theme; onActivated: root.save() }
            Text { text: root.statusText; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
            Text { text: "Steam compatibility tool and resolution controls remain gated behind Steam's private API."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
        }
    }
}
