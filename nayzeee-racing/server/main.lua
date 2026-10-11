if not NAYZEEE_LOCK_OK then return end

--[[
    Core: sessions (source -> racer profile), the request router used by the tablet,
    realtime rooms, notifications and Discord logs.
]]

Core = {
    Sessions = {},   -- [source] = profileId
    Online   = {},   -- [profileId] = source
    Active   = {},   -- [profileId] = lobbyId (pending or racing)
    Lobbies  = {},   -- [lobbyId] = Lobby
}

local Handlers = {}
local Rooms = {}           -- [room] = { [source] = true }
local rate = {}            -- [source] = { t, n }

-- ── router ──────────────────────────────────────────────────────────────
-- Register a tablet request. opts.profile = requires a signed in profile (default true)
function Handle(name, fn, opts)
    Handlers[name] = { fn = fn, profile = not (opts and opts.profile == false) }
end

local function throttled(src)
    local now = GetGameTimer()
    local r = rate[src]
    if not r or now - r.t > 1000 then rate[src] = { t = now, n = 1 } return false end
    r.n = r.n + 1
    return r.n > 25
end

lib.callback.register('nzr:req', function(src, name, data)
    local h = Handlers[name]
    if not h then return { error = 'ERR_UNKNOWN' } end
    if throttled(src) then return { error = 'ERR_RATE' } end
    local profile
    if h.profile then
        profile = Profiles.BySource(src)
        if not profile then return { error = 'ERR_NO_PROFILE' } end
    end
    local ok, res, err, extra = pcall(h.fn, src, profile, type(data) == 'table' and data or {})
    if not ok then
        Log('error', 'Request %s failed: %s', name, tostring(res))
        return { error = 'ERR_GENERIC' }
    end
    if err then return { error = err, extra = extra } end
    return { data = res }
end)

-- ── realtime rooms ──────────────────────────────────────────────────────
function Push(src, channel, data)
    TriggerClientEvent('nzr:push', src, channel, data)
end

function Publish(room, data)
    local subs = Rooms[room]
    if not subs then return end
    for src in pairs(subs) do TriggerClientEvent('nzr:push', src, room, data) end
end

function Subscribe(src, room)
    Rooms[room] = Rooms[room] or {}
    Rooms[room][src] = true
end

function Unsubscribe(src, room)
    if Rooms[room] then
        Rooms[room][src] = nil
        if not next(Rooms[room]) then Rooms[room] = nil end
    end
end

Handle('room:join', function(src, _, d)
    local room = tostring(d.room or '')
    if room ~= 'lobbies' and not room:match('^lobby:%w+$') then return nil, 'ERR_GENERIC' end
    Subscribe(src, room)
    return true
end)

Handle('room:leave', function(src, _, d)
    Unsubscribe(src, tostring(d.room or ''))
    return true
end)

-- ── notifications ───────────────────────────────────────────────────────
function Notify(src, message, kind)
    TriggerClientEvent('nzr:notify', src, message, kind)
end

-- target: 'all' | 'profiles'
function NotifyGroup(target, message, kind)
    if not target then return end
    if target == 'all' then
        TriggerClientEvent('nzr:notify', -1, message, kind)
    elseif target == 'profiles' then
        for src in pairs(Core.Sessions) do Notify(src, message, kind) end
    end
end

-- ── Discord logs ────────────────────────────────────────────────────────
function DiscordLog(kind, title, lines)
    local hook = Config.Logs.Webhook
    if not hook or hook == '' or not Config.Logs[kind] then return end
    local accent = tonumber((Config.UI.Accent or '#08afa2'):gsub('#', ''), 16)
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        embeds = { {
            title = title,
            description = table.concat(lines, '\n'),
            color = accent,
            footer = { text = 'nayzeee-racing' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- ── permissions ─────────────────────────────────────────────────────────
function CanManageTracks(src)
    local tb = Config.Trackbuilder
    if Bridge.IsAdmin(src) then return true end
    if tb.AdminOnly then return false end
    if tb.AllowCreation then return true end
    return IsPlayerAceAllowed(src, tb.AcePermission)
end

function CanCreateEvents(src)
    if Config.Events.AllowCreation then return true end
    return Bridge.IsAdmin(src) or IsPlayerAceAllowed(src, Config.Events.AcePermission)
end

-- ── boot data for the tablet ────────────────────────────────────────────
Handle('boot', function(src)
    local profile = Profiles.SignIn(src)
    return {
        profile = profile and Profiles.Dto(profile) or nil,
        canTracks = CanManageTracks(src),
        canEvents = CanCreateEvents(src),
        activeLobby = profile and Core.Active[profile.id] or nil,
        config = NZR.PublicConfig(),
    }
end, { profile = false })

Handle('balance', function(src, _, d)
    local cur = d.currency == 'crypto' and 'crypto' or 'money'
    return Bridge.GetBalance(src, cur)
end)

Handle('vehicles', function(src)
    return Bridge.GetOwnedVehicles(src)
end)

-- ── items / commands / lifecycle ────────────────────────────────────────
if Config.General.Item then
    Bridge.RegisterUsableItem(Config.General.Item, function(src)
        TriggerClientEvent('nzr:useTablet', src)
    end)
end

local function dropped(src)
    rate[src] = nil
    for room, subs in pairs(Rooms) do
        subs[src] = nil
        if not next(subs) then Rooms[room] = nil end
    end
    local pid = Core.Sessions[src]
    if pid then
        local lid = Core.Active[pid]
        local lobby = lid and Core.Lobbies[lid]
        if lobby then lobby:Disconnected(pid) end
        Profiles.SignOut(src)
    end
end

AddEventHandler('playerDropped', function() dropped(source) end)
Bridge.OnLogout(dropped)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    for _, lobby in pairs(Core.Lobbies) do
        if lobby.status == LobbyStatus.PENDING then lobby:Disband('LOBBY_DISBANDED', true) end
    end
end)
