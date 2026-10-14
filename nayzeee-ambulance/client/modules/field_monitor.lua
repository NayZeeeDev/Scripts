--[[
    NAYZEEE AMBULANCE - Patient monitor (client): the 'monitor' NUI overlay, its live data and
    the monitor prop beside the patient (with a live DUI screen)

      NZA.Monitor.Open(target, opts)     show the overlay bound to a patient (no NUI focus)
          opts = { compact, position = 'tl'|'tr'|'bl'|'br', label, nibpAuto, keep } (keep = no distance close)
      NZA.Monitor.Close()                hide the overlay (stops the live data)
      NZA.Monitor.Attach(entity, target, { silent, scene })   NZA.Treat 'monitor' → prop + overlay
      NZA.Monitor.Detach()               NZA.Treat 'monitor_off' → removes prop + overlay
      NZA.Monitor.AttachedTo(entity) → bool     NZA.Monitor.Target() → target | nil
      NZA.Monitor.Override(map)          { map, sys, dia } | nil  (field resuscitate pressure model)
      NZA.Monitor.Nibp()                 cycle the cuff now      NZA.Monitor.Focus(on)   mouse on the buttons

    Other modules (bay, bed, CPR, intubation) may also open the app directly:
        NZA.UI.Open('monitor', { target = target, compact = true }, { focus = false })
    The app then posts 'monitor:bind' and this file streams NZA.Patient.Watch data to it.

    NUI callbacks: monitor:bind { target }  monitor:unbind {}  monitor:nibp { sys, dia, map }
    Command / key: Config.Field.Monitor.command / focusKey (mouse on the monitor buttons).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Monitor = NZA.Monitor or {}
NZA.Field = NZA.Field or {}
local M = NZA.Monitor
local F = NZA.Field
local APP = 'monitor'

local function cfg() return (Config.Field or {}).Monitor or {} end
local function L(key, ...) return NZA.L('field.' .. key, ...) end

local bound = nil     -- { target, stop, pid }
local attached = nil  -- { entity, target, prop, pos, scene }
local focused = false
local dui = nil       -- { obj, txd, tex, last }
local lastVitals = nil

-- ════════════════════════════════════════════════════════════════════════
-- LIVE DATA
-- ════════════════════════════════════════════════════════════════════════

local function vitalsOf(snap)
    local v = snap.vitals or {}
    return {
        hr = v.hr, ecgRate = v.ecgRate or v.hr, spo2 = v.spo2, sys = v.sys, dia = v.dia, map = v.map, rr = v.rr,
        temp = v.temp, etco2 = v.etco2, rhythm = v.rhythm or 'sinus', state = snap.state, name = snap.name,
    }
end

local function duiPush(v)
    if not dui or not dui.obj then return end
    SendDuiMessage(dui.obj, json.encode({ vitals = v }))
end

local function unbind()
    if bound and bound.stop then pcall(bound.stop) end
    bound = nil
end

local function bind(target)
    unbind()
    if type(target) ~= 'table' then return false end
    local b = { target = target }
    bound = b
    local opts = { keep = true }
    local ok, stop = pcall(NZA.Patient.Watch, target, function(snap, reason)
        if bound ~= b then return end
        if not snap then
            if reason == 'gone' or reason == 'removed' or reason == 'denied' then
                NZA.UI.Send(APP, 'standby', { on = true })
            end
            return
        end
        b.pid = snap.pid
        local v = vitalsOf(snap)
        lastVitals = v
        NZA.UI.Send(APP, 'vitals', v)
        duiPush(v)
    end, opts)
    if ok then b.stop = stop end
    return ok
end

NZA.UI.On(APP, 'bind', function(data, cb)
    cb({ ok = bind(type(data) == 'table' and data.target or nil) })
    NZA.UI.Send(APP, 'locale', NZA.LocaleTable('field'))
end)

NZA.UI.On(APP, 'unbind', function(_, cb)
    unbind()
    cb({ ok = true })
end)

NZA.UI.On(APP, 'nibp', function(data, cb)
    if dui and dui.obj and type(data) == 'table' then SendDuiMessage(dui.obj, json.encode({ nibp = data })) end
    cb({ ok = true })
end)

NZA.Bus.On('ui:closed', function(app)
    if app == APP then unbind() end
end)

-- ════════════════════════════════════════════════════════════════════════
-- OVERLAY
-- ════════════════════════════════════════════════════════════════════════

function M.Open(target, opts)
    opts = opts or {}
    local c = cfg()
    local data = {
        target = target, compact = opts.compact == true, position = opts.position or c.position or 'tl',
        label = opts.label, nibpAuto = opts.nibpAuto or c.nibpAuto or 60, nibpTime = c.nibpTime or 4,
        alarms = c.alarms ~= false, silence = c.silence or 120, beep = c.beep ~= false,
        locale = NZA.LocaleTable('field'),
    }
    NZA.UI.Open(APP, data, { focus = false, cursor = false })
    return true
end

function M.Close()
    unbind()
    focused = false
    return NZA.UI.Close(APP)
end

function M.Override(o)
    NZA.UI.Send(APP, 'override', o or false)
    if dui and dui.obj then SendDuiMessage(dui.obj, json.encode({ override = o or false })) end
end

function M.Nibp() NZA.UI.Send(APP, 'nibp', {}) end

function M.Target() return bound and bound.target or nil end

function M.Focus(on)
    if not NZA.UI.IsOpen(APP) then return false end
    focused = on and true or false
    NZA.UI.SetFocus(APP, { focus = focused, cursor = focused })
    return focused
end

-- ════════════════════════════════════════════════════════════════════════
-- PROP + DUI SCREEN
-- ════════════════════════════════════════════════════════════════════════

local function stopDui()
    if not dui then return end
    if dui.txd and dui.tex then pcall(RemoveReplaceTexture, dui.txd, dui.tex) end
    if dui.obj then pcall(DestroyDui, dui.obj) end
    dui = nil
end

local function startDui()
    stopDui()
    if cfg().screen == false then return end
    local scr = Config.PropScreens and Config.PropScreens.monitor
    if not scr or not scr.txd or not scr.tex then return end
    local url = ('nui://%s/html/apps/monitor/screen.html'):format(GetCurrentResourceName())
    local ok, obj = pcall(CreateDui, url, 512, 256)
    if not ok or not obj then return end
    local rtxd = CreateRuntimeTxd('nza_field_monitor')
    CreateRuntimeTextureFromDuiHandle(rtxd, 'screen', GetDuiHandle(obj))
    AddReplaceTexture(scr.txd, scr.tex, 'nza_field_monitor', 'screen')
    dui = { obj = obj, txd = scr.txd, tex = scr.tex }
    SetTimeout(1200, function()
        if dui and dui.obj == obj and lastVitals then
            SendDuiMessage(obj, json.encode({ vitals = lastVitals, name = lastVitals.name, locale = NZA.LocaleTable('field') }))
        end
    end)
end

local function placeProp(entity)
    if cfg().prop == false then return 0 end
    local frame = F.Frame(entity)
    local pl = cfg().place or { side = 0.62, along = 0.82 }
    local pos = F.Spot(frame, pl.side or 0.62, pl.along or 0.82)
    local face = vector3(-frame.side.x, -frame.side.y, 0.0)   -- screen toward the medic
    local ok, ent = pcall(NZA.Props.Spawn, 'monitor', vector3(pos.x, pos.y, pos.z), { group = 'field_monitor', heading = F.HeadingY(face), collision = false })
    if not ok or not ent or ent == 0 then return 0 end
    PlaceObjectOnGroundProperly(ent)
    FreezeEntityPosition(ent, true)
    return ent
end

local function clearProp()
    if attached and attached.prop and attached.prop ~= 0 then NZA.Props.Delete(attached.prop) end
    if attached then attached.prop = 0 end
    stopDui()
end

-- ════════════════════════════════════════════════════════════════════════
-- ATTACH / DETACH
-- ════════════════════════════════════════════════════════════════════════

function M.AttachedTo(entity)
    if not attached then return false end
    if not entity then return true end
    local t = NZA.Target.FromEntity(entity)
    return t ~= nil and NZA.Target.Same(t, attached.target)
end

function M.Attach(entity, target, opts)
    opts = opts or {}
    target = target or (entity and NZA.Target.FromEntity(entity))
    if not target then return false end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    if not entity or entity == 0 then return false end
    if attached and NZA.Target.Same(attached.target, target) then
        if not NZA.UI.IsOpen(APP) then M.Open(target, opts) end
        return true
    end
    if attached then M.Detach(true) end
    local ok, res = NZA.Treat.Do('monitor', target, {}, { silent = opts.silent == true })
    if not ok then return false end
    attached = { entity = entity, target = target, prop = 0, scene = opts.scene }
    if not (type(res) == 'table' and res.shared) then
        attached.prop = placeProp(entity)
        if attached.prop ~= 0 then attached.pos = GetEntityCoords(entity); startDui() end
    end
    M.Open(target, opts)
    return true
end

function M.Detach(quiet)
    local a = attached
    if not a then M.Close() return false end
    attached = nil
    if a.prop and a.prop ~= 0 then NZA.Props.Delete(a.prop) end
    stopDui()
    M.Close()
    if not quiet then NZA.Treat.Do('monitor_off', a.target, {}, { silent = true }) end
    return true
end

-- keep the overlay with the patient: hide it far away, show it again when back; the prop
-- goes with the patient (picked up when they are moved)
CreateThread(function()
    while true do
        Wait(attached and 750 or 1500)
        local a = attached
        if a then
            local ent = NZA.Target.Entity(a.target)
            if ent == 0 then
                M.Detach(true)
            else
                local st = NZA.Target.State(a.target)
                local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ent))
                local range = cfg().range or 12.0
                if type(st) == 'table' and st.st == 'dead' then
                    M.Detach()
                elseif d > range and NZA.UI.IsOpen(APP) and not a.scene then
                    M.Close()
                elseif d <= range - 1.0 and not NZA.UI.IsOpen(APP) then
                    M.Open(a.target)
                end
                if a.prop and a.prop ~= 0 and a.pos and #(GetEntityCoords(ent) - a.pos) > 3.0 then clearProp() end
                if d > range * 3 then M.Detach() end
            end
        end
    end
end)

-- leaving duty / going down ends it
NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and attached then M.Detach(true) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- MOUSE ON THE MONITOR BUTTONS (key / command)
-- ════════════════════════════════════════════════════════════════════════

do
    local c = cfg()
    local function toggle()
        if not NZA.UI.IsOpen(APP) then return end
        local top = NZA.UI.Top and NZA.UI.Top()
        if top and top ~= APP and not focused then return end   -- another app owns the mouse
        M.Focus(not focused)
    end
    if c.command then RegisterCommand(c.command, toggle, false) end
    if c.focusKey and c.command then
        RegisterKeyMapping(c.command, L('key_monitor'), 'keyboard', c.focusKey)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopDui()
    unbind()
    if NZA.Props and NZA.Props.Clear then NZA.Props.Clear('field_monitor') end
end)
