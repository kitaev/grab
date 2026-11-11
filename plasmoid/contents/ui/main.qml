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
    // grabd runs (or is starting): the tray menu offers to disable it
    readonly property bool serviceOn: backend.control.transition === "starting"
        || (backend.available && backend.control.transition !== "stopping")

    // Drawn by the tray like the Media Player's icon (the default compact
    // representation): Breeze-style symbolic icons, a microphone in a ring,
    // the ring red while recording (packaging/icons, installed to hicolor).
    Plasmoid.icon: recording ? "grab-recorder-recording-symbolic" : "grab-recorder-symbolic"
    // Active (not NeedsAttention) while recording: the tray animates needs-attention
    // icons, and the red ring already says we're recording.
    // Not running (also disabled: it stays in sight, to be enabled again): active.
    Plasmoid.status: !backend.available || recording || backend.count > 0
                   ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    // Right-click menu: Configure…, then turn grabd on or off (Recorder.setEnabled
    // asks first if that finishes recordings in progress), last. The system tray
    // appends Plasma's own "configure" action after a widget's actions, so while
    // the popup is closed that one is hidden and configureProxy takes its
    // place. While it is open, Plasma's shows instead: the popup's heading puts
    // our actions in its ⋮ menu next to its own configure button.
    readonly property var configureAction: Plasmoid.internalAction("configure")
    Binding {
        target: root.configureAction
        when: root.configureAction !== null
        property: "visible"
        value: root.expanded
        restoreMode: Binding.RestoreBindingOrValue
    }
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            id: configureProxy
            text: root.configureAction?.text ?? ""
            icon.name: "configure"
            visible: root.configureAction !== null && !root.expanded
            onTriggered: root.configureAction?.trigger()
        },
        PlasmaCore.Action {
            text: root.serviceOn ? "Disable Recording Service" : "Enable Recording Service"
            enabled: backend.control.known && !backend.control.busy
                     && backend.control.unitState !== "missing"
            onTriggered: backend.setEnabled(!root.serviceOn)
        }
    ]

    Connections {
        target: backend
        function onAttentionRequested() { root.expanded = true; }
    }

    toolTipMainText: "Record What's Playing"
    // "Recording: 1 of 3 streams" / "No Streams", then "Recordings: 2 ready" / "No Recordings"
    toolTipSubText: {
        const control = backend.control;
        if (control.transition === "starting")
            return "Starting…";
        if (control.transition === "stopping")
            return "Stopping…";
        if (control.error)
            return control.error;
        if (!backend.available)
            return control.known && !control.enabled ? "Disabled"
                 : control.unitState === "missing" ? "Recording service not installed"
                 : "Recording service not running";
        const n = backend.streams.count;
        const ready = backend.readyCount;
        return [n ? `Recording: ${backend.recordingCount} of ${n} stream${n === 1 ? "" : "s"}` : "No Streams",
                ready ? `Recordings: ${ready} ready` : "No Recordings"].join("\n");
    }

    fullRepresentation: FullView {
        recorder: backend
    }
}
