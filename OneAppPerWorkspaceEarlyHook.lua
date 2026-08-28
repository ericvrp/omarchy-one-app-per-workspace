local hook = {}

local stateKey = "ericvrp_one_app_per_workspace"

local function removeSubscription(state)
  if not state or not state.subscription then return end

  local subscription = state.subscription
  state.subscription = nil

  if subscription.is_active and subscription:is_active() then
    subscription:remove()
  end
end

local function workspaceHasTiledWindow(workspace, incomingWindow)
  local windows = hl.get_workspace_windows(workspace) or {}

  -- Hyprland may expose the incoming window before its layout target exists.
  for _, window in ipairs(windows) do
    if window ~= incomingWindow and window.mapped ~= false and not window.floating then
      return true
    end
  end

  return false
end

local function shouldMove(window)
  if not window or window.floating then return false end

  local workspace = window.workspace
  local id = workspace and tonumber(workspace.id)
  if not workspace or not id or id <= 0 or workspace.special or not workspace.active then
    return false
  end

  return workspaceHasTiledWindow(workspace, window)
end

local function onWindowOpen(window)
  local state = rawget(_G, stateKey)
  if not state or not state.enabled or not shouldMove(window) then return end

  hl.dispatch(hl.dsp.window.move({
    window = window,
    workspace = "emptynm",
    follow = true,
  }))
end

function hook.sync(enabled)
  local state = rawget(_G, stateKey)
  if not state then
    state = {}
    rawset(_G, stateKey, state)
  end

  state.enabled = enabled == true

  if state.subscription and state.subscription:is_active() then return end

  removeSubscription(state)
  state.subscription = hl.on("window.open_early", onWindowOpen)
end

function hook.remove()
  local state = rawget(_G, stateKey)
  if not state then return end

  state.enabled = false
  removeSubscription(state)
  rawset(_G, stateKey, nil)
end

return hook
