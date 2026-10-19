--[[
    NAYZEEE AMBULANCE - Dispatch (server): client intents, callbacks, commands, pager item

    Every handler checks the source, rate limits, and permissions (on-duty medic through
    NZA.Staff, Config.Dispatch.board.assignPerm for dispatcher actions). Positions are
    always server-side.

    NET EVENTS (C→S)
      nza:dispatch:respond   (callId)            respond to a call (→ ENR)
      nza:dispatch:decline   (callId)            decline (shown on the board)
      nza:dispatch:clear     (callId?)           leave your call (closes it when you were the last unit on scene)
      nza:dispatch:closeCall (callId)            close a call (unit on it, or assignPerm)
      nza:dispatch:assign    (callId, targetSrc) assignPerm: send another unit
      nza:dispatch:unassign  (callId, targetSrc) assignPerm: take a unit off a call
      nza:dispatch:priority  (callId, 1..3)      assignPerm
      nza:dispatch:unitStatus ('10-8'|'10-7')    available / out of service
      nza:dispatch:pair      (bool)              pair the pager with your phone (needs the pager item)
      nza:dispatch:npc       (bool)              receive NPC calls (Player(src).state.nzaNpcCalls)
      nza:dispatch:duty      (bool)              go on / off duty from the job menu (medic job only)
      nza:dispatch:street    (callId, street, zone)  first medic client resolves street names
    CALLBACKS
      nza:dispatch:state  () → { calls, units, me, recent }
      nza:dispatch:board  () → NZA.Dispatch.Board(src)
      nza:dispatch:log    ({ limit, priority, search }) → rows | nil
      nza:dispatch:me     () → me
    NET EVENTS SENT
      nza:dispatch:pager ('toggle')              using the pager item
      nza:dispatch:sync  (payload)               full state (duty change, join)
    COMMANDS
      Config.Dispatch.player911.command  (/911 <message>)   → Bridge.CallEMS (cooldown there)
      Config.Dispatch.units.callsignCommand (/callsign <text>)
]]

if not NAYZEEE_LOCK_OK then return end

local function D() return NZA.Dispatch end
local function L(key, ...) return NZA.L(key, ...) end

local function valid(src)
    src = tonumber(src)
    return src and src > 0 and NZA.Core.Online(src) and src or nil
end

local function rate(src, bucket, limit, ms)
    return NZA.Core.Rate('dispatch:' .. bucket, src, limit, ms)
end

local function notify(src, kind, key, ...)
    NZA.Core.Notify(src, L(key, ...), kind, L('dispatch.title'))
end

local ERR = {
    no_call = 'dispatch.err_no_call', not_unit = 'dispatch.err_not_unit', full = 'dispatch.err_full',
    already = 'dispatch.err_already', not_on_call = 'dispatch.err_not_on_call', no_perm = 'dispatch.err_no_perm',
}

local function fail(src, err)
    notify(src, 'error', ERR[err] or 'dispatch.err_failed')
end

local function unitOf(src)
    return D().EnsureUnit(src)
end

local function canAssign(src)
    return NZA.Staff.Can(src, D().Cfg('board', 'assignPerm', 'manage'))
end

local function callId(v)
    if type(v) ~= 'string' or #v > 24 then return nil end
    return v
end

-- ════════════════════════════════════════════════════════════════════════
-- CALL ACTIONS
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:dispatch:respond', function(id)
    local src = valid(source)
    if not src or not rate(src, 'respond', 4, 3000) then return end
    id = callId(id)
    if not id then return end
    if not unitOf(src) then return fail(src, 'not_unit') end
    local ok, err = D().Respond(src, id)
    if not ok and err ~= 'already' then fail(src, err) end
end)

RegisterNetEvent('nza:dispatch:decline', function(id)
    local src = valid(source)
    if not src or not rate(src, 'decline', 6, 3000) then return end
    id = callId(id)
    if id and unitOf(src) then D().Decline(src, id) end
end)

RegisterNetEvent('nza:dispatch:clear', function(id)
    local src = valid(source)
    if not src or not rate(src, 'clear', 4, 3000) then return end
    if not unitOf(src) then return fail(src, 'not_unit') end
    id = callId(id)
    local ok, err = D().Clear(src, id, 'cleared')
    if ok then notify(src, 'info', 'dispatch.cleared') else fail(src, err) end
end)

RegisterNetEvent('nza:dispatch:closeCall', function(id)
    local src = valid(source)
    if not src or not rate(src, 'close', 4, 3000) then return end
    id = callId(id)
    local c = id and D().Get(id)
    if not c then return fail(src, 'no_call') end
    if not (c.units[src] or canAssign(src)) then return fail(src, 'no_perm') end
    D().Close(id, 'closed')
    notify(src, 'success', 'dispatch.closed_by_you', id)
end)

RegisterNetEvent('nza:dispatch:assign', function(id, target)
    local src = valid(source)
    if not src or not rate(src, 'assign', 6, 3000) then return end
    if not canAssign(src) then return fail(src, 'no_perm') end
    id, target = callId(id), tonumber(target)
    if not id or not target then return end
    local ok, err = D().Assign(id, target, src)
    if ok then
        notify(src, 'success', 'dispatch.assigned_ok', D().UnitLabel(target) or ('#' .. target), id)
    else
        fail(src, err)
    end
end)

RegisterNetEvent('nza:dispatch:unassign', function(id, target)
    local src = valid(source)
    if not src or not rate(src, 'assign', 6, 3000) then return end
    id, target = callId(id), tonumber(target)
    if not id or not target then return end
    if target ~= src and not canAssign(src) then return fail(src, 'no_perm') end
    local ok, err = D().Clear(target, id, 'unassigned')
    if not ok then return fail(src, err) end
    if target ~= src then notify(target, 'warning', 'dispatch.unassigned_you', id) end
end)

RegisterNetEvent('nza:dispatch:priority', function(id, prio)
    local src = valid(source)
    if not src or not rate(src, 'prio', 6, 3000) then return end
    if not canAssign(src) then return fail(src, 'no_perm') end
    id, prio = callId(id), tonumber(prio)
    if not id or not prio or prio < 1 or prio > 3 then return end
    if not D().Update(id, { priority = math.floor(prio) }) then fail(src, 'no_call') end
end)

RegisterNetEvent('nza:dispatch:street', function(id, street, zone)
    local src = valid(source)
    if not src or not rate(src, 'street', 10, 5000) then return end
    id = callId(id)
    local c = id and D().Get(id)
    if not c or c.street then return end
    local rec = NZA.Staff.Get(src)
    if not (rec and rec.medic) and c.callerSrc ~= src then return end
    -- the reporting client must be somewhere near the map: street names are only sane for real coords
    street, zone = D().Str(street, 80), D().Str(zone, 64)
    if not street then return end
    D().Update(id, { street = street, zone = zone or c.zone })
end)

-- ════════════════════════════════════════════════════════════════════════
-- UNIT
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:dispatch:unitStatus', function(code)
    local src = valid(source)
    if not src or not rate(src, 'status', 4, 3000) then return end
    if not unitOf(src) then return fail(src, 'not_unit') end
    if code == '10-7' then
        D().SetOutOfService(src, true)
        notify(src, 'info', 'dispatch.status_oos')
    elseif code == '10-8' then
        D().SetOutOfService(src, false)
        notify(src, 'success', 'dispatch.status_available')
    end
end)

local function hasPager(src)
    if not D().Cfg('pager', 'requireItem', true) then return true end
    local item = Config.Items and Config.Items.pager
    if not item then return true end
    return NZA.Core.B('Inv.HasItem', src, item, 1) == true
end

RegisterNetEvent('nza:dispatch:pair', function(on)
    local src = valid(source)
    if not src or not rate(src, 'pair', 3, 3000) then return end
    if D().PhoneMode() ~= 'paired' then return end
    on = on == true
    if on then
        if D().Cfg('phone', 'linkNeedsPager', true) ~= false and not hasPager(src) then return notify(src, 'error', 'dispatch.err_no_pager') end
        local phoneRes = Bridge and Bridge.Phone and Bridge.Phone.Resource
        if not phoneRes then return notify(src, 'error', 'dispatch.err_no_phone') end
    end
    D().SetPaired(src, on)
    D().SendMe(src)
    notify(src, on and 'success' or 'info', on and 'dispatch.paired' or 'dispatch.unpaired')
    if on and Bridge.Phone.Notify then
        pcall(Bridge.Phone.Notify, src, { title = L('dispatch.title'), message = L('dispatch.paired_phone'), icon = 'pager' })
    end
end)

RegisterNetEvent('nza:dispatch:npc', function(on)
    local src = valid(source)
    if not src or not rate(src, 'npc', 4, 3000) then return end
    if not unitOf(src) then return fail(src, 'not_unit') end
    D().SetNpcCalls(src, on == true)
    D().SendMe(src)
    notify(src, on and 'success' or 'info', on and 'dispatch.npc_on' or 'dispatch.npc_off')
end)

local function nearDutyPoint(src, maxDist)
    if not maxDist then return true end
    if not (NZA.Hospitals and NZA.Hospitals.Points) then return true end
    local ok, points = pcall(NZA.Hospitals.Points, 'duty')
    if not ok or type(points) ~= 'table' or next(points) == nil then return true end
    local a = NZA.Core.SrcCoords(src)
    if not a then return false end
    for _, pt in pairs(points) do
        local c = NZA.Util.vec(pt.coords)
        if c and #(c - a) <= maxDist then return true end
    end
    return false
end

RegisterNetEvent('nza:dispatch:duty', function(on)
    local src = valid(source)
    if not src or not rate(src, 'duty', 2, 4000) then return end
    if not D().Cfg('radial', 'dutyToggle', true) then return end
    if not NZA.Core.B('IsMedic', src) then return notify(src, 'error', 'dispatch.err_not_medic') end
    local maxDist = tonumber(D().Cfg('radial', 'dutyPointDistance', false))
    if not nearDutyPoint(src, maxDist) then return notify(src, 'error', 'dispatch.err_duty_point') end
    on = on == true
    local ok = NZA.Core.B('SetDuty', src, on)
    if not ok then return notify(src, 'error', 'dispatch.err_duty') end
    SetTimeout(300, function()
        NZA.Staff.Refresh(src, true)
        notify(src, on and 'success' or 'info', on and 'dispatch.duty_on' or 'dispatch.duty_off')
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:dispatch:state', function(source)
    local src = valid(source)
    if not src or not rate(src, 'state', 6, 5000) then return nil end
    return D().SyncPayload(src)
end)

lib.callback.register('nza:dispatch:me', function(source)
    local src = valid(source)
    if not src or not rate(src, 'me', 10, 5000) then return nil end
    return D().Me(src)
end)

lib.callback.register('nza:dispatch:board', function(source)
    local src = valid(source)
    if not src or not rate(src, 'board', 4, 2000) then return nil end
    if not D().IsOnDutyMedic(src) and not canAssign(src) then return nil end
    D().EnsureUnit(src)
    return D().Board(src)
end)

lib.callback.register('nza:dispatch:log', function(source, opts)
    local src = valid(source)
    if not src or not rate(src, 'log', 4, 4000) then return nil end
    if not D().IsOnDutyMedic(src) and not canAssign(src) then return nil end
    opts = type(opts) == 'table' and opts or {}
    local rows = NZA.DispatchLog and NZA.DispatchLog.Recent({
        limit = math.min(tonumber(opts.limit) or D().Cfg('board', 'logLimit', 60), 200),
        priority = opts.priority, search = type(opts.search) == 'string' and opts.search or nil,
    })
    if rows then return { rows = rows, db = true } end
    -- no database: the in-memory list of this session
    return { rows = D().Recent(), db = false }
end)

-- ════════════════════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)
    local p911 = Config.Dispatch.player911 or {}
    if p911.enabled ~= false and type(p911.command) == 'string' and p911.command ~= '' then
        RegisterCommand(p911.command, function(source, args)
            local src = valid(source)
            if not src then return end
            if not rate(src, '911', 2, 5000) then return end
            local msg = D().Str(table.concat(args or {}, ' '), tonumber(p911.maxLength) or 200)
            if not msg or #msg < (tonumber(p911.minLength) or 3) then
                return notify(src, 'error', 'dispatch.911_usage', p911.command)
            end
            if Bridge and Bridge.CallEMS then
                local ok, res = Bridge.CallEMS(src, msg, nil, { via = '911' })
                if not ok and res ~= 'cooldown' then notify(src, 'error', 'dispatch.911_failed') end
                return
            end
            -- no bridge phone layer: create the call directly
            local p = NZA.Patients.GetBySource(src)
            local id = D().Create({
                code = '10-52', priority = (p and p.state ~= 'alive') and 1 or 2, title = L('dispatch.911_title'), type = 'call',
                coords = NZA.Core.SrcCoords(src), caller = NZA.Core.Name(src), callerSrc = src, message = msg,
                patients = (p and p.state ~= 'alive') and { p.pid } or {}, source = 'player', via = '911',
            })
            notify(src, id and 'success' or 'error', id and 'dispatch.911_sent' or 'dispatch.911_failed')
        end, false)
    end

    local cs = Config.Dispatch.units and Config.Dispatch.units.callsignCommand
    if type(cs) == 'string' and cs ~= '' then
        RegisterCommand(cs, function(source, args)
            local src = valid(source)
            if not src or not rate(src, 'callsign', 2, 5000) then return end
            local rec = NZA.Staff.Get(src)
            if not (rec and rec.medic) then return notify(src, 'error', 'dispatch.err_not_medic') end
            local ok, text = D().SetCallsign(src, table.concat(args or {}, ' '))
            if ok then notify(src, 'success', 'dispatch.callsign_set', text) else notify(src, 'error', 'dispatch.callsign_usage', cs) end
        end, false)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PAGER ITEM
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1500)
    if not D().Cfg('pager', 'enabled', true) then return end
    local item = Config.Items and Config.Items.pager
    if not item or not (Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function') then return end
    local ok, err = pcall(Bridge.Inv.RegisterUsable, item, function(src)
        src = valid(src)
        if src then TriggerClientEvent('nza:dispatch:pager', src, 'toggle') end
    end)
    if not ok then NZA.Warn('dispatch: could not register the pager item: ' .. tostring(err)) end
end)

-- resource restart while players are on duty: push the state once everything is up
CreateThread(function()
    Wait(2500)
    for _, src in ipairs(NZA.Staff.OnDuty()) do
        if NZA.Core.Online(src) then
            D().EnsureUnit(src)
            TriggerClientEvent('nza:dispatch:sync', src, D().SyncPayload(src))
        end
    end
end)
