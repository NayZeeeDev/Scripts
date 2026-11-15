-- Entry point: keybinds, main loops, server events.
local RES = GetCurrentResourceName()

-- settings + wheel profiles load before any loop touches them
CU.LoadSettings()
Wheel.Load()

---------------------------------------------------------------------------
-- mode
---------------------------------------------------------------------------
local function setActive(on)
    if on == CU.Active then return end
    if on then
        if not Config.CanCutUpHere(GetEntityCoords(PlayerPedId())) then
            UI.Notify(L('mode_blocked'), nil, 'error') return
        end
        CU.Active = true
        if Config.DisablePolice then SetMaxWantedLevel(0) end
        UI.Notify('CUT UP', L('mode_on'), 'success')
    else
        if CU.Run then Scoring.EndRun('run_over') end
        CU.Active = false
        Traffic.Clear()
        Camera.Stop()
        if Config.DisablePolice then SetMaxWantedLevel(5) end
        UI.Notify('CUT UP', L('mode_off'), 'info')
    end
    TriggerServerEvent('nayzeee-cutup:server:setActive', CU.Active)
end

---------------------------------------------------------------------------
-- commands + key mappings
---------------------------------------------------------------------------
local function map(cmd, desc, key)
    if key then RegisterKeyMapping(cmd, desc, 'keyboard', key) end
end

RegisterCommand('cutup', function() setActive(not CU.Active) end, false)
map('cutup', 'CUT UP: toggle mode', Config.Keys.ToggleMode)

RegisterCommand('cutupmenu', function() UI.OpenMenu('camera') end, false)
map('cutupmenu', 'CUT UP: menu', Config.Keys.Menu)

if Config.UI.SettingsCommand then
    RegisterCommand(Config.UI.SettingsCommand, function() UI.OpenMenu('interface') end, false)
end

RegisterCommand('leaderboard', function()
    CU.MenuOpen = true
    SetNuiFocus(true, true)
    UI.Send('board:open', {})
    TriggerServerEvent('nayzeee-cutup:server:leaderboard', 'solo', 1)
end, false)
map('leaderboard', 'CUT UP: leaderboard', Config.Keys.Leaderboard)

RegisterCommand('wheel', function() UI.OpenMenu('wheel') end, false)
RegisterCommand('crew', function() UI.OpenMenu('crew') end, false)

RegisterCommand('cutupcam', function()
    if CU.Veh ~= 0 and (CU.Active or Config.Everywhere.Camera) then Camera.Cycle() end
end, false)
map('cutupcam', 'CUT UP: cycle camera', Config.Keys.Camera)

RegisterCommand('cutupfovup', function() Camera.AdjustFov(2.0) end, false)
map('cutupfovup', 'CUT UP: FOV +', Config.Keys.FovUp)
RegisterCommand('cutupfovdown', function() Camera.AdjustFov(-2.0) end, false)
map('cutupfovdown', 'CUT UP: FOV -', Config.Keys.FovDown)

RegisterCommand('+cutupshiftup', function() Transmission.ShiftUp() end, false)
RegisterCommand('-cutupshiftup', function() end, false)
map('+cutupshiftup', 'CUT UP: shift up', Config.Keys.ShiftUp)
RegisterCommand('+cutupshiftdown', function() Transmission.ShiftDown() end, false)
RegisterCommand('-cutupshiftdown', function() end, false)
map('+cutupshiftdown', 'CUT UP: shift down', Config.Keys.ShiftDown)

RegisterCommand('+cutupclutch', function() CU.Trans.clutchKey = true end, false)
RegisterCommand('-cutupclutch', function() CU.Trans.clutchKey = false end, false)
map('+cutupclutch', 'CUT UP: clutch (hold)', Config.Keys.Clutch)

RegisterCommand('+cutupflash', function()
    if CU.Veh ~= 0 and CU.IsDriver then
        SetVehicleFullbeam(CU.Veh, true)
        CU.Flash.pending = true
    end
end, false)
RegisterCommand('-cutupflash', function()
    if CU.Veh ~= 0 then SetVehicleFullbeam(CU.Veh, false) end
end, false)
map('+cutupflash', 'CUT UP: flash high beams', Config.Keys.Flash)

RegisterCommand('cutuphud', function()
    CU.Settings.hud.show = not CU.Settings.hud.show
    CU.SaveSettings()
    UI.PushConfig()
end, false)
map('cutuphud', 'CUT UP: toggle HUD', Config.Keys.ToggleHud)

if Config.Damage.RepairCommand then
    RegisterCommand(Config.Damage.RepairCommand, function()
        if CU.Veh == 0 or not CU.IsDriver then return end
        if CU.Run or CU.Speed > 1.0 then UI.Notify(L('repair_denied'), nil, 'warn') return end
        Collision.Repair(CU.Veh)
        UI.Notify(L('repaired'), nil, 'success')
    end, false)
end

---------------------------------------------------------------------------
-- server events
---------------------------------------------------------------------------
RegisterNetEvent('nayzeee-cutup:client:profile', function(profile)
    CU.Profile = profile or CU.Profile
    UI.Send('profile', CU.Profile)
end)

RegisterNetEvent('nayzeee-cutup:client:runResult', function(res)
    if not res then return end
    if not res.ok then
        UI.Notify(L('run_over'), L('run_rejected', res.reason or '?'), 'error')
        UI.Send('summary:result', res)
        return
    end
    UI.Send('summary:result', res)
    UI.Notify(L('run_over'), L('run_saved', Util.FormatNumber(res.points)), 'success')
    if res.newPB then UI.Popup(L('new_pb'), '#' .. tostring(res.position), CU.Settings.ui.hudAccent) end
    if res.rankUp then
        UI.Popup(L('rank_up', res.rankUp), nil, CU.Settings.ui.hudAccent2)
        UI.Send('sound', 'rankup')
    end
end)

RegisterNetEvent('nayzeee-cutup:client:leaderboard', function(data) UI.Send('board', data) end)

RegisterNetEvent('nayzeee-cutup:client:crew', function(data)
    CU.Profile.crew = data and data.crew or nil
    UI.Send('crew', data)
end)

RegisterNetEvent('nayzeee-cutup:client:notify', function(title, msg, kind)
    UI.Notify(title, msg, kind)
end)

---------------------------------------------------------------------------
-- loops
---------------------------------------------------------------------------
local function featureOn(name)
    return CU.Active or Config.Everywhere[name]
end

-- every frame
CreateThread(function()
    while true do
        local dt = GetFrameTime()
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        CU.Ped = ped
        if veh ~= CU.Veh then
            CU.Veh = veh
            Collision.Reset()
            Transmission.Reset()
            if veh == 0 and CU.Run then Scoring.EndRun('left_vehicle') end
        end
        CU.IsDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        CU.Speed = veh ~= 0 and GetEntitySpeed(veh) or 0.0

        if CU.Active then Traffic.TickDensity() end
        if CU.IsDriver then
            if featureOn('Wheel') then Wheel.Apply() end
            if featureOn('Transmission') then Transmission.Tick(dt) end
            if CU.Active then Collision.Tick(dt) end
        end
        Crew.TickGhost()
        if featureOn('Camera') then
            Camera.Tick(dt)
        else
            Camera.Stop()
        end
        if CU.Active then Scoring.Tick(dt) end

        if veh == 0 and not CU.Active then Wait(200) else Wait(0) end
    end
end)

-- 50 ms scheduler: HUD 20 Hz, radar 10 Hz, awareness 5 Hz, scans 4 Hz
CreateThread(function()
    local tick = 0
    while true do
        tick = tick + 1
        local hudOn = CU.Active and CU.IsDriver
        if hudOn or tick % 10 == 0 then UI.PushHud() end
        if tick % 2 == 0 then Radar.Update() end
        if CU.Active and CU.Veh ~= 0 then
            if tick % 4 == 0 then Awareness.Update() end
            if tick % 5 == 0 then
                Traffic.Scan()
                Traffic.Update()
            end
        end
        if tick % 5 == 0 then Crew.UpdateSync(0.25) end
        Wait(50)
    end
end)

-- traffic spawner (model loads can wait, so it gets its own thread)
CreateThread(function()
    while true do
        if CU.Active and CU.IsDriver then
            Traffic.Manage()
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

-- slow checks
CreateThread(function()
    while true do
        Wait(1000)
        if CU.Active then
            if Config.DisablePolice and GetPlayerWantedLevel(PlayerId()) > 0 then
                SetPlayerWantedLevel(PlayerId(), 0, false)
                SetPlayerWantedLevelNow(PlayerId(), false)
            end
            if not Config.CanCutUpHere(GetEntityCoords(CU.Ped)) then
                setActive(false)
                UI.Notify(L('mode_blocked'), nil, 'error')
            end
        elseif Config.AutoEnable and CU.IsDriver then
            setActive(true)
        end
    end
end)

---------------------------------------------------------------------------
-- boot
---------------------------------------------------------------------------
CreateThread(function()
    math.randomseed(GetGameTimer())
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    Wait(500)
    UI.PushConfig()
    UI.Send('wheel:profiles', Wheel.GetProfiles())
    TriggerServerEvent('nayzeee-cutup:server:init')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if CU.MenuOpen then SetNuiFocus(false, false) end
    if Config.DisablePolice and CU.Active then SetMaxWantedLevel(5) end
end)
