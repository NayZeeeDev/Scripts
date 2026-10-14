--[[
    NAYZEEE AMBULANCE - NPC patients (client): behaviour of EVERY NPC patient

    Any networked ped with an 'nza' state bag (core) is an NPC patient. The client that owns the
    ped (network control) keeps it in a pose that matches its state:
        dead → body on the ground · arrest → on the back, still (ready for CPR)
        wounded + P/U → unconscious (overdose / cold variants) · wounded + A/V → writhing / sitting
        alive → sitting (fractures) / standing hurt / standing · trapped in a car → slumped in the seat
    It never fights other modules: carried / on a stretcher / bed / bay / seat ('nzaTr' bag),
    attached, escorted (Ask to Walk), in a body bag, during the local medic's procedure on it,
    or while another script plays an animation on it (re-applied only on a state change).
    Walking patients run from gunfire and come back (Config.Calls.npc.flee).
    Every nearby client (owner or not) applies the cosmetic damage packs and wetness of call
    victims ('nzaNpc' bag) and plays the server's speech ('nza:calls:say': subtitle + GTA sound).

    API (client)
      NZA.CallsNpc.Suspend(ped, name, on)       another module animates this NPC
      NZA.CallsNpc.ApplyPose(ped, pose) → bool  play a pose now (Config.Calls.npc.poses key)
      NZA.CallsNpc.Pose(ped) → current pose key | nil
    Net events handled: nza:calls:say, nza:calls:released
]]

if not NAYZEEE_LOCK_OK then return end

NZA.CallsNpc = NZA.CallsNpc or {}
local N = NZA.CallsNpc

local HELD = { carry = true, str = true, bed = true, bay = true, seat = true }
local LYING = { unconscious = true, overdose = true, arrest = true, dead = true, writhe = true, cold = true }

local peds = {}          -- [ped] = { pose, entry, setup, home, fleeUntil, returnUntil, dp, wetAt, owner }
local suspended = {}     -- [ped] = { [name] = true }

local function cfg(section)
    local c = Config.Calls and Config.Calls.npc or {}
    if section then return c[section] or {} end
    return c
end

local function rec(ped)
    local r = peds[ped]
    if not r then
        r = {}
        peds[ped] = r
    end
    return r
end

-- ════════════════════════════════════════════════════════════════════════
-- POSES
-- ════════════════════════════════════════════════════════════════════════

local dictOk = {}

local function loadDict(dict)
    if dictOk[dict] == false then return false end
    if HasAnimDictLoaded(dict) then return true end
    if not DoesAnimDictExist(dict) then
        dictOk[dict] = false
        return false
    end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(25) end
    dictOk[dict] = HasAnimDictLoaded(dict)
    return dictOk[dict]
end

local function entryFor(pose)
    local list = (cfg('poses'))[pose]
    if type(list) ~= 'table' then return nil end
    for _, e in ipairs(list) do
        if e.scenario then return e end
        if e.dict and e.clip and loadDict(e.dict) then return e end
    end
    return nil
end

local function playingEntry(ped, e)
    if not e then return false end
    if e.scenario then return IsPedUsingScenario(ped, e.scenario) end
    return IsEntityPlayingAnim(ped, e.dict, e.clip, 3)
end

function N.ApplyPose(ped, pose)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local e = entryFor(pose)
    if not e then return false end
    local r = rec(ped)
    local inVeh = IsPedInAnyVehicle(ped, false)
    if e.scenario then
        if inVeh then return false end
        ClearPedTasks(ped)
        TaskStartScenarioInPlace(ped, e.scenario, 0, true)
    else
        if not inVeh then ClearPedTasks(ped) end
        local flag = e.flag or (inVeh and 17 or 1)
        TaskPlayAnim(ped, e.dict, e.clip, 4.0, -4.0, -1, flag, 0.0, false, false, false)
    end
    r.pose, r.entry, r.appliedAt = pose, e, GetGameTimer()
    return true
end

function N.Pose(ped)
    local r = peds[ped]
    return r and r.pose or nil
end

function N.Suspend(ped, name, on)
    if not ped then return end
    local s = suspended[ped] or {}
    s[name or 'any'] = on and true or nil
    suspended[ped] = next(s) and s or nil
end

local function isSuspended(ped)
    return suspended[ped] ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
-- DECISIONS
-- ════════════════════════════════════════════════════════════════════════

local function hasTag(bag, tag)
    for _, t in ipairs(type(bag.tags) == 'table' and bag.tags or {}) do
        if t == tag then return true end
    end
    return false
end

local function desiredPose(ped, bag, nb)
    local st = bag.st
    if st == 'dead' then return 'dead' end
    if st == 'arrest' then return 'arrest' end
    nb = type(nb) == 'table' and nb or {}
    if nb.tr and IsPedInAnyVehicle(ped, false) then return 'trapped' end
    local hint = nb.pose
    local female = nb.sex == 'f' or (nb.sex == nil and not IsPedMale(ped))
    if st == 'wounded' then
        if bag.avpu == 'P' or bag.avpu == 'U' then
            if hint == 'overdose' or hint == 'cold' then return hint end
            return 'unconscious'
        end
        if hint == 'sit' then return female and 'sit_f' or 'sit' end
        return 'writhe'
    end
    -- alive
    if nb.tr then return 'writhe' end
    if hasTag(bag, 'fracture') or hint == 'sit' or hint == 'overdose' then
        return female and 'sit_f' or 'sit'
    end
    if (tonumber(bag.inj) or 0) > 0 then return 'hurt' end
    return 'stand'
end

local function held(ped, bag)
    local tr = Entity(ped).state.nzaTr
    if type(tr) == 'table' and HELD[tr.m] then return true end
    if IsEntityAttached(ped) then return true end
    if bag.carried or bag.stretcher or bag.bag then return true end
    local nb = Entity(ped).state.nzaNpc
    if type(nb) == 'table' and (nb.esc or nb.rel or nb.ho) then return true end
    if NZA.Assess and NZA.Assess.Following and NZA.Assess.Following(ped) then return true end
    if isSuspended(ped) then return true end
    local ctx = NZA.Proc and NZA.Proc.Active and NZA.Proc.Active()
    if ctx and ctx.entity == ped then return true end
    return false
end

local function setup(ped, r)
    if r.setup == ped .. ':' .. tostring(NetworkGetEntityOwner(ped)) then return end
    r.setup = ped .. ':' .. tostring(NetworkGetEntityOwner(ped))
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedConfigFlag(ped, 281, true)   -- no GTA writhe
    SetPedKeepTask(ped, true)
    SetPedCanPlayAmbientAnims(ped, false)
    if cfg().invincible ~= false then SetEntityInvincible(ped, true) end
end

local function shotsNear(c, radius)
    return IsAnyPedShootingInArea(c.x - radius, c.y - radius, c.z - radius, c.x + radius, c.y + radius, c.z + radius, false, false)
end

local getUp = {}

local function standUp(ped)
    local g = cfg().getUp
    if type(g) == 'table' and g.dict and loadDict(g.dict) then
        ClearPedTasks(ped)
        TaskPlayAnim(ped, g.dict, g.clip, 4.0, -4.0, g.ms or 1800, 0, 0.0, false, false, false)
        getUp[ped] = GetGameTimer() + (g.ms or 1800)
        return true
    end
    return false
end

local function ownerTick(ped, bag, now)
    local r = rec(ped)
    setup(ped, r)
    -- GTA may still kill an NPC (e.g. invincible turned off) - bring the body back under our control
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
        if bag.st ~= 'dead' or cfg().keepBodies ~= false then
            ResurrectPed(ped)
            SetEntityHealth(ped, GetEntityMaxHealth(ped))
            ClearPedTasksImmediately(ped)
            r.pose = nil
        end
    end
    if held(ped, bag) then
        r.pose = nil
        return
    end
    if getUp[ped] and now < getUp[ped] then return end
    getUp[ped] = nil
    if IsPedRagdoll(ped) or IsPedGettingUp(ped) or IsPedFalling(ped) then return end
    local nb = Entity(ped).state.nzaNpc
    -- sitting in a vehicle without being trapped (passenger, ambulance seat): leave it alone
    if IsPedInAnyVehicle(ped, false) and not (type(nb) == 'table' and nb.tr) then return end

    local want = desiredPose(ped, bag, nb)
    local pos = GetEntityCoords(ped)
    r.home = r.home or pos

    -- walking patients run from gunfire, then return
    local fl = cfg('flee')
    if fl.enabled ~= false and (want == 'stand' or want == 'hurt') then
        if r.fleeUntil and now < r.fleeUntil then return end
        if r.fleeUntil and now >= r.fleeUntil then
            r.fleeUntil = nil
            r.returnUntil = now + 20000
            TaskGoStraightToCoord(ped, r.home.x, r.home.y, r.home.z, 1.0, 20000, GetEntityHeading(ped), 0.5)
            return
        end
        if r.returnUntil then
            if now < r.returnUntil and #(pos - r.home) > 1.6 then return end
            r.returnUntil = nil
            r.pose = nil
        end
        if shotsNear(pos, tonumber(fl.radius) or 30.0) then
            r.fleeUntil = now + (tonumber(fl.time) or 8) * 1000
            ClearPedTasks(ped)
            TaskSmartFleeCoord(ped, pos.x, pos.y, pos.z, 40.0, (tonumber(fl.time) or 8) * 1000, false, false)
            r.pose = nil
            return
        end
    end

    if r.pose == want and playingEntry(ped, r.entry) then return end
    if r.pose == want and (GetIsTaskActive(ped, 134) or (r.entry and not r.entry.scenario and IsPedUsingAnyScenario(ped))) then
        -- somebody else is animating this patient right now (procedure, carry hand-off...)
        return
    end
    -- lying → standing goes through a get-up
    if r.pose and LYING[r.pose] and not LYING[want] and want ~= 'trapped' then
        r.pose = nil
        if standUp(ped) then return end
    end
    N.ApplyPose(ped, want)
    if want == 'hurt' or want == 'stand' then
        local clip = cfg().limpClipset
        if want == 'hurt' and clip then
            RequestAnimSet(clip)
            if HasAnimSetLoaded(clip) then SetPedMovementClipset(ped, clip, 1.0) end
        end
    end
end

-- cosmetic: blood / burns / wet clothes (every nearby client)
local function cosmeticTick(ped, now)
    local nb = Entity(ped).state.nzaNpc
    if type(nb) ~= 'table' then return end
    local r = rec(ped)
    if type(nb.dp) == 'table' and not r.dp then
        r.dp = true
        for _, pack in ipairs(nb.dp) do ApplyPedDamagePack(ped, pack, 0.0, 1.0) end
    end
    if nb.wet and not nb.ho and (not r.wetAt or now - r.wetAt > 15000) then
        r.wetAt = now
        SetPedWetnessHeight(ped, 2.0)
    end
end

CreateThread(function()
    while true do
        local tick = tonumber(cfg().tick) or 600
        Wait(tick)
        if cfg().enabled ~= false then
            local me = GetEntityCoords(PlayerPedId())
            local radius = tonumber(cfg().radius) or 120.0
            local now = GetGameTimer()
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
                    local bag = Entity(ped).state.nza
                    if type(bag) == 'table' and #(GetEntityCoords(ped) - me) <= radius then
                        local ok, err = pcall(cosmeticTick, ped, now)
                        if not ok then NZA.Debug('calls npc cosmetic', err) end
                        if NetworkHasControlOfEntity(ped) then
                            ok, err = pcall(ownerTick, ped, bag, now)
                            if not ok then NZA.Debug('calls npc', err) end
                        end
                    end
                end
            end
            for ped in pairs(peds) do
                if not DoesEntityExist(ped) then peds[ped] = nil; suspended[ped] = nil; getUp[ped] = nil end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SPEECH (server picks the line, every nearby client shows / plays it)
-- ════════════════════════════════════════════════════════════════════════

local function playSound(ped, kind)
    local map = (cfg('speech')).sounds_map or {}
    local s = map[kind]
    if type(s) ~= 'table' or not ped or ped == 0 then return end
    if s.pain then
        local ids = s.pain
        PlayPain(ped, ids[math.random(#ids)], 0.0, false)
    elseif s.speech then
        PlayPedAmbientSpeechNative(ped, s.speech, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
    end
end

RegisterNetEvent('nza:calls:say', function(d)
    if type(d) ~= 'table' then return end
    local net = tonumber(d.net)
    local ped = 0
    if net and NetworkDoesNetworkIdExist(net) then ped = NetworkGetEntityFromNetworkId(net) end
    if ped ~= 0 and d.sound then playSound(ped, d.sound) end
    if type(d.text) == 'string' and d.text ~= '' and NZA.UI and NZA.UI.Speech then
        NZA.UI.Speech(type(d.name) == 'string' and d.name or '', d.text, tonumber(d.ms) or 3800, { npc = true, bystander = d.by == true or nil })
    end
end)

-- released on scene: the owner lets the patient walk off
RegisterNetEvent('nza:calls:released', function(net)
    net = tonumber(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return end
    local ped = NetworkGetEntityFromNetworkId(net)
    if ped == 0 or not NetworkHasControlOfEntity(ped) then return end
    local r = rec(ped)
    local wasLying = LYING[r.pose or ''] or false
    r.pose = nil
    ClearPedTasks(ped)
    if wasLying and standUp(ped) then Wait(1700) end
    PlayPedAmbientSpeechNative(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
    TaskWanderStandard(ped, 10.0, 10)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    peds, suspended, getUp = {}, {}, {}
end)
