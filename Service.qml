import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.Commons
import "OneAppPerWorkspaceModel.js" as WorkspaceModel

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string toggleDir: home + "/.local/state/omarchy/toggles"
  readonly property string disabledFile: toggleDir + "/one-app-per-workspace-off"
  readonly property string earlyHookPath: String(Qt.resolvedUrl("OneAppPerWorkspaceEarlyHook.lua"))
    .replace(/^file:\/\//, "")
  readonly property int eventRetryLimit: 10

  property bool enabled: true
  property bool stateReady: false
  property var pendingEvents: []
  property var pendingOpenWindows: []
  property var pendingCloseChecks: []
  property var lastWindowWorkspaces: ({})
  property int pendingToggleRequests: 0
  property bool stateWritePending: false
  property bool stateWriteValue: true
  property var shell: null

  function probeState() {
    if (!stateProbe.running) stateProbe.running = true
  }

  function startNextStateWrite() {
    if (stateWriteProcess.running || !root.stateWritePending) return

    var value = root.stateWriteValue
    root.stateWritePending = false
    stateWriteProcess.command = value
      ? ["bash", "-c", "rm -f " + Util.shellQuote(root.disabledFile)]
      : ["bash", "-c", "mkdir -p " + Util.shellQuote(root.toggleDir)
        + " && touch " + Util.shellQuote(root.disabledFile)]
    stateWriteProcess.running = true
  }

  function persistState(value) {
    root.stateWriteValue = value === true
    root.stateWritePending = true
    root.startNextStateWrite()
  }

  function notifyToggle(value) {
    var mode = value ? "One app per workspace" : "Multiple apps per workspace"
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send",
      "-t", "2000", "Workspace behavior", mode])
  }

  function setEnabled(value) {
    var next = value === true
    if (!root.stateReady || root.enabled === next) return

    root.enabled = next
    root.persistState(next)
    root.notifyToggle(next)
  }

  function toggle() {
    if (!root.stateReady) {
      root.pendingToggleRequests += 1
      return
    }
    root.setEnabled(!root.enabled)
  }

  function flushPendingToggles() {
    var requests = root.pendingToggleRequests
    root.pendingToggleRequests = 0
    if (requests % 2 === 1) root.setEnabled(!root.enabled)
  }

  function luaString(value) {
    return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  function runLua(code) {
    Util.execDetached("hyprctl repl " + Util.shellQuote(code))
  }

  function syncEarlyHook() {
    if (!Hyprland.usingLua || !root.stateReady) return

    var value = root.enabled ? "true" : "false"
    root.runLua("local hook = dofile(\"" + root.luaString(root.earlyHookPath)
      + "\"); hook.sync(" + value + ")")
  }

  function removeEarlyHook() {
    if (!Hyprland.usingLua) return

    root.runLua("local hook = dofile(\"" + root.luaString(root.earlyHookPath)
      + "\"); hook.remove()")
  }

  function moveWindowToEmptyWorkspace(address) {
    var selector = WorkspaceModel.hyprlandAddress(address)
    if (!selector) return

    if (Hyprland.usingLua) {
      root.runLua("local window = hl.get_window(\"address:" + selector
        + "\"); if window then hl.dispatch(hl.dsp.window.move({ window = window, workspace = \"emptynm\", follow = true })) end")
    } else {
      Hyprland.dispatch("movetoworkspace emptynm,address:" + selector)
    }
  }

  function focusWorkspace(workspaceId) {
    var id = String(workspaceId)
    if (Hyprland.usingLua) {
      root.runLua("hl.dispatch(hl.dsp.focus({ workspace = \"" + root.luaString(id) + "\" }))")
    } else {
      Hyprland.dispatch("workspace " + id)
    }
  }

  function receiveRawEvent(event) {
    if (!event) return

    root.rememberWindowWorkspaces()
    Qt.callLater(root.rememberWindowWorkspaces)

    var name = String(event.name || "")
    if (name === "configreloaded") {
      root.syncEarlyHook()
      return
    }
    if (name !== "openwindow" && name !== "closewindow") return

    var args = []
    try {
      args = event.parse(name === "openwindow" ? 4 : 1)
    } catch (error) {
      console.warn("one-app-per-workspace: could not parse " + name + ": " + error)
      return
    }

    var record = { name: name, args: args }
    if (!root.stateReady) {
      root.pendingEvents = root.pendingEvents.concat([record])
      return
    }

    root.processEvent(record)
  }

  function processEvent(record) {
    if (!root.enabled || !record || !record.args) return

    if (record.name === "openwindow") {
      var activeForOpen = Hyprland.focusedWorkspace
      if (!activeForOpen) return
      root.queueOpenWindow(record.args[0], activeForOpen.id)
      return
    }

    if (record.name !== "closewindow") return

    var activeForClose = Hyprland.focusedWorkspace
    if (!activeForClose || !WorkspaceModel.isNormalWorkspace(activeForClose)) return

    Hyprland.refreshWorkspaces()

    var closingWindow = root.windowByAddress(record.args[0])
    var closingWorkspace = closingWindow ? closingWindow.workspace : null
    var closingAddress = WorkspaceModel.normalizeAddress(record.args[0])
    var rememberedWorkspaceId = root.lastWindowWorkspaces[closingAddress]
    if (!closingWorkspace && rememberedWorkspaceId === undefined) return

    var workspaceId = closingWorkspace ? closingWorkspace.id : rememberedWorkspaceId
    if (Number(workspaceId) !== Number(activeForClose.id)) return

    root.queueCloseCheck(activeForClose.id)
  }

  function flushPendingEvents() {
    var events = root.pendingEvents
    root.pendingEvents = []

    if (!root.enabled) return
    for (var i = 0; i < events.length; i++) root.processEvent(events[i])
  }

  function windowByAddress(address) {
    var target = WorkspaceModel.normalizeAddress(address)
    if (!target || !Hyprland.toplevels) return null

    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      if (WorkspaceModel.normalizeAddress(values[i].address) === target) return values[i]
    }

    return null
  }

  function rememberWindowWorkspaces() {
    if (!Hyprland.toplevels) return

    var known = {}
    for (var address in root.lastWindowWorkspaces)
      known[address] = root.lastWindowWorkspaces[address]

    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      var window = values[i]
      var workspace = window ? window.workspace : null
      var address = WorkspaceModel.normalizeAddress(window ? window.address : "")
      if (address && workspace) known[address] = workspace.id
    }

    root.lastWindowWorkspaces = known
  }

  function queueOpenWindow(address, workspaceId) {
    var normalized = WorkspaceModel.normalizeAddress(address)
    if (!normalized || workspaceId === undefined || workspaceId === null) return

    var pending = root.pendingOpenWindows.slice()
    for (var i = 0; i < pending.length; i++) {
      if (pending[i].address === normalized) return
    }

    pending.push({
      address: normalized,
      workspaceId: Number(workspaceId),
      attempts: 0
    })
    root.pendingOpenWindows = pending
    if (!openWindowTimer.running) openWindowTimer.start()
  }

  function processPendingOpenWindows() {
    if (!root.stateReady || !root.enabled) {
      root.pendingOpenWindows = []
      return
    }

    var pending = root.pendingOpenWindows
    root.pendingOpenWindows = []
    var retry = []

    for (var i = 0; i < pending.length; i++) {
      var record = pending[i]
      if (root.processOpenWindow(record) && record.attempts < root.eventRetryLimit) {
        record.attempts += 1
        retry.push(record)
      }
    }

    if (retry.length > 0) root.pendingOpenWindows = root.pendingOpenWindows.concat(retry)
    if (root.pendingOpenWindows.length > 0) openWindowTimer.restart()
  }

  function processOpenWindow(record) {
    var active = Hyprland.focusedWorkspace
    if (!active || Number(active.id) !== Number(record.workspaceId)) return false

    var window = root.windowByAddress(record.address)
    if (!window) {
      if (record.attempts === 0) Hyprland.refreshToplevels()
      return true
    }
    if (!window.workspace) return true
    if (!WorkspaceModel.floatingStateKnown(window)) {
      Hyprland.refreshToplevels()
      return true
    }

    if (WorkspaceModel.shouldMoveNewWindow(window, active, record.address)) {
      root.moveWindowToEmptyWorkspace(record.address)
    }

    return false
  }

  function queueCloseCheck(workspaceId) {
    var id = Number(workspaceId)
    if (!isFinite(id)) return

    var pending = root.pendingCloseChecks.slice()
    for (var i = 0; i < pending.length; i++) {
      if (Number(pending[i].workspaceId) === id) return
    }

    pending.push({ workspaceId: id, attempts: 0 })
    root.pendingCloseChecks = pending
    if (!closeCheckTimer.running) closeCheckTimer.start()
  }

  function processPendingCloseChecks() {
    if (!root.stateReady || !root.enabled) {
      root.pendingCloseChecks = []
      return
    }

    var pending = root.pendingCloseChecks
    root.pendingCloseChecks = []
    var retry = []

    for (var i = 0; i < pending.length; i++) {
      var record = pending[i]
      if (root.processCloseCheck(record) && record.attempts < root.eventRetryLimit) {
        record.attempts += 1
        retry.push(record)
      }
    }

    if (retry.length > 0) root.pendingCloseChecks = root.pendingCloseChecks.concat(retry)
    if (root.pendingCloseChecks.length > 0) closeCheckTimer.restart()
  }

  function processCloseCheck(record) {
    var active = Hyprland.focusedWorkspace
    if (!active || Number(active.id) !== Number(record.workspaceId)
        || !WorkspaceModel.isNormalWorkspace(active)) return false

    if (WorkspaceModel.windowCount(active) > 0) return true

    var workspaces = Hyprland.workspaces.values || []
    var target = WorkspaceModel.nearestOccupiedWorkspace(workspaces, active.id)
    if (target) {
      root.focusWorkspace(target.id)
    } else if (Number(active.id) !== 1) {
      root.focusWorkspace(1)
    }

    return false
  }

  onEnabledChanged: {
    root.syncEarlyHook()
    if (!root.enabled) {
      openWindowTimer.stop()
      closeCheckTimer.stop()
      root.pendingOpenWindows = []
      root.pendingCloseChecks = []
    }
  }

  Process {
    id: stateProbe

    running: true
    command: ["bash", "-c", "[[ -f " + Util.shellQuote(root.disabledFile)
      + " ]] && echo disabled || echo enabled"]
    stdout: SplitParser {
      onRead: function(line) {
        if (!stateWriteProcess.running)
          root.enabled = String(line).trim() !== "disabled"
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("one-app-per-workspace: state probe failed")
      root.stateReady = true
      root.syncEarlyHook()
      root.flushPendingEvents()
      root.flushPendingToggles()
    }
  }

  Process {
    id: stateWriteProcess

    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("one-app-per-workspace: state write failed")
      root.startNextStateWrite()
    }
  }

  FileView {
    path: root.toggleDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.probeState()
  }

  IpcHandler {
    target: "one-app-per-workspace"

    function status(): string {
      return root.enabled ? "enabled" : "disabled"
    }

    function toggle(): string {
      root.toggle()
      return root.enabled ? "enabled" : "disabled"
    }
  }

  Timer {
    id: openWindowTimer
    interval: 40
    repeat: false
    onTriggered: root.processPendingOpenWindows()
  }

  Timer {
    id: closeCheckTimer
    interval: 40
    repeat: false
    onTriggered: root.processPendingCloseChecks()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      root.receiveRawEvent(event)
    }
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Qt.callLater(root.rememberWindowWorkspaces)
  }

  Component.onDestruction: root.removeEarlyHook()
}
