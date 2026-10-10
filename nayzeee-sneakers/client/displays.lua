--[[
    Display cases on this client.

    The case is networked (server/displays.lua); the side door and the pair inside are local objects
    every client spawns for itself from the case's state bag, so the door swing looks smooth for everyone.
    Placing: the same see-through preview as boxes and tables, and aiming at a case you already placed
    lines the new one up on top of it or beside it, so collections stack into neat walls.
]]

local D = Config.Displays
local cases = {}        -- [base] = { t, door, angle, from, to, start, dur, shoeId, shoe, fade }
local animating = 0

local function typeOfModel(model)
    local m = model & 0xFFFFFFFF
    for id, t in pairs(D.Types) do
        if (t.model & 0xFFFFFFFF) == m then return id, t end
    end
end

local function hinge(t) return vector3(-t.size.x * 0.5, t.size.y * 0.5, 0.0) end

local function attachDoor(base, c)
    local h = hinge(c.t)
    AttachEntityToEntity(c.door, base, 0, h.x, h.y, h.z, 0.0, 0.0, c.angle, false, false, false, false, 2, true)
end

local function easeOut(t) return 1 - (1 - t) ^ 3 end

local function swing(base, open)
    local c = cases[base]
    if not c then return end
    local to = open and D.openAngle or 0.0
    if c.to == to and not c.start then return end
    if not c.start then animating = animating + 1 end
    c.from, c.to, c.start, c.dur = c.angle, to, GetGameTimer(), open and D.openTime or D.closeTime
end

-- the pair ----------------------------------------------------------------------------------------

local function removeShoe(c)
    if c.shoe and DoesEntityExist(c.shoe) then DeleteEntity(c.shoe) end
    c.shoe, c.shoeId = nil, nil
end

local function spawnShoe(base, shoeId, fadeIn)
    local c = cases[base]
    local shoe = Config.Shoes[shoeId]
    local model = shoe and ShoeProp(shoe)
    if not c or not model or not LoadModel(model) then return end
    if not cases[base] or c.shoeId ~= shoeId or c.shoe then return end
    local p = GetEntityCoords(base)
    local obj = CreateObject(model, p.x, p.y, p.z, false, false, false)
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    AttachEntityToEntity(obj, base, 0, 0.0, 0.0, D.floor, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(model)
    c.shoe = obj
    if fadeIn then
        SetEntityAlpha(obj, 0, false)
        c.fade = { obj = obj, from = 0, to = 255, start = GetGameTimer(), dur = 500 }
        animating = animating + 1
    end
end

local function syncShoe(base, animate)
    local c = cases[base]
    if not c then return end
    local want = Entity(base).state['nzs:dshoe'] or nil
    if want == c.shoeId and (want == nil or c.shoe) then return end
    if c.shoe and want ~= c.shoeId then
        if animate then
            -- fade the old pair out, then let it go
            local old = c.shoe
            c.shoe, c.shoeId = nil, nil
            c.fade = { obj = old, from = 255, to = 0, start = GetGameTimer(), dur = 400, delete = true }
            animating = animating + 1
        else
            removeShoe(c)
        end
    end
    if want then
        c.shoeId = want
        CreateThread(function() spawnShoe(base, want, animate) end)
    end
end

CreateThread(function()
    while true do
        if animating > 0 then
            local now = GetGameTimer()
            for base, c in pairs(cases) do
                if c.start then
                    local t = math.min((now - c.start) / c.dur, 1.0)
                    c.angle = c.from + (c.to - c.from) * easeOut(t)
                    if t >= 1.0 then c.angle, c.start = c.to, nil animating = animating - 1 end
                    if DoesEntityExist(c.door) then attachDoor(base, c) end
                end
                local f = c.fade
                if f then
                    local t = math.min((now - f.start) / f.dur, 1.0)
                    if DoesEntityExist(f.obj) then SetEntityAlpha(f.obj, math.floor(f.from + (f.to - f.from) * t), false) end
                    if t >= 1.0 then
                        if f.delete and DoesEntityExist(f.obj) then DeleteEntity(f.obj)
                        elseif DoesEntityExist(f.obj) then ResetEntityAlpha(f.obj) end
                        c.fade = nil
                        animating = animating - 1
                    end
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddStateBagChangeHandler('nzs:dopen', nil, function(bag, _, value)
    local base = GetEntityFromStateBagName(bag)
    if base ~= 0 and cases[base] then swing(base, value == true) end
end)

AddStateBagChangeHandler('nzs:dshoe', nil, function(bag)
    local base = GetEntityFromStateBagName(bag)
    if base ~= 0 and cases[base] then SetTimeout(0, function() syncShoe(base, true) end) end
end)

-- options ------------------------------------------------------------------------------------------

local function st(e, k) return Entity(e).state[k] end
local function netOf(e) return NetworkGetEntityIsNetworked(e) and NetworkGetNetworkIdFromEntity(e) or nil end
local function going(e) return cases[e] and cases[e].gone end

--- A loose pair from the inventory that fits this case, or nil
local function choosePair(t)
    local list = {}
    for _, p in ipairs(lib.callback.await('nayzeee-sneakers:myShoes', false) or {}) do
        if t.fits[p.box] then list[#list + 1] = p end
    end
    if #list == 0 then UI.Notify(Config.Text.dispNoFit:format(t.label:lower()), 'error') return nil end
    if #list == 1 then return list[1].slot end
    local options = {}
    for _, p in ipairs(list) do
        local shoe = Config.Shoes[p.meta.shoe]
        options[#options + 1] = {
            id = p.slot, label = Shared.ShoeName(p.meta), image = shoe and shoe.image,
            description = ('US %s · %s · %s'):format(p.meta.size, Shared.ConditionLabel(p.meta.condition), p.meta.serial),
        }
    end
    return UI.Menu({ title = Config.Text.choosePair, options = options })
end

local function busyWhile(fn)
    if Busy then return end
    Busy = true
    local ok, err = pcall(fn)
    if not ok then print(('^1[nayzeee-sneakers]^7 display: %s'):format(err)) end
    Busy = false
end

local function toggleDoor(e)
    if Busy then return end
    lib.callback.await('nayzeee-sneakers:displayDoor', false, netOf(e))
end

local function putIn(e)
    local c = cases[e]
    if not c then return end
    local slot = choosePair(c.t)
    if not slot then return end
    busyWhile(function()
        Anim.Face(e)
        Anim.PutDown()
        local dur = lib.callback.await('nayzeee-sneakers:displayPut', false, netOf(e), slot)
        if dur then Wait(math.min(dur, 2500)) end
    end)
end

local function takeOut(e)
    busyWhile(function()
        Anim.Face(e)
        Anim.PickUp()
        local dur = lib.callback.await('nayzeee-sneakers:displayTake', false, netOf(e))
        if dur then Wait(math.min(dur, 2000)) end
    end)
end

local function look(e)
    local meta = lib.callback.await('nayzeee-sneakers:displayPair', false, netOf(e))
    if meta then Shoes.Inspect(meta) end
end

local function hideCase(e, hide)
    local c = cases[e]
    for _, x in ipairs({ e, c and c.door, c and c.shoe }) do
        if x and DoesEntityExist(x) then
            if hide then SetEntityAlpha(x, 0, false) else ResetEntityAlpha(x) end
        end
    end
    if c then c.gone = hide or nil end
end

local function pickUp(e)
    busyWhile(function()
        Anim.Face(e)
        Anim.PickUp()
        Wait(300)
        hideCase(e, true)
        if not lib.callback.await('nayzeee-sneakers:displayPickUp', false, netOf(e)) then hideCase(e, false) end
    end)
end

local T = Config.Text
--- Another case standing on this one (it can't be picked up until that one's moved)
local function hasCaseOnTop(base)
    local c = cases[base]
    if not c then return false end
    local top = GetOffsetFromEntityInWorldCoords(base, 0.0, 0.0, c.t.size.z)
    for other in pairs(cases) do
        if other ~= base and DoesEntityExist(other) then
            local p = GetEntityCoords(other)
            if math.abs(p.z - top.z) < 0.06 and #(vector2(p.x, p.y) - vector2(top.x, top.y)) < math.max(c.t.size.x, c.t.size.y) * 0.5 then
                return true
            end
        end
    end
    return false
end

-- an empty case: put a pair in, pick it up. A case with a pair: look at it, take it out.
local options = {
    { name = 'nzs_d_open', label = T.dispOpen, icon = 'fa-solid fa-door-open',
      canInteract = function(e) return D.doorOptions and not going(e) and not st(e, 'nzs:dopen') and not st(e, 'nzs:dbusy') end, onSelect = toggleDoor },
    { name = 'nzs_d_close', label = T.dispClose, icon = 'fa-solid fa-door-closed',
      canInteract = function(e) return D.doorOptions and not going(e) and st(e, 'nzs:dopen') and not st(e, 'nzs:dbusy') end, onSelect = toggleDoor },
    { name = 'nzs_d_look', label = T.dispLook, icon = 'fa-solid fa-magnifying-glass',
      canInteract = function(e) return not going(e) and st(e, 'nzs:dshoe') and not st(e, 'nzs:dbusy') end, onSelect = look },
    { name = 'nzs_d_take', label = T.dispTake, icon = 'fa-solid fa-hand',
      canInteract = function(e) return not going(e) and st(e, 'nzs:dshoe') and not st(e, 'nzs:dbusy') end, onSelect = takeOut },
    { name = 'nzs_d_put', label = T.dispPut, icon = 'fa-solid fa-shoe-prints',
      canInteract = function(e) return not going(e) and not st(e, 'nzs:dshoe') and not st(e, 'nzs:dbusy') end, onSelect = putIn },
    { name = 'nzs_d_pickup', label = T.dispPickUp, icon = 'fa-solid fa-hand-holding',
      canInteract = function(e) return not going(e) and not st(e, 'nzs:dshoe') and not st(e, 'nzs:dbusy') and not hasCaseOnTop(e) end, onSelect = pickUp },
}

-- streaming ----------------------------------------------------------------------------------------

local function removeCase(base)
    local c = cases[base]
    if not c then return end
    if c.start then animating = animating - 1 end
    if c.fade then
        animating = animating - 1
        if c.fade.delete and DoesEntityExist(c.fade.obj) then DeleteEntity(c.fade.obj) end
    end
    if DoesEntityExist(c.door) then DeleteEntity(c.door) end
    removeShoe(c)
    Target.RemoveSpot(base)
    cases[base] = nil
end

local function addCase(base)
    local _, t = typeOfModel(GetEntityModel(base))
    if not t or cases[base] or not DoesEntityExist(base) or not LoadModel(t.door) then return end
    local p = GetEntityCoords(base)
    local door = CreateObject(t.door, p.x, p.y, p.z, false, false, false)
    SetEntityCollision(door, false, false)
    SetEntityInvincible(door, true)
    SetModelAsNoLongerNeeded(t.door)
    local angle = st(base, 'nzs:dopen') and D.openAngle or 0.0
    cases[base] = { t = t, door = door, angle = angle, to = angle }
    attachDoor(base, cases[base])
    syncShoe(base, false)
    -- a box the size of the case, so in a stack each case answers only for itself. It runs from just
    -- above the case's floor to just above its lid; the case on top starts above that.
    local h = t.size.z
    local centre = GetOffsetFromEntityInWorldCoords(base, 0.0, 0.0, (0.004 + h + 0.006) * 0.5)
    Target.AddBox(base, centre, vector3(t.size.x + 0.03, t.size.y + 0.03, h + 0.002), GetEntityHeading(base), options, D.interactDistance)
end

CreateThread(function()
    if not D.Enabled then return end
    local models = {}
    for _, t in pairs(D.Types) do models[#models + 1] = t.model end
    Stream.Watch(models, D.streamDistance, 'nzsDisplays', function(e) return cases[e] ~= nil end, addCase)
    while true do
        if not next(cases) then Wait(1000) goto continue end
        local me = GetEntityCoords(PlayerPedId())
        for base, c in pairs(cases) do
            if not DoesEntityExist(base) or #(GetEntityCoords(base) - me) > D.streamDistance + 5.0 then
                removeCase(base)
            elseif not c.start then
                syncShoe(base, false)
            end
        end
        Wait(750)
        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for base in pairs(cases) do removeCase(base) end
end)

-- placing ------------------------------------------------------------------------------------------

--- The case a ray hit: the case itself, or its door (the door is a separate local object)
local function caseOf(ent)
    if not ent or ent == 0 then return nil end
    if cases[ent] then return ent end
    for base, c in pairs(cases) do
        if c.door == ent or c.shoe == ent then return base end
    end
end

--- A case already standing at this spot (so stacking climbs past it)
local function caseAt(pos)
    for base in pairs(cases) do
        if DoesEntityExist(base) and #(GetEntityCoords(base) - pos) < 0.08 then return base end
    end
end

--- Lines a new case (type t) up with the cases already placed. Aim at a case's top (or anywhere over
--- it) and it goes on top of that stack; aim at a side, or at the floor just beside one, and it sits
--- flush against it. Works from where the cases are, not only from what the aim touched, so the glass,
--- the door and the gap beside a case all count. Returns coords, heading or nil.
local function snapTo(t, hitEnt, coords, normal)
    local w, d = t.size.x, t.size.y
    local function spot(base, o, ox, oy, oz)
        return GetOffsetFromEntityInWorldCoords(base, ox, oy, oz), GetEntityHeading(base)
    end
    local function onTop(base)
        -- climb the stack to its top case
        for _ = 1, 20 do
            local o = cases[base].t.size
            local up = GetOffsetFromEntityInWorldCoords(base, 0.0, (o.y - d) * 0.5, o.z + 0.001)
            local above = caseAt(up)
            if not above or not cases[above] then return spot(base, o, 0.0, (o.y - d) * 0.5, o.z + 0.001) end
            base = above
        end
    end
    local function beside(base, sx, sy)
        local o = cases[base].t.size
        local front = (o.y - d) * 0.5     -- keep the fronts flush
        local ox = sx ~= 0 and sx * ((o.x + w) * 0.5 + 0.002) or 0.0
        local oy = sy ~= 0 and sy * ((o.y + d) * 0.5 + 0.002) or front
        local p, h = spot(base, o, ox, oy, 0.0)
        if caseAt(p) then return nil end    -- that side is taken
        return p, h
    end

    -- 1. aimed right at a case (or its door): the face decides
    local hitBase = caseOf(hitEnt)
    if hitBase and normal then
        local hh = math.rad(-GetEntityHeading(hitBase))
        local lx = normal.x * math.cos(hh) - normal.y * math.sin(hh)
        local ly = normal.x * math.sin(hh) + normal.y * math.cos(hh)
        if normal.z > 0.7 then return onTop(hitBase) end
        if math.abs(lx) >= math.abs(ly) then
            local p, h = beside(hitBase, lx > 0 and 1 or -1, 0)
            if p then return p, h end
        else
            local p, h = beside(hitBase, 0, ly > 0 and 1 or -1)
            if p then return p, h end
        end
        return onTop(hitBase)
    end

    -- 2. aimed near one: over its footprint = on top, just off a side = beside it
    local best, bestGap
    for base, c in pairs(cases) do
        if DoesEntityExist(base) and #(GetEntityCoords(base) - coords) < 3.0 then
            local o = c.t.size
            local l = GetOffsetFromEntityGivenWorldCoords(base, coords.x, coords.y, coords.z)
            local inX, inY = math.abs(l.x) <= o.x * 0.5 + 0.02, math.abs(l.y) <= o.y * 0.5 + 0.02
            if inX and inY and l.z > -0.2 then
                return onTop(base)
            end
            if math.abs(l.z) < 0.3 then
                local gapX = math.abs(l.x) - o.x * 0.5
                local gapY = math.abs(l.y) - o.y * 0.5
                if inY and gapX > 0 and gapX < w * 0.75 and (not bestGap or gapX < bestGap) then
                    best, bestGap = { base, l.x > 0 and 1 or -1, 0 }, gapX
                elseif inX and gapY > 0 and gapY < d * 0.75 and (not bestGap or gapY < bestGap) then
                    best, bestGap = { base, 0, l.y > 0 and 1 or -1 }, gapY
                end
            end
        end
    end
    if best then return beside(best[1], best[2], best[3]) end
end

local function waitForEntity(netId)
    local timeout = GetGameTimer() + 3000
    while not NetworkDoesNetworkIdExist(netId) or not NetworkDoesEntityExistWithNetworkId(netId) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    return NetToObj(netId)
end

RegisterNetEvent('nayzeee-sneakers:client:placeDisplay', function(slot, typeId)
    local t = D.Types[typeId]
    if not t or Busy or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    if not IsModelInCdimage(t.model) then return UI.Notify(Config.Text.modelMissing, 'error') end
    Place.Run(function()
        local spot, heading, ghostDone = Place.Ghost(t.model, {
            range = 3.0,
            extra = { model = t.door, offset = hinge(t) },
            keep = true,
            snap = D.snap and function(hitEnt, coords, normal) return snapTo(t, hitEnt, coords, normal) end or nil,
        })
        if spot then
            Anim.PutDown()
            local netId = lib.callback.await('nayzeee-sneakers:placeDisplay', false, slot, typeId, spot, heading)
            local ent = netId and waitForEntity(netId)
            if ent then addCase(ent) end
            ghostDone()
        end
    end)
end)
