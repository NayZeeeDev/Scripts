-- Dense traffic: native density + scripted top-up ahead of the player, AI lane changes.
Traffic = { owned = {} }
CU.Meta = {}                         -- per NPC vehicle: cruise, personality, lane change, awareness state

local MANEUVER_STYLE = 786468        -- avoid vehicles + objects while changing lanes
local spawnCount, lastLaneRoll = 0, 0

local function loadModel(name)
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    return hash
end

function Traffic.Meta(veh)
    local m = CU.Meta[veh]
    if not m then
        local a = Config.Awareness
        m = {
            cruise = math.max(GetEntitySpeed(veh), Config.Traffic.CruiseMin),
            personality = Util.WeightedPick(a.Personalities),
            laneUntil = 0, changing = false, noticed = false, reactAt = 0, reacted = false,
            lastHorn = 0, hitAt = 0, seen = GetGameTimer(),
        }
        CU.Meta[veh] = m
    end
    m.seen = GetGameTimer()
    return m
end

local function controlled(ent)
    if not NetworkGetEntityIsNetworked(ent) then return true end
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    return false
end
Traffic.Controlled = controlled

function Traffic.Wander(veh, driver, cruise)
    SetVehicleIndicatorLights(veh, 0, false)
    SetVehicleIndicatorLights(veh, 1, false)
    TaskVehicleDriveWander(driver, veh, cruise, Config.Traffic.DriveStyle)
    SetDriveTaskCruiseSpeed(driver, cruise)
end

---------------------------------------------------------------------------
-- density (every frame)
---------------------------------------------------------------------------
function Traffic.TickDensity()
    local d = math.min(1.0, Config.Traffic.AmbientDensity * math.max(0.4, CU.Settings.gameplay.density))
    SetVehicleDensityMultiplierThisFrame(d)
    SetRandomVehicleDensityMultiplierThisFrame(d)
    SetParkedVehicleDensityMultiplierThisFrame(Config.Traffic.ParkedDensity)
    SetAmbientVehicleRangeMultiplierThisFrame(1.5)
end

---------------------------------------------------------------------------
-- nearby scan (every 250 ms) - shared with scoring + awareness
---------------------------------------------------------------------------
function Traffic.Scan()
    local list = {}
    local veh = CU.Veh
    if veh == 0 then CU.NearbyNPC = list return end
    local pos = GetEntityCoords(veh)
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= veh then
            local p = GetEntityCoords(v)
            local dist = #(p - pos)
            if dist < 90.0 then
                local driver = GetPedInVehicleSeat(v, -1)
                if driver ~= 0 and not IsPedAPlayer(driver) and not IsEntityDead(driver) then
                    list[#list + 1] = { veh = v, driver = driver, dist = dist }
                end
            end
        end
    end
    CU.NearbyNPC = list
end

---------------------------------------------------------------------------
-- lane changes
---------------------------------------------------------------------------
local function laneBlocked(veh, dir, ahead)
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= veh then
            local p = GetEntityCoords(v)
            local lo = GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
            local side = lo.x * dir
            if side > 1.2 and side < 6.0 and lo.y > -12.0 and lo.y < ahead * 0.8 then
                return true
            end
        end
    end
    return false
end

-- dir: -1 = left, 1 = right
function Traffic.ChangeLane(veh, dir)
    if not DoesEntityExist(veh) then return false end
    local m = Traffic.Meta(veh)
    local now = GetGameTimer()
    if m.changing or now < m.laneUntil + 1500 or now < m.hitAt + 6000 then return false end
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver == 0 or IsPedAPlayer(driver) then return false end
    if not controlled(veh) or not controlled(driver) then return false end

    local lc = Config.Traffic.LaneChange
    local speed = math.max(GetEntitySpeed(veh), 8.0)
    local ahead = math.max(lc.Lookahead, speed * 1.3)
    local target = GetOffsetFromEntityInWorldCoords(veh, dir * lc.LaneWidth, ahead, 0.0)
    if not IsPointOnRoad(target.x, target.y, target.z, veh) then return false end
    local ok, _, nodeHeading = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 1, 3.0, 0)
    if ok and math.abs(Util.AngleDiff(nodeHeading, GetEntityHeading(veh))) > 60.0 then return false end
    if laneBlocked(veh, dir, ahead) then return false end

    SetVehicleIndicatorLights(veh, dir < 0 and 1 or 0, true)
    TaskVehicleDriveToCoord(driver, veh, target.x, target.y, target.z, speed, 0, GetEntityModel(veh), MANEUVER_STYLE, 3.0, true)
    m.changing = true
    m.laneUntil = now + math.floor(lc.Duration * 1000)
    return true
end

local function finishLaneChanges()
    local now = GetGameTimer()
    for veh, m in pairs(CU.Meta) do
        if not DoesEntityExist(veh) then
            CU.Meta[veh] = nil
        elseif m.changing and now > m.laneUntil then
            local driver = GetPedInVehicleSeat(veh, -1)
            if driver ~= 0 and not IsPedAPlayer(driver) and controlled(driver) then
                Traffic.Wander(veh, driver, m.cruise)
            end
            m.changing = false
        elseif now - m.seen > 30000 and not Traffic.owned[veh] then
            CU.Meta[veh] = nil
        end
    end
end

local function randomLaneChanges()
    local lc = Config.Traffic.LaneChange
    if not lc.Enabled then return end
    local now = GetGameTimer()
    if now - lastLaneRoll < lc.Interval * 1000 then return end
    lastLaneRoll = now
    if math.random() > lc.Chance then return end
    -- prefer cars ahead of the player so lines open / close in front of you
    local candidates = {}
    for _, n in ipairs(CU.NearbyNPC) do
        if n.dist > 25.0 then
            local p = GetEntityCoords(n.veh)
            local lo = GetOffsetFromEntityGivenWorldCoords(CU.Veh, p.x, p.y, p.z)
            if lo.y > 20.0 then candidates[#candidates + 1] = n.veh end
        end
    end
    if #candidates == 0 then return end
    local v = candidates[math.random(#candidates)]
    if not Traffic.ChangeLane(v, math.random() < 0.5 and -1 or 1) then
        Traffic.ChangeLane(v, math.random() < 0.5 and -1 or 1)
    end
end

---------------------------------------------------------------------------
-- spawning
---------------------------------------------------------------------------
local function findSpawn()
    local veh = CU.Veh
    local pos = GetEntityCoords(veh)
    local fwd = GetEntityForwardVector(veh)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local myHeading = GetEntityHeading(veh)
    local t = Config.Traffic
    local wantSame = math.random() < t.SameDirection
    for _ = 1, 8 do
        local dist = t.SpawnMin + math.random() * (t.SpawnMax - t.SpawnMin) + math.min(CU.Speed * 1.5, 120.0)
        local p = pos + fwd * dist + right * ((math.random() - 0.5) * 24.0)
        local ok, node, heading = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 1, 3.0, 0)
        if ok and #(node - pos) > t.SpawnMin * 0.8 then
            local same = math.abs(Util.AngleDiff(heading, myHeading)) < 90.0
            if same == wantSame and not IsAnyVehicleNearPoint(node.x, node.y, node.z, 8.0) then
                return node, heading
            end
        end
    end
    return nil
end

local function pick(list) return list[math.random(#list)] end

local function spawnOne()
    local node, heading = findSpawn()
    if not node then return end
    local t = Config.Traffic
    local modelName = math.random() < t.TruckChance and pick(t.Models.trucks) or pick(t.Models.cars)
    local model = loadModel(modelName)
    local pedModel = loadModel(pick(t.Models.drivers))
    if not model or not pedModel then return end

    local veh = CreateVehicle(model, node.x, node.y, node.z + 0.4, heading, t.Networked, false)
    if veh == 0 then return end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(veh, false)
    SetVehicleDoorsLocked(veh, 2)
    local ped = CreatePedInsideVehicle(veh, 26, pedModel, -1, t.Networked, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
    SetPedCanBeDraggedOut(ped, false)

    local cruise = t.CruiseMin + math.random() * (t.CruiseMax - t.CruiseMin)
    if modelName == 'pounder' or modelName == 'packer' or modelName == 'biff' or modelName == 'flatbed' then
        cruise = cruise * 0.82
    end
    Traffic.Wander(veh, ped, cruise)
    SetVehicleForwardSpeed(veh, cruise * 0.9)
    if t.Networked then
        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), true)
    end

    local m = Traffic.Meta(veh)
    m.cruise = cruise
    Traffic.owned[veh] = { ped = ped, born = GetGameTimer(), frozen = false }
    if not HasCollisionLoadedAroundEntity(veh) then
        FreezeEntityPosition(veh, true)
        Traffic.owned[veh].frozen = true
    end
    SetModelAsNoLongerNeeded(model)
    SetModelAsNoLongerNeeded(pedModel)
    spawnCount = spawnCount + 1
end

local function release(veh, data)
    if DoesEntityExist(veh) and controlled(veh) then
        if data.ped and DoesEntityExist(data.ped) then DeleteEntity(data.ped) end
        DeleteEntity(veh)
    elseif DoesEntityExist(veh) then
        SetEntityAsNoLongerNeeded(veh)
        if data.ped and DoesEntityExist(data.ped) then SetEntityAsNoLongerNeeded(data.ped) end
    end
    Traffic.owned[veh] = nil
    CU.Meta[veh] = nil
end

function Traffic.Clear()
    for veh, data in pairs(Traffic.owned) do release(veh, data) end
end

local function targetCount()
    local t = Config.Traffic
    return math.min(t.MaxCars, math.floor(t.ExtraCars * CU.Settings.gameplay.density + 0.5))
end

-- every 500 ms while in CUT UP mode
function Traffic.Manage()
    local veh = CU.Veh
    if veh == 0 then return end
    local t = Config.Traffic
    local pos = GetEntityCoords(veh)

    -- cleanup
    for v, data in pairs(Traffic.owned) do
        if not DoesEntityExist(v) or IsEntityDead(v) then
            release(v, data)
        else
            local p = GetEntityCoords(v)
            local lo = GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
            local driver = GetPedInVehicleSeat(v, -1)
            if #(p - pos) > t.DespawnRadius or lo.y < -t.DespawnBehind or driver == 0 or IsPedAPlayer(driver) then
                release(v, data)
            elseif data.frozen and HasCollisionLoadedAroundEntity(v) then
                FreezeEntityPosition(v, false)
                SetVehicleForwardSpeed(v, Traffic.Meta(v).cruise * 0.9)
                data.frozen = false
            end
        end
    end

    -- count every NPC car ahead of us (other players' traffic included, so crews don't stack traffic)
    if CU.Speed < 8.0 then return end
    local ahead = 0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= veh then
            local driver = GetPedInVehicleSeat(v, -1)
            if driver ~= 0 and not IsPedAPlayer(driver) then
                local p = GetEntityCoords(v)
                if #(p - pos) < t.SpawnMax + 60.0 then
                    local lo = GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
                    if lo.y > -40.0 then ahead = ahead + 1 end
                end
            end
        end
    end
    local need = targetCount() - ahead
    for _ = 1, math.min(2, need) do spawnOne() end
end

function Traffic.Update()
    finishLaneChanges()
    randomLaneChanges()
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Traffic.Clear() end
end)
