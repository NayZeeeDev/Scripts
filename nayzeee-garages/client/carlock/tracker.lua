--[[
  nayzeee-garages — car lock: vehicle tracker (client, NZ.CarLock). docs/CARLOCK.md §10.

  Locate: asks the server where a trackable vehicle is ('nz:carlock:tracker' { plate }: tracker
  profile, a key, the player's routing bucket, not on the tow truck), sets a waypoint and puts
  a blip on it that follows the vehicle for Config.CarLock.tracker.locateSeconds (positions
  from this client while the vehicle is in scope, else from the server every few seconds).
  Every follow step reports through the local event 'nz:client:carlock:tracking'
  ({ plate, distance, live } | { plate, lost = true }) so the key ring can show a live
  distance. Remote alarm: 'nz:carlock:trackerAlarm' (the server checks key, tracker,
  cooldown). No per-frame work: the follow loop sleeps 1 s (local) / 3 s (server).

  API: CarLock.trackerStatus(plate|nil) -> result ; CarLock.locate(plate) -> result ;
       CarLock.stopLocate() ; CarLock.locating() -> plate|nil ; CarLock.remoteAlarm(plate, on?) -> result
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local LOCAL_STEP = 1000         -- ms between two follow steps while the vehicle is in scope
local SERVER_STEP = 3000        -- ms between two server positions
local LOST_AFTER = 3            -- failed server answers in a row before the vehicle counts as lost

local follow = { plate = nil, netId = nil, blip = nil, generation = 0, untilAt = 0 }

local function trackerCfg()
  local t = CarLock.cfg().tracker
  return type(t) == 'table' and t or {}
end

local function blipCfg()
  local b = trackerCfg().blip
  return type(b) == 'table' and b or {}
end

--- Vehicle of a network id when it exists on this client, else nil.
local function localVehicle(netId)
  netId = tonumber(netId)
  if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
  local vehicle = NetToVeh(netId)
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
  return nil
end

local function removeBlip()
  if follow.blip and DoesBlipExist(follow.blip) then RemoveBlip(follow.blip) end
  follow.blip = nil
end

local function placeBlip(x, y, z)
  if follow.blip and DoesBlipExist(follow.blip) then
    SetBlipCoords(follow.blip, x + 0.0, y + 0.0, z + 0.0)
    return
  end
  local cfg = blipCfg()
  local blip = AddBlipForCoord(x + 0.0, y + 0.0, z + 0.0)
  SetBlipSprite(blip, math.floor(tonumber(cfg.sprite) or 225))
  SetBlipColour(blip, math.floor(tonumber(cfg.color) or 5))
  SetBlipScale(blip, (tonumber(cfg.scale) or 0.85) + 0.0)
  SetBlipAsShortRange(blip, false)
  SetBlipFlashes(blip, true)
  SetBlipFlashTimer(blip, 4000)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(L('Tracker: {plate}', { plate = follow.plate or '' }))
  EndTextCommandSetBlipName(blip)
  follow.blip = blip
end

local function report(data)
  TriggerEvent('nz:client:carlock:tracking', data)
end

---------------------------------------------------------------------------------------
-- Server answers
---------------------------------------------------------------------------------------

--- Key ring status from the server: every key (plate nil) or one key with its position.
---@param plate string|nil
---@return table result { ok, data = { now, tracker, vehicles }, error }
function CarLock.trackerStatus(plate)
  local payload = {}
  if plate ~= nil then
    payload.plate = Utils.plate(plate)
    if not payload.plate then return Utils.fail(L('Invalid plate')) end
  end
  return NZ.NUI.await('nz:carlock:tracker', payload)
end

--- Sound (on = true / nil) or silence (on = false) the alarm of a trackable vehicle.
---@param plate string
---@param on boolean|nil nil = toggle
---@return table result { ok, data = { alarm, seconds?, cooldown }, error }
function CarLock.remoteAlarm(plate, on)
  plate = Utils.plate(plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local payload = { plate = plate }
  if on ~= nil then payload.on = on == true end
  return NZ.NUI.await('nz:carlock:trackerAlarm', payload)
end

---------------------------------------------------------------------------------------
-- Locate: waypoint + following blip
---------------------------------------------------------------------------------------

--- Stop following the located vehicle (the waypoint stays).
function CarLock.stopLocate()
  follow.generation = follow.generation + 1
  local plate = follow.plate
  follow.plate, follow.netId = nil, nil
  removeBlip()
  if plate then report({ plate = plate, stopped = true }) end
end

--- Plate of the vehicle being followed, or nil.
---@return string|nil
function CarLock.locating()
  return follow.plate
end

local function startFollow(plate, netId, generation)
  CreateThread(function()
    local misses = 0
    local nextServer = GetGameTimer() + SERVER_STEP
    while follow.generation == generation and GetGameTimer() < follow.untilAt do
      local vehicle = localVehicle(netId)
      local wait = LOCAL_STEP
      if vehicle then
        local pos = GetEntityCoords(vehicle)
        placeBlip(pos.x, pos.y, pos.z)
        report({ plate = plate, distance = math.floor(#(pos - GetEntityCoords(PlayerPedId())) + 0.5), live = true })
        misses = 0
      elseif GetGameTimer() >= nextServer then
        nextServer = GetGameTimer() + SERVER_STEP
        local res = CarLock.trackerStatus(plate)
        if follow.generation ~= generation then return end
        local st = res.ok and type(res.data) == 'table' and type(res.data.vehicles) == 'table' and res.data.vehicles[1] or nil
        if st and st.trackable and type(st.coords) == 'table' then
          misses = 0
          netId = tonumber(st.netId) or netId
          follow.netId = netId
          placeBlip(st.coords.x, st.coords.y, st.coords.z)
          report({ plate = plate, distance = tonumber(st.distance), live = false })
        elseif st and (not st.spawned or st.towing or not st.trackable) then
          -- stored, towed or out of this routing bucket: the signal is gone
          report({ plate = plate, lost = true, towing = st.towing == true })
          removeBlip()
          follow.plate = nil
          return
        else
          misses = misses + 1
          if misses >= LOST_AFTER then
            report({ plate = plate, lost = true })
            removeBlip()
            follow.plate = nil
            return
          end
        end
        wait = 500
      else
        wait = 500
      end
      Wait(wait)
    end
    if follow.generation == generation then
      removeBlip()
      follow.plate = nil
      report({ plate = plate, stopped = true })
    end
  end)
end

--- Locate a trackable vehicle: waypoint + a blip following it. Yields (server round trip).
---@param plate string
---@return table result { ok, data = { distance, netId }, error }
function CarLock.locate(plate)
  plate = Utils.plate(plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local res = CarLock.trackerStatus(plate)
  if not res.ok then return res end
  local st = type(res.data) == 'table' and type(res.data.vehicles) == 'table' and res.data.vehicles[1] or nil
  if type(st) ~= 'table' then return Utils.fail(L('Something went wrong')) end
  if not st.spawned then return Utils.fail(L('The vehicle is not out')) end
  if st.towing then return Utils.fail(L('This vehicle is being towed')) end
  if res.data.tracker == false then return Utils.fail(L('The vehicle tracker is not available')) end
  if not st.trackable or type(st.coords) ~= 'table' then return Utils.fail(L('This vehicle has no tracker')) end

  CarLock.stopLocate()
  follow.plate = plate
  follow.netId = tonumber(st.netId)
  follow.untilAt = GetGameTimer() + Utils.clamp(tonumber(trackerCfg().locateSeconds) or 120, 10, 1800) * 1000
  local x, y, z = tonumber(st.coords.x) or 0.0, tonumber(st.coords.y) or 0.0, tonumber(st.coords.z) or 0.0
  SetNewWaypoint(x + 0.0, y + 0.0)
  placeBlip(x, y, z)
  report({ plate = plate, distance = tonumber(st.distance), live = false })
  startFollow(plate, follow.netId, follow.generation)
  return Utils.ok({ distance = tonumber(st.distance), netId = follow.netId })
end

AddEventHandler('nz:client:playerUnloaded', function() CarLock.stopLocate() end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  removeBlip()
end)
