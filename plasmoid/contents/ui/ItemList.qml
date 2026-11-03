// A scrollable list of ItemRows for one of the recorder's models, with a
// placeholder when it is empty.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

PlasmaComponents3.ScrollView {
    id: scroll

    required property var recorder
    required property var model
    property string placeholderIcon: "media-record"
    property string placeholderText: ""
    property string placeholderExplanation: ""
    readonly property real listHeight: list.contentHeight

    ListView {
        id: list
        objectName: "itemList"
        clip: true
        model: scroll.model
        reuseItems: false
        boundsBehavior: Flickable.StopAtBounds

        delegate: ColumnLayout {
            id: entry
            required property int index
            required property var model
            width: ListView.view.width
            spacing: 0

            ItemRow {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                recorder: scroll.recorder
                index: entry.index
                itemId: entry.model.itemId
                title: entry.model.title
                app: entry.model.app
                itemState: entry.model.itemState
                busy: entry.model.busy
                pending: entry.model.pending
                muted: entry.model.muted
                stream: entry.model.stream
                input: entry.model.input
                input_description: entry.model.input_description
                file: entry.model.file
                duration: entry.model.duration
                error: entry.model.error
            }
            Kirigami.Separator {
                Layout.fillWidth: true
                visible: entry.index < list.count - 1
                opacity: 0.5
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: list.count === 0
            iconName: scroll.placeholderIcon
            text: scroll.placeholderText
            explanation: scroll.placeholderExplanation
        }
    }
}
