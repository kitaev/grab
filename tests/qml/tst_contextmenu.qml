// Right-clicking an entry opens its "⋮" menu: the stream menu for a stream,
// the recording menu for a recording.
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as W

Item {
    id: root
    width: 600
    height: 400

    QtObject {
        id: fakeRec
        property var inputs: []
        property var levels: ({})
        property bool monitoring: false
        signal shareRequested(string file, string pluginId)
        function isFinished(s) { return s === "done"; }
    }
    W.ItemRow {
        id: streamRow
        width: 500
        recorder: fakeRec; index: 0; itemId: "run-1"; title: "Some stream"; app: "Firefox"
        itemState: "available"; busy: false; pending: false; muted: false; echo_cancel: true
        stream: true; input: ""; input_description: ""; file: ""; duration: 0; error: ""
    }
    W.ItemRow {
        id: recordRow
        y: 150
        width: 500
        recorder: fakeRec; index: 1; itemId: "run-2"; title: "Some recording"; app: "Firefox"
        itemState: "done"; busy: false; pending: false; muted: false; echo_cancel: true
        stream: false; input: ""; input_description: ""; file: "/tmp/x.mp3"; duration: 60; error: ""
    }

    TestCase {
        name: "ContextMenu"
        when: windowShown

        function rightClickOpens(row, menuName, other) {
            // on the title, not on a button
            mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton);
            const menu = findChild(row, menuName);
            tryCompare(menu, "opened", true);
            verify(!findChild(row, other).visible, "only the entry's own menu");
            menu.close();
            tryCompare(menu, "visible", false);
        }

        function test_stream() { rightClickOpens(streamRow, "streamMenu", "moreMenu"); }
        function test_recording() { rightClickOpens(recordRow, "moreMenu", "streamMenu"); }

        function test_leftClickDoesNot() {
            mouseClick(recordRow, recordRow.width / 2, recordRow.height / 2, Qt.LeftButton);
            wait(100);
            verify(!findChild(recordRow, "moreMenu").visible);
        }
    }
}
