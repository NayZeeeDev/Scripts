--[[
    NAYZEEE AMBULANCE - Fracture care (client): X-ray route, set the bone, apply a cast

    Examination routes (NZA.ExamRoutes, shown in the exam's "Next care step" card)
        xray_take    'X-ray needed'  fractures / retained fragments that were not read on a film yet
                                      (available while the patient lies on an X-ray table, or in easy mode)
        xray_reduce  'Set the bone'  displaced limb fracture, read on a film     (perm Config.Xray.Reduce.perm)
        xray_cast    'Apply cast'    aligned limb fracture without a cast        (perm Config.Xray.Cast.perm,
                                      Config.Items.cast)
    Patient options (NZA.Interact): nza_xray_reduce 'Set the bone' (order 68), nza_xray_cast 'Apply cast'
        (order 69) - shown when the patient has a fracture; picks the fracture (context menu when several)
    Procedures (NZA.Proc.Run): 'xray_reduce' → NUI 'xray' mode 'reduce' (traction under live fluoroscopy),
        'xray_cast' → mode 'cast' (padding, plaster turns, moulding). Easy mode: core progress bar.
    Lua API (runtime): NZA.Xray.Reduce(entity, target, injuryId), NZA.Xray.Cast(entity, target, injuryId)
    Uses NZA.Xray.RunApp / Take / TablePoint / EntityOf from client/modules/xray.lua at runtime only.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Xray = NZA.Xray or {}
local U = NZA.Util

local function cfg(section)
    local c = Config.Xray or {}
    return c[section] or {}
end

local function L(key, ...)
    return NZA.L('xray.' .. key, ...)
end

local function X()
    return NZA.Xray or {}
end

local function tolerance()
    return tonumber(cfg('Reduce').tolerance) or 3
end

local function itemsFrom(list)
    local out = {}
    for key, n in pairs(list or {}) do
        local name = Config.Items and Config.Items[key] or nil
        if name and (tonumber(n) or 0) > 0 then out[name] = math.floor(tonumber(n)) end
    end
    return out
end

local function isDisplaced(inj)
    local f = inj.fracture or {}
    local t = inj.treat or {}
    return f.displaced == true and (tonumber(f.angle) or 0) > tolerance() and not t.reduced
end

local function woundCared(inj)
    local t = inj.treat or {}
    return t.irrigated or t.sutured or t.dressed or t.bandaged
end

-- 'reduce' | 'cast' → can this injury get it now
local function eligible(kind, inj)
    if type(inj) ~= 'table' or inj.type ~= 'fracture' or type(inj.fracture) ~= 'table' then return false end
    local regions = (kind == 'reduce' and cfg('Reduce').regions) or cfg('Cast').regions or {}
    if not regions[inj.region] then return false end
    local t = inj.treat or {}
    if t.cast then return false end
    if kind == 'reduce' then return isDisplaced(inj) end
    return not isDisplaced(inj)
end

local function workAnim(s)
    local me = PlayerPedId()
    local ent = s.entity
    local low = ent and ent ~= 0 and DoesEntityExist(ent) and (GetEntityCoords(ent).z - GetEntityCoords(me).z) < -0.35
    if low and NZA.Anim.Kneel then
        NZA.Anim.Kneel(me)
    else
        NZA.Anim.Play(me, 'mini@repair', 'fixing_a_ped', { flag = 49 })
    end
end

local function limbCam(entity, region)
    if not entity or entity == 0 then return end
    NZA.Cam.Close(entity, region, { dist = 1.1, pitch = 58, fov = 44, orbit = true, hideHud = true })
end

-- ════════════════════════════════════════════════════════════════════════
-- RUNNERS
-- ════════════════════════════════════════════════════════════════════════

function NZA.Xray.Reduce(entity, target, injId)
    if type(target) ~= 'table' then target = NZA.Target.FromEntity(entity) end
    if not target then return false end
    entity = entity or NZA.Target.Entity(target)
    return X().RunApp({
        name = 'xray_reduce', mode = 'reduce', entity = entity, target = target, payload = { injury = injId },
        label = L('reduce_title'), keepOpen = 30,
        anim = workAnim,
        cam = function(s) limbCam(entity, (s.ctx.data or {}).region) end,
    })
end

function NZA.Xray.Cast(entity, target, injId)
    if type(target) ~= 'table' then target = NZA.Target.FromEntity(entity) end
    if not target then return false end
    entity = entity or NZA.Target.Entity(target)
    return X().RunApp({
        name = 'xray_cast', mode = 'cast', entity = entity, target = target, payload = { injury = injId },
        label = L('cast_title'), keepOpen = 30,
        anim = workAnim,
        cam = function(s) limbCam(entity, (s.ctx.data or {}).region) end,
    })
end

-- pick the fracture for a patient-menu option
local function pickAndRun(kind, entity, target)
    if X().Busy and X().Busy() then
        X().Toast('err_busy', 'error')
        return
    end
    local ok, snap = pcall(NZA.Patient.Get, target)
    if not ok or type(snap) ~= 'table' then
        X().Toast('err_generic', 'error')
        return
    end
    local list = {}
    for _, inj in ipairs(snap.injuries or {}) do
        if eligible(kind, inj) then list[#list + 1] = inj end
    end
    if #list == 0 then
        local reason = 'err_no_' .. kind
        for _, inj in ipairs(snap.injuries or {}) do
            if kind == 'cast' and eligible('reduce', inj) then reason = 'err_reduce_first' break end
        end
        X().Toast(reason, 'error')
        return
    end
    local run = kind == 'reduce' and NZA.Xray.Reduce or NZA.Xray.Cast
    if #list == 1 then
        run(entity, target, list[1].id)
        return
    end
    local options = {}
    for _, inj in ipairs(list) do
        local f = inj.fracture or {}
        options[#options + 1] = {
            title = ('%s · %s'):format(U.RegionLabel(inj.region), NZA.L('core.bone_' .. tostring(f.bone))),
            description = kind == 'reduce' and L('menu_angle', math.floor(tonumber(f.angle) or 0)) or NZA.L('core.fracture_' .. tostring(f.kind)),
            icon = 'bone',
            onSelect = function() CreateThread(function() run(entity, target, inj.id) end) end,
        }
    end
    lib.registerContext({ id = 'nza_xray_pick', title = L(kind == 'reduce' and 'reduce_title' or 'cast_title'), options = options })
    lib.showContext('nza_xray_pick')
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT OPTIONS
-- ════════════════════════════════════════════════════════════════════════

local function hasFracture(st)
    if type(st) ~= 'table' or type(st.tags) ~= 'table' then return false end
    if st.carried or st.bag then return false end
    for _, t in ipairs(st.tags) do if t == 'fracture' then return true end end
    return false
end

NZA.Interact.Add({
    name = 'nza_xray_reduce', label = L('opt_reduce'), icon = 'bone', order = 68,
    perm = cfg('Reduce').perm or 'splint', states = { alive = true, wounded = true }, distance = 2.5,
    canInteract = function(_, _, st) return hasFracture(st) end,
    onSelect = function(entity, target) pickAndRun('reduce', entity, target) end,
})

NZA.Interact.Add({
    name = 'nza_xray_cast', label = L('opt_cast'), icon = 'splint', order = 69,
    perm = cfg('Cast').perm or 'splint', states = { alive = true, wounded = true }, distance = 2.5,
    canInteract = function(_, _, st) return hasFracture(st) end,
    onSelect = function(entity, target) pickAndRun('cast', entity, target) end,
})

-- ════════════════════════════════════════════════════════════════════════
-- EXAMINATION ROUTES
-- ════════════════════════════════════════════════════════════════════════

local function snapEntity(snap)
    if type(snap) ~= 'table' then return 0 end
    return X().EntityOf({ kind = snap.kind, net = snap.net, sid = snap.src })
end

NZA.ExamRoutes = NZA.ExamRoutes or {}

table.insert(NZA.ExamRoutes, {
    id = 'xray_take', label = L('route_xray'), icon = 'xray', perm = cfg('Take').perm or 'xray', order = 12,
    types = { 'fracture', 'gunshot', 'shrapnel' },
    available = function(inj, snap)
        local t = inj.treat or {}
        if t.xrayMarked then return false end
        if inj.type ~= 'fracture' and ((tonumber(inj.retained) or 0) <= 0 or t.extracted) then return false end
        local R = NZA.Const.Region[inj.region or '']
        if not R or not R.xray then return false end
        local ent = snapEntity(snap)
        if X().TablePoint and X().TablePoint(ent) then return true end
        if cfg('Take').easyAnywhere ~= false and NZA.Easy(cfg('Take').perm or 'xray') then return true end
        if t.xray then return false, L('route_read_again') end
        return false, L('route_need_table')
    end,
    run = function(target, inj)
        local R = NZA.Const.Region[inj.region or '']
        if not R then return end
        X().Take(NZA.Target.Entity(target), target, R.xray)
    end,
})

table.insert(NZA.ExamRoutes, {
    id = 'xray_reduce', label = L('route_reduce'), icon = 'bone', perm = cfg('Reduce').perm or 'splint', order = 30,
    types = { 'fracture' },
    items = itemsFrom(cfg('Reduce').items),
    available = function(inj)
        if not eligible('reduce', inj) then return false end
        local t = inj.treat or {}
        if cfg('Reduce').requireXray ~= false and not (t.xray or t.xrayMarked) and not NZA.Easy(cfg('Reduce').perm or 'splint') then
            return false, L('route_need_xray')
        end
        return true
    end,
    run = function(target, inj)
        NZA.Xray.Reduce(NZA.Target.Entity(target), target, inj.id)
    end,
})

table.insert(NZA.ExamRoutes, {
    id = 'xray_cast', label = L('route_cast'), icon = 'splint', perm = cfg('Cast').perm or 'splint', order = 35,
    types = { 'fracture' },
    items = Config.Items and Config.Items.cast and { [Config.Items.cast] = 1 } or nil,
    available = function(inj)
        if type(inj.fracture) ~= 'table' or not (cfg('Cast').regions or {})[inj.region] then return false end
        local t = inj.treat or {}
        if t.cast then return false end
        if isDisplaced(inj) then return false, L('route_reduce_first') end
        if cfg('Cast').openNeedsWoundCare ~= false and inj.fracture.kind == 'open' and not woundCared(inj) then
            return false, L('route_wound_first')
        end
        return true
    end,
    run = function(target, inj)
        NZA.Xray.Cast(NZA.Target.Entity(target), target, inj.id)
    end,
})
