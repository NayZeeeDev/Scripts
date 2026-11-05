-----------------------------------------------------------------
-- Automatic fit: a chain sits like the clothing it came from
--
-- A clothing chain is skinned to ped bones; most are moved 100% by
-- one bone (the upper spine). chainkit notes that bone, and where
-- the chain sat on the body. Here we stick the prop to that same
-- bone at the same spot, worked out on a real ped of the right body
-- standing still: exactly what the studio's "From clothing" does,
-- without anyone opening the studio.
--
-- Done once per chain per body (male / female), then kept in this
-- player's KVP. A fit saved in the studio always wins over it.
-----------------------------------------------------------------

AutoFit = {}

local VER = 2   -- bump to make every client measure again
local cache = {}      -- ["key|m"] = fit | false (can't be done)
local queued = {}     -- ["key|m"] = ped
local busy = false
local fails = {}      -- ["key|m"] = measurements that didn't work out; after 3 this session keeps the fallback

-- bones a clothing chain can be skinned to: the studio's bone list works with these tags
local TAGS = { 24818, 39317, 24817, 24816, 23553, 57597, 31086, 12844, 35731, 64729, 10706, 11816, 0 }

local function body(female) return female and 'f' or 'm' end

local function sigOf(d)
    local c = d.centre
    return ('%d|%.4f|%.4f|%.4f|%d'):format(VER, c.x, c.y, c.z, tonumber(d.bone) or -1)
end

local function kvpName(key, g) return ('nzc_af:%s:%s'):format(key, g) end

--- The bone tag (or -(index + 1) when it has no tag we know) a chain's clothing was skinned to.
function AutoFit.boneFor(ped, key)
    local d = Chains.def(key)
    local idx = d and tonumber(d.bone)
    if not idx or idx < 0 then return 39317 end
    for _, tag in ipairs(TAGS) do
        if GetPedBoneIndex(ped, tag) == idx then return tag end
    end
    return -(idx + 1)
end

function AutoFit.get(key, female)
    local d = Chains.def(key)
    if not d or not d.centre then return nil end
    local id = key .. '|' .. body(female)
    local c = cache[id]
    if c == nil then
        c = false -- looked: nothing yet (the worker fills it in)
        local raw = GetResourceKvpString(kvpName(key, body(female)))
        local ok, saved = pcall(json.decode, raw or '')
        if ok and type(saved) == 'table' and saved.sig == sigOf(d) and type(saved.fit) == 'table' then c = saved.fit end
        cache[id] = c
    end
    return c or nil
end

--- Standing still on foot, not mid-animation: the pose the clothing was modelled in (near enough)
local function idle(ped)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return false end
    if IsPedInAnyVehicle(ped, true) or not IsPedOnFoot(ped) then return false end
    if IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedJumping(ped) or IsPedClimbing(ped) or IsPedSwimming(ped) then return false end
    if GetEntitySpeed(ped) > 0.12 then return false end
    if IsPedUsingAnyScenario(ped) or IsPedInCover(ped, false) or IsPedReloading(ped) or IsPlayerFreeAiming(PlayerId()) and ped == PlayerPedId() then return false end
    local w = Config.Wear.Anim
    if w and IsEntityPlayingAnim(ped, w.dict, w.clip, 3) then return false end
    for _, a in pairs(Config.Hold.Anims or {}) do
        if a.dict and IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then return false end
    end
    return true
end

-----------------------------------------------------------------
-- measuring (no assumptions about how GTA applies attach angles)
--
-- An invisible golf ball is attached to the bone and the game is
-- asked where it really ended up. Rotation: the attach angles are
-- adjusted (Levenberg-Marquardt, a few dozen frames) until the ball
-- faces exactly like the ped. Position: three nudges tell which way
-- the bone's x / y / z point, then the offset is solved directly.
-----------------------------------------------------------------

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end
local function unit(v) return v and finite(v.x) and finite(v.y) and finite(v.z) and #v > 0.9 and #v < 1.1 end

-- an entity's orientation as 9 numbers: its axes when the game reports clean ones, else from its rotation
local function orient(e, useRot)
    if not useRot then
        local f, r, u = GetEntityMatrix(e)
        if unit(f) and unit(r) and unit(u) then return { f.x, f.y, f.z, r.x, r.y, r.z, u.x, u.y, u.z } end
        return nil
    end
    local rot = GetEntityRotation(e, 2)
    if not rot or not finite(rot.x) then return nil end
    return M3.euler(rot.x, rot.y, rot.z)
end

local function settle(helper, ped)
    for _ = 1, 10 do
        Wait(0)
        if IsEntityAttachedToEntity(helper, ped) then break end
    end
    Wait(0) -- the frame after the attach took effect
end

local ZERO = { x = 0.0, y = 0.0, z = 0.0 }

local function residual(helper, ped, bone, th, useRot)
    Util.attach(helper, ped, bone, ZERO, th)
    settle(helper, ped)
    local A, B = orient(helper, useRot), orient(ped, useRot)
    if not A or not B then return nil end
    local r = {}
    for i = 1, 9 do r[i] = A[i] - B[i] end
    return r
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

--- attach angles that make `helper` on `bone` face exactly like `ped`
local function solveRotation(helper, ped, bone, useRot)
    local KEYS = { 'x', 'y', 'z' }
    local SEEDS = { { x = 0, y = 0, z = 0 }, { x = 90, y = 0, z = 0 }, { x = -90, y = 0, z = 0 }, { x = 0, y = 90, z = 0 },
        { x = 0, y = -90, z = 0 }, { x = 0, y = 0, z = 90 }, { x = 0, y = 0, z = -90 }, { x = 180, y = 0, z = 0 } }
    local best, bestErr = nil, math.huge
    for _, s0 in ipairs(SEEDS) do
        local th = { x = s0.x, y = s0.y, z = s0.z }
        local r = residual(helper, ped, bone, th, useRot)
        if not r then return nil end
        local cost, lambda = sq(r), 1e-2
        for _ = 1, 14 do
            if cost < 2e-6 then break end
            local J = {}
            for k, key in ipairs(KEYS) do
                local t2 = { x = th.x, y = th.y, z = th.z }
                t2[key] = t2[key] + 1.0
                local rk = residual(helper, ped, bone, t2, useRot)
                if not rk then return nil end
                J[k] = {}
                for i = 1, 9 do J[k][i] = (rk[i] - r[i]) / 1.0 end
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
                local rc = residual(helper, ped, bone, cand, useRot)
                if not rc then return nil end
                local c2 = sq(rc)
                if c2 < cost then th, r, cost, lambda, improved = cand, rc, c2, lambda * 0.3, true break end
                lambda = lambda * 10
            end
            if not improved then break end
        end
        if cost < bestErr then best, bestErr = th, cost end
        if bestErr < 2e-5 then break end
    end
    return best, bestErr
end

--- the fit (bone, pos, rot) that puts the chain where the clothing sat, measured on `ped` right now
local function solve(ped, key)
    local d = Chains.def(key)
    if not d or not d.centre then return nil end
    local hash = Util.loadModel(`prop_golf_ball`, true)
    if not hash then return nil end
    local pc = GetEntityCoords(ped)
    local helper = CreateObject(hash, pc.x, pc.y, pc.z - 5.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(helper, false, false)
    SetEntityVisible(helper, false, false)
    SetEntityAlpha(helper, 0, false)

    local fit, why
    local ok, err = pcall(function()
        local c = d.centre
        local function target() return GetOffsetFromEntityInWorldCoords(ped, c.x, c.y, c.z) end

        -- the bone the clothing was rigged to, if it really is near the chain (else the upper spine, then the neck)
        local bone
        for _, b in ipairs({ AutoFit.boneFor(ped, key), 24818, 39317 }) do
            local idx = b < 0 and (-b - 1) or GetPedBoneIndex(ped, b)
            if idx and idx >= 0 and #(GetWorldPositionOfEntityBone(ped, idx) - target()) < 0.35 then bone = b break end
        end
        bone = bone or 39317

        -- rotation: axes straight from the game; if it won't give clean ones, its euler rotation instead
        local useRot = residual(helper, ped, bone, ZERO, false) == nil
        local rot, rerr = solveRotation(helper, ped, bone, useRot)
        if not rot or rerr > 5e-4 then why = ('rotation did not converge (%s)'):format(tostring(rerr)) return end
        rot = { x = Util.wrap180(rot.x), y = Util.wrap180(rot.y), z = Util.wrap180(rot.z) }

        -- position: which way the bone's x / y / z point, measured with three nudges
        local function at(pos)
            Util.attach(helper, ped, bone, pos, rot)
            settle(helper, ped)
            return GetEntityCoords(helper)
        end
        local p0 = at(ZERO)
        local cx = (at({ x = 0.1, y = 0.0, z = 0.0 }) - p0) / 0.1
        local cy = (at({ x = 0.0, y = 0.1, z = 0.0 }) - p0) / 0.1
        local cz = (at({ x = 0.0, y = 0.0, z = 0.1 }) - p0) / 0.1
        p0 = at(ZERO)
        local want = target() - p0
        local x, y, z = solve3({ cx.x, cy.x, cz.x, cx.y, cy.y, cz.y, cx.z, cy.z, cz.z }, { want.x, want.y, want.z })
        if not x or not finite(x) or math.abs(x) + math.abs(y) + math.abs(z) > 1.5 then why = 'position did not solve' return end
        local pos = { x = Util.round(x, 4), y = Util.round(y, 4), z = Util.round(z, 4) }

        -- check it: the ball must land on the clothing's spot
        local miss = #(at(pos) - target())
        if miss > 0.01 then why = ('missed by %.3f m'):format(miss) return end
        fit = { bone = bone, pos = pos, rot = { x = Util.round(rot.x, 3), y = Util.round(rot.y, 3), z = Util.round(rot.z, 3) }, auto = true }
        Chains.debug(('autofit %s: bone %s, rotation error %.2e, miss %.4f m'):format(key, tostring(bone), rerr, miss))
    end)
    Util.delete(helper)
    if not ok then why = tostring(err) end
    if not fit then Chains.debug(('autofit %s failed: %s'):format(key, tostring(why))) end
    return fit
end
AutoFit.solve = solve

local function worker()
    busy = true
    while next(queued) do
        local id, ped = next(queued)
        queued[id] = nil
        local key, g = id:match('^(.*)|([mf])$')
        local d = key and Chains.def(key)
        if d and d.centre and not AutoFit.get(key, g == 'f') then
            -- wait (up to 20s) for this ped, or any ped of the same body, to stand still
            local done = false
            for _ = 1, 40 do
                local cands = { ped }
                if PlayerPedId() ~= ped then cands[2] = PlayerPedId() end
                for _, p in ipairs(cands) do
                    if p and DoesEntityExist(p) and IsPedModel(p, g == 'f' and `mp_f_freemode_01` or `mp_m_freemode_01`) and idle(p) then
                        local fit = solve(p, key)
                        -- moved while it measured: try again when they stand still (a few times)
                        if not fit then
                            fails[id] = (fails[id] or 0) + 1
                            if fails[id] >= 3 then done = true break end
                        end
                        if fit then
                            cache[id] = fit
                            SetResourceKvp(kvpName(key, g), json.encode({ sig = sigOf(d), fit = fit }))
                            Chains.debug(('autofit %s (%s): bone %s pos %.3f %.3f %.3f'):format(key, g, tostring(fit.bone), fit.pos.x, fit.pos.y, fit.pos.z))
                            TriggerEvent('nzc:autofit', key)
                            done = true
                            break
                        end
                    end
                end
                if done then break end
                Wait(500)
            end
        end
        Wait(0)
    end
    busy = false
end

--- Work out the fit of `key` for `ped`'s body when it's free to (no-op if known, queued, or not a converted chain).
function AutoFit.request(key, ped)
    local d = Chains.def(key)
    if not d or not d.centre or not ped or not DoesEntityExist(ped) then return end
    local female
    if IsPedModel(ped, `mp_f_freemode_01`) then female = true
    elseif IsPedModel(ped, `mp_m_freemode_01`) then female = false
    else return end -- other ped models: their skeleton isn't the one the clothing was made for
    local id = key .. '|' .. body(female)
    if queued[id] or (fails[id] or 0) >= 3 or AutoFit.get(key, female) then return end
    queued[id] = ped
    if not busy then CreateThread(worker) end
end

--- Forget the fits (the studio's Reset, or after a chain was rebuilt with a new shape)
function AutoFit.forget(key)
    for _, g in ipairs({ 'm', 'f' }) do
        cache[key .. '|' .. g] = nil
        DeleteResourceKvp(kvpName(key, g))
    end
end

AddEventHandler('nzc:registry', function()
    -- read again from KVP on next use: a rebuilt chain (new shape or bone) fails the sig check and is fitted again
    for id in pairs(cache) do cache[id] = nil end
end)
