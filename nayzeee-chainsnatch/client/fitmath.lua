-----------------------------------------------------------------
-- Fit maths, shared by the studio and the automatic fit
--
-- GTA's attach rotations don't use the same euler order on every
-- build, so we PROBE it once: two invisible golf balls are stuck to
-- the player with known offsets and we read back where they ended up.
-- With the convention known, any wanted orientation can be turned
-- into attach angles (solveEuler).
-----------------------------------------------------------------

FitMath = { conv = nil }   -- nil = not probed yet, false = probe failed (measured mode, tried again after a minute)
local failedAt = 0

local AXFN = { x = M3.rx, y = M3.ry, z = M3.rz }
local PERMS = {
    { 'x', 'y', 'z' }, { 'x', 'z', 'y' }, { 'y', 'x', 'z' },
    { 'y', 'z', 'x' }, { 'z', 'x', 'y' }, { 'z', 'y', 'x' },
}
local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
FitMath.I3 = I3

function FitMath.eulerM(rot, conv)
    local o, s = conv.order, conv.sign
    local m = AXFN[o[1]](rot[o[1]] * s[o[1]])
    m = M3.mul(m, AXFN[o[2]](rot[o[2]] * s[o[2]]))
    return M3.mul(m, AXFN[o[3]](rot[o[3]] * s[o[3]]))
end

function FitMath.attachM(rot, conv)
    return M3.mul(M3.mul(conv.L or I3, FitMath.eulerM(rot, conv)), conv.R or I3)
end

local function solve3(A, b)
    local det = A[1] * (A[5] * A[9] - A[6] * A[8]) - A[2] * (A[4] * A[9] - A[6] * A[7]) + A[3] * (A[4] * A[8] - A[5] * A[7])
    if math.abs(det) < 1e-18 then return nil end
    local function d(c1, c2, c3)
        return c1[1] * (c2[2] * c3[3] - c3[2] * c2[3]) - c2[1] * (c1[2] * c3[3] - c3[2] * c1[3]) + c3[1] * (c1[2] * c2[3] - c2[2] * c1[3])
    end
    local col1, col2, col3 = { A[1], A[4], A[7] }, { A[2], A[5], A[8] }, { A[3], A[6], A[9] }
    return d(b, col2, col3) / det, d(col1, b, col3) / det, d(col1, col2, b) / det
end

--- Euler angles (degrees) that give matrix T under convention `conv`.
function FitMath.solveEuler(T, seed, conv)
    T = M3.mul(M3.mul(M3.t(conv.L or I3), T), M3.t(conv.R or I3))
    local KEYS = { 'x', 'y', 'z' }
    local seeds = {
        seed or { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 90, y = 0, z = 0 }, { x = -90, y = 0, z = 0 },
        { x = 0, y = 90, z = 0 }, { x = 0, y = -90, z = 0 }, { x = 0, y = 0, z = 90 },
        { x = 0, y = 0, z = -90 }, { x = 180, y = 0, z = 0 }, { x = 0, y = 0, z = 180 },
    }
    local eulerM = FitMath.eulerM
    local best, bestErr = nil, math.huge
    for _, s0 in ipairs(seeds) do
        local th = { x = s0.x, y = s0.y, z = s0.z }
        local cost = M3.err(eulerM(th, conv), T)
        local lambda = 1e-3
        for _ = 1, 60 do
            if cost < 1e-12 then break end
            local E = eulerM(th, conv)
            local J = {}
            for k, key in ipairs(KEYS) do
                local t2 = { x = th.x, y = th.y, z = th.z }
                t2[key] = t2[key] + 0.05
                local Ek = eulerM(t2, conv)
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
            local c2 = M3.err(eulerM(cand, conv), T)
            if c2 < cost then th, cost, lambda = cand, c2, lambda * 0.3 else lambda = lambda * 10 end
            if lambda > 1e8 then break end
        end
        if cost < bestErr then best, bestErr = th, cost end
        if bestErr < 1e-10 then break end
    end
    if not best then return nil end
    return { x = Util.wrap180(best.x), y = Util.wrap180(best.y), z = Util.wrap180(best.z) }, bestErr
end

--- An entity's axes as right, forward, up, pos (GetEntityMatrix returns forward, right, up, pos)
function FitMath.axes(entity, conv)
    local a, b, u, p = GetEntityMatrix(entity)
    if conv and conv.swap then return a, b, u, p end
    return b, a, u, p
end

-----------------------------------------------------------------
-- the probe
-----------------------------------------------------------------

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end
local function sane(v) -- a real unit axis, not a matrix read before the game moved the entity
    if not v or not finite(v.x) or not finite(v.y) or not finite(v.z) then return false end
    local l = #v
    return l > 0.9 and l < 1.1
end
local function saneP(v) return v and finite(v.x) and finite(v.y) and finite(v.z) and #v < 100000.0 end

local function ball(at)
    local hash = Util.loadModel(`prop_golf_ball`, true)
    if not hash then return nil end
    local o = CreateObject(hash, at.x, at.y, at.z - 5.0, false, false, false)
    SetEntityCollision(o, false, false)
    SetEntityVisible(o, false, false)
    SetEntityAlpha(o, 0, false)
    return o
end

local PROBES = {
    { pos = { x = 0.11, y = 0.23, z = -0.17 }, rot = { x = 17, y = 41, z = 73 } },
    { pos = { x = -0.07, y = 0.05, z = 0.19 }, rot = { x = -63, y = 22, z = 128 } },
    { pos = { x = 0.02, y = -0.09, z = 0.06 }, rot = { x = 0, y = 0, z = 0 } },
}

local function sample(ped, bone, probe, helper)
    local samples = {}
    Util.attach(helper, ped, bone, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    for i, pr in ipairs(PROBES) do
        Util.attach(probe, ped, bone, pr.pos, pr.rot)
        -- attachments settle over a couple of frames: wait until both read back as real matrices
        local s
        for _ = 1, 12 do
            Wait(0)
            local f1, r1, u1, p1 = GetEntityMatrix(probe)
            local f2, r2, u2, p2 = GetEntityMatrix(helper)
            if sane(f1) and sane(r1) and sane(u1) and sane(f2) and sane(r2) and sane(u2) and saneP(p1) and saneP(p2)
                and IsEntityAttachedToEntity(probe, ped) and IsEntityAttachedToEntity(helper, ped) then
                s = { f1 = f1, r1 = r1, u1 = u1, p1 = p1, f2 = f2, r2 = r2, u2 = u2, p2 = p2 }
                Wait(0) -- one more frame, then read the settled pose
                f1, r1, u1, p1 = GetEntityMatrix(probe)
                f2, r2, u2, p2 = GetEntityMatrix(helper)
                if sane(f1) and sane(r1) and sane(u1) and sane(f2) and sane(r2) and sane(u2) then
                    s = { f1 = f1, r1 = r1, u1 = u1, p1 = p1, f2 = f2, r2 = r2, u2 = u2, p2 = p2 }
                end
                break
            end
        end
        if not s then return nil end
        samples[i] = s
    end
    return samples
end

local function solve(samples)
    local function relFor(s, swap)
        local pr, pf = s.f1, s.r1
        local br, bf = s.f2, s.r2
        if not swap then pr, pf, br, bf = s.r1, s.f1, s.r2, s.f2 end
        local P = M3.fromAxes(pr, pf, s.u1)
        local B = M3.fromAxes(br, bf, s.u2)
        return M3.mul(M3.t(B), P), M3.apply(M3.t(B), s.p1 - s.p2)
    end

    local chosen, posErr = nil, math.huge
    for _, swap in ipairs({ false, true }) do
        local e = 0.0
        for i, s in ipairs(samples) do
            local _, o = relFor(s, swap)
            e = e + #(o - vector3(PROBES[i].pos.x, PROBES[i].pos.y, PROBES[i].pos.z))
        end
        if finite(e) and e < posErr then chosen, posErr = swap, e end
    end
    if chosen == nil or posErr > 0.03 then return nil, 'position', posErr end

    local mats = {}
    for i, s in ipairs(samples) do mats[i] = relFor(s, chosen) end
    local zero = mats[3]
    local wraps = { { L = nil, R = nil }, { L = zero, R = nil }, { L = nil, R = zero } }
    local best, bestErr = nil, math.huge
    for _, w in ipairs(wraps) do
        for _, order in ipairs(PERMS) do
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
                local conv = { order = order, sign = { x = sx, y = sy, z = sz }, L = w.L, R = w.R }
                local e = 0.0
                for i = 1, 2 do
                    local m = M3.mul(M3.mul(w.L or I3, FitMath.eulerM(PROBES[i].rot, conv)), w.R or I3)
                    e = e + M3.err(m, mats[i])
                end
                if finite(e) and e < bestErr then best, bestErr = conv, e end
            end end end
        end
    end
    if not best or bestErr > 0.02 then return nil, 'rotation', bestErr end
    best.swap = chosen
    return best, nil, bestErr
end

local probing = false

--- Probe the attach convention (once per session). Must run in a thread. Returns the convention or false.
function FitMath.calibrate()
    if FitMath.conv == false and GetGameTimer() - failedAt > 60000 then FitMath.conv = nil end
    if FitMath.conv ~= nil then return FitMath.conv end
    while probing do Wait(50) end
    if FitMath.conv ~= nil then return FitMath.conv end
    probing = true
    local result, why, err = false, nil, nil
    local ok, e = pcall(function()
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local probe, helper = ball(c), ball(c)
        if not probe or not helper then why = 'no probe model'; Util.delete(probe); Util.delete(helper); return end
        for _ = 1, 3 do
            local samples = sample(ped, 39317, probe, helper)
            if samples then
                local conv
                conv, why, err = solve(samples)
                if conv then result = conv break end
            else
                why = 'the probe never settled'
            end
            Wait(150)
        end
        Util.delete(probe)
        Util.delete(helper)
    end)
    if not ok then why = tostring(e) end
    if not result then
        -- the studio still works without it (it measures in game instead), so this is a debug note, not a warning
        Chains.debug(('fit probe failed (%s%s), using measured mode'):format(tostring(why), err and (' ' .. tostring(err)) or ''))
    else
        Chains.debug(('fit probe: order %s%s%s, err %.6f'):format(result.order[1], result.order[2], result.order[3], err or 0))
    end
    FitMath.conv = result
    if not result then failedAt = GetGameTimer() end
    probing = false
    return result
end
