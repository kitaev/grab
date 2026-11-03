// One grabd item: the status line, then record/pause (or, for a recording, a
// file icon) left of the title and a "⋮" actions menu on the right. Streams'
// menu: Microphone (the input mixed in), Save Now, Show in Folder, Remove
// Record; recordings': Show in Folder, Remove Entry (and Data). The status
// line names the selected input.
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
    readonly property bool active: itemState === "recording" || itemState === "paused"

    implicitHeight: column.implicitHeight + column.anchors.topMargin + column.anchors.bottomMargin

    // Buttons are taller than a text line: shift them up so they are centred on
    // the title's first line rather than hanging below it.
    FontMetrics { id: titleMetrics; font: titleLabel.font }
    readonly property real buttonShift: -Math.max(0, (toggleButton.implicitHeight - titleMetrics.height) / 2)
    implicitWidth: column.implicitWidth

    function mmss(sec) {
        sec = Math.floor(sec);
        const two = n => String(n).padStart(2, "0");
        return sec >= 3600 ? `${Math.floor(sec / 3600)}:${two(Math.floor(sec / 60) % 60)}:${two(sec % 60)}`
                           : `${Math.floor(sec / 60)}:${two(sec % 60)}`;
    }

    // e.g. "Recording · Brio 500 Analog Stereo", "Paused · Default (…) · saved 0:42"
    readonly property string stateText: {
        const parts = [{
            "available": "Ready to record",
            "recording": "Recording",
            "paused": "Paused",
            "encoding": "Encoding…",
            "done": (app ? `Saved from ${app}` : "Saved") + ` · ${mmss(duration)}`,
            "empty": "Nothing recorded",
            "failed": `Failed: ${error || "unknown error"}`,
        }[itemState] || itemState];
        if (!finished && input)                 // the input mixed into the recording
            parts.push(input_description);
        if (itemState === "paused" && file)
            parts.push(`saved ${mmss(duration)}`);
        if (error && itemState !== "failed")    // failed already says why
            parts.push(error);
        if (busy && active)
            parts.push("saving…");
        return parts.join(" · ");
    }

    readonly property var toggleAction: ({
        "available": {text: "Record", icon: "media-record"},
        "recording": {text: "Pause", icon: "media-playback-pause"},
        "paused": {text: "Resume", icon: "media-record"},
    })[itemState] || {text: "Record", icon: "media-record"}

    // [{value, text}] for the Microphone menu: None, Default, then every source.
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
        anchors.bottomMargin: Kirigami.Units.smallSpacing * 2
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
                Layout.topMargin: row.buttonShift
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
                    id: titleLabel
                    Layout.fillWidth: true
                    text: row.title
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.weight: row.itemState === "recording" ? Font.DemiBold : Font.Normal
                }
            }

            PlasmaComponents3.ToolButton {     // the entry's actions
                id: moreButton
                objectName: "moreButton"
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: row.buttonShift
                icon.name: "view-more-symbolic"
                text: "Actions"
                display: PlasmaComponents3.AbstractButton.IconOnly
                readonly property var menu: row.finished ? moreMenu : streamMenu
                checkable: true
                checked: menu.visible
                onClicked: menu.popup(moreButton, 0, moreButton.height)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered && !menu.visible
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                PlasmaComponents3.Menu {
                    id: streamMenu
                    objectName: "streamMenu"

                    PlasmaComponents3.Menu {
                        id: micMenu
                        objectName: "micMenu"
                        title: "Microphone"
                        icon.name: "audio-input-microphone"
                        enabled: row.controllable && !row.toggling

                        Instantiator {
                            model: row.inputChoices
                            delegate: PlasmaComponents3.MenuItem {
                                required property var modelData
                                text: modelData.text
                                checkable: true
                                autoExclusive: true    // one of them: radio indicators
                                checked: modelData.value === row.input
                                onTriggered: {
                                    row.recorder.setInput(row.itemId, modelData.value);
                                    // triggering toggles `checked`; grabd's state decides it
                                    checked = Qt.binding(() => modelData.value === row.input);
                                }
                            }
                            onObjectAdded: (index, object) => micMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => micMenu.removeItem(object)
                        }
                    }
                    PlasmaComponents3.MenuItem {
                        objectName: "saveNow"
                        text: "Save Now"
                        icon.name: "document-save"
                        enabled: row.active && !row.busy && !row.toggling
                        onTriggered: row.recorder.saveNow(row.itemId)
                    }
                    PlasmaComponents3.MenuItem {
                        text: "Show in Folder"
                        icon.name: "folder-open"
                        enabled: row.file !== ""
                        onTriggered: row.showInFolder()
                    }
                    PlasmaComponents3.MenuSeparator {}
                    PlasmaComponents3.MenuItem {
                        objectName: "removeRecord"
                        text: "Remove Record"
                        icon.name: "user-trash"
                        enabled: row.file !== "" && row.active && !row.toggling
                        onTriggered: row.recorder.removeRecord(row.itemId)
                    }
                }

                PlasmaComponents3.Menu {
                    id: moreMenu
                    objectName: "moreMenu"
                    PlasmaComponents3.MenuItem {
                        text: "Show in Folder"
                        icon.name: "folder-open"
                        enabled: row.file !== ""
                        onTriggered: row.showInFolder()
                    }
                    PlasmaComponents3.MenuSeparator {}
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
    }
}
