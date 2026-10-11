--[[
    NAYZEEE WorldControl - Server Weather (dynamic cycle, forecast, real weather)
    discord.gg/nayzeeedev
]]

local groupQueue = {}   -- Remaining weathers of the group currently playing out

-- ══════════════════════════════════════════════════════════════
-- DYNAMIC CYCLE + FORECAST
-- ══════════════════════════════════════════════════════════════

local function PickGroup()
    local total = 0
    for _, g in ipairs(Config.Weather.groups) do total = total + (g.weight or 0) end
    if total <= 0 then return Config.Weather.groups[1] end

    local roll = math.random() * total
    for _, g in ipairs(Config.Weather.groups) do
        roll = roll - (g.weight or 0)
        if roll <= 0 then return g end
    end
    return Config.Weather.groups[#Config.Weather.groups]
end

-- Resolve a group's sequence into concrete weathers (chance entries rolled now)
local function ResolveSequence(group, startAfter)
    local out, started = {}, startAfter == nil
    for _, entry in ipairs(group.sequence) do
        local id = type(entry) == 'table' and entry[1] or entry
        if started then
            if type(entry) ~= 'table' or math.random(100) <= (entry.chance or 100) then
                if NWC.WeatherById[id] then out[#out + 1] = id end
            end
        elseif id == startAfter then
            started = true
        end
    end
    return out
end

local function NextFromQueue(previous)
    for _ = 1, 10 do
        if #groupQueue == 0 then
            groupQueue = ResolveSequence(PickGroup())
        end
        local nextWeather = table.remove(groupQueue, 1)
        if nextWeather and nextWeather ~= previous then
            return nextWeather
        end
    end
    return Config.Weather.default
end

function RebuildForecast()
    local forecast = {}
    local previous = State.weather.current
    for i = 1, Config.Weather.forecastLength do
        previous = NextFromQueue(previous)
        forecast[i] = previous
    end
    State.weather.forecast = forecast
end

-- Continue the natural progression from a manually chosen weather
local function SeedFromWeather(weather)
    groupQueue = {}
    for _, g in ipairs(Config.Weather.groups) do
        for _, entry in ipairs(g.sequence) do
            if (type(entry) == 'table' and entry[1] or entry) == weather then
                groupQueue = ResolveSequence(g, weather)
                break
            end
        end
        if #groupQueue > 0 then break end
    end
    RebuildForecast()
end

function ResetWeatherTimer()
    State.weather.nextChange = os.time() + State.weather.interval * 60
end

function SetWeather(weather, instant, src)
    if not NWC.WeatherById[weather] then return false end
    State.weather.current = weather
    if instant == nil then instant = State.weather.instant end

    if not State.restart.active then
        Broadcast({ weather = WeatherPayload(instant) })
    end

    if State.weather.method == 'game' then
        SeedFromWeather(weather)
        ResetWeatherTimer()
    end

    if src then
        AddLog(src, ('set weather to %s%s'):format(NWC.WeatherById[weather].label, instant and ' (instant)' or ''), NWC.WeatherById[weather].icon)
    end
    MarkDirty()
    return true
end

function AdvanceWeather(src)
    if #State.weather.forecast == 0 then RebuildForecast() end
    local nextWeather = table.remove(State.weather.forecast, 1)
    State.weather.current = nextWeather

    if not State.restart.active then
        Broadcast({ weather = WeatherPayload(State.weather.instant) })
    end

    -- Top the forecast back up
    local last = State.weather.forecast[#State.weather.forecast] or nextWeather
    while #State.weather.forecast < Config.Weather.forecastLength do
        last = NextFromQueue(last)
        State.weather.forecast[#State.weather.forecast + 1] = last
    end

    ResetWeatherTimer()
    MarkDirty()
    RefreshAdmins()

    if src then
        AddLog(src, ('skipped weather to %s'):format(NWC.WeatherById[nextWeather].label), 'forward')
    elseif Config.Debug then
        NWC.Debug('Dynamic weather ->', nextWeather)
    end
end

-- ══════════════════════════════════════════════════════════════
-- REAL WEATHER (OpenWeatherMap)
-- ══════════════════════════════════════════════════════════════

local function MapOpenWeatherId(id)
    if id >= 200 and id < 300 then return 'THUNDER' end
    if id >= 300 and id < 400 then return 'CLEARING' end
    if id == 500 then return 'CLEARING' end
    if id >= 500 and id < 600 then return 'RAIN' end
    if id == 600 or id == 620 then return 'SNOWLIGHT' end
    if id == 602 or id == 622 then return 'BLIZZARD' end
    if id >= 600 and id < 700 then return 'SNOW' end
    if id == 711 or id == 721 or id == 731 or id == 751 or id == 761 or id == 762 then return 'SMOG' end
    if id >= 700 and id < 800 then return 'FOGGY' end
    if id == 800 then return 'EXTRASUNNY' end
    if id == 801 then return 'CLEAR' end
    if id == 802 then return 'CLOUDS' end
    if id >= 803 then return 'OVERCAST' end
    return 'CLEAR'
end

RealTimezoneOffset = nil -- seconds, set by the API when available
local lastRealFetch = 0

function FetchRealWeather(src)
    local cfg = Config.Weather.real
    lastRealFetch = os.time()
    if cfg.apiKey == '' or cfg.apiKey == 'CHANGE_ME' then
        print('^1[NAYZEEE-WORLDCONTROL] Real weather needs Config.Weather.real.apiKey (openweathermap.org).^0')
        return
    end

    local url = ('https://api.openweathermap.org/data/2.5/weather?q=%s&appid=%s&units=metric')
        :format(cfg.city:gsub(' ', '%%20'), cfg.apiKey)

    PerformHttpRequest(url, function(status, body)
        if status ~= 200 or not body then
            print(('^1[NAYZEEE-WORLDCONTROL] Real weather request failed (%s) - check city & API key.^0'):format(tostring(status)))
            return
        end
        local ok, result = pcall(json.decode, body)
        if not ok or type(result) ~= 'table' or not result.weather or not result.weather[1] then return end
        if State.weather.method ~= 'real' then return end

        RealTimezoneOffset = tonumber(result.timezone)
        State.weather.real = {
            city = result.name or cfg.city,
            country = result.sys and result.sys.country or '',
            description = result.weather[1].description or '',
            temp = result.main and NWC.Round(result.main.temp or 0, 0) or nil,
        }

        if cfg.syncWind and result.wind then
            State.world.wind = NWC.Clamp(result.wind.speed or 0, 0, 12)
            State.world.windDirection = math.floor(result.wind.deg or 0) % 360
            Broadcast({ world = State.world })
        end

        local mapped = MapOpenWeatherId(tonumber(result.weather[1].id) or 800)
        if mapped ~= State.weather.current then
            State.weather.current = mapped
            if not State.restart.active then
                Broadcast({ weather = WeatherPayload(false) })
            end
            AddLog(src or 0, ('real weather in %s is now %s'):format(State.weather.real.city, NWC.WeatherById[mapped].label), 'earth-americas')
        end
        MarkDirty()
        RefreshAdmins()
    end, 'GET', '', { ['Content-Type'] = 'application/json' })
end

-- ══════════════════════════════════════════════════════════════
-- THREADS
-- ══════════════════════════════════════════════════════════════

CreateThread(function()
    math.randomseed(os.time())
    if State.weather.method == 'game' then
        SeedFromWeather(State.weather.current)
    end
    ResetWeatherTimer()

    while true do
        Wait(1000)
        if not State.restart.active then
            if State.weather.method == 'game' then
                if State.weather.dynamic and os.time() >= State.weather.nextChange then
                    AdvanceWeather()
                end
            elseif State.weather.method == 'real' then
                if os.time() - lastRealFetch >= Config.Weather.real.checkInterval * 60 then
                    FetchRealWeather()
                end
            end
        end
    end
end)
