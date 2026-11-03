// One grabd item: title and state, record/pause and file buttons, and the
// microphone combobox on the row below.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: row

    required property var recorder
    required property int index
    required property string itemId
    required property string title
    required property string itemState
    required property bool busy
    required property bool stream
    required property string input
    required property string input_description
    required property string file
    required property real duration
    required property string error

    readonly property bool finished: recorder.isFinished(itemState)
    readonly property bool controllable: ["available", "recording", "paused"].indexOf(itemState) >= 0

    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 2
    implicitWidth: column.implicitWidth

    function mmss(sec) {
        sec = Math.floor(sec);
        const two = n => String(n).padStart(2, "0");
        return sec >= 3600 ? `${Math.floor(sec / 3600)}:${two(Math.floor(sec / 60) % 60)}:${two(sec % 60)}`
                           : `${Math.floor(sec / 60)}:${two(sec % 60)}`;
    }

    readonly property string stateText: {
        let text = {
            "available": "Ready to record",
            "recording": "Recording",
            "paused": file ? `Paused · saved ${mmss(duration)}` : "Paused",
            "encoding": "Encoding…",
            "done": `Saved · ${mmss(duration)}`,
            "empty": "Nothing recorded",
            "failed": `Failed: ${error || "unknown error"}`,
        }[itemState] || itemState;
        if ((itemState === "done" || itemState === "empty") && error)
            text += ` · ${error}`;
        if (busy && (itemState === "recording" || itemState === "paused"))
            text += " · saving…";
        return text;
    }

    readonly property var toggleAction: ({
        "available": {text: "Record", icon: "media-record"},
        "recording": {text: "Pause", icon: "media-playback-pause"},
        "paused": {text: "Resume", icon: "media-record"},
    })[itemState] || {text: "Record", icon: "media-record"}

    // [{value, text}] for the combobox: None, Default, then every source.
    readonly property var inputChoices: {
        const def = recorder.inputs.find(i => i.default);
        return [{value: "", text: "None"},
                {value: "default", text: def ? `Default (${def.description})` : "Default"}]
            .concat(recorder.inputs.map(i => ({value: i.name, text: i.description})));
    }

    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function showInFolder() {
        DBus.SessionBus.asyncCall({service: "org.freedesktop.FileManager1",
                                   path: "/org/freedesktop/FileManager1",
                                   iface: "org.freedesktop.FileManager1", member: "ShowItems",
                                   arguments: [[fileUrl(file)], ""]},
            reply => {},
            reply => Qt.openUrlExternally(fileUrl(file.substring(0, file.lastIndexOf("/")))));
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            Rectangle {                    // red while recording
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Kirigami.Units.iconSizes.small / 2
                implicitHeight: implicitWidth
                radius: width / 2
                color: Kirigami.Theme.negativeTextColor
                visible: row.itemState === "recording"
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.title
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.weight: row.itemState === "recording" ? Font.DemiBold : Font.Normal
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.stateText
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    color: row.itemState === "failed" || row.error ? Kirigami.Theme.negativeTextColor
                                                               : Kirigami.Theme.textColor
                    opacity: row.itemState === "failed" || row.error ? 1 : 0.7
                }
            }

            PlasmaComponents3.ToolButton {
                objectName: "toggleButton"
                icon.name: row.toggleAction.icon
                text: row.toggleAction.text
                display: PlasmaComponents3.AbstractButton.IconOnly
                enabled: row.controllable && row.stream
                opacity: enabled ? 1 : 0.35
                onClicked: row.recorder.toggle(row.itemId)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.ToolButton {
                icon.name: "folder-open"
                text: "Show in folder"
                display: PlasmaComponents3.AbstractButton.IconOnly
                visible: row.file !== ""
                onClicked: row.showInFolder()
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.ToolButton {
                id: removeButton
                objectName: "removeButton"
                icon.name: "edit-delete-remove"
                text: "Remove"
                display: PlasmaComponents3.AbstractButton.IconOnly
                visible: row.finished
                checkable: true
                checked: removeMenu.visible
                onClicked: removeMenu.popup(removeButton, 0, removeButton.height)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered && !removeMenu.visible
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                PlasmaComponents3.Menu {
                    id: removeMenu
                    PlasmaComponents3.MenuItem {
                        text: "Remove Entry"
                        icon.name: "edit-clear"
                        onTriggered: row.recorder.remove(row.itemId, false)
                    }
                    PlasmaComponents3.MenuItem {
                        text: "Remove Entry and Data"
                        icon.name: "user-trash"
                        onTriggered: row.recorder.remove(row.itemId, true)
                    }
                }
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            Kirigami.Icon {
                source: "audio-input-microphone"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
                opacity: micBox.enabled ? 1 : 0.5
            }

            PlasmaComponents3.ComboBox {
                id: micBox
                objectName: "micBox"
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                model: row.inputChoices
                textRole: "text"
                valueRole: "value"
                enabled: row.controllable
                currentIndex: row.inputChoices.findIndex(c => c.value === row.input)
                displayText: currentIndex >= 0 ? currentText : row.input_description
                onActivated: index => {
                    row.recorder.setInput(row.itemId, row.inputChoices[index].value);
                    // selecting replaces the binding; restore it so grabd stays the source of truth
                    currentIndex = Qt.binding(() => row.inputChoices.findIndex(c => c.value === row.input));
                }
            }
        }
    }
}
