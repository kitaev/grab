// Turns grabd on and off through systemd's user manager (D-Bus,
// org.freedesktop.systemd1). Disabling stops grabd.service and masks it, like
// `systemctl --user mask --now grabd`: nothing starts it again, not the
// widget's D-Bus calls (activation), nor login if it is enabled there,
// until it is enabled here (unmasked and started) or with systemctl.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: svc

    property string unit: "grabd.service"
    property bool registered: false        // grabd is on the bus (Recorder's watcher)
    property var bus: DBus.SessionBus      // (tests pass a fake)
    property int startTimeoutMs: 15000

    // "" until known, then "enabled", "disabled" (masked) or "missing" (no unit:
    // not installed)
    property string unitState: ""
    property string transition: ""         // "starting" or "stopping" while it is
    property string error: ""              // the last failure, shown until the next try

    readonly property bool known: unitState !== ""
    readonly property bool enabled: unitState === "enabled"
    readonly property bool busy: transition !== ""

    // `known` turned true the first time: the Recorder may activate grabd now if enabled
    signal checked()

    function plain(v) {
        return v !== null && typeof v === "object" && v.value !== undefined ? v.value : v;
    }

    // Promise-style call to the systemd user manager; onError gets the message.
    function call(member, args, onReply, onError) {
        bus.asyncCall({service: "org.freedesktop.systemd1",
                                   path: "/org/freedesktop/systemd1",
                                   iface: "org.freedesktop.systemd1.Manager",
                                   member: member, arguments: args || []},
            reply => { if (onReply) onReply(reply.value); },
            reply => {
                const e = reply.error;
                if (onError)
                    onError(e.message || e.name || "unknown error", e.name || "");
                else
                    console.warn("grab: systemd", member, "failed:", e.name, e.message);
            });
    }

    function check() {
        const first = !known;
        call("GetUnitFileState", [unit], state => {
            state = String(plain(state));
            unitState = state.startsWith("masked") ? "disabled" : "enabled";
            if (first)
                checked();
        }, (message, name) => {
            // no unit file: the package isn't installed (or a broken unit)
            unitState = name.endsWith("FileNotFound") || name.endsWith("NoSuchUnit")
                ? "missing" : "enabled";
            if (unitState !== "missing")
                console.warn("grab: can't read", unit, "state:", message);
            if (first)
                checked();
        });
    }

    function fail(message) {
        transition = "";
        startTimeout.stop();
        error = message;
        check();
    }

    function enable() {
        if (busy)
            return;
        error = "";
        transition = "starting";
        // unmask (a no-op if it isn't masked), reload, start; then wait for it on the bus
        call("UnmaskUnitFiles", [[unit], false], () => {
            call("Reload", [], () => {
                unitState = "enabled";
                call("StartUnit", [unit, "replace"], () => {
                    if (registered)
                        transition = "";
                    else
                        startTimeout.restart();
                }, message => fail(`Couldn't start the recorder: ${message}`));
            }, message => fail(`Couldn't reload the user services: ${message}`));
        }, message => fail(`Couldn't enable the recorder: ${message}`));
    }

    function disable() {
        if (busy)
            return;
        error = "";
        transition = "stopping";
        // mask first, so nothing starts it again while it stops (it finishes its
        // recordings, which can take a while: TimeoutStopSec)
        call("MaskUnitFiles", [[unit], false, false], () => {
            call("Reload", [], () => {
                unitState = "disabled";
                call("StopUnit", [unit, "replace"], () => {
                    if (!registered)
                        transition = "";
                }, message => fail(`Couldn't stop the recorder: ${message}`));
            }, message => fail(`Couldn't reload the user services: ${message}`));
        }, message => fail(
            // e.g. ~/.config/systemd/user/grabd.service is a real file (an override)
            `Couldn't disable the recorder: ${message}`));
    }

    onRegisteredChanged: {
        if (registered && transition === "starting") {
            transition = "";
            startTimeout.stop();
        } else if (!registered && transition === "stopping") {
            transition = "";
        }
        if (registered)
            error = "";
        check();                           // started or stopped with systemctl, perhaps
    }

    readonly property var startTimeout: Timer {
        interval: svc.startTimeoutMs
        onTriggered: svc.fail("The recorder didn't start. To see why, run: "
                              + "journalctl --user -u grabd")
    }

    // systemctl mask/unmask/enable/disable from elsewhere: systemd signals
    // UnitFilesChanged to subscribed clients
    readonly property var unitFiles: DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.freedesktop.systemd1"
        path: "/org/freedesktop/systemd1"
        iface: "org.freedesktop.systemd1.Manager"
        function dbusUnitFilesChanged() {
            svc.check();
        }
    }

    Component.onCompleted: {
        call("Subscribe", [], null, () => {});   // "already subscribed" is fine
        check();
    }
}
