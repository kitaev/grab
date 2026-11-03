// A menu that tracks the Shift key while it is open, like Dolphin's: items
// read `shift` to offer "Delete" instead of "Move to Trash". Its items should
// be ShiftMenuItems: a menu item has the focus while hovered or selected with
// the keyboard, so it sees the key presses, and hover moves carry the
// modifiers (for Shift already held when the menu opens). While no item has
// the focus (just opened by a click, pointer outside the items), an invisible
// item takes it, so Shift works as soon as the menu is shown.
import QtQuick
import org.kde.plasma.components as PlasmaComponents3

PlasmaComponents3.Menu {
    id: menu

    property bool shift: false

    onAboutToShow: shift = false
    onOpened: keyCatcher.forceActiveFocus()
    // Keys the catcher doesn't use go up to the menu (arrows, Enter, Escape),
    // past the list: its own arrow handling isn't the menu's navigation.
    Component.onCompleted: contentItem.keyNavigationEnabled = false

    Item {                                 // first entry: no size, never current
        id: keyCatcher
        objectName: "shiftKeyCatcher"
        width: 0
        height: 0
        Keys.onPressed: event => { if (event.key === Qt.Key_Shift) menu.shift = true; event.accepted = false; }
        Keys.onReleased: event => { if (event.key === Qt.Key_Shift) menu.shift = false; event.accepted = false; }
    }

    // focus back on the menu itself (e.g. the pointer left the items): catch keys again
    readonly property Connections focusWatch: Connections {
        target: menu.contentItem
        function onActiveFocusChanged() {
            if (menu.opened && menu.contentItem.activeFocus)
                keyCatcher.forceActiveFocus();
        }
    }
}
