// Client side of grabd (org.grab.Recorder1): mirrors its state into `items`
// (a ListModel updated in place, so open popups in delegates survive updates)
// and `inputs`, and wraps its methods.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: rec

    property string service: "org.grab.Recorder"
    readonly property string path: "/org/grab/Recorder"
    readonly property string iface: "org.grab.Recorder1"

    readonly property bool available: watcher.registered
    readonly property ListModel items: ListModel {}
    property var inputs: []                // [{name, description, default}]
    property string folder: ""             // grabd's recordings folder
    property int recordingCount: 0
    property int finishedCount: 0
    property int busyCount: 0
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
        DBus.SessionBus.asyncCall({service: rec.service, path: rec.path, iface: rec.iface,
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
        items.clear();
        inputs = [];
        recordingCount = finishedCount = busyCount = 0;
        recordingTitles = [];
    }

    // Live items first, then finished ones, each in grabd's order. Rows are
    // updated, moved, inserted and removed in place, matched by id.
    function sync(list) {
        const wanted = list.filter(it => it.group === "live")
                           .concat(list.filter(it => it.group === "finished"));
        wanted.forEach((it, k) => {        // no separator after the last row of a section
            it.lastInGroup = k === wanted.length - 1 || wanted[k + 1].group !== it.group;
        });
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
        recordingCount = wanted.filter(it => it.itemState === "recording").length;
        finishedCount = wanted.filter(it => it.group === "finished").length;
        busyCount = wanted.filter(it => it.itemState === "encoding" || it.busy).length;
        recordingTitles = wanted.filter(it => it.itemState === "recording").map(it => it.title);
    }

    readonly property var watcher: DBus.DBusServiceWatcher {
        busType: DBus.BusType.Session
        watchedService: rec.service
        onRegisteredChanged: registered ? rec.refresh() : rec.clear()
    }

    readonly property var signals: DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: rec.service
        path: rec.path
        iface: rec.iface
        function dbusStateChanged(json) {
            rec.apply(String(rec.plain(json)));
        }
    }

    Component.onCompleted: refresh()
}
