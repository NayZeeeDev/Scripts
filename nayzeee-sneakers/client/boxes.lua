--[[
    Placed shoe boxes on this client.

    The base is networked; the lid and the shoes inside are local objects every
    client spawns for itself and animates from the base's state bag, so the lid
    swing and the floating shoes look smooth for everyone.
]]

Boxes = {}
Busy = false

local B, F = Config.Box, Config.Float
local boxes = {}        -- [base] = { t (box type), lid, angle, from, to, start, dur, opening, shoeId, shoe, fx }
local animating = 0     -- lids or shoes mid-animation

--- Box type settings for a placed base entity
local function typeOf(base)
    return Config.BoxTypes[Shared.BoxTypeOfModel(GetEntityModel(base)) or 'shoe']
end

-- Easing ----------------------------------------------------------------------

local function easeOutBack(t)
    local c1 = 1.70158
    return 1.0 + (c1 + 1.0) * (t - 1.0) ^ 3 + c1 * (t - 1.0) ^ 2
end

local function easeOutBounce(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1.0 / d1 then return n1 * t * t end
    if t < 2.0 / d1 then t = t - 1.5 / d1 return n1 * t * t + 0.75 end
    if t < 2.5 / d1 then t = t - 2.25 / d1 return n1 * t * t + 0.9375 end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end

local function easeInOutCubic(t)
    return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2
end

-- Lid -------------------------------------------------------------------------

local function attachLid(base, lid, angle)
    local h = boxes[base] and boxes[base].t.hinge or typeOf(base).hinge
    AttachEntityToEntity(lid, base, 0, h.x, h.y, h.z, angle, 0.0, 0.0, false, false, false, false, 2, true)
end

local function startLid(base, open)
    local box = boxes[base]
    if not box then return end
    local target = open and B.openAngle or 0.0
    if box.to == target then return end
    if not box.start then animating = animating + 1 end
    box.from, box.to, box.opening = box.angle, target, open
    box.start = GetGameTimer()
    box.dur = open and B.openTime or B.closeTime
end

-- Shoes inside ----------------------------------------------------------------

local REST = vector3(0.0, 0.0, B.floor)
local function topOf(box) return vector3(0.0, 0.0, box.t.hinge.z + F.height) end

local function attachShoe(base, obj, pos, pitch, roll, yaw)
    AttachEntityToEntity(obj, base, 0, pos.x, pos.y, pos.z, pitch, roll, yaw, false, false, false, false, 2, true)
end

local function removeShoe(box)
    if box.shoe and DoesEntityExist(box.shoe) then DeleteEntity(box.shoe) end
    box.shoe, box.shoeId = nil, nil
end

local function spawnShoe(base, shoeId)
    local box = boxes[base]
    local shoe = Config.Shoes[shoeId]
    local model = ShoeProp(shoe)
    if not box or not shoe or not LoadModel(model) then return end
    if not boxes[base] or box.shoeId ~= shoeId or box.shoe then return end
    local c = GetEntityCoords(base)
    local obj = CreateObject(model, c.x, c.y, c.z, false, false, false)
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    if box.fx then
        -- mid-float: start hidden at the top, the float step takes over next frame
        SetEntityAlpha(obj, 0, false)
        attachShoe(base, obj, topOf(box), 0.0, 0.0, 0.0)
    else
        attachShoe(base, obj, REST, 0.0, 0.0, 0.0)
    end
    SetModelAsNoLongerNeeded(model)
    box.shoe = obj
end

local function syncShoe(base)
    local box = boxes[base]
    if not box then return end
    local want = Entity(base).state['nzs:shoe'] or nil
    if want == box.shoeId then return end
    -- an 'out' float keeps its prop until it finishes
    if box.fx and box.fx.kind == 'out' then return end
    -- just floated out: don't flash it back while the server catches up
    if want and box.lastOut == want and GetGameTimer() < (box.lastOutUntil or 0) then return end
    removeShoe(box)
    if want then
        box.shoeId = want
        CreateThread(function() spawnShoe(base, want) end)
    end
end

local function startFx(base, kind)
    local box = boxes[base]
    if not box then return end
    if not box.fx then animating = animating + 1 end
    box.fx = { kind = kind, start = GetGameTimer(), dur = kind == 'in' and F.inTime or F.outTime }
end

local function stepShoe(base, box, now)
    local fx = box.fx
    local t = math.min((now - fx.start) / fx.dur, 1.0)
    if box.shoe and DoesEntityExist(box.shoe) then
        local e, alpha
        if fx.kind == 'in' then
            e = easeInOutCubic(t)
            alpha = math.min(1.0, t / 0.25)
        else
            e = 1.0 - easeInOutCubic(t)
            alpha = t < 0.6 and 1.0 or math.max(0.0, 1.0 - (t - 0.6) / 0.4)
        end
        local lift = 1.0 - e                     -- 1 at the top, 0 resting
        local pos = REST + (topOf(box) - REST) * lift + vector3(math.sin(lift * math.pi) * 0.03, 0.0, 0.0)
        local yaw = (fx.kind == 'in' and 35.0 or -35.0) * lift
        local roll = math.sin(lift * math.pi) * 6.0
        attachShoe(base, box.shoe, pos, 0.0, roll, yaw)
        if alpha >= 1.0 then ResetEntityAlpha(box.shoe) else SetEntityAlpha(box.shoe, math.floor(alpha * 255), false) end
    end
    if t >= 1.0 then
        local kind = fx.kind
        box.fx = nil
        animating = animating - 1
        if kind == 'out' then
            box.lastOut, box.lastOutUntil = box.shoeId, now + 1500
            removeShoe(box)
        end
        syncShoe(base)
    end
end

-- Animation loop --------------------------------------------------------------

CreateThread(function()
    while true do
        if animating > 0 then
            local now = GetGameTimer()
            for base, box in pairs(boxes) do
                if box.start then
                    local t = math.min((now - box.start) / box.dur, 1.0)
                    local e = box.opening and easeOutBack(t) or easeOutBounce(t)
                    box.angle = box.from + (box.to - box.from) * e
                    if t >= 1.0 then
                        box.angle, box.start = box.to, nil
                        animating = animating - 1
                    end
                    if DoesEntityExist(box.lid) then attachLid(base, box.lid, box.angle) end
                end
                if box.fx then stepShoe(base, box, now) end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddStateBagChangeHandler('nzs:open', nil, function(bag, _, value)
    local base = GetEntityFromStateBagName(bag)
    if base ~= 0 and boxes[base] then startLid(base, value == true) end
end)

AddStateBagChangeHandler('nzs:shoe', nil, function(bag)
    local base = GetEntityFromStateBagName(bag)
    if base ~= 0 and boxes[base] then
        -- state bag handlers run before the value is readable on the entity
        SetTimeout(0, function() syncShoe(base) end)
    end
end)

AddStateBagChangeHandler('nzs:fx', nil, function(bag, _, value)
    local base = GetEntityFromStateBagName(bag)
    if base ~= 0 and boxes[base] and type(value) == 'table' then
        if value.kind == 'in' then
            SetTimeout(0, function() syncShoe(base) startFx(base, 'in') end)
        else
            startFx(base, 'out')
        end
    end
end)

-- Streaming -------------------------------------------------------------------

local function removeBox(base)
    local box = boxes[base]
    if not box then return end
    if box.start then animating = animating - 1 end
    if box.fx then animating = animating - 1 end
    if DoesEntityExist(box.lid) then DeleteEntity(box.lid) end
    removeShoe(box)
    Target.RemoveSpot(base)
    boxes[base] = nil
end

local targetBox   -- set further down, once the box options exist

local function addBox(base)
    local t = typeOf(base)
    local boxType, colour = Shared.BoxTypeOfModel(GetEntityModel(base))
    local _, lidModel = Shared.BoxModels(boxType, colour)
    if not LoadModel(lidModel) or not DoesEntityExist(base) or boxes[base] then return end
    local c = GetEntityCoords(base)
    local lid = CreateObject(lidModel, c.x, c.y, c.z, false, false, false)
    SetEntityCollision(lid, false, false)
    SetEntityInvincible(lid, true)
    local angle = Entity(base).state['nzs:open'] and B.openAngle or 0.0
    boxes[base] = { t = t, lid = lid, angle = angle, to = angle }
    attachLid(base, lid, angle)
    SetModelAsNoLongerNeeded(lidModel)
    syncShoe(base)
    if targetBox then targetBox(base, t) end
end

CreateThread(function()
    for id, t in pairs(Config.BoxTypes) do
        if not IsModelInCdimage(t.base) or not IsModelInCdimage(t.lid) then
            print(('^1[nayzeee-sneakers]^7 %s (%s)'):format(Config.Text.modelMissing, id))
        end
    end
    -- new boxes come from the shared scan (client/stream.lua); this loop only looks after the ones we have
    local models = {}
    for id in pairs(Config.BoxTypes) do
        for _, c in ipairs(Config.BoxColours or { { id = 'orange' } }) do models[#models + 1] = (Shared.BoxModels(id, c.id)) end
    end
    Stream.Watch(models, B.streamDistance, 'nzsBoxes', function(e) return boxes[e] ~= nil end, addBox)
    while true do
        if not next(boxes) then Wait(1000) goto continue end
        local me = GetEntityCoords(PlayerPedId())
        for base in pairs(boxes) do
            if not DoesEntityExist(base) or #(GetEntityCoords(base) - me) > B.streamDistance + 5.0 then
                removeBox(base)
            else
                syncShoe(base)   -- catches anything a state bag event raced past
            end
        end
        Wait(750)
        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for base in pairs(boxes) do removeBox(base) end
    Cam.Stop(true)
end)

-- Interactions ------------------------------------------------------------------

local function state(ent, key) return Entity(ent).state[key] end
local function netOf(ent) return NetworkGetEntityIsNetworked(ent) and NetworkGetNetworkIdFromEntity(ent) or nil end
local function boxCentre(ent) return GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.0, typeOf(ent).hinge.z * 0.5) end

--- Kneel at the box, close-up camera on it, run `fn`, wait `fn`'s duration, stand up
local function atBox(ent, fn)
    if Busy then return end
    Busy = true
    Anim.Face(ent)
    Anim.Kneel()
    Wait(450)
    Cam.LookAt(boxCentre(ent))
    local ok, duration = fn()
    if ok and duration then Wait(duration) end
    Wait(300)
    Cam.Stop()
    Anim.Stop()
    Busy = false
    return ok
end

--- Pick a pair from the inventory. Returns the slot, or nil.
--- boxType limits the list to pairs that fit that box size.
function Boxes.ChoosePair(boxType)
    local all = lib.callback.await('nayzeee-sneakers:myShoes', false) or {}
    local list = {}
    for _, p in ipairs(all) do
        if not boxType or p.box == boxType then list[#list + 1] = p end
    end
    if #list == 0 then
        if #all > 0 and boxType then
            UI.Notify(Config.Text.wrongBox:format(Config.BoxTypes[all[1].box].label:lower()), 'error')
        else
            UI.Notify(Config.Text.noShoes, 'error')
        end
        return nil
    end
    if #list == 1 then return list[1].slot end
    local options = {}
    for _, p in ipairs(list) do
        local shoe = Config.Shoes[p.meta.shoe]
        options[#options + 1] = {
            id = p.slot,
            label = Shared.ShoeName(p.meta),
            description = ('US %s · %s · %s'):format(p.meta.size, Shared.ConditionLabel(p.meta.condition), p.meta.serial),
            image = shoe and shoe.image,
        }
    end
    return UI.Menu({ title = Config.Text.choosePair, options = options })
end

local function toggleLid(ent)
    if Busy then return end
    lib.callback.await('nayzeee-sneakers:toggleLid', false, netOf(ent))
end

local function putIn(ent)
    if Busy then return end
    local slot = Boxes.ChoosePair(Shared.BoxTypeOfModel(GetEntityModel(ent)))
    if not slot then return end
    atBox(ent, function() return lib.callback.await('nayzeee-sneakers:putIn', false, netOf(ent), slot) end)
end

local function takeOut(ent)
    atBox(ent, function() return lib.callback.await('nayzeee-sneakers:takeOut', false, netOf(ent)) end)
end

--- Hide a box (base, lid and shoes) on this client, e.g. the moment it's picked up
local function hideBox(ent, hide)
    local box = boxes[ent]
    local list = { ent, box and box.lid, box and box.shoe }
    for i = 1, 3 do
        local e = list[i]
        if e and DoesEntityExist(e) then
            if hide then SetEntityAlpha(e, 0, false) else ResetEntityAlpha(e) end
        end
    end
    if box then box.gone = hide or nil end
end

local function pickUp(ent)
    if Busy then return end
    Busy = true
    Anim.Face(ent)
    Anim.PickUp()
    Wait(300)                                  -- hands reach the box
    hideBox(ent, true)                         -- gone from view now, the server catches up
    if not lib.callback.await('nayzeee-sneakers:pickUp', false, netOf(ent)) then hideBox(ent, false) end
    Busy = false
end

local function going(e) return boxes[e] and boxes[e].gone end

local boxOptions = {
        { name = 'nzs_open', label = Config.Text.open, icon = 'fa-solid fa-box-open',
          canInteract = function(e) return not going(e) and not state(e, 'nzs:open') and not state(e, 'nzs:busy') end, onSelect = toggleLid },
        { name = 'nzs_close', label = Config.Text.close, icon = 'fa-solid fa-box',
          canInteract = function(e) return not going(e) and state(e, 'nzs:open') and not state(e, 'nzs:busy') end, onSelect = toggleLid },
        { name = 'nzs_takeout', label = Config.Text.takeOut, icon = 'fa-solid fa-hand',
          canInteract = function(e) return not going(e) and state(e, 'nzs:shoe') and not state(e, 'nzs:busy') end, onSelect = takeOut },
        { name = 'nzs_putin', label = Config.Text.putIn, icon = 'fa-solid fa-shoe-prints',
          canInteract = function(e) return not going(e) and not state(e, 'nzs:shoe') and not state(e, 'nzs:busy') end, onSelect = putIn },
        { name = 'nzs_pickup', label = Config.Text.pickUp, icon = 'fa-solid fa-hand-holding',
          canInteract = function(e) return not going(e) and not state(e, 'nzs:busy') end, onSelect = pickUp },
}

-- Options go on a small sphere around each box as it streams in, so the third eye finds the box
-- wherever you aim on or around it (it doesn't depend on the aim ray hitting the box's collision)
function targetBox(base, t)
    local mn, mx = GetModelDimensions(t.base)
    local half = #(vector2(mx.x - mn.x, mx.y - mn.y)) * 0.5
    local centre = GetOffsetFromEntityInWorldCoords(base, 0.0, 0.0, t.hinge.z * 0.5)
    Target.AddSpot(base, centre, math.max(0.45, half + 0.25), boxOptions, B.interactDistance,
        { offset = vector3(0.0, 0.0, t.hinge.z + 0.08), ignoreLos = true })
end

-- /nzsboxes: what the third eye should be seeing (paste the F8 output if boxes still can't be targeted)
RegisterCommand('nzsboxes', function()
    local me = GetEntityCoords(PlayerPedId())
    print(('^5[nayzeee-sneakers]^7 target system: %s, interact distance %.1f'):format(Target.System(), B.interactDistance))
    local n = 0
    for base, box in pairs(boxes) do
        n = n + 1
        local st = Entity(base).state
        print(('  box %d (%s) %.1fm away  networked=%s  collision=%s  open=%s  shoe=%s  busy=%s'):format(base,
            Shared.BoxTypeOfModel(GetEntityModel(base)) or '?', #(GetEntityCoords(base) - me), tostring(NetworkGetEntityIsNetworked(base)),
            tostring(not GetEntityCollisionDisabled(base)), tostring(st['nzs:open']), tostring(st['nzs:shoe']), tostring(st['nzs:busy'])))
    end
    local seen = 0
    for _, obj in ipairs(GetGamePool('CObject')) do
        if Shared.BoxTypeOfModel(GetEntityModel(obj)) and #(GetEntityCoords(obj) - me) < 50.0 then seen = seen + 1 end
    end
    print(('  %d box(es) set up for the third eye, %d box base(s) within 50m'):format(n, seen))
    local hit, ent = lib.raycast.fromCamera(511, 4, 20)
    local model = hit and Place.ModelOf(ent)
    print(('  aiming at: %s'):format(model and ('entity %d, model %s, is a box: %s'):format(ent, model,
        tostring(Shared.BoxTypeOfModel(model) ~= nil)) or 'nothing / the world'))
end, false)

-- Placing boxes -----------------------------------------------------------------

--- Which colour box: a quick menu (the last one used is at the top). nil = cancelled.
--- Starts loading a colour's box models (they're ready by the time the preview needs them)
local function warm(colour)
    for id in pairs(Config.BoxTypes) do
        local base, lid = Shared.BoxModels(id, colour)
        if IsModelInCdimage(base) then RequestModel(base) end
        if IsModelInCdimage(lid) then RequestModel(lid) end
    end
end

CreateThread(function() warm(GetResourceKvpString('nzs:boxcolour')) end)

function Boxes.PickColour()
    local list = Config.BoxColours or {}
    if not Config.Box.colourPicker or #list < 2 then return Shared.BoxColour(nil) end
    local last = GetResourceKvpString('nzs:boxcolour')
    local options = {}
    for _, c in ipairs(list) do
        local o = { id = c.id, label = c.label, image = 'nz_boxcolour_' .. c.id, description = c.id == last and Config.Text.lastUsed or nil }
        if c.id == last then table.insert(options, 1, o) else options[#options + 1] = o end
    end
    local pick = UI.Menu({ title = Config.Text.boxColour, options = options })
    if pick then SetResourceKvp('nzs:boxcolour', pick) warm(pick) end
    return pick
end

--- Pick where the box goes: a see-through box follows where you look
local function placementSpot(boxType, colour)
    local t = Config.BoxTypes[boxType] or Config.BoxTypes.shoe
    local base, lid = Shared.BoxModels(boxType, colour)
    if not IsModelInCdimage(base) then base, lid = t.base, t.lid end   -- an older nayzeee-sneakers-boxes without colours
    return Place.Ghost(base, {
        range = 2.8,
        extra = { model = lid, offset = t.hinge },
        keep = true,   -- the ghost stays, solid, until the real box is here
    })
end

local function waitForEntity(netId)
    local timeout = GetGameTimer() + 3000
    while not NetworkDoesNetworkIdExist(netId) or not NetworkDoesEntityExistWithNetworkId(netId) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    return NetToObj(netId)
end

RegisterNetEvent('nayzeee-sneakers:client:placeBox', function(slot, kind, boxType, colour)
    if Busy or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local t = Config.BoxTypes[boxType] or Config.BoxTypes.shoe
    if not IsModelInCdimage(t.base) then return UI.Notify(Config.Text.modelMissing, 'error') end
    -- a boxed pair keeps its box; an empty box gets a colour now
    if kind ~= 'boxed' or not colour then colour = Boxes.PickColour() end
    if not colour then return end
    Place.Run(function()
        local spot, heading, ghostDone = placementSpot(boxType, colour)
        if spot then
            Anim.PutDown()
            local netId = lib.callback.await('nayzeee-sneakers:placeBox', false, slot, kind, spot, heading, colour)
            local ent = netId and waitForEntity(netId)
            if ent then addBox(ent) end   -- lid and contents now, not on the next streaming pass
            ghostDone()
        end
    end)
end)

--- Loose pair + empty box from the inventory: put the box down, shoes float in, lid closes
function Boxes.PackFromInventory(slot, meta)
    if Busy or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local colour = Boxes.PickColour()
    if not colour then return end
    Place.Run(function()
        local spot, heading, ghostDone = placementSpot(meta and Shared.BoxTypeForShoe(meta.shoe), colour)
        if not spot then return end
        Anim.PutDown()
        local netId, duration = lib.callback.await('nayzeee-sneakers:packShoes', false, slot, spot, heading, colour)
        local ent = netId and waitForEntity(netId)
        if ent then addBox(ent) end
        ghostDone()
        if ent then
            Anim.Kneel()
            Wait(300)
            Cam.LookAt(boxCentre(ent))
            Wait(duration or 3000)
            Wait(300)
            Cam.Stop()
            Anim.Stop()
        end
    end)
end
