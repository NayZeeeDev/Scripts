-- Spatial audio. Every Config.Audio.updateRate ms this works out, for each playing speaker near you,
-- where it is relative to the camera, how far away, how muffled (walls, buildings, cars), how fast it
-- is closing in (doppler) and what kind of space it sits in, then hands the NUI one small batch.
-- The NUI engine ramps every value across the interval, so this loop can stay slow and cheap:
--   * far placed speakers are skipped before any native is called
--   * entity lookups are cached
--   * raycasts are asynchronous, rate limited per speaker and capped per tick
--   * frame tables are reused: nothing is allocated per speaker per tick
local A = Config.Audio
local RATE      = A.updateRate or 120
local RAY_RATE  = A.occlusionRate or 250     -- ms between occlusion ray sets per speaker
local ROOM_RATE = A.roomRate or 2500         -- ms between room probes for a speaker that moves
local UNLOAD    = A.unloadDistance or 1.35
local CEILING   = A.maxCeiling or 25.0
local RAY_BUDGET, PROBE_BUDGET = 4, 1        -- speakers per tick that may start occlusion rays / a room probe
local FLAGS = 1 | 16                         -- map + objects (vehicles and peds never occlude)
local REACH = 30.0                           -- how far the room probe looks for walls

local states = {}                            -- id -> per speaker cache
local vehOpen = {}                           -- vehicle -> { t, v }
local animDicts = {}                         -- dict -> true (loaded) / false (doesn't exist)
local list = {}
local msg = { action = 'spatial', list = list }
local rayBudget, probeBudget = 0, 0

local DIRS = {}
for i = 0, 7 do
    local a = i * math.pi / 4
    DIRS[i + 1] = vector3(math.cos(a) * REACH, math.sin(a) * REACH, 0.0)
end

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
local function r3(v) return math.floor(v * 1000 + 0.5) / 1000 end

-- one-pole smoothing with separate attack (rising) and release (falling) times, in seconds
local function approach(cur, tgt, dt, up, down)
    return cur + (tgt - cur) * (1.0 - math.exp(-dt / (tgt > cur and up or down)))
end

local function isHit(status, hit) return status == 2 and (hit == true or hit == 1) end

local function stateOf(id)
    local st = states[id]
    if not st then
        st = {
            ent = nil, mode = 0, ref = nil, entAt = -1000000,
            inter = 0, interAt = -1000000,
            occ = 0.0, rayOcc = 0.0, rayAt = -1000000, rayBusy = false,
            rayH = { 0, 0, 0 }, rayHit = { false, false, false },
            probeBusy = false, probeH = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }, probeR = {}, probeO = nil,
            roomPos = nil, roomAt = -1000000,
            wr = 0.0, wh = 0.0, ws = 0.0, twr = 0.0, twh = 0.0, tws = 0.0,
            vel = 0.0, anim = nil, animAt = 0,
            f = { id = id, x = 0.0, y = 0.0, z = -1.0, d = 0.0, r = 1.0, h = 0,
                  lp = 20000, g = 1.0, b = 0.0, wr = 0.0, wh = 0.0, ws = 0.0, v = 0.0 },
        }
        states[id] = st
    end
    return st
end

---------------------------------------------------------------- where is it
-- cached entity behind an emitter: looked up again every 2 s (handles can be reused), a failed
-- lookup is retried at most twice a second
local function resolve(e, st, t)
    local mode, ref
    if e.kind == 'vehicle' then mode, ref = 1, e.vehNet
    elseif e.state == 'carried' then mode, ref = 2, e.carrier
    else mode, ref = 3, e.netId end
    if not ref then st.ent = nil return nil end

    local ent = st.ent
    if st.mode == mode and st.ref == ref then
        if ent and t - st.entAt < 2000 and DoesEntityExist(ent) then return ent end
        if not ent and t - st.entAt < 500 then return nil end
    end
    st.mode, st.ref, st.entAt, ent = mode, ref, t, nil

    if mode == 2 then
        if ref == MyServerId then
            ent = PlayerPedId()
        else
            local p = GetPlayerFromServerId(ref)
            if p ~= -1 then
                local ped = GetPlayerPed(p)
                if ped ~= 0 then ent = ped end
            end
        end
    elseif NetworkDoesNetworkIdExist(ref) then
        local h = NetworkGetEntityFromNetworkId(ref)
        if h ~= 0 and DoesEntityExist(h) then ent = h end
    end
    st.ent = ent
    return ent
end

-- entity + world position of an emitter, or nil when it isn't in scope for us
function LocateEmitter(e)
    local ent = resolve(e, stateOf(e.id), GetGameTimer())
    if ent then return ent, GetEntityCoords(ent) end
end

local function listening(e)
    local l = e.listeners
    if not l then return false end
    for i = 1, #l do
        if l[i] == MyServerId then return true end
    end
    return false
end

---------------------------------------------------------------- cars
-- 0 = sealed cabin, 1 = wide open (no roof, roof down, or enough doors / windows open)
local function openness(veh, t)
    local c = vehOpen[veh]
    if c and t - c.t < 400 then return c.v end
    local o = 1.0
    if DoesVehicleHaveRoof(veh) then
        o = 0.0
        if IsVehicleAConvertible(veh, false) and GetConvertibleRoofState(veh) ~= 0 then o = 1.0 end
        for w = 0, 3 do
            if not IsVehicleWindowIntact(veh, w) then o = o + 0.22 end
        end
        for d = 0, 5 do
            if GetVehicleDoorAngleRatio(veh, d) > 0.1 then o = o + (d == 4 and 0.1 or 0.3) end
        end
        if o > 1.0 then o = 1.0 end
    end
    if c then c.t, c.v = t, o else vehOpen[veh] = { t = t, v = o } end
    return o
end

-- a sealed cabin keeps only the low end: the highs drop away and the bass thumps through the body
local function carMuffle(sealed)
    return 20000.0 * (320.0 / 20000.0) ^ sealed, 1.0 - 0.5 * sealed, 7.0 * sealed
end

---------------------------------------------------------------- occlusion
local function ray(from, tx, ty, tz, ignore)
    -- stop just short of the speaker so its own prop / car never counts as a wall
    local dx, dy, dz = tx - from.x, ty - from.y, tz - from.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    local k = len > 0.6 and (len - 0.3) / len or 1.0
    return StartShapeTestLosProbe(from.x, from.y, from.z, from.x + dx * k, from.y + dy * k, from.z + dz * k, FLAGS, ignore or 0, 7)
end

-- the centre plus two points beside the speaker (sideways to you): a doorway or a corner then
-- reads as partly open instead of flipping between open and blocked
local function castRays(st, cam, pos, rx, ry, ignore)
    local tz = pos.z + 0.5
    st.rayH[1] = ray(cam, pos.x, pos.y, tz, ignore)
    st.rayH[2] = ray(cam, pos.x + rx * 0.8, pos.y + ry * 0.8, tz + 0.3, ignore)
    st.rayH[3] = ray(cam, pos.x - rx * 0.8, pos.y - ry * 0.8, tz - 0.2, ignore)
    st.rayBusy = true
end

local function pollRays(st)
    local pending = false
    for i = 1, 3 do
        local h = st.rayH[i]
        if h ~= 0 then
            local status, hit = GetShapeTestResult(h)
            if status == 1 then
                pending = true
            else
                st.rayH[i] = 0
                st.rayHit[i] = isHit(status, hit)
            end
        end
    end
    if pending then return end
    st.rayBusy = false
    local n = 0
    for i = 1, 3 do if st.rayHit[i] then n = n + 1 end end
    st.rayOcc = n / 3
end

---------------------------------------------------------------- what kind of space
-- one ray up for a ceiling, eight around for walls
local function castProbe(st, pos, ignore)
    local o = pos + vector3(0.0, 0.0, 0.6)
    st.probeO = o
    st.probeH[1] = StartShapeTestLosProbe(o.x, o.y, o.z, o.x, o.y, o.z + CEILING, FLAGS, ignore or 0, 7)
    for i = 1, 8 do
        local d = DIRS[i]
        st.probeH[i + 1] = StartShapeTestLosProbe(o.x, o.y, o.z, o.x + d.x, o.y + d.y, o.z, FLAGS, ignore or 0, 7)
    end
    st.probeBusy = true
end

-- r[1] = ceiling height (or false), r[2..9] = wall distances (or false).
-- Returns the sends for the three reverb buses: small room, large room / hall, street slapback.
local function classify(r)
    local hits, near, sum = 0, 0, 0.0
    for i = 2, 9 do
        local w = r[i]
        if w then
            hits = hits + 1
            sum = sum + w
            if w < 12.0 then near = near + 1 end
        else
            sum = sum + REACH
        end
    end
    local up = r[1]
    if up and hits >= 6 then
        -- indoors: the further the walls and the higher the ceiling, the more it is a hall
        local size = clamp((sum / 8 - 3.5) / 9.0 + (up - 3.5) / 10.0, 0.0, 1.0)
        local amount = 0.10 + 0.16 * hits / 8
        return amount * math.cos(size * math.pi / 2), amount * math.sin(size * math.pi / 2), 0.0
    elseif up then
        -- covered but open: under a bridge, a canopy, a parking deck
        return 0.05, up > 6.0 and 0.05 or 0.0, 0.04 + 0.10 * hits / 8
    end
    -- outdoors: buildings around throw back slaps; an open field stays nearly dry
    return near >= 3 and 0.03 * near / 8 or 0.0, 0.0, 0.02 + 0.18 * (hits / 8) ^ 1.3
end

local function pollProbe(st)
    local pending = false
    for i = 1, 9 do
        local h = st.probeH[i]
        if h ~= 0 then
            local status, hit, endC = GetShapeTestResult(h)
            if status == 1 then
                pending = true
            else
                st.probeH[i] = 0
                st.probeR[i] = isHit(status, hit) and #(endC - st.probeO) or false
            end
        end
    end
    if pending then return end
    st.probeBusy = false
    st.twr, st.twh, st.tws = classify(st.probeR)
end

local function room(st, pos, ent, t, dt, audible)
    if st.probeBusy then pollProbe(st) end
    if audible and not st.probeBusy and probeBudget > 0 then
        local due = not st.roomPos or t - st.roomAt > 30000
            or (t - st.roomAt > ROOM_RATE and #(pos - st.roomPos) > 2.0)
        if due then
            castProbe(st, pos, ent)
            st.roomPos, st.roomAt = pos, t
            probeBudget = probeBudget - 1
        end
    end
    -- glide between spaces instead of switching
    local k = 1.0 - math.exp(-dt / 0.6)
    st.wr = st.wr + (st.twr - st.wr) * k
    st.wh = st.wh + (st.twh - st.wh) * k
    st.ws = st.ws + (st.tws - st.ws) * k
end

---------------------------------------------------------------- prop animation
-- the old models had their own speaker animation; the new ones ship none, so this is guarded
local function propAnim(e, st, obj, t)
    local cfg = e.item and Config.Boomboxes[e.item]
    local a = cfg and cfg.anim
    if not a or e.state ~= 'placed' or animDicts[a.dict] == false then return end
    local on = e.playing and not Settings.streamer
    if st.anim == on and t - st.animAt < 2000 then return end
    if not animDicts[a.dict] then
        if not DoesAnimDictExist(a.dict) then animDicts[a.dict] = false return end
        RequestAnimDict(a.dict)
        if not HasAnimDictLoaded(a.dict) then return end
        animDicts[a.dict] = true
    end
    st.anim, st.animAt = on, t
    local playing = IsEntityPlayingAnim(obj, a.dict, a.clip, 3)
    if on and not playing then
        PlayEntityAnim(obj, a.clip, a.dict, 1000.0, true, true, false, 0.0, 0)
    elseif not on and playing then
        StopEntityAnim(obj, a.clip, a.dict, 1.0)
    end
end

---------------------------------------------------------------- frames
local function headFrame(f)
    f.h, f.x, f.y, f.z, f.d, f.r = 1, 0.0, 0.0, -1.0, 0.0, 1.0
    f.lp, f.g, f.b, f.v = 20000, 1.0, 0.0, 0.0
    f.wr, f.wh, f.ws = 0.0, 0.0, 0.0
end

local function anyPlaying()
    for _, e in pairs(Emitters) do
        if e.track then return true end
    end
    return false
end

local function tick(t, dt)
    local ped = PlayerPedId()
    local me = GetEntityCoords(ped)
    local cam = GetFinalRenderedCamCoord()
    -- listener basis from the camera's yaw only: the third-person camera looks down at the ped, and
    -- feeding that pitch into HRTF put every speaker "under" you. Height is passed, damped.
    local yaw = math.rad(GetFinalRenderedCamRot(2).z)
    local fx, fy = -math.sin(yaw), math.cos(yaw)
    local rx, ry = math.cos(yaw), math.sin(yaw)
    local myVeh = GetVehiclePedIsIn(ped, false)
    local myOpen = myVeh ~= 0 and openness(myVeh, t) or 1.0
    local myInt = GetInteriorFromEntity(ped)
    local lv = GetEntityVelocity(myVeh ~= 0 and myVeh or ped)
    local effects = Settings.effects ~= false and not Settings.streamer
    rayBudget, probeBudget = RAY_BUDGET, PROBE_BUDGET
    local n = 0

    for id, e in pairs(Emitters) do
        if e.track then
            local kind = e.kind
            if kind == 'jam' or kind == 'preview' then
                -- no place in the world: heard in your own ears (a jam only by its members)
                if kind == 'preview' or listening(e) then
                    local st = stateOf(id)
                    headFrame(st.f)
                    n = n + 1
                    list[n] = st.f
                end
            else
                local range = e.range or 10.0
                local far = false
                local c = e.state == 'placed' and kind == 'boombox' and e.coords
                if c then
                    local dx, dy, dz = c.x - me.x, c.y - me.y, c.z - me.z
                    local lim = range * UNLOAD + 3.0
                    far = dx * dx + dy * dy + dz * dz > lim * lim
                end
                local st = not far and stateOf(id)
                local ent = st and resolve(e, st, t)
                if ent then
                    local pos = GetEntityCoords(ent)
                    local dist = #(me - pos)
                    if dist <= range * UNLOAD then
                        local f = st.f
                        if e.state == 'placed' and kind == 'boombox' then propAnim(e, st, ent, t) end
                        local inCar = kind == 'vehicle' and ent == myVeh
                        local mine = e.state == 'carried' and e.carrier == MyServerId

                        if inCar or mine then
                            headFrame(f)
                            st.occ, st.vel = 0.0, 0.0
                            if mine and effects and A.reverb ~= false then
                                -- carrying it: you hear the space you are walking through
                                room(st, pos, ent, t, dt, true)
                                f.wr, f.wh, f.ws = r3(st.wr), r3(st.wh), r3(st.ws)
                            end
                        else
                            local dx, dy, dz = pos.x - cam.x, pos.y - cam.y, pos.z - cam.z
                            f.h = 0
                            f.x, f.y, f.z = r2(dx * rx + dy * ry), r2(dz * 0.35), r2(-(dx * fx + dy * fy))
                            f.d, f.r = r2(dist), range
                            local cut, gain, bass, vel = 20000.0, 1.0, 0.0, 0.0
                            local audible = dist <= range

                            if effects then
                                -- inside vs outside a building: strong muffle
                                if kind == 'boombox' and e.state == 'placed' then
                                    if t - st.interAt > 5000 then st.inter, st.interAt = GetInteriorAtCoords(pos.x, pos.y, pos.z), t end
                                elseif t - st.interAt > RAY_RATE then
                                    st.inter, st.interAt = GetInteriorFromEntity(ent), t
                                end
                                local inter = A.interiorMuffle ~= false and st.inter ~= myInt
                                local target = 0.0
                                if inter then
                                    target = 1.0
                                elseif A.occlusion ~= false and dist > 1.5 then
                                    if st.rayBusy then pollRays(st) end
                                    if audible and not st.rayBusy and t - st.rayAt >= RAY_RATE and rayBudget > 0 then
                                        castRays(st, cam, pos, rx, ry, ent)
                                        st.rayAt, rayBudget = t, rayBudget - 1
                                    end
                                    target = st.rayOcc
                                end
                                -- walls close in quickly and open up a little slower, never a hard switch
                                st.occ = approach(st.occ, target, dt, 0.12, 0.35)
                                if st.occ > 0.002 then
                                    cut = 20000.0 * ((inter and 380.0 or 650.0) / 20000.0) ^ st.occ
                                    gain = 1.0 - (inter and 0.5 or 0.35) * st.occ
                                end

                                if A.vehicleMuffle ~= false then
                                    if kind == 'vehicle' then
                                        local c2, g2, b2 = carMuffle(1.0 - openness(ent, t))
                                        if c2 < cut then cut = c2 end
                                        gain, bass = gain * g2, b2
                                    end
                                    if myVeh ~= 0 then
                                        local c2, g2, b2 = carMuffle(1.0 - myOpen)
                                        if c2 < cut then cut = c2 end
                                        gain = gain * g2
                                        if b2 > bass then bass = b2 end
                                    end
                                end

                                if A.reverb ~= false then room(st, pos, ent, t, dt, audible) end

                                if A.doppler ~= false and dist > 0.5 then
                                    -- closing speed from real velocities (positive while the gap shrinks)
                                    local vx, vy, vz = -lv.x, -lv.y, -lv.z
                                    if kind == 'vehicle' or e.state == 'carried' then
                                        local ev = GetEntityVelocity(ent)
                                        vx, vy, vz = vx + ev.x, vy + ev.y, vz + ev.z
                                    end
                                    local closing = -(vx * (pos.x - me.x) + vy * (pos.y - me.y) + vz * (pos.z - me.z)) / dist
                                    st.vel = approach(st.vel, clamp(closing, -60.0, 60.0), dt, 0.2, 0.2)
                                    vel = st.vel
                                else
                                    st.vel = 0.0
                                end
                            else
                                st.occ, st.vel = 0.0, 0.0
                            end

                            -- through a wall you hear more of the room than of the speaker
                            local wetter = 1.0 + 0.6 * st.occ
                            f.lp, f.g, f.b = math.floor(cut), r3(gain), math.floor(bass * 10 + 0.5) / 10
                            f.wr, f.wh, f.ws = r3(st.wr * wetter), r3(st.wh * wetter), r3(st.ws * wetter)
                            f.v = math.floor(vel * 10 + 0.5) / 10
                        end
                        n = n + 1
                        list[n] = f
                    end
                end
            end
        end
    end

    local i = n + 1
    while list[i] ~= nil do
        list[i] = nil
        i = i + 1
    end
    SendNUIMessage(msg)
    return n
end

CreateThread(function()
    local last, sweep = GetGameTimer(), 0
    while true do
        local t = GetGameTimer()
        local dt = clamp((t - last) / 1000, 0.001, 1.0)
        last = t
        if not anyPlaying() then
            if list[1] ~= nil then
                for i = #list, 1, -1 do list[i] = nil end
                SendNUIMessage(msg)   -- an empty frame: the NUI lets go of anything it stops hearing about
            end
            Wait(500)
        else
            local n = tick(t, dt)
            if t - sweep > 5000 then
                sweep = t
                for id in pairs(states) do
                    if not Emitters[id] then states[id] = nil end
                end
                if next(vehOpen) then vehOpen = {} end
            end
            -- nothing in earshot: check back slower, the NUI unloads what it stopped hearing about
            Wait(n > 0 and RATE or 400)
        end
    end
end)

function ForgetEmitter(id) states[id] = nil end
