-- ═══════════════════════════════════════════════════════════
--  BOLOs · WARRANTS
-- ═══════════════════════════════════════════════════════════

local function boloCard(b)
    return {
        id        = b.id,
        title     = b.title,
        kind      = b.kind,
        plate     = b.plate,
        model     = b.model,
        citizenId = b.citizen_id,
        detail    = b.detail,
        priority  = b.priority,
        status    = b.status,
        issuedBy  = b.issued_by,
        resolvedBy= b.resolved_by,
        stamp     = b.stamp,
        expiresIn = b.expires_at and math.max(0, math.floor((b.expires_at - os.time()) / 3600)) or nil
    }
end

-- ═══════════════════════════════════════════════════════════
--  BOLOs
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:bolo:list', MDT.guard('view.bolo', function(session, search, filter)
    search = MDT.clean(search, 40)

    local where, args = { '1 = 1' }, {}
    if search ~= '' then
        where[#where + 1] = '(title LIKE ? OR plate LIKE ? OR detail LIKE ? OR model LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end
    if filter and filter ~= 'all' then
        where[#where + 1] = 'status = ?'
        args[#args + 1] = filter
    end

    local rows = MySQL.query.await(([[
        SELECT *, DATE_FORMAT(created_at, '%%d/%%m/%%Y %%H:%%i') AS stamp
        FROM nz_mdt_bolos WHERE %s
        ORDER BY (status = 'active') DESC, priority ASC, id DESC LIMIT ?
    ]]):format(table.concat(where, ' AND ')),
        (function() local a = { table.unpack(args) }; a[#a + 1] = Config.Bolo.maxActive * 2; return a end)()) or {}

    local out = {}
    for _, b in ipairs(rows) do out[#out + 1] = boloCard(b) end
    return { ok = true, rows = out }
end))

lib.callback.register('nz_mdt:bolo:create', MDT.guard('bolo.create', function(session, data)
    if not Config.Bolo.enabled then return { ok = false, msg = 'BOLOs are disabled on this server.' } end

    local title = MDT.clean(data and data.title, 90)
    if #title < 3 then return { ok = false, msg = 'Give the BOLO a title.' } end

    local kind = ({ vehicle = 1, person = 1, property = 1 })[data.kind] and data.kind or 'vehicle'
    local active = MySQL.scalar.await("SELECT COUNT(*) FROM nz_mdt_bolos WHERE status = 'active'") or 0
    if active >= Config.Bolo.maxActive then
        return { ok = false, msg = 'The BOLO board is full. Resolve an old one first.' }
    end

    local expires = Config.Bolo.expireHours > 0 and (os.time() + Config.Bolo.expireHours * 3600) or nil
    local priority = math.max(1, math.min(3, math.floor(tonumber(data.priority) or 2)))

    local plate = MDT.opt(data.plate, 12) and MDT.plateKey(data.plate) or nil
    local id = MySQL.insert.await([[
        INSERT INTO nz_mdt_bolos (title, kind, plate, model, citizen_id, detail, priority, issued_by, issuer_id, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        title, kind, plate,
        MDT.opt(data.model, 40),
        MDT.opt(data.citizenId, 32),
        MDT.opt(data.detail, 900),
        priority, session.name, session.identifier, expires
    })

    -- tell everyone on duty; open tablets get it as a tablet notification instead
    for _, src in ipairs(MDT.sourcesFor({ '*' })) do
        if not MDT.viewers[src] then MDT.notify(src, 'BOLO issued', title, priority == 1 and 'error' or 'inform') end
    end
    MDT.push('bolo:new', { id = id, title = title })

    MDT.record(session, 'bolo', 'bolo.create', 'bolo', id,
        'BOLO issued', ('**%s**%s — %s'):format(title, plate and (' · ' .. plate) or '', session.name))

    return { ok = true, msg = 'BOLO is live.', id = id }
end))

lib.callback.register('nz_mdt:bolo:update', MDT.guard('bolo.edit', function(session, id, patch)
    if type(patch) ~= 'table' then return { ok = false, msg = 'Nothing to change.' } end

    local sets, args = {}, {}
    if patch.title then
        if #MDT.clean(patch.title, 90) < 3 then return { ok = false, msg = 'Give the BOLO a title.' } end
        sets[#sets+1] = 'title = ?'; args[#args+1] = MDT.clean(patch.title, 90)
    end
    if patch.detail ~= nil then sets[#sets+1] = 'detail = ?'; args[#args+1] = MDT.opt(patch.detail, 900) end
    if patch.plate ~= nil then sets[#sets+1] = 'plate = ?'; args[#args+1] = MDT.opt(patch.plate, 12) and MDT.plateKey(patch.plate) or nil end
    if patch.model ~= nil then sets[#sets+1] = 'model = ?'; args[#args+1] = MDT.opt(patch.model, 40) end
    if patch.citizenId ~= nil then sets[#sets+1] = 'citizen_id = ?'; args[#args+1] = MDT.opt(patch.citizenId, 32) end
    if patch.kind and ({ vehicle = 1, person = 1, property = 1 })[patch.kind] then
        sets[#sets+1] = 'kind = ?'; args[#args+1] = patch.kind
    end
    if patch.priority then
        sets[#sets+1] = 'priority = ?'
        args[#args+1] = math.max(1, math.min(3, math.floor(tonumber(patch.priority) or 2)))
    end
    if #sets == 0 then return { ok = false, msg = 'Nothing to change.' } end

    args[#args + 1] = tonumber(id)
    MySQL.update.await(('UPDATE nz_mdt_bolos SET %s WHERE id = ?'):format(table.concat(sets, ', ')), args)

    MDT.audit(session, 'bolo.edit', 'bolo', id, 'BOLO edited')
    MDT.push('bolo:update', { id = tonumber(id) })
    return { ok = true, msg = 'BOLO updated.' }
end))

lib.callback.register('nz_mdt:bolo:resolve', MDT.guard('bolo.resolve', function(session, id)
    local b = MySQL.single.await('SELECT * FROM nz_mdt_bolos WHERE id = ?', { tonumber(id) })
    if not b then return { ok = false, msg = 'That BOLO is no longer on the board.' } end
    if b.status ~= 'active' then return { ok = false, msg = 'That BOLO is already closed.' } end

    MySQL.update.await("UPDATE nz_mdt_bolos SET status = 'resolved', resolved_by = ? WHERE id = ?",
        { session.name, b.id })

    MDT.record(session, 'bolo', 'bolo.resolve', 'bolo', b.id,
        'BOLO resolved', ('**%s** resolved by %s'):format(b.title, session.name))
    MDT.push('bolo:update', { id = b.id })

    return { ok = true, msg = 'BOLO resolved.' }
end))

lib.callback.register('nz_mdt:bolo:delete', MDT.guard('bolo.delete', function(session, id)
    MySQL.update.await('DELETE FROM nz_mdt_bolos WHERE id = ?', { tonumber(id) })
    MDT.audit(session, 'bolo.delete', 'bolo', id, 'BOLO deleted')
    MDT.push('bolo:update', { id = tonumber(id) })
    return { ok = true, msg = 'BOLO deleted.' }
end))

--- Used by the ALPR and by plate lookups.
function MDT.boloForPlate(plate)
    if not Config.Bolo.enabled then return nil end
    plate = MDT.plateKey(MDT.clean(plate, 12))
    if plate == '' then return nil end
    return MySQL.single.await(
        "SELECT id, title, detail, priority, issued_by, issuer_id FROM nz_mdt_bolos WHERE plate = ? AND status = 'active' LIMIT 1",
        { plate })
end

-- expiry sweep
CreateThread(function()
    while true do
        Wait(300000)
        if Config.Bolo.enabled and Config.Bolo.expireHours > 0 then
            local n = MySQL.update.await(
                "UPDATE nz_mdt_bolos SET status = 'expired' WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at < ?",
                { os.time() })
            if n and n > 0 then MDT.push('bolo:update', {}) end
        end
        if Config.Warrant.enabled and Config.Warrant.expireDays > 0 then
            local n = MySQL.update.await(
                "UPDATE nz_mdt_warrants SET status = 'expired' WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at < ?",
                { os.time() })
            if n and n > 0 then MDT.push('warrant:update', {}) end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  WARRANTS
-- ═══════════════════════════════════════════════════════════
local function warrantCard(w)
    return {
        id        = w.id,
        citizenId = w.citizen_id,
        citizen   = w.citizen_name,
        type      = w.type,
        title     = w.title,
        detail    = w.detail,
        charges   = MDT.decode(w.charges, {}),
        status    = w.status,
        issuedBy  = w.issued_by,
        executedBy= w.executed_by,
        stamp     = w.stamp,
        expiresIn = w.expires_at and math.max(0, math.floor((w.expires_at - os.time()) / 86400)) or nil
    }
end

lib.callback.register('nz_mdt:warrant:list', MDT.guard('view.warrant', function(session, search, filter)
    search = MDT.clean(search, 40)

    local where, args = { '1 = 1' }, {}
    if search ~= '' then
        where[#where + 1] = '(citizen_name LIKE ? OR title LIKE ? OR detail LIKE ? OR citizen_id LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end
    if filter and filter ~= 'all' then
        where[#where + 1] = 'status = ?'
        args[#args + 1] = filter
    end

    local rows = MySQL.query.await(([[
        SELECT *, DATE_FORMAT(created_at, '%%d/%%m/%%Y %%H:%%i') AS stamp
        FROM nz_mdt_warrants WHERE %s ORDER BY (status = 'active') DESC, id DESC LIMIT 60
    ]]):format(table.concat(where, ' AND ')), args) or {}

    local out = {}
    for _, w in ipairs(rows) do out[#out + 1] = warrantCard(w) end
    return { ok = true, rows = out }
end))

lib.callback.register('nz_mdt:warrant:create', MDT.guard('warrant.create', function(session, data)
    if not Config.Warrant.enabled then return { ok = false, msg = 'Warrants are disabled on this server.' } end

    local citizenId = MDT.clean(data and data.citizenId, 32)
    local title = MDT.clean(data and data.title, 90)
    if citizenId == '' then return { ok = false, msg = 'Pick the citizen this is for.' } end
    if #title < 3 then return { ok = false, msg = 'Give the warrant a title.' } end

    local c = MySQL.single.await('SELECT first_name, last_name FROM nz_mdt_citizens WHERE citizen_id = ?', { citizenId })
    if not c then return { ok = false, msg = 'No citizen record with that ID.' } end

    local kind = 'arrest'
    for _, t in ipairs(Config.Warrant.types) do if t.id == data.type then kind = t.id break end end

    -- keep only charge ids that exist in the penal code
    local charges = {}
    if type(data.charges) == 'table' then
        for _, id in ipairs(data.charges) do
            for _, ch in ipairs(Config.Charges) do
                if ch.id == id then charges[#charges + 1] = { id = ch.id, label = ch.label } break end
            end
        end
    end

    local expires = Config.Warrant.expireDays > 0 and (os.time() + Config.Warrant.expireDays * 86400) or nil
    local name = ('%s %s'):format(c.first_name, c.last_name)

    local id = MySQL.insert.await([[
        INSERT INTO nz_mdt_warrants (citizen_id, citizen_name, type, title, detail, charges, issued_by, issuer_id, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { citizenId, name, kind, title, MDT.opt(data.detail, 900),
          json.encode(charges), session.name, session.identifier, expires })

    for _, src in ipairs(MDT.sourcesFor({ '*' })) do
        if not MDT.viewers[src] then MDT.notify(src, 'Warrant issued', ('%s — %s'):format(name, title), 'error') end
    end
    MDT.push('warrant:new', { id = id, citizen = name })

    MDT.record(session, 'warrant', 'warrant.create', 'warrant', id,
        'Warrant issued', ('**%s** for %s — %s'):format(title, name, session.name))

    return { ok = true, msg = ('Warrant issued for %s.'):format(name), id = id }
end))

lib.callback.register('nz_mdt:warrant:execute', MDT.guard('warrant.execute', function(session, id)
    local w = MySQL.single.await('SELECT * FROM nz_mdt_warrants WHERE id = ?', { tonumber(id) })
    if not w then return { ok = false, msg = 'That warrant is no longer on file.' } end
    if w.status ~= 'active' then return { ok = false, msg = 'That warrant is already closed.' } end

    MySQL.update.await("UPDATE nz_mdt_warrants SET status = 'executed', executed_by = ? WHERE id = ?",
        { session.name, w.id })

    MDT.record(session, 'warrant', 'warrant.execute', 'warrant', w.id,
        'Warrant executed', ('**%s** on %s by %s'):format(w.title, w.citizen_name, session.name))
    MDT.push('warrant:update', { id = w.id })

    return { ok = true, msg = 'Warrant marked as executed.' }
end))

lib.callback.register('nz_mdt:warrant:void', MDT.guard('warrant.edit', function(session, id)
    local w = MySQL.single.await('SELECT * FROM nz_mdt_warrants WHERE id = ?', { tonumber(id) })
    if not w then return { ok = false, msg = 'That warrant is no longer on file.' } end
    if w.status ~= 'active' then return { ok = false, msg = 'Only an active warrant can be voided.' } end

    MySQL.update.await("UPDATE nz_mdt_warrants SET status = 'void' WHERE id = ?", { w.id })
    MDT.record(session, 'warrant', 'warrant.void', 'warrant', w.id,
        'Warrant voided', ('**%s** voided by %s'):format(w.title, session.name))
    MDT.push('warrant:update', { id = w.id })

    return { ok = true, msg = 'Warrant voided.' }
end))

lib.callback.register('nz_mdt:warrant:delete', MDT.guard('warrant.delete', function(session, id)
    MySQL.update.await('DELETE FROM nz_mdt_warrants WHERE id = ?', { tonumber(id) })
    MDT.audit(session, 'warrant.delete', 'warrant', id, 'Warrant deleted')
    MDT.push('warrant:update', { id = tonumber(id) })
    return { ok = true, msg = 'Warrant deleted.' }
end))

--- Used by the ALPR when a registered owner is wanted.
function MDT.warrantsFor(citizenId)
    if not Config.Warrant.enabled or not citizenId then return {} end
    return MySQL.query.await(
        "SELECT id, type, title FROM nz_mdt_warrants WHERE citizen_id = ? AND status = 'active' LIMIT 5",
        { citizenId }) or {}
end

-- ═══════════════════════════════════════════════════════════
--  ALPR  (client sweeps plates, server decides which matter)
-- ═══════════════════════════════════════════════════════════
local function inList(n) return string.rep('?,', n):sub(1, -2) end

--- Check a list of plates in four queries, whatever the size of the list.
local function checkPlates(session, plates)
    local clean, seen = {}, {}
    for _, p in ipairs(plates) do
        local key = MDT.plateKey(MDT.clean(p, 12))
        if key ~= '' and not seen[key] then seen[key] = true clean[#clean + 1] = key end
        if #clean >= 20 then break end
    end
    if #clean == 0 then return {} end

    local hits = {}
    local function add(plate, hit)
        hits[plate] = hits[plate] or {}
        table.insert(hits[plate], hit)
    end

    local bolos = {}
    if Config.ALPR.checkBolo and Config.Bolo.enabled then
        bolos = MySQL.query.await(("SELECT id, plate, title, issuer_id FROM nz_mdt_bolos WHERE status = 'active' AND plate IN (%s)"):format(inList(#clean)), clean) or {}
        for _, b in ipairs(bolos) do
            add(b.plate, { kind = 'bolo', label = 'BOLO match', detail = b.title, tone = 'red' })
            if Config.Bolo.alertOnPlate and b.issuer_id and b.issuer_id ~= session.identifier then
                local src = MDT.onlineBy(b.issuer_id)
                if src then MDT.notify(src, 'BOLO hit', ('%s was scanned by %s.'):format(b.plate, session.name), 'inform') end
            end
        end
    end

    local vehicles = MySQL.query.await(('SELECT * FROM nz_mdt_vehicles WHERE plate IN (%s)'):format(inList(#clean)), clean) or {}
    local byPlate, owners = {}, {}
    for _, v in ipairs(vehicles) do
        byPlate[v.plate] = v
        if Config.ALPR.checkStolen and MDT.bool(v.stolen) then
            add(v.plate, { kind = 'stolen', label = 'Reported stolen', detail = v.model or v.plate, tone = 'red' })
        end
        if v.registration and v.registration ~= 'valid' then
            add(v.plate, { kind = 'registration', label = 'Registration ' .. v.registration, detail = v.owner_name or 'no registered owner', tone = 'amber' })
        end
        if v.insurance == 'expired' or v.insurance == 'none' then
            add(v.plate, { kind = 'insurance', label = v.insurance == 'none' and 'No insurance' or 'Insurance expired', detail = v.owner_name or v.plate, tone = 'amber' })
        end
        if v.owner_id then owners[#owners + 1] = v.owner_id end
    end

    if Config.ALPR.checkWarrants and Config.Warrant.enabled and #owners > 0 then
        local rows = MySQL.query.await(("SELECT citizen_id, COUNT(*) AS n FROM nz_mdt_warrants WHERE status = 'active' AND citizen_id IN (%s) GROUP BY citizen_id"):format(inList(#owners)), owners) or {}
        local wanted = {}
        for _, r in ipairs(rows) do wanted[r.citizen_id] = r.n end
        for _, v in ipairs(vehicles) do
            local n = v.owner_id and wanted[v.owner_id]
            if n then
                add(v.plate, { kind = 'warrant', label = ('%s active warrant%s'):format(n, n == 1 and '' or 's'),
                               detail = v.owner_name or 'registered owner', tone = 'red' })
            end
        end
    end

    local out = {}
    for plate, list in pairs(hits) do
        -- red hits first
        table.sort(list, function(a, b) return (a.tone == 'red' and 0 or 1) < (b.tone == 'red' and 0 or 1) end)
        local v = byPlate[plate]
        out[#out + 1] = { plate = plate, owner = v and v.owner_name or nil, model = v and v.model or nil, hits = list }
        MDT.audit(session, 'alpr.hit', 'vehicle', plate, list[1].label)
    end
    return out
end

local function alprSession(src)
    if not Config.ALPR.enabled then return nil end
    local session = MDT.getSession(src)
    if not session then return nil end
    local info = MDT.online[src]
    if Config.ALPR.onlyOnDuty and (not info or not info.onDuty) then return nil end
    return session
end

lib.callback.register('nz_mdt:alpr:batch', function(src, plates)
    local session = alprSession(src)
    if not session or type(plates) ~= 'table' then return {} end
    return checkPlates(session, plates)
end)

--- Single-plate form, kept for other resources that already call it.
lib.callback.register('nz_mdt:alpr:check', function(src, plate)
    local session = alprSession(src)
    if not session then return nil end
    return checkPlates(session, { plate })[1]
end)
