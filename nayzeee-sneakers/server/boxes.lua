--[[
    Placed shoe boxes.

    The base is a networked object. Its state bag drives every client:
      nzs:type   box size ('shoe' | 'heel' | 'boot')
      nzs:open   lid open?
      nzs:shoe   shoe id resting in the box (false = empty)
      nzs:busy   a sequence is running
      nzs:fx     { kind = 'in' | 'out', n = counter } - float the shoes in / out
    Clients spawn the lid and the shoes locally and animate them from these.
]]

Boxes = {}
GlobalState.nzsBoxes = 0   -- nothing survives a restart
local boxes = {}       -- [entity] = { owner, ownerId, contents, busy, type }
local fxCounter = 0
local B, F = Config.Box, Config.Float

local function nearPlayer(src, coords, dist)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= dist
end

local function boxFromNet(src, netId)
    if type(netId) ~= 'number' then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not DoesEntityExist(ent) or not Shared.BoxTypeOfModel(GetEntityModel(ent)) then return nil end
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

local function emptyItem(boxType) return Config.BoxTypes[boxType or 'shoe'].item end
local function boxLabel(boxType) return Config.BoxTypes[boxType or 'shoe'].label:lower() end

local function spawnBox(src, coords, heading, contents, boxType, colour)
    boxType = Config.BoxTypes[boxType] and boxType or 'shoe'
    colour = Shared.BoxColour(colour)
    local ent = CreateObjectNoOffset((Shared.BoxModels(boxType, colour)), coords.x, coords.y, coords.z, true, true, false)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(ent) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    SetEntityHeading(ent, heading + 0.0)
    FreezeEntityPosition(ent, true)
    local st = Entity(ent).state
    st:set('nzs:type', boxType, true)
    st:set('nzs:open', false, true)
    st:set('nzs:busy', false, true)
    st:set('nzs:shoe', contents and contents.shoe or false, true)
    st:set('nzs:colour', colour, true)
    if contents then contents.boxColour = nil end
    boxes[ent] = { owner = src, ownerId = src > 0 and Bridge.GetIdentifier(src) or nil, contents = contents, busy = false, type = boxType, colour = colour }
    GlobalState.nzsBoxes = (GlobalState.nzsBoxes or 0) + 1
    return ent
end

--- How many boxes are out (clients skip their world scan when there are none)
local function countAll()
    local n = 0
    for _ in pairs(boxes) do n = n + 1 end
    GlobalState.nzsBoxes = n
end

local function deleteBox(ent)
    boxes[ent] = nil
    if DoesEntityExist(ent) then DeleteEntity(ent) end
    countAll()
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

lib.callback.register('nayzeee-sneakers:placeBox', function(src, slot, kind, coords, heading, colour)
    if not validPlacement(src, coords, heading) then return false end
    if countOwned(src) >= B.maxPerPlayer then
        Bridge.Notify(src, Config.Text.boxLimit, 'error')
        return false
    end
    local it = Inv.GetSlot(src, slot)
    if not it then return false end

    local contents, boxType = nil, nil
    if kind == 'boxed' then
        if it.name ~= Config.Items.boxed or not Config.Shoes[it.metadata.shoe] then return false end
        contents = Items.Clean(it.metadata)
        colour = contents.boxColour or colour
        boxType = Shared.BoxTypeForShoe(contents.shoe)
    else
        boxType = Shared.BoxTypeOfItem(it.name)
        if not boxType then return false end
    end
    if not Inv.Remove(src, it.name, 1, slot) then return false end
    local ent = spawnBox(src, coords, heading, contents, boxType, colour)
    if not ent then
        if contents then contents.boxColour = colour Items.GivePair(src, contents, true) else Inv.Add(src, emptyItem(boxType), 1) end
        return false
    end
    return NetworkGetNetworkIdFromEntity(ent)
end)

-- Loose pair -> empty box from the inventory -> placed box with the shoes floating in
lib.callback.register('nayzeee-sneakers:packShoes', function(src, shoeSlot, coords, heading, colour)
    if not validPlacement(src, coords, heading) then return false end
    if countOwned(src) >= B.maxPerPlayer then
        Bridge.Notify(src, Config.Text.boxLimit, 'error')
        return false
    end
    local shoes = Inv.GetSlot(src, shoeSlot)
    if not shoes or shoes.name ~= Config.Items.shoes or not Config.Shoes[shoes.metadata.shoe] then return false end
    local boxType = Shared.BoxTypeForShoe(shoes.metadata.shoe)
    local box = Inv.Find(src, emptyItem(boxType))
    if not box then
        Bridge.Notify(src, Config.Text.noEmptyBox:format(boxLabel(boxType)), 'error')
        return false
    end
    local meta = Items.Clean(shoes.metadata)
    if not Inv.Remove(src, Config.Items.shoes, 1, shoeSlot) then return false end
    if not Inv.Remove(src, emptyItem(boxType), 1, box.slot) then
        Items.GivePair(src, meta, false)
        return false
    end
    local ent = spawnBox(src, coords, heading, nil, boxType, colour)
    if not ent then
        Items.GivePair(src, meta, false)
        Inv.Add(src, emptyItem(boxType), 1)
        return false
    end
    CreateThread(function() sequenceIn(ent, meta) end)
    return NetworkGetNetworkIdFromEntity(ent), inDuration(false)
end)

lib.callback.register('nayzeee-sneakers:toggleLid', function(src, netId)
    local ent, box = boxFromNet(src, netId)
    if not ent or box.busy then return false end
    local st = Entity(ent).state
    st:set('nzs:open', not st['nzs:open'], true)
    return true
end)

lib.callback.register('nayzeee-sneakers:putIn', function(src, netId, shoeSlot)
    local ent, box = boxFromNet(src, netId)
    if not ent then return false end
    if box.busy then Bridge.Notify(src, Config.Text.boxBusy, 'error') return false end
    if box.contents then return false end
    local shoes = Inv.GetSlot(src, shoeSlot)
    if not shoes or shoes.name ~= Config.Items.shoes or not Config.Shoes[shoes.metadata.shoe] then return false end
    local need = Shared.BoxTypeForShoe(shoes.metadata.shoe)
    if need ~= box.type then
        Bridge.Notify(src, Config.Text.wrongBox:format(boxLabel(need)), 'error')
        return false
    end
    local meta = Items.Clean(shoes.metadata)
    if not Inv.Remove(src, Config.Items.shoes, 1, shoeSlot) then return false end
    local wasOpen = Entity(ent).state['nzs:open']
    CreateThread(function() sequenceIn(ent, meta) end)
    return true, inDuration(wasOpen)
end)

lib.callback.register('nayzeee-sneakers:takeOut', function(src, netId)
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

lib.callback.register('nayzeee-sneakers:pickUp', function(src, netId)
    local ent, box = boxFromNet(src, netId)
    if not ent or box.busy then return false end
    if not B.anyoneCanPickUp and box.owner ~= src and not Bridge.IsAdmin(src) then
        Bridge.Notify(src, Config.Text.notYours, 'error')
        return false
    end
    local ok
    if box.contents then
        box.contents.boxColour = box.colour   -- a boxed pair keeps its box colour
        ok = Items.GivePair(src, box.contents, true)
    else
        ok = Inv.Add(src, emptyItem(box.type), 1)
    end
    if not ok then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    deleteBox(ent)
    return true
end)

lib.callback.register('nayzeee-sneakers:myShoes', function(src)
    local out = {}
    for _, it in ipairs(Inv.List(src, Config.Items.shoes)) do
        if Config.Shoes[it.metadata.shoe] then
            out[#out + 1] = { slot = it.slot, meta = Items.Clean(it.metadata), box = Shared.BoxTypeForShoe(it.metadata.shoe) }
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
        if box.contents then box.contents.boxColour = box.colour end
        if box.contents then ok = Items.GivePair(box.owner, box.contents, true)
        else ok = Inv.Add(box.owner, emptyItem(box.type), 1) end
        if ok then return deleteBox(ent) end
    end
    Pending.Add(box.ownerId, box.contents, box.contents ~= nil, box.type)
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
--- boxType defaults to the size the shoes need, or 'shoe'.
function Boxes.Spawn(coords, heading, meta, ownerSrc, boxType)
    boxType = boxType or (meta and Shared.BoxTypeForShoe(meta.shoe)) or 'shoe'
    local ent = spawnBox(ownerSrc or 0, coords, heading or 0.0, meta and Items.Clean(meta), boxType)
    return ent and NetworkGetNetworkIdFromEntity(ent)
end

--- Run the "shoes float in, lid closes" sequence on a placed, empty box
function Boxes.PackInto(netId, meta)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not boxes[ent] or boxes[ent].contents or boxes[ent].busy then return false end
    if Shared.BoxTypeForShoe(meta.shoe) ~= boxes[ent].type then return false end
    CreateThread(function() sequenceIn(ent, Items.Clean(meta)) end)
    return true
end

exports('SpawnBox', Boxes.Spawn)
exports('PackInto', Boxes.PackInto)
