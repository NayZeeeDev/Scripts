-- The only always-running loop. One thread, timer-sliced, diff-only NUI updates.
-- On foot it wakes every 250ms, in a vehicle every 125ms. Nothing runs per frame.

local floor, min, max = math.floor, math.min, math.max
local set, flush = NHUD.set, NHUD.flush
local T = Config.Ticks

local PlayerPedId, PlayerId, GetGameTimer, Wait = PlayerPedId, PlayerId, GetGameTimer, Wait
local GetVehiclePedIsIn, GetEntitySpeed, GetEntityCoords = GetVehiclePedIsIn, GetEntitySpeed, GetEntityCoords
local GetIsVehicleEngineRunning, GetVehicleCurrentRpm, GetVehicleCurrentGear = GetIsVehicleEngineRunning, GetVehicleCurrentRpm, GetVehicleCurrentGear
local GetGameplayCamRot, IsPauseMenuActive, GetEntityHeading = GetGameplayCamRot, IsPauseMenuActive, GetEntityHeading
local GetSelectedPedWeapon, GetAmmoInClip, GetAmmoInPedWeapon, GetWeapontypeGroup = GetSelectedPedWeapon, GetAmmoInClip, GetAmmoInPedWeapon, GetWeapontypeGroup
local GetEntityHealth, GetEntityMaxHealth, GetPedArmour, IsEntityDead = GetEntityHealth, GetEntityMaxHealth, GetPedArmour, IsEntityDead
local NetworkIsPlayerTalking, GetPlayerSprintStaminaRemaining = NetworkIsPlayerTalking, GetPlayerSprintStaminaRemaining
local IsPedSwimmingUnderWater, GetPlayerUnderwaterTimeRemaining = IsPedSwimmingUnderWater, GetPlayerUnderwaterTimeRemaining

local pid = PlayerId()
local ped, veh, mode = 0, 0, false
local nextStatus, nextLoc, nextSlow, nextVehSlow = 0, 0, 0, 0
local lastX, lastY = 0.0, 0.0
local lastVehTick = 0
local maxUnderwater = 10.0
local odo, odoKey, odoSaved = 0.0, nil, 0.0

local UNARMED = `WEAPON_UNARMED`
local MELEE = `GROUP_MELEE`

-- lookups built once
local weaponNames, weaponLabels, weatherNames = {}, {}, {}
for _, name in ipairs(Data.Weapons) do
    local hash = GetHashKey(name)
    weaponNames[hash] = name
    local label = Data.WeaponLabels[name]
    if not label then
        label = name:gsub('^WEAPON_', ''):gsub('_', ' '):lower():gsub('(%a)(%w*)', function(a, b) return a:upper() .. b end)
    end
    weaponLabels[hash] = label
end
for _, name in ipairs(Data.Weather) do weatherNames[GetHashKey(name)] = name end

local function pct(v, m)
    if m <= 0 then return 0 end
    v = floor(v / m * 100 + 0.5)
    return v < 0 and 0 or (v > 100 and 100 or v)
end

-- Speed limits ----------------------------------------------------------------
local limitCache = {}
local function speedLimit(street)
    local v = limitCache[street]
    if v then return v end
    v = Data.SpeedLimits[street]
    if not v then
        local suffix = street:match('(%S+)$')
        v = suffix and Data.SpeedLimitSuffix[suffix]
    end
    v = v or Data.DefaultSpeedLimit
    limitCache[street] = v
    return v
end

-- Fuel ------------------------------------------------------------------------
local function fuelGetter()
    local f = Config.Fuel
    if f == 'auto' then
        f = 'native'
        for _, res in ipairs({ 'LegacyFuel', 'cdn-fuel', 'ps-fuel', 'lj-fuel', 'ox_fuel', 'lc_fuel', 'qs-fuelstations', 'okokGasStation', 'Renewed-Fuel' }) do
            if GetResourceState(res) == 'started' then f = res break end
        end
    end
    if f == 'ox_fuel' or f == 'Renewed-Fuel' or f == 'statebag' then
        return function(v) return Entity(v).state.fuel or GetVehicleFuelLevel(v) end
    end
    if f ~= 'native' then
        return function(v)
            local ok, r = pcall(function() return exports[f]:GetFuel(v) end)
            return (ok and tonumber(r)) or GetVehicleFuelLevel(v)
        end
    end
    return GetVehicleFuelLevel
end
local getFuel = GetVehicleFuelLevel
CreateThread(function() getFuel = fuelGetter() end)

-- Odometer --------------------------------------------------------------------
local function saveOdo()
    if not Config.Odometer or not odoKey then return end
    if odo - odoSaved > 50.0 then
        SetResourceKvpFloat(odoKey, odo)
        odoSaved = odo
    end
end

local function loadOdo(v)
    if not Config.Odometer then odo = 0.0 return end
    local plate = GetVehicleNumberPlateText(v)
    odoKey = plate and ('odo:' .. plate:gsub('%s+', '')) or nil
    odo = odoKey and GetResourceKvpFloat(odoKey) or 0.0
    odoSaved = odo
end

-- Vehicle ---------------------------------------------------------------------
local function modeFor(v)
    local c = GetVehicleClass(v)
    if c == 13 then return 'cycle' end
    if c == 14 then return 'boat' end
    if c == 15 or c == 16 then return 'air' end
    if c == 21 then return 'train' end
    if c == 8 then return 'moto' end
    return 'car'
end

local function onVehicleChange(newVeh, now)
    if veh ~= 0 then
        NHUD.vehicleLeft(veh)
        saveOdo()
    end
    veh = newVeh
    lastVehTick = now
    if veh ~= 0 then
        mode = modeFor(veh)
        NHUD.vehicleEntered(veh, mode)
        loadOdo(veh)
        nextVehSlow = 0
        if Config.HideNativeHud == 'smart' then NHUD.burstHide(6000) end
    else
        mode = false
    end
    set('vm', mode)
    NHUD.updateRadar(veh ~= 0)
end

local function tickVehicleSlow()
    set('fu', floor(min(100, max(0, getFuel(veh) or 0))))
    set('en', pct(GetVehicleEngineHealth(veh), 1000))
    local _, lowOn, highOn = GetVehicleLightsState(veh)
    set('li', highOn == 1 and 2 or (lowOn == 1 and 1 or 0))
    set('lk', GetVehicleDoorLockStatus(veh) >= 2)
    set('ind', GetVehicleIndicatorLights(veh))
    set('odo', floor(odo))
    if mode == 'air' then set('lg', GetLandingGearState(veh)) end
end

local function tickVehicle(now)
    local speed = GetEntitySpeed(veh)
    set('spd', floor(speed * 10 + 0.5)) -- m/s * 10, the UI converts to the player's unit

    local dt = (now - lastVehTick) / 1000
    lastVehTick = now
    if dt > 0 and dt < 1 then odo = odo + speed * dt end

    local running = GetIsVehicleEngineRunning(veh)
    set('eng', running)
    set('rpm', running and floor(GetVehicleCurrentRpm(veh) * 100) or 0)

    if mode == 'air' then
        local c = GetEntityCoords(veh)
        local vel = GetEntityVelocity(veh)
        set('alt', floor(c.z * 3.28084))
        set('agl', floor(GetEntityHeightAboveGround(veh) * 3.28084))
        set('vs', floor(vel.z * 19.685) * 10) -- ft/min, 10 ft steps
        set('pt', floor(GetEntityPitch(veh)))
        set('rl', floor(GetEntityRoll(veh)))
        set('vh', floor((360.0 - GetEntityHeading(veh)) % 360.0))
    else
        local g = GetVehicleCurrentGear(veh)
        set('gr', (not running and 'P') or (g == 0 and 'R') or (speed < 0.3 and 'N') or g)
    end

    if now >= nextVehSlow then
        nextVehSlow = now + T.vehicleSlow
        tickVehicleSlow()
    end
end

-- Player ----------------------------------------------------------------------
local function tickWeapon()
    local w = GetSelectedPedWeapon(ped)
    if w == UNARMED then
        set('wp', false)
        return
    end
    set('wp', weaponNames[w] or 'WEAPON_UNKNOWN')
    set('wl', weaponLabels[w] or 'Weapon')
    if GetWeapontypeGroup(w) == MELEE then
        set('clip', false)
        set('ammo', false)
    else
        local _, clip = GetAmmoInClip(ped, w)
        local total = GetAmmoInPedWeapon(ped, w)
        set('clip', clip)
        set('ammo', max(0, total - clip))
    end
end

local function tickStatus()
    local maxHealth = GetEntityMaxHealth(ped) - 100
    set('h', IsEntityDead(ped) and 0 or pct(GetEntityHealth(ped) - 100, maxHealth))
    set('a', min(100, GetPedArmour(ped)))
    set('st', floor(100 - GetPlayerSprintStaminaRemaining(pid)))

    if IsPedSwimmingUnderWater(ped) then
        local o = GetPlayerUnderwaterTimeRemaining(pid)
        if o > maxUnderwater then maxUnderwater = o end
        set('ox', pct(o, maxUnderwater))
    else
        set('ox', false)
    end

    set('tk', NetworkIsPlayerTalking(pid))

    local D = Bridge.data
    set('hu', floor(D.hunger))
    set('th', floor(D.thirst))
    set('sr', floor(D.stress))
    set('cash', D.cash)
    set('bank', D.bank)
    set('job', D.job)
    set('grd', D.grade)

    set('hr', GetClockHours())
    set('mn', GetClockMinutes())
    set('dow', GetClockDayOfWeek())
end

local function tickLocation()
    local c = GetEntityCoords(ped)
    local dx, dy = c.x - lastX, c.y - lastY
    if dx * dx + dy * dy > 4.0 then
        lastX, lastY = c.x, c.y
        local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
        local street = GetStreetNameFromHashKey(s1)
        if veh ~= 0 and Config.HideNativeHud == 'smart' and street ~= NHUD.get('str') then NHUD.burstHide(4000) end
        set('str', street)
        set('crs', s2 ~= 0 and GetStreetNameFromHashKey(s2) or false)
        set('zn', GetLabelText(GetNameOfZone(c.x, c.y, c.z)))
        set('lim', speedLimit(street))
        if Config.GetPostal then
            local ok, postal = pcall(Config.GetPostal, c)
            set('pst', ok and postal or false)
        end
    end
    set('dir', floor((360.0 - GetEntityHeading(ped)) % 360.0))
    set('wx', weatherNames[GetPrevWeatherTypeHashName()] or 'CLEAR')
end

-- Headshot for the player info widget (only re-taken when the ped changes)
local headshotPed, headshotHandle = 0, nil
local function refreshHeadshot()
    if headshotPed == ped then return end
    headshotPed = ped
    CreateThread(function()
        if headshotHandle then UnregisterPedheadshot(headshotHandle) end
        local h = RegisterPedheadshotTransparent(ped)
        local timeout = GetGameTimer() + 5000
        while not IsPedheadshotReady(h) or not IsPedheadshotValid(h) do
            if GetGameTimer() > timeout then return end
            Wait(100)
        end
        headshotHandle = h
        set('hs', GetPedheadshotTxdString(h))
        flush()
    end)
end

local function tickSlow()
    NHUD.sendMap()
    if NHUD.get('radar') then NHUD.hideHealthBars() end
    refreshHeadshot()
    saveOdo()
end

local function tickFast(now)
    ped = PlayerPedId()
    set('pz', IsPauseMenuActive())
    local rot = GetGameplayCamRot(2)
    set('hdg', floor((360.0 - rot.z) % 360.0))

    local v = GetVehiclePedIsIn(ped, false)
    if v ~= veh then onVehicleChange(v, now) end

    tickWeapon()
    if veh ~= 0 then tickVehicle(now) end
end

CreateThread(function()
    set('id', GetPlayerServerId(pid))
    while true do
        if NHUD.visible then
            local now = GetGameTimer()
            tickFast(now)
            if now >= nextStatus then nextStatus = now + T.status tickStatus() end
            if now >= nextLoc then nextLoc = now + T.location tickLocation() end
            if now >= nextSlow then nextSlow = now + T.slow tickSlow() end
            flush()
            Wait(veh ~= 0 and T.vehicle or T.foot)
        else
            Wait(500)
        end
    end
end)

-- pma-voice: proximity + radio are pushed by state bags, no polling
CreateThread(function()
    local bag = ('player:%s'):format(GetPlayerServerId(pid))
    local prox = LocalPlayer.state.proximity
    set('vr', prox and prox.index or 2)
    set('rd', LocalPlayer.state.radioChannel or false)
    AddStateBagChangeHandler('proximity', bag, function(_, _, value)
        if type(value) == 'table' then set('vr', value.index or 2) flush() end
    end)
    AddStateBagChangeHandler('radioChannel', bag, function(_, _, value)
        set('rd', (value and value ~= 0) and value or false)
        flush()
    end)
end)

AddEventHandler('pma-voice:setTalkingMode', function(index)
    set('vr', index)
    flush()
end)
