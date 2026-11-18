if not NAYZEEE_LOCK_OK then return end

--[[
    Server-authoritative session flow:
        select -> (play)   -> loaded -> (spawn) -> spawning -> (nzm:server:spawned) -> playing
        select -> (create) -> loaded -> (spawn) -> spawning -> (nzm:server:spawned) -> playing
    Every callback checks the stage, ownership and rate limits.

    Sessions[src] = { owner, stage, total, slotInfo, byId (Character), bySlot, raw (framework chars),
                      active, loadedAt, isNew, spawnOpts }
]]

local api = {}
Sessions = setmetatable({}, { __index = api })   -- helpers live in the metatable so pairs(Sessions) only yields players
local T = NZ.T
local Limited = Validate.Limited
local relogFlag = {}

-- src currently playing charId (nil when nobody is)
function api.Playing(charId)
    if not charId then return nil end
    for src, s in pairs(Sessions) do
        if s.active == charId then return src end
    end
end

-- ── helpers ───────────────────────────────────────────────────────────────
local function flushPlaytime(s)
    if s and s.active and s.loadedAt then
        local now = os.time()
        DB.AddPlaytime(s.active, now - s.loadedAt)
        s.loadedAt = now
    end
end

local charName = Characters.Name

local function canDelete(src)
    local cfg = Config.Characters
    if not cfg.allowDelete then return false end
    if cfg.deleteAccess == 'ace' then return IsPlayerAceAllowed(src, cfg.deleteAce) end
    if cfg.deleteAccess == 'list' then
        for _, t in ipairs({ 'license', 'license2' }) do
            local l = GetPlayerIdentifierByType(src, t)
            for _, v in ipairs(cfg.deleteList) do if v == l then return true end end
        end
        return false
    end
    return true
end

-- Load (or reload) the session's character list
local function refresh(src)
    local s = Sessions[src]
    local total, info = Slots.Get(src, s.owner)
    local list, raw = Characters.List(src, s.owner, total)
    s.total, s.slotInfo, s.raw = total, info, raw
    s.byId, s.bySlot = {}, {}
    for i = 1, #list do
        s.byId[list[i].id] = list[i]
        s.bySlot[list[i].slot] = list[i]
    end
    return list
end

-- Rebuild one character after a pref change (fresh meta, cached framework row)
local function rebuild(src, s, charId)
    local c = Characters.Build(s.raw[charId], DB.Get(charId) or {}, src, s.total)
    local old = s.byId[charId]
    s.byId[charId] = c
    if old then s.bySlot[old.slot] = c end
    return c
end

local function selected(list)
    local mode = Config.Characters.autoSelect
    local fav, last, first
    for _, c in ipairs(list) do
        if not c.disabled and not c.locked then
            first = first or c
            if c.favorite then fav = c end
            if c.lastPlayed and (not last or c.lastPlayed > last.lastPlayed) then last = c end
        end
    end
    local pick
    if mode == 'favorite' then pick = fav or last or first
    elseif mode == 'first' then pick = first
    else pick = last or fav or first end
    return pick and pick.id or nil
end

local function payload(src, relog)
    local s = Sessions[src]
    local list = refresh(src)
    local info = s.slotInfo
    return {
        loaded     = false,
        characters = list,
        slots      = { total = s.total, used = #list, max = info.max, base = info.base, extra = info.extra },
        canDelete  = canDelete(src),
        online     = #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 48),
        selected   = selected(list),
        relog      = relog == true,
    }
end

-- Spawn options for the active character. Returns opts|nil, mode
local function spawnOptions(src, s, isNew)
    local cfg = Config.Spawn
    s.spawnOpts = {}
    if cfg.custom.enabled and (not cfg.custom.newOnly or isNew) then return nil, 'custom' end
    if not cfg.selector then return nil, isNew and 'first' or 'last' end
    if isNew and not cfg.forNew then return nil, 'first' end

    local opts = {}
    local raw = s.raw and s.raw[s.active]
    if cfg.lastLocation and not isNew then
        local pos = (raw and raw.position) or Bridge.Position(s.active)
        if pos then
            opts[#opts + 1] = { id = 'last', kind = 'last', label = T('last_location'), desc = T('last_location_sub'), icon = 'pin', coords = pos }
        end
    end
    if cfg.houses then
        local ok, houses = pcall(Housing.Get, src, s.active)
        for _, h in ipairs(ok and houses or {}) do
            if h.coords then
                opts[#opts + 1] = { id = 'house:' .. tostring(h.id), kind = 'house', label = h.label, desc = h.desc or T('your_house'), icon = 'home', coords = h.coords }
            end
        end
    end
    local job, grade = Bridge.ActiveJob(src)
    for _, p in ipairs(Config.SpawnPoints) do
        local ok = not p.newOnly or isNew
        if ok and p.jobs then ok = job ~= nil and p.jobs[job] ~= nil and (grade or 0) >= p.jobs[job] end
        if ok then opts[#opts + 1] = { id = 'point:' .. p.id, kind = 'city', label = p.label, desc = p.desc, icon = p.icon, coords = p.coords } end
    end
    if isNew then
        table.insert(opts, 1, { id = 'first', kind = 'first', label = T('first_spawn'), desc = T('first_spawn_sub'), icon = 'plane', coords = cfg.firstSpawn })
    end
    if #opts == 0 then return nil, isNew and 'first' or 'last' end
    for _, o in ipairs(opts) do s.spawnOpts[o.id] = o end
    return opts, 'selector'
end

local function giveStarter(src, s, data)
    local st = Config.Starter
    Bridge.AddMoney(src, 'cash', st.money.cash or 0)
    Bridge.AddMoney(src, 'bank', st.money.bank or 0)
    for _, it in ipairs(st.items or {}) do
        local meta = it.metadata
        if type(meta) == 'function' then
            local ok, m = pcall(meta, src, data)
            meta = ok and m or nil
        end
        Bridge.AddItem(src, it.name, it.count or 1, meta)
    end
    if st.frameworkDefaults then pcall(Bridge.FrameworkStarter, src) end
end

-- The player is in the world: shared bucket, stage 'playing'
local function enterWorld(src, s)
    s.stage = 'playing'
    Buckets.World(src)
end

-- ── session start ─────────────────────────────────────────────────────────
lib.callback.register('nzm:boot', function(src)
    if not Bridge.Ready then return { loaded = false, error = 'no_framework' } end
    local deadline = GetGameTimer() + 30000
    while not Bridge.Ready() do
        if GetGameTimer() > deadline then return { loaded = false, error = 'framework_timeout' } end
        Wait(100)
    end
    DB.Wait()

    local owner = Bridge.Owner(src)
    if not owner then return { loaded = false, error = 'no_license' } end

    -- Already loaded (resource restart mid-session): keep playing
    if Bridge.IsLoaded(src) then
        local s = Sessions[src]
        if not s or s.stage ~= 'select' then
            Sessions[src] = s or { owner = owner, stage = 'playing', active = Bridge.ActiveId(src), loadedAt = os.time() }
            return { loaded = true }
        end
    end

    local relog = relogFlag[src] == true
    relogFlag[src] = nil
    Sessions[src] = { owner = owner, stage = 'select' }
    Buckets.Lobby(src)
    return payload(src, relog)
end)

-- Reload the list (e.g. after slots changed) without touching the bucket
lib.callback.register('nzm:refresh', function(src)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return nil end
    return payload(src, false)
end)

-- ── prefs ─────────────────────────────────────────────────────────────────
local petNameMax = 24

-- key -> function(src, s, c, value) returning value to store (nil = clear) or false, msg
local prefs = {
    theme = function(_, _, _, v)
        if not Config.Scene.playerPick then return false end
        if v == nil then return nil end
        return type(v) == 'string' and NZ.Theme(v) and v or false
    end,
    mood = function(_, _, c, v)
        if not Config.Scene.playerPick then return false end
        if v == nil then return nil end
        return type(v) == 'string' and Characters.MoodAllowed(c.prefs.theme, v) and v or false
    end,
    pose = function(_, _, _, v)
        if v == nil then return nil end
        return type(v) == 'string' and NZ.PoseById(v) and v or false
    end,
    couplePose = function(_, _, c, v)
        if not Config.Squad.enabled or not Config.Squad.couples then return false end
        if v == nil then return nil end
        if type(v) ~= 'string' or not NZ.CoupleById(v) then return false end
        if not Squads.HasCouple(c.id) then return false end
        return v
    end,
    weapon = function(_, s, c, v)
        if not Config.WeaponShowcase.enabled then return false end
        if v == nil then return nil end
        return Weapons.Valid(c.id, v, s.raw[c.id] and s.raw[c.id].raw) or false
    end,
    pet = function(src, _, c, v)
        if not Config.Pets.enabled then return false end
        if v == nil then return nil end
        if type(v) ~= 'string' or not NZ.PetById(v) then return false end
        if not PetBridge.Can(src, c.id, v) then return false, T('t_not_owned') end
        return v
    end,
    petName = function(_, _, _, v)
        if not Config.Pets.enabled or not Config.Pets.names then return false end
        if v == nil or v == '' then return nil end
        return Validate.Text(v, petNameMax) or false
    end,
    backstory = function(_, _, _, v)
        if not Config.Registration.backstory.enabled then return false end
        local b = Validate.Backstory(v)
        if b == nil then return false, T('v_max', math.min(Config.Registration.backstory.max, 600)) end
        return b ~= '' and b or nil
    end,
}

lib.callback.register('nzm:pref', function(src, charId, key, value)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' or not Validate.Id(charId) or not s.byId or not s.byId[charId] then return { ok = false, msg = T('t_error') } end
    if Limited(src, 'pref') then return { ok = false, msg = T('t_rate') } end
    local c = s.byId[charId]
    if c.disabled then return { ok = false, msg = T('t_disabled') } end
    -- the UI sends 'none' to clear these (JSON null does not survive the NUI bridge)
    if (key == 'couplePose' or key == 'pet') and value == 'none' then value = nil end

    if key == 'favorite' then
        if type(value) ~= 'boolean' then return { ok = false, msg = T('t_invalid') } end
        DB.SetFavorite(s.owner, charId, value)
        for id in pairs(s.byId) do
            if id ~= charId and s.byId[id].favorite then s.byId[id].favorite = false end
        end
    else
        local check = type(key) == 'string' and prefs[key]
        if not check then return { ok = false, msg = T('t_invalid') } end
        local v, msg = check(src, s, c, value)
        if v == false then return { ok = false, msg = msg or T('t_invalid') } end
        DB.Set(charId, key, v)
    end
    return { ok = true, msg = T('t_saved'), character = rebuild(src, s, charId) }
end)

-- ── play ─────────────────────────────────────────────────────────────────
lib.callback.register('nzm:play', function(src, charId)
    local s = Sessions[src]
    if not s or not Validate.Id(charId) then return { ok = false, msg = T('t_error') } end

    -- freshly created character asking for its spawn options (already logged in by nzm:create)
    if s.stage == 'loaded' and s.isNew and s.active == charId then
        local opts, mode = spawnOptions(src, s, true)
        return { ok = true, spawn = opts, mode = mode }
    end

    if s.stage ~= 'select' then return { ok = false } end
    if Limited(src, 'play') then return { ok = false, msg = T('t_rate') } end
    local c = s.byId and s.byId[charId]
    if not c then return { ok = false, msg = T('t_error') } end
    if c.disabled then return { ok = false, msg = T('t_disabled') } end
    if c.locked then return { ok = false, msg = T('t_slot_locked') } end
    if Sessions.Playing(charId) then return { ok = false, msg = T('t_relog_busy') } end

    s.stage = 'loading'
    local ok, loaded = pcall(Bridge.Load, src, s.raw[charId])
    if not ok or not loaded then
        if not ok then print(('^1[nzm] load failed: %s^0'):format(loaded)) end
        s.stage = 'select'
        return { ok = false, msg = T('t_error') }
    end
    s.active, s.loadedAt, s.isNew = charId, os.time(), false
    s.stage = 'loaded'
    DB.Set(charId, 'lastPlayed', os.time())
    Logs.Send('loaded', src, { { 'Character', charName(c) }, { 'ID', charId } })
    Squads.NotifyLinked(charId)

    local opts, mode = spawnOptions(src, s, false)
    return { ok = true, spawn = opts, mode = mode, skin = c.skin, model = c.model, gender = c.gender }
end)

-- ── create ───────────────────────────────────────────────────────────────
lib.callback.register('nzm:create', function(src, slot, form)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return { ok = false, msg = T('t_error') } end
    if Limited(src, 'create') then return { ok = false, msg = T('t_rate') } end
    slot = tonumber(slot)
    if not slot or slot ~= math.floor(slot) or slot < 1 or slot > s.total then return { ok = false, msg = T('t_slot_locked') } end
    if s.bySlot[slot] then return { ok = false, msg = T('t_slot_taken') } end

    local data, errors = Validate.Registration(form)
    if not data then return { ok = false, errors = Validate.Messages(errors) } end

    s.stage = 'creating'
    local ok, created, charId = pcall(Bridge.Create, src, slot, data)
    if not ok or not created or not charId then
        if not ok then print(('^1[nzm] create failed: %s^0'):format(created)) end
        s.stage = 'select'
        return { ok = false, msg = T('t_error') }
    end

    DB.Ensure(charId, s.owner)
    DB.Set(charId, 'nationality', data.nationality)
    if data.backstory then DB.Set(charId, 'backstory', data.backstory) end
    DB.Set(charId, 'lastPlayed', os.time())

    s.active, s.loadedAt, s.isNew = charId, os.time(), true
    s.raw[charId] = { id = charId, slot = slot, firstname = data.firstname, lastname = data.lastname, gender = data.gender,
                      job = { name = 'unemployed' } }
    giveStarter(src, s, data)
    s.stage = 'loaded'

    Logs.Send('created', src, {
        { 'Character', data.firstname .. ' ' .. data.lastname }, { 'ID', charId }, { 'Slot', slot },
        { 'DOB', ('%04d-%02d-%02d'):format(data.dobY, data.dobM, data.dobD) }, { 'Gender', data.gender }, { 'Nationality', data.nationality or '-' },
    })

    local opts, mode = spawnOptions(src, s, true)
    return { ok = true, msg = T('t_created'), charId = charId, gender = data.gender, spawn = opts, mode = mode }
end)

-- ── spawn ────────────────────────────────────────────────────────────────
-- The client only sends an option id; coordinates always come from the server.
-- The bucket stays private until nzm:server:spawned (the departure cutscene still plays in the lobby).
lib.callback.register('nzm:spawn', function(src, optionId)
    local s = Sessions[src]
    if not s or s.stage ~= 'loaded' then return nil end
    local coords
    if optionId == 'first' then
        coords = Config.Spawn.firstSpawn
    elseif optionId == 'last' or optionId == nil then
        coords = (not s.isNew and Bridge.Position(s.active)) or Config.Spawn.firstSpawn
    elseif type(optionId) == 'string' and s.spawnOpts and s.spawnOpts[optionId] then
        coords = s.spawnOpts[optionId].coords
    end
    if not coords then return nil end
    s.stage = 'spawning'

    -- fail-safe: a client that never reports back still leaves the private bucket
    local active = s.active
    SetTimeout(60000, function()
        local cur = Sessions[src]
        if cur and cur.stage == 'spawning' and cur.active == active then enterWorld(src, cur) end
    end)
    return { coords = coords, isNew = s.isNew }
end)

RegisterNetEvent('nzm:server:spawned', function()
    local src = source
    local s = Sessions[src]
    if not s or not s.active then return end
    if s.stage == 'spawning' or s.stage == 'loaded' or s.stage == 'playing' then enterWorld(src, s) end
end)

-- Custom spawn handoff (Config.Spawn.custom): release the player to the other resource
lib.callback.register('nzm:handoff', function(src)
    local s = Sessions[src]
    if not s or (s.stage ~= 'loaded' and s.stage ~= 'spawning') then return false end
    enterWorld(src, s)
    return true
end)

-- ── delete ───────────────────────────────────────────────────────────────
lib.callback.register('nzm:delete', function(src, charId, typed)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return { ok = false, msg = T('t_error') } end
    if not canDelete(src) then return { ok = false, msg = T('t_no_delete') } end
    if Limited(src, 'delete') then return { ok = false, msg = T('t_rate') } end
    local c = Validate.Id(charId) and s.byId[charId]
    if not c then return { ok = false, msg = T('t_error') } end
    if Config.Characters.typeToConfirm and NZ.Trim(type(typed) == 'string' and typed or ''):lower() ~= charName(c):lower() then
        return { ok = false, msg = T('t_name_mismatch') }
    end
    local ok, done = pcall(Bridge.Delete, src, charId)
    if not ok or not done then return { ok = false, msg = T('t_error') } end
    DB.Delete(charId)
    Squads.Purge(charId)
    Weapons.Forget(charId)
    s.byId[charId], s.bySlot[c.slot], s.raw[charId] = nil, nil, nil
    Logs.Send('deleted', src, { { 'Character', charName(c) }, { 'ID', charId } })
    return { ok = true, msg = T('t_deleted') }
end)

-- ── redeem (codes + Tebex) ───────────────────────────────────────────────
local function tebex(code)
    local cfg = ServerConfig.Tebex
    if not cfg.enabled then return nil end
    local secret = GetConvar(cfg.convar, '')
    if secret == '' then return nil end
    local p = promise.new()
    PerformHttpRequest(('https://plugin.tebex.io/payments/%s'):format(code), function(status, body)
        p:resolve(status == 200 and NZ.Decode(body) or nil)
    end, 'GET', '', { ['X-Tebex-Secret'] = secret })
    SetTimeout(8000, function() if p.state == 0 then p:resolve(nil) end end)
    local data = Citizen.Await(p)
    if not data or (data.status and data.status ~= 'Complete') then return nil end
    local add = 0
    for _, pkg in ipairs(data.packages or {}) do
        local per = cfg.packages[tostring(pkg.id)]
        if per then add = add + per * (tonumber(pkg.quantity) or 1) end
    end
    return add > 0 and add or nil
end

lib.callback.register('nzm:redeem', function(src, code)
    local s = Sessions[src]
    if not s then return { ok = false, msg = T('t_error') } end
    if Limited(src, 'redeem') then return { ok = false, msg = T('t_rate') } end
    code = NZ.Trim(type(code) == 'string' and code or '')
    if code == '' or #code > 64 or not code:match('^[%w%-_]+$') then return { ok = false, msg = T('t_redeem_bad') } end

    local add, kind
    local row = MySQL.single.await('SELECT slots, uses, used FROM `multichar_codes` WHERE code = ?', { code })
    if row then
        -- admin code: one redemption per owner, atomic use counter
        if MySQL.scalar.await('SELECT 1 FROM `multichar_redeemed` WHERE code = ? AND owner = ?', { code, s.owner }) then
            return { ok = false, msg = T('t_redeem_bad') }
        end
        if MySQL.update.await('UPDATE `multichar_codes` SET used = used + 1 WHERE code = ? AND used < uses', { code }) ~= 1 then
            return { ok = false, msg = T('t_redeem_bad') }
        end
        add, kind = tonumber(row.slots) or 0, 'code'
    else
        if not ServerConfig.Tebex.enabled then return { ok = false, msg = T('t_redeem_bad') } end
        add = tebex(code)
        if not add then return { ok = false, msg = T('t_redeem_bad') } end
        -- the primary key makes a transaction id redeemable exactly once, even under a race
        local ok, id = pcall(MySQL.insert.await, 'INSERT INTO `multichar_codes` (code, slots, uses, used, created_at) VALUES (?, ?, 1, 1, ?)', { code, add, os.time() })
        if not ok or not id then return { ok = false, msg = T('t_redeem_bad') } end
        kind = 'tebex'
    end
    MySQL.insert.await('INSERT IGNORE INTO `multichar_redeemed` (code, owner, at) VALUES (?, ?, ?)', { code, s.owner, os.time() })
    if add <= 0 then return { ok = false, msg = T('t_redeem_bad') } end

    DB.AddExtra(s.owner, add)
    Logs.Send('redeem', src, { { 'Code', code }, { 'Source', kind }, { 'Slots', add } })
    return { ok = true, msg = T('t_redeemed', add) }
end)

RegisterNetEvent('nzm:server:quit', function()
    local src = source
    local s = Sessions[src]
    if s and s.stage ~= 'playing' then DropPlayer(src, T('t_quit')) end
end)

-- ── relog ────────────────────────────────────────────────────────────────
local relogAt = {}

function Relog(src, force)
    local s = Sessions[src]
    if not s or s.stage ~= 'playing' then
        if not force then TriggerClientEvent('nzm:client:notify', src, T('t_relog_busy'), 'error') end
        return false
    end
    local cd = Config.Relog.command.cooldown or 0
    local now = os.time()
    if not force and relogAt[src] and now - relogAt[src] < cd then
        TriggerClientEvent('nzm:client:notify', src, T('t_relog_wait', cd - (now - relogAt[src])), 'error')
        return false
    end
    relogAt[src] = now

    s.stage = 'relogging'
    TriggerClientEvent('nzm:client:relogPrepare', src)
    Wait(700)
    flushPlaytime(s)
    local name = s.raw and s.raw[s.active] and charName(s.raw[s.active]) or s.active
    local previous = s.active
    pcall(Bridge.Logout, src)
    Logs.Send('relog', src, { { 'From', name or '-' }, { 'Forced', force and 'yes' or 'no' } })
    Sessions[src] = nil
    Weapons.Forget(previous)
    relogFlag[src] = true
    TriggerClientEvent('nzm:client:open', src)
    Squads.NotifyLinked(previous)                     -- linked lobbies: online flag changed
    return true
end

RegisterNetEvent('nzm:server:relog', function()
    local src = source
    if Config.Relog.command.ace and not IsPlayerAceAllowed(src, Config.Relog.command.ace) then return end
    Relog(src, false)
end)

-- ── lifecycle ────────────────────────────────────────────────────────────
local function closeSession(src)
    local s = Sessions[src]
    if not s then return end
    flushPlaytime(s)
    Sessions[src] = nil
    if s.active then
        Weapons.Forget(s.active)
        Squads.NotifyLinked(s.active)
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    Buckets.World(src)
    closeSession(src)
    Validate.Forget(src)
    relogAt[src], relogFlag[src] = nil, nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZ.Resource then return end
    for _, s in pairs(Sessions) do flushPlaytime(s) end
end)

-- Flush playtime every 5 minutes so crashes lose little
CreateThread(function()
    while true do
        Wait(300000)
        for _, s in pairs(Sessions) do
            if s.stage == 'playing' then flushPlaytime(s) end
        end
    end
end)

-- Framework logouts triggered by other resources (e.g. an admin menu) close our session too
local function frameworkLogout(src)
    local s = Sessions[src]
    if s and s.stage == 'playing' then closeSession(src) end
end

if NZ.IsQB then
    AddEventHandler('QBCore:Server:OnPlayerUnload', frameworkLogout)
    AddEventHandler('qbx_core:server:playerLoggedOut', frameworkLogout)
elseif NZ.IsESX then
    AddEventHandler('esx:playerLogout', frameworkLogout)
end
