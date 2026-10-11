-- ═══════════════════════════════════════════════════════════
--  RECORD LINKS
--  Links are stored once and read from both ends, so linking a
--  vehicle to an incident makes each one show the other.
-- ═══════════════════════════════════════════════════════════

local function typeAllowed(kind)
    for _, t in ipairs(Config.Links.types or {}) do
        if t.id == kind then return true end
    end
    return false
end

--- Resolve a record into a title and subtitle the UI can show.
local function describe(kind, id)
    id = tostring(id)

    if kind == 'citizen' then
        local c = MySQL.single.await(
            'SELECT first_name, last_name, dob FROM nz_mdt_citizens WHERE citizen_id = ?', { id })
        if c then return ('%s %s'):format(c.first_name, c.last_name), (c.dob or 'DOB unknown') end

    elseif kind == 'vehicle' then
        local v = MySQL.single.await(
            'SELECT model, owner_name, stolen FROM nz_mdt_vehicles WHERE plate = ?', { id })
        if v then return id, ('%s · %s'):format(v.model or 'unknown model', v.owner_name or 'no owner'), MDT.bool(v.stolen) end

    elseif kind == 'weapon' then
        local w = MySQL.single.await(
            'SELECT label, owner_name, status FROM nz_mdt_weapons WHERE serial = ?', { id })
        if w then return w.label, ('%s · %s'):format(id, w.owner_name or 'no owner'), w.status == 'stolen' end

    elseif kind == 'property' then
        local p = MySQL.single.await('SELECT label, address FROM nz_mdt_properties WHERE id = ?', { tonumber(id) })
        if p then return p.label, p.address end

    elseif kind == 'incident' then
        local i = MySQL.single.await('SELECT title, status FROM nz_mdt_incidents WHERE ref = ?', { id })
        if i then return i.title, ('%s · %s'):format(id, i.status) end

    elseif kind == 'evidence' then
        local e = MySQL.single.await('SELECT description, locker, status FROM nz_mdt_evidence WHERE ref = ?', { id })
        if e then return e.description, ('%s · %s'):format(id, e.locker or 'unassigned') end

    elseif kind == 'warrant' then
        local w = MySQL.single.await('SELECT title, citizen_name, status FROM nz_mdt_warrants WHERE id = ?',
            { tonumber(id) })
        if w then return w.title, w.citizen_name, w.status == 'active' end

    elseif kind == 'bolo' then
        local b = MySQL.single.await('SELECT title, status FROM nz_mdt_bolos WHERE id = ?', { tonumber(id) })
        if b then return b.title, b.status, b.status == 'active' end
    end

    return id, 'No longer on file'
end

--- Every record linked to this one, from either direction.
function MDT.getLinks(subject, subjectId)
    if not Config.Links.enabled then return {} end
    subjectId = tostring(subjectId)

    local rows = MySQL.query.await([[
        SELECT id, from_type, from_id, to_type, to_id, note, linked_by,
               DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
        FROM nz_mdt_links
        WHERE (from_type = ? AND from_id = ?) OR (to_type = ? AND to_id = ?)
        ORDER BY id DESC LIMIT ?
    ]], { subject, subjectId, subject, subjectId, Config.Links.maxPer or 30 }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        -- whichever end is not us is the one to show
        local kind, id
        if r.from_type == subject and r.from_id == subjectId then
            kind, id = r.to_type, r.to_id
        else
            kind, id = r.from_type, r.from_id
        end

        local title, sub, hot = describe(kind, id)
        out[#out + 1] = {
            linkId = r.id, kind = kind, id = id,
            title = title, sub = sub, hot = hot or false,
            note = r.note, linkedBy = r.linked_by, stamp = r.stamp
        }
    end
    return out
end

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:link:list', function(src, subject, subjectId)
    local session = MDT.getSession(src)
    if not session then return { ok = false, rows = {} } end
    return { ok = true, rows = MDT.getLinks(subject, subjectId), types = Config.Links.types }
end)

lib.callback.register('nz_mdt:link:create', MDT.guard('link.create', function(session, fromType, fromId, toType, toId, note)
    if not Config.Links.enabled then return { ok = false, msg = 'Linking is switched off.' } end
    if not typeAllowed(fromType) or not typeAllowed(toType) then
        return { ok = false, msg = 'Those records cannot be linked.' }
    end

    fromId, toId = tostring(fromId), tostring(toId)
    if fromType == toType and fromId == toId then
        return { ok = false, msg = 'A record cannot be linked to itself.' }
    end

    -- make sure both ends actually exist
    local _, toSub = describe(toType, toId)
    if toSub == 'No longer on file' then return { ok = false, msg = 'That record is not on file.' } end
    local _, fromSub = describe(fromType, fromId)
    if fromSub == 'No longer on file' then return { ok = false, msg = 'This record is not on file any more.' } end

    local existing = MySQL.scalar.await([[
        SELECT id FROM nz_mdt_links
        WHERE (from_type = ? AND from_id = ? AND to_type = ? AND to_id = ?)
           OR (from_type = ? AND from_id = ? AND to_type = ? AND to_id = ?)
        LIMIT 1
    ]], { fromType, fromId, toType, toId, toType, toId, fromType, fromId })

    if existing then return { ok = false, msg = 'Those two are already linked.' } end

    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM nz_mdt_links
        WHERE (from_type = ? AND from_id = ?) OR (to_type = ? AND to_id = ?)
    ]], { fromType, fromId, fromType, fromId }) or 0

    if count >= (Config.Links.maxPer or 30) then
        return { ok = false, msg = ('That record already carries %s links.'):format(Config.Links.maxPer) }
    end

    MySQL.insert.await([[
        INSERT INTO nz_mdt_links (from_type, from_id, to_type, to_id, note, linked_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { fromType, fromId, toType, toId, MDT.clean(note, 200), session.name })

    MDT.audit(session, 'link.create', fromType, fromId, ('linked to %s %s'):format(toType, toId))

    return { ok = true, msg = 'Records linked.', rows = MDT.getLinks(fromType, fromId) }
end))

lib.callback.register('nz_mdt:link:remove', MDT.guard('link.remove', function(session, linkId, subject, subjectId)
    local l = MySQL.single.await('SELECT * FROM nz_mdt_links WHERE id = ?', { tonumber(linkId) })
    if not l then return { ok = false, msg = 'That link is gone already.' } end

    MySQL.update.await('DELETE FROM nz_mdt_links WHERE id = ?', { tonumber(linkId) })
    MDT.audit(session, 'link.remove', l.from_type, l.from_id,
        ('unlinked from %s %s'):format(l.to_type, l.to_id))

    return { ok = true, msg = 'Link removed.', rows = MDT.getLinks(subject, subjectId) }
end))

--- Search any record type, so the link picker can find something to attach.
lib.callback.register('nz_mdt:link:search', MDT.guard('link.create', function(session, kind, search)
    search = MDT.clean(search, 40)
    local like = '%' .. search .. '%'
    local rows = {}

    if kind == 'citizen' and session.perms['view.citizen'] then
        local hits = MySQL.query.await([[
            SELECT citizen_id AS id, CONCAT(first_name, ' ', last_name) AS title, dob AS sub
            FROM nz_mdt_citizens
            WHERE CONCAT(first_name, ' ', last_name) LIKE ? OR citizen_id LIKE ? LIMIT 10
        ]], { like, like }) or {}
        rows = hits

    elseif kind == 'vehicle' and session.perms['view.vehicle'] then
        rows = MySQL.query.await([[
            SELECT plate AS id, plate AS title, CONCAT(COALESCE(model,'unknown'), ' · ', COALESCE(owner_name,'no owner')) AS sub
            FROM nz_mdt_vehicles WHERE plate LIKE ? OR owner_name LIKE ? LIMIT 10
        ]], { like, like }) or {}

    elseif kind == 'weapon' and session.perms['view.weapon'] then
        rows = MySQL.query.await([[
            SELECT serial AS id, label AS title, CONCAT(serial, ' · ', COALESCE(owner_name,'no owner')) AS sub
            FROM nz_mdt_weapons WHERE serial LIKE ? OR label LIKE ? LIMIT 10
        ]], { like, like }) or {}

    elseif kind == 'property' and session.perms['view.property'] then
        rows = MySQL.query.await([[
            SELECT id, label AS title, address AS sub FROM nz_mdt_properties
            WHERE label LIKE ? OR address LIKE ? LIMIT 10
        ]], { like, like }) or {}

    elseif kind == 'incident' and session.perms['view.incident'] then
        rows = MySQL.query.await([[
            SELECT ref AS id, title, CONCAT(ref, ' · ', status) AS sub FROM nz_mdt_incidents
            WHERE ref LIKE ? OR title LIKE ? ORDER BY id DESC LIMIT 10
        ]], { like, like }) or {}

    elseif kind == 'evidence' and session.perms['view.evidence'] then
        rows = MySQL.query.await([[
            SELECT ref AS id, description AS title, CONCAT(ref, ' · ', status) AS sub FROM nz_mdt_evidence
            WHERE ref LIKE ? OR description LIKE ? ORDER BY id DESC LIMIT 10
        ]], { like, like }) or {}

    elseif kind == 'warrant' and session.perms['view.warrant'] then
        rows = MySQL.query.await([[
            SELECT id, title, citizen_name AS sub FROM nz_mdt_warrants
            WHERE title LIKE ? OR citizen_name LIKE ? ORDER BY id DESC LIMIT 10
        ]], { like, like }) or {}

    elseif kind == 'bolo' and session.perms['view.bolo'] then
        rows = MySQL.query.await([[
            SELECT id, title, status AS sub FROM nz_mdt_bolos
            WHERE title LIKE ? OR plate LIKE ? ORDER BY id DESC LIMIT 10
        ]], { like, like }) or {}
    end

    return { ok = true, rows = rows }
end))

-- ═══════════════════════════════════════════════════════════
--  EXPORTS — so other resources can wire records together
-- ═══════════════════════════════════════════════════════════
exports('link', function(fromType, fromId, toType, toId, note)
    if not Config.Links.enabled then return false end
    local ok = pcall(function()
        MySQL.insert.await([[
            INSERT IGNORE INTO nz_mdt_links (from_type, from_id, to_type, to_id, note, linked_by)
            VALUES (?, ?, ?, ?, ?, 'System')
        ]], { fromType, tostring(fromId), toType, tostring(toId), note })
    end)
    return ok
end)

exports('linksFor', function(subject, subjectId)
    return MDT.getLinks(subject, subjectId)
end)
