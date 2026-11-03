// Grab: system tray widget for the grabd recording service. A grey dot (red
// while recording) opens a popup with a row per stream: record/pause, the
// microphone to mix in, and for finished recordings Show in folder / Remove.
// Status follows "shown when relevant": passive with nothing to show, active
// otherwise.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Recorder { id: backend }

    readonly property bool recording: backend.recordingCount > 0

    Plasmoid.icon: "media-record"
    // Active (not NeedsAttention) while recording: the tray animates needs-attention
    // icons, and the red dot already says we're recording.
    Plasmoid.status: !backend.available || recording || backend.items.count > 0
                   ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    toolTipMainText: "Grab"
    toolTipSubText: {
        if (!backend.available)
            return "Recorder service not running";
        if (recording)
            return "Recording:\n" + backend.recordingTitles.join("\n");
        if (backend.items.count === 0)
            return "No streams";
        const busy = backend.busyCount;
        return `${backend.items.count} item(s)` + (busy ? `, ${busy} encoding` : "");
    }

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.expanded = !root.expanded

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(Math.min(compact.width, compact.height) * 0.76 / 2) * 2
            height: width
            radius: width / 2
            color: root.recording ? "#da4453" : "#8a8a8a"
            border.width: compact.containsMouse ? 1 : 0
            border.color: Kirigami.Theme.highlightColor
        }
    }

    fullRepresentation: FullView {
        recorder: backend
    }
}
