--[[
    NAYZEEE AMBULANCE - Blood donation (client)

    Point type 'donation' (NZA.Points.RegisterType): Config.Props.donation_chair. Every client dresses a
    streamed chair with the collection mixer (Config.Props.blood_mixer), a blood bag lying on its tray
    that visibly fills (Config.Props.bloodbag_0/25/50/75/100 swapped from GlobalState.nzaBloodChairs)
    and a decorative IV stand. The mixer LCD shows the live mL counter (DUI html/apps/donation/lcd.html
    replacing the model's nz_amb_screen texture while you are near an active chair).
        target 'Donate blood'   (anyone, chair free)  → eligibility → sit (reclined pose)
        target 'Draw blood'     (Config.Blood.Donation.perm, a donor is seated) → NZA.Proc 'donation'
    Seated donor: [E] donate yourself (mode 'self' / 'both'), key mapping 'nza_blood_standup'
    (Config.Blood.Donation.standKey) to stand up. When a medic draws, the donor sees the collection
    card ('donation' app mode 'watch', no focus).

    Minigame (NUI app 'donation' mode 'donate', ProcPanel):
        1 Inflate the cuff (hold Space into the band)  2 Pump with the pulse (Space as each peak crosses the window) until the bag is full
        3 Clamp the line [C] + remove the needle (hold [E]) → label printed
    NUI callbacks: donation:progress { ml }, donation:finish { score, ml }, donation:abort, donation:close
    Net events: C→S nza:blood:donation:leave / :progress   S→C nza:blood:donation:stood
    Callbacks used: nza:blood:donation:check, nza:blood:donation:sit (+ core proc)
    Lua API (runtime): NZA.Blood.Sit(point, entity), NZA.Blood.Draw(point), NZA.Blood.StandUp(),
                       NZA.Blood.Busy() → bool, NZA.Blood.Seated() → point | nil
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Blood = NZA.Blood or {}
local B = NZA.Blood
local U = NZA.Util

local APP = 'donation'

local function dcfg() return (Config.Blood or {}).Donation or {} end
local function L(key, ...) return NZA.L('blood.' .. key, ...) end
local function toast(msg, kind, title)
    if not msg or msg == '' then return end
    NZA.UI.Toast({ title = title or L('don_title'), message = msg, type = kind or 'info' })
end

local dressed = {}   -- [pointId] = { point, chair, group, mixer, bag, bagKey, localMl, ready }
local seated = nil   -- { point, chair, mode, watch }
local run = nil      -- runner session

local function mySid() return GetPlayerServerId(PlayerId()) end
local function chairs() return GlobalState.nzaBloodChairs or {} end
local function chairState(id) return chairs()[tostring(id)] end

local function modeAllows(isSelf)
    local mode = dcfg().mode or 'both'
    if isSelf then return mode == 'self' or mode == 'both' end
    return mode == 'medic' or mode == 'both'
end

function B.Busy() return run ~= nil or seated ~= nil end
function B.Seated() return seated and seated.point or nil end

-- ════════════════════════════════════════════════════════════════════════
-- GEOMETRY
-- ════════════════════════════════════════════════════════════════════════

local function baseOf(point, chair)
    if chair and chair ~= 0 and DoesEntityExist(chair) then
        local c = GetEntityCoords(chair)
        return c, GetEntityHeading(chair)
    end
    local c = point.coords
    return vector3(c.x, c.y, c.z), (c.w or 0.0)
end

local function worldOf(point, chair, off)
    off = U.vec(off) or vector3(0.0, 0.0, 0.0)
    if chair and chair ~= 0 and DoesEntityExist(chair) then
        return GetOffsetFromEntityInWorldCoords(chair, off.x, off.y, off.z)
    end
    local base, h = baseOf(point, chair)
    local r = math.rad(h)
    local cs, sn = math.cos(r), math.sin(r)
    return vector3(base.x + off.x * cs - off.y * sn, base.y + off.x * sn + off.y * cs, base.z + off.z)
end

local function bagKeyFor(pct)
    if pct >= 88 then return 'bloodbag_100' end
    if pct >= 63 then return 'bloodbag_75' end
    if pct >= 38 then return 'bloodbag_50' end
    if pct >= 13 then return 'bloodbag_25' end
    return 'bloodbag_0'
end

-- ════════════════════════════════════════════════════════════════════════
-- DRESSING THE CHAIR (mixer, bag, stand) - every client
-- ════════════════════════════════════════════════════════════════════════

local function placeBag(d, key)
    if not d.mixer or d.mixer == 0 or not DoesEntityExist(d.mixer) then return end
    if d.bagKey == key and d.bag and DoesEntityExist(d.bag) then return end
    d.bagKey = key
    local old = d.bag
    local bm = dcfg().bagOnMixer or {}
    local ent = NZA.Props.Spawn(Config.Props[key] or key, {
        attach = { entity = d.mixer, pos = bm.pos or vec3(-0.15, 0.0, 0.326), rot = bm.rot or vec3(90.0, 0.0, -90.0) },
    }, { group = d.group, fallbackKey = key })
    d.bag = ent ~= 0 and ent or nil
    if old and old ~= d.bag then NZA.Props.Delete(old) end
end

local function dress(point, chair)
    if dressed[point.id] then return end
    local d = { point = point, chair = chair, group = 'blood_chair_' .. tostring(point.id), pct = 0 }
    dressed[point.id] = d
    CreateThread(function()
        local c = dcfg()
        local _, h = baseOf(point, chair)
        local m = c.mixer or {}
        local mp = worldOf(point, chair, m.pos or vec3(0.62, 0.15, 0.0))
        if dressed[point.id] ~= d then return end
        local mixer = NZA.Props.Spawn(Config.Props.blood_mixer, vector4(mp.x, mp.y, mp.z, h + (tonumber(m.heading) or 0.0)),
            { group = d.group, fallbackKey = 'blood_mixer' })
        d.mixer = mixer ~= 0 and mixer or nil
        if c.stand then
            local sp = worldOf(point, chair, c.stand.pos or vec3(-0.55, 0.0, 0.0))
            local stand = NZA.Props.Spawn(Config.Props.ivstand, vector4(sp.x, sp.y, sp.z, h + (tonumber(c.stand.heading) or 0.0)),
                { group = d.group, fallbackKey = 'ivstand' })
            if stand ~= 0 and c.stand.bag ~= false then
                NZA.Props.Spawn(Config.Props.ivbag_saline, { attach = { entity = stand, pos = vec3(0.073, 0.0, 1.766), rot = vec3(0.0, 0.0, 0.0) } },
                    { group = d.group, fallbackKey = 'ivbag_saline' })
            end
        end
        if dressed[point.id] ~= d then
            NZA.Props.Clear(d.group)
            return
        end
        d.ready = true
        placeBag(d, 'bloodbag_0')
    end)
end

local function undress(id)
    local d = dressed[id]
    if not d then return end
    dressed[id] = nil
    NZA.Props.Clear(d.group)
end

-- ════════════════════════════════════════════════════════════════════════
-- MIXER LCD (DUI)
-- ════════════════════════════════════════════════════════════════════════

local lcd = { dui = nil, rtxd = nil, n = 0, last = '', lastAt = 0 }

local function lcdTarget()
    local s = Config.PropScreens and Config.PropScreens.blood_mixer
    return (s and s.txd) or 'nz_amb_blood_mixer', (s and s.tex) or 'nz_amb_screen'
end

local function lcdOn()
    if lcd.dui then return true end
    local c = dcfg().lcd or {}
    if c.enabled == false then return false end
    lcd.dui = CreateDui(('nui://%s/html/apps/donation/lcd.html'):format(GetCurrentResourceName()),
        math.floor(tonumber(c.width) or 256), math.floor(tonumber(c.height) or 128))
    if not lcd.dui then return false end
    lcd.n = lcd.n + 1
    if not lcd.rtxd then lcd.rtxd = CreateRuntimeTxd('nza_blood_lcd') end
    local texName = 'lcd' .. lcd.n
    CreateRuntimeTextureFromDuiHandle(lcd.rtxd, texName, GetDuiHandle(lcd.dui))
    local txd, tex = lcdTarget()
    AddReplaceTexture(txd, tex, 'nza_blood_lcd', texName)
    lcd.last, lcd.lastAt = '', 0
    return true
end

local function lcdOff()
    if not lcd.dui then return end
    local txd, tex = lcdTarget()
    RemoveReplaceTexture(txd, tex)
    DestroyDui(lcd.dui)
    lcd.dui = nil
end

local function lcdSend(data)
    if not lcd.dui then return end
    local s = json.encode(data)
    local now = GetGameTimer()
    if s == lcd.last and now - lcd.lastAt < 2000 then return end
    lcd.last, lcd.lastAt = s, now
    SendDuiMessage(lcd.dui, s)
end

-- ════════════════════════════════════════════════════════════════════════
-- CHAIR LOOP (bag fill + LCD) - only while a chair is streamed
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        if not next(dressed) then
            lcdOff()
            Wait(1500)
        else
            Wait(300)
            local st = chairs()
            local me = GetEntityCoords(PlayerPedId())
            local nearest, nd = nil, math.huge
            for id, d in pairs(dressed) do
                local e = st[tostring(id)]
                local size = (e and tonumber(e.s)) or tonumber((Config.Blood.Bags or {}).bagSize) or 500
                local ml = d.localMl or (e and tonumber(e.ml)) or 0
                if e and e.done then ml = math.max(ml, tonumber(e.t) or 450) end
                if not e then ml = 0 end
                local pct = ml / math.max(1, size) * 100
                if d.ready then
                    local key = bagKeyFor(pct)
                    if key ~= d.bagKey then
                        CreateThread(function() placeBag(d, key) end)
                    end
                end
                local base = baseOf(d.point, d.chair)
                local dist = #(me - base)
                if dist < nd then nearest, nd = { d = d, e = e, ml = ml }, dist end
            end
            local range = tonumber((dcfg().lcd or {}).range) or 12.0
            if nearest and nd <= range and lcdOn() then
                local e = nearest.e
                lcdSend({
                    state = (not e and 'idle') or (e.done and 'done') or (e.a and 'run') or 'ready',
                    ml = math.floor(nearest.ml), target = e and e.t or 450, size = e and e.s or 500, type = e and e.bt or nil,
                    label = L('lcd_label'),
                })
            elseif lcd.dui and nd > range + 4.0 then
                lcdOff()
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SITTING
-- ════════════════════════════════════════════════════════════════════════

local function playSit(ped, s)
    local sit = dcfg().sit or {}
    if not sit.dict then return end
    if not IsEntityPlayingAnim(ped, sit.dict, sit.clip, 3) then
        NZA.Anim.Play(ped, sit.dict, sit.clip, { flag = 1, blendIn = 4.0 })
    end
end

local function seatPed(s)
    local ped = PlayerPedId()
    local sit = dcfg().sit or {}
    local pos = worldOf(s.point, s.chair, sit.offset or vec3(0.0, -0.12, 0.58))
    local _, h = baseOf(s.point, s.chair)
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ped, h + (tonumber(sit.heading) or 0.0))
    FreezeEntityPosition(ped, true)
    playSit(ped, s)
end

local function closeWatch(s)
    if s and s.watch then
        s.watch = nil
        if NZA.UI.IsOpen(APP) and not run then NZA.UI.Close(APP) end
    end
end

function B.StandUp(notify, stay)
    local s = seated
    if not s then return end
    if run and run.isSelf and run.ctx and not run.ended then
        run.abortReq = true
    end
    seated = nil
    NZA.UI.HidePrompt('blood_seat_go')
    NZA.UI.HidePrompt('blood_seat_up')
    closeWatch(s)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if not stay then
        NZA.Anim.Stop(ped, { immediate = true })
        local out = worldOf(s.point, s.chair, vec3(0.9, 0.25, 0.0))
        local base = baseOf(s.point, s.chair)
        SetEntityCoords(ped, out.x, out.y, base.z, false, false, false, false)
    end
    if notify ~= false then TriggerServerEvent('nza:blood:donation:leave', s.point.id) end
end

local function seatLoop(s)
    local sid = mySid()
    local lastCheck, lastAnim = 0, 0
    while seated == s do
        Wait(0)
        local ped = PlayerPedId()
        -- no walking, fighting or weapons while the needle is in
        DisableControlAction(0, 21, true) DisableControlAction(0, 22, true) DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true) DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
        DisableControlAction(0, 37, true) DisableControlAction(0, 44, true) DisableControlAction(0, 140, true)
        local now = GetGameTimer()
        if now - lastCheck > 250 then
            lastCheck = now
            local e = chairState(s.point.id)
            if not e or e.d ~= sid then
                -- give the replicated chair state a moment after sitting down
                if now - (s.since or now) > 4000 then
                    B.StandUp(false)
                    break
                end
                e = { d = sid }
            end
            local medicDrawing = e.a and e.m ~= sid
            if medicDrawing then
                NZA.UI.HidePrompt('blood_seat_go')
                NZA.UI.Prompt('blood_seat_up', { key = dcfg().standKey or 'X', label = L('prompt_stand'), sub = L('prompt_medic_drawing'), tone = 'red' })
                if not s.watch and not run then
                    s.watch = true
                    NZA.UI.Open(APP, { mode = 'watch', locale = B.Locale(), data = { target = e.t, bagSize = e.s, ml = e.ml } },
                        { focus = false, cursor = false })
                end
                if s.watch then NZA.UI.Send(APP, 'watch', { ml = e.ml, active = true, done = false }) end
            else
                if s.watch then
                    NZA.UI.Send(APP, 'watch', { ml = e.ml, active = false, done = e.done == true, bt = e.bt })
                    if not e.done then closeWatch(s) end
                end
                if e.done then
                    NZA.UI.HidePrompt('blood_seat_go')
                    NZA.UI.Prompt('blood_seat_up', { key = dcfg().standKey or 'X', label = L('prompt_stand'), sub = L('prompt_take_it_slow') })
                elseif run then
                    NZA.UI.HidePrompt('blood_seat_go')
                    NZA.UI.HidePrompt('blood_seat_up')
                else
                    if modeAllows(true) then
                        NZA.UI.Prompt('blood_seat_go', { key = 'E', label = L('prompt_donate'), sub = L('prompt_self') })
                    else
                        NZA.UI.HidePrompt('blood_seat_go')
                    end
                    NZA.UI.Prompt('blood_seat_up', { key = dcfg().standKey or 'X', label = L('prompt_stand'),
                        sub = modeAllows(false) and L('prompt_wait_medic') or nil })
                end
            end
        end
        if now - lastAnim > 1000 and not run then
            lastAnim = now
            playSit(ped, s)
        end
        if not run and IsControlJustPressed(0, 38) and modeAllows(true) then
            local e = chairState(s.point.id)
            if e and not e.a and not e.done then
                CreateThread(function() B.RunDonation(s.point, NZA.Target.Self(), true) end)
            end
        end
    end
end

function B.Sit(point, chair)
    if seated or run then return end
    if dcfg().enabled == false then return end
    if NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then return end
    local res = lib.callback.await('nza:blood:donation:check', false, point.id)
    if type(res) ~= 'table' or not res.ok then return toast(B.ErrMsg(res, L('err_failed')), 'error') end
    if res.taken then return toast(L('err_taken'), 'error') end
    if not res.eligible then return toast(res.msg or L('elig_generic'), 'error', L('elig_title')) end
    local r2 = lib.callback.await('nza:blood:donation:sit', false, point.id)
    if type(r2) ~= 'table' or not r2.ok then return toast(B.ErrMsg(r2, L('err_failed')), 'error') end
    local s = { point = point, chair = chair or NZA.Points.Entity(point.id), mode = r2.mode }
    seated = s
    -- walk to the chair side, then sit
    local ped = PlayerPedId()
    local side = worldOf(point, s.chair, vec3(0.75, 0.1, 0.0))
    TaskGoStraightToCoord(ped, side.x, side.y, side.z, 1.0, 2500, GetEntityHeading(ped), 0.2)
    local deadline = GetGameTimer() + 2600
    while GetGameTimer() < deadline do
        local c = GetEntityCoords(ped)
        if #(vector2(c.x, c.y) - vector2(side.x, side.y)) < 0.6 then break end
        Wait(100)
    end
    if seated ~= s then return end
    DoScreenFadeOut(250)
    Wait(260)
    seatPed(s)
    Wait(150)
    DoScreenFadeIn(350)
    if r2.mode == 'medic' then
        toast(L('sit_wait_medic'), 'info')
    elseif r2.mode == 'self' then
        toast(L('sit_self'), 'info')
    else
        toast(L('sit_both'), 'info')
    end
    s.since = GetGameTimer()
    CreateThread(function() seatLoop(s) end)
end

RegisterNetEvent('nza:blood:donation:stood', function(id)
    if seated and tostring(seated.point.id) == tostring(id) then B.StandUp(false) end
end)

RegisterCommand('nza_blood_standup', function()
    if seated then B.StandUp(true) end
end, false)
RegisterKeyMapping('nza_blood_standup', L('key_standup'), 'keyboard', dcfg().standKey or 'X')

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and seated then B.StandUp(true, true) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- DONATION RUN (self or medic)
-- ════════════════════════════════════════════════════════════════════════

local function endRun(s)
    if s.cleaned then return end
    s.cleaned = true
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    NZA.Cam.Stop(500)
    local d = dressed[s.point.id]
    if d then d.localMl = nil end
    if not s.isSelf then
        NZA.Anim.Stop(PlayerPedId())
    end
    if run == s then run = nil end
end

function B.RunDonation(point, target, isSelf)
    if run then return end
    local d = dressed[point.id]
    local chair = (d and d.chair) or NZA.Points.Entity(point.id)
    local s = { point = point, isSelf = isSelf == true, sentAt = 0, lastMl = 0 }
    run = s
    local c = dcfg()
    local anim = isSelf and (c.sit and c.sit.dict and { dict = c.sit.dict, clip = c.sit.clip, flag = 1 } or nil) or c.medicAnim
    local ok, err = pcall(function()
        NZA.Proc.Run('donation', target, { point = point.id }, function(ctx)
            s.ctx = ctx
            ctx.onEnd(function(outcome)
                s.ended = true
                if not outcome then endRun(s) end
            end)
            local ped = PlayerPedId()
            if not isSelf then
                local spot = c.medicSpot or vec4(0.95, 0.35, 0.0, 90.0)
                local sp = worldOf(point, chair, vec3(spot.x, spot.y, spot.z))
                local _, h = baseOf(point, chair)
                TaskGoStraightToCoord(ped, sp.x, sp.y, sp.z, 1.0, 3000, h + (spot.w or 90.0), 0.15)
                local deadline = GetGameTimer() + 3200
                while GetGameTimer() < deadline and not s.ended do
                    local pc = GetEntityCoords(ped)
                    if #(vector2(pc.x, pc.y) - vector2(sp.x, sp.y)) < 0.45 then break end
                    Wait(100)
                end
                if s.ended then return end
                SetEntityHeading(ped, h + (spot.w or 90.0))
                local ma = c.medicAnim or {}
                if ma.scenario then
                    NZA.Anim.Play(ped, nil, nil, { scenario = ma.scenario })
                elseif ma.dict then
                    NZA.Anim.Play(ped, ma.dict, ma.clip, { flag = ma.flag or 49 })
                end
            end
            local cam = c.camera or {}
            local focus = (chair and chair ~= 0) and chair or NZA.Target.Entity(target)
            local _, h = baseOf(point, chair)
            if focus and focus ~= 0 then
                NZA.Cam.Orbit(focus, {
                    dist = cam.dist or 2.6, height = cam.height or 0.55, pitch = cam.pitch or 26.0, fov = cam.fov or 44.0,
                    yaw = h + (cam.yaw or 35.0), minDist = 1.2, maxDist = 4.5,
                })
            end
            NZA.UI.Open(APP, {
                mode = 'donate', locale = B.Locale(), data = ctx.data, keys = c.keys, self = isSelf,
            }, { focus = true, cursor = true })
            while not s.ended and not s.result and not s.abortReq do Wait(100) end
            if s.ended then return end
            if s.abortReq then
                ctx.abort('cancel')
                endRun(s)
                return
            end
            local fine, outcome = ctx.finish(s.result)
            if not fine then
                endRun(s)
                return
            end
            NZA.UI.Send(APP, 'result', outcome or {})
            local deadline = GetGameTimer() + 15000
            while not s.closed and GetGameTimer() < deadline do Wait(100) end
            endRun(s)
        end, { label = L('proc_label'), anim = anim })
    end)
    if not ok then NZA.Warn('blood: donation run failed: ' .. tostring(err)) end
    endRun(s)
end

function B.Draw(point)
    if run then return end
    local e = chairState(point.id)
    if not e or not e.d then return toast(L('err_no_donor'), 'error') end
    if e.a then return toast(L('err_busy_chair'), 'error') end
    if e.done then return toast(L('err_done_chair'), 'error') end
    if not NZA.Perm(dcfg().perm or 'blood') then return toast(L('err_no_perm'), 'error') end
    B.RunDonation(point, { kind = 'player', sid = e.d }, false)
end

-- NUI callbacks (minigame)
NZA.UI.On(APP, 'progress', function(data, cb)
    cb({ ok = true })
    local s = run
    if not s or s.ended or type(data) ~= 'table' then return end
    local ml = U.clamp(tonumber(data.ml) or 0, 0, 1000)
    s.lastMl = ml
    local d = dressed[s.point.id]
    if d then d.localMl = ml end
    local now = GetGameTimer()
    if now - s.sentAt >= 300 then
        s.sentAt = now
        TriggerServerEvent('nza:blood:donation:progress', s.point.id, ml)
    end
end)

NZA.UI.On(APP, 'finish', function(data, cb)
    cb({ ok = true })
    local s = run
    if not s or s.result or type(data) ~= 'table' then return end
    s.result = { score = tonumber(data.score) or 0, ml = tonumber(data.ml) or s.lastMl or 0 }
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    if run and not run.result then run.abortReq = true end
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    local s = run
    if s then
        s.closed = true
        if not s.result then s.abortReq = true end
    end
    if seated and seated.watch then seated.watch = nil end
end)

-- ════════════════════════════════════════════════════════════════════════
-- POINT TYPE
-- ════════════════════════════════════════════════════════════════════════

NZA.Points.RegisterType('donation', {
    label = L('point_donation'), icon = 'bloodbag', prop = Config.Props.donation_chair, needsHeading = true,
    distance = 2.4,
    onSpawn = function(point, entity) dress(point, entity) end,
    onRemove = function(point) undress(point.id) end,
    target = {
        {
            name = 'nza_blood_sit', label = L('opt_sit'), icon = 'chair', distance = 2.2, order = 1,
            canInteract = function(point)
                if dcfg().enabled == false or seated or run then return false end
                if NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then return false end
                return chairState(point.id) == nil
            end,
            onSelect = function(point, entity)
                CreateThread(function() B.Sit(point, entity) end)
            end,
        },
        {
            name = 'nza_blood_draw', label = L('opt_draw'), icon = 'bloodbag', perm = dcfg().perm or 'blood', distance = 2.6, order = 2,
            canInteract = function(point)
                if run or not modeAllows(false) then return false end
                local e = chairState(point.id)
                return e ~= nil and e.d ~= mySid() and not e.a and not e.done
            end,
            onSelect = function(point)
                CreateThread(function() B.Draw(point) end)
            end,
        },
    },
})

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lcdOff()
    if seated then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
    end
    if run then NZA.Cam.Stop(0) end
end)
