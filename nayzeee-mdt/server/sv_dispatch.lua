-- ═══════════════════════════════════════════════════════════
--  DISPATCH
-- ═══════════════════════════════════════════════════════════

local panicCooldown  = {}   -- [identifier] = os.time()
local panicActive    = {}   -- [identifier] = { untilAt, last }
local backupCooldown = {}   -- [identifier] = os.time()

local function callType(id)
    for _, t in ipairs(Config.CallTypes) do
        if t.id == id then return t end
    end
    return nil
end

local function serialise(row, units)
    return {
        id        = row.id,
        ref       = row.ref,
        type      = row.type,
        title     = row.title,
        code      = row.code,
        priority  = row.priority,
        status    = row.status,
        street    = row.street,
        postal    = row.postal,
        x         = row.x, y = row.y, z = row.z,
        detail    = row.detail,
        caller    = row.caller,
        plate     = row.plate,
        closedBy  = row.closed_by,
        closedNote= row.closed_note,
        ageSeconds= row.age_seconds or 0,
        units     = units or {}
    }
end

local function unitsFor(ids)
    if #ids == 0 then return {} end
    local ph = string.rep('?,', #ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT dispatch_id, identifier, name, callsign, department, status FROM nz_mdt_dispatch_units WHERE dispatch_id IN (%s)'):format(ph),
        ids) or {}

    local byCall = {}
    for _, u in ipairs(rows) do
        byCall[u.dispatch_id] = byCall[u.dispatch_id] or {}
        table.insert(byCall[u.dispatch_id], {
            identifier = u.identifier, name = u.name,
            callsign = u.callsign, department = u.department, status = u.status
        })
    end
    return byCall
end

local function callDepartments(row)
    local d = MDT.decode(row and row.departments, nil)
    return type(d) == 'table' and #d > 0 and d or nil
end

--- The live board: open calls, newest first, priority-weighted.
function MDT.getBoard(session, includeClosed)
    local where = includeClosed and '1 = 1' or "status != 'closed'"
    local rows = MySQL.query.await(([[
        SELECT *, TIMESTAMPDIFF(SECOND, created_at, NOW()) AS age_seconds
        FROM nz_mdt_dispatch
        WHERE %s
        ORDER BY (status = 'closed') ASC, priority ASC, id DESC
        LIMIT ?
    ]]):format(where), { Config.Dispatch.maxActive }) or {}

    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.id end
    local units = unitsFor(ids)

    local out = {}
    for _, r in ipairs(rows) do
        -- only show a department the calls routed to it
        local depts = callDepartments(r)
        local visible = not session or not depts
        if not visible then
            for _, d in ipairs(depts) do
                if d == '*' or d == session.department then visible = true break end
            end
        end
        if visible then out[#out + 1] = serialise(r, units[r.id]) end
    end
    return out
end

lib.callback.register('nz_mdt:dispatch:board', MDT.guard('view.dispatch', function(session, includeClosed)
    return {
        ok       = true,
        calls    = MDT.getBoard(session, includeClosed == true),
        officers = MDT.activeOfficers()
    }
end))

-- ═══════════════════════════════════════════════════════════
--  CREATE
-- ═══════════════════════════════════════════════════════════
--- The one entry point every alert goes through — tablet, exports, panic and backup.
--- @param data table { type, title, detail, street, postal, x, y, z, caller, callerId, plate, priority, departments }
function MDT.createCall(data, session)
    if not Config.Dispatch.enabled then return nil, 'Dispatch is offline.' end

    local t = callType(data.type) or callType('other') or Config.CallTypes[1]
    local priority = tonumber(data.priority) or t.priority
    priority = math.max(1, math.min(3, math.floor(priority)))

    local departments = type(data.departments) == 'table' and #data.departments > 0 and data.departments
                        or Config.Dispatch.routing[t.group] or { '*' }

    local title = MDT.clean(data.title, 90)
    local id, ref = MDT.insertWithRef('nz_mdt_dispatch', Config.Dispatch.idPrefix, 4, [[
        INSERT INTO nz_mdt_dispatch
          (ref, type, title, code, priority, street, postal, x, y, z, detail, caller, caller_id, plate, departments)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        false, t.id,
        title ~= '' and title or t.label,
        t.code, priority,
        MDT.opt(data.street, 90), MDT.opt(data.postal, 12),
        tonumber(data.x), tonumber(data.y), tonumber(data.z),
        MDT.opt(data.detail, 500),
        MDT.opt(data.caller, 90), data.callerId,
        data.plate and MDT.opt(data.plate, 12) and MDT.clean(data.plate, 12):upper() or nil,
        json.encode(departments)
    })
    if not id then return nil, 'The call could not be saved.' end

    local row = MySQL.single.await('SELECT *, 0 AS age_seconds FROM nz_mdt_dispatch WHERE id = ?', { id })
    if not row then return nil, 'The call could not be saved.' end
    local call = serialise(row, {})

    -- the board on open tablets
    MDT.push('dispatch:new', call, departments)

    -- the in-game alert (blip, card, tone) for on-duty units
    for _, src in ipairs(MDT.sourcesFor(departments)) do
        TriggerClientEvent('nz_mdt:alert', src, {
            call     = call,
            blip     = t.blip,
            colour   = t.colour,
            sound    = Config.Dispatch.soundOnAlert,
            widget   = Config.Dispatch.widgetOnAlert,
            duration = Config.Dispatch.blipDuration,
            radius   = Config.Dispatch.blipRadius
        })
    end

    MDT.record(session, 'dispatch', 'dispatch.create', 'dispatch', ref,
        'Dispatch created', ('**%s** · %s at %s'):format(ref, call.title, call.street or 'unknown location'))

    return call
end

lib.callback.register('nz_mdt:dispatch:create', MDT.guard('dispatch.create', function(session, data)
    if type(data) ~= 'table' then return { ok = false, msg = 'Fill the call details in.' } end
    if MDT.clean(data.title, 90) == '' and not callType(data.type) then
        return { ok = false, msg = 'Pick a call type.' }
    end

    data.departments = nil   -- routing always comes from the call type for officer-made calls
    data.caller = MDT.opt(data.caller, 90) or session.name
    data.callerId = session.identifier
    local call, err = MDT.createCall(data, session)
    if not call then return { ok = false, msg = err or 'The call could not be created.' } end

    return { ok = true, msg = ('%s is on the board.'):format(call.ref), call = call }
end))

--- Backup request from the tablet: a priority call at the officer, for their department.
lib.callback.register('nz_mdt:dispatch:backup', function(src, data)
    local cfg = Config.Backup or {}
    if not cfg.enabled then return { ok = false, msg = 'Backup requests are switched off.' } end

    local session = MDT.getSession(src)
    if not session then return { ok = false, msg = 'You are not on a department roster.' } end
    if cfg.requirePerm and not session.perms['dispatch.create'] then
        return { ok = false, msg = 'Your rank does not allow that.' }
    end
    if type(data) ~= 'table' or type(data.x) ~= 'number' then return { ok = false, msg = 'Your position is unknown.' } end

    local last = backupCooldown[session.identifier]
    if last and os.time() - last < (cfg.cooldown or 20) then
        return { ok = false, msg = 'You just asked for backup — give units a moment.' }
    end
    backupCooldown[session.identifier] = os.time()

    local info = MDT.online[src]
    local sign = info and info.callsign or session.name
    local urgency = math.max(1, math.min(3, math.floor(tonumber(data.urgency) or 3)))
    local note = MDT.opt(data.note, 300)

    local call, err = MDT.createCall({
        type        = 'backup',
        title       = ('Backup requested — %s (Code %s)'):format(sign, urgency),
        detail      = note or ('%s is requesting Code %s backup.'):format(session.name, urgency),
        street      = data.street,
        x = data.x, y = data.y, z = data.z,
        caller      = session.name, callerId = session.identifier,
        priority    = urgency == 3 and 1 or urgency == 2 and 2 or 3,
        departments = { session.department }
    }, session)

    if not call then return { ok = false, msg = err or 'The request did not go out.' } end
    return { ok = true, msg = ('Backup requested — %s.'):format(call.ref), call = call }
end)

-- ═══════════════════════════════════════════════════════════
--  ASSIGN / DETACH / STATUS
-- ═══════════════════════════════════════════════════════════
local function refreshCall(id)
    local row = MySQL.single.await(
        'SELECT *, TIMESTAMPDIFF(SECOND, created_at, NOW()) AS age_seconds FROM nz_mdt_dispatch WHERE id = ?', { id })
    if not row then return nil end
    local units = unitsFor({ id })
    local call = serialise(row, units[id])
    MDT.broadcast('dispatch:update', call, callDepartments(row))
    return call
end

local function setOfficerStatus(session, status)
    MySQL.update('UPDATE nz_mdt_officers SET status = ? WHERE identifier = ?', { status, session.identifier })
    MDT.setStatus(session.identifier, status)
end

lib.callback.register('nz_mdt:dispatch:attach', MDT.guard('dispatch.assign', function(session, callId)
    callId = tonumber(callId)
    local call = MySQL.single.await('SELECT * FROM nz_mdt_dispatch WHERE id = ?', { callId })
    if not call then return { ok = false, msg = 'That call is no longer on the board.' } end
    if call.status == 'closed' then return { ok = false, msg = 'That call is already closed.' } end

    local already = MySQL.scalar.await('SELECT id FROM nz_mdt_dispatch_units WHERE dispatch_id = ? AND identifier = ?',
        { callId, session.identifier })
    if not already then
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_dispatch_units WHERE dispatch_id = ?', { callId }) or 0
        if count >= Config.Dispatch.maxUnitsPerCall then
            return { ok = false, msg = 'This call already has the maximum number of units.' }
        end
    end

    local info = MDT.online[session.source]
    MySQL.insert.await([[
        INSERT INTO nz_mdt_dispatch_units (dispatch_id, identifier, name, callsign, department, status)
        VALUES (?, ?, ?, ?, ?, 'enroute')
        ON DUPLICATE KEY UPDATE status = 'enroute', callsign = VALUES(callsign)
    ]], { callId, session.identifier, session.name, info and info.callsign or nil, session.department })

    if call.status == 'pending' then
        MySQL.update.await("UPDATE nz_mdt_dispatch SET status = 'assigned' WHERE id = ?", { callId })
    end

    setOfficerStatus(session, 'enroute')
    MDT.audit(session, 'dispatch.attach', 'dispatch', call.ref, 'Attached to the call')
    local updated = refreshCall(callId)
    MDT.push('roster:update', MDT.activeOfficers())

    return { ok = true, msg = ('You are en route to %s.'):format(call.ref), call = updated }
end))

lib.callback.register('nz_mdt:dispatch:detach', MDT.guard('dispatch.assign', function(session, callId)
    callId = tonumber(callId)
    MySQL.update.await('DELETE FROM nz_mdt_dispatch_units WHERE dispatch_id = ? AND identifier = ?',
        { callId, session.identifier })

    local left = MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_dispatch_units WHERE dispatch_id = ?', { callId }) or 0
    if left == 0 then
        MySQL.update.await("UPDATE nz_mdt_dispatch SET status = 'pending' WHERE id = ? AND status != 'closed'", { callId })
    end

    setOfficerStatus(session, 'available')
    local updated = refreshCall(callId)
    MDT.push('roster:update', MDT.activeOfficers())
    return { ok = true, msg = 'You are clear of the call.', call = updated }
end))

lib.callback.register('nz_mdt:dispatch:unitStatus', MDT.guard('dispatch.assign', function(session, callId, status)
    callId = tonumber(callId)
    local valid = false
    for _, s in ipairs(Config.UnitStatus) do if s.id == status then valid = true break end end
    if not valid then return { ok = false, msg = 'Unknown status.' } end

    local changed = MySQL.update.await(
        'UPDATE nz_mdt_dispatch_units SET status = ? WHERE dispatch_id = ? AND identifier = ?',
        { status, callId, session.identifier })
    if not changed or changed == 0 then return { ok = false, msg = 'Attach to the call first.' } end

    if status == 'onscene' then
        MySQL.update.await("UPDATE nz_mdt_dispatch SET status = 'onscene' WHERE id = ? AND status != 'closed'", { callId })
    end

    setOfficerStatus(session, status)
    local updated = refreshCall(callId)
    MDT.push('roster:update', MDT.activeOfficers())
    return { ok = true, call = updated }
end))

local function closeCall(row, closedBy, note, session)
    MySQL.update.await([[
        UPDATE nz_mdt_dispatch SET status = 'closed', closed_by = ?, closed_note = ?, closed_at = NOW()
        WHERE id = ?
    ]], { closedBy, MDT.opt(note, 250), row.id })

    -- free every unit that was on it
    local units = MySQL.query.await('SELECT identifier FROM nz_mdt_dispatch_units WHERE dispatch_id = ?', { row.id }) or {}
    MySQL.update.await("UPDATE nz_mdt_dispatch_units SET status = 'available' WHERE dispatch_id = ?", { row.id })
    for _, u in ipairs(units) do
        MySQL.update("UPDATE nz_mdt_officers SET status = 'available' WHERE identifier = ? AND on_duty = 1", { u.identifier })
        MDT.setStatus(u.identifier, 'available')
    end

    MDT.broadcast('dispatch:closed', { id = row.id, ref = row.ref }, callDepartments(row))
    if #units > 0 then MDT.push('roster:update', MDT.activeOfficers()) end
    MDT.record(session, 'dispatch', 'dispatch.close', 'dispatch', row.ref,
        'Dispatch closed', ('**%s** closed by %s%s'):format(row.ref, closedBy,
            note and note ~= '' and (' — ' .. MDT.clean(note, 120)) or ''))
end

lib.callback.register('nz_mdt:dispatch:close', MDT.guard('dispatch.close', function(session, callId, note)
    callId = tonumber(callId)
    local call = MySQL.single.await('SELECT * FROM nz_mdt_dispatch WHERE id = ?', { callId })
    if not call then return { ok = false, msg = 'That call is no longer on the board.' } end
    if call.status == 'closed' then return { ok = false, msg = 'That call is already closed.' } end

    closeCall(call, session.name, note, session)
    return { ok = true, msg = ('%s closed.'):format(call.ref) }
end))

lib.callback.register('nz_mdt:dispatch:waypoint', MDT.guard('view.dispatch', function(session, callId)
    local call = MySQL.single.await('SELECT ref, x, y, z FROM nz_mdt_dispatch WHERE id = ?', { tonumber(callId) })
    if not call or not call.x then return { ok = false, msg = 'No location was attached to that call.' } end

    TriggerClientEvent('nz_mdt:setWaypoint', session.source, call.x, call.y, call.z, call.ref)
    return { ok = true, msg = ('Route set to %s.'):format(call.ref) }
end))

-- ═══════════════════════════════════════════════════════════
--  PANIC
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('nz_mdt:panic', function(street, x, y, z)
    local src = source
    if not Config.Panic.enabled then return end

    local session = MDT.getSession(src)
    if not session then return end

    local last = panicCooldown[session.identifier]
    if last and (os.time() - last) < Config.Panic.cooldown then
        return MDT.notify(src, 'Panic button', 'Give it a moment before hitting it again.', 'error')
    end
    panicCooldown[session.identifier] = os.time()

    local info = MDT.online[src]
    local sign = info and info.callsign or session.name

    local payload = {
        identifier = session.identifier,
        name       = session.name,
        callsign   = sign,
        department = session.department,
        street     = type(street) == 'string' and street:sub(1, 64) or 'Unknown location',
        x = tonumber(x), y = tonumber(y), z = tonumber(z),
        duration   = Config.Panic.duration,
        follow     = Config.Panic.followOfficer,
        sound      = Config.Panic.sound
    }

    for _, target in ipairs(MDT.sourcesFor({ '*' })) do
        TriggerClientEvent('nz_mdt:panicAlert', target, payload)
    end
    -- off-duty viewers with the tablet open still see it on their board
    for viewer in pairs(MDT.viewers) do
        local v = MDT.online[viewer]
        if not v or not v.onDuty then TriggerClientEvent('nz_mdt:live', viewer, 'panic', payload) end
    end

    if Config.Panic.followOfficer then
        panicActive[session.identifier] = { untilAt = os.time() + (Config.Panic.duration or 120), last = 0 }
        TriggerClientEvent('nz_mdt:panicTrack', src, Config.Panic.duration or 120, Config.Panic.followSeconds or 3)
    end

    if Config.Panic.autoDispatch then
        MDT.createCall({
            type   = 'panic',
            title  = ('Panic button — %s'):format(sign),
            detail = ('%s activated their panic button.'):format(session.name),
            street = payload.street,
            x = payload.x, y = payload.y, z = payload.z,
            caller = session.name, callerId = session.identifier,
            priority = 1
        }, session)
    end

    MDT.record(session, 'panic', 'panic', 'officer', session.identifier,
        'Panic button', ('**%s** (%s) at %s'):format(session.name, sign, payload.street))
end)

--- The panicking officer keeps reporting where they are; relay it to every unit.
RegisterNetEvent('nz_mdt:panic:pos', function(x, y, z, street)
    local src = source
    local info = MDT.online[src]
    if not info or type(x) ~= 'number' or type(y) ~= 'number' then return end

    local active = panicActive[info.identifier]
    if not active then return end
    local now = os.time()
    if now > active.untilAt then panicActive[info.identifier] = nil return end
    if now - active.last < 1 then return end
    active.last = now

    street = type(street) == 'string' and street:sub(1, 64) or nil
    for _, target in ipairs(MDT.sourcesFor({ '*' })) do
        TriggerClientEvent('nz_mdt:panicMove', target, info.identifier, x, y, tonumber(z), street)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  AUTO-CLOSE SWEEP
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        Wait(120000)
        if Config.Dispatch.enabled and Config.Dispatch.autoCloseMinutes > 0 then
            local stale = MySQL.query.await([[
                SELECT * FROM nz_mdt_dispatch
                WHERE status = 'pending' AND created_at < DATE_SUB(NOW(), INTERVAL ? MINUTE)
            ]], { Config.Dispatch.autoCloseMinutes }) or {}

            for _, call in ipairs(stale) do
                closeCall(call, 'Dispatch', 'No units responded', nil)
            end
        end

        -- forget finished panics and old cooldowns
        local now = os.time()
        for id, p in pairs(panicActive) do if now > p.untilAt then panicActive[id] = nil end end
        for id, t in pairs(backupCooldown) do if now - t > 600 then backupCooldown[id] = nil end end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  LIVE MAP FEED
--  Open tablets get the full roster every few seconds. Units with
--  the tablet put away get a compact list for their map blips.
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    local fastEvery = math.max(2, Config.Map.updateSeconds or 4)
    local slowEvery = math.max(fastEvery, Config.Map.blipSeconds or 6)
    local lastSlow = 0

    while true do
        Wait(fastEvery * 1000)
        if Config.Map.enabled and next(MDT.online) then
            local officers = MDT.activeOfficers()

            if next(MDT.viewers) then MDT.push('map:officers', officers) end

            local now = os.time()
            if Config.Map.unitBlips and now - lastSlow >= slowEvery then
                lastSlow = now
                local compact = {}
                for _, o in ipairs(officers) do
                    if o.x then
                        compact[#compact + 1] = {
                            i = o.identifier, x = math.floor(o.x), y = math.floor(o.y), z = math.floor(o.z or 0),
                            n = o.callsign or o.name, s = o.status, d = o.department
                        }
                    end
                end
                for _, src in ipairs(MDT.sourcesFor({ '*' })) do
                    TriggerClientEvent('nz_mdt:units', src, compact)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  EXPORTS  — call these from robbery / heist / medical scripts
-- ═══════════════════════════════════════════════════════════
--- exports['nayzeee-mdt']:alert({ type='store', title='Store robbery', street='...', coords=vec3, plate='...' })
exports('alert', function(data)
    if type(data) ~= 'table' then return false end
    if data.coords then
        data.x, data.y, data.z = data.coords.x, data.coords.y, data.coords.z
    end
    local call = MDT.createCall(data, nil)
    return call and call.ref or false
end)

--- Legacy signature so existing scripts keep working:
---   CustomAlert(coords, title, job|group|type, blipSprite|blipData, priority)
exports('CustomAlert', function(coords, title, third, fourth, fifth)
    local data = {
        title = title,
        x = coords and coords.x, y = coords and coords.y, z = coords and coords.z
    }

    if type(third) == 'string' then
        if callType(third) then
            data.type = third
        elseif Config.Departments[third] then
            data.type = 'other'
            data.departments = { third }
        elseif Config.Dispatch.routing[third] then
            data.departments = Config.Dispatch.routing[third]
        end
    elseif type(third) == 'table' then
        data.departments = third
    end

    if type(fourth) == 'string' and callType(fourth) then data.type = fourth end
    if type(fifth) == 'number' then data.priority = fifth end

    local call = MDT.createCall(data, nil)
    return call and call.ref or false
end)

exports('closeCall', function(ref)
    local call = MySQL.single.await('SELECT * FROM nz_mdt_dispatch WHERE ref = ?', { ref })
    if not call or call.status == 'closed' then return false end
    closeCall(call, 'System', nil, nil)
    return true
end)

exports('activeCalls', function()
    return MDT.getBoard(nil, false)
end)

--- Fire a configured template with one line:
---   exports['nayzeee-mdt']:premade('store_robbery', { street = 'Grove St', coords = vec3 })
--- Anything passed in `over` replaces the template's own value.
function MDT.premade(name, over)
    local template = Config.Premade and Config.Premade[name]
    if not template then
        MDT.debug(('no premade dispatch called "%s"'):format(tostring(name)))
        return nil
    end

    over = type(over) == 'table' and over or {}

    local data = {
        type     = over.type     or template.type,
        title    = over.title    or template.title,
        detail   = over.detail   or template.detail,
        priority = over.priority or template.priority,
        street   = over.street,
        plate    = over.plate,
        caller   = over.caller or 'Automated report'
    }

    if over.coords then
        data.x, data.y, data.z = over.coords.x, over.coords.y, over.coords.z
    else
        data.x, data.y, data.z = over.x, over.y, over.z
    end

    local call = MDT.createCall(data, nil)
    return call and call.ref or nil
end

exports('premade', function(name, over)
    return MDT.premade(name, over)
end)

-- ═══════════════════════════════════════════════════════════
--  GUNSHOT REPORTS
-- ═══════════════════════════════════════════════════════════
local shotPlayer = {}   -- [src] = os.time()
local shotArea   = {}   -- ['gx:gy'] = os.time()

RegisterNetEvent('nz_mdt:alert:shotsFired', function(street, x, y, z)
    local cfg = Config.Alerts and Config.Alerts.shotsFired
    if not cfg or not cfg.enabled then return end

    local src = source
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    -- never alert on a department member firing
    if cfg.ignoreJobs and MDT.getDepartment(xPlayer.job.name) then return end

    -- the client says where it fired from; make sure that is where the player is
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and #(GetEntityCoords(ped) - vec3(x, y, tonumber(z) or 0.0)) > 150.0 then return end

    local now = os.time()
    if shotPlayer[src] and now - shotPlayer[src] < (cfg.cooldown or 900) then return end

    -- one report per block of the map, however many people are shooting there
    local cell = ('%d:%d'):format(math.floor(x / 150), math.floor(y / 150))
    if shotArea[cell] and now - shotArea[cell] < (cfg.areaCooldown or 90) then return end

    shotPlayer[src], shotArea[cell] = now, now

    MDT.premade('shots_fired', {
        street = MDT.clean(street, 90),
        caller = 'Automated gunshot detection',
        x = x, y = y, z = tonumber(z)
    })
end)

AddEventHandler('playerDropped', function()
    shotPlayer[source] = nil
end)
