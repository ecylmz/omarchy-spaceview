const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const qml = fs.readFileSync(`${__dirname}/../Spaceview.qml`, 'utf8');
const names = ['findDrawerWorkspace', 'drawerIsOpen', 'activateDrawer',
  'normalizedAddress', 'moveWindowToDrawer', 'sourceWorkspaceId',
  'moveWindowToWorkspace', 'moveCardSelection', 'cardIndexAfterMove',
  'activateSelectedCard', 'dismissThenActivate', 'activateWindow', 'activateWorkspace', 'open'];
const functions = names.map(name => {
  const match = qml.match(new RegExp(`  function ${name}\\([^]*?\\n  \\}`));
  assert.ok(match, `QML function ${name} exists`);
  return match[0];
}).join('\n');

function setup(workspaces = []) {
  const calls = [];
  const panel = { visible: true };
  const root = { refreshSoon() {}, flushPendingReposition() {},
    focusedScreen() {}, initialSelectedCardIndex() { return 0; },
    opened: false, pendingActivation: null, layoutEvents: [],
    dismiss() { this.opened = false; panel.visible = false; },
    gridCardCount: 3, cardCount: 4, columns: 3, rows: 1,
    workspaceCount: 2, nextWorkspaceId: 3, overviewCardModel: [1, 2, 3],
  };
  const Hyprland = { workspaces: { values: workspaces }, focusedMonitor: {
    lastIpcObject: { specialWorkspace: { name: '' } },
  }, dispatch(command) { calls.push(command); },
    refreshMonitors() {}, refreshToplevels() {}, refreshWorkspaces() {},
  };
  const context = vm.createContext({ root, panel, Hyprland, Qt: { callLater(fn) { fn(); } },
    rescueTimer: { restart() {} }, keyCatcher: { forceActiveFocus() {} },
  });
  vm.runInContext(functions, context);
  vm.runInContext(qml.match(/    function onRawEvent\([^]*?\n    \}/)[0], context);
  for (const name of names) root[name] = context[name];
  return { root, Hyprland, calls, event: context.onRawEvent };
}

test('window selection waits for its layer to close and activates exactly once', () => {
  const { root, calls, event } = setup();
  root.opened = true;
  root.activateWindow({ address: 'abc123' });
  assert.equal(root.opened, false);
  assert.equal(calls.length, 0, 'focus must not be dispatched under the exclusive grab');
  event({ name: 'closelayer', data: 'some-other-overlay' });
  assert.equal(calls.length, 0);
  event({ name: 'closelayer', data: 'spaceview' });
  assert.deepEqual(calls, ['hl.dsp.focus({ window = "address:0xabc123" })']);
  event({ name: 'closelayer', data: 'spaceview' });
  assert.equal(calls.length, 1);
  assert.equal(root.pendingActivation, null);
});

test('workspace, drawer, and Wayland fallback activation also wait for unmap', () => {
  for (const kind of ['workspace', 'drawer', 'wayland']) {
    const { root, calls, event } = setup();
    root.opened = true;
    if (kind === 'workspace') root.activateWorkspace(2);
    else if (kind === 'drawer') root.activateDrawer();
    else root.activateWindow({ wayland: { activate() { calls.push('wayland'); } } });
    assert.equal(calls.length, 0, kind);
    event({ name: 'closelayer', data: 'spaceview' });
    assert.equal(calls.length, 1, kind);
  }
});

test('closing without selection or receiving an old close while reopened does not focus', () => {
  const { root, calls, event } = setup();
  root.dismiss();
  event({ name: 'closelayer', data: 'spaceview' });
  assert.equal(calls.length, 0);
  root.pendingActivation = () => calls.push('stale');
  root.open();
  assert.equal(root.pendingActivation, null);
  event({ name: 'closelayer', data: 'spaceview' });
  root.dismiss();
  event({ name: 'closelayer', data: 'spaceview' });
  assert.equal(calls.length, 0);
});

test('only the named scratchpad is a drawer, never the reposition parking workspace', () => {
  const parking = { id: -2, lastIpcObject: { name: 'special:spaceview-move' } };
  const drawer = { id: -7, lastIpcObject: { name: 'special:scratchpad' } };
  assert.equal(setup([parking, drawer]).root.findDrawerWorkspace(), drawer);
  assert.equal(setup([parking]).root.findDrawerWorkspace(), null);
});

test('activating an already-open drawer never hides it', () => {
  const { root, Hyprland, calls } = setup();
  root.activateDrawer();
  assert.deepEqual(calls, ['hl.dsp.workspace.toggle_special("scratchpad")']);
  Hyprland.focusedMonitor.lastIpcObject.specialWorkspace.name = 'special:scratchpad';
  root.activateDrawer();
  assert.equal(calls.length, 1);
});

test('drawer drops validate addresses and never move a window already inside', () => {
  const { root, calls } = setup();
  assert.equal(root.moveWindowToDrawer({ address: 'bad"command' }), false);
  assert.equal(root.moveWindowToDrawer({ address: 'abc123', workspace: {
    lastIpcObject: { name: 'special:scratchpad' },
  } }), false);
  assert.equal(calls.length, 0);
  assert.equal(root.moveWindowToDrawer({ address: 'abc123' }), true);
  assert.deepEqual(calls, ['hl.dsp.window.move({ workspace = "special:scratchpad", window = "address:0xabc123", follow = false })']);
});

test('a drawer window can move back out to a numbered or new workspace', () => {
  const { root, calls } = setup();
  const window = { address: '0xabc123', workspace: { id: -7 } };
  assert.equal(root.moveWindowToWorkspace(window, 3), true);
  assert.match(calls[0], /workspace = "3"/);
  assert.equal(root.moveWindowToWorkspace(window, -2), false);
  assert.equal(root.moveWindowToWorkspace(window, 11), false);
});

test('scratchpad events refresh monitor state even when the overview is closed', () => {
  const handler = qml.match(/    function onRawEvent\([^]*?\n    \}/);
  assert.ok(handler);
  let refreshes = 0;
  const context = vm.createContext({ root: { opened: false },
    Hyprland: { refreshMonitors() { refreshes++; } },
  });
  vm.runInContext(handler[0], context);
  context.onRawEvent({ name: 'activespecial' });
  context.onRawEvent({ name: 'activespecialv2' });
  context.onRawEvent({ name: 'activewindow' });
  assert.equal(refreshes, 2);
});

test('drawer windows form a non-overlapping thumbnail row regardless of desktop geometry', () => {
  const card = fs.readFileSync(`${__dirname}/../WorkspaceCard.qml`, 'utf8');
  const layout = card.match(/readonly property var layoutRects: (\{[^]*?\n  \})/);
  assert.ok(layout);
  for (const count of [0, 1, 2, 8]) {
    const root = { drawer: true, monitorBounds: null,
      workspace: { toplevels: { values: Array.from({ length: count }, () => ({})) } },
    };
    const rects = vm.runInNewContext(`(function() ${layout[1]})()`, { root });
    assert.equal(rects.length, count);
    for (let i = 0; i < count; i++) {
      assert.equal(rects[i].x, i / count);
      assert.equal(rects[i].width, 1 / count);
      assert.equal(rects[i].y, 0);
      assert.equal(rects[i].height, 1);
    }
  }
});

test('keyboard reaches the empty drawer row without confusing it with +', () => {
  const { root, calls } = setup();
  root.selectedCardIndex = 1;
  root.moveCardSelection(0, 1);
  assert.equal(root.selectedCardIndex, 3);
  root.activateSelectedCard();
  assert.match(calls[0], /toggle_special/);
  root.moveCardSelection(1, 0);
  assert.equal(root.selectedCardIndex, 3);
  root.moveCardSelection(0, -1);
  assert.equal(root.selectedCardIndex, 2);
  root.activateSelectedCard();
  assert.equal(calls[1], 'hl.dsp.focus({ workspace = "3" })');
  root.moveCardSelection(0, 1);
  assert.equal(root.selectedCardIndex, 3);
  root.moveCardSelection(0, 1);
  assert.equal(root.selectedCardIndex, 3);
});
