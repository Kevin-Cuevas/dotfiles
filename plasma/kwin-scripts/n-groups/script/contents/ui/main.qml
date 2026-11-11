// SPDX-License-Identifier: GPL-2.0-only
// n-groups — entry point: KWin signals, shortcuts, pick mode and feedback.

import QtQuick
import QtQuick.Layouts
import org.kde.kwin
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/groups.mjs" as Core

Item {
    id: root

    // Generation token from Core.init(); see groups.mjs.
    property int generation: 0

    // --- core plumbing -------------------------------------------------------

    // Coalesces bursts of KWin signals into one reconcile pass.
    Timer {
        id: reconcileTimer
        interval: 30
        onTriggered: Core.reconcile()
    }

    // Keyboard linking: the first Meta+Space expires if the second never comes.
    Timer {
        id: pendingTimer
        interval: 8000
        onTriggered: Core.cancelPending(true)
    }

    DBusCall {
        id: osdCall
        service: "org.kde.plasmashell"
        path: "/org/kde/osdService"
        dbusInterface: "org.kde.osdService"
        method: "showText"
    }

    // After linking, the new group is shown alone for a moment through KWin's
    // highlightwindow effect (the one Alt+Tab previews use). The IDs must be a
    // typed list<string>: a JS array goes out as D-Bus "av" and is rejected.
    property list<string> flashIds
    DBusCall {
        id: highlightCall
        service: "org.kde.KWin"
        path: "/org/kde/KWin/HighlightWindow"
        dbusInterface: "org.kde.KWin.HighlightWindow"
        method: "highlightWindows"
    }
    function highlight(ids) {
        flashIds = ids;
        highlightCall.arguments = [flashIds];
        highlightCall.call();
    }
    Timer {
        id: flashTimer
        interval: 900
        onTriggered: root.highlight([])
    }

    Connections {
        target: Workspace
        function onWindowAdded(window) { Core.track(window); }
        function onWindowRemoved(window) {
            Core.untrack(window);
            if (root.picking) root.drop(window);
        }
        function onWindowActivated(window) { Core.onActivated(window); }
        function onCurrentDesktopChanged() {
            Core.schedule();
            root.stopPick();
        }
        function onScreensChanged() { Core.schedule(); }
        function onCursorPosChanged() {
            if (root.picking) root.updateHover();
        }
    }

    // --- shortcuts -----------------------------------------------------------

    ShortcutHandler {
        name: "n-groups-link"
        text: "n-groups: Link windows (pick them with the mouse)"
        sequence: "Meta+Space"
        onActivated: {
            if (!Core.pickWithMouse()) Core.linkShortcut();
            else if (root.picking) root.finishPick();
            else root.startPick();
        }
    }
    ShortcutHandler {
        name: "n-groups-unlink-window"
        text: "n-groups: Unlink active window"
        sequence: "Meta+Shift+Space"
        onActivated: Core.unlinkShortcut()
    }
    ShortcutHandler {
        name: "n-groups-dissolve"
        text: "n-groups: Ungroup active window's whole group"
        sequence: ""
        onActivated: Core.dissolveShortcut()
    }
    ShortcutHandler {
        name: "n-groups-next"
        text: "n-groups: Focus next window in group"
        sequence: "Meta+Ctrl+Space"
        onActivated: Core.nextShortcut()
    }

    // --- pick mode -----------------------------------------------------------
    // Meta+Space dims the screen. The window under the pointer is lifted above
    // the dim with an animated frame; clicking toggles it in the selection
    // (numbered). Picking a window that's already grouped brings its group
    // along (marked with the link icon). Enter or Meta+Space links, Esc or right-click cancels.

    property bool picking: false
    property var picked: []    // Window[], in click order
    property var preview: []   // everything that ends up in the group
    property var hovered: null
    property rect area: Qt.rect(0, 0, 0, 0)
    property rect hintScreen: Qt.rect(0, 0, 0, 0)   // screen under the pointer at start
    readonly property string overlayTitle: "n-groups pick"

    // Union of all screens: the overlay spans every monitor.
    function screensArea() {
        let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
        for (const s of Workspace.screens) {
            const g = s.geometry;
            x1 = Math.min(x1, g.x);
            y1 = Math.min(y1, g.y);
            x2 = Math.max(x2, g.x + g.width);
            y2 = Math.max(y2, g.y + g.height);
        }
        return x1 === Infinity ? Qt.rect(0, 0, 1, 1) : Qt.rect(x1, y1, x2 - x1, y2 - y1);
    }

    function startPick() {
        area = screensArea();
        hintScreen = Workspace.activeScreen ? Workspace.activeScreen.geometry : area;
        const w = Workspace.activeWindow;
        picked = w && !w.minimized && Core.isCandidate(w) ? [w] : [];
        preview = Core.linkPreview(picked);
        picking = true;
        updateHover();
    }

    function stopPick() {
        picking = false;
        picked = [];
        preview = [];
        hovered = null;
    }

    function finishPick() {
        const selection = picked;
        stopPick();
        if (selection.length > 0) Core.linkWindows(selection);
    }

    function toggle(w) {
        if (!w) return;
        const next = picked.slice();
        const i = next.indexOf(w);
        if (i >= 0) next.splice(i, 1);
        else next.push(w);
        picked = next;
        preview = Core.linkPreview(picked);
    }

    function drop(w) {
        if (picked.includes(w)) toggle(w);
        if (hovered === w) hovered = null;
    }

    function updateHover() {
        const p = Workspace.cursorPos;
        hovered = Core.windowAt(p.x, p.y, overlayTitle);
    }

    PlasmaCore.Dialog {
        id: overlay
        title: root.overlayTitle
        visible: root.picking
        location: PlasmaCore.Types.Desktop
        type: PlasmaCore.Dialog.OnScreenDisplay
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
        x: root.area.x
        y: root.area.y

        mainItem: Item {
            id: canvas
            width: root.area.width
            height: root.area.height
            focus: true

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.finishPick();
                else if (event.key === Qt.Key_Escape) root.stopPick();
                else return;
                event.accepted = true;
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.4)
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: root.hovered ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPositionChanged: root.updateHover()
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) root.stopPick();
                    else root.toggle(root.hovered);
                }
            }

            // Lifted windows: the group being built, plus the hovered one.
            Repeater {
                model: {
                    const shown = root.preview.slice();
                    if (root.hovered && !shown.includes(root.hovered)) shown.push(root.hovered);
                    return shown;
                }
                delegate: Item {
                    id: lifted
                    required property var modelData
                    readonly property rect g: modelData.frameGeometry
                    readonly property int order: root.picked.indexOf(modelData)   // -1 = not clicked
                    readonly property bool joins: order < 0 && root.preview.includes(modelData)
                    readonly property bool isHovered: root.hovered === modelData

                    x: g.x - root.area.x
                    y: g.y - root.area.y
                    width: g.width
                    height: g.height
                    opacity: 0
                    scale: 0.985
                    Component.onCompleted: appear.start()
                    ParallelAnimation {
                        id: appear
                        NumberAnimation { target: lifted; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: lifted; property: "scale"; to: 1; duration: 180; easing.type: Easing.OutBack }
                    }

                    WindowThumbnail {
                        anchors.fill: parent
                        wId: lifted.modelData.internalId
                    }

                    Rectangle {
                        id: border
                        anchors.fill: parent
                        anchors.margins: -border.border.width
                        color: "transparent"
                        radius: Kirigami.Units.cornerRadius
                        border.width: lifted.order >= 0 ? 4 : 3
                        border.color: lifted.joins ? Qt.alpha(Kirigami.Theme.highlightColor, 0.6)
                                                   : Kirigami.Theme.highlightColor
                        // Only the hovered, not yet picked window breathes.
                        SequentialAnimation on opacity {
                            running: lifted.isHovered && lifted.order < 0
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.45; duration: 550; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                        }
                    }

                    // Badge in the middle: pick order, or the link icon for windows
                    // that come along because they're already grouped with a pick.
                    Rectangle {
                        visible: lifted.order >= 0 || lifted.joins
                        anchors.centerIn: parent
                        width: Kirigami.Units.gridUnit * 4
                        height: width
                        radius: width / 2
                        color: Kirigami.Theme.highlightColor
                        opacity: lifted.joins ? 0.75 : 0.95
                        border.width: 2
                        border.color: Qt.alpha(Kirigami.Theme.highlightedTextColor, 0.5)
                        PlasmaComponents3.Label {
                            visible: lifted.order >= 0
                            anchors.centerIn: parent
                            text: lifted.order + 1
                            color: Kirigami.Theme.highlightedTextColor
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.6
                        }
                        Kirigami.Icon {
                            visible: lifted.joins
                            anchors.centerIn: parent
                            width: parent.width / 2
                            height: width
                            source: "object-group"
                            color: Kirigami.Theme.highlightedTextColor
                            isMask: true
                        }
                    }
                }
            }

            // Hint, bottom-center of the screen the pointer was on.
            Rectangle {
                x: root.hintScreen.x - root.area.x + (root.hintScreen.width - width) / 2
                y: root.hintScreen.y - root.area.y + root.hintScreen.height - height - Kirigami.Units.gridUnit * 4
                width: hint.implicitWidth + Kirigami.Units.gridUnit * 2
                height: hint.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: height / 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                RowLayout {
                    id: hint
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: "object-group"
                    }
                    PlasmaComponents3.Label {
                        text: root.preview.length >= 2
                            ? "<b>" + Core.joinLabels(root.preview) + "</b>"
                            : "<b>Click the windows to link</b>"
                        textFormat: Text.StyledText
                    }
                    PlasmaComponents3.Label {
                        text: "Enter / Meta+Space link · Esc / right-click cancel"
                        opacity: 0.7
                    }
                }
            }
        }
    }

    // --- lifecycle -----------------------------------------------------------

    Component.onCompleted: {
        generation = Core.init({
            workspace: Workspace,
            readConfig: (key, fallback) => KWin.readConfig(key, fallback),
            schedule: () => reconcileTimer.restart(),
            armPending: () => pendingTimer.restart(),
            disarmPending: () => pendingTimer.stop(),
            osd: (icon, text) => {
                osdCall.arguments = [icon, text];
                osdCall.call();
            },
            flash: (ids) => {
                root.highlight(ids);
                flashTimer.restart();
            },
            warn: (...args) => console.warn("n-groups:", ...args),
        });
    }

    Component.onDestruction: Core.teardown(generation)
}
