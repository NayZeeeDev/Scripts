--[[
    Placed shoe boxes.

    The base is a networked object. Its state bag drives every client:
      nzs:open   lid open?
      nzs:shoe   shoe id resting in the box (false = empty)
      nzs:busy   a sequence is running
      nzs:fx     { kind = 'in' | 'out', n = counter } - float the shoes in / out
    Clients spawn the lid and the shoes locally and animate them from these.
]]

Boxes = {}
local boxes = {}       -- [entity] = { owner, ownerId, contents, busy }
local fxCounter = 0
local B, F = Config.Box, Config.Float

local function sameModel(a, b) return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF) end

local function nearPlayer(src, coords, dist)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= dist
end

local function boxFromNet(src, netId)
    if type(netId) ~= 'number' then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not DoesEntityExist(ent) or not sameModel(GetEntityModel(ent), B.base) then return nil end
    if not boxes[ent] then return nil end
    if not nearPlayer(src, GetEntityCoords(ent), B.interactDistance + 2.0) then return nil end
    return ent, boxes[ent]
end

local function countOwned(src)
    local n = 0
    for _, b in pairs(boxes) do if b.owner == src then n = n + 1 end end
    return n
end

local function setBusy(ent, busy)
    boxes[ent].busy = busy
    Entity(ent).state:set('nzs:busy', busy, true)
end

local function playFx(ent, kind)
    fxCounter = fxCounter + 1
    Entity(ent).state:set('nzs:fx', { kind = kind, n = fxCounter }, true)
end

local function openFirst(ent)
    local st = Entity(ent).state
    if st['nzs:open'] then return 0 end
    st:set('nzs:open', true, true)
    Wait(B.openTime + 120)
    return B.openTime + 120
end

-- expected client-side duration of each sequence (for the close-up camera)
local function inDuration(open) return (open and 0 or B.openTime + 120) + F.inTime + 150 + 250 + B.closeTime end
local function outDuration(open) return (open and 0 or B.openTime + 120) + F.outTime + 200 end

local function spawnBox(src, coords, heading, contents)
    local ent = CreateObjectNoOffset(B.base, coords.x, coords.y, coords.z, true, true, false)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(ent) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    SetEntityHeading(ent, heading + 0.0)
    FreezeEntityPosition(ent, true)
    local st = Entity(ent).state
    st:set('nzs:open', false, true)
    st:set('nzs:busy', false, true)
    st:set('nzs:shoe', contents and contents.shoe or false, true)
    boxes[ent] = { owner = src, ownerId = src > 0 and Bridge.GetIdentifier(src) or nil, contents = contents, busy = false }
    return ent
end

local function deleteBox(ent)
    boxes[ent] = nil
    if DoesEntityExist(ent) then DeleteEntity(ent) end
end

--- Shoes float down, lid closes. Runs in its own thread.
local function sequenceIn(ent, meta)
    setBusy(ent, true)
    openFirst(ent)
    local st = Entity(ent).state
    -- fx first: clients then spawn the shoes hidden at the top instead of resting in the box
    playFx(ent, 'in')
    st:set('nzs:shoe', meta.shoe, true)
    Wait(F.inTime + 150)
    if not boxes[ent] then return end
    boxes[ent].contents = meta
    Wait(250)
    st:set('nzs:open', false, true)
    Wait(B.closeTime)
    if boxes[ent] then setBusy(ent, false) end
end

--- Shoes float up and into the player's hands
local function sequenceOut(src, ent)
    setBusy(ent, true)
    openFirst(ent)
    playFx(ent, 'out')
    Wait(F.outTime)
    local box = boxes[ent]
    if not box then return end
    local meta = box.contents
    box.contents = nil
    Entity(ent).state:set('nzs:shoe', false, true)
    if not Items.GivePair(src, meta, false) then
        -- inventory filled up mid-way: put them back
        box.contents = meta
        Entity(ent).state:set('nzs:shoe', meta.shoe, true)
        Bridge.Notify(src, Config.Text.noSpace, 'error')
    end
    setBusy(ent, false)
end

--------------------------------------------------------------------------------
-- Callbacks
--------------------------------------------------------------------------------

local function validPlacement(src, coords, heading)
    return type(coords) == 'vector3' and type(heading) == 'number' and nearPlayer(src, coords, 3.0)
end

lib.callback.register('nz_sneakers:placeBox', function(src, slot, kind, coords, heading)
    if not validPlacement(src, coords, heading) then return false end
    if countOwned(src) >= B.maxPerPlayer then
        Bridge.Notify(src, Config.Text.boxLimit, 'error')
        return false
    end
    local wanted = kind == 'boxed' and Config.Items.boxed or Config.Items.emptyBox
    local it = Inv.GetSlot(src, slot)
    if not it or it.name ~= wanted then return false end

    local contents = nil
    if kind == 'boxed' then
        if not Config.Shoes[it.metadata.shoe] then return false end
        contents = Items.Clean(it.metadata)
    end
    if not Inv.Remove(src, wanted, 1, slot) then return false end
    local ent = spawnBox(src, coords, heading, contents)
    if not ent then
        if contents then Items.GivePair(src, contents, true) else Inv.Add(src, Config.Items.emptyBox, 1) end
        return false
    end
    return NetworkGetNetworkIdFromEntity(ent)
end)

-- Loose pair -> empty box from the inventory -> placed box with the shoes floating in
lib.callback.register('nz_sneakers:packShoes', function(src, shoeSlot, coords, heading)
    if not validPlacement(src, coords, heading) then return false end
    if countOwned(src) >= B.maxPerPlayer then
        Bridge.Notify(src, Config.Text.boxLimit, 'error')
        return false
    end
    local shoes = Inv.GetSlot(src, shoeSlot)
    local box = Inv.Find(src, Config.Items.emptyBox)
    if not shoes or shoes.name ~= Config.Items.shoes or not Config.Shoes[shoes.metadata.shoe] then return false end
    if not box then
        Bridge.Notify(src, Config.Text.noEmptyBox, 'error')
        return false
    end
    local meta = Items.Clean(shoes.metadata)
    if not Inv.Remove(src, Config.Items.shoes, 1, shoeSlot) then return false end
    if not Inv.Remove(src, Config.Items.emptyBox, 1, box.slot) then
        Items.GivePair(src, meta, false)
        return false
    end
    local ent = spawnBox(src, coords, heading, nil)
    if not ent then
        Items.GivePair(src, meta, false)
        Inv.Add(src, Config.Items.emptyBox, 1)
        return false
    end
    CreateThread(function() sequenceIn(ent, meta) end)
    return NetworkGetNetworkIdFromEntity(ent), inDuration(false)
end)

lib.callback.register('nz_sneakers:toggleLid', function(src, netId)
    local ent, box = boxFromNet(src, netId)
    if not ent or box.busy then return false end
    local st = Entity(ent).state
    st:set('nzs:open', not st['nzs:open'], true)
    return true
end)

lib.callback.register('nz_sneakers:putIn', function(src, netId, shoeSlot)
    local ent, box = boxFromNet(src, netId)
    if not ent then return false end
    if box.busy then Bridge.Notify(src, Config.Text.boxBusy, 'error') return false end
    if box.contents then return false end
    local shoes = Inv.GetSlot(src, shoeSlot)
    if not shoes or shoes.name ~= Config.Items.shoes or not Config.Shoes[shoes.metadata.shoe] then return false end
    local meta = Items.Clean(shoes.metadata)
    if not Inv.Remove(src, Config.Items.shoes, 1, shoeSlot) then return false end
    local wasOpen = Entity(ent).state['nzs:open']
    CreateThread(function() sequenceIn(ent, meta) end)
    return true, inDuration(wasOpen)
end)

lib.callback.register('nz_sneakers:takeOut', function(src, netId)
    local ent, box = boxFromNet(src, netId)
    if not ent then return false end
    if box.busy then Bridge.Notify(src, Config.Text.boxBusy, 'error') return false end
    if not box.contents then return false end
    if not Inv.CanCarry(src, Config.Items.shoes, 1, box.contents) then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    local wasOpen = Entity(ent).state['nzs:open']
    CreateThread(function() sequenceOut(src, ent) end)
    return true, outDuration(wasOpen)
end)

lib.callback.register('nz_sneakers:pickUp', function(src, netId)
    local ent, box = boxFromNet(src, netId)
    if not ent or box.busy then return false end
    if not B.anyoneCanPickUp and box.owner ~= src and not Bridge.IsAdmin(src) then
        Bridge.Notify(src, Config.Text.notYours, 'error')
        return false
    end
    local ok
    if box.contents then
        ok = Items.GivePair(src, box.contents, true)
    else
        ok = Inv.Add(src, Config.Items.emptyBox, 1)
    end
    if not ok then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    deleteBox(ent)
    return true
end)

lib.callback.register('nz_sneakers:myShoes', function(src)
    local out = {}
    for _, it in ipairs(Inv.List(src, Config.Items.shoes)) do
        if Config.Shoes[it.metadata.shoe] then
            out[#out + 1] = { slot = it.slot, meta = Items.Clean(it.metadata) }
        end
    end
    return out
end)

--------------------------------------------------------------------------------
-- Cleanup: anything left in a box goes back to its owner (now, or next login)
--------------------------------------------------------------------------------

local function returnBox(ent, box, online)
    if online and GetPlayerPing(box.owner) > 0 then
        local ok
        if box.contents then ok = Items.GivePair(box.owner, box.contents, true)
        else ok = Inv.Add(box.owner, Config.Items.emptyBox, 1) end
        if ok then return deleteBox(ent) end
    end
    Pending.Add(box.ownerId, box.contents, box.contents ~= nil)
    deleteBox(ent)
end

AddEventHandler('playerDropped', function()
    if not B.cleanupOnDrop then return end
    local src = source
    for ent, box in pairs(boxes) do
        if box.owner == src then returnBox(ent, box, false) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ent, box in pairs(boxes) do returnBox(ent, box, true) end
end)

--------------------------------------------------------------------------------
-- Exports for other resources (shops, crafting, selling)
--------------------------------------------------------------------------------

--- Place a box with `meta` inside (or empty). Returns the net id.
function Boxes.Spawn(coords, heading, meta, ownerSrc)
    local ent = spawnBox(ownerSrc or 0, coords, heading or 0.0, meta and Items.Clean(meta))
    return ent and NetworkGetNetworkIdFromEntity(ent)
end

--- Run the "shoes float in, lid closes" sequence on a placed, empty box
function Boxes.PackInto(netId, meta)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not boxes[ent] or boxes[ent].contents or boxes[ent].busy then return false end
    CreateThread(function() sequenceIn(ent, Items.Clean(meta)) end)
    return true
end

exports('SpawnBox', Boxes.Spawn)
exports('PackInto', Boxes.PackInto)
