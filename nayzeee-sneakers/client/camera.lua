--[[
    Close-up "first person" cameras for interactions: the camera sits just in
    front of the player's face and looks at what they're handling, with the
    background softly out of focus.
]]

Cam = {}

--- ox_lib's loaders throw on timeout; these return true/false instead
function LoadModel(model)
    return IsModelInCdimage(model) and pcall(lib.requestModel, model, 5000) or false
end

function LoadAnimDict(dict)
    return (pcall(lib.requestAnimDict, dict, 3000))
end

local cam
local HEAD = 31086

local function dofLoop()
    CreateThread(function()
        while cam do
            SetUseHiDof()
            Wait(0)
        end
    end)
end

--- Point a close-up camera from the player's eyes at `target` (vector3)
function Cam.LookAt(target, fov)
    if not Config.FirstPerson then return end
    Cam.Stop(true)
    local ped = PlayerPedId()
    local from = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0) + GetEntityForwardVector(ped) * 0.14 + vector3(0.0, 0.0, 0.03)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', from.x, from.y, from.z, 0.0, 0.0, 0.0, fov or 55.0, false, 2)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamUseShallowDofMode(cam, true)
    SetCamNearDof(cam, 0.05)
    SetCamFarDof(cam, #(from - target) + 0.6)
    SetCamDofStrength(cam, 0.7)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, false)
    dofLoop()
    return cam, from
end

--- Raw camera for custom views (inspect). Caller positions it.
function Cam.Create(pos, target, fov)
    Cam.Stop(true)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov or 50.0, false, 2)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamUseShallowDofMode(cam, true)
    SetCamNearDof(cam, 0.05)
    SetCamFarDof(cam, #(pos - target) + 0.35)
    SetCamDofStrength(cam, 0.9)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 450, true, false)
    dofLoop()
    return cam
end

function Cam.Stop(instant)
    if not cam then return end
    RenderScriptCams(false, not instant, instant and 0 or 600, true, false)
    DestroyCam(cam, false)
    cam = nil
end

--------------------------------------------------------------------------------
-- Animations used by the interactions
--------------------------------------------------------------------------------

Anim = {}

local KNEEL = { 'amb@medic@standing@kneel@base', 'base' }
local PUTDOWN = { 'pickup_object', 'putdown_low' }
local PICKUP = { 'pickup_object', 'pickup_low' }

local function play(a, duration, flag)
    local ped = PlayerPedId()
    if not LoadAnimDict(a[1]) then return end
    TaskPlayAnim(ped, a[1], a[2], 4.0, -4.0, duration or -1, flag or 1, 0.0, false, false, false)
    RemoveAnimDict(a[1])
end

function Anim.Kneel() play(KNEEL, -1, 1) end
function Anim.PutDown() play(PUTDOWN, 1000, 0) end
function Anim.PickUp() play(PICKUP, 1000, 0) end
function Anim.Stop() ClearPedTasks(PlayerPedId()) end

function Anim.Face(entity)
    TaskTurnPedToFaceEntity(PlayerPedId(), entity, 600)
    Wait(650)
end
