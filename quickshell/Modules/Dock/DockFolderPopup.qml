import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets as DWidgets

// Folder grid modal above the dock icon. Modeled on DockContextMenuBase but standalone:
// the rename field needs keyboard focus, and the gear-driven options panel lives outside
// the plain context-menu layout.
PanelWindow {
    id: root

    property var dockApps: null
    property string folderId: ""
    property bool editMode: false
    readonly property var currentFolder: dockApps ? ((dockApps.items ?? []).find(item => item.folderId === root.folderId) ?? null) : null
    readonly property var members: currentFolder?.folderApps ?? []
    readonly property int columns: Math.max(2, Math.min(6, currentFolder?.columns ?? 3))
    readonly property real spacing: Theme.spacingS
    readonly property real cellWidth: Math.floor((menuColumn.width - spacing * (columns - 1)) / columns)

    property string layerNamespace: "dms:dock-folder-popup"
    property real menuMaxWidth: 400
    property real menuMinWidth: 340

    property point anchorPos: Qt.point(screen ? screen.width / 2 : 0, screen ? screen.height - 100 : 0)
    property var anchorItem: null
    property var surfaceContext: null
    property real dockVisibleHeight: 40

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
        editMode = false;
        folderId = targetFolderId;
        dockVisibleHeight = dockHeight || 40;
        if (dockApps)
            dockApps.requestDockShow = true;
        visible = true;
    }

    function beginRename() {
        editMode = true;
        renameField.text = currentFolder?.folderName ?? "";
        Qt.callLater(() => {
            renameField.forceActiveFocus();
            renameField.selectAll();
        });
    }

    function commitRename() {
        if (!root.folderId)
            return;
        const name = renameField.text.trim();
        if (!name)
            return;
        root.dockApps?.renameFolder(root.folderId, name);
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

    onFolderIdChanged: editMode = false
    onCurrentFolderChanged: {
        if (!currentFolder)
            close();
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

        // Width follows the column count so more columns widen the grid instead of shrinking cells.
        width: Math.min(root.width - 20, Math.max(root.menuMinWidth, root.columns * 108 + Theme.spacingM * 2))
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

        // Swallows clicks inside the panel so option editing never dismisses it; only
        // clicks on the screen outside close the popup.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
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
            width: parent.width - Theme.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                visible: root.members.length === 0
                width: parent.width
                text: I18n.tr("Empty folder")
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                width: parent.width
                height: Theme.iconSize + Theme.spacingS

                StyledText {
                    id: titleText

                    anchors.left: parent.left
                    anchors.right: editButton.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.currentFolder?.folderName ?? ""
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    elide: Text.ElideRight
                }

                DWidgets.DActionButton {
                    id: editButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: root.editMode ? "close" : "tune"
                    buttonSize: Theme.iconSize
                    iconSize: 16
                    Accessible.name: I18n.tr("Folder options")
                    onClicked: root.editMode ? root.editMode = false : root.beginRename()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS
                visible: root.editMode

                DWidgets.DTextField {
                    id: renameField

                    width: parent.width
                    placeholderText: I18n.tr("Folder name")
                    text: root.currentFolder?.folderName ?? ""
                    Keys.onEscapePressed: {
                        root.editMode = false;
                        event.accepted = true;
                    }
                    onAccepted: {
                        root.commitRename();
                        root.editMode = false;
                    }
                }

                // Options as a bordered row group, matching the settings row structure:
                // fixed-height rows, label left, control right, dividers between.
                Column {
                    width: parent.width
                    spacing: 0

                    Item {
                        width: parent.width
                        height: Theme.listItemHeight

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Grid columns")
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DWidgets.DActionButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "remove"
                                iconSize: 16
                                buttonSize: Theme.iconSize - 4
                                enabled: root.columns > 2
                                Accessible.name: I18n.tr("Fewer columns")
                                onClicked: root.dockApps?.setFolderColumns(root.folderId, root.columns - 1)
                            }

                            StyledText {
                                id: columnsValue

                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.fontSizeLarge * 2
                                text: String(root.columns)
                                isMonospace: true
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }

                            DWidgets.DActionButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "add"
                                iconSize: 16
                                buttonSize: Theme.iconSize - 4
                                enabled: root.columns < 6
                                Accessible.name: I18n.tr("More columns")
                                onClicked: root.dockApps?.setFolderColumns(root.folderId, root.columns + 1)
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.outlineHeavy
                        }
                    }

                    Item {
                        width: parent.width
                        height: Theme.listItemHeight

                        DWidgets.DIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            name: "call_split"
                            size: 16
                            color: Theme.surfaceText
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS + 16 + Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Dissolve folder")
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.dockApps?.dissolveFolder(root.folderId);
                                root.close();
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineHeavy
                visible: root.editMode
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
                        property bool longPressing: false
                        property bool dragging: false
                        property point dragStartPos: Qt.point(0, 0)

                        width: root.cellWidth
                        height: root.cellWidth * 0.5 + Theme.fontSizeSmall + Theme.spacingXS + Theme.spacingS

                        Timer {
                            id: cellLongPress

                            interval: 500
                            repeat: false
                            onTriggered: memberCell.longPressing = true
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.cornerRadius
                            color: memberArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            opacity: memberCell.dragging ? 0.25 : 1

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.shortDuration
                                }
                            }

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
                                }

                                DWidgets.DIcon {
                                    anchors.centerIn: parent
                                    size: iconSlot.width * 0.6
                                    name: "extension"
                                    color: Theme.surfaceText
                                    visible: !memberIcon.visible
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

                        // Drag-out accepts a long-press start or a decisive fast pull; a
                        // plain click still activates and right-click pops it to the dock.
                        MouseArea {
                            id: memberArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: memberCell.dragging ? Qt.DragMoveCursor : Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: memberCell.dragging || memberCell.longPressing
                            onPressed: mouse => {
                                if (mouse.button !== Qt.LeftButton)
                                    return;
                                memberCell.dragStartPos = Qt.point(mouse.x, mouse.y);
                                cellLongPress.restart();
                            }
                            onPositionChanged: mouse => {
                                const pulled = Math.hypot(mouse.x - memberCell.dragStartPos.x, mouse.y - memberCell.dragStartPos.y);
                                if (!memberCell.dragging && (memberCell.longPressing || pulled > 24)) {
                                    memberCell.dragging = true;
                                    const start = mapToItem(null, mouse.x, mouse.y);
                                    dragGhost.show(start.x, start.y, memberCell.appId, memberCell.entry);
                                }
                                if (!memberCell.dragging)
                                    return;
                                cellLongPress.stop();
                                const point = mapToItem(null, mouse.x, mouse.y);
                                dragGhost.move(point.x, point.y);
                                // Dock items part under the ghost with the standard shift springs.
                                const slot = root.dockApps?.nearestSlotToScreenPoint(point.x, point.y, Math.max(56, root.dockApps.targetSize * 0.9)) ?? -1;
                                root.dockApps?.previewExternalDrop(slot);
                            }
                            onReleased: mouse => {
                                cellLongPress.stop();
                                if (memberCell.dragging) {
                                    memberCell.dragging = false;
                                    memberCell.longPressing = false;
                                    dragGhost.hide();
                                    const point = mapToItem(null, mouse.x, mouse.y);
                                    const slot = root.dockApps?.nearestSlotToScreenPoint(point.x, point.y, Math.max(56, root.dockApps.targetSize * 0.9)) ?? -1;
                                    root.dockApps?.previewExternalDrop(-1);
                                    if (slot < 0)
                                        return;
                                    root.dockApps?.removeAppFromFolderToSlot(root.folderId, memberCell.appId, slot);
                                    root.close();
                                    return;
                                }
                                memberCell.longPressing = false;
                                if (mouse.button === Qt.LeftButton)
                                    root.activateMember(memberCell.appId);
                            }
                            onCanceled: {
                                cellLongPress.stop();
                                memberCell.dragging = false;
                                memberCell.longPressing = false;
                                dragGhost.hide();
                                root.dockApps?.previewExternalDrop(-1);
                            }
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    root.dockApps?.removeAppFromFolderToDock(root.folderId, memberCell.appId);
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
        function move(x, y) {
            dragGhost.x = x - dragGhost.width / 2;
            dragGhost.y = y - dragGhost.height / 2;
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
