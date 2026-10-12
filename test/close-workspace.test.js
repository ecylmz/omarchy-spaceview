const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const qml = fs.readFileSync(`${__dirname}/../Spaceview.qml`, 'utf8');
const functions = ['closeWorkspace', 'normalizedAddress', 'workspaceById'].map(name => {
  const match = qml.match(new RegExp(`  function ${name}\\([^]*?\\n  \\}`));
  assert.ok(match, `QML function ${name} exists`);
  return match[0];
}).join('\n');

function setup(windows, pending = null) {
  const calls = [];
  const root = { pendingReposition: pending, refreshSoon() {},
    flushPendingReposition() { this.pendingReposition = null; },
  };
  const context = vm.createContext({ root, Hyprland: {
    workspaces: { values: [
      { id: 2, toplevels: { values: windows } },
      { id: 3, toplevels: { values: [{ address: '0xdead' }] } },
    ] },
    dispatch(command) {
      calls.push(command);
      windows.shift(); // Simulate clients disappearing during the close loop.
    },
  } });
  vm.runInContext(functions, context);
  Object.assign(root, { closeWorkspace: context.closeWorkspace,
    normalizedAddress: context.normalizedAddress, workspaceById: context.workspaceById });
  return { root, calls };
}

test('closes every snapshotted window in only the chosen workspace', () => {
  const { root, calls } = setup([{ address: 'abc' }, { address: '0xdef' }]);
  root.closeWorkspace(2);
  assert.deepEqual(calls, [
    'hl.dsp.window.close({ window = "address:0xabc" })',
    'hl.dsp.window.close({ window = "address:0xdef" })',
  ]);
});

test('rejects malformed addresses, duplicates, special and unknown workspaces', () => {
  const { root, calls } = setup([
    { address: 'abc' }, { address: '0xabc' }, { address: 'bad"command' }, null,
  ]);
  for (const id of [-1, 0, 11, 4]) root.closeWorkspace(id);
  assert.equal(calls.length, 0);
  root.closeWorkspace(2);
  assert.equal(calls.length, 1);
  assert.match(calls[0], /address:0xabc/);
});

test('includes a window temporarily parked for this workspace, but not another', () => {
  const pending = { address: '0xbeef', workspaceId: 2 };
  const { root, calls } = setup([{ address: 'abc' }], pending);
  root.closeWorkspace(2);
  assert.equal(root.pendingReposition, null);
  assert.equal(calls.length, 2);
  assert.match(calls[1], /address:0xbeef/);
  const other = setup([{ address: 'abc' }], { address: 'beef', workspaceId: 3 });
  other.root.closeWorkspace(2);
  assert.equal(other.calls.length, 1);
});
