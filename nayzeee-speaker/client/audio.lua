-- Spatial audio: works out where each playing speaker is relative to the camera and how it
-- should sound (distance, direction, muffling, echo), then hands one small batch to the NUI.
local A = Config.Audio
local occl, room, prevDist = {}, {}, {}   -- per emitter caches
local animDicts = {}

local function probe(from, to, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 | 16, ignore or 0, 7)
    local _, hit, endC = GetShapeTestResult(h)
    return hit == 1, endC
end

-- Listener basis from the camera's yaw only. The third-person camera usually looks down at the ped,
-- and feeding that pitch into HRTF put every speaker "under" the listener, which is what made the
-- panning sound hollow. Height is still passed, but damped, so a rooftop speaker reads as above you.
local function camBasis()
    local y = math.rad(GetFinalRenderedCamRot(2).z)
    local fwd = vector3(-math.sin(y), math.cos(y), 0.0)
    local right = vector3(math.cos(y), math.sin(y), 0.0)
    return fwd, right
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

local function openness(veh)
    if not DoesVehicleHaveRoof(veh) then return 1.0 end
    local o = 0.0
    if IsVehicleAConvertible(veh, false) and GetConvertibleRoofState(veh) ~= 0 then o = 1.0 end
    for w = 0, 3 do
        if not IsVehicleWindowIntact(veh, w) then o = o + 0.22 end
    end
    for d = 0, 5 do
        if GetVehicleDoorAngleRatio(veh, d) > 0.1 then o = o + 0.3 end
    end
    return o > 1.0 and 1.0 or o
end

-- how echo-y the space around a speaker is (cached)
local function roomAt(id, pos, ignore, t)
    local c = room[id]
    if c and t - c.t < 1500 and #(c.pos - pos) < 2.0 then return c.wet, c.size end
    local wet, size = 0.0, 0
    local hit, endC = probe(pos + vector3(0.0, 0.0, 0.4), pos + vector3(0.0, 0.0, A.maxCeiling), ignore)
    if hit then
        local h = #(endC - pos)
        local walls, total = 0, 0.0
        for _, d in ipairs({ vector3(12.0, 0.0, 0.0), vector3(-12.0, 0.0, 0.0), vector3(0.0, 12.0, 0.0), vector3(0.0, -12.0, 0.0) }) do
            local wh, we = probe(pos + vector3(0.0, 0.0, 0.8), pos + vector3(0.0, 0.0, 0.8) + d, ignore)
            if wh then walls = walls + 1 total = total + #(we - pos) else total = total + 12.0 end
        end
        local low = 1.0 - math.min(h / A.maxCeiling, 1.0)
        wet = (0.04 + 0.20 * low) * (0.30 + 0.70 * walls / 4)   -- tops out around 0.24
        local span = (total / 4 + h) / 2
        size = span < 4.0 and 0 or (span < 9.0 and 1 or 2)
    end
    room[id] = { t = t, pos = pos, wet = wet, size = size }
    return wet, size
end

local function occluded(id, from, to, ignore, t)
    local c = occl[id]
    if c and t - c.t < 700 then return c.v end
    local hit = probe(from, to + vector3(0.0, 0.0, 0.5), ignore)
    occl[id] = { t = t, v = hit }
    return hit
end

-- entity + world position of an emitter, or nil when it isn't in scope for us
local function locate(e)
    if e.kind == 'vehicle' then
        if not NetworkDoesNetworkIdExist(e.vehNet) then return end
        local veh = NetworkGetEntityFromNetworkId(e.vehNet)
        if veh == 0 or not DoesEntityExist(veh) then return end
        return veh, GetEntityCoords(veh)
    end
    if e.state == 'carried' then
        if e.carrier == MyServerId then return PlayerPedId(), GetEntityCoords(PlayerPedId()) end
        local p = GetPlayerFromServerId(e.carrier or -1)
        if p == -1 then return end
        local ped = GetPlayerPed(p)
        if ped == 0 then return end
        return ped, GetEntityCoords(ped)
    end
    if e.netId and NetworkDoesNetworkIdExist(e.netId) then
        local obj = NetworkGetEntityFromNetworkId(e.netId)
        if obj ~= 0 and DoesEntityExist(obj) then return obj, GetEntityCoords(obj) end
    end
end
LocateEmitter = locate

local function listening(e)
    for _, src in ipairs(e.listeners or {}) do
        if src == MyServerId then return true end
    end
    return false
end

local function propAnim(e, obj)
    local cfg = e.item and Config.Boomboxes[e.item]
    local a = cfg and cfg.anim
    if not a or not obj or e.state ~= 'placed' then return end
    local on = e.playing and not Settings.streamer
    if on then
        if not animDicts[a.dict] then
            RequestAnimDict(a.dict)
            if not HasAnimDictLoaded(a.dict) then return end
            animDicts[a.dict] = true
        end
        if not IsEntityPlayingAnim(obj, a.dict, a.clip, 3) then
            PlayEntityAnim(obj, a.clip, a.dict, 1000.0, true, true, false, 0.0, 0)
        end
    elseif IsEntityPlayingAnim(obj, a.dict, a.clip, 3) then
        StopEntityAnim(obj, a.clip, a.dict, 1.0)
    end
end

CreateThread(function()
    while true do
        local any = false
        for _, e in pairs(Emitters) do
            if e.track then any = true break end
        end

        if not any then
            Wait(500)
        else
            local t = GetGameTimer()
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            local cam = GetFinalRenderedCamCoord()
            local fwd, right = camBasis()
            local myVeh = GetVehiclePedIsIn(ped, false)
            local myOpen = myVeh ~= 0 and openness(myVeh) or 1.0
            local myInt = GetInteriorFromEntity(ped)
            local list = {}

            for id, e in pairs(Emitters) do
                if e.track and e.kind == 'jam' then
                    -- a jam has no place in the world: members hear it in their own ears, full volume
                    if listening(e) then
                        list[#list + 1] = { id = id, x = 0.0, y = 0.0, z = -0.1, d = 0.0, r = 1.0, lp = 20000, g = 1.0, w = 0.0, s = 0, v = 0 }
                    end
                elseif e.track then
                    local ent, pos = locate(e)
                    if ent and e.state == 'placed' then propAnim(e, ent) end
                    if pos then
                        local dist = #(me - pos)
                        if dist <= e.range * A.unloadDistance then
                            local x, y, z = 0.0, 0.0, -0.1
                            local cut, gain, wet, size = 20000, 1.0, 0.0, 0
                            local insideThis = e.kind == 'vehicle' and ent == myVeh

                            if insideThis or (e.state == 'carried' and e.carrier == MyServerId) then
                                dist = 0.0
                            else
                                local d = pos - cam
                                x, y, z = dot(d, right), d.z * 0.35, -dot(d, fwd)

                                -- air absorption: the further away, the duller (cut ~8 kHz at the edge of range)
                                if A.distanceMuffle ~= false then
                                    local far = math.min(dist / e.range, 1.0)
                                    cut = math.min(cut, math.floor(20000 - 12000 * far * far))
                                end

                                if e.kind == 'vehicle' and A.vehicleMuffle then
                                    local o = openness(ent)
                                    cut = 700 + 5200 * (o ^ 1.5)
                                    gain = gain * (0.55 + 0.45 * o)
                                end
                                if myVeh ~= 0 and A.vehicleMuffle then
                                    cut = math.min(cut, 900 + 6000 * myOpen)
                                    gain = gain * (0.6 + 0.4 * myOpen)
                                end

                                local emInt = e.kind == 'vehicle' and GetInteriorFromEntity(ent) or GetInteriorAtCoords(pos.x, pos.y, pos.z)
                                if A.interiorMuffle and emInt ~= myInt then
                                    cut = math.min(cut, 650)
                                    gain = gain * 0.6
                                elseif A.occlusion and dist > 2.0 and occluded(id, cam, pos, ent, t) then
                                    cut = math.min(cut, 1600)
                                    gain = gain * 0.8
                                end
                            end

                            if A.reverb and not insideThis then
                                wet, size = roomAt(id, pos, ent, t)
                            end

                            -- closing speed (m/s), positive when the gap is shrinking → doppler.
                            -- Smoothed over a few frames so position jitter doesn't warble the pitch,
                            -- and reset on big jumps (teleports, getting in or out of a car).
                            local vel = 0.0
                            local pd = prevDist[id]
                            if pd and t > pd.t then
                                local dt = (t - pd.t) / 1000
                                local raw = (pd.d - dist) / dt
                                if dt > 1.0 or math.abs(pd.d - dist) > 20.0 then raw = 0.0 end
                                vel = pd.v + (raw - pd.v) * 0.2
                                if vel > 35.0 then vel = 35.0 elseif vel < -35.0 then vel = -35.0 end
                                if math.abs(vel) < 0.5 then vel = 0.0 end
                            end
                            prevDist[id] = { d = dist, t = t, v = vel }

                            list[#list + 1] = {
                                id = id,
                                x = math.floor(x * 100) / 100, y = math.floor(y * 100) / 100, z = math.floor(z * 100) / 100,
                                d = math.floor(dist * 100) / 100, r = e.range,
                                lp = math.floor(cut), g = math.floor(gain * 1000) / 1000,
                                w = math.floor(wet * 1000) / 1000, s = size,
                                v = A.doppler and math.floor(vel * 10) / 10 or 0,
                            }
                        end
                    end
                end
            end

            SendNUIMessage({ action = 'spatial', list = list })
            Wait(A.updateRate)
        end
    end
end)

function ForgetEmitter(id) occl[id], room[id], prevDist[id] = nil, nil, nil end
