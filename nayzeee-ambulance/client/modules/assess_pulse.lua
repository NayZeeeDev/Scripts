--[[
    NAYZEEE AMBULANCE - Check Pulse (client)                 NUI app 'pulse', NZA.Proc 'pulse'

    Runs the server procedure 'pulse' through NZA.Proc.Run (easy mode = core progress bar).
    The medic kneels with a hand on the patient, the camera closes in on the site
    (Config.Assess.Pulse.camera) and follows when the medic switches between the carotid
    (neck) and the radial artery (wrist; the left wrist when the right arm has a tourniquet).
    World anchors for the app: 'carotid' (neck bone) and 'radial' (hand bone).

    NUI callbacks: pulse:site { site }, pulse:finish (result), pulse:abort, pulse:close
    The result card comes from the server outcome (truth is only revealed after finishing).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Assess = NZA.Assess or {}
NZA.Assess.Start = NZA.Assess.Start or {}
local A = NZA.Assess

local APP = 'pulse'
local BONE_NECK, BONE_R_HAND, BONE_L_HAND = 39317, 57005, 18905

local function radialBone(ctx)
    local d = ctx and ctx.data
    local side = d and d.sites and d.sites.radial and d.sites.radial.side
    return side == 'left' and BONE_L_HAND or BONE_R_HAND
end

local function camTo(s, site)
    local cam = A.Cfg('Pulse').camera
    if not cam or cam.mode == false or cam == false then return end
    if cam.mode == 'close' then
        A.Cam('close', s.entity, {
            bone = site == 'carotid' and BONE_NECK or radialBone(s.ctx),
            dist = cam.dist, pitch = cam.pitch, fov = cam.fov,
        })
    else
        A.Cam(cam.mode or 'orbit', s.entity, cam)
    end
end

function A.Start.pulse(entity, target, keepPose)
    A.RunProc({
        name = 'pulse', app = APP, entity = entity, target = target, keepPose = keepPose,
        label = NZA.L('assess.pulse_title'),
        setup = function(ctx, s)
            A.Anim(PlayerPedId(), A.Cfg('Pulse').anim, 1)
            s.site = (ctx.data and ctx.data.start) or 'radial'
            camTo(s, s.site)
        end,
        anchors = function(ent, ctx)
            return {
                carotid = { entity = ent, bone = BONE_NECK },
                radial = { entity = ent, bone = radialBone(ctx) },
            }
        end,
    })
end

NZA.UI.On(APP, 'site', function(data, cb)
    cb({ ok = true })
    local s = A.Session(APP)
    if not s or type(data) ~= 'table' then return end
    local site = data.site == 'carotid' and 'carotid' or 'radial'
    if s.site == site then return end
    s.site = site
    camTo(s, site)
end)

-- finish / abort / close are the same for every assessment procedure (assess.lua)
CreateThread(function()
    Wait(0)
    A.ProcCallbacks(APP)
end)
