-----------------------------------------------------------------
-- Bags in vehicles
--
-- Get in a car and your bag goes on a free seat instead of vanishing.
-- Every client works out the same seats from the same facts (who's in
-- the car, which seats are taken or being climbed into), so everyone
-- sees the bag in the same place without any extra network traffic.
--
-- A passenger getting in always wins: a seat someone is climbing into
-- counts as taken, so the bag moves out of the way before they sit.
--
-- Orientation: every bag model has its own pivot and axes. We measure
-- how the bag sits on its wearer (which the bag's fit already gets
-- right), stand that upright, and put it on the seat the same way, so
-- it leans against the seat back the way it leaned against your back.
-----------------------------------------------------------------

VehicleBags = {}

local cfg = Config.Vehicle or {}
VehicleBags.enabled = cfg.enabled == true

local SEAT_BONES = {
    [-1] = 'seat_dside_f', [0] = 'seat_pside_f',
    [1] = 'seat_dside_r', [2] = 'seat_pside_r',
    [3] = 'seat_dside_r1', [4] = 'seat_pside_r1',
    [5] = 'seat_dside_r2', [6] = 'seat_pside_r2',
}

local WORN = {}
for _, c in ipairs(cfg.wornClasses or { 8, 13 }) do WORN[c] = true end

-----------------------------------------------------------------
-- frames (true local axes, no guessing GetEntityMatrix's order)
-----------------------------------------------------------------

local function frame(entity)
    local p = GetEntityCoords(entity)
    local x = GetOffsetFromEntityInWorldCoords(entity, 1.0, 0.0, 0.0) - p
    local y = GetOffsetFromEntityInWorldCoords(entity, 0.0, 1.0, 0.0) - p
    local z = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, 1.0) - p
    return M3.fromAxes(x, y, z), p
end

local function rel(parent, child)
    local P = frame(parent)
    local C = frame(child)
    return M3.mul(M3.t(P), C)
end

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function col(m, i) return vector3(m[i], m[3 + i], m[6 + i]) end

--- Rotate so the bag's most vertical axis is exactly vertical (removes
--- the lean of a walking or seated wearer).
local function upright(R)
    local best, bi = -1, 1
    for i = 1, 3 do
        local z = math.abs(col(R, i).z)
        if z > best then best, bi = z, i end
    end
    local a = col(R, bi)
    local target = vector3(0.0, 0.0, a.z >= 0 and 1.0 or -1.0)
    local axis = cross(a, target)
    local len = #axis
    if len < 1e-5 then return R end
    local deg = math.deg(math.acos(math.max(-1.0, math.min(1.0, Util.dot(a, target)))))
    return M3.mul(M3.axis(axis / len, deg), R)
end

-----------------------------------------------------------------
-- euler convention of AttachEntityToEntity (measured once)
-----------------------------------------------------------------

local AXFN = { x = M3.rx, y = M3.ry, z = M3.rz }
local PERMS = {
    { 'x', 'y', 'z' }, { 'x', 'z', 'y' }, { 'y', 'x', 'z' },
    { 'y', 'z', 'x' }, { 'z', 'x', 'y' }, { 'z', 'y', 'x' },
}
local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local conv = nil -- { order, sign, L, R }

local function eulerM(rot, c)
    local o, s = c.order, c.sign
    local m = AXFN[o[1]](rot[o[1]] * s[o[1]])
    m = M3.mul(m, AXFN[o[2]](rot[o[2]] * s[o[2]]))
    return M3.mul(m, AXFN[o[3]](rot[o[3]] * s[o[3]]))
end

local function fullM(rot, c)
    return M3.mul(M3.mul(c.L or I3, eulerM(rot, c)), c.R or I3)
end

local function solve3(A, b)
    local det = A[1] * (A[5] * A[9] - A[6] * A[8]) - A[2] * (A[4] * A[9] - A[6] * A[7]) + A[3] * (A[4] * A[8] - A[5] * A[7])
    if math.abs(det) < 1e-18 then return nil end
    local function d(c1, c2, c3)
        return c1[1] * (c2[2] * c3[3] - c3[2] * c2[3]) - c2[1] * (c1[2] * c3[3] - c3[2] * c1[3]) + c3[1] * (c1[2] * c2[3] - c2[2] * c1[3])
    end
    local c1, c2, c3 = { A[1], A[4], A[7] }, { A[2], A[5], A[8] }, { A[3], A[6], A[9] }
    return d(b, c2, c3) / det, d(c1, b, c3) / det, d(c1, c2, b) / det
end

--- Euler angles that make the attach produce matrix T.
local function solveEuler(T)
    local KEYS = { 'x', 'y', 'z' }
    local seeds = {
        { x = 0, y = 0, z = 0 }, { x = 90, y = 0, z = 0 }, { x = -90, y = 0, z = 0 },
        { x = 0, y = 90, z = 0 }, { x = 0, y = -90, z = 0 }, { x = 0, y = 0, z = 90 },
        { x = 0, y = 0, z = -90 }, { x = 180, y = 0, z = 0 }, { x = 0, y = 0, z = 180 },
    }
    local best, bestErr = nil, math.huge
    for _, s0 in ipairs(seeds) do
        local th = { x = s0.x, y = s0.y, z = s0.z }
        local cost = M3.err(fullM(th, conv), T)
        local lambda = 1e-3
        for _ = 1, 60 do
            if cost < 1e-12 then break end
            local E = fullM(th, conv)
            local J = {}
            for k, key in ipairs(KEYS) do
                local t2 = { x = th.x, y = th.y, z = th.z }
                t2[key] = t2[key] + 0.05
                local Ek = fullM(t2, conv)
                J[k] = {}
                for i = 1, 9 do J[k][i] = (Ek[i] - E[i]) / 0.05 end
            end
            local JTJ, JTr = {}, {}
            for a = 1, 3 do
                local acc = 0.0
                for i = 1, 9 do acc = acc + J[a][i] * (E[i] - T[i]) end
                JTr[a] = -acc
                for b = 1, 3 do
                    local v = 0.0
                    for i = 1, 9 do v = v + J[a][i] * J[b][i] end
                    JTJ[(a - 1) * 3 + b] = v
                end
            end
            for a = 1, 3 do JTJ[(a - 1) * 3 + a] = JTJ[(a - 1) * 3 + a] * (1 + lambda) + 1e-12 end
            local dx, dy, dz = solve3(JTJ, JTr)
            if not dx then break end
            local cand = { x = th.x + dx, y = th.y + dy, z = th.z + dz }
            local c2 = M3.err(fullM(cand, conv), T)
            if c2 < cost then th, cost, lambda = cand, c2, lambda * 0.3 else lambda = lambda * 10 end
            if lambda > 1e8 then break end
        end
        if cost < bestErr then best, bestErr = th, cost end
        if bestErr < 1e-10 then break end
    end
    if not best or bestErr > 0.01 then return nil end
    return { x = Util.wrap180(best.x), y = Util.wrap180(best.y), z = Util.wrap180(best.z) }
end

--- Attach `entity` to `veh` with probe rotations and work out how the
--- game turns attach angles into a rotation. Two frames per probe,
--- with the prop invisible.
local function calibrate(entity, veh, bone)
    local probes = {
        { x = 17, y = 41, z = 73 },
        { x = -63, y = 22, z = 128 },
        { x = 0, y = 0, z = 0 },
    }
    SetEntityAlpha(entity, 0, false)
    local mats = {}
    for i, r in ipairs(probes) do
        AttachEntityToEntity(entity, veh, bone, 0.0, 0.0, 0.0, r.x, r.y, r.z, false, false, false, false, 2, true)
        Wait(0); Wait(0)
        if not DoesEntityExist(entity) or not DoesEntityExist(veh) then return false end
        mats[i] = rel(veh, entity)
    end
    ResetEntityAlpha(entity)

    local zero = mats[3]
    local wraps = { { L = nil, R = nil }, { L = zero, R = nil }, { L = nil, R = zero } }
    local best, bestErr = nil, math.huge
    for _, w in ipairs(wraps) do
        for _, order in ipairs(PERMS) do
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
                local c = { order = order, sign = { x = sx, y = sy, z = sz }, L = w.L, R = w.R }
                local e = 0.0
                for i = 1, 2 do e = e + M3.err(fullM(probes[i], c), mats[i]) end
                if e < bestErr then best, bestErr = c, e end
            end end end
        end
    end
    if bestErr > 0.02 then
        print(('^3[nayzeee-backpack] vehicle seats: could not read the attach rotation (%.4f), bags stay hidden in cars^0'):format(bestErr))
        return false
    end
    conv = best
    return true
end

-----------------------------------------------------------------
-- measuring how a bag sits on its wearer
-----------------------------------------------------------------

local measured = {} -- [bag|variant] = upright rotation of the bag in its wearer's frame

function VehicleBags.measure(key, entity, ped)
    if not VehicleBags.enabled or measured[key] then return end
    if not DoesEntityExist(entity) or not DoesEntityExist(ped) then return end
    measured[key] = upright(rel(ped, entity))
end

function VehicleBags.hasMeasure(key) return measured[key] ~= nil end

-----------------------------------------------------------------
-- seat assignment
-----------------------------------------------------------------

local function seatTaken(veh, seat)
    if not IsVehicleSeatFree(veh, seat) then return true end
    -- someone climbing in right now
    for _, ply in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(ply)
        if GetVehiclePedIsEntering(ped) == veh and GetSeatPedIsTryingToEnter(ped) == seat then return true end
    end
    return false
end

local function seatOf(veh, ped)
    for s = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        if GetPedInVehicleSeat(veh, s) == ped then return s end
    end
    return 99
end

--- holders: { { id = serverId, ped = ped }, ... } wearing bags in `veh`.
--- Returns [serverId] = seat index, or nil (no room: hidden).
function VehicleBags.assign(veh, holders)
    table.sort(holders, function(a, b)
        local sa, sb = seatOf(veh, a.ped), seatOf(veh, b.ped)
        if sa ~= sb then return sa < sb end
        return a.id < b.id
    end)

    local free = {}
    local max = GetVehicleMaxNumberOfPassengers(veh)
    for _, s in ipairs(cfg.seats or { 0, 2, 1, 4, 3 }) do
        local bone = SEAT_BONES[s]
        if s < max and bone and GetEntityBoneIndexByName(veh, bone) ~= -1 and not seatTaken(veh, s) then
            free[#free + 1] = s
        end
    end

    local out = {}
    for i, h in ipairs(holders) do out[h.id] = free[i] end
    return out
end

--- What should happen to a bag whose wearer is in `veh`?
---@return 'worn'|'seat'|'hidden'
function VehicleBags.modeFor(veh)
    if not VehicleBags.enabled then return Config.ShowInVehicle and 'worn' or 'hidden' end
    if WORN[GetVehicleClass(veh)] then return 'worn' end
    return 'seat'
end

-----------------------------------------------------------------
-- putting a bag on a seat
-----------------------------------------------------------------

local function vehicleBone(veh)
    local b = GetEntityBoneIndexByName(veh, 'chassis')
    return b ~= -1 and b or 0
end

--- Attach `entity` (model `hash`) to `seat` of `veh`. Yields a few frames.
--- Returns true when it's on the seat.
function VehicleBags.place(entity, hash, key, veh, seat)
    local R = measured[key]
    if not R or not DoesEntityExist(veh) then return false end
    local seatBone = GetEntityBoneIndexByName(veh, SEAT_BONES[seat] or '')
    if seatBone == -1 then return false end

    local bone = vehicleBone(veh)
    if not conv and not calibrate(entity, veh, bone) then return false end

    local rot = solveEuler(R)
    if not rot then return false end

    -- where the bag's origin goes so its mesh sits on the cushion
    local mn, mx = GetModelDimensions(hash)
    local c = (mn + mx) * 0.5
    local minZ = math.huge
    for _, x in ipairs({ mn.x, mx.x }) do
        for _, y in ipairs({ mn.y, mx.y }) do
            for _, z in ipairs({ mn.z, mx.z }) do
                local v = M3.apply(R, vector3(x, y, z))
                if v.z < minZ then minZ = v.z end
            end
        end
    end
    local cR = M3.apply(R, c)
    local seatAt = GetOffsetFromEntityGivenWorldCoords(veh, GetWorldPositionOfEntityBone(veh, seatBone))
    local want = vector3(
        seatAt.x - cR.x,
        seatAt.y + (cfg.back or -0.10) - cR.y,
        seatAt.z + (cfg.lift or 0.02) - minZ)

    -- attach, then nudge until the origin is exactly where we want it
    -- (covers vehicles whose root bone isn't at the model origin)
    local off = want
    SetEntityAlpha(entity, 0, false)
    for _ = 1, 3 do
        AttachEntityToEntity(entity, veh, bone, off.x, off.y, off.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
        Wait(0)
        if not DoesEntityExist(entity) or not DoesEntityExist(veh) then return false end
        local now = GetOffsetFromEntityGivenWorldCoords(veh, GetEntityCoords(entity))
        local err = want - now
        if #err < 0.01 then break end
        off = off + err
    end
    ResetEntityAlpha(entity)
    SetEntityVisible(entity, true, false)
    return true
end
