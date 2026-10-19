--[[
    NAYZEEE AMBULANCE - CPR (client): the world side of a code                 NZA.Cpr.Scene

    Medic side (called by client/modules/cpr.lua for the active code `a`):
      Scene.Origin(patientPed) → { x, y, z, h }   synced-scene origin sent to the server on start
      Scene.Enter(a)            camera, own animation for the role, NPC patient pose, pad anchors
      Scene.Role(a)             role changed (swap / promoted): compressor ↔ airway partner
      Scene.Phase(a, phase)     phase changed (breaths → BVM on the face, rosc → success clips)
      Scene.Press(a, rate)      a compression started (keeps the pump clip running at your rate)
      Scene.Breath(a, on)       a rescue breath is being given
      Scene.Event(a, ev)        server moments (zapped → ragdoll, shock → camera jolt, swap ...)
      Scene.PadsPlaced(a)       you attached the pads → defibrillator case next to the patient
      Scene.Tick(a)             every frame while the code runs (anim speed, re-apply, control)
      Scene.Leave(a)            stop everything (camera, anims, props, anchors); NPC left lying
    Patient side (player patients animate themselves):
      Scene.Pose({ on, origin, mode, rate })      from the server event 'nza:cpr:pose'
      Scene.PoseStop()

    Placement (Config.Cpr.Anim.placement):
      'side'    (default) the patient's clip (mini@cpr@char_b) plays in place first, then the medic
                kneels beside the chest - the spot comes from the patient's bones (spine3 + side
                offset, Config.Cpr.Anim.kneel), facing the chest - and plays mini@cpr@char_a in
                place. Works whatever way the body lies and whether or not we own the NPC; if the
                body moves under the medic (late pose sync, someone shifts it) the medic re-kneels.
      'synced'  both clips play with TaskPlayAnimAdvanced at one shared origin (Scene.Origin).
    Patients on a bed / stretcher / in the bay are never moved: the medic stands beside them
    (Config.Cpr.Anim.bed).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Cpr = NZA.Cpr or {}
NZA.Cpr.Scene = NZA.Cpr.Scene or {}
local Sc = NZA.Cpr.Scene
local U = NZA.Util

local APP = 'cpr'
local BONE = { head = 31086, spine3 = 24818, spine2 = 24817, pelvis = 11816, rUpper = 40269, lUpper = 45509 }
local GROUP_BVM, GROUP_CASE = 'cpr_bvm', 'cpr_case'

local function cfg() return Config.Cpr or {} end
local function sub(name) return cfg()[name] or {} end
local function animCfg() return sub('Anim') end
local function synced() return animCfg().placement == 'synced' end

local function v3(t, def)
    if type(t) == 'vector3' then return t end
    if type(t) == 'table' then return vector3((tonumber(t.x) or 0) + 0.0, (tonumber(t.y) or 0) + 0.0, (tonumber(t.z) or 0) + 0.0) end
    return def or vector3(0.0, 0.0, 0.0)
end

local function flat(v)
    local l = math.sqrt(v.x * v.x + v.y * v.y)
    if l < 1e-4 then return nil end
    return vector3(v.x / l, v.y / l, 0.0)
end

local function groundZ(pos, fallback)
    local ok, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 0.6, false)
    if ok and gz ~= 0.0 and math.abs(gz - pos.z) < 2.0 then return gz end
    return fallback or pos.z
end

local function loadDict(dict)
    if type(dict) ~= 'string' then return false end
    if HasAnimDictLoaded(dict) then return true end
    local ok = pcall(lib.requestAnimDict, dict, 2500)
    return ok and HasAnimDictLoaded(dict)
end

local function requestControl(ent, ms)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    local deadline = GetGameTimer() + (ms or 600)
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        Wait(25)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

-- anim = { dict, clip }; origin = { x, y, z, h } → synced placement, nil → in place
local function play(ped, anim, origin, loop, blend)
    if type(anim) ~= 'table' or not anim[1] or not DoesEntityExist(ped) then return false end
    if not loadDict(anim[1]) then return false end
    local flag = loop and 1 or 2
    blend = blend or 4.0
    if origin then
        TaskPlayAnimAdvanced(ped, anim[1], anim[2], origin.x, origin.y, origin.z, 0.0, 0.0, origin.h,
            blend, -blend, -1, flag, 0.0, 0, 0)
    else
        TaskPlayAnim(ped, anim[1], anim[2], blend, -blend, -1, flag, 0.0, false, false, false)
    end
    return true
end

local function playing(ped, anim)
    return type(anim) == 'table' and anim[1] and DoesEntityExist(ped) and IsEntityPlayingAnim(ped, anim[1], anim[2], 3)
end

local function bone(ped, id)
    return GetPedBoneCoords(ped, id, 0.0, 0.0, 0.0)
end

-- ════════════════════════════════════════════════════════════════════════
-- ORIGIN & SPOTS
-- ════════════════════════════════════════════════════════════════════════

function Sc.Origin(ped)
    local o = animCfg().origin or {}
    local pc = GetEntityCoords(ped)
    local me = PlayerPedId()
    -- lying peds keep their root about a metre up while an anim plays; ragdolls lie on the ground
    local gz = groundZ(pc, pc.z - 0.95)
    local h = (GetEntityHeading(me) + (tonumber(o.h) or 0.0)) % 360.0
    return {
        x = pc.x + (tonumber(o.x) or 0.0), y = pc.y + (tonumber(o.y) or 0.0),
        z = gz + (tonumber(o.z) or 1.0), h = h + 0.0,
    }
end

-- body axis (pelvis → head) on the ground plane, with a fallback from the entity
local function bodyAxis(patient)
    local head, pelvis = bone(patient, BONE.head), bone(patient, BONE.pelvis)
    return flat(head - pelvis) or flat(GetEntityForwardVector(patient)) or vector3(0.0, 1.0, 0.0)
end

-- the airway partner: kneel (or stand at a bed) just beyond the head, facing the chest
local function helperSpot(patient, bed)
    local head = bone(patient, BONE.head)
    local dir = bodyAxis(patient)
    local pos = head + dir * (tonumber(animCfg().helperDist) or 0.55)
    local me = GetEntityCoords(PlayerPedId())
    local z = bed and me.z or groundZ(pos, me.z - 1.0) + 1.0
    return vector3(pos.x, pos.y, z), GetHeadingFromVector_2d(-dir.x, -dir.y)
end

-- beside the chest on the side the medic is on, facing it: `dist` metres out, `along` towards the head
local function chestSide(patient, dist, along)
    local chest = bone(patient, BONE.spine3)
    local axis = bodyAxis(patient)
    local side = vector3(-axis.y, axis.x, 0.0)
    local me = GetEntityCoords(PlayerPedId())
    local toMe = me - chest
    if toMe.x * side.x + toMe.y * side.y < 0 then side = -side end
    local pos = chest + side * dist + axis * (along or 0.0)
    return vector3(pos.x, pos.y, me.z), GetHeadingFromVector_2d(-side.x, -side.y)
end

-- a medic doing CPR at a bed / stretcher stands beside the chest
local function bedSpot(patient)
    return chestSide(patient, tonumber((animCfg().bed or {}).side) or 0.65, 0.0)
end

-- ...and kneels beside it on the ground ('side' placement)
local function kneelSpot(patient)
    local k = animCfg().kneel or {}
    return chestSide(patient, tonumber(k.side) or 0.55, tonumber(k.along) or 0.0)
end

local function moveTo(ped, pos, heading)
    TaskGoStraightToCoord(ped, pos.x, pos.y, pos.z, 1.0, 1800, heading, 0.15)
    local deadline = GetGameTimer() + 1800
    while GetGameTimer() < deadline and #(GetEntityCoords(ped) - pos) > 0.35 do Wait(50) end
    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ped, heading)
end

-- ════════════════════════════════════════════════════════════════════════
-- PAD ANCHORS (world targets for dragging the pads)
-- ════════════════════════════════════════════════════════════════════════

local function padOffsets(patient)
    local pc = sub('Pads')
    local s3, s2 = bone(patient, BONE.spine3), bone(patient, BONE.spine2)
    local ru, lu = bone(patient, BONE.rUpper), bone(patient, BONE.lUpper)
    local up = vector3(0.0, 0.0, tonumber(pc.lift) or 0.09)
    local r = s3 + (ru - s3) * (tonumber(pc.sternum) or 0.42) + up
    local l = s2 + (lu - s3) * (tonumber(pc.apex) or 0.85) + up * 0.6
    return GetOffsetFromEntityGivenWorldCoords(patient, r.x, r.y, r.z), GetOffsetFromEntityGivenWorldCoords(patient, l.x, l.y, l.z)
end

local function trackPads(a)
    if a.timed then return end   -- easy mode: no device screen, nothing to drag the pads to
    local p = a.entity
    if not p or p == 0 or not DoesEntityExist(p) then return end
    local r, l = padOffsets(p)
    NZA.Anchors.Track(APP, {
        padR = { entity = p, offset = r },
        padL = { entity = p, offset = l },
    })
    a.padsAt = GetGameTimer()
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDIC
-- ════════════════════════════════════════════════════════════════════════

local function medicAnim(a, mode)
    local A = animCfg()
    if a.bed then
        local b = A.bed or {}
        return (mode == 'compress') and b.compress or b.idle
    end
    local m = A.medic or {}
    return m[mode] or m.idle
end

local function patientAnim(mode)
    local p = animCfg().patient or {}
    return p[mode] or p.idle
end

local function npcPatient(a)
    return a.npc and a.entity and a.entity ~= 0 and DoesEntityExist(a.entity) and not IsPedAPlayer(a.entity)
end

-- 'side': lay an NPC patient in the CPR pose (in place) first, so its bones are where the body
-- stays; a player patient poses itself (nza:cpr:pose), give that a moment to reach us
local function settlePatient(a)
    if npcPatient(a) then
        if requestControl(a.entity, 800) and play(a.entity, patientAnim('idle'), nil, true, 8.0) then
            a.panim = patientAnim('idle')
        end
        Wait(300)
    elseif not a.npc then
        Wait(600)
    end
end

-- compressor: kneel beside the chest (or at the synced origin, or stand at the bed) and run the
-- pump / idle clips
local function enterComp(a, intro)
    local me = PlayerPedId()
    a.mode = nil
    if a.bed then
        local pos, h = bedSpot(a.entity)
        moveTo(me, pos, h)
        Sc.SetMode(a, 'idle')
        return
    end
    local A = animCfg()
    if not synced() then
        settlePatient(a)
        local pos, h = kneelSpot(a.entity)
        moveTo(me, pos, h)
        a.kneeling = true
        if intro and play(me, (A.medic or {}).intro, nil, false, 8.0) then
            a.introUntil = GetGameTimer() + (tonumber(A.introMs) or 1800)
        end
        Sc.SetMode(a, 'idle')
        return
    end
    if intro and play(me, (A.medic or {}).intro, a.origin, false, 8.0) then
        if npcPatient(a) and requestControl(a.entity, 800) then play(a.entity, patientAnim('intro'), a.origin, false, 8.0) end
        a.introUntil = GetGameTimer() + (tonumber(A.introMs) or 1800)
    end
    Sc.SetMode(a, 'idle')
end

local function enterAir(a)
    local me = PlayerPedId()
    a.mode, a.kneeling = nil, false
    local pos, h = helperSpot(a.entity, a.bed)
    moveTo(me, pos, h)
    local A = animCfg()
    a.helperAnim = a.bed and A.helperBed or A.helper
    play(me, a.helperAnim, nil, true)
end

-- mode = 'compress' | 'idle' | 'breath' | 'success' (compressor only)
function Sc.SetMode(a, mode)
    if a.role ~= 'comp' then return end
    if a.introUntil and GetGameTimer() < a.introUntil then a.pending = mode; return end
    if a.mode == mode and playing(PlayerPedId(), a.anim) then return end
    local me = PlayerPedId()
    local anim = medicAnim(a, mode)
    if not anim and mode == 'breath' then anim = medicAnim(a, 'idle') end
    local loop = mode ~= 'success'
    local at = (not a.bed and synced()) and a.origin or nil
    play(me, anim, at, loop)
    a.mode, a.anim = mode, anim
    if npcPatient(a) and not a.bed and NetworkHasControlOfEntity(a.entity) then
        local pa = patientAnim(mode == 'breath' and 'breath' or mode) or patientAnim('idle')
        if play(a.entity, pa, at, loop) then a.panim = pa end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- PROPS
-- ════════════════════════════════════════════════════════════════════════

local function bvmOn(a, on)
    if not on then
        if a.bvm then NZA.Props.Clear(GROUP_BVM); a.bvm = nil end
        return
    end
    if a.bvm or sub('Breaths').bvmProp == false then return end
    if not (a.view and a.view.bvm) then return end   -- mouth to mouth: no mask
    local at = sub('Breaths').bvmAttach or {}
    local ent = NZA.Props.Spawn('bvm', { attach = {
        entity = a.entity, bone = tonumber(at.bone) or BONE.head, pos = v3(at.pos, vector3(0.06, 0.11, 0.0)), rot = v3(at.rot, vector3(0.0, -90.0, -90.0)),
        collision = false,
    } }, { group = GROUP_BVM, network = true, collision = false, freeze = false })
    if ent and ent ~= 0 then a.bvm = ent end
end

function Sc.PadsPlaced(a)
    if a.case or sub('Defib').prop == false or not a.view or a.view.defib ~= 'item' then return end
    local p = a.entity
    if not p or p == 0 or not DoesEntityExist(p) then return end
    local chest = bone(p, BONE.spine3)
    local me = GetEntityCoords(PlayerPedId())
    local axis = bodyAxis(p)
    local side = vector3(-axis.y, axis.x, 0.0)
    local toMe = me - chest
    if toMe.x * side.x + toMe.y * side.y < 0 then side = -side end
    local pos = chest + side * (tonumber(sub('Defib').propOffset) or 0.75) + axis * 0.35
    local z = groundZ(pos, me.z - 1.0)
    local ent = NZA.Props.Spawn('defib', vector4(pos.x, pos.y, z, GetHeadingFromVector_2d(-side.x, -side.y)),
        { group = GROUP_CASE, network = true, ground = true })
    if ent and ent ~= 0 then a.case = ent end
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

function Sc.Enter(a)
    a.bed = a.view and a.view.bed == true or false
    local c = sub('Camera')
    if c.enabled ~= false then
        NZA.Cam.Orbit({ entity = a.entity, bone = BONE.spine3 }, {
            dist = tonumber(c.dist) or 2.7, pitch = tonumber(c.pitch) or 58.0, fov = tonumber(c.fov) or 48.0,
            minDist = 1.2, maxDist = 4.5, hideHud = true,
        })
    end
    if a.role == 'comp' then enterComp(a, true) else enterAir(a) end
    trackPads(a)
end

function Sc.Role(a)
    bvmOn(a, false)
    if a.role == 'comp' then enterComp(a, false) else enterAir(a) end
end

function Sc.Phase(a, phase)
    if phase == 'breaths' then
        if a.view and a.view.breather then bvmOn(a, true) end
        if a.role == 'comp' and a.view and a.view.breather then Sc.SetMode(a, 'breath') else Sc.SetMode(a, 'idle') end
    else
        if a.bvm then
            SetTimeout(900, function() if a.view and a.view.phase ~= 'breaths' then bvmOn(a, false) end end)
        end
        if phase == 'rosc' then
            Sc.SetMode(a, 'success')
        elseif a.mode == 'breath' or a.mode == 'success' then
            Sc.SetMode(a, 'idle')
        end
    end
end

function Sc.Press(a, rate)
    a.lastPress = GetGameTimer()
    if rate and rate > 0 then a.rate = rate end
    if a.role == 'comp' and a.mode ~= 'compress' then Sc.SetMode(a, 'compress') end
end

function Sc.Breath(a, on)
    if on then a.breathAt = GetGameTimer() end
end

function Sc.Event(a, ev)
    local me = PlayerPedId()
    if ev.kind == 'zapped' then
        local ms = tonumber(ev.ragdoll) or 1800
        SetPedToRagdoll(me, ms, ms, 0, false, false, false)
        local hp = tonumber(ev.health) or 0
        if hp > 0 then
            SetEntityHealth(me, math.max(101, GetEntityHealth(me) - hp))
            if NZA.Damage and NZA.Damage.SyncBaseline then pcall(NZA.Damage.SyncBaseline) end
        end
        a.mode = nil
        SetTimeout(ms + 600, function() if a.active and a.role == 'comp' then enterComp(a, false) end end)
    elseif ev.kind == 'shock' then
        local cam = NZA.Cam.Handle and NZA.Cam.Handle()
        if cam and cam ~= 0 and DoesCamExist(cam) then ShakeCam(cam, 'SMALL_EXPLOSION_SHAKE', 0.12) end
        if npcPatient(a) and not a.bed and NetworkHasControlOfEntity(a.entity) then
            local f = vector3(0.0, 0.0, 0.6)
            ApplyForceToEntity(a.entity, 1, f.x, f.y, f.z, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        end
    elseif ev.kind == 'analysing' or (ev.kind == 'charged') then
        if a.role == 'comp' then Sc.SetMode(a, 'idle') end
    end
end

-- every frame
function Sc.Tick(a)
    local me = PlayerPedId()
    local now = GetGameTimer()
    -- kneeling right against the body: the two capsules must not shove the medic off the chest
    if a.kneeling and a.entity and DoesEntityExist(a.entity) then SetEntityNoCollisionEntity(me, a.entity, true) end
    if a.introUntil and now >= a.introUntil then
        a.introUntil = nil
        Sc.SetMode(a, a.pending or 'idle')
        a.pending = nil
    end
    if a.role == 'comp' and not a.introUntil then
        local compressing = a.lastPress and now - a.lastPress < 1100
        local ph = a.view and a.view.phase
        if ph ~= 'breaths' and ph ~= 'rosc' and a.mode ~= 'success' then
            local want = compressing and 'compress' or 'idle'
            if a.mode ~= want then Sc.SetMode(a, want) end
        end
        if a.mode == 'compress' and a.anim then
            local base = tonumber(animCfg().baseRate) or 105
            local speed = U.clamp((a.rate or base) / base, 0.6, 1.6)
            SetEntityAnimSpeed(me, a.anim[1], a.anim[2], speed)
            if a.panim and npcPatient(a) then SetEntityAnimSpeed(a.entity, a.panim[1], a.panim[2], speed) end
        end
    end
    -- re-apply what got interrupted (ragdoll, other scripts) twice a second
    if not a.checkAt or now >= a.checkAt then
        a.checkAt = now + 500
        if not IsPedRagdoll(me) then
            if a.role == 'comp' and not a.introUntil and a.anim and a.mode ~= 'success' and not playing(me, a.anim) then
                local m = a.mode; a.mode = nil; Sc.SetMode(a, m or 'idle')
            elseif a.role ~= 'comp' and a.helperAnim and not playing(me, a.helperAnim) then
                play(me, a.helperAnim, nil, true)
            end
        end
        -- the compressor animates an NPC patient (control may arrive late, e.g. right after a swap)
        if a.role == 'comp' and npcPatient(a) and not a.bed and not a.introUntil and a.mode ~= 'success' then
            if not NetworkHasControlOfEntity(a.entity) then
                NetworkRequestControlOfEntity(a.entity)
            else
                local want = patientAnim(a.mode == 'breath' and 'breath' or (a.mode or 'idle')) or patientAnim('idle')
                if not playing(a.entity, want) and play(a.entity, want, synced() and a.origin or nil, true) then a.panim = want end
            end
        end
        -- 'side': stay beside the chest (a player's pose can arrive late, or the body gets moved)
        if a.role == 'comp' and a.kneeling and not a.bed and not a.introUntil and a.mode ~= 'success' and not IsPedRagdoll(me) then
            local pos, h = kneelSpot(a.entity)
            local mc = GetEntityCoords(me)
            if #(vector2(pos.x, pos.y) - vector2(mc.x, mc.y)) > (tonumber((animCfg().kneel or {}).drift) or 0.35) then
                SetEntityCoordsNoOffset(me, pos.x, pos.y, mc.z, false, false, false)
                SetEntityHeading(me, h)
            end
        end
        if not a.padsAt or now - a.padsAt > 1500 then trackPads(a) end
    end
end

function Sc.Leave(a)
    if a.left then return end
    a.left = true
    local me = PlayerPedId()
    NZA.Anchors.Clear(APP)
    NZA.Cam.Stop(600)
    bvmOn(a, false)
    if a.case then NZA.Props.Clear(GROUP_CASE); a.case = nil end
    if a.anim and a.anim[1] then StopAnimTask(me, a.anim[1], a.anim[2], 2.0) end
    if a.helperAnim and a.helperAnim[1] then StopAnimTask(me, a.helperAnim[1], a.helperAnim[2], 2.0) end
    ClearPedTasks(me)
    -- an NPC stays on the ground (the transport module takes it from here)
    if npcPatient(a) and not a.bed and a.role == 'comp' then
        CreateThread(function()
            if requestControl(a.entity, 800) then
                local rest = animCfg().npcRest
                if type(rest) == 'table' and loadDict(rest[1]) then
                    TaskPlayAnim(a.entity, rest[1], rest[2], 2.0, -2.0, -1, 1, 0.0, false, false, false)
                end
            end
        end)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT SIDE (a player patient lies flat in the CPR pose)
-- ════════════════════════════════════════════════════════════════════════

local pose = nil   -- { origin, mode, rate, anim }

local function suspendWounded(on)
    if NZA.Wounded and NZA.Wounded.SuspendPose then pcall(NZA.Wounded.SuspendPose, 'cpr', on) end
end

local function poseAnim(mode)
    return patientAnim(mode) or patientAnim('idle')
end

function Sc.PoseStop()
    if not pose then return end
    local p = pose
    pose = nil
    local me = PlayerPedId()
    if p.anim and p.anim[1] then StopAnimTask(me, p.anim[1], p.anim[2], 2.0) end
    suspendWounded(false)
end

function Sc.Pose(d)
    if type(d) ~= 'table' then return end
    if not d.on then return Sc.PoseStop() end
    local o = d.origin
    if type(o) ~= 'table' or not tonumber(o.x) then return end
    local origin = { x = o.x + 0.0, y = o.y + 0.0, z = o.z + 0.0, h = (tonumber(o.h) or 0.0) + 0.0 }
    local first = pose == nil
    pose = pose or {}
    pose.origin, pose.rate = origin, tonumber(d.rate) or 0
    local mode = d.mode == 'compress' and 'compress' or 'idle'
    if first then
        suspendWounded(true)
        local me = PlayerPedId()
        -- 'side' placement: in place and no intro, so the body stays where the medic kneels beside it
        if synced() and play(me, poseAnim('intro'), origin, false, 8.0) then pose.introUntil = GetGameTimer() + (tonumber(animCfg().introMs) or 1800) end
        CreateThread(function()
            while pose do
                local p = pose
                local me2 = PlayerPedId()
                local now = GetGameTimer()
                local st = NZA.Self.State()
                if st == 'alive' or st == 'dead' then Sc.PoseStop(); break end
                if not p.introUntil or now >= p.introUntil then
                    p.introUntil = nil
                    local want = poseAnim(p.mode)
                    if (p.anim ~= want or not playing(me2, want)) and not IsPedRagdoll(me2) and (not p.retryAt or now >= p.retryAt) then
                        play(me2, want, synced() and p.origin or nil, true)
                        p.anim = want
                        p.retryAt = now + 500
                    end
                    if p.mode == 'compress' and p.anim then
                        local base = tonumber(animCfg().baseRate) or 105
                        SetEntityAnimSpeed(me2, p.anim[1], p.anim[2], U.clamp((p.rate > 0 and p.rate or base) / base, 0.6, 1.6))
                    end
                end
                Wait(0)
            end
        end)
    end
    pose.mode = mode
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if pose then Sc.PoseStop() end
end)
