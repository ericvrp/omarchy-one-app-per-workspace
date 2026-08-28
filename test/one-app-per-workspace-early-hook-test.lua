local hookPath = arg[1]
assert(hookPath, "the early hook path is required")

local registeredCallback
local registrationCount = 0
local currentSubscription
local lastMove
local dispatchCount = 0

hl = {
  get_workspace_windows = function(workspace)
    return workspace.windows
  end,
  on = function(name, callback)
    assert(name == "window.open_early", "registers the early window event")
    registrationCount = registrationCount + 1
    registeredCallback = callback
    currentSubscription = { active = true }
    function currentSubscription:is_active()
      return self.active
    end
    function currentSubscription:remove()
      self.active = false
    end
    return currentSubscription
  end,
  dispatch = function(dispatcher)
    assert(dispatcher == lastMove, "dispatches the requested window move")
    dispatchCount = dispatchCount + 1
  end,
  dsp = {
    window = {
      move = function(options)
        lastMove = options
        return options
      end,
    },
  },
}

local hook = dofile(hookPath)
hook.sync(true)
assert(registrationCount == 1, "registers one early window hook")

local workspace = {
  id = 2,
  active = true,
  special = false,
  windows = {},
}

local firstWindow = { floating = false, mapped = true, workspace = workspace }
workspace.windows = { firstWindow }
registeredCallback(firstWindow)
assert(dispatchCount == 0, "keeps the first tiled window on an empty workspace")

registeredCallback({ floating = true, workspace = workspace })
assert(dispatchCount == 0, "keeps a floating window on its workspace")

workspace.windows = {{ floating = true, mapped = true }}
registeredCallback({ floating = false, workspace = workspace })
assert(dispatchCount == 0, "does not count floating windows")

workspace.windows = { firstWindow }
local newWindow = { floating = false, workspace = workspace }
table.insert(workspace.windows, newWindow)
registeredCallback(newWindow)
assert(dispatchCount == 1, "moves a second tiled window before layout insertion")
assert(lastMove.window == newWindow, "moves the new window")
assert(lastMove.workspace == "emptynm", "uses the first empty workspace")
assert(lastMove.follow == true, "follows the moved window")

workspace.active = false
registeredCallback({ floating = false, workspace = workspace })
assert(dispatchCount == 1, "ignores windows opened on an inactive workspace")

workspace.active = true
workspace.special = true
registeredCallback({ floating = false, workspace = workspace })
assert(dispatchCount == 1, "ignores special workspaces")

workspace.special = false
hook.sync(false)
registeredCallback({ floating = false, workspace = workspace })
assert(dispatchCount == 1, "does not move windows while disabled")

currentSubscription.active = false
hook.sync(true)
assert(registrationCount == 2, "re-registers after a compositor config reload")

hook.remove()
assert(currentSubscription.active == false, "removes the early window hook")
registeredCallback({ floating = false, workspace = workspace })
assert(dispatchCount == 1, "does not move windows after removal")

print("ok - early window hook behavior")
