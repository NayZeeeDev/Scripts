-- Discord profile pictures (static + animated). Token comes from a server-only convar:
--   set nz_squads_bot_token "YOUR_BOT_TOKEN"
Discord = {}

local cfg     = Config.Discord
local token   = GetConvar('nz_squads_bot_token', '')
local cache   = {}   -- [discordId] = { data, expires }
local waiting = {}   -- [discordId] = { callbacks }
local API     = 'https://discord.com/api/v10'
local CDN     = 'https://cdn.discordapp.com'

local enabled = cfg.Enabled and token ~= ''
if cfg.Enabled and token == '' then
    print('^3[nayzeee-squads]^7 Discord avatars are on but ^3nz_squads_bot_token^7 is not set. Initials will be used.')
end

local function discordId(src)
    local id = GetPlayerIdentifierByType(src, 'discord')
    return id and id:gsub('^discord:', '') or nil
end

function Discord.UserId(src) return discordId(src) end
function Discord.Token() return token end

local function build(id, hash, guild)
    if type(hash) ~= 'string' or hash == '' then return nil end
    local base = guild
        and ('%s/guilds/%s/users/%s/avatars/%s'):format(CDN, cfg.GuildId, id, hash)
        or ('%s/avatars/%s/%s'):format(CDN, id, hash)
    local q = ('?size=%d'):format(cfg.Size)
    return {
        static = base .. '.png' .. q,
        anim   = hash:sub(1, 2) == 'a_' and (base .. '.gif' .. q) or nil,
    }
end

local function request(url, cb, tries)
    tries = tries or 0
    PerformHttpRequest(url, function(status, body)
        if status == 429 and tries < 3 then
            local wait = 1500
            local ok, data = pcall(json.decode, body or '')
            if ok and type(data) == 'table' and data.retry_after then wait = math.ceil(data.retry_after * 1000) + 100 end
            return SetTimeout(wait, function() request(url, cb, tries + 1) end)
        end
        if status ~= 200 or not body then return cb(nil) end
        local ok, data = pcall(json.decode, body)
        cb(ok and data or nil)
    end, 'GET', '', { Authorization = 'Bot ' .. token })
end

local function finish(id, data)
    cache[id] = { data = data, expires = os.time() + cfg.CacheMinutes * 60 }
    local list = waiting[id] or {}
    waiting[id] = nil
    for i = 1, #list do list[i](data) end
end

--- Cached avatar or nil, never makes a request.
function Discord.Peek(src)
    if not enabled then return nil end
    local id = discordId(src)
    local c = id and cache[id]
    return c and c.expires > os.time() and c.data or nil
end

--- Resolves the avatar asynchronously. cb(data|nil)
function Discord.Get(src, cb)
    if not enabled then return cb(nil) end
    local id = discordId(src)
    if not id then return cb(nil) end

    local c = cache[id]
    if c and c.expires > os.time() then return cb(c.data) end
    if waiting[id] then
        local w = waiting[id]
        w[#w + 1] = cb
        return
    end
    waiting[id] = { cb }

    local function fromUser()
        request(('%s/users/%s'):format(API, id), function(u)
            finish(id, u and build(id, u.avatar) or nil)
        end)
    end

    if cfg.PreferServerAvatar and cfg.GuildId ~= '' then
        request(('%s/guilds/%s/members/%s'):format(API, cfg.GuildId, id), function(m)
            if m and m.avatar then return finish(id, build(id, m.avatar, true)) end
            if m and m.user and m.user.avatar then return finish(id, build(id, m.user.avatar)) end
            fromUser()
        end)
    else
        fromUser()
    end
end

-- warm the cache as players connect so the first squad sync already has pictures
AddEventHandler('playerJoining', function()
    local src = source
    Discord.Get(src, function() end)
end)
