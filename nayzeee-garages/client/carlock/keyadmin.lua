--[[
  nayzeee-garages — car lock: admin key manager and admin key settings (client).
  docs/CARLOCK.md §15 / §19, docs/V2_CHANGES.md G.12 / G.13.

  /vehiclekeysadmin (server: NZ.CarLock.isAdmin) → event 'nz:client:carlock:keyAdmin' →
  CarLock.openKeyAdmin(opts) opens the 'keyadmin' NUI app. Every answer comes from the server
  (admin checked and rate limited there); this file only forwards and adds what a client can
  see on its own: vehicle labels / makes of the models (display only).

  NUI callbacks (all forward to nz:carlock:admin:*):
    keyadmin:search       { query }                                 -> KeyAdminSearch
    keyadmin:player       { identifier }                            -> KeyAdminPlayerData
    keyadmin:give         { identifier, plate, type, keyKind?, hours? } -> KeyAdminPlayerData
    keyadmin:delete       { identifier, id }                        -> KeyAdminPlayerData
    keyadmin:plate        { plate }                                 -> KeyAdminPlateData
    keyadmin:track        { plate }                                 -> KeyAdminTrack
    keyadmin:waypoint     { plate }  asks nz:carlock:admin:track and sets the waypoint at the
                                     server's position (never a position from the page)
    keyadmin:settings     {}                                        -> KeySettings
    keyadmin:saveSettings { values, reset? }                        -> KeySettings
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local APP = 'keyadmin'
local MAX_QUERY = 64
local MAX_ID = 64
local GIVE_TYPES = { item = true, temp = true, virtual = true }
local PAGES = { keys = true, settings = true }
local SETTING_TABS = {
  keys = true, ground = true, vehicles = true, lockpicking = true, hotwiring = true, npc = true, jobs = true, security = true,
}

local opening = false

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function str(value, max)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('%c', '')
  value = Utils.trim(value)
  if value == '' or #value > max then return nil end
  return value
end

--- Model hash of a vehicle the client can see (network id in scope), else nil.
local function hashOfNet(netId)
  netId = tonumber(netId)
  if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
  local vehicle = NetToVeh(netId)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
  return GetEntityModel(vehicle)
end

--- Display label and make of a model (spawn name), falling back to a visible entity.
---@return number|nil hash, string|nil label, string|nil make
local function describe(model, netId)
  local hash = nil
  if type(model) == 'string' and model ~= '' then
    hash = joaat(model)
    if not IsModelInCdimage(hash) then hash = nil end
  end
  hash = hash or hashOfNet(netId)
  if not hash or type(NZ.Veh.label) ~= 'function' then return hash, nil, nil end
  local ok, label, make = pcall(NZ.Veh.label, hash, type(model) == 'string' and model ~= '' and model or nil)
  if not ok then return hash, nil, nil end
  return hash, label, make ~= '' and make or nil
end

local function decorateRow(row)
  if type(row) ~= 'table' then return end
  local hash, label, make = describe(row.model, row.netId)
  row.hash, row.label, row.make = hash, label, make
end

local function decoratePlayer(res)
  if res.ok and type(res.data) == 'table' and type(res.data.keys) == 'table' then
    for _, row in ipairs(res.data.keys) do decorateRow(row) end
  end
  return res
end

local function decoratePlate(res)
  if res.ok and type(res.data) == 'table' then
    local _, label, make = describe(res.data.model, res.data.netId)
    res.data.label, res.data.make = label, make
  end
  return res
end

--- Plate from the page: trimmed, upper case, at most 8 characters.
local function plateArg(value)
  local plate = Utils.plate(value)
  if not plate or #plate > 8 or plate:find('%c') then return nil end
  return plate
end

local function bad()
  return Utils.fail(L('Invalid request'))
end

---------------------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------------------

--- Open the admin key manager. opts (all optional): { page = 'keys'|'settings', settingsTab,
--- identifier, plate, query } (see KeyAdminOpenData). The server already checked the admin
--- for the command; every callback checks again.
---@param opts table|nil
---@return boolean
function CarLock.openKeyAdmin(opts)
  opts = type(opts) == 'table' and opts or {}
  if opening then return false end
  if NZ.NUI.isOpen(APP) then return true end
  if NZ.NUI.isOpen() then
    NZ.NUI.notify('error', L('Close the open window first'))
    return false
  end
  opening = true
  local cfg = CarLock.cfg()
  local fob = type(cfg.fob) == 'table' and cfg.fob or {}
  local okMode, mode = pcall(CarLock.keyMode)
  NZ.NUI.open(APP, {
    page = PAGES[opts.page] and opts.page or 'keys',
    settingsTab = SETTING_TABS[opts.settingsTab] and opts.settingsTab or nil,
    identifier = str(opts.identifier, MAX_ID),
    plate = plateArg(opts.plate),
    query = str(opts.query, MAX_QUERY),
    fobDesign = type(fob.defaultDesign) == 'string' and fob.defaultDesign or nil,
    tempKeyHours = tonumber(cfg.tempKeyHours) or 24,
    keyMode = okMode and mode or nil,
  })
  opening = false
  return true
end

NZ.NUI.onClose(APP, function()
  opening = false
end)

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

NZ.NUI.register('keyadmin:search', function(data)
  local query = type(data.query) == 'string' and data.query:gsub('%c', '') or ''
  if #query > MAX_QUERY then query = query:sub(1, MAX_QUERY) end
  return NZ.NUI.await('nz:carlock:admin:search', { query = query })
end)

NZ.NUI.register('keyadmin:player', function(data)
  local identifier = str(data.identifier, MAX_ID)
  if not identifier then return bad() end
  return decoratePlayer(NZ.NUI.await('nz:carlock:admin:player', { identifier = identifier }))
end)

NZ.NUI.register('keyadmin:give', function(data)
  local identifier = str(data.identifier, MAX_ID)
  local plate = plateArg(data.plate)
  if not identifier or not plate or not GIVE_TYPES[data.type] then return bad() end
  local payload = { identifier = identifier, plate = plate, type = data.type }
  if data.type == 'item' and (data.keyKind == 'key' or data.keyKind == 'fob') then payload.keyKind = data.keyKind end
  if data.type == 'temp' then payload.hours = tonumber(data.hours) end
  return decoratePlayer(NZ.NUI.await('nz:carlock:admin:give', payload))
end)

NZ.NUI.register('keyadmin:delete', function(data)
  local identifier = str(data.identifier, MAX_ID)
  local id = str(data.id, MAX_ID)
  if not identifier or not id then return bad() end
  return decoratePlayer(NZ.NUI.await('nz:carlock:admin:delete', { identifier = identifier, id = id }))
end)

NZ.NUI.register('keyadmin:plate', function(data)
  local plate = plateArg(data.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  return decoratePlate(NZ.NUI.await('nz:carlock:admin:plate', { plate = plate }))
end)

NZ.NUI.register('keyadmin:track', function(data)
  local plate = plateArg(data.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  return NZ.NUI.await('nz:carlock:admin:track', { plate = plate })
end)

NZ.NUI.register('keyadmin:waypoint', function(data)
  local plate = plateArg(data.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local res = NZ.NUI.await('nz:carlock:admin:track', { plate = plate })
  if not res.ok then return res end
  local info = type(res.data) == 'table' and res.data or {}
  local c = type(info.coords) == 'table' and info.coords or nil
  if not info.spawned or not c or not tonumber(c.x) or not tonumber(c.y) then
    return Utils.fail(L('The vehicle is not out'))
  end
  SetNewWaypoint(tonumber(c.x) + 0.0, tonumber(c.y) + 0.0)
  return res
end)

NZ.NUI.register('keyadmin:settings', function()
  return NZ.NUI.await('nz:carlock:admin:settings', {})
end)

NZ.NUI.register('keyadmin:saveSettings', function(data)
  local values = type(data.values) == 'table' and data.values or {}
  local reset = {}
  if type(data.reset) == 'table' then
    for _, id in ipairs(data.reset) do
      if type(id) == 'string' and #id <= MAX_ID then reset[#reset + 1] = id end
    end
  end
  return NZ.NUI.await('nz:carlock:admin:saveSettings', { values = values, reset = reset })
end)
