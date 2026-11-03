// One grabd item: the status line, then record/pause (or, for a recording, a
// file icon) left of the title with file buttons on the right, and for
// streams that can be recorded the microphone combobox below.
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
    required property string app
    required property string itemState
    required property bool busy
    required property bool pending
    required property bool stream
    required property string input
    required property string input_description
    required property string file
    required property real duration
    required property string error

    readonly property bool finished: recorder.isFinished(itemState)
    // clicked: set on click until grabd reports the toggle (pending) or a new state,
    // so the button reacts at once; the timer covers a click grabd never answers
    property bool clicked: false
    readonly property bool toggling: pending || clicked
    onPendingChanged: clicked = false
    onItemStateChanged: clicked = false
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
            "done": (app ? `Saved from ${app}` : "Saved") + ` · ${mmss(duration)}`,
            "empty": "Nothing recorded",
            "failed": `Failed: ${error || "unknown error"}`,
        }[itemState] || itemState;
        if (error && itemState !== "failed")     // failed already says why
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

        PlasmaComponents3.Label {          // status, above the title and starting where it starts
            objectName: "statusLabel"
            Layout.fillWidth: true
            Layout.leftMargin: lead.implicitWidth + Kirigami.Units.smallSpacing
            Layout.bottomMargin: -Kirigami.Units.smallSpacing
            horizontalAlignment: Text.AlignLeft
            text: row.stateText
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            color: row.itemState === "failed" || row.error ? Kirigami.Theme.negativeTextColor
                                                       : Kirigami.Theme.textColor
            opacity: row.itemState === "failed" || row.error ? 1 : 0.7
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            Item {                         // record/pause for streams, a file icon for recordings
                id: lead
                Layout.alignment: Qt.AlignTop
                implicitWidth: toggleButton.implicitWidth
                implicitHeight: toggleButton.implicitHeight

                PlasmaComponents3.ToolButton {
                    id: toggleButton
                    objectName: "toggleButton"
                    anchors.fill: parent
                    visible: !row.finished
                    icon.name: row.toggling ? "" : row.toggleAction.icon   // spinner shows instead
                    icon.width: Kirigami.Units.iconSizes.smallMedium
                    icon.height: Kirigami.Units.iconSizes.smallMedium
                    text: row.toggleAction.text
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    enabled: row.controllable && row.stream && !row.toggling
                    opacity: enabled || row.toggling ? 1 : 0.35
                    onClicked: {
                        row.clicked = true;
                        clickTimeout.restart();
                        row.recorder.toggle(row.itemId);
                    }
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                PlasmaComponents3.BusyIndicator {
                    objectName: "toggleBusy"
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    visible: row.toggling
                    running: visible
                }

                Timer {
                    id: clickTimeout
                    interval: 3000
                    onTriggered: row.clicked = false
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    visible: row.finished
                    source: row.itemState === "failed" ? "dialog-error" : "audio-x-generic"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                }
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.title
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.weight: row.itemState === "recording" ? Font.DemiBold : Font.Normal
                }
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

        RowLayout {                        // only for streams that can still be recorded
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            Layout.leftMargin: lead.implicitWidth + Kirigami.Units.smallSpacing   // under the title
            visible: row.controllable

            Kirigami.Icon {
                source: "audio-input-microphone"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
            }

            PlasmaComponents3.ComboBox {
                id: micBox
                objectName: "micBox"
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                model: row.inputChoices
                textRole: "text"
                valueRole: "value"
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
