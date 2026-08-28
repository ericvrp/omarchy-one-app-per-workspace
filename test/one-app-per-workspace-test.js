const GLib = imports.gi.GLib
const ByteArray = imports.byteArray

const root = GLib.getenv('ROOT')
imports.searchPath.unshift(root)

const model = imports.OneAppPerWorkspaceModel
const qmlResult = GLib.file_get_contents(root + '/Service.qml')
const serviceQml = ByteArray.toString(qmlResult[1])
const hookResult = GLib.file_get_contents(root + '/OneAppPerWorkspaceEarlyHook.lua')
const earlyHook = ByteArray.toString(hookResult[1])

function assert(condition, description) {
  if (!condition) throw new Error('not ok - ' + description)
  print('ok - ' + description)
}

function assertEqual(actual, expected, description) {
  assert(actual === expected, description + ' (expected ' + expected + ', got ' + actual + ')')
}

function workspace(id, values, special, name) {
  return {
    id: id,
    name: name || String(id),
    special: special === true,
    lastIpcObject: { special: special === true },
    toplevels: { values: values || [] }
  }
}

function window(address, targetWorkspace, floating) {
  return {
    address: address,
    workspace: targetWorkspace,
    floating: floating === true,
    lastIpcObject: { floating: floating === true }
  }
}

assertEqual(model.normalizeAddress('  0xABC  '), 'abc', 'normalizes window addresses')
assertEqual(model.hyprlandAddress('abc'), '0xabc', 'adds the Hyprland address prefix')
assertEqual(model.hyprlandAddress('not-an-address'), '', 'rejects invalid window addresses')
assert(model.isFloating(window('0x1', null, true)), 'recognizes floating windows')
assert(model.floatingStateKnown(window('0x1', null, true)), 'recognizes known floating state')
assert(!model.isFloating(window('0x1', null, false)), 'recognizes tiled windows')

const active = workspace(2, [])
const newWindow = window('0x2', active, false)
active.toplevels.values = [newWindow]
assert(!model.shouldMoveNewWindow(newWindow, active, '0x2'), 'keeps the first window on its workspace')

const existing = window('0x1', active, false)
active.toplevels.values = [existing, newWindow]
assert(model.shouldMoveNewWindow(newWindow, active, '0x2'), 'moves a second tiled window')

active.toplevels.values = [newWindow]
active.lastIpcObject.windows = 2
assert(!model.shouldMoveNewWindow(newWindow, active, '0x2'), 'does not trust stale IPC counts')

const floatingWindow = window('0x3', active, true)
active.toplevels.values = [existing, floatingWindow]
assert(!model.shouldMoveNewWindow(floatingWindow, active, '0x3'), 'does not move a floating window')

const otherWorkspace = workspace(3, [window('0x4', null, false)])
const previousWorkspace = workspace(4, [window('0x5', null, false)])
const nearestPrevious = workspace(5, [window('0x6', null, false)])
const nextWorkspace = workspace(8, [window('0x7', null, false)])
assertEqual(
  model.nearestOccupiedWorkspace([otherWorkspace, nextWorkspace, nearestPrevious, previousWorkspace], 8),
  nearestPrevious,
  'prefers the nearest occupied workspace before the active one'
)
assertEqual(
  model.nearestOccupiedWorkspace([otherWorkspace, nextWorkspace], 3),
  nextWorkspace,
  'uses the nearest occupied workspace after the active one'
)
assertEqual(model.windowCount({ lastIpcObject: { windows: 2 } }), 2, 'uses IPC window count when no model is available')
assert(!model.isNormalWorkspace(workspace(9, [], true)), 'ignores special workspaces')
assert(!model.isNormalWorkspace(workspace(-1, [], false)), 'ignores negative workspace ids')

assert(serviceQml.indexOf('tiledLayout') === -1, 'does not inspect the selected tiling layout')
assert(serviceQml.indexOf('movetoworkspace emptynm,address:') !== -1, 'uses the empty workspace dispatcher')
assert(serviceQml.indexOf('hyprctl repl') !== -1, 'supports Hyprland Lua configuration mode')
assert(serviceQml.indexOf('OneAppPerWorkspaceEarlyHook.lua') !== -1, 'loads the pre-layout hook')
assert(serviceQml.indexOf('configreloaded') !== -1, 'resyncs the hook after config reloads')
assert(earlyHook.indexOf('window.open_early') !== -1, 'registers the pre-layout window event')
assert(earlyHook.indexOf('workspace = "emptynm"') !== -1, 'moves early windows to an empty workspace')
assert(serviceQml.indexOf('one-app-per-workspace-off') !== -1, 'persists the disabled state')
assert(serviceQml.indexOf('target: "one-app-per-workspace"') !== -1, 'exposes a toggle IPC target')
assert(serviceQml.indexOf('pendingToggleRequests') !== -1, 'queues toggles during startup')
