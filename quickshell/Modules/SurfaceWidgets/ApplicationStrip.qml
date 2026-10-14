import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Dock
import qs.Widgets
import "../../Common/settings/DockConfig.js" as DockConfig
import "ApplicationModel.js" as ApplicationModel

Item {
    id: root

    required property var surfaceContext
    required property var options
    property bool renderItems: true
    property var mixedStrip: null
    property int mixedDropIndex: -1
    onDraggedIndexChanged: {
        if (draggedIndex >= 0)
            return;
        mixedDropIndex = -1;
        mixedStrip?.cancelDrag();
        modelUpdate.schedule();
    }
    function updateMixedDrag(item, x, y) {
        if (!mixedStrip)
            return;
        mixedDropIndex = mixedStrip.dropIndex(item, x, y, entry => entry.appData?.isPinned === true && !["launcher", "overflow-toggle"].includes(entry.appData.type));
        mixedStrip.draggingIndex = mixedStrip.appSlot(draggedIndex);
        mixedStrip.targetIndex = mixedDropIndex;
    }
    function dropTarget(localTarget) {
        return mixedStrip?.model[mixedDropIndex]?.appIndex ?? localTarget;
    }
    readonly property var items: repeater.dockItems
    property int desktopRevision: 0
    readonly property var desktopEntries: {
        desktopRevision;
        const entries = {};
        for (const item of items) {
            if (item.isCoreApp || !item.appId || item.appId.startsWith("__") || ApplicationModel.isFolderToken(item.appId) || item.appId in entries)
                continue;
            entries[item.appId] = DesktopEntries.heuristicLookup(item.appId);
        }
        return entries;
    }
    function refreshDesktopEntries() {
        desktopRevision++;
    }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.refreshDesktopEntries();
        }
    }
    readonly property real itemSpacing: layoutFlow.spacing
    readonly property int renderedCount: repeater.count
    function itemAt(index) {
        return repeater.itemAt(index);
    }
    readonly property bool barHosted: surfaceContext.kind === "bar"
    readonly property var pinnedApps: barHosted ? SessionData.barPinnedApps : SessionData.getDockPins(surfaceContext.configId)
    // Folders are dock-only; the bar keeps its plain appId pin list.
    readonly property var dockFolders: barHosted ? ({}) : SessionData.getDockFolders(surfaceContext.configId)
    onDockFoldersChanged: modelUpdate.schedule()
    function setPinnedApps(apps) {
        if (barHosted)
            SessionData.setBarPinnedApps(apps);
        else
            SessionData.setDockPins(surfaceContext.configId, apps);
    }
    function isPinnedApp(id) {
        return pinnedApps.includes(id);
    }
    function addPinnedApp(id) {
        if (id && !isPinnedApp(id))
            setPinnedApps(pinnedApps.concat([id]));
    }
    function removePinnedApp(id) {
        setPinnedApps(pinnedApps.filter(app => app !== id));
    }
    function settleDrag(apply) {
        suppressShiftAnimation = true;
        apply();
        draggedIndex = -1;
        dropTargetIndex = -1;
        modelUpdate.schedule();
        modelUpdate.flush();
        Qt.callLater(() => root.suppressShiftAnimation = false);
    }
    property var contextMenu: null
    property var trashContextMenu: null
    property var folderPopup: null
    function openFolderPopup(item, folderId) {
        if (barHosted || !folderPopup || !item || !folderId)
            return;
        folderPopup.showForButton(item, folderId, targetSize, dockScreen);
    }
    property bool requestDockShow: false
    property int pinnedAppCount: 0
    property bool groupByApp: false
    property bool isVertical: false
    property var dockScreen: null
    property real iconSize: 40
    property bool usesOverlayLayer: false
    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property bool suppressShiftAnimation: false
    property int maxVisibleApps: root.options.maxVisibleApps
    property int maxVisibleRunningApps: root.options.maxVisibleRunningApps
    property bool overflowExpanded: false
    property int overflowItemCount: 0

    readonly property real targetSize: barHosted ? iconSize * (options.iconSizePercentage ?? 100) / 100 : iconSize
    readonly property real indicatorLane: root.barHosted && !root.options.hideIndicators ? DockConfig.indicatorLane(root.options) : 0
    readonly property real crossSize: {
        // The lane is mirrored so icons stay centered on the bar.
        const needed = root.targetSize + root.indicatorLane * 2;
        if (!root.barHosted)
            return needed;
        // A bar pill cannot grow past its widget thickness, so the lane yields there.
        return Math.min(needed, root.surfaceContext?.widgetThickness ?? needed);
    }
    readonly property var hoveredButton: {
        for (let i = 0; i < repeater.count; i++) {
            const button = repeater.itemAt(i)?.dockButton;
            if (button?.showTooltip)
                return button;
        }
        return null;
    }
    clip: false
    property bool _switchingPosition: false
    implicitWidth: appLayout.width
    implicitHeight: appLayout.height

    function focusFirst() {
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (!item?.activeFocusOnTab)
                continue;
            item.forceActiveFocus();
            return;
        }
    }
    function movePinnedApp(fromDockIndex, toDockIndex) {
        const next = ApplicationModel.movePin(pinnedApps, items, fromDockIndex, toDockIndex);
        if (next !== pinnedApps)
            setPinnedApps(next);
    }

    function newFolderId() {
        return "f" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
    }
    // Pin strings stay raw while strip items carry substitution-resolved ids; merge ops
    // must translate back before touching the pin list.
    function rawPinFor(appId) {
        return pinnedApps.find(pin => Paths.moddedAppId(pin) === appId) ?? null;
    }
    function createFolderFromPins(srcAppId, dstAppId) {
        if (barHosted)
            return;
        const src = rawPinFor(srcAppId);
        const dst = rawPinFor(dstAppId);
        if (!src || !dst)
            return;
        const folderId = newFolderId();
        const folders = Object.assign({}, dockFolders);
        const result = ApplicationModel.createFolder(pinnedApps, folders, src, dst, folderId);
        if (!result)
            return;
        result.folders[folderId].name = ApplicationModel.nextFolderName(folders);
        setPinnedApps(result.pins);
        SessionData.setDockFolders(surfaceContext.configId, result.folders);
    }
    function addToFolder(folderId, appId) {
        if (barHosted)
            return;
        const raw = rawPinFor(appId);
        if (!raw)
            return;
        const result = ApplicationModel.addToFolder(pinnedApps, dockFolders, folderId, raw);
        if (!result)
            return;
        setPinnedApps(result.pins);
        SessionData.setDockFolders(surfaceContext.configId, result.folders);
    }
    function removeAppFromFolder(folderId, appId) {
        if (barHosted)
            return;
        const result = ApplicationModel.removeFromFolder(pinnedApps, dockFolders, folderId, appId);
        if (!result)
            return;
        setPinnedApps(result.pins);
        SessionData.setDockFolders(surfaceContext.configId, result.folders);
    }
    // Right-click on the folder icon: drop the token and its contents together.
    function removeFolder(folderId) {
        if (barHosted || !folderId)
            return;
        const folders = Object.assign({}, dockFolders);
        delete folders[folderId];
        setPinnedApps(pinnedApps.filter(pin => pin !== ApplicationModel.folderToken(folderId)));
        SessionData.setDockFolders(surfaceContext.configId, folders);
    }
    // Folder-modal drag-out: remove from the folder and re-pin at a strip slot in one
    // settle. The insert index is corrected against the post-removal pin list, because
    // a dissolved folder token shifts pin positions.
    function removeAppFromFolderToSlot(folderId, appId, slotIndex) {
        if (barHosted)
            return;
        const raw = rawPinFor(appId);
        if (!raw)
            return;
        const result = ApplicationModel.removeFromFolder(pinnedApps, dockFolders, folderId, raw);
        if (!result)
            return;
        let insertAt = ApplicationModel.pinInsertIndex(items, slotIndex);
        const tokenIndexPre = pinnedApps.indexOf(ApplicationModel.folderToken(folderId));
        if (tokenIndexPre >= 0 && tokenIndexPre < insertAt && result.pins.length === pinnedApps.length - 1)
            insertAt--;
        const pins = result.pins.slice();
        if (pins.includes(raw))
            return;
        pins.splice(Math.max(0, Math.min(insertAt, pins.length)), 0, raw);
        setPinnedApps(pins);
        SessionData.setDockFolders(surfaceContext.configId, result.folders);
    }
    function renameFolder(folderId, name) {
        if (barHosted)
            return;
        const folders = ApplicationModel.renameFolder(dockFolders, folderId, name.trim());
        if (folders)
            SessionData.setDockFolders(surfaceContext.configId, folders);
    }
    function insertPinAtSlot(appId, slotIndex) {
        if (barHosted || !appId || isPinnedApp(appId))
            return;
        const pins = pinnedApps.slice();
        pins.splice(Math.min(ApplicationModel.pinInsertIndex(items, slotIndex), pins.length), 0, appId);
        setPinnedApps(pins);
    }
    // Folder-modal drag-out drop targeting: nearest rendered strip slot to a screen point.
    function nearestSlotToScreenPoint(x, y, maxDistance) {
        let best = -1;
        let bestDist = maxDistance;
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (!item || item.width <= 0)
                continue;
            const point = surfaceContext.screenPoint(item, item.width / 2, item.height / 2);
            if (!point)
                continue;
            const dist = Math.hypot(point.x - x, point.y - y);
            if (dist < bestDist) {
                bestDist = dist;
                best = i;
            }
        }
        return best;
    }
    // A pin drag either reorders (off-center release) or merges onto the icon it covers
    // (centered release). The strip owns the decision; buttons only report geometry.
    function resolveDropAction(from, to, residual, slotPitch) {
        const source = items[from];
        const target = items[to];
        if (ApplicationModel.dropMode(residual, slotPitch) === "merge" && from !== to && canMergePinItems(source, target))
            return () => mergePinItems(source, target);
        return () => movePinnedApp(from, to);
    }
    function canMergePinItems(source, target) {
        if (barHosted || !source?.isPinned || !target?.isPinned)
            return false;
        const blocked = ["launcher", "separator", "overflow-toggle"];
        if (blocked.includes(source.type) || blocked.includes(target.type))
            return false;
        return !(source.type === "folder" && target.type === "folder");
    }
    function mergePinItems(source, target) {
        if (target.type === "folder")
            addToFolder(target.folderId, source.appId);
        else if (source.type === "folder")
            addToFolder(source.folderId, target.appId);
        else
            createFolderFromPins(source.appId, target.appId);
    }

    // Folder tokens consume their member apps, so those apps neither show as their own
    // groups nor lose running state: their windows aggregate into the folder item.
    function buildFolderItems(pinnedApps, sortedToplevels) {
        const folders = new Map();
        for (const rawPin of pinnedApps) {
            const folderId = ApplicationModel.parseFolderToken(rawPin);
            if (folderId === null || folders.has(folderId))
                continue;
            const folder = dockFolders[folderId];
            if (!folder)
                continue;
            const members = (folder.apps || []).map(appId => Paths.moddedAppId(appId));
            const windows = [];
            sortedToplevels.forEach((toplevel, index) => {
                if (members.includes(Paths.moddedAppId(toplevel.appId || "unknown")))
                    windows.push({
                        toplevel: toplevel,
                        index: index
                    });
            });
            folders.set(folderId, {
                uniqueKey: "folder_" + folderId,
                type: "folder",
                appId: ApplicationModel.folderToken(folderId),
                folderId: folderId,
                folderName: folder.name || I18n.tr("Folder"),
                folderApps: folder.apps || [],
                toplevel: null,
                isPinned: true,
                isRunning: windows.length > 0,
                windowCount: windows.length,
                allWindows: windows,
                isCoreApp: false,
                coreAppData: null,
                isInOverflow: false
            });
        }
        return folders;
    }

    function groupedItem(group) {
        const firstWindow = group.windows.length > 0 ? group.windows[0] : null;
        return {
            uniqueKey: "grouped_" + group.appId,
            type: "grouped",
            appId: group.appId,
            toplevel: firstWindow ? firstWindow.toplevel : null,
            isPinned: group.isPinned,
            isRunning: group.windows.length > 0,
            windowCount: group.windows.length,
            allWindows: group.windows,
            isCoreApp: group.isCoreApp || false,
            coreAppData: group.coreAppData || null,
            isInOverflow: false
        };
    }

    Item {
        id: appLayout
        width: layoutFlow.width
        height: layoutFlow.height

        Behavior on width {
            enabled: !root._switchingPosition
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            enabled: !root._switchingPosition
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }
        anchors.centerIn: parent

        Flow {
            id: layoutFlow
            layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight
            flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: root.options.itemSpacing ?? Theme.spacingS

            Repeater {
                id: repeater

                property var dockItems: []

                model: ScriptModel {
                    values: root.renderItems ? repeater.dockItems : []
                    objectProp: "uniqueKey"
                }

                Component.onCompleted: updateModel()

                function isOnScreen(toplevel, screenName) {
                    if (!toplevel.screens)
                        return false;
                    for (let i = 0; i < toplevel.screens.length; i++) {
                        if (toplevel.screens[i]?.name === screenName)
                            return true;
                    }
                    return false;
                }

                function getCoreAppData(appId) {
                    if (typeof AppSearchService === "undefined")
                        return null;
                    return (AppSearchService.coreApps || []).find(app => app.builtInPluginId === appId) ?? null;
                }

                function buildBaseItems() {
                    const pinnedApps = [...(root.pinnedApps || [])];
                    const allToplevels = root.visibleWindows;
                    const sortedToplevels = (root.options.isolateDisplays && root.dockScreen) ? allToplevels.filter(t => isOnScreen(t, root.dockScreen.name)) : allToplevels;

                    if (root.groupByApp) {
                        return buildGroupedItems(pinnedApps, sortedToplevels);
                    }
                    return buildUngroupedItems(pinnedApps, sortedToplevels);
                }

                function buildGroupedItems(pinnedApps, sortedToplevels) {
                    const items = [];
                    const appGroups = new Map();
                    const separatePinnedAndRunning = root.options.separatePinnedAndRunningApps;
                    const folderItems = root.buildFolderItems(pinnedApps, sortedToplevels);
                    const consumed = new Set();
                    folderItems.forEach(item => item.folderApps.forEach(app => consumed.add(Paths.moddedAppId(app))));

                    if (!separatePinnedAndRunning) {
                        pinnedApps.forEach(rawAppId => {
                            if (ApplicationModel.isFolderToken(rawAppId))
                                return;
                            const appId = Paths.moddedAppId(rawAppId);
                            if (consumed.has(appId))
                                return;
                            const coreAppData = getCoreAppData(appId);
                            appGroups.set(appId, {
                                appId: appId,
                                isPinned: true,
                                windows: [],
                                isCoreApp: coreAppData !== null,
                                coreAppData: coreAppData
                            });
                        });
                    }

                    sortedToplevels.forEach((toplevel, index) => {
                        const identity = ApplicationModel.windowIdentity(toplevel, Paths.moddedAppId(toplevel.appId || "unknown"), AppSearchService.coreApps || []);
                        if (consumed.has(identity.appId))
                            return;
                        const appId = identity.appId;
                        const coreAppData = identity.coreAppData;

                        if (!appGroups.has(appId)) {
                            appGroups.set(appId, {
                                appId: appId,
                                isPinned: false,
                                windows: [],
                                isCoreApp: coreAppData !== null,
                                coreAppData: coreAppData
                            });
                        }
                        appGroups.get(appId).windows.push({
                            toplevel: toplevel,
                            index: index
                        });
                    });

                    const pinnedGroups = [];
                    const unpinnedGroups = [];
                    const seenPins = new Set();

                    // Pin order drives the strip, so pinned items emit in pin sequence with
                    // folders placed at their token positions.
                    pinnedApps.forEach(rawAppId => {
                        const folderId = ApplicationModel.parseFolderToken(rawAppId);
                        if (folderId !== null) {
                            if (folderItems.has(folderId) && !seenPins.has(ApplicationModel.folderToken(folderId))) {
                                seenPins.add(ApplicationModel.folderToken(folderId));
                                pinnedGroups.push(folderItems.get(folderId));
                            }
                            return;
                        }
                        if (separatePinnedAndRunning)
                            return;
                        const appId = Paths.moddedAppId(rawAppId);
                        if (seenPins.has(appId) || !appGroups.has(appId))
                            return;
                        seenPins.add(appId);
                        pinnedGroups.push(root.groupedItem(appGroups.get(appId)));
                    });

                    if (separatePinnedAndRunning) {
                        pinnedApps.forEach(rawAppId => {
                            const folderId = ApplicationModel.parseFolderToken(rawAppId);
                            if (folderId !== null) {
                                if (folderItems.has(folderId) && !seenPins.has(ApplicationModel.folderToken(folderId))) {
                                    seenPins.add(ApplicationModel.folderToken(folderId));
                                    pinnedGroups.push(folderItems.get(folderId));
                                }
                                return;
                            }
                            const appId = Paths.moddedAppId(rawAppId);
                            if (seenPins.has(appId) || consumed.has(appId))
                                return;
                            seenPins.add(appId);
                            pinnedGroups.push(ApplicationModel.pinnedItem(appId, getCoreAppData(appId), false));
                        });
                    }

                    appGroups.forEach(group => {
                        if (group.isPinned)
                            return;
                        unpinnedGroups.push(root.groupedItem(group));
                    });

                    pinnedGroups.forEach(item => items.push(item));
                    insertLauncher(items);

                    if (pinnedGroups.length > 0 && unpinnedGroups.length > 0) {
                        items.push(ApplicationModel.separator("separator_grouped"));
                    }
                    unpinnedGroups.forEach(item => items.push(item));

                    root.pinnedAppCount = pinnedGroups.length + (root.options.launcherEnabled ? 1 : 0);
                    return {
                        items,
                        pinnedCount: pinnedGroups.length,
                        runningCount: unpinnedGroups.length
                    };
                }

                function buildUngroupedItems(pinnedApps, sortedToplevels) {
                    const items = [];
                    const runningAppIds = new Set();
                    const windowItems = [];
                    const separatePinnedAndRunning = root.options.separatePinnedAndRunningApps;
                    const folderItems = root.buildFolderItems(pinnedApps, sortedToplevels);
                    const consumed = new Set();
                    folderItems.forEach(item => item.folderApps.forEach(app => consumed.add(Paths.moddedAppId(app))));

                    sortedToplevels.forEach((toplevel, index) => {
                        const uniqueKey = CompositorService.windowKey(toplevel);
                        const identity = ApplicationModel.windowIdentity(toplevel, Paths.moddedAppId(toplevel.appId || "unknown"), AppSearchService.coreApps || []);
                        if (consumed.has(identity.appId))
                            return;
                        const finalAppId = identity.appId;
                        const coreAppData = identity.coreAppData;
                        const isCoreApp = identity.isCoreApp;
                        windowItems.push({
                            uniqueKey: uniqueKey,
                            type: "window",
                            appId: finalAppId,
                            toplevel: toplevel,
                            isPinned: false,
                            isRunning: true,
                            isCoreApp: isCoreApp,
                            coreAppData: coreAppData,
                            isInOverflow: false
                        });
                        runningAppIds.add(finalAppId);
                    });

                    const remainingWindowItems = windowItems.slice();

                    pinnedApps.forEach(rawAppId => {
                        const folderId = ApplicationModel.parseFolderToken(rawAppId);
                        if (folderId !== null) {
                            if (folderItems.has(folderId))
                                items.push(folderItems.get(folderId));
                            return;
                        }
                        const appId = Paths.moddedAppId(rawAppId);
                        const coreAppData = getCoreAppData(appId);
                        if (separatePinnedAndRunning) {
                            items.push(ApplicationModel.pinnedItem(appId, coreAppData, false));
                            return;
                        }

                        const matchIndex = remainingWindowItems.findIndex(item => item.appId === appId);

                        if (matchIndex !== -1) {
                            const windowItem = remainingWindowItems.splice(matchIndex, 1)[0];
                            windowItem.isPinned = true;
                            windowItem.uniqueKey = "pinned_" + appId;
                            if (!windowItem.isCoreApp && coreAppData) {
                                windowItem.isCoreApp = true;
                                windowItem.coreAppData = coreAppData;
                            }
                            items.push(windowItem);
                        } else {
                            items.push(ApplicationModel.pinnedItem(appId, coreAppData, runningAppIds.has(appId)));
                        }
                    });

                    root.pinnedAppCount = pinnedApps.length + (root.options.launcherEnabled ? 1 : 0);
                    insertLauncher(items);

                    if (pinnedApps.length > 0 && remainingWindowItems.length > 0) {
                        items.push(ApplicationModel.separator("separator_ungrouped"));
                    }
                    remainingWindowItems.forEach(item => items.push(item));

                    return {
                        items,
                        pinnedCount: pinnedApps.length,
                        runningCount: remainingWindowItems.length
                    };
                }

                function insertLauncher(targetArray) {
                    if (!root.options.launcherEnabled)
                        return;
                    const launcherItem = {
                        uniqueKey: "launcher_button",
                        type: "launcher",
                        appId: "__LAUNCHER__",
                        toplevel: null,
                        isPinned: true,
                        isRunning: false
                    };
                    targetArray.unshift(launcherItem);
                }

                function updateModel() {
                    const baseResult = buildBaseItems();
                    const overflow = ApplicationModel.overflow(baseResult.items, root.maxVisibleApps, root.maxVisibleRunningApps);
                    root.overflowItemCount = overflow.count;
                    let finalItems = overflow.items;
                    if (root.options.showTrash) {
                        finalItems.push({
                            uniqueKey: "trash_button",
                            type: "trash",
                            appId: "__TRASH__",
                            toplevel: null,
                            isPinned: false,
                            isRunning: false,
                            isInOverflow: false
                        });
                    }
                    dockItems = finalItems;
                }

                delegate: ApplicationItem {
                    strip: root
                }
            }
        }
    }

    DTooltip {
        id: tooltip
        screen: root.dockScreen
    }
    onHoveredButtonChanged: {
        tooltip.hide();
        if (!barHosted || !hoveredButton || !surfaceContext.live)
            return;
        const position = surfaceContext.screenPoint(hoveredButton, hoveredButton.width / 2, hoveredButton.height / 2);
        if (!position)
            return;
        const edge = options.position;
        const bounds = SettingsData.getBarBounds(dockScreen, surfaceContext.thickness, edge, surfaceContext.config);
        const x = isVertical ? (edge === SettingsData.Position.Left ? bounds.x + bounds.width : bounds.x) : position.x;
        const y = isVertical ? position.y : (edge === SettingsData.Position.Top ? bounds.y + bounds.height + Theme.spacingS : bounds.y - Theme.listItemHeight);
        tooltip.show(hoveredButton.tooltipText, x, y, dockScreen, isVertical && edge === SettingsData.Position.Left, isVertical && edge === SettingsData.Position.Right);
    }
    onVisibleChanged: if (!visible)
        tooltip.hide()

    readonly property var settingsAppIdSubstitutions: SettingsData.appIdSubstitutions

    onSettingsAppIdSubstitutionsChanged: modelUpdate.schedule()

    onPinnedAppsChanged: modelUpdate.schedule()
    readonly property string modelOptions: JSON.stringify({
        separatePinnedAndRunningApps: options.separatePinnedAndRunningApps,
        isolateDisplays: options.isolateDisplays,
        launcherEnabled: options.launcherEnabled,
        showTrash: options.showTrash
    })
    onModelOptionsChanged: modelUpdate.schedule()
    onDockScreenChanged: modelUpdate.schedule()
    readonly property var visibleWindows: options.currentWorkspace && dockScreen ? CompositorService.filterCurrentWorkspace(CompositorService.sortedToplevels, dockScreen.name) : CompositorService.sortedToplevels
    onVisibleWindowsChanged: modelUpdate.schedule()
    readonly property string windowMetadata: JSON.stringify(visibleWindows.map(toplevel => [toplevel.appId, ["org.quickshell", "com.danklinux.dms"].includes(toplevel.appId) ? toplevel.title : "", options.isolateDisplays ? (toplevel.screens || []).map(screen => screen.name) : null]))
    onWindowMetadataChanged: modelUpdate.schedule()
    readonly property var searchCoreApps: AppSearchService.coreApps

    onSearchCoreAppsChanged: modelUpdate.schedule()
    onGroupByAppChanged: modelUpdate.schedule()
    onMaxVisibleAppsChanged: modelUpdate.schedule()
    onMaxVisibleRunningAppsChanged: modelUpdate.schedule()
    DeferredAction {
        id: modelUpdate
        onTriggered: {
            if (root.draggedIndex >= 0)
                return;
            repeater.updateModel();
        }
    }
}
