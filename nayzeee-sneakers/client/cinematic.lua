--[[
    Cinematic tools for the handover (same camera work as nayzeee-vehiclecargo).

    One scripted camera steered by hand every frame: its position glides to the
    shot and it always looks at the current subject, so a shot can follow a
    walking ped or a car pulling away instead of staring at a fixed spot.

      local cam = Cine.Director()
      cam.cut({ pos = Cine.Fixed(v), look = Cine.At(ent, 0, 0, 0.5), fov = 40 })   -- jump
      cam.go({ ... , speed = 0.04 })                                              -- glide
]]

Cine = { skip = false, on = false }

local function lookRot(from, to)
    local d = to - from
    local flat = math.sqrt(d.x * d.x + d.y * d.y)
    return math.deg(math.atan(d.z, flat)), -math.deg(math.atan(d.x, d.y))
end

function Cine.At(ent, x, y, z)
    return function() return DoesEntityExist(ent) and GetOffsetFromEntityInWorldCoords(ent, x, y, z) or nil end
end
function Cine.Fixed(v) return function() return v end end
function Cine.Between(a, b, z)
    return function()
        if not DoesEntityExist(a) or not DoesEntityExist(b) then return nil end
        return (GetEntityCoords(a) + GetEntityCoords(b)) / 2 + vector3(0.0, 0.0, z or 0.4)
    end
end

-- shot = { pos = fn() -> vector3, look = fn() -> vector3, fov, speed (0..1 per frame) }
function Cine.Director()
    local self = { cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true), on = true }
    function self.cut(shot)
        self.shot = shot
        self.p, self.l = shot.pos(), shot.look()
    end
    function self.go(shot) self.shot = shot end
    CreateThread(function()
        while self.on do
            local sh = self.shot
            if sh then
                local wp, wl = sh.pos(), sh.look()
                if wp and wl then
                    local k = sh.speed or 0.05
                    self.p = self.p and (self.p + (wp - self.p) * k) or wp
                    self.l = self.l and (self.l + (wl - self.l) * math.min(1.0, k * 2.5)) or wl
                    SetCamCoord(self.cam, self.p.x, self.p.y, self.p.z)
                    local pitch, yaw = lookRot(self.p, self.l)
                    SetCamRot(self.cam, pitch, 0.0, yaw, 2)
                    SetCamFov(self.cam, sh.fov or 42.0)
                end
            end
            Wait(0)
        end
    end)
    function self.stop()
        self.on = false
        RenderScriptCams(false, true, 1100, true, false)
        DestroyCam(self.cam, false)
    end
    return self
end

--- Letterbox on, radar off, controls locked. ENTER / BACKSPACE sets Cine.skip.
function Cine.Start()
    Cine.on, Cine.skip = true, false
    CreateThread(function()
        while Cine.on do
            DisableAllControlActions(0)
            EnableControlAction(0, 249, true)   -- push to talk
            if Config.Cinematic.Skip and (IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 177)) then
                Cine.skip = true
            end
            Wait(0)
        end
    end)
    SendNUIMessage({ action = 'cine', on = true, skip = Config.Cinematic.Skip and Config.Text.skip or nil })
    DisplayRadar(false)
end

function Cine.Stop()
    Cine.on = false
    SendNUIMessage({ action = 'cine', on = false })
    DisplayRadar(true)
end

--- A line from the buyer along the bottom of the screen
function Cine.Say(who, list)
    if not Config.Cinematic.Subtitles or not list or #list == 0 then return end
    SendNUIMessage({ action = 'subtitle', who = who, text = list[math.random(1, #list)] })
end

--- Wait for fn() or the timeout, whichever first. Skipping ends it early too.
function Cine.WaitFor(fn, ms)
    local t = GetGameTimer() + ms
    while not Cine.skip and not fn() and GetGameTimer() < t do Wait(50) end
end

function Cine.Sleep(ms) Cine.WaitFor(function() return false end, ms) end

local R_HAND = 57005

--- Hand a prop from one ped to the other with the give/take animation.
--- keep = true leaves it in the receiver's hand and returns it.
function Cine.HandItem(model, from, to, keep)
    local obj
    if model and LoadModel(model) then
        obj = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
        SetModelAsNoLongerNeeded(model)
        SetEntityCollision(obj, false, false)
        AttachEntityToEntity(obj, from, GetPedBoneIndex(from, R_HAND), 0.12, 0.02, -0.03, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
    if LoadAnimDict('mp_common') then
        TaskPlayAnim(from, 'mp_common', 'givetake1_a', 8.0, -8.0, 1800, 49, 0, false, false, false)
        TaskPlayAnim(to, 'mp_common', 'givetake1_b', 8.0, -8.0, 1800, 49, 0, false, false, false)
    end
    Wait(900)
    if obj then
        DetachEntity(obj, true, false)
        AttachEntityToEntity(obj, to, GetPedBoneIndex(to, R_HAND), 0.12, 0.02, -0.03, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
    Wait(900)
    if obj and not keep then DeleteEntity(obj) obj = nil end
    return obj
end

--- Take control of a networked entity for a moment
function Cine.Control(ent, ms)
    if not ent or not DoesEntityExist(ent) then return false end
    local t = GetGameTimer() + (ms or 1000)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        NetworkRequestControlOfEntity(ent)
        Wait(25)
    end
    return NetworkHasControlOfEntity(ent)
end
