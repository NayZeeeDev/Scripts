--[[
    NAYZEEE AMBULANCE - Assessment (client): shared helpers, patient menu, radial, Ask to Walk

    Patient options (NZA.Interact, ARCHITECTURE §11)
        nza_askwalk   'Ask to Walk'       order 10  NPC: stands up and follows you (TaskFollowToOffsetOfEntity)
                                                    player: gets a "walk with the medic" prompt toast
        nza_stopwalk  'Tell to wait'      order 10  the NPC that follows you stops and waits
        nza_examine   'Examine Patient'   order 20  → client/modules/assess_exam.lua
        nza_pulse     'Check Pulse'       order 20  → client/modules/assess_pulse.lua
        nza_breathing 'Check breathing'   order 20  → client/modules/assess_breathing.lua
    Radial (NZA.RadialItems, parent 'patient'): Examine / Pulse / Breathing / Ask to walk on the
    nearest patient within Config.Assess.Radial.range.

    Helpers other assess files use at runtime (never at load time):
        NZA.Assess.Start.exam|pulse|breathing(entity, target)
        NZA.Assess.Busy() / SetBusy(name|nil)      one assessment at a time
        NZA.Assess.Anim(ped, { dict, clip }, flag) / StopAnim(ped)
        NZA.Assess.Prop(model, attach) / ClearProps()
        NZA.Assess.Cam(mode, entity, opts) / CamStop()
        NZA.Assess.Track(app, defs, own) / Untrack(app)   world anchors → NUI ('anchors' action)
              defs[id] = { entity, bone, offset } | { coords } | { fn = function() return vec3 end }
              own = true always uses the local streamer (needed for fn anchors)
        NZA.Assess.ItemLabel(name) / ItemCount(name) / NearestPatient(range) / Toast(key, type, ...)
        NZA.Assess.Locale() → NZA.LocaleTable('assess')

    Net events handled: nza:assess:walkPrompt ({ medic, ms })
    Callbacks used: nza:assess:walk (target, on)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Assess = NZA.Assess or {}
NZA.Assess.Start = NZA.Assess.Start or {}
local A = NZA.Assess

local busy = nil
local props = {}
local tracked = {}       -- [app] = { defs, own }
local streamerOn = false
local ownCam = nil
local follow = nil       -- NPC currently following us
local FOLLOW_TASK = GetHashKey('SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY')

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

function A.Cfg(section)
    local c = Config.Assess or {}
    return c[section] or {}
end

function A.Locale()
    return NZA.LocaleTable('assess')
end

function A.Toast(key, kind, ...)
    NZA.UI.Toast({ title = NZA.L('assess.title'), message = NZA.L(key, ...), type = kind or 'info' })
end

function A.Busy() return busy end
function A.SetBusy(name) busy = name end

local itemKeys = nil
function A.ItemLabel(name)
    if not itemKeys then
        itemKeys = {}
        for key, item in pairs(Config.Items or {}) do itemKeys[item] = key end
    end
    local key = itemKeys[name]
    local def = key and Config.ItemDefs and Config.ItemDefs[key]
    if def and def.label then return def.label end
    return name
end

function A.ItemCount(name)
    if Bridge and Bridge.Inv then
        if Bridge.Inv.Count then
            local ok, n = pcall(Bridge.Inv.Count, name)
            if ok and tonumber(n) then return tonumber(n) end
        end
        if Bridge.Inv.Has then
            local ok, has = pcall(Bridge.Inv.Has, name, 1)
            if ok then return has and 1 or 0 end
        end
    end
    return 0
end

-- ════════════════════════════════════════════════════════════════════════
-- ANIMATIONS, PROPS, CAMERA (core APIs when present, small local fallbacks otherwise)
-- ════════════════════════════════════════════════════════════════════════

local KNEEL_DICT = 'amb@medic@standing@kneel@base'
local KNEEL_ENTER = 'amb@medic@standing@kneel@enter'

function A.IsKneeling(ped)
    return IsEntityPlayingAnim(ped, KNEEL_DICT, 'base', 3) or IsEntityPlayingAnim(ped, KNEEL_ENTER, 'enter', 3)
end

-- direct = true skips the kneel-down clip (already low, e.g. coming back from an idle)
function A.Anim(ped, anim, flag, direct)
    if type(anim) ~= 'table' or not anim.dict or not anim.clip then return end
    if anim.dict == KNEEL_DICT and not direct and NZA.Anim and NZA.Anim.Kneel then
        if A.IsKneeling(ped) then return end
        if pcall(NZA.Anim.Kneel, ped) then return end
    end
    if NZA.Anim and NZA.Anim.Play then
        local ok, played = pcall(NZA.Anim.Play, ped, anim.dict, anim.clip, { flag = flag or 1 })
        if ok and played ~= false then return end
    end
    if lib and lib.requestAnimDict then pcall(lib.requestAnimDict, anim.dict, 3000) end
    if HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, flag or 1, 0.0, false, false, false)
    end
end

function A.StopAnim(ped)
    if NZA.Anim and NZA.Anim.Stop then
        if pcall(NZA.Anim.Stop, ped) then return end
    end
    ClearPedTasks(ped)
end

function A.Prop(model, attach)
    if not model then return nil end
    local ent = nil
    if NZA.Props and NZA.Props.Spawn then
        local ok, res = pcall(NZA.Props.Spawn, model, { attach = attach }, { group = 'assess' })
        if ok then ent = res end
    end
    if not ent or ent == 0 then
        local hash = type(model) == 'number' and model or GetHashKey(model)
        if not IsModelInCdimage(hash) then return nil end
        if lib and lib.requestModel then pcall(lib.requestModel, hash, 3000) end
        if not HasModelLoaded(hash) then return nil end
        local c = GetEntityCoords(attach.entity)
        ent = CreateObject(hash, c.x, c.y, c.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        SetEntityCollision(ent, false, false)
        local pos, rot = attach.pos or vec3(0, 0, 0), attach.rot or vec3(0, 0, 0)
        AttachEntityToEntity(ent, attach.entity, GetPedBoneIndex(attach.entity, attach.bone or 57005),
            pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    end
    props[#props + 1] = ent
    return ent
end

function A.ClearProps()
    if NZA.Props and NZA.Props.Clear then pcall(NZA.Props.Clear, 'assess') end
    for _, ent in ipairs(props) do
        if ent and DoesEntityExist(ent) then
            DetachEntity(ent, true, false)
            DeleteEntity(ent)
        end
    end
    props = {}
end

local function fallbackCam(entity, height)
    local c = GetEntityCoords(entity)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, c.x, c.y, c.z + (height or 2.6))
    PointCamAtCoord(cam, c.x, c.y, c.z)
    SetCamFov(cam, 50.0)
    RenderScriptCams(true, true, 400, true, true)
    return cam
end

-- mode 'topdown' | 'orbit' | 'close' ; opts = { height, dist, fov, bone, target }
function A.Cam(mode, entity, opts)
    opts = opts or {}
    if not mode or entity == 0 then return end
    local Cam = NZA.Cam
    local ok = false
    if Cam then
        if mode == 'topdown' and Cam.TopDown then
            ok = pcall(Cam.TopDown, entity, opts.height or 2.6)
        elseif mode == 'orbit' and Cam.Orbit then
            ok = pcall(Cam.Orbit, opts.target or entity, { dist = opts.dist or opts.height or 2.4, fov = opts.fov or 50.0, pitch = opts.pitch or 55.0 })
        elseif mode == 'close' and Cam.Close then
            ok = pcall(Cam.Close, entity, opts.bone or 24818, { dist = opts.dist or 0.9, fov = opts.fov or 42.0, pitch = opts.pitch or 55.0 })
        end
    end
    if not ok then
        if ownCam then DestroyCam(ownCam, false) end
        ownCam = fallbackCam(entity, mode == 'close' and (opts.dist or 0.9) + 0.6 or (opts.height or 2.6))
    end
end

function A.CamStop()
    if NZA.Cam and NZA.Cam.Stop then pcall(NZA.Cam.Stop) end
    if ownCam then
        RenderScriptCams(false, true, 300, true, true)
        DestroyCam(ownCam, false)
        ownCam = nil
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- WORLD ANCHORS
-- ════════════════════════════════════════════════════════════════════════

local function anchorPos(d)
    if d.fn then
        local ok, v = pcall(d.fn)
        return ok and v or nil
    end
    if d.coords then return d.coords end
    local ent = d.entity
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local o = d.offset or vec3(0, 0, 0)
    if d.bone and IsEntityAPed(ent) then
        return GetPedBoneCoords(ent, d.bone, o.x, o.y, o.z)
    end
    return GetOffsetFromEntityInWorldCoords(ent, o.x, o.y, o.z)
end

local function streamer()
    if streamerOn then return end
    streamerOn = true
    CreateThread(function()
        while true do
            local any = false
            for app, t in pairs(tracked) do
                if t.own then
                    any = true
                    local map = {}
                    for id, d in pairs(t.defs) do
                        local p = anchorPos(d)
                        if p then
                            local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
                            map[id] = { x = x, y = y, visible = on and true or false }
                        else
                            map[id] = { x = 0, y = 0, visible = false }
                        end
                    end
                    NZA.UI.Send(app, 'anchors', map)
                end
            end
            if not any then break end
            Wait(33)
        end
        streamerOn = false
    end)
end

function A.Track(app, defs, own)
    local useCore = not own and NZA.Anchors and NZA.Anchors.Track
    if useCore then
        for _, d in pairs(defs) do
            if d.fn then useCore = false break end
        end
    end
    if useCore then
        local ok = pcall(NZA.Anchors.Track, app, defs)
        if ok then
            tracked[app] = { defs = defs, own = false }
            return
        end
    end
    tracked[app] = { defs = defs, own = true }
    streamer()
end

function A.Untrack(app)
    local t = tracked[app]
    tracked[app] = nil
    if t and not t.own and NZA.Anchors and NZA.Anchors.Clear then pcall(NZA.Anchors.Clear, app) end
end

-- ════════════════════════════════════════════════════════════════════════
-- NEAREST PATIENT (radial menu)
-- ════════════════════════════════════════════════════════════════════════

function A.NearestPatient(range)
    range = range or A.Cfg('Radial').range or 3.0
    local me = PlayerPedId()
    local coords = GetEntityCoords(me)
    local best, bestD = nil, range
    for _, pid in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pid)
        if ped ~= me and ped ~= 0 then
            local d = #(coords - GetEntityCoords(ped))
            if d < bestD then best, bestD = ped, d end
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and Entity(ped).state.nza ~= nil then
            local d = #(coords - GetEntityCoords(ped))
            if d < bestD then best, bestD = ped, d end
        end
    end
    if not best then return nil end
    local target = NZA.Target.FromEntity(best)
    if not target then return nil end
    return best, target
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE RUNNER (pulse & breathing share the same NUI life cycle)
--   o = { name, app, entity, target, label, setup = fn(ctx, s), teardown = fn(s),
--         anchors = fn(entity, ctx) → defs, ownAnchors = bool }
--   NUI: '<app>:finish' (result) '<app>:abort' '<app>:close' are wired by A.ProcCallbacks(app)
-- ════════════════════════════════════════════════════════════════════════

local runs = {}   -- [app] = live session

function A.Session(app) return runs[app] end

local function endRun(s, closeUi)
    if s.cleaned then return end
    s.cleaned = true
    if runs[s.app] == s then runs[s.app] = nil end
    if closeUi and NZA.UI.IsOpen(s.app) then NZA.UI.Close(s.app) end
    A.Untrack(s.app)
    if s.o.teardown then pcall(s.o.teardown, s) end
    A.ClearProps()
    A.CamStop()
    if not s.keepPose then A.StopAnim(PlayerPedId()) end
end
A.EndRun = endRun

function A.ProcCallbacks(app)
    NZA.UI.On(app, 'finish', function(data, cb)
        cb({ ok = true })
        local s = runs[app]
        if s and not s.result and type(data) == 'table' then s.result = data end
    end)
    NZA.UI.On(app, 'abort', function(_, cb)
        cb({ ok = true })
        local s = runs[app]
        if s then s.abortReq = true end
    end)
    NZA.UI.On(app, 'close', function(_, cb)
        cb({ ok = true })
        local s = runs[app]
        if s then s.closed = true end
    end)
end

function A.RunProc(o)
    if not (NZA.Proc and NZA.Proc.Run) then
        A.Toast('assess.err_core', 'error')
        return false
    end
    A.SetBusy(o.name)
    local entity, target = o.entity, o.target
    local ok, err = pcall(NZA.Proc.Run, o.name, target, o.payload or {}, function(ctx)
        local s = { app = o.app, o = o, ctx = ctx, entity = entity, target = target, keepPose = o.keepPose == true }
        runs[o.app] = s
        ctx.onEnd(function(outcome)
            s.ended = true
            -- ended without a result card (abort, cancel, too far, patient died...)
            if not s.result or not outcome then endRun(s, true) end
        end)
        local me = PlayerPedId()
        if entity ~= 0 then
            TaskTurnPedToFaceEntity(me, entity, 600)
            Wait(450)
        end
        if s.ended then return end
        if o.setup then o.setup(ctx, s) end
        local data = ctx.data or {}
        data.locale = A.Locale()
        NZA.UI.Open(o.app, data, { focus = true, cursor = true })
        if o.anchors then A.Track(o.app, o.anchors(entity, ctx), o.ownAnchors) end

        while not s.result and not s.abortReq and not s.closed and not s.ended do Wait(50) end
        if s.ended then return end
        if not s.result then
            ctx.abort(s.closed and 'cancel' or 'silent')
            endRun(s, true)
            return
        end
        local nonce = s.result.nonce
        local fine, outcome = ctx.finish(s.result)
        if not fine then
            endRun(s, true)
            return
        end
        if type(outcome) ~= 'table' or not outcome.rows then
            local okF, fetched = pcall(lib.callback.await, 'nza:assess:outcome', false, nonce)
            if okF and type(fetched) == 'table' then outcome = fetched end
        end
        NZA.UI.Send(o.app, 'result', outcome or {})
        -- keep the scene until the medic closes the result card
        local deadline = GetGameTimer() + 60000
        while not s.closed and GetGameTimer() < deadline do
            Wait(100)
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
        end
        endRun(s, true)
    end, { label = o.label })
    if not ok then NZA.Warn(('assess %s failed: %s'):format(o.name, tostring(err))) end
    -- a session that ended without a result card is cleaned up here; with a card, the
    -- runner thread keeps the scene until the medic closes it
    local s = runs[o.app]
    if s and (not ok or not s.result) then endRun(s, true) end
    if A.Busy() == o.name then A.SetBusy(nil) end
    return ok
end

-- ════════════════════════════════════════════════════════════════════════
-- ASK TO WALK
-- ════════════════════════════════════════════════════════════════════════

local function requestControl(ent, ms)
    if NetworkHasControlOfEntity(ent) then return true end
    local deadline = GetGameTimer() + (ms or 1500)
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        Wait(25)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

local function taskFollow(f, jog)
    local me = PlayerPedId()
    local o = A.Cfg('Walk').offset or vec3(0.7, -1.1, 0.0)
    TaskFollowToOffsetOfEntity(f.ent, me, o.x, o.y, o.z, jog and 2.0 or 1.0, -1, A.Cfg('Walk').stopRange or 1.4, true)
    SetPedKeepTask(f.ent, true)
    f.jog = jog
    f.tasked = GetGameTimer()
end

function A.StopWalk(reason, silent)
    local f = follow
    if not f then return end
    follow = nil
    if DoesEntityExist(f.ent) then
        if requestControl(f.ent, 500) then
            ClearPedTasks(f.ent)
            TaskStandStill(f.ent, 2000)
            if f.clipset then ResetPedMovementClipset(f.ent, 0.25) end
        end
    end
    CreateThread(function()
        pcall(lib.callback.await, 'nza:assess:walk', false, f.target, false)
    end)
    if not silent then
        A.Toast('assess.walk_stopped_' .. (reason or 'asked'), reason == 'asked' and 'info' or 'warning')
    end
end

function A.Following(entity)
    return follow ~= nil and (entity == nil or follow.ent == entity)
end

local function standUp(ped)
    local wc = A.Cfg('Walk')
    ClearPedTasks(ped)
    if IsPedRagdoll(ped) then
        local t = GetGameTimer() + 3000
        while IsPedRagdoll(ped) and GetGameTimer() < t do Wait(50) end
    end
    local a = wc.getUpAnim
    if a and a.dict and a.clip then
        if lib and lib.requestAnimDict then pcall(lib.requestAnimDict, a.dict, 2000) end
        if HasAnimDictLoaded(a.dict) then
            TaskPlayAnim(ped, a.dict, a.clip, 4.0, 4.0, 1600, 0, 0.0, false, false, false)
            Wait(1500)
        end
    end
end

function A.Walk(entity, target)
    if follow then A.StopWalk('asked', true) end
    local ok, res, info = pcall(lib.callback.await, 'nza:assess:walk', false, target, true)
    if not ok or not res then
        NZA.UI.Toast({ title = NZA.L('assess.walk_title'), message = (type(info) == 'string' and info) or NZA.L('assess.err_generic'), type = 'error' })
        return
    end
    info = type(info) == 'table' and info or {}
    if info.player then
        A.Toast('assess.walk_asked_player', 'success')
        return
    end
    if not requestControl(entity, 2000) then
        A.Toast('assess.walk_no_control', 'error')
        pcall(lib.callback.await, 'nza:assess:walk', false, target, false)
        return
    end
    local wc = A.Cfg('Walk')
    SetBlockingOfNonTemporaryEvents(entity, true)
    standUp(entity)
    local f = { ent = entity, target = target, started = GetGameTimer() }
    if info.limp and wc.limpClipset then
        if lib and lib.requestAnimSet then pcall(lib.requestAnimSet, wc.limpClipset, 2000) end
        if HasAnimSetLoaded(wc.limpClipset) then
            SetPedMovementClipset(entity, wc.limpClipset, 0.25)
            f.clipset = wc.limpClipset
        end
    end
    follow = f
    taskFollow(f, false)
    A.Toast('assess.walk_following', 'success')

    CreateThread(function()
        local maxD = wc.maxDistance or 40.0
        local jogD = wc.jogDistance or 6.0
        while follow == f do
            Wait(500)
            if follow ~= f then break end
            local ped = f.ent
            if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then A.StopWalk('gone') break end
            local st = NZA.Target.State(ped)
            if type(st) == 'table' and (st.st ~= 'alive' or st.carried or st.stretcher or st.bag) then A.StopWalk('placed') break end
            if IsEntityAttached(ped) or IsPedInAnyVehicle(ped, true) then A.StopWalk('placed') break end
            local me = PlayerPedId()
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then A.StopWalk('down') break end
            local d = #(GetEntityCoords(me) - GetEntityCoords(ped))
            if d > maxD then A.StopWalk('far') break end
            if not IsPedInAnyVehicle(me, false) then
                if not NetworkHasControlOfEntity(ped) then requestControl(ped, 300) end
                local jog = d > jogD
                local status = GetScriptTaskStatus(ped, FOLLOW_TASK)
                if jog ~= f.jog or status == 7 or GetGameTimer() - f.tasked > 15000 then
                    taskFollow(f, jog)
                end
            end
        end
    end)
end

RegisterNetEvent('nza:assess:walkPrompt', function(data)
    if type(data) ~= 'table' then return end
    NZA.UI.Toast({
        title = NZA.L('assess.walk_prompt_title'),
        message = NZA.L('assess.walk_prompt', tostring(data.medic or '?')),
        type = 'info',
        duration = tonumber(data.ms) or 6000,
        icon = 'walk',
    })
end)

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT MENU
-- ════════════════════════════════════════════════════════════════════════

local function start(name)
    return function(entity, target)
        if busy then
            A.Toast('assess.err_busy', 'error')
            return
        end
        local fn = A.Start[name]
        if fn then fn(entity, target) end
    end
end

local function notPlaced(_, _, st)
    return not (type(st) == 'table' and (st.carried or st.bag))
end

do
    local ic = A.Cfg('Interact')
    local icons = ic.icons or {}
    local perm = ic.perm or 'assess'
    local dist = ic.distance or 2.2
    local wc = A.Cfg('Walk')

    if wc.enabled ~= false then
        NZA.Interact.Add({
            name = 'nza_askwalk', label = NZA.L('assess.opt_walk'), icon = icons.walk or 'walk', order = 10,
            perm = wc.perm, states = { alive = true }, npc = true, player = true, distance = dist,
            canInteract = function(entity, target, st)
                if follow and follow.ent == entity then return false end
                if type(st) == 'table' and (st.carried or st.stretcher or st.bag) then return false end
                if not IsPedAPlayer(entity) and IsPedInAnyVehicle(entity, true) then return false end
                return true
            end,
            onSelect = function(entity, target) A.Walk(entity, target) end,
        })
        NZA.Interact.Add({
            name = 'nza_stopwalk', label = NZA.L('assess.opt_wait'), icon = icons.wait or 'hand', order = 10,
            perm = wc.perm, npc = true, player = false, distance = 6.0,
            canInteract = function(entity) return follow ~= nil and follow.ent == entity end,
            onSelect = function() A.StopWalk('asked') end,
        })
    end
    if ic.examine ~= false then
        NZA.Interact.Add({
            name = 'nza_examine', label = NZA.L('assess.opt_examine'), icon = icons.examine or 'stetho', order = 20,
            perm = perm, states = { alive = true, wounded = true, arrest = true, dead = true }, distance = dist,
            canInteract = notPlaced, onSelect = start('exam'),
        })
    end
    if ic.pulse ~= false then
        NZA.Interact.Add({
            name = 'nza_pulse', label = NZA.L('assess.opt_pulse'), icon = icons.pulse or 'pulse', order = 21,
            perm = perm, states = { alive = true, wounded = true, arrest = true, dead = true }, distance = dist,
            canInteract = notPlaced, onSelect = start('pulse'),
        })
    end
    if ic.breathing ~= false then
        NZA.Interact.Add({
            name = 'nza_breathing', label = NZA.L('assess.opt_breathing'), icon = icons.breathing or 'lungs', order = 22,
            perm = perm, states = { alive = true, wounded = true, arrest = true, dead = true }, distance = dist,
            canInteract = notPlaced, onSelect = start('breathing'),
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL (EMS job menu → Patient)
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

local function radial(id, label, icon, order, perm, fn)
    table.insert(NZA.RadialItems, {
        id = id, parent = 'patient', label = label, icon = icon, order = order, perm = perm,
        canShow = function()
            if A.Cfg('Radial').enabled == false then return false end
            return A.NearestPatient() ~= nil
        end,
        onSelect = function()
            CreateThread(function()
                local ent, target = A.NearestPatient()
                if not ent then
                    A.Toast('assess.err_nobody', 'error')
                    return
                end
                fn(ent, target)
            end)
        end,
    })
end

do
    local perm = A.Cfg('Interact').perm or 'assess'
    radial('assess_examine', NZA.L('assess.opt_examine'), 'stetho', 20, perm, start('exam'))
    radial('assess_pulse', NZA.L('assess.opt_pulse'), 'pulse', 21, perm, start('pulse'))
    radial('assess_breathing', NZA.L('assess.opt_breathing'), 'lungs', 22, perm, start('breathing'))
    if A.Cfg('Walk').enabled ~= false then
        radial('assess_walk', NZA.L('assess.opt_walk'), 'walk', 10, A.Cfg('Walk').perm, function(ent, target)
            if follow and follow.ent == ent then A.StopWalk('asked') else A.Walk(ent, target) end
        end)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if follow and DoesEntityExist(follow.ent) then
        ClearPedTasks(follow.ent)
        if follow.clipset then ResetPedMovementClipset(follow.ent, 0.0) end
    end
    follow = nil
    for _, ent in ipairs(props) do
        if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    props = {}
    if ownCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(ownCam, false)
        ownCam = nil
    end
end)

CreateThread(function()
    Wait(0)
    NZA.Bus.On('self:state', function(new)
        if new ~= 'alive' and follow then A.StopWalk('down') end
    end)
end)
