-----------------------------------------------------------------
-- Wearing chains
--
-- Like nayzeee-backpack: a worn chain STAYS in the inventory, the
-- item just says so (metadata worn = true). What a player wears is
-- always rebuilt from their real inventory, so it survives relogs and
-- restarts, and a chain that leaves the pockets (dropped, traded,
-- stashed) comes off the neck by itself.
--
-- Everyone sees it through the player statebag `nzc_worn`
-- { c = chain key, v = texture letter, h = holding it up }.
-----------------------------------------------------------------

Worn = { list = {}, ident = {}, accept = {}, loaded = {} }

local T = Config.Text

local function notify(src, msg, kind, duration)
    TriggerClientEvent('nzc:c:notify', src, msg, kind, duration)
end
Worn.notify = notify

local function serialOf(meta) return type(meta) == 'table' and meta.serial or nil end
local function newSerial() return ('NZC-%04d-%04d'):format(math.random(0, 9999), math.random(0, 9999)) end

local function clean(meta)
    local m = {}
    for k, v in pairs(meta or {}) do m[k] = v end
    m.worn = nil
    local key, letter = Chains.fromMeta(m)
    if key then m = Chains.meta(key, letter, m) end
    return m
end

local function publish(src)
    local w = Worn.list[src]
    if not GetPlayerName(src) then return end
    Player(src).state:set('nzc_worn', w and { c = w.key, v = w.letter, h = w.holding or nil } or nil, true)
end

-- set or clear the worn flag on one slot. Returns ok
local function flag(src, slot, on)
    local meta = Inv.Peek(src, slot)
    if not meta then return false end
    local m = clean(meta)
    if on then
        m.worn = true
        m.serial = m.serial or newSerial()
    end
    local key, letter = Chains.fromMeta(m)
    if key then m = Chains.meta(key, letter, m) end -- the description says when it's worn
    local ok, lost = Inv.SetMeta(src, slot, m)
    if lost then
        -- qb / qs rewrite the item to change it; if it couldn't go back in, it lands at their feet: never lost
        local c = GetEntityCoords(GetPlayerPed(src))
        Drops.add({ meta = clean(m), coords = { x = c.x, y = c.y, z = c.z - 0.9 }, rot = { x = 0.0, y = 0.0, z = 0.0 }, thrown = true })
        return false
    end
    return ok, m.serial
end

--- Rebuild what `src` wears from their inventory. `want` = serial of a chain they just put on.
function Worn.refresh(src, want)
    local cur = Worn.list[src]
    local keep = want or (cur and cur.serial)
    local pick
    local items = Inv.Chains(src)
    for _, it in ipairs(items) do
        if it.meta.worn and Chains.fromMeta(it.meta) and not it.meta.broken then
            local s = serialOf(it.meta)
            -- ours: the one they put on, the one they had on, or anything flagged when they just loaded in
            if (keep and s == keep) or (not keep and Worn.accept[src]) then
                if not pick then pick = it end
            end
        end
    end
    -- every other "worn" flag (a chain that came from someone else, a stash, the ground ...) is cleared
    -- (only once their character has loaded: before that, nothing is touched)
    if Worn.loaded[src] then
        for _, it in ipairs(items) do
            if it.meta.worn and it ~= pick then flag(src, it.slot, false) end
        end
    end
    Worn.accept[src] = nil
    if pick then
        local key, letter = Chains.fromMeta(pick.meta)
        local holding = cur and cur.serial == serialOf(pick.meta) and cur.holding or false
        Worn.list[src] = { key = key, letter = letter, meta = clean(pick.meta), slot = pick.slot, serial = serialOf(pick.meta), holding = holding }
    else
        Worn.list[src] = nil
    end
    local now = Worn.list[src]
    local function sig(w) return w and ('%s|%s|%s|%s'):format(w.key, w.letter, tostring(w.serial), tostring(w.holding)) or '' end
    if sig(now) ~= sig(cur) then publish(src) end
    return now
end

function Worn.get(src) return Worn.list[src] end

--- Put on a chain that isn't in the pockets yet (snatched, caught, picked up, given). The one worn now stays in
--- the pockets. Returns ok.
function Worn.set(src, meta)
    local key, letter = Chains.fromMeta(meta)
    if not key or meta.broken then return false end
    local m = Chains.meta(key, letter, clean(meta))
    m.serial = m.serial or newSerial()
    m.worn = true
    m = Chains.meta(key, letter, m)
    if not Inv.CanCarry(src, m) or not Inv.Add(src, m) then return false end
    Worn.refresh(src, m.serial)
    return Worn.list[src] ~= nil
end

--- Take the worn chain off the player AND out of their inventory (it's thrown, placed, snatched, handed over).
--- Returns its metadata (no longer worn), key, letter.
function Worn.strip(src)
    local w = Worn.refresh(src)
    if not w then return nil end
    local meta = Inv.TakeSlot(src, w.slot)
    Worn.list[src] = nil
    publish(src)
    if not meta then Worn.refresh(src) return nil end
    meta = clean(meta)
    return meta, w.key, w.letter
end

function Worn.setHolding(src, on)
    local w = Worn.list[src]
    if not w then return false end
    w.holding = on and true or false
    publish(src)
    return true
end

--- Take it off: it stays in the pockets.
function Worn.takeOff(src)
    local w = Worn.refresh(src)
    if not w then return false, T.no_chain end
    flag(src, w.slot, false)
    Worn.list[src] = nil
    publish(src)
    Worn.refresh(src)
    return true, T.took_off:format(w.meta.label or 'chain')
end

--- Chain in inventory slot -> on the neck (the one worn now just comes off, it's in the pockets anyway).
function Worn.wearSlot(src, slot)
    local meta = Inv.Peek(src, slot)
    if not meta then return false end
    if meta.broken then return false, T.broken end
    if not Chains.fromMeta(meta) then return false, 'That chain isn\'t on this server any more.' end
    local cur = Worn.refresh(src)
    if cur and cur.slot == slot then return false, T.wearing:format(cur.meta.label or 'chain') end
    if cur then flag(src, cur.slot, false) end
    local ok, serial = flag(src, slot, true)
    if not ok then Worn.refresh(src) return false end
    Worn.refresh(src, serial)
    local w = Worn.list[src]
    return w ~= nil, w and T.wearing:format(w.meta.label) or nil
end

-----------------------------------------------------------------
-- load in / keep current
-----------------------------------------------------------------

local function kvpKey(ident) return 'worn:' .. ident end

local function restore(src)
    local ident = Bridge.GetIdentifier(src)
    Worn.ident[src] = ident
    -- chains worn with an older version lived outside the inventory: put them back in, worn
    if ident then
        local raw = GetResourceKvpString(kvpKey(ident))
        local ok, meta = pcall(json.decode, raw or 'null')
        if ok and type(meta) == 'table' and Chains.fromMeta(meta) then
            local m = clean(meta)
            m.serial = m.serial or newSerial()
            m.worn = Config.Wear.KeepOnRelog ~= false or nil
            if Inv.Add(src, m) then DeleteResourceKvp(kvpKey(ident)) end
        elseif raw then
            DeleteResourceKvp(kvpKey(ident))
        end
    end
    if Config.Wear.KeepOnRelog == false then
        for _, it in ipairs(Inv.Chains(src)) do if it.meta.worn then flag(src, it.slot, false) end end
    end
    Worn.accept[src] = true
    Worn.loaded[src] = true
    Worn.refresh(src)
    publish(src) -- statebags outlive a resource restart: always send the real state once
end

RegisterNetEvent('nzc:s:ready', function()
    local src = source
    restore(src)
end)

Bridge.OnLoaded(function(src) SetTimeout(1500, function() restore(src) end) end)

Bridge.OnUnloaded(function(src)
    if SnatchForfeit then SnatchForfeit(src) end
    Worn.list[src] = nil
    Worn.ident[src] = nil
    Worn.loaded[src] = nil
    if GetPlayerName(src) then Player(src).state:set('nzc_worn', nil, true) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if SnatchForfeit then SnatchForfeit(src) end
    Worn.list[src] = nil
    Worn.ident[src] = nil
    Worn.accept[src] = nil
    Worn.loaded[src] = nil
end)

-- a worn chain that left the pockets (dropped, given through the inventory, put in a stash) comes off the neck
if GetResourceState('ox_inventory') ~= 'missing' then
    CreateThread(function()
        Wait(2000)
        if Inv.Name ~= 'ox_inventory' then return end
        pcall(function()
            exports.ox_inventory:registerHook('swapItems', function(payload)
                local from, to = payload.fromInventory, payload.toInventory
                SetTimeout(150, function()
                    if type(from) == 'number' then Worn.refresh(from) end
                    if type(to) == 'number' and to ~= from then Worn.refresh(to) end
                end)
            end, { itemFilter = { [Config.Item] = true } })
        end)
    end)
end
CreateThread(function()
    while true do
        Wait(3000)
        for src in pairs(Worn.list) do
            if GetPlayerName(src) then Worn.refresh(src) else Worn.list[src] = nil end
        end
    end
end)

-----------------------------------------------------------------
-- player actions
-----------------------------------------------------------------

local function busyNow(src)
    if SnatchBusy and SnatchBusy(src) then notify(src, T.busy, 'error') return true end
    return false
end
Worn.busy = busyNow

-- using the item opens its menu (put on / take off, hold up, set down, give ...), like a backpack
local function slotInfo(src, slot)
    local meta = Inv.Peek(src, slot)
    local key, letter = Chains.fromMeta(meta)
    if not key then return nil end
    return {
        slot = slot, key = key, variant = letter, label = Chains.label(key, letter), worn = meta.worn == true,
        broken = meta.broken == true, value = Chains.money(Chains.value(key)), stolenFrom = meta.stolenFrom, madeFor = meta.madeFor,
    }
end
Worn.slotInfo = slotInfo

Inv.HookUse(function(src, slot)
    if busyNow(src) then return end
    Worn.refresh(src)
    local info = slot and slotInfo(src, tonumber(slot))
    if not info then return end
    TriggerClientEvent('nzc:c:itemMenu', src, info, Worn.list[src] and Worn.list[src].holding or false)
end)

RegisterNetEvent('nzc:s:wear', function(slot)
    local src = source
    if busyNow(src) then return end
    local ok, msg = Worn.wearSlot(src, slot)
    if msg then notify(src, msg, ok and 'success' or 'error') end
    if ok then TriggerClientEvent('nzc:c:anim', src, 'wear') end
end)

RegisterNetEvent('nzc:s:takeOff', function()
    local src = source
    if busyNow(src) then return end
    local ok, msg = Worn.takeOff(src)
    if msg then notify(src, msg, ok and 'success' or 'error') end
    if ok then TriggerClientEvent('nzc:c:anim', src, 'wear') end
end)

RegisterNetEvent('nzc:s:hold', function(on)
    local src = source
    if on and busyNow(src) then return end
    if not Worn.setHolding(src, on) and on then notify(src, T.no_chain, 'error') end
end)

-- what the chain menu shows
lib.callback.register('nzc:menu', function(src)
    local w = Worn.refresh(src)
    local pockets = {}
    for _, it in ipairs(Inv.Chains(src)) do
        local key, letter = Chains.fromMeta(it.meta)
        if key then
            local p = slotInfo(src, it.slot)
            if p then p.image = Chains.model(key, letter); pockets[#pockets + 1] = p end
        end
    end
    return {
        worn = w and { slot = w.slot, key = w.key, variant = w.letter, label = w.meta.label, image = Chains.model(w.key, w.letter), holding = w.holding,
                       value = Chains.money(Chains.value(w.key)), stolenFrom = w.meta.stolenFrom, madeFor = w.meta.madeFor } or nil,
        pockets = pockets,
    }
end)

-----------------------------------------------------------------
-- admin
-----------------------------------------------------------------

local function newMeta(key, letter, src)
    return Chains.meta(key, letter, {
        serial = newSerial(),
        owner = src and src > 0 and Bridge.GetCharName(src) or nil,
        -- exclusive chains say who they were made for; normal store chains don't
        madeFor = src and src > 0 and Chains.def(key) and Chains.def(key).exclusive and Bridge.GetCharName(src) or nil,
    })
end
Worn.newMeta = newMeta

--- Give a chain to a player. Returns ok.
function Worn.give(target, key, letter)
    if not Chains.exists(key) then return false end
    local v = Chains.variant(key, letter)
    return Inv.Add(target, newMeta(key, v and v.letter or 'a', target))
end

lib.addCommand('givechain', {
    help = 'Give a chain (/chainlist for keys)',
    params = {
        { name = 'id', type = 'playerId', help = 'Player id' },
        { name = 'chain', type = 'string', help = 'Chain key or part of its name' },
        { name = 'variant', type = 'string', help = 'Texture letter (a, b, ...)', optional = true },
    },
    restricted = false,
}, function(src, args)
    if src > 0 and not Bridge.IsAdmin(src) then return notify(src, T.no_admin, 'error') end
    local key = args.chain
    if not Chains.exists(key) then
        local q = key:lower()
        for _, k in ipairs(Chains.keys()) do
            if Chains.list[k].label:lower():find(q, 1, true) or k:lower():find(q, 1, true) then key = k break end
        end
    end
    if not Chains.exists(key) then
        local msg = 'No chain matches "' .. tostring(args.chain) .. '"'
        if src > 0 then notify(src, msg, 'error') else print(msg) end
        return
    end
    local ok = Worn.give(args.id, key, args.variant and args.variant:lower() or nil)
    local msg = ok and ('Gave %s to %s'):format(Chains.label(key, args.variant), GetPlayerName(args.id) or args.id) or 'Could not give it (inventory full?)'
    if src > 0 then notify(src, msg, ok and 'success' or 'error') else print(msg) end
    if ok then Logs.send('admin', 'Chain given', ('%s gave %s to %s'):format(src > 0 and Logs.who(src) or 'console', Chains.label(key, args.variant), Logs.who(args.id))) end
end)

lib.addCommand('chainlist', { help = 'List every chain key', restricted = false }, function(src)
    if src > 0 and not Bridge.IsAdmin(src) then return notify(src, T.no_admin, 'error') end
    local lines = {}
    for _, k in ipairs(Chains.keys()) do
        local d = Chains.list[k]
        local letters = {}
        for _, v in ipairs(d.variants) do letters[#letters + 1] = v.letter end
        lines[#lines + 1] = ('%s  [%s]  %s'):format(d.label, table.concat(letters, ','), k)
    end
    if src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Chains', #lines == 0 and 'none yet' or table.concat(lines, '\n') } })
    else
        print(#lines == 0 and 'no chains yet' or table.concat(lines, '\n'))
    end
end)

-----------------------------------------------------------------
-- exports
-----------------------------------------------------------------

exports('GetWornChain', function(src)
    local w = Worn.list[src]
    return w and { chain = w.key, variant = w.letter, label = w.meta.label, metadata = w.meta, holding = w.holding } or nil
end)
exports('GiveChain', function(src, key, variant) return Worn.give(src, key, variant) end)
exports('TakeWornChain', function(src) return Worn.strip(src) end)
exports('GetChains', function() return Chains.list end)
