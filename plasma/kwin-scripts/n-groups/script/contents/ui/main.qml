// SPDX-License-Identifier: GPL-2.0-only
// n-groups — entry point: wires KWin signals and shortcuts to the core.

import QtQuick
import org.kde.kwin

import "../code/groups.mjs" as Core

Item {
    id: root

    // Generation token from Core.init(); see groups.mjs.
    property int generation: 0

    // Coalesces bursts of KWin signals into one reconcile pass.
    Timer {
        id: reconcileTimer
        interval: 30
        onTriggered: Core.reconcile()
    }

    // The first Meta+Space expires if the second never comes.
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

    Connections {
        target: Workspace
        function onWindowAdded(window) { Core.track(window); }
        function onWindowRemoved(window) { Core.untrack(window); }
        function onWindowActivated(window) { Core.onActivated(window); }
        function onCurrentDesktopChanged() { Core.schedule(); }
        function onScreensChanged() { Core.schedule(); }
    }

    ShortcutHandler {
        name: "n-groups-link"
        text: "n-groups: Link windows (press on one, then on another)"
        sequence: "Meta+Space"
        onActivated: Core.linkShortcut()
    }
    ShortcutHandler {
        name: "n-groups-unlink"
        text: "n-groups: Unlink active window"
        sequence: "Meta+Alt+Space"
        onActivated: Core.unlinkShortcut()
    }
    ShortcutHandler {
        name: "n-groups-ungroup"
        text: "n-groups: Ungroup active window's group"
        sequence: "Meta+Shift+Space"
        onActivated: Core.dissolveShortcut()
    }
    ShortcutHandler {
        name: "n-groups-next"
        text: "n-groups: Focus next window in group"
        sequence: "Meta+Ctrl+Space"
        onActivated: Core.nextShortcut()
    }

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
            warn: (...args) => console.warn("n-groups:", ...args),
        });
    }

    Component.onDestruction: Core.teardown(generation)
}
