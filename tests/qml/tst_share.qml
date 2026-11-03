// A recording's Share ▸ submenu lists KDE Purpose's targets for an MP3, and
// choosing one asks the recorder to share that file with that plugin.
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as W

Item {
    id: root
    width: 600
    height: 400
    property var shared: []
    readonly property string file: "/tmp/grab test/2026-10-31_12-06-57_Смысл и #бессилие.mp3"

    QtObject {
        id: fakeRec
        property var inputs: []
        property var levels: ({})
        signal shareRequested(string file, string pluginId)
        onShareRequested: (file, pluginId) => root.shared = [file, pluginId]
        function isFinished(s) { return s === "done"; }
    }
    W.ItemRow {
        id: row
        width: 500
        recorder: fakeRec; index: 0; itemId: "run-7"; title: "Some recording"; app: "Firefox"
        itemState: "done"; busy: false; pending: false; muted: false; echo_cancel: true
        stream: false; input: ""; input_description: ""; file: root.file; duration: 60; error: ""
    }

    TestCase {
        name: "Share"
        when: windowShown

        function test_menu() {
            const more = findChild(row, "moreMenu");
            more.popup(root, 10, 10);
            tryCompare(more, "opened", true);
            const share = findChild(row, "shareMenu");
            tryVerify(() => share.count > 0, 2000, "Purpose offers share targets");
            const labels = [];
            for (let i = 0; i < share.count; i++)
                labels.push(share.itemAt(i).text);
            console.log("Share ▸", JSON.stringify(labels));
            share.itemAt(0).triggered();
            compare(root.shared[0], root.file);
            verify(root.shared[1] !== "", "a plugin id");
        }
    }
}
