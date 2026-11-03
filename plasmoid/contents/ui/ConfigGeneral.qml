// Settings page: grabd's own settings (the recordings folder),
// read and written over D-Bus (GetSettings/SetSettings), not the widget's
// configuration. The dialog's Apply/OK call saveConfig(); unsavedChanges
// enables Apply.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

KCM.SimpleKCM {
    id: page

    property var saved: null               // grabd's settings, as last read or saved
    property string error: ""

    readonly property string defaultFolder: saved ? saved.default_folder : ""
    readonly property string savedFolder: saved ? (saved.folder || saved.default_folder) : ""
    readonly property string folder: folderField.text.trim().replace(/(.)\/+$/, "$1")
    readonly property bool unsavedChanges: saved !== null
        && folder !== savedFolder

    function plain(v) {
        return v !== null && typeof v === "object" && v.value !== undefined ? v.value : v;
    }

    function call(member, args, onReply, onError) {
        DBus.SessionBus.asyncCall({service: "org.grab.Recorder", path: "/org/grab/Recorder",
                                   iface: "org.grab.Recorder1", member: member,
                                   arguments: args},
            reply => onReply(reply),
            reply => onError(reply.error.message));
    }

    function show(settings) {
        saved = settings;
        folderField.text = saved.folder || saved.default_folder;
    }

    function load() {
        call("GetSettings", [], reply => { error = ""; show(JSON.parse(String(plain(reply.value)))); },
             message => error = "Can't read the recorder's settings: " + message);
    }

    function saveConfig() {
        if (!saved)
            return;
        const changes = {folder: folder === defaultFolder ? "" : folder};
        saved = Object.assign({}, saved, changes);  // Apply turns off until grabd answers
        call("SetSettings", [JSON.stringify(changes)],
             () => { error = ""; load(); },
             message => { error = message; load(); });
    }

    Component.onCompleted: load()

    header: Kirigami.InlineMessage {
        visible: page.error !== ""
        type: Kirigami.MessageType.Error
        text: page.error
        position: Kirigami.InlineMessage.Position.Header
    }

    // the package version (build.sh/PKGBUILD write it into metadata.json)
    footer: QQC2.Label {
        readonly property string version: Plasmoid.metaData?.version ?? ""
        visible: version !== ""
        padding: Kirigami.Units.largeSpacing
        horizontalAlignment: Text.AlignHCenter
        text: "Record What's Playing " + version
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }

    Kirigami.FormLayout {
        enabled: page.saved !== null

        RowLayout {
            Kirigami.FormData.label: "Save recordings in:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: folderField
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                placeholderText: page.defaultFolder
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                text: "Choose…"
                onClicked: folderDialog.open()
            }
            QQC2.Button {
                icon.name: "edit-undo"
                text: "Default"
                enabled: page.folder !== page.defaultFolder
                onClicked: folderField.text = page.defaultFolder
                QQC2.ToolTip.text: page.defaultFolder
                QQC2.ToolTip.visible: hovered && page.defaultFolder !== ""
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: "New recordings go here. Recordings already made stay where they are; "
                + "the list shows the recordings in this folder."
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

    }

    FolderDialog {
        id: folderDialog
        title: "Save Recordings In"
        currentFolder: "file://" + encodeURI(page.folder || page.defaultFolder)
        onAccepted: folderField.text = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
    }
}
