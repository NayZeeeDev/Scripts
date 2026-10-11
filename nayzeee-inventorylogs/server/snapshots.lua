-- Money and inventory snapshots, saved to the database so they survive a crash or restart.
-- Snapshots are keyed by character id, so a rollback always lands on the right character.

local function moneyOf(src)
    local out = {}
    if NZ.Framework == 'esx' then
        local x = exports.es_extended:getSharedObject().GetPlayerFromId(src)
        if not x then return end
        for _, a in ipairs(x.getAccounts and x.getAccounts() or {}) do out[a.name] = a.money end
    else
        local p
        if NZ.Framework == 'qbx' then
            local ok, r = pcall(function() return exports.qbx_core:GetPlayer(src) end)
            p = ok and r or nil
        elseif GetResourceState('qb-core') == 'started' then
            p = exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
        end
        if not p then return end
        for k, v in pairs(p.PlayerData.money or {}) do out[k] = v end
    end
    return out
end

local function itemsOf(src)
    local items = Inv.Get(src)
    if not items then return end
    local out = {}
    for _, it in ipairs(items) do
        out[#out + 1] = { name = it.name, count = it.count, slot = it.slot, metadata = next(it.metadata or {}) and it.metadata or nil }
    end
    return out
end

local function take(kind)
    local players, n = {}, 0
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        local charId = NZ.CharId(id)
        if charId then
            local info = NZ.CharInfo(id)
            local data = kind == 'money' and moneyOf(id) or itemsOf(id)
            if data then
                players[charId] = { name = info.char or info.name, player = GetPlayerName(id), data = data }
                n = n + 1
            end
        end
    end
    if n == 0 then return end
    local id = MySQL.insert.await('INSERT INTO `nayzeee_inventory_snapshots` (`kind`, `players`, `data`) VALUES (?, ?, ?)', { kind, n, json.encode(players) })
    local keep = Config.Rollback.keep or 24
    MySQL.update.await(([[DELETE FROM `nayzeee_inventory_snapshots` WHERE `kind` = ? AND `id` NOT IN (
        SELECT `id` FROM (SELECT `id` FROM `nayzeee_inventory_snapshots` WHERE `kind` = ? ORDER BY `id` DESC LIMIT %d) AS `keep`)]]):format(keep), { kind, kind })
    NZ.Debug(('%s snapshot #%s saved (%d characters)'):format(kind, id, n))
    return id
end
TakeSnapshot = take

CreateThread(function()
    if not Config.Rollback.enabled then return end
    Wait(30000)
    local every = math.max(60, Config.Rollback.interval or 300) * 1000
    while true do
        if Config.Rollback.money then take('money') end
        if Config.Rollback.inventory then take('inventory') end
        Wait(every)
    end
end)

local function load(id)
    local row = MySQL.single.await('SELECT `id`, `kind`, `data`, UNIX_TIMESTAMP(`taken_at`) AS `time` FROM `nayzeee_inventory_snapshots` WHERE `id` = ?', { id })
    if not row then NZ.Fail('That snapshot no longer exists.') end
    row.data = json.decode(row.data) or {}
    return row
end

-- ─── restore helpers ───────────────────────────────────────────────────────
local function restoreMoney(charId, money)
    local src = NZ.OnlineByCharId(charId)
    if not src then return false, 'offline' end
    ResetMoneyBaseline(charId)
    if NZ.Framework == 'esx' then
        local x = exports.es_extended:getSharedObject().GetPlayerFromId(src)
        if not x then return false, 'not loaded' end
        for acc, amount in pairs(money) do pcall(x.setAccountMoney, acc, amount, 'nz-rollback') end
    else
        local p
        if NZ.Framework == 'qbx' then p = exports.qbx_core:GetPlayer(src)
        else p = exports['qb-core']:GetCoreObject().Functions.GetPlayer(src) end
        if not p then return false, 'not loaded' end
        for acc, amount in pairs(money) do p.Functions.SetMoney(acc, amount, 'nz-rollback') end
    end
    return true
end

local function restoreItems(charId, items)
    local src = NZ.OnlineByCharId(charId)
    if src then
        Inv.Clear(src)
        local bad = 0
        for _, it in ipairs(items) do
            MarkKnownTransfer(src, it.name, it.count, 'rollback')
            if not Inv.Add(src, it.name, it.count, it.metadata, it.slot) then bad = bad + 1 end
        end
        return true, bad
    end
    OfflineWrite(charId, items)
    return true, 0
end

NZ.Route('snapshots:list', 'rollback', function(src, d)
    local kind = d.kind == 'money' and 'money' or 'inventory'
    local rows = MySQL.query.await('SELECT `id`, `players`, UNIX_TIMESTAMP(`taken_at`) AS `time` FROM `nayzeee_inventory_snapshots` WHERE `kind` = ? ORDER BY `id` DESC LIMIT 50', { kind }) or {}
    return rows
end)

NZ.Route('snapshots:get', 'rollback', function(src, d)
    local snap = load(tonumber(d.id))
    local list = {}
    for charId, p in pairs(snap.data) do
        local summary
        if snap.kind == 'money' then
            local total = 0
            for _, v in pairs(p.data) do total = total + (tonumber(v) or 0) end
            summary = total
        else
            summary = #p.data
        end
        list[#list + 1] = { charId = charId, name = p.name, player = p.player, summary = summary, online = NZ.OnlineByCharId(charId) }
    end
    table.sort(list, function(a, b) return (a.name or '') < (b.name or '') end)
    return { id = snap.id, kind = snap.kind, time = snap.time, players = list }
end)

--- One character: snapshot vs now
NZ.Route('snapshots:compare', 'rollback', function(src, d)
    local snap = load(tonumber(d.id))
    local p = snap.data[d.charId]
    if not p then NZ.Fail('That character is not in this snapshot.') end
    local online = NZ.OnlineByCharId(d.charId)
    local now
    if snap.kind == 'money' then
        now = online and moneyOf(online) or nil
    else
        now = online and itemsOf(online) or OfflineRead(d.charId)
    end
    return { kind = snap.kind, time = snap.time, name = p.name, before = p.data, now = now, online = online }
end)

NZ.Route('snapshots:rollback', 'rollback', function(src, d)
    local snap = load(tonumber(d.id))
    local targets = {}
    if d.charId then
        if not snap.data[d.charId] then NZ.Fail('That character is not in this snapshot.') end
        targets[d.charId] = snap.data[d.charId]
    else
        targets = snap.data
    end
    local okCount, skipped = 0, 0
    for charId, p in pairs(targets) do
        local ok
        if snap.kind == 'money' then ok = restoreMoney(charId, p.data)
        else ok = restoreItems(charId, p.data) end
        if ok then okCount = okCount + 1 else skipped = skipped + 1 end
    end
    local me = NZ.Actor(src)
    local details = ('%s rolled back %s for %d character%s to %s%s'):format(me.name, snap.kind, okCount, okCount == 1 and '' or 's',
        os.date('%Y-%m-%d %H:%M', snap.time), skipped > 0 and (' (%d offline skipped)'):format(skipped) or '')
    InsertLog({ type = 'rollback', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = snap.kind, item_label = snap.kind == 'money' and 'Money rollback' or 'Inventory rollback', item_count = okCount,
        target_identifier = d.charId, coords = me.coords, details = details, resource = NZ.Resource })
    local who = d.charId and snap.data[d.charId] or nil
    SendWebhook('rollback', snap.kind == 'money' and 'Money rollback' or 'Inventory rollback', { admin = me, details = details, coords = me.coords,
        target = who and { name = who.name, identifier = d.charId, id = NZ.OnlineByCharId(d.charId) } or nil,
        extra = {
            { 'Snapshot', ('#%s · %s'):format(snap.id, os.date('%Y-%m-%d %H:%M', snap.time)), true },
            { 'Restored', ('%s character%s'):format(okCount, okCount == 1 and '' or 's'), true },
            { 'Skipped (offline)', skipped > 0 and tostring(skipped) or nil, true },
            { 'Who', not d.charId and 'Everyone in the snapshot' or nil, true },
        } })
    NZ.Audit(src, 'rollback_' .. snap.kind, d.charId or 'everyone', { snapshot = snap.id, restored = okCount, skipped = skipped })
    NZ.NotifyStaff(details, 'warning', 'staff', src)
    return { restored = okCount, skipped = skipped }
end)

NZ.Route('snapshots:take', 'rollback', function(src, d)
    local m = take('money')
    local i = take('inventory')
    NZ.Audit(src, 'snapshot_take', nil, { money = m, inventory = i })
    return { money = m, inventory = i }
end)
