--[[
    NAYZEEE WorldControl - Server
    discord.gg/nayzeeedev
]]

local RESOURCE = GetCurrentResourceName()
local VERSION = GetResourceMetadata(RESOURCE, 'version', 0) or '2.0.0'
EV = 'nayzeee-worldcontrol:'

-- ═══════════════════════════════════════════════════════════════════════════════
-- NAYZEEE DEVELOPMENT - Server Console Banner
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    print(([[
^2
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
^0
    ^3NAYZEEE WORLDCONTROL^0
    ^2Version: %s^0
    ^5Developer: NAYZEEE DEVELOPMENT^0
    ^6Discord: discord.gg/nayzeeedev^0
]]):format(VERSION))

    if RESOURCE ~= 'nayzeee-worldcontrol' then
        print(('^3[NAYZEEE-WORLDCONTROL]^0 Running as "%s" - exports use this name.'):format(RESOURCE))
    end
    for _, conflict in ipairs({ 'cd_easytime', 'qb-weathersync', 'vSync', 'nayzeee-traffic', 'weathersync' }) do
        if GetResourceState(conflict) == 'started' then
            print(('^1[NAYZEEE-WORLDCONTROL] "%s" is also running - stop it, both will fight over weather/time/traffic.^0'):format(conflict))
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════

State = {
    weather = {
        current = Config.Weather.default,
        method = Config.Weather.method,
        dynamic = Config.Weather.dynamic,
        instant = Config.Weather.instant,
        interval = Config.Weather.interval,
        nextChange = 0,
        forecast = {},
        real = nil,             -- { city, description, temp } when real weather is active
    },
    time = {
        minutes = Config.Time.default.hour * 60 + Config.Time.default.minute, -- float, 0-1440
        frozen = false,
        msPerMinute = Config.Time.msPerGameMinute,
        method = Config.Time.method,
        instant = Config.Time.instant,
    },
    world = {
        blackout = Config.World.blackout,
        snowOnGround = Config.World.snowOnGround,
        wind = Config.World.wind,
        windDirection = Config.World.windDirection,
        rain = Config.World.rain,
    },
    traffic = {
        density = NWC.Copy(Config.Traffic.defaults),
        services = NWC.Copy(Config.Traffic.services),
    },
    restart = {
        active = false,
        endsAt = 0,
        duration = 0,
    },
}

local ActivityLog = {}
local OpenAdmins = {}   -- [src] = true while the panel is open
local dirty = false

-- ══════════════════════════════════════════════════════════════
-- PERSISTENCE (server KVP survives resource/server restarts)
-- ══════════════════════════════════════════════════════════════

function MarkDirty()
    dirty = true
end

local function SaveState()
    local data = {
        weather = {
            current = State.weather.current,
            method = State.weather.method,
            dynamic = State.weather.dynamic,
            instant = State.weather.instant,
            interval = State.weather.interval,
        },
        time = {
            minutes = State.time.minutes,
            frozen = State.time.frozen,
            msPerMinute = State.time.msPerMinute,
            method = State.time.method,
            instant = State.time.instant,
        },
        world = State.world,
        traffic = State.traffic,
    }
    SetResourceKvp(Config.StorageKey, json.encode(data))
    dirty = false
end

local function MergeInto(target, saved)
    if type(saved) ~= 'table' then return end
    for k, v in pairs(saved) do
        if target[k] ~= nil and type(v) == type(target[k]) then
            if type(v) == 'table' then
                MergeInto(target[k], v)
            else
                target[k] = v
            end
        end
    end
end

local function LoadState()
    local encoded = GetResourceKvpString(Config.StorageKey)
    if not encoded then
        -- Migrate from the old nayzeee-traffic resource if it shared this KVP store
        local legacy = GetResourceKvpString('nayzeee_traffic:settings:server')
        if legacy then
            local ok, saved = pcall(json.decode, legacy)
            if ok and type(saved) == 'table' then MergeInto(State.traffic.density, saved) end
        end
        return
    end

    local ok, saved = pcall(json.decode, encoded)
    if not ok or type(saved) ~= 'table' then return end

    MergeInto(State, saved)
    if not NWC.WeatherById[State.weather.current] then
        State.weather.current = Config.Weather.default
    end
    -- Config method wins on restart if the owner changed it in config
    State.weather.method = Config.Weather.method == 'real' and 'real' or State.weather.method
    State.time.method = Config.Time.method == 'real' and 'real' or State.time.method
    State.time.minutes = State.time.minutes % 1440
end

LoadState()

CreateThread(function()
    while true do
        Wait(10000)
        if dirty then SaveState() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == RESOURCE then SaveState() end
end)

-- ══════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ══════════════════════════════════════════════════════════════

local ESX, QBCore

local function GetESX()
    if ESX == nil and GetResourceState('es_extended') == 'started' then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        ESX = ok and obj or false
    end
    return ESX or nil
end

local function GetQB()
    if QBCore == nil and GetResourceState('qb-core') == 'started' then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        QBCore = ok and obj or false
    end
    return QBCore or nil
end

function HasPermission(src)
    if src == 0 then return true end -- server console
    if not Config.Permissions.enabled then return true end

    for _, ace in ipairs(Config.Permissions.acePermissions) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end

    for _, group in ipairs(Config.Permissions.allowedGroups) do
        if IsPlayerAceAllowed(src, 'group.' .. group) then return true end
    end

    if #Config.Permissions.identifiers > 0 then
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            for _, allowed in ipairs(Config.Permissions.identifiers) do
                if id == allowed then return true end
            end
        end
    end

    local esx = GetESX()
    if esx then
        local xPlayer = esx.GetPlayerFromId(src)
        if xPlayer then
            local group = xPlayer.getGroup and xPlayer.getGroup()
            for _, allowed in ipairs(Config.Permissions.allowedGroups) do
                if group == allowed then return true end
            end
        end
    end

    local qb = GetQB()
    if qb and qb.Functions and qb.Functions.HasPermission then
        for _, allowed in ipairs(Config.Permissions.allowedGroups) do
            local ok, result = pcall(qb.Functions.HasPermission, src, allowed)
            if ok and result then return true end
        end
    end

    return false
end

-- ══════════════════════════════════════════════════════════════
-- NOTIFY & LOG
-- ══════════════════════════════════════════════════════════════

function NotifyPlayer(src, message, kind)
    if src == 0 then
        print(('[NAYZEEE-WORLDCONTROL] %s'):format(message))
        return
    end
    TriggerClientEvent(EV .. 'notify', src, message, kind or 'info')
end

local function SendWebhook(name, text)
    if not Config.Log.webhook or Config.Log.webhook == '' then return end
    PerformHttpRequest(Config.Log.webhook, function() end, 'POST', json.encode({
        username = 'NAYZEEE WorldControl',
        embeds = { {
            title = 'World Change',
            description = ('**%s** %s'):format(name, text),
            color = 569250, -- #08afa2
            footer = { text = 'discord.gg/nayzeeedev' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

function AddLog(src, text, icon)
    local name = src == 0 and 'Server' or (GetPlayerName(src) or ('#' .. tostring(src)))
    table.insert(ActivityLog, 1, {
        at = os.date('%H:%M:%S'),
        name = name,
        text = text,
        icon = icon or 'pen',
    })
    while #ActivityLog > Config.Log.size do
        table.remove(ActivityLog)
    end
    if Config.Log.console then
        print(('^3[NAYZEEE-WORLDCONTROL]^0 %s %s'):format(name, text))
    end
    SendWebhook(name, text)
end

-- ══════════════════════════════════════════════════════════════
-- SYNC
-- ══════════════════════════════════════════════════════════════

function TimePayload(snap)
    local total = State.time.minutes
    local h = math.floor(total / 60) % 24
    local m = math.floor(total % 60)
    local s = math.floor((total * 60) % 60)
    return {
        hour = h,
        minute = m,
        second = s,
        frozen = State.time.frozen,
        msPerMinute = State.time.msPerMinute,
        method = State.time.method,
        snap = snap,    -- 'instant' | 'smooth' | 'drift'
    }
end

function WeatherPayload(instant)
    return {
        current = State.weather.current,
        instant = instant,
        transitionTime = Config.Weather.transitionTime,
    }
end

function BuildFullState()
    return {
        weather = WeatherPayload(true),
        time = TimePayload('instant'),
        world = State.world,
        traffic = State.traffic,
        restart = RestartPayload(),
    }
end

function RestartPayload()
    local r = State.restart
    return {
        active = r.active,
        remaining = r.active and math.max(0, r.endsAt - os.time()) or 0,
        duration = r.duration,
    }
end

-- Send a partial state update to everyone (or one player)
function Broadcast(data, target)
    TriggerClientEvent(EV .. 'sync', target or -1, data)
end

function BuildAdminData()
    return {
        weather = {
            current = State.weather.current,
            method = State.weather.method,
            dynamic = State.weather.dynamic,
            instant = State.weather.instant,
            interval = State.weather.interval,
            nextChangeIn = State.weather.dynamic and math.max(0, State.weather.nextChange - os.time()) or nil,
            forecast = State.weather.forecast,
            real = State.weather.real,
            realAvailable = Config.Weather.real.apiKey ~= '' and Config.Weather.real.apiKey ~= 'CHANGE_ME',
        },
        time = TimePayload(),
        timeInstant = State.time.instant,
        world = State.world,
        traffic = State.traffic,
        restart = RestartPayload(),
        log = ActivityLog,
        players = #GetPlayers(),
    }
end

-- Push fresh panel data to every admin that currently has the panel open
function RefreshAdmins()
    if not next(OpenAdmins) then return end
    local data = BuildAdminData()
    for src in pairs(OpenAdmins) do
        TriggerClientEvent(EV .. 'adminData', src, data)
    end
end

-- Keep forecast countdowns & clock fresh while someone has the panel open
CreateThread(function()
    while true do
        Wait(5000)
        RefreshAdmins()
    end
end)

-- ══════════════════════════════════════════════════════════════
-- CLIENT EVENTS
-- ══════════════════════════════════════════════════════════════

RegisterNetEvent(EV .. 'requestState', function()
    local src = source
    Broadcast(BuildFullState(), src)
end)

RegisterNetEvent(EV .. 'requestOpen', function()
    local src = source
    if not HasPermission(src) then
        NotifyPlayer(src, 'You do not have permission to use World Control', 'error')
        return
    end
    OpenAdmins[src] = true
    TriggerClientEvent(EV .. 'open', src, BuildAdminData())
end)

RegisterNetEvent(EV .. 'closed', function()
    OpenAdmins[source] = nil
end)

-- Every panel change goes through one validated action dispatcher
local lastAction = {}

RegisterNetEvent(EV .. 'action', function(name, data)
    local src = source
    if not HasPermission(src) then
        NotifyPlayer(src, 'You do not have permission to use World Control', 'error')
        return
    end
    if type(name) ~= 'string' or not Actions[name] then return end

    -- Light flood protection (slider spam)
    local now = GetGameTimer()
    if lastAction[src] and now - lastAction[src] < 50 then return end
    lastAction[src] = now

    local ok, err = pcall(Actions[name], src, type(data) == 'table' and data or {})
    if not ok then
        print(('^1[NAYZEEE-WORLDCONTROL] Action "%s" failed: %s^0'):format(name, err))
        NotifyPlayer(src, 'Something went wrong - check the server console', 'error')
        return
    end

    MarkDirty()
    RefreshAdmins()
end)

AddEventHandler('playerDropped', function()
    OpenAdmins[source] = nil
    lastAction[source] = nil
end)
