-----------------------------------------------------------------
-- Handing a bag to someone (server)
--
-- Offer -> they accept -> the giver's `nb_hand` statebag tells every
-- client to draw the bag in the giver's hand, then the taker's -> the
-- item moves with its metadata, so the stash (contents) goes with it.
-- Everything is checked again at the moment the bag changes hands.
-----------------------------------------------------------------

local cfg = Config.Handoff
if not cfg or not cfg.enabled then return end

local ox = exports.ox_inventory

local offers = {} -- [taker] = { from, slot, name, bagid, expires }
local busy = {}   -- [src] = true while giving or taking

--- Giving or taking a bag right now? (nobody opens it mid hand-off)
function HandoffBusy(src) return busy[src] == true end

local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end
local function tell(src, key, kind, ...) TriggerClientEvent('nayzeee-backpack:notify', src, S(key, ...), kind or 'error') end

local function online(src) return src and GetPlayerPing(src) > 0 end

local function close(a, b, extra)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= cfg.distance + (extra or 0.5)
end

local function isOutfitBag(name)
    return Config.OutfitBag and Config.OutfitBag.enabled and name == Config.OutfitBag.item
end

--- The item being handed over: a given slot, or the bag you carry.
local function itemFor(src, slot)
    local item
    if slot then
        item = ox:GetSlot(src, tonumber(slot) or -1)
    else
        item = FindBagItem(src)
    end
    if not item or not item.name then return nil end
    if not Config.Backpacks[item.name] and not isOutfitBag(item.name) then return nil end
    return item
end

local function label(name)
    if Config.Backpacks[name] then return Bags.label(name) end
    return Strings.ob_title
end

--- Can `src` hand `item` to `taker` right now? Returns the reason if not.
local function blocked(src, taker, item)
    local status = Player(src).state.nb_status or {}
    if status.dead or status.cuffed then return 'ho_busy' end
    if Player(src).state.nb_open then return 'ho_close_first' end
    local tstatus = Player(taker).state.nb_status or {}
    if tstatus.dead or tstatus.cuffed then return 'ho_busy' end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 or GetVehiclePedIsIn(GetPlayerPed(taker), false) ~= 0 then
        return 'ho_busy'
    end

    if Config.Backpacks[item.name] then
        if Bags.isJobBag(item.name) and not cfg.jobBags then return 'ho_job' end
        if Config.OneBagOnly and FindBagItem(taker) then return 'ho_has_bag' end
        if not ServerCanUseBag(taker, item.name) then return 'ho_cant_use' end
    end
    if not ox:CanCarryItem(taker, item.name, 1, item.metadata) then return 'ho_cant_carry' end
end

RegisterNetEvent('nayzeee-backpack:handoff:offer', function(taker, slot)
    local src = source
    taker = tonumber(taker)
    if not taker or taker == src or not online(taker) then return tell(src, 'ho_nobody') end
    if busy[src] or busy[taker] or offers[taker] then return tell(src, 'ho_busy') end
    for _, o in pairs(offers) do if o.from == src then return tell(src, 'ho_busy') end end
    if not close(src, taker) then return tell(src, 'ho_nobody') end

    local item = itemFor(src, slot)
    if not item then return tell(src, 'no_bag') end

    local why = blocked(src, taker, item)
    if why then return tell(src, why) end

    local offer = {
        from = src, slot = item.slot, name = item.name,
        bagid = item.metadata and item.metadata.bagid,
        expires = os.time() + cfg.timeout,
    }
    offers[taker] = offer
    TriggerClientEvent('nayzeee-backpack:handoff:ask', taker, label(item.name), cfg.timeout)
    tell(src, 'ho_offered', 'inform', label(item.name))

    SetTimeout(cfg.timeout * 1000 + 1000, function()
        if offers[taker] == offer then
            offers[taker] = nil
            if online(src) then tell(src, 'ho_expired', 'inform') end
        end
    end)
end)

--- Move the item with its metadata. Hands it back if the taker can't hold it.
local function transfer(src, taker, item)
    -- a copy: the original is what RemoveItem matches against
    local meta = lib.table.deepclone(item.metadata or {})
    if Config.Backpacks[item.name] then meta.stowed = nil end

    if not ox:RemoveItem(src, item.name, 1, item.metadata, item.slot) then return false end
    if ox:AddItem(taker, item.name, 1, meta) then return true end

    if not ox:AddItem(src, item.name, 1, meta) then
        ox:CustomDrop(label(item.name), { { item.name, 1, meta } }, GetEntityCoords(GetPlayerPed(src)))
    end
    return false
end

local function finish(src, taker)
    busy[src], busy[taker] = nil, nil
    -- after the taker's worn bag is on, so nobody sees an empty frame
    SetTimeout(200, function()
        if online(src) then Player(src).state:set('nb_hand', nil, true) end
    end)
end

RegisterNetEvent('nayzeee-backpack:handoff:answer', function(accept)
    local taker = source
    local offer = offers[taker]
    offers[taker] = nil
    if not offer or os.time() > offer.expires then return end

    local src = offer.from
    if not online(src) then return end
    if not accept then return tell(src, 'ho_declined', 'inform') end
    if busy[src] or busy[taker] then return tell(src, 'ho_busy') end
    if not close(src, taker, 1.0) then return tell(src, 'ho_moved') end

    -- still the same item in the same slot?
    local item = itemFor(src, offer.slot)
    if not item or item.name ~= offer.name or (item.metadata and item.metadata.bagid) ~= offer.bagid then
        return tell(src, 'no_bag')
    end
    local why = blocked(src, taker, item)
    if why then
        tell(src, why)
        return tell(taker, why)
    end

    local model, texture, worn
    if Config.Backpacks[item.name] then
        model, texture = Bags.resolve(item.name, item.metadata and item.metadata.variant)
        local wearing = FindBagItem(src)
        worn = wearing and wearing.slot == item.slot and not (item.metadata and item.metadata.stowed) or false
    else
        model, texture, worn = Config.OutfitBag.prop, 0, false
    end

    busy[src], busy[taker] = true, true
    -- whatever the giver had open (their bag's stash) closes now
    TriggerClientEvent('ox_inventory:closeInventory', src)
    Player(src).state:set('nb_hand', { to = taker, model = model, texture = texture or 0, worn = worn }, true)

    if Sounds then
        if worn then Sounds.play('strap', src, 200) end
        Sounds.play('rustle', src, (worn and cfg.takeOff or 0) + cfg.swap)
    end

    local total = (worn and cfg.takeOff or 0) + cfg.finish
    SetTimeout(total, function()
        if not online(src) or not online(taker) then return finish(src, taker) end
        if not close(src, taker, 1.5) then
            tell(src, 'ho_moved'); tell(taker, 'ho_moved')
            return finish(src, taker)
        end

        local now = itemFor(src, offer.slot)
        if not now or now.name ~= offer.name or (now.metadata and now.metadata.bagid) ~= offer.bagid then
            tell(src, 'no_bag')
            return finish(src, taker)
        end
        -- anything could have changed in 3 seconds (a second bag, a death, cuffs)
        local late = blocked(src, taker, now)
        if late then
            tell(src, late); tell(taker, late)
            return finish(src, taker)
        end
        TriggerClientEvent('ox_inventory:closeInventory', src)
        if not transfer(src, taker, now) then
            tell(src, 'ho_cant_carry'); tell(taker, 'ho_cant_carry')
            return finish(src, taker)
        end

        if Config.Backpacks[now.name] then
            RefreshBagState(src)
            RefreshBagState(taker)
        end
        tell(src, 'ho_given', 'success', label(now.name))
        tell(taker, 'ho_received', 'success', label(now.name))
        if Logs then Logs.handoff(src, taker, now.name, now.metadata) end
        TriggerEvent('nayzeee-backpack:server:handedOver', src, taker, now.name)
        finish(src, taker)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    offers[src] = nil
    busy[src] = nil
    for taker, o in pairs(offers) do
        if o.from == src then offers[taker] = nil end
    end
end)

-- a restart mid hand-off must not leave a bag stuck in someone's hand
CreateThread(function()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if Player(src).state.nb_hand then Player(src).state:set('nb_hand', nil, true) end
    end
end)
