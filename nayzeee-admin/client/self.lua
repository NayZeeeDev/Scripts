-- Self toggles. Every loop here only exists while its toggle is on, so the resource idles at 0.00.
Toggles = { noclip = false, god = false, invis = false, superjump = false, fastrun = false, ammo = false, night = false,
    thermal = false, headlight = false, names = false, ids = false, coords = false, freeze = false, blackout = false, localtime = false,
    vehgod = false }

local Local = LocalActions
local running = {}

local function spawnLoop(key, fn)
    if running[key] then return end
    running[key] = true
    CreateThread(function()
        while Toggles[key] do fn() end
        running[key] = nil
    end)
end

local function sync() NUI('toggles', Toggles) end

-- ─── noclip ─────────────────────────────────────────────────────────────
local speeds = { 0.15, 0.5, 1.2, 2.5, 5.0, 10.0 }
local speedIdx = 3

local function noclipEntity()
    local veh = cache.vehicle
    if veh and GetPedInVehicleSeat(veh, -1) == cache.ped then return veh end
    return cache.ped
end

local noclipEnt -- the entity noclip was switched on for (ped or the car you drive)

local function setNoclip(on)
    Toggles.noclip = on
    local ent = on and noclipEntity() or (noclipEnt and DoesEntityExist(noclipEnt) and noclipEnt or noclipEntity())
    noclipEnt = on and ent or nil
    if on then
        TriggerServerEvent('nzadmin:sv:movement', 8)
        SetEntityCollision(ent, false, false)
        FreezeEntityPosition(ent, true)
        SetEntityInvincible(ent, true)
        if ent ~= cache.ped then SetEntityInvincible(cache.ped, true) end
        SetEntityVisible(ent, false, false)
        NUI('noclip', { on = true, speed = speedIdx, pos = Settings.noclipPos })
        local lastPing = GetGameTimer()
        spawnLoop('noclip', function()
            local e = noclipEntity()
            if e ~= noclipEnt then -- got in or out of a car while flying: hand noclip over
                if noclipEnt and DoesEntityExist(noclipEnt) then
                    SetEntityCollision(noclipEnt, true, true); FreezeEntityPosition(noclipEnt, false)
                    SetEntityVisible(noclipEnt, not Toggles.invis, false); SetEntityInvincible(noclipEnt, Toggles.god)
                end
                noclipEnt = e
                SetEntityCollision(e, false, false); FreezeEntityPosition(e, true); SetEntityInvincible(e, true); SetEntityVisible(e, false, false)
            end
            SetLocalPlayerVisibleLocally(true)
            DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true); DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true); DisableControlAction(0, 35, true)
            DisableControlAction(0, 44, true); DisableControlAction(0, 38, true)
            DisableControlAction(0, 14, true); DisableControlAction(0, 15, true)
            DisableControlAction(0, 16, true); DisableControlAction(0, 17, true)
            DisableControlAction(0, 85, true); DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true); DisableControlAction(0, 257, true)

            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then
                speedIdx = math.min(#speeds, speedIdx + 1); NUI('noclip', { on = true, speed = speedIdx, pos = Settings.noclipPos })
            elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then
                speedIdx = math.max(1, speedIdx - 1); NUI('noclip', { on = true, speed = speedIdx, pos = Settings.noclipPos })
            end

            local speed = speeds[speedIdx]
            if IsControlPressed(0, 21) then speed = speed * 3.0 elseif IsControlPressed(0, 36) then speed = speed * 0.25 end

            local rot = GetGameplayCamRot(2)
            local rx, rz = math.rad(rot.x), math.rad(rot.z)
            local fx, fy, fz = -math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx)
            local sx, sy = math.cos(rz), math.sin(rz)
            local pos = GetEntityCoords(e)
            local x, y, z = pos.x, pos.y, pos.z

            if IsDisabledControlPressed(0, 32) then x, y, z = x + fx * speed, y + fy * speed, z + fz * speed end
            if IsDisabledControlPressed(0, 33) then x, y, z = x - fx * speed, y - fy * speed, z - fz * speed end
            if IsDisabledControlPressed(0, 35) then x, y = x + sx * speed, y + sy * speed end
            if IsDisabledControlPressed(0, 34) then x, y = x - sx * speed, y - sy * speed end
            if IsDisabledControlPressed(0, 44) then z = z + speed end
            if IsDisabledControlPressed(0, 38) then z = z - speed end

            SetEntityCoordsNoOffset(e, x, y, z, true, true, true)
            SetEntityHeading(e, rot.z)
            SetEntityVelocity(e, 0.0, 0.0, 0.0)

            if GetGameTimer() - lastPing > 5000 then
                lastPing = GetGameTimer()
                TriggerServerEvent('nzadmin:sv:movement', 8)
            end
            Wait(0)
        end)
    else
        SetEntityCollision(ent, true, true)
        FreezeEntityPosition(ent, Toggles.freeze and ent == (cache.vehicle or cache.ped))
        SetEntityVisible(ent, not Toggles.invis, false)
        SetEntityInvincible(ent, ent == cache.ped and Toggles.god or (ent ~= cache.ped and Toggles.vehgod))
        SetEntityInvincible(cache.ped, Toggles.god)
        SetEntityVisible(cache.ped, not Toggles.invis, false)
        if ent == cache.ped then
            -- drop to the ground so we don't fall through or take damage
            local c = GetEntityCoords(ent)
            local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
            if ok and c.z - gz < 3.0 then SetEntityCoordsNoOffset(ent, c.x, c.y, gz, false, false, false) end
        end
        TriggerServerEvent('nzadmin:sv:movement', 5)
        NUI('noclip', { on = false })
    end
end

-- ─── simple toggles ─────────────────────────────────────────────────────
local handlers = {}

handlers.noclip = { perm = 'self.noclip', fn = setNoclip }

handlers.god = { perm = 'self.godmode', fn = function(on)
    Toggles.god = on
    SetEntityInvincible(cache.ped, on)
    SetPlayerInvincible(cache.playerId, on)
    if on then
        spawnLoop('god', function()
            if GetEntityHealth(cache.ped) < GetEntityMaxHealth(cache.ped) then SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped)) end
            SetEntityInvincible(cache.ped, true)
            Wait(500)
        end)
    end
end }

handlers.invis = { perm = 'self.invisibility', fn = function(on)
    Toggles.invis = on
    SetEntityVisible(cache.ped, not on, false)
    if cache.vehicle then SetEntityVisible(cache.vehicle, not on, false) end
    if on then
        spawnLoop('invis', function()
            SetLocalPlayerVisibleLocally(true)
            SetEntityAlpha(cache.ped, 130, false)
            Wait(0)
        end)
    else
        ResetEntityAlpha(cache.ped)
    end
end }

handlers.superjump = { perm = 'self.super_jump', fn = function(on)
    Toggles.superjump = on
    if on then
        spawnLoop('superjump', function()
            SetSuperJumpThisFrame(cache.playerId)
            SetPedCanRagdoll(cache.ped, false)
            Wait(0)
        end)
    else
        SetPedCanRagdoll(cache.ped, true)
    end
end }

handlers.fastrun = { perm = 'self.fast_run', fn = function(on)
    Toggles.fastrun = on
    SetRunSprintMultiplierForPlayer(cache.playerId, on and 1.49 or 1.0)
    SetSwimMultiplierForPlayer(cache.playerId, on and 1.49 or 1.0)
    if on then
        spawnLoop('fastrun', function() RestorePlayerStamina(cache.playerId, 1.0); Wait(1000) end)
    end
end }

handlers.ammo = { perm = 'self.infinite_ammo', fn = function(on)
    Toggles.ammo = on
    SetPedInfiniteAmmoClip(cache.ped, on)
    if on then
        spawnLoop('ammo', function()
            local _, w = GetCurrentPedWeapon(cache.ped, true)
            if w and w ~= `WEAPON_UNARMED` then SetPedInfiniteAmmo(cache.ped, true, w) end
            Wait(1000)
        end)
    else
        SetPedInfiniteAmmo(cache.ped, false)
    end
end }

handlers.night = { perm = 'self.night_vision', fn = function(on)
    if on and Toggles.thermal then handlers.thermal.fn(false) end
    Toggles.night = on
    SetNightvision(on)
end }

handlers.thermal = { perm = 'self.thermal_vision', fn = function(on)
    if on and Toggles.night then handlers.night.fn(false) end
    Toggles.thermal = on
    SetSeethrough(on)
end }

handlers.headlight = { perm = 'self.head_light', fn = function(on)
    Toggles.headlight = on
    if on then
        spawnLoop('headlight', function()
            local c = GetEntityCoords(cache.ped)
            local rot = GetGameplayCamRot(2)
            local rx, rz = math.rad(rot.x), math.rad(rot.z)
            local dir = vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
            DrawSpotLight(c.x, c.y, c.z + 0.7, dir.x, dir.y, dir.z, 255, 255, 255, 60.0, 8.0, 3.0, 30.0, 12.0)
            Wait(0)
        end)
    end
end }

local frozenEnt
handlers.freeze = { perm = 'self.freeze', fn = function(on)
    Toggles.freeze = on
    if on then
        frozenEnt = cache.vehicle or cache.ped
        FreezeEntityPosition(frozenEnt, true)
    else
        if frozenEnt and DoesEntityExist(frozenEnt) and not (Toggles.noclip and frozenEnt == noclipEnt) then FreezeEntityPosition(frozenEnt, false) end
        frozenEnt = nil
    end
end }

-- vehicle god mode: no loop, it follows you through lib.onCache('vehicle')
local function vehGod(veh, on)
    if not veh or not DoesEntityExist(veh) then return end
    SetEntityInvincible(veh, on)
    SetVehicleCanBeVisiblyDamaged(veh, not on)
    SetVehicleTyresCanBurst(veh, not on)
    SetVehicleEngineCanDegrade(veh, not on)
    SetVehicleWheelsCanBreak(veh, not on)
    if on then SetVehicleFixed(veh); SetVehicleEngineHealth(veh, 1000.0) end
end
handlers.vehgod = { perm = 'self.godmode', fn = function(on)
    Toggles.vehgod = on
    vehGod(cache.vehicle, on)
end }
lib.onCache('vehicle', function(veh, old)
    if not Toggles.vehgod then return end
    if old then vehGod(old, false) end
    if veh then vehGod(veh, true) end
end)

handlers.blackout = { perm = 'self.blackout', fn = function(on)
    Toggles.blackout = on
    SetArtificialLightsState(on)
    SetArtificialLightsStateAffectsVehicles(false)
end }

-- ─── names / ids overlay ────────────────────────────────────────────────
local meta, metaAt = {}, 0

local function drawText3D(x, y, z, text, r, g, b)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextColour(r or 255, g or 255, b or 255, 235)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function hexRGB(hex)
    hex = tostring(hex or ''):gsub('#', '')
    if #hex ~= 6 then return 255, 255, 255 end
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local flagColors = {}
for _, f in ipairs(Config.Flags or {}) do flagColors[f.id] = f.label end

local function overlayLoop()
    spawnLoop('overlay', function()
        if not (Toggles.names or Toggles.ids) then Wait(0) return end
        if GetGameTimer() - metaAt > 10000 then
            metaAt = GetGameTimer()
            CreateThread(function()
                local ok, data = RPC('names:meta')
                if ok and type(data) == 'table' then meta = data end
            end)
        end
        local me = GetEntityCoords(cache.ped)
        local dist = Config.Staff.NameDistance or 80.0
        for _, pid in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(pid)
            local c = GetEntityCoords(ped)
            if #(me - c) < dist and (pid ~= cache.playerId or Toggles.noclip) then
                local sid = GetPlayerServerId(pid)
                local m = meta[tostring(sid)]
                local parts = {}
                if Toggles.ids then parts[#parts + 1] = ('[%d]'):format(sid) end
                if Toggles.names then parts[#parts + 1] = GetPlayerName(pid) end
                if NetworkIsPlayerTalking(pid) then parts[#parts + 1] = '~b~(talking)~s~' end
                local r, g, b = 255, 255, 255
                if m and m.staff then r, g, b = hexRGB(m.staff) end
                local line = table.concat(parts, ' ')
                if m and m.flags and #m.flags > 0 then
                    local tags = {}
                    for _, f in ipairs(m.flags) do tags[#tags + 1] = flagColors[f] or f end
                    drawText3D(c.x, c.y, c.z + 1.25, '~y~' .. table.concat(tags, ' · '))
                end
                local hp = math.max(0, GetEntityHealth(ped) - 100)
                drawText3D(c.x, c.y, c.z + 1.1, ('%s  ~c~%d hp'):format(line, hp), r, g, b)
            end
        end
        Wait(0)
    end)
end

-- running flag is keyed by 'overlay' but it stops once both are off
local function overlayActive() return Toggles.names or Toggles.ids end
handlers.names = { perm = 'self.player_names', fn = function(on)
    Toggles.names = on
    Toggles.overlay = overlayActive()
    if Toggles.overlay then overlayLoop() end
end }
handlers.ids = { perm = 'self.player_ids', fn = function(on)
    Toggles.ids = on
    Toggles.overlay = overlayActive()
    if Toggles.overlay then overlayLoop() end
end }

-- ─── coords hud ─────────────────────────────────────────────────────────
handlers.coords = { perm = 'self.show_coords', fn = function(on)
    Toggles.coords = on
    if on then
        spawnLoop('coords', function()
            local c = GetEntityCoords(cache.ped)
            NUI('coords', { x = NZ.Round(c.x), y = NZ.Round(c.y), z = NZ.Round(c.z), h = NZ.Round(GetEntityHeading(cache.ped)),
                street = GetStreetNameFromHashKey(GetStreetNameAtCoord(c.x, c.y, c.z)), pos = Settings.coordsPos })
            Wait(250)
        end)
    else
        NUI('coords', false)
    end
end }

-- ─── local time / weather ───────────────────────────────────────────────
local localWeather
handlers.localtime = { perm = 'self.manage_time', fn = function(on, d)
    Toggles.localtime = on
    if on then
        d = d or {}
        localWeather = { hour = tonumber(d.hour) or 12, minute = tonumber(d.minute) or 0, weather = d.weather or 'EXTRASUNNY' }
        SetWeatherTypeNowPersist(localWeather.weather)
        spawnLoop('localtime', function()
            NetworkOverrideClockTime(localWeather.hour, localWeather.minute, 0)
            SetWeatherTypeNowPersist(localWeather.weather)
            Wait(0)
        end)
    else
        localWeather = nil
        ClearWeatherTypePersist()
        ClearOverrideWeather()
        if WorldWeather then WorldWeather() end
    end
end }

-- ─── toggle entry points ────────────────────────────────────────────────
function SetToggle(key, on, data)
    local h = handlers[key]
    if not h then return false end
    if on == nil then on = not Toggles[key] end -- resolve first, a plain toggle must still check the permission
    on = on == true
    if on and not Can(h.perm) then Notify('You do not have permission for that.', 'error'); return false end
    h.fn(on, data)
    sync()
    return Toggles[key]
end

function StopAllToggles()
    for key in pairs(handlers) do
        if Toggles[key] then handlers[key].fn(false) end
    end
    sync()
end

Local.toggle = function(d) return { state = SetToggle(d.key, d.state, d.data), toggles = Toggles } end
Local.toggles = function() return Toggles end

-- ─── teleports ──────────────────────────────────────────────────────────
LastPos = nil
local function savePos() local c = GetEntityCoords(cache.ped); LastPos = vec4(c.x, c.y, c.z, GetEntityHeading(cache.ped)) end
function SaveLastPos() savePos() end

--- Ground z under x,y. Streams collision in from the top down, gives up after ~3s.
local function findGround(ent, x, y, z)
    local top = math.max(z or 0.0, 950.0)
    local t = GetGameTimer()
    for h = top, -100.0, -50.0 do
        SetEntityCoordsNoOffset(ent, x, y, h + 0.0, false, false, false)
        RequestCollisionAtCoord(x, y, h + 0.0)
        local tries = 0
        repeat
            Wait(0)
            local ok, gz = GetGroundZFor_3dCoord(x, y, h + 0.0, false)
            if ok then return gz end
            tries = tries + 1
        until tries > 4
        if GetGameTimer() - t > 3000 then break end
    end
    local water, wz = GetWaterHeight(x, y, top)
    if water then return wz end
    return z
end

local teleporting = false
function TeleportTo(x, y, z, heading, ground)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or teleporting then return false end
    teleporting = true
    savePos()
    TriggerServerEvent('nzadmin:sv:movement', 6)
    local ent = cache.vehicle and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped and cache.vehicle or cache.ped
    DoScreenFadeOut(150)
    local t = GetGameTimer()
    while not IsScreenFadedOut() and GetGameTimer() - t < 1000 do Wait(0) end
    FreezeEntityPosition(ent, true)
    RequestCollisionAtCoord(x, y, (z or 0.0) + 0.0)
    SetEntityCoordsNoOffset(ent, x, y, (z or 0.0) + 0.0, false, false, false)
    if ground or not z then
        local gz = findGround(ent, x, y, z)
        z = gz or z or 0.0
        SetEntityCoordsNoOffset(ent, x, y, z + 0.0, false, false, false)
    end
    t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() - t < 3000 do Wait(0) end
    if heading then SetEntityHeading(ent, heading + 0.0) end
    -- stay frozen while noclip or freeze self is on
    FreezeEntityPosition(ent, Toggles.noclip or (Toggles.freeze and ent == frozenEnt))
    DoScreenFadeIn(250)
    teleporting = false
    return true
end

local function tpWaypoint()
    if not Can('self.teleport') then return false end
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then Notify('Set a waypoint first.', 'error'); return false end
    local c = GetBlipInfoIdCoord(blip)
    TeleportTo(c.x, c.y, nil, nil, true)
    return true
end

Local.tpWaypoint = tpWaypoint
Local.tpCoords = function(d)
    if not Can('self.teleport') then return false end
    local x, y, z = tonumber(d.x), tonumber(d.y), tonumber(d.z)
    if not x or not y then return false end
    CreateThread(function() TeleportTo(x, y, z, tonumber(d.w), not z) end)
    return true
end
Local.back = function()
    if not Can('self.teleport') then return false end
    if not LastPos then Notify('No previous position.', 'error'); return false end
    local p = LastPos
    CreateThread(function() TeleportTo(p.x, p.y, p.z, p.w) end)
    return true
end

-- ─── self actions ───────────────────────────────────────────────────────
Local.selfHeal = function()
    if not Can('self.revive') then return false end
    SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    SetPedArmour(cache.ped, 100)
    ClearPedBloodDamage(cache.ped)
    return true
end
Local.selfKill = function() if not Can('self.kill') then return false end SetEntityHealth(cache.ped, 0) return true end
Local.selfClothing = function() if not Can('self.clothing_menu') then return false end CloseUI(); Bridge.OpenClothing() return true end
Local.selfRevive = function()
    if not Can('self.revive') then return false end
    CreateThread(function() local ok, err = RPC('self:revive', {}); if not ok then Notify(err, 'error') end end)
    return true
end
Local.selfWeapon = function(d)
    if not Can('self.give_weapon') then return false end
    local w = joaat(tostring(d.weapon or ''):upper())
    if not IsWeaponValid(w) then Notify('Invalid weapon.', 'error'); return false end
    GiveWeaponToPed(cache.ped, w, tonumber(d.ammo) or 250, false, true)
    return true
end
Local.localTime = function(d)
    if Toggles.localtime then handlers.localtime.fn(false) end -- apply new values
    return SetToggle('localtime', true, d)
end
Local.copyCoords = function(d)
    local c = GetEntityCoords(cache.ped)
    local h = GetEntityHeading(cache.ped)
    local fmt = d.format or 'vec4'
    local text
    if fmt == 'vec3' then text = ('vec3(%.2f, %.2f, %.2f)'):format(c.x, c.y, c.z)
    elseif fmt == 'json' then text = json.encode({ x = NZ.Round(c.x), y = NZ.Round(c.y), z = NZ.Round(c.z), w = NZ.Round(h) })
    elseif fmt == 'raw' then text = ('%.2f, %.2f, %.2f, %.2f'):format(c.x, c.y, c.z, h)
    else text = ('vec4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, h) end
    lib.setClipboard(text)
    return text
end

-- ─── commands ───────────────────────────────────────────────────────────
local C = Config.Commands
local function cmd(key, fn, desc)
    local c = C[key]
    if not c or not c.enabled then return end
    RegisterCommand(c.name, fn, false)
    if c.key ~= nil then RegisterKeyMapping(c.name, desc, 'keyboard', c.key or '') end
end

cmd('noclip', function() if Me.isStaff then SetToggle('noclip') end end, 'Admin: noclip')
cmd('tpm', function() if Me.isStaff then CreateThread(tpWaypoint) end end, 'Admin: teleport to waypoint')
cmd('back', function() if Me.isStaff and Can('self.teleport') then Local.back() end end, 'Admin: back to last position')
cmd('names', function()
    if not Me.isStaff then return end
    local on = not (Toggles.names or Toggles.ids)
    if Can('self.player_names') then SetToggle('names', on) end
    if Can('self.player_ids') then SetToggle('ids', on) end
end, 'Admin: player names')
cmd('coords', function(_, a)
    if not Me.isStaff then return end
    if a[1] == 'copy' then Notify('Copied ' .. Local.copyCoords({ format = a[2] }), 'success') else SetToggle('coords') end
end, 'Admin: show coords')

-- ped swaps reset some flags
lib.onCache('ped', function()
    if not Me.isStaff then return end
    SetTimeout(200, function()
        if Toggles.god then handlers.god.fn(true) end
        if Toggles.invis then handlers.invis.fn(true) end
        if Toggles.ammo then handlers.ammo.fn(true) end
        if Toggles.superjump then SetPedCanRagdoll(cache.ped, false) end
    end)
end)

ToggleHandlers = handlers
