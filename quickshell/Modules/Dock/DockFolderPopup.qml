import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets as DWidgets

// Folder grid modal above the dock icon. Modeled on DockContextMenuBase but standalone:
// the rename field needs keyboard focus and the drag ghost must live outside the menu column.
PanelWindow {
    id: root

    property var dockApps: null
    property string folderId: ""
    readonly property var currentFolder: dockApps ? ((dockApps.items ?? []).find(item => item.folderId === root.folderId) ?? null) : null
    readonly property var members: currentFolder?.folderApps ?? []
    readonly property int columns: 3
    readonly property real spacing: Theme.spacingS
    readonly property real cellWidth: Math.floor((menuColumn.width - spacing * (columns - 1)) / columns)

    property string layerNamespace: "dms:dock-folder-popup"
    property real menuMaxWidth: 400
    property real menuMinWidth: 340

    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    // The rename field needs keyboard input.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    function showForButton(button, targetFolderId, dockHeight, dockScreen) {
        if (dockScreen)
            screen = dockScreen;
        surfaceContext = button?.dockApps?.surfaceContext ?? null;
        dockApps = button?.dockApps ?? null;
        anchorItem = button;
        renameField.text = "";
        folderId = targetFolderId;
        dockVisibleHeight = dockHeight || 40;
        if (dockApps)
            dockApps.requestDockShow = true;
        visible = true;
    }

    function close() {
        visible = false;
    }

    function updatePosition() {
        if (!anchorItem || !screen)
            return;
        const point = surfaceContext?.screenPoint(anchorItem, anchorItem.width / 2, anchorItem.height / 2);
        if (!point)
            return;
        const extent = (surfaceContext?.thickness ?? dockVisibleHeight) / 2 + Theme.spacingS;
        switch (dockApps?.options.position) {
        case SettingsData.Position.Left:
            anchorPos = Qt.point(point.x + extent, point.y);
            return;
        case SettingsData.Position.Right:
            anchorPos = Qt.point(point.x - extent, point.y);
            return;
        case SettingsData.Position.Top:
            anchorPos = Qt.point(point.x, point.y + extent);
            return;
        default:
            anchorPos = Qt.point(point.x, point.y - extent);
        }
    }

    onAnchorItemChanged: {
        if (!anchorItem) {
            close();
            return;
        }
        updatePosition();
    }
    onVisibleChanged: {
        if (visible) {
            updatePosition();
            return;
        }
        anchorItem = null;
        surfaceContext = null;
        if (dockApps)
            dockApps.requestDockShow = false;
    }

    onCurrentFolderChanged: {
        if (!currentFolder) {
            close();
            return;
        }
        // Fresh item objects arrive on every model rebuild; never clobber in-progress edits.
        if (!renameField.activeFocus)
            renameField.text = currentFolder.folderName;
    }

    function memberToplevels(appId) {
        const modded = Paths.moddedAppId(appId);
        return (currentFolder?.allWindows ?? []).filter(window => Paths.moddedAppId(window.toplevel?.appId || "unknown") === modded).map(window => window.toplevel);
    }

    function activateMember(appId) {
        const toplevels = memberToplevels(appId);
        if (toplevels.length > 0) {
            CompositorService.activateToplevel(toplevels[0]);
            root.close();
            return;
        }
        const core = (AppSearchService.coreApps || []).find(app => app.builtInPluginId === appId);
        if (core) {
            AppSearchService.executeCoreApp(core);
            root.close();
            return;
        }
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry) {
            AppUsageHistoryData.addAppUsage({
                "id": appId,
                "name": entry.name || appId,
                "icon": entry.icon ? String(entry.icon) : "",
                "exec": entry.exec || "",
                "comment": entry.comment || ""
            });
            SessionService.launchDesktopEntry(entry);
        }
        root.close();
    }

    WindowBlur {
        targetWindow: root
        surfaceColor: menuContainer.color
        blurX: menuContainer.x
        blurY: menuContainer.y
        blurWidth: root.visible ? menuContainer.width : 0
        blurHeight: root.visible ? menuContainer.height : 0
        blurRadius: Theme.windowRadius
    }

    screen: null
    visible: false
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Rectangle {
        id: menuContainer

        readonly property bool isVertical: dockApps?.options.position === SettingsData.Position.Left || dockApps?.options.position === SettingsData.Position.Right

        x: {
            if (!isVertical) {
                const want = root.anchorPos.x - width / 2;
                return Math.max(10, Math.min(root.width - width - 10, want));
            }
            if (dockApps?.options.position === SettingsData.Position.Right)
                return Math.max(10, root.anchorPos.x - width);
            return Math.min(root.width - width - 10, root.anchorPos.x);
        }
        y: {
            if (isVertical) {
                const want = root.anchorPos.y - height / 2;
                return Math.max(10, Math.min(root.height - height - 10, want));
            }
            if (dockApps?.options.position === SettingsData.Position.Bottom)
                return Math.max(10, root.anchorPos.y - height);
            return Math.min(root.height - height - 10, root.anchorPos.y);
        }

        width: Math.min(root.menuMaxWidth, Math.max(root.menuMinWidth, menuColumn.implicitWidth + Theme.spacingS * 2))
        height: menuColumn.implicitHeight + Theme.spacingS * 2
        color: Theme.floatingSurface
        radius: Theme.windowRadius
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        opacity: root.visible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.emphasizedEasing
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.leftMargin: 2
            anchors.rightMargin: -2
            anchors.bottomMargin: -4
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.15)
            z: -1
        }

        Column {
            id: menuColumn
            width: parent.width - Theme.spacingS * 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS
            spacing: 1

            StyledText {
                visible: root.members.length === 0
                width: parent.width
                text: I18n.tr("Empty folder")
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            DWidgets.DTextField {
                id: renameField

                width: parent.width
                placeholderText: I18n.tr("Folder name")
                onAccepted: {
                    if (root.folderId)
                        root.dockApps?.renameFolder(root.folderId, renameField.text);
                }
                onEditingFinished: {
                    if (!root.folderId)
                        return;
                    const name = renameField.text.trim();
                    if (!name || name === (root.currentFolder?.folderName ?? ""))
                        return;
                    root.dockApps?.renameFolder(root.folderId, name);
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineHeavy
            }

            Grid {
                width: parent.width
                columns: root.columns
                columnSpacing: root.spacing
                rowSpacing: root.spacing

                Repeater {
                    model: root.members

                    Item {
                        id: memberCell

                        required property var modelData
                        readonly property string appId: modelData
                        readonly property var entry: DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))
                        readonly property bool running: root.memberToplevels(appId).length > 0
                        property bool cellDragging: false
                        property point dragStartPos: Qt.point(0, 0)

                        width: root.cellWidth
                        height: root.cellWidth * 0.5 + Theme.fontSizeSmall + Theme.spacingXS + Theme.spacingS

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.cornerRadius
                            color: memberArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            Item {
                                id: iconSlot

                                width: root.cellWidth * 0.45
                                height: width
                                anchors.horizontalCenter: parent.horizontalCenter

                                IconImage {
                                    id: memberIcon

                                    anchors.centerIn: parent
                                    implicitSize: parent.width
                                    source: Paths.getAppIcon(Paths.moddedAppId(memberCell.appId), memberCell.entry)
                                    mipmap: true
                                    smooth: true
                                    asynchronous: true
                                    visible: status === Image.Ready
                                    opacity: memberCell.cellDragging ? 0.3 : 1
                                }

                                DWidgets.DIcon {
                                    anchors.centerIn: parent
                                    size: iconSlot.width * 0.6
                                    name: "extension"
                                    color: Theme.surfaceText
                                    visible: !memberIcon.visible
                                    opacity: memberCell.cellDragging ? 0.3 : 1
                                }
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.cellWidth - Theme.spacingXS
                                text: memberCell.entry?.name || memberCell.appId
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        Rectangle {
                            readonly property bool running: memberCell.running

                            width: Math.max(4, iconSlot.width * 0.1)
                            height: width
                            radius: width / 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.spacingXXS
                            color: Theme.surfaceTextSecondary
                            visible: running
                        }

                        DWidgets.DActionButton {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: -Theme.spacingXS
                            iconName: "close"
                            iconSize: 12
                            buttonSize: 20
                            visible: memberArea.containsMouse && !memberCell.cellDragging
                            onClicked: {
                                root.dockApps?.removeAppFromFolder(root.folderId, memberCell.appId);
                            }
                        }

                        Timer {
                            id: longPressTimer

                            interval: 500
                            repeat: false
                            onTriggered: memberCell.cellDragging = true
                        }

                        MouseArea {
                            id: memberArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: memberCell.cellDragging ? Qt.DragMoveCursor : Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: memberCell.cellDragging
                            onPressed: mouse => {
                                if (mouse.button !== Qt.LeftButton)
                                    return;
                                dragStartPos = Qt.point(mouse.x, mouse.y);
                                longPressTimer.restart();
                            }
                            onPositionChanged: mouse => {
                                if (!memberCell.cellDragging) {
                                    if (Math.hypot(mouse.x - dragStartPos.x, mouse.y - dragStartPos.y) > 10) {
                                        longPressTimer.stop();
                                        memberCell.cellDragging = true;
                                    }
                                }
                                if (!memberCell.cellDragging)
                                    return;
                                // mapToItem(null) yields window-content coordinates, and this
                                // full-screen window's content matches screen coordinates.
                                const point = mapToItem(null, mouse.x, mouse.y);
                                dragGhost.show(point.x, point.y, memberCell.appId, memberCell.entry);
                            }
                            onReleased: mouse => {
                                longPressTimer.stop();
                                if (memberCell.cellDragging) {
                                    memberCell.cellDragging = false;
                                    dragGhost.hide();
                                    const point = mapToItem(null, mouse.x, mouse.y);
                                    const slot = root.dockApps?.nearestSlotToScreenPoint(point.x, point.y, root.dockApps.targetSize * 0.9) ?? -1;
                                    if (slot < 0)
                                        return;
                                    root.dockApps?.removeAppFromFolder(root.folderId, memberCell.appId);
                                    root.dockApps?.insertPinAtSlot(memberCell.appId, slot);
                                    return;
                                }
                                if (mouse.button === Qt.LeftButton)
                                    root.activateMember(memberCell.appId);
                            }
                            onCanceled: {
                                longPressTimer.stop();
                                memberCell.cellDragging = false;
                                dragGhost.hide();
                            }
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    root.dockApps?.removeAppFromFolder(root.folderId, memberCell.appId);
                                    root.close();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Drag ghost lives beside the menu column so Column layout never reflows around it.
    Item {
        id: dragGhost

        visible: false
        width: 44
        height: 44
        z: 100

        function show(x, y, appId, entry) {
            ghostIcon.source = Paths.getAppIcon(Paths.moddedAppId(appId), entry);
            dragGhost.x = x - dragGhost.width / 2;
            dragGhost.y = y - dragGhost.height / 2;
            dragGhost.visible = true;
        }
        function hide() {
            dragGhost.visible = false;
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.primarySelected
            border.width: 1
            border.color: Theme.primary
        }

        IconImage {
            id: ghostIcon

            anchors.centerIn: parent
            implicitSize: 36
            mipmap: true
            smooth: true
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.close()
    }
}
