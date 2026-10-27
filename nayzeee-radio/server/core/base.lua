--[[
    NAYZEEE RADIO - Server core helpers (NZR.Core, NZR.Callback, NZR.Command)

    Small helpers every server file uses. Nothing here runs at load time except function
    definitions; the player-lifecycle hook, the startup print and the props check run from
    threads so the bridge (loaded earlier) and every server file are ready.

      NZR.Core.B(path, ...)              pcall-guarded Bridge call: NZR.Core.B('Inv.HasItem', src, 'radio', 1)
      NZR.Core.Has(path)                 → true when that Bridge function exists
      NZR.Core.Online(src)               → bool
      NZR.Core.Identifier(src)           → character identifier (Bridge.GetIdentifier, license fallback)
      NZR.Core.Name(src)                 → 'First Last'
      NZR.Core.IsAdmin(src)              → bool (src 0 = console = true; ace Config.Admin.ace, then Bridge.IsAdmin)
      NZR.Core.IsLocalSource(src)        → true for server-originated (non-network) events
      NZR.Core.SrcCoords(src)            → vector3 | nil (server-side ped coords, never the client's word)
      NZR.Core.Distance(a, b)            → metres between two players (math.huge when unknown)
      NZR.Core.Rate(bucket, key, n, ms)  → true while under n calls per ms window (fixed window from the first call)
      NZR.Core.ClearRate(key)            forget every bucket of key (done on playerDropped)
      NZR.Core.Notify(src, msg, type, title, duration)   → Bridge.Notify (toast); msg may be a table
      NZR.Core.Webhook(kind, title, fields)             Discord embed (ServerConfig.Discord)
      NZR.Core.WebhookField(name, value, inline?)       → { name, value, inline }
      NZR.Callback(name, fn(src, ...))   lib.callback.register through a pcall: a Lua error answers
                                         { ok = false, reason = 'error' } instead of leaving the
                                         client waiting in lib.callback.await forever
      NZR.Command(name, fn(src, args, raw), adminOnly?, opts?) → command name | nil
                                         name = a Config.Commands key ('admin') or a literal name;
                                         false / '' / missing key = not registered.
                                         adminOnly: console or NZR.Core.IsAdmin, others get a toast.
                                         opts = { help = '...', params = { { name, help }, ... } }
                                         adds a chat suggestion (admins only for admin commands).
                                         fn runs in a pcall; an error is logged and answered.
      NZR.Notify / NZR.Webhook / NZR.WebhookField   aliases of the Core functions

    Events sent:
      chat:addSuggestion (S→C)         command suggestions (NZR.Command opts.help), admins only for admin commands
      nzr:ui:toast (S→C)               NZR.Core.Notify when the bridge has no Notify (normally Bridge.Notify sends it)

    Bus events emitted (server):
      player:loaded (src)              character loaded (Bridge.OnPlayerLoaded)
      player:unloaded (src)            character logged out or player dropped (Bridge.OnPlayerUnloaded)
      player:job (src, job)            Bridge.OnJobChanged
      player:dropped (src)             playerDropped (after player:unloaded)

    Startup: one console line with version, framework and inventory, and a warning when
    Config.PropsResource is not running.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Core = NZR.Core or {}
local Core = NZR.Core

local TAG = '[nayzeee-radio]'

-- ════════════════════════════════════════════════════════════════════════
-- BRIDGE ACCESS (always guarded: the bridge is an open file server owners edit,
-- core must never crash because one of its functions broke)
-- ════════════════════════════════════════════════════════════════════════

local warned = {}

local function resolve(path)
    local node = Bridge
    if type(node) ~= 'table' then return nil end
    for part in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    if type(node) == 'function' then return node end
    -- callable tables (e.g. exported function references) count as functions
    if type(node) == 'table' then
        local mt = getmetatable(node)
        if mt and mt.__call then return node end
    end
    return nil
end

function Core.Has(path)
    return resolve(path) ~= nil
end

function Core.B(path, ...)
    local fn = resolve(path)
    if not fn then
        if not warned[path] then
            warned[path] = true
            NZR.Debug('bridge function missing:', path)
        end
        return nil
    end
    local res = table.pack(pcall(fn, ...))
    if not res[1] then
        NZR.Warn(('bridge call Bridge.%s failed: %s'):format(path, tostring(res[2])))
        return nil
    end
    return table.unpack(res, 2, res.n)
end

-- ════════════════════════════════════════════════════════════════════════
-- PLAYERS
-- ════════════════════════════════════════════════════════════════════════

function Core.Online(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    return GetPlayerName(src) ~= nil
end

function Core.Identifier(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    if Core.Has('GetIdentifier') then
        local id = Core.B('GetIdentifier', src)
        if id ~= nil and id ~= '' then return tostring(id) end
        return nil
    end
    -- No bridge: fall back to the Rockstar license so persistence still works.
    return GetPlayerIdentifierByType(tostring(src), 'license')
end

function Core.Name(src)
    src = tonumber(src)
    if not src then return '?' end
    local name = Core.B('GetName', src)
    if type(name) == 'string' and name ~= '' then return name end
    return GetPlayerName(src) or ('#' .. src)
end

function Core.IsAdmin(src)
    src = tonumber(src)
    if src == 0 then return true end           -- server console
    if not src or src < 0 then return false end
    local ace = (Config.Admin and Config.Admin.ace) or 'nzr.admin'
    if IsPlayerAceAllowed(tostring(src), ace) then return true end
    if Core.Has('IsAdmin') and Core.B('IsAdmin', src) then return true end
    return false
end

-- Events triggered with TriggerEvent on the server have no player source.
function Core.IsLocalSource(src)
    if src == nil or src == '' then return true end
    local n = tonumber(src)
    return n == nil or n <= 0
end

-- ════════════════════════════════════════════════════════════════════════
-- POSITIONS (always server-side — never trust client coordinates)
-- ════════════════════════════════════════════════════════════════════════

function Core.SrcCoords(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function Core.Distance(a, b)
    local pa, pb = Core.SrcCoords(a), Core.SrcCoords(b)
    if not pa or not pb then return math.huge end
    return #(pa - pb)
end

-- ════════════════════════════════════════════════════════════════════════
-- RATE LIMIT (fixed window counters)
-- ════════════════════════════════════════════════════════════════════════

local buckets = {}

function Core.Rate(bucket, key, limit, windowMs)
    local b = buckets[bucket]
    if not b then
        b = {}
        buckets[bucket] = b
    end
    local now = GetGameTimer()
    local e = b[key]
    if not e or now - e.start >= windowMs then
        b[key] = { start = now, n = 1 }
        return true
    end
    e.n = e.n + 1
    return e.n <= limit
end

function Core.ClearRate(key)
    for _, b in pairs(buckets) do b[key] = nil end
end

-- ════════════════════════════════════════════════════════════════════════
-- NOTIFY (Bridge.Notify: our NUI toast, or the configured notify resource)
-- ════════════════════════════════════════════════════════════════════════

function Core.Notify(src, message, kind, title, duration)
    src = tonumber(src)
    if not src or (src <= 0 and src ~= -1) then
        if message then print(('%s %s'):format(TAG, type(message) == 'table' and tostring(message.message) or tostring(message))) end
        return
    end
    local data
    if type(message) == 'table' then
        data = message
    else
        data = { title = title or NZR.L('core.title'), message = message, type = kind or 'info', duration = duration or 5000 }
    end
    if Core.Has('Notify') then
        Core.B('Notify', src, data)
    else
        TriggerClientEvent('nzr:ui:toast', src, data)
    end
end

NZR.Notify = NZR.Notify or function(...) return Core.Notify(...) end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ox_lib does not reply when a callback throws - it logs and stops, and the client
-- is left in lib.callback.await forever. Every callback of this resource goes
-- through here so an error still answers.
-- ════════════════════════════════════════════════════════════════════════

function NZR.Callback(name, fn)
    if type(name) ~= 'string' or type(fn) ~= 'function' then return end
    lib.callback.register(name, function(src, ...)
        local res = table.pack(pcall(fn, src, ...))
        if res[1] then return table.unpack(res, 2, res.n) end
        print(('^1%s^7 callback %s errored and answered { ok = false } instead of hanging:'):format(TAG, name))
        print(('^1%s^7   %s'):format(TAG, tostring(res[2])))
        return { ok = false, reason = 'error' }
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════════════════════

local suggestions = {}   -- { name = '/x', help, params, admin }

local function reply(src, msg, kind)
    if src == 0 then
        print(('%s %s'):format(TAG, tostring(msg)))
    else
        Core.Notify(src, msg, kind or 'info')
    end
end

local function commandName(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local cmds = Config.Commands
    if type(cmds) == 'table' and cmds[name] ~= nil then
        local v = cmds[name]
        if type(v) ~= 'string' or v == '' then return nil end   -- disabled in the config
        return v
    end
    return name
end

local function sendSuggestions(src)
    if not Core.Online(src) then return end
    local admin = nil
    for _, s in ipairs(suggestions) do
        if s.admin then
            if admin == nil then admin = Core.IsAdmin(src) end
        end
        if not s.admin or admin then
            TriggerClientEvent('chat:addSuggestion', src, s.name, s.help, s.params)
        end
    end
end

function NZR.Command(name, fn, adminOnly, opts)
    local cmd = commandName(name)
    if not cmd or type(fn) ~= 'function' then return nil end
    opts = type(opts) == 'table' and opts or {}
    RegisterCommand(cmd, function(source, args, raw)
        local src = tonumber(source) or 0
        if adminOnly and src > 0 and not Core.IsAdmin(src) then
            reply(src, NZR.L('core.cmd_no_perm'), 'error')
            return
        end
        local ok, err = pcall(fn, src, args or {}, raw or '')
        if not ok then
            NZR.Warn(('/%s failed: %s'):format(cmd, tostring(err)))
            reply(src, NZR.L('core.err_failed'), 'error')
        end
    end, false)
    if opts.help then
        local entry = { name = '/' .. cmd, help = tostring(opts.help), params = opts.params or {}, admin = adminOnly == true }
        suggestions[#suggestions + 1] = entry
        -- commands registered after start-up reach the players already online too
        if Core.ready then
            for _, id in ipairs(GetPlayers()) do
                local p = tonumber(id)
                if p and (not entry.admin or Core.IsAdmin(p)) then
                    TriggerClientEvent('chat:addSuggestion', p, entry.name, entry.help, entry.params)
                end
            end
        end
    end
    return cmd
end

-- ════════════════════════════════════════════════════════════════════════
-- DISCORD WEBHOOK
-- ServerConfig.Discord = { enabled, webhook (or convar nayzeee_radio_webhook), username,
-- avatar, log = { admin, emergency, jammers } }. kind = a key of log; a kind set to
-- false there is not sent. Console always gets a debug line.
-- ════════════════════════════════════════════════════════════════════════

local COLORS = {
    admin     = 0x08afa2,   -- teal (house colour)
    emergency = 0xe5484d,   -- red
    jammers   = 0xe5a50a,   -- amber
}
local DEFAULT_COLOR = 0x08afa2
local FOOTER = 'NAYZEEE Radio  ·  discord.gg/nayzeeedev'

function Core.WebhookField(name, value, inline)
    return { name = tostring(name or '-'):sub(1, 256), value = tostring(value or '-'):sub(1, 1000), inline = inline ~= false }
end

function Core.Webhook(kind, title, fields)
    NZR.Debug('webhook', kind, title)
    local cfg = ServerConfig and ServerConfig.Discord
    if type(cfg) ~= 'table' or not cfg.enabled then return end
    if type(cfg.log) == 'table' and cfg.log[kind] == false then return end
    local url = (type(cfg.webhook) == 'string' and cfg.webhook ~= '') and cfg.webhook or GetConvar('nayzeee_radio_webhook', '')
    if url == '' then return end

    local payload = {
        username = (type(cfg.username) == 'string' and cfg.username ~= '') and cfg.username or 'NAYZEEE Radio',
        avatar_url = (type(cfg.avatar) == 'string' and cfg.avatar ~= '') and cfg.avatar or nil,
        embeds = { {
            title = tostring(title or kind or 'Radio'):sub(1, 256),
            color = COLORS[kind] or DEFAULT_COLOR,
            fields = type(fields) == 'table' and fields or {},
            footer = { text = FOOTER },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }

    PerformHttpRequest(url, function(status)
        if (tonumber(status) or 0) >= 300 then NZR.Debug('webhook failed', status) end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

NZR.Webhook = Core.Webhook
NZR.WebhookField = Core.WebhookField

-- ════════════════════════════════════════════════════════════════════════
-- PLAYER LIFECYCLE → BUS
-- One registration with the bridge; every server file listens on the bus instead.
-- ════════════════════════════════════════════════════════════════════════

local hooked = false

function Core.HookPlayers()
    if hooked then return end
    hooked = true

    Core.B('OnPlayerLoaded', function(src)
        src = tonumber(src)
        if src then NZR.Bus.Emit('player:loaded', src) end
    end)

    Core.B('OnPlayerUnloaded', function(src)
        src = tonumber(src)
        if src then NZR.Bus.Emit('player:unloaded', src) end
    end)

    Core.B('OnJobChanged', function(src, job)
        src = tonumber(src)
        if src then NZR.Bus.Emit('player:job', src, job) end
    end)
end

NZR.Bus.On('player:loaded', function(src)
    SetTimeout(2000, function() sendSuggestions(src) end)
end)

-- The bridge's own playerDropped handler (bridge/server/framework.lua, loaded first)
-- has already sent player:unloaded by the time this one runs.
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    NZR.Bus.Emit('player:dropped', src)
    Core.ClearRate(src)
end)

-- ════════════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════════════

local function propsCheck()
    local props = Config.PropsResource
    if not props then return end
    local state = GetResourceState(props)
    if state ~= 'started' and state ~= 'starting' then
        print(('^3%s %s is not running (%s): radios and jammers will be invisible. '
            .. 'Ensure it BEFORE nayzeee-radio (or set Config.PropsResource = false).^7'):format(TAG, props, state))
    end
end

CreateThread(function()
    Wait(0)
    Core.HookPlayers()
    propsCheck()
    Wait(1000)   -- the inventory bridge resolves its adapter 500 ms after start
    Core.ready = true
    local version = GetResourceMetadata(NZR.Resource, 'version', 0) or NZR.Version
    local inventory = Core.B('Inv.Resource') or '?'
    print(('^2%s^7 v%s loaded  ·  framework: ^5%s^7  ·  inventory: ^5%s^7'):format(
        TAG, version, tostring(Bridge and Bridge.Framework or '?'), tostring(inventory)))
    Wait(3000)
    for _, id in ipairs(GetPlayers()) do sendSuggestions(tonumber(id)) end
end)
