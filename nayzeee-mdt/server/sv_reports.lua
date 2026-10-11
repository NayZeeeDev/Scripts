-- ═══════════════════════════════════════════════════════════
--  INCIDENTS · CHARGES · EVIDENCE
-- ═══════════════════════════════════════════════════════════

local chargeIndex = {}
for _, c in ipairs(Config.Charges) do chargeIndex[c.id] = c end

--- Reports and evidence can be opened by numeric id or by reference (INC-000012).
local function byIdOrRef(tbl, value, columns)
    local id = tonumber(value)
    if id and tostring(math.floor(id)) == tostring(value) then
        return MySQL.single.await(('SELECT %s FROM %s WHERE id = ?'):format(columns or '*', tbl), { id })
    end
    return MySQL.single.await(('SELECT %s FROM %s WHERE ref = ?'):format(columns or '*', tbl), { MDT.clean(value, 24) })
end

-- ═══════════════════════════════════════════════════════════
--  INCIDENTS
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:incident:list', MDT.guard('view.incident', function(session, search, page, status, mine)
    search = MDT.clean(search, 40)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = 10

    local where, args = { '1 = 1' }, {}
    if search ~= '' then
        where[#where + 1] = '(ref LIKE ? OR title LIKE ? OR primary_name LIKE ? OR location LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end
    if status and status ~= 'all' then
        where[#where + 1] = 'status = ?'
        args[#args + 1] = status
    end
    if mine == true then
        where[#where + 1] = 'creator_id = ?'
        args[#args + 1] = session.identifier
    end

    local clause = table.concat(where, ' AND ')
    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_mdt_incidents WHERE %s'):format(clause), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(([[
        SELECT i.*,
               DATE_FORMAT(i.created_at, '%%d %%b %%Y · %%H:%%i') AS stamp,
               (SELECT COUNT(*) FROM nz_mdt_incident_charges c WHERE c.incident_id = i.id) AS charge_count
        FROM nz_mdt_incidents i WHERE %s ORDER BY i.id DESC LIMIT ? OFFSET ?
    ]]):format(clause), qArgs) or {}

    return { ok = true, rows = rows, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))

lib.callback.register('nz_mdt:incident:get', MDT.guard('view.incident', function(session, value)
    local inc = byIdOrRef('nz_mdt_incidents', value, [[
        *, DATE_FORMAT(created_at, '%d/%m/%Y, %H:%i') AS created_stamp,
           DATE_FORMAT(closed_at,  '%d/%m/%Y, %H:%i') AS closed_stamp
    ]])
    if not inc then return { ok = false, msg = 'That report is no longer on file.' } end
    local id = inc.id

    local people = MySQL.query.await(
        'SELECT citizen_id, name, role, notes FROM nz_mdt_incident_people WHERE incident_id = ?', { id }) or {}
    local charges = MySQL.query.await(
        'SELECT * FROM nz_mdt_incident_charges WHERE incident_id = ? ORDER BY id ASC', { id }) or {}
    local evidence = MySQL.query.await([[
        SELECT id, ref, description, type, locker, status FROM nz_mdt_evidence WHERE incident_id = ?
    ]], { id }) or {}

    MDT.audit(session, 'incident.view', 'incident', inc.ref, 'Report opened')

    return {
        ok = true, incident = inc, people = people, charges = charges,
        evidence = evidence, notes = MDT.getNotes(session, 'incident', inc.ref),
        photos = MDT.getPhotos('incident', inc.ref),
        links  = MDT.getLinks('incident', inc.ref)
    }
end))

--- Create or update a report in one call. `data.id` present = update.
local function saveIncident(session, data, isUpdate)
    local title = MDT.clean(data and data.title, 90)
    if #title < 3 then return { ok = false, msg = 'Give the report a title.' } end

    local people  = type(data.people) == 'table' and data.people or {}
    local charges = type(data.charges) == 'table' and data.charges or {}

    -- drop people with no record id before counting
    for i = #people, 1, -1 do
        if type(people[i]) ~= 'table' or MDT.clean(people[i].citizenId, 32) == '' then table.remove(people, i) end
    end

    if #people > Config.Incident.maxCitizens then
        return { ok = false, msg = ('A report holds at most %s people.'):format(Config.Incident.maxCitizens) }
    end
    if #charges > Config.Incident.maxCharges then
        return { ok = false, msg = ('A report holds at most %s charges.'):format(Config.Incident.maxCharges) }
    end

    -- resolve the charge rows off the server-side penal code, never the client
    local resolved, totalFine, totalJail = {}, 0, 0
    for _, ch in ipairs(charges) do
        local base = chargeIndex[ch.id]
        if base then
            local counts = math.max(1, math.min(20, math.floor(tonumber(ch.counts) or 1)))
            local reduced = ch.reduced == true
            local fine = math.floor(base.fine * counts * (reduced and 0.5 or 1))
            local jail = math.floor(base.jail * counts * (reduced and 0.5 or 1))

            resolved[#resolved + 1] = {
                citizenId = MDT.clean(ch.citizenId, 32),
                id = base.id, label = base.label, class = base.class,
                counts = counts, fine = fine, jail = jail, reduced = reduced
            }
            totalFine = totalFine + fine
            totalJail = totalJail + jail
        end
    end

    if not Config.Incident.autoFine then totalFine = math.max(0, math.floor(tonumber(data.fine) or 0)) end
    if not Config.Incident.autoJail then totalJail = math.max(0, math.floor(tonumber(data.jail) or 0)) end

    local primary = people[1]
    local incidentId, ref

    if isUpdate then
        incidentId = tonumber(data.id)
        local existing = MySQL.single.await('SELECT ref, status FROM nz_mdt_incidents WHERE id = ?', { incidentId })
        if not existing then return { ok = false, msg = 'That report is no longer on file.' } end
        if existing.status == 'closed' and not session.perms['incident.reopen'] then
            return { ok = false, msg = 'Reopen the report before editing it.' }
        end
        ref = existing.ref

        MySQL.update.await([[
            UPDATE nz_mdt_incidents SET title = ?, detail = ?, location = ?, dispatch_ref = ?,
                   primary_id = ?, primary_name = ?, total_fine = ?, total_jail = ?
            WHERE id = ?
        ]], {
            title, MDT.opt(data.detail, 2000), MDT.opt(data.location, 120), MDT.opt(data.dispatchRef, 20),
            primary and MDT.clean(primary.citizenId, 32) or nil,
            primary and MDT.clean(primary.name, 90) or nil,
            totalFine, totalJail, incidentId
        })

        MySQL.update.await('DELETE FROM nz_mdt_incident_people WHERE incident_id = ?', { incidentId })
        MySQL.update.await('DELETE FROM nz_mdt_incident_charges WHERE incident_id = ?', { incidentId })
    else
        incidentId, ref = MDT.insertWithRef('nz_mdt_incidents', Config.Incident.idPrefix, 6, [[
            INSERT INTO nz_mdt_incidents
              (ref, title, detail, location, status, primary_id, primary_name,
               total_fine, total_jail, created_by, creator_id, dispatch_ref)
            VALUES (?, ?, ?, ?, 'open', ?, ?, ?, ?, ?, ?, ?)
        ]], {
            false, title, MDT.opt(data.detail, 2000), MDT.opt(data.location, 120),
            primary and MDT.clean(primary.citizenId, 32) or nil,
            primary and MDT.clean(primary.name, 90) or nil,
            totalFine, totalJail, session.name, session.identifier,
            MDT.opt(data.dispatchRef, 20)
        })
        if not incidentId then return { ok = false, msg = 'The report could not be saved.' } end
    end

    local seen = {}
    for _, p in ipairs(people) do
        local cid = MDT.clean(p.citizenId, 32)
        local role = ({ suspect = 1, victim = 1, witness = 1, officer = 1 })[p.role] and p.role or 'suspect'
        local key = cid .. role
        if cid ~= '' and not seen[key] then
            seen[key] = true
            MySQL.insert.await([[
                INSERT IGNORE INTO nz_mdt_incident_people (incident_id, citizen_id, name, role, notes)
                VALUES (?, ?, ?, ?, ?)
            ]], { incidentId, cid, MDT.clean(p.name, 90), role, MDT.clean(p.notes, 200) })
        end
    end

    for _, ch in ipairs(resolved) do
        local onReport = false
        for _, p in ipairs(people) do if MDT.clean(p.citizenId, 32) == ch.citizenId then onReport = true break end end
        MySQL.insert.await([[
            INSERT INTO nz_mdt_incident_charges
              (incident_id, citizen_id, charge_id, label, class, counts, fine, jail, reduced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            incidentId,
            (onReport and ch.citizenId ~= '') and ch.citizenId or (primary and MDT.clean(primary.citizenId, 32) or 'unknown'),
            ch.id, ch.label, ch.class, ch.counts, ch.fine, ch.jail, ch.reduced and 1 or 0
        })
    end

    MDT.record(session, 'incident', isUpdate and 'incident.edit' or 'incident.create', 'incident', ref,
        isUpdate and 'Report updated' or 'Report filed',
        ('**%s** · %s — %s%s fine, %s months'):format(ref, title, Config.Currency, totalFine, totalJail))

    MDT.push('incident:update', { ref = ref }, { session.department })

    return { ok = true, msg = ('%s saved.'):format(ref), id = incidentId, ref = ref }
end

lib.callback.register('nz_mdt:incident:create', MDT.guard('incident.create', function(session, data)
    return saveIncident(session, data, false)
end))

lib.callback.register('nz_mdt:incident:update', MDT.guard('incident.edit', function(session, data)
    return saveIncident(session, data, true)
end))

--- Charge the closed report's fine to the primary citizen.
function MDT.billCitizen(session, inc)
    local citizen = MySQL.single.await('SELECT identifier FROM nz_mdt_citizens WHERE citizen_id = ?', { inc.primary_id })
    if not citizen or not citizen.identifier then return end

    local mode = Config.Incident.billMode or 'export'
    local label = ('%s · %s'):format(inc.ref, inc.title):sub(1, 255)

    if mode == 'esx_billing' then
        local ok = pcall(MySQL.insert.await, [[
            INSERT INTO billing (identifier, sender, target_type, target, label, amount)
            VALUES (?, ?, 'society', ?, ?, ?)
        ]], { citizen.identifier, session.identifier, 'society_' .. session.department, label, inc.total_fine })
        if ok then
            local target = ESX.GetPlayerFromIdentifier(citizen.identifier)
            if target then MDT.notify(target.source, 'Fine issued', ('%s%s — %s'):format(Config.Currency, inc.total_fine, label), 'inform') end
        else
            print('^1[nayzeee-mdt]^7 billMode esx_billing: the billing table was not found')
        end

    elseif mode == 'bank' then
        local target = ESX.GetPlayerFromIdentifier(citizen.identifier)
        if not target then
            return MDT.notify(session.source, 'Fine', 'The citizen is not in the city — the fine was not taken.', 'error')
        end
        target.removeAccountMoney('bank', inc.total_fine)
        MDT.notify(target.source, 'Fine paid', ('%s%s taken from your bank — %s'):format(Config.Currency, inc.total_fine, label), 'inform')
        if GetResourceState('esx_addonaccount') == 'started' then
            TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. session.department, function(account)
                if account then account.addMoney(inc.total_fine) end
            end)
        end

    else
        local exp = Config.Incident.billExport
        if exp and GetResourceState(exp.resource) == 'started' then
            pcall(function()
                exports[exp.resource][exp.method](nil, citizen.identifier, session.department, inc.total_fine, label, session.name)
            end)
        end
    end
end

lib.callback.register('nz_mdt:incident:status', MDT.guard('incident.edit', function(session, id, status)
    id = tonumber(id)
    local inc = MySQL.single.await('SELECT * FROM nz_mdt_incidents WHERE id = ?', { id })
    if not inc then return { ok = false, msg = 'That report is no longer on file.' } end

    if status == 'closed' then
        if not session.perms['incident.close'] then
            return { ok = false, msg = 'Only a supervisor can close a report.' }
        end

        if inc.status == 'closed' then return { ok = false, msg = 'That report is already closed.' } end
        MySQL.update.await([[
            UPDATE nz_mdt_incidents SET status = 'closed', closed_by = ?, closed_at = NOW() WHERE id = ?
        ]], { session.name, id })

        -- hand off the fine and the sentence
        if Config.Incident.billOnClose and inc.total_fine > 0 and inc.primary_id then
            MDT.billCitizen(session, inc)
        end

        if Config.Incident.jailOnClose and inc.total_jail > 0 and inc.primary_id then
            local citizen = MySQL.single.await('SELECT identifier FROM nz_mdt_citizens WHERE citizen_id = ?',
                { inc.primary_id })
            if citizen and citizen.identifier then
                local target = ESX.GetPlayerFromIdentifier(citizen.identifier)
                if target then
                    TriggerEvent(Config.Incident.jailEvent, target.source, inc.total_jail)
                end
            end
        end

        MDT.record(session, 'incident', 'incident.close', 'incident', inc.ref,
            'Report closed', ('**%s** closed by %s'):format(inc.ref, session.name))

    elseif status == 'open' or status == 'pending' then
        if inc.status == 'closed' and not session.perms['incident.reopen'] then
            return { ok = false, msg = 'Only a supervisor can reopen a report.' }
        end
        if inc.status == status then return { ok = false, msg = ('That report is already %s.'):format(status) } end
        MySQL.update.await('UPDATE nz_mdt_incidents SET status = ?, closed_at = NULL, closed_by = NULL WHERE id = ?',
            { status, id })
        MDT.audit(session, 'incident.reopen', 'incident', inc.ref, 'Status set to ' .. status)
    else
        return { ok = false, msg = 'Unknown status.' }
    end

    MDT.push('incident:update', { ref = inc.ref }, { session.department })
    return { ok = true, msg = status == 'closed' and ('%s closed.'):format(inc.ref) or 'Report updated.' }
end))

lib.callback.register('nz_mdt:incident:delete', MDT.guard('incident.delete', function(session, id)
    local inc = MySQL.single.await('SELECT ref FROM nz_mdt_incidents WHERE id = ?', { tonumber(id) })
    if not inc then return { ok = false, msg = 'That report is gone already.' } end

    MySQL.update.await('DELETE FROM nz_mdt_incidents WHERE id = ?', { tonumber(id) })
    MDT.record(session, 'incident', 'incident.delete', 'incident', inc.ref,
        'Report deleted', ('**%s** deleted by %s'):format(inc.ref, session.name))

    return { ok = true, msg = ('%s deleted.'):format(inc.ref) }
end))

-- ═══════════════════════════════════════════════════════════
--  CHARGES (penal code browser + per-citizen history)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:charges:list', MDT.guard('view.charge', function(session, search, category)
    search = MDT.clean(search, 40):lower()
    local out, categories, seen = {}, {}, {}

    for _, c in ipairs(Config.Charges) do
        if not seen[c.category] then
            seen[c.category] = true
            categories[#categories + 1] = c.category
        end
        local match = search == '' or c.label:lower():find(search, 1, true) or c.id:lower():find(search, 1, true)
        local inCat = not category or category == 'all' or c.category == category
        if match and inCat then out[#out + 1] = c end
    end

    return { ok = true, rows = out, categories = categories, classes = Config.ChargeClasses }
end))

-- ═══════════════════════════════════════════════════════════
--  EVIDENCE
-- ═══════════════════════════════════════════════════════════
local function evidenceCard(e)
    return {
        id          = e.id,
        ref         = e.ref,
        description = e.description,
        type        = e.type,
        location    = e.location,
        locker      = e.locker,
        incidentId  = e.incident_id,
        incidentRef = e.incident_ref,
        collectedBy = e.collected_by,
        status      = e.status,
        holder      = e.holder,
        photos      = MDT.decode(e.photos, {}),
        stamp       = e.stamp
    }
end

lib.callback.register('nz_mdt:evidence:list', MDT.guard('view.evidence', function(session, search, page, status)
    search = MDT.clean(search, 40)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = 12

    local where, args = { '1 = 1' }, {}
    if search ~= '' then
        where[#where + 1] = '(e.ref LIKE ? OR e.description LIKE ? OR e.location LIKE ? OR e.locker LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end
    if status and status ~= 'all' then
        where[#where + 1] = 'e.status = ?'
        args[#args + 1] = status
    end

    local clause = table.concat(where, ' AND ')
    local total = MySQL.scalar.await(
        ('SELECT COUNT(*) FROM nz_mdt_evidence e WHERE %s'):format(clause), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(([[
        SELECT e.*, i.ref AS incident_ref,
               DATE_FORMAT(e.created_at, '%%d %%b · %%H:%%i') AS stamp,
               (SELECT COUNT(*) FROM nz_mdt_evidence_chain c WHERE c.evidence_id = e.id) AS chain_count
        FROM nz_mdt_evidence e
        LEFT JOIN nz_mdt_incidents i ON i.id = e.incident_id
        WHERE %s ORDER BY e.id DESC LIMIT ? OFFSET ?
    ]]):format(clause), qArgs) or {}

    local out = {}
    for _, e in ipairs(rows) do
        local card = evidenceCard(e)
        card.chainCount = e.chain_count or 0
        out[#out + 1] = card
    end

    return { ok = true, rows = out, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))

lib.callback.register('nz_mdt:evidence:get', MDT.guard('view.evidence', function(session, value)
    local key = tonumber(value)
    local byId = key and tostring(math.floor(key)) == tostring(value)
    local e = MySQL.single.await(([[
        SELECT e.*, i.ref AS incident_ref, DATE_FORMAT(e.created_at, '%%d %%b %%Y · %%H:%%i') AS stamp
        FROM nz_mdt_evidence e LEFT JOIN nz_mdt_incidents i ON i.id = e.incident_id
        WHERE %s = ?
    ]]):format(byId and 'e.id' or 'e.ref'), { byId and key or MDT.clean(value, 24) })
    if not e then return { ok = false, msg = 'That item is not in the locker system.' } end

    local chain = MySQL.query.await([[
        SELECT action, actor, note, DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
        FROM nz_mdt_evidence_chain WHERE evidence_id = ? ORDER BY id ASC
    ]], { e.id }) or {}

    return { ok = true, evidence = evidenceCard(e), chain = chain,
             notes  = MDT.getNotes(session, 'evidence', e.ref),
             photos = MDT.getPhotos('evidence', e.ref),
             links  = MDT.getLinks('evidence', e.ref) }
end))

lib.callback.register('nz_mdt:evidence:create', MDT.guard('evidence.create', function(session, data)
    local description = MDT.clean(data and data.description, 150)
    if #description < 3 then return { ok = false, msg = 'Describe the item.' } end

    local kind = 'physical'
    for _, t in ipairs(Config.Evidence.types) do if t.id == data.type then kind = t.id break end end

    local incidentId
    local incidentRef = MDT.opt(data.incidentRef, 20)
    if incidentRef then
        incidentId = MySQL.scalar.await('SELECT id FROM nz_mdt_incidents WHERE ref = ?', { incidentRef:upper() })
        if not incidentId then return { ok = false, msg = ('No report with the reference %s.'):format(incidentRef) } end
    end

    local locker = MDT.opt(data.locker, 60)
    local id, ref = MDT.insertWithRef('nz_mdt_evidence', Config.Evidence.idPrefix, 4, [[
        INSERT INTO nz_mdt_evidence (ref, description, type, location, locker, incident_id, collected_by, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'in')
    ]], { false, description, kind, MDT.opt(data.location, 120), locker, incidentId, session.name })
    if not id then return { ok = false, msg = 'The item could not be logged.' } end

    MySQL.insert.await(
        "INSERT INTO nz_mdt_evidence_chain (evidence_id, action, actor, note) VALUES (?, 'collected', ?, ?)",
        { id, session.name, MDT.opt(data.location, 200) })

    MDT.record(session, 'evidence', 'evidence.create', 'evidence', ref,
        'Evidence logged', ('**%s** · %s by %s'):format(ref, description, session.name))

    return { ok = true, msg = ('%s logged.'):format(ref), id = id, ref = ref }
end))

lib.callback.register('nz_mdt:evidence:checkout', MDT.guard('evidence.checkout', function(session, id, action, note)
    id = tonumber(id)
    local e = MySQL.single.await('SELECT * FROM nz_mdt_evidence WHERE id = ?', { id })
    if not e then return { ok = false, msg = 'That item is not in the locker system.' } end

    if e.status == 'destroyed' then return { ok = false, msg = 'That item has been destroyed.' } end

    local status, chainAction, holder
    if action == 'out' then
        if e.status == 'out' then
            return { ok = false, msg = ('%s already has this item signed out.'):format(e.holder or 'Someone') }
        end
        status, chainAction, holder = 'out', 'checked out', session.name
    elseif action == 'in' then
        if e.status == 'in' then return { ok = false, msg = 'That item is already in the locker.' } end
        status, chainAction, holder = 'in', 'checked in', nil
    elseif action == 'released' then
        status, chainAction, holder = 'released', 'released', nil
    elseif action == 'destroyed' then
        if not session.perms['evidence.delete'] then
            return { ok = false, msg = 'Only command can destroy evidence.' }
        end
        status, chainAction, holder = 'destroyed', 'destroyed', nil
    else
        return { ok = false, msg = 'Unknown action.' }
    end

    MySQL.update.await('UPDATE nz_mdt_evidence SET status = ?, holder = ? WHERE id = ?', { status, holder, id })
    MySQL.insert.await(
        'INSERT INTO nz_mdt_evidence_chain (evidence_id, action, actor, note) VALUES (?, ?, ?, ?)',
        { id, chainAction, session.name, MDT.clean(note, 200) })

    MDT.record(session, 'evidence', 'evidence.' .. action, 'evidence', e.ref,
        'Chain of custody', ('**%s** %s by %s'):format(e.ref, chainAction, session.name))

    return { ok = true, msg = ('%s %s.'):format(e.ref, chainAction) }
end))

lib.callback.register('nz_mdt:evidence:update', MDT.guard('evidence.edit', function(session, id, patch)
    if type(patch) ~= 'table' then return { ok = false, msg = 'Nothing to change.' } end

    local sets, args = {}, {}
    if patch.description then sets[#sets+1] = 'description = ?'; args[#args+1] = MDT.clean(patch.description, 150) end
    if patch.locker then sets[#sets+1] = 'locker = ?'; args[#args+1] = MDT.clean(patch.locker, 60) end
    if patch.location then sets[#sets+1] = 'location = ?'; args[#args+1] = MDT.clean(patch.location, 120) end
    if patch.type then sets[#sets+1] = 'type = ?'; args[#args+1] = MDT.clean(patch.type, 24) end
    if #sets == 0 then return { ok = false, msg = 'Nothing to change.' } end

    args[#args + 1] = tonumber(id)
    MySQL.update.await(('UPDATE nz_mdt_evidence SET %s WHERE id = ?'):format(table.concat(sets, ', ')), args)

    MDT.audit(session, 'evidence.edit', 'evidence', id, 'Item edited')
    return { ok = true, msg = 'Item updated.' }
end))

lib.callback.register('nz_mdt:evidence:photo', MDT.guard('evidence.edit', function(session, id, url)
    url = MDT.clean(url, 240)
    if not url:match('^https?://') then return { ok = false, msg = 'Photos need a full https link.' } end

    local e = MySQL.single.await('SELECT ref, photos FROM nz_mdt_evidence WHERE id = ?', { tonumber(id) })
    if not e then return { ok = false, msg = 'That item is not in the locker system.' } end

    local photos = MDT.decode(e.photos, {})
    if #photos >= 8 then return { ok = false, msg = 'That item already carries eight photos.' } end
    photos[#photos + 1] = url

    MySQL.update.await('UPDATE nz_mdt_evidence SET photos = ? WHERE id = ?', { json.encode(photos), tonumber(id) })
    MySQL.insert.await(
        "INSERT INTO nz_mdt_evidence_chain (evidence_id, action, actor, note) VALUES (?, 'photo added', ?, ?)",
        { tonumber(id), session.name, url })

    return { ok = true, msg = 'Photo attached.', photos = photos }
end))

lib.callback.register('nz_mdt:evidence:delete', MDT.guard('evidence.delete', function(session, id)
    local e = MySQL.single.await('SELECT ref FROM nz_mdt_evidence WHERE id = ?', { tonumber(id) })
    if not e then return { ok = false, msg = 'That item is gone already.' } end

    MySQL.update.await('DELETE FROM nz_mdt_evidence WHERE id = ?', { tonumber(id) })
    MDT.record(session, 'evidence', 'evidence.delete', 'evidence', e.ref,
        'Evidence deleted', ('**%s** deleted by %s'):format(e.ref, session.name))

    return { ok = true, msg = ('%s deleted.'):format(e.ref) }
end))

-- ═══════════════════════════════════════════════════════════
--  DASHBOARD SUMMARY
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:dashboard', function(src)
    local session = MDT.getSession(src)
    if not session then return { ok = false } end

    local incidents, warrants, announcements = {}, {}, {}

    if session.perms['view.incident'] then
        incidents = MySQL.query.await([[
            SELECT id, ref, title, location, status, total_fine, total_jail,
                   DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
            FROM nz_mdt_incidents ORDER BY id DESC LIMIT 6
        ]]) or {}
    end

    if session.perms['view.warrant'] then
        warrants = MySQL.query.await([[
            SELECT id, citizen_id, citizen_name, type, title, detail, issued_by,
                   DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
            FROM nz_mdt_warrants WHERE status = 'active' ORDER BY id DESC LIMIT 6
        ]]) or {}
    end

    if session.perms['view.announcement'] then
        announcements = MySQL.query.await([[
            SELECT id, title, body, pinned, author, DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
            FROM nz_mdt_announcements
            WHERE (department IS NULL OR department = ?) AND (expires_at IS NULL OR expires_at > ?)
            ORDER BY pinned DESC, id DESC LIMIT 4
        ]], { session.department, os.time() }) or {}
    end

    local calls = session.perms['view.dispatch'] and MDT.getBoard(session, false) or {}

    local counts = {
        openIncidents = MySQL.scalar.await("SELECT COUNT(*) FROM nz_mdt_incidents WHERE status != 'closed'") or 0,
        activeWarrants= MySQL.scalar.await("SELECT COUNT(*) FROM nz_mdt_warrants WHERE status = 'active'") or 0,
        activeBolos   = MySQL.scalar.await("SELECT COUNT(*) FROM nz_mdt_bolos WHERE status = 'active'") or 0,
        openCalls     = #calls,
        evidenceOut   = MySQL.scalar.await("SELECT COUNT(*) FROM nz_mdt_evidence WHERE status = 'out'") or 0
    }

    -- department performance over the trailing window
    local days = Config.Incident.statsDays or 30
    local arrests = MySQL.scalar.await([[
        SELECT COUNT(DISTINCT i.id) FROM nz_mdt_incidents i
        JOIN nz_mdt_incident_charges c ON c.incident_id = i.id
        WHERE c.jail > 0 AND i.created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { days }) or 0

    local citations = MySQL.scalar.await([[
        SELECT COUNT(DISTINCT i.id) FROM nz_mdt_incidents i
        JOIN nz_mdt_incident_charges c ON c.incident_id = i.id
        WHERE c.jail = 0 AND c.fine > 0 AND i.created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { days }) or 0

    local filed = MySQL.scalar.await(
        'SELECT COUNT(*) FROM nz_mdt_incidents WHERE created_at > DATE_SUB(NOW(), INTERVAL ? DAY)',
        { days }) or 0

    local closed = MySQL.scalar.await([[
        SELECT COUNT(*) FROM nz_mdt_incidents
        WHERE status = 'closed' AND created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { days }) or 0

    local stats = {
        days       = days,
        arrests    = arrests,
        citations  = citations,
        filed      = filed,
        closed     = closed,
        clearance  = filed > 0 and math.floor((closed / filed) * 100) or 0,
        revenue    = MySQL.scalar.await([[
            SELECT COALESCE(SUM(total_fine), 0) FROM nz_mdt_incidents
            WHERE status = 'closed' AND created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { days }) or 0,
        myReports  = MySQL.scalar.await([[
            SELECT COUNT(*) FROM nz_mdt_incidents
            WHERE creator_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { session.identifier, days }) or 0
    }

    local officer = MDT.getOfficer(session.identifier)
    local live = officer and MDT.bool(officer.on_duty) and officer.last_on and (os.time() - officer.last_on) or 0

    return {
        ok = true,
        counts    = counts,
        stats     = stats,
        incidents = incidents,
        warrants  = warrants,
        announcements = announcements,
        officers  = MDT.activeOfficers(),
        calls     = calls,
        me = {
            onDuty       = officer and MDT.bool(officer.on_duty) or false,
            status       = officer and officer.status or 'available',
            callsign     = officer and officer.callsign or nil,
            badge        = officer and officer.badge or nil,
            shiftMinutes = math.floor(live / 60),
            totalHours   = math.floor(((officer and officer.duty_seconds or 0) + live) / 3600)
        }
    }
end)
