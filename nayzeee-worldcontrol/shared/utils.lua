--[[
    NAYZEEE WorldControl - Shared helpers
    discord.gg/nayzeeedev
]]

NWC = NWC or {}

NWC.DensityKeys = { 'pedestrians', 'vehicles', 'parkedCars', 'randomVehicles', 'scenarioPeds' }

NWC.ServiceKeys = { 'dispatch', 'garbageTrucks', 'randomBoats', 'randomTrains', 'randomCops', 'wantedLevel', 'distantSirens' }

-- Weather lookup: NWC.WeatherById['RAIN'] = { id, label, icon, build? }
NWC.WeatherById = {}
for _, w in ipairs(Config.WeatherTypes) do
    NWC.WeatherById[w.id] = w
end

NWC.TrafficPresetById = {}
for _, p in ipairs(Config.TrafficPresets) do
    NWC.TrafficPresetById[p.id] = p
end

NWC.SceneById = {}
for _, s in ipairs(Config.Scenes) do
    NWC.SceneById[s.id] = s
end

function NWC.Clamp(value, min, max)
    value = tonumber(value)
    if not value or value ~= value then return nil end -- nil or NaN
    if value < min then return min end
    if value > max then return max end
    return value
end

function NWC.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

function NWC.Copy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local out = {}
    for k, v in pairs(tbl) do out[k] = NWC.Copy(v) end
    return out
end

function NWC.Debug(...)
    if Config.Debug then
        print('^3[NAYZEEE-WORLDCONTROL]^0', ...)
    end
end
