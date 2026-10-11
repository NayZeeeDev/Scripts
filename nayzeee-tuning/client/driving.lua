--[[
    Everything that only matters to the person driving:
    ECU / engine swap / wear handling, nitrous + purge, anti-lag, launch control, blow-off valve,
    air ride keys and mileage telemetry. Nothing runs unless you're in the driver seat.
]]

local HANDLING = {
    'fInitialDriveForce', 'fInitialDriveMaxFlatVel', 'fBrakeForce', 'fBrakeBiasFront', 'fTractionCurveMax',
    'fTractionBiasFront', 'fAntiRollBarForce', 'fSuspensionForce', 'fSuspensionCompDamp', 'fSuspensionReboundDamp',
    'fSteeringLock', 'fLowSpeedTractionLossMult', 'fDriveBiasFront', 'fTractionLossMult', 'fTractionCurveMin',
    'fTractionCurveLateral',
}

local base = {}           -- [veh] = { field = value }
local touched = {}        -- [veh] = true when we changed handling
local driving             -- vehicle we're currently driving
local data = {}           -- nzTune of that vehicle (live)
local nitro = { amount = 0, capacity = 0, power = 1.0, boosting = false, used = 0, purging = false }
local launching = false

local function exhaustBones(veh)
    local out = {}
    for _, b in ipairs({ 'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4' }) do
        local idx = GetEntityBoneIndexByName(veh, b)
        if idx ~= -1 then out[#out + 1] = idx end
    end
    return out
end

local function hget(veh, f) return GetVehicleHandlingFloat(veh, 'CHandlingData', f) end
local function hset(veh, f, v) SetVehicleHandlingFloat(veh, 'CHandlingData', f, v + 0.0) end

local function captureBase(veh)
    if base[veh] then return base[veh] end
    local b = {}
    for _, f in ipairs(HANDLING) do b[f] = hget(veh, f) end
    base[veh] = b
    return b
end

--------------------------------------------------------------------- handling

local function applyHandling(veh)
    local d = data or {}
    local ecu, sw, fx = d.ecu, d.swap and NZ.SwapBySound[d.swap], d.wearFx
    local tyre = d.tyres and NZ.TyreById[d.tyres]
    local drive = d.drive and NZ.DriveById[d.drive]
    local chassis = tyre or drive or d.ceramic or d.driftKit or d.tcs or d.esc
    if not ecu and not sw and not fx and not chassis and not touched[veh] then return end
    local b = captureBase(veh)
    ecu, fx = ecu or {}, fx or {}
    local pct = function(k) return (ecu[k] or 0) / 100 end
    local dk = d.driftKit and Config.DriftKit
    local tcs = d.tcs and Config.DriverAssists.TCS
    local esc = d.esc and Config.DriverAssists.ESC

    local power = (1 + pct('power') + (ecu.mapGain or 0) / 100) * (sw and sw.power or 1.0) * (fx.engine or 1.0) * (fx.turbo or 1.0)
    hset(veh, 'fInitialDriveForce', b.fInitialDriveForce * power)
    hset(veh, 'fInitialDriveMaxFlatVel', b.fInitialDriveMaxFlatVel * (1 + pct('gearing')))
    hset(veh, 'fBrakeForce', b.fBrakeForce * (1 + pct('brake')) * (fx.brakes or 1.0) * (d.ceramic and Config.CeramicBrakes.BrakeForce or 1.0))
    hset(veh, 'fBrakeBiasFront', NZ.Clamp(b.fBrakeBiasFront + pct('brakeBias'), 0.1, 0.9))
    local grip = (1 + pct('grip')) * (fx.tyres or 1.0) * (tyre and tyre.grip or 1.0)
    hset(veh, 'fTractionCurveMax', b.fTractionCurveMax * grip * (dk and dk.CurveMax or 1.0))
    hset(veh, 'fTractionCurveMin', b.fTractionCurveMin * grip * (dk and dk.CurveMin or 1.0))
    hset(veh, 'fTractionCurveLateral', b.fTractionCurveLateral * (esc and esc.Lateral or 1.0))
    hset(veh, 'fTractionBiasFront', NZ.Clamp(b.fTractionBiasFront + pct('gripBias') + (dk and dk.BiasFront or 0) + (esc and esc.BiasFront or 0), 0.1, 0.9))
    hset(veh, 'fTractionLossMult', b.fTractionLossMult * (tyre and tyre.offroad or 1.0) * (tcs and tcs.TractionLoss or 1.0))
    hset(veh, 'fLowSpeedTractionLossMult', b.fLowSpeedTractionLossMult * (dk and dk.LowSpeedLoss or 1.0) * (tcs and tcs.LowSpeedLoss or 1.0))
    hset(veh, 'fAntiRollBarForce', b.fAntiRollBarForce * (1 + pct('antiRoll')))
    hset(veh, 'fSuspensionForce', b.fSuspensionForce * (1 + pct('spring')))
    hset(veh, 'fSuspensionCompDamp', b.fSuspensionCompDamp * (1 + pct('damping')))
    hset(veh, 'fSuspensionReboundDamp', b.fSuspensionReboundDamp * (1 + pct('damping')))
    hset(veh, 'fSteeringLock', b.fSteeringLock * (1 + pct('steer')) * (dk and dk.Steer or 1.0))
    hset(veh, 'fDriveBiasFront', drive and drive.bias or b.fDriveBiasFront)
    touched[veh] = true

    -- slammed air ride caps speed
    local cap = Config.AirRide.SlammedSpeedCap
    if d.airride and cap > 0 and d.air == #Config.AirRide.Presets then
        SetVehicleMaxSpeed(veh, cap / 3.6)
    else
        SetVehicleMaxSpeed(veh, 0.0)
    end
end

--------------------------------------------------------------------- HUD

local function nitroHud()
    if not Config.Nitrous.Hud then return end
    if driving and data.nitrous then
        UI.Send('hud:nitrous', { show = true, pct = nitro.capacity > 0 and nitro.amount / nitro.capacity or 0,
            level = data.nitrous.level, boosting = nitro.boosting, purging = nitro.purging })
    else
        UI.Send('hud:nitrous', { show = false })
    end
end

-- value: the new bag value from a change handler (the bag itself still holds the old one then)
local function readData(veh, value)
    local st = Entity(veh).state
    data = value or (st and st.nzTune) or {}
    if data.nitrous then
        local lvl = Config.Nitrous.Levels[data.nitrous.level] or Config.Nitrous.Levels[1]
        if not nitro.boosting and not nitro.purging then nitro.amount = data.nitrous.amount or 0 end
        nitro.capacity, nitro.power = lvl.capacity, lvl.power
    else
        nitro.amount, nitro.capacity = 0, 0
    end
end

--------------------------------------------------------------------- nitrous

local function flushNitro()
    if nitro.used > 0.5 and driving then
        TriggerServerEvent('nayzeee-tuning:nitrousUsed', VehToNet(driving), NZ.Round(nitro.used, 1))
        nitro.flushedAt = GetGameTimer()
    end
    nitro.used = 0
end

-- report usage while still in the seat (the server drops it once you're out), at most once a second
local function flushSoon(now)
    if now - (nitro.flushedAt or 0) > 1000 then flushNitro() end
end

-- the server throttles reports to one per 250 ms: don't let the final one land inside that window
local function flushLast()
    local gap = GetGameTimer() - (nitro.flushedAt or 0)
    if gap < 260 then Wait(260 - gap) end
    flushNitro()
end

local function flames(veh, bones)
    if not Config.Nitrous.Flames or #bones == 0 then return end
    if not HasNamedPtfxAssetLoaded('core') then RequestNamedPtfxAsset('core') return end
    for _, idx in ipairs(bones) do
        UseParticleFxAssetNextCall('core')
        StartNetworkedParticleFxNonLoopedOnEntityBone('veh_backfire', veh, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, idx, 1.25, false, false, false)
    end
end

local function startBoost()
    local veh = driving
    if not veh or not data.nitrous or nitro.boosting or nitro.amount <= 0 then return end
    if GetEntitySpeed(veh) * 3.6 < Config.Nitrous.MinSpeed then return end
    nitro.boosting = true
    if Config.Nitrous.ScreenEffect then AnimpostfxPlay('RaceTurbo', 0, true) end
    local bones = exhaustBones(veh)
    CreateThread(function()
        local lastFx, lastHud, last = 0, 0, GetGameTimer()
        while nitro.boosting and driving == veh and nitro.amount > 0 do
            local now = GetGameTimer()
            local dt = (now - last) / 1000
            last = now
            SetVehicleCheatPowerIncrease(veh, nitro.power)
            local use = Config.Nitrous.DrainPerSecond * dt
            nitro.amount = math.max(0, nitro.amount - use)
            nitro.used = nitro.used + use
            if now - lastFx > 110 then lastFx = now flames(veh, bones) end
            if now - lastHud > 100 then lastHud = now nitroHud() end
            flushSoon(now)
            Wait(0)
        end
        nitro.boosting = false
        if Config.Nitrous.ScreenEffect then AnimpostfxStop('RaceTurbo') end
        flushLast()
        nitroHud()
    end)
end

local function startPurge()
    local veh = driving
    if not veh or not data.nitrous or nitro.purging or nitro.amount <= 0 then return end
    if GetEntitySpeed(veh) * 3.6 > 25.0 then return end
    nitro.purging = true
    CreateThread(function()
        lib.requestNamedPtfxAsset('core', 1000)
        local fxs = {}
        for _, side in ipairs({ -1, 1 }) do
            local mn, mx = GetModelDimensions(GetEntityModel(veh))
            UseParticleFxAssetNextCall('core')
            fxs[#fxs + 1] = StartNetworkedParticleFxLoopedOnEntity('ent_sht_steam', veh, side * (mx.x - 0.15), mx.y - 0.35, 0.15, 40.0, 0.0, side * 60.0, 0.55, false, false, false)
        end
        UI.Send('sound', { name = 'purge', volume = 0.55 })
        local last = GetGameTimer()
        while nitro.purging and driving == veh and nitro.amount > 0 do
            local now = GetGameTimer()
            local use = Config.Nitrous.PurgeDrainPerSecond * (now - last) / 1000
            last = now
            nitro.amount = math.max(0, nitro.amount - use)
            nitro.used = nitro.used + use
            flushSoon(now)
            Wait(100)
            nitroHud()
        end
        for _, fx in ipairs(fxs) do StopParticleFxLooped(fx, false) end
        UI.Send('sound', { name = 'purge', stop = true })
        nitro.purging = false
        flushLast()
        nitroHud()
    end)
end

if Config.Nitrous.Enabled then
    lib.addKeybind({ name = 'nzt_nitrous', description = 'Tuning: nitrous boost (hold)', defaultKey = Config.Keys.Nitrous,
        onPressed = startBoost, onReleased = function() nitro.boosting = false end })
    lib.addKeybind({ name = 'nzt_purge', description = 'Tuning: nitrous purge (hold)', defaultKey = Config.Keys.Purge,
        onPressed = startPurge, onReleased = function() nitro.purging = false end })
end

RegisterNetEvent('nayzeee-tuning:useNitrousBottle', function()
    local veh = cache.vehicle or VehUtil.Closest(4.0)
    if not veh or veh == 0 then return Notify(L('no_vehicle'), 'error') end
    if cache.vehicle then return Notify(L('get_out_first'), 'error') end
    if not Bridge.Progress(L('refilling_nitrous'), 5000, { 'mini@repair', 'fixing_a_ped', 1 }, { model = joaat('prop_gascyl_01a'), bone = 60309, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) }) then return end
    local ok, err = lib.callback.await('nayzeee-tuning:refillNitrous', false, VehToNet(veh))
    Notify(ok and L('nitrous_refilled') or (err or L('failed')), ok and 'success' or 'error')
end)

--------------------------------------------------------------------- air ride keys

local function airRide(dir)
    local veh = driving
    if not veh or not data.airride or not Config.AirRide.Enabled then return end
    if GetEntitySpeed(veh) * 3.6 > Config.AirRide.MaxSpeedToChange then return Notify(L('airride_speed'), 'error') end
    local cur = data.air or Config.AirRide.DefaultPreset
    local nxt = NZ.Clamp(cur + dir, 1, #Config.AirRide.Presets)
    if nxt == cur then return end
    TriggerServerEvent('nayzeee-tuning:airRide', VehToNet(veh), nxt)
    UI.Send('hud:toast', { icon = 'fa-wind', text = Config.AirRide.Presets[nxt].label })
end

if Config.AirRide.Enabled then
    lib.addKeybind({ name = 'nzt_air_up', description = 'Tuning: air ride up', defaultKey = Config.Keys.AirRideUp, onPressed = function() airRide(-1) end })
    lib.addKeybind({ name = 'nzt_air_down', description = 'Tuning: air ride down', defaultKey = Config.Keys.AirRideDown, onPressed = function() airRide(1) end })
end

--------------------------------------------------------------------- anti-lag / BOV / launch control

-- called on entry and again whenever the car's data changes (late sync, parts bought while seated)
local fxVeh
local function driveFx(veh)
    if fxVeh == veh then return end
    local hasTurbo = Config.Turbo.BlowOff and IsToggleModOn(veh, 18)
    local knocky = data.ecu and (data.ecu.knock or 0) >= Config.ECU.Map.KnockDamage
    if not data.antilag and not data.launch and not hasTurbo and not knocky then return end
    fxVeh = veh
    CreateThread(function()
        local bones = exhaustBones(veh)
        local prevThrottle, prevRpm = 0.0, 0.0
        while driving == veh do
            local throttle = GetControlNormal(0, 71)
            local brake = GetControlNormal(0, 72)
            local rpm = GetVehicleCurrentRpm(veh)
            local speed = GetEntitySpeed(veh)

            -- throttle lift at high rpm
            if prevThrottle > 0.55 and throttle < 0.1 then
                if data.antilag and prevRpm >= Config.AntiLag.MinRpm then
                    CreateThread(function()
                        for _ = 1, math.random(1, Config.AntiLag.MaxPops) do
                            flames(veh, bones)
                            if Config.AntiLag.Sound then UI.Send('sound', { name = 'crackle', volume = 0.45 }) end
                            Wait(Config.AntiLag.Cooldown + math.random(0, 90))
                        end
                    end)
                end
                if hasTurbo and prevRpm >= Config.Turbo.MinRpm then UI.Send('sound', { name = 'bov', volume = 0.4 }) end
            end

            -- launch control
            if data.launch and not launching and speed < 1.0 and throttle > 0.8 and brake > 0.6 then
                launching = true
                UI.Send('hud:toast', { icon = 'fa-flag-checkered', text = L('launch_armed'), hold = true })
                while driving == veh and GetControlNormal(0, 72) > 0.4 and GetControlNormal(0, 71) > 0.6 do
                    SetVehicleCurrentRpm(veh, Config.LaunchControl.HoldRpm)
                    Wait(0)
                end
                UI.Send('hud:toast', { hide = true })
                if driving == veh and GetControlNormal(0, 71) > 0.6 then
                    local b = captureBase(veh)
                    hset(veh, 'fLowSpeedTractionLossMult', b.fLowSpeedTractionLossMult * Config.LaunchControl.TractionHelp)
                    touched[veh] = true
                    UI.Send('hud:toast', { icon = 'fa-bolt', text = L('launch_go') })
                    Wait(Config.LaunchControl.BoostMs)
                    if DoesEntityExist(veh) then hset(veh, 'fLowSpeedTractionLossMult', b.fLowSpeedTractionLossMult) end
                end
                launching = false
            end

            -- an over-aggressive ignition map hurts the engine at the top end
            if knocky and rpm > 0.92 and GetGameTimer() % 4000 < 60 and math.random() < 0.35 then
                SetVehicleEngineHealth(veh, math.max(50.0, GetVehicleEngineHealth(veh) - 15.0))
                if Config.AntiLag.Sound then UI.Send('sound', { name = 'crackle', volume = 0.3 }) end
            end

            prevThrottle, prevRpm = throttle, rpm
            Wait(60)
        end
        if fxVeh == veh then fxVeh = nil end
    end)
end

--------------------------------------------------------------------- manual gearbox

local manual = { on = false, gear = 1 }

local function gearHud()
    if not Config.Gearbox.Hud then return end
    if driving and data.gearbox == 'manual' then
        UI.Send('hud:gear', { show = true, manual = manual.on, gear = manual.gear })
    else
        UI.Send('hud:gear', { show = false })
    end
end

local function topGear(veh) return math.max(1, GetVehicleHandlingInt(veh, 'CHandlingData', 'nInitialDriveGears')) end

local function manualLoop(veh)
    CreateThread(function()
        local maxG = topGear(veh)
        manual.gear = math.max(1, math.min(GetVehicleCurrentGear(veh), maxG))
        gearHud()
        while manual.on and driving == veh do
            local cur = GetVehicleCurrentGear(veh)
            local reversing = cur == 0 or (GetEntitySpeedVector(veh, true).y < -0.5)
            if not reversing then
                SetVehicleHighGear(veh, manual.gear)
                if cur ~= manual.gear then
                    SetVehicleCurrentGear(veh, manual.gear)
                    SetVehicleNextGear(veh, manual.gear)
                end
            end
            Wait(0)
        end
        if DoesEntityExist(veh) then SetVehicleHighGear(veh, topGear(veh)) end
        gearHud()
    end)
end

local function shift(dir)
    local veh = driving
    if not veh or not manual.on then return end
    local maxG = topGear(veh)
    local nxt = NZ.Clamp(manual.gear + dir, 1, maxG)
    if nxt == manual.gear then return end
    if dir < 0 and GetVehicleCurrentRpm(veh) > 0.86 then
        -- money shift
        SetVehicleEngineHealth(veh, math.max(50.0, GetVehicleEngineHealth(veh) - Config.Gearbox.OverRevDamage))
        UI.Send('sound', { name = 'crackle', volume = 0.5 })
    end
    manual.gear = nxt
    gearHud()
end

if Config.Gearbox.Enabled then
    lib.addKeybind({ name = 'nzt_shift_up', description = 'Tuning: manual shift up', defaultKey = Config.Gearbox.ShiftUp, onPressed = function() shift(1) end })
    lib.addKeybind({ name = 'nzt_shift_down', description = 'Tuning: manual shift down', defaultKey = Config.Gearbox.ShiftDown, onPressed = function() shift(-1) end })
    lib.addKeybind({ name = 'nzt_gearbox', description = 'Tuning: toggle manual gearbox', defaultKey = Config.Gearbox.Toggle,
        onPressed = function()
            if not driving or data.gearbox ~= 'manual' then return end
            manual.on = not manual.on
            UI.Send('hud:toast', { icon = 'fa-arrow-down-up-across-line', text = manual.on and L('gearbox_manual') or L('gearbox_auto') })
            if manual.on then manualLoop(driving) else gearHud() end
        end })
end

--------------------------------------------------------------------- driver assists

local function toggleAssist(which)
    if not Config.DriverAssists.Enabled or not driving then return end
    local on = not data[which]
    TriggerServerEvent('nayzeee-tuning:assist', VehToNet(driving), which, on)
    UI.Send('hud:toast', { icon = 'fa-car-burst', text = ('%s %s'):format(which:upper(), on and 'ON' or 'OFF') })
end
Driving = { ToggleAssist = toggleAssist, Vehicle = function() return driving end, Data = function() return data end }

if Config.DriverAssists.Enabled then
    RegisterCommand('tcs', function() toggleAssist('tcs') end, false)
    RegisterCommand('esc', function() toggleAssist('esc') end, false)
end

--------------------------------------------------------------------- telemetry

local function telemetry(veh)
    if not Config.Wear.Enabled then return end
    CreateThread(function()
        local km, hard, sinceSync = 0.0, 0.0, 0
        while driving == veh do
            Wait(1000)
            if not DoesEntityExist(veh) then break end
            local d = GetEntitySpeed(veh) / 1000.0
            km = km + d
            local rpm = GetVehicleCurrentRpm(veh)
            local slide = math.abs(GetEntitySpeedVector(veh, true).x) > 3.0
            if rpm > 0.88 or slide or IsVehicleInBurnout(veh) then hard = hard + d end
            sinceSync = sinceSync + 1
            if sinceSync >= Config.Wear.SyncEvery and km > 0.01 then
                TriggerServerEvent('nayzeee-tuning:telemetry', VehToNet(veh), NZ.Round(km, 3), NZ.Round(hard, 3), IsToggleModOn(veh, 18))
                km, hard, sinceSync = 0.0, 0.0, 0
            end
        end
        if km > 0.05 and DoesEntityExist(veh) then
            TriggerServerEvent('nayzeee-tuning:telemetry', VehToNet(veh), NZ.Round(km, 3), NZ.Round(hard, 3), IsToggleModOn(veh, 18))
        end
    end)
end

--------------------------------------------------------------------- driver lifecycle

local requested = {}

local function onDriver(veh)
    if driving == veh then return end
    driving = veh
    readData(veh)
    -- fresh from a garage the plate may not have reached the server yet: keep asking for a few seconds
    if not Entity(veh).state.nzTune and not requested[veh] then
        requested[veh] = true
        CreateThread(function()
            for _ = 1, 8 do
                if driving ~= veh or not DoesEntityExist(veh) or Entity(veh).state.nzTune then break end
                if NetworkGetEntityIsNetworked(veh) then TriggerServerEvent('nayzeee-tuning:requestData', VehToNet(veh)) end
                Wait(1000)
            end
        end)
    end
    applyHandling(veh)
    nitroHud()
    gearHud()
    driveFx(veh)
    telemetry(veh)
    if data.wearFx then Notify(L('service_due'), 'inform', 7000) end

    -- keep up with state changes while driving (refills, air ride, purchases)
    CreateThread(function()
        local sig = json.encode(data)
        while driving == veh do
            Wait(1000)
            if not DoesEntityExist(veh) then break end
            readData(veh)
            local s = json.encode(data)
            if s ~= sig then
                sig = s
                applyHandling(veh)
                nitroHud()
                driveFx(veh)
            end
        end
    end)
end

local function offDriver()
    if not driving then return end
    nitro.boosting, nitro.purging = false, false
    manual.on = false
    flushNitro()
    driving = nil
    data = {}
    nitroHud()
    gearHud()
    UI.Send('hud:toast', { hide = true })
end

lib.onCache('seat', function(seat)
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if seat == -1 and veh ~= 0 then onDriver(veh) else offDriver() end
end)
-- warped straight from one driver seat into another (/car, garage swaps): the seat never changes
lib.onCache('vehicle', function(veh)
    if not veh then return offDriver() end
    if driving and driving ~= veh then
        offDriver()
        if GetPedInVehicleSeat(veh, -1) == cache.ped then onDriver(veh) end
    end
end)

CreateThread(function()
    Wait(1500)
    if cache.vehicle and cache.seat == -1 then onDriver(cache.vehicle) end
    while true do
        Wait(60000)
        for veh in pairs(base) do
            if not DoesEntityExist(veh) then base[veh], touched[veh], requested[veh] = nil, nil, nil end
        end
    end
end)

AddStateBagChangeHandler('nzTune', nil, function(bagName, _, value)
    if not driving then return end
    local ent = GetEntityFromStateBagName(bagName)
    if ent ~= driving then return end
    readData(ent, value or {})
    applyHandling(ent)
    nitroHud()
    driveFx(ent)
end)

-- put handling back to stock so a restart doesn't stack the tune on top of itself
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    AnimpostfxStop('RaceTurbo')
    for veh, b in pairs(base) do
        if DoesEntityExist(veh) then
            for f, v in pairs(b) do hset(veh, f, v) end
            SetVehicleMaxSpeed(veh, 0.0)
        end
    end
    if driving and DoesEntityExist(driving) then SetVehicleHighGear(driving, topGear(driving)) end
end)

-- /testsound <audio name> (admins): try a sound pack on your car before adding it to Config.SoundPacks
RegisterNetEvent('nayzeee-tuning:testSound', function(audio)
    local veh = cache.vehicle
    if not veh or type(audio) ~= 'string' then return Notify(L('no_vehicle'), 'error') end
    ForceUseAudioGameObject(veh, audio)
    SetVehicleEngineOn(veh, true, true, false)
    Notify(L('sound_testing', audio), 'inform', 7000)
end)
