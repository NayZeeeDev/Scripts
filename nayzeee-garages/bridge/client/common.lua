--[[
  nayzeee-garages — framework-agnostic client bridge (loaded after the framework adapters).
  Provides notify(), standalone fallbacks so every NZ.Bridge function exists, and error
  guards so a failing framework call never throws into the caller.
]]

local Bridge = NZ.Bridge
local State = NZ.State

local STANDALONE = NZ.Framework == 'standalone'

local TOAST_TYPES = {
  success = 'success', error = 'error', info = 'info', warning = 'warning',
  inform = 'info', warn = 'warning', primary = 'info',
}

--- Toast through our NUI (handled by client/nui.lua via the local event nz:client:notify).
---@param message string
---@param kind 'success'|'error'|'info'|'warning'|nil
function Bridge.notify(message, kind)
  if message == nil then return end
  TriggerEvent('nz:client:notify', { type = TOAST_TYPES[kind] or 'info', message = tostring(message) })
end

---------------------------------------------------------------------------------------
-- Standalone / missing-adapter fallbacks
---------------------------------------------------------------------------------------

local standaloneLoaded = false

local fallback = {}

function fallback.isLoggedIn()
  return STANDALONE and standaloneLoaded
end

function fallback.getIdentifier() return nil end
function fallback.getJob() return State.job end
function fallback.getGang() return State.gang end

for name, fn in pairs(fallback) do
  if type(Bridge[name]) ~= 'function' then Bridge[name] = fn end
end

if STANDALONE then
  -- No framework: the character is "loaded" once the player is in the session.
  standaloneLoaded = NetworkIsPlayerActive(PlayerId()) == true
  AddEventHandler('playerSpawned', function()
    if standaloneLoaded then return end
    standaloneLoaded = true
    TriggerEvent('nz:client:playerLoaded')
  end)
end

---------------------------------------------------------------------------------------
-- Error guards
---------------------------------------------------------------------------------------

local safeValue = {
  isLoggedIn = function() return false end,
  getIdentifier = function() return nil end,
  getJob = function() return State.job end,
  getGang = function() return State.gang end,
  notify = function() end,
}

local lastErrorAt = {}

for name, safe in pairs(safeValue) do
  local fn = Bridge[name]
  Bridge[name] = function(...)
    local res = table.pack(pcall(fn, ...))
    if res[1] then return table.unpack(res, 2, res.n) end
    local now = GetGameTimer()
    if not lastErrorAt[name] or now - lastErrorAt[name] > 30000 then
      lastErrorAt[name] = now
      lib.print.error(('[nayzeee-garages] NZ.Bridge.%s failed: %s'):format(name, tostring(res[2])))
    end
    return safe(...)
  end
end
