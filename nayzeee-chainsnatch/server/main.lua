-----------------------------------------------------------------
-- Wearing chains
--
-- Putting a chain on takes it OUT of the inventory and onto the
-- player (so it can't be dropped, sold or duped while worn).
-- Taking it off puts it back. What someone wears is saved per
-- character, so it survives relogs and restarts.
--
-- Everyone sees it through the player statebag `nzc_worn`
-- { c = chain key, v = texture letter, h = holding it up }.
-----------------------------------------------------------------

Worn = { list = {}, ident = {} }

local T = Config.Text

local function notify(src, msg, kind, duration)
    TriggerClientEvent('nzc:c:notify', src, msg, kind, duration)
end
Worn.notify = notify

local function kvpKey(ident) return 'worn:' .. ident end

local function persist(src)
    local ident = Worn.ident[src]
    if not ident then return end
    local w = Worn.list[src]
    if w then SetResourceKvp(kvpKey(ident), json.encode(w.meta)) else DeleteResourceKvp(kvpKey(ident)) end
end

local function publish(src)
    local w = Worn.list[src]
    Player(src).state:set('nzc_worn', w and { c = w.key, v = w.letter, h = w.holding or nil } or nil, true)
end

function Worn.get(src) return Worn.list[src] end

--- Put a chain (item metadata) on the player.
function Worn.set(src, meta)
    local key, letter = Chains.fromMeta(meta)
    if not key then return false end
    Worn.list[src] = { key = key, letter = letter, meta = Chains.meta(key, letter, meta), holding = false }
    publish(src)
    persist(src)
    return true
end

--- Take the chain off the player without giving it anywhere. Returns its metadata.
function Worn.strip(src)
    local w = Worn.list[src]
    if not w then return nil end
    Worn.list[src] = nil
    publish(src)
    persist(src)
    return w.meta, w.key, w.letter
end

function Worn.setHolding(src, on)
    local w = Worn.list[src]
    if not w then return false end
    w.holding = on and true or false
    publish(src)
    return true
end

--- Worn chain back into the pockets.
function Worn.takeOff(src)
    local w = Worn.list[src]
    if not w then return false, T.no_chain end
    if not Inv.CanCarry(src, w.meta) then return false, T.no_room end
    local meta = Worn.strip(src)
    if not Inv.Add(src, meta) then
        Worn.set(src, meta) -- put it straight back on, nothing lost
        return false, T.no_room
    end
    return true, T.took_off:format(meta.label or 'chain')
end

--- Chain in inventory slot -> on the neck. A chain already worn goes back in its place.
function Worn.wearSlot(src, slot)
    local current = Worn.list[src]
    if current and not Inv.CanCarry(src, current.meta) then return false, T.no_room end
    local peek = Inv.Peek(src, slot)
    if peek and peek.broken then return false, T.broken end
    local meta = Inv.TakeSlot(src, slot)
    if not meta then return false end
    if not Chains.fromMeta(meta) then
        Inv.Add(src, meta) -- not a chain we know (removed from the server?), give it back
        return false, 'That chain isn\'t on this server any more.'
    end
    if current then
        local old = Worn.strip(src)
        Inv.Add(src, old)
    end
    Worn.set(src, meta)
    return true, T.wearing:format(Worn.list[src].meta.label)
end

-----------------------------------------------------------------
-- restore on join / character load
-----------------------------------------------------------------

local function restore(src)
    local ident = Bridge.GetIdentifier(src)
    if not ident then return end
    if Worn.ident[src] == ident and Worn.list[src] then return publish(src) end
    Worn.ident[src] = ident
    Worn.list[src] = nil
    local raw = GetResourceKvpString(kvpKey(ident))
    local ok, meta = pcall(json.decode, raw or 'null')
    if ok and type(meta) == 'table' and Chains.fromMeta(meta) then
        local key, letter = Chains.fromMeta(meta)
        if Config.Wear.KeepOnRelog or not Inv.Add(src, Chains.meta(key, letter, meta)) then
            Worn.list[src] = { key = key, letter = letter, meta = Chains.meta(key, letter, meta), holding = false }
        else
            DeleteResourceKvp(kvpKey(ident)) -- it went back into the pockets
        end
    end
    publish(src)
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
    if GetPlayerName(src) then Player(src).state:set('nzc_worn', nil, true) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if SnatchForfeit then SnatchForfeit(src) end
    Worn.list[src] = nil
    Worn.ident[src] = nil
end)

-----------------------------------------------------------------
-- player actions
-----------------------------------------------------------------

local function busyNow(src)
    if SnatchBusy and SnatchBusy(src) then notify(src, T.busy, 'error') return true end
    return false
end
Worn.busy = busyNow

Inv.HookUse(function(src, slot)
    if busyNow(src) then return end
    local ok, msg = Worn.wearSlot(src, slot)
    if msg then notify(src, msg, ok and 'success' or 'error') end
    if ok then TriggerClientEvent('nzc:c:anim', src, 'wear') end
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
    local w = Worn.list[src]
    local pockets = {}
    for _, it in ipairs(Inv.Chains(src)) do
        local key, letter = Chains.fromMeta(it.meta)
        if key then
            pockets[#pockets + 1] = { slot = it.slot, key = key, variant = letter, label = Chains.label(key, letter), image = Chains.model(key, letter), broken = it.meta.broken == true }
        end
    end
    return {
        worn = w and { key = w.key, variant = w.letter, label = w.meta.label, image = Chains.model(w.key, w.letter), holding = w.holding,
                       value = Chains.money(Chains.value(w.key)), stolenFrom = w.meta.stolenFrom, owner = w.meta.owner } or nil,
        pockets = pockets,
    }
end)

-----------------------------------------------------------------
-- admin
-----------------------------------------------------------------

local function newMeta(key, letter, src)
    return Chains.meta(key, letter, {
        serial = ('NZC-%04d-%04d'):format(math.random(0, 9999), math.random(0, 9999)),
        owner = src and src > 0 and Bridge.GetCharName(src) or nil,
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
    restricted = 'group.admin',
}, function(src, args)
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

lib.addCommand('chainlist', { help = 'List every chain key', restricted = 'group.admin' }, function(src)
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
