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
    // real moves count: the hover updates Qt sends on key presses can carry
    // stale modifiers.
    HoverHandler {
        property point last: Qt.point(-1, -1)
        onPointChanged: {
            const p = point.position;
            if (!hovered || (p.x === last.x && p.y === last.y))
                return;
            last = p;
            item.setShift((point.modifiers & Qt.ShiftModifier) !== 0);
        }
    }
}
