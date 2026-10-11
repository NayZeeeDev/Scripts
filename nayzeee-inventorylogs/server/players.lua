-- Player lookup and inventory management. Offline edits write the character's saved inventory
-- through the inventory integration, and refuse to run while that character is online.
local function slotLimit() return Inv.Limits().slots end
local function weightLimit() return Inv.Limits().weight end

-- ─── item catalogue ─────────────────────────────────────────────────────────
function ItemCatalogue(force) return Inv.Items(force) end
function ItemInfo(name) return Inv.Item(name) end

NZ.Route('items:list', 'view', function() return ItemCatalogue() end)

-- ─── offline storage ────────────────────────────────────────────────────────
local function readOffline(charId) return Inv.OfflineRead(charId) end
local function writeOffline(charId, items)
    local clean = {}
    for _, it in pairs(items) do
        if type(it) == 'table' and it.name and (it.count or 0) > 0 then clean[#clean + 1] = it end
    end
    table.sort(clean, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return Inv.OfflineWrite(charId, clean)
end
OfflineRead, OfflineWrite = readOffline, writeOffline

local function serial()
    local s = ''
    for _ = 1, 3 do s = s .. string.char(math.random(65, 90)) end
    return s .. math.random(100000, 999999)
end

--- Add to a saved item list (common shape). Returns true or nil, err.
function OfflineAdd(items, name, count, metadata)
    local info = ItemInfo(name)
    if not info then return nil, 'That item does not exist.' end
    metadata = type(metadata) == 'table' and metadata or {}
    if info.weapon and not next(metadata) then
        metadata = Inv.NewWeaponMeta(serial())
    end
    local stack = info.stack ~= false and not next(metadata)
    local used = {}
    for _, it in pairs(items) do if it.slot then used[it.slot] = it end end
    if stack then
        for _, it in pairs(items) do
            if it.name == name and (not it.metadata or not next(it.metadata)) then
                it.count = (it.count or 0) + count
                return true
            end
        end
    end
    local perSlot = stack and count or 1
    local slots = stack and 1 or count
    for _ = 1, slots do
        local free
        for s = 1, slotLimit() do if not used[s] then free = s break end end
        if not free then return nil, 'Their inventory is out of free slots.' end
        local entry = { name = name, count = perSlot, slot = free, metadata = next(metadata) and metadata or nil }
        items[#items + 1] = entry
        used[free] = entry
    end
    return true
end

function OfflineRemove(items, name, count, slot)
    local left = count
    for i, it in pairs(items) do
        if it.name == name and (not slot or it.slot == slot) then
            local take = left == math.huge and it.count or math.min(it.count or 0, left)
            it.count = (it.count or 0) - take
            if it.count <= 0 then items[i] = nil end
            if left ~= math.huge then left = left - take end
            if left <= 0 then break end
        end
    end
    return count == math.huge and true or left < count
end

-- ─── target resolution ─────────────────────────────────────────────────────
--- d.target = { id = serverId } or { charId = '...' }
local function resolve(t)
    t = t or {}
    local id = tonumber(t.id)
    if id and GetPlayerName(id) then
        local info = NZ.CharInfo(id)
        return { online = true, id = id, charId = info.charId, name = info.char or info.name, player = GetPlayerName(id) }
    end
    if t.charId and t.charId ~= '' then
        local online = NZ.OnlineByCharId(t.charId)
        if online then return resolve({ id = online }) end
        return { online = false, charId = t.charId, name = t.name or t.charId }
    end
    NZ.Fail('That player could not be found.')
end
ResolveTarget = resolve

local function listFromInventory(items)
    local out = {}
    for slot, it in pairs(items or {}) do
        if type(it) == 'table' and it.name then
            local info = ItemInfo(it.name)
            out[#out + 1] = {
                slot = it.slot or tonumber(slot), name = it.name, label = it.label or (info and info.label) or it.name,
                count = it.count or 1, weight = it.weight or ((info and info.weight or 0) * (it.count or 1)), metadata = it.metadata or {},
            }
        end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end
InventoryList = listFromInventory

local function logAdmin(src, kind, target, item, label, count, details)
    local me = NZ.Actor(src)
    InsertLog({
        type = kind, source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        target_name = target.name, target_identifier = target.charId, target_id = target.id,
        item_name = item, item_label = label or item, item_count = count, coords = me.coords, details = details,
        resource = NZ.Resource,
    })
    local tgt = target.online and target.id and NZ.Actor(target.id) or { name = target.name, identifier = target.charId }
    local inv = target.online and target.id or nil
    local wipe = item == 'all_items'
    SendWebhook(kind, wipe and 'Inventory wiped' or (kind == 'admin_give' and 'Admin gave item' or 'Admin removed item'), {
        admin = me, target = tgt,
        item = not wipe and { name = item, label = label or item, count = count } or nil,
        from = kind == 'admin_remove' and inv or nil, to = kind == 'admin_give' and inv or nil,
        details = details, coords = me.coords,
        extra = {
            { 'Target was', target.online and 'Online' or 'Offline (saved to their character)', true },
            { 'Character ID', target.charId and ('`%s`'):format(target.charId) or nil, true },
        },
    })
end
LogAdminAction = logAdmin

-- ─── routes: players ────────────────────────────────────────────────────────
NZ.Route('players:online', 'view', function()
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        local info = NZ.CharInfo(id)
        local ids = NZ.Identifiers(id)
        local discord = ids.discord and ids.discord:gsub('discord:', '') or nil
        out[#out + 1] = {
            id = id, player = info.name, name = info.char or info.name, charId = info.charId,
            job = info.job, grade = info.grade, jobName = info.jobName, license = NZ.License(id),
            discord = discord, avatar = discord and GetDiscordAvatar and GetDiscordAvatar(discord) or nil,
            ping = GetPlayerPing(id),
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

-- Character table columns differ between frameworks and versions, so they're read once.
local charCols
local function characterColumns()
    if charCols then return charCols end
    local rows = MySQL.query.await('SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { NZ.DB.players }) or {}
    local have = {}
    for _, r in ipairs(rows) do have[r.c] = true end
    local seen
    for _, c in ipairs({ 'last_seen', 'last_logged_out', 'last_updated', 'lastupdated', 'last_login', 'updated_at', 'created_at' }) do
        if have[c] then seen = c break end
    end
    charCols = { have = have, seen = seen }
    return charCols
end

--- charId -> character name for a list of ids (used by find item for offline characters)
function CharacterNames(ids)
    local out = {}
    if #ids == 0 then return out end
    local have = characterColumns().have
    local sel
    if have.firstname and have.lastname then sel = '`firstname`, `lastname`'
    elseif have.charinfo then sel = '`charinfo`'
    elseif have.name then sel = '`name`' end
    if not sel then return out end
    local ok, rows = pcall(MySQL.query.await, ('SELECT `%s` AS `id`, %s FROM `%s` WHERE `%s` IN (?)'):format(NZ.DB.pcol, sel, NZ.DB.players, NZ.DB.pcol), { ids })
    for _, r in ipairs(ok and rows or {}) do
        local name
        if r.firstname or r.lastname then name = NZ.Trim(('%s %s'):format(r.firstname or '', r.lastname or ''))
        elseif r.charinfo then
            local okc, ci = pcall(json.decode, r.charinfo)
            if okc and type(ci) == 'table' then name = NZ.Trim(('%s %s'):format(ci.firstname or '', ci.lastname or '')) end
        else name = r.name end
        if name and name ~= '' then out[tostring(r.id)] = name end
    end
    return out
end

local function onlineMap()
    local map = {}
    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        local c = NZ.CharId(id)
        if c then map[c] = id end
    end
    return map
end

local function decodeJson(v)
    if type(v) ~= 'string' or v == '' then return {} end
    local ok, r = pcall(json.decode, v)
    return ok and type(r) == 'table' and r or {}
end

--- Every character in the database, online or not. Empty search = most recently seen.
NZ.Route('players:search', 'view', function(src, d)
    local q = NZ.Trim(d.q)
    local cols = characterColumns()
    local has = cols.have
    local like = '%' .. q .. '%'
    local limit = q == '' and 60 or 40
    local order = cols.seen and (' ORDER BY `%s` DESC'):format(cols.seen) or ''
    local seenSel = cols.seen and (', UNIX_TIMESTAMP(`%s`) AS `seen`'):format(cols.seen) or ''
    local where, params, sel = {}, {}, {}
    local pcol = NZ.DB.pcol
    sel[#sel + 1] = ('`%s` AS `charId`'):format(pcol)
    where[#where + 1] = ('`%s` LIKE ?'):format(pcol)
    if has.firstname and has.lastname then
        sel[#sel + 1] = '`firstname`, `lastname`'
        where[#where + 1] = '`firstname` LIKE ?'
        where[#where + 1] = '`lastname` LIKE ?'
        where[#where + 1] = "CONCAT_WS(' ', `firstname`, `lastname`) LIKE ?"
    end
    if has.charinfo then sel[#sel + 1] = '`charinfo`' where[#where + 1] = '`charinfo` LIKE ?' end
    if has.name then sel[#sel + 1] = '`name`' where[#where + 1] = '`name` LIKE ?' end
    if has.license then sel[#sel + 1] = '`license`' where[#where + 1] = '`license` LIKE ?' end
    if has.job then sel[#sel + 1] = '`job`' end
    local sql = ('SELECT %s%s FROM `%s`'):format(table.concat(sel, ', '), seenSel, NZ.DB.players)
    if q ~= '' then
        sql = sql .. ' WHERE ' .. table.concat(where, ' OR ')
        for _ = 1, #where do params[#params + 1] = like end
    end
    sql = sql .. order .. (' LIMIT %d'):format(limit)
    local ok, rows = pcall(MySQL.query.await, sql, params)
    if not ok then
        NZ.Print('Character search failed: ' .. tostring(rows), 'error')
        NZ.Fail('Character search failed, check the server console.')
    end
    local online = onlineMap()
    local out = {}
    for _, r in ipairs(rows or {}) do
        local name
        if r.firstname or r.lastname then name = NZ.Trim(('%s %s'):format(r.firstname or '', r.lastname or '')) end
        if (not name or name == '') and r.charinfo then
            local ci = decodeJson(r.charinfo)
            name = NZ.Trim(('%s %s'):format(ci.firstname or '', ci.lastname or ''))
        end
        local job = r.job
        if type(job) == 'string' and job:sub(1, 1) == '{' then
            local j = decodeJson(job)
            job = j.label or j.name
        end
        local charId = tostring(r.charId)
        out[#out + 1] = {
            charId = charId, name = (name and name ~= '') and name or charId, player = r.name, job = job,
            license = r.license, seen = r.seen, online = online[charId],
        }
    end
    -- online characters first, then most recently seen
    table.sort(out, function(x, y)
        if (x.online ~= nil) ~= (y.online ~= nil) then return x.online ~= nil end
        return (x.seen or 0) > (y.seen or 0)
    end)
    return out
end)

NZ.Route('player:timeline', 'view', function(src, d)
    if not d.identifier or d.identifier == '' then return {} end
    return FetchLogsRaw({ identifier = d.identifier }, 150)
end)

-- ─── routes: one player's inventory ────────────────────────────────────────
NZ.Route('inventory:get', 'view', function(src, d)
    local t = resolve(d.target)
    if t.online then
        local items, info = Inv.Get(t.id)
        if not items then NZ.Fail('Their inventory is not loaded yet.') end
        local list = listFromInventory(items)
        local w = info.weight
        if not w then w = 0 for _, it in ipairs(list) do w = w + (it.weight or 0) end end
        local L = Inv.Limits()
        return { target = t, items = list, weight = w, maxWeight = info.maxWeight or L.weight, slots = info.slots or L.slots }
    end
    local items = readOffline(t.charId)
    if not items then NZ.Fail('No character with that id.') end
    local list = listFromInventory(items)
    local w = 0
    for _, it in ipairs(list) do w = w + (it.weight or 0) end
    return { target = t, items = list, weight = w, maxWeight = weightLimit(), slots = slotLimit() }
end)

local function parseMeta(m)
    if type(m) == 'table' then return m end
    if type(m) == 'string' and m ~= '' then
        local ok, v = pcall(json.decode, m)
        if ok and type(v) == 'table' then return v end
        NZ.Fail('Metadata must be valid JSON, for example {"serial":"ABC123"}.')
    end
end

NZ.Route('inventory:give', 'manage', function(src, d)
    local t = resolve(d.target)
    local item, count = tostring(d.item or ''), math.floor(tonumber(d.count) or 0)
    if count <= 0 then NZ.Fail('Amount has to be at least 1.') end
    if count > (Config.GlobalActions.maxGive or 100000) then NZ.Fail('That amount is over the configured limit.') end
    local info = ItemInfo(item)
    if not info then NZ.Fail(('No item called "%s".'):format(item)) end
    local meta = parseMeta(d.metadata)
    if t.online then
        if not d.force and not Inv.CanCarry(t.id, item, count, meta) then NZ.Fail('They can\'t carry that much. Tick "ignore weight" to force it.') end
        MarkKnownTransfer(t.id, item, count, 'admin')
        local ok, resp = Inv.Add(t.id, item, count, meta)
        if not ok then NZ.Fail(('%s refused: %s'):format(Inv.label, resp or 'unknown reason')) end
    else
        local items = readOffline(t.charId)
        if not items then NZ.Fail('No character with that id.') end
        local ok, err = OfflineAdd(items, item, count, meta)
        if not ok then NZ.Fail(err) end
        writeOffline(t.charId, items)
    end
    logAdmin(src, 'admin_give', t, item, info.label, count, ('%s gave %s x%s to %s%s'):format(GetPlayerName(src) or 'Console', info.label, count, t.name, t.online and '' or ' (offline)'))
    NZ.Audit(src, 'give', t.charId, { item = item, count = count, online = t.online, metadata = meta })
    NZ.NotifyStaff(('%s gave %s x%s to %s'):format(GetPlayerName(src) or 'Console', info.label, count, t.name), 'success', 'staff', src)
    return true
end)

NZ.Route('inventory:remove', 'manage', function(src, d)
    local t = resolve(d.target)
    local item = tostring(d.item or '')
    local count = d.count == 'all' and math.huge or math.floor(tonumber(d.count) or 0)
    if count <= 0 then NZ.Fail('Amount has to be at least 1.') end
    local slot = tonumber(d.slot)
    local info = ItemInfo(item)
    local label = info and info.label or item
    local removed
    if t.online then
        local have = slot and (Inv.Slot(t.id, slot) or {}).count or Inv.Count(t.id, item)
        local want = math.min(have or 0, count)
        if want <= 0 then NZ.Fail('They don\'t have that item.') end
        removed = Inv.Remove(t.id, item, want, nil, slot)
        if removed <= 0 then NZ.Fail(('%s could not remove it.'):format(Inv.label)) end
    else
        local items = readOffline(t.charId)
        if not items then NZ.Fail('No character with that id.') end
        local before = 0
        for _, it in pairs(items) do if it.name == item and (not slot or it.slot == slot) then before = before + (it.count or 0) end end
        if before == 0 then NZ.Fail('They don\'t have that item.') end
        OfflineRemove(items, item, count, slot)
        writeOffline(t.charId, items)
        removed = math.min(before, count)
    end
    logAdmin(src, 'admin_remove', t, item, label, removed, ('%s removed %s x%s from %s%s'):format(GetPlayerName(src) or 'Console', label, removed, t.name, t.online and '' or ' (offline)'))
    NZ.Audit(src, 'remove', t.charId, { item = item, count = removed, slot = slot, online = t.online })
    return removed
end)

NZ.Route('inventory:set', 'manage', function(src, d)
    local t = resolve(d.target)
    local item, slot = tostring(d.item or ''), tonumber(d.slot)
    local want = math.floor(tonumber(d.count) or -1)
    if want < 0 then NZ.Fail('Enter an amount of 0 or more.') end
    local have
    if t.online then
        have = slot and (Inv.Slot(t.id, slot) or {}).count or Inv.Count(t.id, item)
    else
        local items = readOffline(t.charId) or {}
        have = 0
        for _, it in pairs(items) do if it.name == item and (not slot or it.slot == slot) then have = have + (it.count or 0) end end
    end
    have = have or 0
    if want == have then return true end
    local ok, r
    if want > have then
        ok, r = NZ.Call(src, 'inventory:give', { target = d.target, item = item, count = want - have, force = true })
    else
        ok, r = NZ.Call(src, 'inventory:remove', { target = d.target, item = item, count = have - want, slot = slot })
    end
    if not ok then NZ.Fail(r) end
    return true
end)

NZ.Route('inventory:wipe', 'manage', function(src, d)
    local t = resolve(d.target)
    if t.online then
        Inv.Clear(t.id, d.keep)
    else
        if not readOffline(t.charId) then NZ.Fail('No character with that id.') end
        writeOffline(t.charId, {})
    end
    logAdmin(src, 'admin_remove', t, 'all_items', 'Inventory wipe', 0, ('%s wiped the inventory of %s'):format(GetPlayerName(src) or 'Console', t.name))
    NZ.Audit(src, 'wipe_inventory', t.charId, { online = t.online })
    NZ.NotifyStaff(('%s wiped the inventory of %s'):format(GetPlayerName(src) or 'Console', t.name), 'warning', 'staff', src)
    return true
end)

-- ─── any inventory by id (stashes, trunks, drops, backpacks) ───────────────
NZ.Route('inventory:view', 'view', function(src, d)
    if not Config.AllowRemoteView then NZ.Fail('Remote inventory viewing is turned off in the config.') end
    local invId = NZ.Trim(d.inv)
    if invId == '' or invId == 'ground' then NZ.Fail('That inventory can\'t be viewed.') end
    local items, info = Inv.Read(invId)
    if not items then NZ.Fail('That inventory isn\'t loaded and has nothing saved.') end
    local list = listFromInventory(items)
    local w = 0
    for _, it in ipairs(list) do w = w + (it.weight or 0) end
    return { id = invId, label = info.label or invId, type = info.type, items = list, weight = info.weight or w, maxWeight = info.maxWeight, live = info.live == true }
end)

NZ.Route('inventory:removeFrom', 'manage', function(src, d)
    local invId = NZ.Trim(d.inv)
    local count = math.floor(tonumber(d.count) or 1)
    local removed = Inv.RemoveFrom(invId, d.item, count, nil, tonumber(d.slot))
    if removed <= 0 then NZ.Fail('Could not remove it. The item is not in that slot any more.') end
    local me = NZ.Actor(src)
    InsertLog({ type = 'admin_remove', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = d.item, item_label = Inv.Label(d.item), item_count = removed, inventory_from = invId, coords = me.coords, resource = NZ.Resource,
        details = ('%s removed %s x%s from %s'):format(me.name, Inv.Label(d.item), removed, invId) })
    NZ.Audit(src, 'remove_from_inventory', invId, { item = d.item, count = removed, slot = d.slot })
    return true
end)

-- ─── stash / trunk / glovebox browser ───────────────────────────────────────
NZ.Route('storage:list', 'view', function(src, d)
    if not Config.AllowRemoteView then NZ.Fail('Remote inventory viewing is turned off in the config.') end
    local want = d.kind
    local q = NZ.Trim(d.q):lower()
    local kinds = (want and want ~= 'all') and { [want] = true } or nil
    local out, total = {}, 0
    Inv.EachStorage(function(id, kind, label, items, owner)
        if q ~= '' and not (id:lower():find(q, 1, true) or tostring(label):lower():find(q, 1, true)) then return end
        total = total + 1
        if #out >= 300 then return end
        local n, stacks = 0, 0
        for _, it in ipairs(items) do n = n + (it.count or 0) stacks = stacks + 1 end
        out[#out + 1] = { id = id, kind = kind, label = label, owner = owner, stacks = stacks, count = n }
    end, nil, kinds)
    table.sort(out, function(a, b) return a.stacks > b.stacks end)
    return { rows = out, total = total }
end)
