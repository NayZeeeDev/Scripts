--[[
    NAYZEEE AMBULANCE - NPC patients (client): behaviour of EVERY NPC patient

    Any networked ped with an 'nza' state bag (core) is an NPC patient. The client that owns the
    ped (network control) keeps it in a pose that matches its state. With Config.Calls.npc.supine
    (default) every NPC patient on the ground lies ON THE BACK, so the head-to-toe check sees the
    whole body:
        dead / arrest / unconscious → flat on the back, still · overdose / cold → on the back, slumped
        conscious (wounded A/V, or alive and never stood up) → 'awake': on the back, quiet
        alive and stood up by a medic (Help up, Ask to Walk, out of a vehicle) → standing (hurt)
        trapped in a car → slumped in the seat
    (supine = false: the old poses - writhing, sitting up with fractures / after an overdose, standing.)
    Knocked over (vehicle, explosion, shove): once the ragdoll has settled - it can land face down -
    a lying patient goes straight onto their back instead of getting up first.
    It never fights other modules: carried / on a stretcher / bed / bay / seat ('nzaTr' bag),
    attached, escorted (Ask to Walk), in a body bag, during the local medic's procedure on it,
    or while another script plays an animation on it (re-applied only on a state change).
    Walking (standing) patients run from gunfire and come back (Config.Calls.npc.flee).
    Every nearby client (owner or not) applies the cosmetic damage packs and wetness of call
    victims ('nzaNpc' bag) and plays the server's speech ('nza:calls:say': subtitle + GTA sound).
    State bags are read through NZA.Scan.State (cached), never per tick from the bag itself.

    API (client)
      NZA.CallsNpc.Suspend(ped, name, on)       another module animates this NPC
      NZA.CallsNpc.ApplyPose(ped, pose) → bool  play a pose now (Config.Calls.npc.poses key; with the
                                                supine rule a sitting / writhing pose becomes 'awake')
      NZA.CallsNpc.Settle(ped) → bool           put a patient that was just let go of (dropped, off a
                                                cot, out of the bay) straight into its pose (on the back)
      NZA.CallsNpc.Stood(ped, ms)               a medic stood this patient up (help up, off a bed):
                                                it stays on its feet while alive; ms = its get-up clip
      NZA.CallsNpc.Pose(ped) → current pose key | nil
    Net events handled: nza:calls:say, nza:calls:released
]]

if not NAYZEEE_LOCK_OK then return end

NZA.CallsNpc = NZA.CallsNpc or {}
local N = NZA.CallsNpc

local HELD = { carry = true, str = true, bed = true, bay = true, seat = true }
local LYING = { unconscious = true, overdose = true, arrest = true, dead = true, writhe = true, cold = true, awake = true }
-- the lying poses that are on the back (the supine rule keeps these, everything else on the ground → 'awake')
local FACE_UP = { unconscious = true, overdose = true, arrest = true, dead = true, cold = true, awake = true }
local STANDING = { stand = true, hurt = true }
-- 'awake' when the config has no entry for it: conscious, on the back
local AWAKE_DEFAULT = {
    { dict = 'amb@world_human_bum_slumped@male@laying_on_back@base', clip = 'base' },
    { dict = 'mini@cpr@char_b@cpr_def', clip = 'cpr_pumpchest_idle' },
}
local SETTLE_MS = 900    -- a knocked-over patient lying still this long is turned onto its back
local UP_GRACE = 6000    -- after a stand-up the patient's new state ('alive') can arrive a moment later

local peds = {}          -- [ped] = { pose, entry, setup, home, fleeUntil, returnUntil, dp, wetAt, up, rag, mine }
local suspended = {}     -- [ped] = { [name] = true }

local function cfg(section)
    local c = Config.Calls and Config.Calls.npc or {}
    if section then return c[section] or {} end
    return c
end

-- Config.Calls.npc.supine (default on): every NPC patient on the ground lies on the back
local function supine() return cfg().supine ~= false end

-- cached state bag read (NZA.Scan keeps tracked peds' bags), plain read as a fallback
local function bagOf(ped, key)
    if NZA.Scan and NZA.Scan.State then return NZA.Scan.State(ped, key) end
    return Entity(ped).state[key]
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

local function poseList(pose)
    local list = (cfg('poses'))[pose]
    if pose == 'awake' and type(list) ~= 'table' then list = AWAKE_DEFAULT end
    return type(list) == 'table' and list or nil
end

local function entryFor(pose)
    local list = poseList(pose)
    if not list then return nil end
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

-- is the ped playing one of the lying poses right now (synced from its previous owner)?
local function playingLying(ped)
    for pose in pairs(LYING) do
        for _, e in ipairs(poseList(pose) or {}) do
            if e.dict and e.clip and IsEntityPlayingAnim(ped, e.dict, e.clip, 3) then return true end
        end
    end
    return false
end

-- is the ped standing in one of the standing poses ('hurt' / 'stand', synced from its previous owner)?
local function playingStanding(ped)
    for pose in pairs(STANDING) do
        for _, e in ipairs(poseList(pose) or {}) do
            if e.scenario and IsPedUsingScenario(ped, e.scenario) then return true end
            if e.dict and e.clip and IsEntityPlayingAnim(ped, e.dict, e.clip, 3) then return true end
        end
    end
    return false
end

-- the supine rule for a pose asked for by any module (scene builder, cut free...): sitting /
-- writhing on the ground becomes 'awake' (on the back); a patient a medic stood up keeps standing
local function supinePose(pose, r)
    if not pose or not supine() or FACE_UP[pose] or pose == 'trapped' then return pose end
    if STANDING[pose] and r and r.up then return pose end
    return 'awake'
end

function N.ApplyPose(ped, pose)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local r = rec(ped)
    pose = supinePose(pose, r)
    local e = entryFor(pose)
    if not e then return false end
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
    if LYING[pose] then r.up = false end
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

-- the pose from the state alone (the old rules, also what supine = false uses)
local function statePose(ped, bag, nb)
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
        -- awake again after an overdose / a near drowning / the cold: sitting up, drowsy
        if hint == 'sit' or hint == 'overdose' or hint == 'cold' or hint == 'unconscious' then
            return female and 'sit_f' or 'sit'
        end
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

-- the supine rule (Config.Calls.npc.supine): on the ground = on the back. Only an alive patient a
-- medic stood up stays on its feet (a sitting / lying alive patient is not stood up by itself).
local function standing(r, bag)
    if not r.up then return false end
    return bag.st == 'alive' or (r.upAt ~= nil and GetGameTimer() - r.upAt < UP_GRACE)
end

local function desiredPose(ped, bag, nb, r)
    local want = statePose(ped, bag, nb)
    if not supine() or want == 'trapped' then return want end
    if bag.st ~= 'dead' and bag.st ~= 'arrest' and standing(r, bag) then
        return STANDING[want] and want or 'hurt'
    end
    if FACE_UP[want] then return want end
    return 'awake'
end

local function held(ped, bag, nb)
    local tr = bagOf(ped, 'nzaTr')
    if type(tr) == 'table' and HELD[tr.m] then return true end
    if IsEntityAttached(ped) then return true end
    if bag.carried or bag.stretcher or bag.bag then return true end
    if type(nb) == 'table' and (nb.esc or nb.rel or nb.ho) then return true end
    if NZA.Assess and NZA.Assess.Following and NZA.Assess.Following(ped) then return true end
    if isSuspended(ped) then return true end
    local ctx = NZA.Proc and NZA.Proc.Active and NZA.Proc.Active()
    if ctx and ctx.entity == ped then return true end
    return false
end

local function setup(ped, r)
    local owner = NetworkGetEntityOwner(ped)
    if r.setup == owner then return end
    r.setup = owner
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

-- first look at a patient this client did not pose itself (spawned elsewhere, or taken over from
-- another client, also again after another client owned it for a while): was it stood up by a
-- medic, or is it on the ground? What it is visibly doing now wins over an older nzaTr command.
local function inferUp(ped, bag, nb, inVeh)
    if bag.st ~= 'alive' or inVeh then return false end
    if playingLying(ped) then return false end
    if playingStanding(ped) then return true end
    local tr = bagOf(ped, 'nzaTr')
    -- the server's last word on where it was put: stood up (help up, off a bed / cot, out of a car) or down
    if type(tr) == 'table' and tr.m == 'free' then return tr.stand == true end
    if type(nb) == 'table' and nb.c then return false end   -- a call victim, found on the ground
    return not IsPedRagdoll(ped) and not playingLying(ped)  -- anything else: as it is now
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
    -- owned by another client for a while (a second medic helped it up / laid it down): what this
    -- client remembered about standing may be old. Visibly lying → on the ground; not known to be
    -- standing → look at the patient again (inferUp)
    if r.mine == false then
        if playingLying(ped) then r.up = false elseif r.up ~= true then r.up = nil end
    end
    r.mine = true
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
    local nb = bagOf(ped, 'nzaNpc')
    if held(ped, bag, nb) then
        r.pose = nil
        r.rag = nil
        -- walking with a medic / released on scene: back on its feet
        if type(nb) == 'table' and (nb.esc or nb.rel) then r.up = true end
        return
    end
    -- collapsed again (wounded / arrest / dead): back on the ground
    if r.up and not standing(r, bag) then r.up = false end
    if getUp[ped] and now < getUp[ped] then return end
    getUp[ped] = nil
    local inVeh = IsPedInAnyVehicle(ped, false)
    -- sitting in a vehicle without being trapped (passenger, ambulance seat): leave it alone
    if inVeh and not (type(nb) == 'table' and nb.tr) then return end
    if r.up == nil then r.up = inferUp(ped, bag, nb, inVeh) end

    local want = desiredPose(ped, bag, nb, r)

    -- knocked over (vehicle, explosion, a shove): a lying patient is not left where the ragdoll
    -- settled (it can land face down) and does not get up first - once it lies still it goes
    -- straight onto its back. Standing patients get up by themselves as before.
    if IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedGettingUp(ped) then
        if not LYING[want] then
            r.rag = nil
            return
        end
        local gettingUp = IsPedGettingUp(ped)
        if gettingUp or (not IsPedFalling(ped) and GetEntitySpeed(ped) < 0.35) then
            r.rag = r.rag or now
            if gettingUp or now - r.rag >= SETTLE_MS then
                r.rag = nil
                ClearPedTasksImmediately(ped)
                r.pose = nil
                N.ApplyPose(ped, want)
            end
        else
            r.rag = nil
        end
        return
    end
    r.rag = nil

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
    local nb = bagOf(ped, 'nzaNpc')
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

-- Config.PatientVoice.screams off: no GTA pain yells / ambient voice from this NPC patient on this
-- client (where the sound would be heard). Once per ped.
local function mute(ped)
    local r = rec(ped)
    if r.muted then return end
    r.muted = true
    DisablePedPainAudio(ped, true)
    StopPedSpeaking(ped, true)
end

CreateThread(function()
    while true do
        local tick = tonumber(cfg().tick) or 600
        Wait(tick)
        if cfg().enabled ~= false then
            local me = GetEntityCoords(PlayerPedId())
            local radius = tonumber(cfg().radius) or 120.0
            local now = GetGameTimer()
            local quiet = not NZA.UI.PatientVoice('screams')
            for _, ped in ipairs(NZA.Scan.Peds()) do
                local bag = bagOf(ped, 'nza')
                if type(bag) == 'table' and #(GetEntityCoords(ped) - me) <= radius then
                    if quiet then pcall(mute, ped) end
                    local ok, err = pcall(cosmeticTick, ped, now)
                    if not ok then NZA.Debug('calls npc cosmetic', err) end
                    if NetworkHasControlOfEntity(ped) then
                        ok, err = pcall(ownerTick, ped, bag, now)
                        if not ok then NZA.Debug('calls npc', err) end
                    else
                        local r = peds[ped]
                        if r and r.mine then r.mine = false end
                    end
                end
            end
            for ped in pairs(peds) do
                if not DoesEntityExist(ped) then peds[ped] = nil; suspended[ped] = nil; getUp[ped] = nil end
            end
        end
    end
end)

-- just let go of (dropped from a carry, off a cot, out of the bay): straight into the pose its state
-- asks for - on the back - instead of a ragdoll that can land face down. false = not ours to pose.
function N.Settle(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return false end
    if cfg().enabled == false or IsPedInAnyVehicle(ped, false) then return false end
    local bag = bagOf(ped, 'nza')
    if type(bag) ~= 'table' then return false end
    local r = rec(ped)
    r.mine = true   -- posed by this client now (not a stale take-over)
    if not standing(r, bag) then r.up = false end
    local want = desiredPose(ped, bag, bagOf(ped, 'nzaNpc'), r)
    if not LYING[want] then return false end
    getUp[ped], r.rag, r.pose = nil, nil, nil
    return N.ApplyPose(ped, want)
end

-- a medic stood this patient up (Help up, helped off a bed / table / out of a vehicle): it stays on
-- its feet while alive. ms = the get-up clip the caller plays (no pose is forced on top of it).
function N.Stood(ped, ms)
    if not ped or ped == 0 then return end
    local r = rec(ped)
    r.up, r.upAt, r.pose, r.rag = true, GetGameTimer(), nil, nil
    if NetworkHasControlOfEntity(ped) then r.mine = true end   -- this client stood it up: not a stale take-over
    if tonumber(ms) then getUp[ped] = GetGameTimer() + math.floor(tonumber(ms)) end
end

-- ════════════════════════════════════════════════════════════════════════
-- SPEECH (server picks the line, every nearby client shows / plays it)
-- ════════════════════════════════════════════════════════════════════════

local function playSound(ped, kind)
    if not NZA.UI.PatientVoice('screams') then return end   -- Config.PatientVoice.screams (default off)
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

-- patients and bystanders: the GTA sound obeys Config.PatientVoice.screams (playSound), the
-- subtitle Config.PatientVoice.speech (NZA.UI.Speech)
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
    r.pose, r.up = nil, true
    ClearPedTasks(ped)
    if wasLying and standUp(ped) then Wait(1700) end
    if NZA.UI.PatientVoice('screams') then PlayPedAmbientSpeechNative(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR') end
    TaskWanderStandard(ped, 10.0, 10)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    peds, suspended, getUp = {}, {}, {}
end)
