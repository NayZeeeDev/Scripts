-- Item logging shared by every inventory integration. Integrations translate their own events
-- into these calls (see inventories/*.lua), and any script can report through the exports below.
InvLog = {}
local known = {}

local function enabled(kind) return Config.Logs.Enabled[kind] ~= false end
InvLog.Enabled = enabled

local function isBackpack(id)
    id = tostring(id or '')
    for _, prefix in ipairs(Config.BackpackPrefixes or {}) do
        if id:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- container type -> log prefix. `put` = player puts into container, `take` = player takes out
local CONTAINERS = { stash = 'stash', trunk = 'trunk', glovebox = 'glovebox', container = 'container', policeevidence = 'evidence', evidence = 'evidence', backpack = 'backpack' }
local TITLES = {
    drop = 'Item dropped', pickup = 'Item picked up', give = 'Item given', take = 'Item taken from player',
    stash_put = 'Stash deposit', stash_take = 'Stash withdrawal', trunk_put = 'Trunk deposit', trunk_take = 'Trunk withdrawal',
    glovebox_put = 'Glovebox deposit', glovebox_take = 'Glovebox withdrawal', container_put = 'Container deposit', container_take = 'Container withdrawal',
    evidence_put = 'Evidence deposit', evidence_take = 'Evidence withdrawal', backpack_put = 'Backpack deposit', backpack_take = 'Backpack withdrawal',
    shop = 'Shop purchase', craft = 'Item crafted', created = 'Item created', suspicious = 'Suspicious item',
}
LogTitles = TITLES

--- (fromType, toType) -> log type. Types: player, otherplayer, drop, stash, trunk, glovebox, container, evidence, backpack
function InvLog.Classify(fromType, toType, fromInv, toInv)
    if fromType == 'player' and (toType == 'drop' or toType == 'newdrop') then return 'drop' end
    if fromType == 'drop' and toType == 'player' then return 'pickup' end
    if fromType == 'player' and (toType == 'player' or toType == 'otherplayer') then
        if fromInv == toInv then return end
        return 'give'
    end
    if fromType == 'otherplayer' and toType == 'player' then return 'take' end
    if fromType == 'player' and CONTAINERS[toType] then
        if toType == 'stash' and isBackpack(toInv) then return 'backpack_put' end
        return CONTAINERS[toType] .. '_put'
    end
    if CONTAINERS[fromType] and toType == 'player' then
        if fromType == 'stash' and isBackpack(fromInv) then return 'backpack_take' end
        return CONTAINERS[fromType] .. '_take'
    end
end

local function playerOf(inv)
    local id = tonumber(inv)
    if id and GetPlayerName(id) then return NZ.Actor(id) end
end

local function describe(kind, label, count, from, to, other)
    if kind == 'drop' then return ('Dropped %s x%s'):format(label, count) end
    if kind == 'pickup' then return ('Picked up %s x%s'):format(label, count) end
    if kind == 'give' then return ('Gave %s x%s to %s'):format(label, count, other or to) end
    if kind == 'take' then return ('Took %s x%s from %s'):format(label, count, other or from) end
    if kind:find('_put$') then return ('Put %s x%s into %s'):format(label, count, to) end
    if kind:find('_take$') then return ('Took %s x%s from %s'):format(label, count, from) end
    return ('%s x%s'):format(label, count)
end

local function isWeapon(name)
    local info = Inv.Item(name)
    if info and info.weapon then return true end
    return tostring(name):upper():sub(1, 7) == 'WEAPON_'
end

--- item = { name, label?, metadata? }. src = the player who did it.
function InvLog.Move(src, kind, item, count, fromInv, toInv)
    src = tonumber(src)
    if not src or not kind or not enabled(kind) or type(item) ~= 'table' then return end
    local me = NZ.Actor(src)
    local name = item.name or 'unknown'
    local label = item.label or Inv.Label(name)
    count = tonumber(count) or item.count or 1
    local other
    if kind == 'give' then other = playerOf(toInv) elseif kind == 'take' then other = playerOf(fromInv) end
    local from = kind == 'pickup' and 'ground' or tostring(fromInv)
    local to = kind == 'drop' and 'ground' or tostring(toInv)
    InsertLog({
        type = kind,
        source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        target_name = other and other.name or nil, target_identifier = other and other.identifier or nil, target_id = other and other.id or nil,
        item_name = name, item_label = label, item_count = count, metadata = item.metadata,
        inventory_from = from, inventory_to = to, coords = me.coords,
        details = describe(kind, label, count, from, to, other and other.name),
    })
    SendWebhook(kind, TITLES[kind] or kind, {
        player = me, target = other, item = { name = name, label = label, count = count },
        from = from, to = to, coords = me.coords, metadata = item.metadata, weapon = isWeapon(name),
        details = describe(kind, label, count, from, to, other and other.name),
    })
end

-- ─── suspicious detection ──────────────────────────────────────────────────
local function inList(list, value)
    value = tostring(value or ''):lower()
    for _, v in ipairs(list or {}) do if tostring(v):lower() == value then return true end end
    return false
end
InvLog.InList = inList

local function watchlisted(item)
    local S = Config.Suspicious
    if S.flagWeapons and isWeapon(item) then return true end
    return inList(S.watchlist, item)
end

local function overThreshold(item, count)
    local t = Config.Suspicious.thresholds[item] or Config.Suspicious.thresholds[item:lower()]
    return t and count >= t
end

function MarkKnownTransfer(playerId, itemName, count, reason)
    known[('%s:%s'):format(playerId, tostring(itemName):lower())] = { at = os.time(), reason = reason }
end
exports('MarkKnownTransfer', MarkKnownTransfer)
InvLog.Known = MarkKnownTransfer

local function isKnown(playerId, item)
    local k = ('%s:%s'):format(playerId, tostring(item):lower())
    local v = known[k]
    if v and os.time() - v.at <= 15 then known[k] = nil return true end
    return false
end

local function checkCreated(playerId, item, label, count, resource, metadata)
    local S = Config.Suspicious
    if not S.enabled then return end
    if inList(S.trustedResources, resource) and not inList(S.alwaysCheckResources, resource) then return end
    if isKnown(playerId, item) then return end
    local reasons = {}
    if inList(S.alwaysCheckResources, resource) then reasons[#reasons + 1] = ('created by %s'):format(resource) end
    if watchlisted(item) then reasons[#reasons + 1] = 'watchlisted item' end
    if overThreshold(item, count) then reasons[#reasons + 1] = ('amount over %s'):format(S.thresholds[item] or S.thresholds[item:lower()]) end
    if #reasons == 0 then return end
    local me = NZ.Actor(playerId)
    local details = ('%s x%s from %s: %s'):format(label, count, resource or 'unknown', table.concat(reasons, ', '))
    InsertLog({
        type = 'suspicious', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = item, item_label = label, item_count = count, metadata = metadata,
        inventory_to = tostring(playerId), coords = me.coords, details = details, resource = resource,
    })
    SendWebhook('suspicious', 'Flagged item', { player = me, item = { name = item, label = label, count = count }, resource = resource, coords = me.coords, details = details,
        metadata = metadata, to = playerId, extra = { { 'Why', table.concat(reasons, '\n'), true } } })
    if S.notifyStaff then NZ.NotifyStaff(('Flagged: %s received %s x%s (%s)'):format(me.name, label, count, resource or 'unknown'), 'error', 'flags') end
end

-- ─── anti-dupe: the same item bounced between the same two inventories very fast ───
local rapid = {}
function InvLog.Rapid(src, item, fromInv, toInv, count)
    local R = Config.AntiDupe and Config.AntiDupe.rapid
    if not (Config.AntiDupe and Config.AntiDupe.enabled and R and R.enabled) or not src or not item then return end
    local a, b = tostring(fromInv), tostring(toInv)
    if a == b then return end
    if a > b then a, b = b, a end
    local key = ('%s|%s|%s|%s'):format(src, item, a, b)
    local now = GetGameTimer()
    local r = rapid[key]
    if not r or now - r.start > R.seconds * 1000 then r = { start = now, n = 0 } rapid[key] = r end
    r.n = r.n + 1
    if r.n == R.moves then
        local me = NZ.Actor(src)
        local details = ('%s moved %s back and forth between %s and %s %d times in %ds'):format(me.name, item, a, b, r.n, math.ceil((now - r.start) / 1000))
        InsertLog({ type = 'dupe_attempt', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
            item_name = item, item_count = count or 1, inventory_from = a, inventory_to = b, coords = me.coords, details = details })
        SendWebhook('dupe', 'Possible dupe attempt', { player = me, item = { name = item, label = Inv.Label(item), count = count or 1 }, from = a, to = b, details = details, coords = me.coords,
            extra = { { 'Pattern', ('%d moves between the same two inventories in %ds'):format(r.n, math.ceil((now - r.start) / 1000)), false } } })
        if Config.AntiDupe.notifyStaff then NZ.NotifyStaff(details, 'error', 'dupes') end
    end
end

--- Shop purchase. price/currency optional.
function InvLog.Shop(src, item, count, shop, price, currency, metadata, toInv)
    src = tonumber(src)
    if not src or not enabled('shop') then return end
    local me = NZ.Actor(src)
    local label = Inv.Label(item)
    count = tonumber(count) or 1
    shop = tostring(shop or 'shop')
    local details = ('Bought %s x%s at %s for %s %s'):format(label, count, shop, price or 0, currency or 'money')
    InsertLog({ type = 'shop', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = item, item_label = label, item_count = count, metadata = metadata,
        inventory_from = shop, inventory_to = tostring(toInv or src), coords = me.coords, details = details })
    SendWebhook('shop', TITLES.shop, { player = me, item = { name = item, label = label, count = count }, from = shop, to = toInv or src, coords = me.coords, details = details, metadata = metadata,
        extra = { { 'Paid', ('%s %s'):format(NZ.Comma(price or 0), currency or 'money'), true } } })
    MarkKnownTransfer(src, item, count, 'shop')
end

--- Crafted item. ingredients = { name = amount } (optional)
function InvLog.Craft(src, item, count, bench, ingredients, metadata)
    src = tonumber(src)
    if not src or not enabled('craft') then return end
    local me = NZ.Actor(src)
    local label = Inv.Label(item)
    count = tonumber(count) or 1
    bench = tostring(bench or '?')
    local parts = {}
    for ing, n in pairs(ingredients or {}) do parts[#parts + 1] = ('%s x%s'):format(ing, n) end
    local details = ('Crafted %s x%s at %s%s'):format(label, count, bench, #parts > 0 and (' using ' .. table.concat(parts, ', ')) or '')
    InsertLog({ type = 'craft', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = item, item_label = label, item_count = count, metadata = metadata,
        inventory_from = 'bench:' .. bench, inventory_to = tostring(src), coords = me.coords, details = details })
    SendWebhook('craft', TITLES.craft, { player = me, item = { name = item, label = label, count = count }, from = 'bench:' .. bench, to = src, coords = me.coords, details = details, metadata = metadata,
        extra = { { 'Used', #parts > 0 and table.concat(parts, '\n') or nil, true } } })
    MarkKnownTransfer(src, item, count, 'craft')
end

local FRAMEWORK_RES = { es_extended = true, ['qb-core'] = true, qbx_core = true }

--- A script put an item into a player's inventory (not a move between inventories).
function InvLog.Created(playerId, item, count, resource, metadata, reason)
    playerId = tonumber(playerId)
    if not playerId or not GetPlayerName(playerId) or not item then return end
    local label = Inv.Label(item)
    count = tonumber(count) or 1
    resource = resource or 'unknown'
    if FRAMEWORK_RES[resource] then
        local by = AttrFor(playerId, 'item', item) or AttrFor(playerId, 'money', item)
        if by then
            resource = by
        elseif IsAccountItem(item) and resource == 'es_extended' then
            return -- ESX's own money call, already logged from the esx money event
        end
    end
    if IsAccountItem(item) and resource ~= 'es_extended' and not AttrFor(playerId, 'money', item) then
        AdjustBaseline(playerId, item, count)
        LogMoneyChange(playerId, item, count, 'Added as an inventory item', resource)
    end
    checkCreated(playerId, item, label, count, resource, metadata)
    local C = Config.CreationLogs
    if C.enabled and enabled('created') and not inList(C.ignoreItems, item) and not inList(C.ignoreResources, resource) then
        local me = NZ.Actor(playerId)
        InsertLog({ type = 'created', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
            item_name = item, item_label = label, item_count = count, metadata = metadata,
            inventory_to = tostring(playerId), coords = me.coords, resource = resource,
            details = ('%s x%s created by %s%s'):format(label, count, resource, reason and reason ~= '' and (' · ' .. tostring(reason)) or '') })
        SendWebhook('created', TITLES.created, { player = me, item = { name = item, label = label, count = count }, resource = resource, coords = me.coords, to = playerId,
            metadata = metadata, weapon = isWeapon(item), details = ('%s x%s given by %s'):format(label, count, resource),
            extra = { { 'Reason', reason and reason ~= '' and tostring(reason) or nil, true } } })
    end
end

-- ─── exports for inventories without a built-in integration ─────────────────
-- exports['nayzeee-inventorylogs']:LogMove({ source = 1, item = 'water', count = 2, fromType = 'player', toType = 'stash', from = 1, to = 'police_locker', metadata = {} })
exports('LogMove', function(d)
    if type(d) ~= 'table' then return end
    local kind = d.type or InvLog.Classify(d.fromType, d.toType, d.from, d.to)
    if not kind then return end
    InvLog.Rapid(d.source, d.item, d.from, d.to, d.count)
    InvLog.Move(d.source, kind, { name = d.item, label = d.label, metadata = d.metadata }, d.count, d.from, d.to)
end)
-- exports['nayzeee-inventorylogs']:LogShop({ source = 1, item = 'water', count = 2, shop = '24/7 #3', price = 10, currency = 'cash' })
exports('LogShop', function(d)
    if type(d) ~= 'table' then return end
    InvLog.Shop(d.source, d.item, d.count, d.shop, d.price, d.currency, d.metadata, d.to)
end)
-- exports['nayzeee-inventorylogs']:LogCraft({ source = 1, item = 'lockpick', count = 1, bench = 'mechanic', ingredients = { metalscrap = 2 } })
exports('LogCraft', function(d)
    if type(d) ~= 'table' then return end
    InvLog.Craft(d.source, d.item, d.count, d.bench, d.ingredients, d.metadata)
end)
-- exports['nayzeee-inventorylogs']:LogCreated({ source = 1, item = 'weed_bag', count = 5, resource = GetInvokingResource() })
exports('LogCreated', function(d)
    if type(d) ~= 'table' then return end
    InvLog.Created(d.source, d.item, d.count, d.resource or GetInvokingResource(), d.metadata, d.reason)
end)

-- ─── start ──────────────────────────────────────────────────────────────────
Inv.Select()

CreateThread(function()
    Wait(500)
    if Inv.Ready() and Inv.Has('start') then Inv.Call('start') end
    Inv.StartWatching()
end)

-- clear stale known-transfer marks
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for k, v in pairs(known) do if now - v.at > 60 then known[k] = nil end end
        local t = GetGameTimer()
        for k, v in pairs(rapid) do if t - v.start > 120000 then rapid[k] = nil end end
    end
end)
