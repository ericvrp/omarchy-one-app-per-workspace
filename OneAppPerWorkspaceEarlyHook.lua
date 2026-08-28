local hook = {}

local stateKey = "ericvrp_one_app_per_workspace"

local function removeSubscription(state, field)
  if not state or not state[field] then return end

  local subscription = state[field]
  state[field] = nil

  if subscription.is_active and subscription:is_active() then
    subscription:remove()
  end
end

local function subscriptionIsActive(state, field)
  local subscription = state and state[field]
  return subscription and subscription.is_active and subscription:is_active()
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

local function workspaceHasOtherWindow(workspace, closingWindow)
  local windows = hl.get_workspace_windows(workspace) or {}

  for _, window in ipairs(windows) do
    if window ~= closingWindow then return true end
  end

  return false
end

local function isNormalWorkspace(workspace)
  local id = workspace and tonumber(workspace.id)
  local name = workspace and tostring(workspace.name or "") or ""
  return workspace and id and id > 0 and not workspace.special and name:sub(1, 8) ~= "special:"
end

local function isFocusedWorkspace(workspace)
  local active = hl.get_active_workspace()
  return active and workspace and tonumber(active.id) == tonumber(workspace.id)
end

local function workspaceHasWindow(workspace)
  return #(hl.get_workspace_windows(workspace) or {}) > 0
end

local function nearestOccupiedWorkspace(activeWorkspace)
  local activeId = tonumber(activeWorkspace and activeWorkspace.id)
  if not activeId then return nil end

  local previous
  local nextWorkspace

  for _, workspace in ipairs(hl.get_workspaces() or {}) do
    local id = tonumber(workspace and workspace.id)
    if isNormalWorkspace(workspace) and workspaceHasWindow(workspace) then
      if id < activeId and (not previous or id > tonumber(previous.id)) then
        previous = workspace
      elseif id > activeId and (not nextWorkspace or id < tonumber(nextWorkspace.id)) then
        nextWorkspace = workspace
      end
    end
  end

  return previous or nextWorkspace
end

local function focusWorkspace(workspaceId)
  if workspaceId == nil then return end

  hl.dispatch(hl.dsp.focus({ workspace = tostring(workspaceId) }))
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

local function onWindowClose(window)
  local state = rawget(_G, stateKey)
  if not state or not state.enabled or not window then return end

  local workspace = window.workspace
  if not isNormalWorkspace(workspace) or not isFocusedWorkspace(workspace) then return end
  if workspaceHasOtherWindow(workspace, window) then return end

  local target = nearestOccupiedWorkspace(workspace)
  if target then
    focusWorkspace(target.id)
  elseif tonumber(workspace.id) ~= 1 then
    focusWorkspace(1)
  end
end

function hook.sync(enabled)
  local state = rawget(_G, stateKey)
  if not state then
    state = {}
    rawset(_G, stateKey, state)
  end

  state.enabled = enabled == true

  if subscriptionIsActive(state, "subscription") and subscriptionIsActive(state, "closeSubscription") then return end

  if not subscriptionIsActive(state, "subscription") then
    removeSubscription(state, "subscription")
    state.subscription = hl.on("window.open_early", onWindowOpen)
  end

  if not subscriptionIsActive(state, "closeSubscription") then
    removeSubscription(state, "closeSubscription")
    state.closeSubscription = hl.on("window.close", onWindowClose)
  end
end

function hook.remove()
  local state = rawget(_G, stateKey)
  if not state then return end

  state.enabled = false
  removeSubscription(state, "subscription")
  removeSubscription(state, "closeSubscription")
  rawset(_G, stateKey, nil)
end

return hook
