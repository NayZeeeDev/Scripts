--[[
    NAYZEEE AMBULANCE - Wounded (server): respawn at a hospital

    Flow
      1. client  'nza:respawn' ()                     held E on the death screen
      2. server  validates (dead, Config.Death.respawnTimer passed, rate limit, no respawn
                 pending), picks the spot: NZA.Hospitals.RespawnPoint(coords) when the
                 hospital module has one built, else the nearest Config.Respawn.points entry.
                 Reserves a free bed (NZA.Hospitals.FreeBed + OccupyBed, or a fallback bed)
                 when Config.Respawn.useBed.
      3. server  'nza:wounded:respawn' { token, coords, bed, label, fadeMs, bedTime } → client
                 fades out, teleports, waits for collision
      4. client  'nza:wounded:arrived' (token)        → server checks the token and the
                 server-side position (moves the ped itself when the client did not), then
                 NZA.Patients.Revive(pid, { full = Config.Death.clearInjuries }), takes items /
                 cash per Config.Death, charges Config.Death.respawnFee (NZA.Billing.Charge
                 when installed - it applies insurance - else Bridge.RemoveMoney with
                 NZA.Insurance cover) and releases the bed after Config.Respawn.bedTime.
         No ack within Config.Respawn.ackTimeout → the server finishes on its own.

    Net events: nza:respawn (C→S), nza:wounded:arrived (C→S), nza:wounded:respawn (S→C)
    Server API: NZA.Wounded.RespawnPoint(src, p) → { coords = vector4, label, hospital, point, beds }
                NZA.Wounded.RespawnPreview(src, p) → { hospital, fee, cover, plan, pay, loseItems, loseCash, heal }
                NZA.Wounded.ForceRespawn(src, { coords = vec4?, label?, fee = false?, bed = false? }) → bool
                    same flow without the timer (morgue processing, admin tools)
    Bus events emitted (server): wounded:respawned (src, p, spot)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Wounded = NZA.Wounded or {}
local W = NZA.Wounded

local pending = {}     -- src → { token, pid, spot, bed, at }
local usedBeds = {}    -- fallback bed key → src

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section, key, default)
    local s = Config[section]
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end

local function bridge(path, ...)
    if NZA.Core and NZA.Core.B then return NZA.Core.B(path, ...) end
    local node = Bridge
    for part in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    if type(node) ~= 'function' then return nil end
    local ok, res = pcall(node, ...)
    if ok then return res end
    return nil
end

local function notify(src, kind, key, ...)
    local msg = NZA.L(key, ...)
    if NZA.Core and NZA.Core.Notify then
        NZA.Core.Notify(src, msg, kind, NZA.L('wounded.title_toast'), 6500)
    else
        TriggerClientEvent('nza:ui:toast', src, { title = NZA.L('wounded.title_toast'), message = msg, type = kind, duration = 6500 })
    end
end

local function srcCoords(src)
    if NZA.Core and NZA.Core.SrcCoords then return NZA.Core.SrcCoords(src) end
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then return GetEntityCoords(ped) end
    return nil
end

local function rate(src, bucket, n, ms)
    if NZA.Core and NZA.Core.Rate then return NZA.Core.Rate('wounded:' .. bucket, src, n, ms) end
    return true
end

-- anything coordinate-like → vector4
local function v4(v)
    local t = type(v)
    if t == 'vector4' then return v end
    if t == 'vector3' then return vector4(v.x, v.y, v.z, 0.0) end
    if t == 'table' then
        local x = tonumber(v.x or v[1])
        local y = tonumber(v.y or v[2])
        local z = tonumber(v.z or v[3])
        if not (x and y and z) then return nil end
        local w = tonumber(v.w or v.h or v.heading or v[4]) or 0.0
        return vector4(x + 0.0, y + 0.0, z + 0.0, w + 0.0)
    end
    return nil
end

local function plain(c)
    if not c then return nil end
    return { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 }
end

local function identifierOf(src, p)
    if p and p.identifier then return p.identifier end
    if NZA.Core and NZA.Core.Identifier then return NZA.Core.Identifier(src) end
    return bridge('GetIdentifier', src)
end

-- ════════════════════════════════════════════════════════════════════════
-- WHERE
-- ════════════════════════════════════════════════════════════════════════

local function hospitalLabel(id)
    if not id or not (NZA.Hospitals and NZA.Hospitals.Get) then return nil end
    local ok, h = pcall(NZA.Hospitals.Get, id)
    if ok and type(h) == 'table' then return h.label or h.name end
    return nil
end

function W.RespawnPoint(src, p)
    local at = srcCoords(src)
    if not at and p and NZA.Patients.Coords then at = NZA.Patients.Coords(p) end
    at = at or vector3(0.0, 0.0, 0.0)

    if NZA.Hospitals and NZA.Hospitals.RespawnPoint then
        local ok, pt = pcall(NZA.Hospitals.RespawnPoint, at)
        if ok and pt then
            local c = v4(type(pt) == 'table' and pt.coords or pt)
            if not c and type(pt) == 'table' then c = v4(pt) end
            if c then
                local hid = type(pt) == 'table' and pt.hospital or nil
                return {
                    coords = c,
                    label = hospitalLabel(hid) or (type(pt) == 'table' and pt.label) or nil,
                    hospital = hid,
                    point = type(pt) == 'table' and pt.id or nil,
                }
            end
        end
    end

    local list = cfg('Respawn', 'points', {}) or {}
    local best, bestD, bestI = nil, math.huge, nil
    for i, spot in ipairs(list) do
        local c = v4(spot.coords)
        if c then
            local d = #(vector3(c.x, c.y, c.z) - at)
            if d < bestD then best, bestD, bestI = spot, d, i end
        end
    end
    if best then
        return { coords = v4(best.coords), label = best.label, beds = best.beds, index = bestI }
    end
    return nil
end

function W.RespawnPreview(src, p)
    local fee = math.max(0, math.floor(tonumber(cfg('Death', 'respawnFee', 0)) or 0))
    local cover, plan = 0, nil
    if fee > 0 and NZA.Insurance and NZA.Insurance.Get then
        local id = identifierOf(src, p)
        local ok, ins = pcall(NZA.Insurance.Get, id)
        if ok and type(ins) == 'table' then
            local expired = type(ins.expires) == 'number' and ins.expires > 0 and ins.expires < os.time()
            if not expired then
                cover = math.max(0, math.min(1, tonumber(ins.cover) or 0))
                plan = ins.plan or ins.label
            end
        end
    end
    local spot = W.RespawnPoint(src, p)
    return {
        hospital = (spot and spot.label) or NZA.L('wounded.death_hospital'),
        fee = fee,
        cover = cover,
        plan = plan,
        pay = math.floor(fee * (1 - cover) + 0.5),
        loseItems = cfg('Death', 'loseItems', false) and true or false,
        loseCash = cfg('Death', 'loseCash', false) and true or false,
        heal = cfg('Death', 'clearInjuries', true) ~= false,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- BEDS
-- ════════════════════════════════════════════════════════════════════════

local function reserveBed(spot, p, src)
    if not cfg('Respawn', 'useBed', true) or not spot then return nil end
    if spot.hospital and NZA.Hospitals and NZA.Hospitals.FreeBed then
        local ok, bed = pcall(NZA.Hospitals.FreeBed, spot.hospital)
        if ok and type(bed) == 'table' then
            local c = v4(bed.coords)
            if c then
                if bed.id and NZA.Hospitals.OccupyBed then pcall(NZA.Hospitals.OccupyBed, bed.id, p.pid) end
                return { point = bed.id, coords = c }
            end
        end
    end
    if type(spot.beds) == 'table' and #spot.beds > 0 then
        local free = {}
        for i, b in ipairs(spot.beds) do
            local key = tostring(spot.index or 0) .. ':' .. i
            if not usedBeds[key] and v4(b) then free[#free + 1] = { key = key, coords = v4(b) } end
        end
        if #free > 0 then
            local pick = free[math.random(#free)]
            usedBeds[pick.key] = src
            return { key = pick.key, coords = pick.coords }
        end
    end
    return nil
end

local function releaseBed(bed)
    if not bed then return end
    if bed.point and NZA.Hospitals and NZA.Hospitals.ReleaseBed then
        pcall(NZA.Hospitals.ReleaseBed, bed.point)
    end
    if bed.key then usedBeds[bed.key] = nil end
end

-- ════════════════════════════════════════════════════════════════════════
-- PAYMENT & LOSSES
-- ════════════════════════════════════════════════════════════════════════

local function charge(src, p)
    local preview = W.RespawnPreview(src, p)
    local fee = preview.fee
    if fee <= 0 then return end
    local reason = NZA.L('wounded.respawn_reason')

    if NZA.Billing and NZA.Billing.Charge then
        local ok, res = pcall(NZA.Billing.Charge, src, fee, reason, { kind = 'respawn', pid = p.pid })
        if ok and res ~= false then return end
    end

    local pay = preview.pay
    if pay <= 0 then
        notify(src, 'info', 'wounded.respawn_bill_ins', 0, fee)
        return
    end
    local acc = cfg('Billing', 'account', 'bank') or 'bank'
    local paid = bridge('RemoveMoney', src, acc, pay, reason)
    if not paid then
        paid = bridge('RemoveMoney', src, acc == 'bank' and 'cash' or 'bank', pay, reason)
    end
    if paid then
        local society = cfg('Billing', 'society', nil)
        if society then bridge('Society.Add', society, pay) end
        if pay < fee then
            notify(src, 'info', 'wounded.respawn_bill_ins', pay, fee - pay)
        else
            notify(src, 'info', 'wounded.respawn_bill', pay)
        end
    else
        notify(src, 'warning', 'wounded.respawn_unpaid', pay)
    end
end

local function losses(src)
    if cfg('Death', 'loseItems', false) then
        local keep = cfg('Death', 'keepItems', {}) or {}
        bridge('Inv.Clear', src, keep)
        notify(src, 'warning', 'wounded.respawn_items')
    end
    if cfg('Death', 'loseCash', false) then
        local cash = math.floor(tonumber(bridge('GetMoney', src, 'cash')) or 0)
        if cash > 0 and bridge('RemoveMoney', src, 'cash', cash, NZA.L('wounded.respawn_reason')) then
            notify(src, 'warning', 'wounded.respawn_cash', cash)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- RESPAWN
-- ════════════════════════════════════════════════════════════════════════

local function finish(src, forced)
    local pd = pending[src]
    if not pd then return end
    pending[src] = nil

    local p = NZA.Patients.Get(pd.pid)
    if not p or p.state ~= 'dead' or p.src ~= src then
        releaseBed(pd.bed)
        return
    end

    local target = (pd.bed and pd.bed.coords) or pd.spot.coords
    local here = srcCoords(src)
    if forced or not here or #(here - vector3(target.x, target.y, target.z)) > 30.0 then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            SetEntityCoords(ped, target.x, target.y, target.z, false, false, false, false)
            SetEntityHeading(ped, target.w or 0.0)
        end
    end

    NZA.Patients.Revive(p.pid, { full = cfg('Death', 'clearInjuries', true) ~= false, reason = 'respawn' })
    losses(src)
    if pd.fee ~= false then charge(src, p) end
    notify(src, 'success', 'wounded.respawn_done', pd.spot.label or NZA.L('wounded.death_hospital'))

    if pd.bed then
        local bedTime = tonumber(cfg('Respawn', 'bedTime', 8)) or 8
        local bed = pd.bed
        SetTimeout(math.floor((bedTime + 10) * 1000), function() releaseBed(bed) end)
    end
    NZA.Bus.Emit('wounded:respawned', src, p, pd.spot)
end

-- opts (other modules): { coords = vec4, label = string, fee = false, bed = false }
local function startRespawn(src, p, opts)
    opts = type(opts) == 'table' and opts or {}
    local spot
    if opts.coords and v4(opts.coords) then
        spot = { coords = v4(opts.coords), label = opts.label }
    else
        spot = W.RespawnPoint(src, p)
    end
    if not spot then
        NZA.Warn('wounded: no respawn point (build one in game or fill Config.Respawn.points)')
        return false
    end
    local bed = nil
    if opts.bed ~= false then bed = reserveBed(spot, p, src) end
    local token = NZA.Util.uid('rs')
    pending[src] = { token = token, pid = p.pid, spot = spot, bed = bed, at = os.time(), fee = opts.fee ~= false }

    TriggerClientEvent('nza:wounded:respawn', src, {
        token = token,
        coords = plain(spot.coords),
        bed = bed and plain(bed.coords) or nil,
        label = spot.label,
        fadeMs = tonumber(cfg('Respawn', 'fadeMs', 900)) or 900,
        bedTime = tonumber(cfg('Respawn', 'bedTime', 8)) or 8,
    })

    local timeout = (tonumber(cfg('Respawn', 'ackTimeout', 20)) or 20) * 1000
    SetTimeout(math.floor(timeout), function()
        local pd = pending[src]
        if pd and pd.token == token then finish(src, true) end
    end)
    return true
end

RegisterNetEvent('nza:respawn', function()
    local src = source
    if not tonumber(src) or src <= 0 then return end
    if not rate(src, 'respawn', 2, 5000) then return end
    if pending[src] then return end
    local p = NZA.Patients.GetBySource(src)
    if not p or p.state ~= 'dead' then return end

    local now = os.time()
    local deadFor = now - (tonumber(p.deadAt) or now)
    local timer = tonumber(cfg('Death', 'respawnTimer', 300)) or 300
    if deadFor < timer - 2 then
        notify(src, 'error', 'wounded.respawn_wait', NZA.Util.formatTime(timer - deadFor))
        return
    end
    startRespawn(src, p)
end)

-- Server API: respawn a dead player now (morgue processing, admin tools...). Skips the timer.
function W.ForceRespawn(src, opts)
    src = tonumber(src)
    if not src or pending[src] then return false end
    local p = NZA.Patients.GetBySource(src)
    if not p or p.state ~= 'dead' then return false end
    return startRespawn(src, p, opts)
end

RegisterNetEvent('nza:wounded:arrived', function(token)
    local src = source
    local pd = pending[src]
    if not pd or type(token) ~= 'string' or pd.token ~= token then return end
    finish(src, false)
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

local function drop(src)
    local pd = pending[src]
    if pd then
        pending[src] = nil
        releaseBed(pd.bed)
    end
    for key, owner in pairs(usedBeds) do
        if owner == src then usedBeds[key] = nil end
    end
end

AddEventHandler('playerDropped', function()
    drop(source)
end)

NZA.Bus.On('player:unloaded', function(src)
    if src then drop(src) end
end)
