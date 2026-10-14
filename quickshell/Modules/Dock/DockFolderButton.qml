import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root
    required property var options

    clip: false
    property var appData
    property var dockApps: null
    property int index: -1
    property var parentDockScreen: null
    property bool longPressing: false
    property bool dragging: false
    property point dragStartPos: Qt.point(0, 0)
    property real dragAxisOffset: 0
    property int targetIndex: -1
    property int originalIndex: -1
    property bool isVertical: root.options.position === SettingsData.Position.Left || root.options.position === SettingsData.Position.Right
    property bool isHovered: mouseArea.containsMouse && !dragging
    property bool showTooltip: mouseArea.containsMouse && !dragging
    property real actualIconSize: 40
    readonly property var folderApps: appData?.folderApps ?? []
    property string tooltipText: appData?.folderName || ""

    property bool shouldShowIndicator: {
        if (root.options.hideIndicators || !appData)
            return false;
        return appData.isRunning === true;
    }
    readonly property bool indicatorAtFarEdge: root.options.position === SettingsData.Position.Bottom || root.options.position === SettingsData.Position.Right
    readonly property bool indicatorInPadding: !(root.dockApps?.barHosted ?? false)
    readonly property real indicatorThickness: indicatorInPadding ? root.options.spacing : Math.max(0, ((isVertical ? width : height) - actualIconSize) / 2)

    function cancelDrag() {
        longPressTimer.stop();
        longPressing = false;
        dragging = false;
        dragAxisOffset = 0;
        targetIndex = -1;
        originalIndex = -1;
        if (!dockApps)
            return;
        dockApps.draggedIndex = -1;
        dockApps.dropTargetIndex = -1;
    }

    function activate() {
        dockApps?.openFolderPopup(root, appData?.folderId ?? "");
    }

    Timer {
        id: longPressTimer

        interval: 500
        repeat: false
        onTriggered: {
            if (appData && appData.isPinned)
                longPressing = true;
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        enabled: true
        preventStealing: dragging || longPressing
        cursorShape: longPressing ? Qt.DragMoveCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (appData && appData.isPinned) {
                dragStartPos = Qt.point(mouse.x, mouse.y);
                longPressTimer.start();
            }
        }
        onCanceled: root.cancelDrag()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                dockApps?.removeFolder(appData?.folderId ?? "");
        }

        onReleased: mouse => {
            longPressTimer.stop();

            const wasDragging = dragging;
            const didReorder = wasDragging && targetIndex >= 0 && dockApps && (targetIndex !== originalIndex || dockApps.mixedDropIndex >= 0);

            if (didReorder) {
                const from = originalIndex;
                const to = dockApps.dropTarget(targetIndex);
                const residual = dragAxisOffset - (targetIndex - originalIndex) * (dockApps.targetSize + dockApps.itemSpacing);
                dockApps.settleDrag(dockApps.resolveDropAction(from, to, residual, dockApps.targetSize + dockApps.itemSpacing));
            }

            root.cancelDrag();

            if (wasDragging)
                return;

            dockApps?.openFolderPopup(root, appData?.folderId ?? "");
        }

        onPositionChanged: mouse => {
            if (longPressing && !dragging) {
                const distance = Math.sqrt(Math.pow(mouse.x - dragStartPos.x, 2) + Math.pow(mouse.y - dragStartPos.y, 2));
                if (distance > 5) {
                    dragging = true;
                    targetIndex = index;
                    originalIndex = index;
                    if (dockApps) {
                        dockApps.draggedIndex = index;
                        dockApps.dropTargetIndex = index;
                    }
                }
            }

            if (!dragging || !dockApps)
                return;

            const axisOffset = isVertical ? (mouse.y - dragStartPos.y) : (mouse.x - dragStartPos.x);
            dragAxisOffset = axisOffset;
            dockApps.updateMixedDrag(mouseArea, mouse.x, mouse.y);

            const slotOffset = Math.round(axisOffset / (dockApps.targetSize + dockApps.itemSpacing));
            const newTargetIndex = Math.max(0, Math.min(dockApps.pinnedAppCount - 1, originalIndex + slotOffset));

            if (newTargetIndex !== targetIndex) {
                targetIndex = newTargetIndex;
                dockApps.dropTargetIndex = newTargetIndex;
            }
        }
    }

    readonly property real hoverAnimOffset: hoverBounce.offset

    DockHoverBounce {
        id: hoverBounce
        hovered: root.isHovered
        suppressed: mouseArea.pressed || root.dragging
        barHosted: root.dockApps?.barHosted ?? false
        position: root.options.position
        distance: root.actualIconSize
    }

    Item {
        id: visualContent
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: parent.width
        height: parent.height

        transform: Translate {
            x: {
                if (dragging && !isVertical)
                    return dragAxisOffset;
                if (!dragging && isVertical)
                    return hoverAnimOffset;
                return 0;
            }
            y: {
                if (dragging && isVertical)
                    return dragAxisOffset;
                if (!dragging && !isVertical)
                    return hoverAnimOffset;
                return 0;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.primarySelected
            border.width: 2
            border.color: Theme.primary
            visible: dragging
            z: -1
        }

        Item {
            id: iconSlot

            anchors.fill: parent
            scale: root.options?.enlargeOnHover && root.isHovered ? (root.options?.enlargePercentage ?? 125) / 100 : 1

            // Mini grid previews the first members; a glyph covers empty or sparse folders.
            Grid {
                id: miniGrid

                anchors.centerIn: parent
                columns: 2
                rows: 2
                spacing: Math.max(2, actualIconSize * 0.05)

                Repeater {
                    model: root.folderApps.slice(0, 4)

                    IconImage {
                        required property var modelData
                        readonly property var entry: dockApps?.desktopEntries[Paths.moddedAppId(modelData)] ?? null

                        implicitSize: (actualIconSize - miniGrid.spacing) / 2
                        source: Paths.getAppIcon(Paths.moddedAppId(modelData), entry)
                        mipmap: true
                        smooth: true
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                }
            }

            DIcon {
                anchors.centerIn: parent
                size: actualIconSize * 0.8
                name: "folder"
                color: Theme.surfaceText
                visible: folderApps.length === 0
            }
        }

        Item {
            id: indicatorSlot

            readonly property real cellSize: root.isVertical ? parent.width : parent.height
            readonly property real crossStart: {
                if (root.indicatorAtFarEdge)
                    return root.indicatorInPadding ? cellSize : cellSize - root.indicatorThickness;
                return root.indicatorInPadding ? -root.indicatorThickness : 0;
            }

            x: root.isVertical ? crossStart : 0
            y: root.isVertical ? 0 : crossStart
            width: root.isVertical ? root.indicatorThickness : parent.width
            height: root.isVertical ? parent.height : root.indicatorThickness

            Rectangle {
                anchors.centerIn: parent
                width: root.options.indicatorStyle === "circle" ? Math.max(4, actualIconSize * 0.1) : Math.max(6, actualIconSize * 0.2)
                height: root.options.indicatorStyle === "circle" ? width : Math.max(2, actualIconSize * 0.05)
                radius: height / 2
                visible: root.shouldShowIndicator
                color: Theme.surfaceTextSecondary

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.shortDuration
                    }
                }
            }
        }
    }
}
