// The popup: live streams first, then finished recordings, and a footer with
// the recordings folder and Remove All Finished.
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
    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 34,
                                     Math.max(Kirigami.Units.gridUnit * 12,
                                              list.contentHeight + footer.implicitHeight
                                              + Kirigami.Units.largeSpacing * 2))

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            id: list
            objectName: "itemList"
            clip: true
            model: view.recorder.items
            reuseItems: false
            boundsBehavior: Flickable.StopAtBounds

            section.property: "group"
            section.criteria: ViewSection.FullString
            section.delegate: PlasmaExtras.ListSectionHeader {
                required property string section
                width: ListView.view.width
                text: section === "finished" ? "Finished" : "Streams"
            }

            delegate: ColumnLayout {
                id: entry
                required property int index
                required property var model
                width: ListView.view.width
                spacing: 0

                ItemRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    recorder: view.recorder
                    index: entry.index
                    itemId: entry.model.itemId
                    title: entry.model.title
                    itemState: entry.model.itemState
                    busy: entry.model.busy
                    pending: entry.model.pending
                    stream: entry.model.stream
                    input: entry.model.input
                    input_description: entry.model.input_description
                    file: entry.model.file
                    duration: entry.model.duration
                    error: entry.model.error
                }
                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: entry.index < list.count - 1
                    opacity: 0.5
                }
            }

            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: list.count === 0
                iconName: view.recorder.available ? "media-record" : "dialog-warning"
                text: view.recorder.available ? "No recordable streams" : "Recorder service not running"
                explanation: view.recorder.available
                    ? "Start playing audio in an application to record it."
                    : "Start it with: systemctl --user start grabd"
            }
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
