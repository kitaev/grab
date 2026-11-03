// Grab: system tray widget for the grabd recording service. A microphone in a
// ring (red while recording) opens a popup with a row per stream: record/pause, the
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

    Plasmoid.icon: "audio-input-microphone"
    // Active (not NeedsAttention) while recording: the tray animates needs-attention
    // icons, and the red ring already says we're recording.
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

        // A microphone in a ring: white, the ring red while recording.
        Rectangle {
            id: ring
            anchors.centerIn: parent
            width: Math.round(Math.min(compact.width, compact.height) * 0.84 / 2) * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1.5, Math.round(width * 0.09 * 2) / 2)
            border.color: root.recording ? "#da4453"
                        : compact.containsMouse ? Kirigami.Theme.highlightColor : "white"

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(ring.width * 0.62)
                height: width
                source: "audio-input-microphone-symbolic"
                isMask: true
                color: "white"
            }
        }
    }

    fullRepresentation: FullView {
        recorder: backend
    }
}
