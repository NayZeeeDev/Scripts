--[[
    NAYZEEE AMBULANCE - EMS Manager (server): departments, roster, grades, outfits,
    garage, positions, HQ and funds

    Access
      admins (Bridge.IsAdmin / ace Config.Admin.ace)  → every department, everything
      bosses (their grade has 'manage')                → their own department: roster, grades,
                                                         outfits, garage and society funds, opened
                                                         from one of their department's boss points
    Command: /nzadmin (Config.Commands.admin) → client opens the manager in admin mode.

    Callbacks (lib.callback) — every one returns { ok, err?, msg?, data? } where data is the
    refreshed manager snapshot (see BuildData) so the NUI re-renders from server truth:
      nza:hospital:mgr:open        ({ mode = 'admin'|'boss', point? })
      nza:hospital:mgr:create      ({ id, label })                       admin
      nza:hospital:mgr:save        ({ mode, dept = {...} })              admin / boss (limited fields)
      nza:hospital:mgr:delete      ({ id })                              admin
      nza:hospital:mgr:hire        ({ mode, dept, target, grade })       target = server id | identifier
      nza:hospital:mgr:grade       ({ mode, dept, identifier, grade })
      nza:hospital:mgr:fire        ({ mode, dept, identifier })
      nza:hospital:mgr:point:add   ({ dept, type, coords, data, label }) admin, within builder range
      nza:hospital:mgr:point:move  ({ id, coords })                      admin, within builder range
      nza:hospital:mgr:point:data  ({ id, data, label })                 admin
      nza:hospital:mgr:point:delete ({ id })                             admin
      nza:hospital:mgr:hq          ({ dept, coords })                    admin, within builder range
      nza:hospital:mgr:funds       ({ mode, dept, action = 'deposit'|'withdraw', amount })
    Net events: nza:hospital:openManager (S→C, mode)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Hospitals = NZA.Hospitals or {}
NZA.Hospitals.Internal = NZA.Hospitals.Internal or {}
local H = NZA.Hospitals
local I = H.Internal
local Core = NZA.Core
local U = NZA.Util

local function cfg(key, default)
    local c = Config.Hospital
    if c and c[key] ~= nil then return c[key] end
    return default
end

local function fail(err, ...)
    return { ok = false, err = err, msg = NZA.L('hospital.err_' .. err, ...) }
end

local function plainCoords(c)
    if not c then return nil end
    return { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 }
end

local function plainPoint(p)
    return { id = p.id, hospital = p.hospital, type = p.type, coords = plainCoords(p.coords), data = p.data, label = p.label }
end

-- ════════════════════════════════════════════════════════════════════════
-- ACCESS
-- ════════════════════════════════════════════════════════════════════════

local function isAdmin(src)
    return Core.IsAdmin(src) == true
end

-- department + grade of src when that grade has 'manage' (duty not required)
local function bossOf(src)
    local d, level = I.Membership(src, nil)
    if not d then return nil end
    local g = I.GradeFor(d, level)
    if not g then return nil end
    for _, p in ipairs(g.perms or {}) do
        if p == 'manage' then return d, g end
    end
    return nil
end

local bossSession = {}   -- [src] = { dept, at } opened from a boss point

-- → role ('admin'|'boss'), dept (boss), grade (boss)  or nil, err
local function access(src, payload, deptId)
    local mode = type(payload) == 'table' and payload.mode or nil
    if mode ~= 'boss' and isAdmin(src) then return 'admin' end
    local d, g = bossOf(src)
    if not d then return nil, 'no_access' end
    local sess = bossSession[src]
    if not sess or sess.dept ~= d.id or os.time() - sess.at > 3600 then return nil, 'no_access' end
    if deptId and deptId ~= d.id then return nil, 'no_access' end
    return 'boss', d, g
end

local function rate(src)
    local n = (cfg('rates', {}).manager) or 8
    return Core.Rate('nza:hospital:mgr', src, n, 4000)
end

local function within(src, coords, extra)
    local me = Core.SrcCoords(src)
    if not me then return false end
    local c = I.Coords(coords)
    if not c then return false end
    local max = ((cfg('builder', {}).maxDistance) or 25.0) + (extra or 8.0)
    return #(me - vector3(c.x, c.y, c.z)) <= max
end

-- ════════════════════════════════════════════════════════════════════════
-- SNAPSHOT FOR THE NUI
-- ════════════════════════════════════════════════════════════════════════

local function onlineIndex()
    local idx = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ident = src and Core.Identifier(src)
        if ident then idx[ident] = src end
    end
    return idx
end

local function staffRows(d, idx)
    local rows, seen = {}, {}
    for _, row in ipairs(I.StaffOf(d.id)) do
        local src = idx[row.identifier]
        local rec = src and NZA.Staff.Get(src)
        seen[row.identifier] = true
        rows[#rows + 1] = {
            identifier = row.identifier, name = (src and Core.Name(src)) or row.name or row.identifier,
            grade = row.grade, online = src ~= nil, src = src,
            onDuty = rec and rec.dept == d.id and rec.onDuty == true or false,
            created = row.created and tostring(row.created) or nil, linked = false,
        }
    end
    -- members through the framework job link (online only, no stored row)
    if d.job then
        for ident, src in pairs(idx) do
            if not seen[ident] then
                local rec = NZA.Staff.Get(src)
                if rec and rec.dept == d.id then
                    rows[#rows + 1] = {
                        identifier = ident, name = Core.Name(src), grade = rec.grade, online = true, src = src,
                        onDuty = rec.onDuty == true, linked = true,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

local function BuildData(src, role, bossDept)
    local idx = onlineIndex()
    local list = {}
    if role == 'admin' then
        list = H.All()
    elseif bossDept then
        list = { bossDept }
    end

    local staffMap, society, totals = {}, {}, { departments = #list, staff = 0, onDuty = 0, points = 0 }
    for _, d in ipairs(list) do
        local rows = staffRows(d, idx)
        staffMap[d.id] = rows
        totals.staff = totals.staff + #rows
        for _, r in ipairs(rows) do if r.onDuty then totals.onDuty = totals.onDuty + 1 end end
        if role == 'boss' then
            society[d.id] = tonumber(Core.B('Society.Get', I.Society(d))) or 0
        end
    end

    local pts = {}
    if role == 'admin' then
        for _, p in ipairs(I.PointList()) do pts[#pts + 1] = plainPoint(p) end
    else
        -- bosses see their garage / helipad spawn points (read only)
        for _, p in ipairs(I.PointList(function(p) return p.hospital == bossDept.id and (p.type == 'garage' or p.type == 'heli') end)) do
            pts[#pts + 1] = plainPoint(p)
        end
    end
    totals.points = #pts

    local online = {}
    for ident, s in pairs(idx) do
        online[#online + 1] = { src = s, name = Core.Name(s), identifier = role == 'admin' and ident or nil }
    end
    table.sort(online, function(a, b) return a.src < b.src end)

    local me = NZA.Staff.Get(src) or {}
    local depts = {}
    for _, d in ipairs(list) do depts[#depts + 1] = U.deepcopy(d) end

    local perms = {}
    for _, p in ipairs(NZA.Const.Perms) do perms[#perms + 1] = { key = p.key, label = NZA.L('hospital.perm_' .. p.key) ~= ('hospital.perm_' .. p.key) and NZA.L('hospital.perm_' .. p.key) or p.label, desc = p.desc } end

    return {
        mode = role,
        admin = role == 'admin',
        me = { dept = me.dept, grade = me.grade, src = src, identifier = Core.Identifier(src), name = Core.Name(src) },
        depts = depts,
        staff = staffMap,
        points = pts,
        online = online,
        society = society,
        totals = totals,
        perms = perms,
        limits = cfg('limits', {}),
        blips = cfg('blips', {}),
        bossOutranks = (cfg('staff', {}).bossOutranks) ~= false,
        canSetJob = Core.Has('SetJob'),
    }
end
I.BuildData = BuildData

local function reply(src, role, bossDept, extra)
    local out = { ok = true, data = BuildData(src, role, bossDept) }
    if type(extra) == 'table' then for k, v in pairs(extra) do out[k] = v end end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- OPEN
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:hospital:mgr:open', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not H.Ready() then return fail('loading') end
    payload = type(payload) == 'table' and payload or {}
    if payload.mode ~= 'boss' and isAdmin(src) then
        return reply(src, 'admin')
    end
    local d = bossOf(src)
    if not d then
        if isAdmin(src) then return reply(src, 'admin') end
        return fail('no_access')
    end
    -- bosses open the manager from one of their department's boss points
    local pt = H.Point(payload.point)
    local me = Core.SrcCoords(src)
    if not pt or pt.type ~= 'boss' or pt.hospital ~= d.id or not me or #(me - I.PointPos(pt)) > 6.0 then
        return fail('no_access')
    end
    bossSession[src] = { dept = d.id, at = os.time() }
    return reply(src, 'boss', d)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then bossSession[src] = nil end
end)

-- ════════════════════════════════════════════════════════════════════════
-- DEPARTMENTS
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:hospital:mgr:create', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    payload = type(payload) == 'table' and payload or {}
    local d, err = I.CreateDept(payload.id, payload.label)
    if not d then return fail(err or 'failed') end
    return reply(src, 'admin', nil, { dept = d.id, msg = NZA.L('hospital.created', d.label) })
end)

local function gradeHasManage(d, level)
    local g = d.grades[(tonumber(level) or 0) + 1]
    if not g then return false end
    for _, p in ipairs(g.perms or {}) do if p == 'manage' then return true end end
    return false
end

-- the NUI sends each grade's previous level as `from`; → { [oldLevel] = newLevel }
local function gradeMap(base, rawGrades, newGrades)
    local map, used = {}, {}
    if type(rawGrades) == 'table' then
        local i = 0
        for _, g in ipairs(rawGrades) do
            if type(g) == 'table' then
                i = i + 1
                local from = I.int(g.from, 0, #base.grades - 1)
                if from and newGrades[i] and not used[from] then
                    used[from] = true
                    map[from] = i - 1
                end
            end
        end
    end
    -- removed grades: staff drop to the nearest lower grade that still exists
    for level = 0, #base.grades - 1 do
        if map[level] == nil then
            local to = 0
            for l = level - 1, 0, -1 do
                if map[l] ~= nil then to = map[l]; break end
            end
            map[level] = math.min(to, #newGrades - 1)
        end
    end
    return map
end

local function sameGrade(a, b)
    return a and b and a.name == b.name and a.label == b.label and a.salary == b.salary
        and table.concat(a.perms or {}, ',') == table.concat(b.perms or {}, ',')
end

-- bosses may only touch grades below their own: the top grades from theirs upwards must
-- stay identical, in the same order, on top of the list
local function bossGradesOk(base, d, map, bossLevel)
    local keep = #base.grades - bossLevel
    if #d.grades < keep then return false end
    for k = 0, keep - 1 do
        local old = base.grades[#base.grades - k]
        local new = d.grades[#d.grades - k]
        if not sameGrade(old, new) or map[old.level] ~= new.level then return false end
    end
    return true
end

local function remapStaff(d, map)
    local changed = {}
    for _, row in ipairs(I.StaffOf(d.id)) do
        local to = map[row.grade]
        if to == nil then to = math.min(row.grade, #d.grades - 1) end
        if to ~= row.grade then
            I.SetStaff(row.identifier, d.id, to, row.name, nil)
            changed[#changed + 1] = row.identifier
        end
    end
    return changed
end

lib.callback.register('nza:hospital:mgr:save', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local input = type(payload.dept) == 'table' and payload.dept or {}
    local id = I.ValidId(input.id)
    local base = id and H.Get(id)
    if not base then return fail('no_dept') end
    local role, bossDept, bossGrade = access(src, payload, id)
    if not role then return fail(bossDept or 'no_access') end

    local only = nil
    if role == 'boss' then only = { grades = true, outfits = true, vehicles = true } end
    local d, err = I.SanitizeDept(input, base, only)
    if not d then return fail(err or 'failed') end
    local map = gradeMap(base, input.grades, d.grades)

    if role == 'boss' then
        local myLevel = map[bossGrade.level] or bossGrade.level
        if not gradeHasManage(d, myLevel) then return fail('own_manage') end
        if cfg('staff', {}).bossOutranks ~= false and not bossGradesOk(base, d, map, bossGrade.level) then
            return fail('outranked')
        end
    end

    I.UpdateDept(d)
    local changed = remapStaff(d, map)
    if #changed > 0 then
        for _, ident in ipairs(changed) do
            local s = Core.B('GetSourceFromIdentifier', ident)
            s = tonumber(s)
            if s and Core.Online(s) then NZA.Staff.Refresh(s, true) end
        end
    end
    return reply(src, role, role == 'boss' and H.Get(d.id) or nil, { msg = NZA.L('hospital.saved', d.label) })
end)

lib.callback.register('nza:hospital:mgr:delete', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    local id = type(payload) == 'table' and I.ValidId(payload.id) or nil
    local d = id and H.Get(id)
    if not d then return fail('no_dept') end
    local label = d.label
    I.DeleteDept(id)
    return reply(src, 'admin', nil, { msg = NZA.L('hospital.deleted', label) })
end)

-- ════════════════════════════════════════════════════════════════════════
-- ROSTER
-- ════════════════════════════════════════════════════════════════════════

local function resolveTarget(target)
    local n = tonumber(target)
    if n and n > 0 and n < 65536 and math.floor(n) == n then
        if not Core.Online(n) then return nil end
        local ident = Core.Identifier(n)
        if not ident then return nil end
        return ident, n, Core.Name(n)
    end
    local ident = type(target) == 'string' and I.str(target, 80, '^[%w:_%-]+$') or nil
    if not ident then return nil end
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if s and Core.Identifier(s) == ident then return ident, s, Core.Name(s) end
    end
    local s = Core.B('GetSourceFromIdentifier', ident)
    s = tonumber(s)
    if s and Core.Online(s) then return ident, s, Core.Name(s) end
    local row = I.StaffRow(ident)
    return ident, nil, row and row.name or nil
end

local function currentLevel(ident, src, deptId)
    local row = I.StaffRow(ident)
    if row and row.department == deptId and not row.excluded then return row.grade end
    if src then
        local rec = NZA.Staff.Get(src)
        if rec and rec.dept == deptId then return rec.grade end
    end
    return nil
end

local function syncJob(src, d, grade)
    if not src or not d.job or not Core.Has('SetJob') then return false end
    if (cfg('staff', {}).syncFrameworkJob) == false then return false end
    return Core.B('SetJob', src, d.job, grade) == true
end

local function refresh(src)
    if src and Core.Online(src) then NZA.Staff.Refresh(src, true) end
end

lib.callback.register('nza:hospital:mgr:hire', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local d = H.Get(payload.dept)
    if not d then return fail('no_dept') end
    local role, bossDept, bossGrade = access(src, payload, d.id)
    if not role then return fail(bossDept or 'no_access') end

    local ident, tsrc, name = resolveTarget(payload.target)
    if not ident then return fail('no_target') end
    local grade = I.int(payload.grade, 0, #d.grades - 1, 0)
    if role == 'boss' and cfg('staff', {}).bossOutranks ~= false then
        if grade >= bossGrade.level then return fail('outranked') end
        local cur = currentLevel(ident, tsrc, d.id)
        if cur and cur >= bossGrade.level then return fail('outranked') end
        if ident == Core.Identifier(src) then return fail('self') end
    end
    local row = I.StaffRow(ident)
    if row and not row.excluded and row.department ~= d.id and H.Get(row.department) then
        return fail('other_dept', H.Get(row.department).label)
    end
    if #I.StaffOf(d.id) >= ((cfg('limits', {}).staff) or 500) then return fail('limit') end

    I.SetStaff(ident, d.id, grade, name or ident, Core.Identifier(src))
    syncJob(tsrc, d, grade)
    refresh(tsrc)
    if tsrc then
        Core.Notify(tsrc, NZA.L('hospital.you_hired', d.label, d.grades[grade + 1].label), 'success', d.label)
    end
    return reply(src, role, role == 'boss' and d or nil, { msg = NZA.L('hospital.hired', name or ident, d.grades[grade + 1].label) })
end)

lib.callback.register('nza:hospital:mgr:grade', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local d = H.Get(payload.dept)
    if not d then return fail('no_dept') end
    local role, bossDept, bossGrade = access(src, payload, d.id)
    if not role then return fail(bossDept or 'no_access') end

    local ident, tsrc, name = resolveTarget(payload.identifier)
    if not ident then return fail('no_target') end
    local cur = currentLevel(ident, tsrc, d.id)
    if cur == nil then return fail('not_member') end
    local grade = I.int(payload.grade, 0, #d.grades - 1, 0)
    if role == 'boss' and cfg('staff', {}).bossOutranks ~= false then
        if ident == Core.Identifier(src) then return fail('self') end
        if grade >= bossGrade.level or cur >= bossGrade.level then return fail('outranked') end
    end
    I.SetStaff(ident, d.id, grade, name, nil)
    syncJob(tsrc, d, grade)
    refresh(tsrc)
    if tsrc then
        Core.Notify(tsrc, NZA.L(grade > cur and 'hospital.you_promoted' or 'hospital.you_demoted', d.grades[grade + 1].label), grade > cur and 'success' or 'warning', d.label)
    end
    return reply(src, role, role == 'boss' and d or nil, { msg = NZA.L('hospital.graded', name or ident, d.grades[grade + 1].label) })
end)

lib.callback.register('nza:hospital:mgr:fire', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local d = H.Get(payload.dept)
    if not d then return fail('no_dept') end
    local role, bossDept, bossGrade = access(src, payload, d.id)
    if not role then return fail(bossDept or 'no_access') end

    local ident, tsrc, name = resolveTarget(payload.identifier)
    if not ident then return fail('no_target') end
    local cur = currentLevel(ident, tsrc, d.id)
    if cur == nil then return fail('not_member') end
    if role == 'boss' then
        if ident == Core.Identifier(src) then return fail('self') end
        if cfg('staff', {}).bossOutranks ~= false and cur >= bossGrade.level then return fail('outranked') end
    end

    -- linked department: take the framework job away, or keep an "excluded" marker so the
    -- job link doesn't make them a member again
    local jobRemoved = false
    if d.job and tsrc and Core.Has('SetJob') then
        local fj = (cfg('staff', {}).fireJob) or { name = 'unemployed', grade = 0 }
        jobRemoved = Core.B('SetJob', tsrc, fj.name, fj.grade) == true
    end
    I.RemoveStaff(ident, d.job ~= nil and not jobRemoved, d.id)
    if tsrc then
        I.SetOwnDuty(tsrc, nil)
        refresh(tsrc)
        Core.Notify(tsrc, NZA.L('hospital.you_fired', d.label), 'error', d.label)
    end
    return reply(src, role, role == 'boss' and d or nil, { msg = NZA.L('hospital.fired', name or ident) })
end)

-- ════════════════════════════════════════════════════════════════════════
-- POSITIONS & HQ (admins, placed in world)
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:hospital:mgr:point:add', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    payload = type(payload) == 'table' and payload or {}
    local d = H.Get(payload.dept)
    if not d then return fail('no_dept') end
    if not within(src, payload.coords) then return fail('too_far') end
    local p, err = I.AddPoint(d.id, payload.type, payload.coords, payload.data, payload.label)
    if not p then return fail(err or 'failed') end
    return reply(src, 'admin', nil, { point = plainPoint(p), msg = NZA.L('hospital.point_added') })
end)

lib.callback.register('nza:hospital:mgr:point:move', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    payload = type(payload) == 'table' and payload or {}
    if not within(src, payload.coords) then return fail('too_far') end
    local p, err = I.MovePoint(payload.id, payload.coords)
    if not p then return fail(err or 'failed') end
    return reply(src, 'admin', nil, { point = plainPoint(p), msg = NZA.L('hospital.point_moved') })
end)

lib.callback.register('nza:hospital:mgr:point:data', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    payload = type(payload) == 'table' and payload or {}
    local p, err = I.SetPointData(payload.id, payload.data, payload.label)
    if not p then return fail(err or 'failed') end
    return reply(src, 'admin', nil, { point = plainPoint(p), msg = NZA.L('hospital.point_saved') })
end)

lib.callback.register('nza:hospital:mgr:point:delete', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    payload = type(payload) == 'table' and payload or {}
    if not I.DeletePoint(payload.id) then return fail('no_point') end
    return reply(src, 'admin', nil, { msg = NZA.L('hospital.point_deleted') })
end)

lib.callback.register('nza:hospital:mgr:hq', function(src, payload)
    if not rate(src) then return fail('rate') end
    if not isAdmin(src) then return fail('no_access') end
    payload = type(payload) == 'table' and payload or {}
    local d = H.Get(payload.dept)
    if not d then return fail('no_dept') end
    local c = I.Coords(payload.coords)
    if not c then return fail('bad_coords') end
    if not within(src, c) then return fail('too_far') end
    local nd = U.deepcopy(d)
    nd.hq = c
    nd.updated = os.time()
    I.UpdateDept(nd)
    return reply(src, 'admin', nil, { hq = c, msg = NZA.L('hospital.hq_set', d.label) })
end)

-- ════════════════════════════════════════════════════════════════════════
-- FUNDS (society account through Bridge.Society)
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:hospital:mgr:funds', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local d = H.Get(payload.dept)
    if not d then return fail('no_dept') end
    local role, bossDept = access(src, payload, d.id)
    if not role then return fail(bossDept or 'no_access') end
    if not Core.Has('Society.Get') then return fail('no_society') end
    local amount = I.int(payload.amount, 1, 100000000)
    if not amount then return fail('bad_amount') end
    local society = I.Society(d)
    local account = payload.account == 'bank' and 'bank' or 'cash'

    if payload.action == 'deposit' then
        if not Core.B('RemoveMoney', src, account, amount, 'society_deposit') then return fail('no_money') end
        if not Core.B('Society.Add', society, amount) then
            Core.B('AddMoney', src, account, amount, 'society_refund')
            return fail('failed')
        end
    elseif payload.action == 'withdraw' then
        if not Core.B('Society.Remove', society, amount) then return fail('society_short') end
        Core.B('AddMoney', src, account, amount, 'society_withdraw')
    else
        return fail('failed')
    end
    NZA.Debug(('hospital funds: %s %s %d (%s) by %s'):format(d.id, payload.action, amount, society, Core.Name(src)))
    return reply(src, role, role == 'boss' and d or nil, { msg = NZA.L(payload.action == 'deposit' and 'hospital.deposited' or 'hospital.withdrew', amount) })
end)

-- ════════════════════════════════════════════════════════════════════════
-- /nzadmin
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)
    local name = Config.Commands and Config.Commands.admin
    if type(name) ~= 'string' or name == '' then return end
    RegisterCommand(name, function(source)
        local src = tonumber(source) or 0
        if src <= 0 then
            print('[nayzeee-ambulance] /' .. name .. ' must be used in game')
            return
        end
        if not isAdmin(src) then
            Core.Notify(src, NZA.L('hospital.err_no_access'), 'error')
            return
        end
        TriggerClientEvent('nza:hospital:openManager', src, 'admin')
    end, false)

    local function suggest(src)
        if isAdmin(src) then
            TriggerClientEvent('chat:addSuggestion', src, '/' .. name, NZA.L('hospital.cmd_help'), {})
        end
    end
    NZA.Bus.On('player:loaded', function(src)
        SetTimeout(2500, function() if Core.Online(src) then suggest(src) end end)
    end)
    Wait(4000)
    for _, id in ipairs(GetPlayers()) do suggest(tonumber(id)) end
end)
