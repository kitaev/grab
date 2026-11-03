// A menu that tracks the Shift key while it is open, like Dolphin's: items
// read `shift` to offer "Delete" instead of "Move to Trash". Its items should
// be ShiftMenuItems: a menu item has the focus while hovered or selected with
// the keyboard, so they see the key presses, and hover events carry the
// modifiers (for Shift already held when the menu opens).
import QtQuick
import org.kde.plasma.components as PlasmaComponents3

PlasmaComponents3.Menu {
    property bool shift: false
    onAboutToShow: shift = false
}
