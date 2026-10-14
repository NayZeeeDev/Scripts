--[[
    NAYZEEE AMBULANCE - Wheelchair (server)

    The folding wheelchair item unfolds into a networked Config.Props.wheelchair object created by the
    server. Every chair carries an entity state bag 'nzaChair' = { owner = src, occ = src | netId,
    occNpc = bool, push = src } that all clients read for their target options and HUD.

    Usable item Config.Items.wheelchair → S→C 'nza:splint:chair:place' (the client plays the unfold
    animation and asks for the chair with the callback below).
    Callbacks
      nza:splint:chair:spawn  (coords, heading)  → { ok, net } | { ok = false, err, msg }
      nza:splint:chair:sit    (net)              → { ok } | ...           sit in it yourself
      nza:splint:chair:push   (net, on)          → { ok } | ...           take / let go of the handles
      nza:splint:chair:fold   (net)              → { ok } | ...           fold it back into the item
      nza:splint:chair:seat   (net, target)      → { ok, npc } | ...      medic seats a patient (Wheelchair.seatPerm)
      nza:splint:chair:unseat (net)              → { ok, npc, occ } | ... medic helps the patient out
    Net events: C→S 'nza:splint:chair:leave' (net) · S→C 'nza:splint:chair:seated' (net, on)
    Cleanup: players leaving free their seat / handles; empty chairs of owners who left are removed after
    Wheelchair.abandonMinutes; every chair is deleted when the resource stops.
    Server API: NZA.Splint.Chairs() → { [net] = chair }, NZA.Splint.ChairOf(src) → net | nil
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Splint = NZA.Splint or {}
local SP = NZA.Splint
local U = NZA.Util

local function C(section)
    local c = Config.Splint or {}
    return c[section] or {}
end

local function W() return C('Wheelchair') end

local function L(key, ...)
    return NZA.L('splint.' .. key, ...)
end

local function fail(err, ...)
    return { ok = false, err = err, msg = L('err_' .. err, ...) }
end

local function B(path, ...)
    if NZA.Core and NZA.Core.B then return NZA.Core.B(path, ...) end
    return nil
end

local chairs = {}       -- net → { ent, net, owner, ownerGoneAt, occ = { kind, src | net }, push = src, created }

function SP.Chairs() return chairs end

local function itemName()
    local key = W().item or 'wheelchair'
    return Config.Items and Config.Items[key] or nil
end

local function modelName()
    local key = W().prop or 'wheelchair'
    return (Config.Props and Config.Props[key]) or 'prop_wheelchair_01'
end

local function srcCoords(src)
    if NZA.Core and NZA.Core.SrcCoords then return NZA.Core.SrcCoords(src) end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function chairOf(net)
    net = tonumber(net)
    local c = net and chairs[net]
    if not c then return nil end
    if not DoesEntityExist(c.ent) then
        chairs[net] = nil
        return nil
    end
    return c
end

local function near(src, c, maxDist)
    local a = srcCoords(src)
    if not a then return false end
    local b = GetEntityCoords(c.ent)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) <= (maxDist or 3.0)
end

local function alive(src)
    local p = NZA.Patients.GetBySource(src)
    return not p or p.state == 'alive'
end

local function inVehicle(src)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0
end

local function sync(c)
    if not DoesEntityExist(c.ent) then return end
    local occ = c.occ
    Entity(c.ent).state:set('nzaChair', {
        owner = c.owner,
        occ = occ and (occ.kind == 'npc' and occ.net or occ.src) or nil,
        occNpc = occ and occ.kind == 'npc' or nil,
        push = c.push,
    }, true)
end

local function countOwned(src)
    local n = 0
    for _, c in pairs(chairs) do
        if c.owner == src and DoesEntityExist(c.ent) then n = n + 1 end
    end
    return n
end

function SP.ChairOf(src)
    for net, c in pairs(chairs) do
        if c.occ and c.occ.kind == 'player' and c.occ.src == src then return net end
    end
    return nil
end

local function rate(src, n, ms)
    return NZA.Core.Rate('splint:chair', src, n or 6, ms or 2000)
end

-- ════════════════════════════════════════════════════════════════════════
-- UNFOLD
-- ════════════════════════════════════════════════════════════════════════

local function useItem(src)
    if W().enabled == false then return end
    if not alive(src) or inVehicle(src) then
        if NZA.Core.Notify then NZA.Core.Notify(src, L('err_cant_now'), 'error', L('chair')) end
        return
    end
    if countOwned(src) >= (tonumber(W().maxPerPlayer) or 1) then
        if NZA.Core.Notify then NZA.Core.Notify(src, L('err_max_chairs'), 'error', L('chair')) end
        return
    end
    TriggerClientEvent('nza:splint:chair:place', src)
end

lib.callback.register('nza:splint:chair:spawn', function(src, coords, heading)
    if W().enabled == false then return fail('disabled') end
    if not rate(src, 3, 3000) then return fail('rate') end
    local name = itemName()
    if not name then return fail('disabled') end
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return fail('bad') end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (x and y and z) then return fail('bad') end
    local me = srcCoords(src)
    if not me or #(vector3(me.x, me.y, me.z) - vector3(x, y, z)) > 3.5 then return fail('too_far') end
    if not alive(src) or inVehicle(src) then return fail('cant_now') end
    if countOwned(src) >= (tonumber(W().maxPerPlayer) or 1) then return fail('max_chairs') end
    if not B('Inv.RemoveItem', src, name, 1) then return fail('no_chair') end

    local hash = joaat(modelName())
    local ent = CreateObjectNoOffset(hash, x, y, z, true, true, false)
    local deadline = GetGameTimer() + 4000
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and GetGameTimer() < deadline do Wait(25) end
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        B('Inv.AddItem', src, name, 1)
        return fail('spawn')
    end
    SetEntityHeading(ent, tonumber(heading) or 0.0)
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, ent, 2) end
    local net = NetworkGetNetworkIdFromEntity(ent)
    chairs[net] = { ent = ent, net = net, owner = src, created = os.time() }
    sync(chairs[net])
    return { ok = true, net = net }
end)

-- ════════════════════════════════════════════════════════════════════════
-- SIT / PUSH / FOLD
-- ════════════════════════════════════════════════════════════════════════

local function clearSeatOf(src)
    for _, c in pairs(chairs) do
        local changed = false
        if c.occ and c.occ.kind == 'player' and c.occ.src == src then c.occ = nil changed = true end
        if c.push == src then c.push = nil changed = true end
        if changed then sync(c) end
    end
end

lib.callback.register('nza:splint:chair:sit', function(src, net)
    if not rate(src) then return fail('rate') end
    local c = chairOf(net)
    if not c then return fail('no_chair_here') end
    if c.occ then return fail('taken') end
    if c.push == src then return fail('taken') end
    if not near(src, c, 2.6) then return fail('too_far') end
    if not alive(src) or inVehicle(src) then return fail('cant_now') end
    if SP.ChairOf(src) then return fail('cant_now') end
    c.occ = { kind = 'player', src = src }
    sync(c)
    return { ok = true }
end)

RegisterNetEvent('nza:splint:chair:leave', function(net)
    local src = source
    local c = chairOf(net)
    if not c or not c.occ or c.occ.kind ~= 'player' or c.occ.src ~= src then return end
    c.occ = nil
    sync(c)
end)

lib.callback.register('nza:splint:chair:push', function(src, net, on)
    if not rate(src) then return fail('rate') end
    local c = chairOf(net)
    if not c then return fail('no_chair_here') end
    if on then
        if c.push and c.push ~= src then return fail('taken') end
        if c.occ and c.occ.kind == 'player' and c.occ.src == src then return fail('cant_now') end
        if not near(src, c, 2.6) then return fail('too_far') end
        if not alive(src) or inVehicle(src) then return fail('cant_now') end
        c.push = src
    elseif c.push == src then
        c.push = nil
    end
    sync(c)
    return { ok = true }
end)

lib.callback.register('nza:splint:chair:fold', function(src, net)
    if not rate(src, 3, 3000) then return fail('rate') end
    local c = chairOf(net)
    if not c then return fail('no_chair_here') end
    if c.occ then return fail('occupied') end
    if c.push and c.push ~= src then return fail('taken') end
    if W().foldOwnerOnly and c.owner ~= src and not (NZA.Staff and NZA.Staff.Can(src, W().seatPerm or 'transport')) then
        return fail('not_owner')
    end
    if not near(src, c, 2.6) then return fail('too_far') end
    local name = itemName()
    if not name then return fail('disabled') end
    if B('Inv.CanCarry', src, name, 1) == false then return fail('cant_carry') end
    chairs[c.net] = nil
    if DoesEntityExist(c.ent) then DeleteEntity(c.ent) end
    B('Inv.AddItem', src, name, 1)
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════
-- MEDICS: SEAT / HELP OUT A PATIENT
-- ════════════════════════════════════════════════════════════════════════

local function allowedState(p)
    local list = W().states or { 'alive' }
    for _, s in ipairs(list) do if p.state == s then return true end end
    return false
end

local function bill(src, p)
    local amount = tonumber(C('Billing').chair) or 0
    if amount <= 0 or type(p) ~= 'table' or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, L('bill_chair'), { medic = src, kind = 'splint_chair' })
    if not ok then NZA.Warn('splint chair billing failed: ' .. tostring(err)) end
end

lib.callback.register('nza:splint:chair:seat', function(src, net, target)
    if not rate(src) then return fail('rate') end
    if not (NZA.Staff and NZA.Staff.Can(src, W().seatPerm or 'transport')) then return fail('no_perm') end
    local c = chairOf(net)
    if not c then return fail('no_chair_here') end
    if c.occ then return fail('occupied') end
    local p = NZA.Patients.Resolve(target)
    if not p then return fail('no_patient') end
    if p.kind == 'player' and p.src == src then return fail('cant_now') end
    if not allowedState(p) then return fail('patient_state') end
    local dist = NZA.Core.DistanceTo and NZA.Core.DistanceTo(src, p) or 0
    if dist > (tonumber(C('Interact').distance) or 2.2) + 1.5 then return fail('too_far') end
    local pc = NZA.Core.PatientCoords and NZA.Core.PatientCoords(p)
    if pc then
        local cc = GetEntityCoords(c.ent)
        if #(vector3(pc.x, pc.y, pc.z) - vector3(cc.x, cc.y, cc.z)) > (tonumber(C('Interact').chairRange) or 6.0) + 1.0 then
            return fail('chair_far')
        end
    end
    if p.kind == 'player' then
        if not p.src then return fail('no_patient') end
        if SP.ChairOf(p.src) then return fail('occupied') end
        c.occ = { kind = 'player', src = p.src }
        sync(c)
        TriggerClientEvent('nza:splint:chair:seated', p.src, c.net, true)
    else
        if not p.net then return fail('no_patient') end
        c.occ = { kind = 'npc', net = p.net }
        sync(c)
    end
    bill(src, p)
    return { ok = true, npc = p.kind ~= 'player' }
end)

lib.callback.register('nza:splint:chair:unseat', function(src, net)
    if not rate(src) then return fail('rate') end
    if not (NZA.Staff and NZA.Staff.Can(src, W().seatPerm or 'transport')) then return fail('no_perm') end
    local c = chairOf(net)
    if not c then return fail('no_chair_here') end
    if not c.occ then return fail('empty') end
    if not near(src, c, 3.0) then return fail('too_far') end
    local occ = c.occ
    c.occ = nil
    sync(c)
    if occ.kind == 'player' and occ.src then
        TriggerClientEvent('nza:splint:chair:seated', occ.src, c.net, false)
        return { ok = true, npc = false }
    end
    return { ok = true, npc = true, occ = occ.net }
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function()
    local src = source
    clearSeatOf(src)
    for _, c in pairs(chairs) do
        if c.owner == src then c.ownerGoneAt = os.time() end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        local limit = (tonumber(W().abandonMinutes) or 20) * 60
        for net, c in pairs(chairs) do
            if not DoesEntityExist(c.ent) then
                chairs[net] = nil
            else
                -- occupants / pushers that vanished
                local changed = false
                if c.occ and c.occ.kind == 'player' and GetPlayerName(c.occ.src) == nil then c.occ = nil changed = true end
                if c.occ and c.occ.kind == 'npc' then
                    local ped = NetworkGetEntityFromNetworkId(c.occ.net)
                    if not ped or ped == 0 or not DoesEntityExist(ped) then c.occ = nil changed = true end
                end
                if c.push and GetPlayerName(c.push) == nil then c.push = nil changed = true end
                if changed then sync(c) end
                if c.ownerGoneAt and not c.occ and not c.push and now - c.ownerGoneAt >= limit then
                    chairs[net] = nil
                    DeleteEntity(c.ent)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, c in pairs(chairs) do
        if DoesEntityExist(c.ent) then DeleteEntity(c.ent) end
    end
    chairs = {}
end)

-- usable item
CreateThread(function()
    local name = itemName()
    if not name or W().enabled == false then return end
    local deadline = GetGameTimer() + 30000
    while not (Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function') and GetGameTimer() < deadline do Wait(500) end
    if Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function' then
        local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src) useItem(src) end)
        if not ok then NZA.Warn('splint: could not register the wheelchair item: ' .. tostring(err)) end
    else
        NZA.Warn('splint: Bridge.Inv.RegisterUsable is missing - the wheelchair cannot be used from the inventory')
    end
end)
