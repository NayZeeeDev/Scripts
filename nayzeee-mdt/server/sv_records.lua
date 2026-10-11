-- ═══════════════════════════════════════════════════════════
--  REGISTRIES — citizens · vehicles · weapons · properties
-- ═══════════════════════════════════════════════════════════

local function newCitizenId()
    for _ = 1, 12 do
        local id = ('CZ%s'):format(MDT.rand(8))
        if not MySQL.scalar.await('SELECT id FROM nz_mdt_citizens WHERE citizen_id = ?', { id }) then
            return id
        end
    end
    return ('CZ%s'):format(os.time())
end

--- Normalise a plate for storage and lookup. Wrapped so only the string comes back
--- (gsub's second return value used to leak into SQL parameter lists).
local function plateKey(plate)
    plate = tostring(plate or ''):upper()
    if Config.Registry.trimPlates then plate = MDT.trim(plate) end
    return (plate:gsub('%s+$', ''))
end
MDT.plateKey = plateKey

local function ownerName(citizenId)
    if not citizenId then return nil end
    local c = MySQL.single.await('SELECT first_name, last_name FROM nz_mdt_citizens WHERE citizen_id = ?', { citizenId })
    return c and ('%s %s'):format(c.first_name, c.last_name) or nil
end

-- ═══════════════════════════════════════════════════════════
--  IMPORT FROM ESX
-- ═══════════════════════════════════════════════════════════
--- Pull an ESX user into the MDT registry the first time they are looked up.
--- @param force boolean import even when auto-import is switched off (admin bulk import)
function MDT.importCitizen(identifier, force)
    if not force and not Config.Registry.autoImportCitizens then return nil end

    local existing = MySQL.single.await('SELECT * FROM nz_mdt_citizens WHERE identifier = ?', { identifier })
    if existing then return existing end

    local ok, user = pcall(MySQL.single.await,
        'SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number, job FROM users WHERE identifier = ?',
        { identifier })
    if not ok or not user then return nil end

    local id = newCitizenId()
    MySQL.insert.await([[
        INSERT INTO nz_mdt_citizens (identifier, citizen_id, first_name, last_name, dob, gender, phone, job, fingerprint, dna)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE first_name = VALUES(first_name), last_name = VALUES(last_name)
    ]], {
        identifier, id,
        user.firstname or 'Unknown', user.lastname or 'Unknown',
        user.dateofbirth, user.sex == 'm' and 'Male' or user.sex == 'f' and 'Female' or user.sex,
        user.phone_number, user.job,
        ('FP%s'):format(MDT.rand(10)), ('DNA%s'):format(MDT.rand(10))
    })

    return MySQL.single.await('SELECT * FROM nz_mdt_citizens WHERE identifier = ?', { identifier })
end

--- Import every ESX-owned vehicle for a citizen the first time we see them.
--- Owned-vehicle rows store the model as a hash; turn the stock ones back into names.
local modelNames
function MDT.modelName(model)
    if model == nil then return nil end
    if type(model) == 'string' and not tonumber(model) then return model:sub(1, 40) end
    if not modelNames then
        modelNames = {}
        for _, name in ipairs(Config.VehicleModels or {}) do modelNames[joaat(name)] = name end
    end
    local hash = math.floor(tonumber(model) or 0)
    if hash < 0 then hash = hash + 4294967296 end
    return modelNames[hash] or modelNames[hash - 4294967296] or tostring(model)
end

local function importVehicles(citizen)
    if not Config.Registry.autoImportVehicles or not citizen.identifier then return end

    local ok, rows = pcall(MySQL.query.await,
        ('SELECT plate, vehicle FROM %s WHERE owner = ?'):format(Config.Registry.vehiclesTable),
        { citizen.identifier })
    if not ok or not rows then return end

    for _, v in ipairs(rows) do
        local plate = plateKey(v.plate)
        if plate ~= '' then
            local props = MDT.decode(v.vehicle, {})
            MySQL.insert.await([[
                INSERT IGNORE INTO nz_mdt_vehicles (plate, model, type, owner_id, owner_name, vin)
                VALUES (?, ?, ?, ?, ?, ?)
            ]], {
                plate,
                MDT.modelName(props.model),
                nil,
                citizen.citizen_id,
                ('%s %s'):format(citizen.first_name, citizen.last_name),
                ('VIN%s'):format(MDT.rand(11))
            })
        end
    end
end

-- ═══════════════════════════════════════════════════════════
--  SERIALISERS
-- ═══════════════════════════════════════════════════════════
local function citizenCard(c)
    return {
        id        = c.citizen_id,
        rowId     = c.id,
        identifier= c.identifier,
        first     = c.first_name,
        last      = c.last_name,
        name      = ('%s %s'):format(c.first_name, c.last_name),
        dob       = c.dob,
        gender    = c.gender,
        phone     = c.phone,
        job       = c.job,
        address   = c.address,
        height    = c.height,
        hair      = c.hair,
        eyes      = c.eyes,
        mugshot   = c.mugshot,
        licences  = MDT.decode(c.licences, {}),
        flags     = MDT.decode(c.flags, {}),
        fingerprint = c.fingerprint,
        dna       = c.dna
    }
end

local function vehicleCard(v)
    return {
        id       = v.id,
        plate    = v.plate,
        model    = v.model,
        type     = v.type,
        colour   = v.colour,
        vin      = v.vin,
        ownerId  = v.owner_id,
        ownerName= v.owner_name,
        insurance= v.insurance,
        registration = v.registration,
        stolen   = MDT.bool(v.stolen),
        impounded= MDT.bool(v.impounded),
        flags    = MDT.decode(v.flags, {}),
        photo    = v.photo
    }
end

local function weaponCard(w)
    return {
        id       = w.id,
        serial   = w.serial,
        label    = w.label,
        weapon   = w.weapon_name,
        ownerId  = w.owner_id,
        ownerName= w.owner_name,
        status   = w.status,
        flags    = MDT.decode(w.flags, {}),
        registered = MDT.date(w.registered_at)
    }
end

-- ═══════════════════════════════════════════════════════════
--  CITIZENS
-- ═══════════════════════════════════════════════════════════
--- Pull ESX characters matching a search into the registry, so officers can
--- find anyone who has ever played without an admin running an import.
local importedSearches = {}
local function importMatching(search)
    if not Config.Registry.autoImportCitizens or #search < 3 then return end
    local key = search:lower()
    if importedSearches[key] and os.time() - importedSearches[key] < 300 then return end
    importedSearches[key] = os.time()

    local ok, users = pcall(MySQL.query.await, [[
        SELECT u.identifier FROM users u
        LEFT JOIN nz_mdt_citizens c ON c.identifier = u.identifier
        WHERE c.id IS NULL AND (CONCAT(u.firstname, ' ', u.lastname) LIKE ? OR u.phone_number LIKE ?)
        LIMIT 10
    ]], { '%' .. search .. '%', '%' .. search .. '%' })
    if not ok or not users then return end
    for _, u in ipairs(users) do MDT.importCitizen(u.identifier) end
end

lib.callback.register('nz_mdt:citizen:list', MDT.guard('view.citizen', function(session, search, page)
    search = MDT.clean(search, 40)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = 12

    if search ~= '' then importMatching(search) end

    local where, args = '1 = 1', {}
    if search ~= '' then
        where = [[(CONCAT(first_name, ' ', last_name) LIKE ? OR citizen_id LIKE ? OR phone LIKE ?
                   OR fingerprint LIKE ? OR dna LIKE ? OR dob LIKE ?)]]
        for _ = 1, 6 do args[#args + 1] = '%' .. search .. '%' end
    end

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_mdt_citizens WHERE %s'):format(where), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(
        ('SELECT * FROM nz_mdt_citizens WHERE %s ORDER BY last_name ASC, first_name ASC LIMIT ? OFFSET ?'):format(where),
        qArgs) or {}

    local out = {}
    for _, c in ipairs(rows) do out[#out + 1] = citizenCard(c) end

    return { ok = true, rows = out, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))

--- Full profile: record, vehicles, weapons, properties, warrants, incidents, notes.
lib.callback.register('nz_mdt:citizen:profile', MDT.guard('view.citizen', function(session, citizenId)
    citizenId = MDT.clean(citizenId, 32)
    local c = MySQL.single.await('SELECT * FROM nz_mdt_citizens WHERE citizen_id = ?', { citizenId })
    if not c then return { ok = false, msg = 'No record with that ID.' } end

    importVehicles(c)

    local vehicles = MySQL.query.await('SELECT * FROM nz_mdt_vehicles WHERE owner_id = ? LIMIT 40', { citizenId }) or {}
    local weapons  = MySQL.query.await('SELECT * FROM nz_mdt_weapons WHERE owner_id = ? LIMIT 40', { citizenId }) or {}
    local props    = MySQL.query.await('SELECT * FROM nz_mdt_properties WHERE owner_id = ? LIMIT 20', { citizenId }) or {}

    local warrants = MySQL.query.await([[
        SELECT id, type, title, status, issued_by, DATE_FORMAT(created_at, '%d %b %Y') AS stamp
        FROM nz_mdt_warrants WHERE citizen_id = ? ORDER BY (status = 'active') DESC, id DESC LIMIT 20
    ]], { citizenId }) or {}

    local incidents = MySQL.query.await([[
        SELECT i.id, i.ref, i.title, i.status, i.total_fine, i.total_jail,
               DATE_FORMAT(i.created_at, '%d %b %Y') AS stamp
        FROM nz_mdt_incidents i
        LEFT JOIN nz_mdt_incident_people p ON p.incident_id = i.id
        WHERE i.primary_id = ? OR p.citizen_id = ?
        GROUP BY i.id ORDER BY i.id DESC LIMIT 25
    ]], { citizenId, citizenId }) or {}

    local charges = MySQL.query.await([[
        SELECT label, class, SUM(counts) AS counts, SUM(fine) AS fine, SUM(jail) AS jail
        FROM nz_mdt_incident_charges WHERE citizen_id = ? GROUP BY charge_id ORDER BY counts DESC LIMIT 30
    ]], { citizenId }) or {}

    local totals = MySQL.single.await([[
        SELECT COALESCE(SUM(fine),0) AS fine, COALESCE(SUM(jail),0) AS jail, COUNT(*) AS count
        FROM nz_mdt_incident_charges WHERE citizen_id = ?
    ]], { citizenId }) or {}

    local vOut, wOut, pOut = {}, {}, {}
    for _, v in ipairs(vehicles) do vOut[#vOut + 1] = vehicleCard(v) end
    for _, w in ipairs(weapons) do wOut[#wOut + 1] = weaponCard(w) end
    for _, p in ipairs(props) do
        pOut[#pOut + 1] = { id = p.id, label = p.label, address = p.address, type = p.type }
    end

    -- flag the officer when there is a live warrant
    local activeWarrants = 0
    for _, w in ipairs(warrants) do if w.status == 'active' then activeWarrants = activeWarrants + 1 end end
    if activeWarrants > 0 and Config.Warrant.alertOnLookup then
        MDT.notify(session.source, 'Wanted',
            ('%s %s has %s active warrant%s.'):format(c.first_name, c.last_name, activeWarrants,
                activeWarrants == 1 and '' or 's'), 'error')
    end

    MDT.audit(session, 'citizen.view', 'citizen', citizenId, 'Profile opened')

    return {
        ok        = true,
        citizen   = citizenCard(c),
        vehicles  = vOut,
        weapons   = wOut,
        properties= pOut,
        warrants  = warrants,
        incidents = incidents,
        charges   = charges,
        record    = {
            charges = tonumber(totals.count) or 0,
            fine    = tonumber(totals.fine) or 0,
            jail    = tonumber(totals.jail) or 0,
            wanted  = activeWarrants > 0
        },
        notes     = MDT.getNotes(session, 'citizen', citizenId),
        photos    = MDT.getPhotos('citizen', citizenId),
        links     = MDT.getLinks('citizen', citizenId)
    }
end))

lib.callback.register('nz_mdt:citizen:create', MDT.guard('citizen.create', function(session, data)
    local first = MDT.clean(data and data.first, 40)
    local last  = MDT.clean(data and data.last, 40)
    if #first < 2 or #last < 2 then return { ok = false, msg = 'A first and last name are required.' } end

    local id = newCitizenId()
    MySQL.insert.await([[
        INSERT INTO nz_mdt_citizens
          (identifier, citizen_id, first_name, last_name, dob, gender, phone, job, address, height, hair, eyes, fingerprint, dna)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        MDT.opt(data.identifier, 64), id, first, last,
        MDT.opt(data.dob, 16), MDT.opt(data.gender, 16), MDT.opt(data.phone, 24),
        MDT.opt(data.job, 48), MDT.opt(data.address, 90),
        MDT.opt(data.height, 16), MDT.opt(data.hair, 24), MDT.opt(data.eyes, 24),
        ('FP%s'):format(MDT.rand(10)), ('DNA%s'):format(MDT.rand(10))
    })

    MDT.record(session, 'records', 'citizen.create', 'citizen', id,
        'Citizen registered', ('**%s %s** added by %s'):format(first, last, session.name))

    return { ok = true, msg = ('%s %s is on file.'):format(first, last), id = id }
end))

lib.callback.register('nz_mdt:citizen:update', MDT.guard('citizen.edit', function(session, citizenId, patch)
    if type(patch) ~= 'table' then return { ok = false, msg = 'Nothing to change.' } end

    local map = {
        first = 'first_name', last = 'last_name', dob = 'dob', gender = 'gender',
        phone = 'phone', job = 'job', address = 'address',
        height = 'height', hair = 'hair', eyes = 'eyes', mugshot = 'mugshot'
    }

    if patch.first ~= nil and #MDT.clean(patch.first, 40) < 2 then return { ok = false, msg = 'A first name is required.' } end
    if patch.last ~= nil and #MDT.clean(patch.last, 40) < 2 then return { ok = false, msg = 'A last name is required.' } end

    local sets, args = {}, {}
    for key, column in pairs(map) do
        if patch[key] ~= nil then
            sets[#sets + 1] = column .. ' = ?'
            args[#args + 1] = MDT.opt(patch[key], key == 'mugshot' and 255 or 96)
        end
    end
    if #sets == 0 then return { ok = false, msg = 'Nothing to change.' } end

    args[#args + 1] = citizenId
    MySQL.update.await(('UPDATE nz_mdt_citizens SET %s WHERE citizen_id = ?'):format(table.concat(sets, ', ')), args)

    MDT.audit(session, 'citizen.edit', 'citizen', citizenId, 'Profile edited')
    return { ok = true, msg = 'Record updated.' }
end))

lib.callback.register('nz_mdt:citizen:licence', MDT.guard('citizen.licence', function(session, citizenId, licence, state)
    local valid = false
    for _, l in ipairs(Config.Registry.licences) do if l.id == licence then valid = true break end end
    if not valid then return { ok = false, msg = 'Unknown licence type.' } end

    local allowed = { valid = true, suspended = true, revoked = true, none = true }
    if not allowed[state] then return { ok = false, msg = 'Unknown licence state.' } end

    local c = MySQL.single.await('SELECT licences FROM nz_mdt_citizens WHERE citizen_id = ?', { citizenId })
    if not c then return { ok = false, msg = 'No record with that ID.' } end

    local licences = MDT.decode(c.licences, {})
    licences[licence] = state
    MySQL.update.await('UPDATE nz_mdt_citizens SET licences = ? WHERE citizen_id = ?',
        { json.encode(licences), citizenId })

    MDT.record(session, 'records', 'citizen.licence', 'citizen', citizenId,
        'Licence changed', ('%s licence set to **%s** by %s'):format(licence, state, session.name))

    return { ok = true, msg = ('Licence set to %s.'):format(state), licences = licences }
end))

lib.callback.register('nz_mdt:citizen:flag', MDT.guard('citizen.note', function(session, citizenId, label, tone, remove)
    local c = MySQL.single.await('SELECT flags FROM nz_mdt_citizens WHERE citizen_id = ?', { citizenId })
    if not c then return { ok = false, msg = 'No record with that ID.' } end

    local flags = MDT.decode(c.flags, {})
    label = MDT.clean(label, 40)

    if remove then
        for i = #flags, 1, -1 do
            if flags[i].label == label then table.remove(flags, i) end
        end
    else
        if #label < 2 then return { ok = false, msg = 'Give the flag a label.' } end
        if #flags >= 8 then return { ok = false, msg = 'That record already carries eight flags.' } end
        for _, f in ipairs(flags) do
            if f.label == label then return { ok = false, msg = 'That flag is already on the record.' } end
        end
        flags[#flags + 1] = {
            label = label,
            tone  = (tone == 'red' or tone == 'amber') and tone or 'teal',
            by    = session.name,
            at    = os.date('%d %b %Y')
        }
    end

    MySQL.update.await('UPDATE nz_mdt_citizens SET flags = ? WHERE citizen_id = ?', { json.encode(flags), citizenId })
    MDT.audit(session, remove and 'citizen.unflag' or 'citizen.flag', 'citizen', citizenId, label)

    return { ok = true, msg = remove and 'Flag removed.' or 'Flag added.', flags = flags }
end))

lib.callback.register('nz_mdt:citizen:delete', MDT.guard('citizen.delete', function(session, citizenId)
    MySQL.update.await('DELETE FROM nz_mdt_citizens WHERE citizen_id = ?', { citizenId })
    MDT.record(session, 'records', 'citizen.delete', 'citizen', citizenId,
        'Citizen record deleted', ('`%s` removed by %s'):format(citizenId, session.name))
    return { ok = true, msg = 'Record deleted.' }
end))

--- Search for online players to attach to a record (register-citizen flow).
lib.callback.register('nz_mdt:players:search', MDT.guard('view.citizen', function(session, search)
    search = MDT.clean(search, 32):lower()
    local out = {}

    for _, id in ipairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(id))
        if xPlayer then
            local name = MDT.fullName(xPlayer)
            if search == '' or name:lower():find(search, 1, true) or tostring(id) == search then
                out[#out + 1] = {
                    source     = tonumber(id),
                    name       = name,
                    identifier = xPlayer.identifier,
                    job        = xPlayer.job.label or xPlayer.job.name
                }
            end
        end
        if #out >= 20 then break end
    end

    return { ok = true, rows = out }
end))

-- ═══════════════════════════════════════════════════════════
--  VEHICLES
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:vehicle:list', MDT.guard('view.vehicle', function(session, search, page, filter)
    search = plateKey(MDT.clean(search, 24))
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = 12

    local where, args = { '1 = 1' }, {}
    if search ~= '' then
        where[#where + 1] = '(plate LIKE ? OR model LIKE ? OR owner_name LIKE ? OR vin LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end
    if filter == 'stolen' then where[#where + 1] = 'stolen = 1' end
    if filter == 'impounded' then where[#where + 1] = 'impounded = 1' end

    local clause = table.concat(where, ' AND ')
    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_mdt_vehicles WHERE %s'):format(clause), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(
        ('SELECT * FROM nz_mdt_vehicles WHERE %s ORDER BY stolen DESC, id DESC LIMIT ? OFFSET ?'):format(clause),
        qArgs) or {}

    local out = {}
    for _, v in ipairs(rows) do out[#out + 1] = vehicleCard(v) end
    return { ok = true, rows = out, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))

--- Plate lookup used by both the UI and the ALPR.
function MDT.lookupPlate(plate)
    plate = plateKey(plate)
    if plate == '' then return nil end

    local v = MySQL.single.await('SELECT * FROM nz_mdt_vehicles WHERE plate = ?', { plate })
    if v then return v end

    if not Config.Registry.autoImportVehicles then return nil end

    local ok, owned = pcall(MySQL.single.await,
        ('SELECT owner, plate, vehicle FROM %s WHERE REPLACE(plate, ' .. "' '" .. ", '') = ?"):format(Config.Registry.vehiclesTable),
        { (plate:gsub('%s', '')) })
    if not ok or not owned then return nil end

    local citizen = MySQL.single.await('SELECT * FROM nz_mdt_citizens WHERE identifier = ?', { owned.owner })
                    or MDT.importCitizen(owned.owner)

    local props = MDT.decode(owned.vehicle, {})
    MySQL.insert.await([[
        INSERT IGNORE INTO nz_mdt_vehicles (plate, model, owner_id, owner_name, vin)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        plate,
        MDT.modelName(props.model),
        citizen and citizen.citizen_id or nil,
        citizen and ('%s %s'):format(citizen.first_name, citizen.last_name) or nil,
        ('VIN%s'):format(MDT.rand(11))
    })

    return MySQL.single.await('SELECT * FROM nz_mdt_vehicles WHERE plate = ?', { plate })
end

lib.callback.register('nz_mdt:vehicle:profile', MDT.guard('view.vehicle', function(session, plate)
    local v = MDT.lookupPlate(plate)
    if not v then return { ok = false, msg = 'That plate is not on the registry.' } end

    local owner
    if v.owner_id then
        local c = MySQL.single.await('SELECT * FROM nz_mdt_citizens WHERE citizen_id = ?', { v.owner_id })
        if c then owner = citizenCard(c) end
    end

    local bolos = MySQL.query.await([[
        SELECT id, title, detail, status, issued_by, DATE_FORMAT(created_at, '%d %b · %H:%i') AS stamp
        FROM nz_mdt_bolos WHERE plate = ? ORDER BY (status = 'active') DESC, id DESC LIMIT 10
    ]], { v.plate }) or {}

    MDT.audit(session, 'vehicle.view', 'vehicle', v.plate, 'Plate looked up')

    return {
        ok      = true,
        vehicle = vehicleCard(v),
        owner   = owner,
        bolos   = bolos,
        notes   = MDT.getNotes(session, 'vehicle', v.plate),
        photos  = MDT.getPhotos('vehicle', v.plate),
        links   = MDT.getLinks('vehicle', v.plate)
    }
end))

lib.callback.register('nz_mdt:vehicle:create', MDT.guard('vehicle.create', function(session, data)
    local plate = plateKey(MDT.clean(data and data.plate, 12))
    if #plate < 2 then return { ok = false, msg = 'Enter a plate.' } end

    if MySQL.scalar.await('SELECT id FROM nz_mdt_vehicles WHERE plate = ?', { plate }) then
        return { ok = false, msg = 'That plate is already registered.' }
    end

    local ownerId = MDT.opt(data.ownerId, 32)
    local owner = ownerName(ownerId)
    if ownerId and not owner then return { ok = false, msg = 'No citizen record with that owner ID.' } end

    local insurance = ({ valid = 1, expired = 1, none = 1, unknown = 1 })[data.insurance] and data.insurance or 'unknown'
    local registration = ({ valid = 1, expired = 1, revoked = 1 })[data.registration] and data.registration or 'valid'

    MySQL.insert.await([[
        INSERT INTO nz_mdt_vehicles (plate, model, type, colour, vin, owner_id, owner_name, insurance, registration)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        plate, MDT.opt(data.model, 40), MDT.opt(data.type, 24), MDT.opt(data.colour, 24),
        ('VIN%s'):format(MDT.rand(11)), ownerId, owner, insurance, registration
    })

    MDT.record(session, 'records', 'vehicle.create', 'vehicle', plate,
        'Vehicle registered', ('`%s` registered by %s'):format(plate, session.name))

    return { ok = true, msg = ('%s is on the registry.'):format(plate), plate = plate }
end))

--- vehicle.edit can change anything; vehicle.flag can only flip stolen / impounded.
lib.callback.register('nz_mdt:vehicle:update', function(src, plate, patch)
    local session = MDT.getSession(src)
    if not session then return { ok = false, msg = 'You are not on a department roster.' } end
    if type(patch) ~= 'table' then return { ok = false, msg = 'Nothing to change.' } end

    if not session.perms['vehicle.edit'] then
        if not session.perms['vehicle.flag'] then return { ok = false, msg = 'Your rank does not allow that.' } end
        patch = { stolen = patch.stolen, impounded = patch.impounded }
    end

    plate = plateKey(plate)
    if not MySQL.scalar.await('SELECT id FROM nz_mdt_vehicles WHERE plate = ?', { plate }) then
        return { ok = false, msg = 'That plate is not on the registry.' }
    end

    local map = { model = 'model', type = 'type', colour = 'colour' }
    local enums = {
        insurance    = { valid = 1, expired = 1, none = 1, unknown = 1 },
        registration = { valid = 1, expired = 1, revoked = 1 }
    }

    local sets, args = {}, {}
    for key, column in pairs(map) do
        if patch[key] ~= nil then
            sets[#sets + 1] = column .. ' = ?'
            args[#args + 1] = MDT.opt(patch[key], 40)
        end
    end
    for key, allowed in pairs(enums) do
        if patch[key] ~= nil and allowed[patch[key]] then
            sets[#sets + 1] = key .. ' = ?'
            args[#args + 1] = patch[key]
        end
    end
    if patch.stolen ~= nil then sets[#sets + 1] = 'stolen = ?'; args[#args + 1] = patch.stolen and 1 or 0 end
    if patch.impounded ~= nil then sets[#sets + 1] = 'impounded = ?'; args[#args + 1] = patch.impounded and 1 or 0 end
    if #sets == 0 then return { ok = false, msg = 'Nothing to change.' } end

    args[#args + 1] = plate
    MySQL.update.await(('UPDATE nz_mdt_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', ')), args)

    if patch.stolen ~= nil then
        MDT.record(session, 'records', 'vehicle.stolen', 'vehicle', plate,
            patch.stolen and 'Vehicle flagged stolen' or 'Stolen flag cleared',
            ('`%s` by %s'):format(plate, session.name))
    elseif patch.impounded ~= nil then
        MDT.audit(session, 'vehicle.impound', 'vehicle', plate, patch.impounded and 'Impounded' or 'Released')
    else
        MDT.audit(session, 'vehicle.edit', 'vehicle', plate, 'Registry entry edited')
    end

    return { ok = true, msg = 'Registry updated.' }
end)

--- The tablet resolved a numeric model hash into a name; store it once.
lib.callback.register('nz_mdt:vehicle:model', MDT.guard('view.vehicle', function(session, plate, name)
    name = MDT.clean(name, 40)
    if name == '' then return { ok = false } end
    MySQL.update.await("UPDATE nz_mdt_vehicles SET model = ? WHERE plate = ? AND model REGEXP '^-{0,1}[0-9]+$'",
        { name, plateKey(plate) })
    return { ok = true }
end))

lib.callback.register('nz_mdt:vehicle:delete', MDT.guard('vehicle.delete', function(session, plate)
    MySQL.update.await('DELETE FROM nz_mdt_vehicles WHERE plate = ?', { plateKey(plate) })
    MDT.record(session, 'records', 'vehicle.delete', 'vehicle', plate,
        'Vehicle removed', ('`%s` removed by %s'):format(plate, session.name))
    return { ok = true, msg = 'Vehicle removed from the registry.' }
end))

-- ═══════════════════════════════════════════════════════════
--  WEAPONS
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:weapon:list', MDT.guard('view.weapon', function(session, search, page)
    search = MDT.clean(search, 32)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = 12

    local where, args = '1 = 1', {}
    if search ~= '' then
        where = '(serial LIKE ? OR label LIKE ? OR owner_name LIKE ? OR weapon_name LIKE ?)'
        for _ = 1, 4 do args[#args + 1] = '%' .. search .. '%' end
    end

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_mdt_weapons WHERE %s'):format(where), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(
        ('SELECT * FROM nz_mdt_weapons WHERE %s ORDER BY id DESC LIMIT ? OFFSET ?'):format(where), qArgs) or {}

    local out = {}
    for _, w in ipairs(rows) do out[#out + 1] = weaponCard(w) end
    return { ok = true, rows = out, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))

lib.callback.register('nz_mdt:weapon:profile', MDT.guard('view.weapon', function(session, serial)
    local w = MySQL.single.await('SELECT * FROM nz_mdt_weapons WHERE serial = ?', { MDT.clean(serial, 32) })
    if not w then return { ok = false, msg = 'That serial is not on the registry.' } end

    local owner
    if w.owner_id then
        local c = MySQL.single.await('SELECT * FROM nz_mdt_citizens WHERE citizen_id = ?', { w.owner_id })
        if c then owner = citizenCard(c) end
    end

    MDT.audit(session, 'weapon.view', 'weapon', w.serial, 'Serial looked up')

    return { ok = true, weapon = weaponCard(w), owner = owner,
             notes  = MDT.getNotes(session, 'weapon', w.serial),
             photos = MDT.getPhotos('weapon', w.serial),
             links  = MDT.getLinks('weapon', w.serial) }
end))

lib.callback.register('nz_mdt:weapon:create', MDT.guard('weapon.create', function(session, data)
    local label = MDT.clean(data and data.label, 60)
    if #label < 2 then return { ok = false, msg = 'Name the weapon.' } end

    local serial = MDT.clean(data.serial, 32):upper()
    if serial == '' then serial = ('WP%s'):format(MDT.rand(10)) end
    if MySQL.scalar.await('SELECT id FROM nz_mdt_weapons WHERE serial = ?', { serial }) then
        return { ok = false, msg = 'That serial is already registered.' }
    end

    local ownerId = MDT.opt(data.ownerId, 32)
    local owner = ownerName(ownerId)
    if ownerId and not owner then return { ok = false, msg = 'No citizen record with that owner ID.' } end

    MySQL.insert.await([[
        INSERT INTO nz_mdt_weapons (serial, label, weapon_name, owner_id, owner_name, status)
        VALUES (?, ?, ?, ?, ?, 'registered')
    ]], { serial, label, MDT.opt(data.weapon, 60), ownerId, owner })

    MDT.record(session, 'records', 'weapon.create', 'weapon', serial,
        'Weapon registered', ('**%s** `%s` by %s'):format(label, serial, session.name))

    return { ok = true, msg = 'Weapon registered.', serial = serial }
end))

lib.callback.register('nz_mdt:weapon:update', MDT.guard('weapon.edit', function(session, serial, patch)
    local allowed = { registered = true, stolen = true, seized = true, destroyed = true }
    local sets, args = {}, {}

    if patch and patch.status and allowed[patch.status] then
        sets[#sets + 1] = 'status = ?'; args[#args + 1] = patch.status
    end
    if patch and patch.label then sets[#sets + 1] = 'label = ?'; args[#args + 1] = MDT.clean(patch.label, 60) end
    if #sets == 0 then return { ok = false, msg = 'Nothing to change.' } end

    args[#args + 1] = MDT.clean(serial, 32)
    MySQL.update.await(('UPDATE nz_mdt_weapons SET %s WHERE serial = ?'):format(table.concat(sets, ', ')), args)

    MDT.audit(session, 'weapon.edit', 'weapon', serial, patch.status or 'edited')
    return { ok = true, msg = 'Registry updated.' }
end))

lib.callback.register('nz_mdt:weapon:delete', MDT.guard('weapon.delete', function(session, serial)
    MySQL.update.await('DELETE FROM nz_mdt_weapons WHERE serial = ?', { MDT.clean(serial, 32) })
    MDT.record(session, 'records', 'weapon.delete', 'weapon', serial,
        'Weapon removed', ('`%s` removed by %s'):format(serial, session.name))
    return { ok = true, msg = 'Weapon removed from the registry.' }
end))

-- ═══════════════════════════════════════════════════════════
--  PROPERTIES
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:property:list', MDT.guard('view.property', function(session, search, page)
    search = MDT.clean(search, 40)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local size = 12

    local where, args = '1 = 1', {}
    if search ~= '' then
        where = '(label LIKE ? OR address LIKE ? OR owner_name LIKE ?)'
        for _ = 1, 3 do args[#args + 1] = '%' .. search .. '%' end
    end

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_mdt_properties WHERE %s'):format(where), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = size
    qArgs[#qArgs + 1] = (page - 1) * size

    local rows = MySQL.query.await(
        ('SELECT * FROM nz_mdt_properties WHERE %s ORDER BY id DESC LIMIT ? OFFSET ?'):format(where), qArgs) or {}

    for _, p in ipairs(rows) do p.flags = MDT.decode(p.flags, {}) end

    return { ok = true, rows = rows, page = page, pages = math.max(1, math.ceil(total / size)), total = total }
end))

lib.callback.register('nz_mdt:property:create', MDT.guard('property.create', function(session, data)
    local label   = MDT.clean(data and data.label, 90)
    local address = MDT.clean(data and data.address, 120)
    if #label < 2 or #address < 3 then return { ok = false, msg = 'Give it a name and an address.' } end

    local ownerId = MDT.opt(data.ownerId, 32)
    local owner = ownerName(ownerId)
    if ownerId and not owner then return { ok = false, msg = 'No citizen record with that owner ID.' } end

    local kind = ({ residential = 1, commercial = 1, industrial = 1, warehouse = 1 })[data.type] and data.type or 'residential'

    local id = MySQL.insert.await([[
        INSERT INTO nz_mdt_properties (label, address, type, owner_id, owner_name, coords)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { label, address, kind, ownerId, owner, MDT.opt(data.coords, 60) })

    MDT.record(session, 'records', 'property.create', 'property', id,
        'Property registered', ('**%s** — %s'):format(label, address))

    return { ok = true, msg = 'Property registered.', id = id }
end))

lib.callback.register('nz_mdt:property:delete', MDT.guard('property.delete', function(session, id)
    MySQL.update.await('DELETE FROM nz_mdt_properties WHERE id = ?', { tonumber(id) })
    MDT.audit(session, 'property.delete', 'property', id, 'Property removed')
    return { ok = true, msg = 'Property removed.' }
end))

-- ═══════════════════════════════════════════════════════════
--  GLOBAL SEARCH  (the omni-bar on the dashboard)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:search', function(src, term)
    local session = MDT.getSession(src)
    if not session then return { ok = false, rows = {} } end

    term = MDT.clean(term, 40)
    if #term < 2 then return { ok = true, rows = {} } end
    local like = '%' .. term .. '%'
    local rows = {}

    if session.perms['view.citizen'] then importMatching(term) end

    if session.perms['view.citizen'] then
        local hits = MySQL.query.await([[
            SELECT citizen_id, first_name, last_name, dob, phone FROM nz_mdt_citizens
            WHERE CONCAT(first_name, ' ', last_name) LIKE ? OR citizen_id LIKE ? OR phone LIKE ?
               OR fingerprint LIKE ? OR dna LIKE ?
            LIMIT 6
        ]], { like, like, like, like, like }) or {}
        for _, c in ipairs(hits) do
            rows[#rows + 1] = {
                kind = 'citizen', id = c.citizen_id,
                title = ('%s %s'):format(c.first_name, c.last_name),
                sub = ('%s · %s'):format(c.dob or 'DOB unknown', c.phone or 'no number')
            }
        end
    end

    if session.perms['view.vehicle'] then
        local plateLike = '%' .. plateKey(term) .. '%'
        local hits = MySQL.query.await([[
            SELECT plate, model, owner_name, stolen FROM nz_mdt_vehicles
            WHERE plate LIKE ? OR model LIKE ? OR owner_name LIKE ? OR vin LIKE ? LIMIT 6
        ]], { plateLike, like, like, like }) or {}
        for _, v in ipairs(hits) do
            rows[#rows + 1] = {
                kind = 'vehicle', id = v.plate, title = v.plate,
                sub = ('%s · %s'):format(v.model or 'unknown model', v.owner_name or 'no owner'),
                hot = MDT.bool(v.stolen)
            }
        end
    end

    if session.perms['view.weapon'] then
        local hits = MySQL.query.await([[
            SELECT serial, label, owner_name, status FROM nz_mdt_weapons
            WHERE serial LIKE ? OR label LIKE ? OR owner_name LIKE ? LIMIT 4
        ]], { like, like, like }) or {}
        for _, w in ipairs(hits) do
            rows[#rows + 1] = {
                kind = 'weapon', id = w.serial, title = w.label,
                sub = ('%s · %s'):format(w.serial, w.owner_name or 'no owner'),
                hot = w.status == 'stolen'
            }
        end
    end

    if session.perms['view.incident'] then
        local hits = MySQL.query.await([[
            SELECT id, ref, title, status, primary_name FROM nz_mdt_incidents
            WHERE ref LIKE ? OR title LIKE ? OR primary_name LIKE ? ORDER BY id DESC LIMIT 4
        ]], { like, like, like }) or {}
        for _, i in ipairs(hits) do
            rows[#rows + 1] = { kind = 'incident', id = i.id, title = i.title,
                                sub = ('%s · %s%s'):format(i.ref, i.status, i.primary_name and (' · ' .. i.primary_name) or '') }
        end
    end

    if session.perms['view.evidence'] then
        local hits = MySQL.query.await([[
            SELECT id, ref, description, locker FROM nz_mdt_evidence
            WHERE ref LIKE ? OR description LIKE ? ORDER BY id DESC LIMIT 3
        ]], { like, like }) or {}
        for _, e in ipairs(hits) do
            rows[#rows + 1] = { kind = 'evidence', id = e.id, title = e.description,
                                sub = ('%s · %s'):format(e.ref, e.locker or 'unassigned') }
        end
    end

    if session.perms['view.warrant'] then
        local hits = MySQL.query.await([[
            SELECT id, citizen_id, citizen_name, title FROM nz_mdt_warrants
            WHERE status = 'active' AND (citizen_name LIKE ? OR title LIKE ?) LIMIT 4
        ]], { like, like }) or {}
        for _, w in ipairs(hits) do
            rows[#rows + 1] = { kind = 'warrant', id = w.citizen_id, title = w.title,
                                sub = w.citizen_name, hot = true }
        end
    end

    return { ok = true, rows = rows }
end)
