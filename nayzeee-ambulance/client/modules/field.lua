--[[
    NAYZEEE AMBULANCE - Field resuscitation (client): shared helpers, worn binder, menus

      NZA.Field (client)
        F.Cfg(section)  F.L(key, ...)  F.Toast(msg, type, title)  F.ItemName(key)  F.ItemCount(key)
        F.Frame(ped)          body frame of a lying patient { pelvis, head, axis, side, z } (side points
                              away from the medic)
        F.Spot(frame, side, along) → vector3 on the ground   F.HeadingX(vec) / F.HeadingY(vec)
        F.Ground(pos) → z     F.NearestPatient(range) → entity, target
        F.Busy() / F.SetBusy(name)
        F.Start(entity, target)          field resuscitation scene      (client/modules/field_scene.lua)
        F.StartIV(entity, target, site)  IV cannulation                 (client/modules/field_scene.lua)
      NZA.Monitor (client/modules/field_monitor.lua) - patient monitor overlay + prop

    Registries (top level): NZA.Interact.Add (Field resuscitation 31, Attach / remove patient
    monitor 25/26, IV cannulation 44, Remove pelvic binder 48, Remove IV / IO line 49),
    NZA.ExamRoutes ('field_resus', 'field_iv'), NZA.RadialItems (patient: field_resus, field_iv,
    field_monitor).
    Worn binder: every client attaches Config.Props.binder_worn to SKEL_Pelvis of patients whose
    state bag says binder = true (within Config.Field.Binder.worn.range).
    Net events: nza:field:use (what) from the usable trauma kit / IV kit.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Field = NZA.Field or {}
local F = NZA.Field

function F.Cfg(section)
    local c = Config.Field or {}
    if section then return c[section] or {} end
    return c
end

local function L(key, ...) return NZA.L('field.' .. key, ...) end
F.L = L

function F.Toast(msg, kind, title)
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'info' })
end

function F.ItemName(key)
    return key and Config.Items and Config.Items[key] or nil
end

function F.ItemCount(key)
    local name = F.ItemName(key)
    if not name or not Bridge or not Bridge.Inv then return 0 end
    if Bridge.Inv.Count then
        local ok, n = pcall(Bridge.Inv.Count, name)
        if ok and tonumber(n) then return tonumber(n) end
    end
    if Bridge.Inv.Has then
        local ok, has = pcall(Bridge.Inv.Has, name, 1)
        if ok then return has and 1 or 0 end
    end
    return 1    -- unknown inventory: let the server decide
end

local busy = nil
function F.Busy() return busy end
function F.SetBusy(name) busy = name end

-- ════════════════════════════════════════════════════════════════════════
-- GEOMETRY (where things go around a lying patient)
-- ════════════════════════════════════════════════════════════════════════

function F.Ground(pos)
    local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    if found then return z end
    return pos.z - 0.9
end

function F.Frame(ped)
    local pelvis = GetPedBoneCoords(ped, 11816, 0.0, 0.0, 0.0)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local ax = vector3(head.x - pelvis.x, head.y - pelvis.y, 0.0)
    local len = #ax
    if len < 0.25 then
        local fw = GetEntityForwardVector(ped)
        ax = vector3(fw.x, fw.y, 0.0)
        len = #ax
    end
    ax = len > 0.001 and (ax / len) or vector3(0.0, 1.0, 0.0)
    local side = vector3(ax.y, -ax.x, 0.0)
    local me = GetEntityCoords(PlayerPedId())
    local toMe = vector3(me.x - pelvis.x, me.y - pelvis.y, 0.0)
    if toMe.x * side.x + toMe.y * side.y > 0 then side = -side end
    return { pelvis = pelvis, head = head, axis = ax, side = side, z = F.Ground(pelvis) }
end

function F.Spot(frame, side, along)
    local p = frame.pelvis + frame.side * (side or 0.0) + frame.axis * (along or 0.0)
    return vector3(p.x, p.y, F.Ground(vector3(p.x, p.y, frame.pelvis.z)))
end

-- heading that points the prop's +Y / +X along a flat vector
function F.HeadingY(v) return (math.deg(math.atan(-v.x, v.y)) + 360.0) % 360.0 end
function F.HeadingX(v) return (math.deg(math.atan(v.y, v.x)) + 360.0) % 360.0 end

function F.NearestPatient(range)
    range = range or F.Cfg('Radial').range or 3.0
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestD = nil, range
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= me and DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d < bestD and Player(GetPlayerServerId(pl)).state.nza then best, bestD = ped, d end
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d < bestD and Entity(ped).state.nza then best, bestD = ped, d end
        end
    end
    if not best then return nil end
    local target = NZA.Target.FromEntity(best)
    if not target then return nil end
    return best, target
end

local function hasKit()
    local key = F.Cfg('Resus').kit
    if not key then return true end
    return F.ItemCount(key) > 0
end
F.HasKit = hasKit

local function canResus()
    for _, perm in ipairs(F.Cfg('Resus').perms or { 'iv', 'binder' }) do
        if NZA.Perm(perm) then return true end
    end
    return false
end
F.CanResus = canResus

-- ════════════════════════════════════════════════════════════════════════
-- WORN PELVIC BINDER (rendered by every client from the state bag)
-- ════════════════════════════════════════════════════════════════════════

local worn = {}   -- [ped] = entity

local function attachBinder(ped)
    local key = Config.Props and Config.Props.binder_worn and 'binder_worn' or nil
    if not key then return 0 end
    local at = F.Cfg('Binder').attach or {}
    local p, r = at.pos or { 0.0, 0.0, 0.0 }, at.rot or { 0.0, 90.0, 0.0 }
    local ok, ent = pcall(NZA.Props.Spawn, key, {
        attach = { entity = ped, bone = at.bone or 11816, pos = vector3(p[1], p[2], p[3]), rot = vector3(r[1], r[2], r[3]), collision = false },
    }, { group = 'field_worn', collision = false })
    return ok and ent or 0
end

local function clearWorn(ped)
    local ent = worn[ped]
    worn[ped] = nil
    if ent and ent ~= 0 then NZA.Props.Delete(ent) end
end

CreateThread(function()
    Wait(2500)
    while true do
        local range = tonumber((F.Cfg('Binder').worn or {}).range) or 40.0
        local pos = GetEntityCoords(PlayerPedId())
        local want = {}
        for _, pl in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(pl)
            local bag = Player(GetPlayerServerId(pl)).state.nza
            if type(bag) == 'table' and bag.binder and DoesEntityExist(ped) and #(GetEntityCoords(ped) - pos) < range then want[ped] = true end
        end
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and #(GetEntityCoords(ped) - pos) < range then
                local bag = Entity(ped).state.nza
                if type(bag) == 'table' and bag.binder and not bag.bag then want[ped] = true end
            end
        end
        for ped, ent in pairs(worn) do
            if not want[ped] or not DoesEntityExist(ped) or (ent ~= 0 and not DoesEntityExist(ent)) then clearWorn(ped) end
        end
        for ped in pairs(want) do
            if not worn[ped] then worn[ped] = attachBinder(ped) end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ped in pairs(worn) do clearWorn(ped) end
    if NZA.Props and NZA.Props.Clear then NZA.Props.Clear('field_worn') end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT OPTIONS (order bands: 20 assessment, 30 resuscitation, 40 treatment)
-- ════════════════════════════════════════════════════════════════════════

local function free(st) return type(st) == 'table' and not st.bag and not st.carried end

local function start(name, ...)
    local args = { ... }
    return function(entity, target)
        local fn = F[name]
        if fn then fn(entity, target, table.unpack(args)) end
    end
end

do
    local ic = F.Cfg('Interact')
    local icons = ic.icons or {}
    local dist = ic.distance or 2.2
    local LIVE = { alive = true, wounded = true, arrest = true }
    local ALL = { alive = true, wounded = true, arrest = true, dead = true }

    if ic.resus ~= false then
        NZA.Interact.Add({
            name = 'nza_field_resus', label = L('opt_resus'), icon = icons.resus or 'iv', order = 31,
            states = { alive = true, wounded = true }, distance = dist,
            canInteract = function(_, _, st)
                if not free(st) or not canResus() or not hasKit() then return false end
                local bleed = tonumber(st.bleed) or 0
                return bleed >= (ic.resusBleed or 2) or (bleed >= 1 and not st.iv)
            end,
            onSelect = start('Start'),
        })
    end
    if ic.iv ~= false then
        NZA.Interact.Add({
            name = 'nza_field_iv', label = L('opt_iv'), icon = icons.iv or 'syringe', order = 44,
            perm = F.Cfg('IV').perm or 'iv', states = LIVE, distance = dist,
            canInteract = function(_, _, st) return free(st) and not st.iv and F.ItemCount(F.Cfg('IV').item or 'iv_kit') > 0 end,
            onSelect = start('StartIV'),
        })
    end
    if ic.monitor ~= false then
        NZA.Interact.Add({
            name = 'nza_field_monitor', label = L('opt_monitor'), icon = icons.monitor or 'monitor', order = 25,
            perm = F.Cfg('Monitor').perm or 'assess', states = LIVE, distance = dist,
            canInteract = function(entity, _, st)
                return free(st) and NZA.Monitor ~= nil and not NZA.Monitor.AttachedTo(entity)
            end,
            onSelect = function(entity, target) if NZA.Monitor then NZA.Monitor.Attach(entity, target) end end,
        })
        NZA.Interact.Add({
            name = 'nza_field_monitor_off', label = L('opt_monitor_off'), icon = icons.monitor or 'monitor', order = 26,
            perm = F.Cfg('Monitor').perm or 'assess', states = ALL, distance = dist + 1.0,
            canInteract = function(entity) return NZA.Monitor ~= nil and NZA.Monitor.AttachedTo(entity) end,
            onSelect = function() if NZA.Monitor then NZA.Monitor.Detach() end end,
        })
    end
    if ic.binderOff ~= false then
        NZA.Interact.Add({
            name = 'nza_field_binder_off', label = L('opt_binder_off'), icon = icons.binderOff or 'shield', order = 48,
            perm = F.Cfg('Binder').perm or 'binder', states = ALL, distance = dist,
            canInteract = function(_, _, st) return type(st) == 'table' and st.binder == true and not st.bag end,
            onSelect = function(entity, target)
                if F.Busy() then return end
                NZA.Treat.Do('binder_off', target or entity, {})
            end,
        })
    end
    if ic.ivOff ~= false then
        NZA.Interact.Add({
            name = 'nza_field_iv_off', label = L('opt_iv_off'), icon = icons.ivOff or 'iv', order = 49,
            perm = F.Cfg('IV').perm or 'iv', states = ALL, distance = dist,
            canInteract = function(_, _, st) return type(st) == 'table' and st.iv == true and not st.bag end,
            onSelect = function(entity, target)
                if F.Busy() then return end
                NZA.Treat.Do('iv_off', target or entity, {})
            end,
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- EXAMINATION ROUTES ('Injuries to treat' card of the assess module)
-- ════════════════════════════════════════════════════════════════════════

NZA.ExamRoutes = NZA.ExamRoutes or {}

local function items(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = F.ItemName(key)
        if name then out[name] = n end
    end
    return out
end

local PELVIC = { pelvic = true, femoral = true }

do
    local ex = F.Cfg('Exam')
    if ex.enabled ~= false then
        table.insert(NZA.ExamRoutes, {
            id = 'field_resus', label = L('route_resus'), icon = 'iv', perm = F.Cfg('Infusion').perm or 'iv', order = 18,
            types = { 'gunshot', 'shrapnel', 'stab', 'laceration', 'internal', 'fracture', 'contusion' },
            items = items({ [F.Cfg('Resus').kit or 'trauma_kit'] = 1 }),
            available = function(inj, snap)
                local organ = inj.internal and inj.internal.organ
                local heavy = (tonumber(inj.bleed) or 0) >= (ex.heavyBleed or 25)
                local pelvic = inj.region == 'pelvis' or (organ and PELVIC[organ])
                local internal = inj.type == 'internal' and (tonumber(inj.bleed) or 0) > 1
                if not (heavy or pelvic or internal) then return false end
                if snap and (snap.state == 'dead' or snap.state == 'arrest') then return false, L('route_arrest') end
                return true
            end,
            run = function(target) F.Start(NZA.Target.Entity(target), target) end,
        })
        table.insert(NZA.ExamRoutes, {
            id = 'field_iv', label = L('route_iv'), icon = 'syringe', perm = F.Cfg('IV').perm or 'iv', order = 19,
            types = { 'gunshot', 'shrapnel', 'stab', 'laceration', 'internal', 'burn', 'fracture' },
            items = items({ [F.Cfg('IV').item or 'iv_kit'] = 1 }),
            available = function(inj, snap)
                if (tonumber(inj.bleed) or 0) < 3 then return false end
                local d = snap and snap.devices or {}
                if d.iv or d.port then return false, L('route_has_line') end
                return true
            end,
            run = function(target) F.StartIV(NZA.Target.Entity(target), target) end,
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- EMS RADIAL (Patient)
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

local function radial(id, label, icon, order, perm, fn, show)
    table.insert(NZA.RadialItems, {
        id = id, parent = 'patient', label = label, icon = icon, order = order, perm = perm,
        canShow = function()
            if F.Cfg('Radial').enabled == false then return false end
            if show and not show() then return false end
            return F.NearestPatient() ~= nil
        end,
        onSelect = function()
            CreateThread(function()
                local ent, target = F.NearestPatient()
                if not ent then F.Toast(L('err_nobody'), 'error') return end
                fn(ent, target)
            end)
        end,
    })
end

do
    radial('field_resus', L('opt_resus'), 'iv', 31, nil, function(e, t) F.Start(e, t) end, function() return canResus() and hasKit() end)
    radial('field_iv', L('opt_iv'), 'syringe', 44, F.Cfg('IV').perm or 'iv', function(e, t) F.StartIV(e, t) end)
    radial('field_monitor', L('opt_monitor_toggle'), 'monitor', 25, F.Cfg('Monitor').perm or 'assess', function(e, t)
        if not NZA.Monitor then return end
        if NZA.Monitor.AttachedTo(e) then NZA.Monitor.Detach() else NZA.Monitor.Attach(e, t) end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS (trauma kit / IV kit from the inventory)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:field:use', function(what)
    if F.Busy() then return end
    local ent, target = F.NearestPatient(F.Cfg('Interact').distance or 2.5)
    if not ent then
        F.Toast(L('err_nobody'), 'error')
        return
    end
    if what == 'iv' then F.StartIV(ent, target) else F.Start(ent, target) end
end)
