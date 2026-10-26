-- Core: framework detection, permissions, player identity and the NUI RPC router.
NZ = NZ or {}
NZ.Resource = GetCurrentResourceName()
NZ.Version = GetResourceMetadata(NZ.Resource, 'version', 0) or '3.0.0'
NZ.Framework = 'none'
NZ.OxFramework = GetConvar('inventory:framework', 'esx')

local ESX, QB

-- ─── detection ──────────────────────────────────────────────────────────────
local function detect()
    local want = Config.Framework or 'auto'
    if (want == 'auto' or want == 'esx') and GetResourceState('es_extended') == 'started' then
        ESX = exports.es_extended:getSharedObject()
        NZ.Framework = 'esx'
    elseif (want == 'auto' or want == 'qbx') and GetResourceState('qbx_core') == 'started' then
        NZ.Framework = 'qbx'
        if GetResourceState('qb-core') == 'started' then QB = exports['qb-core']:GetCoreObject() end
    elseif (want == 'auto' or want == 'qbcore') and GetResourceState('qb-core') == 'started' then
        QB = exports['qb-core']:GetCoreObject()
        NZ.Framework = 'qbcore'
    end
end
detect()

-- the framework may start after this resource (server.cfg order): look again when it does
local FRAMEWORKS = { es_extended = true, qbx_core = true, ['qb-core'] = true }
AddEventHandler('onServerResourceStart', function(res)
    if not FRAMEWORKS[res] then return end
    local before = NZ.Framework
    SetTimeout(500, function()
        detect()
        if NZ.Framework ~= before then
            if Inv and Inv.id and Inv.id ~= 'none' then NZ.SetDBLayout(Inv.id, Inv.a.db) end
            NZ.Print(('Framework: %s (it started after this resource; ensure it earlier in server.cfg)'):format(NZ.Framework), 'warn')
        end
    end)
end)

-- Character + vehicle tables. On ox_inventory these follow its `inventory:framework` convar
-- (mirrors ox_inventory/modules/mysql/server.lua); other inventories go by the framework and
-- can override it from their integration file (`db = { ... }`).
local DB_LAYOUT = {
    esx = { players = 'users', pcol = 'identifier', vehicles = 'owned_vehicles', vcol = 'plate' },
    qbx = { players = 'players', pcol = 'citizenid', vehicles = 'player_vehicles', vcol = 'id' },
    ox = { players = 'character_inventory', pcol = 'charid', vehicles = 'vehicles', vcol = 'id' },
    nd = { players = 'nd_characters', pcol = 'charid', vehicles = 'nd_vehicles', vcol = 'id' },
}
local FW_LAYOUT = { esx = 'esx', qbcore = 'qbx', qbx = 'qbx' }
NZ.DB = DB_LAYOUT[FW_LAYOUT[NZ.Framework] or NZ.OxFramework] or DB_LAYOUT.esx

--- Called once the inventory integration is chosen
function NZ.SetDBLayout(invId, override)
    local base = invId == 'ox_inventory' and DB_LAYOUT[NZ.OxFramework] or DB_LAYOUT[FW_LAYOUT[NZ.Framework] or 'esx'] or DB_LAYOUT.esx
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(type(override) == 'table' and override or {}) do out[k] = v end
    NZ.DB = out
end

-- ─── helpers ────────────────────────────────────────────────────────────────
function NZ.Trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

function NZ.Round(n, d)
    local m = 10 ^ (d or 2)
    return math.floor((tonumber(n) or 0) * m + 0.5) / m
end

function NZ.Comma(n)
    local s = tostring(math.floor(math.abs(tonumber(n) or 0)))
    s = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return ((tonumber(n) or 0) < 0 and '-' or '') .. s
end

function NZ.Print(msg, level)
    local tag = level == 'error' and '^1' or level == 'warn' and '^3' or '^2'
    print(('%s[inventory-manager]^0 %s'):format(tag, msg))
end

function NZ.Debug(msg)
    if Config.Debug then NZ.Print(msg, 'warn') end
end

--- All identifiers in a keyed table: { license = 'license:..', discord = 'discord:..', ... }
function NZ.Identifiers(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        local kind = id:match('^([^:]+):')
        if kind and not out[kind] then out[kind] = id end
    end
    return out
end

function NZ.License(src)
    local ids = NZ.Identifiers(src)
    return ids.license2 and ids.license or ids.license or ids.fivem
end

--- Character id the inventory stores this player under (users.identifier / players.citizenid / charid)
function NZ.CharId(src)
    src = tonumber(src)
    if not src then return end
    if NZ.Framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        return x and x.identifier
    elseif NZ.Framework == 'qbx' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and p then return p.PlayerData.citizenid end
    elseif QB then
        local p = QB.Functions.GetPlayer(src)
        return p and p.PlayerData.citizenid
    end
    if Inv and Inv.Ready() then return Inv.Owner(src) end
end

function NZ.CharInfo(src)
    src = tonumber(src)
    local info = { name = GetPlayerName(src) or ('Player %s'):format(src), job = nil, grade = nil }
    if NZ.Framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x then
            info.char = x.getName and x.getName() or nil
            info.job = x.job and x.job.label or nil
            info.jobName = x.job and x.job.name or nil
            info.grade = x.job and x.job.grade_label or nil
            info.charId = x.identifier
            info.group = x.getGroup and x.getGroup() or nil
        end
    else
        local p
        if NZ.Framework == 'qbx' then
            local ok, r = pcall(function() return exports.qbx_core:GetPlayer(src) end)
            p = ok and r or nil
        elseif QB then
            p = QB.Functions.GetPlayer(src)
        end
        if p and p.PlayerData then
            local d = p.PlayerData
            info.char = d.charinfo and ('%s %s'):format(d.charinfo.firstname or '', d.charinfo.lastname or '') or nil
            info.job = d.job and d.job.label or nil
            info.jobName = d.job and d.job.name or nil
            info.grade = d.job and d.job.grade and d.job.grade.name or nil
            info.charId = d.citizenid
        end
    end
    info.charId = info.charId or NZ.CharId(src)
    return info
end

function NZ.OnlineByCharId(charId)
    if not charId then return end
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        if NZ.CharId(id) == charId then return id end
    end
end

--- Player block used by logs + webhooks
function NZ.Actor(src)
    src = tonumber(src)
    if not src or src <= 0 then return { name = 'Console', identifier = 'console', id = 0 } end
    local ped = GetPlayerPed(src)
    local c = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
    local ids = NZ.Identifiers(src)
    return {
        id = src,
        name = GetPlayerName(src) or 'Unknown',
        identifier = NZ.CharId(src) or NZ.License(src) or 'unknown',
        license = NZ.License(src),
        discord = ids.discord,
        coords = ('%.2f, %.2f, %.2f'):format(c.x, c.y, c.z),
    }
end

function NZ.Notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Inventory Manager', description = msg, type = kind or 'inform', duration = 5000 })
end

-- ─── permissions ────────────────────────────────────────────────────────────
-- Each tier is granted by a framework group listed in Config.Permissions[tier] or by the ACE
-- `nayzeee.inventory.<tier>`. There is no blanket fallback: an unlisted group gets nothing.
local TIERS = { 'view', 'manage', 'global', 'editor', 'rollback', 'wipe' }
NZ.Tiers = TIERS

--- IsPlayerAceAllowed as a real boolean. Depending on the server build it can answer 1/0 instead of
--- true/false; the panel treated 1 as allowed while the server's checks wanted `true`, so staff saw the
--- editor pages and then got "You do not have permission" on every action in them.
local function ace(src, object)
    local v = IsPlayerAceAllowed(tostring(src), object)
    return v == true or v == 1 or v == '1' or v == 'true'
end
NZ.Ace = ace

local function frameworkGroups(src)
    local groups = {}
    if NZ.Framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x and x.getGroup then groups[x.getGroup()] = true end
    elseif NZ.Framework == 'qbx' or QB then
        for _, g in ipairs({ 'god', 'admin', 'mod', 'owner', 'superadmin' }) do
            if ace(src, g) then groups[g] = true end
        end
        if QB and QB.Functions.GetPermission then
            local ok, perms = pcall(QB.Functions.GetPermission, src)
            if ok and type(perms) == 'table' then for g, v in pairs(perms) do if v then groups[g] = true end end end
            if ok and type(perms) == 'string' then groups[perms] = true end
        end
    end
    return groups
end

function NZ.Perms(src)
    src = tonumber(src)
    local out = {}
    if not src or src <= 0 then
        for _, t in ipairs(TIERS) do out[t] = true end
        return out
    end
    local groups = frameworkGroups(src)
    for _, tier in ipairs(TIERS) do
        local ok = ace(src, 'nayzeee.inventory.' .. tier)
        if not ok then
            for _, g in ipairs(Config.Permissions[tier] or {}) do
                if groups[g] then ok = true break end
            end
        end
        out[tier] = ok == true
    end
    -- every higher tier implies view
    for _, t in ipairs(TIERS) do if out[t] then out.view = true end end
    return out
end

function NZ.Can(src, tier)
    return NZ.Perms(src)[tier] == true
end

function NZ.OnlineStaff(tier)
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        if NZ.Can(id, tier or 'view') then out[#out + 1] = id end
    end
    return out
end

-- ─── per-staff notification settings ──────────────────────────────────────
-- Stored per license so they follow the staff member across characters and restarts.
NZ.NotifyCategories = { 'flags', 'dupes', 'staff' }
local prefsCache = {}

local function prefsKey(src) return 'nzinv:prefs:' .. (NZ.License(src) or ('src' .. src)) end

function NZ.GetPrefs(src)
    local key = prefsKey(src)
    local p = prefsCache[key]
    if not p then
        local raw = GetResourceKvpString(key)
        p = raw and json.decode(raw) or {}
        prefsCache[key] = p
    end
    local out = { notify = p.notify ~= false, sounds = p.sounds ~= false }
    for _, c in ipairs(NZ.NotifyCategories) do out[c] = p[c] ~= false end
    return out
end

function NZ.SetPrefs(src, changes)
    local cur = NZ.GetPrefs(src)
    for k, v in pairs(changes or {}) do
        if cur[k] ~= nil and type(v) == 'boolean' then cur[k] = v end
    end
    local key = prefsKey(src)
    prefsCache[key] = cur
    SetResourceKvp(key, json.encode(cur))
    return cur
end

--- Notify online staff. category = 'flags' | 'dupes' | 'staff'. `except` skips the staff member
--- who caused it (they already see the result in their panel).
function NZ.NotifyStaff(msg, kind, category, except)
    if not Config.NotifyStaff then return end
    for _, id in ipairs(NZ.OnlineStaff('view')) do
        if id ~= except then
            local p = NZ.GetPrefs(id)
            if p.notify and (not category or p[category] ~= false) then NZ.Notify(id, msg, kind) end
        end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    local key = 'nzinv:prefs:' .. (NZ.License(src) or ('src' .. src))
    prefsCache[key] = nil
end)

-- ─── RPC router ─────────────────────────────────────────────────────────────
local Routes = {}

--- Register a panel action. fn(src, data) returns data or raises NZ.Fail
function NZ.Route(name, tier, fn)
    Routes[name] = { tier = tier, fn = fn }
end

function NZ.Fail(msg) error({ nz = true, msg = msg }, 0) end

local busy = {}
local denied = {}

--- Console line explaining a refused action, at most once a minute per player and tier
local function explainDenied(src, name, tier)
    local k = src .. ':' .. tier
    if denied[k] and os.time() - denied[k] < 60 then return end
    denied[k] = os.time()
    local have = {}
    for _, t in ipairs(TIERS) do if NZ.Perms(src)[t] then have[#have + 1] = t end end
    local groups = {}
    for g in pairs(frameworkGroups(src)) do groups[#groups + 1] = g end
    NZ.Print(('%s (id %s) was refused "%s": it needs the "%s" tier. They have: %s. Framework groups seen: %s. ACE nayzeee.inventory.%s = %s. (answered by resource %s)')
        :format(GetPlayerName(src) or '?', src, name, tier, #have > 0 and table.concat(have, ', ') or 'none',
            #groups > 0 and table.concat(groups, ', ') or 'none', tier, tostring(IsPlayerAceAllowed(tostring(src), 'nayzeee.inventory.' .. tier)), NZ.Resource), 'warn')
end

lib.callback.register('nzinv:rpc', function(src, name, data)
    local route = Routes[name]
    if not route then return { ok = false, err = 'Unknown action' } end
    if not NZ.Can(src, route.tier) then
        explainDenied(src, name, route.tier)
        return { ok = false, err = ('You do not have permission for that (needs %s). Check the server console.'):format(route.tier) }
    end
    local key = src .. ':' .. name
    if busy[key] and route.tier ~= 'view' then return { ok = false, err = 'Still working on the last request.' } end
    busy[key] = true
    local ok, res = pcall(route.fn, src, type(data) == 'table' and data or {})
    busy[key] = nil
    if ok then return { ok = true, data = res } end
    if type(res) == 'table' and res.nz then return { ok = false, err = res.msg } end
    NZ.Print(('%s failed: %s'):format(name, tostring(res)), 'error')
    return { ok = false, err = 'Server error, check the console.' }
end)

--- Invoke a route from server code (used by commands / exports)
function NZ.Call(src, name, data)
    local route = Routes[name]
    if not route then return false, 'Unknown action' end
    local ok, res = pcall(route.fn, src, data or {})
    if ok then return true, res end
    return false, type(res) == 'table' and res.msg or tostring(res)
end

-- ─── audit trail ────────────────────────────────────────────────────────────
function NZ.Audit(src, action, target, details)
    local a = NZ.Actor(src)
    MySQL.insert('INSERT INTO `nayzeee_inventory_audit` (`admin_name`, `admin_identifier`, `action`, `target`, `details`) VALUES (?, ?, ?, ?, ?)', {
        a.name or 'Console', a.license or a.identifier or 'console', action, target and tostring(target):sub(1, 128) or '',
        details and json.encode(details) or '{}',
    })
end

NZ.Route('audit:list', 'view', function(src, d)
    local page = math.max(1, tonumber(d.page) or 1)
    local per = 50
    local where, params = '', {}
    if d.q and d.q ~= '' then
        where = ' WHERE `admin_name` LIKE ? OR `action` LIKE ? OR `target` LIKE ? OR `details` LIKE ?'
        local q = '%' .. d.q .. '%'
        params = { q, q, q, q }
    end
    local total = MySQL.scalar.await('SELECT COUNT(*) FROM `nayzeee_inventory_audit`' .. where, params) or 0
    local p2 = { table.unpack(params) }
    p2[#p2 + 1] = per
    p2[#p2 + 1] = (page - 1) * per
    local rows = MySQL.query.await('SELECT `id`, `admin_name`, `admin_identifier`, `action`, `target`, `details`, UNIX_TIMESTAMP(`timestamp`) AS `time` FROM `nayzeee_inventory_audit`' .. where .. ' ORDER BY `id` DESC LIMIT ? OFFSET ?', p2) or {}
    return { rows = rows, total = total, page = page, pages = math.max(1, math.ceil(total / per)) }
end)
