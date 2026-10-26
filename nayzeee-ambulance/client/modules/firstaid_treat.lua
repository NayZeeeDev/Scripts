--[[
    NAYZEEE AMBULANCE - First aid (client): the 'treat' NUI app runner

      FA.Start.bleed(entity, target, injuryId?)          NZA.Proc 'stopbleed'  (pressure → pack → wrap | dressing)
      FA.Start.tq(entity, target, injuryId?, region?)    NZA.Proc 'tourniquet' (place → twist → lock)
      FA.Start.collar(entity, target)                    NZA.Proc 'collar'     (measure & size → fasten in line)
      FA.Start.meds(entity, target, presetDrug?)         dose panel → NZA.Treat 'fa_med'
      FA.Start.kit(entity, target)                       first aid item chooser → FA.UseItem
      FA.Start.oxygen(entity, target, on)                NZA.Treat 'fa_oxygen' / 'fa_oxygen_off'
      FA.Start.tqOff / collarOff / foilOff(entity, target)
      FA.Start.recovery(entity, target)                  NZA.Treat 'fa_recovery' (recovery position)
      FA.TqPlacing() → { ped } while a tourniquet minigame shows its own strap prop

    Close-up camera (NZA.Cam.Close on Const.RegionBone / the limb joint / the neck), the medic kneels
    (or works standing for an upright patient), world anchors stream the limb joints, the wound
    region or the head/neck to the app, NZA.Patient.Watch streams vitals (medics only).

    NUI callbacks: treat:finish { result }  treat:abort  treat:tqPlace { seg, frac }
                   treat:give { drug, dose, route }  treat:use { key }  treat:close (core)
    Lua → NUI: open, anchors (core), vitals, result, given, meds
    Easy mode: NZA.Proc.Run shows the core progress bar instead of the runner (server decides).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Firstaid = NZA.Firstaid or {}
NZA.Firstaid.Start = NZA.Firstaid.Start or {}
local FA = NZA.Firstaid
local Start = FA.Start
local APP = 'treat'

local session = nil   -- running procedure (bleed / tq / collar)
local panel = nil     -- meds / kit panel
local tqTemp = nil    -- { entity, ped } temporary strap prop while placing a tourniquet
local tqSeq = 0       -- one per tqPlace post: a spawn that finishes after a newer post drops its prop

local KNEEL = { dict = 'amb@medic@standing@kneel@base', clip = 'base' }
local STAND = { dict = 'mini@repair', clip = 'fixing_a_ped' }

local function L(key, ...) return NZA.L('firstaid.' .. key, ...) end

local function clockText()
    if (FA.Cfg('Tourniquet').clock or 'game') == 'real' then return nil end
    return ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
end

local function anyBusy()
    if FA.Busy() or session or panel then return true end
    if NZA.Proc and NZA.Proc.Active and NZA.Proc.Active() then return true end
    if lib.progressActive and lib.progressActive() then return true end
    return false
end

local function vitalsOf(snap)
    local v = snap and snap.vitals or {}
    return { hr = v.hr, sys = v.sys, dia = v.dia, spo2 = v.spo2, rr = v.rr, bleed = snap and snap.bleedTotal }
end

function FA.TqPlacing()
    return tqTemp
end

local function clearTqTemp()
    if tqTemp and tqTemp.entity and tqTemp.entity ~= 0 then NZA.Props.Delete(tqTemp.entity) end
    tqTemp = nil
end

-- ════════════════════════════════════════════════════════════════════════
-- ANCHORS & CAMERA PER MODE
-- ════════════════════════════════════════════════════════════════════════

local function limbAnchors(ped, region)
    local limb = FA.LimbOf(region)
    if not limb then return nil end
    return {
        j0 = { entity = ped, bone = limb.chain[1] },
        j1 = { entity = ped, bone = limb.chain[2] },
        j2 = { entity = ped, bone = limb.chain[3] },
    }
end

local function anchorsFor(ped, data)
    if data.mode == 'collar' then
        return { head = { entity = ped, bone = 31086 }, neck = { entity = ped, bone = 39317 }, chest = { entity = ped, bone = 24818 } }
    end
    local region = data.mode == 'tq' and data.region or (data.injury and data.injury.region)
    local limb = limbAnchors(ped, region)
    if limb then return limb end
    local bone = NZA.Const.RegionBone[region or 'chest'] or 24818
    return { wound = { entity = ped, bone = bone }, pel = { entity = ped, bone = 11816 }, neck = { entity = ped, bone = 39317 } }
end

local function cameraFor(ped, data)
    local cfg, bone
    if data.mode == 'collar' then
        cfg, bone = FA.Cfg('Collar').camera or {}, 39317
    elseif data.mode == 'tq' then
        cfg = FA.Cfg('Tourniquet').camera or {}
        local limb = FA.LimbOf(data.region)
        bone = limb and limb.chain[2] or NZA.Const.RegionBone[data.region]
    else
        cfg = FA.Cfg('StopBleed').camera or {}
        bone = NZA.Const.RegionBone[data.injury and data.injury.region or 'chest'] or 24818
    end
    -- right-drag turns the close-up (so a wound at the edge of the frame can be brought into view), wheel zooms
    local ok = pcall(NZA.Cam.Close, ped, bone, { dist = cfg.dist or 0.95, pitch = cfg.pitch or 58.0, fov = cfg.fov or 42.0,
        orbit = cfg.orbit ~= false, minPitch = 25.0, maxPitch = 85.0 })
    if not ok then pcall(NZA.Cam.Orbit, ped, { dist = 1.6, pitch = 55.0 }) end
end

local function medicPose(ped, entity, mode)
    if FA.Lying(entity) then
        local a = mode == 'bleed' and FA.Cfg('StopBleed').anim or nil
        if NZA.Anim.Kneel then pcall(NZA.Anim.Kneel, ped) end
        if a and a.dict then
            SetTimeout(1400, function()
                if session and session.ped == ped then pcall(NZA.Anim.Play, ped, a.dict, a.clip, { flag = 1, blendIn = 2.0 }) end
            end)
        end
    else
        pcall(NZA.Anim.Play, ped, STAND.dict, STAND.clip, { flag = 1 })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE RUNNER
-- ════════════════════════════════════════════════════════════════════════

local function cleanup(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    if session == s then session = nil end
    if s.stopWatch then pcall(s.stopWatch) end
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    pcall(NZA.Anchors.Clear, APP)
    clearTqTemp()
    pcall(NZA.Cam.Stop)
    pcall(NZA.Anim.Stop, PlayerPedId())
    if FA.Busy() == s.name then FA.SetBusy(nil) end
end

local function runProc(name, entity, target, payload)
    if anyBusy() then
        FA.Toast(L('err_busy'), 'error')
        return false
    end
    target = FA.Target(entity, target)
    if not target then return false end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    if not entity or entity == 0 then return false end
    FA.SetBusy(name)
    local ok, err = pcall(NZA.Proc.Run, name, target, payload or {}, function(ctx)
        local me = PlayerPedId()
        local s = { name = name, ctx = ctx, entity = entity, target = target, ped = me, data = ctx.data or {} }
        session = s
        ctx.onEnd(function(outcome) s.ended = true; s.outcome = outcome end)
        TaskTurnPedToFaceEntity(me, entity, 600)
        Wait(500)
        if s.ended then cleanup(s) return end
        local data = s.data
        medicPose(me, entity, data.mode)
        cameraFor(entity, data)
        data.locale = NZA.LocaleTable('firstaid')
        data.keys = FA.Cfg('Keys')
        if data.mode == 'tq' and not data.time then data.time = clockText() end
        NZA.UI.Open(APP, data, { focus = true, cursor = true })
        pcall(NZA.Anchors.Track, APP, anchorsFor(entity, data))
        local okW, stop = pcall(NZA.Patient.Watch, target, function(snap)
            if snap and session == s then NZA.UI.Send(APP, 'vitals', vitalsOf(snap)) end
        end, { initial = false })
        if okW then s.stopWatch = stop end

        while not s.result and not s.abortReq and not s.closed and not s.ended do Wait(50) end
        if s.ended then cleanup(s) return end
        if not s.result then
            ctx.abort('cancel')
            cleanup(s)
            return
        end
        -- from here on the runner owns the scene (result card) even after NZA.Proc.Run returned
        s.finishing = true
        local fine, outcome = ctx.finish(s.result)
        if not fine or s.closed then cleanup(s) return end
        NZA.UI.Send(APP, 'result', outcome or {})
        local deadline = GetGameTimer() + 12000
        while not s.closed and GetGameTimer() < deadline do
            Wait(100)
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
        end
        cleanup(s)
    end, { label = L('title_' .. name) })
    if not ok then NZA.Warn(('firstaid %s failed: %s'):format(name, tostring(err))) end
    local s = session
    if s and s.name == name then
        if not ok or not s.finishing then cleanup(s) end
    elseif FA.Busy() == name then
        FA.SetBusy(nil)
    end
    return ok
end

function Start.bleed(entity, target, injuryId)
    return runProc('stopbleed', entity, target, { injury = injuryId })
end

function Start.tq(entity, target, injuryId, region)
    return runProc('tourniquet', entity, target, { injury = injuryId, region = region })
end

function Start.collar(entity, target)
    return runProc('collar', entity, target, {})
end

NZA.UI.On(APP, 'finish', function(data, cb)
    cb({ ok = true })
    local s = session
    if s and not s.result and type(data) == 'table' and type(data.result) == 'table' then s.result = data.result end
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    if session then session.abortReq = true end
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    if session then session.closed = true end
    if panel then panel.closed = true end
end)

NZA.UI.On(APP, 'tqPlace', function(data, cb)
    cb({ ok = true })
    local s = session
    if not s or s.data.mode ~= 'tq' or type(data) ~= 'table' then return end
    local seg = data.seg == 'lower' and 'lower' or 'upper'
    local frac = math.max(0.0, math.min(1.0, tonumber(data.frac) or 0.2))
    tqSeq = tqSeq + 1
    local seq = tqSeq
    CreateThread(function()
        clearTqTemp()
        local ped = s.entity
        if not DoesEntityExist(ped) then return end
        local at = FA.TqAttach(ped, s.data.region, { s = seg, f = frac })
        local key = (FA.Cfg('Props').tourniquet or {}).prop or 'tourniquet_worn'
        if not at or not key then return end
        local ent = NZA.Props.Spawn(key, { attach = { entity = ped, bone = at.bone, pos = at.pos, rot = at.rot, collision = false } },
            { group = 'firstaid_proc', collision = false })
        -- Spawn can yield while the model loads: only the newest post keeps its strap
        if session == s and seq == tqSeq then
            clearTqTemp()
            tqTemp = { entity = ent, ped = ped }
        elseif ent and ent ~= 0 then NZA.Props.Delete(ent) end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- MEDICATION PANEL
-- ════════════════════════════════════════════════════════════════════════

local function buildDrugs()
    local out = {}
    for _, d in ipairs(FA.Cfg('Meds').drugs or {}) do
        local item = Config.Items and Config.Items[d.item or d.id]
        if item and d.enabled ~= false then
            out[#out + 1] = {
                id = d.id, label = L('drug_' .. d.id), short = L('drug_' .. d.id .. '_short'), desc = L('drug_' .. d.id .. '_desc'),
                icon = d.icon or 'syringe', item = item, have = FA.ItemCount(item), routes = d.routes or { 'iv' },
                doses = d.doses or { { dose = 1, mg = '' } }, default = d.default or 1, access = d.access == true,
                img = FA.ItemImage(item),
            }
        end
    end
    return out
end

local function closePanel(p)
    if not p or p.cleaned then return end
    p.cleaned = true
    if panel == p then panel = nil end
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if p.cam then pcall(NZA.Cam.Stop) end
    pcall(NZA.Anim.Stop, PlayerPedId())
    if FA.Busy() == p.kind then FA.SetBusy(nil) end
end

local function watchPanel(p)
    local me = PlayerPedId()
    if not DoesEntityExist(p.entity) then return 'gone' end
    if p.entity ~= me and #(GetEntityCoords(me) - GetEntityCoords(p.entity)) > 4.5 then return 'far' end
    if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then return 'down' end
    return nil
end

local function giveDrug(p, g)
    local mc = FA.Cfg('Meds')
    local me = PlayerPedId()
    local a = mc.anim or {}
    TaskTurnPedToFaceEntity(me, p.entity, 500)
    Wait(400)
    local anim = FA.Lying(p.entity) and KNEEL or a
    if anim.dict then
        pcall(NZA.Anim.Play, me, anim.dict, anim.clip, {
            flag = anim.flag or 1,
            prop = mc.prop and { model = mc.prop, bone = 57005, pos = vector3(0.12, 0.03, -0.02), rot = vector3(-70.0, 0.0, 0.0) } or nil,
        })
    end
    Wait(tonumber(a.duration) or 2600)
    pcall(NZA.Anim.Stop, me)
    -- the panel waits for 'given': an error here must still answer it
    local called, ok = pcall(NZA.Treat.Do, 'fa_med', p.target, { drug = g.drug, dose = g.dose, route = g.route })
    if not called then NZA.Debug('fa_med failed', ok); ok = false end
    if p.closed then return end
    if ok and not mc.keepOpen then
        NZA.UI.Send(APP, 'given', { ok = true })
        Wait(450)
        p.closed = true
        return
    end
    local got, info = pcall(lib.callback.await, 'nza:firstaid:meds', false, p.target)
    NZA.UI.Send(APP, 'given', { ok = ok, drugs = buildDrugs() })
    if got and info then NZA.UI.Send(APP, 'meds', info) end
end

function Start.meds(entity, target, preset)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    local mc = FA.Cfg('Meds')
    if not NZA.Perm(mc.perm or 'meds') then FA.Toast(L('err_no_perm'), 'error') return end
    target = FA.Target(entity, target)
    if not target then return end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    local info, err = lib.callback.await('nza:firstaid:meds', false, target)
    if not info then FA.Toast(L('err_' .. tostring(err or 'failed')), 'error') return end
    local p = { kind = 'meds', entity = entity, target = target }
    panel = p
    FA.SetBusy('meds')
    if entity ~= PlayerPedId() then
        local cam = mc.camera or {}
        p.cam = pcall(NZA.Cam.Orbit, entity, { dist = cam.dist or 2.2, pitch = cam.pitch or 28.0, fov = cam.fov or 45.0 })
    end
    NZA.UI.Open(APP, {
        mode = 'meds', locale = NZA.LocaleTable('firstaid'), info = info, drugs = buildDrugs(), preset = preset,
        patient = { name = info.name }, tune = { morphineRR = mc.morphineRR or 10, morphineSys = mc.morphineSys or 90 },
        easy = NZA.Easy and NZA.Easy(mc.perm or 'meds') or false,
    }, { focus = true, cursor = true })
    while not p.closed do
        Wait(100)
        local why = watchPanel(p)
        if why then
            if why ~= 'down' then FA.Toast(L('closed_' .. why), 'warning') end
            break
        end
        if p.give then
            local g = p.give
            p.give = nil
            giveDrug(p, g)
        end
    end
    closePanel(p)
end

NZA.UI.On(APP, 'give', function(data, cb)
    cb({ ok = true })
    local p = panel
    if not p or p.kind ~= 'meds' or type(data) ~= 'table' or p.give then return end
    if type(data.drug) ~= 'string' then return end
    p.give = { drug = data.drug, dose = math.floor(tonumber(data.dose) or 1), route = type(data.route) == 'string' and data.route or nil }
end)

-- ════════════════════════════════════════════════════════════════════════
-- FIRST AID KIT CHOOSER
-- ════════════════════════════════════════════════════════════════════════

function Start.kit(entity, target)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    target = FA.Target(entity, target)
    if not target then return end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    local info = lib.callback.await('nza:firstaid:kit', false, target)
    if type(info) ~= 'table' then FA.Toast(L('err_failed'), 'error') return end
    local items = {}
    for _, e in ipairs(info.items or {}) do
        local name = e.item or (Config.Items and Config.Items[e.key])
        items[#items + 1] = { key = e.key, label = FA.ItemLabel(name), have = FA.ItemCount(name), usable = e.usable == true, text = e.text, img = FA.ItemImage(name) }
    end
    local p = { kind = 'kit', entity = entity, target = target }
    panel = p
    FA.SetBusy('kit')
    NZA.UI.Open(APP, { mode = 'kit', locale = NZA.LocaleTable('firstaid'), name = info.name, self = info.self, items = items }, { focus = true, cursor = true })
    while not p.closed and not p.use do
        Wait(100)
        if watchPanel(p) then break end
    end
    local use = p.use
    closePanel(p)
    if use then FA.UseItem(use, entity, target) end
end

NZA.UI.On(APP, 'use', function(data, cb)
    cb({ ok = true })
    local p = panel
    if not p or p.kind ~= 'kit' or type(data) ~= 'table' or type(data.key) ~= 'string' then return end
    if FA.ItemActions[data.key] then p.use = data.key end
end)

-- ════════════════════════════════════════════════════════════════════════
-- QUICK DEVICES (oxygen, removing a tourniquet / collar / foil blanket)
-- ════════════════════════════════════════════════════════════════════════

local function quick(entity, target, ms, label, anim)
    target = FA.Target(entity, target)
    if not target then return nil end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    local me = PlayerPedId()
    if entity ~= me then TaskTurnPedToFaceEntity(me, entity, 500) Wait(400) end
    anim = anim or (FA.Lying(entity) and KNEEL or STAND)
    FA.SetBusy('quick')
    local ok = lib.progressBar({
        duration = ms, label = label, useWhileDead = false, canCancel = true, allowRagdoll = false,
        disable = { move = true, car = true, combat = true, sprint = true },
        anim = anim and { dict = anim.dict, clip = anim.clip, flag = anim.flag or 1 } or nil,
    })
    FA.SetBusy(nil)
    if not ok then FA.Toast(L('cancelled'), 'error') return nil end
    return target
end

function Start.oxygen(entity, target, on)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    local oc = FA.Cfg('Oxygen')
    if on then
        local item = Config.Items and Config.Items[oc.item or 'oxygen_mask']
        if item and FA.ItemCount(item) < 1 then FA.Toast(L('err_need_item', FA.ItemLabel(item)), 'error') return end
        local a = oc.anim or {}
        local t = quick(entity, target, tonumber(a.duration) or 2500, L('use_oxygen'), a.dict and a or nil)
        if t then NZA.Treat.Do('fa_oxygen', t) end
    else
        local t = quick(entity, target, 1500, L('use_oxygen_off'))
        if t then NZA.Treat.Do('fa_oxygen_off', t) end
    end
end

local function removeTq(entity, target, region)
    local t = quick(entity, target, 2500, L('use_tq_off'))
    if t then NZA.Treat.Do('fa_tq_off', t, { region = region }) end
end

function Start.tqOff(entity, target)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    local st = NZA.Target.State(entity)
    local regions = {}
    for region in pairs(type(st) == 'table' and type(st.tq) == 'table' and st.tq or {}) do regions[#regions + 1] = region end
    if #regions == 0 then FA.Toast(L('err_no_tq'), 'error') return end
    if #regions == 1 then return removeTq(entity, target, regions[1]) end
    table.sort(regions)
    local options = {}
    for _, region in ipairs(regions) do
        options[#options + 1] = {
            title = L('tq_off_region', NZA.Util.RegionLabel(region)), icon = 'fa-solid fa-xmark',
            onSelect = function() CreateThread(function() removeTq(entity, target, region) end) end,
        }
    end
    lib.registerContext({ id = 'nza_fa_tqoff', title = L('opt_tq_off'), options = options })
    lib.showContext('nza_fa_tqoff')
end

function Start.collarOff(entity, target)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    local t = quick(entity, target, 2500, L('use_collar_off'))
    if t then NZA.Treat.Do('fa_collar_off', t) end
end

function Start.foilOff(entity, target)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    local t = quick(entity, target, 1500, L('use_foil_off'))
    if t then NZA.Treat.Do('fa_foil_off', t) end
end

function Start.recovery(entity, target)
    if anyBusy() then FA.Toast(L('err_busy'), 'error') return end
    local t = quick(entity, target, tonumber(FA.Cfg('Recovery').duration) or 3500, L('use_recovery'))
    if t then NZA.Treat.Do('fa_recovery', t) end
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearTqTemp()
    if NZA.Props and NZA.Props.Clear then pcall(NZA.Props.Clear, 'firstaid_proc') end
    if session or panel then
        RenderScriptCams(false, false, 0, true, true)
        ClearPedTasks(PlayerPedId())
    end
    session, panel = nil, nil
end)

CreateThread(function()
    Wait(0)
    NZA.Bus.On('self:state', function(new)
        if new == 'alive' then return end
        if session then session.abortReq = true end
        if panel then panel.closed = true end
    end)
end)
