-----------------------------------------------------------------
-- Automatic fit: a chain sits exactly like the clothing it came from
--
-- Clothing is skinned: the game moves it with a bone, relative to
-- where that bone sits in the skeleton's REST pose (shared/skeleton.lua,
-- from the freemode .yft). chainkit notes the bone each chain is
-- skinned to (nearly always SKEL_Spine3) and where the chain sat.
-- So the prop gets exactly the clothing's own relation to the bone:
--
--   position = inverse(rest pose of the bone) * where the chain sat
--   rotation = inverse(rest rotation of the bone)
--
-- That doesn't depend on how the character stands, so there's
-- nothing to wait for. The only thing measured in game is how GTA
-- turns that rotation into attach angles: once per bone, with two
-- invisible markers on the same bone read in the same frame (so it
-- works while the player moves). Kept in KVP. A fit saved in the
-- studio always wins.
-----------------------------------------------------------------

AutoFit = {}

local VER = 3
local rots = {}        -- [bone tag] = { rot = attach angles, measured = true|nil }
local queue, busy = {}, false
local fails = {}       -- [bone tag] = failed measurements this session

local XYZ = { order = { 'x', 'y', 'z' }, sign = { x = 1, y = 1, z = 1 } }   -- first guess of GTA's attach order

local function kvpName(tag) return ('nzc_bind:%d:v%d'):format(tag, VER) end

--- The skeleton bone a chain is skinned to: index, rest pose. Unknown or face bones: the upper spine.
local function boneOf(d)
    local idx = tonumber(d and d.bone)
    local s = idx and Skeleton[idx]
    if s then return idx, s end
    return 38, Skeleton[38]
end

-- inverse(rest rotation) as a 3x3 (row-major, like M3): R^T
local function restInv(s)
    local R = s.rot
    return { R[1], R[4], R[7], R[2], R[5], R[8], R[3], R[6], R[9] }
end

local function restPos(s, c)
    local T = restInv(s)
    local dx, dy, dz = c.x - s.pos[1], c.y - s.pos[2], c.z - s.pos[3]
    return {
        x = Util.round(T[1] * dx + T[2] * dy + T[3] * dz, 4),
        y = Util.round(T[4] * dx + T[5] * dy + T[6] * dz, 4),
        z = Util.round(T[7] * dx + T[8] * dy + T[9] * dz, 4),
    }
end

local function guess(s)
    local r = FitMath.solveEuler(restInv(s), nil, XYZ)
    return r and { x = Util.round(r.x, 3), y = Util.round(r.y, 3), z = Util.round(r.z, 3) } or { x = 0.0, y = 90.0, z = 180.0 }
end

local function rotFor(s)
    local r = rots[s.tag]
    if r == nil then
        local raw = GetResourceKvpString(kvpName(s.tag))
        local ok, saved = pcall(json.decode, raw or '')
        if ok and type(saved) == 'table' and tonumber(saved.x) then
            r = { rot = { x = saved.x, y = saved.y, z = saved.z }, measured = true }
        else
            r = { rot = guess(s) }
        end
        rots[s.tag] = r
    end
    return r
end

--- The bone tag a chain's clothing was skinned to (the studio's bone list uses tags)
function AutoFit.boneFor(_, key)
    local _, s = boneOf(Chains.def(key))
    return s.tag
end

--- The automatic fit of a converted chain (nil for chains without a clothing position)
function AutoFit.get(key)
    local d = Chains.def(key)
    if not d or not d.centre then return nil end
    local _, s = boneOf(d)
    local r = rotFor(s)
    return {
        bone = s.tag, pos = restPos(s, d.centre),
        rot = { x = r.rot.x, y = r.rot.y, z = r.rot.z }, auto = true,
    }
end

-----------------------------------------------------------------
-- measuring GTA's attach angles for one bone
-----------------------------------------------------------------

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end

-- an entity's axes as a matrix (columns x, y, z), straight from "where is my local x / y / z": no layout guessing
local function axesOf(e)
    local p = GetEntityCoords(e)
    local x = GetOffsetFromEntityInWorldCoords(e, 1.0, 0.0, 0.0) - p
    local y = GetOffsetFromEntityInWorldCoords(e, 0.0, 1.0, 0.0) - p
    local z = GetOffsetFromEntityInWorldCoords(e, 0.0, 0.0, 1.0) - p
    for _, v in ipairs({ x, y, z }) do
        if not finite(v.x) or not finite(v.y) or not finite(v.z) or #v < 0.9 or #v > 1.1 then return nil end
    end
    return M3.fromAxes(x, y, z)
end

local ZERO = { x = 0.0, y = 0.0, z = 0.0 }

local function ball(at)
    local hash = Util.loadModel(`prop_golf_ball`, true)
    if not hash then return nil end
    local o = CreateObject(hash, at.x, at.y, at.z - 5.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(o, false, false)
    SetEntityVisible(o, false, false)
    SetEntityAlpha(o, 0, false)
    return o
end

local function sq(r) local e = 0.0 for i = 1, 9 do e = e + r[i] * r[i] end return e end

local function solve3(A, b)
    local det = A[1] * (A[5] * A[9] - A[6] * A[8]) - A[2] * (A[4] * A[9] - A[6] * A[7]) + A[3] * (A[4] * A[8] - A[5] * A[7])
    if math.abs(det) < 1e-18 then return nil end
    local function d(c1, c2, c3)
        return c1[1] * (c2[2] * c3[3] - c3[2] * c2[3]) - c2[1] * (c1[2] * c3[3] - c3[2] * c1[3]) + c3[1] * (c1[2] * c2[3] - c2[2] * c1[3])
    end
    local col1, col2, col3 = { A[1], A[4], A[7] }, { A[2], A[5], A[8] }, { A[3], A[6], A[9] }
    return d(b, col2, col3) / det, d(col1, b, col3) / det, d(col1, col2, b) / det
end

-- attach angles -> the rotation they really give relative to the bone, read off the game: marker h0 sits on the bone
-- with no rotation (= the bone's own axes), h1 with `rot`; both read in the same frame
local function relative(ped, tag, h0, h1, rot)
    Util.attach(h1, ped, tag, ZERO, rot)
    for _ = 1, 10 do
        Wait(0)
        if IsEntityAttachedToEntity(h1, ped) and IsEntityAttachedToEntity(h0, ped) then break end
    end
    Wait(0)
    local B, P = axesOf(h0), axesOf(h1)
    if not B or not P then return nil end
    return M3.mul(M3.t(B), P)
end

local function measure(tag, s)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return nil end
    local at = GetEntityCoords(ped)
    local h0, h1 = ball(at), ball(at)
    if not h0 or not h1 then Util.delete(h0); Util.delete(h1); return nil end
    local T = restInv(s)
    local best, bestErr
    local ok, err = pcall(function()
        Util.attach(h0, ped, tag, ZERO, ZERO)
        local function res(rot)
            local A = relative(ped, tag, h0, h1, rot)
            if not A then return nil end
            local r = {}
            for i = 1, 9 do r[i] = A[i] - T[i] end
            return r
        end
        local seeds = { rotFor(s).rot, guess(s), { x = 0, y = 90, z = 180 }, { x = 0, y = 0, z = 0 }, { x = 90, y = 0, z = 0 },
            { x = 0, y = -90, z = 0 }, { x = 180, y = 0, z = 0 }, { x = 0, y = 0, z = 90 } }
        bestErr = math.huge
        for _, s0 in ipairs(seeds) do
            local th = { x = s0.x, y = s0.y, z = s0.z }
            local r = res(th)
            if not r then return end
            local cost, lambda = sq(r), 1e-2
            for _ = 1, 14 do
                if cost < 1e-6 then break end
                local J = {}
                for k, key in ipairs({ 'x', 'y', 'z' }) do
                    local t2 = { x = th.x, y = th.y, z = th.z }
                    t2[key] = t2[key] + 1.0
                    local rk = res(t2)
                    if not rk then return end
                    J[k] = {}
                    for i = 1, 9 do J[k][i] = rk[i] - r[i] end
                end
                local improved = false
                for _ = 1, 4 do
                    local JTJ, JTr = {}, {}
                    for a = 1, 3 do
                        local acc = 0.0
                        for i = 1, 9 do acc = acc + J[a][i] * r[i] end
                        JTr[a] = -acc
                        for b = 1, 3 do
                            local v = 0.0
                            for i = 1, 9 do v = v + J[a][i] * J[b][i] end
                            JTJ[(a - 1) * 3 + b] = v
                        end
                    end
                    for a = 1, 3 do JTJ[(a - 1) * 3 + a] = JTJ[(a - 1) * 3 + a] * (1 + lambda) + 1e-9 end
                    local dx, dy, dz = solve3(JTJ, JTr)
                    if not dx then break end
                    local cand = { x = th.x + dx, y = th.y + dy, z = th.z + dz }
                    local rc = res(cand)
                    if not rc then return end
                    local c2 = sq(rc)
                    if c2 < cost then th, r, cost, lambda, improved = cand, rc, c2, lambda * 0.3, true break end
                    lambda = lambda * 10
                end
                if not improved then break end
            end
            if cost < bestErr then best, bestErr = th, cost end
            if bestErr < 1e-5 then break end
        end
    end)
    Util.delete(h0)
    Util.delete(h1)
    if not ok then Chains.debug('autofit measure failed: ' .. tostring(err)) return nil end
    if not best or bestErr > 5e-4 then
        Chains.debug(('autofit: bone %d did not converge (%s)'):format(tag, tostring(bestErr)))
        return nil
    end
    Chains.debug(('autofit: bone %d (%s) attach rotation %.2f %.2f %.2f, error %.1e'):format(tag, s.name, best.x, best.y, best.z, bestErr))
    return { x = Util.round(Util.wrap180(best.x), 3), y = Util.round(Util.wrap180(best.y), 3), z = Util.round(Util.wrap180(best.z), 3) }
end

local function worker()
    busy = true
    while next(queue) do
        local tag, s = next(queue)
        queue[tag] = nil
        local r = rotFor(s)
        if not r.measured then
            local rot = measure(tag, s)
            if rot then
                local changed = math.abs(rot.x - r.rot.x) + math.abs(rot.y - r.rot.y) + math.abs(rot.z - r.rot.z) > 0.05
                rots[tag] = { rot = rot, measured = true }
                SetResourceKvp(kvpName(tag), json.encode(rot))
                if changed then TriggerEvent('nzc:autofit', tag) end
            else
                fails[tag] = (fails[tag] or 0) + 1
            end
        end
        Wait(0)
    end
    busy = false
end

--- Make sure the attach angles for this chain's bone have been checked in game (once per bone, ever).
function AutoFit.request(key)
    local d = Chains.def(key)
    if not d or not d.centre then return end
    local _, s = boneOf(d)
    if rotFor(s).measured or queue[s.tag] or (fails[s.tag] or 0) >= 3 then return end
    queue[s.tag] = s
    if not busy then CreateThread(worker) end
end

--- The studio's "From clothing": the automatic fit, checked in game first. Must run in a thread.
function AutoFit.solve(_, key)
    local d = Chains.def(key)
    if not d or not d.centre then return nil end
    local _, s = boneOf(d)
    if not rotFor(s).measured then
        local rot = measure(s.tag, s)
        if rot then
            rots[s.tag] = { rot = rot, measured = true }
            SetResourceKvp(kvpName(s.tag), json.encode(rot))
        end
    end
    return AutoFit.get(key)
end

function AutoFit.forget()
    for tag in pairs(rots) do DeleteResourceKvp(kvpName(tag)) end
    rots = {}
end
