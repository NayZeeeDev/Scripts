--[[
  nayzeee-garages — car lock: the key ring NUI app 'keys' (client, NZ.CarLock).
  docs/CARLOCK.md §10, docs/V2_CHANGES.md G.3 / G.5 / G.8 / G.10 / G.11.

  Opened by Config.CarLock.commands.keyRing (/keys), the keybind Config.CarLock.keys.keyRing
  (pressing it again while the ring is open closes it: KeysOpenData.closeKey), the client
  export OpenKeys(plate?) and the server ('nz:client:carlock:keyRing', e.g. a fob used far
  from its vehicle). The keys AND the vehicles behind them come from ONE server call,
  nz:carlock:tracker {} (server/carlock/tracker.lua); re-opening within CACHE_MS reuses the
  last answer and a request the server rate-limits is tried once more. Every action goes to
  the server, which answers with its own rules (ranges, owner, mode, fob, immobiliser):

    keys:refresh  {}                     -> KeysOpenData
    keys:lock     { plate }              -> { plate, locked?, refused? = 'range', message? }   nz:carlock:toggleLock
    keys:remote   { plate, action, on }  -> KeyRemoteAnswer   nz:carlock:remote (hold = engine, keep holding = windows)
    keys:locate   { plate, stop? }       -> { distance }      tracker: waypoint + following blip
    keys:alarm    { plate }              -> { alarm, seconds, cooldown, refused? = 'cooldown', message? }
    keys:track    { plate }              -> KeyTrackData      nz:carlock:tracker { plate } + street / own position
    keys:players  {}                     -> KeyRingPlayer[]   nz:carlock:nearbyPlayers
    keys:share    { plate, target }      -> { how }           nz:carlock:share (copy / hand-over / access)
    keys:holders  { plate }              -> KeyHolder[]       nz:carlock:keyHolders (owner; opaque ids)
    keys:revoke   { plate, id }          -> KeyHolder[]       nz:carlock:keyRevoke
    keys:inspect  { plate }              -> KeyInspectInfo    nz:carlock:inspect (a key item of the ring)
    keys:drop     { plate }              -> { plate }         nz:carlock:ground:drop (out of the window in a vehicle)
    keys:leave    { plate }              -> null              nz:carlock:leaveKey (give back a key someone gave you)
    keys:groundKeep / keys:groundReturn { id }                the ground key the open inspect card holds
    keys:settings {} / keys:saveSettings { settings }         nz:carlock:playerSettings / savePlayerSettings
    keys:immobiliser { plate }           -> ImmobiliserInfo
    keys:pinEnter { id, pin }            -> PinResult         nz:carlock:pin for the vehicle the open pad is about
    keys:pinSet   { plate, pin, oldPin? } -> ImmobiliserInfo  nz:carlock:setPin
    keys:pinDone  { id, pin? }           -> null              the pad closed (Lua keeps the server's verdict)

  Dialogs (KeysOpenData.dialog): over the open ring, or alone (view 'dialog') when no other
  window holds the focus. API: CarLock.openKeyInspect({ groundId } | { slot } | { keyId, plate }),
  CarLock.openGiveKeys(plate), CarLock.openTrack(plate), CarLock.openKeySettings(). The Ghost
  immobiliser keypad replaces CarLock.pinPrompt (digits), CarLock.enterPin (the driver's PIN,
  the pad shows the server's answers) and CarLock.openPinSetup (the owner sets / changes it);
  the core's ox_lib versions stay the fallback while another window holds the focus.

  While the window is open a 1 s loop pushes what this client sees itself ('update' -> live:
  distance, lock, engine of vehicles in scope) and the tracker's readout of the located
  vehicle ('update' -> tracking). Nothing runs while it is closed.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local APP = 'keys'
local LIVE_STEP = 1000           -- ms between two live updates while the window is open
local REFRESH_DEBOUNCE = 1200    -- ms: a burst of key changes refreshes once
local CACHE_MS = 2000            -- ms: re-opening the ring this soon reuses the last data
local RETRY_WAIT = 1100          -- ms: a request the server rate-limited is tried once more after this
local PAD_WATCH_MS = 300         -- ms: the driver's PIN pad closes when they leave the seat
local SETUP_WAIT_MS = 120000     -- ms: a PIN set-up waits this long for the locksmith window to close
local LEAVE_TIMEOUT = 6000       -- ms: a server without nz:carlock:leaveKey never answers
local USED_KVP = 'nz_keys_used'  -- resource KVP: { [plate] = time the player last used the key }
local USED_MAX = 80
local LEAVE_CB = 'nz:carlock:leaveKey'

local ring = {
  open = false,                  -- the key ring (or the settings) is on screen
  view = nil,                    -- 'ring' | 'settings' | 'dialog' while the app is open
  opening = false,
  byPlate = {},                  -- [plate] = KeyEntry of the last data
  mode = 'virtual',
  clock = nil,                   -- { server = os.time() of the server, game = GetGameTimer() }
  cache = nil,                   -- { at = GetGameTimer(), res } of the last build
  generation = 0,
  refreshQueued = false,
  held = nil,                    -- ground key id the open inspect card holds
}
local keybind = nil              -- the key ring keybind (its current key closes the open ring)
local pad = { seq = 0, cur = nil } -- the Ghost PIN pad on screen: cur = { id, mode, plate, netId, p, success, pin }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function serverNow()
  if not ring.clock then return nil end
  return ring.clock.server + math.floor((GetGameTimer() - ring.clock.game) / 1000)
end

local function localVehicle(netId)
  netId = tonumber(netId)
  if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
  local vehicle = NetToVeh(netId)
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
  return nil
end

local function lockedOf(vehicle)
  local bag = Entity(vehicle).state.nzLocked
  if bag ~= nil then return bag == true end
  return (tonumber(GetVehicleDoorLockStatus(vehicle)) or 0) >= 2
end

local function engineOf(vehicle)
  return GetIsVehicleEngineRunning(vehicle) == true or GetIsVehicleEngineRunning(vehicle) == 1
end

--- Plate of the vehicle the player sits in (real plate as this client knows it), or nil.
local function seatPlate()
  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if vehicle == 0 then return nil, nil end
  return CarLock.plateOf(vehicle), vehicle
end

local function vehicleTypeOf(hash)
  if not hash or hash == 0 or type(NZ.Veh.categoryOf) ~= 'function' then return 'car' end
  local ok, cat = pcall(NZ.Veh.categoryOf, hash)
  return ok and (cat == 'sea' or cat == 'air') and cat or 'car'
end

local function enrich(data)
  if type(NZ.Veh.enrichDeep) ~= 'function' then return data end
  local ok, res = pcall(NZ.Veh.enrichDeep, data)
  return ok and res or data
end

local function vehicleName(hash)
  if not hash or hash == 0 or type(NZ.Veh.label) ~= 'function' then return nil end
  local ok, label = pcall(NZ.Veh.label, hash)
  return ok and type(label) == 'string' and label ~= '' and label or nil
end

local function ranges()
  return { key = CarLock.range('key'), fob = CarLock.range('fob'), give = CarLock.range('give') }
end

--- The admin's default fob design (keys.defaultFob).
local function defaultDesign()
  local fob = CarLock.cfg().fob
  local d = type(fob) == 'table' and fob.defaultDesign or nil
  return type(d) == 'string' and d ~= '' and d:sub(1, 24) or 'classic'
end

--- The player's key ring preferences (key order, units).
local function prefs()
  local s = type(CarLock.playerSettings) == 'function' and CarLock.playerSettings() or {}
  return { keyOrder = s.keyOrder or 'recent', units = s.units or 'metric' }
end

--- The key the player bound to the key ring (ox_lib keybind), else the configured default.
local function closeKey()
  if keybind and type(keybind.getCurrentKey) == 'function' then
    local ok, key = pcall(keybind.getCurrentKey, keybind)
    if ok and type(key) == 'string' and key:match('^[%w_]+$') then return key end
  end
  local keys = CarLock.cfg().keys
  local key = type(keys) == 'table' and keys.keyRing or nil
  return type(key) == 'string' and key:match('^[%w_]+$') and key or nil
end

local function forget()
  ring.cache = nil
end

local function notify(kind, message)
  if type(message) == 'string' and message ~= '' then NZ.NUI.notify(kind, message) end
end

---------------------------------------------------------------------------------------
-- Recently used keys (key order 'recent'): this client remembers when each key was used
-- (key ring actions, driving the vehicle). Display order only: nothing is trusted from it.
---------------------------------------------------------------------------------------

local used = nil

local function usedMap()
  if used then return used end
  used = {}
  local raw = GetResourceKvpString(USED_KVP)
  if type(raw) == 'string' and raw ~= '' then
    local ok, t = pcall(json.decode, raw)
    if ok and type(t) == 'table' then
      for plate, at in pairs(t) do
        if type(plate) == 'string' and tonumber(at) then used[plate] = math.floor(tonumber(at)) end
      end
    end
  end
  return used
end

local function nowStamp()
  return tonumber(GetCloudTimeAsInt()) or 0
end

local function markUsed(plate)
  plate = Utils.plate(plate)
  if not plate then return end
  local map = usedMap()
  local now = nowStamp()
  if map[plate] and now - map[plate] < 60 then return end -- once a minute is plenty
  map[plate] = now
  local count, oldest, oldestAt = 0, nil, math.huge
  for p, at in pairs(map) do
    count = count + 1
    if at < oldestAt then oldest, oldestAt = p, at end
  end
  if count > USED_MAX and oldest then map[oldest] = nil end
  SetResourceKvp(USED_KVP, json.encode(map))
  local entry = ring.byPlate[plate]
  if entry then entry.usedAt = now end
end

-- driving a vehicle counts as using its key
AddEventHandler('nz:client:carlock:driver', function(data)
  if type(data) == 'table' and data.allowed == true and type(data.plate) == 'string' then markUsed(data.plate) end
end)

---------------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------------

--- One KeyEntry from the core key + the server status of its vehicle.
local function entryOf(key, st, mode)
  local plate = key.plate
  local kind = key.kind
  if kind == 'item' and key.keyKind == 'fob' then kind = 'fob' end
  local isOwner = st.isOwner == true
  local group
  if key.kind == 'temp' then
    group = 'temp'
  elseif isOwner then
    group = 'owned'
  elseif key.kind == 'item' then
    group = 'items'
  else
    group = 'shared'   -- a garage share, a fleet vehicle or a virtual key someone gave you
  end
  local hash = tonumber(st.hash)
  local netId = tonumber(st.netId) or tonumber(key.netId)
  local immo = st.immobiliser
  local entry = {
    plate = plate,
    model = type(st.model) == 'string' and st.model or (type(key.model) == 'string' and key.model or ''),
    hash = hash or 0,
    vehicleType = vehicleTypeOf(hash),
    nickname = st.nickname or (key.kind == 'owner' and type(key.label) == 'string' and key.label ~= '' and key.label or nil),
    kind = kind,
    group = group,
    keyType = st.keyType == 'fob' and 'fob' or 'key',
    profile = st.profile or 'standard',
    profileLabel = st.profileLabel or L('Standard'),
    remote = st.remote == true,
    expiresIn = nil,
    -- how the key was obtained: a temporary key's reason, or the crime origin of a key item
    -- (back-alley copy, spare key found in a search) the server reports
    reason = (key.kind == 'temp' and type(key.reason) == 'string' and key.reason)
      or (type(st.origin) == 'string' and st.origin ~= '' and st.origin:sub(1, 16)) or nil,
    isOwner = isOwner,
    spawned = st.spawned == true or netId ~= nil,
    netId = netId,
    locked = st.locked,
    distance = st.distance,
    tracker = st.tracker == true,
    trackable = st.trackable == true,
    towing = st.towing == true,
    alarm = st.alarm == true,
    -- a crime's key (temporary key or key item) / another script's has no tracker access (server rule)
    trackerAccess = (st.trackerAccess == nil and key.kind ~= 'temp') or st.trackerAccess == true,
    canShare = (mode == 'virtual' and isOwner and key.kind ~= 'temp') or (mode == 'physical' and key.kind == 'item'),
    holders = nil,
    design = type(key.design) == 'string' and key.design ~= '' and key.design:sub(1, 24) or defaultDesign(),
    immobiliser = (immo == 'standard' or immo == 'ghost') and immo or 'none',
    engine = nil,
    usedAt = usedMap()[plate],
    slot = key.kind == 'item' and tonumber(key.slot) or nil,
    keyId = key.kind == 'item' and type(key.keyId) == 'string' and key.keyId or nil,
  }
  local now = serverNow()
  if key.kind == 'temp' and tonumber(key.expires) and now then
    entry.expiresIn = math.max(math.floor(tonumber(key.expires) - now), 0)
  end
  -- a vehicle that is not out: the server may not know its class (no shared vehicle list, no
  -- driver reported it yet); this client knows every model's class, so the profile shown
  -- (tracker, fob) is its own. Vehicles that are out keep the server's view (what it enforces).
  if not entry.spawned and entry.hash ~= 0 then
    local okClass, class = pcall(GetVehicleClassFromName, entry.hash)
    if okClass and type(class) == 'number' then
      local name, profile = CarLock.profileOf(entry.hash, class)
      entry.profile = name
      entry.profileLabel = L(type(profile.label) == 'string' and profile.label or 'Standard')
      entry.remote = profile.remote == true
      entry.keyType = CarLock.keyKindOf(profile)
      entry.tracker = profile.tracker == true
    end
  end
  -- what this client sees itself is the freshest
  local vehicle = netId and localVehicle(netId) or nil
  if vehicle then
    entry.spawned = true
    entry.locked = lockedOf(vehicle)
    entry.engine = engineOf(vehicle)
    entry.distance = math.floor(#(GetEntityCoords(vehicle) - GetEntityCoords(PlayerPedId())) + 0.5)
    if entry.hash == 0 then
      entry.hash = GetEntityModel(vehicle)
      entry.vehicleType = vehicleTypeOf(entry.hash)
    end
  end
  return entry
end

--- The server's key ring answer (yields): nz:carlock:tracker {} = keys + vehicles in one call.
--- The server asks to wait when it comes too soon (closing and re-opening, a key change right
--- after an open): tried once more after RETRY_WAIT instead of showing an error.
local function fetchList()
  local res = CarLock.trackerStatus(nil)
  if not res.ok and res.error == L('Please wait a moment') then
    Wait(RETRY_WAIT)
    res = CarLock.trackerStatus(nil)
  end
  return res
end

--- KeysOpenData from the server (yields). Returns a result table.
local function build(focus)
  local res = fetchList()
  if not res.ok then return res end
  local data = type(res.data) == 'table' and res.data or {}
  local mode = data.mode == 'physical' and 'physical' or 'virtual'
  if tonumber(data.now) then ring.clock = { server = tonumber(data.now), game = GetGameTimer() } end
  local statuses = {}
  for _, st in ipairs(type(data.vehicles) == 'table' and data.vehicles or {}) do
    local plate = type(st) == 'table' and Utils.plate(st.plate) or nil
    if plate then statuses[plate] = st end
  end

  local list, byPlate = {}, {}
  for _, key in ipairs(type(data.keys) == 'table' and data.keys or {}) do
    local plate = type(key) == 'table' and Utils.plate(key.plate) or nil
    if plate and not byPlate[plate] then
      key.plate = plate
      local entry = entryOf(key, statuses[plate] or {}, mode)
      list[#list + 1] = entry
      byPlate[plate] = entry
    end
  end
  enrich(list)
  ring.byPlate = byPlate
  ring.mode = mode
  local seat = seatPlate()
  local out = Utils.ok({
    mode = mode,
    keyMode = CarLock.keyMode(),
    keys = list,
    nearbyPlayers = {},
    ranges = ranges(),
    tracker = data.tracker == true,
    focus = Utils.plate(focus),
    seatPlate = seat,
    closeKey = closeKey(),
    prefs = prefs(),
    tracking = nil,
    live = nil,
  })
  ring.cache = { at = GetGameTimer(), res = out }
  return out
end

--- Data of a dialog shown on its own (no ring behind it).
local function aloneData(dialog, base)
  local data = type(base) == 'table' and base or {
    mode = ring.mode, keyMode = CarLock.keyMode(), keys = {}, nearbyPlayers = {}, ranges = ranges(),
    tracker = true, closeKey = closeKey(), prefs = prefs(),
  }
  data.view = 'dialog'
  data.dialog = dialog
  data.focus = nil
  return data
end

---------------------------------------------------------------------------------------
-- Live updates while open
---------------------------------------------------------------------------------------

local function liveLoop(generation)
  CreateThread(function()
    while ring.open and ring.generation == generation do
      Wait(LIVE_STEP)
      if not ring.open or ring.generation ~= generation then return end
      if NZ.Points.incapacitated() then
        NZ.NUI.close(APP)
        return
      end
      local live, any = {}, false
      local ped = GetEntityCoords(PlayerPedId())
      for plate, entry in pairs(ring.byPlate) do
        local vehicle = entry.netId and localVehicle(entry.netId) or nil
        if vehicle then
          live[plate] = { distance = math.floor(#(GetEntityCoords(vehicle) - ped) + 0.5), locked = lockedOf(vehicle),
            alarm = type(Entity(vehicle).state.nzAlarm) == 'table', engine = engineOf(vehicle) }
          any = true
        end
      end
      local seat = seatPlate()
      NZ.NUI.send('update', { app = APP, data = { live = any and live or {}, seatPlate = seat or false } })
    end
  end)
end

local function refreshNow()
  if not ring.open then return end
  local res = build(nil)
  if res.ok and ring.open then
    res.data.focus = nil
    NZ.NUI.send('update', { app = APP, data = enrich(res.data) })
  end
end

local function queueRefresh()
  if not ring.open or ring.refreshQueued then return end
  ring.refreshQueued = true
  SetTimeout(REFRESH_DEBOUNCE, function()
    ring.refreshQueued = false
    refreshNow()
  end)
end

-- keys handed over, revoked, received, a change of locks...
AddEventHandler('nz:client:carlock:keysChanged', function()
  forget()
  queueRefresh()
end)

-- the tracker follows a located vehicle: forward its readout
AddEventHandler('nz:client:carlock:tracking', function(data)
  if not ring.open or type(data) ~= 'table' then return end
  NZ.NUI.send('update', { app = APP, data = { tracking = {
    plate = data.plate,
    distance = tonumber(data.distance),
    live = data.live == true,
    lost = data.lost == true,
    stopped = data.stopped == true,
    towing = data.towing == true,
  } } })
end)

---------------------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------------------

--- Open the key ring (yields), on `focus` (plate) when given; view 'settings' opens the
--- settings tab. While it is open the NUI closes it on the key ring keybind (closeKey) and Esc.
---@param focus string|nil
---@param view 'ring'|'settings'|nil
---@return boolean opened
function CarLock.openKeyRing(focus, view)
  if not CarLock.enabled() or ring.opening then return false end
  view = view == 'settings' and 'settings' or 'ring'
  if NZ.NUI.isOpen(APP) then
    -- a dialog on its own (PIN pad, a key from the ground) finishes first
    if ring.view == 'dialog' then return false end
    local patch = {}
    if focus then patch.focus = Utils.plate(focus) end
    if view == 'settings' then patch.view = 'settings' end
    if next(patch) then NZ.NUI.send('update', { app = APP, data = patch }) end
    return true
  end
  -- another window (garage, admin...) holds the focus: never stack the key ring on it
  if NZ.NUI.hasFocus() or IsPauseMenuActive() or NZ.Points.incapacitated() then return false end
  ring.opening = true
  local res
  local cached = ring.cache
  if cached and GetGameTimer() - cached.at < CACHE_MS and cached.res.ok then
    -- closed and opened again right away: the answer of a moment ago
    res = cached.res
    res.data.focus = Utils.plate(focus)
    res.data.seatPlate = seatPlate()
    res.data.prefs = prefs()
  else
    res = build(focus)
  end
  ring.opening = false
  if not res.ok then
    notify('error', res.error)
    return false
  end
  if NZ.NUI.hasFocus() or NZ.NUI.isOpen(APP) then return false end
  res.data.view = view
  res.data.dialog = false
  ring.open = true
  ring.view = view
  ring.generation = ring.generation + 1
  NZ.NUI.open(APP, enrich(res.data))
  liveLoop(ring.generation)
  return true
end

--- Open the key ring on its settings tab (yields).
function CarLock.openKeySettings()
  return CarLock.openKeyRing(nil, 'settings')
end

--- Show a dialog: over the open ring, else alone when no other window holds the focus.
--- `base` = the KeysOpenData to show behind a lone dialog (give keys needs the keys).
---@return boolean shown
local function showDialog(dialog, base)
  if NZ.NUI.isOpen(APP) then
    if ring.view == 'dialog' then return false end -- one lone dialog at a time
    NZ.NUI.send('update', { app = APP, data = { dialog = dialog } })
    return true
  end
  if NZ.NUI.hasFocus() or IsPauseMenuActive() then return false end
  ring.view = 'dialog'
  ring.open = false
  NZ.NUI.open(APP, enrich(aloneData(dialog, base)))
  return true
end

--- Take a dialog away (the ring stays; a lone dialog closes the app).
local function hideDialog()
  if not NZ.NUI.isOpen(APP) then return end
  if ring.view == 'dialog' then
    NZ.NUI.close(APP)
  else
    NZ.NUI.send('update', { app = APP, data = { dialog = false } })
  end
end

--- Resolve the pad on screen (idempotent).
local function padResolve(id, result)
  local cur = pad.cur
  if not cur or (id ~= nil and cur.id ~= id) then return end
  pad.cur = nil
  cur.p:resolve(result or {})
end

NZ.NUI.onClose(APP, function()
  ring.open = false
  ring.view = nil
  ring.generation = ring.generation + 1
  -- a waiting PIN prompt ends (cancelled unless the server already accepted it)
  local cur = pad.cur
  if cur then padResolve(cur.id, { success = cur.success == true, pin = cur.pin }) end
  -- a ground key held for the inspect card goes back to everyone
  local held = ring.held
  ring.held = nil
  if held then CreateThread(function() CarLock.returnGroundKey(held) end) end
end)

local function openAsync(focus)
  CreateThread(function() CarLock.openKeyRing(focus) end)
end

RegisterNetEvent('nz:client:carlock:keyRing', function(data)
  openAsync(type(data) == 'table' and data.plate or nil)
end)

if CarLock.enabled() then
  local cfg = CarLock.cfg()
  local keys = type(cfg.keys) == 'table' and cfg.keys or {}
  local commands = type(cfg.commands) == 'table' and cfg.commands or {}
  if type(commands.keyRing) == 'string' and commands.keyRing ~= '' then
    RegisterCommand(commands.keyRing, function() openAsync(nil) end, false)
  end
  if type(keys.keyRing) == 'string' and keys.keyRing ~= '' then
    keybind = lib.addKeybind({
      name = 'nz_carlock_keyring',
      description = L('Open the key ring'),
      defaultKey = keys.keyRing,
      onPressed = function()
        if IsNuiFocused() then return end
        openAsync(nil)
      end,
    })
  end
end

exports('OpenKeys', function(plate)
  openAsync(type(plate) == 'string' and plate or nil)
  return true
end)

exports('OpenKeySettings', function()
  CreateThread(function() CarLock.openKeySettings() end)
  return true
end)

---------------------------------------------------------------------------------------
-- Dialogs: inspect a key, give keys, track a vehicle
---------------------------------------------------------------------------------------

--- KeyInspectInfo from a GroundKeyInfo / CarriedKeyInfo answer.
local function inspectInfo(data, source)
  local model = type(data.model) == 'string' and data.model ~= '' and data.model or nil
  local fob = data.keyKind == 'fob'
  local info = {
    plate = Utils.plate(data.plate) or '',
    keyKind = fob and 'fob' or 'key',
    keyLabel = type(data.label) == 'string' and data.label or CarLock.keyLabel(fob and 'fob' or 'key', data.plate),
    model = model,
    hash = model and GetHashKey(model) or 0,
    design = fob and (type(data.design) == 'string' and data.design ~= '' and data.design:sub(1, 24) or defaultDesign()) or 'key',
    kind = data.kind == 'temp' and 'temp' or 'item',
  }
  if source == 'carried' then
    info.valid = data.valid == true
    info.reason = type(data.reason) == 'string' and data.reason or nil
    info.origin = type(data.origin) == 'string' and data.origin:sub(1, 16) or nil
  elseif tonumber(data.droppedAt) then
    info.droppedAgo = math.max(nowStamp() - math.floor(tonumber(data.droppedAt)), 0)
  end
  return enrich(info)
end

--- Look at a key up close (yields): opts.groundId = a key on the ground (Keep / Return to
--- ground; the server holds it for you meanwhile), else a key you carry ({ slot } | { keyId, plate }).
---@param opts table
---@return boolean shown
function CarLock.openKeyInspect(opts)
  if not CarLock.enabled() or type(opts) ~= 'table' then return false end
  if type(opts.groundId) == 'string' then
    if ring.held then return false end
    local ok, data = CarLock.inspectGroundKey(opts.groundId)
    if not ok or type(data) ~= 'table' then
      notify('error', data)
      return false
    end
    local id = opts.groundId
    ring.held = id
    if not showDialog({ kind = 'inspect', source = 'ground', id = id, info = inspectInfo(data, 'ground') }) then
      ring.held = nil
      CarLock.returnGroundKey(id)
      return false
    end
    return true
  end
  local ok, data = CarLock.inspectKey({ slot = tonumber(opts.slot), keyId = opts.keyId, plate = opts.plate })
  if not ok or type(data) ~= 'table' then
    notify('error', data)
    return false
  end
  return showDialog({ kind = 'inspect', source = 'carried', info = inspectInfo(data, 'carried') })
end

--- The give keys picker of one key (yields): nearby players, Refresh, then the share.
---@param plate string
---@return boolean shown
function CarLock.openGiveKeys(plate)
  plate = Utils.plate(plate)
  if not CarLock.enabled() or not plate then return false end
  if NZ.NUI.isOpen(APP) and ring.view ~= 'dialog' then
    if not ring.byPlate[plate] then return false end
    return showDialog({ kind = 'give', plate = plate })
  end
  if NZ.NUI.hasFocus() then return false end
  local res = build(nil)
  if not res.ok then
    notify('error', res.error)
    return false
  end
  if not ring.byPlate[plate] then
    notify('error', L('You do not have the keys of this vehicle'))
    return false
  end
  return showDialog({ kind = 'give', plate = plate }, res.data)
end

--- The track vehicle modal of a plate (live map, status, Set waypoint).
---@param plate string
---@return boolean shown
function CarLock.openTrack(plate)
  plate = Utils.plate(plate)
  if not CarLock.enabled() or not plate then return false end
  return showDialog({ kind = 'track', plate = plate })
end

---------------------------------------------------------------------------------------
-- Ghost immobiliser keypad (docs/CARLOCK.md §17): replaces the core's ox_lib prompts
---------------------------------------------------------------------------------------

local corePinPrompt = CarLock.pinPrompt
local coreEnterPin = CarLock.enterPin

--- Can the pad be shown now (over the ring, or alone)?
local function padUsable()
  if IsPauseMenuActive() then return false end
  if NZ.NUI.isOpen(APP) then return ring.view ~= 'dialog' end
  return not NZ.NUI.hasFocus()
end

--- Show the keypad and wait until it closes (yields). nil = it could not be shown.
---@return table|nil { success?, pin? }
local function openPad(spec)
  if pad.cur then padResolve(nil, {}) end
  pad.seq = pad.seq + 1
  local cur = { id = pad.seq, mode = spec.mode, plate = spec.plate, netId = spec.netId, p = promise.new(), success = false }
  pad.cur = cur
  local dialog = { kind = 'pin', pad = {
    id = cur.id, mode = spec.mode, plate = spec.plate or '', vehicle = spec.label,
    attemptsLeft = tonumber(spec.attemptsLeft), cooldown = tonumber(spec.cooldown), pinSet = spec.pinSet == true, length = 4,
  } }
  if not showDialog(dialog) then
    pad.cur = nil
    return nil
  end
  if spec.mode == 'enter' and spec.entity then
    -- the driver gets out (or the car is gone): the pad closes
    CreateThread(function()
      while pad.cur == cur do
        Wait(PAD_WATCH_MS)
        if pad.cur ~= cur then return end
        local ped = PlayerPedId()
        if not DoesEntityExist(spec.entity) or GetVehiclePedIsIn(ped, false) ~= spec.entity
          or GetPedInVehicleSeat(spec.entity, -1) ~= ped then
          padResolve(cur.id, { success = cur.success == true })
          hideDialog()
          return
        end
      end
    end)
  end
  return Citizen.Await(cur.p)
end

--- Ask the player for a Ghost PIN (yields): the digits or nil.
---@param info table { plate, cooldown, attemptsLeft? }
---@return string|nil
function CarLock.pinPrompt(info)
  info = type(info) == 'table' and info or {}
  if not padUsable() then return corePinPrompt(info) end
  local res = openPad({ mode = 'collect', plate = Utils.plate(info.plate), attemptsLeft = info.attemptsLeft, cooldown = info.cooldown })
  if res == nil then return corePinPrompt(info) end
  local pin = type(res.pin) == 'string' and res.pin or ''
  return pin:match('^%d%d%d%d$') and pin or nil
end

--- Enter the Ghost PIN of the vehicle we drive (yields): the pad sends it to the server
--- itself (keys:pinEnter), shows wrong PINs, attempts and the cooldown, and closes once the
--- server accepted it. Returns true when it was accepted.
---@param vehicle number
---@param info table|nil the server's pin info
---@return boolean
function CarLock.enterPin(vehicle, info)
  info = type(info) == 'table' and info or {}
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
  if not padUsable() or not NetworkGetEntityIsNetworked(vehicle) then return coreEnterPin(vehicle, info) end
  local res = openPad({
    mode = 'enter', plate = Utils.plate(info.plate) or CarLock.plateOf(vehicle), entity = vehicle,
    netId = NetworkGetNetworkIdFromEntity(vehicle), label = vehicleName(GetEntityModel(vehicle)),
    cooldown = info.cooldown, attemptsLeft = info.attemptsLeft,
  })
  if res == nil then return coreEnterPin(vehicle, info) end
  if res.success then
    notify('success', L('PIN accepted')) -- a security step: always confirmed
    if type(CarLock.refreshIgnition) == 'function' then CarLock.refreshIgnition() end
    return true
  end
  return false
end

--- The owner sets / changes the Ghost PIN of `plate` (after a Ghost install at a locksmith,
--- or from the key ring). Waits for the locksmith window to close first.
---@param plate string
function CarLock.openPinSetup(plate)
  plate = Utils.plate(plate)
  if not plate then return end
  CreateThread(function()
    local deadline = GetGameTimer() + SETUP_WAIT_MS
    while not padUsable() and GetGameTimer() < deadline do Wait(500) end
    if not padUsable() then
      notify('info', L('Set the PIN of {plate} from your key ring', { plate = plate }))
      return
    end
    local res = NZ.NUI.await('nz:carlock:immobiliser', { plate = plate })
    if not res.ok or type(res.data) ~= 'table' then
      notify('error', res.error)
      return
    end
    if res.data.level ~= 'ghost' then return end
    local entry = ring.byPlate[plate]
    local out = openPad({ mode = 'set', plate = plate, pinSet = res.data.pinSet == true,
      label = entry and (entry.nickname or entry.label) or nil })
    if out == nil then
      notify('info', L('Set the PIN of {plate} from your key ring', { plate = plate }))
    elseif out.success then
      notify('success', L('PIN saved'))
    end
  end)
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

local function entryFor(data)
  local plate = Utils.plate(type(data) == 'table' and data.plate or nil)
  if not plate or #plate > 16 then return nil, nil end
  return ring.byPlate[plate], plate
end

local function isPin(v)
  return type(v) == 'string' and v:match('^%d%d%d%d$') ~= nil
end

NZ.NUI.register('keys:refresh', function()
  forget()
  local res = build(nil)
  if res.ok then res.data = enrich(res.data) end
  return res
end)

NZ.NUI.register('keys:lock', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  if entry.towing then return Utils.fail(L('This vehicle is being towed')) end
  if not entry.netId then return Utils.fail(L('The vehicle is not out')) end
  -- the server locks the vehicle you sit in: never surprise the player with another one
  local seat, seatVehicle = seatPlate()
  if seatVehicle and seat ~= plate then
    return Utils.fail(L('Get out of your vehicle to lock another one'))
  end
  forget()
  local res = NZ.NUI.await('nz:carlock:toggleLock', { netId = entry.netId })
  if not res.ok then
    -- out of range is the server's answer, not a failure: the key ring shows it as such
    -- (the same Lua locale on both sides: no translated text is parsed in the NUI)
    if res.error == L('The vehicle is too far away') then
      return Utils.ok({ plate = plate, refused = 'range', message = res.error })
    end
    return res
  end
  local out = type(res.data) == 'table' and res.data or {}
  local donePlate = Utils.plate(out.plate) or plate
  local done = ring.byPlate[donePlate]
  if done then done.locked = out.locked == true end
  markUsed(donePlate)
  CarLock.playFob()
  return Utils.ok({ plate = donePlate, locked = out.locked == true })
end)

NZ.NUI.register('keys:remote', function(data)
  local entry, plate = entryFor(data)
  local action = data.action
  if not plate or (action ~= 'engine' and action ~= 'windows') or type(data.on) ~= 'boolean' then
    return Utils.fail(L('Invalid request'))
  end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  if entry.towing then return Utils.fail(L('This vehicle is being towed')) end
  local payload = { action = action, on = data.on }
  if entry.netId then payload.netId = entry.netId else payload.plate = plate end
  forget()
  local res = NZ.NUI.await('nz:carlock:remote', payload)
  if not res.ok then
    if res.error == L('The vehicle is too far away') then
      return Utils.ok({ action = action, on = data.on, plate = plate, refused = 'range', message = res.error })
    end
    return res
  end
  local out = type(res.data) == 'table' and res.data or {}
  local on = out.on ~= false
  if action == 'engine' then entry.engine = on end
  markUsed(plate)
  CarLock.playFob()
  return Utils.ok({ action = action, on = on, plate = plate })
end)

NZ.NUI.register('keys:locate', function(data)
  local _, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if data.stop == true then
    if CarLock.locating() == plate then CarLock.stopLocate() end
    return Utils.ok({ distance = nil })
  end
  -- the server checks the key and the tracker (also from the garage, where the ring is closed)
  local res = CarLock.locate(plate)
  if not res.ok then return res end
  return Utils.ok({ distance = res.data and res.data.distance or nil })
end)

NZ.NUI.register('keys:alarm', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  local on = nil
  if data.on == true or data.on == false then on = data.on end
  forget()
  local res = CarLock.remoteAlarm(plate, on)
  if not res.ok then return res end
  local out = type(res.data) == 'table' and res.data or {}
  entry.alarm = out.alarm == true
  return Utils.ok({
    alarm = out.alarm == true,
    seconds = tonumber(out.seconds),
    cooldown = tonumber(out.cooldown) or 0,
    -- still cooling down: the seconds left come as a number, the text for the player as is
    refused = out.refused == 'cooldown' and 'cooldown' or nil,
    message = out.refused == 'cooldown' and type(out.message) == 'string' and out.message or nil,
  })
end)

--- Street and area of a position (this client's map data).
local function placeOf(x, y, z)
  local okStreet, s1 = pcall(GetStreetNameAtCoord, x + 0.0, y + 0.0, z + 0.0)
  local street = okStreet and s1 and s1 ~= 0 and GetStreetNameFromHashKey(s1) or nil
  local okZone, zone = pcall(GetNameOfZone, x + 0.0, y + 0.0, z + 0.0)
  local area = okZone and type(zone) == 'string' and zone ~= '' and GetLabelText(zone) or nil
  if area == 'NULL' or area == '' then area = nil end
  return type(street) == 'string' and street ~= '' and street or nil, area
end

NZ.NUI.register('keys:track', function(data)
  local plate = Utils.plate(type(data) == 'table' and data.plate or nil)
  if not plate or #plate > 16 then return Utils.fail(L('Invalid plate')) end
  -- the server checks the key and reports a position only for trackable vehicles
  local res = CarLock.trackerStatus(plate)
  if not res.ok then return res end
  local d = type(res.data) == 'table' and res.data or {}
  local st = type(d.vehicles) == 'table' and type(d.vehicles[1]) == 'table' and d.vehicles[1] or nil
  if not st then return Utils.fail(L('Something went wrong')) end
  local ped = GetEntityCoords(PlayerPedId())
  local out = {
    plate = plate,
    model = type(st.model) == 'string' and st.model or '',
    hash = tonumber(st.hash) or 0,
    nickname = st.nickname,
    profileLabel = st.profileLabel or L('Standard'),
    tracker = st.tracker == true,
    trackerAccess = st.trackerAccess ~= false,
    trackable = st.trackable == true and d.tracker ~= false,
    spawned = st.spawned == true,
    towing = st.towing == true,
    locked = st.locked,
    engine = nil,
    alarm = st.alarm == true,
    immobiliser = (st.immobiliser == 'standard' or st.immobiliser == 'ghost') and st.immobiliser or 'none',
    me = { x = Utils.round(ped.x, 1), y = Utils.round(ped.y, 1) },
    live = false,
  }
  local vehicle = tonumber(st.netId) and localVehicle(st.netId) or nil
  if vehicle then
    out.locked = lockedOf(vehicle)
    out.engine = engineOf(vehicle)
    if out.hash == 0 then out.hash = GetEntityModel(vehicle) end
  end
  if out.trackable and (vehicle or type(st.coords) == 'table') then
    local pos, heading
    if vehicle then
      pos, heading = GetEntityCoords(vehicle), GetEntityHeading(vehicle)
      out.live = true
      out.distance = math.floor(#(pos - ped) + 0.5)
    else
      pos = vector3(tonumber(st.coords.x) or 0.0, tonumber(st.coords.y) or 0.0, tonumber(st.coords.z) or 0.0)
      out.distance = tonumber(st.distance)
    end
    out.coords = { x = Utils.round(pos.x, 1), y = Utils.round(pos.y, 1), z = Utils.round(pos.z, 1) }
    out.heading = heading and Utils.round(heading, 0) or nil
    out.street, out.area = placeOf(pos.x, pos.y, pos.z)
  elseif d.tracker == false then
    out.reason = 'disabled'
  elseif not out.tracker then
    out.reason = 'notracker'
  elseif not out.trackerAccess then
    out.reason = 'noaccess'
  elseif out.towing then
    out.reason = 'towing'
  else
    out.reason = 'notout'
  end
  return Utils.ok(enrich(out))
end)

NZ.NUI.register('keys:players', function()
  local res = NZ.NUI.await('nz:carlock:nearbyPlayers', {})
  if not res.ok then return res end
  return Utils.ok(type(res.data) == 'table' and res.data or {})
end)

NZ.NUI.register('keys:share', function(data)
  local entry, plate = entryFor(data)
  local target = tonumber(data.target)
  if not plate or not target or target ~= math.floor(target) or target <= 0 then return Utils.fail(L('Invalid request')) end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  if not entry.canShare then
    return Utils.fail(entry.kind == 'temp' and L('You cannot lend a temporary key') or L('Only the owner can share this key'))
  end
  forget()
  local res = NZ.NUI.await('nz:carlock:share', { plate = plate, target = math.tointeger(target) })
  if not res.ok then return res end
  local how = type(res.data) == 'table' and res.data.how or nil
  return Utils.ok({ how = type(how) == 'string' and how or nil })
end)

--- KeyHolder list for the NUI (server times turned into seconds left / ago on this clock).
--- id: the server's opaque holder id (identifiers never reach the NUI).
local function holdersOf(raw)
  local now = serverNow()
  local list = {}
  for _, h in ipairs(type(raw) == 'table' and raw or {}) do
    if type(h) == 'table' and type(h.id) == 'string' and h.id ~= '' then
      local expires, at = tonumber(h.expires), tonumber(h.at)
      local temp = h.kind == 'temp'
      list[#list + 1] = {
        id = h.id,
        name = type(h.name) == 'string' and h.name or L('Unknown'),
        kind = temp and 'temp' or 'virtual',
        reason = temp and type(h.reason) == 'string' and h.reason or nil,
        masked = h.masked == true,
        agoSeconds = (at and now) and math.max(now - at, 0) or nil,
        expiresIn = (expires and now) and math.max(expires - now, 0) or nil,
      }
    end
  end
  return list
end

local function holderResult(res, plate)
  if not res.ok then return res end
  local list = holdersOf(res.data)
  local entry = ring.byPlate[plate]
  if entry then entry.holders = #list end
  return Utils.ok(list)
end

NZ.NUI.register('keys:holders', function(data)
  local _, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  return holderResult(NZ.NUI.await('nz:carlock:keyHolders', { plate = plate }), plate)
end)

NZ.NUI.register('keys:revoke', function(data)
  local _, plate = entryFor(data)
  local id = type(data) == 'table' and type(data.id) == 'string' and #data.id <= 32 and data.id ~= '' and data.id or nil
  if not plate or not id then return Utils.fail(L('Invalid request')) end
  forget()
  -- the server answers with the new holder list
  return holderResult(NZ.NUI.await('nz:carlock:keyRevoke', { plate = plate, id = id }), plate)
end)

--- { slot, keyId, plate } of a key item of the ring, or nil.
local function itemRef(entry, plate)
  if not entry or (entry.kind ~= 'item' and entry.kind ~= 'fob') then return nil end
  if not entry.slot and not entry.keyId then return nil end
  return { slot = entry.slot, keyId = entry.keyId, plate = plate }
end

NZ.NUI.register('keys:inspect', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local ref = itemRef(entry, plate)
  if not ref then return Utils.fail(L('This key is not an item')) end
  local ok, out = CarLock.inspectKey(ref)
  if not ok or type(out) ~= 'table' then return Utils.fail(out) end
  return Utils.ok(inspectInfo(out, 'carried'))
end)

NZ.NUI.register('keys:drop', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local ref = itemRef(entry, plate)
  if not ref then return Utils.fail(L('This key is not an item')) end
  local ped = PlayerPedId()
  local inVehicle = IsPedInAnyVehicle(ped, false)
  -- in a vehicle the key goes out of the window (server: toss), on foot it lands at your feet
  if inVehicle then ref.toss = true end
  local ground = CarLock.cfg().ground
  if not inVehicle and not (type(ground) == 'table' and ground.animateDrops == false) then
    if pcall(lib.requestAnimDict, 'pickup_object', 1000) then
      TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 900, 0, 0, false, false, false)
      SetTimeout(1100, function() RemoveAnimDict('pickup_object') end)
      Wait(600)
    end
  end
  forget()
  local res = NZ.NUI.await('nz:carlock:ground:drop', ref)
  if not res.ok then return res end
  queueRefresh()
  return Utils.ok({ plate = plate })
end)

--- A server callback that may not exist yet (yields): fails after `ms` instead of hanging.
local function awaitSoft(name, payload, ms)
  local p = promise.new()
  local settled = false
  lib.callback(name, false, function(res)
    if settled then return end
    settled = true
    p:resolve(res)
  end, payload)
  SetTimeout(ms, function()
    if settled then return end
    settled = true
    p:resolve(false)
  end)
  local res = Citizen.Await(p)
  if res == false then return Utils.fail(L('The server did not respond, try again')) end
  if type(res) ~= 'table' or type(res.ok) ~= 'boolean' then return Utils.fail(L('The server did not respond, try again')) end
  return res
end

NZ.NUI.register('keys:leave', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not entry or entry.isOwner or (entry.kind ~= 'virtual' and entry.kind ~= 'temp') then
    return Utils.fail(L('You cannot give this key back'))
  end
  forget()
  -- the server removes your own virtual / temporary key of the plate (never someone else's)
  local res = awaitSoft(LEAVE_CB, { plate = plate }, LEAVE_TIMEOUT)
  if not res.ok then return res end
  queueRefresh()
  return Utils.ok(nil)
end)

NZ.NUI.register('keys:groundKeep', function(data)
  local id = type(data) == 'table' and type(data.id) == 'string' and data.id or nil
  if not id or id ~= ring.held then return Utils.fail(L('Invalid request')) end
  ring.held = nil
  -- the card goes first, then the pick-up animation plays (the server checks range and pockets)
  NZ.NUI.close(APP)
  local ok, out = CarLock.keepGroundKey(id)
  if not ok then return Utils.fail(out) end
  return Utils.ok({ plate = type(out) == 'table' and out.plate or nil })
end)

NZ.NUI.register('keys:groundReturn', function(data)
  local id = type(data) == 'table' and type(data.id) == 'string' and data.id or nil
  if not id or id ~= ring.held then return Utils.ok(nil) end
  ring.held = nil
  CarLock.returnGroundKey(id)
  return Utils.ok(nil)
end)

NZ.NUI.register('keys:settings', function()
  local data = CarLock.loadPlayerSettings()
  if type(data) ~= 'table' then return Utils.fail(L('The server did not respond, try again')) end
  return Utils.ok(data)
end)

NZ.NUI.register('keys:saveSettings', function(data)
  local partial = type(data) == 'table' and type(data.settings) == 'table' and data.settings or nil
  if not partial then return Utils.fail(L('Invalid request')) end
  -- the server merges the valid fields only (normalizePlayerSettings)
  local ok, out = CarLock.savePlayerSettings(partial)
  if not ok then return Utils.fail(out) end
  forget()
  return Utils.ok(out)
end)

NZ.NUI.register('keys:immobiliser', function(data)
  local plate = Utils.plate(type(data) == 'table' and data.plate or nil)
  if not plate then return Utils.fail(L('Invalid plate')) end
  return NZ.NUI.await('nz:carlock:immobiliser', { plate = plate })
end)

NZ.NUI.register('keys:pinEnter', function(data)
  local cur = pad.cur
  if not cur or cur.mode ~= 'enter' or tonumber(data.id) ~= cur.id or not cur.netId then
    return Utils.fail(L('Invalid request'))
  end
  if not isPin(data.pin) then return Utils.fail(L('The PIN must be four digits')) end
  local res = NZ.NUI.await('nz:carlock:pin', { netId = cur.netId, pin = data.pin })
  if not res.ok then return res end
  local out = type(res.data) == 'table' and res.data or {}
  -- the server's verdict is what counts (never the pad's)
  if out.success == true and pad.cur == cur then cur.success = true end
  return Utils.ok({
    success = out.success == true,
    error = type(out.error) == 'string' and out.error or nil,
    attemptsLeft = tonumber(out.attemptsLeft),
    cooldown = tonumber(out.cooldown),
    alarm = out.alarm == true,
  })
end)

NZ.NUI.register('keys:pinSet', function(data)
  local plate = Utils.plate(type(data) == 'table' and data.plate or nil)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not isPin(data.pin) then return Utils.fail(L('The PIN must be four digits')) end
  local oldPin = isPin(data.oldPin) and data.oldPin or nil
  local res = NZ.NUI.await('nz:carlock:setPin', { plate = plate, pin = data.pin, oldPin = oldPin })
  local cur = pad.cur
  if res.ok and cur and cur.mode == 'set' and cur.plate == plate then cur.success = true end
  return res
end)

NZ.NUI.register('keys:pinDone', function(data)
  local cur = pad.cur
  if not cur or tonumber(data.id) ~= cur.id then return Utils.ok(nil) end
  -- collect: the digits are the answer; enter / set: what the server said
  local pin = cur.mode == 'collect' and isPin(data.pin) and data.pin or nil
  padResolve(cur.id, { success = cur.success == true or pin ~= nil, pin = pin })
  return Utils.ok(nil)
end)
