--[[
    NAYZEEE AMBULANCE - Medical bag (client)

    The medbag item puts a bag on the ground in front of you (server event 'nza:medbag:place').
    Target options on the bag model (Bridge.Target.Model, every medbag model incl. fallbacks):
    Open medical bag · Carry medical bag · Pick up medical bag. While carrying: [G] put it down,
    [E] open it, [H] pack it away (keys in Config.Medbag.Bag.Carry.keys).
    The storage window is the NUI app 'medbag' (HUD side panels); every move goes to the server.

      NZA.Medbag.Open(id|nil)     open a bag (nil = the one in your hand)
      NZA.Medbag.Carry(id)        pick a ground bag up into your hand
      NZA.Medbag.PutDown()        put the bag in your hand on the ground
      NZA.Medbag.Stow()           bag in your hand → inventory
      NZA.Medbag.PickUp(id)       ground bag → inventory
      NZA.Medbag.Carrying() → id | nil      NZA.Medbag.NearestBag(range) → { id, entity, dist } | nil

    Callbacks used: nza:medbag:put / open / move / action / carry / held / pickup / stow
    Net events handled: nza:medbag:place (token), nza:medbag:sync (id, bag), nza:medbag:closed (id, reason),
                        nza:medbag:carryEnd ()
    Net events sent: nza:medbag:close (id)
    NUI callbacks: medbag:move, medbag:action (+ medbag:close by the router)
    Registries: Bridge.Target.Model (bag models), NZA.RadialItems mb_open / mb_drop / mb_stow
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Medbag = NZA.Medbag or {}
local MB = NZA.Medbag

local S = { carry = nil, open = nil, busy = false }
MB.State = S

local PROMPT_DROP, PROMPT_OPEN, PROMPT_STOW = 'nza_mb_drop', 'nza_mb_open', 'nza_mb_stow'
local BLOCK = { 24, 25, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }
local hashes = nil

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function C(section)
    local c = Config.Medbag or {}
    if not section then return c end
    return c[section] or {}
end

local function L(key, ...) return NZA.L('medbag.' .. key, ...) end

local function toast(msg, kind, icon)
    NZA.UI.Toast({ title = L('title'), message = msg, type = kind or 'info', icon = icon, duration = kind == 'error' and 3500 or 3000 })
end

local function err(res)
    toast(type(res) == 'table' and res.msg or L('err_failed'), 'error')
end

local function down()
    return NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() or false
end

function MB.Models()
    local b = C('Bag')
    local list = { b.model or (Config.Props and Config.Props.medbag) or 'nz_amb_medbag' }
    local fb = Config.PropFallbacks and Config.PropFallbacks.medbag
    if fb then list[#list + 1] = fb end
    for _, m in ipairs(b.extraModels or {}) do list[#list + 1] = m end
    return list
end

local function modelSet()
    if hashes then return hashes end
    hashes = {}
    for _, m in ipairs(MB.Models()) do hashes[GetHashKey(m)] = true end
    return hashes
end

local function bagOf(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) or not NetworkGetEntityIsNetworked(ent) then return nil end
    local st = Entity(ent).state.nzaMedbag
    if type(st) == 'table' and type(st.id) == 'string' then return st end
    return nil
end

function MB.NearestBag(range)
    range = range or 3.0
    local me = GetEntityCoords(PlayerPedId())
    local set = modelSet()
    local best, bestD = nil, range
    for _, obj in ipairs(GetGamePool('CObject')) do
        if set[GetEntityModel(obj)] then
            local d = #(me - GetEntityCoords(obj))
            if d <= bestD then
                local st = bagOf(obj)
                if st then best, bestD = { id = st.id, entity = obj, dist = d, owner = st.owner, locked = st.locked }, d end
            end
        end
    end
    return best
end

function MB.Carrying() return S.carry and S.carry.id or nil end

local function handsFull()
    if S.carry then return true end
    if MB.BodyCarrying and MB.BodyCarrying() then return true end
    return false
end
MB.HandsFull = handsFull

local function playOnce(a)
    if type(a) ~= 'table' or not a.dict then return end
    local ped = PlayerPedId()
    local ok, token = NZA.Anim.Play(ped, a.dict, a.clip, { flag = a.flag or 0 })
    Wait(math.floor(tonumber(a.ms) or 900))
    if ok then NZA.Anim.Stop(ped, { token = token }) end
end

-- a free spot on the ground in front of you (never through a wall)
function MB.GroundSpot(ahead)
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local target = GetOffsetFromEntityInWorldCoords(ped, 0.0, ahead or 0.85, 0.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, target.x, target.y, target.z, 1 + 16, ped, 4)
    local _, hit, hitPos = GetShapeTestResult(ray)
    if hit == 1 and hitPos then
        local dir = target - origin
        local len = #dir
        local back = len > 0.01 and (dir / len) * 0.35 or vector3(0.0, 0.0, 0.0)
        target = vector3(hitPos.x, hitPos.y, target.z) - back
    end
    local found, z = GetGroundZFor_3dCoord(target.x, target.y, target.z + 1.0, false)
    if not found then
        local f2, z2 = GetGroundZFor_3dCoord(target.x, target.y, origin.z + 2.5, false)
        found, z = f2, z2
    end
    if not found or math.abs(z - origin.z) > 2.4 then z = origin.z - 0.98 end
    return vector3(target.x, target.y, z), GetEntityHeading(ped)
end

local function plainV(v) return { x = v.x, y = v.y, z = v.z } end

-- the ambulance treatment bay is a local interior: nothing networked goes down in there
local function inBay()
    local T = NZA.Transport
    return T and T.Bay and T.Bay.Active and T.Bay.Active() and true or false
end

-- the pockets (+Y) of the bag face you
local function bagHeading(h) return (h + 180.0) % 360.0 end

-- ════════════════════════════════════════════════════════════════════════
-- OPEN / NUI
-- ════════════════════════════════════════════════════════════════════════

function MB.Open(id)
    if S.open then return end
    if down() then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return toast(L('err_vehicle'), 'error') end
    local res = lib.callback.await('nza:medbag:open', false, id)
    if type(res) ~= 'table' or not res.ok then return err(res) end
    S.open = res.bag.id
    NZA.UI.Open('medbag', {
        locale = NZA.LocaleTable('medbag'), bag = res.bag, me = res.me, kit = res.kit,
    }, { focus = true, cursor = true })
end

local function closeLocal(reason)
    local id = S.open
    if not id then return end
    S.open = nil
    NZA.UI.Close('medbag')
    TriggerServerEvent('nza:medbag:close', id)
    if reason then toast(L('closed_' .. reason), 'warning') end
end
MB.Close = closeLocal

NZA.UI.On('medbag', 'move', function(data, cb)
    if not S.open or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_bag') }) end
    local res = lib.callback.await('nza:medbag:move', false, S.open, {
        dir = data.dir, from = tonumber(data.from), to = tonumber(data.to), name = data.name,
        count = data.count == 'all' and 'all' or tonumber(data.count),
    })
    cb(type(res) == 'table' and res or { ok = false, msg = L('err_failed') })
end)

NZA.UI.On('medbag', 'action', function(data, cb)
    if not S.open or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_bag') }) end
    local res = lib.callback.await('nza:medbag:action', false, S.open, data.action, data.data)
    cb(type(res) == 'table' and res or { ok = false, msg = L('err_failed') })
end)

NZA.Bus.On('ui:closed', function(app)
    if app ~= 'medbag' then return end
    local id = S.open
    S.open = nil
    if id then TriggerServerEvent('nza:medbag:close', id) end
end)

RegisterNetEvent('nza:medbag:sync', function(id, bag)
    if S.open and S.open == id then NZA.UI.Send('medbag', 'sync', { bag = bag }) end
end)

RegisterNetEvent('nza:medbag:closed', function(id, reason)
    if not S.open or S.open ~= id then return end
    S.open = nil
    NZA.UI.Close('medbag')
    local key = 'closed_' .. tostring(reason)
    if NZA.L('medbag.' .. key) ~= 'medbag.' .. key then toast(L(key), 'warning') end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PLACE (item use)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:medbag:place', function(token)
    if S.busy then return end
    CreateThread(function()
        S.busy = true
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            S.busy = false
            return toast(L('err_vehicle'), 'error')
        end
        if down() then S.busy = false return end
        if inBay() then
            S.busy = false
            return toast(L('err_bad_spot'), 'error')
        end
        playOnce(C('Bag').putDown)
        local coords, h = MB.GroundSpot(C('Bag').placeAhead)
        local res = lib.callback.await('nza:medbag:put', false, token, plainV(coords), bagHeading(h))
        S.busy = false
        if type(res) ~= 'table' or not res.ok then return err(res) end
        toast(res.msg or L('ok_placed'), 'success', 'medkit')
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- CARRY
-- ════════════════════════════════════════════════════════════════════════

local function endCarry()
    local cur = S.carry
    S.carry = nil
    NZA.UI.HidePrompt(PROMPT_DROP)
    NZA.UI.HidePrompt(PROMPT_OPEN)
    NZA.UI.HidePrompt(PROMPT_STOW)
    local ped = PlayerPedId()
    if cur and cur.animToken then NZA.Anim.Stop(ped, { token = cur.animToken }) end
    NZA.Props.Clear('medbag_hand')
end
MB.EndCarry = endCarry

local function keyOf(name, def)
    local k = (C('Bag').Carry or {}).keys or {}
    return k[name] or def
end

local function carryLoop()
    local c = C('Bag').Carry or {}
    local dropK = keyOf('drop', { control = 47, label = 'G' })
    local openK = keyOf('open', { control = 38, label = 'E' })
    local stowK = keyOf('stow', { control = 74, label = 'H' })
    local maxSpeed = tonumber(c.maxSpeed) or 2.0
    local lastAnim = 0
    NZA.UI.Prompt(PROMPT_DROP, { key = dropK.label, label = L('p_drop'), sub = L('p_sub') })
    NZA.UI.Prompt(PROMPT_OPEN, { key = openK.label, label = L('p_open') })
    NZA.UI.Prompt(PROMPT_STOW, { key = stowK.label, label = L('p_stow') })
    while S.carry do
        local ped = PlayerPedId()
        for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
        DisableControlAction(0, 23, true)                   -- enter vehicle
        if maxSpeed < 3.0 then DisableControlAction(0, 21, true) end
        if maxSpeed <= 1.0 then SetPedMaxMoveBlendRatio(ped, 1.0) end
        DisableControlAction(0, dropK.control, true)
        DisableControlAction(0, openK.control, true)
        DisableControlAction(0, stowK.control, true)

        local now = GetGameTimer()
        if c.anim and now - lastAnim > 1000 then
            lastAnim = now
            if not IsEntityPlayingAnim(ped, c.anim.dict, c.anim.clip, 3) then
                local ok, token = NZA.Anim.Play(ped, c.anim.dict, c.anim.clip, { flag = c.anim.flag or 49 })
                if ok and S.carry then S.carry.animToken = token end
            end
        end

        if not S.busy and not S.open and not NZA.UI.Top() then
            if IsDisabledControlJustPressed(0, dropK.control) then
                CreateThread(MB.PutDown)
            elseif IsDisabledControlJustPressed(0, openK.control) then
                CreateThread(function() MB.Open(nil) end)
            elseif IsDisabledControlJustPressed(0, stowK.control) then
                CreateThread(MB.Stow)
            end
        end
        Wait(0)
    end
end

local function startCarry(res)
    local c = C('Bag').Carry or {}
    local ped = PlayerPedId()
    local model = (res.models and res.models[1]) or MB.Models()[1]
    local ent, net = NZA.Props.Spawn(model, {
        attach = { entity = ped, bone = c.bone or 28422, pos = c.pos or vector3(0.0, 0.0, -0.40), rot = c.rot or vector3(0.0, 0.0, 0.0) },
    }, { network = true, group = 'medbag_hand', collision = false, fallbackKey = 'medbag' })
    S.carry = { id = res.id, ent = ent }
    if net then lib.callback.await('nza:medbag:held', false, res.token, net) end
    if c.anim then
        local ok, token = NZA.Anim.Play(ped, c.anim.dict, c.anim.clip, { flag = c.anim.flag or 49 })
        if ok then S.carry.animToken = token end
    end
    CreateThread(carryLoop)
end

function MB.Carry(id)
    if S.busy or handsFull() then return toast(L('err_carrying'), 'error') end
    if down() then return end
    S.busy = true
    local res = lib.callback.await('nza:medbag:carry', false, id)
    if type(res) ~= 'table' or not res.ok then
        S.busy = false
        return err(res)
    end
    playOnce(C('Bag').pickUp)
    startCarry(res)
    S.busy = false
end

function MB.PutDown()
    if not S.carry or S.busy then return end
    if inBay() then return toast(L('err_bad_spot'), 'error') end
    S.busy = true
    playOnce(C('Bag').putDown)
    local coords, h = MB.GroundSpot(C('Bag').placeAhead)
    local res = lib.callback.await('nza:medbag:put', false, nil, plainV(coords), bagHeading(h))
    S.busy = false
    if type(res) ~= 'table' or not res.ok then return err(res) end
    endCarry()
    toast(res.msg or L('ok_placed'), 'success', 'medkit')
end

function MB.Stow()
    if not S.carry or S.busy then return end
    S.busy = true
    local res = lib.callback.await('nza:medbag:stow', false)
    S.busy = false
    if type(res) ~= 'table' or not res.ok then return err(res) end
    if S.open then closeLocal() end
    endCarry()
    toast(res.msg or L('ok_picked'), 'success', 'medkit')
end

function MB.PickUp(id)
    if S.busy then return end
    if down() then return end
    S.busy = true
    playOnce(C('Bag').pickUp)
    local res = lib.callback.await('nza:medbag:pickup', false, id)
    S.busy = false
    if type(res) ~= 'table' or not res.ok then return err(res) end
    toast(res.msg or L('ok_picked'), 'success', 'medkit')
end

RegisterNetEvent('nza:medbag:carryEnd', function()
    endCarry()
end)

-- ════════════════════════════════════════════════════════════════════════
-- TARGETS & RADIAL
-- ════════════════════════════════════════════════════════════════════════

local function targetOptions()
    local dist = tonumber(C('Bag').distance) or 2.0
    local function ok(ent) return C('Bag').enabled ~= false and bagOf(ent) ~= nil and not down() and not IsPedInAnyVehicle(PlayerPedId(), false) end
    return {
        {
            name = 'nza_medbag_open', label = L('open'), icon = 'medkit', distance = dist,
            canInteract = function(ent) return ok(ent) and not S.open end,
            onSelect = function(ent)
                local st = bagOf(type(ent) == 'table' and ent.entity or ent)
                if st then CreateThread(function() MB.Open(st.id) end) end
            end,
        },
        {
            name = 'nza_medbag_carry', label = L('carry'), icon = 'bag', distance = dist,
            canInteract = function(ent) return ok(ent) and (C('Bag').Carry or {}).enabled ~= false and not handsFull() end,
            onSelect = function(ent)
                local st = bagOf(type(ent) == 'table' and ent.entity or ent)
                if st then CreateThread(function() MB.Carry(st.id) end) end
            end,
        },
        {
            name = 'nza_medbag_pickup', label = L('pickup'), icon = 'backpack', distance = dist,
            canInteract = function(ent) return ok(ent) end,
            onSelect = function(ent)
                local st = bagOf(type(ent) == 'table' and ent.entity or ent)
                if st then CreateThread(function() MB.PickUp(st.id) end) end
            end,
        },
    }
end

CreateThread(function()
    Wait(1500)
    if C('Bag').enabled == false then return end
    if Bridge and Bridge.Target and Bridge.Target.Model then
        local ok, e = pcall(Bridge.Target.Model, MB.Models(), targetOptions())
        if not ok then NZA.Warn('medbag: target registration failed: ' .. tostring(e)) end
    end
end)

NZA.RadialItems = NZA.RadialItems or {}
table.insert(NZA.RadialItems, {
    id = 'mb_open', label = L('r_open'), desc = L('r_open_d'), icon = 'medkit', order = 70,
    canShow = function()
        if C().radial == false or C('Bag').enabled == false then return false end
        return S.carry ~= nil or MB.NearestBag(3.0) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            if S.carry then return MB.Open(nil) end
            local b = MB.NearestBag(3.0)
            if b then MB.Open(b.id) end
        end)
    end,
})
table.insert(NZA.RadialItems, {
    id = 'mb_drop', label = L('r_drop'), desc = L('r_drop_d'), icon = 'arrow-down', order = 71,
    canShow = function() return C().radial ~= false and S.carry ~= nil end,
    onSelect = function() CreateThread(MB.PutDown) end,
})
table.insert(NZA.RadialItems, {
    id = 'mb_stow', label = L('r_stow'), desc = L('r_stow_d'), icon = 'backpack', order = 72,
    canShow = function() return C().radial ~= false and S.carry ~= nil end,
    onSelect = function() CreateThread(MB.Stow) end,
})

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

-- going down: the server drops the bag where you are; the window closes
NZA.Bus.On('self:state', function(new)
    if new == 'alive' then return end
    if S.open then closeLocal() end
    if S.carry then endCarry() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    if S.carry then
        NZA.UI.HidePrompt(PROMPT_DROP)
        NZA.UI.HidePrompt(PROMPT_OPEN)
        NZA.UI.HidePrompt(PROMPT_STOW)
        local ped = PlayerPedId()
        if S.carry.animToken then NZA.Anim.Stop(ped, { token = S.carry.animToken, immediate = true }) end
    end
end)
