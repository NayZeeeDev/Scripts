--[[
    Recon drone (item: heist_drone). Free-flying camera drone with a tablet animation.
    Heist nodes of type `drone` register drop zones; press E above a zone to drop the payload.
    Everything here runs only while the drone is flying.
]]

Drone = { active = false, zones = {} }

local MAX_RANGE = 250.0
local MODEL = 'ch_prop_casino_drone_02a'

--- zones: list of { id, coords, radius, label, onDrop = function(zone) }
function Drone.setZones(zones) Drone.zones = zones or {} end

local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vec3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

function Drone.launch()
    if Drone.active then return UI.notify(locale('drone_active'), 'error') end
    if cache.vehicle then return end
    Drone.active = true
    local ped = cache.ped
    local start = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.5)
    local drone = Props.spawn('drone', MODEL, start, GetEntityHeading(ped), { freeze = false, collision = true })
    if not drone then Drone.active = false return end
    SetEntityHasGravity(drone, false)
    SetEntityDynamic(drone, true)

    lib.requestAnimDict('amb@world_human_seat_wall_tablet@female@base')
    TaskPlayAnim(ped, 'amb@world_human_seat_wall_tablet@female@base', 'base', 3.0, 3.0, -1, 49, 0, false, false, false)
    local tablet = Props.attach(ped, 'prop_cs_tablet', 60309, vec3(0.03, 0.002, -0.0), vec3(10.0, 160.0, 0.0))

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    AttachCamToEntity(cam, drone, 0.0, 0.0, -0.25, true)
    SetCamFov(cam, 70.0)
    RenderScriptCams(true, true, 500, true, true)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.0)

    UI.send('drone', { show = true, zones = #Drone.zones })
    local pitch, yaw = -20.0, GetEntityHeading(ped)
    local origin = GetEntityCoords(ped)
    local lastHud = 0

    CreateThread(function()
        while Drone.active do
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true) EnableControlAction(0, 2, true) -- look
            EnableControlAction(0, 245, true) EnableControlAction(0, 249, true) -- chat / ptt

            yaw = yaw - GetDisabledControlNormal(0, 1) * 6.0
            pitch = math.max(-89.0, math.min(30.0, pitch - GetDisabledControlNormal(0, 2) * 6.0))
            SetCamRot(cam, pitch, 0.0, yaw, 2)
            SetEntityHeading(drone, yaw)

            local speed = IsDisabledControlPressed(0, 21) and 0.55 or 0.2
            local pos = GetEntityCoords(drone)
            local forward = rotationToDirection(vec3(0.0, 0.0, yaw))
            local right = vec3(forward.y, -forward.x, 0.0)
            local move = vec3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then move = move + forward end
            if IsDisabledControlPressed(0, 33) then move = move - forward end
            if IsDisabledControlPressed(0, 35) then move = move + right end
            if IsDisabledControlPressed(0, 34) then move = move - right end
            if IsDisabledControlPressed(0, 44) then move = move + vec3(0.0, 0.0, 1.0) end -- Q up
            if IsDisabledControlPressed(0, 38) then move = move - vec3(0.0, 0.0, 1.0) end -- E down
            local target = pos + move * speed
            if #(target - origin) <= MAX_RANGE then
                SetEntityCoordsNoOffset(drone, target.x, target.y, target.z, false, false, false)
            end
            SetEntityVelocity(drone, 0.0, 0.0, 0.0)

            -- zone detection
            local inZone
            for i = 1, #Drone.zones do
                local z = Drone.zones[i]
                if not z.dropped then
                    local flat = vec2(pos.x - z.coords.x, pos.y - z.coords.y)
                    if #flat <= z.radius and pos.z > z.coords.z - 3.0 then inZone = z end
                    DrawMarker(1, z.coords.x, z.coords.y, z.coords.z - 1.0, 0, 0, 0, 0, 0, 0, z.radius * 2, z.radius * 2, 1.5, 124, 92, 255, 90, false, false, 2, false, nil, nil, false)
                end
            end

            if IsDisabledControlJustPressed(0, 47) and inZone then -- G drop
                inZone.dropped = true
                CreateThread(function() inZone.onDrop(inZone, pos) end)
            end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) or IsEntityDead(ped) then
                Drone.land()
            end

            local now = GetGameTimer()
            if now - lastHud > 250 then
                lastHud = now
                local remaining = 0
                for i = 1, #Drone.zones do if not Drone.zones[i].dropped then remaining = remaining + 1 end end
                UI.send('drone', {
                    show = true, altitude = math.floor(pos.z - (GetHeightmapBottomZForPosition(pos.x, pos.y) or 0.0)),
                    distance = math.floor(#(pos - origin)), range = MAX_RANGE, inZone = inZone ~= nil, remaining = remaining,
                    zones = #Drone.zones,
                })
            end
            Wait(0)
        end

        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(cam, false)
        ClearTimecycleModifier()
        Props.delete('drone')
        if tablet and DoesEntityExist(tablet) then DeleteEntity(tablet) end
        StopAnimTask(ped, 'amb@world_human_seat_wall_tablet@female@base', 'base', 1.0)
        UI.send('drone', { show = false })
    end)
end

function Drone.land()
    Drone.active = false
end

RegisterNetEvent('nzh:drone:use', function()
    if GetInvokingResource() then return end
    Drone.launch()
end)
