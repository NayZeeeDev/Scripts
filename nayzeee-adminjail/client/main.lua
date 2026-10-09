--[[
    NAYZEEE Admin Jail — client enforcement

    Idle cost is zero: no threads exist until the server says this player is jailed.
    While jailed there is one 1000ms watcher (zone + restrictions) and the work loop,
    which only runs per-frame when standing near the current task marker.
]]

Jail = {}

local Event = AJ.Event
local UNARMED = `WEAPON_UNARMED`

local sentence      -- last payload from the server
local syncedAt = 0
local phase = 'idle' -- 'idle' | 'placing' | 'active'
local token = 0      -- bumps on every enforce/release so stale placement threads bail out
local watching = false
local lastSpawnAt = 0

function Jail.Phase() return phase end
function Jail.Sentence() return sentence end

--[[ Spawn detection — waits out spawn selectors, multichar, apartments, loading screens ]]

local function spawned(ped)
    return Bridge.IsLoaded()
        and DoesEntityExist(ped)
        and IsEntityVisible(ped)
        and not IsPlayerSwitchInProgress()
        and not IsScreenFadedOut()
        and not IsScreenFadingOut()
        and not IsScreenFadingIn()
        and GetRenderingCam() == -1
        and (not IsNuiFocused() or Hud.PanelOpen())
end

local function waitForSpawn(myToken)
    local deadline = GetGameTimer() + Config.Spawn.settleTimeout * 1000
    local stable = 0
    while myToken == token do
        if spawned(PlayerPedId()) then
            stable = stable + 1
            if stable >= Config.Spawn.settleChecks then return true end
        else
            stable = 0
            if GetGameTimer() > deadline and Bridge.IsLoaded() then return true end
        end
        Wait(500)
    end
    return false
end

local function teleport(coords)
    local ped = PlayerPedId()
    DoScreenFadeOut(300)
    local timeout = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(0) end

    if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    FreezeEntityPosition(ped, true)

    timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(50) end

    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(500)
end

--[[ Restrictions — all native state, nothing per-frame ]]

local R = Config.Restrictions

local function restrict(ped)
    if R.godmode then SetEntityInvincible(ped, true) end
    if R.noMelee then SetPedConfigFlag(ped, 122, true) end
    if R.disarm and GetSelectedPedWeapon(ped) ~= UNARMED then SetCurrentPedWeapon(ped, UNARMED, true) end
    if R.noVehicles and IsPedInAnyVehicle(ped, true) then TaskLeaveAnyVehicle(ped, 0, 16) end
    if R.blockInventory then
        -- ox_lib progress bars reset invBusy when they finish, so this is re-asserted every tick
        if not LocalPlayer.state.invBusy then LocalPlayer.state:set('invBusy', true, false) end
        if not LocalPlayer.state.inv_busy then LocalPlayer.state:set('inv_busy', true, false) end
    end
end

local function unrestrict()
    local ped = PlayerPedId()
    if R.godmode then SetEntityInvincible(ped, false) end
    if R.noMelee then SetPedConfigFlag(ped, 122, false) end
    if R.blockInventory then
        LocalPlayer.state:set('invBusy', false, false)
        LocalPlayer.state:set('inv_busy', false, false)
    end
end

--[[ Watcher — 1 Hz while jailed ]]

local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        local strikes, lastReport = 0, 0
        while phase ~= 'idle' do
            if phase == 'active' then
                local ped = cache.ped
                restrict(ped)

                local loc = AJ.GetLocation(sentence.location)
                local away = not IsEntityDead(ped) and not IsScreenFadedOut()
                    and not AJ.InZone(loc, GetEntityCoords(ped))

                if away then
                    strikes = strikes + 1
                    local t = GetGameTimer()
                    if strikes >= 2 and t - lastReport > 5000 then
                        strikes, lastReport = 0, t
                        local recentSpawn = t - lastSpawnAt < Config.Spawn.pullbackWindow * 1000
                        TriggerServerEvent(Event('server:outside'), recentSpawn)
                    end
                else
                    strikes = 0
                end
            end
            Wait(1000)
        end
        watching = false
    end)
end

local function debugZone()
    if not Config.Debug then return end
    CreateThread(function()
        while phase ~= 'idle' do
            local zone = AJ.GetLocation(sentence.location).zone
            local pts = zone.points
            if pts then
                for i = 1, #pts do
                    local a, b = pts[i], pts[i % #pts + 1]
                    DrawLine(a.x, a.y, zone.minZ, b.x, b.y, zone.minZ, 8, 175, 162, 255)
                    DrawLine(a.x, a.y, zone.maxZ, b.x, b.y, zone.maxZ, 8, 175, 162, 255)
                    DrawLine(a.x, a.y, zone.minZ, a.x, a.y, zone.maxZ, 229, 72, 77, 255)
                end
            end
            Wait(0)
        end
    end)
end

local function fmt(sec)
    local m = math.floor(sec / 60)
    if m >= 60 then return ('%dh %02dm'):format(m // 60, m % 60) end
    return ('%dm %02ds'):format(m, sec % 60)
end

--[[ Server events ]]

RegisterNetEvent(Event('client:enforce'), function(data)
    token = token + 1
    local myToken = token
    local wasIdle = phase == 'idle'

    sentence, syncedAt = data, GetGameTimer()
    phase = 'placing'
    if not wasIdle then Hud.Sync(data) end

    CreateThread(function()
        if not data.instant and not waitForSpawn(myToken) then return end
        if myToken ~= token then return end

        local loc = AJ.GetLocation(data.location)
        local inside = AJ.InZone(loc, GetEntityCoords(PlayerPedId()))
        if not (inside and (data.kind == 'restore' or data.kind == 'pullback')) then
            teleport(loc.spawn)
        end
        if myToken ~= token then return end

        phase = 'active'
        restrict(PlayerPedId())
        if wasIdle then
            Hud.Show(sentence)
            debugZone()
        end
        watch()
        TriggerServerEvent(Event('server:placed'))

        if data.kind == 'escape' then
            Bridge.Notify(locale('escape_target', data.penalty), 'error')
            Hud.Flash('red', ('+%d min'):format(data.penalty))
        elseif data.kind == 'restore' and wasIdle then
            Bridge.Notify(locale('restored', fmt(data.remaining)), 'inform')
        end
    end)
end)

RegisterNetEvent(Event('client:sync'), function(data)
    if phase == 'idle' then return end
    sentence, syncedAt = data, GetGameTimer()
    Hud.Sync(data)
end)

local function stop()
    token = token + 1
    phase = 'idle'
    sentence = nil
    Work.Stop()
    unrestrict()
    Hud.Hide()
end

RegisterNetEvent(Event('client:release'), function(coords)
    stop()
    CreateThread(function() teleport(coords) end)
end)

RegisterNetEvent(Event('client:suspend'), stop)

--[[ Lifecycle → tell the server we're here; it decides if we're jailed ]]

local function ready()
    TriggerServerEvent(Event('server:ready'))
end

Bridge.onLoaded = ready
Bridge.onUnloaded = function() if phase ~= 'idle' then stop() end end
Bridge.onSpawned = function()
    lastSpawnAt = GetGameTimer()
    if phase ~= 'idle' or Bridge.IsLoaded() then ready() end
end

CreateThread(function()
    Wait(1000)
    if Bridge.IsLoaded() then ready() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= AJ.Resource or phase == 'idle' then return end
    Work.Stop()
    unrestrict()
    FreezeEntityPosition(PlayerPedId(), false)
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(0) end
end)

--[[ Exports ]]

exports('IsJailed', function() return phase ~= 'idle' end)
exports('GetRemaining', function()
    if not sentence then return 0 end
    if not sentence.ticking then return sentence.remaining end
    return math.max(0, sentence.remaining - (GetGameTimer() - syncedAt) // 1000)
end)
exports('GetLocation', function() return sentence and AJ.GetLocation(sentence.location) end)
