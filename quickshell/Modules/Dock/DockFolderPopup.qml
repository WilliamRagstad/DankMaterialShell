import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets as DWidgets
import qs.Modals.Common
import "../../Common/settings/DockConfig.js" as DockConfig

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
    // Grid sizing follows the dock's own iconSize config so the popup scales with the dock.
    readonly property real dockIconSize: Math.max(24, dockApps?.iconSize ?? 42)
    readonly property real dockPadding: Math.max(0, dockApps?.options.spacing ?? Theme.spacingM)
    readonly property real popupPadding: Math.max(Theme.spacingS, dockPadding)
    readonly property real popupBottomPadding: popupPadding + Theme.spacingS
    readonly property real popupMargin: Math.max(Theme.spacingS, dockApps?.options.margin ?? 0)
    readonly property real spacing: Math.max(0, dockApps?.options.itemSpacing ?? Theme.spacingS)
    TextMetrics {
        id: labelMetrics
        font.pixelSize: Theme.fontSizeSmall
        text: "Ag"
    }
    readonly property real slotPitch: dockIconSize * 1.6 + spacing
    readonly property real minPopupWidth: Math.max(280, columns >= 2 ? 2 * slotPitch + popupPadding * 2 : slotPitch + popupPadding * 2)
    readonly property real cellWidth: dockIconSize * 1.6
    readonly property real cellLabelHeight: labelMetrics.height * 2
    readonly property real cellHeight: dockIconSize + cellLabelHeight + Theme.spacingXS + Theme.spacingS
    readonly property int rowCount: Math.ceil(members.length / columns)
    readonly property real baseGridWidth: columns * cellWidth + Math.max(0, columns - 1) * spacing
    readonly property real baseGridHeight: rowCount * cellHeight + Math.max(0, rowCount - 1) * spacing
    readonly property real basePopupWidth: Math.max(minPopupWidth, baseGridWidth + popupPadding * 2)
    readonly property bool dockOutlineEnabled: dockApps?.options.borderEnabled === true && !(dockApps?.surfaceContext?.host?.usesConnectedFrameChrome ?? false)
    readonly property real dockOutlineWidth: Math.max(1, dockApps?.options.borderThickness ?? 1)
    readonly property bool magnificationEnabled: dockApps?.options.magnification === true && dockApps?.options.folderMagnification === true
    readonly property real magnificationScale: Math.max(1, Math.min(1.3, (dockApps?.options.folderMagnificationScale ?? 110) / 100))
    readonly property string magnificationProfile: dockApps?.options.magnificationProfile ?? "parabolic"
    readonly property real magnificationRadius: DockConfig.magnificationRadius(dockIconSize, magnificationProfile)
    property real magnificationProgress: 0
    readonly property var magnificationScales: {
        const scales = Array(members.length).fill(1);
        if (!magnificationEnabled || magnificationProgress <= 0.001)
            return scales;
        const cursor = gridMagnification.point.position;
        for (let index = 0; index < members.length; index++) {
            const column = index % columns;
            const row = Math.floor(index / columns);
            const centerX = column * slotPitch + cellWidth / 2;
            const centerY = row * (cellHeight + spacing) + cellHeight / 2;
            const distance = Math.hypot(centerX - cursor.x, centerY - cursor.y);
            const factor = DockConfig.magnificationFactor(distance, magnificationRadius, magnificationProfile);
            scales[index] = 1 + (magnificationScale - 1) * factor * magnificationProgress;
        }
        return scales;
    }
    readonly property var columnExpansions: {
        const expansions = Array(columns).fill(0);
        for (let index = 0; index < magnificationScales.length; index++) {
            const column = index % columns;
            expansions[column] = Math.max(expansions[column], (magnificationScales[index] - 1) * cellWidth);
        }
        return expansions;
    }
    readonly property var rowExpansions: {
        const expansions = Array(rowCount).fill(0);
        for (let index = 0; index < magnificationScales.length; index++) {
            const row = Math.floor(index / columns);
            expansions[row] = Math.max(expansions[row], (magnificationScales[index] - 1) * cellHeight);
        }
        return expansions;
    }
    readonly property real magnificationExpansionWidth: columnExpansions.reduce((sum, extra) => sum + extra, 0)
    readonly property real magnificationExpansionHeight: rowExpansions.reduce((sum, extra) => sum + extra, 0)
    readonly property color popupBorderColor: {
        if (!dockOutlineEnabled)
            return BlurService.borderColor;
        const opacity = dockApps?.options.borderOpacity ?? 1;
        switch (dockApps?.options.borderColor) {
        case "secondary":
            return Theme.withAlpha(Theme.secondary, opacity);
        case "primary":
            return Theme.withAlpha(Theme.primary, opacity);
        default:
            return Theme.withAlpha(Theme.surfaceText, opacity);
        }
    }

    property string layerNamespace: "dms:dock-folder-popup"

    property point anchorPos: Qt.point(screen ? screen.width / 2 : 0, screen ? screen.height - 100 : 0)
    property var anchorItem: null
    property var surfaceContext: null
    property real dockVisibleHeight: 40
    property int reorderFrom: -1
    property int reorderTo: -1

    function previewSlotFor(index) {
        if (reorderFrom < 0 || reorderTo < 0 || reorderFrom === reorderTo)
            return index;
        if (index === reorderFrom)
            return reorderTo;
        if (reorderFrom < reorderTo && index > reorderFrom && index <= reorderTo)
            return index - 1;
        if (reorderFrom > reorderTo && index >= reorderTo && index < reorderFrom)
            return index + 1;
        return index;
    }

    function cellX(column) {
        let x = 0;
        for (let index = 0; index < column; index++)
            x += cellWidth + (columnExpansions[index] ?? 0) + spacing;
        return x;
    }

    function cellY(row) {
        let y = 0;
        for (let index = 0; index < row; index++)
            y += cellHeight + (rowExpansions[index] ?? 0) + spacing;
        return y;
    }

    function folderSlotAt(point) {
        if (members.length === 0 || point.x < 0 || point.y < 0 || point.x > folderGrid.width || point.y > folderGrid.height)
            return -1;
        let best = -1;
        let bestDistance = Infinity;
        for (let slot = 0; slot < members.length; slot++) {
            const column = slot % columns;
            const row = Math.floor(slot / columns);
            const centerX = cellX(column) + (cellWidth + (columnExpansions[column] ?? 0)) / 2;
            const centerY = cellY(row) + (cellHeight + (rowExpansions[row] ?? 0)) / 2;
            const distance = Math.hypot(point.x - centerX, point.y - centerY);
            if (distance < bestDistance) {
                best = slot;
                bestDistance = distance;
            }
        }
        return best;
    }

    function clearFolderReorder() {
        reorderFrom = -1;
        reorderTo = -1;
    }

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

    function requestDissolve() {
        dissolveConfirmDialog.show(
            I18n.tr("Dissolve folder?"),
            I18n.tr("Apps in %1 will return to the dock as individual icons.").arg(currentFolder?.folderName ?? I18n.tr("Folder")),
            () => {
                root.dockApps?.dissolveFolder(root.folderId);
                root.close();
            }
        );
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
        const extent = (surfaceContext?.thickness ?? dockVisibleHeight) / 2 + (dockApps?.options.folderPopupGap ?? Theme.spacingS);
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
        clearFolderReorder();
        anchorItem = null;
        surfaceContext = null;
        if (dockApps)
            dockApps.requestDockShow = false;
    }

    ConfirmModal {
        id: dissolveConfirmDialog
        confirmButtonText: I18n.tr("Dissolve")
        useOverlayLayer: true
    }

    onFolderIdChanged: editMode = false
    Binding {
        target: root
        property: "magnificationProgress"
        value: root.magnificationEnabled && gridMagnification.hovered && root.reorderFrom < 0 ? 1 : 0
        restoreMode: Binding.RestoreNone
    }
    Behavior on magnificationProgress {
        enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            duration: gridMagnification.hovered ? Theme.shorterDuration : Theme.shortDuration
            easing.type: gridMagnification.hovered ? Easing.OutCubic : Easing.InCubic
        }
    }
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
            const maxX = root.width - width - root.popupMargin;
            if (!isVertical) {
                const want = root.anchorPos.x - width / 2;
                return Math.max(root.popupMargin, Math.min(maxX, want));
            }
            if (dockApps?.options.position === SettingsData.Position.Right)
                return Math.max(root.popupMargin, Math.min(maxX, root.anchorPos.x - width));
            return Math.max(root.popupMargin, Math.min(maxX, root.anchorPos.x));
        }
        y: {
            const maxY = root.height - height - root.popupMargin;
            if (isVertical) {
                const want = root.anchorPos.y - height / 2;
                return Math.max(root.popupMargin, Math.min(maxY, want));
            }
            if (dockApps?.options.position === SettingsData.Position.Bottom)
                return Math.max(root.popupMargin, Math.min(maxY, root.anchorPos.y - height));
            return Math.max(root.popupMargin, Math.min(maxY, root.anchorPos.y));
        }

        // Width follows the dock iconSize and column count so more columns widen the
        // grid instead of shrinking cells.
        width: Math.min(root.width - root.popupMargin * 2, root.basePopupWidth + root.magnificationExpansionWidth)
        height: menuColumn.implicitHeight + root.popupPadding + root.popupBottomPadding
        color: Theme.floatingSurface
        radius: Theme.windowRadius
        border.color: root.popupBorderColor
        border.width: root.dockOutlineEnabled ? root.dockOutlineWidth : BlurService.borderWidth

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
            width: parent.width - root.popupPadding * 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: root.popupPadding
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
                            onClicked: root.requestDissolve()
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

            Item {
                id: folderGrid
                width: root.baseGridWidth + root.magnificationExpansionWidth
                height: root.baseGridHeight + root.magnificationExpansionHeight
                implicitWidth: width
                implicitHeight: height
                anchors.horizontalCenter: parent.horizontalCenter

                HoverHandler {
                    id: gridMagnification
                    enabled: root.magnificationEnabled && root.reorderFrom < 0
                }

                Repeater {
                    model: root.members

                    Item {
                        id: memberCell

                        required property var modelData
                        required property int index
                        readonly property string appId: modelData
                        readonly property var entry: DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))
                        readonly property bool running: root.memberToplevels(appId).length > 0
                        readonly property int previewSlot: root.previewSlotFor(index)
                        readonly property int gridColumn: previewSlot % root.columns
                        readonly property int gridRow: Math.floor(previewSlot / root.columns)
                        readonly property real visualScale: root.magnificationScales[index] ?? 1
                        property bool longPressing: false
                        property bool dragging: false
                        property point dragStartPos: Qt.point(0, 0)

                        width: root.cellWidth + (root.columnExpansions[gridColumn] ?? 0)
                        height: root.cellHeight + (root.rowExpansions[gridRow] ?? 0)
                        x: root.cellX(gridColumn)
                        y: root.cellY(gridRow)
                        z: dragging ? 10 : 0

                        Behavior on x {
                            enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                            NumberAnimation {
                                duration: Theme.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on y {
                            enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                            NumberAnimation {
                                duration: Theme.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }

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
                            id: memberContent
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            opacity: memberCell.dragging ? 0.25 : 1
                            scale: memberCell.visualScale

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.shortDuration
                                }
                            }

                            Item {
                                id: iconSlot

                                width: root.dockIconSize
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
                                id: memberLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.cellWidth - Theme.spacingXS * 2
                                text: memberCell.entry?.name || memberCell.appId
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
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

                        // A drag only starts after a real hold (500ms) plus a clear pull;
                        // every click, however long, simply opens the app.
                        MouseArea {
                            id: memberArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: memberCell.dragging ? Qt.DragMoveCursor : Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: memberCell.dragging
                            onPressed: mouse => {
                                if (mouse.button !== Qt.LeftButton)
                                    return;
                                memberCell.dragStartPos = Qt.point(mouse.x, mouse.y);
                                cellLongPress.restart();
                            }
                            onPositionChanged: mouse => {
                                if (!memberCell.dragging) {
                                    if (!memberCell.longPressing || Math.hypot(mouse.x - memberCell.dragStartPos.x, mouse.y - memberCell.dragStartPos.y) <= 10)
                                        return;
                                    memberCell.dragging = true;
                                    root.reorderFrom = memberCell.index;
                                    root.reorderTo = memberCell.index;
                                    const start = mapToItem(null, mouse.x, mouse.y);
                                    dragGhost.show(start.x, start.y, memberCell.appId, memberCell.entry);
                                }
                                cellLongPress.stop();
                                const point = mapToItem(null, mouse.x, mouse.y);
                                dragGhost.move(point.x, point.y);
                                const folderPoint = memberArea.mapToItem(folderGrid, mouse.x, mouse.y);
                                const folderSlot = root.folderSlotAt(folderPoint);
                                if (folderSlot >= 0) {
                                    root.reorderTo = folderSlot;
                                    root.dockApps?.previewExternalDrop(-1);
                                    return;
                                }
                                root.reorderTo = -1;
                                // Dock items part under the ghost with the standard shift springs.
                                const slot = root.dockApps?.nearestSlotToScreenPoint(point.x, point.y, Math.max(56, root.dockApps.targetSize * 0.9)) ?? -1;
                                root.dockApps?.previewExternalDrop(slot);
                            }
                            onReleased: mouse => {
                                cellLongPress.stop();
                                const wasDragging = memberCell.dragging;
                                const fromIndex = root.reorderFrom;
                                const folderPoint = memberArea.mapToItem(folderGrid, mouse.x, mouse.y);
                                const folderSlot = wasDragging ? root.folderSlotAt(folderPoint) : -1;
                                const point = wasDragging ? mapToItem(null, mouse.x, mouse.y) : null;
                                const dockSlot = wasDragging && folderSlot < 0 ? root.dockApps?.nearestSlotToScreenPoint(point.x, point.y, Math.max(56, root.dockApps.targetSize * 0.9)) ?? -1 : -1;
                                memberCell.dragging = false;
                                memberCell.longPressing = false;
                                dragGhost.hide();
                                if (wasDragging) {
                                    root.clearFolderReorder();
                                    root.dockApps?.previewExternalDrop(-1);
                                    if (folderSlot >= 0) {
                                        if (folderSlot !== fromIndex)
                                            root.dockApps?.reorderFolderApps(root.folderId, fromIndex, folderSlot);
                                        return;
                                    }
                                    if (dockSlot < 0)
                                        return;
                                    root.dockApps?.removeAppFromFolderToSlot(root.folderId, memberCell.appId, dockSlot);
                                    root.close();
                                    return;
                                }
                                if (mouse.button === Qt.LeftButton)
                                    root.activateMember(memberCell.appId);
                            }
                            onCanceled: {
                                cellLongPress.stop();
                                memberCell.dragging = false;
                                memberCell.longPressing = false;
                                dragGhost.hide();
                                root.clearFolderReorder();
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
        width: root.dockIconSize + 8
        height: width
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
            implicitSize: root.dockIconSize * 0.8
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
