--[[
    NAYZEEE AMBULANCE - Hospitals, departments, positions & staff (server data layer)

    A department is one hospital / organisation built in game. It owns grades
    (permissions + salary), outfits, garage vehicles, an HQ + map blip, its staff and
    its placed positions ("points"). This file loads and saves all of it, installs the
    staff resolver (NZA.Staff.Provider) and serves the public API every module uses.

    API (ARCHITECTURE §8)
      NZA.Hospitals.Get(id) → department          NZA.Hospitals.All() → { department }
      NZA.Hospitals.Nearest(coords) → department, dist
      NZA.Hospitals.Points(type?, hospitalId?) → { point }      NZA.Hospitals.Point(id) → point
      NZA.Hospitals.RespawnPoint(coords) → point | nil          (nearest 'respawn' position)
      NZA.Hospitals.FreeBed(hospitalId?) → point | nil          NZA.Hospitals.OccupyBed(pointId, pid) → bool
      NZA.Hospitals.ReleaseBed(pointId) → bool                  NZA.Hospitals.BedOccupant(pointId) → pid | nil
      NZA.Hospitals.Department(src) → department | nil         NZA.Hospitals.IsMember(src, id) → bool
      NZA.Hospitals.Society(id) → society account name          NZA.Hospitals.Ready() → bool
    A point = { id, hospital, type, coords = vector4, data = {}, label? }.
    A department = { id, label, description, job, discord, society, easy, easyPerms, hq, blip,
                     grades = { { level, name, label, salary, perms } }, outfits, vehicles, updated }.

    Data (oxmysql, created on start): nza_departments, nza_points, nza_staff, nza_hospital_stash.

    Net events
      nza:hospital:ready (C→S)       client booted → gets nza:points:sync + nza:hospital:depts
      nza:points:sync / upsert / remove (S→C, §17)
      nza:hospital:depts (S→C)       public department summary (labels, HQ, blips, vehicle models)
    Bus (server): hospital:changed (deptId|nil), hospital:points (reason, point|id)

    Internal helpers for the other hospital_*.lua files live in NZA.Hospitals.Internal.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Hospitals = NZA.Hospitals or {}
NZA.Hospitals.Internal = NZA.Hospitals.Internal or {}
local H = NZA.Hospitals
local I = H.Internal
local U = NZA.Util
local Core = NZA.Core

local depts = {}       -- [id] = department
local points = {}      -- [id] = point
local staff = {}       -- [identifier] = { identifier, department, grade, name, excluded, hiredBy, created }
local ownDuty = {}     -- [src] = bool   duty for members without a framework medic job (or override)
local beds = {}        -- [pointId] = pid
local loaded = false
local pending = {}     -- [src] = true   asked for a sync before the database was loaded

I.depts, I.points, I.staff, I.ownDuty, I.beds = depts, points, staff, ownDuty, beds

local function cfg(key, default)
    local c = Config.Hospital
    if c and c[key] ~= nil then return c[key] end
    return default
end
I.cfg = cfg

-- ════════════════════════════════════════════════════════════════════════
-- SANITIZING
-- ════════════════════════════════════════════════════════════════════════

local function trim(s)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function str(v, max, pattern)
    v = trim(v)
    if not v or v == '' then return nil end
    v = v:gsub('[%c]', '')
    if max and #v > max then v = v:sub(1, max) end
    if pattern and not v:match(pattern) then return nil end
    return v
end
I.str = str

local function int(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    v = math.floor(v + 0.5)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
I.int = int

local function num(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return default end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
I.num = num

local PERM = {}
local function permSet()
    if next(PERM) == nil then
        for _, p in ipairs(NZA.Const.Perms) do PERM[p.key] = true end
    end
    return PERM
end

function I.ValidId(id)
    if type(id) ~= 'string' then return nil end
    id = id:lower()
    if not id:match('^[a-z0-9_]+$') or #id < 2 or #id > 32 then return nil end
    return id
end

-- vector4 / { x, y, z, w } / { x, y, z, h } → { x, y, z, w } inside the map, or nil
function I.Coords(v)
    if type(v) ~= 'table' and type(v) ~= 'vector4' and type(v) ~= 'vector3' then return nil end
    local x = num(v.x or v[1], -12000.0, 12000.0)
    local y = num(v.y or v[2], -12000.0, 12000.0)
    local z = num(v.z or v[3], -500.0, 3000.0)
    if not (x and y and z) then return nil end
    local w = num(v.w or v.h or v.heading or v[4], -720.0, 720.0, 0.0) % 360.0
    return { x = U.round(x, 3), y = U.round(y, 3), z = U.round(z, 3), w = U.round(w, 2) }
end

local function vec4(c)
    if not c then return nil end
    return vector4(c.x + 0.0, c.y + 0.0, c.z + 0.0, (c.w or 0.0) + 0.0)
end
I.vec4 = vec4

local function permList(list)
    local set, out = {}, {}
    if type(list) ~= 'table' then return out end
    local valid = permSet()
    for k, v in pairs(list) do
        local key = (type(k) == 'number' and v) or (v and k) or nil
        if type(key) == 'string' and valid[key] and not set[key] then
            set[key] = true
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end
I.PermList = permList

local function defaultPerms(level)
    local map = Config.DefaultPerms or {}
    local best, bestLevel
    for g, list in pairs(map) do
        g = tonumber(g)
        if g and g <= level and (not bestLevel or g > bestLevel) then best, bestLevel = list, g end
    end
    return permList(best or map[0] or {})
end

local function sanitizeGrades(list)
    local out = {}
    local maxN = (cfg('limits', {}).grades) or 20
    if type(list) == 'table' then
        for _, g in ipairs(list) do
            if type(g) == 'table' and #out < maxN then
                local level = #out
                out[#out + 1] = {
                    level = level,
                    name = str(g.name, 24, '^[%w_%-]+$') or ('grade' .. level),
                    label = str(g.label, 32) or NZA.L('hospital.grade_n', level),
                    salary = int(g.salary, 0, 1000000, 0),
                    perms = g.perms == nil and defaultPerms(level) or permList(g.perms),
                }
            end
        end
    end
    if #out == 0 then
        out[1] = { level = 0, name = 'member', label = NZA.L('hospital.grade_member'), salary = 0, perms = defaultPerms(0) }
    end
    return out
end

local function outfitPart(raw, allowed)
    if type(raw) ~= 'table' then return {} end
    local okIds = {}
    for _, id in ipairs(allowed or {}) do okIds[id] = true end
    local out, seen = {}, {}
    for _, e in ipairs(raw) do
        if type(e) == 'table' then
            local id = int(e[1] or e.id, 0, 12)
            if id and okIds[id] and not seen[id] then
                seen[id] = true
                out[#out + 1] = { id, int(e[2] or e.d, -1, 5000, 0), int(e[3] or e.t, -1, 500, 0) }
            end
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local function outfitData(raw)
    if type(raw) ~= 'table' then return nil end
    local lk = cfg('locker', {})
    local data = {
        components = outfitPart(raw.components, lk.components or { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }),
        props = outfitPart(raw.props, lk.props or { 0, 1, 2, 6, 7 }),
    }
    if #data.components == 0 and #data.props == 0 then return nil end
    return data
end

local function sanitizeOutfits(list, gradeCount)
    local out = {}
    local maxN = (cfg('limits', {}).outfits) or 40
    if type(list) ~= 'table' then return out end
    for _, o in ipairs(list) do
        if type(o) == 'table' and #out < maxN then
            local grades, seen = {}, {}
            if type(o.grades) == 'table' then
                for _, g in ipairs(o.grades) do
                    g = int(g, 0, gradeCount - 1)
                    if g and not seen[g] then seen[g] = true; grades[#grades + 1] = g end
                end
                table.sort(grades)
            end
            local entry = {
                id = str(o.id, 24, '^[%w_%-]+$') or U.uid('o'),
                name = str(o.name, 32) or NZA.L('hospital.outfit_n', #out + 1),
                grades = grades,
                male = outfitData(o.male),
                female = outfitData(o.female),
            }
            out[#out + 1] = entry
        end
    end
    return out
end

local function sanitizeVehicles(list, gradeCount)
    local out = {}
    local maxN = (cfg('limits', {}).vehicles) or 40
    if type(list) ~= 'table' then return out end
    for _, v in ipairs(list) do
        if type(v) == 'table' and #out < maxN then
            local model = str(v.model, 32, '^[%w_%-]+$')
            if model then
                local extras, seen = {}, {}
                if type(v.extras) == 'table' then
                    for _, e in ipairs(v.extras) do
                        e = int(e, 0, 20)
                        if e and not seen[e] then seen[e] = true; extras[#extras + 1] = e end
                    end
                    table.sort(extras)
                end
                out[#out + 1] = {
                    id = str(v.id, 24, '^[%w_%-]+$') or U.uid('v'),
                    model = model:lower(),
                    label = str(v.label, 32) or model,
                    type = v.type == 'heli' and 'heli' or 'car',
                    minGrade = int(v.minGrade, 0, math.max(0, gradeCount - 1), 0),
                    livery = int(v.livery, -1, 60, -1),
                    extras = extras,
                    colour = int(v.colour, -1, 160, -1),
                }
            end
        end
    end
    return out
end

local function sanitizeBlip(b, label)
    b = type(b) == 'table' and b or {}
    local nd = (cfg('newDepartment', {}).blip) or {}
    return {
        enabled = b.enabled ~= false,
        sprite = int(b.sprite, 1, 900, nd.sprite or 61),
        colour = int(b.colour, 0, 85, nd.colour or 1),
        scale = U.round(num(b.scale, 0.4, 2.0, nd.scale or 0.85), 2),
        label = (str(b.label, 48) ~= label) and str(b.label, 48) or nil,   -- nil = the department label
        shortRange = b.shortRange ~= false,
    }
end

local function sanitizeEasyPerms(map)
    local out = {}
    if type(map) ~= 'table' then return out end
    local valid = permSet()
    for k, v in pairs(map) do
        if type(k) == 'string' and valid[k] and type(v) == 'boolean' then out[k] = v end
    end
    return out
end

-- Full department from untrusted input. `base` = the stored department (fields the input
-- leaves out keep their stored value). `only` = { grades = true, ... } limits which fields
-- the input may change (bosses).
function I.SanitizeDept(input, base, only)
    input = type(input) == 'table' and input or {}
    base = base or {}
    local function pick(key)
        if only and not only[key] then return base[key] end
        if input[key] == nil then return base[key] end
        return input[key]
    end
    local id = base.id or I.ValidId(input.id)
    if not id then return nil, 'bad_id' end
    local d = {
        id = id,
        label = str(pick('label'), 48) or base.label or id:upper(),
        description = str(pick('description'), 400) or '',
        job = str(pick('job'), 40, '^[%w_%-]+$'),
        discord = str(pick('discord'), 24, '^%d+$'),
        society = str(pick('society'), 40, '^[%w_%-]+$'),
        easy = pick('easy') == true,
        easyPerms = sanitizeEasyPerms(pick('easyPerms')),
        hq = I.Coords(pick('hq')),
        created = base.created or os.time(),
        updated = os.time(),
    }
    if only and not only.job then d.job = base.job end
    d.blip = sanitizeBlip(pick('blip'), d.label)
    d.grades = sanitizeGrades(pick('grades'))
    d.outfits = sanitizeOutfits(pick('outfits'), #d.grades)
    d.vehicles = sanitizeVehicles(pick('vehicles'), #d.grades)
    return d
end

-- ════════════════════════════════════════════════════════════════════════
-- DATABASE
-- ════════════════════════════════════════════════════════════════════════

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `nza_departments` (
        `id` VARCHAR(48) NOT NULL,
        `label` VARCHAR(64) NOT NULL,
        `job` VARCHAR(64) NULL DEFAULT NULL,
        `data` LONGTEXT NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nza_points` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `department` VARCHAR(48) NOT NULL,
        `type` VARCHAR(32) NOT NULL,
        `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` DOUBLE NOT NULL DEFAULT 0,
        `label` VARCHAR(64) NULL DEFAULT NULL,
        `data` LONGTEXT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `department` (`department`)
    ) DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nza_staff` (
        `identifier` VARCHAR(80) NOT NULL,
        `department` VARCHAR(48) NOT NULL,
        `grade` INT NOT NULL DEFAULT 0,
        `name` VARCHAR(80) NULL DEFAULT NULL,
        `excluded` TINYINT(1) NOT NULL DEFAULT 0,
        `hired_by` VARCHAR(80) NULL DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`),
        KEY `department` (`department`)
    ) DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nza_hospital_stash` (
        `id` VARCHAR(120) NOT NULL,
        `items` LONGTEXT NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) DEFAULT CHARSET=utf8mb4]],
}

local function decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    if ok then return v end
    return nil
end
I.decode = decode

local function pointFromRow(r)
    return {
        id = tonumber(r.id),
        hospital = r.department,
        type = r.type,
        coords = vector4(r.x + 0.0, r.y + 0.0, r.z + 0.0, (r.h or 0) + 0.0),
        label = r.label,
        data = decode(r.data) or {},
    }
end

function I.SaveDept(d)
    local data = {}
    for k, v in pairs(d) do
        if k ~= 'id' and k ~= 'label' and k ~= 'job' then data[k] = v end
    end
    MySQL.query.await('INSERT INTO `nza_departments` (`id`, `label`, `job`, `data`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `job` = VALUES(`job`), `data` = VALUES(`data`)',
        { d.id, d.label, d.job, json.encode(data) })
end

local function loadAll()
    for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end

    local rows = MySQL.query.await('SELECT * FROM `nza_departments`') or {}
    for _, r in ipairs(rows) do
        local data = decode(r.data) or {}
        data.id, data.label, data.job = r.id, r.label, r.job
        local d = I.SanitizeDept(data, { id = r.id, created = data.created })
        if d then
            d.updated = tonumber(data.updated) or d.updated
            depts[d.id] = d
        end
    end

    rows = MySQL.query.await('SELECT * FROM `nza_points`') or {}
    for _, r in ipairs(rows) do
        local p = pointFromRow(r)
        if p.id then points[p.id] = p end
    end

    rows = MySQL.query.await('SELECT * FROM `nza_staff`') or {}
    for _, r in ipairs(rows) do
        staff[r.identifier] = {
            identifier = r.identifier, department = r.department, grade = tonumber(r.grade) or 0,
            name = r.name, excluded = tonumber(r.excluded) == 1 or r.excluded == true,
            hiredBy = r.hired_by, created = r.created_at,
        }
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- DEPARTMENT HELPERS
-- ════════════════════════════════════════════════════════════════════════

function I.GradeFor(d, level)
    if not d or not d.grades or #d.grades == 0 then return nil end
    level = tonumber(level) or 0
    local best
    for _, g in ipairs(d.grades) do
        if g.level <= level and (not best or g.level > best.level) then best = g end
    end
    return best or d.grades[1]
end

function I.Society(d)
    if type(d) == 'string' then d = depts[d] end
    if not d then return nil end
    return d.society or d.job or d.id
end

function I.DeptByJob(job)
    if not job then return nil end
    local best
    for _, d in pairs(depts) do
        if d.job == job and (not best or d.id < best.id) then best = d end
    end
    return best
end

-- public summary for every client (blips, labels, vehicle ghosts)
local function publicDepts()
    local out = {}
    for _, d in pairs(depts) do
        local veh = {}
        for _, v in ipairs(d.vehicles or {}) do veh[#veh + 1] = { model = v.model, type = v.type, label = v.label } end
        out[#out + 1] = { id = d.id, label = d.label, job = d.job, hq = d.hq, blip = d.blip, vehicles = veh }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function I.BroadcastDepts(target)
    TriggerClientEvent('nza:hospital:depts', target or -1, publicDepts())
end

function I.PointList(filter)
    local out = {}
    for _, p in pairs(points) do
        if not filter or filter(p) then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function syncTo(src)
    TriggerClientEvent('nza:points:sync', src, I.PointList())
    I.BroadcastDepts(src)
end

-- ════════════════════════════════════════════════════════════════════════
-- DEPARTMENT CRUD (callers check permissions)
-- ════════════════════════════════════════════════════════════════════════

function I.CreateDept(id, label)
    id = I.ValidId(id)
    if not id then return nil, 'bad_id' end
    if depts[id] then return nil, 'exists' end
    if U.tableCount(depts) >= ((cfg('limits', {}).departments) or 20) then return nil, 'limit' end
    local nd = cfg('newDepartment', {})
    local easy = nd.easy
    if easy == nil then easy = Config.EasyMode and Config.EasyMode.default == true end
    local d = I.SanitizeDept({
        id = id, label = str(label, 48) or id:upper(), job = nd.job, easy = easy,
        blip = nd.blip, grades = U.deepcopy(nd.grades or {}), vehicles = U.deepcopy(nd.vehicles or {}),
    }, nil)
    if not d then return nil, 'bad_id' end
    depts[id] = d
    I.SaveDept(d)
    I.BroadcastDepts()
    NZA.Bus.Emit('hospital:changed', id)
    return d
end

function I.UpdateDept(d)
    depts[d.id] = d
    I.SaveDept(d)
    I.BroadcastDepts()
    NZA.Staff.RefreshAll()
    NZA.Bus.Emit('hospital:changed', d.id)
    return d
end

function I.DeleteDept(id)
    if not depts[id] then return false end
    depts[id] = nil
    MySQL.query.await('DELETE FROM `nza_departments` WHERE `id` = ?', { id })
    MySQL.query.await('DELETE FROM `nza_points` WHERE `department` = ?', { id })
    MySQL.query.await('DELETE FROM `nza_staff` WHERE `department` = ?', { id })
    for pid, p in pairs(points) do
        if p.hospital == id then
            points[pid] = nil
            beds[pid] = nil
            TriggerClientEvent('nza:points:remove', -1, pid)
        end
    end
    for ident, row in pairs(staff) do
        if row.department == id then staff[ident] = nil end
    end
    I.BroadcastDepts()
    NZA.Staff.RefreshAll(true)
    NZA.Bus.Emit('hospital:changed', id)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- POINTS
-- ════════════════════════════════════════════════════════════════════════

local function cleanData(data, depth)
    depth = depth or 0
    if type(data) ~= 'table' or depth > 3 then return {} end
    local out, n = {}, 0
    for k, v in pairs(data) do
        n = n + 1
        if n > 40 then break end
        if type(k) == 'string' and #k <= 32 and k:match('^[%w_]+$') then
            local t = type(v)
            if t == 'string' then out[k] = v:gsub('[%c]', ''):sub(1, 120)
            elseif t == 'number' then out[k] = (v == v and v ~= math.huge and v ~= -math.huge) and v or 0
            elseif t == 'boolean' then out[k] = v
            elseif t == 'table' then out[k] = cleanData(v, depth + 1) end
        elseif type(k) == 'number' and depth > 0 then
            local t = type(v)
            if t == 'string' or t == 'number' or t == 'boolean' then out[k] = v end
        end
    end
    return out
end
I.CleanData = cleanData

function I.CountPoints(deptId)
    local n = 0
    for _, p in pairs(points) do if p.hospital == deptId then n = n + 1 end end
    return n
end

function I.AddPoint(deptId, kind, coords, data, label)
    if not depts[deptId] then return nil, 'no_dept' end
    kind = str(kind, 32, '^[%w_]+$')
    if not kind then return nil, 'bad_type' end
    local c = I.Coords(coords)
    if not c then return nil, 'bad_coords' end
    if I.CountPoints(deptId) >= ((cfg('limits', {}).points) or 400) then return nil, 'limit' end
    data = cleanData(data)
    label = str(label, 64)
    local id = MySQL.insert.await('INSERT INTO `nza_points` (`department`, `type`, `x`, `y`, `z`, `h`, `label`, `data`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { deptId, kind, c.x, c.y, c.z, c.w, label, json.encode(data) })
    id = tonumber(id)
    if not id then return nil, 'db' end
    local p = { id = id, hospital = deptId, type = kind, coords = vec4(c), data = data, label = label }
    points[id] = p
    TriggerClientEvent('nza:points:upsert', -1, p)
    NZA.Bus.Emit('hospital:points', 'add', p)
    return p
end

function I.MovePoint(id, coords)
    local p = points[tonumber(id)]
    if not p then return nil, 'no_point' end
    local c = I.Coords(coords)
    if not c then return nil, 'bad_coords' end
    MySQL.query.await('UPDATE `nza_points` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { c.x, c.y, c.z, c.w, p.id })
    p.coords = vec4(c)
    TriggerClientEvent('nza:points:upsert', -1, p)
    NZA.Bus.Emit('hospital:points', 'move', p)
    return p
end

function I.SetPointData(id, data, label)
    local p = points[tonumber(id)]
    if not p then return nil, 'no_point' end
    p.data = cleanData(data)
    p.label = str(label, 64)
    MySQL.query.await('UPDATE `nza_points` SET `data` = ?, `label` = ? WHERE `id` = ?', { json.encode(p.data), p.label, p.id })
    TriggerClientEvent('nza:points:upsert', -1, p)
    NZA.Bus.Emit('hospital:points', 'data', p)
    return p
end

function I.DeletePoint(id)
    id = tonumber(id)
    local p = id and points[id]
    if not p then return false end
    points[id] = nil
    if beds[id] then H.ReleaseBed(id) end
    MySQL.query.await('DELETE FROM `nza_points` WHERE `id` = ?', { id })
    TriggerClientEvent('nza:points:remove', -1, id)
    NZA.Bus.Emit('hospital:points', 'remove', id)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- STAFF
-- ════════════════════════════════════════════════════════════════════════

function I.StaffRow(identifier)
    return staff[identifier]
end

function I.StaffOf(deptId)
    local out = {}
    for _, row in pairs(staff) do
        if row.department == deptId and not row.excluded then out[#out + 1] = row end
    end
    return out
end

function I.SetStaff(identifier, deptId, grade, name, by)
    local row = staff[identifier] or { identifier = identifier }
    row.department, row.grade, row.excluded = deptId, grade, false
    row.name = name or row.name
    row.hiredBy = by or row.hiredBy
    row.created = row.created or os.date('%Y-%m-%d %H:%M:%S')
    staff[identifier] = row
    MySQL.query.await('INSERT INTO `nza_staff` (`identifier`, `department`, `grade`, `name`, `excluded`, `hired_by`) VALUES (?, ?, ?, ?, 0, ?) ON DUPLICATE KEY UPDATE `department` = VALUES(`department`), `grade` = VALUES(`grade`), `name` = VALUES(`name`), `excluded` = 0, `hired_by` = VALUES(`hired_by`)',
        { identifier, deptId, grade, row.name, row.hiredBy })
    return row
end

-- linked departments: a fired member who still has the framework job is excluded
function I.RemoveStaff(identifier, keepExcluded, deptId)
    local row = staff[identifier]
    if keepExcluded then
        row = row or { identifier = identifier, grade = 0 }
        row.department = deptId or row.department
        row.excluded = true
        staff[identifier] = row
        MySQL.query.await('INSERT INTO `nza_staff` (`identifier`, `department`, `grade`, `name`, `excluded`) VALUES (?, ?, ?, ?, 1) ON DUPLICATE KEY UPDATE `department` = VALUES(`department`), `excluded` = 1',
            { identifier, row.department, row.grade or 0, row.name })
        return true
    end
    staff[identifier] = nil
    MySQL.query.await('DELETE FROM `nza_staff` WHERE `identifier` = ?', { identifier })
    return true
end

function I.RenameStaff(identifier, name)
    local row = staff[identifier]
    if not row or not name or row.name == name then return end
    row.name = name
    MySQL.query('UPDATE `nza_staff` SET `name` = ? WHERE `identifier` = ?', { name, identifier })
end

-- ════════════════════════════════════════════════════════════════════════
-- STAFF RESOLVER (NZA.Staff.Provider)
-- ════════════════════════════════════════════════════════════════════════

-- easy mode belongs to the department (master switch + per-permission overrides)
local function easySet(d)
    local out = {}
    local overrides = d.easyPerms or {}
    for _, p in ipairs(NZA.Const.Perms) do
        local on = overrides[p.key]
        if on == nil then on = d.easy == true end
        if on then out[p.key] = true end
    end
    return out
end

-- membership of src: dept, level, row (nil when the player is not in any department)
function I.Membership(src, base)
    local ident = Core.Identifier(src)
    local row = ident and staff[ident]
    if row then
        if row.excluded then return nil, nil, row end
        local d = depts[row.department]
        if d then return d, row.grade, row end
    end
    local job = base and base.job
    if not job then
        local j = Core.B('GetJob', src)
        job = type(j) == 'table' and j.name or nil
        base = base or { grade = type(j) == 'table' and j.grade or 0 }
    end
    local d = I.DeptByJob(job)
    if d then return d, tonumber(base and base.grade) or 0, nil end
    return nil
end

function I.OwnDuty(src)
    return ownDuty[src]
end

function I.SetOwnDuty(src, on)
    ownDuty[src] = on
end

local function provider(src, base)
    local d, level, row = I.Membership(src, base)
    if not d then
        if row and row.excluded then
            -- fired from a linked department but still on the framework job: no medic perms
            return {
                hospital = nil, dept = nil, grade = 0, gradeLabel = nil, perms = {}, easy = {},
                onDuty = false, medic = false, police = base.police, job = base.job, jobLabel = base.jobLabel,
                excluded = true,
            }
        end
        return nil
    end
    local g = I.GradeFor(d, level)
    local perms = {}
    for _, p in ipairs(g and g.perms or {}) do perms[p] = true end

    local onDuty
    local own = ownDuty[src]
    if base.medic then
        onDuty = base.onDuty
        if own ~= nil then onDuty = own end
    else
        onDuty = own == true
    end

    return {
        hospital = d.id, dept = d.id, deptLabel = d.label,
        grade = g and g.level or 0, gradeLabel = g and g.label or nil, gradeName = g and g.name or nil,
        salary = g and g.salary or 0,
        perms = perms, easy = easySet(d),
        onDuty = onDuty == true,
        medic = true, police = base.police,
        job = base.job, jobLabel = base.jobLabel,
        isBoss = perms.manage == true,
        linked = d.job ~= nil,
        frameworkMedic = base.medic == true,
    }
end
I.Provider = provider

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ════════════════════════════════════════════════════════════════════════

function H.Ready()
    return loaded
end

function H.Get(id)
    return id and depts[id] or nil
end

function H.All()
    local out = {}
    for _, d in pairs(depts) do out[#out + 1] = d end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function pointPos(p)
    local c = p.coords
    return vector3(c.x, c.y, c.z)
end
I.PointPos = pointPos

function H.Point(id)
    return points[tonumber(id) or id]
end

function H.Points(kind, hospitalId)
    return I.PointList(function(p)
        return (not kind or p.type == kind) and (not hospitalId or p.hospital == hospitalId)
    end)
end

function H.Nearest(coords)
    coords = U.vec(coords)
    if not coords then return nil end
    local best, bestD = nil, math.huge
    for _, d in pairs(depts) do
        if d.hq then
            local dist = #(coords - vector3(d.hq.x, d.hq.y, d.hq.z))
            if dist < bestD then best, bestD = d, dist end
        end
    end
    for _, p in pairs(points) do
        local d = depts[p.hospital]
        if d then
            local dist = #(coords - pointPos(p))
            if dist < bestD then best, bestD = d, dist end
        end
    end
    if not best then return nil end
    return best, bestD
end

function H.RespawnPoint(coords)
    coords = U.vec(coords) or vector3(0.0, 0.0, 0.0)
    local best, bestD = nil, math.huge
    for _, p in pairs(points) do
        if p.type == 'respawn' and depts[p.hospital] then
            local dist = #(coords - pointPos(p))
            if dist < bestD then best, bestD = p, dist end
        end
    end
    if not best then return nil end
    local d = depts[best.hospital]
    return { id = best.id, hospital = best.hospital, coords = best.coords, label = best.label or (d and d.label), data = best.data }
end

local function bedValid(pointId)
    local pid = beds[pointId]
    if not pid then return false end
    local p = NZA.Patients.Get(pid)
    if not p then
        beds[pointId] = nil
        return false
    end
    local bed = p.meta and p.meta.bed
    if type(bed) == 'table' and bed.point ~= nil and tonumber(bed.point) ~= pointId then
        beds[pointId] = nil
        return false
    end
    return true
end

function H.BedOccupant(pointId)
    pointId = tonumber(pointId)
    if not pointId or not bedValid(pointId) then return nil end
    return beds[pointId]
end

function H.FreeBed(hospitalId)
    local list = I.PointList(function(p)
        return p.type == 'bed' and (not hospitalId or p.hospital == hospitalId)
    end)
    local free = {}
    for _, p in ipairs(list) do
        if not bedValid(p.id) then free[#free + 1] = p end
    end
    if #free == 0 then return nil end
    return free[math.random(#free)]
end

function H.OccupyBed(pointId, pid)
    pointId = tonumber(pointId)
    local pt = pointId and points[pointId]
    if not pt then return false end
    local p = NZA.Patients.Get(pid)
    if not p then return false end
    if bedValid(pointId) and beds[pointId] ~= p.pid then return false end
    -- leave any other bed first
    for id, occupant in pairs(beds) do
        if occupant == p.pid and id ~= pointId then beds[id] = nil end
    end
    beds[pointId] = p.pid
    NZA.Patients.SetMeta(p, 'bed', { point = pointId, type = pt.type, hospital = pt.hospital })
    if pt.type == 'bed' then NZA.Patients.SetMeta(p, 'inBed', true) end
    NZA.Bus.Emit('hospital:bed', pointId, p.pid, true)
    return true
end

function H.ReleaseBed(pointId)
    pointId = tonumber(pointId)
    local pid = pointId and beds[pointId]
    if not pid then return false end
    beds[pointId] = nil
    local p = NZA.Patients.Get(pid)
    if p and p.meta then
        local bed = p.meta.bed
        if type(bed) == 'table' and tonumber(bed.point) == pointId then
            NZA.Patients.SetMeta(p, 'bed', nil)
            NZA.Patients.SetMeta(p, 'inBed', nil)
        end
    end
    NZA.Bus.Emit('hospital:bed', pointId, pid, false)
    return true
end

function H.Department(src)
    local rec = NZA.Staff.Get(src)
    return rec and rec.dept and depts[rec.dept] or nil
end

function H.IsMember(src, deptId)
    local rec = NZA.Staff.Get(src)
    return rec ~= nil and rec.dept ~= nil and rec.dept == deptId
end

function H.Society(id)
    return I.Society(id)
end

-- ════════════════════════════════════════════════════════════════════════
-- SYNC & LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:hospital:ready', function()
    local src = tonumber(source)
    if not src or not Core.Rate('nza:hospital:ready', src, 3, 10000) then return end
    if not loaded then
        pending[src] = true
        return
    end
    syncTo(src)
end)

NZA.Bus.On('player:loaded', function(src)
    if not loaded then return end
    local ident = Core.Identifier(src)
    if ident and staff[ident] then I.RenameStaff(ident, Core.Name(src)) end
end)

NZA.Bus.On('player:unloaded', function(src, reason)
    src = tonumber(src)
    if not src then return end
    if reason == 'dropped' then ownDuty[src] = nil end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then ownDuty[src] = nil; pending[src] = nil end
end)

-- once the framework reports a duty state again it is authoritative (our override only
-- bridges the moment between Bridge.SetDuty and the framework's job update)
NZA.Bus.On('player:job', function(src, job)
    src = tonumber(src)
    if not src or ownDuty[src] == nil or type(job) ~= 'table' or job.onDuty == nil then return end
    if (job.onDuty == true) == ownDuty[src] then
        ownDuty[src] = nil
        NZA.Staff.Refresh(src)
    end
end)

-- a patient leaving the server / being removed frees their bed
NZA.Bus.On('patient:removed', function(pid)
    for id, occupant in pairs(beds) do
        if occupant == pid then beds[id] = nil end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PAYCHECKS (standalone departments; frameworks pay their own jobs)
-- ════════════════════════════════════════════════════════════════════════

local dutyMinutes = {}

local function payTick()
    local pc = cfg('paycheck', {})
    if pc.enabled == false then return end
    local interval = math.max(1, tonumber(pc.interval) or 15)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local rec = src and NZA.Staff.Get(src)
        if rec and rec.dept and rec.onDuty and (not pc.standaloneOnly or not rec.linked) then
            dutyMinutes[src] = (dutyMinutes[src] or 0) + 1
            if dutyMinutes[src] >= interval then
                dutyMinutes[src] = 0
                local amount = math.floor(tonumber(rec.salary) or 0)
                if amount > 0 then
                    local paid = true
                    if pc.fromSociety then
                        paid = Core.B('Society.Remove', I.Society(rec.dept), amount) == true
                    end
                    if paid then
                        Core.B('AddMoney', src, pc.account or 'bank', amount, 'paycheck')
                        Core.Notify(src, NZA.L('hospital.paycheck', amount), 'success', NZA.L('hospital.paycheck_title'))
                    else
                        Core.Notify(src, NZA.L('hospital.paycheck_empty'), 'warning', NZA.L('hospital.paycheck_title'))
                    end
                end
            end
        elseif src then
            dutyMinutes[src] = nil
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- BOOT
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local ok, err = pcall(loadAll)
    if not ok then
        NZA.Warn('hospital: database load failed: ' .. tostring(err))
    end
    loaded = true
    NZA.Staff.Provider(provider)
    TriggerClientEvent('nza:points:sync', -1, I.PointList())
    I.BroadcastDepts()
    for src in pairs(pending) do
        if Core.Online(src) then syncTo(src) end
    end
    pending = {}
    NZA.Debug(('hospital: %d departments, %d positions, %d staff loaded'):format(U.tableCount(depts), U.tableCount(points), U.tableCount(staff)))
    while true do
        Wait(60000)
        local okTick, errTick = pcall(payTick)
        if not okTick then NZA.Warn('hospital paycheck failed: ' .. tostring(errTick)) end
    end
end)
