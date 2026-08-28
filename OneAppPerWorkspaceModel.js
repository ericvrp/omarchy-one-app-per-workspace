function isTrue(value) {
  return value === true || value === 1 || value === "1" || value === "true"
}

function normalizeAddress(value) {
  var address = String(value || "").trim().toLowerCase()
  return address.indexOf("0x") === 0 ? address.slice(2) : address
}

function hyprlandAddress(value) {
  var address = normalizeAddress(value)
  return /^[0-9a-f]+$/.test(address) ? "0x" + address : ""
}

function isFloating(window) {
  if (!window) return false
  var raw = window.lastIpcObject || {}
  return isTrue(raw.floating) || isTrue(window.floating)
}

function floatingStateKnown(window) {
  if (!window) return false
  var raw = window.lastIpcObject || {}
  return raw.floating !== undefined || window.floating !== undefined
}

function windowsIn(workspace) {
  if (!workspace) return []
  var toplevels = workspace.toplevels
  if (toplevels && toplevels.values !== undefined) return toplevels.values || []
  return []
}

function windowCount(workspace) {
  var values = windowsIn(workspace)
  if (workspace && workspace.toplevels && workspace.toplevels.values !== undefined)
    return values.length

  var raw = workspace && workspace.lastIpcObject ? workspace.lastIpcObject : {}
  var ipcCount = Number(raw.windows)
  return isFinite(ipcCount) && ipcCount > 0 ? ipcCount : 0
}

function isNormalWorkspace(workspace) {
  if (!workspace) return false

  var id = Number(workspace.id)
  if (!isFinite(id) || id <= 0) return false

  var raw = workspace.lastIpcObject || {}
  if (isTrue(workspace.special) || isTrue(raw.special)) return false

  var name = String(workspace.name || raw.name || "")
  return name.indexOf("special:") !== 0
}

function shouldMoveNewWindow(window, activeWorkspace, address) {
  if (!window || !activeWorkspace || isFloating(window)) return false
  if (!window.workspace || Number(window.workspace.id) !== Number(activeWorkspace.id)) return false

  var targetAddress = normalizeAddress(address || window.address)
  var values = windowsIn(activeWorkspace)
  var count = windowCount(activeWorkspace)
  if (count <= 1) return false

  for (var i = 0; i < values.length; i++) {
    var existing = values[i]
    if (existing === window) continue

    var existingAddress = normalizeAddress(existing && existing.address)
    if (!targetAddress || !existingAddress || existingAddress !== targetAddress) return true
  }

  return false
}

function nearestOccupiedWorkspace(workspaces, activeId) {
  var active = Number(activeId)
  var previous = null
  var next = null

  for (var i = 0; i < workspaces.length; i++) {
    var workspace = workspaces[i]
    if (!isNormalWorkspace(workspace) || windowCount(workspace) === 0) continue

    var id = Number(workspace.id)
    if (id < active && (!previous || id > Number(previous.id))) {
      previous = workspace
    } else if (id > active && (!next || id < Number(next.id))) {
      next = workspace
    }
  }

  return previous || next
}

if (typeof module !== "undefined") {
  module.exports = {
    floatingStateKnown: floatingStateKnown,
    hyprlandAddress: hyprlandAddress,
    isFloating: isFloating,
    isNormalWorkspace: isNormalWorkspace,
    nearestOccupiedWorkspace: nearestOccupiedWorkspace,
    normalizeAddress: normalizeAddress,
    shouldMoveNewWindow: shouldMoveNewWindow,
    windowCount: windowCount
  }
}
