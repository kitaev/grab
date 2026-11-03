// "Delete All" (Shift) asks first, and counts the recordings listed then.
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as W

Item {
    property var asked: null

    W.Recorder {
        id: rec
        service: "org.grab.Test.NotRunning"     // never reaches a real grabd
    }
    Connections {
        target: rec
        function onConfirmRequested(title, message, action, proceed) { asked = [message, proceed]; }
    }

    TestCase {
        name: "DeleteAll"

        function test_listedOnly() {
            rec.records.append({itemId: "r-1", title: "a"});
            rec.records.append({itemId: "r-2", title: "b"});
            rec.removeFinishedWithFiles(true);
            verify(asked, "asks before deleting");
            compare(asked[0], "All 2 recordings in the list will be deleted permanently.");
            rec.records.append({itemId: "r-3", title: "c"});   // finishes while the dialog is open
            asked[1]();                                         // proceeds without throwing
        }
    }
}
