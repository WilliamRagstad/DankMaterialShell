.pragma library

function windowIdentity(toplevel, appId, coreApps) {
    const core = ["org.quickshell", "com.danklinux.dms"].includes(toplevel.appId)
        ? coreApps.find(app => app.name === toplevel.title) ?? null : null;
    return { appId: core?.builtInPluginId ?? appId, coreAppData: core, isCoreApp: core !== null };
}

function pinnedItem(appId, coreAppData, isRunning) {
    return {
        uniqueKey: "pinned_" + appId, type: "pinned", appId, toplevel: null,
        isPinned: true, isRunning: isRunning ?? false, isCoreApp: coreAppData !== null,
        coreAppData, isInOverflow: false
    };
}

function separator(key) {
    return { uniqueKey: key, type: "separator", appId: "__SEPARATOR__", toplevel: null, isPinned: false, isRunning: false };
}

function overflow(items, maxPinned, maxRunning) {
    const pinned = items.filter(item => item.isPinned && item.type !== "launcher");
    const running = items.filter(item => item.isRunning && !item.isPinned);
    const hidden = new Set((maxPinned > 0 ? pinned.slice(maxPinned) : []).concat(maxRunning > 0 ? running.slice(maxRunning) : []).map(item => item.uniqueKey));
    if (!hidden.size)
        return { items: items.map(item => Object.assign({}, item, { isInOverflow: false })), count: 0 };
    const result = [];
    let separated = false;
    for (const item of items) {
        if (item.type === "separator")
            continue;
        if (item.type === "launcher") {
            result.push(item);
            continue;
        }
        if (!item.isPinned && !item.isRunning)
            continue;
        if (!item.isPinned && !separated && result.length) {
            result.push(separator("separator_overflow"));
            separated = true;
        }
        result.push(Object.assign({}, item, { isInOverflow: hidden.has(item.uniqueKey) }));
    }
    const separatorIndex = result.findIndex(item => item.type === "separator");
    result.splice(separatorIndex < 0 ? result.length : separatorIndex, 0, {
        uniqueKey: "overflow_toggle", type: "overflow-toggle", appId: "__OVERFLOW_TOGGLE__",
        toplevel: null, isPinned: false, isRunning: false, overflowCount: hidden.size
    });
    return { items: result, count: hidden.size };
}

// Folders ride the pin list as opaque tokens ("folder:<id>") so every ordering path
// (unitList, movePin, reorderPins) treats them like any other pin. Contents live in a
// parallel dockFolders map of {id, name, apps}.
var FOLDER_PREFIX = "folder:";

function folderToken(folderId) {
    return FOLDER_PREFIX + folderId;
}

function parseFolderToken(pin) {
    return typeof pin === "string" && pin.startsWith(FOLDER_PREFIX) ? pin.slice(FOLDER_PREFIX.length) : null;
}

function isFolderToken(pin) {
    return parseFolderToken(pin) !== null;
}

// Drop lands on the target icon itself when the residual offset inside the slot is small;
// a centered drop at the next slot boundary is also a perfect overlap. Otherwise it is a reorder.
function dropMode(residual, slotPitch) {
    return Math.abs(residual) < 0.35 * slotPitch ? "merge" : "move";
}

// Strip slot -> pin list insertion point: pinned strip items map 1:1 onto the pin list order.
function pinInsertIndex(items, slotIndex) {
    let count = 0;
    for (let i = 0; i < items.length && i < slotIndex; i++) {
        if (items[i].isPinned && items[i].type !== "launcher")
            count++;
    }
    return count;
}

function createFolder(pins, folders, srcAppId, dstAppId, folderId) {
    if (!srcAppId || !dstAppId || srcAppId === dstAppId)
        return null;
    const dstIndex = pins.indexOf(dstAppId);
    const srcIndex = pins.indexOf(srcAppId);
    if (dstIndex < 0 || srcIndex < 0)
        return null;
    const nextPins = pins.filter(pin => pin !== srcAppId && pin !== dstAppId);
    const insertAt = dstIndex < srcIndex ? dstIndex : dstIndex - 1;
    nextPins.splice(Math.max(0, insertAt), 0, folderToken(folderId));
    return {
        pins: nextPins,
        folders: Object.assign({}, folders, {
            [folderId]: { id: folderId, name: "", apps: [dstAppId, srcAppId] }
        })
    };
}

function addToFolder(pins, folders, folderId, appId) {
    const folder = folders[folderId];
    if (!folder || !appId || !pins.includes(appId))
        return null;
    return {
        pins: pins.filter(pin => pin !== appId),
        folders: Object.assign({}, folders, {
            [folderId]: Object.assign({}, folder, { apps: folder.apps.concat([appId]) })
        })
    };
}

// Removing the second-to-last app dissolves the folder: the token is replaced by the remaining
// app (or nothing), so the last member reappears as a normal pin at the folder's position.
function removeFromFolder(pins, folders, folderId, appId) {
    const folder = folders[folderId];
    if (!folder || !folder.apps.includes(appId))
        return null;
    const remaining = folder.apps.filter(app => app !== appId);
    const nextFolders = Object.assign({}, folders);
    const token = folderToken(folderId);
    const tokenIndex = pins.indexOf(token);
    if (remaining.length > 1) {
        nextFolders[folderId] = Object.assign({}, folder, { apps: remaining });
        return { pins, folders: nextFolders, dissolved: false };
    }
    delete nextFolders[folderId];
    const nextPins = pins.slice();
    if (remaining.length === 1 && tokenIndex >= 0)
        nextPins[tokenIndex] = remaining[0];
    else
        nextPins.splice(tokenIndex >= 0 ? tokenIndex : nextPins.length, tokenIndex >= 0 ? 1 : 0);
    return { pins: nextPins, folders: nextFolders, dissolved: true };
}

function renameFolder(folders, folderId, name) {
    const folder = folders[folderId];
    if (!folder)
        return null;
    return Object.assign({}, folders, {
        [folderId]: Object.assign({}, folder, { name })
    });
}

function nextFolderName(folders) {
    let max = 0;
    for (const id in folders) {
        const match = /^Folder (\d+)$/.exec(folders[id].name || "");
        if (match)
            max = Math.max(max, Number(match[1]));
    }
    return "Folder " + (max + 1);
}

function movePin(pins, items, from, to) {
    const source = items[from];
    const target = items[to];
    if (!source?.isPinned || !target?.isPinned || source.type === "launcher")
        return pins;
    const pinned = items.filter(item => item.isPinned && item.type !== "launcher");
    const sourceIndex = pinned.indexOf(source);
    const targetIndex = target.type === "launcher" ? items.slice(0, to).filter(item => item.isPinned && item.type !== "launcher").length : pinned.indexOf(target);
    if (sourceIndex < 0 || sourceIndex >= pins.length || targetIndex < 0 || sourceIndex === targetIndex)
        return pins;
    const result = pins.slice();
    result.splice(Math.min(targetIndex, result.length - 1), 0, result.splice(sourceIndex, 1)[0]);
    return result;
}
