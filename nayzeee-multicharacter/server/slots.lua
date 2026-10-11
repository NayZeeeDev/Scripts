if not NAYZEEE_LOCK_OK then return end

Slots = {}

local discordCache = {}   -- [discordId] = { roles = {}, at = os.time() }

local function discordRoles(src)
    local cfg = Config.Slots.discord
    if not cfg.enabled or cfg.guild == '' then return nil end
    local token = GetConvar(ServerConfig.DiscordTokenConvar, '')
    if token == '' then return nil end
    local did = GetPlayerIdentifierByType(src, 'discord')
    if not did then return nil end
    did = did:gsub('^discord:', '')

    local cached = discordCache[did]
    if cached and os.time() - cached.at < (cfg.cacheMinutes or 10) * 60 then return cached.roles end

    local p = promise.new()
    PerformHttpRequest(('https://discord.com/api/v10/guilds/%s/members/%s'):format(cfg.guild, did), function(code, body)
        if code == 200 then
            local data = NZ.Decode(body)
            p:resolve(data and data.roles or {})
        else
            p:resolve({})
        end
    end, 'GET', '', { Authorization = 'Bot ' .. token })
    SetTimeout(5000, function() if p.state == 0 then p:resolve({}) end end)
    local roles = Citizen.Await(p)
    discordCache[did] = { roles = roles, at = os.time() }
    return roles
end

-- Returns total, info (for Settings > Account and /mc_slotsinfo)
function Slots.Get(src, owner)
    local cfg = Config.Slots
    local base, source = cfg.default, 'default'

    for perm, n in pairs(cfg.ace or {}) do
        if n > base and IsPlayerAceAllowed(src, perm) then base, source = n, 'ace:' .. perm end
    end

    for _, t in ipairs({ 'license', 'license2' }) do
        local lic = GetPlayerIdentifierByType(src, t)
        local n = lic and cfg.licenses[lic]
        if n and n > base then base, source = n, 'license' end
    end

    local roles = discordRoles(src)
    if roles then
        for i = 1, #roles do
            local n = cfg.discord.roles[roles[i]]
            if n and n > base then base, source = n, 'discord' end
        end
    end

    local extra = DB.Extra(owner)
    local total = math.max(1, math.min(cfg.max, base + extra))
    return total, { base = base, source = source, extra = extra, total = total, max = cfg.max }
end
