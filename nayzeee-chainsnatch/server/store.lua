-----------------------------------------------------------------
-- Jewelry store (server)
--
-- Buy for money, craft from materials, repair what snapped.
-- Exclusive chains (studio > Look > Owners) are tied to game
-- licenses: they're left out of everyone else's catalogue and the
-- server refuses anyone else who tries to buy them anyway.
-----------------------------------------------------------------

local cfg = Config.Store
local T = Config.Text
local busy = {}

local function recipe(key)
    local c = cfg.Craft
    if not c or not c.Enabled then return nil end
    local d = Chains.def(key)
    if not d or d.craftable == false then return nil end
    return c.PerChain and c.PerChain[key] or c.Default
end

local function repairPrice(key)
    local r = cfg.Repair or {}
    return math.max(r.Minimum or 0, math.floor((Chains.price(key) or Chains.value(key)) * (r.Rate or 0.15)))
end

local function nearStore(src)
    if cfg.OpenMode == 'command' then return true end -- no physical store at all
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    for _, loc in ipairs(cfg.Locations or {}) do
        if #(c - loc.coords) < 6.0 then return true end
    end
    return false
end

local function wallet(src)
    return { amount = Bridge.GetMoney(src, cfg.Currency), currency = cfg.Currency == 'bank' and 'Bank' or 'Cash' }
end

--- What this player can see in the store
local function catalog(src)
    local list = {}
    for _, key in ipairs(Chains.keys()) do
        local d = Chains.def(key)
        local price = Chains.price(key)
        if price and Registry.canBuy(src, key) then
            local vars = {}
            for _, v in ipairs(d.variants) do vars[#vars + 1] = { letter = v.letter, prop = v.prop, label = v.label } end
            local mats = recipe(key)
            local need = nil
            if mats then
                need = {}
                for _, m in ipairs(mats) do
                    need[#need + 1] = { item = m.item, label = m.label or m.item, count = m.count, have = Inv.Count(src, m.item) }
                end
            end
            list[#list + 1] = {
                key = key, label = d.label, price = price, variants = vars, exclusive = d.exclusive == true,
                madeFor = d.exclusive and d.madeFor or nil, recipe = need,
            }
        end
    end
    -- exclusive ones first: they were made for you
    table.sort(list, function(a, b)
        if a.exclusive ~= b.exclusive then return a.exclusive end
        if a.price ~= b.price then return a.price < b.price end
        return a.label < b.label
    end)
    return list
end

local function repairs(src)
    local out = {}
    for _, it in ipairs(Inv.Chains(src)) do
        local key, letter = Chains.fromMeta(it.meta)
        if key and it.meta.broken then
            out[#out + 1] = { slot = it.slot, key = key, variant = letter, label = Chains.label(key, letter), image = Chains.model(key, letter), price = repairPrice(key) }
        end
    end
    return out
end

lib.callback.register('nzc:store:open', function(src)
    if not cfg.Enabled or not nearStore(src) then return nil end
    return { items = catalog(src), repairs = repairs(src), wallet = wallet(src), craft = cfg.Craft and cfg.Craft.Enabled or false }
end)

local function done(src, ok, msg)
    TriggerClientEvent('nzc:store:result', src, ok, msg, { items = catalog(src), repairs = repairs(src), wallet = wallet(src) })
end

local function newChain(src, key, letter, how)
    local meta = Worn.newMeta(key, letter, src)
    if not Inv.CanCarry(src, meta) then return false end
    if not Inv.Add(src, meta) then return false end
    Logs.send('info', 'Jewelry store', ('%s %s %s'):format(Logs.who(src), how, Chains.label(key, letter)))
    return true
end

RegisterNetEvent('nzc:store:buy', function(key, letter)
    local src = source
    if busy[src] or not cfg.Enabled or not nearStore(src) or not Chains.exists(key) then return end
    if not Registry.canBuy(src, key) then return done(src, false, T.not_yours) end
    local price = Chains.price(key)
    if not price then return end
    local v = Chains.variant(key, letter)
    busy[src] = true
    if not Inv.CanCarry(src, Chains.meta(key, v.letter)) then busy[src] = nil return done(src, false, T.no_room) end
    if not Bridge.RemoveMoney(src, price, cfg.Currency, 'jewelry-store') then busy[src] = nil return done(src, false, T.no_money) end
    if not newChain(src, key, v.letter, ('bought (%s)'):format(Chains.money(price))) then
        -- pockets filled up in between: give the money back
        Bridge.AddMoney(src, price, cfg.Currency, 'jewelry-store refund')
        busy[src] = nil
        return done(src, false, T.no_room)
    end
    busy[src] = nil
    done(src, true, T.bought:format(Chains.label(key, v.letter)))
end)

RegisterNetEvent('nzc:store:craft', function(key, letter)
    local src = source
    if busy[src] or not cfg.Enabled or not nearStore(src) or not Chains.exists(key) then return end
    if not Registry.canBuy(src, key) then return done(src, false, T.not_yours) end
    local mats = recipe(key)
    if not mats or not Chains.price(key) then return end
    local v = Chains.variant(key, letter)
    for _, m in ipairs(mats) do
        if Inv.Count(src, m.item) < m.count then return done(src, false, T.no_materials) end
    end
    if not Inv.CanCarry(src, Chains.meta(key, v.letter)) then return done(src, false, T.no_room) end
    busy[src] = true
    TriggerClientEvent('nzc:store:working', src, cfg.Craft.Time or 4000, 'craft')
    SetTimeout(cfg.Craft.Time or 4000, function()
        if not GetPlayerName(src) then busy[src] = nil return end
        for _, m in ipairs(mats) do
            if Inv.Count(src, m.item) < m.count then busy[src] = nil return done(src, false, T.no_materials) end
        end
        -- room first, then the materials, then the chain: nothing is taken unless the chain can be handed over
        if not Inv.CanCarry(src, Chains.meta(key, v.letter)) then busy[src] = nil return done(src, false, T.no_room) end
        local taken = {}
        for _, m in ipairs(mats) do
            if not Inv.RemoveItem(src, m.item, m.count) then
                for _, t in ipairs(taken) do Inv.AddItem(src, t.item, t.count) end
                busy[src] = nil
                return done(src, false, T.no_materials)
            end
            taken[#taken + 1] = m
        end
        local ok = newChain(src, key, v.letter, 'crafted')
        if not ok then for _, t in ipairs(taken) do Inv.AddItem(src, t.item, t.count) end end
        busy[src] = nil
        done(src, ok, ok and T.crafted:format(Chains.label(key, v.letter)) or T.no_room)
    end)
end)

RegisterNetEvent('nzc:store:repair', function(slot)
    local src = source
    if not cfg.Enabled then return end
    if busy[src] then return done(src, false, T.busy) end
    if not nearStore(src) then return done(src, false, T.too_far) end
    local meta = Inv.Peek(src, slot)
    local key = meta and Chains.fromMeta(meta)
    if not key or not meta.broken then return done(src, false, T.no_chain) end
    local price = repairPrice(key)
    if Bridge.GetMoney(src, cfg.Currency) < price then return done(src, false, T.no_money) end
    busy[src] = true
    TriggerClientEvent('nzc:store:working', src, cfg.Repair.Time or 3000, 'repair')
    SetTimeout(cfg.Repair.Time or 3000, function()
        local m = GetPlayerName(src) and Inv.Peek(src, slot)
        if not m or not m.broken or m.chain ~= meta.chain or m.serial ~= meta.serial then
            busy[src] = nil
            return GetPlayerName(src) and done(src, false, T.no_chain)
        end
        if not Bridge.RemoveMoney(src, price, cfg.Currency, 'jewelry-repair') then busy[src] = nil return done(src, false, T.no_money) end
        m.broken = nil
        local fixed = Chains.meta(m.chain, m.variant, m)
        local ok, lost = Inv.SetMeta(src, slot, fixed)
        if lost then
            -- it came out of the pockets but wouldn't go back in: on the counter floor, not gone
            local c = GetEntityCoords(GetPlayerPed(src))
            Drops.add({ meta = fixed, coords = { x = c.x, y = c.y, z = c.z - 0.9 }, rot = { x = 0.0, y = 0.0, z = 0.0 }, thrown = true })
            ok = true
        end
        busy[src] = nil
        done(src, ok, ok and T.repaired:format(fixed.label) or 'Could not repair it.')
    end)
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

-- admins: where am I standing (for Config.Store.Locations)
lib.addCommand('chainstorehere', { help = 'Print your spot for a jewelry store location', restricted = 'group.admin' }, function(src)
    local ped = GetPlayerPed(src)
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local line = ('coords = vector3(%.2f, %.2f, %.2f), heading = %.1f,'):format(c.x, c.y, c.z, h)
    print(line)
    TriggerClientEvent('chat:addMessage', src, { args = { 'Jewelry store', line } })
end)
