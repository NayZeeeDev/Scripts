--[[
    NAYZEEE AMBULANCE - Department Console (client): opens the 'manager' NUI app and carries its
    actions to the server (server/modules/hospital_manager.lua checks everything again).

    Open
      /nzadmin (Config.Commands.admin, server checks admin)   → 'nza:hospital:openManager' ('admin')
      boss point "Command desk"                                → NZA.HospitalC.OpenManager('boss', pointId)
      radial "Department Console" (admins)
    NUI open data: { mode, data (server snapshot), types (every registered position type),
                     me = { x, y, z, w }, locale, resume }

    NUI callbacks (manager:*)
      create { id, label }      save { dept }          delete { id }
      hire { dept, target, grade }   grade { dept, identifier, grade }   fire { dept, identifier }
      pointData { id, data, label }  pointDelete { id }  funds { dept, action, amount, account }
      place { dept, type, point?, hq? }   → closes the window, runs the site survey HUD, reopens
      goto { coords }                     → admins: fade teleport there
      capture {}                          → { gender, data } outfit from what you wear now
      tryOn { data }  restore {}          → wear an outfit locally / put your clothes back
      refresh {}                          → fresh server snapshot
    Every server reply is { ok, err?, msg?, data? }.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.HospitalC = NZA.HospitalC or {}
local C = NZA.HospitalC

local APP = 'manager'
local session = nil      -- { mode, point }

local function L(key, ...) return NZA.L('hospital.' .. key, ...) end

local function call(name, payload)
    local ok, res = pcall(lib.callback.await, name, false, payload)
    if not ok or type(res) ~= 'table' then return { ok = false, msg = L('err_failed') } end
    return res
end

local function myCoords()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
end

-- every registered position type, for the "Add a position" buttons and the folders
local function typeList()
    local out = {}
    for name, def in pairs(NZA.Points.Types()) do
        local kind = def.ghost or (def.prop and 'prop' or 'marker')
        out[#out + 1] = {
            name = name, label = def.label or name, icon = def.icon or 'pin', kind = kind,
            desc = def.desc, manager = def.manager ~= false, data = def.data or {},
            prop = def.prop and tostring(def.prop) or nil,
        }
    end
    table.sort(out, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return out
end

local function openWith(res, resume, extra)
    local data = {
        mode = session and session.mode or 'admin',
        data = res.data, types = typeList(), me = myCoords(),
        locale = NZA.LocaleTable('hospital'), resume = resume == true,
    }
    if extra then for k, v in pairs(extra) do data[k] = v end end
    NZA.UI.Open(APP, data, { focus = true, cursor = true })
end

function C.OpenManager(mode, pointId)
    if C.Placing and C.Placing() then return end
    local res = call('nza:hospital:mgr:open', { mode = mode, point = pointId })
    if not res.ok then
        if res.msg then C.toast(res.msg, 'error') end
        return
    end
    local same = session and session.mode == res.data.mode
    session = { mode = res.data.mode, point = pointId }
    openWith(res, same)
end

RegisterNetEvent('nza:hospital:openManager', function(mode)
    CreateThread(function() C.OpenManager(mode == 'boss' and 'boss' or 'admin') end)
end)

-- forward one NUI action to a server callback and hand the reply back
local function relay(event, server, shape)
    NZA.UI.On(APP, event, function(data, cb)
        if type(data) ~= 'table' then data = {} end
        local payload = shape and shape(data) or data
        payload.mode = session and session.mode or 'admin'
        local res = call(server, payload)
        res.me = myCoords()
        cb(res)
    end)
end

relay('create', 'nza:hospital:mgr:create')
relay('save', 'nza:hospital:mgr:save')
relay('delete', 'nza:hospital:mgr:delete')
relay('hire', 'nza:hospital:mgr:hire')
relay('grade', 'nza:hospital:mgr:grade')
relay('fire', 'nza:hospital:mgr:fire')
relay('pointData', 'nza:hospital:mgr:point:data')
relay('pointDelete', 'nza:hospital:mgr:point:delete')
relay('funds', 'nza:hospital:mgr:funds')

NZA.UI.On(APP, 'refresh', function(_, cb)
    local res = call('nza:hospital:mgr:open', { mode = session and session.mode or 'admin', point = session and session.point })
    res.me = myCoords()
    res.types = typeList()
    cb(res)
end)

-- ════════════════════════════════════════════════════════════════════════
-- PLACEMENT (close → place in world → reopen where the admin left off)
-- ════════════════════════════════════════════════════════════════════════

local function vehicleModel(deptId, kind)
    local d = C.depts and C.depts[deptId]
    for _, v in ipairs(d and d.vehicles or {}) do
        if v.type == kind then return v.model end
    end
    local gc = (Config.Hospital and Config.Hospital.garage) or {}
    return kind == 'heli' and (gc.heliModel or 'polmav') or (gc.carModel or 'ambulance')
end

NZA.UI.On(APP, 'place', function(data, cb)
    if type(data) ~= 'table' or not data.dept or not (data.type or data.hq) then
        cb({ ok = false })
        return
    end
    local rec = NZA.Staff.Get() or {}
    if not rec.admin then
        cb({ ok = false, msg = L('err_no_access') })
        return
    end
    cb({ ok = true })
    CreateThread(function()
        NZA.UI.Close(APP)
        local typeName = data.hq and 'hq' or data.type
        local def = NZA.Points.Type(typeName) or {}
        local kind = def.ghost or (def.prop and 'prop' or 'marker')
        local d = C.depts and C.depts[data.dept]
        local from = nil
        if data.point then
            local pt = NZA.Points.Get(tonumber(data.point) or data.point)
            if pt then from = { x = pt.coords.x, y = pt.coords.y, z = pt.coords.z, w = pt.coords.w } end
        elseif data.hq and d and d.hq then
            from = d.hq
        end
        local coords = C.Place({
            type = typeName, label = def.label or typeName, icon = def.icon, kind = kind, prop = def.prop,
            model = (kind == 'car' or kind == 'heli') and vehicleModel(data.dept, kind) or nil,
            dept = data.dept, deptLabel = d and d.label or data.dept, from = from,
        })

        local res, note = nil, nil
        if coords then
            if data.hq then
                res = call('nza:hospital:mgr:hq', { dept = data.dept, coords = coords })
            elseif data.point then
                res = call('nza:hospital:mgr:point:move', { id = data.point, coords = coords })
            else
                res = call('nza:hospital:mgr:point:add', { dept = data.dept, type = typeName, coords = coords, data = def.data or {} })
            end
            note = { ok = res.ok, msg = res.msg, point = res.point, hq = res.hq }
        end
        if not res or not res.ok then
            res = call('nza:hospital:mgr:open', { mode = session and session.mode or 'admin' })
        end
        if res.ok and res.data then
            openWith(res, true, { placed = note })
        elseif res.msg then
            C.toast(res.msg, 'error')
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- GO TO / OUTFITS
-- ════════════════════════════════════════════════════════════════════════

NZA.UI.On(APP, 'goto', function(data, cb)
    local rec = NZA.Staff.Get() or {}
    local c = type(data) == 'table' and data.coords
    if not rec.admin or type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) or not tonumber(c.z) then
        cb({ ok = false, msg = L('err_no_access') })
        return
    end
    cb({ ok = true })
    CreateThread(function()
        NZA.UI.Close(APP)
        C.Teleport(vector3(tonumber(c.x), tonumber(c.y), tonumber(c.z)), tonumber(c.w))
    end)
end)

NZA.UI.On(APP, 'capture', function(_, cb)
    local gender = C.Gender()
    if not gender then
        cb({ ok = false, msg = L('err_no_freemode') })
        return
    end
    cb({ ok = true, gender = gender, data = C.CaptureOutfit() })
end)

NZA.UI.On(APP, 'tryOn', function(data, cb)
    if type(data) ~= 'table' or type(data.data) ~= 'table' then
        cb({ ok = false })
        return
    end
    if Bridge.Clothing and Bridge.Clothing.HasSaved and not Bridge.Clothing.HasSaved() then Bridge.Clothing.Save() end
    C.ApplyOutfit(data.data)
    cb({ ok = true })
end)

NZA.UI.On(APP, 'restore', function(_, cb)
    local ok = Bridge.Clothing and Bridge.Clothing.HasSaved and Bridge.Clothing.HasSaved() and Bridge.Clothing.Restore()
    cb({ ok = ok and true or false, msg = ok and L('civvies_on') or L('err_no_civvies') })
end)
