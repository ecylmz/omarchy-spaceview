const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// Exercise the actual QML model functions, not a duplicate of their logic.
const qml = fs.readFileSync(`${__dirname}/../Spaceview.qml`, 'utf8');
const functions = ['workspaceIds', 'nextWorkspaceAfter'].map(name => {
  const match = qml.match(new RegExp(`  function ${name}\\([^]*?\\n  \\}`));
  assert.ok(match, `QML function ${name} exists`);
  return match[0];
}).join('\n');

function model(entries, focusedId) {
  const context = vm.createContext({ Hyprland: {
    focusedWorkspace: focusedId === null ? null : { id: focusedId },
    workspaces: { values: entries.map(([id, count]) => ({
      id, toplevels: { values: Array(count).fill({}) },
    })) },
  } });
  vm.runInContext(functions, context);
  const ids = Array.from(context.workspaceIds());
  return { ids, next: context.nextWorkspaceAfter(ids) };
}

test('only occupied and current workspaces survive, sorted, excluding special workspaces', () => {
  assert.deepEqual(model([[5, 1], [3, 0], [2, 0], [1, 2], [-1, 1], [11, 1]], 3),
    { ids: [1, 3, 5], next: 2 });
});

test('empty desktop retains current workspace and one add slot', () => {
  assert.deepEqual(model([[1, 0], [2, 0]], 1), { ids: [1], next: 2 });
  assert.deepEqual(model([], null), { ids: [], next: 1 });
});

test('workspace 10 does not hide the add card when lower slots are empty', () => {
  assert.deepEqual(model([[1, 1], [10, 1]], 10), { ids: [1, 10], next: 2 });
  assert.equal(model(Array.from({ length: 10 }, (_, i) => [i + 1, 1]), 1).next, -1);
});
