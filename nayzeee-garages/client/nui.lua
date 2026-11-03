--[[
  nayzeee-garages — NUI bridge (NZ.NUI).
  Sends messages to the interface, tracks which apps are open and owns NUI focus,
  registers NUI callbacks with a uniform { ok, data, error } response and forwards
  server-only callbacks 1:1 to `nz:<name>` (docs/ARCHITECTURE.md §3.3, §6, §8).
]]

local NUI = NZ.NUI

local openApps = {}        -- [app] = { focus = boolean }
local closeHooks = {}      -- [app] = { fn, ... }
local handlers = {}        -- [callbackName] = handler(data)
local nuiReady = false     -- the page called 'ready' (or any callback)
local initWithDefaults = false
local hasFocus = false
local lastPrompt = nil     -- 'key|label' of the prompt currently shown

---------------------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------------------

local function interfaceSettings()
  local settings = NZ.State.settings
  if type(settings) == 'table' and type(settings.interface) == 'table' then
    return settings.interface, true
  end
  return Config.DefaultSettings.interface, false
end

local function enrich(data)
  if type(data) ~= 'table' then return data end
  if NZ.Veh and NZ.Veh.enrichDeep then
    local ok, res = pcall(NZ.Veh.enrichDeep, data)
    if ok and res ~= nil then return res end
    if not ok then lib.print.warn(('[nayzeee-garages] enrichDeep failed: %s'):format(res)) end
  end
  return data
end

--- Normalize any handler return value into a callback result table.
local function toResult(res)
  if type(res) == 'table' and type(res.ok) == 'boolean' then
    if res.ok then
      return { ok = true, data = res.data }
    end
    return { ok = false, error = res.error or L('Something went wrong') }
  end
  return NZ.Utils.ok(res)
end

--- Apply NUI focus from the open apps. Only touches the native when the wanted state
--- changes (or `force`), so modules that briefly drop focus themselves (creator walk
--- mode) are not overridden by unrelated open/close calls.
local function applyFocus(force)
  local want = false
  for _, info in pairs(openApps) do
    if info.focus then
      want = true
      break
    end
  end
  if want == hasFocus and not force then return end
  hasFocus = want
  SetNuiFocus(want, want)
  if not want then SetNuiFocusKeepInput(false) end
end

local function runHooks(app, reason)
  local list = closeHooks[app]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], app, reason)
    if not ok then
      lib.print.error(('[nayzeee-garages] close hook for "%s" failed: %s'):format(app, err))
    end
  end
end

local function sendInit()
  local settings, loaded = interfaceSettings()
  initWithDefaults = not loaded
  SendNUIMessage({
    action = 'init',
    data = {
      locale = Locales[Config.Locale] or {},
      settings = settings,
      resource = NZ.ResourceName,
    },
  })
end

---------------------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------------------

--- Send a raw message to the interface (`{ action, data }`).
---@param action string
---@param data any
function NUI.send(action, data)
  if type(action) ~= 'string' then return end
  SendNUIMessage({ action = action, data = data })
end

--- Open an app with its data. Apps take NUI focus unless `focus` is false.
---@param app string AppName
---@param data table|nil
---@param focus boolean|nil default true
function NUI.open(app, data, focus)
  if type(app) ~= 'string' then return end
  openApps[app] = { focus = focus ~= false }
  NUI.send('open', { app = app, data = data })
  applyFocus()
  -- The interaction prompt never stays on top of a window.
  if focus ~= false then NUI.prompt(nil) end
end

--- Close one app (or every app when `app` is nil). Close hooks run once for each app
--- that was open; `reason` is passed to them ('lua' by default, 'nui' when the
--- interface asked to close).
---@param app string|nil
---@param reason string|nil
function NUI.close(app, reason)
  reason = reason or 'lua'
  if app == nil then
    local closed = {}
    for name in pairs(openApps) do closed[#closed + 1] = name end
    openApps = {}
    NUI.send('close', {})
    applyFocus()
    for i = 1, #closed do runHooks(closed[i], reason) end
    return
  end
  local wasOpen = openApps[app] ~= nil
  openApps[app] = nil
  NUI.send('close', { app = app })
  applyFocus()
  if wasOpen then runHooks(app, reason) end
end

--- Whether an app (or any app when nil) is open.
---@param app string|nil
---@return boolean
function NUI.isOpen(app)
  if app == nil then return next(openApps) ~= nil end
  return openApps[app] ~= nil
end

--- Change whether an already open app holds NUI focus (e.g. the creator while walking).
---@param app string
---@param focus boolean
function NUI.setFocus(app, focus)
  local info = openApps[app]
  if not info then return end
  info.focus = focus == true
  applyFocus(true)
end

--- Re-apply NUI focus from the open apps (e.g. after an ox_lib dialog).
function NUI.syncFocus()
  applyFocus(true)
end

--- Whether the interface currently holds focus.
---@return boolean
function NUI.hasFocus()
  return hasFocus
end

--- Register a cleanup function run when `app` closes: fn(app, reason).
---@param app string
---@param fn function
function NUI.onClose(app, fn)
  if type(app) ~= 'string' or type(fn) ~= 'function' then return end
  closeHooks[app] = closeHooks[app] or {}
  local list = closeHooks[app]
  list[#list + 1] = fn
end

--- Notification through NZ.Notify.show (bridge/client/notify.lua): drawn inside the interface
--- while a window holds focus, otherwise through the configured notify integration. Also
--- reachable from the server through the 'nz:client:notify' event and from the interface
--- through the 'notify' callback.
--- Call shapes: NUI.notify(type, message, title) or NUI.notify({ type, message, title?, duration? }).
---@param ntype string|table 'success'|'error'|'info'|'warning' (or a notification table)
---@param message string|nil
---@param title string|nil
function NUI.notify(ntype, message, title)
  local duration
  if type(ntype) == 'table' then
    local n = ntype
    ntype, message, title, duration = n.type, n.message, n.title, n.duration
  end
  if type(message) ~= 'string' or message == '' then return end
  NZ.Notify.show(ntype, message, title, tonumber(duration))
end

--- Draw a notification inside the interface (Lua -> NUI 'notify'). Only NZ.Notify.show calls
--- this, while a window holds NUI focus (FiveM then draws our page above every other
--- resource's NUI, so the notify resource would be hidden behind the window); everything
--- else uses NUI.notify. The text is already plain and capped by NZ.Notify.
---@param n table { type, message, title?, duration }
function NUI.toast(n)
  if type(n) ~= 'table' or type(n.message) ~= 'string' then return end
  NUI.send('notify', {
    type = n.type,
    title = n.title,
    message = n.message,
    duration = n.duration,
  })
end

--- Show (label) or hide (nil) the interaction prompt.
---@param label string|nil
---@param key string|nil default Config.Keys.interact
function NUI.prompt(label, key)
  if type(label) ~= 'string' or label == '' then
    if lastPrompt ~= nil then
      lastPrompt = nil
      NUI.send('prompt', nil)
    end
    return
  end
  key = key or Config.Keys.interact or 'E'
  local id = key .. '|' .. label
  if id == lastPrompt then return end
  lastPrompt = id
  NUI.send('prompt', { key = key, label = label })
end

--- Show (data) or hide (nil) the key hint bar: { title?, keys = { { keys = {...}, label } } }.
---@param data table|nil
function NUI.hint(data)
  NUI.send('hint', type(data) == 'table' and data or nil)
end

--- Build HUD data from a vehicle entity.
local function hudFromEntity(vehicle)
  local model = GetEntityModel(vehicle)
  local label, make, image = nil, nil, nil
  if NZ.Veh and NZ.Veh.label then
    local l, m, _, img = NZ.Veh.label(model)
    label, make, image = l, m, img
  end
  local fuel = 100
  if NZ.Fuel and NZ.Fuel.get then
    local ok, v = pcall(NZ.Fuel.get, vehicle)
    if ok and tonumber(v) then fuel = tonumber(v) end
  end
  local category = 'car'
  if NZ.Veh and NZ.Veh.categoryOf then category = NZ.Veh.categoryOf(model) or 'car' end
  return {
    plate = NZ.Utils.trim(GetVehicleNumberPlateText(vehicle) or '') or '',
    model = image or '',
    label = label or L('Vehicle'),
    make = make or '',
    image = image,
    vehicleType = category,
    mileage = 0,
    fuel = NZ.Utils.round(fuel, 0),
    engine = NZ.Utils.round(NZ.Utils.clamp(GetVehicleEngineHealth(vehicle) / 10, 0, 100), 0),
    body = NZ.Utils.round(NZ.Utils.clamp(GetVehicleBodyHealth(vehicle) / 10, 0, 100), 0),
  }
end

--- Interior stats HUD. Accepts HudVehicle data, a vehicle entity, or nil to hide.
---@param vehicle table|integer|nil
function NUI.hud(vehicle)
  if type(vehicle) == 'number' then
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
      NUI.send('hud', hudFromEntity(vehicle))
    else
      NUI.send('hud', nil)
    end
    return
  end
  if type(vehicle) == 'table' then
    NUI.send('hud', enrich(vehicle))
    return
  end
  NUI.send('hud', nil)
end

--- Push the interface settings after they load or change. Re-sends 'init' when the
--- page was initialised before the real settings were known.
function NUI.syncSettings()
  local settings, loaded = interfaceSettings()
  if not loaded then return end
  if initWithDefaults or not nuiReady then
    -- Settings arrive after login, long after the page loaded; if its 'ready' call was
    -- missed this (re)initialises it, otherwise 'ready' will send init again anyway.
    sendInit()
    nuiReady = true
  else
    NUI.send('settings', settings)
  end
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

--- Register a NUI callback. handler(data) returns a result table ({ ok, data, error })
--- or plain data; it runs in its own thread (awaiting is allowed) inside pcall, and the
--- interface always receives { ok, data, error }.
---@param name string
---@param handler function
function NUI.register(name, handler)
  if type(name) ~= 'string' or type(handler) ~= 'function' then return end
  local already = handlers[name] ~= nil
  handlers[name] = handler
  if already then return end
  RegisterNUICallback(name, function(data, cb)
    nuiReady = true
    CreateThread(function()
      local fn = handlers[name]
      local okCall, res = pcall(fn, type(data) == 'table' and data or {})
      local response
      if okCall then
        response = toResult(res)
      else
        lib.print.error(('[nayzeee-garages] NUI callback "%s" failed: %s'):format(name, res))
        response = NZ.Utils.fail(L('Something went wrong'))
      end
      cb(response)
    end)
  end)
end

--- Await a server callback and always return a result table.
---@param name string full callback name ('nz:...')
---@param payload table|nil
---@return table result
function NUI.await(name, payload)
  local ok, res = pcall(lib.callback.await, name, false, payload or {})
  if not ok then
    lib.print.error(('[nayzeee-garages] callback "%s" failed: %s'):format(name, res))
    return NZ.Utils.fail(L('The server did not respond, try again'))
  end
  if type(res) ~= 'table' or type(res.ok) ~= 'boolean' then
    return NZ.Utils.fail(L('The server did not respond, try again'))
  end
  if not res.ok and not res.error then res.error = L('Something went wrong') end
  return res
end

--- Forward NUI callback `name` 1:1 to the server callback 'nz:'..name. The response data
--- is enriched with vehicle labels. `after(result, data)` runs on the result when given.
---@param name string
---@param after function|nil
function NUI.forward(name, after)
  NUI.register(name, function(data)
    local result = NUI.await('nz:' .. name, data)
    if result.ok and result.data ~= nil then
      result.data = enrich(result.data)
    end
    if after then
      local ok, err = pcall(after, result, data)
      if not ok then
        lib.print.error(('[nayzeee-garages] follow-up for "%s" failed: %s'):format(name, err))
      end
    end
    return result
  end)
end

---------------------------------------------------------------------------------------
-- Built-in callbacks and forwards (registered once at load)
---------------------------------------------------------------------------------------

NUI.register('ready', function()
  nuiReady = true
  sendInit()
  return nil
end)

NUI.register('close', function(data)
  local app = type(data.app) == 'string' and data.app or nil
  NUI.close(app, 'nui')
  return nil
end)

-- 'notify' { type, message, title? }: the interface raises a notification (every toast()
-- and request() error in the web app). Validated and lightly rate limited; NZ.Notify.show
-- then decides where it is drawn (back inside the interface while a window has focus).
local NOTIFY_KINDS = { success = true, error = true, info = true, warning = true }
local NOTIFY_MAX_MESSAGE, NOTIFY_MAX_TITLE = 300, 60
local NOTIFY_WINDOW_MS, NOTIFY_PER_WINDOW = 3000, 8
local notifyWindowStart, notifyWindowCount = 0, 0

--- Character count (UTF-8 code points; byte length when the text is not valid UTF-8).
local function textLength(s)
  return utf8.len(s) or #s
end

NUI.register('notify', function(data)
  local kind, message, title = data.type, data.message, data.title
  if type(kind) ~= 'string' or not NOTIFY_KINDS[kind] then
    return NZ.Utils.fail(L('Invalid notification'))
  end
  if type(message) ~= 'string' or message:find('%S') == nil or textLength(message) > NOTIFY_MAX_MESSAGE then
    return NZ.Utils.fail(L('Invalid notification'))
  end
  if title ~= nil and (type(title) ~= 'string' or textLength(title) > NOTIFY_MAX_TITLE) then
    return NZ.Utils.fail(L('Invalid notification'))
  end
  local now = GetGameTimer()
  if now - notifyWindowStart >= NOTIFY_WINDOW_MS then
    notifyWindowStart, notifyWindowCount = now, 0
  end
  if notifyWindowCount >= NOTIFY_PER_WINDOW then
    return NZ.Utils.fail(L('Too many notifications, slow down'))
  end
  notifyWindowCount = notifyWindowCount + 1
  NZ.Notify.show(kind, message, title)
  return nil
end)

--- Re-fetch the open garage and push it to the garage app.
local function refreshGarage()
  if not NUI.isOpen('garage') then return end
  local result = NUI.await('nz:garage:refresh', {})
  if not result.ok then
    NUI.notify('error', result.error)
    return
  end
  local data = enrich(result.data)
  if NZ.Garage and NZ.Garage.setData then NZ.Garage.setData(data) end
  NUI.send('update', { app = 'garage', data = data })
end

local function onGarageData(result)
  if result.ok and type(result.data) == 'table' and NZ.Garage and NZ.Garage.setData then
    NZ.Garage.setData(result.data)
  end
end

local function refreshAfter(result)
  if result.ok then refreshGarage() end
end

local function onImpoundData(result)
  if result.ok and type(result.data) == 'table' and NZ.ImpoundClient and NZ.ImpoundClient.setData then
    NZ.ImpoundClient.setData(result.data)
  end
end

local followUps = {
  ['garage:refresh'] = onGarageData,
  ['garage:transfer'] = refreshAfter,
  ['garage:recover'] = refreshAfter,
  ['garage:payFinance'] = refreshAfter,
  ['garage:switchGroup'] = function(result)
    if not result.ok then return end
    local data = result.data
    if type(data) == 'table' and type(data.garage) == 'table' and type(data.vehicles) == 'table' then
      if NZ.Garage and NZ.Garage.setData then NZ.Garage.setData(data) end
      NUI.send('update', { app = 'garage', data = data })
    else
      refreshGarage()
    end
  end,
  ['garage:sellGarage'] = function(result)
    if result.ok then NUI.close('garage') end
  end,
  ['impound:refresh'] = onImpoundData,
  ['impound:release'] = onImpoundData,
  ['impoundForm:submit'] = function(result)
    if result.ok then NUI.close('impoundForm') end
  end,
  ['admin:settings:save'] = function(result)
    if not result.ok or type(result.data) ~= 'table' then return end
    NZ.State.settings = result.data
    NUI.syncSettings()
  end,
  -- Keep the admin client's cache current (used when re-opening the panel after a tool).
  ['admin:refresh'] = function(result)
    if result.ok and NZ.AdminClient and NZ.AdminClient.setCache then NZ.AdminClient.setCache(result.data) end
  end,
}

local forwarded = {
  'garage:refresh', 'garage:favourite', 'garage:rename', 'garage:transferOptions',
  'garage:transfer', 'garage:shares', 'garage:share', 'garage:unshare', 'garage:sell',
  'garage:recover', 'garage:payFinance', 'garage:members', 'garage:memberAdd',
  'garage:memberRole', 'garage:memberRemove', 'garage:sellGarage', 'garage:switchGroup',
  'impound:refresh', 'impound:release', 'impoundForm:submit',
  'interior:page', 'interior:invite', 'interior:kick', 'interior:players',
  'admin:refresh', 'admin:location:save', 'admin:location:delete', 'admin:location:toggle',
  'admin:location:import', 'admin:groups', 'admin:group:save', 'admin:group:delete',
  'admin:group:member', 'admin:interior:delete', 'admin:interior:toggle',
  'admin:settings:save', 'admin:players:search', 'admin:players:vehicles',
  'admin:vehicle:get', 'admin:vehicle:assign', 'admin:vehicle:update', 'admin:vehicle:delete',
  'admin:vehicle:activity',
}

for i = 1, #forwarded do
  local name = forwarded[i]
  NUI.forward(name, followUps[name])
end

---------------------------------------------------------------------------------------
-- Events & cleanup
---------------------------------------------------------------------------------------

-- Notification from the server (NZ.Bridge.notify) or another resource. Both call shapes:
-- ({ type, message, title?, duration? }) or (type, message, title?); a lone string is an
-- 'info' message.
RegisterNetEvent('nz:client:notify', function(a, b, c)
  if type(a) == 'table' then
    NUI.notify(a)
  elseif type(a) == 'string' and type(b) == 'string' then
    NUI.notify(a, b, type(c) == 'string' and c or nil)
  elseif type(a) == 'string' then
    NUI.notify('info', a)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  if hasFocus or next(openApps) then
    SetNuiFocus(false, false)
  end
end)
