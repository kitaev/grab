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

    Recorder {
        id: backend
        monitoring: root.expanded          // level meters only while the popup is open
    }

    readonly property bool recording: backend.recordingCount > 0

    Plasmoid.icon: "media-record"
    // Active (not NeedsAttention) while recording: the tray animates needs-attention
    // icons, and the red dot already says we're recording.
    Plasmoid.status: !backend.available || recording || backend.count > 0
                   ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    toolTipMainText: "Record What's Playing"
    // "Recording: 1 of 3 streams" / "No Streams", then "Recordings: 2 ready" / "No Recordings"
    toolTipSubText: {
        if (!backend.available)
            return "Recorder service not running";
        const n = backend.streams.count;
        const ready = backend.readyCount;
        return [n ? `Recording: ${backend.recordingCount} of ${n} stream${n === 1 ? "" : "s"}` : "No Streams",
                ready ? `Recordings: ${ready} ready` : "No Recordings"].join("\n");
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
