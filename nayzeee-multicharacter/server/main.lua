if not NAYZEEE_LOCK_OK then return end

--[[
    Server-authoritative session flow:
        select  -> (play)   -> loaded  -> (spawn) -> playing
        select  -> (create) -> created -> (shop)  -> loaded -> (spawn) -> playing
    Every callback checks the stage, ownership and rate limits.
]]

Sessions = {}
local T = NZ.T

-- ── helpers ───────────────────────────────────────────────────────────────
local limits = {}
local function limited(src, action)
    local ms = ServerConfig.RateLimit[action] or 1000
    limits[src] = limits[src] or {}
    local now = GetGameTimer()
    if limits[src][action] and now - limits[src][action] < ms then return true end
    limits[src][action] = now
    return false
end

local function setBucket(src, isolated)
    if not Config.World.routingBucket then return end
    if isolated then
        local b = Config.World.bucketBase + src
        SetPlayerRoutingBucket(src, b)
        SetRoutingBucketPopulationEnabled(b, not Config.World.noPopulation)
    else
        SetPlayerRoutingBucket(src, 0)
    end
end

local function flushPlaytime(s)
    if s and s.active and s.loadedAt then
        local now = os.time()
        DB.AddPlaytime(s.active, now - s.loadedAt)
        s.loadedAt = now
    end
end

local function charName(c) return c and (c.firstname .. ' ' .. c.lastname) or '?' end

-- Strip server-only fields before a character goes to the client
local function forClient(list)
    local out = {}
    for i = 1, #list do
        local c = list[i]
        local copy = {}
        for k, v in pairs(c) do if k ~= 'raw' then copy[k] = v end end
        out[i] = copy
    end
    return out
end

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
    local list, rawList = Characters.List(src, s.owner, total)
    s.total, s.slotInfo = total, info
    s.byId, s.bySlot = {}, {}
    for i = 1, #list do
        s.byId[list[i].id] = list[i]
        s.bySlot[list[i].slot] = list[i]
    end
    s.raw = {}
    for i = 1, #rawList do s.raw[rawList[i].id] = rawList[i] end
    return list
end

local function payload(src)
    local s = Sessions[src]
    local list = refresh(src)
    return {
        characters = forClient(list),
        slots      = s.slotInfo,
        canDelete  = canDelete(src),
        online     = #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 48),
        tebex      = ServerConfig.Tebex.enabled,
    }
end

-- Spawn options for a character (nil = no selector, spawn at firstSpawn)
local function spawnOptions(src, s, isNew)
    local cfg = Config.Spawn
    if cfg.custom.enabled and (not cfg.custom.newOnly or isNew) then return nil, 'custom' end
    if not cfg.selector then return nil, isNew and 'first' or 'last' end
    if isNew and not cfg.forNew then return nil, 'first' end

    local opts = {}
    local raw = s.raw and s.raw[s.active]
    if cfg.lastLocation and not isNew then
        local pos = (raw and raw.position) or Bridge.Position(s.active)
        if pos then
            opts[#opts + 1] = { id = 'last', kind = 'last', label = T('last_location'), desc = T('last_location_sub', raw and raw.firstname or ''), icon = 'clock-rotate-left', coords = pos }
        end
    end
    if cfg.houses then
        for _, h in ipairs(Housing.Get(src, s.active) or {}) do
            opts[#opts + 1] = { id = 'house:' .. h.id, kind = 'house', label = h.label, desc = h.desc or T('your_house'), icon = 'house', coords = h.coords }
        end
    end
    local job, grade = Bridge.ActiveJob(src)
    for _, p in ipairs(Config.SpawnPoints) do
        local ok = not p.newOnly or isNew
        if ok and p.jobs then ok = p.jobs[job] ~= nil and grade >= p.jobs[job] end
        if ok then opts[#opts + 1] = { id = 'point:' .. p.id, kind = 'point', label = p.label, desc = p.desc, icon = p.icon, coords = p.coords } end
    end
    if isNew then
        table.insert(opts, 1, { id = 'first', kind = 'point', label = T('first_spawn'), desc = T('first_spawn_sub'), icon = 'plane-arrival', coords = cfg.firstSpawn })
    end
    s.spawnOpts = {}
    for _, o in ipairs(opts) do s.spawnOpts[o.id] = o end
    return opts
end

local function giveStarter(src, s)
    local st = Config.Starter
    Bridge.AddMoney(src, 'cash', st.money.cash or 0)
    Bridge.AddMoney(src, 'bank', st.money.bank or 0)
    local c = s.raw and s.raw[s.active] or {}
    for _, it in ipairs(st.items or {}) do
        local meta = type(it.metadata) == 'function' and it.metadata(src, c) or it.metadata
        Bridge.AddItem(src, it.name, it.count or 1, meta)
    end
    if st.frameworkDefaults then Bridge.FrameworkStarter(src) end
end

-- ── session start ─────────────────────────────────────────────────────────
lib.callback.register('nzm:boot', function(src)
    while not Bridge.Ready() do Wait(100) end
    DB.Wait()

    local owner = Bridge.Owner(src)
    if not owner then return { error = 'no_license' } end

    -- Already loaded (resource restart mid-session): keep playing
    if Bridge.IsLoaded(src) then
        local s = Sessions[src]
        if not s or s.stage ~= 'select' then
            Sessions[src] = s or { owner = owner, stage = 'playing', active = Bridge.ActiveId(src), loadedAt = os.time() }
            return { loaded = true }
        end
    end

    Sessions[src] = { owner = owner, stage = 'select' }
    setBucket(src, true)
    return payload(src)
end)

-- ── play ─────────────────────────────────────────────────────────────────
lib.callback.register('nzm:play', function(src, charId)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return { ok = false } end
    if limited(src, 'play') then return { ok = false, msg = T('t_rate') } end
    local c = s.byId and s.byId[charId]
    if not c then return { ok = false, msg = T('t_error') } end
    if c.disabled then return { ok = false, msg = T('t_disabled') } end
    if c.locked then return { ok = false, msg = T('t_slot_locked') } end

    s.stage = 'loading'
    if not Bridge.Load(src, s.raw[charId] or c) then
        s.stage = 'select'
        return { ok = false, msg = T('t_error') }
    end
    s.active, s.loadedAt, s.isNew = charId, os.time(), false
    s.stage = 'loaded'
    DB.Set(charId, 'last_played', os.time())
    Logs.Send('loaded', src, { { 'Character', charName(c) }, { 'ID', charId } })

    local opts, mode = spawnOptions(src, s, false)
    return { ok = true, spawn = opts, mode = mode, skin = c.skin, model = c.model, gender = c.gender }
end)

-- ── create ───────────────────────────────────────────────────────────────
lib.callback.register('nzm:create', function(src, slot, form)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return { ok = false } end
    if limited(src, 'create') then return { ok = false, msg = T('t_rate') } end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > s.total then return { ok = false, msg = T('t_slot_locked') } end
    if s.bySlot[slot] then return { ok = false, msg = T('t_slot_taken') } end

    local data, errors = Validate.Registration(form)
    if not data then
        local R, msgs = Config.Registration, {}
        for field, key in pairs(errors) do
            if key == 'v_min' then msgs[field] = T(key, field == 'backstory' and R.backstory.min or R.name.min)
            elseif key == 'v_max' then msgs[field] = T(key, field == 'backstory' and R.backstory.max or R.name.max)
            elseif key == 'v_age_min' then msgs[field] = T(key, R.dob.minAge)
            elseif key == 'v_age_max' then msgs[field] = T(key, R.dob.maxAge)
            elseif key == 'v_height' then msgs[field] = T(key, R.height.min, R.height.max)
            else msgs[field] = T(key) end
        end
        return { ok = false, errors = msgs }
    end

    s.stage = 'creating'
    local ok, charId = Bridge.Create(src, slot, data)
    if not ok or not charId then
        s.stage = 'select'
        return { ok = false, msg = T('t_error') }
    end

    DB.Ensure(charId, s.owner)
    DB.Set(charId, 'nationality', data.nationality)
    DB.Set(charId, 'height', data.height)
    if data.backstory then DB.Set(charId, 'backstory', data.backstory) end
    DB.Set(charId, 'last_played', os.time())

    s.active, s.loadedAt, s.isNew = charId, os.time(), true
    s.raw = s.raw or {}
    s.raw[charId] = { id = charId, firstname = data.firstname, lastname = data.lastname, gender = data.gender }
    giveStarter(src, s)
    s.stage = Config.StarterShop.enabled and 'created' or 'loaded'

    Logs.Send('created', src, {
        { 'Character', data.firstname .. ' ' .. data.lastname }, { 'ID', charId }, { 'Slot', slot },
        { 'DOB', ('%04d-%02d-%02d'):format(data.dobY, data.dobM, data.dobD) }, { 'Gender', data.gender }, { 'Nationality', data.nationality or '-' },
    })

    local opts, mode = spawnOptions(src, s, true)
    return { ok = true, charId = charId, shop = Config.StarterShop.enabled, spawn = opts, mode = mode, gender = data.gender }
end)

-- ── starter shop ─────────────────────────────────────────────────────────
lib.callback.register('nzm:shop', function(src, cart)
    local s = Sessions[src]
    if not s or s.stage ~= 'created' then return { ok = false } end
    local cfg = Config.StarterShop
    local byName, spent, lines = {}, 0, {}
    for _, it in ipairs(cfg.items) do byName[it.type .. ':' .. it.name] = it end

    local picks = {}
    for key, qty in pairs(type(cart) == 'table' and cart or {}) do
        local it = byName[key]
        qty = math.floor(tonumber(qty) or 0)
        if it and qty > 0 then
            qty = math.min(qty, it.max or 1)
            spent = spent + it.price * qty
            picks[#picks + 1] = { it = it, qty = qty }
        end
    end
    if spent > cfg.budget then return { ok = false, msg = T('t_shop_budget') } end

    s.stage = 'loaded'
    for _, p in ipairs(picks) do
        if p.it.type == 'vehicle' then
            for _ = 1, p.qty do Bridge.GiveVehicle(src, s.active, p.it.name) end
        else
            Bridge.AddItem(src, p.it.name, p.qty)
        end
        lines[#lines + 1] = ('%sx %s'):format(p.qty, p.it.label)
    end
    local left = cfg.budget - spent
    if cfg.refundLeftover and left > 0 then Bridge.AddMoney(src, 'bank', left) end
    if #lines > 0 then Logs.Send('shop', src, { { 'Bought', table.concat(lines, ', ') }, { 'Spent', spent } }) end
    return { ok = true }
end)

lib.callback.register('nzm:shopSkip', function(src)
    local s = Sessions[src]
    if not s or s.stage ~= 'created' then return false end
    s.stage = 'loaded'
    if Config.StarterShop.refundLeftover then Bridge.AddMoney(src, 'bank', Config.StarterShop.budget) end
    return true
end)

-- ── spawn ────────────────────────────────────────────────────────────────
-- The client only sends an option id; coordinates always come from the server.
lib.callback.register('nzm:spawn', function(src, optionId)
    local s = Sessions[src]
    if not s or s.stage ~= 'loaded' then return nil end
    local coords
    if optionId == 'first' or optionId == nil then
        coords = Config.Spawn.firstSpawn
        if optionId == nil and not s.isNew then coords = Bridge.Position(s.active) or coords end
    elseif optionId == 'last' then
        coords = Bridge.Position(s.active) or Config.Spawn.firstSpawn
    elseif s.spawnOpts and s.spawnOpts[optionId] then
        coords = s.spawnOpts[optionId].coords
    end
    if not coords then return nil end
    s.stage = 'playing'
    setBucket(src, false)
    return { coords = coords, isNew = s.isNew }
end)

-- Custom spawn handoff (Config.Spawn.custom): release the player to the other resource
lib.callback.register('nzm:handoff', function(src)
    local s = Sessions[src]
    if not s or s.stage ~= 'loaded' then return false end
    s.stage = 'playing'
    setBucket(src, false)
    return true
end)

-- ── delete ───────────────────────────────────────────────────────────────
lib.callback.register('nzm:delete', function(src, charId, typed)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return { ok = false } end
    if not canDelete(src) then return { ok = false, msg = T('t_no_delete') } end
    if limited(src, 'delete') then return { ok = false, msg = T('t_rate') } end
    local c = s.byId[charId]
    if not c then return { ok = false, msg = T('t_error') } end
    if Config.Characters.typeToConfirm and NZ.Trim(typed or ''):lower() ~= charName(c):lower() then
        return { ok = false, msg = T('t_name_mismatch') }
    end
    if not Bridge.Delete(src, charId) then return { ok = false, msg = T('t_error') } end
    DB.Delete(charId)
    Logs.Send('deleted', src, { { 'Character', charName(c) }, { 'ID', charId } })
    return { ok = true, data = payload(src) }
end)

-- ── per-character meta (pose / favorite / backstory / partner) ─────────────
lib.callback.register('nzm:meta', function(src, charId, key, value)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' or not s.byId[charId] then return false end
    if limited(src, 'meta') then return false end
    local c = s.byId[charId]

    if key == 'pose' then
        local valid = value == nil
        for _, p in ipairs(Config.Poses) do if p.id == value then valid = true end end
        if not valid then return false end
        DB.Set(charId, 'pose', value)
        c.pose = value
    elseif key == 'favorite' then
        local on = value == true
        MySQL.update.await('UPDATE nayzeee_multichar SET favorite = 0 WHERE owner = ?', { s.owner })
        if on then DB.Set(charId, 'favorite', 1) end
        for _, other in pairs(s.byId) do other.favorite = false end
        c.favorite = on
    elseif key == 'backstory' then
        if not Config.Registration.backstory.enabled then return false end
        local b = Validate.Backstory(value)
        DB.Set(charId, 'backstory', b ~= '' and b or nil)
        c.backstory = b ~= '' and b or nil
    elseif key == 'partner' then
        if c.partner then
            DB.Set(charId, 'partner', nil)
            DB.Set(charId, 'partner_type', nil)
            c.partner = nil
        end
    else
        return false
    end
    return true
end)

-- ── redeem (Tebex) ───────────────────────────────────────────────────────
lib.callback.register('nzm:redeem', function(src, code)
    local s = Sessions[src]
    if not s then return { ok = false } end
    local cfg = ServerConfig.Tebex
    if not cfg.enabled then return { ok = false, msg = T('t_redeem_off') } end
    if limited(src, 'redeem') then return { ok = false, msg = T('t_rate') } end
    code = NZ.Trim(code or '')
    if not code:match('^[%w%-]+$') or #code > 64 then return { ok = false, msg = T('t_redeem_bad') } end
    if MySQL.scalar.await('SELECT 1 FROM nayzeee_multichar_redeem WHERE tid = ?', { code }) then return { ok = false, msg = T('t_redeem_bad') } end

    local secret = GetConvar(cfg.convar, '')
    if secret == '' then return { ok = false, msg = T('t_redeem_off') } end

    local p = promise.new()
    PerformHttpRequest(('https://plugin.tebex.io/payments/%s'):format(code), function(status, body)
        p:resolve(status == 200 and NZ.Decode(body) or nil)
    end, 'GET', '', { ['X-Tebex-Secret'] = secret })
    SetTimeout(8000, function() if p.state == 0 then p:resolve(nil) end end)
    local data = Citizen.Await(p)
    if not data or (data.status and data.status ~= 'Complete') then return { ok = false, msg = T('t_redeem_bad') } end

    local add = 0
    for _, pkg in ipairs(data.packages or {}) do
        local per = cfg.packages[tostring(pkg.id)]
        if per then add = add + per * (tonumber(pkg.quantity) or 1) end
    end
    if add <= 0 then return { ok = false, msg = T('t_redeem_bad') } end

    MySQL.insert.await('INSERT INTO nayzeee_multichar_redeem (tid, owner, slots, redeemed_at) VALUES (?, ?, ?, ?)', { code, s.owner, add, os.time() })
    DB.SetExtra(s.owner, DB.Extra(s.owner) + add, 'tebex')
    Logs.Send('redeem', src, { { 'Transaction', code }, { 'Slots', add } })
    local out = { ok = true, msg = T('t_redeemed', add) }
    if s.stage == 'select' then out.data = payload(src) end
    return out
end)

-- Reload the list (e.g. after slots changed)
lib.callback.register('nzm:refresh', function(src)
    local s = Sessions[src]
    if not s or s.stage ~= 'select' then return nil end
    return payload(src)
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
    Bridge.Logout(src)
    Logs.Send('relog', src, { { 'From', name or '-' }, { 'Forced', force and 'yes' or 'no' } })
    Sessions[src] = nil
    TriggerClientEvent('nzm:client:open', src)
    return true
end

RegisterNetEvent('nzm:server:relog', function()
    local src = source
    if Config.Relog.command.ace and not IsPlayerAceAllowed(src, Config.Relog.command.ace) then return end
    Relog(src, false)
end)

-- ── lifecycle ────────────────────────────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    flushPlaytime(Sessions[src])
    Sessions[src], limits[src], relogAt[src] = nil, nil, nil
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
if NZ.IsQB then
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        local s = Sessions[src]
        if s and s.stage == 'playing' then flushPlaytime(s) Sessions[src] = nil end
    end)
else
    AddEventHandler('esx:playerLogout', function(src)
        local s = Sessions[src]
        if s and s.stage == 'playing' then flushPlaytime(s) Sessions[src] = nil end
    end)
end
