--[[
  nayzeee-garages — client boot (last client file).
  Waits for the character to load, pulls the client state from the server
  ('nz:state:bootstrap'), fills NZ.State, builds the interaction points and keeps the
  state in sync with server pushes and framework job / gang / login events.
]]

local State = NZ.State

local bootGeneration = 0
local rebuildQueued = false

---------------------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------------------

local function setSettings(settings)
  if type(settings) ~= 'table' then return end
  State.settings = NZ.Utils.applyDefaults(settings, Config.DefaultSettings)
end

--- Split client views into NZ.State.locations (by id) and NZ.State.houses (kind 'house').
local function setLocations(views)
  local locations, houses = {}, {}
  if type(views) == 'table' then
    for _, view in pairs(views) do
      if type(view) == 'table' and view.id ~= nil then
        if view.kind == 'house' then
          houses[view.id] = view
        else
          locations[tonumber(view.id) or view.id] = view
        end
      end
    end
  end
  State.locations = locations
  State.houses = houses
end

--- Groups arrive as { [locationId] = true } (keys may be strings after JSON).
local function setGroups(groups)
  local out = {}
  if type(groups) == 'table' then
    for key, value in pairs(groups) do
      if value == true then
        out[tonumber(key) or key] = true
      elseif type(value) == 'number' or type(value) == 'string' then
        out[tonumber(value) or value] = true
      end
    end
  end
  State.groups = out
end

local function bridgeCall(fn)
  if type(fn) ~= 'function' then return nil end
  local ok, res = pcall(fn)
  if ok and type(res) == 'table' then return res end
  return nil
end

local function refreshJobs()
  State.job = bridgeCall(NZ.Bridge.getJob)
  State.gang = bridgeCall(NZ.Bridge.getGang)
end

local function isLoggedIn()
  if type(NZ.Bridge.isLoggedIn) == 'function' then
    local ok, res = pcall(NZ.Bridge.isLoggedIn)
    return ok and res == true
  end
  return NetworkIsPlayerActive(PlayerId())
end

local function safeRun(label, fn)
  local ok, err = pcall(fn)
  if not ok then lib.print.error(('[nayzeee-garages] %s failed: %s'):format(label, err)) end
end

--- Coalesce rebuild requests that arrive together (locations + settings + groups).
local function scheduleRebuild()
  if not State.ready or rebuildQueued then return end
  rebuildQueued = true
  SetTimeout(100, function()
    rebuildQueued = false
    if State.ready then safeRun('points rebuild', NZ.Points.rebuild) end
  end)
end

---------------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------------

local function applyBootstrap(data)
  setSettings(type(data.settings) == 'table' and data.settings or NZ.Utils.deepCopy(Config.DefaultSettings))
  setLocations(data.locations)
  setGroups(data.groups)
  State.isAdmin = data.isAdmin == true
  refreshJobs()
  safeRun('NUI settings', NZ.NUI.syncSettings)
  safeRun('points rebuild', NZ.Points.rebuild)
  safeRun('impound target', NZ.ImpoundClient.setupTarget)
  State.ready = true
  NZ.Utils.debug('client state ready')
end

--- (Re)load the client state. A newer call cancels an older one still waiting.
local function boot()
  bootGeneration = bootGeneration + 1
  local generation = bootGeneration
  CreateThread(function()
    while generation == bootGeneration and not isLoggedIn() do Wait(500) end
    local delay = 1000
    while generation == bootGeneration do
      local ok, res = pcall(lib.callback.await, 'nz:state:bootstrap', false, {})
      local data = nil
      if ok and type(res) == 'table' then
        if res.ok == true then
          data = res.data
        elseif res.ok == nil and res.settings ~= nil then
          data = res
        else
          NZ.Utils.debug('bootstrap refused:', tostring(res.error))
        end
      elseif not ok then
        NZ.Utils.debug('bootstrap failed:', tostring(res))
      end
      if type(data) == 'table' then
        if generation == bootGeneration then applyBootstrap(data) end
        return
      end
      -- The server is probably still loading: retry with backoff.
      Wait(delay)
      delay = math.min(delay * 2, 15000)
    end
  end)
end

---------------------------------------------------------------------------------------
-- Server pushes
---------------------------------------------------------------------------------------

RegisterNetEvent('nz:client:locations', function(views)
  setLocations(views)
  scheduleRebuild()
end)

RegisterNetEvent('nz:client:settings', function(settings)
  if type(settings) ~= 'table' then return end
  setSettings(settings)
  safeRun('NUI settings', NZ.NUI.syncSettings)
  scheduleRebuild()
end)

RegisterNetEvent('nz:client:groups', function(groups)
  setGroups(groups)
  scheduleRebuild()
end)

---------------------------------------------------------------------------------------
-- Framework events (fired locally by the bridge)
---------------------------------------------------------------------------------------

AddEventHandler('nz:client:jobUpdated', function(job)
  if type(job) == 'table' and type(job.name) == 'string' then
    State.job = job
  else
    State.job = bridgeCall(NZ.Bridge.getJob)
  end
  scheduleRebuild()
end)

AddEventHandler('nz:client:gangUpdated', function(gang)
  if type(gang) == 'table' and type(gang.name) == 'string' then
    State.gang = gang
  else
    State.gang = bridgeCall(NZ.Bridge.getGang)
  end
  scheduleRebuild()
end)

AddEventHandler('nz:client:playerLoaded', function()
  boot()
end)

AddEventHandler('nz:client:playerUnloaded', function()
  bootGeneration = bootGeneration + 1 -- cancel a boot still waiting
  State.ready = false
  safeRun('close apps', function() NZ.NUI.close(nil) end)
  NZ.NUI.prompt(nil)
  NZ.NUI.hint(nil)
  NZ.NUI.hud(nil)
  safeRun('points clear', NZ.Points.clear)
  State.job, State.gang = nil, nil
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  SetNuiFocus(false, false)
end)

-- Resource start (or restart while the character is already loaded).
CreateThread(boot)
