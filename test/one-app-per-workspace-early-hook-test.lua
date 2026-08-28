local hookPath = arg[1]
assert(hookPath, "the early hook path is required")

local registeredCallbacks = {}
local registrationCounts = {}
local currentSubscriptions = {}
local lastMove
local lastFocus
local lastDispatcher
local dispatchCount = 0
local activeWorkspace
local workspaces = {}

hl = {
  get_workspace_windows = function(workspace)
    return workspace.windows
  end,
  get_active_workspace = function()
    return activeWorkspace
  end,
  get_workspaces = function()
    return workspaces
  end,
  on = function(name, callback)
    assert(name == "window.open_early" or name == "window.close", "registers a known window event")
    registrationCounts[name] = (registrationCounts[name] or 0) + 1
    registeredCallbacks[name] = callback
    local subscription = { active = true }
    currentSubscriptions[name] = subscription
    function subscription:is_active()
      return self.active
    end
    function subscription:remove()
      self.active = false
    end
    return subscription
  end,
  dispatch = function(dispatcher)
    assert(dispatcher == lastDispatcher, "dispatches the requested action")
    dispatchCount = dispatchCount + 1
  end,
  dsp = {
    window = {
      move = function(options)
        lastMove = options
        lastDispatcher = options
        return options
      end,
    },
    focus = function(options)
      assert(activeWorkspace and #activeWorkspace.windows == 1, "focuses the destination before close removal")
      lastFocus = options
      lastDispatcher = options
      return options
    end,
  },
}

local hook = dofile(hookPath)
hook.sync(true)
assert(registrationCounts["window.open_early"] == 1, "registers one early open hook")
assert(registrationCounts["window.close"] == 1, "registers one early close hook")

local workspace = {
  id = 2,
  name = "2",
  active = true,
  special = false,
  windows = {},
}
activeWorkspace = workspace
workspaces = { workspace }

local firstWindow = { floating = false, mapped = true, workspace = workspace }
workspace.windows = { firstWindow }
registeredCallbacks["window.open_early"](firstWindow)
assert(dispatchCount == 0, "keeps the first tiled window on an empty workspace")

registeredCallbacks["window.open_early"]({ floating = true, workspace = workspace })
assert(dispatchCount == 0, "keeps a floating window on its workspace")

workspace.windows = {{ floating = true, mapped = true }}
registeredCallbacks["window.open_early"]({ floating = false, workspace = workspace })
assert(dispatchCount == 0, "does not count floating windows")

workspace.windows = { firstWindow }
local newWindow = { floating = false, workspace = workspace }
table.insert(workspace.windows, newWindow)
registeredCallbacks["window.open_early"](newWindow)
assert(dispatchCount == 1, "moves a second tiled window before layout insertion")
assert(lastMove.window == newWindow, "moves the new window")
assert(lastMove.workspace == "emptynm", "uses the first empty workspace")
assert(lastMove.follow == true, "follows the moved window")

local targetWorkspace = {
  id = 1,
  name = "1",
  special = false,
  windows = {{ floating = false, mapped = true }},
}
local closingWindow = { floating = false, mapped = true, workspace = workspace }
workspace.windows = { closingWindow }
workspaces = { workspace, targetWorkspace }
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 2, "focuses another workspace before closing the last window")
assert(lastFocus.workspace == "1", "focuses the occupied workspace before closing")

workspace.windows = { closingWindow, { floating = true, mapped = true } }
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 2, "keeps the workspace when another window remains")

workspace.windows = { closingWindow }
activeWorkspace = targetWorkspace
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 2, "ignores windows closing on an inactive workspace")

activeWorkspace = workspace
workspace.special = true
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 2, "ignores special workspaces")

workspace.special = false
local previousWorkspace = {
  id = 5,
  name = "5",
  special = false,
  windows = {{ floating = false, mapped = true }},
}
local nextWorkspace = {
  id = 9,
  name = "9",
  special = false,
  windows = {{ floating = false, mapped = true }},
}
workspace.id = 8
workspace.name = "8"
workspaces = { nextWorkspace, workspace, previousWorkspace }
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 3, "focuses an occupied workspace before the closing workspace")
assert(lastFocus.workspace == "5", "prefers the nearest occupied workspace before the active one")

local fallbackWorkspace = {
  id = 4,
  name = "4",
  special = false,
  windows = { closingWindow },
}
closingWindow.workspace = fallbackWorkspace
activeWorkspace = fallbackWorkspace
workspaces = { fallbackWorkspace }
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 4, "falls back to workspace 1 before closing")
assert(lastFocus.workspace == "1", "uses workspace 1 when no occupied workspace exists")

hook.sync(false)
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 4, "does not focus workspaces while disabled")

currentSubscriptions["window.close"].active = false
hook.sync(true)
assert(registrationCounts["window.open_early"] == 1, "keeps the active open hook during resync")
assert(registrationCounts["window.close"] == 2, "re-registers an inactive close hook")

hook.remove()
assert(currentSubscriptions["window.open_early"].active == false, "removes the early open hook")
assert(currentSubscriptions["window.close"].active == false, "removes the early close hook")
registeredCallbacks["window.close"](closingWindow)
assert(dispatchCount == 4, "does not focus workspaces after removal")

print("ok - early window hook behavior")
