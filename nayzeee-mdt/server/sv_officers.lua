-- ═══════════════════════════════════════════════════════════
--  OFFICERS · DUTY · ANNOUNCEMENTS · NOTES
-- ═══════════════════════════════════════════════════════════

-- ── duty ────────────────────────────────────────────────────
function MDT.clockIn(session)
    local now = os.time()
    MySQL.update.await([[
        UPDATE nz_mdt_officers SET on_duty = 1, status = 'available', last_on = ? WHERE identifier = ?
    ]], { now, session.identifier })

    local info = MDT.online[session.source]
    if info then
        info.onDuty, info.status, info.lastOn = true, 'available', now
    end

    if Config.Duty.announce then
        for _, src in ipairs(MDT.sourcesFor({ session.department })) do
            if src ~= session.source then
                MDT.notify(src, 'Roster', ('%s is on duty.'):format(session.name), 'inform')
            end
        end
    end

    MDT.push('roster:update', MDT.activeOfficers())
    MDT.record(session, 'duty', 'duty.on', 'officer', session.identifier,
        'On duty', ('**%s** clocked in'):format(session.name))
end

function MDT.clockOut(identifier, silent)
    local officer = MDT.getOfficer(identifier)
    if not officer or not MDT.bool(officer.on_duty) then return end

    local worked = officer.last_on and math.max(0, os.time() - officer.last_on) or 0
    MySQL.update.await([[
        UPDATE nz_mdt_officers SET on_duty = 0, status = 'break', duty_seconds = duty_seconds + ?, last_on = NULL
        WHERE identifier = ?
    ]], { Config.Duty.trackTime and worked or 0, identifier })

    -- drop them from any open calls, and put calls nobody is on back to pending
    local calls = MySQL.query.await([[
        SELECT u.dispatch_id FROM nz_mdt_dispatch_units u
        JOIN nz_mdt_dispatch d ON d.id = u.dispatch_id
        WHERE u.identifier = ? AND d.status != 'closed'
    ]], { identifier }) or {}

    if #calls > 0 then
        MySQL.update.await([[
            DELETE u FROM nz_mdt_dispatch_units u
            JOIN nz_mdt_dispatch d ON d.id = u.dispatch_id
            WHERE u.identifier = ? AND d.status != 'closed'
        ]], { identifier })
        for _, c in ipairs(calls) do
            MySQL.update.await([[
                UPDATE nz_mdt_dispatch SET status = 'pending'
                WHERE id = ? AND status != 'closed'
                  AND NOT EXISTS (SELECT 1 FROM nz_mdt_dispatch_units WHERE dispatch_id = ?)
            ]], { c.dispatch_id, c.dispatch_id })
        end
    end

    MDT.positions[identifier] = nil

    for _, info in pairs(MDT.online) do
        if info.identifier == identifier then info.onDuty, info.status, info.lastOn = false, 'break', nil end
    end

    if not silent then MDT.push('roster:update', MDT.activeOfficers()) end
end

local function toggleDuty(src, session)
    local officer = MDT.ensureOfficer(session)
    if MDT.bool(officer.on_duty) then
        MDT.clockOut(session.identifier)
        MDT.record(session, 'duty', 'duty.off', 'officer', session.identifier,
            'Off duty', ('**%s** clocked out'):format(session.name))
        TriggerClientEvent('nz_mdt:dutyChanged', src, false, 'break')
        return false
    end

    MDT.clockIn(session)
    TriggerClientEvent('nz_mdt:dutyChanged', src, true, 'available')
    return true
end

lib.callback.register('nz_mdt:duty:toggle', function(src)
    local session = MDT.getSession(src)
    if not session then return { ok = false, msg = 'You are not on a department roster.' } end
    if not MDT.online[src] then return { ok = false, msg = 'Give the roster a second to load you in.' } end

    local onDuty = toggleDuty(src, session)
    return { ok = true, onDuty = onDuty, msg = onDuty and 'You are on duty.' or 'You are off duty.' }
end)

lib.callback.register('nz_mdt:duty:status', function(src, status)
    local session = MDT.getSession(src)
    if not session then return { ok = false } end

    local info = MDT.online[src]
    if not info or not info.onDuty then return { ok = false, msg = 'Clock on duty first.' } end

    local label
    for _, s in ipairs(Config.UnitStatus) do if s.id == status then label = s.label break end end
    if not label then return { ok = false, msg = 'Unknown status.' } end

    MySQL.update.await('UPDATE nz_mdt_officers SET status = ? WHERE identifier = ?', { status, session.identifier })
    info.status = status
    MDT.push('roster:update', MDT.activeOfficers())
    return { ok = true, msg = ('Status set to %s.'):format(label) }
end)

RegisterCommand(Config.Duty.command, function(src)
    if src == 0 then return end
    local session = MDT.getSession(src)
    if not session then return MDT.notify(src, 'Duty', 'You are not on a department roster.', 'error') end
    if not MDT.online[src] then return MDT.notify(src, 'Duty', 'Give the roster a second to load you in.', 'error') end

    if toggleDuty(src, session) then
        MDT.notify(src, 'Duty', 'You are on duty.', 'success')
    else
        MDT.notify(src, 'Duty', 'You are off duty.', 'inform')
    end
end, false)

-- ── callsign ────────────────────────────────────────────────
local function cleanCallsign(value)
    return (MDT.clean(value, 12):upper():gsub('[^%w%-]', ''))
end

lib.callback.register('nz_mdt:officer:callsign', MDT.guard('officer.callsign', function(session, callsign)
    callsign = cleanCallsign(callsign)
    if #callsign < 2 then return { ok = false, msg = 'Use at least two characters.' } end

    local taken = MySQL.scalar.await(
        'SELECT identifier FROM nz_mdt_officers WHERE callsign = ? AND identifier != ?',
        { callsign, session.identifier })
    if taken then return { ok = false, msg = 'Another unit already runs that callsign.' } end

    MySQL.update.await('UPDATE nz_mdt_officers SET callsign = ? WHERE identifier = ?',
        { callsign, session.identifier })
    if MDT.online[session.source] then MDT.online[session.source].callsign = callsign end

    MDT.push('roster:update', MDT.activeOfficers())
    MDT.audit(session, 'officer.callsign', 'officer', session.identifier, 'Callsign set to ' .. callsign)

    return { ok = true, msg = ('Callsign set to %s.'):format(callsign), callsign = callsign }
end))

-- ── roster ──────────────────────────────────────────────────
lib.callback.register('nz_mdt:officer:roster', MDT.guard('view.officer', function(session, search, onlyOnDuty)
    search = MDT.clean(search, 32)
    local args, where = {}, { '1 = 1' }

    if search ~= '' then
        where[#where + 1] = '(name LIKE ? OR callsign LIKE ? OR badge LIKE ?)'
        for _ = 1, 3 do args[#args + 1] = '%' .. search .. '%' end
    end
    if onlyOnDuty == true then where[#where + 1] = 'on_duty = 1' end

    local rows = MySQL.query.await(([[
        SELECT identifier, name, department, rank, badge, callsign, on_duty, status, duty_seconds, last_on
        FROM nz_mdt_officers WHERE %s ORDER BY on_duty DESC, name ASC LIMIT 100
    ]]):format(table.concat(where, ' AND ')), args) or {}

    local now = os.time()
    for _, o in ipairs(rows) do
        o.onDuty = MDT.bool(o.on_duty)
        local live = MDT.bool(o.on_duty) and o.last_on and (now - o.last_on) or 0
        o.shiftMinutes = math.floor(live / 60)
        o.totalHours = math.floor(((o.duty_seconds or 0) + live) / 3600)
        local pos = MDT.positions[o.identifier]
        o.street = pos and pos.street or nil
        o.x, o.y = pos and pos.x or nil, pos and pos.y or nil
        o.last_on, o.on_duty = nil, nil
    end

    return { ok = true, rows = rows }
end))

lib.callback.register('nz_mdt:officer:update', MDT.guard('officer.manage', function(session, identifier, patch)
    if type(patch) ~= 'table' then return { ok = false, msg = 'Nothing to change.' } end

    local officer = MDT.getOfficer(identifier)
    if not officer then return { ok = false, msg = 'That officer is not on file.' } end

    local src, info = MDT.onlineBy(identifier)
    local sets, args = {}, {}

    local badge = MDT.opt(patch.badge, 20)
    if badge then sets[#sets + 1] = 'badge = ?'; args[#args + 1] = badge end

    if patch.callsign ~= nil then
        local sign = cleanCallsign(patch.callsign)
        if #sign >= 2 then
            if MySQL.scalar.await('SELECT identifier FROM nz_mdt_officers WHERE callsign = ? AND identifier != ?', { sign, identifier }) then
                return { ok = false, msg = 'Another unit already runs that callsign.' }
            end
            sets[#sets + 1] = 'callsign = ?'; args[#args + 1] = sign
            if info then info.callsign = sign end
        end
    end

    if patch.status then
        local valid = false
        for _, s in ipairs(Config.UnitStatus) do if s.id == patch.status then valid = true break end end
        if valid then
            sets[#sets + 1] = 'status = ?'; args[#args + 1] = patch.status
            if info then info.status = patch.status end
        end
    end

    if #sets > 0 then
        args[#args + 1] = identifier
        MySQL.update.await(('UPDATE nz_mdt_officers SET %s WHERE identifier = ?'):format(table.concat(sets, ', ')), args)
    end

    -- clocking someone out goes through the normal path so their shift is banked
    if patch.onDuty == false and MDT.bool(officer.on_duty) then
        MDT.clockOut(identifier)
        if src then
            TriggerClientEvent('nz_mdt:dutyChanged', src, false, 'break')
            MDT.notify(src, 'Duty', ('%s clocked you out.'):format(session.name), 'inform')
        end
    elseif #sets == 0 then
        return { ok = false, msg = 'Nothing to change.' }
    end

    MDT.push('roster:update', MDT.activeOfficers())
    MDT.audit(session, 'officer.update', 'officer', identifier, 'Officer record edited')
    return { ok = true, msg = 'Officer record updated.' }
end))

-- ── announcements ───────────────────────────────────────────
lib.callback.register('nz_mdt:announce:list', MDT.guard('view.announcement', function(session)
    local rows = MySQL.query.await([[
        SELECT id, title, body, pinned, department, author,
               DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
        FROM nz_mdt_announcements
        WHERE (department IS NULL OR department = ?)
          AND (expires_at IS NULL OR expires_at > ?)
        ORDER BY pinned DESC, id DESC LIMIT 40
    ]], { session.department, os.time() }) or {}
    return { ok = true, rows = rows }
end))

lib.callback.register('nz_mdt:announce:create', MDT.guard('announcement.create', function(session, data)
    local title = MDT.clean(data and data.title, 90)
    local body  = MDT.clean(data and data.body, 1200)
    if #title < 3 or #body < 3 then return { ok = false, msg = 'Give it a title and a body.' } end

    -- keep the board from silting up
    local live = MySQL.scalar.await([[
        SELECT COUNT(*) FROM nz_mdt_announcements
        WHERE (department IS NULL OR department = ?) AND (expires_at IS NULL OR expires_at > ?)
    ]], { session.department, os.time() }) or 0

    if live >= (Config.Announcement and Config.Announcement.maxActive or 20) then
        return { ok = false, msg = 'The bulletin board is full. Remove an old one first.' }
    end

    local days = tonumber(data.expireDays)
    if days == nil then days = Config.Announcement and Config.Announcement.expireDays or 0 end
    days = math.max(0, math.min(365, math.floor(days)))
    local expires = days > 0 and (os.time() + days * 86400) or nil
    local everyone = data.allDepartments == true

    MySQL.insert.await([[
        INSERT INTO nz_mdt_announcements (title, body, pinned, department, author, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { title, body, data.pinned and 1 or 0, (not everyone) and session.department or nil, session.name, expires })

    local depts = everyone and { '*' } or { session.department }
    for _, src in ipairs(MDT.sourcesFor(depts)) do
        if not MDT.viewers[src] then MDT.notify(src, 'Department bulletin', title, 'inform') end
    end

    MDT.push('announce:new', { title = title }, depts)
    MDT.record(session, 'admin', 'announcement.create', 'announcement', title,
        'Bulletin posted', ('**%s** — %s'):format(title, session.name))

    return { ok = true, msg = 'Bulletin posted.' }
end))

lib.callback.register('nz_mdt:announce:delete', MDT.guard('announcement.create', function(session, id)
    local row = MySQL.single.await('SELECT id, department FROM nz_mdt_announcements WHERE id = ?', { tonumber(id) })
    if not row then return { ok = false, msg = 'That bulletin is gone already.' } end

    -- another department's bulletin, or an all-departments one, needs command
    if row.department ~= session.department and not session.perms['officer.manage'] then
        return { ok = false, msg = 'Only command can remove that bulletin.' }
    end

    MySQL.update.await('DELETE FROM nz_mdt_announcements WHERE id = ?', { row.id })
    MDT.audit(session, 'announcement.delete', 'announcement', row.id, 'Bulletin removed')
    return { ok = true, msg = 'Bulletin removed.' }
end))

-- ── notes (shared across every record type) ─────────────────
local NOTE_SUBJECTS = {
    citizen = true, vehicle = true, weapon = true, property = true,
    incident = true, evidence = true, bolo = true, warrant = true, dispatch = true
}

function MDT.getNotes(session, subject, subjectId)
    if not NOTE_SUBJECTS[subject] then return {} end

    local rows = MySQL.query.await([[
        SELECT id, body, visibility, author, author_id, department,
               DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
        FROM nz_mdt_notes WHERE subject = ? AND subject_id = ? ORDER BY id DESC LIMIT 50
    ]], { subject, tostring(subjectId) }) or {}

    local out = {}
    for _, n in ipairs(rows) do
        local visible = true
        if n.visibility == 'private' then
            visible = n.author_id == session.identifier
        elseif n.visibility == 'command' then
            visible = session.perms['officer.manage'] == true or n.author_id == session.identifier
        elseif n.visibility == 'department' then
            visible = n.department == nil or n.department == session.department
        end
        if visible then
            n.mine = n.author_id == session.identifier
            n.author_id = nil
            out[#out + 1] = n
        end
    end
    return out
end

lib.callback.register('nz_mdt:notes:list', function(src, subject, subjectId)
    local session = MDT.getSession(src)
    if not session then return { ok = false, rows = {} } end
    return { ok = true, rows = MDT.getNotes(session, subject, subjectId) }
end)

lib.callback.register('nz_mdt:notes:add', function(src, subject, subjectId, body, visibility)
    local session = MDT.getSession(src)
    if not session then return { ok = false, msg = 'You are not on a department roster.' } end
    if not NOTE_SUBJECTS[subject] then return { ok = false, msg = 'Notes cannot be attached to that.' } end
    if subjectId == nil or tostring(subjectId) == '' then return { ok = false, msg = 'That record has no ID.' } end

    body = MDT.clean(body, 1000)
    if #body < 2 then return { ok = false, msg = 'Write something first.' } end

    if visibility ~= 'private' and visibility ~= 'command' then visibility = 'department' end

    MySQL.insert.await([[
        INSERT INTO nz_mdt_notes (subject, subject_id, body, visibility, author, author_id, department)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { subject, tostring(subjectId):sub(1, 48), body, visibility, session.name, session.identifier, session.department })

    MDT.audit(session, 'note.add', subject, subjectId, body:sub(1, 100))
    return { ok = true, msg = 'Note added.', rows = MDT.getNotes(session, subject, subjectId) }
end)

lib.callback.register('nz_mdt:notes:delete', function(src, noteId)
    local session = MDT.getSession(src)
    if not session then return { ok = false } end

    local note = MySQL.single.await('SELECT * FROM nz_mdt_notes WHERE id = ?', { tonumber(noteId) })
    if not note then return { ok = false, msg = 'That note is gone already.' } end
    if note.author_id ~= session.identifier and not session.perms['officer.manage'] then
        return { ok = false, msg = 'Only the author or command can remove that note.' }
    end

    MySQL.update.await('DELETE FROM nz_mdt_notes WHERE id = ?', { note.id })
    MDT.audit(session, 'note.delete', note.subject, note.subject_id, 'Note removed')

    return { ok = true, msg = 'Note removed.', rows = MDT.getNotes(session, note.subject, note.subject_id) }
end)

-- ── audit log page ──────────────────────────────────────────
lib.callback.register('nz_mdt:audit:list', MDT.guard('view.audit', function(session, page, search)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = Config.Audit.pageSize or 20
    search = MDT.clean(search, 40)

    local where, args = '1 = 1', {}
    if search ~= '' then
        where = '(actor LIKE ? OR action LIKE ? OR subject_id LIKE ? OR detail LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_mdt_audit WHERE %s'):format(where), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(([[
        SELECT actor, department, action, subject, subject_id, detail,
               DATE_FORMAT(created_at, '%%d %%b · %%H:%%i') AS stamp
        FROM nz_mdt_audit WHERE %s ORDER BY id DESC LIMIT ? OFFSET ?
    ]]):format(where), qArgs) or {}

    return { ok = true, rows = rows, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))
