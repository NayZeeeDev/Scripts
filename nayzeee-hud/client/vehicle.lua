-- Seatbelt, cruise (speed limiter), indicators and the vehicle control panel.
-- Nothing in here runs on a loop except the control-disable thread while the panel is open.

local belt, cruise, interior = false, false, false
local windows = {}
local panelOpen = false

local function myVehicle()
    local ped = PlayerPedId()
    return ped, GetVehiclePedIsIn(ped, false)
end

local function isDriver(ped, veh)
    return GetPedInVehicleSeat(veh, -1) == ped
end

local function setBelt(state)
    local ped, veh = myVehicle()
    if veh == 0 or not NHUD.hasBelt then state = false end
    belt = state and true or false
    if Config.Seatbelt.ejectProtection then
        SetPedConfigFlag(ped, 32, not belt) -- 32 = can fly through windscreen
    end
    NHUD.set('bl', belt)
    NHUD.flush()
    TriggerEvent('nayzeee-hud:seatbelt', belt)
end

function NHUD.vehicleEntered(veh, mode)
    belt, cruise, interior = false, false, false
    NHUD.hasBelt = Config.Seatbelt.enabled and mode == 'car'
    SetPedConfigFlag(PlayerPedId(), 32, true)
    NHUD.set('bl', false)
    NHUD.set('cr', false)
    NHUD.set('hb', NHUD.hasBelt)
end

function NHUD.vehicleLeft(veh)
    if cruise and DoesEntityExist(veh) then SetVehicleMaxSpeed(veh, 0.0) end
    belt, cruise = false, false
    NHUD.hasBelt = false
    SetPedConfigFlag(PlayerPedId(), 32, true)
    NHUD.set('bl', false)
    NHUD.set('cr', false)
    NHUD.set('hb', false)
    windows[veh] = nil
    if panelOpen then NHUD.closePanel() end
end

local function toggleCruise()
    if not Config.Cruise.enabled then return end
    local ped, veh = myVehicle()
    if veh == 0 or not isDriver(ped, veh) then return end
    if cruise then
        cruise = false
        SetVehicleMaxSpeed(veh, 0.0)
    else
        local speed = GetEntitySpeed(veh)
        if speed < 2.0 then return end
        cruise = true
        SetVehicleMaxSpeed(veh, speed)
    end
    NHUD.set('cr', cruise)
    NHUD.flush()
end

local function indicator(which)
    local ped, veh = myVehicle()
    if veh == 0 or not isDriver(ped, veh) then return end
    local st = GetVehicleIndicatorLights(veh)
    local l, r = (st == 1 or st == 3), (st == 2 or st == 3)
    if which == 'hazard' then
        local on = not (l and r)
        l, r = on, on
    elseif which == 'left' then
        l = not (l and not r)
        r = false
    else
        r = not (r and not l)
        l = false
    end
    SetVehicleIndicatorLights(veh, 1, l)
    SetVehicleIndicatorLights(veh, 0, r)
    NHUD.set('ind', (l and 1 or 0) + (r and 2 or 0))
    NHUD.flush()
end

local function panelState(ped, veh)
    local s = {
        engine = GetIsVehicleEngineRunning(veh),
        lock = GetVehicleDoorLockStatus(veh) >= 2,
        ind = GetVehicleIndicatorLights(veh),
        cruise = cruise,
        interior = interior,
        driver = isDriver(ped, veh),
        doors = {}, windows = {}, seats = {},
    }
    local _, lowOn, highOn = GetVehicleLightsState(veh)
    s.lights = lowOn == 1 or highOn == 1
    local neon = false
    for i = 0, 3 do
        if IsVehicleNeonLightEnabled(veh, i) then neon = true break end
    end
    s.neon = neon
    local w = windows[veh] or {}
    for i = 0, 5 do
        local valid = GetIsDoorValid(veh, i)
        s.doors[i + 1] = valid and ((GetVehicleDoorAngleRatio(veh, i) > 0.05) and 1 or 0) or -1
        if i < 4 then s.windows[i + 1] = valid and (w[i] and 1 or 0) or -1 end
    end
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
    for i = -1, 2 do
        if i + 2 > seats then
            s.seats[i + 2] = -1
        else
            local occ = GetPedInVehicleSeat(veh, i)
            s.seats[i + 2] = occ == ped and 2 or (occ ~= 0 and 1 or 0)
        end
    end
    return s
end

function NHUD.vehicleAction(action, index)
    local ped, veh = myVehicle()
    if veh == 0 then return false end
    local driver = isDriver(ped, veh)
    index = tonumber(index)

    if action == 'engine' then
        if driver then SetVehicleEngineOn(veh, not GetIsVehicleEngineRunning(veh), false, true) end
    elseif action == 'lock' then
        Config.ToggleLock(veh)
    elseif action == 'left' or action == 'right' or action == 'hazard' then
        indicator(action)
    elseif action == 'lights' then
        if driver then
            local _, lowOn, highOn = GetVehicleLightsState(veh)
            SetVehicleLights(veh, (lowOn == 1 or highOn == 1) and 1 or 2)
        end
    elseif action == 'cruise' then
        toggleCruise()
    elseif action == 'neon' then
        local any = false
        for i = 0, 3 do if IsVehicleNeonLightEnabled(veh, i) then any = true break end end
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, not any) end
    elseif action == 'interior' then
        interior = not interior
        SetVehicleInteriorlight(veh, interior)
    elseif action == 'door' and index and GetIsDoorValid(veh, index) then
        if GetVehicleDoorAngleRatio(veh, index) > 0.05 then
            SetVehicleDoorShut(veh, index, false)
        else
            SetVehicleDoorOpen(veh, index, false, false)
        end
    elseif action == 'window' and index then
        windows[veh] = windows[veh] or {}
        if windows[veh][index] then RollUpWindow(veh, index) else RollDownWindow(veh, index) end
        windows[veh][index] = not windows[veh][index]
    elseif action == 'seat' and index then
        if IsVehicleSeatFree(veh, index) and not (index == -1 and GetEntitySpeed(veh) > 1.0) then
            SetPedIntoVehicle(ped, veh, index)
        end
    end

    Wait(200) -- let doors / seats settle before reporting state back
    ped, veh = myVehicle()
    if veh == 0 then return false end
    return panelState(ped, veh)
end

local function disableWhilePanelOpen()
    CreateThread(function()
        while panelOpen do
            DisableControlAction(0, 1, true)   -- look lr
            DisableControlAction(0, 2, true)   -- look ud
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 68, true)  -- vehicle aim
            DisableControlAction(0, 69, true)  -- vehicle attack
            DisableControlAction(0, 70, true)
            DisableControlAction(0, 91, true)
            DisableControlAction(0, 92, true)
            DisableControlAction(0, 106, true) -- vehicle mouse control
            DisableControlAction(0, 114, true)
            DisableControlAction(0, 199, true) -- pause
            DisableControlAction(0, 200, true) -- pause alt
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true)
            Wait(0)
        end
    end)
end

local function openPanel()
    if panelOpen or NHUD.focus then return end
    local ped, veh = myVehicle()
    if veh == 0 then return end
    panelOpen = true
    NHUD.focus = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(Config.ControlPanel.keepInput)
    NHUD.send('panel', { open = true, s = panelState(ped, veh) })
    if Config.ControlPanel.keepInput then disableWhilePanelOpen() end
end

function NHUD.closePanel()
    if not panelOpen then return end
    panelOpen = false
    NHUD.focus = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    NHUD.send('panel', { open = false })
end

function NHUD.isPanelOpen() return panelOpen end

-- Commands + default keys (rebindable in GTA settings)
if Config.Seatbelt.enabled then
    RegisterCommand('nhud_seatbelt', function()
        if not NHUD.hasBelt then return end
        setBelt(not belt)
    end, false)
    RegisterKeyMapping('nhud_seatbelt', 'HUD: Toggle seatbelt', 'keyboard', Config.Keys.seatbelt)
end

if Config.Cruise.enabled then
    RegisterCommand('nhud_cruise', toggleCruise, false)
    RegisterKeyMapping('nhud_cruise', 'HUD: Cruise control / limiter', 'keyboard', Config.Keys.cruise)
end

RegisterCommand('nhud_indleft', function() indicator('left') end, false)
RegisterCommand('nhud_indright', function() indicator('right') end, false)
RegisterCommand('nhud_hazard', function() indicator('hazard') end, false)
RegisterKeyMapping('nhud_indleft', 'HUD: Left indicator', 'keyboard', Config.Keys.indicatorLeft)
RegisterKeyMapping('nhud_indright', 'HUD: Right indicator', 'keyboard', Config.Keys.indicatorRight)
RegisterKeyMapping('nhud_hazard', 'HUD: Hazard lights', 'keyboard', Config.Keys.hazard)

RegisterCommand(Config.Commands.vehicleMenu, function()
    if panelOpen then NHUD.closePanel() else openPanel() end
end, false)
RegisterKeyMapping(Config.Commands.vehicleMenu, 'HUD: Vehicle control panel', 'keyboard', Config.Keys.vehicleMenu)

-- Integrations for other seatbelt scripts
exports('SetSeatbelt', setBelt)
exports('IsSeatbeltOn', function() return belt end)
exports('IsCruiseOn', function() return cruise end)
RegisterNetEvent('nayzeee-hud:client:setSeatbelt', setBelt)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped, veh = myVehicle()
    SetPedConfigFlag(ped, 32, true)
    if cruise and veh ~= 0 then SetVehicleMaxSpeed(veh, 0.0) end
    if panelOpen then SetNuiFocus(false, false) SetNuiFocusKeepInput(false) end
    DisplayRadar(true)
end)
