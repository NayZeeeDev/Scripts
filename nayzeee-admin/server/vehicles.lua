local function vt() return Bridge.VT() end

local function randomPlate()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
    for _ = 1, 20 do
        local p = ''
        for _ = 1, 8 do local i = math.random(1, #chars); p = p .. chars:sub(i, i) end
        if not Bridge.PlateTaken(p) then return p end
    end
    return tostring(os.time()):sub(-8)
end

local function trimPlate(p) return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local function occupants(veh)
    local out = {}
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then
            local owner = NetworkGetEntityOwner(ped)
            if owner and owner > 0 then out[#out + 1] = { id = owner, name = GetPlayerName(owner), seat = seat } end
        end
    end
    return out
end

-- ─── spawn / give ───────────────────────────────────────────────────────
NZ.Route('vehicles:spawn', 'vehicles.spawn', function(src, d)
    d.model = NZ.Trim(d.model, 64); if d.model == '' then return false, 'Enter a model.' end
    local tid = tonumber(d.id) or src
    if tid ~= src then
        local ok, err = NZ.Target(src, tid); if not ok then return false, err end
        TriggerClientEvent('nzadmin:cl:do', tid, 'spawnVehicle', { model = d.model, maxed = d.maxed })
    else
        TriggerClientEvent('nzadmin:cl:do', src, 'spawnVehicle', { model = d.model, maxed = d.maxed, keep = d.keep })
    end
    NZ.Log('staff', 'spawn_vehicle', src, tid ~= src and tid or nil, 'spawned ' .. tostring(d.model))
    return true
end)

NZ.Route('vehicles:give', 'vehicles.give', function(src, d)
    local tid, err = NZ.Target(src, d.id or src, false); if not tid then return false, err end
    if Bridge.fw == 'standalone' then return false, 'Owned vehicles need ESX or QBCore.' end
    d.model = NZ.Trim(d.model, 64):lower(); if d.model == '' then return false, 'Enter a model.' end
    local plate = NZ.Trim(d.plate or '', 8):upper()
    if plate == '' then plate = randomPlate() elseif Bridge.PlateTaken(plate) then return false, 'That plate is taken.' end
    local props = d.props
    if not props and d.maxed then props = { modEngine = 3, modBrakes = 2, modTransmission = 2, modSuspension = 3, modArmor = 4, modTurbo = true } end
    Bridge.GiveOwnedVehicle(tid, d.model, plate, props)
    if d.spawn then TriggerClientEvent('nzadmin:cl:do', tid, 'spawnVehicle', { model = d.model, plate = plate, maxed = d.maxed, keys = true }) end
    NZ.Log('staff', 'give_vehicle', src, tid, ('gave %s [%s]'):format(d.model, plate))
    return plate
end)

--- /admincar: save the vehicle you sit in to your own garage
RegisterNetEvent('nzadmin:sv:admincar', function(props, model)
    local src = source
    if not NZ.HasPerm(src, 'vehicles.give') then return end
    if Bridge.fw == 'standalone' or type(props) ~= 'table' then return end
    model = NZ.Trim(model, 64); if model == '' then return end
    local plate = trimPlate(props.plate)
    if plate == '' or Bridge.PlateTaken(plate) then plate = randomPlate() end
    props.plate = plate
    Bridge.GiveOwnedVehicle(src, model, plate, props)
    NZ.Notify(src, ('Saved to your garage with plate %s.'):format(plate), 'success')
    NZ.Log('staff', 'admincar', src, nil, ('saved %s [%s]'):format(model, plate))
    TriggerClientEvent('nzadmin:cl:do', src, 'setPlate', { plate = plate })
end)

-- ─── world vehicles ─────────────────────────────────────────────────────
NZ.Route('vehicles:world', 'vehicles.view', function(src)
    local out, me = {}, GetEntityCoords(GetPlayerPed(src))
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) then
            local c = GetEntityCoords(veh)
            out[#out + 1] = {
                net = NetworkGetNetworkIdFromEntity(veh), hash = GetEntityModel(veh), plate = trimPlate(GetVehicleNumberPlateText(veh)),
                x = NZ.Round(c.x, 1), y = NZ.Round(c.y, 1), z = NZ.Round(c.z, 1), dist = math.floor(#(c - me)),
                engine = math.floor(GetVehicleEngineHealth(veh)), body = math.floor(GetVehicleBodyHealth(veh)),
                locked = GetVehicleDoorLockStatus(veh) >= 2, occupants = occupants(veh),
            }
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end)

local function worldVeh(net)
    local veh = NetworkGetEntityFromNetworkId(tonumber(net) or 0)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    return veh
end

NZ.Route('vehicles:world:action', false, function(src, d)
    local veh = worldVeh(d.net); if not veh then return false, 'Vehicle is gone.' end
    local a = d.action
    local need = ({ despawn = 'vehicles.despawn', repair = 'vehicles.repair', unlock = 'vehicles.unlock_doors', ['goto'] = 'self.teleport', plate = 'vehicles.set_plate', keys = 'vehicles.give_key', max = 'vehicles.set_mods', flip = 'vehicles.repair' })[a]
    if not need or not NZ.HasPerm(src, need) then return false, 'No permission.' end
    if a == 'despawn' then
        for _, o in ipairs(occupants(veh)) do TriggerClientEvent('nzadmin:cl:do', o.id, 'leaveVehicle') end
        DeleteEntity(veh)
    elseif a == 'goto' then
        local c = GetEntityCoords(veh)
        NZ.Teleport(src, { x = c.x, y = c.y, z = c.z + 2.0 })
    elseif a == 'keys' then
        local to = tonumber(d.to) or src
        if not GetPlayerName(to) then return false, 'That player is not online.' end
        TriggerClientEvent('nzadmin:cl:do', to, 'giveKeys', { net = tonumber(d.net) })
    else
        local plate = a == 'plate' and NZ.Trim(d.plate, 8):upper() or nil
        if a == 'plate' and (plate == '' or Bridge.PlateTaken(plate)) then return false, 'Plate is empty or taken.' end
        -- the entity owner applies it. Never broadcast (-1) when the vehicle has no owner.
        local owner = NetworkGetEntityOwner(veh)
        if not owner or owner <= 0 or not GetPlayerName(owner) then owner = src end
        TriggerClientEvent('nzadmin:cl:do', owner, 'vehicleNet', { net = tonumber(d.net), action = a, plate = plate })
    end
    NZ.Log('staff', 'vehicle_' .. a, src, nil, ('%s on %s'):format(a, (GetVehicleNumberPlateText(veh) or '?')))
    return true
end)

local wiping = false
NZ.Route('vehicles:wipe', 'vehicles.force_wipe', function(src, d)
    if wiping then return false, 'A wipe is already running.' end
    wiping = true
    local total = Config.VehicleWipe.Countdown[1] or 30
    NZ.Log('staff', 'vehicle_wipe', src, nil, ('started a vehicle wipe (%ds)'):format(total))
    CreateThread(function()
        local marks = {}
        for _, s in ipairs(Config.VehicleWipe.Countdown) do marks[s] = true end
        for left = total, 1, -1 do
            if marks[left] then
                NZ.Announce(src, { title = 'Vehicle wipe', message = ('Unoccupied vehicles will be removed in %d seconds.'):format(left), seconds = 6, kind = 'warning', anonymous = true })
            end
            Wait(1000)
        end
        local owned = {}
        if Config.VehicleWipe.SkipOwned and Bridge.fw ~= 'standalone' then
            local v = vt()
            for _, r in ipairs(MySQL.query.await(('SELECT `%s` AS plate FROM `%s`'):format(v.plate, v.table)) or {}) do owned[trimPlate(r.plate)] = true end
        end
        local n = 0
        for _, veh in ipairs(GetAllVehicles()) do
            local plate = trimPlate(GetVehicleNumberPlateText(veh))
            local skip = (Config.VehicleWipe.SkipOccupied and #occupants(veh) > 0) or owned[plate]
            if not skip then DeleteEntity(veh); n = n + 1 end
        end
        wiping = false
        NZ.Announce(src, { title = 'Vehicle wipe', message = ('%d vehicles removed.'):format(n), seconds = 5, anonymous = true })
    end)
    return true
end)

-- ─── owned vehicle database ─────────────────────────────────────────────
NZ.Route('vehicles:db', 'vehicles_database.view', function(src, d)
    if Bridge.fw == 'standalone' then return {} end
    local v = vt()
    local q = '%' .. (d.search or '') .. '%'
    local rows
    if Bridge.fw == 'esx' then
        rows = MySQL.query.await(([[SELECT v.`%s` AS plate, v.`%s` AS owner, v.`%s` AS props, v.`%s` AS stored, CONCAT(u.firstname, ' ', u.lastname) AS owner_name
            FROM `%s` v LEFT JOIN users u ON u.identifier = v.`%s` WHERE v.`%s` LIKE ? OR v.`%s` LIKE ? OR CONCAT(u.firstname, ' ', u.lastname) LIKE ? LIMIT 150]]):format(
            v.plate, v.owner, v.props, v.stored, v.table, v.owner, v.plate, v.owner), { q, q, q }) or {}
        for _, r in ipairs(rows) do local p = json.decode(r.props or '{}') or {}; r.hash = p.model; r.props = nil end
    else
        rows = MySQL.query.await(([[SELECT v.`%s` AS plate, v.`%s` AS owner, v.`%s` AS model, v.`%s` AS stored, v.`%s` AS garage,
            CONCAT(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))) AS owner_name
            FROM `%s` v LEFT JOIN players p ON p.citizenid = v.`%s` WHERE v.`%s` LIKE ? OR v.`%s` LIKE ? OR v.`%s` LIKE ? LIMIT 150]]):format(
            v.plate, v.owner, v.model, v.stored, v.garage, v.table, v.owner, v.plate, v.owner, v.model), { q, q, q }) or {}
    end
    return rows
end)

NZ.Route('vehicles:db:action', false, function(src, d)
    if Bridge.fw == 'standalone' then return false end
    local v = vt()
    local plate = NZ.Trim(d.plate, 8)
    if plate == '' then return false, 'Missing plate.' end
    local a = d.action
    if a == 'owner' then
        if not NZ.HasPerm(src, 'vehicles.set_owner') then return false, 'No permission.' end
        local owner = NZ.Trim(d.owner, 64)
        local license
        if tonumber(owner) and GetPlayerName(tonumber(owner)) then
            license = NZ.License(tonumber(owner))
            owner = Bridge.CharId(tonumber(owner))
        end
        if not owner or owner == '' then return false, 'Enter a player ID or character identifier.' end
        if Bridge.fw ~= 'esx' and v.license then
            if not license then -- offline citizenid: take the license from the players table
                local row = MySQL.single.await('SELECT license FROM players WHERE citizenid = ?', { owner })
                if not row then return false, 'No character with that citizen ID.' end
                license = row.license
            end
            MySQL.update.await(('UPDATE `%s` SET `%s` = ?, `%s` = ? WHERE `%s` = ?'):format(v.table, v.owner, v.license, v.plate), { owner, license, plate })
        else
            MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(v.table, v.owner, v.plate), { owner, plate })
        end
    elseif a == 'plate' then
        if not NZ.HasPerm(src, 'vehicles.set_plate') then return false, 'No permission.' end
        local np = NZ.Trim(d.newPlate, 8):upper()
        if np == '' or Bridge.PlateTaken(np) then return false, 'Plate is empty or taken.' end
        -- the plate lives in the props json too, keep both in sync
        local row = MySQL.single.await(('SELECT `%s` AS props FROM `%s` WHERE `%s` = ?'):format(v.props, v.table, v.plate), { plate })
        if not row then return false, 'Vehicle not found.' end
        local ok, p = pcall(json.decode, row.props or '{}')
        p = ok and type(p) == 'table' and p or {}
        p.plate = np
        MySQL.update.await(('UPDATE `%s` SET `%s` = ?, `%s` = ? WHERE `%s` = ?'):format(v.table, v.plate, v.props, v.plate), { np, json.encode(p), plate })
    elseif a == 'garage' then
        if not NZ.HasPerm(src, 'vehicles.send_to_garage') then return false, 'No permission.' end
        MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(v.table, v.stored, v.plate), { v.storedValue, plate })
        for _, veh in ipairs(GetAllVehicles()) do
            if trimPlate(GetVehicleNumberPlateText(veh)) == plate and #occupants(veh) == 0 then DeleteEntity(veh) end
        end
    elseif a == 'delete' then
        if not NZ.HasPerm(src, 'vehicles.remove') then return false, 'No permission.' end
        MySQL.update.await(('DELETE FROM `%s` WHERE `%s` = ?'):format(v.table, v.plate), { plate })
    else return false end
    NZ.Log('staff', 'owned_vehicle_' .. a, src, nil, ('%s on plate %s %s'):format(a, plate, d.newPlate or d.owner or ''))
    return true
end)
