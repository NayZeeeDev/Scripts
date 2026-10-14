--[[
    NAYZEEE AMBULANCE - Body bag & morgue (client)

    Medic side
      Patient option 'Place in body bag' (dead players / NPC patients, perm Config.Medbag.Body.perm,
      the body bag item) → NZA.Proc 'bodybag': kneel, unfold, roll the body in, zip it (ox_lib
      progress per step; easy mode = one bar). Dead ambient NPCs that are not patients yet get the
      same option through Bridge.Target.Ped (nza:medbag:body:adopt first).
      Options on the bag prop (NZA.Interact, bag = true): Carry body bag · Open body bag (players) ·
      Read the toe tag · Deliver to the morgue (bag near a morgue point).
      Carrying: [G] put it down, [E] context = deliver at a morgue / lay it on a free stretcher
      (transport module) / put it in the vehicle behind you. Near a vehicle with body bags inside:
      [E] take one out.
    Patient side (the bagged player)
      Player state bag 'nzaInBag' = { id, net, mode, off }: the ped is hidden and attached to the
      bag prop (or the vehicle it was loaded into). Released when the bag is opened, delivered
      (respawn), the patient is revived or respawns.
    Point type 'morgue' (placed with the hospital builder) with a 'Deliver body bag' option.

      NZA.Medbag.BagBody(entity, target)   NZA.Medbag.CarryBody(id)   NZA.Medbag.DropBody()
      NZA.Medbag.Deliver(pointId, id?)     NZA.Medbag.BodyCarrying() → id | nil

    Callbacks used: nza:medbag:body:adopt / carry / drop / stretcher / vehicle / open / deliver / tag,
                    nza:medbag:held; procedure 'bodybag' (NZA.Proc)
    Net events handled: nza:medbag:body:carryEnd (), nza:medbag:body:release (coords, heading, teleport),
                        nza:wounded:respawn (let go of the bag before the respawn teleport)
    Registries: NZA.Interact nza_bodybag / nza_bodybag_carry / nza_bodybag_open / nza_bodybag_tag /
                nza_bodybag_deliver, Bridge.Target.Ped nza_bodybag_ambient, point type 'morgue',
                NZA.RadialItems bb_place (patient) / bb_drop / bb_unload
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Medbag = NZA.Medbag or {}
local MB = NZA.Medbag

local B_ = { body = nil, busy = false, inBag = false }
MB.BodyState = B_

local PROMPT_DROP, PROMPT_CTX, PROMPT_UNLOAD = 'nza_bb_drop', 'nza_bb_ctx', 'nza_bb_unload'
local BLOCK = { 21, 22, 23, 24, 25, 36, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function B(section)
    local b = (Config.Medbag or {}).Body or {}
    if not section then return b end
    return b[section] or {}
end
local function M() return (Config.Medbag or {}).Morgue or {} end
local function L(key, ...) return NZA.L('medbag.' .. key, ...) end
local function perm() return B().perm or 'bodybag' end

local function toast(msg, kind, icon, title)
    NZA.UI.Toast({ title = title or L('bb_progress'), message = msg, type = kind or 'info', icon = icon, duration = kind == 'error' and 3500 or 3200 })
end

local function errText(res)
    if type(res) == 'table' and type(res.msg) == 'string' then return res.msg end
    local code = type(res) == 'table' and res.err or res
    if type(code) == 'string' then
        local k = 'medbag.bb_err_' .. code
        local v = NZA.L(k)
        if v ~= k then return v end
        k = 'core_client.err.' .. code
        v = NZA.L(k)
        if v ~= k then return v end
    end
    return L('bb_err_failed')
end
local function err(res) toast(errText(res), 'error') end

local function down() return NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() or false end
local function plainV(v) return v and { x = v.x, y = v.y, z = v.z } or nil end
local function mySid() return GetPlayerServerId(PlayerId()) end

function MB.BodyCarrying() return B_.body and B_.body.id or nil end

local function handsFull()
    if B_.body then return true end
    if MB.Carrying and MB.Carrying() then return true end
    return false
end

local function bodyOf(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) or not NetworkGetEntityIsNetworked(ent) then return nil end
    local st = Entity(ent).state.nzaBody
    if type(st) == 'table' and type(st.id) == 'string' then return st end
    return nil
end

local function hasBagItem()
    if B().requireItem == false then return true end
    local name = Config.Items and Config.Items.bodybag
    if not name then return true end
    return Bridge and Bridge.Inv and Bridge.Inv.Has and Bridge.Inv.Has(name, 1) or false
end

local function playOnce(a)
    if type(a) ~= 'table' or not a.dict then return end
    local ped = PlayerPedId()
    local ok, token = NZA.Anim.Play(ped, a.dict, a.clip, { flag = a.flag or 0 })
    Wait(math.floor(tonumber(a.ms) or 900))
    if ok then NZA.Anim.Stop(ped, { token = token }) end
end

local function progress(ms, label, anim)
    local data = {
        duration = math.max(500, math.floor(ms)), label = label, useWhileDead = false, canCancel = true, allowRagdoll = false,
        disable = { move = true, car = true, combat = true, sprint = true },
        anim = anim and anim.dict and { dict = anim.dict, clip = anim.clip, flag = anim.flag or 1 } or nil,
    }
    if Config.EasyMode and Config.EasyMode.style == 'circle' then
        data.position = 'bottom'
        return lib.progressCircle(data)
    end
    return lib.progressBar(data)
end

-- ground under a body (bag position) + its heading
local function bodySpot(ent)
    local c = GetEntityCoords(ent)
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 0.6, false)
    if not found or math.abs(z - c.z) > 1.6 then z = c.z - 0.2 end
    return vector3(c.x, c.y, z), GetEntityHeading(ent)
end

-- ════════════════════════════════════════════════════════════════════════
-- BAGGING
-- ════════════════════════════════════════════════════════════════════════

function MB.BagBody(entity, target)
    if B_.busy then return end
    if handsFull() then return toast(L('bb_err_hands'), 'error') end
    if not hasBagItem() then return toast(L('bb_err_no_item'), 'error') end
    B_.busy = true
    local cfg = B()
    local total = tonumber(cfg.time) or 9
    local steps = cfg.steps or {}
    local ok, res = NZA.Proc.Run('bodybag', target, {}, function(ctx)
        local ped = PlayerPedId()
        local body = NZA.Target.Entity(target)
        if body ~= 0 then
            TaskTurnPedToFaceEntity(ped, body, 700)
            Wait(700)
        end
        if #steps == 0 then
            if not progress(total * 1000, L('bb_progress'), { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 }) then return ctx.abort('cancel') end
        else
            for _, st in ipairs(steps) do
                local share = tonumber(st.share) or (1 / #steps)
                if ctx.done() then return end
                if not progress(total * share * 1000, L(st.label or 'bb_progress'), st) then return ctx.abort('cancel') end
            end
        end
        if ctx.done() then return end
        local at, h = nil, nil
        body = NZA.Target.Entity(target)
        if body ~= 0 then at, h = bodySpot(body) end
        ctx.finish({ score = 100, at = plainV(at), heading = h })
    end, { label = L('bb_progress'), silent = true })
    B_.busy = false
    if ok then
        toast((type(res) == 'table' and res.msg) or L('bb_ok_bagged', '?'), 'success', 'skull')
    elseif res ~= 'cancel' and res ~= 'silent' then
        err(res)
    end
end

-- a dead ambient NPC (not a patient yet)
local function bagAmbient(ent)
    if B_.busy or not DoesEntityExist(ent) then return end
    local net = NetworkGetNetworkIdFromEntity(ent)
    local res = lib.callback.await('nza:medbag:body:adopt', false, net)
    if type(res) ~= 'table' or not res.ok then return err(res) end
    -- wait for the patient state bag so the procedure resolves it
    local t = GetGameTimer()
    while Entity(ent).state.nza == nil and GetGameTimer() - t < 1500 do Wait(50) end
    MB.BagBody(ent, res.target)
end

-- ════════════════════════════════════════════════════════════════════════
-- CARRYING
-- ════════════════════════════════════════════════════════════════════════

local function endBodyCarry()
    local cur = B_.body
    B_.body = nil
    NZA.UI.HidePrompt(PROMPT_DROP)
    NZA.UI.HidePrompt(PROMPT_CTX)
    local ped = PlayerPedId()
    if cur and cur.animToken then NZA.Anim.Stop(ped, { token = cur.animToken }) end
    NZA.Props.Clear('medbag_body_hand')
end

-- morgue points (hospital builder) + config fallbacks
local function morgues()
    local out = {}
    if NZA.Points and NZA.Points.All then
        for _, p in ipairs(NZA.Points.All('morgue') or {}) do
            if p.coords then out[#out + 1] = { id = p.id, coords = vector3(p.coords.x, p.coords.y, p.coords.z), label = p.label } end
        end
    end
    if #out == 0 then
        for i, f in ipairs(M().fallback or {}) do
            if f.coords then out[#out + 1] = { id = 'fb:' .. i, coords = vector3(f.coords.x, f.coords.y, f.coords.z), label = f.label, fallback = true } end
        end
    end
    return out
end

local function nearestMorgue(pos, range)
    local best, bestD = nil, range
    for _, m in ipairs(morgues()) do
        local d = #(pos - m.coords)
        if d <= bestD then best, bestD = m, d end
    end
    return best
end
MB.NearestMorgue = nearestMorgue

local function freeCot(pos, range)
    if B('Stretcher').enabled == false then return nil end
    local best, bestD = nil, range
    local me = mySid()
    for _, obj in ipairs(GetGamePool('CObject')) do
        if NetworkGetEntityIsNetworked(obj) then
            local st = Entity(obj).state.nzaStr
            if type(st) == 'table' and not st.pid and not st.veh and (not st.pusher or st.pusher == me) and Entity(obj).state.nzaBodyOn == nil then
                local d = #(pos - GetEntityCoords(obj))
                if d <= bestD then best, bestD = obj, d end
            end
        end
    end
    return best
end

local function vehicleOk(veh)
    local vc = B('Vehicle')
    local class = GetVehicleClass(veh)
    for _, c in ipairs(vc.blockedClasses or {}) do if c == class then return false end end
    if type(vc.models) == 'table' and #vc.models > 0 then
        local h = GetEntityModel(veh)
        for _, m in ipairs(vc.models) do if GetHashKey(m) == h then return true end end
        return false
    end
    return true
end

local function vehicleRear(veh)
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 0.35, 0.0)
end

-- the vehicle whose back you stand at; wantBodies = only vehicles with body bags inside
local function rearVehicle(pos, range, wantBodies)
    local vc = B('Vehicle')
    if vc.enabled == false then return nil end
    local best, bestD = nil, range
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if #(pos - GetEntityCoords(veh)) < 9.0 and NetworkGetEntityIsNetworked(veh) and vehicleOk(veh) and GetPedInVehicleSeat(veh, -1) ~= PlayerPedId() then
            local d = #(pos - vehicleRear(veh))
            if d <= bestD then
                local st = Entity(veh).state.nzaBodies
                local n = type(st) == 'table' and (tonumber(st.n) or 0) or 0
                if wantBodies then
                    if n > 0 then best, bestD = veh, d end
                elseif n < (tonumber(vc.max) or 2) then
                    best, bestD = veh, d
                end
            end
        end
    end
    return best
end

local function openDoors(veh, open)
    if B('Vehicle').openDoor == false or not DoesEntityExist(veh) then return end
    local doors = { 5 }
    if GetIsDoorValid(veh, 2) and GetIsDoorValid(veh, 3) and not GetIsDoorValid(veh, 5) then doors = { 2, 3 } end
    for _, d in ipairs(doors) do
        if open then SetVehicleDoorOpen(veh, d, false, false) else SetVehicleDoorShut(veh, d, false) end
    end
end

-- what [E] does right now while carrying
local function context()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local m = nearestMorgue(pos, (tonumber(M().range) or 4.0))
    if m then return { kind = 'morgue', point = m, label = L('bb_p_morgue'), sub = m.label or L('morgue') } end
    local cot = freeCot(pos, tonumber(B('Stretcher').range) or 2.6)
    if cot then return { kind = 'stretcher', entity = cot, label = L('bb_p_stretcher') } end
    local veh = rearVehicle(pos, tonumber(B('Vehicle').range) or 3.0, false)
    if veh then return { kind = 'vehicle', entity = veh, label = L('bb_p_vehicle') } end
    return nil
end

local function bodyCarryLoop()
    local c = B('Carry')
    local keys = c.keys or {}
    local dropK = keys.drop or { control = 47, label = 'G' }
    local ctxK = keys.context or { control = 38, label = 'E' }
    local maxSpeed = tonumber(c.maxSpeed) or 1.0
    local ctx, nextCtx, lastAnim, lastMarker = nil, 0, 0, nil
    NZA.UI.Prompt(PROMPT_DROP, { key = dropK.label, label = L('bb_p_drop'), sub = L('bb_sub', B_.body and B_.body.name or '') })
    while B_.body do
        local ped = PlayerPedId()
        for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
        if maxSpeed <= 1.0 then SetPedMaxMoveBlendRatio(ped, 1.0) end
        DisableControlAction(0, dropK.control, true)
        DisableControlAction(0, ctxK.control, true)

        local now = GetGameTimer()
        if c.anim and now - lastAnim > 1000 then
            lastAnim = now
            if not IsEntityPlayingAnim(ped, c.anim.dict, c.anim.clip, 3) then
                local okA, token = NZA.Anim.Play(ped, c.anim.dict, c.anim.clip, { flag = c.anim.flag or 49 })
                if okA and B_.body then B_.body.animToken = token end
            end
        end
        if now >= nextCtx then
            nextCtx = now + 250
            ctx = context()
            if ctx then
                NZA.UI.Prompt(PROMPT_CTX, { key = ctxK.label, label = ctx.label, sub = ctx.sub })
            else
                NZA.UI.HidePrompt(PROMPT_CTX)
            end
            lastMarker = nil
            if M().fallbackMarker ~= false then
                for _, m in ipairs(morgues()) do
                    if m.fallback and #(GetEntityCoords(ped) - m.coords) < 35.0 then lastMarker = m.coords break end
                end
            end
        end
        if lastMarker then
            DrawMarker(1, lastMarker.x, lastMarker.y, lastMarker.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                (tonumber(M().range) or 4.0) * 0.5, (tonumber(M().range) or 4.0) * 0.5, 0.35, 8, 175, 162, 90, false, false, 2, false, nil, nil, false)
        end

        if not B_.busy and not NZA.UI.Top() then
            if IsDisabledControlJustPressed(0, dropK.control) then
                CreateThread(MB.DropBody)
            elseif ctx and IsDisabledControlJustPressed(0, ctxK.control) then
                local cur = ctx
                CreateThread(function()
                    if cur.kind == 'morgue' then MB.Deliver(cur.point.id, B_.body and B_.body.id)
                    elseif cur.kind == 'stretcher' then MB.BodyToStretcher(cur.entity)
                    elseif cur.kind == 'vehicle' then MB.BodyToVehicle(cur.entity) end
                end)
            end
        end
        Wait(0)
    end
end

local function spawnHeld(model, attach, group, token)
    local ent, net = NZA.Props.Spawn(model, { attach = attach }, { network = true, group = group, collision = false })
    if ent == 0 or not net then return ent, false end
    local res = lib.callback.await('nza:medbag:held', false, token, net)
    return ent, type(res) == 'table' and res.ok
end

function MB.CarryBody(id)
    if B_.busy then return end
    if handsFull() then return toast(L('bb_err_hands'), 'error') end
    if down() or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    B_.busy = true
    local res = lib.callback.await('nza:medbag:body:carry', false, id)
    if type(res) ~= 'table' or not res.ok then
        B_.busy = false
        return err(res)
    end
    local c = B('Carry')
    playOnce(c.pickup)
    local ped = PlayerPedId()
    B_.body = { id = res.id or id, name = res.name }
    local ent = spawnHeld(res.model, { entity = ped, bone = c.bone or 0, pos = c.pos or vector3(0.24, 0.02, 0.62), rot = c.rot or vector3(0.0, 0.0, 0.0) }, 'medbag_body_hand', res.token)
    if B_.body then B_.body.ent = ent end
    if c.anim then
        local okA, token = NZA.Anim.Play(ped, c.anim.dict, c.anim.clip, { flag = c.anim.flag or 49 })
        if okA and B_.body then B_.body.animToken = token end
    end
    B_.busy = false
    CreateThread(bodyCarryLoop)
end

function MB.DropBody()
    if not B_.body or B_.busy then return end
    local T = NZA.Transport
    if T and T.Bay and T.Bay.Active and T.Bay.Active() then return toast(L('err_bad_spot'), 'error') end
    B_.busy = true
    local c = B('Carry')
    local ped = PlayerPedId()
    local coords, h
    if MB.GroundSpot then coords, h = MB.GroundSpot(c.putAhead or 0.9) end
    coords = coords or GetEntityCoords(ped)
    h = h or GetEntityHeading(ped)
    playOnce(c.pickup)
    local res = lib.callback.await('nza:medbag:body:drop', false, plainV(coords), (h + (tonumber(c.dropHeading) or 90.0)) % 360.0)
    B_.busy = false
    if type(res) ~= 'table' or not res.ok then return err(res) end
    endBodyCarry()
    toast(res.msg or L('bb_ok_down'), 'success', 'skull')
end

function MB.BodyToStretcher(cot)
    if not B_.body or B_.busy or not DoesEntityExist(cot) then return end
    B_.busy = true
    local res = lib.callback.await('nza:medbag:body:stretcher', false, NetworkGetNetworkIdFromEntity(cot))
    if type(res) ~= 'table' or not res.ok then
        B_.busy = false
        return err(res)
    end
    endBodyCarry()
    local st = B('Stretcher')
    playOnce(B('Carry').pickup)
    if DoesEntityExist(cot) then
        spawnHeld(res.model, { entity = cot, bone = 0, pos = st.pos or vector3(0.0, 0.0, 0.93), rot = st.rot or vector3(0.0, 0.0, 0.0) }, 'medbag_body_cot', res.token)
    end
    B_.busy = false
    toast(res.msg or L('bb_ok_stretcher'), 'success', 'stretcher')
end

function MB.BodyToVehicle(veh)
    if not B_.body or B_.busy or not DoesEntityExist(veh) then return end
    B_.busy = true
    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, GetEntityCoords(veh), 600)
    openDoors(veh, true)
    Wait(600)
    playOnce(B('Carry').pickup)
    local res = lib.callback.await('nza:medbag:body:vehicle', false, NetworkGetNetworkIdFromEntity(veh))
    B_.busy = false
    SetTimeout(1500, function() openDoors(veh, false) end)
    if type(res) ~= 'table' or not res.ok then return err(res) end
    endBodyCarry()
    toast(res.msg or L('bb_ok_vehicle'), 'success', 'trunk')
end

function MB.UnloadBody(veh)
    if B_.busy or handsFull() or not DoesEntityExist(veh) then return end
    local st = Entity(veh).state.nzaBodies
    local id = type(st) == 'table' and type(st.ids) == 'table' and st.ids[1] or nil
    if not id then return end
    openDoors(veh, true)
    MB.CarryBody(id)
    SetTimeout(1500, function() openDoors(veh, false) end)
end

function MB.Deliver(pointId, id)
    if B_.busy then return end
    B_.busy = true
    local res = lib.callback.await('nza:medbag:body:deliver', false, pointId, id)
    B_.busy = false
    if type(res) ~= 'table' or not res.ok then return err(res) end
    if B_.body and (not id or B_.body.id == id) then endBodyCarry() end
    NZA.UI.Toast({ title = L('morgue'), message = res.msg, type = 'success', icon = 'skull', duration = 4500 })
end

local function readTag(id)
    local res = lib.callback.await('nza:medbag:body:tag', false, id)
    if type(res) ~= 'table' or not res.ok then return err(res) end
    local parts = { L('bb_tag_tod', res.tod or '--:--') }
    if res.cause then parts[#parts + 1] = res.cause end
    if res.by then parts[#parts + 1] = L('bb_tag_by', res.by) end
    NZA.UI.Toast({ title = L('bb_tag_title', res.name or L('unknown')), message = table.concat(parts, ' · '), type = 'info', icon = 'note', duration = 8000 })
end

RegisterNetEvent('nza:medbag:body:carryEnd', function()
    endBodyCarry()
end)

-- ════════════════════════════════════════════════════════════════════════
-- THE BAGGED PLAYER (own ped hidden + attached)
-- ════════════════════════════════════════════════════════════════════════

local attachedTo = 0

local function releaseSelf(at, heading)
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    attachedTo = 0
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    if at then
        SetEntityCoordsNoOffset(ped, at.x + 0.0, at.y + 0.0, at.z + 0.1, false, false, false)
        if heading then SetEntityHeading(ped, heading + 0.0) end
    end
    B_.inBag = false
end

local function trunkOffset(veh)
    local min, max = GetModelDimensions(GetEntityModel(veh))
    return vector3(0.0, min.y + 0.75, (min.z + max.z) * 0.5 - 0.15)
end

local function applyInBag(v)
    local ped = PlayerPedId()
    B_.inBag = true
    if IsEntityVisible(ped) then SetEntityVisible(ped, false, false) end
    local net = tonumber(v.net)
    local ent = 0
    if net and NetworkDoesEntityExistWithNetworkId(net) then ent = NetworkGetEntityFromNetworkId(net) end
    if ent == 0 or not DoesEntityExist(ent) then
        -- the bag is being moved (new prop on its way): stay put
        if IsEntityAttached(ped) and attachedTo ~= 0 and not DoesEntityExist(attachedTo) then DetachEntity(ped, false, false) end
        FreezeEntityPosition(ped, true)
        return
    end
    if attachedTo ~= ent or not IsEntityAttachedToEntity(ped, ent) then
        local off
        if v.mode == 'vehicle' then off = trunkOffset(ent)
        else off = v.off and vector3(v.off.x or 0.0, v.off.y or 0.0, v.off.z or 0.0) or vector3(0.0, 0.0, 0.2) end
        FreezeEntityPosition(ped, false)
        if IsEntityAttached(ped) then DetachEntity(ped, false, false) end
        AttachEntityToEntity(ped, ent, 0, off.x, off.y, off.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        attachedTo = ent
    end
    SetEntityCollision(ped, false, false)
end

CreateThread(function()
    while true do
        local v = LocalPlayer.state.nzaInBag
        if type(v) == 'table' then
            applyInBag(v)
            Wait(250)
        else
            if B_.inBag then releaseSelf() end
            Wait(500)
        end
    end
end)

RegisterNetEvent('nza:medbag:body:release', function(at, heading, teleport)
    if teleport and at then
        DoScreenFadeOut(600)
        local t = GetGameTimer()
        while not IsScreenFadedOut() and GetGameTimer() - t < 1500 do Wait(0) end
        releaseSelf(at, heading)
        RequestCollisionAtCoord(at.x + 0.0, at.y + 0.0, at.z + 0.0)
        t = GetGameTimer()
        while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() - t < 4000 do Wait(0) end
        DoScreenFadeIn(800)
    else
        releaseSelf(at, heading)
    end
    toast(L('bb_released'), 'info', 'body')
end)

-- the wounded module is about to teleport us to the hospital
RegisterNetEvent('nza:wounded:respawn', function()
    if B_.inBag then releaseSelf() end
end)

-- ════════════════════════════════════════════════════════════════════════
-- INTERACTIONS
-- ════════════════════════════════════════════════════════════════════════

NZA.Interact.Add({
    name = 'nza_bodybag', label = L('bb_place'), icon = 'skull', order = 90,
    perm = perm(), states = { dead = true }, player = true, npc = true,
    distance = tonumber(B().distance) or 2.0,
    canInteract = function(entity, target, st)
        if B().enabled == false or B_.busy then return false end
        if type(st) == 'table' and (st.bag or st.carried or st.stretcher) then return false end
        if handsFull() or IsPedInAnyVehicle(PlayerPedId(), false) then return false end
        return hasBagItem()
    end,
    onSelect = function(entity, target) MB.BagBody(entity, target) end,
})

local function bagOpt(name, label, icon, order, opts)
    local o = { name = name, label = label, icon = icon, order = order, bag = true, player = false, npc = false,
        distance = (tonumber(B().distance) or 2.0) + 0.5 }
    for k, v in pairs(opts) do o[k] = v end
    NZA.Interact.Add(o)
end

bagOpt('nza_bodybag_carry', L('bb_carry'), 'body', 91, {
    perm = perm(),
    canInteract = function(entity)
        local st = bodyOf(entity)
        if not st or (st.mode ~= 'ground' and st.mode ~= 'stretcher') then return false end
        return (B('Carry').enabled ~= false) and not handsFull() and not B_.busy
    end,
    onSelect = function(entity)
        local st = bodyOf(entity)
        if st then MB.CarryBody(st.id) end
    end,
})

bagOpt('nza_bodybag_deliver', L('bb_deliver'), 'hospital', 92, {
    perm = perm(),
    canInteract = function(entity)
        local st = bodyOf(entity)
        if not st or (st.mode ~= 'ground' and st.mode ~= 'stretcher') then return false end
        return nearestMorgue(GetEntityCoords(entity), tonumber(M().range) or 4.0) ~= nil
    end,
    onSelect = function(entity)
        local st = bodyOf(entity)
        local m = st and nearestMorgue(GetEntityCoords(entity), (tonumber(M().range) or 4.0) + 0.5)
        if m then MB.Deliver(m.id, st.id) end
    end,
})

bagOpt('nza_bodybag_tag', L('bb_tag'), 'clipboard', 93, {
    canInteract = function(entity) return bodyOf(entity) ~= nil end,
    onSelect = function(entity)
        local st = bodyOf(entity)
        if st then readTag(st.id) end
    end,
})

bagOpt('nza_bodybag_open', L('bb_open'), 'scissors', 94, {
    perm = perm(),
    canInteract = function(entity)
        if B().unbag == false then return false end
        local st = bodyOf(entity)
        return st ~= nil and st.kind == 'player' and (st.mode == 'ground' or st.mode == 'stretcher') and not B_.busy
    end,
    onSelect = function(entity)
        local st = bodyOf(entity)
        if not st then return end
        B_.busy = true
        local ped = PlayerPedId()
        TaskTurnPedToFaceEntity(ped, entity, 500)
        Wait(500)
        local done = progress(2500, L('bb_open'), { dict = 'amb@medic@standing@kneel@idle_a', clip = 'idle_a', flag = 1 })
        if not done then B_.busy = false return end
        local res = lib.callback.await('nza:medbag:body:open', false, st.id)
        B_.busy = false
        if type(res) ~= 'table' or not res.ok then return err(res) end
        toast(res.msg or L('bb_ok_opened'), 'success', 'scissors')
    end,
})

-- dead ambient NPCs that are not patients yet
CreateThread(function()
    Wait(2000)
    if B().enabled == false or B().anyDeadPed == false then return end
    if not (Bridge and Bridge.Target and Bridge.Target.Ped) then return end
    local ok, e = pcall(Bridge.Target.Ped, { {
        name = 'nza_bodybag_ambient', label = L('bb_place'), icon = 'skull', distance = tonumber(B().distance) or 2.0,
        canInteract = function(ent)
            if type(ent) == 'table' then ent = ent.entity end
            if not ent or ent == 0 or not DoesEntityExist(ent) or IsPedAPlayer(ent) then return false end
            if not IsPedDeadOrDying(ent, true) or not NetworkGetEntityIsNetworked(ent) then return false end
            if Entity(ent).state.nza ~= nil then return false end   -- patients use the regular option
            if not NZA.Perm(perm()) or handsFull() or B_.busy or down() then return false end
            return hasBagItem()
        end,
        onSelect = function(ent)
            if type(ent) == 'table' then ent = ent.entity end
            CreateThread(function() bagAmbient(ent) end)
        end,
    } })
    if not ok then NZA.Warn('medbag: ped target failed: ' .. tostring(e)) end
end)

-- [E] take a body bag out of the vehicle you stand behind
CreateThread(function()
    local shown = false
    while true do
        local sleep = 800
        local veh = nil
        if B().enabled ~= false and B('Vehicle').enabled ~= false and not handsFull() and not down() and NZA.Perm(perm())
            and not IsPedInAnyVehicle(PlayerPedId(), false) then
            veh = rearVehicle(GetEntityCoords(PlayerPedId()), tonumber(B('Vehicle').range) or 3.0, true)
        end
        if veh then
            sleep = 0
            if not shown then
                local k = (B('Carry').keys or {}).context or { control = 38, label = 'E' }
                NZA.UI.Prompt(PROMPT_UNLOAD, { key = k.label, label = L('bb_p_unload') })
                shown = true
            end
            local k = (B('Carry').keys or {}).context or { control = 38, label = 'E' }
            if not B_.busy and not NZA.UI.Top() and IsControlJustPressed(0, k.control) then
                local target = veh
                CreateThread(function() MB.UnloadBody(target) end)
                Wait(400)
            end
        elseif shown then
            NZA.UI.HidePrompt(PROMPT_UNLOAD)
            shown = false
        end
        Wait(sleep)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- MORGUE POINT TYPE
-- ════════════════════════════════════════════════════════════════════════

local function nearestBodyTo(pos, range)
    local best, bestD = nil, range
    local model = GetHashKey((Config.Props and Config.Props.bodybag) or 'xm_prop_body_bag')
    for _, obj in ipairs(GetGamePool('CObject')) do
        if GetEntityModel(obj) == model then
            local st = bodyOf(obj)
            if st and (st.mode == 'ground' or st.mode == 'stretcher') then
                local d = #(pos - GetEntityCoords(obj))
                if d <= bestD then best, bestD = st, d end
            end
        end
    end
    return best
end

NZA.Points.RegisterType('morgue', {
    label = L('morgue'), icon = 'skull', desc = L('morgue_desc'), radius = 1.5, distance = 3.0,
    target = {
        {
            name = 'deliver', label = L('bb_deliver'), icon = 'skull', perm = perm(),
            canInteract = function(point)
                if B_.body then return true end
                local c = point and point.coords
                return c ~= nil and nearestBodyTo(vector3(c.x, c.y, c.z), (tonumber(M().range) or 4.0)) ~= nil
            end,
            onSelect = function(point)
                local id = B_.body and B_.body.id
                if not id and point and point.coords then
                    local st = nearestBodyTo(vector3(point.coords.x, point.coords.y, point.coords.z), (tonumber(M().range) or 4.0) + 0.5)
                    id = st and st.id
                end
                if id then MB.Deliver(point.id, id) end
            end,
        },
    },
})

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL
-- ════════════════════════════════════════════════════════════════════════

local function nearestDeadPatient(range)
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestT, bestD = nil, nil, range
    local function consider(ped)
        if ped == me or not DoesEntityExist(ped) then return end
        local d = #(pos - GetEntityCoords(ped))
        if d > bestD then return end
        local st = NZA.Target.State(ped)
        if type(st) ~= 'table' or st.st ~= 'dead' or st.bag or st.carried or st.stretcher then return end
        local t = NZA.Target.FromEntity(ped)
        if t then best, bestT, bestD = ped, t, d end
    end
    for _, pid in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pid)) end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then consider(ped) end
    end
    return best, bestT
end

NZA.RadialItems = NZA.RadialItems or {}
table.insert(NZA.RadialItems, {
    id = 'bb_place', parent = 'patient', label = L('bb_r_place'), desc = L('bb_r_place_d'), icon = 'skull', order = 90, perm = perm(),
    canShow = function()
        if (Config.Medbag or {}).radial == false or B().enabled == false or handsFull() then return false end
        return nearestDeadPatient(2.6) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ent, target = nearestDeadPatient(2.6)
            if ent then MB.BagBody(ent, target) end
        end)
    end,
})
table.insert(NZA.RadialItems, {
    id = 'bb_drop', label = L('bb_r_drop'), desc = L('bb_r_drop_d'), icon = 'arrow-down', order = 73,
    canShow = function() return (Config.Medbag or {}).radial ~= false and B_.body ~= nil end,
    onSelect = function() CreateThread(MB.DropBody) end,
})
table.insert(NZA.RadialItems, {
    id = 'bb_unload', label = L('bb_unload'), icon = 'trunk', order = 74, perm = perm(),
    canShow = function()
        if (Config.Medbag or {}).radial == false or handsFull() then return false end
        return rearVehicle(GetEntityCoords(PlayerPedId()), (tonumber(B('Vehicle').range) or 3.0) + 0.5, true) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local veh = rearVehicle(GetEntityCoords(PlayerPedId()), (tonumber(B('Vehicle').range) or 3.0) + 0.5, true)
            if veh then MB.UnloadBody(veh) end
        end)
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and B_.body then endBodyCarry() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    NZA.UI.HidePrompt(PROMPT_DROP)
    NZA.UI.HidePrompt(PROMPT_CTX)
    NZA.UI.HidePrompt(PROMPT_UNLOAD)
    if B_.body and B_.body.animToken then NZA.Anim.Stop(PlayerPedId(), { token = B_.body.animToken, immediate = true }) end
    if B_.inBag then releaseSelf() end
end)
