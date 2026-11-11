// The popup: a Streams tab (what can be or is being recorded) and a Recordings
// tab (finished recordings), and a footer with the recordings folder and,
// on Recordings, a "⋮" menu to remove all of them. The tabs are in the header
// (a PlasmoidHeading, like the Volume widget's): the system tray joins it to
// its title row, one background without a line between them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.purpose as Purpose

PlasmaExtras.Representation {
    id: view

    required property var recorder

    collapseMarginsHint: true
    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    // sized for the longer list, so switching tabs doesn't resize the popup
    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 34,
                                     Math.max(Kirigami.Units.gridUnit * 12,
                                              Math.max(streamList.listHeight, recordList.listHeight)
                                              + tabs.implicitHeight + folderBar.implicitHeight
                                              + Kirigami.Units.largeSpacing * 2))

    readonly property bool onRecords: tabs.currentIndex === 1

    // Questions before files are deleted for good or grabd is stopped
    // (Recorder.confirm). One asked from the tray menu may come before this
    // view exists: it waits in pendingConfirm.
    function showConfirm() {
        const c = view.recorder.pendingConfirm;
        if (!c)
            return;
        view.recorder.pendingConfirm = null;
        confirmDialog.title = c.title;
        confirmMessage.text = c.message;
        confirmAction.text = c.action;
        confirmAction.icon.name = c.icon || "edit-delete";
        confirmDialog.proceed = c.proceed;
        confirmDialog.open();
    }
    Connections {
        target: view.recorder
        function onConfirmRequested() { view.showConfirm(); }
    }
    Component.onCompleted: showConfirm()

    // While grabd isn't running, the lists say why, with a button to enable it
    readonly property var control: recorder.control
    readonly property string offText: {
        switch (control.transition) {
        case "starting": return "Starting the recording service…";
        case "stopping": return "Stopping the recording service…";
        }
        if (!control.known)
            return "";
        if (control.unitState === "missing")
            return "Recording service not installed";
        return control.enabled ? "Recording service not running" : "Recording service disabled";
    }
    readonly property string offExplanation: {
        if (control.transition === "stopping")
            return "Recordings in progress are being finished and saved.";
        if (control.busy || !control.known)
            return "";
        if (control.unitState === "missing")
            return "grabd.service wasn't found. Reinstall the grab-recorder package.";
        return control.enabled ? "Start it to record what applications play."
                               : "Enable it to record what applications play.";
    }
    readonly property Kirigami.Action offAction: Kirigami.Action {
        objectName: "enableAction"
        text: view.control.enabled ? "Start Recording Service" : "Enable Recording Service"
        icon.name: "media-record"
        enabled: !view.control.busy
        visible: view.control.known && !view.control.busy
        onTriggered: view.recorder.setEnabled(true)
    }

    // Share: run the chosen Purpose plugin for a recording. Plugins that need
    // settings (a Bluetooth device, a Nextcloud account, ...) show them in
    // shareDialog; others (Telegram, Email, Clipboard) just run.
    Purpose.PurposeAlternativesModel {
        id: shareModel
        objectName: "shareModel"
        pluginType: "Export"
    }
    property var shareIds: []              // shareModel's plugin ids, by row
    Instantiator {
        model: shareModel
        delegate: QtObject {
            required property int index
            required property string pluginId
        }
        onObjectAdded: (index, object) => { const ids = view.shareIds.slice(); ids[index] = object.pluginId; view.shareIds = ids; }
        onObjectRemoved: (index, object) => { const ids = view.shareIds.slice(); ids.splice(index, 1); view.shareIds = ids; }
    }

    function share(file, pluginId) {
        if (shareJob.jobState === Purpose.PurposeJobController.Configuring
                || shareJob.jobState === Purpose.PurposeJobController.Running)
            return;                        // one at a time
        shareModel.inputData = {urls: ["file://" + file.split("/").map(encodeURIComponent).join("/")],
                                mimeType: "audio/mpeg"};
        const row = shareIds.indexOf(pluginId);
        if (row < 0) {
            console.warn("grab: share target not found:", pluginId);
            return;
        }
        shareDialog.message = "";
        shareJob.index = -1;               // a new job even for the same row
        shareJob.index = row;
        shareJob.start();
    }

    Connections {
        target: view.recorder
        function onShareRequested(file, pluginId) { view.share(file, pluginId); }
    }

    Connections {
        target: shareJob
        function onJobStateChanged() {
            switch (shareJob.jobState) {
            case Purpose.PurposeJobController.Configuring:
                shareDialog.open();
                break;
            case Purpose.PurposeJobController.Finished: {
                const url = shareJob.job && shareJob.job.output ? shareJob.job.output.url : "";
                if (url) {                 // uploads report where the file went
                    shareDialog.message = "Shared: " + url;
                    shareDialog.open();
                } else {
                    shareDialog.close();
                }
                break;
            }
            case Purpose.PurposeJobController.Error:
                shareDialog.message = "Could not share: "
                    + (shareJob.job ? shareJob.job.errorString || shareJob.job.errorText : "unknown error");
                shareDialog.open();
                break;
            case Purpose.PurposeJobController.Cancelled:
                shareDialog.close();
                break;
            }
        }
    }

    Kirigami.Dialog {
        id: shareDialog
        objectName: "shareDialog"
        property string message: ""
        parent: view
        title: "Share"
        preferredWidth: Kirigami.Units.gridUnit * 22
        standardButtons: QQC2.Dialog.NoButton

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Purpose.JobView {
                id: shareJob
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.minimumHeight: jobState === Purpose.PurposeJobController.Running
                    ? Kirigami.Units.gridUnit * 4 : 0
                model: shareModel
                visible: shareDialog.message === ""
            }
            Kirigami.SelectableLabel {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                visible: shareDialog.message !== ""
                text: shareDialog.message
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
        }
    }

    Kirigami.PromptDialog {
        id: confirmDialog
        objectName: "confirmDialog"
        property var proceed: null
        parent: view
        standardButtons: QQC2.Dialog.Cancel
        customFooterActions: [
            Kirigami.Action {
                id: confirmAction
                icon.name: "edit-delete"
                onTriggered: {
                    const proceed = confirmDialog.proceed;
                    confirmDialog.close();
                    if (proceed)
                        proceed();
                }
            }
        ]
        onClosed: proceed = null

        QQC2.Label {                       // titles come from apps and web pages: plain text
            id: confirmMessage
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    header: PlasmaExtras.PlasmoidHeading {
        // the tab bar reaches the heading's bottom border, as in the Volume widget
        bottomPadding: -bottomInset

        PlasmaComponents3.TabBar {
            id: tabs
            objectName: "tabs"
            anchors.fill: parent

            PlasmaComponents3.TabButton {
                text: "Streams"
            }
            PlasmaComponents3.TabButton {
                text: "Recordings"
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        Kirigami.InlineMessage {           // enabling or disabling grabd failed
            objectName: "serviceError"
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: view.control.error !== ""
            type: Kirigami.MessageType.Error
            text: view.control.error
            showCloseButton: true
            onVisibleChanged: if (!visible) view.control.error = ""   // closed
        }
        Kirigami.InlineMessage {           // grabd finishes its recordings before it exits
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: view.control.transition === "stopping" && view.recorder.available
            type: Kirigami.MessageType.Information
            text: "Stopping the recording service: recordings in progress are being finished and saved…"
        }

        StackLayout {
            enabled: view.control.transition !== "stopping"
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            ItemList {
                id: streamList
                recorder: view.recorder
                model: view.recorder.streams
                placeholderIcon: "media-record"
                placeholderText: view.recorder.available ? "No recordable streams" : view.offText
                placeholderExplanation: view.recorder.available
                    ? "Start playing audio in an application to record it." : view.offExplanation
                placeholderAction: view.recorder.available ? null : view.offAction
                placeholderBusy: !view.recorder.available && view.control.busy
            }

            ItemList {
                id: recordList
                recorder: view.recorder
                model: view.recorder.records
                placeholderIcon: view.recorder.available ? "audio-x-generic" : "media-record"
                placeholderText: view.recorder.available ? "No recordings" : view.offText
                placeholderExplanation: view.recorder.available
                    ? "Finished recordings appear here." : view.offExplanation
                placeholderAction: view.recorder.available ? null : view.offAction
                placeholderBusy: !view.recorder.available && view.control.busy
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            id: folderBar
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                icon.name: "folder-music"
                text: "Open Recordings Folder"
                visible: view.recorder.folder !== ""
                enabled: view.recorder.available   // grabd's folder: not known while it is off
                onClicked: Qt.openUrlExternally("file://" + view.recorder.folder.split("/")
                                                .map(encodeURIComponent).join("/"))
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents3.ToolButton {
                id: removeAllButton
                objectName: "removeAllButton"
                icon.name: "view-more-symbolic"
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                text: "Remove All"
                display: PlasmaComponents3.AbstractButton.IconOnly
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered && !removeAllMenu.visible
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                visible: view.onRecords
                enabled: view.recorder.finishedCount > 0
                checkable: true
                checked: removeAllMenu.visible
                onClicked: removeAllMenu.popup(removeAllButton, 0, -removeAllMenu.implicitHeight)

                ShiftMenu {
                    id: removeAllMenu
                    ShiftMenuItem {
                        text: "Remove All Entries"
                        icon.name: "edit-clear-all"
                        onTriggered: view.recorder.removeFinished(false)
                    }
                    ShiftMenuItem {             // Shift: delete permanently (like Dolphin)
                        text: removeAllMenu.shift ? "Remove All Entries and Delete Files"
                                                  : "Remove All Entries and Move to Trash"
                        icon.name: removeAllMenu.shift ? "edit-delete" : "user-trash"
                        onTriggered: view.recorder.removeFinishedWithFiles(removeAllMenu.shift)
                    }
                }
            }
        }
    }
}
