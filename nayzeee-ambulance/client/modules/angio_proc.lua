--[[
    NAYZEEE AMBULANCE - Angiography (client): the procedure runner

    NZA.Angio.Runner(ctx) is the minigame NZA.Proc.Run('angio') runs (client/modules/angio.lua
    starts it). It opens the NUI app 'angio' (html/apps/angio) and drives the world around it:

      * FLUOROSCOPY ON THE MONITOR - a DUI page (html/apps/angio/screen.html) is drawn into a
        runtime texture that replaces Config.PropScreens.angio_monitor on the boom monitor
        (AddReplaceTexture). The overlay streams its screen state ('angio:screen', ~20 Hz)
        and this file forwards it with SendDuiMessage. Without the custom monitor model, with
        Config.Angio.dui.enabled = false, or when the DUI cannot be created, the overlay draws
        the same image itself (open data dui = false).
      * CAMERAS (NZA.Cam) per step: overview of the patient (choose the access), close-up of
        the access site (steps 1 and 6, right-drag look around, wheel zoom), the monitor screen
        (steps 2-5), the injector for Config.Angio.injectorShot seconds after the red button.
      * ROOM MODE ({Z} in the overlay): the overlay loses focus, the medic walks; near the red
        button pedestal an [E] prompt presses it → contrast run → injector shot → back to the
        monitor. {Z} again returns to the monitor.
      * The power injector's plunger (optional prop) follows the contrast used, the needle prop
        sits in the access site while the needle is in, medic animations per step, patient
        speech subtitles, live vitals for the console.

    NUI callbacks (angio:*)
        step { phase, step, cam, access, view }     camera / animation / needle prop
        screen { state }                            → DUI
        run { kind, selective, blush, fromButton }  → server act 'run'|'puff' → { ok, left, delay }
        refill {}                                   → server act 'refill'  → { ok, left, bottles }
        coil { dist, onPath }                       → server act 'coil'    → { ok, left }
        room { on }   view { mode }   say { line }   finish { result }   abort {}   close
    NUI actions sent: open, close, vitals (vitals), room ({ on }), pressed, anchors
    Callbacks used: nza:angio:act (server/modules/angio.lua)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Angio = NZA.Angio or {}
local Angio = NZA.Angio
local U = NZA.Util

local APP = 'angio'
local RUN_GROUP = 'nza:angio:run'
local PROMPT = 'angio_btn'
local INJECT_SECONDS = 2.4       -- the overlay's injection time of a full run (app.js INJ.run)

local S = nil                    -- the running session

local PHASE_ANIM = {
    aim = 'work', wire = 'work', sheath = 'work', needle = 'work',
    nav = 'work', select = 'work', coil = 'work', confirm = 'work',
    pull = 'work', press = 'hold',
}

local function cfg() return Config.Angio or {} end
local function suiteCfg() return cfg().suite or {} end
local function L(key, ...) return NZA.L('angio.' .. key, ...) end

local function valid(ent)
    return ent ~= nil and ent ~= 0 and DoesEntityExist(ent)
end

local function piece(key)
    local suite = S and S.suite
    local ent = suite and suite.ents and suite.ents[key]
    return valid(ent) and ent or nil
end

-- ════════════════════════════════════════════════════════════════════════
-- DUI (the in-world fluoroscopy screen)
-- ════════════════════════════════════════════════════════════════════════

local Dui = { obj = nil, handle = nil, txd = nil, tex = nil, n = 0, replaced = nil, gen = 0 }
local TXD = 'nza_angio_screen'

local function screenLocale()
    local out = {}
    for k, v in pairs(NZA.LocaleTable('angio')) do
        if k:sub(1, 7) == 'screen.' then out[k] = v end
    end
    return out
end

local function duiSend(tbl)
    if Dui.obj then SendDuiMessage(Dui.obj, json.encode(tbl)) end
end

local function duiDestroy()
    if Dui.replaced then
        RemoveReplaceTexture(Dui.replaced.txd, Dui.replaced.tex)
        Dui.replaced = nil
    end
    if Dui.obj then
        DestroyDui(Dui.obj)
        Dui.obj, Dui.handle = nil, nil
    end
end

local function duiAcquire(suite)
    local dc = cfg().dui or {}
    if dc.enabled == false or not suite or not suite.screenOk then return false end
    local scr = Config.PropScreens and Config.PropScreens.angio_monitor
    if type(scr) ~= 'table' or not scr.txd or not scr.tex then return false end
    Dui.gen = Dui.gen + 1          -- cancels a pending linger shutdown
    if not Dui.obj then
        local url = ('nui://%s/html/apps/angio/screen.html'):format(GetCurrentResourceName())
        local ok, obj = pcall(CreateDui, url, math.floor(tonumber(dc.width) or 1280), math.floor(tonumber(dc.height) or 720))
        if not ok or not obj then return false end
        Dui.obj = obj
        Dui.handle = GetDuiHandle(obj)
        if not Dui.txd then Dui.txd = CreateRuntimeTxd(TXD) end
        Dui.n = Dui.n + 1
        Dui.tex = 'screen' .. Dui.n
        CreateRuntimeTextureFromDuiHandle(Dui.txd, Dui.tex, Dui.handle)
        local t = GetGameTimer()
        while not IsDuiAvailable(obj) and GetGameTimer() - t < 4000 do Wait(50) end
    end
    if not Dui.replaced then
        AddReplaceTexture(scr.txd, scr.tex, TXD, Dui.tex)
        Dui.replaced = { txd = scr.txd, tex = scr.tex }
    end
    duiSend({ type = 'locale', locale = screenLocale() })
    return true
end

-- standby screen for a while, then the model's own screen comes back and the browser closes
local function duiRelease()
    if not Dui.obj then return end
    duiSend({ type = 'standby' })
    local gen = Dui.gen
    local linger = math.max(0, tonumber((cfg().dui or {}).linger) or 30)
    SetTimeout(math.floor(linger * 1000), function()
        if Dui.gen == gen and not S then duiDestroy() end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- CAMERAS
-- ════════════════════════════════════════════════════════════════════════

local function camOverview()
    if not valid(S.patient) then return end
    local oc = suiteCfg().overviewCam or {}
    NZA.Cam.Orbit(S.patient, {
        dist = tonumber(oc.dist) or 2.7, pitch = tonumber(oc.pitch) or 34.0, fov = tonumber(oc.fov) or 50.0,
        height = tonumber(oc.height) or 0.15, minDist = 1.4, maxDist = 4.5, minPitch = 10.0, maxPitch = 80.0, ease = 700,
    })
end

local function camAccess()
    if not valid(S.patient) then return end
    local acc = (cfg().access or {})[S.access or 'femoral_r'] or {}
    local ac = cfg().accessCam or {}
    NZA.Cam.Close(S.patient, tonumber(acc.bone) or 51826, {
        offset = acc.offset, dist = tonumber(ac.dist) or 0.6, pitch = tonumber(ac.pitch) or 52.0, fov = tonumber(ac.fov) or 38.0,
        orbit = true, zoom = true, minDist = 0.3, maxDist = 1.4, minPitch = 15.0, maxPitch = 85.0, ease = 700,
    })
end

local function camMonitor()
    local mon = piece('monitor')
    if not mon then return camOverview() end
    local scr = suiteCfg().screen or {}
    local pos = U.vec(scr.pos) or vector3(0.0, 0.06, 1.62)
    local focus = vector3(pos.x, pos.y, pos.z - (tonumber(scr.drop) or 0.0))
    local fwd = GetEntityForwardVector(mon)
    NZA.Cam.Close(mon, focus, {
        dist = tonumber(scr.dist) or 1.15, yaw = math.deg(math.atan(fwd.y, fwd.x)), pitch = tonumber(scr.pitch) or 2.0,
        fov = tonumber(scr.fov) or 44.0, orbit = false, pan = false, zoom = false, minDist = 0.3, maxDist = 3.0, ease = 700,
    })
end

local function camInjector()
    local inj = piece('injector')
    if not inj then return false end
    local ic = suiteCfg().injectorCam or {}
    local look = U.vec(ic.look) or vector3(0.0, 0.0, 1.0)
    local pos = U.vec(ic.pos) or vector3(-0.55, -0.55, 1.45)
    local wl = GetOffsetFromEntityInWorldCoords(inj, look.x, look.y, look.z)
    local wp = GetOffsetFromEntityInWorldCoords(inj, pos.x, pos.y, pos.z)
    local d = wp - wl
    local dist = math.max(0.3, #d)
    NZA.Cam.Close(inj, look, {
        dist = dist, yaw = math.deg(math.atan(d.y, d.x)), pitch = math.deg(math.asin(U.clamp(d.z / dist, -1.0, 1.0))),
        fov = tonumber(ic.fov) or 40.0, orbit = false, pan = false, zoom = false, minDist = 0.2, maxDist = 3.0, ease = 450,
    })
    return true
end

-- kind = 'overview' | 'access' | 'monitor'; remembered while walking around / during the injector shot
local function setCam(kind, force)
    local s = S
    if not s then return end
    s.cam = kind or s.cam or 'overview'
    if s.room or s.shot then return end
    if not force and s.camLive == s.cam and (s.cam ~= 'access' or s.camAccess == s.access) then return end
    s.camLive, s.camAccess = s.cam, s.access
    if s.cam == 'access' then camAccess()
    elseif s.cam == 'monitor' then camMonitor()
    else camOverview() end
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDIC: position & animations
-- ════════════════════════════════════════════════════════════════════════

local function playAnim(key)
    local s = S
    if not s then return end
    s.animWant = key
    if s.room or s.walking then return end
    if s.animKey == key then return end
    local ped = PlayerPedId()
    if s.animToken then
        NZA.Anim.Stop(ped, { token = s.animToken })
        s.animToken = nil
    end
    s.animKey = key
    if not key then return end
    local a = (cfg().anims or {})[key]
    if type(a) ~= 'table' or not a.dict then return end
    local ok, token = NZA.Anim.Play(ped, a.dict, a.clip, { flag = a.flag or 1 })
    if ok then s.animToken = token end
end

-- walk to the operator spot beside the table and face the patient (blocking, ≤ 5 s)
local function goToOperator()
    local s = S
    if not s then return end
    local ped = PlayerPedId()
    if not s.suite then
        if valid(s.patient) then TaskTurnPedToFaceEntity(ped, s.patient, 800) end
        return
    end
    local op = U.vec(suiteCfg().operator) or vector3(0.75, -0.3, 0.0)
    local spot = Angio.ToWorld(s.suite, op)
    local across = Angio.ToWorld(s.suite, vector3(0.0, op.y, 0.0))
    local heading = GetHeadingFromVector_2d(across.x - spot.x, across.y - spot.y)
    local me = GetEntityCoords(ped)
    if #(vector2(me.x, me.y) - vector2(spot.x, spot.y)) > 0.35 then
        s.walking = true
        if s.animToken then NZA.Anim.Stop(ped, { token = s.animToken }) s.animToken, s.animKey = nil, nil end
        TaskGoStraightToCoord(ped, spot.x, spot.y, me.z, 1.0, 5000, heading, 0.15)
        local t = GetGameTimer()
        while S == s and GetGameTimer() - t < 5000 do
            local p = GetEntityCoords(ped)
            if #(vector2(p.x, p.y) - vector2(spot.x, spot.y)) <= 0.4 then break end
            Wait(100)
        end
        if S ~= s then return end
        s.walking = false
    end
    SetEntityHeading(ped, heading)
    if not s.room then
        local want = s.animWant
        s.animKey = nil
        playAnim(want)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- PROPS: needle, injector plunger
-- ════════════════════════════════════════════════════════════════════════

local function needleIn()
    local s = S
    if not s or s.needle or not cfg().needleProp or not valid(s.patient) then return end
    local acc = (cfg().access or {})[s.access or 'femoral_r'] or {}
    local n = type(acc.needle) == 'table' and acc.needle or {}
    local ent = NZA.Props.Spawn(cfg().needleProp, {
        attach = { entity = s.patient, bone = tonumber(acc.bone) or 51826, pos = n.pos or acc.offset or vector3(0.0, 0.0, 0.0), rot = n.rot or vector3(0.0, 45.0, 0.0) },
    }, { group = RUN_GROUP, collision = false, fallbackKey = cfg().needleProp })
    if S ~= s then
        if ent ~= 0 then NZA.Props.Delete(ent) end
        return
    end
    if ent ~= 0 then s.needle = ent end
end

local function needleOut()
    if S and S.needle then
        NZA.Props.Delete(S.needle)
        S.needle = nil
    end
end

-- plunger position = share of the current bottle that is used (0 = full syringe)
local function plungerTo(frac, seconds)
    local s = S
    local suite = s and s.suite
    local pl = suite and suite.ents and suite.ents.plunger
    if not valid(pl) or not suite.plungerRest or not suite.plungerAxis then return end
    local travel = tonumber((suiteCfg().plunger or {}).travel) or 0.12
    local from = s.plungerFrac or 0.0
    s.plungerFrac = frac
    local token = {}
    s.plungerToken = token
    CreateThread(function()
        local t0 = GetGameTimer()
        local dur = math.max(1, math.floor((seconds or 1.0) * 1000))
        while DoesEntityExist(pl) do
            if s.plungerToken ~= token then return end
            local k = math.min(1.0, (GetGameTimer() - t0) / dur)
            local f = from + (frac - from) * k
            local p = suite.plungerRest + suite.plungerAxis * (travel * f)
            SetEntityCoordsNoOffset(pl, p.x, p.y, p.z, false, false, false)
            if k >= 1.0 then return end
            Wait(0)
        end
    end)
end

local function plungerReset(suite)
    local pl = suite and suite.ents and suite.ents.plunger
    if valid(pl) and suite.plungerRest then
        local p = suite.plungerRest
        SetEntityCoordsNoOffset(pl, p.x, p.y, p.z, false, false, false)
    end
end

local function usedFrac(left)
    local per = tonumber(cfg().contrastPerItem) or 100
    return U.clamp(1.0 - (tonumber(left) or per) / per, 0.0, 1.0)
end

-- ════════════════════════════════════════════════════════════════════════
-- ROOM MODE (walk to the red button)
-- ════════════════════════════════════════════════════════════════════════

local function hidePrompt()
    if S and S.promptOn then
        NZA.UI.HidePrompt(PROMPT)
        S.promptOn = false
    end
end

local function setRoom(on, notify)
    local s = S
    if not s or s.room == on then return end
    s.room = on
    local ped = PlayerPedId()
    if on then
        NZA.UI.SetFocus(APP, { focus = false })
        s.camLive = nil
        NZA.Cam.Stop(450)
        if s.animToken then NZA.Anim.Stop(ped, { token = s.animToken }) end
        s.animToken, s.animKey = nil, nil
        ClearPedTasks(ped)
    else
        hidePrompt()
        NZA.UI.SetFocus(APP, { focus = true, cursor = true })
        setCam(s.cam or 'monitor', true)
        CreateThread(goToOperator)
    end
    if notify then NZA.UI.Send(APP, 'room', { on = on }) end
end

local function pressButton()
    local s = S
    local btn = piece('button')
    if not s or s.pressing or not btn then return end
    s.pressing = true
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, btn, 500)
    Wait(450)
    local a = (cfg().anims or {}).press
    if type(a) == 'table' and a.dict then NZA.Anim.Play(ped, a.dict, a.clip, { flag = a.flag or 48, duration = 1200 }) end
    Wait(350)
    if S ~= s then return end
    PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
    NZA.UI.Send(APP, 'pressed', {})
    Wait(900)
    s.pressing = false
end

local function roomTick()
    local s = S
    local c = cfg()
    local keys = c.keys or {}
    local pressKey, backKey = tonumber(keys.press) or 38, tonumber(keys.roomBack) or 20
    DisableControlAction(0, pressKey, true)
    DisableControlAction(0, backKey, true)
    local btn = piece('button')
    local near = false
    if btn then
        near = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(btn)) <= (tonumber(c.buttonDistance) or 1.3)
    end
    if near and not s.shot then
        if not s.promptOn then
            NZA.UI.Prompt(PROMPT, { key = keys.pressLabel or 'E', label = L('prompt_button'), sub = L('prompt_button_sub'), tone = 'red' })
            s.promptOn = true
        end
        if IsDisabledControlJustPressed(0, pressKey) and not s.pressing then CreateThread(pressButton) end
    else
        hidePrompt()
    end
    if IsDisabledControlJustPressed(0, backKey) and not s.shot and not s.pressing then setRoom(false, true) end
end

-- ════════════════════════════════════════════════════════════════════════
-- CONTRAST RUN IN THE WORLD
-- ════════════════════════════════════════════════════════════════════════

-- plunger follows the dye; after the red button the camera shows the injector for
-- `delay` seconds, then goes back to the monitor (the overlay starts the fill after it)
local function fire(kind, delay, left, fromButton)
    local s = S
    if not s then return end
    plungerTo(usedFrac(left), (kind == 'puff' and 0.8 or INJECT_SECONDS) + delay)
    if delay <= 0 then
        -- no injector shot: straight back to the monitor to watch the run
        if fromButton and s.room then setRoom(false, true) end
        return
    end
    CreateThread(function()
        s.shot = true
        hidePrompt()
        if not camInjector() then
            s.shot = false
            return
        end
        s.camLive = 'injector'
        Wait(math.floor(delay * 1000))
        if S ~= s then return end
        s.shot = false
        if s.room then setRoom(false, true) else setCam(s.cam or 'monitor', true) end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- SESSION
-- ════════════════════════════════════════════════════════════════════════

local function cleanup(s)
    if S ~= s then return end
    S = nil
    if s.stopWatch then pcall(s.stopWatch) end
    NZA.UI.HidePrompt(PROMPT)
    NZA.Anchors.Clear(APP)
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if NZA.Cam.Active() then NZA.Cam.Stop(600) end
    local ped = PlayerPedId()
    if s.animToken then NZA.Anim.Stop(ped, { token = s.animToken }) end
    if s.walking or s.room then ClearPedTasks(ped) end
    NZA.Props.Clear(RUN_GROUP)
    s.plungerToken = nil
    plungerReset(s.suite)
    duiRelease()
end

function Angio.Runner(ctx)
    local c = cfg()
    local data = ctx.data or {}
    local patient = ctx.entity
    local suite = Angio.Suite(data.point)
    if not suite and valid(patient) then suite = Angio.SuiteNear(GetEntityCoords(patient), (tonumber(c.tableRange) or 1.8) + 1.0) end
    if not suite then suite = Angio.SuiteNear(GetEntityCoords(PlayerPedId()), 4.0) end

    local s = {
        ctx = ctx, suite = suite, patient = patient, room = false, cam = 'overview', phase = 'choose',
        avpu = type(data.patient) == 'table' and data.patient.avpu or 'A', name = type(data.patient) == 'table' and data.patient.name or '',
    }
    if S then cleanup(S) end
    S = s
    ctx.onEnd(function() cleanup(s) end)
    if ctx.done() then
        cleanup(s)
        return
    end

    s.dui = duiAcquire(suite)
    if S ~= s then return end

    local btn, inj = piece('button'), piece('injector')
    NZA.UI.Open(APP, {
        data = data, locale = NZA.LocaleTable('angio'), dui = s.dui == true, hasButton = btn ~= nil,
    }, { focus = true, cursor = true })

    local anchors = {}
    if btn then anchors.button = { entity = btn, offset = suite.layout.button and suite.layout.button.anchor or vector3(0.0, 0.0, 1.2) } end
    if inj then anchors.injector = { entity = inj, offset = suite.layout.injector and suite.layout.injector.anchor or vector3(0.0, 0.0, 1.1) } end
    if next(anchors) then NZA.Anchors.Track(APP, anchors) end

    s.stopWatch = NZA.Patient.Watch(ctx.target, function(snap)
        if S ~= s or type(snap) ~= 'table' or type(snap.vitals) ~= 'table' then return end
        s.avpu = snap.vitals.avpu or s.avpu
        NZA.UI.Send(APP, 'vitals', snap.vitals)
    end, { keep = true })

    setCam('overview', true)
    CreateThread(goToOperator)

    while S == s and not ctx.done() do
        if s.room then
            roomTick()
            Wait(0)
        else
            Wait(150)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local ACCESS_KEYS = { femoral_r = true, femoral_l = true, radial = true }

NZA.UI.On(APP, 'step', function(data, cb)
    cb({ ok = true })
    local s = S
    if not s then return end
    if type(data.access) == 'string' and ACCESS_KEYS[data.access] then s.access = data.access end
    local phase = type(data.phase) == 'string' and data.phase or s.phase
    if phase == 'needleOut' then
        needleOut()
        return
    end
    s.phase = phase
    if phase == 'aim' then CreateThread(needleIn)
    elseif phase == 'nav' or phase == 'pull' or phase == 'done' then needleOut() end
    if data.cam == 'overview' or data.cam == 'access' or data.cam == 'monitor' then setCam(data.cam) end
    playAnim(PHASE_ANIM[phase])
end)

NZA.UI.On(APP, 'screen', function(data, cb)
    cb({ ok = true })
    if S and S.dui and Dui.obj and type(data.state) == 'table' then
        duiSend({ type = 'state', state = data.state })
    end
end)

local function act(name, info)
    local ok, res = pcall(lib.callback.await, 'nza:angio:act', false, name, info)
    if not ok or type(res) ~= 'table' then return { ok = false, err = 'error', msg = L('err.error') } end
    return res
end

NZA.UI.On(APP, 'run', function(data, cb)
    local s = S
    if not s then return cb({ ok = false, err = 'session' }) end
    local kind = data.kind == 'puff' and 'puff' or 'run'
    local res = act(kind, { kind = kind, selective = data.selective == true, blush = data.blush == true })
    if res.ok then
        local c = cfg()
        local delay = 0
        local shot = tonumber(c.injectorShot) or 0
        if kind == 'run' and shot > 0 and piece('injector') and (data.fromButton == true or c.injectorShotOnKey == true) then
            delay = U.clamp(shot, 0.0, 4.0)
        end
        res.delay = delay
        fire(kind, delay, res.left, data.fromButton == true)
    end
    cb(res)
end)

NZA.UI.On(APP, 'refill', function(_, cb)
    if not S then return cb({ ok = false, err = 'session' }) end
    local res = act('refill', {})
    if res.ok then plungerTo(usedFrac(res.left), 1.2) end
    cb(res)
end)

NZA.UI.On(APP, 'coil', function(data, cb)
    if not S then return cb({ ok = false, err = 'session' }) end
    cb(act('coil', { dist = tonumber(data.dist) or 99, onPath = data.onPath == true }))
end)

NZA.UI.On(APP, 'room', function(data, cb)
    cb({ ok = true })
    if S then setRoom(data.on == true, false) end
end)

NZA.UI.On(APP, 'view', function(data, cb)
    cb({ ok = true })
    if S then S.view = data.mode == 'screen' and 'screen' or 'monitor' end
end)

NZA.UI.On(APP, 'say', function(data, cb)
    cb({ ok = true })
    local s = S
    if not s or cfg().speech == false then return end
    local line = type(data.line) == 'string' and data.line or ''
    if not line:match('^[%a_]+$') then return end
    if s.avpu ~= 'A' and s.avpu ~= 'V' then return end
    local now = GetGameTimer()
    if now - (s.saidAt or 0) < 3500 then return end
    local key = 'angio.say.' .. line
    local text = NZA.L(key)
    if text == key then return end
    s.saidAt = now
    NZA.UI.Speech(s.name or '', text, 3600)
end)

-- only the fields the server reads; it clamps and checks them against its own log
local function cleanResult(r)
    r = type(r) == 'table' and r or {}
    local num = function(v) v = tonumber(v) return v and v == v and v or nil end
    local parts = {}
    if type(r.parts) == 'table' then
        for _, k in ipairs({ 'access', 'nav', 'contrast', 'dose', 'coil', 'haemostasis' }) do parts[k] = num(r.parts[k]) end
    end
    return {
        score = num(r.score) or 0, success = r.success == true,
        access = ACCESS_KEYS[r.access] and r.access or nil,
        coils = num(r.coils), runs = num(r.runs), contrast = num(r.contrast), fluoro = num(r.fluoro),
        dose = num(r.dose), bestDist = num(r.bestDist), parts = parts,
    }
end

NZA.UI.On(APP, 'finish', function(data, cb)
    cb({ ok = true })
    local s = S
    if not s or s.finishing then return end
    s.finishing = true
    local result = cleanResult(data.result)
    CreateThread(function()
        s.ctx.finish(result)
    end)
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    if S and not S.ctx.done() then S.ctx.abort('cancel') end
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    if S and not S.ctx.done() and not S.finishing then S.ctx.abort('cancel') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if S then cleanup(S) end
    duiDestroy()
end)
