--[[
    NAYZEEE RADIO - Held radios (client): radios in hands for every player + the raised radio

    Every client draws a local (non-networked) radio for every player in range from their
    nzr_hold state bag: the complete model ('nzr_<m>', baked idle screen) in the right hand,
    shown while the radio is raised, or while talking when Config.Radios.Talk.showProp is on.
    Nothing is networked, so nothing is left behind when someone crashes.

    The local player's RAISED radio is different: the body model ('nzr_<m>_body', the one
    whose screen carries the live DUI) with every pressable part and the LED lenses as
    their own props attached to it, so keys really move when pressed and knobs turn.

      NZR.Held.Raise(model) → body entity | nil     build the raised assembly in the hand
      NZR.Held.Lower()                              remove it (the full radio comes back if shown)
      NZR.Held.Available(model) → bool              body + parts are streamed (else: no raised view)
      NZR.Held.Body() → entity | nil    NZR.Held.Part(id) → entity | nil    NZR.Held.Model() → model | nil
      NZR.Held.Press(partId, down, dir?)            key travel along its press axis (45 ms in, held,
                                                    70 ms out); the d-pad also tilts toward dir
                                                    ('up'|'down'|'left'|'right')
      NZR.Held.Turn(partId, steps)                  knob turns 360 / detents per step about its axis
      NZR.Held.Led(kind, mode)                      kind 'red'|'green'|'amber', mode true|false|'blink'
      NZR.Held.SyncLeds()                           red = TX, green = RX, amber blinking = emergency
      NZR.Held.Grip(model) → { pos, rot }           Config.Radios.Models[m].grip (or the /radiogrip value)

    COMMAND        Config.Commands.grip (/radiogrip x y z rx ry rz) - Config.Debug, or an admin
                   (the server answers nzr:admin:check; asked once, then remembered)
    CALLBACKS      nzr:admin:check () → { ok, admin } (C→S, lib.callback)
    STATE BAGS     reads nzr_hold on every player (change handler + a 5 s sweep)
    BUS HANDLED    'radio:changed' (LEDs, own prop, preloading the models you own)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Held = NZR.Held or {}
local H = NZR.Held

local BONE = 28422               -- PH_R_Hand
local FALLBACK = 'prop_cs_hand_radio'
local RANGE = 120.0
local GROUP_HELD = 'nzr_held'
local GROUP_RIG = 'nzr_rig'
local PRESS_IN_MS = 45
local PRESS_OUT_MS = 70
local TURN_MS = 60
local BLINK_MS = 400
local SWEEP_MS = 5000
local LED_MODELS = { red = 'nzr_led_red', green = 'nzr_led_green', amber = 'nzr_led_amber' }
local LED_PRIORITY = { red = 3, amber = 2, green = 1 }

local holders = {}               -- [serverId] = nzr_hold value
local props = {}                 -- [serverId] = { entity, sig }
local dirty = true
local warned = {}
local gripOverride = {}
local preloaded = {}
local rig = nil
local animRunning = false
local blinkRunning = false
local ledMode = { red = false, green = false, amber = false }
local myId = nil

local function me()
    if not myId then myId = GetPlayerServerId(PlayerId()) end
    return myId
end

local function L(key, ...) return NZR.L('client.' .. key, ...) end

local function modelExists(name)
    if type(name) ~= 'string' or name == '' then return false end
    local h = GetHashKey(name)
    return IsModelInCdimage(h) or IsModelValid(h)
end

local function warnOnce(name)
    if warned[name] then return end
    warned[name] = true
    NZR.Warn(('radio model "%s" is not streamed - is %s started before nayzeee-radio?'):format(
        name, tostring(Config.PropsResource or 'nayzeee-radio-props')))
end

function H.Grip(model)
    local o = gripOverride[model]
    if o then return o end
    local m = Config.Radios.Models[model]
    local g = m and m.grip or {}
    return { pos = g.pos or vec3(0.0, 0.0, 0.0), rot = g.rot or vec3(0.0, 0.0, 0.0) }
end

local function gripSig(g)
    return ('%.4f,%.4f,%.4f,%.2f,%.2f,%.2f'):format(g.pos.x, g.pos.y, g.pos.z, g.rot.x, g.rot.y, g.rot.z)
end

local function fullModel(m)
    local lay = PropsLayout and PropsLayout[m]
    local name = (lay and lay.full) or ('nzr_' .. m)
    if modelExists(name) then return name end
    warnOnce(name)
    return FALLBACK
end

function H.Available(model)
    local lay = PropsLayout and PropsLayout[model]
    if type(lay) ~= 'table' then return false end
    if not modelExists(lay.body) then
        warnOnce(lay.body or ('nzr_' .. tostring(model) .. '_body'))
        return false
    end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- EVERYONE'S RADIOS
-- ════════════════════════════════════════════════════════════════════════

local function remove(sid)
    local p = props[sid]
    if not p then return end
    NZR.Props.Delete(p.entity)
    props[sid] = nil
end

local function shouldShow(st, isMe)
    if type(st) ~= 'table' or type(st.m) ~= 'string' or not Config.Radios.Models[st.m] then return false end
    if isMe and rig then return false end
    return st.r == true or (st.t == true and Config.Radios.Talk.showProp == true)
end

local function refreshOne(sid, ped, st)
    if not shouldShow(st, sid == me()) then return remove(sid) end
    local model = fullModel(st.m)
    local g = H.Grip(st.m)
    local sig = ('%s|%d|%s'):format(model, ped, gripSig(g))
    local p = props[sid]
    if p and p.sig == sig and DoesEntityExist(p.entity) and IsEntityAttachedToEntity(p.entity, ped) then return end
    remove(sid)
    local ent = NZR.Props.Spawn(model, { attach = { entity = ped, bone = BONE, pos = g.pos, rot = g.rot } },
        { group = GROUP_HELD, collision = false, keepModel = true })
    if ent and ent ~= 0 then props[sid] = { entity = ent, sig = sig } end
end

local function pedOf(sid, myPed)
    if sid == me() then return myPed end
    local pl = GetPlayerFromServerId(sid)
    if not pl or pl == -1 then return 0 end
    return GetPlayerPed(pl)
end

local function tick()
    local myPed = PlayerPedId()
    local myPos = GetEntityCoords(myPed)
    local seen = {}
    for sid, st in pairs(holders) do
        local ped = pedOf(sid, myPed)
        if ped ~= 0 and DoesEntityExist(ped) and (ped == myPed or #(GetEntityCoords(ped) - myPos) < RANGE) then
            seen[sid] = true
            refreshOne(sid, ped, st)
        end
    end
    for sid in pairs(props) do
        if not seen[sid] then remove(sid) end
    end
end

-- players who came into scope with a bag already set do not always fire the handler
local function sweep()
    local found = {}
    for _, pl in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(pl)
        local ok, st = pcall(function() return Player(sid).state.nzr_hold end)
        if ok and type(st) == 'table' then
            found[sid] = true
            holders[sid] = st
        end
    end
    for sid in pairs(holders) do
        if not found[sid] then holders[sid] = nil end
    end
end

AddStateBagChangeHandler('nzr_hold', nil, function(bagName, _, value)
    local sid = tonumber(tostring(bagName):match('^player:(%d+)$'))
    if not sid then return end
    holders[sid] = type(value) == 'table' and value or nil
    dirty = true
end)

CreateThread(function()
    local nextSweep = 0
    while true do
        local now = GetGameTimer()
        if now >= nextSweep then
            sweep()
            nextSweep = now + SWEEP_MS
        end
        dirty = false
        if next(holders) ~= nil or next(props) ~= nil then tick() end
        -- once a second, or half a second after a bag changed (idle: two cheap wake-ups)
        local waited = 0
        while waited < 1000 and not dirty do
            Wait(500)
            waited = waited + 500
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- THE RAISED RADIO (local player only)
-- ════════════════════════════════════════════════════════════════════════

local function easeOut(t)
    return 1.0 - (1.0 - t) * (1.0 - t)
end

local function attachPart(p, x, y, z, rx, ry, rz)
    AttachEntityToEntity(p.ent, rig.body, 0, x, y, z, rx, ry, rz, false, false, false, false, 2, true)
end

-- → true while the part is still moving
local function placePart(p, now)
    local k = p.key
    local t = p.dur > 0 and math.min(1.0, (now - p.t0) / p.dur) or 1.0
    p.f = p.from + (p.to - p.from) * easeOut(t)
    local ta = math.min(1.0, (now - p.aT0) / TURN_MS)
    p.shown = p.aFrom + (p.angle - p.aFrom) * easeOut(ta)

    local press = k.press or vec3(0.0, -1.0, 0.0)
    local depth = (tonumber(k.depth) or 0.0012) * p.f
    local rx, ry, rz = 0.0, 0.0, 0.0
    if k.tilt and p.dir then
        -- a rocker pivots: half the travel, the rest is the tilt toward the pressed edge
        depth = depth * 0.5
        local a = (tonumber(k.tilt) or 5.0) * p.f
        if p.dir == 'up' then rx = a elseif p.dir == 'down' then rx = -a
        elseif p.dir == 'left' then rz = -a elseif p.dir == 'right' then rz = a end
    end
    if k.axis and p.shown ~= 0.0 then
        rx = rx + k.axis.x * p.shown
        ry = ry + k.axis.y * p.shown
        rz = rz + k.axis.z * p.shown
    end
    attachPart(p, k.pos.x + press.x * depth, k.pos.y + press.y * depth, k.pos.z + press.z * depth, rx, ry, rz)
    if t >= 1.0 and p.to == 0.0 then p.dir = nil end
    return t < 1.0 or ta < 1.0
end

local function animLoop()
    if animRunning then return end
    animRunning = true
    CreateThread(function()
        while rig do
            local now = GetGameTimer()
            local busy = false
            for _, p in pairs(rig.parts) do
                if p.moving then
                    p.moving = placePart(p, now)
                    if p.moving then busy = true end
                end
            end
            if not busy then break end
            Wait(0)
        end
        animRunning = false
    end)
end

function H.Press(partId, down, dir)
    local p = rig and rig.parts[partId]
    if not p then return false end
    p.from = p.f
    p.to = down and 1.0 or 0.0
    p.t0 = GetGameTimer()
    p.dur = down and PRESS_IN_MS or PRESS_OUT_MS
    if dir then p.dir = dir end
    p.moving = true
    animLoop()
    return true
end

function H.Turn(partId, steps)
    local p = rig and rig.parts[partId]
    if not p then return false end
    local detents = math.max(1, tonumber(p.key.detents) or 16)
    -- keep both angles small so the ease never spins the long way round
    local wrap = math.floor(p.shown / 360.0) * 360.0
    p.aFrom = p.shown - wrap
    p.angle = (p.angle - wrap) + (tonumber(steps) or 1) * 360.0 / detents
    p.aT0 = GetGameTimer()
    p.moving = true
    animLoop()
    return true
end

-- ── LEDs ──────────────────────────────────────────────────────────────

local function applyLeds()
    if not rig then return end
    local blinkOn = (GetGameTimer() // BLINK_MS) % 2 == 0
    local lit = {}
    for kind, mode in pairs(ledMode) do lit[kind] = mode == true or (mode == 'blink' and blinkOn) end
    -- lenses that share one light pipe: only the most important colour shows
    for kind, led in pairs(rig.leds) do
        if lit[kind] then
            for other, o in pairs(rig.leds) do
                if other ~= kind and lit[other] and #(o.pos - led.pos) < 0.002
                    and LED_PRIORITY[other] > LED_PRIORITY[kind] then
                    lit[kind] = false
                end
            end
        end
    end
    for kind, led in pairs(rig.leds) do
        if led.on ~= lit[kind] then
            led.on = lit[kind]
            SetEntityVisible(led.ent, led.on == true, false)
        end
    end
end

local function blinkLoop()
    if blinkRunning then return end
    blinkRunning = true
    CreateThread(function()
        while rig and (ledMode.red == 'blink' or ledMode.green == 'blink' or ledMode.amber == 'blink') do
            applyLeds()
            Wait(100)
        end
        blinkRunning = false
        applyLeds()
    end)
end

function H.Led(kind, mode)
    if ledMode[kind] == nil then return end
    if mode ~= 'blink' then mode = mode == true end
    if ledMode[kind] == mode then return end
    ledMode[kind] = mode
    applyLeds()
    if mode == 'blink' then blinkLoop() end
end

function H.SyncLeds()
    local S = NZR.Radio and NZR.Radio.State
    if not S then return end
    H.Led('red', S.tx and S.tx.active == true)
    H.Led('green', next(S.rx or {}) ~= nil)
    H.Led('amber', (S.emergencyUntil or 0) > GetGameTimer() and 'blink' or false)
end

-- ── assembly ──────────────────────────────────────────────────────────

local function spawnOnBody(model, pos, body)
    return NZR.Props.Spawn(model, { attach = { entity = body, bone = 0, pos = pos, rot = vec3(0.0, 0.0, 0.0) } },
        { group = GROUP_RIG, collision = false, keepModel = true })
end

function H.Raise(model)
    H.Lower()
    local lay = PropsLayout and PropsLayout[model]
    if type(lay) ~= 'table' or not H.Available(model) then return nil end
    local ped = PlayerPedId()
    local g = H.Grip(model)
    local body = NZR.Props.Spawn(lay.body, { attach = { entity = ped, bone = BONE, pos = g.pos, rot = g.rot } },
        { group = GROUP_RIG, collision = false, keepModel = true })
    if not body or body == 0 then return nil end
    rig = { model = model, layout = lay, body = body, ped = ped, parts = {}, leds = {} }
    for _, k in ipairs(lay.keys or {}) do
        if k.id and k.model and k.pos then
            if modelExists(k.model) then
                local ent = spawnOnBody(k.model, k.pos, body)
                if ent and ent ~= 0 then
                    rig.parts[k.id] = { ent = ent, key = k, f = 0.0, from = 0.0, to = 0.0, t0 = 0, dur = 0,
                        dir = nil, angle = 0.0, shown = 0.0, aFrom = 0.0, aT0 = 0, moving = false }
                end
            else
                warnOnce(k.model)
            end
        end
    end
    local leds = lay.leds or {}
    for kind, name in pairs(LED_MODELS) do
        local pos = (kind == 'red' and leds.tx) or (kind == 'green' and (leds.rx or leds.tx)) or (leds.amber or leds.tx)
        if pos and modelExists(name) then
            local ent = spawnOnBody(name, pos, body)
            if ent and ent ~= 0 then
                SetEntityVisible(ent, false, false)
                rig.leds[kind] = { ent = ent, pos = pos, on = false }
            end
        end
    end
    ledMode = { red = false, green = false, amber = false }
    H.SyncLeds()
    dirty = true
    return body
end

function H.Lower()
    if not rig then return end
    rig = nil
    NZR.Props.Clear(GROUP_RIG)
    dirty = true
end

function H.Body() return rig and rig.body or nil end
function H.Model() return rig and rig.model or nil end
function H.Part(id)
    local p = rig and rig.parts[id]
    return p and p.ent or nil
end

-- ════════════════════════════════════════════════════════════════════════
-- PRELOAD (every model of a radio you own, the first time you own it)
-- ════════════════════════════════════════════════════════════════════════

local function preload(model)
    if preloaded[model] then return end
    preloaded[model] = true
    local lay = PropsLayout and PropsLayout[model]
    if type(lay) ~= 'table' then return end
    CreateThread(function()
        local names = { lay.full, lay.body }
        for _, k in ipairs(lay.keys or {}) do names[#names + 1] = k.model end
        for _, n in pairs(LED_MODELS) do names[#names + 1] = n end
        for _, n in ipairs(names) do
            if modelExists(n) then
                NZR.Props.Load(n, 3000)
                Wait(0)
            end
        end
    end)
end

NZR.Bus.On('radio:changed', function(what)
    local S = NZR.Radio.State
    if what == 'raised' or what == 'tx' or what == 'model' or what == 'record' or what == 'reset' or what == 'dropped' then
        holders[me()] = LocalPlayer.state.nzr_hold
        dirty = true
    end
    if what == 'tx' or what == 'rx' or what == 'emergency' or what == 'power' or what == 'record' then H.SyncLeds() end
    if what == 'record' or what == 'init' or what == 'model' then
        for model in pairs(S.owned or {}) do
            if Config.Radios.Models[model] then preload(model) end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- /radiogrip (debug)
-- ════════════════════════════════════════════════════════════════════════

local function toast(key, kind, ...)
    NZR.UI.Toast({ title = L('title'), message = L(key, ...), type = kind or 'info' })
end

-- Debug on: anyone. Debug off: only players the server calls admins (SPEC §9.3).
local gripAdmin = nil
local function gripAllowed()
    if Config.Debug then return true end
    if gripAdmin == nil then
        local ok, res = pcall(lib.callback.await, 'nzr:admin:check', false)
        -- a refused (rate limited) or failed check is asked again next time
        if ok and type(res) == 'table' and res.ok ~= false then gripAdmin = res.admin == true end
    end
    return gripAdmin == true
end

local gripCmd = Config.Commands and Config.Commands.grip
if gripCmd then
    RegisterCommand(gripCmd, function(_, args) CreateThread(function()
        if not gripAllowed() then return toast('grip_debug', 'error') end
        local S = NZR.Radio.State
        local model = S.model
        if not model then return toast('no_radio', 'error') end
        local n = {}
        for i = 1, 6 do n[i] = tonumber(args and args[i]) end
        local g = H.Grip(model)
        if n[1] then
            for i = 1, 6 do
                if not n[i] then return toast('grip_usage', 'error', gripCmd) end
            end
            g = { pos = vec3(n[1], n[2], n[3]), rot = vec3(n[4], n[5], n[6]) }
            gripOverride[model] = g
            if rig and rig.model == model and DoesEntityExist(rig.body) then
                local ped = PlayerPedId()
                AttachEntityToEntity(rig.body, ped, GetPedBoneIndex(ped, BONE), g.pos.x, g.pos.y, g.pos.z,
                    g.rot.x, g.rot.y, g.rot.z, false, false, false, true, 2, true)
            end
            dirty = true
        end
        print(('^5[nayzeee-radio]^7 Config.Radios.Models.%s.grip = { pos = vec3(%.3f, %.3f, %.3f), rot = vec3(%.1f, %.1f, %.1f) },')
            :format(model, g.pos.x, g.pos.y, g.pos.z, g.rot.x, g.rot.y, g.rot.z))
        toast('grip_printed', 'success')
    end) end, false)
    CreateThread(function()
        Wait(1000)
        if Config.Debug then
            TriggerEvent('chat:addSuggestion', '/' .. gripCmd, L('cmd_grip'), {
                { name = 'x' }, { name = 'y' }, { name = 'z' }, { name = 'rx' }, { name = 'ry' }, { name = 'rz' },
            })
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    rig = nil
    NZR.Props.Clear(GROUP_RIG)
    NZR.Props.Clear(GROUP_HELD)
    props = {}
end)
