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

local VER = 1
local cache = {}      -- ["key|m"] = fit | false (can't be done)
local queued = {}     -- ["key|m"] = ped
local busy = false

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

local function unit(v) return v and v == v and #v > 0.9 and #v < 1.1 end

local function compute(ped, key, conv)
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

    local fit
    local ok, err = pcall(function()
        local bone = AutoFit.boneFor(ped, key)
        Util.attach(helper, ped, bone, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
        for _ = 1, 12 do
            Wait(0)
            local f, r, u = GetEntityMatrix(helper)
            if unit(f) and unit(r) and unit(u) and IsEntityAttachedToEntity(helper, ped) then break end
        end
        Wait(0)
        if not idle(ped) then return end
        -- one frame: the bone, the ped and where the clothing sat, all read together
        local br, bf, bu, bp = FitMath.axes(helper, conv)
        local pr, pf, pu = FitMath.axes(ped, conv)
        if not (unit(br) and unit(bf) and unit(bu) and unit(pr) and unit(pf) and unit(pu)) then return end
        local c = d.centre
        local point = GetOffsetFromEntityInWorldCoords(ped, c.x, c.y, c.z)
        local B = M3.fromAxes(br, bf, bu)
        -- the prop's mesh is in the ped's own axes (that's how clothing is modelled)
        local rot = FitMath.solveEuler(M3.mul(M3.t(B), M3.fromAxes(pr, pf, pu)), nil, conv)
        if not rot then return end
        local mid = vector3(0.0, 0.0, 0.0)
        if d.min and d.max then mid = vector3((d.min.x + d.max.x) / 2, (d.min.y + d.max.y) / 2, (d.min.z + d.max.z) / 2) end
        local pos = M3.apply(M3.t(B), point - bp) - M3.apply(FitMath.attachM(rot, conv), mid)
        if pos ~= pos or #pos > 1.5 then return end -- nonsense: keep the fallback
        fit = {
            bone = bone,
            pos = { x = Util.round(pos.x, 4), y = Util.round(pos.y, 4), z = Util.round(pos.z, 4) },
            rot = { x = Util.round(rot.x, 3), y = Util.round(rot.y, 3), z = Util.round(rot.z, 3) },
            auto = true,
        }
    end)
    Util.delete(helper)
    if not ok then Chains.debug('autofit failed: ' .. tostring(err)) end
    return fit
end

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
                local cands = { ped, PlayerPedId() }
                for _, p in ipairs(cands) do
                    if p and DoesEntityExist(p) and IsPedModel(p, g == 'f' and `mp_f_freemode_01` or `mp_m_freemode_01`) and idle(p) then
                        local conv = FitMath.calibrate()
                        if not conv then done = true break end
                        local fit = compute(p, key, conv)
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
    if queued[id] or AutoFit.get(key, female) then return end
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
