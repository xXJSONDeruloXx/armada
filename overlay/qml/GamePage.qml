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
    property bool coresCustom: false
    property bool gamescopeCoresCustom: false
    property string customCoresText: ""
    property string customGamescopeCoresText: ""
    property bool environmentMode: false
    property var environmentEntries: []
    property int environmentIndex: -1
    property string environmentOriginalKey: ""
    property string environmentKeyText: ""
    property string environmentValueText: ""
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
        result.sort(function(a, b) {
            if (a.appid === "") return -1;
            if (b.appid === "") return 1;
            return a.name.localeCompare(b.name);
        });
        return result;
    }
    function targetName() {
        var match = games().filter(function(game) { return game.appid === selectedAppid; });
        return match.length ? match[0].name : "Default";
    }
    function targetDisplay() {
        if (selectedAppid) return targetName();
        var running = armada.config.game || {};
        return running.name ? "Default · " + running.name : "Default";
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
    function environmentKeys() {
        var keys = {};
        var global = (draftTweaks.global || {}).env || {};
        var own = (selectedAppid ? ownSettings() : draftTweaks.global || {}).env || {};
        Object.keys(global).forEach(function(key) { keys[key] = true; });
        Object.keys(own).forEach(function(key) { keys[key] = true; });
        return Object.keys(keys).sort();
    }
    function effectiveEnvironmentValue(key) {
        var own = ownSettings().env || {};
        if (Object.prototype.hasOwnProperty.call(own, key)) return own[key] === null ? "" : String(own[key]);
        return String(((draftTweaks.global || {}).env || {})[key] || "");
    }
    function openEnvironmentEditor() {
        environmentMode = true;
        focusIndex = 0;
        environmentEntries = environmentKeys();
        environmentIndex = environmentEntries.length ? 0 : -1;
        loadEnvironmentEntry();
        rebuildRows();
    }
    function loadEnvironmentEntry() {
        environmentOriginalKey = environmentIndex >= 0 ? environmentEntries[environmentIndex] : "";
        environmentKeyText = environmentOriginalKey;
        environmentValueText = environmentOriginalKey ? effectiveEnvironmentValue(environmentOriginalKey) : "";
        if (environmentKeyField) environmentKeyField.text = environmentKeyText;
        if (environmentValueField) environmentValueField.text = environmentValueText;
    }
    function updateEnvironmentEntries() {
        environmentEntries = environmentKeys();
        if (environmentOriginalKey) {
            var nextIndex = environmentEntries.indexOf(environmentOriginalKey);
            environmentIndex = nextIndex;
        }
        if (environmentIndex < 0 && environmentEntries.length) environmentIndex = 0;
        loadEnvironmentEntry();
    }
    function saveEnvironmentEntry() {
        var key = String(environmentKeyField.text || "").trim();
        var value = String(environmentValueField.text || "");
        if (!key || key.indexOf("=") >= 0 || key.indexOf("\u0000") >= 0) {
            statusText = "Invalid variable name";
            return;
        }
        var next = clone(draftTweaks);
        var target = selectedAppid ? ((next.games || {})[selectedAppid] || {name: targetName()}) : (next.global || {});
        if (selectedAppid) {
            if (!next.games) next.games = {};
            next.games[selectedAppid] = target;
        } else {
            next.global = target;
        }
        var env = target.env || {};
        if (environmentOriginalKey && environmentOriginalKey !== key) delete env[environmentOriginalKey];
        env[key] = value;
        target.env = env;
        draftTweaks = next;
        dirty = true;
        environmentOriginalKey = key;
        environmentKeyText = key;
        environmentValueText = value;
        updateEnvironmentEntries();
        statusText = "Variable staged";
    }
    function deleteEnvironmentEntry() {
        var key = environmentOriginalKey || String(environmentKeyField.text || "").trim();
        if (!key) return;
        var next = clone(draftTweaks);
        var target = selectedAppid ? ((next.games || {})[selectedAppid] || {name: targetName()}) : (next.global || {});
        if (selectedAppid && !Object.prototype.hasOwnProperty.call(target.env || {}, key)) {
            if (!target.env) target.env = {};
            target.env[key] = null;
        } else {
            var env = target.env || {};
            delete env[key];
            if (Object.keys(env).length) target.env = env;
            else delete target.env;
        }
        if (selectedAppid) {
            if (!next.games) next.games = {};
            next.games[selectedAppid] = target;
        } else {
            next.global = target;
        }
        draftTweaks = next;
        dirty = true;
        updateEnvironmentEntries();
        statusText = "Variable deleted; save to apply";
    }
    function newEnvironmentEntry() {
        environmentIndex = -1;
        environmentOriginalKey = "";
        environmentKeyText = "";
        environmentValueText = "";
        environmentKeyField.text = "";
        environmentValueField.text = "";
        environmentKeyField.forceActiveFocus();
    }
    function closeEnvironmentEditor() {
        environmentMode = false;
        rebuildRows();
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
    function fexValue(key) { return fexConfig()[key] === "1" ? "On" : "Off"; }
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
    function thunkDisplay(key) { return thunkValue(key) ? "On" : "Off"; }
    function toggleThunk(key) {
        var next = clone(effective("thunks") || {});
        next[key] = !thunkValue(key);
        setSetting("thunks", next);
    }
    function optionValues(key) {
        var result = ["default"];
        (armada.config.perf && armada.config.perf.corePresets || []).forEach(function(item) { result.push(item.data); });
        result.push("custom");
        return result;
    }
    function optionLabel(key, value) {
        if (!value || value === "default") return "Default";
        if (value === "custom") return "Custom";
        var options = armada.config.perf && armada.config.perf.corePresets || [];
        var match = options.filter(function(item) { return item.data === value; });
        return match.length ? match[0].label : value;
    }
    function cycleOption(key, direction) {
        var values = optionValues(key);
        var current = String(effective(key) || "default");
        var index = values.indexOf(current);
        var next = values[(index + direction + values.length) % values.length];
        var custom = next === "custom";
        if (key === "cores") coresCustom = custom;
        else gamescopeCoresCustom = custom;
        setSetting(key, custom ? (key === "cores" ? customCoresText : customGamescopeCoresText) : (next === "default" ? undefined : next));
        rebuildRows();
    }
    function cpulistError(text) {
        var seen = {};
        var count = Number(armada.config.perf && armada.config.perf.cpuCount || 0);
        var found = 0;
        var parts = String(text || "").split(",");
        function isDigits(value) { return /^[0-9]+$/.test(value); }
        for (var i = 0; i < parts.length; i++) {
            var item = parts[i].trim();
            if (!item) continue;
            var range = item.split("-");
            if (range.length > 2 || !isDigits(range[0]) || (range.length === 2 && !isDigits(range[1]))) return "Invalid entry: " + item;
            var low = Number(range[0]);
            var high = range.length === 2 ? Number(range[1]) : low;
            if (high < low) return "Invalid range: " + item;
            for (var cpu = low; cpu <= high; cpu++) {
                if (count && cpu >= count) return "No such CPU: " + cpu;
                if (seen[cpu]) return "Duplicate CPU: " + cpu;
                seen[cpu] = true;
                found++;
            }
        }
        return found ? "" : "Enter cores, e.g. 7,3-6";
    }
    function commitCustomCores(key, text) {
        var error = cpulistError(text);
        if (error) {
            statusText = error;
            return;
        }
        if (key === "cores") customCoresText = text.trim();
        else customGamescopeCoresText = text.trim();
        setSetting(key, text.trim());
        statusText = "Custom core list staged";
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
        var coreValue = String(effective("cores") || "");
        var gamescopeCoreValue = String(effective("gamescopeCores") || "");
        coresCustom = coreValue !== "" && optionValues("cores").indexOf(coreValue) < 0;
        gamescopeCoresCustom = gamescopeCoreValue !== "" && optionValues("gamescopeCores").indexOf(gamescopeCoreValue) < 0;
        customCoresText = coresCustom ? coreValue : "";
        customGamescopeCoresText = gamescopeCoresCustom ? gamescopeCoreValue : "";
        rebuildRows();
    }
    function rebuildRows() {
        if (environmentMode) {
            rows = [environmentKeyRow, environmentValueRow, environmentSaveRow, environmentDeleteRow, environmentNewRow, environmentBackRow];
            rows.forEach(function(item, index) { item.selected = index === focusIndex; });
            return;
        }
        var nextRows = [targetRow, fexRow, fexTsoRow, fexX87Row, fexMultiblockRow, fexVectorRow, fexMemcpyRow,
            fexBarrierRow, thunkVulkanRow, thunkGlRow, thunkAsoundRow, thunkDrmRow, thunkWaylandRow, cpuCoresRow];
        if (coresCustom) nextRows.push(coreTextRow);
        nextRows.push(cpuTopologyRow, niceRow, gamescopeCoresRow);
        if (gamescopeCoresCustom) nextRows.push(gamescopeCoreTextRow);
        nextRows.push(gamescopeNiceRow, gamescopeRealtimeRow, schedulerRow, environmentRow, reapplyRow, restartRow, resetRow, saveRow);
        rows = nextRows;
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function handleAction(action) {
        if (environmentMode) {
            handleEnvironmentAction(action);
            return;
        }
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
            else if (row === coreTextRow) statusText = "Press A to edit the custom CPU list";
            else if (row === cpuTopologyRow) setSetting("wineTopology", effective("wineTopology") === false ? undefined : false);
            else if (row === niceRow) adjust("nice", direction, -20, 19);
            else if (row === gamescopeCoresRow) cycleOption("gamescopeCores", direction);
            else if (row === gamescopeCoreTextRow) statusText = "Press A to edit the custom Gamescope CPU list";
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
            if (row === coreTextRow) coreField.forceActiveFocus();
            else if (row === gamescopeCoreTextRow) gamescopeCoreField.forceActiveFocus();
            else if (row === environmentRow) openEnvironmentEditor();
            else if (row === reapplyRow) reapply();
            else if (row === restartRow) restartGameMode();
            else if (row === resetRow) resetTarget();
            else if (row === saveRow) save();
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function schedulerValue() { return String(effective("scheduler") || "default").toUpperCase(); }
    function boolValue(key) { return effective(key) === false ? "Off" : "On"; }
    function handleEnvironmentAction(action) {
        var row = rows[focusIndex];
        if (action === "up") focusIndex = Math.max(0, focusIndex - 1);
        else if (action === "down") focusIndex = Math.min(rows.length - 1, focusIndex + 1);
        else if (action === "left" || action === "right") {
            var direction = action === "right" ? 1 : -1;
            if (row === environmentKeyRow && environmentEntries.length) {
                environmentIndex = (environmentIndex + direction + environmentEntries.length) % environmentEntries.length;
                loadEnvironmentEntry();
            }
        } else if (action === "accept") {
            if (row === environmentKeyRow) {
                environmentKeyField.focus = true;
            } else if (row === environmentValueRow) {
                environmentValueField.focus = true;
            } else if (row === environmentSaveRow) {
                saveEnvironmentEntry();
            } else if (row === environmentDeleteRow) {
                deleteEnvironmentEntry();
            } else if (row === environmentNewRow) {
                newEnvironmentEntry();
            } else if (row === environmentBackRow) {
                closeEnvironmentEditor();
            }
        }
        rows.forEach(function(item, index) { item.selected = index === focusIndex; });
    }
    function handleBack() {
        if (!environmentMode) return false;
        closeEnvironmentEditor();
        return true;
    }

    Connections { target: armada; function onConfigChanged() { root.sync(); } }
    Component.onCompleted: {
        fexKnobRows = [fexTsoRow, fexX87Row, fexMultiblockRow, fexVectorRow, fexMemcpyRow, fexBarrierRow];
        thunkRows = [thunkVulkanRow, thunkGlRow, thunkAsoundRow, thunkDrmRow, thunkWaylandRow];
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
            FocusRow { id: targetRow; width: parent.width; title: "Edit target"; value: root.targetDisplay(); theme: root.theme }
            Text { text: armada.config.game && armada.config.game.name ? "Running: " + armada.config.game.name : "No tracked game"; color: theme.muted; font.pixelSize: theme.bodySize; width: parent.width; elide: Text.ElideRight }
            FocusRow { id: fexRow; width: parent.width; title: "FEX preset"; value: root.fexLabel(String(root.effective("fexProfile") || "default")); theme: root.theme }
            FocusRow { id: fexTsoRow; width: parent.width; title: "TSO enabled"; value: root.fexValue("TSOEnabled"); theme: root.theme }
            FocusRow { id: fexX87Row; width: parent.width; title: "X87 reduced precision"; value: root.fexValue("X87ReducedPrecision"); theme: root.theme }
            FocusRow { id: fexMultiblockRow; width: parent.width; title: "Multiblock"; value: root.fexValue("Multiblock"); theme: root.theme }
            FocusRow { id: fexVectorRow; width: parent.width; title: "Vector TSO enabled"; value: root.fexValue("VectorTSOEnabled"); theme: root.theme }
            FocusRow { id: fexMemcpyRow; width: parent.width; title: "Memcpy TSO enabled"; value: root.fexValue("MemcpySetTSOEnabled"); theme: root.theme }
            FocusRow { id: fexBarrierRow; width: parent.width; title: "Half barrier TSO"; value: "On"; theme: root.theme }
            FocusRow { id: thunkVulkanRow; width: parent.width; title: "Host Vulkan"; value: root.thunkDisplay("Vulkan"); theme: root.theme }
            FocusRow { id: thunkGlRow; width: parent.width; title: "Host OpenGL"; value: root.thunkDisplay("GL"); theme: root.theme }
            FocusRow { id: thunkAsoundRow; width: parent.width; title: "Host ALSA"; value: root.thunkDisplay("asound"); theme: root.theme }
            FocusRow { id: thunkDrmRow; width: parent.width; title: "Host DRM"; value: root.thunkDisplay("drm"); theme: root.theme }
            FocusRow { id: thunkWaylandRow; width: parent.width; title: "Host Wayland"; value: root.thunkDisplay("WaylandClient"); theme: root.theme }
            FocusRow { id: cpuCoresRow; width: parent.width; title: "Game CPU cores"; value: root.coresCustom ? "Custom" : root.optionLabel("cores", effective("cores")); theme: root.theme }
            FocusRow { id: coreTextRow; visible: root.coresCustom; width: parent.width; title: "Custom game CPU list"; value: root.customCoresText || "Edit"; theme: root.theme; onActivated: coreField.forceActiveFocus() }
            TextField { id: coreField; visible: root.coresCustom; width: parent.width; text: root.customCoresText; placeholderText: "e.g. 7,3-6"; onEditingFinished: root.commitCustomCores("cores", text) }
            FocusRow { id: cpuTopologyRow; width: parent.width; title: "Wine CPU topology"; value: root.boolValue("wineTopology"); theme: root.theme }
            FocusRow { id: niceRow; width: parent.width; title: "Game priority"; value: String(effective("nice") === undefined ? 0 : effective("nice")); theme: root.theme }
            FocusRow { id: gamescopeCoresRow; width: parent.width; title: "Gamescope CPU cores"; value: root.gamescopeCoresCustom ? "Custom" : root.optionLabel("gamescopeCores", effective("gamescopeCores")); theme: root.theme }
            FocusRow { id: gamescopeCoreTextRow; visible: root.gamescopeCoresCustom; width: parent.width; title: "Custom Gamescope CPU list"; value: root.customGamescopeCoresText || "Edit"; theme: root.theme; onActivated: gamescopeCoreField.forceActiveFocus() }
            TextField { id: gamescopeCoreField; visible: root.gamescopeCoresCustom; width: parent.width; text: root.customGamescopeCoresText; placeholderText: "e.g. 7,3-6"; onEditingFinished: root.commitCustomCores("gamescopeCores", text) }
            FocusRow { id: gamescopeNiceRow; width: parent.width; title: "Gamescope priority"; value: String(effective("gamescopeNice") === undefined ? 0 : effective("gamescopeNice")); theme: root.theme }
            FocusRow { id: gamescopeRealtimeRow; width: parent.width; title: "Gamescope realtime"; value: effective("gamescopeRr") ? "On" : "Off"; theme: root.theme }
            FocusRow { id: schedulerRow; width: parent.width; title: "CPU scheduler"; value: root.schedulerValue(); theme: root.theme }
            FocusRow { id: environmentRow; width: parent.width; title: "Environment variables"; value: root.environmentKeys().length + " advanced"; theme: root.theme; onActivated: root.openEnvironmentEditor() }
            FocusRow { id: reapplyRow; width: parent.width; title: "Re-apply to running game"; value: "A"; theme: root.theme; onActivated: root.reapply() }
            FocusRow { id: restartRow; width: parent.width; title: "Restart Game Mode"; value: "A"; theme: root.theme; onActivated: root.restartGameMode() }
            FocusRow { id: resetRow; width: parent.width; title: root.selectedAppid ? "Reset game settings" : "Reset all game settings"; value: "A"; theme: root.theme; onActivated: root.resetTarget() }
            FocusRow { id: saveRow; width: parent.width; title: root.dirty ? "Save changes *" : "Save changes"; value: "A"; theme: root.theme; onActivated: root.save() }
            Text { text: root.statusText; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
            Text { text: "Steam compatibility tool and resolution controls remain gated behind Steam's private API."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
        }
    }

    Rectangle {
        visible: root.environmentMode
        anchors.fill: parent
        color: theme.panel
        z: 10
        Column {
            anchors.fill: parent
            spacing: theme.spacing
            Text { text: "Environment variables"; color: theme.text; font.pixelSize: theme.pageTitleSize }
            Text { text: "Advanced editor; keyboard entry may be required."; color: theme.muted; font.pixelSize: theme.bodySize; wrapMode: Text.WordWrap; width: parent.width }
            FocusRow { id: environmentKeyRow; width: parent.width; title: "Name"; value: root.environmentKeyText || "New variable"; theme: root.theme; onActivated: environmentKeyField.forceActiveFocus() }
            TextField { id: environmentKeyField; width: parent.width; text: root.environmentKeyText; placeholderText: "Variable name" }
            FocusRow { id: environmentValueRow; width: parent.width; title: "Value"; value: root.environmentValueText || "Empty"; theme: root.theme; onActivated: environmentValueField.forceActiveFocus() }
            TextField { id: environmentValueField; width: parent.width; text: root.environmentValueText; placeholderText: "Variable value" }
            FocusRow { id: environmentSaveRow; width: parent.width; title: "Save variable"; value: "A"; theme: root.theme; onActivated: root.saveEnvironmentEntry() }
            FocusRow { id: environmentDeleteRow; width: parent.width; title: "Delete variable"; value: "A"; theme: root.theme; onActivated: root.deleteEnvironmentEntry() }
            FocusRow { id: environmentNewRow; width: parent.width; title: "New variable"; value: "A"; theme: root.theme; onActivated: root.newEnvironmentEntry() }
            FocusRow { id: environmentBackRow; width: parent.width; title: "Back"; value: "B"; theme: root.theme; onActivated: root.closeEnvironmentEditor() }
        }
    }
}
