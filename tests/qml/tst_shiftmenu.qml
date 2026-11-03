// ShiftMenu: Shift turns "Move to Trash" into "Delete" only while it is held,
// with or without an item hovered, and keyboard navigation still works.
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as W

Item {
    id: root
    width: 420
    height: 300
    property int triggered: 0

    W.ShiftMenu {
        id: menu
        W.ShiftMenuItem { id: first; text: "Show in Folder"; onTriggered: root.triggered++ }
        W.ShiftMenuItem { id: del; text: menu.shift ? "Delete" : "Move to Trash" }
    }
    W.ShiftMenu {                          // labels of different widths (the menu resizes)
        id: wide
        W.ShiftMenuItem { text: "Show in Folder" }
        W.ShiftMenuItem {
            id: wideDel
            text: wide.shift ? "Remove Entry and Delete File, a much longer label"
                             : "Remove Entry and Move to Trash"
        }
    }

    TestCase {
        name: "ShiftMenu"
        when: windowShown

        function open(m, x) {
            m.popup(root, x, 10);
            tryCompare(m, "opened", true);
        }
        function close(m) {
            m.close();
            tryCompare(m, "visible", false);
        }
        function cleanup() {
            close(menu);
            close(wide);
            keyRelease(Qt.Key_Shift);
        }

        function test_hovered() {
            open(menu, 10);
            compare(del.text, "Move to Trash");
            mouseMove(first, 10, 5);
            wait(100);
            keyPress(Qt.Key_Shift);
            compare(del.text, "Delete", "press while another item is hovered");
            keyRelease(Qt.Key_Shift);
            compare(del.text, "Move to Trash", "release");
        }

        function test_hoverModifiers() {        // Shift already held when the menu opened
            open(menu, 10);
            mouseMove(del, 10, 5, -1, Qt.NoButton, Qt.ShiftModifier);
            wait(50);
            compare(del.text, "Delete", "hover with Shift held");
            mouseMove(del, 12, 6, -1, Qt.NoButton, Qt.NoModifier);
            wait(50);
            compare(del.text, "Move to Trash", "hover without Shift");
        }

        function test_resetOnOpen() {
            open(menu, 10);
            keyPress(Qt.Key_Shift);             // still held when the menu closes
            close(menu);
            open(menu, 10);
            compare(del.text, "Move to Trash");
        }

        function test_heldOnly() {              // the menu moves under a still pointer
            for (const x of [10, 400]) {        // 400: shifted left at the window's edge
                open(wide, x);
                mouseMove(wideDel, 30, 5, -1, Qt.NoButton, Qt.NoModifier);
                wait(100);
                for (let i = 0; i < 3; i++) {
                    keyPress(Qt.Key_Shift);
                    wait(200);
                    compare(wideDel.text, "Remove Entry and Delete File, a much longer label",
                            `held, x ${x}, round ${i}`);
                    keyRelease(Qt.Key_Shift);
                    wait(200);
                    compare(wideDel.text, "Remove Entry and Move to Trash", `released, x ${x}, round ${i}`);
                }
                close(wide);
            }
        }

        function test_noHover() {
            mouseMove(root, 5, 290);            // pointer away from the menu
            open(menu, 200);
            keyPress(Qt.Key_Shift); wait(50);
            compare(del.text, "Delete", "no item hovered");
            keyRelease(Qt.Key_Shift); wait(50);
            compare(del.text, "Move to Trash");

            keyClick(Qt.Key_Down); wait(50);
            compare(menu.currentIndex, 1, "Down selects the first real item");
            verify(first.highlighted);
            keyClick(Qt.Key_Down); wait(50);
            compare(menu.currentIndex, 2);
            keyClick(Qt.Key_Down); wait(50);
            verify(menu.currentIndex !== 0, "never the key catcher");
            keyPress(Qt.Key_Shift); wait(50);
            compare(del.text, "Delete", "item selected with the keyboard");
            keyRelease(Qt.Key_Shift); wait(50);

            mouseMove(first, 10, 5); wait(50);  // hover, then leave the items
            mouseMove(root, 5, 290); wait(100);
            keyPress(Qt.Key_Shift); wait(50);
            compare(del.text, "Delete", "after the pointer left the items");
            keyRelease(Qt.Key_Shift); wait(50);
            compare(del.text, "Move to Trash");
        }

        function test_enterEscape() {
            mouseMove(root, 5, 290);
            open(menu, 200);
            const before = root.triggered;
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            wait(50);
            compare(root.triggered, before + 1, "Enter triggers the selected item");
            tryCompare(menu, "visible", false);
            open(menu, 200);
            keyClick(Qt.Key_Escape);
            tryCompare(menu, "visible", false, 2000, "Escape closes");
        }
    }
}
