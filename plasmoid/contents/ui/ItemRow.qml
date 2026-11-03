// One grabd item: the status line, then record/pause (or, for a recording, a
// file icon) left of the title and a "⋮" actions menu on the right. Streams'
// menu: Microphone (the input mixed in), Save Now, Show in Folder, Move to
// Trash or Delete Recording; recordings': Show in Folder, Remove Entry (and Move
// to Trash or Delete File, per the "trash" setting). The status
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
    required property bool muted
    required property bool echo_cancel
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

    // Buttons have padding around their icons: shift them up by it, so the icons'
    // tops line up with the top of the title.
    readonly property real buttonShift: -Math.max(0, (toggleButton.implicitHeight
                                                      - Kirigami.Units.iconSizes.smallMedium) / 2)
    implicitWidth: column.implicitWidth

    function mmss(sec) {
        sec = Math.floor(sec);
        const two = n => String(n).padStart(2, "0");
        return sec >= 3600 ? `${Math.floor(sec / 3600)}:${two(Math.floor(sec / 60) % 60)}:${two(sec % 60)}`
                           : `${Math.floor(sec / 60)}:${two(sec % 60)}`;
    }

    // Status line: the state, "· 🔇" if playback is muted, then "·" and (with an
    // input) a mic icon, the input and the rest, e.g.
    // "Recording · 🔇 · 🎤 Brio 500 Analog Stereo", "Paused · saved 0:42"
    readonly property bool showInput: !finished && input !== ""
    readonly property bool showMuted: !finished && muted
    readonly property bool split: showInput || showMuted   // icons: state, tail in separate labels
    readonly property var statusTail: (showInput ? [input_description] : []).concat(statusRest)
    readonly property string stateText: split ? statusHead : [statusHead].concat(statusRest).join(" · ")
    readonly property string inputText: statusTail.join(" · ")
    readonly property string statusHead: {
        return {
            "available": "Ready to record",
            "recording": "Recording",
            "paused": "Paused",
            "encoding": "Encoding…",
            "done": (app ? `Saved from ${app}` : "Saved") + ` · ${mmss(duration)}`,
            "empty": "Nothing recorded",
            "failed": `Failed: ${error || "unknown error"}`,
        }[itemState] || itemState;
    }
    readonly property var statusRest: {
        const parts = [];
        if (itemState === "paused" && file)
            parts.push(`saved ${mmss(duration)}`);
        if (error && itemState !== "failed")    // failed already says why
            parts.push(error);
        if (busy && active)
            parts.push("saving…");
        return parts;
    }

    readonly property var toggleAction: ({
        "available": {text: "Record", icon: "media-record"},
        "recording": {text: "Pause", icon: ""},   // drawn: "recording" ring, see below
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

        RowLayout {                        // status, above the title and starting where it starts
            id: statusLine
            objectName: "statusLine"
            Layout.fillWidth: true
            // as tall as with the mic icon, so selecting an input doesn't shift the layout
            Layout.minimumHeight: Kirigami.Units.iconSizes.small
            Layout.leftMargin: lead.implicitWidth + Kirigami.Units.smallSpacing
            // gap to the title: a bit more than the space between title lines
            Layout.bottomMargin: 0
            spacing: 0
            readonly property bool alert: row.itemState === "failed" || row.error !== ""
            readonly property color textColor: alert ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            opacity: alert ? 1 : 0.7

            PlasmaComponents3.Label {
                objectName: "statusLabel"
                Layout.fillWidth: !row.split
                text: row.stateText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                color: statusLine.textColor
            }
            FontMetrics { id: statusMetrics; font: Kirigami.Theme.smallFont }
            PlasmaComponents3.Label {      // "·" between the state and the muted icon
                objectName: "mutedDot"
                visible: row.showMuted
                Layout.leftMargin: statusMetrics.advanceWidth(" ")
                Layout.rightMargin: statusMetrics.advanceWidth(" ") - mutedIcon.padding
                text: "·"
                font: Kirigami.Theme.smallFont
                color: statusLine.textColor
            }
            Kirigami.Icon {
                id: mutedIcon
                objectName: "mutedIcon"
                // transparent margin around the speaker glyph: ~1 of 16 px (Breeze)
                readonly property real padding: Math.round(implicitWidth * 0.0625)
                visible: row.showMuted
                source: "audio-volume-muted"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
                color: statusLine.textColor
            }
            PlasmaComponents3.Label {      // "·" with a space's width on both sides
                objectName: "statusDot"
                visible: row.split && row.statusTail.length > 0
                Layout.leftMargin: statusMetrics.advanceWidth(" ") - (row.showMuted ? mutedIcon.padding : 0)
                Layout.rightMargin: statusMetrics.advanceWidth(" ") - (row.showInput ? micIcon.padding : 0)
                text: "·"
                font: Kirigami.Theme.smallFont
                color: statusLine.textColor
            }
            Kirigami.Icon {
                id: micIcon
                // transparent margin inside the icon left of the mic glyph: ~3 of
                // 16 px for Breeze, measured on a plasmashell screenshot (offscreen
                // test renders load icons differently and show ~6)
                readonly property real padding: Math.round(implicitWidth * 0.1875)
                visible: row.showInput
                source: "audio-input-microphone"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
                color: statusLine.textColor
            }
            Item {                         // keeps "state 🔇" left-aligned when nothing follows
                Layout.fillWidth: true
                visible: row.split && row.statusTail.length === 0
            }
            PlasmaComponents3.Label {
                objectName: "inputLabel"
                visible: row.split && row.statusTail.length > 0
                Layout.fillWidth: true
                text: row.inputText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                color: statusLine.textColor
            }
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

                Item {                     // while recording: a red dot inside a red ring
                    objectName: "recordingIcon"
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    visible: row.itemState === "recording" && !row.toggling
                    opacity: toggleButton.opacity

                    Rectangle {            // ring, pulsing while the popup is open
                        id: ring
                        anchors.fill: parent
                        anchors.margins: Math.round(parent.width * 0.08)
                        radius: width / 2
                        color: "transparent"
                        border.width: Math.max(1.5, parent.width * 0.09)
                        border.color: "#da4453"    // Breeze's media-record red

                        SequentialAnimation {
                            running: ring.parent.visible && row.recorder.monitoring
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) { ring.opacity = 1; ring.scale = 1; }
                            ParallelAnimation {
                                NumberAnimation { target: ring; property: "opacity"; to: 0.25; duration: 1300; easing.type: Easing.InOutSine }
                                NumberAnimation { target: ring; property: "scale"; to: 1.12; duration: 1300; easing.type: Easing.InOutSine }
                            }
                            ParallelAnimation {
                                NumberAnimation { target: ring; property: "opacity"; to: 1; duration: 1300; easing.type: Easing.InOutSine }
                                NumberAnimation { target: ring; property: "scale"; to: 1; duration: 1300; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Rectangle {            // dot
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.46)
                        height: width
                        radius: width / 2
                        color: "#da4453"
                    }
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

                Item {                     // the stream's level: blue while recording, else gray
                    id: levelBar
                    objectName: "levelBar"
                    // measured by grabd at the stream's outputs: what gets recorded
                    readonly property real value: row.recorder.levels[row.itemId] ?? 0
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
                    visible: !row.finished && row.stream

                    Rectangle {                // track
                        anchors.fill: parent
                        radius: height / 2
                        color: Kirigami.Theme.textColor
                        opacity: 0.15
                    }
                    Rectangle {                // level
                        objectName: "levelFill"
                        height: parent.height
                        width: parent.width * Math.min(1, levelBar.value)
                        radius: height / 2
                        color: row.itemState === "recording" ? Kirigami.Theme.highlightColor
                                                             : Kirigami.Theme.disabledTextColor
                        Behavior on width {
                            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }

            PlasmaComponents3.ToolButton {     // the entry's actions
                id: moreButton
                objectName: "moreButton"
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: row.buttonShift
                icon.name: "view-more-symbolic"
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
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
                        PlasmaComponents3.MenuSeparator {}
                        PlasmaComponents3.MenuItem {
                            objectName: "echoCancel"
                            text: "Echo Cancellation"
                            checkable: true
                            checked: row.echo_cancel
                            onTriggered: {
                                row.recorder.setEchoCancel(row.itemId, !row.echo_cancel);
                                checked = Qt.binding(() => row.echo_cancel);   // grabd's state decides
                            }
                        }
                    }
                    PlasmaComponents3.MenuItem {
                        objectName: "mutePlayback"
                        text: "Mute Playback"
                        icon.name: "audio-volume-muted"
                        checkable: true
                        checked: row.muted
                        enabled: row.stream && !row.finished
                        onTriggered: {
                            row.recorder.setPlaybackMuted(row.itemId, !row.muted);
                            checked = Qt.binding(() => row.muted);   // grabd's state decides
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
                        text: row.recorder.trash ? "Move Recording to Trash" : "Delete Recording"
                        icon.name: row.recorder.trash ? "user-trash" : "edit-delete"
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
                        text: row.recorder.trash ? "Remove Entry and Move to Trash"
                                                 : "Remove Entry and Delete File"
                        icon.name: row.recorder.trash ? "user-trash" : "edit-delete"
                        onTriggered: row.recorder.remove(row.itemId, true)
                    }
                }
            }
        }
    }
}
