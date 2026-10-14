--[[
    NAYZEEE AMBULANCE - Check Breathing (client)     NUI app 'breathing', NZA.Proc 'breathing'

    Runs the server procedure 'breathing' through NZA.Proc.Run (easy mode = core progress bar).
    Camera close-up on the chest (Config.Assess.Breathing.camera). The 6 auscultation zones
    are computed every frame from the patient's skeleton (spine, neck and clavicle bones →
    left/right, up and anterior axes) so the anchors sit on the front of the chest whatever
    pose the patient is in; they are streamed to the app with the local anchor streamer
    (NZA.Assess.Track(..., own = true)):  chest, ru, rm, rl, lu, lm, ll.
    Step 2 puts the stethoscope (Config.Props.stethoscope) in the medic's right hand.

    NUI callbacks: breathing:step { step }, breathing:finish (result), breathing:abort, breathing:close
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Assess = NZA.Assess or {}
NZA.Assess.Start = NZA.Assess.Start or {}
local A = NZA.Assess

local APP = 'breathing'
local B = { s3 = 24818, s2 = 24817, s1 = 24816, neck = 39317, lcl = 64729, rcl = 10706 }

local function norm(v)
    local l = #v
    if l < 0.0001 then return vector3(0.0, 0.0, 1.0) end
    return v / l
end

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

-- chest surface points, computed once per frame per patient
local cache = { frame = -1, ent = 0, pts = nil }
local function geometry(ent)
    local f = GetFrameCount()
    if cache.frame == f and cache.ent == ent and cache.pts then return cache.pts end
    local function bone(id) return GetPedBoneCoords(ent, id, 0.0, 0.0, 0.0) end
    local s3, s2, s1 = bone(B.s3), bone(B.s2), bone(B.s1)
    local neck, lcl, rcl = bone(B.neck), bone(B.lcl), bone(B.rcl)
    local lat = norm(lcl - rcl)                 -- patient's right → left
    local up = norm(neck - s1)                  -- towards the head
    local ant = norm(cross(lat, up))            -- out of the front of the chest
    local upper, mid, lower = s3 + ant * 0.13, s2 + ant * 0.15, s1 + ant * 0.13
    cache.frame, cache.ent = f, ent
    cache.pts = {
        chest = mid,
        ru = upper - lat * 0.085 + up * 0.03, lu = upper + lat * 0.085 + up * 0.03,
        rm = mid - lat * 0.11, lm = mid + lat * 0.11,
        rl = lower - lat * 0.12 + up * 0.03, ll = lower + lat * 0.12 + up * 0.03,
    }
    return cache.pts
end

local function zoneDefs(ent)
    local defs = {}
    for _, id in ipairs({ 'chest', 'ru', 'rm', 'rl', 'lu', 'lm', 'll' }) do
        defs[id] = { fn = function()
            if not DoesEntityExist(ent) then return nil end
            return geometry(ent)[id]
        end }
    end
    return defs
end

local function stethoscope(on)
    A.ClearProps()
    if not on then return end
    local pc = A.Cfg('Breathing').prop or {}
    local model = Config.Props and Config.Props.stethoscope
    if not model then return end
    A.Prop(model, {
        entity = PlayerPedId(), bone = pc.bone or 57005,
        pos = pc.pos or vec3(0.12, 0.03, -0.02), rot = pc.rot or vec3(-80.0, 0.0, 0.0),
    })
end

function A.Start.breathing(entity, target, keepPose)
    A.RunProc({
        name = 'breathing', app = APP, entity = entity, target = target, keepPose = keepPose,
        label = NZA.L('assess.breath_title'),
        ownAnchors = true,
        setup = function(ctx, s)
            local bc = A.Cfg('Breathing')
            A.Anim(PlayerPedId(), bc.anim, 1)
            local cam = bc.camera
            if cam and cam.mode then
                A.Cam(cam.mode, entity, { bone = B.s2, dist = cam.dist, pitch = cam.pitch, fov = cam.fov, height = cam.height })
            end
            s.stetho = ctx.data and ctx.data.stetho == true
        end,
        anchors = function(ent) return zoneDefs(ent) end,
        teardown = function() stethoscope(false) end,
    })
end

NZA.UI.On(APP, 'step', function(data, cb)
    cb({ ok = true })
    local s = A.Session(APP)
    if not s or type(data) ~= 'table' then return end
    local step = tonumber(data.step)
    if step == 2 then
        stethoscope(s.stetho)
        local listen = A.Cfg('Breathing').listenAnim
        if listen then A.Anim(PlayerPedId(), listen, 1) end
    elseif step == 3 then
        stethoscope(false)
    end
end)

CreateThread(function()
    Wait(0)
    A.ProcCallbacks(APP)
end)
