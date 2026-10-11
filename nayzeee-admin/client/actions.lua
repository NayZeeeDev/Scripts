-- Things staff do TO a player. Everything here is event driven, nothing ticks unless a state needs it.
local Do = {}

local function loadModel(model)
    model = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(model) then return false end
    return lib.requestModel(model, 10000) and model or false
end

Do.heal = function()
    SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    ClearPedBloodDamage(cache.ped)
    Notify('You were healed by staff.', 'success')
end

Do.armour = function() SetPedArmour(cache.ped, 100) end

Do.kill = function() SetEntityHealth(cache.ped, 0) end

Do.slap = function()
    local ped = cache.ped
    SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
    ApplyForceToEntity(ped, 1, math.random(-8, 8) + 0.0, math.random(-8, 8) + 0.0, 12.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
    SetEntityHealth(ped, math.max(101, GetEntityHealth(ped) - 10))
end

Do.ragdoll = function() SetPedToRagdoll(cache.ped, 4000, 4000, 0, false, false, false) end

Do.burn = function() StartEntityFire(cache.ped) end

Do.explode = function()
    local c = GetEntityCoords(cache.ped)
    AddExplosion(c.x, c.y, c.z, 2, 4.0, true, false, 1.0)
end

Do.unarm = function() RemoveAllPedWeapons(cache.ped, true) end

Do.nativeRevive = function()
    local ped = cache.ped
    local c = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    ClearPedTasksImmediately(PlayerPedId())
    SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
    ClearPedBloodDamage(PlayerPedId())
end

-- freeze
local frozen, frozenEnt = false, nil
Do.freeze = function(d)
    local was = frozen
    frozen = d.state == true
    if frozen then frozenEnt = cache.vehicle or cache.ped; FreezeEntityPosition(frozenEnt, true)
    else
        if frozenEnt and DoesEntityExist(frozenEnt) then FreezeEntityPosition(frozenEnt, false) end
        FreezeEntityPosition(cache.ped, false)
        frozenEnt = nil
    end
    if frozen and was then return end -- loop already running
    if frozen then
        Notify('You have been frozen by staff.', 'warning')
        CreateThread(function()
            while frozen do
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
                DisableControlAction(0, 75, true); DisableControlAction(0, 23, true)
                Wait(0)
            end
        end)
    else
        Notify('You were unfrozen.', 'info')
    end
end

-- cuff
local cuffed = false
Do.cuff = function(d)
    local was = cuffed
    cuffed = d.state == true
    local ped = cache.ped
    if cuffed and was then return end
    if cuffed then
        lib.requestAnimDict('mp_arresting')
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        SetEnableHandcuffs(ped, true)
        CreateThread(function()
            while cuffed do
                local p = cache.ped
                if not IsEntityPlayingAnim(p, 'mp_arresting', 'idle', 3) then
                    TaskPlayAnim(p, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
                end
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true); DisableControlAction(0, 23, true); DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true); DisableControlAction(0, 140, true); DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true); DisableControlAction(0, 257, true); DisableControlAction(0, 263, true)
                Wait(0)
            end
        end)
    else
        SetEnableHandcuffs(ped, false)
        ClearPedTasks(ped)
        RemoveAnimDict('mp_arresting')
    end
end

Do.setPed = function(d)
    local m = loadModel(d.model)
    if not m then return Notify('Invalid ped model.', 'error') end
    local health, armour = GetEntityHealth(cache.ped), GetPedArmour(cache.ped)
    SetPlayerModel(cache.playerId, m)
    SetPedDefaultComponentVariation(PlayerPedId())
    SetModelAsNoLongerNeeded(m)
    SetEntityHealth(PlayerPedId(), health)
    SetPedArmour(PlayerPedId(), armour)
end

Do.resetPed = function() Bridge.ReloadSkin() end

Do.clothing = function() if UI.open then CloseUI() end Bridge.OpenClothing() end

Do.giveWeapon = function(d)
    local w = joaat(tostring(d.weapon):upper())
    if not IsWeaponValid(w) then return Notify('Invalid weapon: ' .. tostring(d.weapon), 'error') end
    GiveWeaponToPed(cache.ped, w, math.floor(tonumber(d.ammo) or 250), false, true)
end

Do.back = function() if LastPos then TeleportTo(LastPos.x, LastPos.y, LastPos.z) end end

Do.leaveVehicle = function()
    if cache.vehicle then TaskLeaveVehicle(cache.ped, cache.vehicle, 16) end
end

Do.seatIn = function(d)
    local veh = NetworkDoesNetworkIdExist(d.net) and NetToVeh(d.net)
    if not veh or veh == 0 then return end
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        if IsVehicleSeatFree(veh, seat) then SetPedIntoVehicle(cache.ped, veh, seat); return end
    end
    Notify('No free seat.', 'error')
end

-- vehicles
local function maxOut(veh)
    SetVehicleModKit(veh, 0)
    for mod = 0, 49 do
        local n = GetNumVehicleMods(veh, mod)
        if n > 0 then SetVehicleMod(veh, mod, n - 1, false) end
    end
    ToggleVehicleMod(veh, 18, true)
    ToggleVehicleMod(veh, 22, true)
    SetVehicleWindowTint(veh, 1)
    SetVehicleTyresCanBurst(veh, false)
end

local spawned = {}
Do.spawnVehicle = function(d)
    local m = loadModel(d.model)
    if not m or not IsModelAVehicle(m) then return Notify('Unknown vehicle model: ' .. tostring(d.model), 'error') end
    local ped = cache.ped
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    if cache.vehicle and not d.keep then
        local old = cache.vehicle
        if GetPedInVehicleSeat(old, -1) == ped and spawned[old] then SetEntityAsMissionEntity(old, true, true); DeleteVehicle(old) end
    end
    local veh = CreateVehicle(m, c.x, c.y, c.z + 0.5, h, true, false)
    local t = GetGameTimer()
    while not DoesEntityExist(veh) and GetGameTimer() - t < 3000 do Wait(0) end
    SetModelAsNoLongerNeeded(m)
    if not DoesEntityExist(veh) then return end
    spawned[veh] = true
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetVehicleOnGroundProperly(veh)
    if d.plate then SetVehicleNumberPlateText(veh, d.plate) end
    if d.maxed then maxOut(veh) end
    SetPedIntoVehicle(ped, veh, -1)
    SetVehicleEngineOn(veh, true, true, false)
    Bridge.SetFuel(veh, 100.0)
    Bridge.GiveKeys(veh, GetVehicleNumberPlateText(veh))
end

Do.setPlate = function(d)
    if cache.vehicle then SetVehicleNumberPlateText(cache.vehicle, d.plate); Bridge.GiveKeys(cache.vehicle, d.plate) end
end

Do.giveKeys = function(d)
    local veh = NetworkDoesNetworkIdExist(d.net) and NetToVeh(d.net)
    if veh and veh ~= 0 then Bridge.GiveKeys(veh, GetVehicleNumberPlateText(veh)); Notify('You received vehicle keys.', 'success') end
end

Do.vehicleNet = function(d)
    local veh = NetworkDoesNetworkIdExist(d.net) and NetToVeh(d.net)
    if not veh or veh == 0 then return end
    if d.action == 'repair' then
        SetVehicleFixed(veh); SetVehicleDeformationFixed(veh); SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0); SetVehiclePetrolTankHealth(veh, 1000.0); SetVehicleDirtLevel(veh, 0.0); Bridge.SetFuel(veh, 100.0)
    elseif d.action == 'unlock' then
        SetVehicleDoorsLocked(veh, 1); SetVehicleDoorsLockedForAllPlayers(veh, false)
    elseif d.action == 'plate' and d.plate then
        SetVehicleNumberPlateText(veh, d.plate)
    elseif d.action == 'max' then
        maxOut(veh)
    elseif d.action == 'flip' then
        local r = GetEntityRotation(veh, 2)
        SetEntityRotation(veh, 0.0, 0.0, r.z, 2, true)
        SetVehicleOnGroundProperly(veh)
    end
end

RegisterNetEvent('nzadmin:cl:do', function(action, data)
    if GetInvokingResource() then return end
    local fn = Do[action]
    if fn then fn(data or {}) end
end)

RegisterNetEvent('nzadmin:cl:teleport', function(c, ground)
    if GetInvokingResource() or type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) then return end
    local z = tonumber(c.z)
    TeleportTo(c.x + 0.0, c.y + 0.0, z, tonumber(c.w), (ground and true or false) and not z)
end)

-- ─── self vehicle helpers used by the quick menu ────────────────────────
local Local = LocalActions
local function repair(veh)
    SetVehicleFixed(veh); SetVehicleDeformationFixed(veh); SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0); SetVehiclePetrolTankHealth(veh, 1000.0); SetVehicleDirtLevel(veh, 0.0); Bridge.SetFuel(veh, 100.0)
end
Local.vehRepair = function()
    if not cache.vehicle or not Can('vehicles.repair') then return false end
    repair(cache.vehicle); return true
end
Local.vehMax = function()
    if not cache.vehicle or not Can('vehicles.set_mods') then return false end
    maxOut(cache.vehicle); return true
end
local function flip(veh)
    local r = GetEntityRotation(veh, 2)
    SetEntityRotation(veh, 0.0, 0.0, r.z, 2, true)
    SetVehicleOnGroundProperly(veh)
end
Local.vehFlip = function()
    if not cache.vehicle or not Can('vehicles.repair') then return false end
    flip(cache.vehicle); return true
end
Local.vehClean = function()
    if not cache.vehicle or not Can('vehicles.repair') then return false end
    SetVehicleDirtLevel(cache.vehicle, 0.0); WashDecalsFromVehicle(cache.vehicle, 1.0); return true
end
Local.vehDelete = function()
    if not Can('vehicles.despawn') then return false end
    local veh = cache.vehicle or lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0, false)
    if not veh or veh == 0 then return false end
    if cache.vehicle then TaskLeaveVehicle(cache.ped, veh, 16) end
    if NetworkGetEntityIsNetworked(veh) then NetworkRequestControlOfEntity(veh) end
    SetEntityAsMissionEntity(veh, true, true); DeleteVehicle(veh)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    return true
end
Local.vehColor = function(d)
    if not cache.vehicle or not Can('vehicles.set_mods') then return false end
    local function rgb(hex) hex = hex:gsub('#', ''); return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) end
    if d.primary then SetVehicleCustomPrimaryColour(cache.vehicle, rgb(d.primary)) end
    if d.secondary then SetVehicleCustomSecondaryColour(cache.vehicle, rgb(d.secondary)) end
    return true
end
Local.vehPlate = function(d)
    if not cache.vehicle or not Can('vehicles.set_plate') then return false end
    local plate = tostring(d.plate or ''):upper():sub(1, 8)
    if plate == '' then return false end
    if lib.callback.await('nzadmin:ownedPlate', false, plate) then Notify('That plate is taken.', 'error'); return false end
    SetVehicleNumberPlateText(cache.vehicle, plate); Bridge.GiveKeys(cache.vehicle, plate); return true
end
Local.vehInfo = function()
    local v = cache.vehicle; if not v then return false end
    local m = GetEntityModel(v)
    return { model = GetDisplayNameFromVehicleModel(m):lower(), plate = GetVehicleNumberPlateText(v), engine = math.floor(GetVehicleEngineHealth(v)),
        body = math.floor(GetVehicleBodyHealth(v)), fuel = math.floor(GetVehicleFuelLevel(v)), net = VehToNet(v) }
end

-- ─── jail ───────────────────────────────────────────────────────────────
local jail
RegisterNetEvent('nzadmin:cl:jail', function(data, back)
    if GetInvokingResource() then return end
    if not data then
        jail = nil
        NUI('jail', false)
        if type(back) == 'table' and tonumber(back.x) then TeleportTo(back.x, back.y, back.z, back.w) end
        Notify(NZ.L('jail_released'), 'success', 'Jail')
        return
    end
    local cell = data.cell
    local first = jail == nil
    jail = { cell = vec3(cell.x, cell.y, cell.z), w = cell.w, radius = cell.radius or 8.0 }
    if Config.Jail.RemoveWeapons then RemoveAllPedWeapons(cache.ped, true) end
    TeleportTo(cell.x, cell.y, cell.z, cell.w)
    NUI('jail', data.info)
    if first then
        CreateThread(function()
            while jail do
                local c = GetEntityCoords(cache.ped)
                if #(c - jail.cell) > jail.radius then
                    if cache.vehicle then TaskLeaveVehicle(cache.ped, cache.vehicle, 16); Wait(1500) end
                    SetEntityCoords(cache.ped, jail.cell.x, jail.cell.y, jail.cell.z, false, false, false, false)
                    SetEntityHeading(cache.ped, jail.w or 0.0)
                    Notify('You cannot leave your cell.', 'error', 'Jail')
                end
                Wait(Config.Jail.CheckEvery or 5000)
            end
        end)
    end
end)

-- ─── developer: client-side Lua ─────────────────────────────────────────
local function dump(v, depth)
    depth = depth or 0
    if type(v) ~= 'table' then return tostring(v) end
    if depth > 3 then return '{...}' end
    local out = {}
    for k, val in pairs(v) do
        out[#out + 1] = ('%s%s = %s'):format(string.rep('  ', depth + 1), tostring(k), dump(val, depth + 1))
        if #out > 60 then out[#out + 1] = '  ...'; break end
    end
    return '{\n' .. table.concat(out, ',\n') .. '\n' .. string.rep('  ', depth) .. '}'
end

RegisterNetEvent('nzadmin:cl:devExec', function(code, staff)
    if GetInvokingResource() then return end
    local fn, err = load(code, '=nzadmin', 't')
    local result
    if not fn then result = 'Syntax error: ' .. tostring(err)
    else
        local ok, a, b, c = pcall(fn)
        if not ok then result = 'Error: ' .. tostring(a)
        else
            local parts = {}
            for _, v in ipairs({ a, b, c }) do parts[#parts + 1] = dump(v) end
            result = #parts > 0 and table.concat(parts, '\n') or 'nil'
        end
    end
    TriggerServerEvent('nzadmin:sv:devResult', staff, result:sub(1, 8000))
end)

-- ─── death log (event driven) ───────────────────────────────────────────
if Config.Logs.Enabled and Config.Logs.Deaths then
    local lastDeath = 0
    AddEventHandler('gameEventTriggered', function(name, args)
        if name ~= 'CEventNetworkEntityDamage' then return end
        local victim, attacker, fatal, weapon = args[1], args[2], args[6] == 1, args[7]
        if victim ~= cache.ped or not fatal then return end
        if GetGameTimer() - lastDeath < 3000 then return end
        lastDeath = GetGameTimer()
        local killer
        if attacker and attacker ~= -1 and IsEntityAPed(attacker) and IsPedAPlayer(attacker) then
            killer = GetPlayerServerId(NetworkGetPlayerIndexFromPed(attacker))
        elseif attacker and IsEntityAVehicle(attacker) then
            local drv = GetPedInVehicleSeat(attacker, -1)
            if drv ~= 0 and IsPedAPlayer(drv) then killer = GetPlayerServerId(NetworkGetPlayerIndexFromPed(drv)) end
        end
        local c = GetEntityCoords(cache.ped)
        TriggerServerEvent('nzadmin:sv:died', killer, weapon, { x = NZ.Round(c.x), y = NZ.Round(c.y), z = NZ.Round(c.z) })
    end)
end

-- a restart must not leave anyone frozen, cuffed or stuck in a cell loop
AddEventHandler('onResourceStop', function(r)
    if r ~= NZ.Resource then return end
    if frozen then Do.freeze({ state = false }) end
    if cuffed then Do.cuff({ state = false }) end
    jail = nil
end)
