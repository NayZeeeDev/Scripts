--[[ Discord avatars (static + animated). Token comes from the server-only convar nayzeee_tuning_discord_token. ]]

Avatars = {}

local D = Config.Discord
local token = GetConvar('nayzeee_tuning_discord_token', '')
local byId = {}        -- identifier -> url
local fetchedAt = {}   -- identifier -> os.time()
local pending = {}

local function enabled() return D.Avatars and token ~= '' end

CreateThread(function()
    while not DB or not DB.Ready do Wait(500) end
    local rows = MySQL.query.await('SELECT identifier, avatar, avatar_at FROM nz_tuning_tablet WHERE avatar IS NOT NULL') or {}
    for _, r in ipairs(rows) do byId[r.identifier], fetchedAt[r.identifier] = r.avatar, r.avatar_at or 0 end
    if D.Avatars and token == '' then print('^3[nayzeee-tuning] Discord avatars are on but no token is set (set nayzeee_tuning_discord_token "..." in server.cfg)^7') end
end)

function Avatars.Of(identifier) return identifier and byId[identifier] or nil end

local function discordId(src)
    local id = GetPlayerIdentifierByType(src, 'discord')
    return id and id:gsub('^discord:', '') or nil
end

local function urlFor(did, user)
    local size = D.Size or 128
    if user.avatar then
        local animated = D.Animated and user.avatar:sub(1, 2) == 'a_'
        return ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=%d'):format(did, user.avatar, animated and 'gif' or 'png', size)
    end
    -- no custom avatar: Discord's default one
    local n = tonumber(did)
    local idx = n and ((n >> 22) % 6) or 0
    return ('https://cdn.discordapp.com/embed/avatars/%d.png'):format(idx)
end

-- refresh one player's avatar; cb(url | nil) when done (async)
function Avatars.Refresh(src, force, cb)
    local identifier = Bridge.GetIdentifier(src)
    if not identifier or not enabled() then if cb then cb(Avatars.Of(identifier)) end return end
    local fresh = fetchedAt[identifier] and (os.time() - fetchedAt[identifier]) < (D.RefreshMinutes or 30) * 60
    if fresh and not force then if cb then cb(byId[identifier]) end return end
    local did = discordId(src)
    if not did or pending[identifier] then if cb then cb(byId[identifier]) end return end
    pending[identifier] = true
    PerformHttpRequest(('https://discord.com/api/v10/users/%s'):format(did), function(code, body)
        pending[identifier] = nil
        local url
        if code == 200 and body then
            local ok, user = pcall(json.decode, body)
            if ok and type(user) == 'table' then url = urlFor(did, user) end
        end
        if url then
            byId[identifier], fetchedAt[identifier] = url, os.time()
            MySQL.insert('INSERT INTO nz_tuning_tablet (identifier, avatar, avatar_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE avatar = VALUES(avatar), avatar_at = VALUES(avatar_at)',
                { identifier, url, os.time() })
        end
        if cb then cb(byId[identifier]) end
    end, 'GET', '', { Authorization = 'Bot ' .. token, ['User-Agent'] = 'nayzeee-tuning (FiveM)' })
end

-- grab it when someone joins so customers have one before they ever open a tablet
AddEventHandler('playerJoining', function()
    local src = source
    if not enabled() then return end
    CreateThread(function()
        for _ = 1, 8 do                       -- wait for the framework to load the character
            Wait(15000)
            if not GetPlayerName(src) then return end
            if Bridge.GetIdentifier(src) then return Avatars.Refresh(src) end
        end
    end)
end)
