-----------------------------------------------------------------
-- Scenario dressing: guards, party guests, drivers, chasers
-- All peds are networked so associates and police see the same
-- thing. Their net ids are sent to the server for cleanup.
-----------------------------------------------------------------
Scenarios = {}

local S = Config.Sourcing
local hostile

local function group()
    if hostile then return hostile end
    local _, h = AddRelationshipGroup('NZ_CARGO_HOSTILE')
    hostile = h
    SetRelationshipBetweenGroups(5, hostile, joaat("PLAYER"))
    SetRelationshipBetweenGroups(5, joaat("PLAYER"), hostile)
    SetRelationshipBetweenGroups(0, hostile, hostile)
    return hostile
end

local function pick(list) return list[math.random(1, #list)] end

local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    return ok and gz or z
end

function Scenarios.Ped(model, x, y, z, h)
    local hash = Client.LoadModel(model)
    if not hash then return nil end
    local ped = CreatePed(4, hash, x, y, groundZ(x, y, z), h or 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRandomComponentVariation(ped, 0)
    return ped
end

-- illegal = tougher guards (Config.Sourcing.Guards.Illegal)
local function arm(ped, weapon, illegal)
    local G = S.Guards
    local I = illegal and G.Illegal or nil
    GiveWeaponToPed(ped, joaat(weapon or pick(I and I.Weapons or G.Weapons)), 250, false, true)
    SetPedArmour(ped, I and I.Armour or G.Armour)
    SetPedAccuracy(ped, I and I.Accuracy or G.Accuracy)
    SetPedCombatAttributes(ped, 46, true)   -- always fight
    SetPedCombatAttributes(ped, 5, true)    -- fight armed peds when unarmed
    SetPedCombatAbility(ped, I and 2 or 1)
    SetPedCombatRange(ped, 1)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedRelationshipGroupHash(ped, group())
    SetPedSeeingRange(ped, 35.0)
    SetPedHearingRange(ped, 45.0)
end
Scenarios.Arm = arm

local function ring(center, count, radius)
    local out = {}
    for i = 1, count do
        local a = (i / count) * math.pi * 2 + math.random() * 0.5
        local r = radius + math.random() * 2.0
        out[i] = vec3(center.x + math.cos(a) * r, center.y + math.sin(a) * r, center.z)
    end
    return out
end

-- Armed guards standing around a spot (guarded car, impound, depot, helipad)
function Scenarios.Guards(spot, count, kind, illegal)
    if type(count) == 'string' then kind, count = count, nil end
    if not count then
        local range = S.Guards.Count[kind] or { 2, 4 }
        count = math.random(range[1], range[2])
    end
    local models = kind == 'impound' and S.ImpoundGuardModels or S.Guards.Models
    local peds = {}
    if count < 1 then return peds end
    for _, pos in ipairs(ring(spot, count, 5.0)) do
        local h = GetHeadingFromVector_2d(spot.x - pos.x, spot.y - pos.y) + 180.0
        local ped = Scenarios.Ped(pick(models), pos.x, pos.y, pos.z, h)
        if ped then
            arm(ped, nil, illegal)
            TaskGuardCurrentPosition(ped, 12.0, 12.0, true)
            peds[#peds + 1] = ped
        end
    end
    return peds
end

-- Party guests hanging around the car. One of them has the keys.
local partyScenarios = { 'WORLD_HUMAN_PARTYING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_STAND_MOBILE' }
function Scenarios.Party(spot, count)
    local guests = {}
    for i, pos in ipairs(ring(spot, count, 4.0)) do
        local h = GetHeadingFromVector_2d(spot.x - pos.x, spot.y - pos.y)
        local ped = Scenarios.Ped(pick(S.PartyModels), pos.x, pos.y, pos.z, h)
        if ped then
            SetBlockingOfNonTemporaryEvents(ped, true)
            TaskStartScenarioInPlace(ped, pick(partyScenarios), 0, true)
            guests[#guests + 1] = { ped = ped, index = i }
        end
    end
    return guests
end

-- armed = hand them a pistol first (a guest pulling a gun)
function Scenarios.Anger(ped, armed)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    SetBlockingOfNonTemporaryEvents(ped, false)
    ClearPedTasks(ped)
    if armed then GiveWeaponToPed(ped, joaat('WEAPON_PISTOL'), 60, false, true) SetPedAccuracy(ped, S.Guards.Accuracy) end
    SetPedRelationshipGroupHash(ped, group())
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    TaskCombatPed(ped, cache.ped, 0, 16)
end

-- Hands up and stay put
function Scenarios.Surrender(ped)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    SetBlockingOfNonTemporaryEvents(ped, true)
    ClearPedTasksImmediately(ped)
    TaskHandsUp(ped, -1, cache.ped, -1, true)
    SetPedKeepTask(ped, true)
end

function Scenarios.Flee(ped)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    SetBlockingOfNonTemporaryEvents(ped, false)
    ClearPedTasks(ped)
    SetPedFleeAttributes(ped, 0, true)
    TaskSmartFleePed(ped, cache.ped, 400.0, -1, false, false)
    SetPedKeepTask(ped, true)
end

-- The car's owner. mode 'wander' = strolls around the car, 'guard' = stands by it armed.
function Scenarios.Owner(spot, models, mode, weapon, armour)
    local a = math.random() * math.pi * 2
    local x, y = spot.x + math.cos(a) * 4.0, spot.y + math.sin(a) * 4.0
    local ped = Scenarios.Ped(pick(models), x, y, spot.z, GetHeadingFromVector_2d(spot.x - x, spot.y - y))
    if not ped then return nil end
    if mode == 'wander' then
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        -- short walks with long stops so you can get behind him
        TaskWanderInArea(ped, spot.x, spot.y, spot.z, 14.0, 2.0, 6.0)
    else
        arm(ped, weapon)
        if armour then SetPedArmour(ped, armour) end
        SetPedSeeingRange(ped, S.Hostile.Aggro)
        TaskGuardCurrentPosition(ped, 8.0, 8.0, true)
    end
    return ped
end

-- NPC driver for the moving target
function Scenarios.Driver(vehicle)
    local c = GetEntityCoords(vehicle)
    local ped = Scenarios.Ped(pick(S.PartyModels), c.x, c.y, c.z + 2.0, 0.0)
    if not ped then return nil end
    SetPedIntoVehicle(ped, vehicle, -1)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetDriverAbility(ped, 0.8)
    SetDriverAggressiveness(ped, 0.4)
    TaskVehicleDriveWander(ped, vehicle, 22.0, 786603)
    return ped
end

-- A road spot out of sight, like GTA: never on screen, never right
-- behind you. They come from somewhere you can't see and drive in.
local function headingTo(from, to)
    return (math.deg(math.atan(-(to.x - from.x), to.y - from.y))) % 360
end

local function hiddenRoad(used)
    local cfg = Config.Attackers.Spawn
    local p = GetEntityCoords(cache.ped)
    for _ = 1, 40 do
        local a = math.random() * math.pi * 2
        local d = cfg.Min + math.random() * (cfg.Max - cfg.Min)
        local ok, node, nodeHeading = GetClosestVehicleNodeWithHeading(p.x + math.cos(a) * d, p.y + math.sin(a) * d, p.z, 1, 3.0, 0)
        if ok then
            local dist = #(node - p)
            local clear = dist >= cfg.Min * 0.8 and math.abs(node.z - p.z) < 30.0
                and not IsSphereVisible(node.x, node.y, node.z + 1.0, 5.0)
            for _, u in ipairs(used) do if #(u - node) < 12.0 then clear = false end end
            if clear then
                -- drive the way that points at you
                local want = headingTo(node, p)
                local h1, h2 = nodeHeading % 360, (nodeHeading + 180.0) % 360
                local function diff(h) local x = math.abs(h - want) % 360 return x > 180 and 360 - x or x end
                return node, diff(h1) <= diff(h2) and h1 or h2
            end
        end
    end
    -- nothing hidden found: far behind you on the road
    local back = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, -cfg.Max, 0.0)
    local ok, node, heading = GetClosestVehicleNodeWithHeading(back.x, back.y, back.z, 1, 3.0, 0)
    if ok then return node, heading end
    return back, GetEntityHeading(cache.ped)
end

-- Chase cars. mode 'shoot' = passengers fire, 'ram' = drivers try to ram
function Scenarios.Chasers(cfg, count, mode)
    local made, used = {}, {}
    for _ = 1, count do
        local pos, heading = hiddenRoad(used)
        used[#used + 1] = pos
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        local vhash = Client.LoadModel(pick(cfg.Vehicles))
        if vhash then
            local veh = CreateVehicle(vhash, pos.x, pos.y, pos.z + 0.5, heading, true, true)
            SetVehicleOnGroundProperly(veh)
            SetModelAsNoLongerNeeded(vhash)
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleEngineOn(veh, true, true, false)
            local driver = Scenarios.Ped(pick(cfg.Peds), pos.x, pos.y, pos.z + 2.0, heading)
            if driver then
                SetPedIntoVehicle(driver, veh, -1)
                arm(driver, cfg.Weapons and pick(cfg.Weapons) or 'WEAPON_MICROSMG')
                SetDriverAbility(driver, 1.0)
                SetDriverAggressiveness(driver, 1.0)
                if mode == 'ram' then
                    TaskVehicleMissionPedTarget(driver, veh, cache.ped, 2, 60.0, 1074528293, 1.0, 1.0, true)
                else
                    TaskVehicleChase(driver, cache.ped)
                end
                made[#made + 1] = driver
            end
            if mode ~= 'ram' then
                local gunner = Scenarios.Ped(pick(cfg.Peds), pos.x, pos.y, pos.z + 2.0, heading)
                if gunner then
                    SetPedIntoVehicle(gunner, veh, 0)
                    arm(gunner, cfg.Weapons and pick(cfg.Weapons) or 'WEAPON_MICROSMG')
                    TaskCombatPed(gunner, cache.ped, 0, 16)
                    made[#made + 1] = gunner
                end
            end
            local b = AddBlipForEntity(veh)
            SetBlipSprite(b, 225)
            SetBlipColour(b, 1)
            made[#made + 1] = veh
        end
    end
    return made
end

-- Is anything we spawned actively fighting the player?
function Scenarios.InCombat(peds)
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) and IsPedInCombat(ped, cache.ped) then return true end
    end
    return false
end

function Scenarios.NetIds(list)
    local out = {}
    for _, e in ipairs(list) do
        if DoesEntityExist(e) and NetworkGetEntityIsNetworked(e) then out[#out + 1] = NetworkGetNetworkIdFromEntity(e) end
    end
    return out
end

function Scenarios.Release(list)
    for _, e in ipairs(list) do
        if DoesEntityExist(e) then
            if IsEntityAPed(e) then SetPedAsNoLongerNeeded(e) else SetEntityAsNoLongerNeeded(e) end
        end
    end
end
