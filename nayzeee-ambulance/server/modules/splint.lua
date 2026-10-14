--[[
    NAYZEEE AMBULANCE - Splints & crutches (server)

    Procedure (ARCHITECTURE §5.2)
      NZA.Proc.Register('splint', { perm = Config.Splint.Splint.perm, items = { [Config.Items.splint] = 1 }, ... })
        payload  { injury = 'i7' } | { region = 'r_lower_leg' }
        onStart  → a limb fracture without a splint / cast in Config.Splint.Splint.regions; open fractures must
                   be dressed first when requireDressedOpen (skipped in easy mode). A standing player patient is
                   asked to sit down (net event 'nza:splint:pose').
                   data → { injury, region, regionLabel, device, deviceLabel, deviceModel, limb, segment, joints,
                            fracture { kind, kindLabel, bone, boneLabel, displaced, angle }, open, dressed, severity,
                            pulse ('present'|'weak'|'absent'), pulseWhy, hr, sys, refill, responsive, name, sex, pain,
                            size { width, depth, wall, limbRadius }, tune {...} }
        onFinish → result { score, align, mould, straps, checks, pressure, padded, tight, loose, resets, time } is
                   clamped; devices.splints[region] = 'leg'|'arm', treat.splinted, quality.splinted, extra pain
                   relief, bill. A score under minScore fails (the splint item is handed back).
        onAbort  → patient pose released.
    Treatments (NZA.Treat)
      'splint_remove'  { region }  perm Splint.removePerm - takes a splint off (item back when removeReturns)
      'crutches_give'  {}          perm Crutches.givePerm, medic's crutches item → the player patient (+ bill)
    Crutches
      usable item Config.Items.crutches → toggles crutch walking; player state bag 'nzaCrutch' = true (replicated)
      callback 'nza:splint:crutch:toggle' () → { ok, on } | { ok = false, err, msg }      (key / command)
      S→C 'nza:splint:crutch' (on)  ·  S→C 'nza:splint:pose' (on)
      Server check every Crutches.checkEvery s that crutch users still carry the item; crutches drop when the
      player goes down or leaves.
    Bus: listens to injury:removed / injury:updated (auto-remove healed splints), state:changed.
    Server API: NZA.Splint.SetCrutches(src, on), NZA.Splint.HasCrutches(src), NZA.Splint.Remove(p, region, src?)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Splint = NZA.Splint or {}
local SP = NZA.Splint
local U = NZA.Util

local function C(section)
    local c = Config.Splint or {}
    return c[section] or {}
end

local function L(key, ...)
    return NZA.L('splint.' .. key, ...)
end

local function itemName(key)
    return key and Config.Items and Config.Items[key] or nil
end

local function fail(err, ...)
    return { err = err, msg = L('err_' .. err, ...) }
end

local function B(path, ...)
    if NZA.Core and NZA.Core.B then return NZA.Core.B(path, ...) end
    return nil
end

local function notify(src, msg, kind)
    if NZA.Core and NZA.Core.Notify then NZA.Core.Notify(src, msg, kind or 'info', L('title')) end
end

local function statesSet(list)
    local out = {}
    for _, s in ipairs(list or {}) do out[s] = true end
    if next(out) == nil then out.alive, out.wounded = true, true end
    return out
end

local function isEasy(src, perm)
    if NZA.Staff and NZA.Staff.Easy then return NZA.Staff.Easy(src, perm) == true end
    return Config.EasyMode ~= nil and Config.EasyMode.default == true
end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local LIMB_ORDER = {
    l_upper_arm = { 'l_arm', 1 }, l_lower_arm = { 'l_arm', 2 }, r_upper_arm = { 'r_arm', 1 }, r_lower_arm = { 'r_arm', 2 },
    l_upper_leg = { 'l_leg', 1 }, l_lower_leg = { 'l_leg', 2 }, r_upper_leg = { 'r_leg', 1 }, r_lower_leg = { 'r_leg', 2 },
}

local JOINT_KEYS = {
    l_upper_arm = { 'shoulder', 'elbow', 'fingers' }, r_upper_arm = { 'shoulder', 'elbow', 'fingers' },
    l_lower_arm = { 'elbow', 'wrist', 'fingers' },    r_lower_arm = { 'elbow', 'wrist', 'fingers' },
    l_upper_leg = { 'hip', 'knee', 'toes' },           r_upper_leg = { 'hip', 'knee', 'toes' },
    l_lower_leg = { 'knee', 'ankle', 'toes' },         r_lower_leg = { 'knee', 'ankle', 'toes' },
}

local function deviceFor(region)
    local map = C('Splint').regions or {}
    local d = map[region]
    if d == 'leg' or d == 'arm' then return d end
    return nil
end

function SP.DeviceFor(region) return deviceFor(region) end

local function regionLabel(region)
    if U.RegionLabel then return U.RegionLabel(region) end
    local R = NZA.Const.Region[region]
    return R and R.label or tostring(region)
end

local function boneLabel(bone)
    if not bone then return nil end
    local key = 'core.bone_' .. tostring(bone)
    local s = NZA.L(key)
    if s == key then return tostring(bone) end
    return s
end

local function fractureKindLabel(kind)
    local key = 'core.fracture_' .. tostring(kind or 'closed')
    local s = NZA.L(key)
    if s == key then return tostring(kind or '') end
    return s
end

local function isFracture(inj)
    return type(inj) == 'table' and (inj.type == 'fracture' or type(inj.fracture) == 'table')
end

local function findInjury(p, payload)
    if type(payload) ~= 'table' then return nil end
    local id = payload.injury
    if (type(id) == 'string' or type(id) == 'number') and p.injuries then
        local inj = p.injuries[id]
        if not inj then
            for _, i in pairs(p.injuries) do
                if tostring(i.id) == tostring(id) then inj = i break end
            end
        end
        if inj then return inj end
    end
    local region = payload.region
    if type(region) == 'string' and p.injuries then
        local best
        for _, i in pairs(p.injuries) do
            if i.region == region and isFracture(i) and not ((i.treat or {}).splinted or (i.treat or {}).cast) then
                if not best or (i.severity or 0) > (best.severity or 0) then best = i end
            end
        end
        return best
    end
    return nil
end

local function splintable(p, inj)
    if not isFracture(inj) then return false, 'no_fracture' end
    if not deviceFor(inj.region) then return false, 'not_limb' end
    local t = inj.treat or {}
    if t.cast then return false, 'has_cast' end
    if t.splinted then return false, 'already' end
    if p.devices and type(p.devices.splints) == 'table' and p.devices.splints[inj.region] then return false, 'already' end
    return true
end

local function woundCovered(inj)
    local t = inj.treat or {}
    return t.dressed or t.bandaged or t.sutured or t.packed
end

-- distal pulse beyond the fracture: tourniquet above it, shock, or present
local function distalPulse(p, region)
    local me = LIMB_ORDER[region]
    local tq = p.devices and p.devices.tourniquet or {}
    if me then
        for r in pairs(tq) do
            local o = LIMB_ORDER[r]
            if o and o[1] == me[1] and o[2] <= me[2] then return 'absent', L('pulse_tq') end
        end
    end
    local v = p.vitals or {}
    if p.state == 'arrest' or (tonumber(v.hr) or 80) <= 0 then return 'absent', L('pulse_none') end
    local sys = tonumber(v.sys) or 120
    if sys < (tonumber(C('Splint').shockSys) or 85) then return 'weak', L('pulse_shock', math.floor(sys)) end
    return 'present', nil
end

local function limbRadius(device, region)
    local lr = C('Splint').limbRadius or {}
    local upper = region:find('upper') ~= nil
    if device == 'leg' then return tonumber(upper and lr.thigh or lr.leg) or (upper and 0.075 or 0.055) end
    return tonumber(upper and lr.upperArm or lr.arm) or (upper and 0.048 or 0.040)
end

local function tuneData()
    local s = C('Splint')
    return {
        tolerance = tonumber(s.tolerance) or 0.035, angleTolerance = tonumber(s.angleTolerance) or 8,
        lockHold = tonumber(s.lockHold) or 0.7, rotateSpeed = tonumber(s.rotateSpeed) or 55,
        nudgeSpeed = tonumber(s.nudgeSpeed) or 0.2, fine = tonumber(s.fine) or 0.22,
        shapePoints = s.shapePoints, shapeSeconds = tonumber(s.shapeSeconds) or 1.15,
        shapeClick = tonumber(s.shapeClick) or 0.18, shapeZone = s.shapeZone,
        strapZone = s.strapZone, strapTight = tonumber(s.strapTight) or 0.88, strapPeriod = tonumber(s.strapPeriod) or 1.7,
    }
end

local function bill(src, p, key)
    local amount = tonumber(C('Billing')[key]) or 0
    if amount <= 0 or type(p) ~= 'table' or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, L('bill_' .. key), { medic = src, kind = 'splint_' .. key })
    if not ok then NZA.Warn('splint billing failed: ' .. tostring(err)) end
end

local function pose(p, on)
    if type(p) ~= 'table' or p.kind ~= 'player' or not p.src then return end
    if C('Splint').patientPose == false then return end
    TriggerClientEvent('nza:splint:pose', p.src, on == true)
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE 'splint'
-- ════════════════════════════════════════════════════════════════════════

local function splintItems()
    local name = itemName(C('Splint').item or 'splint')
    return name and { [name] = 1 } or {}
end

if C('Splint').enabled ~= false then
    local sc = C('Splint')
    NZA.Proc.Register('splint', {
        perm = sc.perm or 'splint',
        items = function() return splintItems() end,
        maxDist = tonumber(sc.maxDist) or 3.0,
        minTime = tonumber(sc.minTime) or 14,
        maxTime = tonumber(sc.maxTime) or 480,
        easyTime = tonumber(sc.easyTime) or 8,
        consume = 'finish',
        label = L('title'),
        states = statesSet(sc.states),
        onStart = function(src, p, payload, info)
            local inj = findInjury(p, payload)
            if not inj then return false, fail('no_fracture') end
            local ok, why = splintable(p, inj)
            if not ok then return false, fail(why) end
            local f = type(inj.fracture) == 'table' and inj.fracture or {}
            local easy = info and info.easy or isEasy(src, sc.perm or 'splint')
            local isOpen = f.kind == 'open'
            if isOpen and sc.requireDressedOpen and not easy and not woundCovered(inj) then
                return false, fail('cover_first')
            end
            local device = deviceFor(inj.region)
            local dev = (sc.device or {})[device] or {}
            local jk = JOINT_KEYS[inj.region] or { 'prox', 'dist', 'toes' }
            local pulse, why2 = distalPulse(p, inj.region)
            local v = p.vitals or {}
            local avpu = v.avpu or p.avpu or 'A'
            local hr = tonumber(v.hr) or 80
            local sys = tonumber(v.sys) or 120
            local refill = pulse == 'present' and (sys < 100 and 2.4 or 1.4) or (pulse == 'weak' and 3.2 or 5.0)
            if p.kind == 'player' and p.state == 'alive' then pose(p, true) end
            return true, {
                injury = inj.id, region = inj.region, regionLabel = regionLabel(inj.region),
                device = device, limb = device, segment = inj.region:find('upper') and 'upper' or 'lower',
                deviceLabel = L('dev_' .. device), deviceModel = dev.model or (device == 'leg' and 'CS-76' or 'CS-40'),
                joints = { prox = L('joint_' .. jk[1]), dist = L('joint_' .. jk[2]), cms = L('joint_' .. jk[3]),
                           proxKey = jk[1], distKey = jk[2], cmsKey = jk[3] },
                fracture = {
                    kind = f.kind or 'closed', kindLabel = fractureKindLabel(f.kind), bone = f.bone,
                    boneLabel = boneLabel(f.bone), displaced = f.displaced == true, angle = tonumber(f.angle) or 0,
                },
                open = isOpen, dressed = woundCovered(inj) and true or false, severity = inj.severity or 2,
                pulse = pulse, pulseWhy = why2, hr = math.floor(hr), sys = math.floor(sys), refill = refill,
                responsive = (avpu == 'A' or avpu == 'V') and p.state ~= 'arrest',
                name = p.name, sex = p.sex, pain = math.floor(tonumber(inj.pain) or tonumber(p.pain) or 0),
                size = {
                    width = tonumber(dev.width) or (device == 'leg' and 0.15 or 0.105),
                    depth = tonumber(dev.depth) or (device == 'leg' and 0.07 or 0.05),
                    wall = tonumber(dev.wall) or 0.01,
                    limbRadius = limbRadius(device, inj.region),
                },
                tune = tuneData(),
            }
        end,
        onFinish = function(src, p, session, result)
            pose(p, false)
            local inj = findInjury(p, { injury = session.data and session.data.injury })
            local giveBack = function()
                local name = itemName(sc.item or 'splint')
                if name then B('Inv.AddItem', src, name, 1) end
            end
            if not inj then giveBack() return { ok = false, msg = L('err_no_fracture') } end
            local ok, why = splintable(p, inj)
            if not ok then giveBack() return { ok = false, msg = L('err_' .. why) } end

            local score = U.clamp(tonumber(result.score) or 0, 0, 100)
            if score < (tonumber(sc.minScore) or 0) then
                giveBack()
                return { ok = false, score = score, msg = L('fail_score') }
            end
            local function pct(x) return math.floor(U.clamp(tonumber(x) or score, 0, 100) + 0.5) end
            local function cnt(x, hi) return math.floor(U.clamp(tonumber(x) or 0, 0, hi or 20)) end

            local device = deviceFor(inj.region)
            NZA.Patients.SetDevice(p.pid, 'splints', { [inj.region] = device })
            local relief = (tonumber(sc.painRelief) or 12) * score / 100
            local pain = math.max(0, (tonumber(inj.pain) or 0) - relief)
            NZA.Patients.UpdateInjury(p.pid, inj.id, {
                pain = pain, treat = { splinted = true }, quality = { splinted = math.floor(score) },
            })
            bill(src, p, 'splint')
            NZA.Bus.Emit('splint:applied', src, p, inj, score)
            local msg = L('done_msg', regionLabel(inj.region))
            if result.easy ~= true and cnt(result.pressure, 9) > 0 then msg = msg .. ' · ' .. L('done_pressure', cnt(result.pressure, 9)) end
            return {
                ok = true, msg = msg, region = inj.region, device = device,
                align = pct(result.align), mould = pct(result.mould), straps = pct(result.straps),
                pressure = cnt(result.pressure, 9), checks = cnt(result.checks, 9),
                record = {
                    region = inj.region, device = device, score = math.floor(score), grade = U.Grade(score),
                    align = pct(result.align), mould = pct(result.mould), straps = pct(result.straps),
                    pressure = cnt(result.pressure, 9), cms = 'intact', easy = result.easy == true,
                },
            }
        end,
        onAbort = function(src, p)
            if p then pose(p, false) end
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- TAKING A SPLINT OFF
-- ════════════════════════════════════════════════════════════════════════

-- remove the splint of a region (fractures under it lose 'splinted' unless already healed)
function SP.Remove(p, region, src)
    p = NZA.Patients.Resolve(p)
    if not p or type(region) ~= 'string' then return false end
    if not (p.devices and type(p.devices.splints) == 'table' and p.devices.splints[region]) then return false end
    NZA.Patients.SetDevice(p.pid, 'splints', region, false)
    for _, inj in pairs(p.injuries or {}) do
        if inj.region == region and isFracture(inj) and (inj.treat or {}).splinted then
            NZA.Patients.UpdateInjury(p.pid, inj.id, { treat = { splinted = false } })
        end
    end
    NZA.Bus.Emit('splint:removed', src, p, region)
    return true
end

NZA.Treat.Register('splint_remove', {
    perm = C('Splint').removePerm or 'splint',
    maxDist = tonumber(C('Splint').maxDist) or 3.0,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    cooldown = 800,
    handler = function(src, p, payload)
        local region = type(payload) == 'table' and payload.region or nil
        if type(region) ~= 'string' or not deviceFor(region) then return false, fail('no_splint') end
        if not SP.Remove(p, region, src) then return false, fail('no_splint') end
        if C('Splint').removeReturns then
            local name = itemName(C('Splint').item or 'splint')
            if name then B('Inv.AddItem', src, name, 1) end
        end
        return true, { msg = L('removed', regionLabel(region)) }
    end,
})

-- the splint comes off by itself when no fracture is left under it
local function checkHealed(p, region)
    if C('Splint').autoRemoveHealed == false or type(p) ~= 'table' then return end
    if not (p.devices and type(p.devices.splints) == 'table' and p.devices.splints[region]) then return end
    for _, inj in pairs(p.injuries or {}) do
        if inj.region == region and isFracture(inj) then return end
    end
    NZA.Patients.SetDevice(p.pid, 'splints', region, false)
    if p.kind == 'player' and p.src then notify(p.src, L('healed_off', regionLabel(region)), 'success') end
end

NZA.Bus.On('injury:removed', function(p)
    if type(p) ~= 'table' or not p.devices or type(p.devices.splints) ~= 'table' then return end
    local regions = {}
    for region in pairs(p.devices.splints) do regions[#regions + 1] = region end
    for _, region in ipairs(regions) do checkHealed(p, region) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- CRUTCHES
-- ════════════════════════════════════════════════════════════════════════

local crutchUsers = {}   -- src → true

local function crutchItem()
    return itemName(C('Crutches').item or 'crutches')
end

local function hasItem(src, name)
    if not name then return false end
    local n = tonumber(B('Inv.Count', src, name)) or 0
    if n > 0 then return true end
    return B('Inv.HasItem', src, name, 1) == true
end

function SP.HasCrutches(src)
    return crutchUsers[tonumber(src) or -1] == true
end

function SP.SetCrutches(src, on, silent)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    on = on == true
    if on then crutchUsers[src] = true else crutchUsers[src] = nil end
    local ply = Player(src)
    if ply and ply.state then ply.state:set('nzaCrutch', on or nil, true) end
    TriggerClientEvent('nza:splint:crutch', src, on, silent == true)
    return true
end

local function canUseCrutches(src)
    local p = NZA.Patients.GetBySource(src)
    if p and p.state ~= 'alive' then return false, 'down' end
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0 then return false, 'in_vehicle' end
    return true
end

local function toggleCrutches(src)
    if C('Crutches').enabled == false then return { ok = false, err = 'disabled', msg = L('err_disabled') } end
    if not NZA.Core.Rate('splint:crutch', src, 4, 3000) then return { ok = false, err = 'rate' } end
    if SP.HasCrutches(src) then
        SP.SetCrutches(src, false)
        return { ok = true, on = false }
    end
    if not hasItem(src, crutchItem()) then return { ok = false, err = 'no_crutches', msg = L('err_no_crutches') } end
    local ok, why = canUseCrutches(src)
    if not ok then return { ok = false, err = why, msg = L('err_' .. why) } end
    SP.SetCrutches(src, true)
    return { ok = true, on = true }
end

lib.callback.register('nza:splint:crutch:toggle', function(src)
    return toggleCrutches(src)
end)

NZA.Treat.Register('crutches_give', {
    perm = C('Crutches').givePerm or 'splint',
    npc = false, player = true,
    maxDist = tonumber(C('Interact').distance) or 2.2,
    states = { alive = true, wounded = true },
    cooldown = 1500,
    items = function()
        local name = crutchItem()
        return name and { [name] = 1 } or {}
    end,
    handler = function(src, p)
        if C('Crutches').enabled == false or C('Crutches').give == false then return false, fail('disabled') end
        local name = crutchItem()
        if not name or not p.src then return false, fail('no_crutches') end
        if B('Inv.CanCarry', p.src, name, 1) == false then return false, fail('cant_carry') end
        if not B('Inv.AddItem', p.src, name, 1) then return false, fail('cant_carry') end
        notify(p.src, L('crutches_received'), 'success')
        if C('Crutches').autoEquip ~= false and p.state == 'alive' then
            local ok = canUseCrutches(p.src)
            if ok then SP.SetCrutches(p.src, true) end
        end
        bill(src, p, 'crutches')
        return true, { msg = L('crutches_given', p.name or '') }
    end,
})

-- crutches drop when the player goes down
NZA.Bus.On('state:changed', function(p, _, new)
    if type(p) ~= 'table' or p.kind ~= 'player' or not p.src then return end
    if new ~= 'alive' and SP.HasCrutches(p.src) then SP.SetCrutches(p.src, false, true) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    crutchUsers[src] = nil
end)

-- still carrying the crutches?
CreateThread(function()
    while true do
        Wait(math.max(5, tonumber(C('Crutches').checkEvery) or 15) * 1000)
        local name = crutchItem()
        for src in pairs(crutchUsers) do
            if GetPlayerName(src) == nil then
                crutchUsers[src] = nil
            elseif not hasItem(src, name) then
                SP.SetCrutches(src, false)
                notify(src, L('crutches_gone'), 'warning')
            end
        end
    end
end)

-- usable item
CreateThread(function()
    local name = crutchItem()
    if not name or C('Crutches').enabled == false then return end
    local deadline = GetGameTimer() + 30000
    while not (Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function') and GetGameTimer() < deadline do Wait(500) end
    if Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function' then
        local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src)
            local r = toggleCrutches(src)
            if r and r.ok == false and r.msg then notify(src, r.msg, 'error') end
        end)
        if not ok then NZA.Warn('splint: could not register the crutches item: ' .. tostring(err)) end
    else
        NZA.Warn('splint: Bridge.Inv.RegisterUsable is missing - crutches cannot be used from the inventory')
    end
end)

-- patient pose / crutches end with the resource
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(crutchUsers) do
        local ply = Player(src)
        if ply and ply.state then ply.state:set('nzaCrutch', nil, true) end
    end
end)
