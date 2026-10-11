--[[
    NAYZEEE WorldControl - Client Traffic & Population
    discord.gg/nayzeeedev
]]

Traffic = {}

-- Localised natives (cheaper lookups inside the per-frame loop)
local SetPedDensityMultiplierThisFrame = SetPedDensityMultiplierThisFrame
local SetVehicleDensityMultiplierThisFrame = SetVehicleDensityMultiplierThisFrame
local SetParkedVehicleDensityMultiplierThisFrame = SetParkedVehicleDensityMultiplierThisFrame
local SetRandomVehicleDensityMultiplierThisFrame = SetRandomVehicleDensityMultiplierThisFrame
local SetScenarioPedDensityMultiplierThisFrame = SetScenarioPedDensityMultiplierThisFrame
local Wait = Wait

local density = NWC.Copy(Config.Traffic.defaults)
local services = NWC.Copy(Config.Traffic.services)
local loopRunning = false
local loopId = 0
local popArea = nil

-- ══════════════════════════════════════════════════════════════
-- PURGE (force-clear existing population so lowering density
-- takes effect immediately instead of waiting for a natural despawn)
-- ══════════════════════════════════════════════════════════════

local purgeActive = false

function Traffic.Purge()
    if not Config.Traffic.purge.enabled or purgeActive then return end
    purgeActive = true

    CreateThread(function()
        local cfg = Config.Traffic.purge
        local elapsed = 0
        while elapsed < cfg.duration do
            local coords = GetEntityCoords(PlayerPedId())
            ClearAreaOfPeds(coords.x, coords.y, coords.z, cfg.radius, 0)
            ClearAreaOfVehicles(coords.x, coords.y, coords.z, cfg.radius, false, false, false, false, false)
            Wait(cfg.interval)
            elapsed = elapsed + cfg.interval
        end
        purgeActive = false
    end)
end

RegisterNetEvent(EV .. 'purge', function()
    Traffic.Purge()
end)

-- ══════════════════════════════════════════════════════════════
-- DENSITY
-- ══════════════════════════════════════════════════════════════

local function IsDefault()
    for _, key in ipairs(NWC.DensityKeys) do
        if density[key] ~= 1.0 then return false end
    end
    return true
end

-- 'frame' mode: the only per-frame loop, and it only exists while densities differ from GTA default
local function StartFrameLoop()
    if loopRunning then return end
    loopRunning = true
    loopId = loopId + 1
    local myId = loopId

    CreateThread(function()
        while loopRunning and myId == loopId do
            local d = density
            SetPedDensityMultiplierThisFrame(d.pedestrians)
            SetVehicleDensityMultiplierThisFrame(d.vehicles)
            SetParkedVehicleDensityMultiplierThisFrame(d.parkedCars)
            SetRandomVehicleDensityMultiplierThisFrame(d.randomVehicles)
            SetScenarioPedDensityMultiplierThisFrame(d.scenarioPeds, d.scenarioPeds)
            Wait(0)
        end
    end)
end

-- 'zero' mode: persistent natives, nothing runs per frame
local function ApplyZeroMode()
    local function budget(v) return math.floor(math.min(v, 1.0) * 3 + 0.5) end
    SetPedPopulationBudget(budget(math.max(density.pedestrians, density.scenarioPeds)))
    SetVehiclePopulationBudget(budget(math.max(density.vehicles, density.randomVehicles)))

    if popArea then
        RemovePopMultiplierArea(popArea, false)
        popArea = nil
    end
    if not IsDefault() then
        popArea = AddPopMultiplierArea(-10000.0, -10000.0, -1000.0, 10000.0, 10000.0, 5000.0,
            math.min(density.pedestrians, 1.0) + 0.0, math.min(density.vehicles, 1.0) + 0.0, false, false)
    end
end

local function RefreshDensity()
    if Config.Performance.densityMode == 'zero' then
        ApplyZeroMode()
        return
    end
    if IsDefault() then
        loopRunning = false -- back to 0.00ms
    else
        StartFrameLoop()
    end
end

-- ══════════════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════════════

local function ApplyServices(onlyEnforceDisabled)
    local s = services
    local me = PlayerId()

    if not (onlyEnforceDisabled and s.dispatch) then
        for i = 1, 15 do EnableDispatchService(i, s.dispatch) end
    end
    if not (onlyEnforceDisabled and s.garbageTrucks) then SetGarbageTrucks(s.garbageTrucks) end
    if not (onlyEnforceDisabled and s.randomBoats) then SetRandomBoats(s.randomBoats) end
    if not (onlyEnforceDisabled and s.randomTrains) then SetRandomTrains(s.randomTrains) end
    if not (onlyEnforceDisabled and s.randomCops) then
        SetCreateRandomCops(s.randomCops)
        SetCreateRandomCopsNotOnScenarios(s.randomCops)
        SetCreateRandomCopsOnScenarios(s.randomCops)
    end
    if not (onlyEnforceDisabled and s.distantSirens) then DistantCopCarSirens(s.distantSirens) end

    if not s.wantedLevel then
        SetMaxWantedLevel(0)
        if GetPlayerWantedLevel(me) > 0 then
            ClearPlayerWantedLevel(me)
        end
    elseif not onlyEnforceDisabled then
        SetMaxWantedLevel(5)
    end
end

-- Some frameworks/scripts re-enable services; quietly enforce the disabled ones
CreateThread(function()
    while true do
        Wait(15000)
        if Current.traffic then ApplyServices(true) end
    end
end)

-- ══════════════════════════════════════════════════════════════
-- APPLY FROM SERVER
-- ══════════════════════════════════════════════════════════════

function Traffic.Apply(traffic)
    local decreased = false
    for _, key in ipairs(NWC.DensityKeys) do
        local value = tonumber(traffic.density and traffic.density[key]) or 1.0
        if value < (density[key] or 1.0) then decreased = true end
        density[key] = value + 0.0
    end

    local servicesChanged = Current.traffic == nil
    if traffic.services then
        for _, key in ipairs(NWC.ServiceKeys) do
            if traffic.services[key] ~= nil and traffic.services[key] ~= services[key] then
                services[key] = traffic.services[key]
                servicesChanged = true
            end
        end
    end

    Current.traffic = { density = NWC.Copy(density), services = NWC.Copy(services) }

    if decreased then Traffic.Purge() end
    RefreshDensity()
    if servicesChanged then ApplyServices(false) end
end

function Traffic.Cleanup()
    loopRunning = false
    if popArea then
        RemovePopMultiplierArea(popArea, false)
        popArea = nil
    end
    if Config.Performance.densityMode == 'zero' then
        SetPedPopulationBudget(3)
        SetVehiclePopulationBudget(3)
    end
end
