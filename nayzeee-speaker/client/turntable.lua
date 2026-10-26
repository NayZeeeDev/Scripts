--[[
    The turntable you can see: platter, tonearm and record on every placed record console near you.

    All of it is local to each player (nothing networked) and is worked out from the emitter snapshot
    the server already sends, so everyone sees the same thing at the same moment:
      * a record goes on: it shows in the hand of whoever put it on, floats onto the spindle and drops
        into place. The platter spins up, the arm lifts off its rest, swings over the lead-in groove
        and lowers. The server holds the music until that moment, so it starts as the needle lands.
      * while it plays the arm creeps inward across the album, track by track, lead-in to run-out
      * pause spins the platter down, a skip lifts the arm to the new groove, the end of the record
        (or stop) sends the arm home
      * the record comes off: arm home, platter stops, the record lifts off and goes back to the hand
        of whoever gets it (or rises and fades when that player isn't here)
    Someone walking up mid-song sees everything already in place. Nothing at all happens until the
    turntable props (nayzeee_tt_platter, nayzeee_tt_arm, nayzeee_vinyl) are in the game, and with no
    turntable near this only looks around once a second.
]]
local RES = GetCurrentResourceName()
local C = Config.Turntable or {}
if C.visuals == false then return end

local DIST     = C.distance or 35.0                   -- props exist within this many metres
local LABEL    = C.labelArt ~= false                  -- album cover on the record label
local LABEL_PX = C.labelSize or 512
local PUT      = C.putAnim or { dict = 'mp_common', clip = 'givetake1_a', flag = 48, duration = 1400 }
local TAKE     = C.takeAnim or { dict = 'mp_common', clip = 'givetake1_b', flag = 48, duration = 1400 }

local MODELS = { platter = 'nayzeee_tt_platter', arm = 'nayzeee_tt_arm', vinyl = 'nayzeee_vinyl' }
local HASH = {}
for k, name in pairs(MODELS) do HASH[k] = joaat(name) end

---------------------------------------------------------------- geometry (metres, console space)
-- see the turntable section of the asset contract: +Y = front, +X = the player's left, +Z = up
local PLATTER = { 0.300, 0.000, 0.785 }   -- platter origin (centre of its underside)
local RECORD  = { 0.300, 0.000, 0.811 }   -- record origin when it lies on the slipmat
local PIVOT   = { 0.075, -0.125, 0.835 }  -- tonearm pivot
local ARM_LEN, LEAD_IN, RUN_OUT = 0.250, 0.146, 0.062
local PC_X, PC_Y = RECORD[1] - PIVOT[1], RECORD[2] - PIVOT[2]
local PC_D = math.sqrt(PC_X * PC_X + PC_Y * PC_Y)         -- pivot -> platter centre, 0.2574
local PC_A = math.deg(math.atan(-PC_X, PC_Y))             -- arm angle pointing at the centre, -60.9

---------------------------------------------------------------- timing (seconds)
-- putting a record on, measured from the server's insert time (server/vinyl.lua holds the music
-- for INSERT_LEAD = 4.4 s: seated at 2.35 + lift 0.35 + swing ~0.9 + lower 0.5, with a little spare)
local IN_FACE, IN_REACH, IN_HAND, IN_LET_GO, IN_OVER, IN_SEATED = 0.0, 0.3, 0.55, 1.05, 2.05, 2.35
local HOVER, DROP = 0.040, 0.004          -- height over the spindle, and the last little drop
local LIFT      = 3.0                     -- degrees the arm tips up to clear the record
local LIFT_T, LOWER_T, REST_T = 0.35, 0.5, 0.3
local SWING     = 30.0                    -- degrees per second across the record
local MOVE_EPS  = 0.6                     -- further than this (degrees) the arm lifts and moves
local RPM       = 200.0                   -- 33 1/3 rpm in degrees per second
local SPIN_UP, SPIN_DOWN = 1.0, 1.2
local ARM_CLEAR = -12.0                   -- arm angle that is well clear of the record
local OFF_LIFT, OFF_AWAY, OFF_HOLD, OFF_RISE = 0.3, 0.85, 0.35, 0.8
local HAND_BONE, HAND_REACH = 57005, 6.0  -- right hand; a hand further than this from the deck doesn't count

---------------------------------------------------------------- math
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function smooth(k) return k * k * (3.0 - 2.0 * k) end
local function smoother(k) return k * k * k * (k * (k * 6.0 - 15.0) + 10.0) end
local function lerp(a, b, k) return a + (b - a) * k end
local function lerpAngle(a, b, k) return a + ((b - a + 180.0) % 360.0 - 180.0) * k end

-- arm angle (degrees about Z, 0 = on its rest, negative = over the record) that puts the stylus
-- `r` metres from the platter centre: the triangle pivot / centre / stylus, law of cosines
local function armAngle(r)
    local c = (PC_D * PC_D + ARM_LEN * ARM_LEN - r * r) / (2.0 * PC_D * ARM_LEN)
    return PC_A + math.deg(math.acos(clamp(c, -1.0, 1.0)))
end

-- stylus radius `p` (0-1) of the way through track `idx` of `n`: the whole album spans the grooves
local function grooveRadius(idx, p, n)
    n = math.max(n or 1, 1)
    local k = ((clamp(idx or 1, 1, n) - 1) + clamp(p or 0.0, 0.0, 1.0)) / n
    return LEAD_IN - (LEAD_IN - RUN_OUT) * k
end

-- a value that glides to a target with an eased curve; t in ms
local function chan(v) return { v = v, to = v } end

local function toward(ch, to, secs, t)
    if ch.t0 then
        if math.abs(ch.to - to) < 1e-4 then return end
    elseif math.abs(ch.v - to) < 1e-4 then
        ch.v, ch.to = to, to
        return
    end
    ch.from, ch.to, ch.t0, ch.dur = ch.v, to, t, math.max(secs, 0.01) * 1000.0
end

local function advance(ch, t)
    if ch.t0 then
        local k = (t - ch.t0) / ch.dur
        if k >= 1.0 then
            ch.v, ch.t0 = ch.to, nil
        else
            ch.v = ch.from + (ch.to - ch.from) * smooth(k > 0.0 and k or 0.0)
        end
    end
    return ch.v
end

local function serverNow()
    return ServerTime and ServerTime() or GetGameTimer()
end

---------------------------------------------------------------- state
local V = {}              -- emitter id -> deck visual
local offs = {}           -- emitter id -> { by, t }: someone just took the record off
local running = false     -- the per-frame thread is alive
local stopped = false     -- the resource is stopping
local ready = nil         -- props exist in the game (nil = not checked yet)
local loaded = false      -- models are in memory
local loadFailed = -1e9   -- when loading them last timed out (try again 10 s later)
local idleSince = 0
local label = { dui = nil, url = nil, replaced = false, id = nil }

local function isDeck(e)
    if not e or e.kind ~= 'boombox' or e.state ~= 'placed' or not e.coords then return false end
    if e.turntable then return true end
    local cfg = e.item and Config.Boomboxes[e.item]
    return cfg ~= nil and cfg.vinyl == true
end

local function propsAvailable()
    for _, h in pairs(HASH) do
        if not IsModelInCdimage(h) then return false end
    end
    return true
end

local function loadModels()
    if loaded then return true end
    if GetGameTimer() - loadFailed < 10000 then return false end
    for _, h in pairs(HASH) do RequestModel(h) end
    local t = GetGameTimer()
    while GetGameTimer() - t < 5000 do
        local all = true
        for _, h in pairs(HASH) do
            if not HasModelLoaded(h) then all = false break end
        end
        if all then loaded = true return true end
        Wait(0)
    end
    loadFailed = GetGameTimer()
    return false
end

local function releaseModels()
    if not loaded then return end
    for _, h in pairs(HASH) do SetModelAsNoLongerNeeded(h) end
    loaded = false
end

local function spawn(hash, x, y, z, yaw)
    local obj = CreateObjectNoOffset(hash, x, y, z, false, false, false)
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    SetEntityRotation(obj, 0.0, 0.0, yaw or 0.0, 2, false)
    return obj
end

local function kill(obj)
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
end

-- console space -> world
local function world(v, lx, ly, lz)
    return v.cx + lx * v.cos - ly * v.sin, v.cy + lx * v.sin + ly * v.cos, v.cz + lz
end

local function pose(obj, x, y, z, pitch, yaw)
    SetEntityCoordsNoOffset(obj, x, y, z, false, false, false)
    SetEntityRotation(obj, pitch, 0.0, yaw, 2, false)
end

local function alpha(obj, a)
    if a >= 255 then ResetEntityAlpha(obj) else SetEntityAlpha(obj, math.floor(clamp(a, 0, 254)), false) end
end

---------------------------------------------------------------- hands and animations
-- the ped of a player (server id) standing at this deck, or nil
local function handPed(v, src)
    if not src then return nil end
    local ped
    if src == MyServerId then
        ped = PlayerPedId()
    else
        local p = GetPlayerFromServerId(src)
        if p == -1 then return nil end
        ped = GetPlayerPed(p)
    end
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    local x, y, z = world(v, RECORD[1], RECORD[2], RECORD[3])
    local dx, dy, dz = c.x - x, c.y - y, c.z - z
    if dx * dx + dy * dy + dz * dz > HAND_REACH * HAND_REACH then return nil end
    return ped
end

-- a record held up by its edge in the right hand, facing the way it is about to travel
local function inHand(v, ped)
    local h = GetPedBoneCoords(ped, HAND_BONE, 0.0, 0.0, 0.0)
    local sx, sy = world(v, RECORD[1], RECORD[2], RECORD[3])
    local dx, dy = sx - h.x, sy - h.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then dx, dy, len = 0.0, 1.0, 1.0 end
    dx, dy = dx / len, dy / len
    return h.x + dx * 0.135, h.y + dy * 0.135, h.z - 0.02, 75.0, math.deg(math.atan(dy, dx))
end

local function canAnimate(ped)
    return not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) and not IsPedRagdoll(ped) and not Carrying
end

local function playAnim(a)
    if not a or not a.dict or not DoesAnimDictExist(a.dict) then return end
    if not HasAnimDictLoaded(a.dict) then RequestAnimDict(a.dict) return end
    local ped = PlayerPedId()
    if not canAnimate(ped) then return end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, 4.0, a.duration or 1400, a.flag or 48, 0.0, false, false, false)
end

local function preloadAnim(a)
    if a and a.dict and DoesAnimDictExist(a.dict) then RequestAnimDict(a.dict) end
end

local function faceDeck(v)
    local ped = PlayerPedId()
    if not canAnimate(ped) then return end
    local x, y, z = world(v, RECORD[1], RECORD[2], RECORD[3])
    TaskTurnPedToFaceCoord(ped, x, y, z, 600)
end

---------------------------------------------------------------- what the deck should be doing
local REST = { mode = 'rest', theta = 0.0 }

--[[
    Arm goal and whether the platter turns, from the emitter snapshot.
      rest   arm home on its rest                  hover  lifted over a groove, waiting for the song
      down   needle in the groove (follows it)     cue    lifted, lands exactly at `land` (local ms)
]]
local function goals(v, e, t, srv)
    local vin = e and e.vinyl
    local rec = v.rec
    if not vin or not rec or rec.phase ~= 'seated' or v.leaving[1] then return REST, false end
    local n = #(vin.tracks or {})
    local idx = vin.idx or 1
    if vin.loading then
        local th = armAngle(grooveRadius(idx, 0.0, n))
        return { mode = vin.move == 'flow' and 'down' or 'hover', theta = th }, true
    end
    local tr = e.track
    if not tr then return REST, false end
    local dur = tonumber(tr.duration) or 0
    if dur <= 0 then dur = 240.0 end      -- not known yet: assume a normal song, it glides when it arrives
    if e.playing then
        local start = e.startedAt or srv
        if start > srv then
            return { mode = 'cue', theta = armAngle(grooveRadius(idx, 0.0, n)), land = t + (start - srv) }, true
        end
        return { mode = 'down', theta = armAngle(grooveRadius(idx, (srv - start) / 1000.0 / dur, n)) }, true
    end
    return { mode = 'down', theta = armAngle(grooveRadius(idx, (e.pos or 0) / dur, n)) }, false
end

-- lift off, swing across, then do what the goal asks
local function armStep(v, g, t, dt)
    local th, lf = v.th, v.lf
    if math.abs(th.v - g.theta) > MOVE_EPS or th.t0 then
        if not th.t0 and lf.v < LIFT * 0.85 then
            toward(lf, LIFT, LIFT_T * (1.0 - lf.v / LIFT), t)
        else
            if not th.t0 or math.abs(th.to - g.theta) > 0.05 then
                toward(th, g.theta, clamp(math.abs(g.theta - th.v) / SWING, 0.45, 1.2), t)
            end
            toward(lf, LIFT, LIFT_T * (1.0 - lf.v / LIFT), t)
        end
    else
        local m = g.mode
        if m == 'down' or m == 'rest' then
            -- rides the groove exactly; a small jump (the song length arriving) glides instead
            local d = g.theta - th.v
            th.v = math.abs(d) < 0.05 and g.theta or th.v + d * (1.0 - math.exp(-dt / 0.4))
            toward(lf, 0.0, (m == 'rest' and REST_T or LOWER_T) * lf.v / LIFT, t)
        elseif m == 'hover' then
            toward(lf, LIFT, LIFT_T * (1.0 - lf.v / LIFT), t)
        elseif t < g.land - LOWER_T * 1000.0 then
            toward(lf, LIFT, LIFT_T * (1.0 - lf.v / LIFT), t)
        else
            -- the needle lands on the dot (or as soon as it can, if the arm got here late)
            toward(lf, 0.0, math.max(0.2, (g.land - t) / 1000.0), t)
        end
    end
    advance(lf, t)
    advance(th, t)
end

local function spinStep(v, on, t, dt)
    local sp = v.sp
    local want = on and RPM or 0.0
    if (sp.t0 and sp.to ~= want) or (not sp.t0 and sp.v ~= want) then
        toward(sp, want, (on and SPIN_UP or SPIN_DOWN) * math.abs(want - sp.v) / RPM, t)
    end
    local w0 = sp.v
    local w1 = advance(sp, t)
    v.spin = (v.spin - (w0 + w1) * 0.5 * dt) % 360.0     -- clockwise seen from above
end

-- jump straight to where things should be (someone walked up, or the console streamed in)
local function snap(v, g, on, t)
    v.th.v, v.th.to, v.th.t0 = g.theta, g.theta, nil
    local lift = 0.0
    if g.mode == 'hover' then
        lift = LIFT
    elseif g.mode == 'cue' then
        local k = (t - (g.land - LOWER_T * 1000.0)) / (LOWER_T * 1000.0)
        lift = k <= 0.0 and LIFT or LIFT * (1.0 - smooth(math.min(k, 1.0)))
    end
    v.lf.v, v.lf.to, v.lf.t0 = lift, lift, nil
    local w = on and RPM or 0.0
    v.sp.v, v.sp.to, v.sp.t0 = w, w, nil
end

---------------------------------------------------------------- records
local function recordKey(vin) return vin and (tostring(vin.item) .. '@' .. tostring(vin.at)) or nil end

local function seatedPose(v, r)
    local x, y, z = world(v, RECORD[1], RECORD[2], RECORD[3])
    return x, y, z, 0.0, v.h + v.spin + r.yaw
end

local function ensureObj(v, r, x, y, z)
    if not r.obj then r.obj = spawn(HASH.vinyl, x, y, z, v.h) end
    return r.obj
end

-- the record going on: hand, flight, settle. Returns true while it is still moving (and on the frame it lands).
local function stepIn(v, r, t, srv)
    local u = (srv - r.at) / 1000.0
    if r.mine then
        if not r.faced and u >= IN_FACE then r.faced = true faceDeck(v) end
        if not r.reached and u >= IN_REACH then r.reached = true playAnim(PUT) end
    end
    if u >= IN_SEATED then
        r.phase = 'seated'
        local x, y, z, p, yaw = seatedPose(v, r)
        local obj = ensureObj(v, r, x, y, z)
        if obj then pose(obj, x, y, z, p, yaw) alpha(obj, 255) end
        r.spin = v.spin
        return true             -- one more frame: the platter and arm start from here
    end
    if u < IN_HAND then return true end

    if u < IN_LET_GO then
        local ped = r.hand and handPed(v, r.by) or nil
        if ped then
            local x, y, z, p, yaw = inHand(v, ped)
            local obj = ensureObj(v, r, x, y, z)
            if obj then pose(obj, x, y, z, p, yaw) end
            r.held = { x, y, z, p, yaw }
        end
        return true
    end

    if not r.p0 then
        if r.held then
            r.p0 = r.held
        else
            -- nobody's hand to come from: it floats down from above and fades in
            local x, y, z = world(v, RECORD[1], RECORD[2], RECORD[3] + 0.35)
            r.p0 = { x, y, z, 0.0, v.h + v.spin + r.yaw - 90.0 }
            r.fade = true
        end
    end
    local sx, sy, sz, _, yawEnd = seatedPose(v, r)
    local obj = ensureObj(v, r, r.p0[1], r.p0[2], r.p0[3])
    if not obj then return true end
    if u < IN_OVER then
        local k = smoother((u - IN_LET_GO) / (IN_OVER - IN_LET_GO))
        local p0 = r.p0
        local dx, dy = sx - p0[1], sy - p0[2]
        local arc = math.min(0.12, 0.25 * math.sqrt(dx * dx + dy * dy)) * math.sin(math.pi * k)
        pose(obj, lerp(p0[1], sx, k), lerp(p0[2], sy, k), lerp(p0[3], sz + HOVER, k) + arc,
            lerp(p0[4], 0.0, k), lerpAngle(p0[5], yawEnd, k))
        alpha(obj, r.fade and 255 * k or 255)
        return true
    end
    -- down the spindle, and the last few millimetres it just drops
    local k = (u - IN_OVER) / (IN_SEATED - IN_OVER)
    local dz
    if k < 0.75 then
        dz = DROP + (HOVER - DROP) * (1.0 - smooth(k / 0.75))
    else
        local kk = (k - 0.75) / 0.25
        dz = DROP * (1.0 - kk * kk)
    end
    pose(obj, sx, sy, sz + dz, 0.0, yawEnd)
    alpha(obj, 255)
    return true
end

-- a record coming off: wait for the arm, lift, then to the hand (or up and away). Returns false once gone.
local function stepOff(v, r, t)
    if r.phase == 'wait' then
        local clear = v.dying or (v.th.v > ARM_CLEAR and v.sp.v < 50.0) or t - r.t0 > 2500
        if not clear then
            if r.obj and r.spin ~= v.spin then
                SetEntityRotation(r.obj, 0.0, 0.0, v.h + v.spin + r.yaw, 2, false)
                r.spin = v.spin
            end
            return true
        end
        local x, y, z, _, yaw = seatedPose(v, r)
        r.phase, r.t0, r.base = 'lift', t, { x, y, z, yaw }
        if r.mine then faceDeck(v) playAnim(TAKE) end
    end
    if not r.obj then return false end
    local b = r.base
    if r.phase == 'lift' then
        local k = math.min((t - r.t0) / (OFF_LIFT * 1000.0), 1.0)
        pose(r.obj, b[1], b[2], b[3] + 0.07 * smooth(k), 0.0, b[4])
        if k >= 1.0 then
            r.ped = handPed(v, r.by)
            r.phase, r.t0 = r.ped and 'away' or 'rise', t
        end
        return true
    end
    if r.phase == 'away' or r.phase == 'hold' then
        if not DoesEntityExist(r.ped) then
            r.phase, r.t0 = 'rise', t
            local c = GetEntityCoords(r.obj)
            r.base = { c.x, c.y, c.z - 0.07, b[4] }
            return true
        end
        local hx, hy, hz, hp, hyaw = inHand(v, r.ped)
        if r.phase == 'hold' then
            pose(r.obj, hx, hy, hz, hp, hyaw)
            return t - r.t0 < OFF_HOLD * 1000.0
        end
        local k = math.min((t - r.t0) / (OFF_AWAY * 1000.0), 1.0)
        local e = smoother(k)
        local sz = b[3] + 0.07
        local dx, dy = hx - b[1], hy - b[2]
        local arc = math.min(0.12, 0.25 * math.sqrt(dx * dx + dy * dy)) * math.sin(math.pi * e)
        pose(r.obj, lerp(b[1], hx, e), lerp(b[2], hy, e), lerp(sz, hz, e) + arc, lerp(0.0, hp, e), lerpAngle(b[4], hyaw, e))
        if k >= 1.0 then r.phase, r.t0 = 'hold', t end
        return true
    end
    -- rise and fade
    local k = math.min((t - r.t0) / (OFF_RISE * 1000.0), 1.0)
    pose(r.obj, b[1], b[2], b[3] + 0.07 + 0.45 * smooth(k), 0.0, b[4])
    alpha(r.obj, 255 * (1.0 - k))
    return k < 1.0
end

local function leave(v, r, t)
    local off = offs[v.id]
    local fresh = off and GetGameTimer() - off.t < 5000
    r.by = fresh and off.by or nil
    r.mine = fresh and off.by == MyServerId or false
    r.phase, r.t0 = 'wait', t
    if r.mine then preloadAnim(TAKE) end
    v.leaving[#v.leaving + 1] = r
end

-- the record on the deck changed (on, off or swapped)
local function syncRecord(v, e, t, srv)
    local vin = e and e.vinyl
    local key = recordKey(vin)
    if key == v.recKey then return end
    local old = v.rec
    if old then
        if old.phase == 'seated' then leave(v, old, t) else kill(old.obj) end
        v.rec = nil
    end
    v.recKey = key
    if not vin then return end
    local at = tonumber(vin.at) or srv
    local live = not v.fresh and srv < at + IN_SEATED * 1000.0
    v.rec = {
        at = at, by = vin.by, phase = live and 'in' or 'seated',
        yaw = (at % 360000) / 1000.0,            -- any label angle, the same on every client
        hand = live and vin.on == v.id,          -- linked decks get the record without the hand
    }
    if live and vin.by == MyServerId and v.rec.hand then
        v.rec.mine = true
        preloadAnim(PUT)
    end
end

---------------------------------------------------------------- one deck per frame
local function drop(v)
    kill(v.platter) kill(v.arm)
    v.platter, v.arm = nil, nil
end

local function wipe(v)
    drop(v)
    if v.rec then kill(v.rec.obj) end
    for _, r in ipairs(v.leaving) do kill(r.obj) end
    v.rec, v.recKey, v.leaving = nil, nil, {}
end

-- returns true while anything on this deck still moves
local function update(v, t, dt, srv)
    local busy = false
    if not v.dying then
        if not v.platter then return false end
        local e = Emitters[v.id]
        syncRecord(v, e, t, srv)
        local g, on = goals(v, e, t, srv)
        if v.fresh then
            v.fresh = false
            snap(v, g, on, t)
        end
        armStep(v, g, t, dt)
        spinStep(v, on, t, dt)
        if v.sp.v ~= 0.0 or v.lastSpin ~= v.spin then
            SetEntityRotation(v.platter, 0.0, 0.0, v.h + v.spin, 2, false)
            v.lastSpin = v.spin
        end
        -- a needle riding its groove moves a few thousandths of a degree a second: no need to set it every frame
        local th, lf = v.th.v, v.lf.v
        local riding = g.mode == 'down' and on and not v.th.t0
        if lf ~= v.lastLf or (th ~= v.lastTh and not (riding and math.abs(th - v.lastTh) < 0.002)) then
            SetEntityRotation(v.arm, lf, 0.0, v.h + th, 2, false)
            v.lastTh, v.lastLf = th, lf
        end
        local r = v.rec
        if r then
            if r.phase ~= 'seated' then
                busy = stepIn(v, r, t, srv)
            elseif not r.obj then
                local x, y, z, p, yaw = seatedPose(v, r)
                local obj = ensureObj(v, r, x, y, z)
                if obj then pose(obj, x, y, z, p, yaw) end
                r.spin = v.spin
            elseif r.spin ~= v.spin then
                SetEntityRotation(r.obj, 0.0, 0.0, v.h + v.spin + r.yaw, 2, false)   -- it only turns
                r.spin = v.spin
            end
        end
        busy = busy or v.sp.v ~= 0.0 or v.sp.t0 ~= nil or v.th.t0 ~= nil or v.lf.t0 ~= nil
            or math.abs(v.th.v - g.theta) > 0.005
    end
    for i = #v.leaving, 1, -1 do
        local r = v.leaving[i]
        if stepOff(v, r, t) then
            busy = true
        else
            kill(r.obj)
            table.remove(v.leaving, i)
        end
    end
    if v.dying and not v.leaving[1] then V[v.id] = nil end
    return busy
end

local function frameLoop()
    while not stopped do
        local t = GetGameTimer()
        local dt = clamp(GetFrameTime(), 0.0, 0.1)
        local srv = serverNow()
        local busy = false
        for _, v in pairs(V) do
            if update(v, t, dt, srv) then busy = true end
        end
        if not busy then break end
        Wait(0)
    end
    running = false
end

local function wake()
    if running or not ready or stopped then return end
    running = true
    CreateThread(frameLoop)
end

---------------------------------------------------------------- finding decks (twice a second at most)
-- the emitter is gone (packed up / broken): the parts go, a record on it still flies off
local function retire(v)
    if v.dying then return end
    drop(v)
    local r = v.rec
    v.rec, v.recKey = nil, nil
    if r then
        if r.phase == 'seated' and r.obj then leave(v, r, GetGameTimer()) else kill(r.obj) end
    end
    v.dying = true
    if not v.leaving[1] then V[v.id] = nil end
end

local function bind(v, e)
    local ent = LocateEmitter(e)
    if ent ~= v.console then
        wipe(v)
        v.console = ent
    end
    if not ent or not DoesEntityExist(ent) then return false end
    if not loadModels() then return false end
    local c = GetEntityCoords(ent)
    local h = GetEntityHeading(ent)
    local moved = not v.cx or math.abs(c.x - v.cx) + math.abs(c.y - v.cy) + math.abs(c.z - v.cz) > 0.005
        or math.abs(h - v.h) > 0.2
    if moved then
        v.cx, v.cy, v.cz, v.h = c.x, c.y, c.z, h
        v.cos, v.sin = math.cos(math.rad(h)), math.sin(math.rad(h))
        if v.platter then
            -- it was moved: put everything back on it
            wipe(v)
        end
    end
    if not v.platter then
        local px, py, pz = world(v, PLATTER[1], PLATTER[2], PLATTER[3])
        local ax, ay, az = world(v, PIVOT[1], PIVOT[2], PIVOT[3])
        v.platter = spawn(HASH.platter, px, py, pz, h + v.spin)
        v.arm = spawn(HASH.arm, ax, ay, az, h + v.th.v)
        if not v.platter or not v.arm then drop(v) return false end
        v.lastSpin, v.lastTh, v.lastLf = nil, nil, nil
        v.fresh = true
    end
    return true
end

local function newVisual(id)
    return { id = id, th = chan(0.0), lf = chan(0.0), sp = chan(0.0), spin = 0.0, leaving = {} }
end

-- one album cover on the label of the nearest record (the texture is shared by every record)
local function urlencode(s)
    return (s:gsub('[^%w%-%._~]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

local function html(s)
    return (tostring(s or ''):gsub('[&<>"\']', { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;' }))
end

local function labelPage(vin)
    local px = LABEL_PX
    return 'data:text/html;charset=utf-8,' .. urlencode(([[<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:%dpx;height:%dpx;overflow:hidden;background:#0e1011}
.l{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
background:radial-gradient(circle,#15181a 0 30%%,#08afa2 30.5%% 33%%,#15181a 33.5%%);color:#fff;font:600 %dpx sans-serif;
text-align:center;letter-spacing:.08em;text-transform:uppercase}
.l b{display:block;max-width:60%%;margin-top:%dpx}.l span{opacity:.6;font-size:.7em;display:block;max-width:60%%}
img{position:absolute;inset:0;width:100%%;height:100%%;object-fit:cover}
.r{position:absolute;inset:0;border-radius:50%%;box-shadow:inset 0 0 0 %dpx rgba(0,0,0,.28)}
.h{position:absolute;left:50%%;top:50%%;width:%dpx;height:%dpx;margin:-%dpx;border-radius:50%%;background:#050505}
</style></head><body><div class="l"><b>%s</b><span>%s</span></div>
<img src="%s" onerror="this.remove()"><div class="r"></div><div class="h"></div></body></html>]]):format(
        px, px, math.floor(px * 0.045), math.floor(px * 0.2), math.floor(px * 0.018),
        math.floor(px * 0.075), math.floor(px * 0.075), math.floor(px * 0.0375),
        html(vin.album), html(vin.artist), html(vin.cover)))
end

local function setLabel(vin)
    local url = vin and vin.cover or nil
    if url == label.url then return end
    label.url = url
    if url then
        if not label.dui then
            label.dui = CreateDui('about:blank', LABEL_PX, LABEL_PX)
            local txd = CreateRuntimeTxd('nzspk_vinyl_label')
            CreateRuntimeTextureFromDuiHandle(txd, 'label', GetDuiHandle(label.dui))
        end
        SetDuiUrl(label.dui, labelPage(vin))
        if not label.replaced then
            AddReplaceTexture('nayzeee_audio_texture', 'nayzeee_vinyl_label', 'nzspk_vinyl_label', 'label')
            label.replaced = true
        end
    else
        if label.replaced then
            RemoveReplaceTexture('nayzeee_audio_texture', 'nayzeee_vinyl_label')
            label.replaced = false
        end
        if label.dui then SetDuiUrl(label.dui, 'about:blank') end
    end
end

-- nearest playing record wins (then nearest paused one); the current one keeps it unless another
-- is clearly closer, so walking between two decks doesn't flip the label back and forth
local function pickLabel(me)
    if not LABEL or Settings.streamer then return setLabel(nil) end
    local best, bestScore, bestId, cur
    for id, v in pairs(V) do
        local e = Emitters[id]
        local vin = e and e.vinyl
        if v.platter and v.rec and vin and type(vin.cover) == 'string' and vin.cover:match('^https?://') then
            local score = #(me - e.coords) + ((e.playing and e.track) and 0.0 or 1000.0)
            if id == label.id then cur = { vin, score } end
            if not bestScore or score < bestScore then best, bestScore, bestId = vin, score, id end
        end
    end
    if cur and bestId ~= label.id and bestScore > cur[2] - 2.0 then best, bestId = cur[1], label.id end
    label.id = bestId
    setLabel(best)
end

local function manage()
    local me = GetEntityCoords(PlayerPedId())
    local near = false
    for id, e in pairs(Emitters) do
        if isDeck(e) then
            local c = e.coords
            local dx, dy, dz = c.x - me.x, c.y - me.y, c.z - me.z
            local d2 = dx * dx + dy * dy + dz * dz
            local v = V[id]
            if d2 <= DIST * DIST then
                if not v or v.dying then
                    if v then wipe(v) end
                    V[id] = newVisual(id)
                end
                near = true
            elseif v and not v.dying and d2 > (DIST + 5.0) * (DIST + 5.0) then
                wipe(v)
                V[id] = nil
            end
        end
    end
    for id, v in pairs(V) do
        local e = Emitters[id]
        if not v.dying then
            if not isDeck(e) then retire(v) else bind(v, e) end
        end
    end
    pickLabel(me)
    if next(V) then
        idleSince = GetGameTimer()
        wake()
    elseif loaded and GetGameTimer() - idleSince > 15000 then
        releaseModels()
    end
    return near
end

CreateThread(function()
    Wait(2000)
    ready = propsAvailable()
    if not ready then
        NZ.Debug('turntable props are not in the game yet (nayzeee_tt_platter / nayzeee_tt_arm / nayzeee_vinyl): visuals off')
        return
    end
    while not stopped do
        Wait(manage() and 500 or 1000)
    end
end)

---------------------------------------------------------------- server events (react right away)
RegisterNetEvent(RES .. ':client:emitter', function(e)
    if ready and type(e) == 'table' and V[e.id] then wake() end
end)

RegisterNetEvent(RES .. ':client:remove', function(id)
    local v = V[id]
    if v and not v.dying then
        retire(v)
        wake()
    end
end)

RegisterNetEvent(RES .. ':client:vinylOff', function(id, by, _)
    offs[id] = { by = by or nil, t = GetGameTimer() }
    if V[id] then wake() end
    for k, o in pairs(offs) do
        if GetGameTimer() - o.t > 10000 then offs[k] = nil end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    stopped = true
    for _, v in pairs(V) do wipe(v) end
    V = {}
    if label.replaced then RemoveReplaceTexture('nayzeee_audio_texture', 'nayzeee_vinyl_label') end
    if label.dui then DestroyDui(label.dui) end
    label.dui, label.replaced = nil, false
    releaseModels()
end)

-- the geometry, for other files and tests
NZ.Turntable = { armAngle = armAngle, grooveRadius = grooveRadius, smooth = smooth, smoother = smoother }
