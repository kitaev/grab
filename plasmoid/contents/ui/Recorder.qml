// Client side of grabd (org.grab.Recorder1): mirrors its state into
// `streams` and `records` (ListModels updated in place, so open popups in
// delegates survive updates) and `inputs`, and wraps its methods.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: rec

    property string service: "org.grab.Recorder"
    property var bus: DBus.SessionBus      // (tests pass a fake)
    readonly property string path: "/org/grab/Recorder"
    readonly property string iface: "org.grab.Recorder1"

    readonly property bool available: watcher.registered
    // grabd.service on/off (systemd); while it is off nothing here calls grabd,
    // since any call would start it (D-Bus activation)
    readonly property Service control: Service {
        registered: watcher.registered
        bus: rec.bus
        onChecked: if (enabled && !rec.available) rec.refresh()   // starts grabd, as before
    }
    readonly property ListModel streams: ListModel {}   // available, recording, paused, encoding
    readonly property ListModel records: ListModel {}   // done, empty, failed
    readonly property int count: streams.count + records.count
    property var inputs: []                // [{name, description, default}]
    property string folder: ""             // grabd's recordings folder

    // Level meters (see ItemRow): grabd measures each stream at its outputs
    // while `monitoring` (the popup is open) and sends {item id: level}.
    property bool monitoring: false
    property var levels: ({})
    onMonitoringChanged: {
        if (available)                     // else: requested once grabd appears
            call("Meters", [monitoring]);
        if (!monitoring)
            levels = {};
    }
    readonly property var meterLease: Timer {   // grabd stops meters 5 s after the last call
        interval: 2000
        repeat: true
        running: rec.monitoring && rec.available
        onTriggered: rec.call("Meters", [true])
    }
    property int recordingCount: 0
    property int finishedCount: 0
    property int readyCount: 0             // saved recordings (done)
    property int busyCount: 0
    property int activeCount: 0            // recording, paused or encoding: disabling finishes them
    property var recordingTitles: []

    readonly property var finishedStates: ["done", "empty", "failed"]

    function isFinished(state) {
        return finishedStates.indexOf(state) >= 0;
    }

    // Plasma's D-Bus module wraps strings and doubles as {value: ...}.
    function plain(v) {
        return v !== null && typeof v === "object" && v.value !== undefined ? v.value : v;
    }

    function call(member, args, onReply) {
        rec.bus.asyncCall({service: rec.service, path: rec.path, iface: rec.iface,
                                   member: member, arguments: args || []},
            reply => { if (onReply) onReply(reply); },
            reply => console.warn("grab:", member, "failed:", reply.error.message));
    }

    function refresh() {
        call("GetState", [], reply => apply(String(plain(reply.value))));
    }

    function toggle(id) { call("Toggle", [id]); }
    function setInput(id, input) { call("SetInput", [id, input]); }
    function remove(id, withData) { call("Remove", [id, withData]); }
    function removeFinished(withData) { call("RemoveFinished", [withData]); }
    function saveNow(id) { call("SaveNow", [id]); }
    function setPlaybackMuted(id, muted) { call("SetPlaybackMuted", [id, muted]); }
    function setEchoCancel(id, on) { call("SetEchoCancel", [id, on]); }
    function removeRecord(id) { call("RemoveRecord", [id]); }

    // Share ▸ (KDE Purpose, like Dolphin's): FullView runs the plugin, showing
    // its settings if it needs any (e.g. which Bluetooth device).
    signal shareRequested(string file, string pluginId)

    // Removing files: to the Trash right away; deleted permanently (Shift held,
    // see ShiftMenu) after confirmRequested (FullView asks) calls proceed.
    signal confirmRequested(string title, string message, string action, var proceed)
    property var pendingConfirm: null      // the last request, until FullView takes it
    function confirm(title, message, action, proceed, icon) {
        pendingConfirm = {title: title, message: message, action: action, proceed: proceed,
                          icon: icon || "edit-delete"};
        confirmRequested(title, message, action, proceed);
    }

    // The tray menu's "Enable/Disable Recording Service" and the popup's
    // "Enable Recording Service": stopping grabd finishes
    // what is recording, so ask first then (FullView shows the question).
    signal attentionRequested()           // open the popup (for the question)
    function setEnabled(on) {
        if (on) {
            control.enable();
        } else if (activeCount > 0) {
            attentionRequested();
            confirm("Disable Recording Service?",
                    activeCount === 1 ? "The recording in progress will be finished and saved."
                                      : `The ${activeCount} recordings in progress will be finished and saved.`,
                    "Disable", () => control.disable(), "media-playback-stop");
        } else {
            control.disable();
        }
    }

    function discardRecording(id, title, permanently) {
        if (!permanently)
            removeRecord(id);
        else
            confirm("Delete Recording?",
                             `The recording of “${title}” will be stopped and deleted permanently.`,
                             "Delete", () => call("DeleteRecord", [id]));
    }
    function removeWithFile(id, title, permanently) {
        if (!permanently)
            remove(id, true);
        else
            confirm("Delete File?", `“${title}” will be deleted permanently.`,
                             "Delete", () => call("Delete", [id]));
    }
    function removeFinishedWithFiles(permanently) {
        if (!permanently) {
            removeFinished(true);
            return;
        }
        // exactly the recordings listed now: not ones that finish while the dialog is open
        const ids = [];
        for (let i = 0; i < records.count; i++)
            ids.push(records.get(i).itemId);
        const n = ids.length;
        confirm("Delete Files?",
                         `${n === 1 ? "The recording" : `All ${n} recordings`} in the list will be deleted permanently.`,
                         "Delete All", () => ids.forEach(id => call("Delete", [id])));
    }

    function apply(json) {
        let state;
        try {
            state = JSON.parse(json);
        } catch (e) {
            console.warn("grab: bad state", e);
            return;
        }
        inputs = state.inputs || [];
        folder = state.folder || "";
        // id and state can't be delegate property names in QML: expose them as itemId/itemState
        sync((state.items || []).map(it => {
            const row = Object.assign({}, it, {itemId: it.id, itemState: it.state,
                                               group: isFinished(it.state) ? "finished" : "live"});
            delete row.id;
            delete row.state;
            return row;
        }));
    }

    function clear() {
        streams.clear();
        records.clear();
        inputs = [];
        recordingCount = finishedCount = readyCount = busyCount = activeCount = 0;
        recordingTitles = [];
    }

    function sync(list) {
        syncModel(streams, list.filter(it => it.group === "live"));
        syncModel(records, list.filter(it => it.group === "finished"));
        recordingCount = list.filter(it => it.itemState === "recording").length;
        finishedCount = records.count;
        readyCount = list.filter(it => it.itemState === "done").length;
        busyCount = list.filter(it => it.itemState === "encoding" || it.busy).length;
        activeCount = list.filter(it => ["recording", "paused", "encoding"].indexOf(it.itemState) >= 0).length;
        recordingTitles = list.filter(it => it.itemState === "recording").map(it => it.title);
    }

    // Make `items` match `wanted` (in grabd's order): rows are updated, moved,
    // inserted and removed in place, matched by id.
    function syncModel(items, wanted) {
        const ids = new Set(wanted.map(it => it.itemId));
        for (let i = items.count - 1; i >= 0; i--) {
            if (!ids.has(items.get(i).itemId))
                items.remove(i);
        }
        for (let k = 0; k < wanted.length; k++) {
            const it = wanted[k];
            let idx = -1;
            for (let i = k; i < items.count; i++) {
                if (items.get(i).itemId === it.itemId) { idx = i; break; }
            }
            if (idx < 0) {
                items.insert(k, it);
                continue;
            }
            if (idx !== k)
                items.move(idx, k, 1);
            const row = items.get(k);
            for (const key in it) {
                if (row[key] !== it[key])
                    items.setProperty(k, key, it[key]);
            }
        }
    }

    readonly property var watcher: DBus.DBusServiceWatcher {
        busType: DBus.BusType.Session
        watchedService: rec.service
        onRegisteredChanged: {
            if (registered) {
                rec.refresh();
                if (rec.monitoring)            // grabd (re)started while the popup is open
                    rec.call("Meters", [true]);
            } else {
                rec.clear();
            }
        }
    }

    readonly property var signals: DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: rec.service
        path: rec.path
        iface: rec.iface
        function dbusStateChanged(json) {
            rec.apply(String(rec.plain(json)));
        }
        function dbusLevels(json) {
            if (rec.monitoring)
                rec.levels = JSON.parse(String(rec.plain(json)));
        }
    }

    // grabd is called (and so started) once control knows it is enabled: onChecked
}
