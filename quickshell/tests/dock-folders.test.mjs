import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const model = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Modules/SurfaceWidgets/ApplicationModel.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), model);
const plain = value => JSON.parse(JSON.stringify(value));

test("folder tokens round-trip", () => {
    assert.equal(model.folderToken("f1"), "folder:f1");
    assert.equal(model.parseFolderToken("folder:f1"), "f1");
    assert.equal(model.parseFolderToken("firefox"), null);
    assert.equal(model.parseFolderToken("folder:"), "");
});

test("createFolder replaces both pins with a token at the drop target", () => {
    const pins = ["a", "b", "c"];
    const folders = {};
    const result = model.createFolder(pins, folders, "c", "a", "f1");
    assert.deepEqual(plain(result.pins), ["folder:f1", "b"]);
    assert.deepEqual(plain(result.folders.f1.apps), ["a", "c"]);
    assert.equal(result.folders.f1.id, "f1");
    assert.deepEqual(plain(pins), ["a", "b", "c"], "inputs are not mutated");
});

test("createFolder rejects self-merge and missing pins", () => {
    const pins = ["a", "b"];
    assert.equal(model.createFolder(pins, {}, "a", "a", "f1"), null);
    assert.equal(model.createFolder(pins, {}, "a", "zz", "f1"), null);
    assert.equal(model.createFolder(pins, {}, "zz", "a", "f1"), null);
});

test("addToFolder moves the pin into the folder", () => {
    const pins = ["folder:f1", "b", "c"];
    const folders = { f1: { id: "f1", name: "Folder 1", apps: ["a"] } };
    const result = model.addToFolder(pins, folders, "f1", "c");
    assert.deepEqual(plain(result.pins), ["folder:f1", "b"]);
    assert.deepEqual(plain(result.folders.f1.apps), ["a", "c"]);
    assert.equal(model.addToFolder(pins, folders, "missing", "c"), null);
    assert.equal(model.addToFolder(pins, folders, "f1", "zz"), null);
});

test("removeFromFolder keeps the folder while it holds more than one app", () => {
    const pins = ["folder:f1", "x"];
    const folders = { f1: { id: "f1", name: "F", apps: ["a", "b", "c"] } };
    const result = model.removeFromFolder(pins, folders, "f1", "b");
    assert.deepEqual(plain(result.pins), ["folder:f1", "x"]);
    assert.deepEqual(plain(result.folders.f1.apps), ["a", "c"]);
    assert.equal(result.dissolved, false);
});

test("removeFromFolder dissolves at one app, re-pinning it at the token slot", () => {
    const pins = ["x", "folder:f1", "y"];
    const folders = { f1: { id: "f1", name: "F", apps: ["a", "b"] } };
    const result = model.removeFromFolder(pins, folders, "f1", "a");
    assert.equal(result.dissolved, true);
    assert.deepEqual(plain(result.pins), ["x", "b", "y"]);
    assert.equal(result.folders.f1, undefined);

    const last = model.removeFromFolder(["folder:f2"], { f2: { id: "f2", name: "F", apps: ["z"] } }, "f2", "z");
    assert.equal(last.dissolved, true);
    assert.deepEqual(plain(last.pins), []);
    assert.deepEqual(plain(Object.keys(last.folders)), []);
});

test("removeFromFolder ignores unknown apps and folders", () => {
    const pins = ["folder:f1"];
    const folders = { f1: { id: "f1", name: "F", apps: ["a"] } };
    assert.equal(model.removeFromFolder(pins, folders, "f1", "zz"), null);
    assert.equal(model.removeFromFolder(pins, folders, "zz", "a"), null);
});

test("renameFolder updates the name in place", () => {
    const folders = { f1: { id: "f1", name: "Folder 1", apps: ["a"] } };
    const result = model.renameFolder(folders, "f1", "Work");
    assert.equal(result.f1.name, "Work");
    assert.deepEqual(plain(result.f1.apps), ["a"]);
    assert.equal(model.renameFolder(folders, "zz", "X"), null);
});

test("nextFolderName counts existing generated names", () => {
    assert.equal(model.nextFolderName({}), "Folder 1");
    const folders = {
        f1: { id: "f1", name: "Folder 2", apps: [] },
        f2: { id: "f2", name: "Work", apps: [] },
        f3: { id: "f3", name: "Folder 17", apps: [] }
    };
    assert.equal(model.nextFolderName(folders), "Folder 18");
});

test("pinInsertIndex maps a strip slot to a pin list position", () => {
    const items = [
        { type: "launcher", isPinned: true },
        { type: "folder", isPinned: true, appId: "folder:f1" },
        { type: "separator" },
        { type: "pinned", isPinned: true },
        { type: "grouped", isPinned: false }
    ];
    assert.equal(model.pinInsertIndex(items, 0), 0);
    assert.equal(model.pinInsertIndex(items, 1), 0);
    assert.equal(model.pinInsertIndex(items, 3), 1);
    assert.equal(model.pinInsertIndex(items, 4), 2);
    assert.equal(model.pinInsertIndex(items, 99), 2);
});

test("updateFolder patches folder records without touching others", () => {
    const folders = {
        f1: { id: "f1", name: "A", apps: ["a"], columns: 3 },
        f2: { id: "f2", name: "B", apps: ["b"], columns: 3 }
    };
    const result = model.updateFolder(folders, "f1", { columns: 5 });
    assert.equal(result.f1.columns, 5);
    assert.equal(result.f1.name, "A");
    assert.equal(result.f2.columns, 3);
    assert.equal(model.updateFolder(folders, "zz", { columns: 4 }), null);
});

test("dissolveFolder spreads members into the pin list at the token slot", () => {
    const pins = ["x", "folder:f1", "y"];
    const folders = { f1: { id: "f1", name: "F", apps: ["a", "b", "c"], columns: 3 } };
    const result = model.dissolveFolder(pins, folders, "f1");
    assert.deepEqual(plain(result.pins), ["x", "a", "b", "c", "y"]);
    assert.equal(result.folders.f1, undefined);
    assert.equal(model.dissolveFolder(pins, folders, "zz"), null);
    assert.equal(model.dissolveFolder(["a"], folders, "f1"), null, "missing token rejects");
});

test("dropMode separates merge targets from reorder slots", () => {
    const pitch = 50;
    assert.equal(model.dropMode(0, pitch), "merge");
    assert.equal(model.dropMode(10, pitch), "merge");
    assert.equal(model.dropMode(-10, pitch), "merge");
    assert.equal(model.dropMode(25, pitch), "move");
    assert.equal(model.dropMode(-25, pitch), "move");
    assert.equal(model.dropMode(24, pitch), "move");
});
