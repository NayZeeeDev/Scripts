if not NAYZEEE_LOCK_OK then return end

--[[
    Showroom: 3D preview of a shop vehicle. The vehicle is local (only this player sees it) and is placed at
    Config.Showroom.Location while a scripted camera looks at it. The shop stays open with a see-through overlay:
    drag to turn the vehicle, scroll to zoom, pick a paint colour, toggle lights and doors.
]]

local sr = nil   -- { veh, cam, hash, pos, heading, zoom, radius, idleUntil, lights, doors }

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end
    return hash
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Bars are relative to typical GTA values, so 100% = one of the fastest / best cars in the game
local function stats(hash)
    local speed = GetVehicleModelEstimatedMaxSpeed(hash) * 3.6
    local accel, brake, grip = GetVehicleModelAcceleration(hash), GetVehicleModelMaxBraking(hash), GetVehicleModelMaxTraction(hash)
    return {
        speed = math.floor(speed + 0.5), seats = GetVehicleModelNumberOfSeats(hash),
        bars = { speed = clamp(speed / 300, 0, 1), accel = clamp(accel / 0.45, 0, 1), brake = clamp(brake / 1.4, 0, 1), grip = clamp(grip / 3.0, 0, 1) },
    }
end

local function placeCam()
    local dist = sr.radius * (1.25 + sr.zoom)
    local a = math.rad(sr.camAngle)
    local p = sr.pos
    SetCamCoord(sr.cam, p.x + math.cos(a) * dist, p.y + math.sin(a) * dist, p.z + 0.35 + sr.radius * 0.18)
    PointCamAtCoord(sr.cam, p.x, p.y, p.z + 0.15)
end

function ShowroomStop()
    if not sr then return end
    local s = sr
    sr = nil
    RenderScriptCams(false, true, 500, true, true)
    if s.cam then DestroyCam(s.cam, false) end
    if s.veh and DoesEntityExist(s.veh) then DeleteEntity(s.veh) end
    ClearFocus()
    if Config.Showroom.Time then NetworkClearClockTimeOverride() end
end

function ShowroomActive() return sr ~= nil end

RegisterNUICallback('showroom:open', function(d, cb)
    if sr then ShowroomStop() end
    if not Config.Showroom.Enabled then return cb({ error = 'ERR_DISABLED' }) end
    local hash = d and d.model and loadModel(d.model)
    if not hash then return cb({ error = 'ERR_TD_MODEL' }) end
    local loc = Config.Showroom.Location
    SetFocusPosAndVel(loc.x, loc.y, loc.z, 0.0, 0.0, 0.0)          -- stream the area around the showroom, not the player
    RequestCollisionAtCoord(loc.x, loc.y, loc.z)
    local veh = CreateVehicle(hash, loc.x, loc.y, loc.z, loc.w, false, false)
    local deadline = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < deadline do Wait(0) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(veh) then ClearFocus() return cb({ error = 'ERR_TD_MODEL' }) end
    deadline = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < deadline do RequestCollisionAtCoord(loc.x, loc.y, loc.z) Wait(0) end
    SetVehicleOnGroundProperly(veh)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleNumberPlateText(veh, 'SHOWROOM')
    local min, max = GetModelDimensions(hash)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', loc.x, loc.y, loc.z + 2.0, 0.0, 0.0, 0.0, 45.0, false, 0)
    sr = {
        veh = veh, cam = cam, hash = hash, pos = GetEntityCoords(veh), heading = loc.w, zoom = 0.35, camAngle = loc.w + 125.0,
        radius = math.max(2.0, math.max(max.x - min.x, max.y - min.y) * 0.75), idleUntil = 0, lights = false, doors = false,
    }
    placeCam()
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, true)
    if Config.Showroom.Time then NetworkOverrideClockTime(Config.Showroom.Time, 0, 0) end
    TriggerScreenblurFadeOut(200)

    CreateThread(function()
        while sr do
            if not DoesEntityExist(sr.veh) then ShowroomStop() break end
            if GetGameTimer() > sr.idleUntil then sr.heading = (sr.heading + 0.12) % 360 end   -- slow turntable while idle
            SetEntityHeading(sr.veh, sr.heading)
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
    cb({ data = stats(hash) })
end)

RegisterNUICallback('showroom:rotate', function(d, cb)
    if sr then
        sr.heading = (sr.heading + clamp(tonumber(d.dx) or 0, -400, 400) * 0.35) % 360
        sr.idleUntil = GetGameTimer() + 4000
    end
    cb(true)
end)

RegisterNUICallback('showroom:zoom', function(d, cb)
    if sr then
        sr.zoom = clamp(sr.zoom + clamp(tonumber(d.dy) or 0, -600, 600) * 0.0015, 0.0, 1.6)
        placeCam()
    end
    cb(true)
end)

RegisterNUICallback('showroom:color', function(d, cb)
    local c = sr and Config.Showroom.Colors[tonumber(d.index) or 0]
    if c then
        SetVehicleModKit(sr.veh, 0)
        SetVehicleCustomPrimaryColour(sr.veh, c[2], c[3], c[4])
        SetVehicleCustomSecondaryColour(sr.veh, c[2], c[3], c[4])
    end
    cb(true)
end)

RegisterNUICallback('showroom:toggle', function(d, cb)
    if sr then
        if d.what == 'lights' then
            sr.lights = not sr.lights
            SetVehicleLights(sr.veh, sr.lights and 2 or 1)
        elseif d.what == 'doors' then
            sr.doors = not sr.doors
            for door = 0, 5 do
                if sr.doors then SetVehicleDoorOpen(sr.veh, door, false, false) else SetVehicleDoorShut(sr.veh, door, false) end
            end
        end
    end
    cb({ data = sr and { lights = sr.lights, doors = sr.doors } or nil })
end)

RegisterNUICallback('showroom:reset', function(_, cb)
    if sr then
        sr.zoom, sr.heading, sr.idleUntil = 0.35, Config.Showroom.Location.w, 0
        placeCam()
    end
    cb(true)
end)

RegisterNUICallback('showroom:close', function(_, cb)
    ShowroomStop()
    if Config.General.Blur and exports[NZC.Resource]:isOpen() then TriggerScreenblurFadeIn(200) end
    cb(true)
end)

AddEventHandler('onResourceStop', function(res)
    if res == NZC.Resource then ShowroomStop() end
end)
