// The popup: a Streams tab (what can be or is being recorded) and a Recordings
// tab (finished recordings), and a footer with the recordings folder and,
// on Recordings, Remove All Finished.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

ColumnLayout {
    id: view

    required property var recorder

    spacing: 0
    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    // sized for the longer list, so switching tabs doesn't resize the popup
    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 34,
                                     Math.max(Kirigami.Units.gridUnit * 12,
                                              Math.max(streamList.listHeight, recordList.listHeight)
                                              + tabs.implicitHeight + footer.implicitHeight
                                              + Kirigami.Units.largeSpacing * 2))

    readonly property bool onRecords: tabs.currentIndex === 1

    PlasmaComponents3.TabBar {
        id: tabs
        objectName: "tabs"
        Layout.fillWidth: true

        PlasmaComponents3.TabButton {
            text: "Streams"
        }
        PlasmaComponents3.TabButton {
            text: "Recordings"
        }
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabs.currentIndex

        ItemList {
            id: streamList
            recorder: view.recorder
            model: view.recorder.streams
            placeholderIcon: view.recorder.available ? "media-record" : "dialog-warning"
            placeholderText: view.recorder.available ? "No recordable streams" : "Recorder service not running"
            placeholderExplanation: view.recorder.available
                ? "Start playing audio in an application to record it."
                : "Start it with: systemctl --user start grabd"
        }

        ItemList {
            id: recordList
            recorder: view.recorder
            model: view.recorder.records
            placeholderIcon: view.recorder.available ? "audio-x-generic" : "dialog-warning"
            placeholderText: view.recorder.available ? "No recordings" : "Recorder service not running"
            placeholderExplanation: view.recorder.available
                ? "Finished recordings appear here."
                : "Start it with: systemctl --user start grabd"
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    RowLayout {
        id: footer
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.ToolButton {
            icon.name: "folder-music"
            text: "Open Recordings Folder"
            visible: view.recorder.folder !== ""
            onClicked: Qt.openUrlExternally("file://" + view.recorder.folder.split("/")
                                            .map(encodeURIComponent).join("/"))
        }

        Item { Layout.fillWidth: true }

        PlasmaComponents3.ToolButton {
            id: removeAllButton
            objectName: "removeAllButton"
            icon.name: "edit-clear-all"
            text: "Remove All Finished"
            visible: view.onRecords
            enabled: view.recorder.finishedCount > 0
            checkable: true
            checked: removeAllMenu.visible
            onClicked: removeAllMenu.popup(removeAllButton, 0, -removeAllMenu.implicitHeight)

            PlasmaComponents3.Menu {
                id: removeAllMenu
                PlasmaComponents3.MenuItem {
                    text: "Remove All Entries"
                    icon.name: "edit-clear-all"
                    onTriggered: view.recorder.removeFinished(false)
                }
                PlasmaComponents3.MenuItem {
                    text: "Remove All Entries and Data"
                    icon.name: "user-trash"
                    onTriggered: view.recorder.removeFinished(true)
                }
            }
        }
    }
}
