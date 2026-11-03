// A menu item that keeps its ShiftMenu's `shift` up to date (see ShiftMenu).
import QtQuick
import org.kde.plasma.components as PlasmaComponents3

PlasmaComponents3.MenuItem {
    id: item

    function setShift(on) {
        if (item.menu && item.menu.shift !== undefined)
            item.menu.shift = on;
    }

    Keys.onPressed: event => { if (event.key === Qt.Key_Shift) setShift(true); event.accepted = false; }
    Keys.onReleased: event => { if (event.key === Qt.Key_Shift) setShift(false); event.accepted = false; }

    // Shift already held when the menu opens: seen once the mouse moves. Only
    // real moves count, i.e. a new position in the window: Qt also sends hover
    // updates when items move under a still pointer (the menu widens with the
    // "Delete" label and shifts left at the popup's edge), and those can carry
    // modifiers from before the last key press or release (Wayland), which
    // flipped `shift` back.
    HoverHandler {
        property point last: Qt.point(-1, -1)
        onPointChanged: {
            const p = point.scenePosition;
            if (!hovered || (p.x === last.x && p.y === last.y))
                return;
            last = p;
            item.setShift((point.modifiers & Qt.ShiftModifier) !== 0);
        }
    }
}
