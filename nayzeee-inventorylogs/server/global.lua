-- Server-wide item actions: give to everyone, find an item anywhere, remove it everywhere.
local function countIn(items, name)
    local n = 0
    for _, it in pairs(items or {}) do
        if type(it) == 'table' and it.name == name then n = n + (it.count or 0) end
    end
    return n
end

local function onlineCharIds()
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        local c = NZ.CharId(id)
        if c then out[c] = id end
    end
    return out
end

local function scan(item, scope)
    scope = scope or {}
    local res = { online = {}, offline = {}, stashes = {}, vehicles = {}, totals = { online = 0, offline = 0, stashes = 0, vehicles = 0 } }

    if scope.online ~= false then
        for _, sid in ipairs(GetPlayers()) do
            local id = tonumber(sid)
            local n = Inv.Count(id, item)
            if n > 0 then
                local info = NZ.CharInfo(id)
                res.online[#res.online + 1] = { id = id, name = info.char or info.name, charId = info.charId, count = n }
                res.totals.online = res.totals.online + n
            end
        end
    end

    if scope.offline or scope.stashes or scope.vehicles then Inv.Save() end

    if scope.offline then
        local online = onlineCharIds()
        Inv.EachOffline(function(id, items)
            if online[id] then return end
            local n = countIn(items, item)
            if n > 0 then
                res.offline[#res.offline + 1] = { charId = id, count = n }
                res.totals.offline = res.totals.offline + n
            end
        end, item)
    end

    if scope.stashes or scope.vehicles then
        Inv.EachStorage(function(id, kind, label, items, owner)
            local n = countIn(items, item)
            if n <= 0 then return end
            if kind == 'trunk' or kind == 'glovebox' then
                if scope.vehicles then
                    res.vehicles[#res.vehicles + 1] = { id = id, key = label, where = kind, count = n }
                    res.totals.vehicles = res.totals.vehicles + n
                end
            elseif scope.stashes then
                res.stashes[#res.stashes + 1] = { id = id, name = label, owner = owner, count = n }
                res.totals.stashes = res.totals.stashes + n
            end
        end, item, { stash = scope.stashes and true or nil, trunk = scope.vehicles and true or nil, glovebox = scope.vehicles and true or nil })
    end

    if #res.offline > 0 then
        local ids = {}
        for i, r in ipairs(res.offline) do ids[i] = r.charId end
        local map = CharacterNames and CharacterNames(ids) or {}
        for _, r in ipairs(res.offline) do r.name = map[r.charId] end
    end

    for _, list in pairs({ res.online, res.offline, res.stashes, res.vehicles }) do
        table.sort(list, function(a, b) return a.count > b.count end)
    end
    res.total = res.totals.online + res.totals.offline + res.totals.stashes + res.totals.vehicles
    return res
end

NZ.Route('global:scan', 'view', function(src, d)
    local item = NZ.Trim(d.item)
    if item == '' then NZ.Fail('Pick an item first.') end
    local r = scan(item, d.scope)
    r.item = item
    return r
end)

-- ─── remove everywhere ─────────────────────────────────────────────────────
local function strip(items, name, amount)
    local removed = 0
    for i, it in pairs(items) do
        if type(it) == 'table' and it.name == name then
            local take = amount and math.min(it.count or 0, amount - removed) or (it.count or 0)
            it.count = (it.count or 0) - take
            removed = removed + take
            if it.count <= 0 then items[i] = nil end
            if amount and removed >= amount then break end
        end
    end
    local clean = {}
    for _, it in pairs(items) do if type(it) == 'table' then clean[#clean + 1] = it end end
    return clean, removed
end

NZ.Route('global:remove', 'global', function(src, d)
    local item = NZ.Trim(d.item)
    if item == '' then NZ.Fail('Pick an item first.') end
    local scope = d.scope or { online = true }
    local per = tonumber(d.amount)   -- nil = every copy
    if per then
        per = math.floor(per)
        if per < 1 then NZ.Fail('Amount has to be at least 1.') end
    end
    local done = { online = 0, offline = 0, stashes = 0, vehicles = 0, inventories = 0 }

    if scope.online ~= false then
        for _, sid in ipairs(GetPlayers()) do
            local id = tonumber(sid)
            local have = Inv.Count(id, item)
            if have > 0 then
                local n = Inv.Remove(id, item, per and math.min(per, have) or have)
                if n > 0 then
                    done.online = done.online + n
                    done.inventories = done.inventories + 1
                end
            end
        end
    end

    if scope.offline or scope.stashes or scope.vehicles then Inv.Save() end

    if scope.offline then
        local online = onlineCharIds()
        local targets = {}
        Inv.EachOffline(function(id, items)
            if not online[id] and countIn(items, item) > 0 then targets[#targets + 1] = { id = id, items = items } end
        end, item)
        for _, t in ipairs(targets) do
            local left, n = per, 0
            for _, it in ipairs(t.items) do
                if it.name == item and (not left or left > 0) then
                    local take = left and math.min(left, it.count) or it.count
                    it.count = it.count - take
                    n = n + take
                    if left then left = left - take end
                end
            end
            if n > 0 then
                local keep = {}
                for _, it in ipairs(t.items) do if it.count > 0 then keep[#keep + 1] = it end end
                Inv.OfflineWrite(t.id, keep)
                done.offline = done.offline + n
                done.inventories = done.inventories + 1
            end
        end
    end

    if scope.stashes or scope.vehicles then
        local targets = {}
        Inv.EachStorage(function(id, kind, _, items)
            local have = countIn(items, item)
            if have > 0 then targets[#targets + 1] = { id = id, kind = kind, have = have } end
        end, item, { stash = scope.stashes and true or nil, trunk = scope.vehicles and true or nil, glovebox = scope.vehicles and true or nil })
        for i, t in ipairs(targets) do
            local n = Inv.RemoveFrom(t.id, item, per and math.min(per, t.have) or t.have)
            if n > 0 then
                local bucket = (t.kind == 'trunk' or t.kind == 'glovebox') and 'vehicles' or 'stashes'
                done[bucket] = done[bucket] + n
                done.inventories = done.inventories + 1
            end
            if i % 50 == 0 then Wait(0) end
        end
    end

    local total = done.online + done.offline + done.stashes + done.vehicles
    local me = NZ.Actor(src)
    local info = ItemInfo(item)
    local label = info and info.label or item
    local details = ('%s removed %s x%s server-wide from %d inventories (online %d, offline %d, stashes %d, vehicles %d)'):format(me.name, label, total, done.inventories, done.online, done.offline, done.stashes, done.vehicles)
    InsertLog({ type = 'global_remove', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = item, item_label = label, item_count = total, coords = me.coords, details = details, resource = NZ.Resource })
    SendWebhook('global', 'Item removed server-wide', { admin = me, item = { name = item, label = label, count = total }, details = details, coords = me.coords,
        extra = {
            { 'Removed from', ('%s inventories'):format(NZ.Comma(done.inventories)), true },
            { 'Per inventory', per and ('up to %s'):format(NZ.Comma(per)) or 'every copy', true },
            { 'Breakdown', ('Online players: %s\nOffline characters: %s\nStashes: %s\nVehicles: %s'):format(NZ.Comma(done.online), NZ.Comma(done.offline), NZ.Comma(done.stashes), NZ.Comma(done.vehicles)), false },
        } })
    NZ.Audit(src, 'global_remove', item, { scope = scope, amount = per, result = done })
    NZ.NotifyStaff(details, 'warning', 'staff', src)
    done.total = total
    return done
end)

-- ─── give to everyone ──────────────────────────────────────────────────────
NZ.Route('global:give', 'global', function(src, d)
    local item = NZ.Trim(d.item)
    local count = math.floor(tonumber(d.count) or 0)
    if count <= 0 then NZ.Fail('Amount has to be at least 1.') end
    if count > (Config.GlobalActions.maxGive or 100000) then NZ.Fail('That amount is over the configured limit.') end
    local info = ItemInfo(item)
    if not info then NZ.Fail(('No item called "%s".'):format(item)) end
    local meta
    if type(d.metadata) == 'string' and d.metadata ~= '' then
        local ok, v = pcall(json.decode, d.metadata)
        if not ok or type(v) ~= 'table' then NZ.Fail('Metadata must be valid JSON.') end
        meta = v
    end
    local jobs, jobList = {}, {}
    for _, j in ipairs(type(d.jobs) == 'table' and d.jobs or {}) do
        if type(j) == 'string' or type(j) == 'number' then
            jobs[tostring(j):lower()] = true
            jobList[#jobList + 1] = tostring(j)
        end
    end
    local exclude = {}
    for _, id in ipairs(type(d.exclude) == 'table' and d.exclude or {}) do exclude[tonumber(id) or -1] = true end
    local only
    if type(d.only) == 'table' and #d.only > 0 then
        only = {}
        for _, id in ipairs(d.only) do only[tonumber(id) or -1] = true end
    end

    local res = { given = 0, players = 0, full = {}, skipped = 0 }
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        local info2 = next(jobs) and NZ.CharInfo(id) or nil
        local allowed = not exclude[id] and (not only or only[id]) and (not next(jobs) or (info2 and jobs[(info2.jobName or ''):lower()]))
        if not allowed then
            res.skipped = res.skipped + 1
        elseif not d.force and not Inv.CanCarry(id, item, count, meta) then
            res.full[#res.full + 1] = { id = id, name = GetPlayerName(id) }
        else
            MarkKnownTransfer(id, item, count, 'global')
            local ok = Inv.Add(id, item, count, meta)
            if ok then
                res.given = res.given + count
                res.players = res.players + 1
                if type(d.message) == 'string' and d.message ~= '' then NZ.Notify(id, d.message, 'success') end
            else
                res.full[#res.full + 1] = { id = id, name = GetPlayerName(id) }
            end
        end
    end

    local me = NZ.Actor(src)
    local details = ('%s gave %s x%s to %d players%s'):format(me.name, info.label, count, res.players, next(jobs) and (' (jobs: ' .. table.concat(jobList, ', ') .. ')') or '')
    InsertLog({ type = 'global_give', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = item, item_label = info.label, item_count = res.given, metadata = meta, coords = me.coords, details = details, resource = NZ.Resource })
    local fullNames = {}
    for i, f in ipairs(res.full) do if i <= 10 then fullNames[#fullNames + 1] = ('%s (%s)'):format(f.name or '?', f.id) end end
    SendWebhook('global', 'Item given server-wide', { admin = me, item = { name = item, label = info.label, count = count }, details = details, metadata = meta, coords = me.coords,
        extra = {
            { 'Players', NZ.Comma(res.players), true },
            { 'Total given', NZ.Comma(res.given), true },
            { 'Only jobs', next(jobs) and table.concat(jobList, ', ') or nil, true },
            { 'Skipped', res.skipped > 0 and NZ.Comma(res.skipped) or nil, true },
            { ('Couldn\'t carry it (%d)'):format(#res.full), #res.full > 0 and table.concat(fullNames, '\n') or nil, false },
            { 'Message to players', type(d.message) == 'string' and d.message ~= '' and d.message or nil, false },
        } })
    NZ.Audit(src, 'global_give', item, { count = count, jobs = jobList, only = d.only, exclude = d.exclude, result = { players = res.players, full = #res.full } })
    NZ.NotifyStaff(details, 'success', 'staff', src)
    return res
end)

exports('ScanItem', function(item, scope) return scan(item, scope) end)
