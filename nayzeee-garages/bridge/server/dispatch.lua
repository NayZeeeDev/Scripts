--[[
  nayzeee-garages — police dispatch integration (server): NZ.Dispatch. docs/CARLOCK.md §6.
  Open file: edit the CUSTOM adapter below for a dispatch resource that is not supported.

  NZ.Dispatch.alert(src, alert) -> boolean
    src    the offender (player source) or nil for alerts without one (trusted server code)
    alert  { kind = 'theft'|'lockpick'|'hotwire'|'search'|'robbery'|'alarm'|'locksmith'|'fakeplate'|...,
             code?, title?, message?, coords?, plate?, model?, modelHash?, color?, street?,
             streetFromClient?, modelFromClient? (street / model are the offender's client's text:
             officers' clients use their own lookup instead, see bridge/client/dispatch.lua),
             priority? (1 high .. 3 low), jobs? (default Config.CarLock.dispatch.jobs),
             blip? = { sprite, color, scale, seconds, radius, flash } }
    Missing fields come from Config.CarLock.dispatch (codes, blip, jobs) and the kind
    (translated title, message built from colour, model and plate). coords default to the
    offender's SERVER ped position; nothing a client sends decides who is alerted or where.

  Config.CarLock.dispatch.system:
    'auto'   first started of wasabi_mdt, rcore_dispatch, cd_dispatch3d / cd_dispatch,
             qs-dispatch, core_dispatch, ps-dispatch (last: other systems mirror or emulate
             it), else 'internal'. Detected when an alert is sent (cached a few seconds and
             reset when one of them starts / stops).
    '<name>' that system ('internal' when it is not running)
    'internal' on-duty players of the configured jobs get a notification and a timed blip
    'custom'   the CUSTOM adapter below (+ CUSTOM.client in bridge/client/dispatch.lua)
    'none'     no alerts

  Where an alert is delivered (one system per alert):
    server side (TriggerEvent / exports): wasabi_mdt ('wasabi_mdt:createExternalDispatch'),
      rcore_dispatch ('rcore_dispatch:server:sendAlert'), core_dispatch (sendAlert, addCall),
      qs-dispatch ('qs-dispatch:server:CreateDispatchCall').
      ps-dispatch 3.x (SendTargetedAlert to the on-duty receivers, offender or not).
    on the OFFENDER's client ('nz:client:dispatch' with the payload built here; their client
      APIs need it): ps-dispatch 2.x (CustomAlert), cd_dispatch (GetPlayerInfo + AddNotification).
      Without an offender these use their server paths: ps-dispatch 2.x
      'ps-dispatch:server:notify', cd_dispatch's server event.
    Display text (street, model, message ...) is stripped of markup before it reaches any of
    them.
    Any error (or a client that reports its system failed, once per alert id) falls back to
    'internal'. Durations are configured in seconds and converted per system.
]]

local Dispatch = NZ.Dispatch
local Utils = NZ.Utils

---------------------------------------------------------------------------------------
-- CUSTOM ADAPTER — edit this for a dispatch resource that is not supported out of the box
-- and set Config.CarLock.dispatch.system = 'custom'.
--   server(src, alert): runs on the server. Return true when the alert was sent. src is the
--     offender (nil for alerts without one). alert: see the header (all fields filled in).
--   client = true: run CUSTOM.client (bridge/client/dispatch.lua) on the offender's client
--     instead whenever there is an offender (server() is used for alerts without one).
---------------------------------------------------------------------------------------

local CUSTOM = {
  client = false,
  server = function(src, alert) -- luacheck: ignore 212
    -- Example:
    -- TriggerEvent('my_dispatch:server:newCall', {
    --   jobs = alert.jobs, coords = alert.coords, title = alert.code .. ' - ' .. alert.title,
    --   message = alert.message, blipSprite = alert.blip.sprite, seconds = alert.blip.seconds,
    -- })
    -- return true
    return false
  end,
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local CACHE_MS = 5000
local PENDING_MS = 30000          -- a client-delivered alert may report a failure this long
local MAX_PENDING = 200
local AUTO_ORDER = { 'wasabi_mdt', 'rcore_dispatch', 'cd_dispatch', 'qs-dispatch', 'core_dispatch', 'ps-dispatch' }
local RESOURCES = {
  wasabi_mdt = { 'wasabi_mdt' },
  rcore_dispatch = { 'rcore_dispatch' },
  cd_dispatch = { 'cd_dispatch3d', 'cd_dispatch' },
  ['qs-dispatch'] = { 'qs-dispatch' },
  core_dispatch = { 'core_dispatch' },
  ['ps-dispatch'] = { 'ps-dispatch' },
}
local WATCH = {}
for _, list in pairs(RESOURCES) do
  for _, name in ipairs(list) do WATCH[name] = true end
end

local warned = {}
local cache = { system = nil, at = -1e9 }
local pending = {}                -- [id] = { src, alert, expires }
local pendingCount = 0
local counter = 0

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(('[nayzeee-garages] dispatch: %s'):format(message))
end

local function cfg()
  local carlock = type(Config.CarLock) == 'table' and Config.CarLock or {}
  return type(carlock.dispatch) == 'table' and carlock.dispatch or {}
end

local function started(name)
  return Utils.resourceStarted(name) == true
end

local function resourceOf(system)
  for _, name in ipairs(RESOURCES[system] or {}) do
    if started(name) then return name end
  end
  return nil
end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

--- Text that ends up in police MDT / dispatch UIs (which may render it as HTML): no control
--- characters, no markup, straight quotes made typographic, at most `max` bytes of whole
--- UTF-8 characters.
local function text(value, max)
  if type(value) == 'number' then value = tostring(value) end
  if type(value) ~= 'string' then return nil end
  value = value:gsub('[%c]', ' '):gsub('[<>&`\\]', ''):gsub("'", '\u{2019}'):gsub('"', '\u{201D}')
  value = value:gsub('^%s+', ''):gsub('%s+$', '')
  if #value > max then
    value = value:sub(1, max)
    for _ = 1, 3 do
      if utf8.len(value) then break end
      value = value:sub(1, -2)
    end
  end
  if value == '' then return nil end
  return value
end

local function number(value, min, max, default)
  local n = tonumber(value)
  if not n or n ~= n then return default end
  return Utils.clamp(n, min, max)
end

--- Call a third-party function; false + one warning per label on error.
local function try(label, fn, ...)
  local res = table.pack(pcall(fn, ...))
  if not res[1] then
    warnOnce('err:' .. label, ('%s failed: %s'):format(label, tostring(res[2])))
    return false
  end
  return true, table.unpack(res, 2, res.n)
end

---------------------------------------------------------------------------------------
-- System
---------------------------------------------------------------------------------------

local KNOWN = { internal = true, custom = true, none = true }
for name in pairs(RESOURCES) do KNOWN[name] = true end
local ALIASES = { cd_dispatch3d = 'cd_dispatch', ps_dispatch = 'ps-dispatch', qs_dispatch = 'qs-dispatch', wasabi = 'wasabi_mdt' }

local function detect()
  local configured = cfg().system
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  configured = ALIASES[configured] or configured
  if configured == 'auto' then
    for _, system in ipairs(AUTO_ORDER) do
      if resourceOf(system) then return system end
    end
    return 'internal'
  end
  if not KNOWN[configured] then
    warnOnce('unknown:' .. configured, ('unknown system "%s": using "internal"'):format(configured))
    return 'internal'
  end
  if RESOURCES[configured] and not resourceOf(configured) then
    warnOnce('missing:' .. configured, ('%s is not running: using "internal"'):format(configured))
    return 'internal'
  end
  return configured
end

--- Dispatch system in use right now ('none' | 'internal' | 'custom' | a resource name).
---@return string
function Dispatch.system()
  local now = GetGameTimer()
  if cache.system and now - cache.at < CACHE_MS then return cache.system end
  cache.system, cache.at = detect(), now
  return cache.system
end

local function resetCache(resource)
  if WATCH[resource] then cache.system = nil end
end
AddEventHandler('onResourceStart', resetCache)
AddEventHandler('onResourceStop', resetCache)

---------------------------------------------------------------------------------------
-- Alert building
---------------------------------------------------------------------------------------

local TITLES = {
  theft = 'Vehicle theft',
  lockpick = 'Vehicle break-in',
  hotwire = 'Vehicle theft in progress',
  search = 'Suspicious person in a vehicle',
  robbery = 'Carjacking',
  alarm = 'Car alarm',
  locksmith = 'Suspicious key cutting',
  fakeplate = 'Fake licence plate',
  tracker = 'Stolen vehicle tracker',
}
local PRIORITY = { robbery = 1, alarm = 3, locksmith = 3, fakeplate = 3 }
local VEHICLE_KINDS = { theft = true, lockpick = true, hotwire = true, search = true, robbery = true, alarm = true, tracker = true }

local function titleOf(kind)
  local custom = type(cfg().titles) == 'table' and cfg().titles[kind] or nil
  if type(custom) == 'string' and custom ~= '' then return L(custom) end
  return L(TITLES[kind] or 'Vehicle theft')
end

local function codeOf(kind)
  local codes = type(cfg().codes) == 'table' and cfg().codes or {}
  return text(codes[kind], 16) or text(codes.theft, 16) or '10-60'
end

--- "Red Karin Sultan · plate 12ABC345" (parts that are known).
local function describe(alert)
  local vehicle = alert.model
  if vehicle and alert.color then vehicle = L('{color} {model}', { color = alert.color, model = vehicle }) end
  if vehicle and alert.plate then return L('{vehicle} · plate {plate}', { vehicle = vehicle, plate = alert.plate }) end
  if vehicle then return vehicle end
  if alert.plate then return L('Vehicle with plate {plate}', { plate = alert.plate }) end
  return L('Unknown vehicle')
end

local function blipOf(kind, given)
  local base = type(cfg().blip) == 'table' and cfg().blip or {}
  local perKind = type(cfg().blips) == 'table' and type(cfg().blips[kind]) == 'table' and cfg().blips[kind] or {}
  given = type(given) == 'table' and given or {}
  local function pick(key) if given[key] ~= nil then return given[key] end if perKind[key] ~= nil then return perKind[key] end return base[key] end
  return {
    sprite = math.floor(number(pick('sprite'), 1, 999, 225)),
    color = math.floor(number(pick('color'), 0, 85, 1)),
    scale = number(pick('scale'), 0.1, 3.0, 1.0) + 0.0,
    seconds = math.floor(number(pick('seconds'), 5, 3600, 90)),
    radius = number(pick('radius'), 0.0, 500.0, 0.0) + 0.0,
    flash = pick('flash') ~= false,
  }
end

local function jobsOf(given)
  local list = type(given) == 'table' and given or cfg().jobs
  local out, seen = {}, {}
  for _, job in ipairs(type(list) == 'table' and list or {}) do
    local name = text(job, 32)
    if name and not seen[name:lower()] then
      seen[name:lower()] = true
      out[#out + 1] = name
    end
    if #out >= 16 then break end
  end
  if #out == 0 then out[1] = 'police' end
  return out
end

local function coordsOf(src, given)
  local v = Utils.v3(given)
  if v then return v end
  if src then
    local ped = GetPlayerPed(tostring(src))
    if ped and ped ~= 0 then
      local c = GetEntityCoords(ped)
      if c then return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 } end
    end
  end
  return nil
end

--- Complete, sanitized alert (nil when there is no position).
---@param src number|nil
---@param alert table
---@return table|nil
function Dispatch.build(src, alert)
  alert = type(alert) == 'table' and alert or {}
  local kind = text(alert.kind, 24) or 'theft'
  local coords = coordsOf(src, alert.coords)
  if not coords then return nil end
  local out = {
    kind = kind,
    code = text(alert.code, 16) or codeOf(kind),
    coords = coords,
    plate = text(alert.plate, 16),
    model = text(alert.model, 48),
    modelHash = math.tointeger(tonumber(alert.modelHash)) or nil,
    color = text(alert.color, 32),
    street = text(alert.street, 64),
    streetFromClient = alert.streetFromClient == true or nil,
    modelFromClient = alert.modelFromClient == true or nil,
    priority = math.floor(number(alert.priority, 1, 3, PRIORITY[kind] or 2)),
    jobs = jobsOf(alert.jobs),
    blip = blipOf(kind, alert.blip),
    vehicle = VEHICLE_KINDS[kind] == true,
  }
  out.title = text(alert.title, 64) or titleOf(kind)
  out.message = text(alert.message, 200) or describe(out)
  return out
end

---------------------------------------------------------------------------------------
-- Delivery: internal
---------------------------------------------------------------------------------------

--- Online players with one of `jobs`, on duty.
---@param jobs string[]
---@return number[]
function Dispatch.receivers(jobs)
  local wanted = {}
  for _, job in ipairs(jobs or {}) do wanted[tostring(job):lower()] = true end
  local out = {}
  if type(NZ.Bridge.getJob) ~= 'function' then return out end
  for _, id in ipairs(GetPlayers() or {}) do
    local src = validSrc(id)
    if src then
      local ok, job = pcall(NZ.Bridge.getJob, src)
      if ok and type(job) == 'table' and type(job.name) == 'string' and wanted[job.name:lower()] and job.onDuty ~= false then
        out[#out + 1] = src
      end
    end
  end
  return out
end

local function sendInternal(alert)
  local list = Dispatch.receivers(alert.jobs)
  local payload = {
    kind = alert.kind, code = alert.code, title = alert.title, message = alert.message, coords = alert.coords,
    street = alert.street, plate = alert.plate, model = alert.model, modelHash = alert.modelHash,
    streetFromClient = alert.streetFromClient, modelFromClient = alert.modelFromClient,
    color = alert.color, priority = alert.priority, blip = alert.blip, sound = cfg().sound ~= false,
  }
  for _, target in ipairs(list) do TriggerClientEvent('nz:client:dispatch:alert', target, payload) end
  return true
end

---------------------------------------------------------------------------------------
-- Delivery: dispatch resources (server side)
---------------------------------------------------------------------------------------

local function vec(c) return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) end
local function minutes(seconds) return math.max(1, math.ceil(seconds / 60)) end
local function location(alert) return alert.street or alert.plate and L('Plate {plate}', { plate = alert.plate }) or L('Unknown location') end

local function wasabiType(kind)
  local types = type(cfg().wasabiTypes) == 'table' and cfg().wasabiTypes or {}
  return text(types[kind], 32) or text(types.default, 32) or 'robbery'
end

local function psVersion()
  local ok, version = pcall(GetResourceMetadata, 'ps-dispatch', 'version', 0)
  local major = ok and type(version) == 'string' and tonumber(version:match('^%s*(%d+)')) or nil
  return major or 0
end

--- ps-dispatch blip / alert table (length in minutes).
local function psAlert(alert)
  return {
    radius = alert.blip.radius, sprite = alert.blip.sprite, color = alert.blip.color, scale = alert.blip.scale,
    length = minutes(alert.blip.seconds), sound = 'Lose_1st', sound2 = 'GTAO_FM_Events_Soundset',
    offset = false, flash = alert.blip.flash,
  }
end

local function cdPayload(alert, uniqueId)
  return {
    job_table = alert.jobs, coords = vec(alert.coords), title = ('%s - %s'):format(alert.code, alert.title),
    message = alert.message, flash = alert.priority == 1 and 1 or 0,
    unique_id = uniqueId or tostring(math.random(1000000, 9999999)), sound = 1,
    blip = { sprite = alert.blip.sprite, scale = alert.blip.scale, colour = alert.blip.color, flashes = alert.blip.flash,
      text = alert.title, time = minutes(alert.blip.seconds), radius = alert.blip.radius },
  }
end

local function qsPayload(alert)
  local info = { { text = alert.plate or L('Unknown plate'), icon = 'fas fa-car' } }
  if alert.model then
    info[#info + 1] = { text = alert.color and L('{color} {model}', { color = alert.color, model = alert.model }) or alert.model,
      icon = 'fas fa-car-side' }
  end
  if alert.street then info[#info + 1] = { text = alert.street, icon = 'fas fa-location-dot' } end
  return {
    job = alert.jobs, callLocation = vec(alert.coords),
    callCode = { code = alert.code, snippet = alert.title }, message = alert.message, flashes = alert.blip.flash,
    image = nil,
    blip = { sprite = alert.blip.sprite, scale = alert.blip.scale, colour = alert.blip.color, flashes = alert.blip.flash,
      text = alert.title, time = alert.blip.seconds * 1000 },
    otherData = info,
  }
end

local SERVER = {}

SERVER.wasabi_mdt = function(alert)
  TriggerEvent('wasabi_mdt:createExternalDispatch', {
    type = wasabiType(alert.kind),
    title = ('%s - %s'):format(alert.code, alert.title),
    description = alert.message,
    location = location(alert),
    coords = { x = alert.coords.x, y = alert.coords.y, z = alert.coords.z },
    priority = ({ 4, 2, 1 })[alert.priority] or 2,
    departments = alert.jobs,
  })
  return true
end

SERVER.rcore_dispatch = function(alert)
  TriggerEvent('rcore_dispatch:server:sendAlert', {
    code = alert.code,
    default_priority = ({ 'high', 'medium', 'low' })[alert.priority] or 'medium',
    coords = vec(alert.coords),
    job = alert.jobs,
    text = ('%s - %s'):format(alert.title, alert.message),
    type = alert.vehicle and 'car_robbery' or 'alerts',
    blip_time = alert.blip.seconds,
    blip = { sprite = alert.blip.sprite, colour = alert.blip.color, scale = alert.blip.scale, text = alert.title,
      flashes = alert.blip.flash, radius = alert.blip.radius },
  })
  return true
end

SERVER.core_dispatch = function(alert)
  local okSend = try('core_dispatch sendAlert', function()
    exports.core_dispatch:sendAlert({
      code = alert.code, message = ('%s - %s'):format(alert.title, alert.message),
      extraInfo = { { icon = 'fa-car', info = alert.plate or L('Unknown plate') } },
      coords = vec(alert.coords), priority = alert.priority == 1, job = alert.jobs[1],
      time = alert.blip.seconds * 1000, blip = alert.blip.sprite, color = alert.blip.color,
    })
  end)
  if okSend then return true end
  return (try('core_dispatch addCall', function()
    exports.core_dispatch:addCall(alert.code, alert.title, { { icon = 'fa-car', info = alert.message } },
      vec(alert.coords), alert.jobs[1], 5000, alert.blip.sprite, alert.blip.color, alert.priority == 1)
  end))
end

SERVER.cd_dispatch = function(alert)
  TriggerEvent('cd_dispatch:AddNotification', cdPayload(alert))
  return true
end

SERVER['qs-dispatch'] = function(alert)
  TriggerEvent('qs-dispatch:server:CreateDispatchCall', qsPayload(alert))
  return true
end

SERVER['ps-dispatch'] = function(alert)
  local data = {
    message = alert.title, information = alert.message, code = alert.code, codeName = 'nz_' .. alert.kind,
    icon = 'fas fa-car', priority = alert.priority, coords = vec(alert.coords), street = alert.street or '',
    vehicle = alert.model, plate = alert.plate, color = alert.color, jobs = alert.jobs, alert = psAlert(alert),
  }
  if psVersion() >= 3 then
    -- 3.x: never the notify event from the server (its rate limit compares the source with 0)
    local targets = Dispatch.receivers(alert.jobs)
    if #targets == 0 then return true end
    data.addToList = true
    local ok, res = try('ps-dispatch SendTargetedAlert', function()
      return exports['ps-dispatch']:SendTargetedAlert(targets, data)
    end)
    return ok and res ~= false
  end
  TriggerEvent('ps-dispatch:server:notify', data)
  return true
end

SERVER.custom = function(alert, src)
  local ok, res = try('custom dispatch', CUSTOM.server, src, alert)
  return ok and res == true
end

-- Systems whose alert is sent from the offender's client when there is one (their alert API
-- needs it: ps-dispatch 2.x CustomAlert, cd_dispatch GetPlayerInfo). Everything else, qs-dispatch
-- and ps-dispatch 3.x (SendTargetedAlert) included, is sent here on the server, where a modified
-- client cannot drop it.
local CLIENT = { ['ps-dispatch'] = true, cd_dispatch = true }

local function viaOffenderClient(system)
  if system == 'custom' then return CUSTOM.client == true end
  if not CLIENT[system] then return false end
  return not (system == 'ps-dispatch' and psVersion() >= 3)
end

---------------------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------------------

local function remember(src, alert)
  local now = GetGameTimer()
  if pendingCount >= MAX_PENDING then
    for id, entry in pairs(pending) do
      if entry.expires <= now then pending[id] = nil pendingCount = pendingCount - 1 end
    end
    if pendingCount >= MAX_PENDING then return end
  end
  pending[alert.id] = { src = src, alert = alert, expires = now + PENDING_MS }
  pendingCount = pendingCount + 1
end

--- Send a police alert. Returns true when it was handed to a system.
---@param src number|nil offender (player source) or nil
---@param alert table see the header
---@return boolean
function Dispatch.alert(src, alert)
  local ok, res = pcall(function()
    src = validSrc(src)
    local system = Dispatch.system()
    if system == 'none' then return false end
    local built = Dispatch.build(src, alert)
    if not built then return false end
    counter = counter + 1
    built.id = counter
    Utils.debug(('dispatch: %s alert "%s" via %s'):format(built.kind, built.title, system))

    local viaClient = src ~= nil and viaOffenderClient(system)
    if viaClient then
      built.system = system
      built.resource = resourceOf(system)
      remember(src, built)
      TriggerClientEvent('nz:client:dispatch', src, built)
      return true
    end
    local sender = SERVER[system]
    if sender then
      local okSend, sent = pcall(sender, built, src)
      if okSend and sent then return true end
      if not okSend then warnOnce('send:' .. system, ('%s failed: %s (using "internal")'):format(system, tostring(sent))) end
    end
    return sendInternal(built)
  end)
  if not ok then
    lib.print.warn(('[nayzeee-garages] dispatch: alert failed: %s'):format(tostring(res)))
    return false
  end
  return res == true
end

-- The offender's client could not use its dispatch resource (missing export, error): the
-- alert it was given (server-built, once per id) goes out through 'internal'.
lib.callback.register('nz:dispatch:failed', function(source, payload)
  local src = validSrc(source)
  local id = type(payload) == 'table' and math.tointeger(tonumber(payload.id)) or nil
  local entry = id and pending[id] or nil
  if not src or not entry or entry.src ~= src then return Utils.ok(false) end
  pending[id] = nil
  pendingCount = pendingCount - 1
  if entry.expires < GetGameTimer() then return Utils.ok(false) end
  warnOnce('client:' .. tostring(entry.alert.system), ('%s could not be used on a client (%s): using "internal"')
    :format(tostring(entry.alert.system), type(payload.reason) == 'string' and payload.reason:sub(1, 120) or 'unknown'))
  return Utils.ok(sendInternal(entry.alert))
end)

-- The client delivered it: forget the alert.
lib.callback.register('nz:dispatch:sent', function(source, payload)
  local src = validSrc(source)
  local id = type(payload) == 'table' and math.tointeger(tonumber(payload.id)) or nil
  local entry = id and pending[id] or nil
  if src and entry and entry.src == src then
    pending[id] = nil
    pendingCount = pendingCount - 1
  end
  return Utils.ok(true)
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  for id, entry in pairs(pending) do
    if entry.src == src then
      pending[id] = nil
      pendingCount = pendingCount - 1
    end
  end
end)
