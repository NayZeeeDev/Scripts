--[[
    NAYZEEE AMBULANCE - Body bag & morgue (server)

    Procedure 'bodybag' (NZA.Proc, perm Config.Medbag.Body.perm, item Config.Items.bodybag used at
    the finish): a dead patient (player or NPC) is zipped into a body bag. The bag is a networked
    prop (Config.Props.bodybag). Server-created while it lies on the ground; spawned + registered by
    the medic's client (nza:medbag:held, one-use token) while carried or laid on a stretcher.

    Body record (server only): MB.bodies[id] = { id ('BB-XXXXX'), pid, kind, src (player), name,
        mode = 'ground'|'carry'|'stretcher'|'vehicle', ent, net, coords, heading, bucket,
        carrier, cot, veh, by, byName, tod, cause, callId, since }
    Players stay patients (state 'dead', meta.bodybag = id → state bag 'bag'); their own client hides
    the ped and attaches it to whatever holds the bag (player state bag 'nzaInBag'). NPC peds are
    deleted and their patient record removed (a snapshot stays in the body record).

    State bags (server-set, replicated)
      bag prop   'nzaBag'  = { kind, sid | net }  (core: body bag targets resolve to the patient)
                 'nzaBody' = { id, name, kind, mode }
      player     'nzaInBag' = { id, net (entity to attach to), mode, off = { x, y, z } | nil }
      cot        'nzaBodyOn' = id        vehicle 'nzaBodies' = { n, ids }

    Callbacks (lib.callback) - replies { ok = true, ... } | { ok = false, err, msg }
      nza:medbag:body:adopt (pedNet)                 a dead ambient NPC becomes an NPC patient → { target }
      nza:medbag:body:carry (id)                     ground / stretcher / vehicle → hands → { token, model, name }
      nza:medbag:body:drop (coords, heading)         hands → ground
      nza:medbag:body:stretcher (cotNet)             hands → stretcher (transport module) → { token, model }
      nza:medbag:body:vehicle (vehNet)               hands → vehicle
      nza:medbag:body:open (id)                      unzip a player's bag where it lies
      nza:medbag:body:deliver (pointId, id|nil)      morgue: players respawn, NPCs pay a reward
      nza:medbag:body:tag (id)                       → { name, tod, cause, by }
    Net events S→C: nza:medbag:body:carryEnd (), nza:medbag:body:release (coords, heading) to the
                    bagged player (out of the bag at that spot)
    Bus (server) emitted: bodybag:bagged (src, body), bodybag:morgue (src, body)
    Bus listened: state:changed, patient:revived, wounded:respawned, player:unloaded
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Medbag = NZA.Medbag or {}
local MB = NZA.Medbag

MB.bodies    = MB.bodies or {}     -- [id] = body
MB.bodyCarry = MB.bodyCarry or {}  -- [carrier src] = id
local byPid  = {}                  -- [pid] = id
local lastPos = {}                 -- [src] = { coords, heading, bucket }

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

local function fail(err, ...)
    return { ok = false, err = err, msg = L('bb_err_' .. err, ...) }
end

local function rate(src, bucket, n, ms)
    return NZA.Core.Rate('medbag:bb:' .. bucket, src, n, ms)
end

local function perm(src)
    return NZA.Staff.Can(src, B().perm or 'bodybag')
end

local function srcCoords(src) return NZA.Core.SrcCoords(src) end

local function model() return (Config.Props and Config.Props.bodybag) or 'xm_prop_body_bag' end

function MB.BodyModels() return { model() } end

function MB.BodyCarrying(src) return MB.bodyCarry[src] ~= nil end

local ID_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function genId()
    local id
    repeat
        local t = {}
        for i = 1, 5 do
            local n = math.random(1, #ID_CHARS)
            t[i] = ID_CHARS:sub(n, n)
        end
        id = 'BB-' .. table.concat(t)
    until not MB.bodies[id]
    return id
end

local function plain(v)
    if not v then return nil end
    return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 }
end

local function vehicleBodies(vehNet)
    local ids = {}
    for id, b in pairs(MB.bodies) do
        if b.mode == 'vehicle' and b.veh == vehNet then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function vehState(vehNet)
    local veh = MB.EntFromNet(vehNet)
    if veh == 0 then return end
    local ids = vehicleBodies(vehNet)
    Entity(veh).state:set('nzaBodies', #ids > 0 and { n = #ids, ids = ids } or nil, true)
end

local function cotState(cotNet, id)
    local cot = MB.EntFromNet(cotNet)
    if cot == 0 then return end
    Entity(cot).state:set('nzaBodyOn', id, true)
end

local function bagTarget(body)
    if body.kind == 'player' then return { kind = 'player', sid = body.src } end
    return { kind = 'npc', net = body.npcNet or 0 }
end

local function propState(body)
    if not body.ent or body.ent == 0 or not DoesEntityExist(body.ent) then return end
    local st = Entity(body.ent).state
    st:set('nzaBag', bagTarget(body), true)
    st:set('nzaBody', { id = body.id, name = body.name, kind = body.kind, mode = body.mode }, true)
end

-- the bagged player's client follows this
local function playerState(body)
    if body.kind ~= 'player' or not body.src or not NZA.Core.Online(body.src) then return end
    local data = { id = body.id, mode = body.mode }
    if body.mode == 'vehicle' then
        data.net = body.veh
    else
        data.net = body.net
        local o = B().insideOffset
        if o then data.off = { x = o.x + 0.0, y = o.y + 0.0, z = o.z + 0.0 } end
    end
    Player(body.src).state:set('nzaInBag', data, true)
end

local function clearPlayer(body)
    if body.kind ~= 'player' or not body.src then return end
    if NZA.Core.Online(body.src) then Player(body.src).state:set('nzaInBag', nil, true) end
end

-- current world position of a body bag
local function bodyPos(body)
    if body.mode == 'carry' and body.carrier then
        return srcCoords(body.carrier) or body.coords
    elseif body.mode == 'vehicle' then
        local veh = MB.EntFromNet(body.veh)
        if veh ~= 0 then return GetEntityCoords(veh) end
    elseif body.ent and body.ent ~= 0 and DoesEntityExist(body.ent) then
        return GetEntityCoords(body.ent)
    end
    return body.coords
end
MB.BodyPos = bodyPos

local function deleteProp(body)
    if body.ent and body.ent ~= 0 and DoesEntityExist(body.ent) then DeleteEntity(body.ent)
    elseif body.net then MB.DeleteNet(body.net) end
    body.ent, body.net = nil, nil
end

local function endCarry(body, notifyCarrier)
    local src = body.carrier
    body.carrier = nil
    if src then
        if MB.bodyCarry[src] == body.id then MB.bodyCarry[src] = nil end
        local h = MB.held[src]
        if h and h.kind == 'body' and h.id == body.id then MB.held[src] = nil end
        if notifyCarrier and NZA.Core.Online(src) then TriggerClientEvent('nza:medbag:body:carryEnd', src) end
    end
end

-- leave whatever the bag is on / in (props deleted, states cleared)
local function detach(body, notifyCarrier)
    if body.mode == 'carry' then endCarry(body, notifyCarrier) end
    if body.mode == 'stretcher' and body.cot then
        cotState(body.cot, nil)
        body.cot = nil
    end
    if body.mode == 'vehicle' and body.veh then
        local veh = body.veh
        body.veh = nil
        body.mode = 'none'
        vehState(veh)
    end
    deleteProp(body)
end

local function setGround(body, coords, heading, bucket, physics)
    local ent, net = MB.SpawnObject(model(), coords, heading, bucket, { freeze = not physics })
    if ent == 0 then return false end
    body.mode = 'ground'
    body.ent, body.net = ent, net
    body.coords, body.heading, body.bucket = coords, heading, bucket or 0
    body.since = os.time()
    propState(body)
    playerState(body)
    if physics then
        local id = body.id
        SetTimeout(4000, function()
            local b = MB.bodies[id]
            if b and b.ent == ent and DoesEntityExist(ent) then
                FreezeEntityPosition(ent, true)
                b.coords = GetEntityCoords(ent)
            end
        end)
    end
    return true
end

-- put a body down where it is now when nobody can (carrier gone, cot / vehicle deleted)
local function dropHere(body, at, heading, bucket)
    detach(body, true)
    at = at or body.coords
    if not at then return false end
    return setGround(body, vector3(at.x, at.y, at.z + 0.25), heading or body.heading or 0.0, bucket or body.bucket or 0, true)
end
MB.BodyDropHere = dropHere

-- completely forget a body (morgue, respawn, revive)
local function destroy(body, releaseAt)
    detach(body, true)
    MB.bodies[body.id] = nil
    if body.pid and byPid[body.pid] == body.id then byPid[body.pid] = nil end
    if body.kind == 'player' then
        local p = NZA.Patients.Get(body.pid)
        if p and p.meta and p.meta.bodybag then NZA.Patients.SetMeta(p, 'bodybag', nil) end
        clearPlayer(body)
        if releaseAt and body.src and NZA.Core.Online(body.src) then
            TriggerClientEvent('nza:medbag:body:release', body.src, plain(releaseAt), body.heading or 0.0)
        end
    end
end

local function causeText(p)
    if NZA.Wounded and NZA.Wounded.CauseLines then
        local ok, lines = pcall(NZA.Wounded.CauseLines, p)
        if ok and type(lines) == 'table' then
            local out = {}
            for i = 1, math.min(2, #lines) do
                local l = lines[i]
                local text = type(l) == 'table' and (l.text or l[1]) or l
                if type(text) == 'string' then out[#out + 1] = text end
            end
            if #out > 0 then return table.concat(out, ' · ') end
        end
    end
    -- worst injury
    local worst
    for _, inj in pairs(p.injuries or {}) do
        if not worst or (inj.severity or 0) > (worst.severity or 0) then worst = inj end
    end
    if worst then return ('%s · %s'):format(NZA.Util.InjuryLabel(worst.type), NZA.Util.RegionLabel(worst.region)) end
    return nil
end

local function validSpot(src, coords)
    local me = srcCoords(src)
    if not me or not coords then return false end
    local flat = #(vector2(me.x, me.y) - vector2(coords.x, coords.y))
    return flat <= 3.2 and math.abs(me.z - coords.z) <= 2.6
end

-- ════════════════════════════════════════════════════════════════════════
-- BAGGING (procedure)
-- ════════════════════════════════════════════════════════════════════════

local function bagBody(src, p, result)
    local cfg = B()
    local pc = NZA.Core.PatientCoords(p)
    local pedEnt = NZA.Core.PatientPed(p)
    local heading = pedEnt ~= 0 and GetEntityHeading(pedEnt) or 0.0
    local at = MB.V3(type(result) == 'table' and result.at or nil)
    if not at or not pc or #(at - pc) > 2.5 then
        at = pc and vector3(pc.x, pc.y, pc.z - 0.25) or srcCoords(src)
    end
    if type(result) == 'table' and tonumber(result.heading) then heading = tonumber(result.heading) end
    heading = (heading + (tonumber(cfg.bagHeading) or 0.0)) % 360.0
    local off = cfg.groundOffset
    if off then at = vector3(at.x + off.x, at.y + off.y, at.z + off.z) end
    local bucket = MB.BucketOf(src)

    local body = {
        id = genId(), pid = p.pid, kind = p.kind, src = p.kind == 'player' and p.src or nil,
        name = p.name or L('unknown'), by = src, byName = NZA.Core.Name(src),
        tod = tonumber(p.deadAt) or os.time(), cause = causeText(p),
        callId = p.meta and p.meta.callId or nil, npcNet = p.kind == 'npc' and p.net or nil,
    }
    if not setGround(body, at, heading, bucket, false) then return nil end
    MB.bodies[body.id] = body
    byPid[p.pid] = body.id

    if p.kind == 'player' then
        NZA.Patients.SetMeta(p, 'bodybag', body.id)
        playerState(body)
        NZA.Core.Notify(body.src, L('bb_you_bagged'), 'info', L('bb_progress'))
    else
        -- the NPC body is in the bag now: the ped goes, the record goes
        local pid, net = p.pid, p.net
        SetTimeout(0, function()
            local ent = MB.EntFromNet(net)
            if ent ~= 0 and GetEntityType(ent) == 1 and not IsPedAPlayer(ent) then DeleteEntity(ent) end
            if NZA.Patients.Get(pid) then NZA.Patients.Remove(pid, 'bodybag') end
        end)
    end
    NZA.Bus.Emit('bodybag:bagged', src, body)
    return body
end

NZA.Proc.Register('bodybag', {
    perm = (Config.Medbag and Config.Medbag.Body and Config.Medbag.Body.perm) or 'bodybag',
    label = NZA.L('medbag.bb_progress'),
    items = function()
        local cfg = B()
        if cfg.requireItem == false or not (Config.Items and Config.Items.bodybag) then return {} end
        return { [Config.Items.bodybag] = 1 }
    end,
    maxDist = 3.0,
    minTime = math.max(2, math.floor((tonumber(Config.Medbag and Config.Medbag.Body and Config.Medbag.Body.time) or 9) * 0.8)),
    maxTime = 180,
    consume = 'finish',
    states = { dead = true },
    self = false, npc = true, player = true,
    record = true,
    onStart = function(src, p)
        local cfg = B()
        if cfg.enabled == false then return false, { err = 'disabled', msg = L('bb_err_failed') } end
        if MB.HandsFull(src) then return false, { err = 'hands', msg = L('bb_err_hands') } end
        if p.state ~= 'dead' then return false, { err = 'state', msg = L('bb_err_not_dead') } end
        local m = p.meta or {}
        if m.bodybag or byPid[p.pid] then return false, { err = 'bagged', msg = L('bb_err_bagged') } end
        if m.carried or m.stretcher or m.bay or m.vehicle or m.inBed then return false, { err = 'busy', msg = L('bb_err_busy') } end
        if p.kind == 'player' and not (p.src and NZA.Core.Online(p.src)) then return false, { err = 'no_patient', msg = L('bb_err_failed') } end
        return true, { time = tonumber(cfg.time) or 9 }
    end,
    onFinish = function(src, p, session, result)
        if p.state ~= 'dead' or byPid[p.pid] then return { msg = L('bb_err_bagged'), failed = true } end
        local body = bagBody(src, p, result)
        if not body then return { msg = L('bb_err_failed'), failed = true } end
        return { msg = L('bb_ok_bagged', body.name), id = body.id, name = body.name,
                 record = { msg = L('bb_record'), by = body.byName, bag = body.id } }
    end,
})

-- a dead ambient NPC (no patient yet) becomes an NPC patient so it can be bagged
lib.callback.register('nza:medbag:body:adopt', function(src, net)
    if not rate(src, 'adopt', 3, 2000) then return fail('failed') end
    if B().anyDeadPed == false then return fail('not_ped') end
    if not perm(src) then return fail('no_perm') end
    net = tonumber(net)
    local ent = MB.EntFromNet(net)
    if ent == 0 or GetEntityType(ent) ~= 1 or IsPedAPlayer(ent) then return fail('not_ped') end
    local me = srcCoords(src)
    if not me or #(GetEntityCoords(ent) - me) > (tonumber(B().distance) or 2.0) + 2.0 then return fail('not_ped') end
    local existing = NZA.Patients.GetByNet(net)
    if existing then
        if existing.state ~= 'dead' then return fail('alive') end
        return { ok = true, target = { kind = 'npc', net = net } }
    end
    local dead = GetEntityHealth(ent) <= 0
    if not dead and GetPedCauseOfDeath then
        local ok, cause = pcall(GetPedCauseOfDeath, ent)
        dead = ok and cause ~= nil and cause ~= 0
    end
    if not dead then return fail('alive') end
    local p = NZA.Patients.CreateNPC({ net = net, state = 'dead', reason = 'found_dead', meta = { found = true } })
    if not p then return fail('failed') end
    return { ok = true, target = { kind = 'npc', net = net } }
end)

-- ════════════════════════════════════════════════════════════════════════
-- CARRY / DROP / STRETCHER / VEHICLE
-- ════════════════════════════════════════════════════════════════════════

local function medicReady(src)
    if not perm(src) then return fail('no_perm') end
    if not MB.PlayerAlive(src) then return fail('failed') end
    if MB.InVehicle(src) then return fail('failed') end
    return nil
end

lib.callback.register('nza:medbag:body:carry', function(src, id)
    if not rate(src, 'carry', 3, 2000) then return fail('failed') end
    if B('Carry').enabled == false then return fail('failed') end
    local bad = medicReady(src)
    if bad then return bad end
    if MB.HandsFull(src) then return fail('hands') end
    local body = type(id) == 'string' and MB.bodies[id] or nil
    if not body then return fail('no_body') end
    if body.mode == 'carry' then return fail('carried') end
    local me = srcCoords(src)
    local pos = bodyPos(body)
    local range = (body.mode == 'vehicle') and ((tonumber(B('Vehicle').range) or 3.0) + 4.0) or ((tonumber(B().distance) or 2.0) + 1.8)
    if not me or not pos or #(me - pos) > range then return fail('no_body') end
    detach(body, false)
    body.mode = 'carry'
    body.carrier = src
    body.since = os.time()
    MB.bodyCarry[src] = body.id
    local token = NZA.Util.uid('bbh')
    MB.held[src] = { kind = 'body', id = body.id, token = token, at = os.time(), attach = 'carry' }
    playerState(body)
    return { ok = true, id = body.id, token = token, model = model(), name = body.name }
end)

-- the client registered the prop it spawned (hand or cot) - called from nza:medbag:held
function MB.BodyHeld(src, h)
    local body = MB.bodies[h.id]
    MB.held[src] = nil
    if not body then
        MB.DeleteNet(h.net)
        return
    end
    local wanted = (h.attach == 'cot') and 'stretcher' or 'carry'
    if body.mode ~= wanted or (wanted == 'carry' and body.carrier ~= src) then
        MB.DeleteNet(h.net)
        return
    end
    if body.net and body.net ~= h.net then deleteProp(body) end
    body.net = h.net
    body.ent = MB.EntFromNet(h.net)
    if body.ent ~= 0 and SetEntityOrphanMode then pcall(SetEntityOrphanMode, body.ent, 2) end
    propState(body)
    playerState(body)
end

lib.callback.register('nza:medbag:body:drop', function(src, coords, heading)
    if not rate(src, 'drop', 3, 2000) then return fail('failed') end
    local id = MB.bodyCarry[src]
    local body = id and MB.bodies[id]
    if not body then
        MB.bodyCarry[src] = nil
        return fail('no_body')
    end
    coords = MB.V3(coords)
    if not coords or not validSpot(src, coords) then coords = nil end
    local me = srcCoords(src)
    detach(body, false)
    local ok
    if coords then
        ok = setGround(body, coords, tonumber(heading) or 0.0, MB.BucketOf(src), false)
    elseif me then
        ok = setGround(body, vector3(me.x, me.y, me.z + 0.25), tonumber(heading) or 0.0, MB.BucketOf(src), true)
    end
    if not ok then return fail('failed') end
    return { ok = true, msg = L('bb_ok_down') }
end)

lib.callback.register('nza:medbag:body:stretcher', function(src, cotNet)
    if not rate(src, 'cot', 3, 2000) then return fail('failed') end
    local st = B('Stretcher')
    if st.enabled == false then return fail('no_cot') end
    local id = MB.bodyCarry[src]
    local body = id and MB.bodies[id]
    if not body then return fail('no_body') end
    cotNet = tonumber(cotNet)
    local T = NZA.Transport
    local rec = T and T.stretchers and cotNet and T.stretchers[cotNet] or nil
    if not rec then return fail('no_cot') end
    if rec.pid or rec.veh or (rec.pusher and rec.pusher ~= src) then return fail('cot_busy') end
    for _, b in pairs(MB.bodies) do
        if b.mode == 'stretcher' and b.cot == cotNet then return fail('cot_busy') end
    end
    local cot = MB.EntFromNet(cotNet)
    local me = srcCoords(src)
    if cot == 0 or not me or #(GetEntityCoords(cot) - me) > (tonumber(st.range) or 2.6) + 1.5 then return fail('no_cot') end
    detach(body, false)
    body.mode = 'stretcher'
    body.cot = cotNet
    body.since = os.time()
    body.coords = GetEntityCoords(cot)
    rec.touched = os.time()
    cotState(cotNet, body.id)
    local token = NZA.Util.uid('bbs')
    MB.held[src] = { kind = 'body', id = body.id, token = token, at = os.time(), attach = 'cot' }
    playerState(body)
    return { ok = true, token = token, model = model(), msg = L('bb_ok_stretcher') }
end)

local BAD_TYPES = { bike = true, boat = true, heli = true, plane = true, train = true, submarine = true, trailer = true }

lib.callback.register('nza:medbag:body:vehicle', function(src, vehNet)
    if not rate(src, 'veh', 3, 2000) then return fail('failed') end
    local vc = B('Vehicle')
    if vc.enabled == false then return fail('no_veh') end
    local id = MB.bodyCarry[src]
    local body = id and MB.bodies[id]
    if not body then return fail('no_body') end
    vehNet = tonumber(vehNet)
    local veh = MB.EntFromNet(vehNet)
    if veh == 0 or GetEntityType(veh) ~= 2 then return fail('no_veh') end
    local okType, vtype = pcall(GetVehicleType, veh)
    if okType and BAD_TYPES[vtype] then return fail('veh_class') end
    if type(vc.models) == 'table' and #vc.models > 0 then
        local h, found = GetEntityModel(veh), false
        for _, m in ipairs(vc.models) do
            if (joaat(m) % 4294967296) == (h % 4294967296) then found = true break end
        end
        if not found then return fail('veh_class') end
    end
    local me = srcCoords(src)
    if not me or #(GetEntityCoords(veh) - me) > (tonumber(vc.range) or 3.0) + 4.0 then return fail('no_veh') end
    if #vehicleBodies(vehNet) >= (tonumber(vc.max) or 2) then return fail('veh_full') end
    detach(body, false)
    body.mode = 'vehicle'
    body.veh = vehNet
    body.since = os.time()
    body.coords = GetEntityCoords(veh)
    vehState(vehNet)
    playerState(body)
    return { ok = true, msg = L('bb_ok_vehicle') }
end)

-- ════════════════════════════════════════════════════════════════════════
-- OPEN / TOE TAG
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:medbag:body:open', function(src, id)
    if not rate(src, 'open', 2, 2000) then return fail('failed') end
    if B().unbag == false then return fail('npc_open') end
    local bad = medicReady(src)
    if bad then return bad end
    local body = type(id) == 'string' and MB.bodies[id] or nil
    if not body then return fail('no_body') end
    if body.kind ~= 'player' then return fail('npc_open') end
    if body.mode ~= 'ground' and body.mode ~= 'stretcher' then return fail('carried') end
    local me, pos = srcCoords(src), bodyPos(body)
    if not me or not pos or #(me - pos) > (tonumber(B().distance) or 2.0) + 1.8 then return fail('no_body') end
    destroy(body, pos)
    if B().returnItem and Config.Items and Config.Items.bodybag then
        NZA.Core.B('Inv.AddItem', src, Config.Items.bodybag, 1)
    end
    return { ok = true, msg = L('bb_ok_opened') }
end)

lib.callback.register('nza:medbag:body:tag', function(src, id)
    if not rate(src, 'tag', 4, 2000) then return fail('failed') end
    local body = type(id) == 'string' and MB.bodies[id] or nil
    if not body then return fail('no_body') end
    local me, pos = srcCoords(src), bodyPos(body)
    if not me or not pos or #(me - pos) > (tonumber(B().distance) or 2.0) + 2.5 then return fail('no_body') end
    return {
        ok = true, id = body.id, name = body.name, kind = body.kind,
        tod = os.date('%H:%M', body.tod or os.time()), cause = body.cause, by = body.byName,
    }
end)

-- ════════════════════════════════════════════════════════════════════════
-- MORGUE
-- ════════════════════════════════════════════════════════════════════════

local function morguePoint(pointId)
    if type(pointId) == 'string' and pointId:sub(1, 3) == 'fb:' then
        local idx = tonumber(pointId:sub(4))
        local f = idx and (M().fallback or {})[idx]
        if not f or not f.coords then return nil end
        local c = f.coords
        return { id = pointId, coords = vector3(c.x, c.y, c.z), heading = c.w or 0.0, label = f.label or L('morgue') }
    end
    local H = NZA.Hospitals
    if not H or not H.Point then return nil end
    local ok, pt = pcall(H.Point, pointId)
    if not ok or type(pt) ~= 'table' or pt.type ~= 'morgue' or not pt.coords then return nil end
    local label = pt.label
    if (not label or label == '') and pt.hospital and H.Get then
        local okH, hosp = pcall(H.Get, pt.hospital)
        if okH and type(hosp) == 'table' then label = hosp.label end
    end
    local c = pt.coords
    return { id = pt.id, hospital = pt.hospital, coords = vector3(c.x, c.y, c.z), heading = c.w or 0.0, label = label or L('morgue') }
end

local function closeCall(callId)
    local D = NZA.Dispatch
    if not callId or not D or not D.Get or not D.Close then return end
    local ok, call = pcall(D.Get, callId)
    if not ok or type(call) ~= 'table' then return end
    for _, pid in ipairs(call.patients or {}) do
        if NZA.Patients.Get(pid) then return end   -- someone of this call is still around
    end
    pcall(D.Close, callId, 'morgue')
end

local function pay(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    local r = M().reward or {}
    local okPay = NZA.Core.B('AddMoney', src, r.account or 'bank', amount, L('bb_reward_reason'))
    if okPay == false then return 0 end
    return amount
end

local function respawnPlayer(body, point)
    local p = NZA.Patients.Get(body.pid)
    if not p or not body.src or not NZA.Core.Online(body.src) then return end
    local m = M()
    local atMorgue = m.respawn == 'morgue'
    if NZA.Wounded and NZA.Wounded.ForceRespawn and p.state == 'dead' then
        local opts = { fee = m.fee == true }
        if atMorgue then
            opts.coords = vector4(point.coords.x, point.coords.y, point.coords.z, point.heading or 0.0)
            opts.label = point.label
            opts.bed = false
        end
        local ok, res = pcall(NZA.Wounded.ForceRespawn, body.src, opts)
        if ok and res then return end
    end
    -- no wounded module: revive and move the player ourselves
    local spot = point.coords
    local heading = point.heading or 0.0
    if not atMorgue and NZA.Hospitals and NZA.Hospitals.RespawnPoint then
        local ok, rp = pcall(NZA.Hospitals.RespawnPoint, point.coords)
        if ok and rp then
            local c = type(rp) == 'table' and rp.coords or rp
            if c then spot = vector3(c.x, c.y, c.z); heading = c.w or heading end
        end
    end
    NZA.Patients.Revive(p, { full = true, reason = 'morgue' })
    TriggerClientEvent('nza:medbag:body:release', body.src, plain(spot), heading, true)
end

lib.callback.register('nza:medbag:body:deliver', function(src, pointId, id)
    if not rate(src, 'deliver', 2, 3000) then return fail('failed') end
    local bad = medicReady(src)
    if bad then return bad end
    id = id or MB.bodyCarry[src]
    local body = type(id) == 'string' and MB.bodies[id] or nil
    if not body then return fail('no_body') end
    local point = morguePoint(pointId)
    if not point then return fail('no_morgue') end
    local range = tonumber(M().range) or 4.0
    local me = srcCoords(src)
    if not me or #(me - point.coords) > range + 2.5 then return fail('no_morgue') end
    if body.mode == 'carry' and body.carrier ~= src then return fail('carried') end
    if body.mode == 'vehicle' then return fail('morgue_far') end
    local pos = bodyPos(body)
    if not pos or #(pos - point.coords) > range + 1.5 then return fail('morgue_far') end

    local r = M().reward or {}
    local amount = pay(src, body.kind == 'npc' and r.npc or r.player)
    local soc = math.floor(tonumber(r.society) or 0)
    if soc > 0 and Config.Billing and Config.Billing.society then
        NZA.Core.B('Society.Add', Config.Billing.society, soc)
    end

    if body.kind == 'player' then
        local p = NZA.Patients.Get(body.pid)
        if p then
            NZA.Records.Add(p, { medic = src, action = 'morgue', summary = { msg = L('bb_record_morgue', point.label), bag = body.id, by = body.byName } })
            NZA.Core.Notify(body.src, L('bb_you_morgue'), 'info', point.label)
        end
        destroy(body, nil)
        respawnPlayer(body, point)
    else
        destroy(body, nil)
        if NZA.Patients.Get(body.pid) then NZA.Patients.Remove(body.pid, 'morgue') end
    end
    closeCall(body.callId)
    NZA.Bus.Emit('bodybag:morgue', src, body, point)
    local msg = amount > 0 and L('bb_ok_reward', body.name, tostring(amount)) or L('bb_ok_morgue', body.name)
    return { ok = true, msg = msg, reward = amount }
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

local function bodyOfPatient(p)
    if not p then return nil end
    local id = byPid[p.pid] or (p.meta and p.meta.bodybag)
    return id and MB.bodies[id] or nil
end

-- revived / respawned / no longer dead → out of the bag
NZA.Bus.On('state:changed', function(p, old, new)
    if not p then return end
    if new ~= 'dead' then
        local body = bodyOfPatient(p)
        if body then destroy(body, bodyPos(body)) end
    end
    -- a carrier who goes down drops the body bag
    if p.kind == 'player' and p.src and new ~= 'alive' and MB.bodyCarry[p.src] then
        local b = MB.bodies[MB.bodyCarry[p.src]]
        if b then
            local pos = srcCoords(p.src)
            dropHere(b, pos, nil, MB.BucketOf(p.src))
        else
            MB.bodyCarry[p.src] = nil
        end
        NZA.Core.Notify(p.src, L('bb_dropped'), 'warning', L('bb_progress'))
    end
end)

NZA.Bus.On('patient:revived', function(p)
    local body = bodyOfPatient(p)
    if body then destroy(body, bodyPos(body)) end
end)

NZA.Bus.On('wounded:respawned', function(src, p)
    local body = bodyOfPatient(p)
    if body then destroy(body, nil) end
end)

local function forgetSource(src)
    -- a bagged player left: the body goes with them
    for _, b in pairs(MB.bodies) do
        if b.kind == 'player' and b.src == src then destroy(b, nil) end
    end
    -- a carrier left: the bag is put down where they were
    local id = MB.bodyCarry[src]
    if id then
        local b = MB.bodies[id]
        local last = lastPos[src]
        if b then dropHere(b, last and last.coords or b.coords, last and last.heading, last and last.bucket) end
        MB.bodyCarry[src] = nil
    end
    lastPos[src] = nil
end

AddEventHandler('playerDropped', function()
    forgetSource(source)
end)

NZA.Bus.On('player:unloaded', function(src)
    if src then forgetSource(src) end
end)

-- watchdog: carriers, cots and vehicles that disappeared, props removed by other scripts
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for src in pairs(MB.bodyCarry) do
            local p = GetPlayerPed(src)
            if p and p ~= 0 and DoesEntityExist(p) then
                lastPos[src] = { coords = GetEntityCoords(p), heading = GetEntityHeading(p), bucket = MB.BucketOf(src) }
            end
        end
        for _, body in pairs(MB.bodies) do
            if body.mode == 'carry' then
                local src = body.carrier
                if not src or not NZA.Core.Online(src) or MB.bodyCarry[src] ~= body.id then
                    local last = src and lastPos[src]
                    dropHere(body, last and last.coords or body.coords, last and last.heading, last and last.bucket)
                else
                    body.coords = srcCoords(src) or body.coords
                    if not body.net and now - (body.since or now) > 12 then
                        local last = lastPos[src]
                        dropHere(body, body.coords, last and last.heading, last and last.bucket)
                    end
                end
            elseif body.mode == 'stretcher' then
                local cot = MB.EntFromNet(body.cot)
                local T = NZA.Transport
                local rec = T and T.stretchers and T.stretchers[body.cot]
                if cot == 0 or not rec or rec.pid then
                    dropHere(body, cot ~= 0 and GetEntityCoords(cot) or body.coords)
                else
                    rec.touched = now
                    body.coords = GetEntityCoords(cot)
                    if not body.net and now - (body.since or now) > 12 then
                        dropHere(body, body.coords)
                    end
                end
            elseif body.mode == 'vehicle' then
                local veh = MB.EntFromNet(body.veh)
                if veh == 0 then
                    dropHere(body, body.coords)
                else
                    body.coords = GetEntityCoords(veh)
                end
            elseif body.mode == 'ground' then
                if not body.ent or body.ent == 0 or not DoesEntityExist(body.ent) then
                    body.ent, body.net = nil, nil
                    setGround(body, body.coords, body.heading or 0.0, body.bucket or 0, false)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, body in pairs(MB.bodies) do
        if body.ent and body.ent ~= 0 and DoesEntityExist(body.ent) then DeleteEntity(body.ent)
        elseif body.net then MB.DeleteNet(body.net) end
        if body.kind == 'player' and body.src and NZA.Core.Online(body.src) then
            Player(body.src).state:set('nzaInBag', nil, true)
            local p = NZA.Patients.Get(body.pid)
            if p and p.meta and p.meta.bodybag then NZA.Patients.SetMeta(p, 'bodybag', nil) end
        end
        if body.veh then
            local veh = MB.EntFromNet(body.veh)
            if veh ~= 0 then Entity(veh).state:set('nzaBodies', nil, true) end
        end
        if body.cot then
            local cot = MB.EntFromNet(body.cot)
            if cot ~= 0 then Entity(cot).state:set('nzaBodyOn', nil, true) end
        end
    end
end)

exports('GetBodyBags', function()
    local out = {}
    for id, b in pairs(MB.bodies) do
        out[#out + 1] = { id = id, pid = b.pid, kind = b.kind, name = b.name, mode = b.mode, coords = plain(bodyPos(b)) }
    end
    return out
end)
