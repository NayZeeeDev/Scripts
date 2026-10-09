-----------------------------------------------------------------
-- Giving chains
--
--   give   hand it over (from your neck or your pockets) into their pockets
--   puton  put it straight on their neck (theirs goes in their pockets)
--   swap   you both wear one: swap them (couples)
--
-- The other player always has to accept ([Y] / [X]). Nothing moves
-- until they do, and everything is checked again when they answer.
-----------------------------------------------------------------

local cfg = Config.Give
local T = Config.Text
local offers = {}     -- [target] = { id, from, kind, slot, expires }
local nextId = 1

local function near(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or not pb or pa == 0 or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= (cfg.Distance or 2.5) + 1.5
end

--- What the giver is offering: meta, label, image (nil if they don't have it any more)
local function offered(src, slot)
    local meta
    if slot then meta = Inv.Peek(src, slot) else local w = Worn.get(src); meta = w and w.meta end
    local key, letter = Chains.fromMeta(meta)
    if not key then return nil end
    return meta, Chains.label(key, letter), Chains.model(key, letter)
end

local function clear(target, reason)
    local o = offers[target]
    if not o then return end
    offers[target] = nil
    TriggerClientEvent('nzc:c:offerEnd', target, o.id)
    if reason and GetPlayerName(o.from) then Worn.notify(o.from, reason, 'error') end
end

RegisterNetEvent('nzc:s:offer', function(kind, target, slot)
    local src = source
    target, slot = tonumber(target), tonumber(slot)
    if not cfg.Enabled or not target or target == src or not GetPlayerName(target) then return end
    if kind ~= 'give' and kind ~= 'puton' and kind ~= 'swap' then return end
    if Worn.busy(src) or (SnatchBusy and SnatchBusy(target)) then return Worn.notify(src, T.busy, 'error') end
    if offers[target] then return Worn.notify(src, T.busy, 'error') end
    if not near(src, target) then return Worn.notify(src, T.too_far, 'error') end
    if kind ~= 'give' then slot = slot and kind == 'puton' and slot or nil end

    local meta, label, image = offered(src, slot)
    if not meta then return Worn.notify(src, T.no_chain, 'error') end
    if kind ~= 'give' and meta.broken then return Worn.notify(src, T.broken, 'error') end
    if kind == 'swap' and not Worn.get(target) then return Worn.notify(src, T.nothing_to_take, 'error') end

    local id = nextId
    nextId = id + 1
    offers[target] = { id = id, from = src, kind = kind, slot = slot, expires = os.time() + (cfg.Timeout or 15), serial = meta.serial }
    local fromName = Bridge.GetCharName(src)
    local text = kind == 'swap' and T.offer_swap:format(fromName) or (kind == 'puton' and T.offer_puton or T.offer_give):format(fromName, label)
    local theirs = Worn.get(target)
    TriggerClientEvent('nzc:c:offer', target, {
        id = id, kind = kind, text = text, label = label, image = image, timeout = cfg.Timeout or 15, from = src,
        theirs = kind == 'swap' and theirs and theirs.meta.label or nil,
    })
    Worn.notify(src, T.offer_sent, 'info')
end)

local function anims(a, b)
    TriggerClientEvent('nzc:c:giveAnim', a, b, 'give')
    TriggerClientEvent('nzc:c:giveAnim', b, a, 'take')
end

RegisterNetEvent('nzc:s:offerAnswer', function(id, accept)
    local target = source
    local o = offers[target]
    if not o or o.id ~= tonumber(id) then return end
    offers[target] = nil
    local src = o.from
    if not GetPlayerName(src) then return end
    if not accept then return Worn.notify(src, T.offer_declined, 'error') end
    if os.time() > o.expires then return Worn.notify(src, T.offer_expired, 'error') end
    if not near(src, target) then return Worn.notify(target, T.too_far, 'error') end
    if Worn.busy(src) or Worn.busy(target) then return end

    -- it has to be the very chain that was offered
    local meta = offered(src, o.slot)
    if not meta or meta.serial ~= o.serial then return Worn.notify(target, T.no_chain, 'error') end

    if o.kind == 'give' then
        if not Inv.CanCarry(target, meta) then
            Worn.notify(src, T.no_room, 'error')
            return Worn.notify(target, T.no_room, 'error')
        end
        local taken = o.slot and Inv.TakeSlot(src, o.slot) or Worn.strip(src)
        if not taken then return end
        if not Inv.Add(target, taken) then
            -- couldn't hand it over after all: back where it came from
            if o.slot then Inv.Add(src, taken) else Worn.set(src, taken) end
            return Worn.notify(src, T.no_room, 'error')
        end
        anims(src, target)
        Worn.notify(src, T.gave:format(taken.label or 'chain'), 'success')
        Worn.notify(target, T.got_given:format(taken.label or 'chain'), 'success')
        Logs.send('info', 'Chain given', ('%s gave %s to %s'):format(Logs.who(src), taken.label or '?', Logs.who(target)))

    elseif o.kind == 'puton' then
        local theirs = Worn.get(target)
        if theirs and not Inv.CanCarry(target, theirs.meta) then return Worn.notify(target, T.no_room, 'error') end
        local taken = o.slot and Inv.TakeSlot(src, o.slot) or Worn.strip(src)
        if not taken then return end
        if theirs then
            local old = Worn.strip(target)
            if not Inv.Add(target, old) then
                Worn.set(target, old)
                if o.slot then Inv.Add(src, taken) else Worn.set(src, taken) end
                return Worn.notify(target, T.no_room, 'error')
            end
        end
        Worn.set(target, taken)
        anims(src, target)
        Worn.notify(src, T.gave:format(taken.label or 'chain'), 'success')
        Worn.notify(target, T.wearing:format(taken.label or 'chain'), 'success')
        Logs.send('info', 'Chain put on', ('%s put %s on %s'):format(Logs.who(src), taken.label or '?', Logs.who(target)))

    elseif o.kind == 'swap' then
        if not Worn.get(src) or not Worn.get(target) then return end
        local a, b = Worn.strip(src), Worn.strip(target)
        Worn.set(src, b)
        Worn.set(target, a)
        anims(src, target)
        Worn.notify(src, T.swapped, 'success')
        Worn.notify(target, T.swapped, 'success')
        Logs.send('info', 'Chains swapped', ('%s and %s swapped chains (%s / %s)'):format(Logs.who(src), Logs.who(target), a.label or '?', b.label or '?'))
    end
end)

-- expiry
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for target, o in pairs(offers) do
            if now > o.expires or not GetPlayerName(o.from) then clear(target, T.offer_expired) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    clear(src)
    for target, o in pairs(offers) do
        if o.from == src then clear(target) end
    end
end)
