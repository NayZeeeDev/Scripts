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

--- The prop to show for a shoe: its own, or the stand-in for its box size when it has none yet
--- (shoes added in the studio before the app made their props)
function ShoeProp(shoe)
    if not shoe then return nil end
    if IsModelInCdimage(shoe.prop) then return shoe.prop end
    local name = Config.Studio and Config.Studio.StandIn and Config.Studio.StandIn[shoe.box or 'shoe']
    return name and GetHashKey(name) or shoe.prop
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

-- GTA's own first-person camera, for the "first person" work view
local fpPrev

local function leaveFirstPerson()
    if fpPrev then
        SetFollowPedCamViewMode(fpPrev)
        fpPrev = nil
    end
end

--- Switches to the game's real first-person camera (drops any scripted camera)
function Cam.FirstPerson()
    if not Config.FirstPerson then return end
    if cam then
        RenderScriptCams(false, true, 500, true, false)
        DestroyCam(cam, false)
        cam = nil
    end
    if not fpPrev then fpPrev = GetFollowPedCamViewMode() end
    SetFollowPedCamViewMode(4)
end

--- Point the camera at `target` from `pos`. If a camera is already up it glides
--- over (so switching views mid-work is smooth); otherwise it eases in from gameplay.
function Cam.Shot(pos, target, fov, ms)
    if not Config.FirstPerson then return end
    leaveFirstPerson()
    ms = ms or 700
    local old = cam
    local new = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov or 50.0, false, 2)
    PointCamAtCoord(new, target.x, target.y, target.z)
    SetCamUseShallowDofMode(new, true)
    SetCamNearDof(new, 0.05)
    SetCamFarDof(new, #(pos - target) + 0.8)
    SetCamDofStrength(new, 0.65)
    cam = new
    if old then
        SetCamActiveWithInterp(new, old, ms, 1, 1)
        SetTimeout(ms + 100, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else
        SetCamActive(new, true)
        RenderScriptCams(true, true, ms, true, false)
        dofLoop()
    end
end

--------------------------------------------------------------------------------
-- Work views: the player picks how crafting and cleaning are shot
--------------------------------------------------------------------------------

Views = { order = { 'three', 'first', 'close' } }

local function valid(v) for _, x in ipairs(Views.order) do if x == v then return true end end end

--- The player's saved view (or the server default)
function Views.Get()
    local v = GetResourceKvpString('nzs_view')
    if Config.Camera.Switch and valid(v) then return v end
    return valid(Config.Camera.Default) and Config.Camera.Default or 'three'
end

function Views.Set(v)
    if valid(v) then SetResourceKvp('nzs_view', v) end
end

function Views.Next(v)
    for i, x in ipairs(Views.order) do
        if x == v then return Views.order[i % #Views.order + 1] end
    end
    return Views.order[1]
end

function Views.Label(v)
    return Config.Text[({ three = 'viewThree', first = 'viewFirst', close = 'viewClose' })[v] or 'viewThree']
end

--- Shows one view. shots = { three = {pos, look, fov}, first = 'native' | {pos, look, fov}, ... }
function Views.Show(view, shots)
    local s = shots[view]
    if s == 'native' then Cam.FirstPerson()
    elseif s then Cam.Shot(s[1], s[2], s[3]) end
end

--- Inside a work loop: V switches to the next view
function Views.Poll(current, shots)
    if not Config.Camera.Switch then return current end
    DisableControlAction(0, 0, true)   -- V (next camera)
    if IsDisabledControlJustPressed(0, 0) then
        current = Views.Next(current)
        Views.Show(current, shots)
        Views.Set(current)
        UI.Notify(Views.Label(current), 'inform')
    end
    return current
end

function Cam.Stop(instant)
    leaveFirstPerson()
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
