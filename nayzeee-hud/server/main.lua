-- HUD server side: stress (qb-hud compatible events). Kept in a local table so it can't
-- collide with the squads module's server globals.

local S = Config.Stress
local framework = 'standalone'
local QBCore
local memory = {} -- standalone stress per player

local function detect()
    local f = Config.Framework
    if f == 'qbcore' then f = 'qb' end
    if f ~= 'auto' then return f end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

CreateThread(function()
    framework = detect()
    if framework == 'qb' then QBCore = exports['qb-core']:GetCoreObject() end
end)

local function getPlayer(src)
    if framework == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if framework == 'qb' and QBCore then return QBCore.Functions.GetPlayer(src) end
end

local function jobWhitelisted(player)
    local job = player and player.PlayerData and player.PlayerData.job
    return job and (S.whitelistedJobs[job.name] or (job.type and S.whitelistedJobs[job.type]))
end

local function changeStress(src, delta)
    if not S.enabled then return end
    if framework == 'qb' or framework == 'qbx' then
        local player = getPlayer(src)
        if not player then return end
        if delta > 0 and jobWhitelisted(player) then return end
        local md = player.PlayerData.metadata or {}
        local value = math.max(0, math.min(100, (tonumber(md.stress) or 0) + delta))
        if player.Functions and player.Functions.SetMetaData then
            player.Functions.SetMetaData('stress', value)
        elseif player.SetMetaData then
            player.SetMetaData('stress', value)
        end
        TriggerClientEvent('hud:client:UpdateStress', src, value)
    elseif framework == 'esx' then
        if GetResourceState('esx_status') ~= 'started' then return end
        -- esx_status runs 0 - 1,000,000
        TriggerClientEvent(delta > 0 and 'esx_status:add' or 'esx_status:remove', src, 'stress', math.abs(delta) * 10000)
    else
        local value = math.max(0, math.min(100, (memory[src] or 0) + delta))
        memory[src] = value
        TriggerClientEvent('hud:client:UpdateStress', src, value)
    end
end

RegisterNetEvent('hud:server:GainStress', function(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    changeStress(source, math.min(100, math.floor(amount)))
end)

RegisterNetEvent('hud:server:RelieveStress', function(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    changeStress(source, -math.min(100, math.floor(amount)))
end)

AddEventHandler('playerDropped', function() memory[source] = nil end)

-- server-side scripts can use these directly
exports('GainStress', function(src, amount) changeStress(src, math.abs(tonumber(amount) or 0)) end)
exports('RelieveStress', function(src, amount) changeStress(src, -math.abs(tonumber(amount) or 0)) end)

-- Players online for the player info widget --------------------------------------------
local function updatePlayers()
    GlobalState.nhud_players = GetNumPlayerIndices()
end
GlobalState.nhud_maxPlayers = GetConvarInt('sv_maxclients', 48)
AddEventHandler('playerJoining', updatePlayers)
AddEventHandler('playerDropped', function() SetTimeout(500, updatePlayers) end)
CreateThread(updatePlayers)

-- Discord pictures -------------------------------------------------------------------------
-- Uses the squads module's Discord cache when squads is on (one shared cache and rate limit),
-- otherwise its own small fetcher. Static PNG + animated GIF when the avatar is animated.
local D = Config.Discord
local token = GetConvar('nhud_discord_token', '')
if token == '' then token = GetConvar('nz_squads_bot_token', '') end
local guild = D.guildId ~= '' and D.guildId or (SquadsConfig and SquadsConfig.Discord and SquadsConfig.Discord.GuildId) or ''
local avatarCache, lastAsk = {}, {}

if D.enabled and token == '' then
    print('^3[nayzeee-hud]^7 Discord pictures are on but ^3nhud_discord_token^7 is not set. Character headshots will be used.')
end

local function discordId(src)
    local id = GetPlayerIdentifierByType(src, 'discord')
    return id and id:gsub('^discord:', '') or nil
end

local function build(id, hash, inGuild)
    if type(hash) ~= 'string' or hash == '' then return nil end
    local base = inGuild
        and ('https://cdn.discordapp.com/guilds/%s/users/%s/avatars/%s'):format(guild, id, hash)
        or ('https://cdn.discordapp.com/avatars/%s/%s'):format(id, hash)
    local q = ('?size=%d'):format(D.size)
    return { static = base .. '.png' .. q, anim = hash:sub(1, 2) == 'a_' and (base .. '.gif' .. q) or nil }
end

local function api(path, cb)
    PerformHttpRequest('https://discord.com/api/v10' .. path, function(status, body)
        if status ~= 200 or not body then return cb(nil) end
        local ok, data = pcall(json.decode, body)
        cb(ok and data or nil)
    end, 'GET', '', { Authorization = 'Bot ' .. token })
end

local function ownFetch(src, cb)
    local id = discordId(src)
    if not id then return cb(nil) end
    local c = avatarCache[id]
    if c and c.expires > os.time() then return cb(c.data) end
    local function done(data)
        avatarCache[id] = { data = data, expires = os.time() + D.cacheMinutes * 60 }
        cb(data)
    end
    local function fromUser()
        api(('/users/%s'):format(id), function(u) done(u and build(id, u.avatar) or nil) end)
    end
    if D.preferServerAvatar and guild ~= '' then
        api(('/guilds/%s/members/%s'):format(guild, id), function(m)
            if m and m.avatar then return done(build(id, m.avatar, true)) end
            if m and m.user and m.user.avatar then return done(build(id, m.user.avatar)) end
            fromUser()
        end)
    else
        fromUser()
    end
end

RegisterNetEvent('nhud:server:avatar', function()
    local src = source
    if not D.enabled or token == '' then return end
    local now = os.time()
    if lastAsk[src] and now - lastAsk[src] < 30 then return end -- one lookup per player per 30s
    lastAsk[src] = now
    local fetch = (Discord and Discord.Get) or ownFetch -- squads module cache when it's running
    fetch(src, function(data)
        if GetPlayerName(src) then TriggerClientEvent('nhud:client:avatar', src, data or false) end
    end)
end)

AddEventHandler('playerDropped', function() lastAsk[source] = nil end)
