// SPDX-License-Identifier: GPL-2.0-only
//
// n-switcher — Alt+Tab layout for n-groups.
//
// Plain windows: thumbnail + icon + caption, like Breeze's grid.
// Groups: one entry with a live mosaic of every member, laid out like they
// are on screen, and a preview of the whole group while it's selected.
//
// Group state comes from the n-groups script itself: KWin builds the switcher
// in the same QQmlEngine as declarative scripts, so importing the script's
// module by the same URL yields the same live instance. The path is relative
// to the install location:
//   ~/.local/share/kwin/tabbox/n-switcher/contents/ui/main.qml
//   ~/.local/share/kwin/scripts/n-groups/contents/code/groups.mjs
// so n-switcher needs n-groups installed next to it (install.sh takes care).

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami

import "../../../../scripts/n-groups/contents/code/groups.mjs" as Groups

KWin.TabBoxSwitcher {
    id: tabBox

    // --- group preview -------------------------------------------------------
    // While Alt+Tab is open KWin's highlightwindow effect shows the selected
    // window and ghosts the rest, but TabBox only hands it one window. Its
    // D-Bus API takes a list and the last call wins, so shortly after each
    // selection change the list is re-sent with every member of the group.

    property var selectedGroup: null
    property bool overrodeHighlight: false

    // Must be a typed list<string> (QStringList, D-Bus "as"): a plain JS array
    // is sent as "av" and KWin answers "no slot matched".
    property list<string> highlightIds

    // The popup is a KWin internal window whose caption is the Dialog title.
    // TabBox always puts it in its own highlight list; without it the effect
    // ghosts the switcher itself and Alt+Tab seems to vanish.
    readonly property string popupTitle: "n-switcher"

    // Top-most live match: the previous popup may still be fading out.
    function popupId() {
        const stack = KWin.Workspace.stackingOrder;
        for (let i = stack.length - 1; i >= 0; i--) {
            const w = stack[i];
            if (w.caption === popupTitle && !w.deleted) return String(w.internalId);
        }
        return null;
    }

    function sendHighlight(ids) {
        highlightIds = ids;
        highlightCall.arguments = [highlightIds];
        highlightCall.call();
    }

    KWin.DBusCall {
        id: highlightCall
        service: "org.kde.KWin"
        path: "/org/kde/KWin/HighlightWindow"
        dbusInterface: "org.kde.KWin.HighlightWindow"
        method: "highlightWindows"
    }

    // Runs after TabBox's own highlight call. If Alt+Tab opens with a group
    // already selected the popup may not be mapped yet: retry for a while and
    // never send a list without it.
    Timer {
        id: highlightTimer
        interval: 40
        property int attempts: 0
        onTriggered: {
            if (!tabBox.visible || !tabBox.selectedGroup) return;
            const popup = tabBox.popupId();
            if (!popup) {
                if (++attempts < 25) restart();
                return;
            }
            const ids = tabBox.selectedGroup.members.map((w) => String(w.internalId));
            tabBox.sendHighlight(ids.concat([popup]));
            tabBox.overrodeHighlight = true;
        }
    }

    function scheduleHighlight() {
        highlightTimer.attempts = 0;
        highlightTimer.restart();
    }

    onSelectedGroupChanged: scheduleHighlight()
    onCurrentIndexChanged: scheduleHighlight()
    onVisibleChanged: {
        if (visible) {
            scheduleHighlight();
        } else {
            highlightTimer.stop();
            // TabBox ends highlighting on close; this only covers one of our
            // calls arriving after that (same D-Bus connection, so this empty
            // list is processed last).
            if (overrodeHighlight) sendHighlight([]);
            overrodeHighlight = false;
        }
    }

    // --- popup ---------------------------------------------------------------

    Instantiator {
        active: tabBox.visible
        delegate: PlasmaCore.Dialog {
            title: tabBox.popupTitle
            location: PlasmaCore.Types.Floating
            visible: true
            flags: Qt.Popup | Qt.X11BypassWindowManagerHint
            x: tabBox.screenGeometry.x + (tabBox.screenGeometry.width - mainItem.width) / 2
            y: tabBox.screenGeometry.y + (tabBox.screenGeometry.height - mainItem.height) / 2

            mainItem: FocusScope {
                id: frame
                focus: true

                readonly property var currentGroup: grid.currentItem ? grid.currentItem.group : null
                onCurrentGroupChanged: tabBox.selectedGroup = currentGroup
                Component.onCompleted: tabBox.selectedGroup = currentGroup
                Component.onDestruction: tabBox.selectedGroup = null

                readonly property real screenRatio: tabBox.screenGeometry.width / Math.max(1, tabBox.screenGeometry.height)
                readonly property int maxWidth: tabBox.screenGeometry.width * 0.9
                readonly property int maxHeight: tabBox.screenGeometry.height * 0.75
                // Roughly square grid that fits the screen width.
                readonly property int columns: Math.max(1, Math.min(grid.count,
                    Math.floor(maxWidth / grid.cellWidth),
                    Math.ceil(Math.sqrt(grid.count * 1.6))))
                readonly property int rows: Math.max(1, Math.ceil(grid.count / columns))

                width: Math.min(maxWidth, grid.cellWidth * columns)
                height: Math.min(maxHeight, grid.cellHeight * rows)
                clip: true

                KSvg.FrameSvgItem {
                    id: margins
                    imagePath: "widgets/viewitem"
                    prefix: "hover"
                    visible: false
                }

                GridView {
                    id: grid
                    anchors.fill: parent
                    focus: true
                    model: tabBox.model
                    // Bound to TabBox and only written back when the user
                    // moves (arrows, mouse): assigning it from here would break
                    // the binding and the highlight would stop following Alt+Tab.
                    currentIndex: tabBox.currentIndex
                    onCurrentIndexChanged: if (currentIndex !== tabBox.currentIndex) tabBox.currentIndex = currentIndex
                    keyNavigationWraps: true
                    highlightMoveDuration: 0

                    readonly property int thumbWidth: Kirigami.Units.gridUnit * 16
                    readonly property int thumbHeight: Math.round(thumbWidth / frame.screenRatio)
                    readonly property int captionHeight: Kirigami.Units.gridUnit * 2

                    cellWidth: margins.margins.left + thumbWidth + margins.margins.right
                    cellHeight: margins.margins.top + thumbHeight + captionHeight + margins.margins.bottom

                    highlight: KSvg.FrameSvgItem {
                        imagePath: "widgets/viewitem"
                        prefix: "hover"
                    }

                    delegate: MouseArea {
                        id: cell

                        required property int index
                        required property var model

                        // null for plain windows, { members, label } for groups
                        readonly property var group: Groups.switcherGroup(model.windowId)

                        width: grid.cellWidth
                        height: grid.cellHeight
                        hoverEnabled: true
                        Accessible.name: group ? group.label : model.caption
                        Accessible.role: Accessible.ListItem
                        onClicked: tabBox.model.activate(index)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: margins.margins.left * 2
                            anchors.rightMargin: margins.margins.right * 2
                            anchors.topMargin: margins.margins.top * 2
                            anchors.bottomMargin: margins.margins.bottom * 2
                            spacing: Kirigami.Units.smallSpacing

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // plain window
                                Loader {
                                    anchors.fill: parent
                                    active: !cell.group
                                    sourceComponent: KWin.WindowThumbnail {
                                        wId: cell.model.windowId
                                    }
                                }
                                Kirigami.Icon {
                                    visible: !cell.group
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.bottom
                                    anchors.verticalCenterOffset: -height / 4
                                    width: Kirigami.Units.iconSizes.huge
                                    height: width
                                    source: cell.model.icon
                                }

                                // group mosaic
                                Item {
                                    id: mosaic
                                    anchors.fill: parent
                                    visible: !!cell.group

                                    readonly property var members: cell.group ? cell.group.members : []
                                    readonly property rect bounds: {
                                        let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
                                        for (const w of members) {
                                            const g = w.frameGeometry;
                                            x1 = Math.min(x1, g.x);
                                            y1 = Math.min(y1, g.y);
                                            x2 = Math.max(x2, g.x + g.width);
                                            y2 = Math.max(y2, g.y + g.height);
                                        }
                                        return members.length ? Qt.rect(x1, y1, x2 - x1, y2 - y1) : Qt.rect(0, 0, 1, 1);
                                    }
                                    readonly property real factor: Math.min(width / Math.max(1, bounds.width),
                                                                           height / Math.max(1, bounds.height))
                                    readonly property real offsetX: (width - bounds.width * factor) / 2
                                    readonly property real offsetY: (height - bounds.height * factor) / 2

                                    Repeater {
                                        model: mosaic.members
                                        delegate: Item {
                                            id: piece
                                            required property var modelData
                                            readonly property rect g: modelData.frameGeometry
                                            readonly property int gap: 2

                                            x: mosaic.offsetX + (g.x - mosaic.bounds.x) * mosaic.factor + gap
                                            y: mosaic.offsetY + (g.y - mosaic.bounds.y) * mosaic.factor + gap
                                            width: Math.max(1, g.width * mosaic.factor - gap * 2)
                                            height: Math.max(1, g.height * mosaic.factor - gap * 2)
                                            opacity: modelData.minimized ? 0.45 : 1

                                            KWin.WindowThumbnail {
                                                anchors.fill: parent
                                                wId: piece.modelData.internalId
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                color: "transparent"
                                                radius: Kirigami.Units.cornerRadius
                                                border.width: 1
                                                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.25)
                                            }
                                            Kirigami.Icon {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.bottom
                                                anchors.verticalCenterOffset: -height / 3
                                                width: Math.min(Kirigami.Units.iconSizes.large,
                                                                Math.max(Kirigami.Units.iconSizes.small, parent.width / 3))
                                                height: width
                                                source: piece.modelData.icon
                                            }
                                        }
                                    }

                                    // badge: group icon + member count
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: -Kirigami.Units.smallSpacing
                                        height: badge.implicitHeight + Kirigami.Units.smallSpacing
                                        width: badge.implicitWidth + Kirigami.Units.largeSpacing
                                        radius: height / 2
                                        color: Kirigami.Theme.highlightColor
                                        RowLayout {
                                            id: badge
                                            anchors.centerIn: parent
                                            spacing: Kirigami.Units.smallSpacing / 2
                                            Kirigami.Icon {
                                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                                source: "object-group"
                                                color: Kirigami.Theme.highlightedTextColor
                                                isMask: true
                                            }
                                            PlasmaComponents3.Label {
                                                text: mosaic.members.length
                                                color: Kirigami.Theme.highlightedTextColor
                                                font.bold: true
                                            }
                                        }
                                    }
                                }

                                // Closing "a group" is ambiguous: plain windows only.
                                PlasmaComponents3.Button {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -margins.margins.right * 2
                                    anchors.topMargin: -margins.margins.top * 2
                                    icon.name: "window-close-symbolic"
                                    visible: !cell.group && cell.model.closeable
                                        && typeof tabBox.model.close !== "undefined"
                                        && (cell.containsMouse || hovered || cell.GridView.isCurrentItem
                                            || Kirigami.Settings.tabletMode || Kirigami.Settings.hasTransientTouchInput)
                                    onClicked: tabBox.model.close(cell.index)
                                }
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                Layout.preferredHeight: grid.captionHeight
                                text: cell.group ? cell.group.label : cell.model.caption
                                font.bold: !!cell.group
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.largeSpacing * 2
                    icon.source: "edit-none"
                    text: "No open windows"
                    visible: grid.count === 0
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Left) grid.moveCurrentIndexLeft();
                    else if (event.key === Qt.Key_Right) grid.moveCurrentIndexRight();
                    else if (event.key === Qt.Key_Up) grid.moveCurrentIndexUp();
                    else if (event.key === Qt.Key_Down) grid.moveCurrentIndexDown();
                    else return;
                    event.accepted = true;
                }
            }

            // Intentionally empty: avoids a qFatal on graphics resets.
            onSceneGraphError: () => {}
        }
    }
}
