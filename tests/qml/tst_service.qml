// Enabling and disabling grabd through systemd (Service), with a fake bus:
// the calls made, their order, failures, and that nothing calls grabd (which
// would start it) while it is disabled.
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as W

Item {
    id: root

    QtObject {
        id: fakeBus
        property var calls: []             // [{member, args, service, resolve, reject}]
        property var unitState: "enabled"  // GetUnitFileState's answer, or {error}
        function asyncCall(msg, resolve, reject) {
            const c = {member: msg.member, args: msg.arguments, service: msg.service,
                       resolve: resolve, reject: reject};
            calls = calls.concat([c]);
            if (msg.member === "Subscribe")
                resolve({value: undefined});
            else if (msg.member === "GetUnitFileState")
                unitState.error ? reject({error: unitState.error}) : resolve({value: {value: unitState}});
        }
        function members() { return calls.map(c => c.member); }
        function last(member) {
            for (let i = calls.length - 1; i >= 0; i--)
                if (calls[i].member === member)
                    return calls[i];
            return null;
        }
        function ok(member) { last(member).resolve({value: undefined}); }
        function fail(member, message) {
            last(member).reject({error: {name: "org.freedesktop.DBus.Error.Failed", message: message}});
        }
    }

    Component {
        id: recorderComponent
        W.Recorder {
            service: "org.grab.RecorderTest"   // never on the bus: `available` stays false
            bus: fakeBus
        }
    }

    TestCase {
        name: "Service"

        function make(state) {
            fakeBus.calls = [];
            fakeBus.unitState = state;
            const rec = createTemporaryObject(recorderComponent, root);
            rec.control.startTimeoutMs = 200;
            tryVerify(() => rec.control.known);
            return rec;
        }
        function grabdCalls() {
            return fakeBus.calls.filter(c => c.service === "org.grab.RecorderTest").map(c => c.member);
        }

        function test_startsGrabdWhenEnabled() {
            make("enabled");
            tryVerify(() => grabdCalls().indexOf("GetState") >= 0, 1000, "activates grabd as before");
        }

        function test_disabledStaysOff() {
            const rec = make("masked");
            compare(rec.control.unitState, "disabled");
            wait(100);
            compare(grabdCalls(), [], "no call to grabd: it would start it");
        }

        function test_missing() {
            const rec = make({error: {name: "org.freedesktop.DBus.Error.FileNotFound",
                                      message: "No such file or directory"}});
            compare(rec.control.unitState, "missing");
            compare(grabdCalls(), []);
        }

        function test_enable() {
            const rec = make("masked");
            rec.setEnabled(true);
            compare(rec.control.transition, "starting");
            compare(fakeBus.last("UnmaskUnitFiles").args, [["grabd.service"], false]);
            fakeBus.ok("UnmaskUnitFiles");
            fakeBus.ok("Reload");
            compare(fakeBus.last("StartUnit").args, ["grabd.service", "replace"]);
            fakeBus.ok("StartUnit");
            compare(rec.control.transition, "starting", "until grabd is on the bus");
            rec.control.registered = true;
            compare(rec.control.transition, "");
            compare(rec.control.error, "");
        }

        function test_enableTimesOut() {
            const rec = make("masked");
            rec.setEnabled(true);
            fakeBus.ok("UnmaskUnitFiles");
            fakeBus.ok("Reload");
            fakeBus.ok("StartUnit");
            tryCompare(rec.control, "transition", "", 1000);
            verify(rec.control.error.indexOf("journalctl --user -u grabd") >= 0, rec.control.error);
        }

        function test_startFails() {
            const rec = make("enabled");
            rec.setEnabled(true);
            fakeBus.ok("UnmaskUnitFiles");
            fakeBus.ok("Reload");
            fakeBus.fail("StartUnit", "Unit grabd.service not found.");
            compare(rec.control.transition, "");
            compare(rec.control.error, "Couldn't start the recording service: Unit grabd.service not found.");
        }

        function test_disable() {
            const rec = make("enabled");
            rec.control.registered = true;
            rec.setEnabled(false);              // nothing recording: no question
            compare(rec.control.transition, "stopping");
            compare(fakeBus.last("MaskUnitFiles").args, [["grabd.service"], false, false],
                    "masked without force: never overwrites a user's unit file");
            fakeBus.unitState = "masked";       // as systemd reports it from now on
            fakeBus.ok("MaskUnitFiles");
            fakeBus.ok("Reload");
            compare(fakeBus.members().indexOf("StopUnit") > fakeBus.members().indexOf("MaskUnitFiles"),
                    true, "masked before it is stopped");
            fakeBus.ok("StopUnit");
            compare(rec.control.transition, "stopping", "until grabd has left the bus");
            rec.control.registered = false;
            compare(rec.control.transition, "");
            compare(rec.control.unitState, "disabled");
        }

        function test_maskFails() {
            const rec = make("enabled");
            rec.control.registered = true;
            rec.setEnabled(false);
            fakeBus.fail("MaskUnitFiles", "File exists");
            compare(rec.control.transition, "");
            compare(rec.control.error, "Couldn't disable the recording service: File exists");
            compare(fakeBus.last("StopUnit"), null, "not stopped");
        }

        function test_disableAsksWhileRecording() {
            const rec = make("enabled");
            rec.control.registered = true;
            rec.activeCount = 2;
            let asked = 0;
            rec.attentionRequested.connect(() => asked++);
            rec.setEnabled(false);
            compare(asked, 1, "opens the popup for the question");
            verify(rec.pendingConfirm !== null);
            compare(rec.pendingConfirm.title, "Disable Recording Service?");
            verify(rec.pendingConfirm.message.indexOf("2 recordings") >= 0);
            compare(fakeBus.last("MaskUnitFiles"), null, "nothing yet");
            rec.pendingConfirm.proceed();
            verify(fakeBus.last("MaskUnitFiles") !== null);
        }
    }
}
