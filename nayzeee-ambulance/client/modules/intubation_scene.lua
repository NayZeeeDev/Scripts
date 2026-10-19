--[[
    NAYZEEE AMBULANCE - Airway (client): the world side of a BVM round / intubation

      NZA.Intubation.Scene.Begin(entity, mode, opts) → scene     medic walks to the head and
          kneels (ground) or stands (bed / stretcher), suction unit + monitor on the ground
          beside the head (intubation), mask on the face, camera on the face
      NZA.Intubation.Scene.Phase(scene, phase, info)              props / camera / hands per
          minigame phase: preox position reox bvm (mask on the face, bag anchor) · suction ·
          insert lift (laryngoscope in the left hand) · tube (+ tube in the right hand) ·
          cuff (tube at the mouth, syringe) · confirm (bag on the tube) · done (info.placed)
      NZA.Intubation.Scene.End(scene, keepTube)                    removes everything it made
      NZA.Intubation.Scene.Geometry(entity) → head, feet dir, right dir, onBed

    Props come from Config.Props (bvm, suction, laryngoscope, ett, syringe, monitor) with the
    offsets of Config.Intubation.props; the app gets the anchors 'bvm' (bag) and 'mouth'.
    World tubes: every client shows Config.Props.ett at the mouth of patients whose state bag
    says intub (Config.Intubation.worldTube / worldRange), except during its own scene.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Intubation = NZA.Intubation or {}
NZA.Intubation.Scene = NZA.Intubation.Scene or {}
local Sc = NZA.Intubation.Scene
local APP = 'intubation'
local GROUP = 'intubation_scene'
local HEAD = 31086
local PELVIS = 11816
local DEG = math.pi / 180.0

local function cfg() return Config.Intubation or {} end
local function sub(k)
    local c = cfg()[k]
    return type(c) == 'table' and c or {}
end
local function vec(t, d)
    if type(t) == 'vector3' then return t end
    if type(t) == 'table' then return vector3(tonumber(t[1] or t.x) or 0.0, tonumber(t[2] or t.y) or 0.0, tonumber(t[3] or t.z) or 0.0) end
    return d or vector3(0.0, 0.0, 0.0)
end
local function norm(v)
    local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if l < 1e-6 then return vector3(0.0, 1.0, 0.0) end
    return vector3(v.x / l, v.y / l, v.z / l)
end

-- ════════════════════════════════════════════════════════════════════════
-- GEOMETRY
-- ════════════════════════════════════════════════════════════════════════

function Sc.Geometry(entity)
    local head = GetPedBoneCoords(entity, HEAD, 0.0, 0.0, 0.0)
    local pelvis = GetPedBoneCoords(entity, PELVIS, 0.0, 0.0, 0.0)
    local d = pelvis - head
    local feet = norm(vector3(d.x, d.y, 0.0))
    local right = vector3(feet.y, -feet.x, 0.0)     -- feet × up: the patient's right when supine
    local okG, gz = GetGroundZFor_3dCoord(head.x, head.y, head.z + 0.5, false)
    local ground = okG and gz or (GetEntityCoords(entity).z - 1.0)
    local onBed = head.z - ground > (tonumber(sub('anim').bedHeight) or 0.55)
    return head, feet, right, onBed, ground
end

local function onGround(S, side, forward)
    local p = S.head + S.right * side + S.feet * forward
    local okG, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 0.8, false)
    return vector3(p.x, p.y, okG and gz or S.ground)
end

local function headingOf(v) return (math.atan(v.y, v.x) / DEG) - 90.0 end

-- ════════════════════════════════════════════════════════════════════════
-- PROPS
-- ════════════════════════════════════════════════════════════════════════

local function net() return cfg().networkProps == true end

local function del(S, key)
    local e = S.props[key]
    if e and e ~= 0 then pcall(NZA.Props.Delete, e) end
    S.props[key] = nil
end

local function attach(S, key, model, entity, def)
    if S.props[key] and S.props[key] ~= 0 and DoesEntityExist(S.props[key]) then return S.props[key] end
    if not entity or entity == 0 or not DoesEntityExist(entity) or not def then return 0 end
    local ok, ent = pcall(NZA.Props.Spawn, model, { attach = { entity = entity, bone = def.bone or HEAD, pos = vec(def.pos), rot = vec(def.rot), collision = false } },
        { group = GROUP, network = net(), collision = false })
    S.props[key] = ok and ent or 0
    return S.props[key]
end

local function place(S, key, model, pos, heading)
    if S.props[key] and S.props[key] ~= 0 then return S.props[key] end
    local ok, ent = pcall(NZA.Props.Spawn, model, pos, { group = GROUP, network = net(), heading = heading, ground = true, collision = false })
    S.props[key] = ok and ent or 0
    return S.props[key]
end

local function setHands(S, left, right)
    local P = sub('props')
    if left == 'scope' then attach(S, 'scope', 'laryngoscope', PlayerPedId(), P.laryngoscope) else del(S, 'scope') end
    if right == 'tube' then
        del(S, 'syringe')
        attach(S, 'tubeHand', 'ett', PlayerPedId(), P.tubeHand)
    elseif right == 'syringe' then
        del(S, 'tubeHand')
        attach(S, 'syringe', 'syringe', PlayerPedId(), P.syringe)
    else
        del(S, 'tubeHand'); del(S, 'syringe')
    end
end

local function setFace(S, what)
    local P = sub('props')
    if what == 'mask' then
        del(S, 'bvmEtt'); del(S, 'ett')
        attach(S, 'bvm', 'bvm', S.entity, P.bvm)
    elseif what == 'tube' then
        del(S, 'bvm'); del(S, 'bvmEtt')
        attach(S, 'ett', 'ett', S.entity, P.ett)
    elseif what == 'tubebag' then
        del(S, 'bvm')
        attach(S, 'ett', 'ett', S.entity, P.ett)
        attach(S, 'bvmEtt', 'bvm', S.entity, P.bvmEtt)
    else
        del(S, 'bvm'); del(S, 'bvmEtt'); del(S, 'ett')
    end
    S.face = what
end

-- ════════════════════════════════════════════════════════════════════════
-- CAMERA / ANIMATION / ANCHORS
-- ════════════════════════════════════════════════════════════════════════

local function camera(S, name)
    local c = sub('camera')
    if c.enabled == false or S.cam == name then return end
    local o = type(c[name]) == 'table' and c[name] or c.preox or {}
    S.cam = name
    -- yaw 0 = above the top of the head looking down the body, + towards the patient's right
    local a = (tonumber(o.yaw) or 0.0) * DEG
    local d = (S.feet * -math.cos(a)) + (S.right * math.sin(a))
    local yaw = math.atan(d.y, d.x) / DEG
    pcall(NZA.Cam.Orbit, { entity = S.entity, bone = HEAD }, {
        dist = tonumber(o.dist) or 1.0, pitch = tonumber(o.pitch) or 45.0, yaw = yaw, fov = tonumber(o.fov) or 44.0,
        minDist = 0.35, maxDist = 3.2, minPitch = 5.0, maxPitch = 85.0, ease = tonumber(c.ease) or 650, hideHud = true,
    })
end

local function pose(S)
    local me = PlayerPedId()
    local a = sub('anim')
    local an = S.onBed and a.stand or a.kneel
    if type(an) ~= 'table' or not an.dict then return end
    local ok, token = pcall(NZA.Anim.Play, me, an.dict, an.clip, { flag = 1, blendIn = 3.0, blendOut = -3.0 })
    if ok then S.anim = token end
end

local function walkTo(S)
    local me = PlayerPedId()
    local off = tonumber(sub('anim').headOffset) or 0.62
    local spot = S.head - S.feet * off
    local okG, gz = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 0.8, false)
    if okG then spot = vector3(spot.x, spot.y, gz) end
    local heading = headingOf(S.feet)
    local cur = GetEntityCoords(me)
    if #(vector3(cur.x, cur.y, 0.0) - vector3(spot.x, spot.y, 0.0)) > 0.3 then
        ClearPedTasks(me)
        TaskGoStraightToCoord(me, spot.x, spot.y, spot.z, 1.0, 3500, heading, 0.15)
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < 3600 and #(GetEntityCoords(me).xy - spot.xy) > 0.25 and not S.ended do Wait(100) end
    end
    if S.ended then return end
    SetEntityHeading(me, heading)
end

local function trackAnchors(S)
    local map = { mouth = { entity = S.entity, bone = HEAD, offset = vector3(0.0, 0.12, -0.04) } }
    local bag = S.props.bvm or S.props.bvmEtt
    if bag and bag ~= 0 and DoesEntityExist(bag) then map.bvm = { entity = bag, offset = vector3(0.0, 0.21, 0.095) } end
    pcall(NZA.Anchors.Track, APP, map)
end

-- ════════════════════════════════════════════════════════════════════════
-- SCENE
-- ════════════════════════════════════════════════════════════════════════

function Sc.Begin(entity, mode, opts)
    opts = opts or {}
    local head, feet, right, onBed, ground = Sc.Geometry(entity)
    local S = { entity = entity, mode = mode, head = head, feet = feet, right = right, onBed = onBed, ground = ground,
        props = {}, ended = false, easy = opts.easy == true }
    Sc.active = S
    walkTo(S)
    if S.ended then return S end
    pose(S)
    if mode == 'intubate' then
        local P = sub('props')
        local su = P.suction or {}
        local sp = onGround(S, tonumber(su.side) or 0.62, tonumber(su.forward) or -0.15)
        place(S, 'suction', 'suction', sp, headingOf(S.right * -1.0))
        if cfg().monitorProp ~= false and not opts.noMonitor then
            local mo = P.monitor or {}
            local mp = onGround(S, tonumber(mo.side) or -0.7, tonumber(mo.forward) or 0.2)
            place(S, 'monitor', 'monitor', mp, headingOf(S.right))
        end
    end
    if opts.intubated then setFace(S, 'tubebag') else setFace(S, 'mask') end
    camera(S, mode == 'bvm' and 'bvm' or 'preox')
    trackAnchors(S)
    return S
end

local PHASES = {
    preox    = { face = 'mask', cam = 'preox' },
    reox     = { face = 'mask', cam = 'preox' },
    position = { face = 'mask', cam = 'preox' },
    bvm      = { face = 'mask', cam = 'bvm' },
    suction  = { face = 'none', cam = 'scope' },
    insert   = { face = 'none', cam = 'scope', left = 'scope' },
    lift     = { face = 'none', cam = 'scope', left = 'scope' },
    tube     = { face = 'none', cam = 'scope', left = 'scope', right = 'tube' },
    cuff     = { face = 'tube', cam = 'scope', right = 'syringe' },
    confirm  = { face = 'tubebag', cam = 'confirm' },
}

function Sc.Phase(S, phase, info)
    if not S or S.ended then return end
    info = info or {}
    if phase == 'done' then
        setHands(S, nil, nil)
        if S.mode == 'bvm' then
            setFace(S, S.face == 'tubebag' and 'tube' or 'none')
        elseif info.placed == 'trachea' or info.placed == 'oesophagus' then
            setFace(S, 'tube')
        else
            setFace(S, 'mask')
        end
        camera(S, 'confirm')
        trackAnchors(S)
        return
    end
    local ph = PHASES[phase]
    if not ph then return end
    local face = ph.face
    if S.mode == 'bvm' and S.face == 'tubebag' then face = 'tubebag' end
    if face ~= S.face then setFace(S, face) end
    setHands(S, ph.left, ph.right)
    camera(S, ph.cam)
    trackAnchors(S)
end

function Sc.End(S)
    if not S or S.ended then return end
    S.ended = true
    if Sc.active == S then Sc.active = nil end
    pcall(NZA.Anchors.Clear, APP)
    pcall(NZA.Props.Clear, GROUP)
    S.props = {}
    pcall(NZA.Cam.Stop, 600)
    pcall(NZA.Anim.Stop, PlayerPedId(), { token = S.anim })
end

-- ════════════════════════════════════════════════════════════════════════
-- WORLD TUBES (everyone sees the tube at the mouth of intubated patients)
-- ════════════════════════════════════════════════════════════════════════

local worldTubes = {}    -- ped → prop

local function dropWorld(ped)
    local e = worldTubes[ped]
    if e and e ~= 0 then pcall(NZA.Props.Delete, e) end
    worldTubes[ped] = nil
end

local function intubated(ped)
    local bag = NZA.Target.State(ped)
    return type(bag) == 'table' and bag.intub == true and bag.bag ~= true
end

CreateThread(function()
    while true do
        if cfg().worldTube == false then
            for ped in pairs(worldTubes) do dropWorld(ped) end
            Wait(3000)
        else
            local range = tonumber(cfg().worldRange) or 45.0
            local me = PlayerPedId()
            local mc = GetEntityCoords(me)
            local seen = {}
            local scene = Sc.active
            local cands = NZA.Scan.Peds()
            for _, pl in ipairs(GetActivePlayers()) do cands[#cands + 1] = GetPlayerPed(pl) end
            for _, ped in ipairs(cands) do
                if DoesEntityExist(ped) and #(GetEntityCoords(ped) - mc) <= range and intubated(ped)
                    and not (scene and scene.entity == ped) then
                    seen[ped] = true
                    if not worldTubes[ped] or not DoesEntityExist(worldTubes[ped]) then
                        local def = sub('props').ett
                        local ok, ent = pcall(NZA.Props.Spawn, 'ett', { attach = { entity = ped, bone = (def and def.bone) or HEAD,
                            pos = vec(def and def.pos), rot = vec(def and def.rot), collision = false } }, { group = 'intubation_world', collision = false })
                        worldTubes[ped] = ok and ent or 0
                    end
                end
            end
            for ped in pairs(worldTubes) do
                if not seen[ped] then dropWorld(ped) end
            end
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Sc.active then Sc.End(Sc.active) end
    pcall(NZA.Props.Clear, 'intubation_world')
    pcall(NZA.Props.Clear, GROUP)
end)
