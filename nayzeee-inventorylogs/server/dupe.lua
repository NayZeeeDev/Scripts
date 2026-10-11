-- Anti-dupe. A scheduled scan reads every inventory (online players, offline characters, stashes,
-- trunks and gloveboxes) and looks for two things:
--   1. the same unique value (weapon serial by default) in more than one slot
--   2. an item whose total count on the server jumped since the last scan
-- The rapid back-and-forth detector lives in hooks.lua because it runs on every move.
local D = Config.AntiDupe
local Last = nil          -- latest scan result
local Alerted = {}        -- dupe group key -> true (so a group is only reported once)
local LastSupply = nil    -- item -> total from the previous scan
local scanning = false

local function decode(s)
    if not s or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    return ok and type(v) == 'table' and v or {}
end

local function ignoredValue(v)
    v = tostring(v)
    for _, prefix in ipairs(D.ignoreValues or {}) do
        if v == prefix or v:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local IGNORE_SUPPLY = {}
for _, n in ipairs((D.supply and D.supply.ignore) or {}) do IGNORE_SUPPLY[n] = true end

-- ─── scan ────────────────────────────────────────────────────────────────────
local function scan()
    local started = os.clock()
    local groups, supply = {}, {}
    local counts = { online = 0, offline = 0, stashes = 0, vehicles = 0 }
    local keys = Inv.UniqueKeys()

    local function feed(kind, id, label, items, online)
        for _, it in pairs(items or {}) do
            if type(it) == 'table' and it.name then
                local n = tonumber(it.count) or 1
                if not IGNORE_SUPPLY[it.name] then supply[it.name] = (supply[it.name] or 0) + n end
                local meta = it.metadata
                if type(meta) == 'table' then
                    for _, k in ipairs(keys) do
                        local v = meta[k]
                        if v ~= nil and v ~= '' and not ignoredValue(v) then
                            local gk = ('%s|%s=%s'):format(it.name, k, tostring(v))
                            local g = groups[gk]
                            if not g then g = { item = it.name, key = k, value = tostring(v), where = {} } groups[gk] = g end
                            g.where[#g.where + 1] = { kind = kind, id = tostring(id), label = label, slot = it.slot, online = online }
                        end
                    end
                end
            end
        end
    end

    -- online players come straight from the inventory's memory
    local online = {}
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        local items = Inv.Get(src)
        if items then
            local charId = NZ.CharId(src)
            if charId then online[charId] = src end
            feed('player', src, GetPlayerName(src) or ('#' .. src), items, src)
            counts.online = counts.online + 1
        end
    end

    Inv.Save()

    if D.includeOffline ~= false then
        Inv.EachOffline(function(id, items)
            if not online[id] then
                feed('offline', id, id, items)
                counts.offline = counts.offline + 1
            end
        end)
    end

    if D.includeStashes ~= false or D.includeVehicles ~= false then
        Inv.EachStorage(function(id, kind, label, items)
            local vehicle = kind == 'trunk' or kind == 'glovebox'
            feed(vehicle and kind or 'stash', id, id, items)
            if vehicle then counts.vehicles = counts.vehicles + 1 else counts.stashes = counts.stashes + 1 end
        end, nil, { stash = D.includeStashes ~= false or nil, trunk = D.includeVehicles ~= false or nil, glovebox = D.includeVehicles ~= false or nil })
    end

    -- duplicates = any unique value found in more than one slot
    local dupes = {}
    for gk, g in pairs(groups) do
        if #g.where > 1 then
            g.id = gk
            dupes[#dupes + 1] = g
        end
    end
    table.sort(dupes, function(a, b) return #a.where > #b.where end)

    -- supply movement vs the previous scan
    local movers, spikes = {}, {}
    local S = D.supply or {}
    for item, total in pairs(supply) do
        local prev = LastSupply and LastSupply[item]
        if prev then
            local diff = total - prev
            if diff ~= 0 then movers[#movers + 1] = { item = item, total = total, prev = prev, diff = diff, pct = prev > 0 and math.floor(diff / prev * 1000) / 10 or 100 } end
            if S.enabled and diff >= (S.minimum or 50) and prev > 0 and (diff / prev * 100) >= (S.percent or 40) then
                spikes[#spikes + 1] = { item = item, total = total, prev = prev, diff = diff }
            end
        end
    end
    table.sort(movers, function(a, b) return math.abs(a.diff) > math.abs(b.diff) end)

    local result = {
        time = os.time(), took = math.floor((os.clock() - started) * 1000), counts = counts,
        dupes = dupes, movers = { table.unpack(movers, 1, math.min(#movers, 40)) }, items = 0,
    }
    for _ in pairs(supply) do result.items = result.items + 1 end
    return result, supply, spikes
end

local function report(result, supply, spikes)
    -- new duplicate groups
    for _, g in ipairs(result.dupes) do
        if not Alerted[g.id] then
            Alerted[g.id] = true
            local info = ItemInfo(g.item)
            local label = info and info.label or g.item
            local places = {}
            for i, w in ipairs(g.where) do if i <= 6 then places[#places + 1] = ('%s %s'):format(w.kind, w.label) end end
            local details = ('%s with %s %s found in %d places: %s'):format(label, g.key, g.value, #g.where, table.concat(places, ', '))
            local holder = g.where[1] and g.where[1].online and NZ.Actor(g.where[1].online) or { name = g.where[1] and g.where[1].label or '?' }
            InsertLog({ type = 'dupe', source_name = holder.name, source_identifier = holder.identifier, source_id = holder.id,
                item_name = g.item, item_label = label, item_count = #g.where, metadata = { [g.key] = g.value },
                details = details })
            local KIND = { player = 'Player', offline = 'Offline player', stash = 'Stash', trunk = 'Trunk', glovebox = 'Glovebox', drop = 'Ground drop' }
            local list = {}
            for i, w in ipairs(g.where) do
                if i <= 12 then list[#list + 1] = ('`%d.` %s **%s**%s'):format(i, KIND[w.kind] or w.kind, w.label or w.id, w.slot and (' · slot %s'):format(w.slot) or '') end
            end
            if #g.where > 12 then list[#list + 1] = ('…and %d more'):format(#g.where - 12) end
            SendWebhook('dupe', 'Duplicate item found', { player = holder.id and holder or nil, item = { name = g.item, label = label, count = #g.where },
                details = ('The same **%s** (%s `%s`) exists in **%d** places at once. Only one of them can be the real one.'):format(label, g.key, tostring(g.value), #g.where),
                metadata = { [g.key] = g.value },
                extra = {
                    { ('Found in (%d)'):format(#g.where), table.concat(list, '\n'), false },
                    { 'What to do', 'Open **Dupes** in the panel to compare them and remove the copies.', false },
                } })
            if D.notifyStaff then NZ.NotifyStaff(('Duplicate %s (%s %s) in %d places'):format(label, g.key, g.value, #g.where), 'error', 'dupes') end
        end
    end
    -- supply spikes
    for _, sp in ipairs(spikes) do
        local info = ItemInfo(sp.item)
        local label = info and info.label or sp.item
        local details = ('%s went from %s to %s on the server since the last scan (+%s)'):format(label, NZ.Comma(sp.prev), NZ.Comma(sp.total), NZ.Comma(sp.diff))
        InsertLog({ type = 'supply_spike', source_name = 'Server', source_identifier = 'server', item_name = sp.item, item_label = label, item_count = sp.diff, details = details })
        SendWebhook('dupe', 'Item supply spike', { item = { name = sp.item, label = label, count = sp.diff }, details = details,
            extra = {
                { 'Last scan', NZ.Comma(sp.prev), true },
                { 'Now', NZ.Comma(sp.total), true },
                { 'Change', ('+%s (+%s%%)'):format(NZ.Comma(sp.diff), sp.prev > 0 and math.floor(sp.diff / sp.prev * 100) or 100), true },
            } })
        if D.notifyStaff then NZ.NotifyStaff(details, 'warning', 'dupes') end
    end
    -- keep supply history for the charts
    if D.supply and D.supply.enabled then
        local rows, params = {}, {}
        for item, total in pairs(supply) do
            rows[#rows + 1] = '(?, ?)'
            params[#params + 1] = item
            params[#params + 1] = total
            if #rows >= 400 then
                MySQL.insert.await('INSERT INTO `nayzeee_inventory_supply` (`item`, `total`) VALUES ' .. table.concat(rows, ','), params)
                rows, params = {}, {}
            end
        end
        if #rows > 0 then MySQL.insert.await('INSERT INTO `nayzeee_inventory_supply` (`item`, `total`) VALUES ' .. table.concat(rows, ','), params) end
        MySQL.update('DELETE FROM `nayzeee_inventory_supply` WHERE `taken_at` < DATE_SUB(NOW(), INTERVAL ? DAY)', { D.supply.keepDays or 7 })
    end
    LastSupply = supply
end

local function runScan()
    if scanning then NZ.Fail('A scan is already running.') end
    scanning = true
    local ok, result, supply, spikes = pcall(scan)
    scanning = false
    if not ok then NZ.Print('Anti-dupe scan failed: ' .. tostring(result), 'error') NZ.Fail('The scan failed, check the server console.') end
    report(result, supply, spikes)
    Last = result
    return result
end

CreateThread(function()
    if not D or not D.enabled then return end
    Wait(90000)
    -- the first scan only sets the supply baseline, it doesn't raise supply alerts
    local ok, r, supply = pcall(scan)
    if ok then Last = r report(r, supply, {}) end
    local every = math.max(5, D.scanMinutes or 30) * 60000
    while true do
        Wait(every)
        if not scanning then pcall(runScan) end
    end
end)

-- ─── routes ──────────────────────────────────────────────────────────────────
NZ.Route('dupe:status', 'view', function()
    local flags = FetchLogsRaw({ type = 'dupe' }, 20)
    local attempts = FetchLogsRaw({ type = 'dupe_attempt' }, 20)
    local supplyFlags = FetchLogsRaw({ type = 'supply_spike' }, 20)
    return { enabled = D.enabled, keys = Inv.UniqueKeys(), last = Last, scanning = scanning, every = D.scanMinutes, flags = flags, attempts = attempts, supply = supplyFlags }
end)

NZ.Route('dupe:scan', 'manage', function(src)
    local r = runScan()
    NZ.Audit(src, 'dupe_scan', nil, { dupes = #r.dupes, took = r.took })
    return r
end)

NZ.Route('supply:item', 'view', function(src, d)
    local days = math.min(30, math.max(1, tonumber(d.days) or 7))
    return MySQL.query.await('SELECT `total`, UNIX_TIMESTAMP(`taken_at`) AS `time` FROM `nayzeee_inventory_supply` WHERE `item` = ? AND `taken_at` >= DATE_SUB(NOW(), INTERVAL ? DAY) ORDER BY `id`', { d.item, days }) or {}
end)

--- Remove one duplicate copy. d = { item, key, value, where = { kind, id, slot } }
NZ.Route('dupe:remove', 'manage', function(src, d)
    local w = d.where or {}
    local meta = { [d.key or 'serial'] = d.value }
    local done = false
    if w.kind == 'player' then
        done = Inv.Remove(tonumber(w.id), d.item, 1, meta, tonumber(w.slot)) > 0
    elseif w.kind == 'offline' then
        if NZ.OnlineByCharId(w.id) then NZ.Fail('That character just came online. Run the scan again.') end
        local items = OfflineRead(w.id)
        if items then
            for i, it in ipairs(items) do
                if it.name == d.item and (not w.slot or it.slot == tonumber(w.slot)) and Inv.MetaMatch(it.metadata, meta) then
                    table.remove(items, i)
                    OfflineWrite(w.id, items)
                    done = true
                    break
                end
            end
        end
    else
        done = Inv.RemoveFrom(tostring(w.id), d.item, 1, meta, tonumber(w.slot)) > 0
    end
    if not done then NZ.Fail('That copy was not found any more. Run the scan again.') end
    local me = NZ.Actor(src)
    InsertLog({ type = 'admin_remove', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = d.item, item_count = 1, metadata = meta, inventory_from = tostring(w.id), coords = me.coords, resource = NZ.Resource,
        details = ('%s removed a duplicate %s (%s %s) from %s %s'):format(me.name, d.item, d.key or 'serial', d.value, w.kind or '?', w.id or '?') })
    NZ.Audit(src, 'dupe_remove', d.item, { key = d.key, value = d.value, where = w })
    -- keep the cached result in step
    if Last then
        for _, g in ipairs(Last.dupes) do
            if g.item == d.item and g.value == tostring(d.value) then
                for i, x in ipairs(g.where) do
                    if x.kind == w.kind and x.id == tostring(w.id) and tostring(x.slot) == tostring(w.slot) then table.remove(g.where, i) break end
                end
            end
        end
    end
    return true
end)
