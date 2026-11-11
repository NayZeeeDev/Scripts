--[[
  nayzeee-garages — car lock: no-key driver flow, lockpicking doors, NPC drivers (client,
  NZ.CarLock). docs/CARLOCK.md §8. The server decides every outcome (server/carlock/crime.lua);
  this file shows the skill checks, progress bars, hints and animations, and runs the NPC
  behaviour the server asks for.

  - No-key driver flow: in the driver seat without a key (ignition.lua: 'nz:client:carlock:driver'
    with allowed = false) a hint shows Hotwire and Search (keybinds Config.CarLock.keys.hotwire /
    .search, default H / Z). Hotwire per profile ('skillcheck' | 'progress' | 'hack');
    success = temporary key and the engine starts. Search once per vehicle (progress).
  - Doors: "Pick the lock" target option on locked vehicles, the server's item use
    ('nz:client:carlock:crime'), and qb-smallresources' lockpick event (onLockpickEvent).
  - NPC drivers: aiming a weapon at a stopped / slow NPC driver starts a hold-up (keep aiming);
    resisting drivers flee with the car or fight. Dead original drivers carry the key: target
    option on the body (or on the vehicle while the body sits in the driver seat). Authorized
    jobs get "Request the vehicle" on NPC-driven vehicles.
  - 'nz:client:carlock:npc': the server asks the client that owns an NPC to run a step
    (holdup, release, flee, fight, pullover, handover, resume).
  Without ox_target / qb-target the body search and the vehicle request use an [E] prompt.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

-- A used lockpick is for the car in front of the player (same rule as the server's item use):
local ITEM_RANGE = 2.5         -- m: vehicle centre
local BIG_ITEM_RANGE = 7.0     -- m: the same for buses, trucks, industrial / service vehicles (not taxis)
local BIG_CLASSES = { [10] = true, [17] = true, [20] = true }
local AIM_POLL_MS = 150
local AIM_HOLD = 2             -- polls aiming at the same driver before the hold-up starts
local AIM_LOST_MS = 600        -- the hold-up ends when you stop aiming this long
local BODY_SCAN_MS = 1000
local BODY_RANGE = 10.0        -- m: bodies that get a target option
local BODY_TARGET_DISTANCE = 2.0
local MAX_BODIES = 8
local PROMPT_RANGE = 2.2
local LAST_DRIVER_RANGE = 15.0 -- m: a vehicle's last driver counts as its driver this close (server rule)
local TRIED_MS = 30000         -- a driver you tried to rob is not asked again for this long
local ENGINE_WAIT_MS = 4000
local ITEM_IDLE_WAIT_MS = 1500 -- a used tool waits this long for another script's progress bar

local ANIMS = {
  lockpick = { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_force_entry_ds', flag = 1 },
  hotwire = { dict = 'veh@std@ds@base', clip = 'hotwire', flag = 49 },
  search = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 49 },
  body = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', flag = 1 },
  holdup = { dict = 'mp_am_hold_up', clip = 'holdup_victim_20s', flag = 49 },
}

--- Hashes compared as unsigned 32-bit (natives and joaat may differ in sign).
local function u32(hash) return math.floor(tonumber(hash) or 0) % 4294967296 end
-- class 17 (service) models the size of a car: the normal reach and facing rules (server rule)
local CAR_SIZED = { [u32(joaat('taxi'))] = true, [u32(joaat('vivanite2'))] = true }

local NO_ROB_GROUPS = {}
for _, group in ipairs({ 'GROUP_UNARMED', 'GROUP_MELEE', 'GROUP_THROWN', 'GROUP_PETROLCAN', 'GROUP_FIREEXTINGUISHER',
  'GROUP_PARACHUTE', 'GROUP_NIGHTVISION', 'GROUP_DIGISCANNER' }) do
  NO_ROB_GROUPS[u32(joaat(group))] = true
end
local POP_AMBIENT = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
local POP_TRAFFIC = { [1] = true, [3] = true, [4] = true, [5] = true } -- not 2 (random parked)

local busy = false
local hintShown = false
local keybinds = {}
local weapon = nil             -- current weapon (lib.onCache)
local aimRunning = false
local tried = {}               -- [ped] = GetGameTimer() until the next attempt
local robbedFrom = {}          -- [ped] = vehicle: drivers this client held up (body search)
local bodies = {}              -- [ped] = target id
local bodyCount = 0

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function section(name)
  local value = CarLock.cfg()[name]
  return type(value) == 'table' and value or {}
end

local function now() return GetGameTimer() end

local function notify(kind, message)
  if type(message) == 'string' and message ~= '' then NZ.NUI.notify(kind, message) end
end

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

local function isPed(ped)
  return type(ped) == 'number' and ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped)
end

local function netIdOf(entity)
  if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then return nil end
  local id = NetworkGetNetworkIdFromEntity(entity)
  return id ~= 0 and id or nil
end

local function entityOf(netId)
  netId = tonumber(netId)
  if not netId or not NetworkDoesNetworkIdExist(netId) then return 0 end
  return NetworkGetEntityFromNetworkId(netId)
end

local function towing(vehicle)
  if type(NZ.Tow.isTowing) ~= 'function' then return false end
  local ok, res = pcall(NZ.Tow.isTowing, vehicle)
  return ok and res == true
end

local function locked(vehicle)
  local bag = Entity(vehicle).state.nzLocked
  if bag ~= nil then return bag == true end
  return (tonumber(GetVehicleDoorLockStatus(vehicle)) or 0) >= 2
end

local function hasKeyCached(vehicle)
  return CarLock.cachedKey(CarLock.plateOf(vehicle)) == true
end

local function idle()
  if busy or IsPauseMenuActive() or IsNuiFocused() then return false end
  if lib.progressActive() or lib.skillCheckActive() then return false end
  return not IsEntityDead(PlayerPedId())
end

--- Server callback; returns the result table or nil.
local function call(name, payload)
  local ok, res = pcall(lib.callback.await, name, false, payload)
  if not ok or type(res) ~= 'table' then return nil end
  return res
end

--- Street and model label of a vehicle (display text for police alerts).
local function displayInfo(vehicle, payload)
  if isVehicle(vehicle) then
    payload.street = NZ.Dispatch.streetAt(GetEntityCoords(vehicle))
    payload.label = NZ.Dispatch.modelLabel(GetEntityModel(vehicle))
  end
  return payload
end

local function playAnim(ped, anim)
  if not pcall(lib.requestAnimDict, anim.dict, 1500) then return false end
  TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag, 0, false, false, false)
  return true
end

local function stopAnim(ped, anim)
  StopAnimTask(ped, anim.dict, anim.clip, 1.0)
  RemoveAnimDict(anim.dict)
end

local DIFFICULTIES = { easy = true, medium = true, hard = true }

--- ox_lib skill checks from the server's list; true when every check passed.
local function skillCheck(list, inputs)
  local checks = {}
  for _, entry in ipairs(type(list) == 'table' and list or {}) do
    if type(entry) == 'string' and DIFFICULTIES[entry] then
      checks[#checks + 1] = entry
    elseif type(entry) == 'table' and tonumber(entry.areaSize) and tonumber(entry.speedMultiplier) then
      checks[#checks + 1] = { areaSize = tonumber(entry.areaSize), speedMultiplier = tonumber(entry.speedMultiplier) }
    end
  end
  if #checks == 0 then checks[1] = 'medium' end
  local keys = nil
  if type(inputs) == 'table' and #inputs > 0 then keys = inputs end
  local ok, res = pcall(lib.skillCheck, checks, keys)
  return ok and res == true
end

local function progress(duration, label, anim, disable)
  local ok, res = pcall(lib.progressCircle, {
    duration = duration, label = label, position = 'bottom', useWhileDead = false, canCancel = true,
    disable = disable or { move = true, car = true, combat = true },
    anim = anim and { dict = anim.dict, clip = anim.clip, flag = anim.flag } or nil,
  })
  return ok and res == true
end

local function cancelProgress()
  if lib.progressActive() then pcall(lib.cancelProgress) end
end

--- The NUI minigames this client can play (client/carlock/minigame.lua), sent with the starts.
local function minigames()
  return type(CarLock.minigameSupport) == 'function' and CarLock.minigameSupport() or nil
end

--- Play the server's NUI puzzle (minigame.lua): success, answer, snapped.
local function playMinigame(game, puzzle, opts)
  if type(CarLock.playMinigame) ~= 'function' then return false, nil, false end
  local ok, out = pcall(CarLock.playMinigame, game, puzzle, opts)
  if not ok or type(out) ~= 'table' then return false, nil, false end
  return out.success == true, out.answer, out.snapped == true
end

---------------------------------------------------------------------------------------
-- No-key driver hint (Hotwire / Search)
---------------------------------------------------------------------------------------

local function keyLabel(name, fallback)
  local bind = keybinds[name]
  if bind and type(bind.getCurrentKey) == 'function' then
    local ok, key = pcall(bind.getCurrentKey, bind)
    if ok and type(key) == 'string' and key ~= '' then return key end
  end
  return fallback
end

local function keyConfig()
  return section('keys')
end

--- Driver seat, no key, the hint applies?
local function noKeyDriver()
  local state = CarLock.driverState()
  if not state or state.allowed ~= false or not isVehicle(state.vehicle) then return nil end
  if towing(state.vehicle) then return nil end
  return state
end

--- Can this vehicle be searched (once, traffic / parked GTA vehicles; the server decides)?
local function searchable(vehicle)
  local search = section('search')
  if search.enabled == false or Entity(vehicle).state.nzSearched == true then return false end
  return search.ambientOnly == false or POP_AMBIENT[GetEntityPopulationType(vehicle)] == true
end

local function updateHint()
  local state = (not busy) and CarLock.enabled() and noKeyDriver() or nil
  if not state then
    if hintShown then
      hintShown = false
      NZ.NUI.hint(nil)
    end
    return
  end
  local keys = { { keys = { keyLabel('hotwire', keyConfig().hotwire or 'H') }, label = L('Hotwire') } }
  if searchable(state.vehicle) then
    keys[#keys + 1] = { keys = { keyLabel('search', keyConfig().search or 'Z') }, label = L('Search the vehicle') }
  end
  hintShown = true
  NZ.NUI.hint({ title = L('No key for this vehicle'), keys = keys })
end

AddEventHandler('nz:client:carlock:driver', function()
  updateHint()
end)

local function setBusy(value)
  busy = value
  updateHint()
end

--- Start the engine once the ignition knows about the new key.
local function startEngineWhenAllowed(vehicle)
  CarLock.refreshIgnition()
  local deadline = now() + ENGINE_WAIT_MS
  while now() < deadline do
    local state = CarLock.driverState()
    if not state or state.vehicle ~= vehicle then return end
    if state.allowed == true then
      SetVehicleEngineOn(vehicle, true, false, true)
      return
    end
    Wait(100)
  end
end

--- Hotwire the vehicle we drive (no key). `slot`: the item slot of the server's item use.
---@param slot number|nil
function CarLock.hotwire(slot)
  if not idle() then return end
  local state = noKeyDriver()
  if not state or not state.netId then return end
  local vehicle = state.vehicle
  setBusy(true)
  local ok, err = pcall(function()
    local res = call('nz:carlock:hotwire', displayInfo(vehicle, {
      step = 'start', netId = state.netId, slot = slot, minigames = minigames(),
    }))
    if not res then return end
    if not res.ok then return notify('error', res.error) end
    local since = now()
    local data = type(res.data) == 'table' and res.data or {}
    local ped = PlayerPedId()
    local success, answer
    if data.method == 'wires' or data.method == 'reader' then
      -- the NUI minigames (G.7): splice the wires / tune the signal reader
      local anim = playAnim(ped, ANIMS.hotwire)
      success, answer = playMinigame(data.method, data.puzzle, { vehicle = vehicle, since = since })
      if anim then stopAnim(ped, ANIMS.hotwire) end
    elseif data.method == 'progress' then
      success = progress(math.floor(tonumber(data.duration) or 6000), L('Hotwiring...'), ANIMS.hotwire, { move = true, car = true, combat = true })
    else
      local anim = playAnim(ped, ANIMS.hotwire)
      success = skillCheck(data.difficulty, data.inputs)
      if anim then stopAnim(ped, ANIMS.hotwire) end
    end
    local fin = call('nz:carlock:hotwire', { step = 'finish', id = data.id, success = success, answer = answer })
    if not fin or not fin.ok then return notify('error', fin and fin.error) end
    local result = type(fin.data) == 'table' and fin.data or {}
    if result.broke then notify('error', L('Your hacking device broke')) end
    if result.success then
      notify('success', L('You hotwired the vehicle'))
      startEngineWhenAllowed(vehicle)
    else
      notify('error', L('You failed to hotwire the vehicle'))
    end
  end)
  if not ok then Utils.debug(('carlock: hotwire failed: %s'):format(tostring(err))) end
  setBusy(false)
end

--- Search the vehicle we drive (no key, once per vehicle).
function CarLock.searchVehicle()
  if not idle() or section('search').enabled == false then return end
  local state = noKeyDriver()
  if not state or not state.netId then return end
  if Entity(state.vehicle).state.nzSearched == true then return notify('error', L('This vehicle was already searched')) end
  if not searchable(state.vehicle) then return notify('error', L('You cannot search this vehicle')) end
  local vehicle = state.vehicle
  setBusy(true)
  local ok, err = pcall(function()
    local res = call('nz:carlock:search', displayInfo(vehicle, { step = 'start', netId = state.netId }))
    if not res then return end
    if not res.ok then return notify('error', res.error) end
    local data = type(res.data) == 'table' and res.data or {}
    local success = progress(math.floor(tonumber(data.duration) or 7000), L('Searching the vehicle...'), ANIMS.search,
      { move = true, car = true, combat = true })
    local fin = call('nz:carlock:search', { step = 'finish', id = data.id, success = success })
    if not fin or not fin.ok then return notify('error', fin and fin.error) end
    local result = type(fin.data) == 'table' and fin.data or {}
    if not result.success then return end
    local found = type(result.found) == 'table' and result.found or {}
    if #found == 0 then
      notify('info', L('You found nothing useful'))
    else
      notify('success', L('You found: {items}', { items = table.concat(found, ', ') }))
    end
  end)
  if not ok then Utils.debug(('carlock: search failed: %s'):format(tostring(err))) end
  setBusy(false)
end

---------------------------------------------------------------------------------------
-- Doors: lockpick / screwdriver / hacking device
---------------------------------------------------------------------------------------

--- Pick the lock of `vehicle` with `tool` (Config.CarLock.items key; nil = the server picks
--- the first tool of the vehicle's profile we carry).
---@param vehicle number
---@param tool string|nil
---@param slot number|nil
function CarLock.lockpick(vehicle, tool, slot)
  if not idle() or not isVehicle(vehicle) then return end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return end
  local netId = netIdOf(vehicle)
  if not netId then return end
  if not locked(vehicle) then return notify('info', L('This vehicle is not locked')) end
  setBusy(true)
  local ok, err = pcall(function()
    local res = call('nz:carlock:lockpick', displayInfo(vehicle, {
      step = 'start', netId = netId, tool = type(tool) == 'string' and tool or nil, slot = tonumber(slot),
      minigames = minigames(),
    }))
    if not res then return end
    if not res.ok then return notify('error', res.error) end
    local since = now()
    local data = type(res.data) == 'table' and res.data or {}
    TaskTurnPedToFaceEntity(ped, vehicle, 800)
    Wait(800)
    local anim = playAnim(ped, ANIMS.lockpick)
    local success, answer, snapped
    if data.method == 'pins' then
      -- the 3D pin lock (G.6); an overset pin may snap the pick (the server rolls snapChance)
      success, answer, snapped = playMinigame('pins', data.puzzle, { vehicle = vehicle, since = since, snapChance = data.snapChance })
    else
      success = skillCheck(data.difficulty, data.inputs)
    end
    if anim then stopAnim(ped, ANIMS.lockpick) end
    local fin = call('nz:carlock:lockpick', {
      step = 'finish', id = data.id, success = success, answer = answer, snapped = snapped or nil,
    })
    if not fin or not fin.ok then return notify('error', fin and fin.error) end
    local result = type(fin.data) == 'table' and fin.data or {}
    if result.broke then notify('error', snapped and L('Your lockpick snapped') or L('Your tool broke')) end
    if result.success then
      notify('success', L('The lock gave way'))
    else
      notify('error', L('You failed to pick the lock'))
    end
  end)
  if not ok then Utils.debug(('carlock: lockpick failed: %s'):format(tostring(err))) end
  setBusy(false)
end

--- Does the vehicle's security profile take `tool` (Config.CarLock.items key)?
local function takesTool(vehicle, tool)
  local _, profile = CarLock.profileOf(GetEntityModel(vehicle), GetVehicleClass(vehicle))
  local item = CarLock.itemName(tool)
  for _, entry in ipairs(type(profile.accessTools) == 'table' and profile.accessTools or {}) do
    if type(entry) == 'table' and type(entry.item) == 'string' and CarLock.itemName(entry.item) == item then return true end
  end
  return false
end

--- Nearest locked vehicle in front of us that `tool` can open: nobody alive at the wheel, no
--- key, not towed (the server's item-use rule, so a car behind us stays out of a robbery).
local function nearestLocked(tool)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local h = math.rad(tonumber(GetEntityHeading(ped)) or 0.0)
  local fx, fy = -math.sin(h), math.cos(h)
  local best, bestDist = nil, math.huge
  for _, entry in ipairs(lib.getNearbyVehicles(coords, BIG_ITEM_RANGE, false) or {}) do
    local vehicle = entry.vehicle
    local d = entry.coords - coords
    local dist = #d
    if dist < bestDist and isVehicle(vehicle) then
      local big = BIG_CLASSES[GetVehicleClass(vehicle)] == true and not CAR_SIZED[u32(GetEntityModel(vehicle))]
      local flat = math.sqrt(d.x * d.x + d.y * d.y)
      local facing = flat < 0.01 and 1.0 or (d.x * fx + d.y * fy) / flat
      local driver = GetPedInVehicleSeat(vehicle, -1)
      if dist <= (big and BIG_ITEM_RANGE or ITEM_RANGE) and facing >= (big and 0.0 or 0.3)
        and not (driver ~= 0 and not IsEntityDead(driver)) and locked(vehicle) and not towing(vehicle)
        and not hasKeyCached(vehicle) and takesTool(vehicle, tool) then
        best, bestDist = vehicle, dist
      end
    end
  end
  return best
end

--- qb-smallresources' lockpick item (event 'lockpicks:UseLockpick', forwarded by
--- bridge/client/listeners.lua): a locked vehicle nearby that this lockpick opens is ours,
--- anything else (house and store robberies) is left to the scripts that listen too.
---@param isAdvanced boolean
function CarLock.onLockpickEvent(isAdvanced)
  if not CarLock.enabled() or busy then return end
  if IsPedInAnyVehicle(PlayerPedId(), false) then return end
  local tool = isAdvanced == true and 'advancedLockpick' or 'lockpick'
  local vehicle = nearestLocked(tool)
  if not vehicle then return end
  CarLock.lockpick(vehicle, tool)
end

--- The inventory already counted the item use as handled: wait a moment for another script's
--- progress bar / skill check / NUI focus to end instead of losing the use silently.
local function waitIdle(ms)
  local deadline = GetGameTimer() + ms
  while not idle() and GetGameTimer() < deadline do Wait(100) end
  return idle()
end

-- The server's item use found a vehicle for this tool (server/carlock/crime.lua).
RegisterNetEvent('nz:client:carlock:crime', function(data)
  if type(data) ~= 'table' then return end
  local vehicle = entityOf(data.netId)
  if not isVehicle(vehicle) then return end
  if data.action ~= 'lockpick' and data.action ~= 'hotwire' then return end
  CreateThread(function()
    if not waitIdle(ITEM_IDLE_WAIT_MS) then return notify('error', L('You are busy')) end
    if data.action == 'lockpick' then
      CarLock.lockpick(vehicle, type(data.tool) == 'string' and data.tool or nil, data.slot)
    else
      CarLock.hotwire(data.slot)
    end
  end)
end)

---------------------------------------------------------------------------------------
-- NPC drivers: hold-up (aim), request (jobs), dead driver (body search)
---------------------------------------------------------------------------------------

local function npcCfg() return section('npc') end

local function robbable(ped)
  if not isPed(ped) or IsPedAPlayer(ped) or IsEntityDead(ped) or not NetworkGetEntityIsNetworked(ped) then return nil end
  if npcCfg().ambientOnly ~= false and not POP_AMBIENT[GetEntityPopulationType(ped)] then return nil end
  if Entity(ped).state.nzTowDriver == true then return nil end
  if not IsPedInAnyVehicle(ped, false) then return nil end
  local vehicle = GetVehiclePedIsIn(ped, false)
  if not isVehicle(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped or not netIdOf(vehicle) then return nil end
  if towing(vehicle) or hasKeyCached(vehicle) then return nil end
  return vehicle
end

local assistAllowed -- defined with the request below

--- The NPC driver we aim at, when a hold-up can start (never for on-duty assist jobs: they
--- aim at drivers on duty and use "Request the vehicle").
local function aimTarget()
  local player = PlayerId()
  local ped = PlayerPedId()
  if not weapon or NO_ROB_GROUPS[u32(GetWeapontypeGroup(weapon))] then return nil end
  if assistAllowed() then return nil end
  if IsPedInAnyVehicle(ped, false) or not IsPlayerFreeAiming(player) then return nil end
  local aiming, target = GetEntityPlayerIsFreeAimingAt(player)
  if not aiming or not target or target == 0 then return nil end
  local until_ = tried[target]
  if until_ and until_ > now() then return nil end
  local vehicle = robbable(target)
  if not vehicle then return nil end
  local npc = npcCfg()
  if GetEntitySpeed(vehicle) > (tonumber(npc.maxSpeed) or 8.0) then return nil end
  if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (tonumber(npc.range) or 6.0) then return nil end
  return target, vehicle
end

local function stillAiming(target)
  local player = PlayerId()
  if IsPlayerFreeAimingAtEntity(player, target) then return true end
  local aiming, current = GetEntityPlayerIsFreeAimingAt(player)
  return aiming and current == target
end

local function holdUp(target, vehicle)
  local range = (tonumber(npcCfg().range) or 6.0) + 2.0
  tried[target] = now() + TRIED_MS
  local res = call('nz:carlock:npcRob', displayInfo(vehicle, { step = 'start', netId = netIdOf(vehicle), pedNetId = netIdOf(target) }))
  if not res then return end
  if not res.ok then return notify('error', res.error) end
  local data = type(res.data) == 'table' and res.data or {}
  robbedFrom[target] = vehicle
  if data.outcome == 'flee' then return notify('error', L('The driver floors it!')) end
  if data.outcome == 'fight' then return notify('error', L('The driver fights back!')) end
  if data.outcome == 'drop' then return notify('info', L('The driver threw the keys down and ran!')) end
  if not data.id then return end
  local watching = true
  CreateThread(function()
    local lostSince = nil
    while watching do
      local ped = PlayerPedId()
      local ok = DoesEntityExist(target) and not IsEntityDead(target) and not IsEntityDead(ped)
        and #(GetEntityCoords(ped) - GetEntityCoords(target)) <= range
      if ok and not stillAiming(target) then
        lostSince = lostSince or now()
        ok = now() - lostSince < AIM_LOST_MS
      else
        lostSince = nil
      end
      if not ok then cancelProgress() break end
      Wait(100)
    end
  end)
  local success = progress(math.floor(tonumber(data.duration) or 3500), L('Keep aiming: the driver hands over the key'), nil, {})
  watching = false
  local fin = call('nz:carlock:npcRob', { step = 'finish', id = data.id, success = success })
  if not fin or not fin.ok then return notify('error', fin and fin.error) end
  if type(fin.data) == 'table' and fin.data.success then
    notify('success', L('The driver hands you the key'))
  else
    notify('error', L('The driver got away'))
  end
end

local function aimLoop()
  if aimRunning then return end
  aimRunning = true
  CreateThread(function()
    local last, held = nil, 0
    Wait(0)
    while weapon and CarLock.enabled() and npcCfg().robbery ~= false do
      local target, vehicle = nil, nil
      if idle() then target, vehicle = aimTarget() end
      if target and target == last then held = held + 1 else held = target and 1 or 0 end
      last = target
      if target and held >= AIM_HOLD then
        held, last = 0, nil
        setBusy(true)
        local ok, err = pcall(holdUp, target, vehicle)
        if not ok then Utils.debug(('carlock: hold-up failed: %s'):format(tostring(err))) end
        setBusy(false)
      end
      Wait(AIM_POLL_MS)
    end
    aimRunning = false
  end)
end

assistAllowed = function()
  local jobs = npcCfg().assistJobs
  local job = NZ.Bridge.getJob and NZ.Bridge.getJob() or nil
  if type(jobs) ~= 'table' or type(job) ~= 'table' or type(job.name) ~= 'string' or job.onDuty == false then return false end
  local name = job.name:lower()
  for _, allowed in ipairs(jobs) do
    if type(allowed) == 'string' and allowed:lower() == name then return true end
  end
  return false
end

--- NPC driver of `vehicle` an authorized job may ask for the vehicle.
local function assistDriver(vehicle)
  if not isVehicle(vehicle) or not netIdOf(vehicle) or towing(vehicle) or hasKeyCached(vehicle) then return nil end
  local ped = GetPedInVehicleSeat(vehicle, -1)
  if not isPed(ped) or IsPedAPlayer(ped) or IsEntityDead(ped) or not netIdOf(ped) then return nil end
  if Entity(ped).state.nzTowDriver == true then return nil end
  return ped
end

--- Authorized jobs: ask the NPC driver of `vehicle` to hand it over (no alert).
---@param vehicle number
function CarLock.requestVehicle(vehicle)
  if not idle() or not assistAllowed() then return end
  local ped = assistDriver(vehicle)
  if not ped then return end
  setBusy(true)
  local ok, err = pcall(function()
    local res = call('nz:carlock:npcAssist', { step = 'start', netId = netIdOf(vehicle), pedNetId = netIdOf(ped) })
    if not res then return end
    if not res.ok then return notify('error', res.error) end
    local data = type(res.data) == 'table' and res.data or {}
    local success = progress(math.floor(tonumber(data.duration) or 4000), L('Asking the driver for the vehicle...'), nil,
      { car = true, combat = true })
    local fin = call('nz:carlock:npcAssist', { step = 'finish', id = data.id, success = success })
    if not fin or not fin.ok then return notify('error', fin and fin.error) end
    if type(fin.data) == 'table' and fin.data.success then
      notify('success', L('The driver hands you the key'))
    end
  end)
  if not ok then Utils.debug(('carlock: request failed: %s'):format(tostring(err))) end
  setBusy(false)
end

--- A dead NPC the server may let us search: a traffic ped (npc.ambientOnly) or one we held up.
local function searchableBody(ped)
  if not isPed(ped) or IsPedAPlayer(ped) or not IsEntityDead(ped) or not netIdOf(ped) then return false end
  return npcCfg().ambientOnly == false or robbedFrom[ped] ~= nil or POP_AMBIENT[GetEntityPopulationType(ped)] == true
end

--- Does `vehicle` keep its dead driver's key (server rule)? A traffic vehicle (population
--- 1/3/4/5), or the driver we held up; never a random parked car or a script vehicle.
local function keepsBodyKey(vehicle, ped)
  return npcCfg().ambientOnly == false or robbedFrom[ped] ~= nil or POP_TRAFFIC[GetEntityPopulationType(vehicle)] == true
end

--- Vehicle a dead NPC drove (still in the seat, the vehicle's last driver, or one we robbed).
local function bodyVehicle(ped)
  if not searchableBody(ped) then return nil end
  local vehicle = GetVehiclePedIsIn(ped, false)
  if isVehicle(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
    return keepsBodyKey(vehicle, ped) and vehicle or nil
  end
  vehicle = GetVehiclePedIsIn(ped, true)
  if isVehicle(vehicle) and GetLastPedInVehicleSeat(vehicle, -1) == ped
    and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= LAST_DRIVER_RANGE then
    return keepsBodyKey(vehicle, ped) and vehicle or nil
  end
  vehicle = robbedFrom[ped]
  if isVehicle(vehicle) then return vehicle end
  return nil
end

--- Search the body of a vehicle's dead original driver for the key.
---@param ped number
---@param vehicle number|nil
function CarLock.searchDriver(ped, vehicle)
  if not idle() or npcCfg().deadDriverKeys == false then return end
  vehicle = isVehicle(vehicle) and vehicle or bodyVehicle(ped)
  if not vehicle or not netIdOf(vehicle) or not netIdOf(ped) then return end
  if hasKeyCached(vehicle) then return notify('info', L('You already have the keys of this vehicle')) end
  setBusy(true)
  local ok, err = pcall(function()
    local res = call('nz:carlock:deadDriver', { step = 'start', netId = netIdOf(vehicle), pedNetId = netIdOf(ped) })
    if not res then return end
    if not res.ok then return notify('error', res.error) end
    local data = type(res.data) == 'table' and res.data or {}
    local inVehicle = IsPedInAnyVehicle(PlayerPedId(), false)
    local success = progress(math.floor(tonumber(data.duration) or 4500), L('Searching the driver...'),
      not inVehicle and ANIMS.body or nil, { move = true, car = true, combat = true })
    local fin = call('nz:carlock:deadDriver', { step = 'finish', id = data.id, success = success })
    if not fin or not fin.ok then return notify('error', fin and fin.error) end
    if type(fin.data) == 'table' and fin.data.success then
      notify('success', L('You found the key of the vehicle'))
      local id = bodies[ped]
      if id then
        NZ.Target.remove(id)
        bodies[ped] = nil
        bodyCount = bodyCount - 1
      end
    end
  end)
  if not ok then Utils.debug(('carlock: body search failed: %s'):format(tostring(err))) end
  setBusy(false)
end

---------------------------------------------------------------------------------------
-- NPC behaviour (this client owns the ped; the server picked the step)
---------------------------------------------------------------------------------------

local function takeControl(entity, timeout)
  if NetworkHasControlOfEntity(entity) then return true end
  local deadline = now() + (timeout or 1000)
  NetworkRequestControlOfEntity(entity)
  while not NetworkHasControlOfEntity(entity) and now() < deadline do
    Wait(50)
    NetworkRequestControlOfEntity(entity)
  end
  return NetworkHasControlOfEntity(entity)
end

local function leaveVehicle(ped, vehicle, flag)
  if not isVehicle(vehicle) or not IsPedInVehicle(ped, vehicle, false) then return end
  TaskLeaveVehicle(ped, vehicle, flag or 256)
  local deadline = now() + 3000
  while IsPedInAnyVehicle(ped, false) and now() < deadline do Wait(100) end
end

local function fleeOnFoot(ped, threat)
  ClearPedTasks(ped)
  SetBlockingOfNonTemporaryEvents(ped, false)
  SetPedFleeAttributes(ped, 0, false)
  ResetPedLastVehicle(ped)
  if threat ~= 0 and DoesEntityExist(threat) then
    TaskSmartFleePed(ped, threat, 100.0, -1, false, false)
  else
    TaskWanderStandard(ped, 10.0, 10)
  end
  SetPedKeepTask(ped, true)
end

local STEPS = {}

STEPS.holdup = function(ped, vehicle, _, data)
  local ms = math.floor(Utils.clamp(tonumber(data.ms) or 9000, 1000, 40000))
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedKeepTask(ped, true)
  if isVehicle(vehicle) then
    takeControl(vehicle, 500)
    TaskVehicleTempAction(ped, vehicle, 6, ms)
  end
  playAnim(ped, ANIMS.holdup)
  PlayPain(ped, 6, 0)
end

STEPS.release = function(ped, vehicle, threat)
  StopAnimTask(ped, ANIMS.holdup.dict, ANIMS.holdup.clip, 1.0)
  leaveVehicle(ped, vehicle, 256)
  PlayPain(ped, 7, 0)
  fleeOnFoot(ped, threat)
end

-- 'drop' reaction: out of the car, the keys go on the ground (the server puts them there),
-- then away on foot
STEPS.drop = function(ped, vehicle, threat)
  StopAnimTask(ped, ANIMS.holdup.dict, ANIMS.holdup.clip, 1.0)
  PlayPain(ped, 7, 0)
  leaveVehicle(ped, vehicle, 256)
  local dict, clip = 'pickup_object', 'putdown_low'
  if pcall(lib.requestAnimDict, dict, 1000) then
    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, 900, 0, 0, false, false, false)
    Wait(900)
    RemoveAnimDict(dict)
  end
  fleeOnFoot(ped, threat)
end

STEPS.flee = function(ped, vehicle, threat)
  StopAnimTask(ped, ANIMS.holdup.dict, ANIMS.holdup.clip, 1.0)
  ClearPedTasks(ped)
  PlayPain(ped, 7, 0)
  if isVehicle(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
    takeControl(vehicle, 500)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetVehicleEngineOn(vehicle, true, true, false)
    TaskVehicleDriveWander(ped, vehicle, 40.0, 786469)
    SetPedKeepTask(ped, true)
  else
    fleeOnFoot(ped, threat)
  end
end

STEPS.fight = function(ped, vehicle, threat, data)
  StopAnimTask(ped, ANIMS.holdup.dict, ANIMS.holdup.clip, 1.0)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCombatAttributes(ped, 3, true)
  leaveVehicle(ped, vehicle, 256)
  if type(data.weapon) == 'string' and data.weapon ~= '' then
    GiveWeaponToPed(ped, joaat(data.weapon), 60, false, true)
  end
  SetPedFleeAttributes(ped, 0, false)
  SetPedCombatAttributes(ped, 5, true)
  SetPedCombatAttributes(ped, 46, true)
  SetPedAccuracy(ped, 25)
  SetBlockingOfNonTemporaryEvents(ped, false)
  if threat ~= 0 and DoesEntityExist(threat) then
    TaskCombatPed(ped, threat, 0, 16)
  else
    TaskCombatHatedTargetsAroundPed(ped, 30.0, 0)
  end
  SetPedKeepTask(ped, true)
end

STEPS.pullover = function(ped, vehicle, officer, data)
  local ms = math.floor(Utils.clamp(tonumber(data.ms) or 9000, 1000, 40000))
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedKeepTask(ped, true)
  if isVehicle(vehicle) then
    takeControl(vehicle, 500)
    TaskVehicleTempAction(ped, vehicle, 27, 2500)
    local deadline = now() + 2500
    while now() < deadline and GetEntitySpeed(vehicle) > 0.5 do Wait(100) end
    leaveVehicle(ped, vehicle, 0)
  end
  if officer ~= 0 and DoesEntityExist(officer) then TaskTurnPedToFaceEntity(ped, officer, ms) end
end

STEPS.handover = function(ped)
  ClearPedTasks(ped)
  SetBlockingOfNonTemporaryEvents(ped, false)
  ResetPedLastVehicle(ped)
  TaskWanderStandard(ped, 10.0, 10)
  SetPedKeepTask(ped, true)
end

STEPS.resume = function(ped, vehicle)
  StopAnimTask(ped, ANIMS.holdup.dict, ANIMS.holdup.clip, 1.0)
  ClearPedTasks(ped)
  SetBlockingOfNonTemporaryEvents(ped, false)
  if isVehicle(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
    TaskVehicleDriveWander(ped, vehicle, 15.0, 786603)
  else
    TaskWanderStandard(ped, 10.0, 10)
  end
end

RegisterNetEvent('nz:client:carlock:npc', function(data)
  if type(data) ~= 'table' or type(data.step) ~= 'string' or not STEPS[data.step] then return end
  CreateThread(function()
    local ped = entityOf(data.ped)
    if not isPed(ped) or IsPedAPlayer(ped) then return end
    local vehicle = entityOf(data.vehicle)
    local threat = 0
    local player = tonumber(data.robber) and GetPlayerFromServerId(math.floor(tonumber(data.robber))) or -1
    if player and player ~= -1 then threat = GetPlayerPed(player) end
    -- task natives on a ped this client does not own only change the local clone
    if not takeControl(ped, 1000) then
      return Utils.debug(('carlock: npc step %s: no control of the ped'):format(data.step))
    end
    local ok, err = pcall(STEPS[data.step], ped, vehicle, threat or 0, data)
    if not ok then Utils.debug(('carlock: npc step %s failed: %s'):format(data.step, tostring(err))) end
  end)
end)

---------------------------------------------------------------------------------------
-- Target options, body scan, prompt fallback
---------------------------------------------------------------------------------------

local toolCache = { at = -1e9, profile = nil, value = false }

--- Do we carry a tool of this profile? (cached for a second; the server checks again)
local function carriesTool(profileName, profile)
  if toolCache.profile == profileName and now() - toolCache.at < 1000 then return toolCache.value end
  local value = false
  for _, entry in ipairs(type(profile.accessTools) == 'table' and profile.accessTools or {}) do
    local item = type(entry) == 'table' and CarLock.itemName(entry.item) or nil
    if item and NZ.Inventory.hasItem(item) then value = true break end
  end
  toolCache.profile, toolCache.value, toolCache.at = profileName, value, now()
  return value
end

local function canLockpick(vehicle)
  if busy or not CarLock.enabled() or not isVehicle(vehicle) or not netIdOf(vehicle) then return false end
  if IsPedInAnyVehicle(PlayerPedId(), false) or not locked(vehicle) or towing(vehicle) or hasKeyCached(vehicle) then return false end
  local driver = GetPedInVehicleSeat(vehicle, -1)
  if driver ~= 0 and not IsEntityDead(driver) then return false end
  local name, profile = CarLock.profileOf(GetEntityModel(vehicle), GetVehicleClass(vehicle))
  return carriesTool(name, profile)
end

local function deadDriverIn(vehicle)
  if not isVehicle(vehicle) then return nil end
  local ped = GetPedInVehicleSeat(vehicle, -1)
  if ped == 0 or not searchableBody(ped) or not keepsBodyKey(vehicle, ped) then return nil end
  return ped
end

local function registerTargets()
  if not CarLock.enabled() or not NZ.Target.available() then return end
  NZ.Target.addVehicleOption('nz_carlock_lockpick', {
    label = L('Pick the lock'), icon = 'fas fa-unlock', distance = 2.0,
    canInteract = function(entity) return canLockpick(entity) end,
    onSelect = function(data) CreateThread(function() CarLock.lockpick(data.entity) end) end,
  })
  if npcCfg().deadDriverKeys ~= false then
    NZ.Target.addVehicleOption('nz_carlock_driver_key', {
      label = L('Take the key from the driver'), icon = 'fas fa-key', distance = 2.5,
      canInteract = function(entity)
        return not busy and CarLock.enabled() and deadDriverIn(entity) ~= nil and not towing(entity) and not hasKeyCached(entity)
      end,
      onSelect = function(data)
        local ped = deadDriverIn(data.entity)
        if ped then CreateThread(function() CarLock.searchDriver(ped, data.entity) end) end
      end,
    })
  end
  if type(npcCfg().assistJobs) == 'table' and next(npcCfg().assistJobs) ~= nil then
    NZ.Target.addVehicleOption('nz_carlock_request', {
      label = L('Request the vehicle'), icon = 'fas fa-hand', distance = 3.0,
      canInteract = function(entity)
        return not busy and CarLock.enabled() and assistAllowed() and assistDriver(entity) ~= nil
      end,
      onSelect = function(data) CreateThread(function() CarLock.requestVehicle(data.entity) end) end,
    })
  end
end

local function forgetBody(ped)
  local id = bodies[ped]
  if not id then return end
  NZ.Target.remove(id)
  bodies[ped] = nil
  bodyCount = bodyCount - 1
end

--- Bodies of dead NPC drivers around us get a "Search the driver" target option; without a
--- target resource the nearest one (or an NPC driver an authorized job may ask) shows a prompt.
local prompt = nil   -- { label, run } shown while near

local function scanBodies(coords, targets)
  local seen = {}
  local nearest, nearestDist = nil, PROMPT_RANGE
  for _, entry in ipairs(lib.getNearbyPeds(coords, BODY_RANGE) or {}) do
    local ped = entry.ped
    if not IsPedInAnyVehicle(ped, false) then
      local vehicle = bodyVehicle(ped)
      if vehicle and not hasKeyCached(vehicle) and not towing(vehicle) then
        seen[ped] = true
        if targets and not bodies[ped] and bodyCount < MAX_BODIES then
          local id = 'nz_carlock_body_' .. tostring(netIdOf(ped))
          local added = NZ.Target.addLocalEntity(id, ped, {
            { label = L('Search the driver'), icon = 'fas fa-hand', distance = BODY_TARGET_DISTANCE,
              canInteract = function() return not busy end,
              onSelect = function() CreateThread(function() CarLock.searchDriver(ped) end) end },
          })
          if added then
            bodies[ped] = id
            bodyCount = bodyCount + 1
          end
        end
        local dist = #(entry.coords - coords)
        if not targets and dist <= nearestDist then
          nearest, nearestDist = { label = L('Search the driver'), run = function() CarLock.searchDriver(ped) end }, dist
        end
      end
    end
  end
  for ped in pairs(bodies) do
    if not seen[ped] then forgetBody(ped) end
  end
  return nearest
end

--- Without a target resource: a dead NPC driver still at the wheel of the nearest vehicle.
local function nearbySeatedBody(coords)
  local vehicle = lib.getClosestVehicle(coords, PROMPT_RANGE + 1.0, false)
  local ped = vehicle and deadDriverIn(vehicle) or nil
  if not ped or towing(vehicle) or hasKeyCached(vehicle) then return nil end
  return { label = L('Take the key from the driver'), run = function() CarLock.searchDriver(ped, vehicle) end }
end

local function nearbyRequest(coords)
  if not assistAllowed() then return nil end
  local vehicle = lib.getClosestVehicle(coords, PROMPT_RANGE + 1.0, false)
  if not vehicle or not assistDriver(vehicle) then return nil end
  return { label = L('Request the vehicle'), run = function() CarLock.requestVehicle(vehicle) end }
end

local function promptLoop()
  CreateThread(function()
    while prompt do
      if IsControlJustReleased(0, 38) and idle() then
        local run = prompt.run
        prompt = nil
        NZ.NUI.prompt(nil)
        run()
      end
      Wait(0)
    end
  end)
end

local function setPrompt(entry)
  if entry and prompt and prompt.label == entry.label then
    prompt.run = entry.run
    return
  end
  local had = prompt ~= nil
  prompt = entry
  if entry then
    NZ.NUI.prompt(entry.label, 'E')
    if not had then promptLoop() end
  elseif had then
    NZ.NUI.prompt(nil)
  end
end

local function interactionTick()
  local ped = PlayerPedId()
  if not CarLock.enabled() or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
    setPrompt(nil)
    for body in pairs(bodies) do forgetBody(body) end
    return
  end
  local coords = GetEntityCoords(ped)
  local targets = NZ.Target.available()
  local entry = nil
  if npcCfg().deadDriverKeys ~= false then
    entry = scanBodies(coords, targets)
    if not targets and not entry then entry = nearbySeatedBody(coords) end
  end
  if not targets and not entry then entry = nearbyRequest(coords) end
  setPrompt((not targets and not busy) and entry or nil)
end

---------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------

if CarLock.enabled() then
  local keys = keyConfig()
  keybinds.hotwire = lib.addKeybind({
    name = 'nz_carlock_hotwire',
    description = L('Hotwire the vehicle (no key)'),
    defaultKey = type(keys.hotwire) == 'string' and keys.hotwire or 'H',
    onPressed = function()
      if hintShown then CreateThread(function() CarLock.hotwire() end) end
    end,
  })
  if section('search').enabled ~= false then
    keybinds.search = lib.addKeybind({
      name = 'nz_carlock_search',
      description = L('Search the vehicle (no key)'),
      defaultKey = type(keys.search) == 'string' and keys.search or 'Z',
      onPressed = function()
        if hintShown then CreateThread(function() CarLock.searchVehicle() end) end
      end,
    })
  end

  lib.onCache('weapon', function(value)
    weapon = value or nil
    if weapon then aimLoop() end
  end)

  AddStateBagChangeHandler('nzSearched', nil, function()
    if hintShown then SetTimeout(0, updateHint) end
  end)

  AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' or resource == 'qb-target' then SetTimeout(1000, registerTargets) end
  end)

  CreateThread(function()
    Wait(1000)
    registerTargets()
    weapon = cache.weapon or nil
    if weapon then aimLoop() end
    while true do
      local ok, err = pcall(interactionTick)
      if not ok then Utils.debug(('carlock: interaction tick failed: %s'):format(tostring(err))) end
      Wait(prompt and 300 or BODY_SCAN_MS)
    end
  end)

  CreateThread(function()
    while true do
      Wait(60000)
      local t = now()
      for ped, until_ in pairs(tried) do
        if until_ < t or not DoesEntityExist(ped) then tried[ped] = nil end
      end
      for ped in pairs(robbedFrom) do
        if not DoesEntityExist(ped) then robbedFrom[ped] = nil end
      end
    end
  end)
end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  if hintShown then NZ.NUI.hint(nil) end
  if prompt then NZ.NUI.prompt(nil) end
end)
