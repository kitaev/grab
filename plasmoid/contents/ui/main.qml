// Grab: system tray widget for the grabd recording service. A microphone in a
// ring (the ring red while recording) opens a popup with a row per stream: record/pause, the
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

    // Drawn by the tray like the Media Player's icon (the default compact
    // representation): Breeze-style symbolic icons, a microphone in a ring,
    // the ring red while recording (packaging/icons, installed to hicolor).
    Plasmoid.icon: recording ? "grab-recorder-recording-symbolic" : "grab-recorder-symbolic"
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

    fullRepresentation: FullView {
        recorder: backend
    }
}
