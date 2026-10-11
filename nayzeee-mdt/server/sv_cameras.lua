-- ═══════════════════════════════════════════════════════════
--  CAMERAS — placed CCTV, viewable from the MDT
-- ═══════════════════════════════════════════════════════════

local function modelAllowed(model)
    for _, m in ipairs(Config.Cameras.models or {}) do
        if m.model == model then return m end
    end
    return nil
end

local function camCard(c)
    return {
        id          = c.cam_id,
        rowId       = c.id,
        label       = c.label,
        model       = c.model,
        coords      = { x = c.x, y = c.y, z = c.z },
        rot         = { x = c.rx, y = c.ry, z = c.rz },
        departments = MDT.decode(c.departments, {}),
        status      = c.status,
        fixed       = MDT.bool(c.fixed),
        placedBy    = c.placed_by,
        stamp       = c.stamp
    }
end

--- Send the whole world list once to every client, instead of every client asking.
local function pushWorld()
    local rows = MySQL.query.await(
        'SELECT cam_id, label, model, x, y, z, rx, ry, rz, status FROM nz_mdt_cameras') or {}
    local out = {}
    for _, c in ipairs(rows) do
        out[#out + 1] = {
            id = c.cam_id, label = c.label, model = c.model, status = c.status,
            coords = { x = c.x, y = c.y, z = c.z },
            rot = { x = c.rx, y = c.ry, z = c.rz }
        }
    end
    TriggerClientEvent('nz_mdt:cameras:refresh', -1, out)
end

--- A camera with no department list is visible to everyone.
local function canSee(session, departments)
    if type(departments) ~= 'table' or #departments == 0 then return true end
    for _, d in ipairs(departments) do
        if d == session.department or d == '*' then return true end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
--  SEED THE FIXED POINTS
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    Wait(2000)
    if not Config.Cameras.enabled then return end

    for _, p in ipairs(Config.Cameras.points or {}) do
        local exists = MySQL.scalar.await('SELECT id FROM nz_mdt_cameras WHERE cam_id = ?', { p.id })
        if not exists then
            MySQL.insert.await([[
                INSERT INTO nz_mdt_cameras (cam_id, label, model, x, y, z, rz, fixed, placed_by)
                VALUES (?, ?, 'prop_cctv_cam_01a', ?, ?, ?, ?, 1, 'Config')
            ]], { p.id, p.label, p.coords.x, p.coords.y, p.coords.z, p.heading or 0.0 })
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:camera:list', MDT.guard('view.camera', function(session, search, status)
    search = MDT.clean(search, 40)

    local where, args = { '1 = 1' }, {}
    if search ~= '' then
        where[#where + 1] = '(label LIKE ? OR cam_id LIKE ?)'
        args[#args + 1] = '%' .. search .. '%'
        args[#args + 1] = '%' .. search .. '%'
    end
    if status and status ~= 'all' then
        where[#where + 1] = 'status = ?'
        args[#args + 1] = status
    end

    local rows = MySQL.query.await(([[
        SELECT *, DATE_FORMAT(created_at, '%%d %%b %%Y') AS stamp FROM nz_mdt_cameras
        WHERE %s ORDER BY fixed DESC, id DESC LIMIT 200
    ]]):format(table.concat(where, ' AND ')), args) or {}

    local out = {}
    for _, c in ipairs(rows) do
        local card = camCard(c)
        if canSee(session, card.departments) then out[#out + 1] = card end
    end

    return { ok = true, rows = out, models = Config.Cameras.models,
             placeable = Config.Cameras.placeable == true }
end))

lib.callback.register('nz_mdt:camera:get', MDT.guard('view.camera', function(session, camId)
    local c = MySQL.single.await('SELECT * FROM nz_mdt_cameras WHERE cam_id = ?', { MDT.clean(camId, 40) })
    if not c then return { ok = false, msg = 'That camera is not on the network.' } end

    local card = camCard(c)
    if not canSee(session, card.departments) then
        return { ok = false, msg = 'Your department has no access to that camera.' }
    end
    if card.status == 'destroyed' then
        return { ok = false, msg = 'That camera is offline — it needs repairing.' }
    end

    MDT.audit(session, 'camera.view', 'camera', card.id, card.label)
    return { ok = true, camera = card }
end))

lib.callback.register('nz_mdt:camera:place', MDT.guard('camera.place', function(session, data)
    if not Config.Cameras.enabled or not Config.Cameras.placeable then
        return { ok = false, msg = 'Camera placement is switched off.' }
    end

    local label = MDT.clean(data and data.label, 90)
    if #label < 2 then return { ok = false, msg = 'Give the camera a name.' } end

    if not modelAllowed(data.model) then return { ok = false, msg = 'Unknown camera model.' } end

    local coords = data.coords
    if type(coords) ~= 'table' or not tonumber(coords.x) then
        return { ok = false, msg = 'The placement was cancelled.' }
    end

    -- the cap is per department, counted on cameras that department can see
    local count = MySQL.scalar.await(
        "SELECT COUNT(*) FROM nz_mdt_cameras WHERE fixed = 0 AND departments LIKE ?",
        { '%"' .. session.department .. '"%' }) or 0
    if count >= (Config.Cameras.maxPerDept or 40) then
        return { ok = false, msg = 'Your department camera network is full. Remove one first.' }
    end

    -- default to the placing officer's own department
    local departments = {}
    if type(data.departments) == 'table' and #data.departments > 0 then
        for _, d in ipairs(data.departments) do
            if Config.Departments[d] then departments[#departments + 1] = d end
        end
    end
    if #departments == 0 then departments = { session.department } end

    local camId = ('CAM-%s'):format(MDT.rand(6))
    local rot = type(data.rot) == 'table' and data.rot or {}

    MySQL.insert.await([[
        INSERT INTO nz_mdt_cameras (cam_id, label, model, x, y, z, rx, ry, rz, departments, placed_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        camId, label, data.model,
        tonumber(coords.x), tonumber(coords.y), tonumber(coords.z),
        tonumber(rot.x) or 0.0, tonumber(rot.y) or 0.0, tonumber(rot.z) or 0.0,
        json.encode(departments), session.name
    })

    MDT.record(session, 'records', 'camera.place', 'camera', camId,
        'Camera placed', ('**%s** placed by %s'):format(label, session.name))

    MDT.push('camera:update', {})
    pushWorld()

    return { ok = true, msg = ('%s is online.'):format(label), id = camId }
end))

lib.callback.register('nz_mdt:camera:update', MDT.guard('camera.manage', function(session, camId, patch)
    local c = MySQL.single.await('SELECT * FROM nz_mdt_cameras WHERE cam_id = ?', { MDT.clean(camId, 40) })
    if not c then return { ok = false, msg = 'That camera is not on the network.' } end

    local sets, args = {}, {}
    if patch and patch.label then
        sets[#sets + 1] = 'label = ?'
        args[#args + 1] = MDT.clean(patch.label, 90)
    end
    if patch and patch.model and modelAllowed(patch.model) then
        sets[#sets + 1] = 'model = ?'
        args[#args + 1] = patch.model
    end
    if patch and type(patch.departments) == 'table' then
        local departments = {}
        for _, d in ipairs(patch.departments) do
            if Config.Departments[d] then departments[#departments + 1] = d end
        end
        sets[#sets + 1] = 'departments = ?'
        args[#args + 1] = json.encode(departments)
    end
    if patch and type(patch.coords) == 'table' and tonumber(patch.coords.x) then
        sets[#sets + 1] = 'x = ?'; args[#args + 1] = tonumber(patch.coords.x)
        sets[#sets + 1] = 'y = ?'; args[#args + 1] = tonumber(patch.coords.y)
        sets[#sets + 1] = 'z = ?'; args[#args + 1] = tonumber(patch.coords.z)
        local rot = type(patch.rot) == 'table' and patch.rot or {}
        sets[#sets + 1] = 'rx = ?'; args[#args + 1] = tonumber(rot.x) or 0.0
        sets[#sets + 1] = 'ry = ?'; args[#args + 1] = tonumber(rot.y) or 0.0
        sets[#sets + 1] = 'rz = ?'; args[#args + 1] = tonumber(rot.z) or 0.0
    end

    if #sets == 0 then return { ok = false, msg = 'Nothing to change.' } end

    args[#args + 1] = c.cam_id
    MySQL.update.await(('UPDATE nz_mdt_cameras SET %s WHERE cam_id = ?'):format(table.concat(sets, ', ')), args)

    MDT.audit(session, 'camera.edit', 'camera', c.cam_id, 'Camera updated')
    MDT.push('camera:update', {})
    pushWorld()

    return { ok = true, msg = 'Camera updated.' }
end))

lib.callback.register('nz_mdt:camera:repair', MDT.guard('camera.manage', function(session, camId)
    local c = MySQL.single.await('SELECT * FROM nz_mdt_cameras WHERE cam_id = ?', { MDT.clean(camId, 40) })
    if not c then return { ok = false, msg = 'That camera is not on the network.' } end
    if c.status ~= 'destroyed' then return { ok = false, msg = 'That camera is already online.' } end

    MySQL.update.await("UPDATE nz_mdt_cameras SET status = 'online' WHERE cam_id = ?", { c.cam_id })

    MDT.record(session, 'records', 'camera.repair', 'camera', c.cam_id,
        'Camera repaired', ('**%s** brought back online by %s'):format(c.label, session.name))

    MDT.push('camera:update', {})
    pushWorld()

    return { ok = true, msg = ('%s is back online.'):format(c.label) }
end))

lib.callback.register('nz_mdt:camera:delete', MDT.guard('camera.manage', function(session, camId)
    local c = MySQL.single.await('SELECT * FROM nz_mdt_cameras WHERE cam_id = ?', { MDT.clean(camId, 40) })
    if not c then return { ok = false, msg = 'That camera is gone already.' } end
    if MDT.bool(c.fixed) then
        return { ok = false, msg = 'That camera comes from the config — remove it there instead.' }
    end

    MySQL.update.await('DELETE FROM nz_mdt_cameras WHERE cam_id = ?', { c.cam_id })

    MDT.record(session, 'records', 'camera.delete', 'camera', c.cam_id,
        'Camera removed', ('**%s** removed by %s'):format(c.label, session.name))

    MDT.push('camera:update', {})
    pushWorld()

    return { ok = true, msg = 'Camera removed.' }
end))

-- ═══════════════════════════════════════════════════════════
--  DESTRUCTION  (shot out in the world)
-- ═══════════════════════════════════════════════════════════
local destroyedBy = {}   -- [src] = os.time(), stops one client spamming reports

RegisterNetEvent('nz_mdt:camera:destroyed', function(camId)
    if not Config.Cameras.destructible then return end

    local src = source
    local now = os.time()
    if destroyedBy[src] and now - destroyedBy[src] < 2 then return end
    destroyedBy[src] = now
    camId = MDT.clean(camId, 40)

    local c = MySQL.single.await('SELECT * FROM nz_mdt_cameras WHERE cam_id = ?', { camId })
    if not c or c.status == 'destroyed' then return end

    -- only trust a client that is actually standing near it
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local pos = GetEntityCoords(ped)
        if #(pos - vec3(c.x, c.y, c.z)) > 120.0 then return end
    end

    MySQL.update.await("UPDATE nz_mdt_cameras SET status = 'destroyed' WHERE cam_id = ?", { camId })

    local depts = MDT.decode(c.departments, {})
    for _, target in ipairs(MDT.sourcesFor(#depts > 0 and depts or { '*' })) do
        MDT.notify(target, 'Camera offline', ('%s has stopped transmitting.'):format(c.label), 'error')
    end

    MDT.log('records', 'Camera destroyed', ('**%s** (`%s`) stopped transmitting.'):format(c.label, camId))
    MDT.push('camera:update', {})
    pushWorld()
end)

--- The client asks for the list it needs to spawn props.
lib.callback.register('nz_mdt:cameras:world', function(src)
    if not Config.Cameras.enabled then return {} end

    local rows = MySQL.query.await(
        'SELECT cam_id, label, model, x, y, z, rx, ry, rz, status FROM nz_mdt_cameras') or {}

    local out = {}
    for _, c in ipairs(rows) do
        out[#out + 1] = {
            id = c.cam_id, label = c.label, model = c.model, status = c.status,
            coords = { x = c.x, y = c.y, z = c.z },
            rot = { x = c.rx, y = c.ry, z = c.rz }
        }
    end
    return out
end)

exports('cameras', function()
    return MySQL.query.await('SELECT cam_id, label, x, y, z, status FROM nz_mdt_cameras') or {}
end)
