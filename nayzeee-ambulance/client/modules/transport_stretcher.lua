--[[
    NAYZEEE AMBULANCE - Transport (client): stretcher

      NZA.Transport.Str.TakeFromVehicle(veh) / TakeFromPoint(point)   cot rolls out of the back / off the rack
      NZA.Transport.Str.Grab(ent) / Release()                         push (attached in front of you) / let go
      NZA.Transport.Str.ToggleHeight(ent?)                            raise / lower (swaps to the low model if any)
      NZA.Transport.Str.PlacePatient(ent?, patient, target)           patient onto the cot (from the ground / carry / bed)
      NZA.Transport.Str.TakeOff(ent)                                  patient off the cot, next to it
      NZA.Transport.Str.Load(veh) / Unload(veh)                       roll into / out of the ambulance (animated slide)
      NZA.Transport.Str.Store(ent, veh?, point?)                      put an empty cot away
      NZA.Transport.Str.FreeNear(coords, range?) → ent | nil          free cot (no patient, not loaded)
      NZA.Transport.Str.All(coords, range) → { { ent, bag, d } }      NZA.Transport.Str.Models() → { hash }
      NZA.Transport.LowModelActive(ent) → bool

    Pushing: walk speed, [G] let go, [H] raise / lower, [E] context: load into the ambulance (patient on
    it), return the cot (empty, at an ambulance or a stretcher rack), transfer the patient to a nearby
    bed / table. Targets: on the cot model (push, raise/lower, put the patient on, take off, move to the
    bed, return) and on the configured ambulance models (take, load, unload, return).
    Hospital point type owned here: 'stretcher' (rack where cots are taken and returned).
    Net events handled: nza:transport:pushEnd (net)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local Tr = NZA.Transport
Tr.Str = Tr.Str or {}
local St = Tr.Str

local BLOCK = { 22, 23, 24, 25, 36, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }
local PROMPT, PROMPT_H, PROMPT_CTX = 'nza_tr_push', 'nza_tr_push_h', 'nza_tr_push_ctx'
local GROUP = 'transport'

local function S() return Tr.S end
local function sc() return Tr.Cfg('Stretcher') end
local function perm() return Tr.Cfg().perm or 'transport' end
local function mySid() return GetPlayerServerId(PlayerId()) end

-- ════════════════════════════════════════════════════════════════════════
-- MODELS
-- ════════════════════════════════════════════════════════════════════════

local modelSet, modelList = nil, nil

local function buildModels()
    modelSet, modelList = {}, {}
    local function add(k)
        if not k then return end
        for _, name in ipairs({ Config.Props and Config.Props[k], Config.PropFallbacks and Config.PropFallbacks[k] }) do
            if name then
                local h = GetHashKey(name)
                if not modelSet[h] then
                    modelSet[h] = true
                    modelList[#modelList + 1] = h
                end
            end
        end
    end
    add(sc().model or 'stretcher')
    add(sc().lowModel)
end

function St.Models()
    if not modelList then buildModels() end
    return modelList
end

local function lowName()
    local k = sc().lowModel
    return k and Config.Props and Config.Props[k] or nil
end

function Tr.LowModelActive(ent)
    local n = lowName()
    return n ~= nil and ent and ent ~= 0 and GetEntityModel(ent) == GetHashKey(n)
end

function St.Is(ent)
    if not modelSet then buildModels() end
    return ent and ent ~= 0 and DoesEntityExist(ent) and modelSet[GetEntityModel(ent)] == true and Tr.StrBag(ent) ~= nil
end

-- networked cots in the object pool (rebuilt at most every 750 ms: targets ask every frame)
local poolCache = { at = -1000, list = {} }
local function cots()
    local now = GetGameTimer()
    if now - poolCache.at < 750 then return poolCache.list end
    if not modelSet then buildModels() end
    local list = {}
    for _, obj in ipairs(GetGamePool('CObject')) do
        if modelSet[GetEntityModel(obj)] and NetworkGetEntityIsNetworked(obj) then list[#list + 1] = obj end
    end
    poolCache.at, poolCache.list = now, list
    return list
end

function St.All(coords, range)
    local out = {}
    for _, obj in ipairs(cots()) do
        if DoesEntityExist(obj) then
            local d = #(coords - GetEntityCoords(obj))
            if d <= range then
                local bag = Tr.StrBag(obj)
                if bag then out[#out + 1] = { ent = obj, bag = bag, d = d } end
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function pusherOk(bag)
    return not bag.pusher or bag.pusher == mySid()
end

function St.FreeNear(coords, range)
    for _, s in ipairs(St.All(coords, range or sc().findRange or 6.0)) do
        if not s.bag.pid and not s.bag.veh and pusherOk(s.bag) then return s.ent end
    end
    return nil
end

local function emptyNear(coords, range)
    for _, s in ipairs(St.All(coords, range)) do
        if not s.bag.pid and not s.bag.veh and pusherOk(s.bag) then return s.ent end
    end
    return nil
end

-- nearest configured ambulance whose back doors are within reach
function St.Ambulance(reach)
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestD = nil, math.huge
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if #(pos - GetEntityCoords(veh)) < 12.0 and Tr.VehCfg(veh) then
            local ok, d = Tr.NearRear(veh, reach)
            if ok and d < bestD then best, bestD = veh, d end
        end
    end
    return best
end

local function rackNear(coords, range)
    for _, pt in ipairs(NZA.Points.All('stretcher')) do
        local c = pt.coords
        if c and #(coords - vector3(c.x, c.y, c.z)) <= range then return pt end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- DOORS & SLIDE
-- ════════════════════════════════════════════════════════════════════════

local function doorList(veh)
    local c = Tr.VehCfg(veh) or {}
    return c.doors or { 2, 3 }
end

local function openDoors(veh)
    if (sc().load or {}).openDoors == false then return end
    if not Tr.Control(veh, 600) then return end
    for _, d in ipairs(doorList(veh)) do
        if GetVehicleDoorAngleRatio(veh, d) < 0.5 then SetVehicleDoorOpen(veh, d, false, false) end
    end
end

local function closeDoors(veh, delay)
    if (sc().load or {}).closeDoors == false then return end
    CreateThread(function()
        Wait(delay or 900)
        if not DoesEntityExist(veh) or not Tr.Control(veh, 600) then return end
        for _, d in ipairs(doorList(veh)) do SetVehicleDoorShut(veh, d, false) end
    end)
end

local function angleLerp(a, b, t)
    local d = ((b - a + 540.0) % 360.0) - 180.0
    return a + d * t
end

local function ease(t)
    return t < 0.5 and 2 * t * t or 1 - ((-2 * t + 2) ^ 2) / 2
end

-- keyframes = { { pos = vector3 (vehicle space), rz = deg, t = 0..1 }, ... }; attach to veh and animate
local function slide(ent, veh, keys, ms)
    local rot = (Tr.VehCfg(veh) or {}).rot or vector3(0.0, 0.0, 0.0)
    local start = GetGameTimer()
    ms = math.max(200, ms or 1400)
    while true do
        if not DoesEntityExist(ent) or not DoesEntityExist(veh) then return false end
        local t = math.min(1.0, (GetGameTimer() - start) / ms)
        local et = ease(t)
        local a, b = keys[1], keys[#keys]
        for i = 1, #keys - 1 do
            if et >= keys[i].t and et <= keys[i + 1].t then a, b = keys[i], keys[i + 1] break end
        end
        local span = math.max(0.0001, b.t - a.t)
        local k = math.min(1.0, math.max(0.0, (et - a.t) / span))
        local p = a.pos + (b.pos - a.pos) * k
        local rz = angleLerp(a.rz, b.rz, k)
        AttachEntityToEntity(ent, veh, 0, p.x, p.y, p.z, rot.x, rot.y, rz, false, false, false, false, 2, true)
        if t >= 1.0 then return true end
        Wait(0)
    end
end

local function insidePos(veh)
    local c = Tr.VehCfg(veh) or {}
    return c.pos or vector3(0.0, -1.6, -0.35), (c.rot or vector3(0.0, 0.0, 0.0)).z
end

local function rearDistance(veh)
    local c = Tr.VehCfg(veh) or {}
    if tonumber(c.rear) then return tonumber(c.rear) end
    local mn = GetModelDimensions(GetEntityModel(veh))
    return -mn.y
end

-- ════════════════════════════════════════════════════════════════════════
-- LOW MODEL SWAP
-- ════════════════════════════════════════════════════════════════════════

local function attachToMe(ent)
    local p = sc().push or {}
    local me = PlayerPedId()
    local pos = p.pos or vector3(0.0, 1.42, -0.97)
    local rot = p.rot or vector3(0.0, 0.0, 0.0)
    local bone = (p.bone and p.bone ~= 0) and GetPedBoneIndex(me, p.bone) or 0
    FreezeEntityPosition(ent, false)
    AttachEntityToEntity(ent, me, bone, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
end

-- replace the cot entity with the low / normal model (only when a low model exists)
local function maybeSwap(ent, low)
    local want = low and lowName() or (Config.Props and Config.Props[sc().model or 'stretcher'])
    if not lowName() or not want then return ent end
    local hash = GetHashKey(want)
    if GetEntityModel(ent) == hash or not IsModelInCdimage(hash) then return ent end
    if not Tr.Control(ent, 1500) then return ent end
    local oldNet = Tr.Net(ent)
    local c = GetEntityCoords(ent)
    local mine = S().pushing and S().pushing.ent == ent
    local attachedTo = GetEntityAttachedTo(ent)
    local newEnt, newNet = NZA.Props.Spawn(want, vector4(c.x, c.y, c.z, GetEntityHeading(ent)),
        { network = true, freeze = true, group = GROUP, fallbackKey = 'stretcher' })
    if newEnt == 0 or not newNet then return ent end
    if mine then
        DetachEntity(ent, false, false)
        attachToMe(newEnt)
    elseif attachedTo ~= 0 and IsEntityAVehicle(attachedTo) then
        local off = GetOffsetFromEntityGivenWorldCoords(attachedTo, c.x, c.y, c.z)
        local rz = GetEntityHeading(ent) - GetEntityHeading(attachedTo)
        AttachEntityToEntity(newEnt, attachedTo, 0, off.x, off.y, off.z, 0.0, 0.0, rz, false, false, false, false, 2, true)
    end
    local bag = Tr.StrBag(ent)
    if bag and bag.pk and bag.pk.kind == 'npc' then
        local npc = NZA.Target.Entity(bag.pk)
        if npc ~= 0 and Tr.Control(npc, 1000) then Tr.AttachToStretcher(npc, newEnt) end
    end
    local ok = Tr.Call('str:swap', oldNet, newNet)
    if not ok then
        NZA.Props.Delete(newEnt)
        if mine then attachToMe(ent) end
        return ent
    end
    if mine then
        S().pushing.ent, S().pushing.net = newEnt, newNet
    end
    return newEnt
end

-- ════════════════════════════════════════════════════════════════════════
-- PUSHING
-- ════════════════════════════════════════════════════════════════════════

local function pushAnim() return (sc().push or {}).anim end

local function context(cur)
    local ent = cur.ent
    local pos = GetEntityCoords(ent)
    local bag = Tr.StrBag(ent) or {}
    local reach = (sc().rearReach or 2.3) + 0.6
    local veh = St.Ambulance(reach)
    if bag.pid then
        if Tr.Bed and Tr.Bed.Nearest then
            local pt = Tr.Bed.Nearest(pos, Tr.Cfg('Beds').range or 3.0, true)
            if pt then return { kind = 'bed', pt = pt, label = Tr.L('p_transfer', Tr.Bed.Label(pt)) } end
        end
        if veh then
            local vb = Tr.VehBag(veh)
            if not vb or not vb.str or vb.str == cur.net then return { kind = 'load', veh = veh, label = Tr.L('p_load') } end
        end
    else
        if veh then
            local vb = Tr.VehBag(veh)
            if not vb or not vb.inside then return { kind = 'return', veh = veh, label = Tr.L('p_return') } end
        end
        local rack = rackNear(GetEntityCoords(PlayerPedId()), 2.8)
        if rack then return { kind = 'return', point = rack, label = Tr.L('p_return') } end
    end
    return nil
end

local function runContext(ctx)
    local cur = S().pushing
    if not cur or cur.acting then return end
    if ctx.kind == 'load' then
        St.Load(ctx.veh)
    elseif ctx.kind == 'return' then
        St.Store(cur.ent, ctx.veh, ctx.point)
    elseif ctx.kind == 'bed' then
        cur.acting = true
        Tr.Bed.Transfer(ctx.pt, cur.ent)
        if S().pushing == cur then cur.acting = false end
    end
end

local function loop()
    CreateThread(function()
        local keys = sc().keys or {}
        local relK = keys.release or { control = 47, label = 'G' }
        local ctxK = keys.context or { control = 38, label = 'E' }
        local hK = keys.height or { control = 74, label = 'H' }
        local push = sc().push or {}
        local nextCheck, ctx, shownCtx, shownLow = 0, nil, nil, nil
        while S().pushing do
            local cur = S().pushing
            local me = PlayerPedId()
            local now = GetGameTimer()
            for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
            DisableControlAction(0, 21, true)
            DisableControlAction(0, relK.control, true)
            DisableControlAction(0, ctxK.control, true)
            DisableControlAction(0, hK.control, true)
            SetPedMaxMoveBlendRatio(me, cur.low and (push.lowSpeed or 0.55) or (push.maxSpeed or 1.0))
            if now >= nextCheck then
                nextCheck = now + 300
                if not DoesEntityExist(cur.ent) or IsPedInAnyVehicle(me, false) or (NZA.Self and NZA.Self.State() ~= 'alive') then
                    St.Release(not DoesEntityExist(cur.ent))
                    break
                end
                if not cur.acting then
                    if not IsEntityAttachedToEntity(cur.ent, me) then
                        if Tr.Control(cur.ent, 200) then attachToMe(cur.ent) end
                    end
                    if not Tr.Playing(me, pushAnim()) then Tr.Play(me, pushAnim()) end
                end
                ctx = (not cur.acting) and context(cur) or nil
                if cur.low ~= shownLow then
                    shownLow = cur.low
                    NZA.UI.Prompt(PROMPT, { key = relK.label, label = Tr.L('p_release'), sub = Tr.L(cur.low and 'sub_push_low' or 'sub_push') })
                    NZA.UI.Prompt(PROMPT_H, { key = hK.label, label = Tr.L(cur.low and 'p_raise' or 'p_lower'), sub = Tr.L('sub_push') })
                end
                local label = ctx and ctx.label or nil
                if label ~= shownCtx then
                    shownCtx = label
                    if label then
                        NZA.UI.Prompt(PROMPT_CTX, { key = ctxK.label, label = label, sub = Tr.L('sub_push') })
                    else
                        NZA.UI.HidePrompt(PROMPT_CTX)
                    end
                end
            end
            cur = S().pushing
            if cur and not cur.acting then
                if IsDisabledControlJustPressed(0, relK.control) then
                    St.Release()
                    break
                elseif IsDisabledControlJustPressed(0, hK.control) then
                    CreateThread(function() St.ToggleHeight(cur.ent) end)
                elseif ctx and IsDisabledControlJustPressed(0, ctxK.control) then
                    local which = ctx
                    CreateThread(function() runContext(which) end)
                end
            end
            Wait(0)
        end
        NZA.UI.HidePrompt(PROMPT)
        NZA.UI.HidePrompt(PROMPT_H)
        NZA.UI.HidePrompt(PROMPT_CTX)
    end)
end

local function startPushing(ent, net, low)
    local me = PlayerPedId()
    Tr.Play(me, pushAnim(), { blendIn = 6.0 })
    attachToMe(ent)
    S().pushing = { ent = ent, net = net, low = low == true }
    loop()
end

function St.Grab(ent)
    if Tr.Busy() then return Tr.Toast(Tr.L('err_busy'), 'error') end
    local net = Tr.Net(ent)
    if not net then return end
    local ok, res = Tr.Call('str:push', net, true)
    if not ok then return Tr.Err(res) end
    if not Tr.Control(ent, 2000) then
        Tr.Call('str:push', net, false)
        return Tr.Err({ err = 'failed' })
    end
    -- step up to the foot-end handle
    local me = PlayerPedId()
    local h = GetEntityHeading(ent)
    local hy = (sc().push and sc().push.pos and sc().push.pos.y) or 1.42
    local handle = GetOffsetFromEntityInWorldCoords(ent, 0.0, -hy, 0.0)
    local myPos = GetEntityCoords(me)
    if #(vector2(myPos.x, myPos.y) - vector2(handle.x, handle.y)) > 0.35 then
        TaskGoStraightToCoord(me, handle.x, handle.y, myPos.z, 1.0, 1800, h, 0.15)
        local t = GetGameTimer() + 1900
        while GetGameTimer() < t do
            local p = GetEntityCoords(me)
            if #(vector2(p.x, p.y) - vector2(handle.x, handle.y)) < 0.3 then break end
            Wait(50)
        end
        ClearPedTasks(me)
    end
    SetEntityHeading(me, h)
    local grab = (sc().push or {}).grabMs or 450
    if grab > 0 then
        Tr.Play(me, pushAnim(), { blendIn = 4.0 })
        Wait(grab)
    end
    startPushing(ent, net, res.low)
end

function St.Release(silent)
    local cur = S().pushing
    if not cur then return end
    S().pushing = nil
    NZA.UI.HidePrompt(PROMPT)
    NZA.UI.HidePrompt(PROMPT_H)
    NZA.UI.HidePrompt(PROMPT_CTX)
    local me = PlayerPedId()
    Tr.StopAnim(me, pushAnim())
    local ent = cur.ent
    if DoesEntityExist(ent) and IsEntityAttachedToEntity(ent, me) and NetworkHasControlOfEntity(ent) then
        DetachEntity(ent, true, false)
        PlaceObjectOnGroundProperly(ent)
        SetEntityCollision(ent, true, true)
        FreezeEntityPosition(ent, true)
    end
    if not silent then CreateThread(function() Tr.Call('str:push', cur.net, false) end) end
end

function St.ToggleHeight(ent)
    ent = ent or (S().pushing and S().pushing.ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local cur = S().pushing
    if cur then cur.acting = true end
    local bag = Tr.StrBag(ent) or {}
    local low = not bag.low
    local lever = sc().lever
    local me = PlayerPedId()
    if lever then
        Tr.Play(me, lever, { flag = 48 })
        Wait(math.floor(lever.ms or 700))
    end
    local ok, res = Tr.Call('str:height', Tr.Net(ent), low)
    if lever then Tr.StopAnim(me, lever) end
    if not ok then
        if cur then cur.acting = false end
        return Tr.Err(res)
    end
    if cur and cur.ent == ent then cur.low = res.low end
    maybeSwap(ent, res.low)
    if cur then
        cur.acting = false
        if S().pushing == cur then Tr.Play(me, pushAnim()) end
    end
    Tr.Toast(res.msg, 'success')
end

RegisterNetEvent('nza:transport:pushEnd', function(net)
    local cur = S().pushing
    if cur and (net == nil or cur.net == net) then St.Release(true) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- TAKE / STORE
-- ════════════════════════════════════════════════════════════════════════

local function spawnCot(where)
    local ent, net = NZA.Props.Spawn(sc().model or 'stretcher', where,
        { network = true, freeze = true, collision = true, group = GROUP, fallbackKey = 'stretcher' })
    if ent == 0 or not net then
        if ent ~= 0 then NZA.Props.Delete(ent) end
        return 0, nil
    end
    SetNetworkIdCanMigrate(net, true)
    return ent, net
end

function St.TakeFromVehicle(veh)
    if Tr.Busy() then return Tr.Toast(Tr.L('err_busy'), 'error') end
    local vnet = Tr.Net(veh)
    if not vnet then return end
    local ok, res = Tr.Call('str:take', { veh = vnet })
    if not ok then return Tr.Err(res) end
    local me = PlayerPedId()
    local vh = GetEntityHeading(veh)
    local back = rearDistance(veh)
    -- step to the doors, facing away from the ambulance
    local stand = Tr.Rear(veh, 0.45)
    TaskGoStraightToCoord(me, stand.x, stand.y, stand.z, 1.0, 1500, (vh + 180.0) % 360.0, 0.2)
    openDoors(veh)
    local inPos, inRz = insidePos(veh)
    local w = GetOffsetFromEntityInWorldCoords(veh, inPos.x, inPos.y, inPos.z)
    local ent, net = spawnCot(vector4(w.x, w.y, w.z, (vh + inRz) % 360.0))
    if ent == 0 then
        Tr.Call('str:register', res.token, -1)
        return Tr.Err({ err = 'model' })
    end
    local okR, r2 = Tr.Call('str:register', res.token, net)
    if not okR then
        NZA.Props.Delete(ent)
        return Tr.Err(r2)
    end
    -- roll it out foot-end first, swing it round behind the ambulance
    local outW = Tr.Rear(veh, 0.45 + ((sc().push and sc().push.pos and sc().push.pos.y) or 1.42))
    local gz = Tr.Ground(outW, outW.z - 1.0)
    local outL = GetOffsetFromEntityGivenWorldCoords(veh, outW.x, outW.y, gz)
    local doorL = vector3(inPos.x * 0.5, -(back - 0.15), inPos.z)
    slide(ent, veh, {
        { pos = inPos, rz = inRz, t = 0.0 },
        { pos = doorL, rz = inRz, t = 0.5 },
        { pos = outL, rz = inRz + 180.0, t = 1.0 },
    }, (sc().load or {}).slideMs or 1400)
    DetachEntity(ent, true, false)
    closeDoors(veh, 300)
    ClearPedTasks(me)
    SetEntityHeading(me, (vh + 180.0) % 360.0)
    startPushing(ent, net, false)
end

function St.TakeFromPoint(point)
    if Tr.Busy() then return Tr.Toast(Tr.L('err_busy'), 'error') end
    local ok, res = Tr.Call('str:take', { point = point.id })
    if not ok then return Tr.Err(res) end
    local c = point.coords
    local ent, net = spawnCot(vector4(c.x, c.y, Tr.Ground(vector3(c.x, c.y, c.z), c.z), c.w or 0.0))
    if ent == 0 then
        Tr.Call('str:register', res.token, -1)
        return Tr.Err({ err = 'model' })
    end
    local okR, r2 = Tr.Call('str:register', res.token, net)
    if not okR then
        NZA.Props.Delete(ent)
        return Tr.Err(r2)
    end
    PlaceObjectOnGroundProperly(ent)
    St.Grab(ent)
end

function St.Store(ent, veh, point)
    local net = Tr.Net(ent)
    if not net then return end
    local cur = S().pushing
    if cur and cur.ent == ent then cur.acting = true end
    if veh then openDoors(veh) end
    local ok, res = Tr.Call('str:store', net, veh and Tr.Net(veh) or nil, point and point.id or nil)
    if not ok then
        if cur and S().pushing == cur then cur.acting = false end
        return Tr.Err(res)
    end
    if cur and cur.ent == ent then St.Release(true) end
    if veh then closeDoors(veh, 500) end
    Tr.Toast(res.msg, 'success')
end

-- ════════════════════════════════════════════════════════════════════════
-- LOAD / UNLOAD
-- ════════════════════════════════════════════════════════════════════════

function St.Load(veh)
    local cur = S().pushing
    if not cur or cur.acting then return end
    cur.acting = true
    local ok, res = Tr.Call('str:load', cur.net, Tr.Net(veh))
    if not ok then
        if S().pushing == cur then cur.acting = false end
        return Tr.Err(res)
    end
    -- the server already let go of the pusher: roll it in
    S().pushing = nil
    NZA.UI.HidePrompt(PROMPT)
    NZA.UI.HidePrompt(PROMPT_H)
    NZA.UI.HidePrompt(PROMPT_CTX)
    local me = PlayerPedId()
    local ent = cur.ent
    openDoors(veh)
    if Tr.Control(ent, 1500) then
        local wc = GetEntityCoords(ent)
        local relH = GetEntityHeading(ent) - GetEntityHeading(veh)
        DetachEntity(ent, false, false)
        FreezeEntityPosition(ent, false)
        local from = GetOffsetFromEntityGivenWorldCoords(veh, wc.x, wc.y, wc.z)
        local inPos, inRz = insidePos(veh)
        local back = rearDistance(veh)
        local doorL = vector3(inPos.x * 0.5, -(back - 0.15), inPos.z)
        local lip = vector3(inPos.x * 0.5, -(back + 0.35), inPos.z - 0.05)
        slide(ent, veh, {
            { pos = from, rz = relH, t = 0.0 },
            { pos = lip, rz = inRz, t = 0.35 },
            { pos = doorL, rz = inRz, t = 0.55 },
            { pos = inPos, rz = inRz, t = 1.0 },
        }, (sc().load or {}).slideMs or 1400)
        if res.low then maybeSwap(ent, true) end
    end
    Tr.StopAnim(me, pushAnim())
    closeDoors(veh, 700)
    Tr.Toast(res.msg, 'success')
end

function St.Unload(veh)
    if Tr.Busy() then return Tr.Toast(Tr.L('err_busy'), 'error') end
    local ok, res = Tr.Call('str:unload', Tr.Net(veh))
    if not ok then return Tr.Err(res) end
    local ent = Tr.Ent(res.net, 2000)
    if ent == 0 or not Tr.Control(ent, 2000) then
        Tr.Call('str:push', res.net, false)
        return Tr.Err({ err = 'failed' })
    end
    local me = PlayerPedId()
    local vh = GetEntityHeading(veh)
    local stand = Tr.Rear(veh, 0.45)
    TaskGoStraightToCoord(me, stand.x, stand.y, stand.z, 1.0, 1500, (vh + 180.0) % 360.0, 0.2)
    openDoors(veh)
    ent = maybeSwap(ent, false)
    local inPos, inRz = insidePos(veh)
    local back = rearDistance(veh)
    local outW = Tr.Rear(veh, 0.45 + ((sc().push and sc().push.pos and sc().push.pos.y) or 1.42))
    local gz = Tr.Ground(outW, outW.z - 1.0)
    local outL = GetOffsetFromEntityGivenWorldCoords(veh, outW.x, outW.y, gz)
    local cur = GetEntityCoords(ent)
    local fromL = GetOffsetFromEntityGivenWorldCoords(veh, cur.x, cur.y, cur.z)
    local doorL = vector3(inPos.x * 0.5, -(back - 0.15), inPos.z)
    slide(ent, veh, {
        { pos = fromL, rz = inRz, t = 0.0 },
        { pos = doorL, rz = inRz, t = 0.5 },
        { pos = outL, rz = inRz + 180.0, t = 1.0 },
    }, (sc().load or {}).slideMs or 1400)
    DetachEntity(ent, true, false)
    closeDoors(veh, 400)
    ClearPedTasks(me)
    SetEntityHeading(me, (vh + 180.0) % 360.0)
    startPushing(ent, Tr.Net(ent) or res.net, res.low)
    Tr.Toast(res.msg, 'success')
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT ON / OFF
-- ════════════════════════════════════════════════════════════════════════

function St.PlacePatient(ent, patient, target)
    ent = ent or St.FreeNear(GetEntityCoords(patient))
    if not ent then
        Tr.Err({ err = 'no_stretcher' })
        return false
    end
    local net = Tr.Net(ent)
    if not net then return false end
    if target.kind == 'npc' then Tr.Control(patient, 1500) end
    local me = PlayerPedId()
    local carrying = S().carrying ~= nil
    local pick = Tr.Cfg('Carry').pickup
    if not carrying and not S().pushing and type(pick) == 'table' then
        TaskTurnPedToFaceEntity(me, patient, 500)
        Wait(400)
        Tr.Play(me, pick, { flag = 0 })
        Wait(math.floor((pick.ms or 900) * 0.7))
    end
    local ok, res = Tr.Call('str:place', net, target)
    if type(pick) == 'table' then Tr.StopAnim(me, pick) end
    if not ok then
        Tr.Err(res)
        return false
    end
    if res.npc then Tr.ApplyNpc(res.target or target, res.cmd) end
    return true
end

function St.TakeOff(ent)
    if not ent or ent == 0 then return end
    local net = Tr.Net(ent)
    local bag = Tr.StrBag(ent) or {}
    if bag.pk and bag.pk.kind == 'npc' then
        local npc = NZA.Target.Entity(bag.pk)
        if npc ~= 0 then Tr.Control(npc, 1500) end
    end
    local ok, res = Tr.Call('str:off', net)
    if not ok then return Tr.Err(res) end
    if res.npc then Tr.ApplyNpc(res.target, res.cmd) end
end

-- ════════════════════════════════════════════════════════════════════════
-- TARGETS
-- ════════════════════════════════════════════════════════════════════════

local function canUse()
    return sc().enabled ~= false and NZA.Perm(perm())
end

local function nearestFreePatient(coords, range)
    local best, bestT, bestD = nil, nil, range
    local me = PlayerPedId()
    local function consider(ped)
        if ped == me or not DoesEntityExist(ped) then return end
        local d = #(coords - GetEntityCoords(ped))
        if d > bestD then return end
        local t = NZA.Target.FromEntity(ped)
        if not t then return end
        local st = NZA.Target.State(ped)
        if type(st) == 'table' and (st.carried or st.stretcher or st.bag) then return end
        if Tr.Held(Tr.Bag(ped)) then return end
        best, bestT, bestD = ped, t, d
    end
    for _, pl in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pl)) end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and Entity(ped).state.nza ~= nil then consider(ped) end
    end
    return best, bestT
end

local function strOptions()
    local d = sc().distance or 2.4
    return {
        {
            name = 'nza_str_push', label = Tr.L('str_push'), icon = 'hand', distance = d, order = 1,
            canInteract = function(ent)
                if not canUse() or Tr.Busy() then return false end
                local b = Tr.StrBag(ent)
                return b ~= nil and not b.veh and not b.pusher
            end,
            onSelect = function(ent) CreateThread(function() St.Grab(ent) end) end,
        },
        {
            name = 'nza_str_height', label = Tr.L('str_height'), icon = 'arrow-down', distance = d, order = 2,
            canInteract = function(ent)
                if not canUse() or (Tr.Busy() and Tr.Busy() ~= 'push') then return false end
                local b = Tr.StrBag(ent)
                return b ~= nil and not b.veh and pusherOk(b)
            end,
            onSelect = function(ent) CreateThread(function() St.ToggleHeight(ent) end) end,
        },
        {
            name = 'nza_str_place', label = Tr.L('str_place'), icon = 'bed', distance = d, order = 3,
            canInteract = function(ent)
                if not canUse() or (Tr.Busy() and Tr.Busy() ~= 'push' and Tr.Busy() ~= 'carry') then return false end
                local b = Tr.StrBag(ent)
                if not b or b.pid or b.veh or not pusherOk(b) then return false end
                if S().carrying then return true end
                return nearestFreePatient(GetEntityCoords(ent), 3.5) ~= nil
            end,
            onSelect = function(ent)
                CreateThread(function()
                    local cur = S().carrying
                    if cur then
                        if St.PlacePatient(ent, cur.ent, cur.target) and Tr.Carry then Tr.Carry.End() end
                        return
                    end
                    local ped, t = nearestFreePatient(GetEntityCoords(ent), 3.5)
                    if ped then St.PlacePatient(ent, ped, t) end
                end)
            end,
        },
        {
            name = 'nza_str_off', label = Tr.L('take_off'), icon = 'bed', distance = d, order = 4,
            canInteract = function(ent)
                if not canUse() or Tr.Busy() then return false end
                local b = Tr.StrBag(ent)
                return b ~= nil and b.pid ~= nil and not b.veh and pusherOk(b)
            end,
            onSelect = function(ent) CreateThread(function() St.TakeOff(ent) end) end,
        },
        {
            name = 'nza_str_tobed', label = Tr.L('str_tobed'), icon = 'bed', distance = d, order = 5,
            canInteract = function(ent)
                if not canUse() or (Tr.Busy() and Tr.Busy() ~= 'push') or not Tr.Bed or not Tr.Bed.Nearest then return false end
                local b = Tr.StrBag(ent)
                if not b or not b.pid or b.veh or not pusherOk(b) then return false end
                return Tr.Bed.Nearest(GetEntityCoords(ent), Tr.Cfg('Beds').range or 3.0, true) ~= nil
            end,
            onSelect = function(ent)
                CreateThread(function()
                    local pt = Tr.Bed.Nearest(GetEntityCoords(ent), Tr.Cfg('Beds').range or 3.0, true)
                    if pt then Tr.Bed.Transfer(pt, ent) end
                end)
            end,
        },
        {
            name = 'nza_str_return', label = Tr.L('str_return'), icon = 'trunk', distance = d, order = 6,
            canInteract = function(ent)
                if not canUse() or (Tr.Busy() and Tr.Busy() ~= 'push') then return false end
                local b = Tr.StrBag(ent)
                if not b or b.pid or b.veh or not pusherOk(b) then return false end
                return St.Ambulance((sc().rearReach or 2.3) + 3.0) ~= nil or rackNear(GetEntityCoords(ent), 4.0) ~= nil
            end,
            onSelect = function(ent)
                CreateThread(function()
                    local veh = St.Ambulance((sc().rearReach or 2.3) + 3.0)
                    local rack = not veh and rackNear(GetEntityCoords(ent), 4.0) or nil
                    St.Store(ent, veh, rack)
                end)
            end,
        },
    }
end

local function vehOptions()
    local reach = sc().rearReach or 2.3
    return {
        {
            name = 'nza_amb_take', label = Tr.L('str_take'), icon = 'bed', distance = 6.0, order = 1,
            canInteract = function(veh)
                if not canUse() or Tr.Busy() or not Tr.NearRear(veh, reach) then return false end
                local vb = Tr.VehBag(veh)
                return not vb or not vb.str
            end,
            onSelect = function(veh) CreateThread(function() St.TakeFromVehicle(veh) end) end,
        },
        {
            name = 'nza_amb_load', label = Tr.L('str_load'), icon = 'truck', distance = 6.0, order = 2,
            canInteract = function(veh)
                local cur = S().pushing
                if not canUse() or not cur or not Tr.NearRear(veh, reach + 0.6) then return false end
                local vb = Tr.VehBag(veh)
                return not vb or not vb.str or vb.str == cur.net
            end,
            onSelect = function(veh) CreateThread(function() St.Load(veh) end) end,
        },
        {
            name = 'nza_amb_unload', label = Tr.L('str_unload'), icon = 'truck', distance = 6.0, order = 3,
            canInteract = function(veh)
                if not canUse() or Tr.Busy() or not Tr.NearRear(veh, reach) then return false end
                local vb = Tr.VehBag(veh)
                return vb ~= nil and vb.str ~= nil and vb.inside == true
            end,
            onSelect = function(veh) CreateThread(function() St.Unload(veh) end) end,
        },
        {
            name = 'nza_amb_return', label = Tr.L('str_return'), icon = 'trunk', distance = 6.0, order = 4,
            canInteract = function(veh)
                if not canUse() or not Tr.NearRear(veh, reach + 0.6) then return false end
                local vb = Tr.VehBag(veh)
                if vb and vb.inside then return false end
                local cur = S().pushing
                if cur then
                    local b = Tr.StrBag(cur.ent)
                    return b ~= nil and not b.pid
                end
                if Tr.Busy() then return false end
                return emptyNear(GetEntityCoords(PlayerPedId()), 4.0) ~= nil
            end,
            onSelect = function(veh)
                CreateThread(function()
                    local cur = S().pushing
                    local ent = cur and cur.ent or emptyNear(GetEntityCoords(PlayerPedId()), 4.0)
                    if ent then St.Store(ent, veh, nil) end
                end)
            end,
        },
    }
end

CreateThread(function()
    Wait(500)
    if not Bridge or not Bridge.Target then return end
    Bridge.Target.Model(St.Models(), strOptions())
    local names = {}
    for name in pairs(sc().vehicles or {}) do names[#names + 1] = name end
    if #names > 0 then Bridge.Target.Model(names, vehOptions()) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- HOSPITAL POINT: STRETCHER RACK
-- ════════════════════════════════════════════════════════════════════════

NZA.Points.RegisterType('stretcher', {
    label = Tr.L('point_stretcher'), icon = 'bed', needsHeading = true, radius = 1.3, distance = 2.4,
    target = {
        {
            name = 'take', label = Tr.L('str_take'), icon = 'bed', perm = (Config.Transport and Config.Transport.perm) or 'transport',
            canInteract = function() return sc().enabled ~= false and not Tr.Busy() end,
            onSelect = function(point) St.TakeFromPoint(point) end,
        },
        {
            name = 'return', label = Tr.L('str_return'), icon = 'trunk', perm = (Config.Transport and Config.Transport.perm) or 'transport',
            canInteract = function(point)
                local cur = S().pushing
                if cur then
                    local b = Tr.StrBag(cur.ent)
                    return b ~= nil and not b.pid
                end
                if Tr.Busy() then return false end
                local c = point.coords
                return emptyNear(vector3(c.x, c.y, c.z), 4.0) ~= nil
            end,
            onSelect = function(point)
                local cur = S().pushing
                local c = point.coords
                local ent = cur and cur.ent or emptyNear(vector3(c.x, c.y, c.z), 4.0)
                if ent then St.Store(ent, nil, point) end
            end,
        },
    },
})

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL (parent 'stretcher')
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

local function radialOn() return Tr.Cfg().radial ~= false and canUse() end
local function radialRange() return Tr.Cfg().radialRange or 3.0 end

local function nearestCot(filter)
    for _, s in ipairs(St.All(GetEntityCoords(PlayerPedId()), radialRange())) do
        if not filter or filter(s.bag, s.ent) then return s.ent end
    end
    return nil
end

local function radial(def)
    def.parent = 'stretcher'
    def.perm = (Config.Transport and Config.Transport.perm) or 'transport'
    table.insert(NZA.RadialItems, def)
end

radial({
    id = 'tr_str_take', label = Tr.L('str_take'), icon = 'bed', order = 1,
    canShow = function()
        if not radialOn() or Tr.Busy() then return false end
        local veh = St.Ambulance(sc().rearReach or 2.3)
        if veh then
            local vb = Tr.VehBag(veh)
            return not vb or not vb.str
        end
        return rackNear(GetEntityCoords(PlayerPedId()), 2.5) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local veh = St.Ambulance(sc().rearReach or 2.3)
            if veh then return St.TakeFromVehicle(veh) end
            local rack = rackNear(GetEntityCoords(PlayerPedId()), 2.5)
            if rack then St.TakeFromPoint(rack) end
        end)
    end,
})

radial({
    id = 'tr_str_push', label = Tr.L('str_push'), icon = 'hand', order = 2,
    canShow = function()
        return radialOn() and not Tr.Busy() and nearestCot(function(b) return not b.veh and not b.pusher end) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ent = nearestCot(function(b) return not b.veh and not b.pusher end)
            if ent then St.Grab(ent) end
        end)
    end,
})

radial({
    id = 'tr_str_release', label = Tr.L('str_release'), icon = 'hand', order = 3,
    canShow = function() return radialOn() and S().pushing ~= nil end,
    onSelect = function() St.Release() end,
})

radial({
    id = 'tr_str_height', label = Tr.L('str_height'), icon = 'arrow-down', order = 4,
    canShow = function()
        if not radialOn() then return false end
        if S().pushing then return true end
        return not Tr.Busy() and nearestCot(function(b) return not b.veh and pusherOk(b) end) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ent = S().pushing and S().pushing.ent or nearestCot(function(b) return not b.veh and pusherOk(b) end)
            if ent then St.ToggleHeight(ent) end
        end)
    end,
})

radial({
    id = 'tr_str_load', label = Tr.L('str_load'), icon = 'truck', order = 5,
    canShow = function()
        return radialOn() and S().pushing ~= nil and St.Ambulance((sc().rearReach or 2.3) + 0.6) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local veh = St.Ambulance((sc().rearReach or 2.3) + 0.6)
            if veh then St.Load(veh) end
        end)
    end,
})

radial({
    id = 'tr_str_unload', label = Tr.L('str_unload'), icon = 'truck', order = 6,
    canShow = function()
        if not radialOn() or Tr.Busy() then return false end
        local veh = St.Ambulance(sc().rearReach or 2.3)
        local vb = veh and Tr.VehBag(veh)
        return vb ~= nil and vb.str ~= nil and vb.inside == true
    end,
    onSelect = function()
        CreateThread(function()
            local veh = St.Ambulance(sc().rearReach or 2.3)
            if veh then St.Unload(veh) end
        end)
    end,
})

radial({
    id = 'tr_str_return', label = Tr.L('str_return'), icon = 'trunk', order = 7,
    canShow = function()
        if not radialOn() then return false end
        local cur = S().pushing
        if not cur then return false end
        local b = Tr.StrBag(cur.ent)
        if not b or b.pid then return false end
        return St.Ambulance((sc().rearReach or 2.3) + 0.6) ~= nil or rackNear(GetEntityCoords(PlayerPedId()), 3.0) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local cur = S().pushing
            if not cur then return end
            local veh = St.Ambulance((sc().rearReach or 2.3) + 0.6)
            St.Store(cur.ent, veh, not veh and rackNear(GetEntityCoords(PlayerPedId()), 3.0) or nil)
        end)
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if S().pushing then
        local ent = S().pushing.ent
        S().pushing = nil
        if DoesEntityExist(ent) then DetachEntity(ent, true, false) end
        Tr.StopAnim(PlayerPedId(), pushAnim())
    end
end)
