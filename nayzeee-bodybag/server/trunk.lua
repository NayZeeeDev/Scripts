-- ═══════════════════════════════════════════════════════════════
--  VEHICLE TRUNKS - load a carried body bag into a car, take it out later
--  Trunks[vehNetId] = { veh, items = { { kind, body }, ... } }
-- ═══════════════════════════════════════════════════════════════

local function updateTrunkState(vehNetId)
    local t = Trunks[vehNetId]
    if not t then return end
    if #t.items == 0 then
        Trunks[vehNetId] = nil
        if DoesEntityExist(t.veh) then Entity(t.veh).state:set('nzTrunk', nil, true) end
    elseif DoesEntityExist(t.veh) then
        Entity(t.veh).state:set('nzTrunk', #t.items, true)
    end
end

local function getVehicle(vehNetId)
    local veh = EntityFromNet(vehNetId)
    if not veh or GetEntityType(veh) ~= 2 then return nil end
    return veh
end

-- used by server/main.lua when a victim gets revived inside a trunk
function RemoveFromTrunk(vehNetId, body)
    local t = Trunks[vehNetId]
    if not t then return end
    for i, item in ipairs(t.items) do
        if item.body == body then
            table.remove(t.items, i)
            break
        end
    end
    updateTrunkState(vehNetId)
end

-- called every 2s by the watchdog in server/main.lua
function SyncTrunks(syncVictim)
    for vehNetId, t in pairs(Trunks) do
        if not DoesEntityExist(t.veh) then
            -- car was deleted / impounded -> the bodies are found, victims released
            Trunks[vehNetId] = nil
            for _, item in ipairs(t.items) do ReleaseBody(item.body) end
            Log(nil, 'TRUNK_LOST', ('vehicle with %d body(s) vanished, victims released'):format(#t.items))
        else
            local coords = GetEntityCoords(t.veh)
            for _, item in ipairs(t.items) do syncVictim(item.body, coords) end
        end
    end
end

-- carried bag -> trunk
lib.callback.register('nayzeee-bodybag:trunkPut', function(src, vehNetId, bagNetId)
    if not Config.Trunk.Enabled then return false end
    local c = Containers[bagNetId]
    if not c or c.carrier ~= src or not Config.Trunk.AllowedKinds[c.kind] then return false end
    local veh = getVehicle(vehNetId)
    if not veh or not IsNearEntity(src, veh, 8.0) then return false end

    local t = Trunks[vehNetId] or { veh = veh, items = {} }
    if #t.items >= Config.Trunk.MaxBodies then
        Notify(src, 'The trunk is full', 'error')
        return false
    end

    RemoveContainer(bagNetId)
    AddDna(c.body, src)
    t.items[#t.items + 1] = { kind = c.kind, body = c.body }
    c.body.where = { type = 'trunk', key = vehNetId }
    Trunks[vehNetId] = t
    updateTrunkState(vehNetId)
    Log(src, 'TRUNK_IN', ('%s -> plate %s'):format(c.body.name or 'NPC', GetVehicleNumberPlateText(veh)))
    return true
end)

-- trunk -> ground behind the car
RegisterNetEvent('nayzeee-bodybag:server:trunkTake', function(vehNetId)
    local src = source
    local t = Trunks[vehNetId]
    if not t or #t.items == 0 or not IsNearEntity(src, t.veh, 8.0) then return end

    local item = table.remove(t.items)
    updateTrunkState(vehNetId)

    -- 2.5m behind the car
    local coords, heading = GetEntityCoords(t.veh), GetEntityHeading(t.veh)
    local rad = math.rad(heading)
    local behind = coords - vector3(-math.sin(rad), math.cos(rad), 0.0) * 2.5

    local obj, netId = SpawnProp(item.kind, behind, heading)
    if not obj then
        ReleaseBody(item.body)
        return Notify(src, 'Something went wrong - the body rolled away', 'error')
    end
    AddDna(item.body, src)
    AddContainer(obj, netId, item.kind, item.body)
    Log(src, 'TRUNK_OUT', item.body.name or 'NPC')
end)

-- police: what's in this trunk?
lib.callback.register('nayzeee-bodybag:trunkSearch', function(src, vehNetId)
    if not Config.Trunk.PoliceCanSearch or not IsPolice(src) then return nil end
    local t = Trunks[vehNetId]
    if not t or not IsNearEntity(src, t.veh, 8.0) then return {} end
    local list = {}
    for _, item in ipairs(t.items) do list[#list + 1] = DescribeBody(item.body, true) end
    Log(src, 'TRUNK_SEARCHED', ('%d body(s) found'):format(#list))
    return list
end)
