--[[
    NAYZEEE RADIO - Jammers (client): world props, noise bed, placing, pick up and hack

    The server keeps every placed jammer in GlobalState 'nzr_jammers'. Each client spawns its
    own frozen, non-networked props for the ones within Config.Jammers.drawDistance (a scan
    every second near a jammer, up to 5 s when the nearest one is far away, nothing at all
    while there are none) and works out its own jam: NZR.Signal.Jam at the player with the
    active radio's jamResist. Inside a jammer's radius a 250 ms loop feeds the noise bed of
    a powered, unmuted radio ('_core' noise); outside every radius it stops.

    Placing (the jammer item → 'nzr:jammer:begin'): a see-through ghost follows a ray from
    the camera, the wheel or the arrow keys turn it (Shift = slow), [E] sets it down,
    Backspace / right mouse put it away. The spot must be in reach, flat enough, dry and not
    on a car or a person; the overlay app shows the key card and whether the spot is good.
    The server checks everything again.

    On a placed jammer (bridge target: ox_target / qb-target / ... or the built-in [E] prompt):
    the owner and Config.Jammers.seizeJobs get "Pick up", everyone else (or only
    Config.Jammers.hackJobs) gets "Hack": 'nzr:jammer:hackStart' → the hack window (focused)
    while a tablet animation plays → 'hack:result' → 'nzr:jammer:hackResult'. Walking away,
    dying or the jammer going away ends the attempt.

      NZR.Jammers.LocalJam(resist?) → 0..1   jam at the player (resist = active radio's jamResist)
      NZR.Jammers.NoiseGain(jam, volume, muted, powered) → 0..1   noise bed level (pure)
      NZR.Jammers.CheckSpot(info) → ok, reason    placement rule (pure), reason ∈ vehicle, water,
                                                  aim, far, steep, surface
              info = { hit, coords, normal, from, reach, entityType, onJammer, water, inVehicle, swimming }
      NZR.Jammers.Place(type) → bool         start placing      NZR.Jammers.CancelPlace()
      NZR.Jammers.Hack(id) → bool            NZR.Jammers.IsBusy() → bool (placing or hacking)
      NZR.Jammers.List() → nzr_jammers       NZR.Jammers.Spawned() → { [id] = entity }
      NZR.Jammers.UpdateNoise() → inside     NZR.Jammers.ModelCode(type) → 'JX-40'

    EVENTS SENT      nzr:jammer:place (type, coords, heading), nzr:jammer:pickup (id),
                     nzr:jammer:hackResult (id, token, success) (C→S)
    CALLBACKS        nzr:jammer:hackStart (id) → { ok, token, bands, time, seed, type, label } (C→S)
    EVENTS HANDLED   nzr:jammer:begin (type), nzr:jammer:hacked (id, by) (S→C)
    NUI SENT         overlay open { hints = {}, place = true } / place { title, code, label, type, hints,
                     valid, status, reason, heading } / placeHide / close (only when placing opened it)
                     (place goes out again when the heading changes by a degree)
                     hack open { id, title, code, label, type, bands, time, seed, difficulty } / close
                     _core noise { gain }, _core sfx { name = 'place' | 'error' }
    NUI HANDLED      'hack:result' { id, success, cancelled }, 'hack:close'
    STATE BAGS       reads GlobalState.nzr_jammers (+ change handler)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Jammers = NZR.Jammers or {}
local J = NZR.Jammers

local GROUP = 'nzr_jammers'
local GHOST_GROUP = 'nzr_jammer_ghost'
local FALLBACK_MODEL = 'prop_ld_case_01'     -- something to see and target while the props resource is missing
local SCAN_MS = 1000
local SCAN_MAX_MS = 5000
local SCAN_SPEED = 60.0                      -- m/s: how fast someone can close the gap to a boundary between scans
local DESPAWN_SLACK = 10.0
local RETRY_MS = 30000
local NOISE_MS = 250
local JAM_CACHE_MS = 100
local NOISE_EPS = 0.02

local GHOST_ALPHA = 170
local GHOST_ALPHA_BAD = 80
local MIN_NORMAL_Z = 0.80                    -- about 37° of slope at most
local MAX_RISE = 1.6                         -- metres between the ped's centre and the spot
local RAY_FLAGS = 23                         -- world 1 + vehicles 2 + peds 4 + objects 16
local RAY_EXTRA = 8.0                        -- the camera sits behind the ped
local ROTATE_STEP = 10.0
local ROTATE_SPEED = 90.0                    -- degrees a second while an arrow key is held
local FINE = 0.2

local HACK_REACH = 3.0
local HACK_CHECK_MS = 250
local TARGET_DISTANCE = 2.0

local CODES = { pocket = 'JX-10', case = 'JX-40', heavy = 'JX-90' }

local PLACE_ANIM = { dict = 'random@domestic', clip = 'pickup_low' }
local HACK_ANIM = {
    dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', clip = 'base',
    prop = { model = 'prop_cs_tablet', bone = 60309, pos = vector3(0.03, 0.002, 0.0), rot = vector3(10.0, 160.0, 0.0) },
}

-- while placing: attack / aim / weapon wheel and slots / cover / reload / melee, the wheel
-- and arrows (turning), E (set down), Backspace (put away)
local PLACE_BLOCK = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 47, 58, 140, 141, 142, 143, 174, 175, 177, 194, 241, 242, 257, 263, 264 }

local list = {}           -- GlobalState nzr_jammers: [id] = { t, x, y, z, h, o, e }
local known = {}          -- [id] = type, kept after removal (owner notices)
local spawned = {}        -- [id] = { ent, x, y, z, h, t, failed, retryAt }
local entIndex = {}       -- [entity] = id
local scanning = false
local noiseLoop = false
local lastGain = 0.0
local jamCache = {}       -- [resist] = { at, v }
local placing = nil       -- { type, gen }
local placeGen = 0
local hacking = nil       -- { id, token, anim, done }
local myId = nil

local function L(key, ...) return NZR.L('world.' .. key, ...) end
local function cfg() return Config.Jammers or {} end
local function enabled() return cfg().enabled ~= false end
local function clamp(v, lo, hi) return NZR.Util.Clamp(v, lo, hi) end

local function typeDef(t)
    local types = cfg().Types
    return type(t) == 'string' and type(types) == 'table' and types[t] or nil
end

local function me()
    if not myId then myId = GetPlayerServerId(PlayerId()) end
    return myId
end

local function toast(key, kind, ...)
    NZR.UI.Toast({ title = L('title_jammer'), message = L(key, ...), type = kind or 'info' })
end

local function sfx(name)
    NZR.UI.Send('_core', 'sfx', { name = name })
end

local function drawDistance()
    return tonumber(cfg().drawDistance) or 150.0
end

function J.ModelCode(t)
    return CODES[t] or 'JX'
end

function J.List()
    return list
end

function J.Spawned()
    local out = {}
    for id, s in pairs(spawned) do
        if s.ent and s.ent ~= 0 then out[id] = s.ent end
    end
    return out
end

function J.IsBusy()
    return placing ~= nil or hacking ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
-- JAM AT THE PLAYER + NOISE BED
-- ════════════════════════════════════════════════════════════════════════

local function activeResist()
    local S = NZR.Radio and NZR.Radio.State
    local m = S and S.model and Config.Radios.Models[S.model]
    return m and tonumber(m.jamResist) or 0.0
end

function J.LocalJam(resist)
    if not enabled() or next(list) == nil then return 0.0 end
    if resist == nil then resist = activeResist() end
    local now = GetGameTimer()
    local c = jamCache[resist]
    if c and now - c.at < JAM_CACHE_MS then return c.v end
    local ok, v = pcall(NZR.Signal.Jam, GetEntityCoords(PlayerPedId()), list, resist)
    v = ok and clamp(tonumber(v) or 0.0, 0.0, 1.0) or 0.0
    jamCache[resist] = { at = now, v = v }
    return v
end

-- How loud the static is: the jam, lifted a little at the fringe so you notice it
-- coming, scaled by the radio's volume knob (a turned-down radio hisses quietly too).
function J.NoiseGain(jam, volume, muted, powered)
    jam = clamp(tonumber(jam) or 0.0, 0.0, 1.0)
    if not powered or muted or jam < NOISE_EPS then return 0.0 end
    local vol = clamp((tonumber(volume) or 60) / 100, 0.0, 1.0)
    local g = (jam ^ 0.8) * (0.3 + 0.7 * vol)
    return math.floor(clamp(g, 0.0, 1.0) * 100 + 0.5) / 100
end

local function sendNoise(gain)
    if gain == lastGain then return end
    if gain > 0 and lastGain > 0 and math.abs(gain - lastGain) < NOISE_EPS then return end
    lastGain = gain
    NZR.UI.Send('_core', 'noise', { gain = gain })
end

local function insideAny(pos)
    for _, j in pairs(list) do
        local def = typeDef(j.t)
        if def and NZR.Signal.Distance(pos, j) < (tonumber(def.radius) or 0.0) then return true end
    end
    return false
end

function J.UpdateNoise()
    local pos = GetEntityCoords(PlayerPedId())
    local inside = enabled() and insideAny(pos)
    local jam = inside and J.LocalJam() or 0.0
    local S = NZR.Radio.State
    sendNoise(inside and J.NoiseGain(jam, S.volume, S.muted, S.power == true and S.model ~= nil) or 0.0)
    return inside
end

local function startNoise()
    if noiseLoop then return end
    noiseLoop = true
    CreateThread(function()
        while noiseLoop and J.UpdateNoise() do Wait(NOISE_MS) end
        noiseLoop = false
        sendNoise(0.0)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- WORLD PROPS
-- ════════════════════════════════════════════════════════════════════════

local function isOwner(j)
    return type(j) == 'table' and tonumber(j.o) == me()
end

local function jobMatches(rule)
    if type(rule) ~= 'table' then return false end
    local ok, match = pcall(function() return Bridge.JobMatches(Bridge.GetJob(), rule, false) end)
    return ok and match == true
end

-- Not with the radio up: its camera and pose would cover the hack window and replace the
-- tablet / pick-up animation (and [E] is not a key the raised radio takes away).
local function canAct()
    local ped = PlayerPedId()
    return not J.IsBusy() and not NZR.Radio.State.raised and not IsPedInAnyVehicle(ped, false)
        and not NZR.Radio.API.IsDead()
end

local function lowerRadio()
    if NZR.Radio.State.raised then NZR.Radio.API.Lower() end
end

local function targetOptions(id)
    return {
        {
            name = 'nzr_jammer_pickup', label = L('target_pickup'), icon = 'pickup',
            distance = TARGET_DISTANCE, order = 10,
            canInteract = function()
                local j = list[id]
                return j ~= nil and canAct() and (isOwner(j) or jobMatches(cfg().seizeJobs))
            end,
            onSelect = function(ent)
                if not list[id] then return end
                CreateThread(function()
                    lowerRadio()
                    local ped = PlayerPedId()
                    if ent and ent ~= 0 and DoesEntityExist(ent) then TaskTurnPedToFaceEntity(ped, ent, 500) end
                    NZR.Anim.Play(ped, PLACE_ANIM.dict, PLACE_ANIM.clip, { flag = 0, duration = 1100, blendIn = 6.0, blendOut = -4.0 })
                    TriggerServerEvent('nzr:jammer:pickup', id)
                end)
            end,
        },
        {
            name = 'nzr_jammer_hack', label = L('target_hack'), icon = 'hack',
            distance = TARGET_DISTANCE, order = 20,
            canInteract = function()
                local j = list[id]
                if j == nil or isOwner(j) or not canAct() then return false end
                local rule = cfg().hackJobs
                return type(rule) ~= 'table' or jobMatches(rule)
            end,
            onSelect = function() J.Hack(id) end,
        },
    }
end

local function despawn(id)
    local s = spawned[id]
    spawned[id] = nil
    if not s or not s.ent or s.ent == 0 then return end
    entIndex[s.ent] = nil
    pcall(Bridge.Target.RemoveEntity, s.ent)
    NZR.Props.Delete(s.ent)
end

local function spawn(id, j)
    local def = typeDef(j.t)
    if not def then return end
    local rec = { ent = 0, x = j.x, y = j.y, z = j.z, h = j.h, t = j.t }
    spawned[id] = rec
    local ent = NZR.Props.Spawn(def.model, vector3(j.x + 0.0, j.y + 0.0, j.z + 0.0), {
        group = GROUP, heading = tonumber(j.h) or 0.0, frozen = true, collision = true,
        fallback = FALLBACK_MODEL, timeout = 4000,
    })
    if spawned[id] ~= rec then
        -- removed or moved while the model loaded
        if ent and ent ~= 0 then NZR.Props.Delete(ent) end
        return
    end
    if not ent or ent == 0 then
        rec.failed, rec.retryAt = true, GetGameTimer() + RETRY_MS
        NZR.Debug('jammer prop could not be spawned', def.model)
        return
    end
    rec.ent = ent
    entIndex[ent] = id
    pcall(SetEntityLodDist, ent, math.floor(drawDistance() + 25.0))
    pcall(Bridge.Target.Entity, ent, targetOptions(id))
end

-- Time until the player could cross a boundary that matters (draw distance or a radius).
local function sleepFor(pos)
    local draw = drawDistance()
    local gap = math.huge
    for _, j in pairs(list) do
        local def = typeDef(j.t)
        if def then
            local d = NZR.Signal.Distance(pos, j)
            gap = math.min(gap, math.abs(d - draw), math.abs(d - (tonumber(def.radius) or 0.0)))
        end
    end
    if gap == math.huge then return SCAN_MAX_MS end
    return math.floor(clamp(gap / SCAN_SPEED * 1000.0, SCAN_MS, SCAN_MAX_MS))
end

local function scanOnce()
    local pos = GetEntityCoords(PlayerPedId())
    local draw = drawDistance()
    local inside = false
    local now = GetGameTimer()
    for id, j in pairs(list) do
        local def = typeDef(j.t)
        if def then
            local d = NZR.Signal.Distance(pos, j)
            if d < (tonumber(def.radius) or 0.0) then inside = true end
            local s = spawned[id]
            if s and (s.x ~= j.x or s.y ~= j.y or s.z ~= j.z or s.h ~= j.h) then
                despawn(id)
                s = nil
            end
            if d <= draw then
                if not s or (s.failed and now >= (s.retryAt or 0)) then spawn(id, j) end
            elseif s and d > draw + DESPAWN_SLACK then
                despawn(id)
            end
        end
    end
    for id in pairs(spawned) do
        if not list[id] then despawn(id) end
    end
    return pos, inside
end

local function wakeScan()
    if scanning or not enabled() then return end
    if next(list) == nil and next(spawned) == nil then return end
    scanning = true
    CreateThread(function()
        while true do
            local pos, inside = scanOnce()
            if inside then startNoise() end
            if next(list) == nil and next(spawned) == nil then break end
            Wait(sleepFor(pos))
        end
        scanning = false
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- HACK
-- ════════════════════════════════════════════════════════════════════════

local function finishHack(success, why)
    local h = hacking
    if not h or h.done then return end
    h.done = true
    hacking = nil
    if h.token and why ~= 'gone' then
        TriggerServerEvent('nzr:jammer:hackResult', h.id, h.token, success == true)
    end
    if h.opened then NZR.UI.Close('hack') end
    if h.anim then NZR.Anim.Stop(PlayerPedId(), { token = h.anim }) end
    if why == 'far' then toast('hack_far', 'error')
    elseif why == 'gone' then toast('hack_gone', 'info') end
end

local REFUSED = { gone = 'hack_gone', far = 'hack_far', busy = 'hack_busy', denied = 'hack_denied', lockout = 'hack_lockout' }

function J.Hack(id)
    if not enabled() or J.IsBusy() then return false end
    local j = list[id]
    if not j or not typeDef(j.t) then return false end
    hacking = { id = id, done = false }
    local h = hacking
    CreateThread(function()
        local ok, res = pcall(lib.callback.await, 'nzr:jammer:hackStart', false, id)
        if not ok or type(res) ~= 'table' then res = { ok = false, reason = 'error' } end
        if hacking ~= h or h.done then return end
        if not res.ok then
            hacking = nil
            if res.reason == 'lockout' then
                toast('hack_lockout', 'error', math.max(1, math.floor(tonumber(res.wait) or 1)))
            else
                toast(REFUSED[res.reason] or 'hack_error', 'error')
            end
            return
        end
        h.token = res.token
        local jt = list[id] and list[id].t or j.t
        if not list[id] then return finishHack(false, 'gone') end
        local def = typeDef(jt) or {}
        lowerRadio()
        local ped = PlayerPedId()
        local okA, token = NZR.Anim.Play(ped, HACK_ANIM.dict, HACK_ANIM.clip, { flag = 49, prop = HACK_ANIM.prop })
        if okA then h.anim = token end
        if h.done then return end
        h.opened = true
        NZR.UI.Open('hack', {
            id = id, title = L('hack_title', J.ModelCode(jt), def.label or jt),
            code = J.ModelCode(jt), label = def.label or jt, type = jt,
            bands = tonumber(res.bands) or tonumber(def.bands) or 1, time = tonumber(res.time) or tonumber(def.time) or 30,
            seed = res.seed, difficulty = tonumber(res.bands) or tonumber(def.bands) or 1,
        }, { focus = true, cursor = true })
        -- the attempt ends when the player walks off, dies, gets in a car or the jammer goes
        while hacking == h and not h.done do
            local jj = list[id]
            local p = PlayerPedId()
            if not jj then
                finishHack(false, 'gone')
            elseif NZR.Radio.API.IsDead() then
                finishHack(false, 'dead')
            elseif IsPedInAnyVehicle(p, false) or NZR.Signal.Distance(GetEntityCoords(p), jj) > HACK_REACH then
                finishHack(false, 'far')
            end
            Wait(HACK_CHECK_MS)
        end
    end)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- PLACING
-- ════════════════════════════════════════════════════════════════════════

local function dist3(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The placement rule, without natives (tested offline). Order matters: the reason shown
-- is the first thing the player has to change.
function J.CheckSpot(info)
    info = info or {}
    if info.inVehicle then return false, 'vehicle' end
    if info.swimming then return false, 'water' end
    if not info.hit or not info.coords or not info.from then return false, 'aim' end
    local c, from = info.coords, info.from
    if dist3(from, c) > (tonumber(info.reach) or 3.0) then return false, 'far' end
    if math.abs(c.z - from.z) > MAX_RISE then return false, 'far' end
    local nz = info.normal and tonumber(info.normal.z) or 0.0
    if nz < (tonumber(info.minNormal) or MIN_NORMAL_Z) then return false, 'steep' end
    if info.entityType == 1 or info.entityType == 2 or info.onJammer then return false, 'surface' end
    if info.water then return false, 'water' end
    return true, nil
end

local function waterAt(x, y, z)
    local ok, found, h = pcall(GetWaterHeightNoWaves, x, y, z + 2.0)
    if ok and found and tonumber(h) and h >= z - 0.05 then return true end
    ok, found, h = pcall(GetWaterHeight, x, y, z + 2.0)
    return ok and found == true and tonumber(h) ~= nil and h >= z - 0.05
end

local function placeHints()
    return {
        { keys = { 'E' }, label = L('place_hint_set') },
        { keys = { 'WHEEL', 'ARROWS' }, label = L('place_hint_turn') },
        { keys = { 'SHIFT' }, label = L('place_hint_fine') },
        { keys = { 'BACKSPACE', 'RMB' }, label = L('place_hint_cancel') },
    }
end

local function camRay(ped, reach)
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cxr = math.abs(math.cos(rx))
    local len = reach + RAY_EXTRA
    return StartShapeTestLosProbe(cam.x, cam.y, cam.z,
        cam.x - math.sin(rz) * cxr * len, cam.y + math.cos(rz) * cxr * len, cam.z + math.sin(rx) * len,
        RAY_FLAGS, ped, 7)
end

local function placeLoop(jtype, def, gen)
    local ped = PlayerPedId()
    local ghost = NZR.Props.Spawn(def.model, GetEntityCoords(ped), {
        group = GHOST_GROUP, frozen = true, collision = false, alpha = GHOST_ALPHA, fallback = FALLBACK_MODEL,
    })
    if not ghost or ghost == 0 then
        toast('place_nomodel', 'error')
        return
    end
    SetEntityVisible(ghost, false, false)
    pcall(SetEntityDrawOutline, ghost, true)

    local overlayOpened = false
    if not NZR.UI.IsOpen('overlay') then
        NZR.UI.Open('overlay', { hints = {}, place = true }, { focus = false })
        overlayOpened = true
    end
    local code = J.ModelCode(jtype)
    local function card(valid, reason, heading)
        NZR.UI.Send('overlay', 'place', {
            title = L('place_title', code, def.label or jtype), code = code, label = def.label or jtype,
            type = jtype, hints = placeHints(), valid = valid == true,
            status = L(valid and 'place_ok' or ('place_' .. tostring(reason or 'aim'))), reason = reason,
            heading = math.floor(heading % 360.0 + 0.5) % 360,
        })
    end
    local function cleanup()
        if ghost then
            NZR.Props.Delete(ghost)
            ghost = nil
        end
        NZR.UI.Send('overlay', 'placeHide', {})
        if overlayOpened and not NZR.Radio.State.raised then NZR.UI.Close('overlay') end
        overlayOpened = false
    end

    local reach = tonumber(cfg().placeDistance) or 3.0
    local heading = (GetEntityHeading(ped) + 180.0) % 360.0
    local shape = nil
    local hit = nil              -- { x, y, z, nx, ny, nz, ent }
    local water, waterKey = false, nil
    local valid, reason = false, 'aim'
    local shownValid, shownReason, cardDeg = nil, nil, nil
    local lastX, lastY, lastZ, lastH = 0.0, 0.0, 0.0, -1.0

    while placing and placing.gen == gen do
        for i = 1, #PLACE_BLOCK do DisableControlAction(0, PLACE_BLOCK[i], true) end
        ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, true) or NZR.Radio.API.IsDead() or NZR.Radio.State.raised then break end
        if IsDisabledControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then break end

        -- last frame's ray, then the next one
        if shape then
            local status, didHit, endCoords, normal, ent = GetShapeTestResult(shape)
            if status ~= 1 then
                shape = nil
                if status == 2 then
                    if didHit == 1 or didHit == true then
                        hit = { x = endCoords.x, y = endCoords.y, z = endCoords.z, nx = normal.x, ny = normal.y, nz = normal.z, ent = ent }
                    else
                        hit = nil
                    end
                end
            end
        end
        if not shape then shape = camRay(ped, reach) end

        -- turning: wheel steps, arrows turn smoothly, Shift slows both
        local fine = IsControlPressed(0, 21) and FINE or 1.0
        if IsDisabledControlJustPressed(0, 241) then heading = heading + ROTATE_STEP * fine end
        if IsDisabledControlJustPressed(0, 242) then heading = heading - ROTATE_STEP * fine end
        local dt = GetFrameTime()
        if IsDisabledControlPressed(0, 174) then heading = heading + ROTATE_SPEED * fine * dt end
        if IsDisabledControlPressed(0, 175) then heading = heading - ROTATE_SPEED * fine * dt end
        heading = heading % 360.0

        local entType = 0
        if hit then
            local key = ('%.1f:%.1f:%.1f'):format(hit.x, hit.y, hit.z)
            if key ~= waterKey then
                waterKey = key
                water = waterAt(hit.x, hit.y, hit.z)
            end
            if hit.ent and hit.ent ~= 0 and DoesEntityExist(hit.ent) then entType = GetEntityType(hit.ent) or 0 end
        end
        valid, reason = J.CheckSpot({
            hit = hit ~= nil, coords = hit and vector3(hit.x, hit.y, hit.z) or nil,
            normal = hit and vector3(hit.nx, hit.ny, hit.nz) or nil, from = GetEntityCoords(ped), reach = reach,
            entityType = entType, onJammer = hit ~= nil and entIndex[hit.ent] ~= nil, water = water,
            inVehicle = false, swimming = IsPedSwimming(ped) == true,
        })

        if hit and ghost and (math.abs(hit.x - lastX) > 0.002 or math.abs(hit.y - lastY) > 0.002
            or math.abs(hit.z - lastZ) > 0.002 or heading ~= lastH) then
            lastX, lastY, lastZ, lastH = hit.x, hit.y, hit.z, heading
            SetEntityCoordsNoOffset(ghost, hit.x, hit.y, hit.z, false, false, false)
            SetEntityHeading(ghost, heading)
            if not IsEntityVisible(ghost) then SetEntityVisible(ghost, true, false) end
        end

        local shownDeg = math.floor(heading + 0.5) % 360
        if valid ~= shownValid or reason ~= shownReason or shownDeg ~= cardDeg then
            shownValid, shownReason, cardDeg = valid, reason, shownDeg
            if ghost then
                SetEntityAlpha(ghost, valid and GHOST_ALPHA or GHOST_ALPHA_BAD, false)
                if valid then
                    pcall(SetEntityDrawOutlineColor, 8, 175, 162, 200)
                else
                    pcall(SetEntityDrawOutlineColor, 229, 72, 77, 200)
                end
            end
            card(valid, reason, heading)
        end

        if IsDisabledControlJustPressed(0, 38) then
            if valid and hit then
                local x, y, z, h = hit.x, hit.y, hit.z, heading
                placing = nil
                cleanup()
                TaskTurnPedToFaceCoord(ped, x, y, z, 600)
                Wait(450)
                NZR.Anim.Play(ped, PLACE_ANIM.dict, PLACE_ANIM.clip, { flag = 0, duration = 1100, blendIn = 6.0, blendOut = -4.0 })
                Wait(700)
                TriggerServerEvent('nzr:jammer:place', jtype, vector3(x, y, z), math.floor(h * 10 + 0.5) / 10)
                sfx('place')
                return
            end
            sfx('error')
        end
        Wait(0)
    end
    cleanup()
end

function J.CancelPlace()
    if not placing then return false end
    placing = nil
    return true
end

function J.Place(jtype)
    if not enabled() then return false end
    local def = typeDef(jtype)
    if not def then return false end
    if J.IsBusy() then
        toast('place_busy', 'error')
        return false
    end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) then
        toast('place_vehicle', 'error')
        return false
    end
    if NZR.Radio.API.IsDead() then return false end
    if NZR.Radio.State.raised then NZR.Radio.API.Lower() end
    placeGen = placeGen + 1
    local gen = placeGen
    placing = { type = jtype, gen = gen }
    CreateThread(function()
        local ok, err = pcall(placeLoop, jtype, def, gen)
        if not ok then NZR.Warn('placing a jammer failed: ' .. tostring(err)) end
        if placing and placing.gen == gen then placing = nil end
        NZR.Props.Clear(GHOST_GROUP)
    end)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- EVENTS / STATE BAGS
-- ════════════════════════════════════════════════════════════════════════

local function setList(value)
    list = type(value) == 'table' and value or {}
    for id, j in pairs(list) do
        if type(j) == 'table' then known[id] = j.t end
    end
    jamCache = {}
    for id in pairs(spawned) do
        if not list[id] then despawn(id) end
    end
    if hacking and not hacking.done and hacking.token and not list[hacking.id] then finishHack(false, 'gone') end
    wakeScan()
    if next(list) == nil then sendNoise(0.0) end
end

AddStateBagChangeHandler('nzr_jammers', 'global', function(_, _, value)
    setList(value)
end)

RegisterNetEvent('nzr:jammer:begin', function(jtype)
    J.Place(jtype)
end)

RegisterNetEvent('nzr:jammer:hacked', function(id)
    local t = known[id] or (list[id] and list[id].t)
    local def = typeDef(t) or {}
    local name = def.label and ('%s %s'):format(J.ModelCode(t), def.label) or J.ModelCode(t)
    toast('hacked_owner', 'warning', name)
end)

CreateThread(function()
    Wait(0)
    NZR.UI.On('hack', 'result', function(data, cb)
        cb({ ok = true })
        if hacking and data and data.id == hacking.id then
            finishHack(data.success == true and data.cancelled ~= true, data.cancelled == true and 'cancelled' or nil)
        end
    end)
    NZR.UI.On('hack', 'close', function(_, cb)
        -- closed without a result (Esc): counts as giving up
        if hacking and hacking.opened and not hacking.done then
            hacking.opened = false
            finishHack(false, 'cancelled')
        end
        cb({ ok = true })
    end)
    setList(GlobalState.nzr_jammers)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    placing = nil
    if hacking and hacking.opened then NZR.UI.Close('hack') end
    hacking = nil
    for _, s in pairs(spawned) do
        if s.ent and s.ent ~= 0 then pcall(Bridge.Target.RemoveEntity, s.ent) end
    end
    spawned, entIndex = {}, {}
    if lastGain > 0 then NZR.UI.Send('_core', 'noise', { gain = 0.0 }) end
end)
