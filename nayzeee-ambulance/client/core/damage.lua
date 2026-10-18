--[[
    NAYZEEE AMBULANCE - Client core: damage detection & GTA death (NZA.Damage)

    Turns everything that hurts the local player into 'nza:damage' reports for the server
    (which turns them into injuries) and replaces GTA death with 'nza:down'.

    Sources:
      gameEventTriggered CEventNetworkEntityDamage (victim == own ped)
          weapon hash + group, last damaged bone → region (chest/back flipped by attacker
          direction), damage = health delta, armour = armour delta, attacker server id /
          net id, melee flag. Hits within 200 ms with the same weapon/region/attacker are
          merged into one report (shotgun pellets) with hits = n.
      falls        height tracked while falling / ragdolling in the air, reported on landing
                   when ≥ Config.Damage.fall.minHeight (merged into GTA's WEAPON_FALL report)
      vehicles     speed drop per 100 ms ≥ Config.Damage.vehicle.minSpeedDrop with a real
                   collision, report speedDrop + belted (also sent as 'seatbelt', the field
                   core-server reads), merged into the crash damage report
      fire         while on fire, one report every Config.Damage.fire.tick with fire = true
      drowning     underwater with no air left, one report every 2 s with drown = true

    GTA death: the instant the local ped dies we resurrect it in place (out of the vehicle,
    to the water surface when drowned), set a safe health value, keep the blood decals, and
    send 'nza:down' once (only while the patient is 'alive', never twice within 5 s). While
    already wounded/arrest/dead we still resurrect (a dead ped cannot play the wounded
    anims) but never report, with a backoff so a script that keeps killing us cannot loop.
    spawnmanager auto-spawn and the native death restart / fade are disabled.

      NZA.Damage.SyncBaseline()     call after changing health/armour from script so the
                                    change is not reported as damage (self.lua does)
      NZA.Damage.IsBelted()         → bool (seatbelt detection used for crash reports)
      NZA.Damage.WeaponName(hash)   → 'WEAPON_X' | nil (known names only)

    Events sent: nza:damage (report), nza:down (info)
    Bus events emitted: self:down (info)          right after 'nza:down' was sent
                        self:resurrected (wasAlive) after every in-place resurrect, so modules
                                                    holding a pose (wounded) re-apply it
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Damage = NZA.Damage or {}
local D = NZA.Damage
local U = NZA.Util

-- ════════════════════════════════════════════════════════════════════════
-- HASH HELPERS (game events give unsigned, natives give signed - compare as signed)
-- ════════════════════════════════════════════════════════════════════════

local function s32(x)
    x = math.tointeger(math.floor(tonumber(x) or 0)) or 0
    x = x & 0xFFFFFFFF
    if x >= 0x80000000 then x = x - 0x100000000 end
    return x
end

local function h(name)
    return s32(GetHashKey(name))
end

local W = {
    FALL = h('WEAPON_FALL'),
    FIRE = h('WEAPON_FIRE'),
    MOLOTOV = h('WEAPON_MOLOTOV'),
    PETROLCAN = h('WEAPON_PETROLCAN'),
    FLARE = h('WEAPON_FLARE'),
    DROWN = h('WEAPON_DROWNING'),
    DROWN_VEH = h('WEAPON_DROWNING_IN_VEHICLE'),
    RAMMED = h('WEAPON_RAMMED_BY_CAR'),
    RUN_OVER = h('WEAPON_RUN_OVER_BY_CAR'),
    HELI_CRASH = h('WEAPON_HELI_CRASH'),
    EXPLOSION = h('WEAPON_EXPLOSION'),
    UNARMED = h('WEAPON_UNARMED'),
}
local FIRE_WEAPONS = { [W.FIRE] = true, [W.MOLOTOV] = true, [W.PETROLCAN] = true, [W.FLARE] = true }
local DROWN_WEAPONS = { [W.DROWN] = true, [W.DROWN_VEH] = true }
local CRASH_WEAPONS = { [W.RAMMED] = true, [W.RUN_OVER] = true, [W.HELI_CRASH] = true }

local GROUPS = {
    'GROUP_UNARMED', 'GROUP_MELEE', 'GROUP_PISTOL', 'GROUP_SMG', 'GROUP_RIFLE', 'GROUP_MG',
    'GROUP_SHOTGUN', 'GROUP_SNIPER', 'GROUP_HEAVY', 'GROUP_THROWN', 'GROUP_PETROLCAN',
    'GROUP_STUNGUN', 'GROUP_FIREEXTINGUISHER', 'GROUP_PARACHUTE', 'GROUP_DIGISCANNER',
    'GROUP_NIGHTVISION', 'GROUP_TRANQILIZER', 'GROUP_METALDETECTOR',
}
local groupByHash = nil
local nameByHash = nil

local EXTRA_NAMES = {
    'WEAPON_FALL', 'WEAPON_FIRE', 'WEAPON_DROWNING', 'WEAPON_DROWNING_IN_VEHICLE', 'WEAPON_RAMMED_BY_CAR',
    'WEAPON_RUN_OVER_BY_CAR', 'WEAPON_HELI_CRASH', 'WEAPON_EXPLOSION', 'WEAPON_EXHAUSTION', 'WEAPON_BLEEDING',
    'WEAPON_HIT_BY_WATER_CANNON', 'WEAPON_ELECTRIC_FENCE', 'WEAPON_UNARMED', 'WEAPON_ANIMAL', 'WEAPON_COUGAR',
    'WEAPON_BARBED_WIRE', 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_MOLOTOV', 'WEAPON_PETROLCAN', 'WEAPON_FLARE',
}

local function buildLookups()
    groupByHash, nameByHash = {}, {}
    for _, g in ipairs(GROUPS) do groupByHash[h(g)] = g end
    local groups = Config.Damage and Config.Damage.groups
    if type(groups) == 'table' then
        for g in pairs(groups) do groupByHash[h(g)] = g end
    end
    for _, n in ipairs(EXTRA_NAMES) do nameByHash[h(n)] = n end
    local weapons = Config.Damage and Config.Damage.weapons
    if type(weapons) == 'table' then
        for n in pairs(weapons) do nameByHash[h(n)] = n end
    end
end

local function weaponGroup(hash)
    if not groupByHash then buildLookups() end
    local g = GetWeapontypeGroup(hash)
    return groupByHash[s32(g)]
end

function D.WeaponName(hash)
    if not nameByHash then buildLookups() end
    return nameByHash[s32(hash)]
end

-- ════════════════════════════════════════════════════════════════════════
-- BASELINE (previous health + armour, so damage = delta)
-- ════════════════════════════════════════════════════════════════════════

local base = { hp = 0, ar = 0, pendingSince = nil }

function D.SyncBaseline()
    local ped = PlayerPedId()
    base.hp = GetEntityHealth(ped)
    base.ar = GetPedArmour(ped)
    base.pendingSince = nil
end

-- ════════════════════════════════════════════════════════════════════════
-- REGIONS
-- ════════════════════════════════════════════════════════════════════════

local LEGS = { 'l_lower_leg', 'r_lower_leg', 'l_upper_leg', 'r_upper_leg' }
local FIRE_REGIONS = {
    { 'l_lower_leg', 14 }, { 'r_lower_leg', 14 }, { 'l_upper_leg', 9 }, { 'r_upper_leg', 9 },
    { 'l_lower_arm', 8 }, { 'r_lower_arm', 8 }, { 'l_upper_arm', 5 }, { 'r_upper_arm', 5 },
    { 'chest', 8 }, { 'back', 8 }, { 'abdomen', 6 }, { 'face', 4 }, { 'head', 2 },
}

local function attackerIsBehind(ped, attacker)
    if not attacker or attacker == 0 or attacker == ped or not DoesEntityExist(attacker) then return false end
    local fwd = GetEntityForwardVector(ped)
    local d = GetEntityCoords(attacker) - GetEntityCoords(ped)
    local len = math.sqrt(d.x * d.x + d.y * d.y)
    if len < 0.01 then return false end
    return (fwd.x * d.x + fwd.y * d.y) / len < -0.2
end

local function regionFor(ped, bone, weapon, attacker)
    local region = NZA.Const.BoneToRegion[bone]
    if region == 'chest' and attackerIsBehind(ped, attacker) then region = 'back' end
    if region then return region end
    if weapon == W.FALL then return LEGS[math.random(#LEGS)] end
    if FIRE_WEAPONS[weapon] then return U.weightedPick(FIRE_REGIONS) end
    return 'chest'
end

-- ════════════════════════════════════════════════════════════════════════
-- ATTACKER
-- ════════════════════════════════════════════════════════════════════════

local function attackerInfo(ped, ent)
    if not ent or ent == 0 or ent == -1 or not DoesEntityExist(ent) then return 0, nil end
    local aPed = ent
    if IsEntityAVehicle(ent) then aPed = GetPedInVehicleSeat(ent, -1) end
    local sid = 0
    if aPed and aPed ~= 0 and aPed ~= ped and IsEntityAPed(aPed) and IsPedAPlayer(aPed) then
        local idx = NetworkGetPlayerIndexFromPed(aPed)
        if idx and idx ~= -1 then sid = GetPlayerServerId(idx) end
    end
    local net = nil
    if ent ~= ped and NetworkGetEntityIsNetworked(ent) then net = NetworkGetNetworkIdFromEntity(ent) end
    return sid, net
end

-- ════════════════════════════════════════════════════════════════════════
-- REPORT QUEUE (merge bursts, attach fall / crash context, rate limit)
-- ════════════════════════════════════════════════════════════════════════

local pending = {}
local flushScheduled = false
local sentTimes = {}
local lastFall = nil      -- { h, at, reported }
local lastCrash = nil     -- { drop, belted, at, reported }
local fireAcc, drownAcc = 0, 0
local burning, drowning = false, false

local MAX_PER_SECOND = 15

local function enabled()
    return Config.Damage and Config.Damage.enabled ~= false
end

local function send(rep)
    if not enabled() then return end
    local now = GetGameTimer()
    for i = #sentTimes, 1, -1 do
        if now - sentTimes[i] > 1000 then table.remove(sentTimes, i) end
    end
    if #sentTimes >= MAX_PER_SECOND then return end
    sentTimes[#sentTimes + 1] = now
    rep.damage = math.floor((rep.damage or 0) + 0.5)
    rep.armour = math.floor((rep.armour or 0) + 0.5)
    rep.attacker = rep.attacker or 0
    rep.weaponName = rep.weaponName or D.WeaponName(rep.weapon)
    TriggerServerEvent('nza:damage', rep)
    NZA.Debug('damage', rep)
end

local function flush()
    flushScheduled = false
    local now = GetGameTimer()
    local list = pending
    pending = {}
    for _, rep in pairs(list) do
        if rep.weapon == W.FALL and lastFall and now - lastFall.at < 1500 then
            rep.fall = U.round(lastFall.h, 1)
            lastFall.reported = true
        end
        if lastCrash and now - lastCrash.at < 800 and not rep.attacker_is_gun then
            rep.speedDrop = U.round(lastCrash.drop, 1)
            rep.belted = lastCrash.belted
            rep.seatbelt = lastCrash.belted
            lastCrash.reported = true
        end
        rep.attacker_is_gun = nil
        if rep.damage + rep.armour >= 1 or rep.fall or rep.speedDrop then
            send(rep)
        end
    end
end

local function queue(rep)
    local key = ('%d:%s:%d'):format(rep.weapon, rep.region, rep.attacker or 0)
    local p = pending[key]
    if p then
        p.damage = p.damage + rep.damage
        p.armour = p.armour + rep.armour
        p.hits = p.hits + 1
        if rep.fatal then p.fatal = true end
    else
        pending[key] = rep
    end
    if not flushScheduled then
        flushScheduled = true
        SetTimeout(200, flush)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- GAME EVENT: ENTITY DAMAGE
-- ════════════════════════════════════════════════════════════════════════

local GUN_GROUPS = {
    GROUP_PISTOL = true, GROUP_SMG = true, GROUP_RIFLE = true, GROUP_MG = true,
    GROUP_SHOTGUN = true, GROUP_SNIPER = true, GROUP_HEAVY = true,
}

-- the killing blow, for the down report (the bone is cleared after every hit)
local lastHit = nil   -- { weapon, bone, region, attacker, sid, net, at }

-- GTA death handling (defined in the GTA DEATH section below)
local downing = false
local handleDeath

-- A fatal hit wakes the death check at once, so the idle death watcher can sleep 500 ms.
-- Polls every 50 ms for up to 1.5 s until GTA has really killed the ped (also across a
-- resurrect still in progress); deaths without a damage event (a script setting health 0)
-- are caught by the watcher.
local deathKick = false
local function kickDeathCheck()
    if deathKick then return end
    deathKick = true
    CreateThread(function()
        local t = GetGameTimer()
        while GetGameTimer() - t < 1500 do
            local ped = PlayerPedId()
            if not downing and (IsEntityDead(ped) or IsPedDeadOrDying(ped, true)) then
                handleDeath(ped)
                break
            end
            Wait(50)
        end
        deathKick = false
    end)
end

local function onDamage(ped, args)
    local attacker = args[2]
    local weapon = s32(args[7] or 0)
    if weapon == 0 then weapon = s32(GetPedCauseOfDeath(ped)) end

    local hp, ar = GetEntityHealth(ped), GetPedArmour(ped)
    local fatal = hp <= 100 or IsEntityDead(ped)
    if fatal then kickDeathCheck() end
    local dmg = math.max(0, base.hp - math.max(hp, 100))
    local arm = math.max(0, base.ar - ar)
    base.hp, base.ar, base.pendingSince = hp, ar, nil

    local okBone, bone = GetPedLastDamageBone(ped)
    if not okBone then bone = 0 end
    ClearPedLastDamageBone(ped)

    local group = weaponGroup(weapon)
    -- the event's own melee flag moved between game builds; the weapon group never lies
    local melee = group == 'GROUP_UNARMED' or group == 'GROUP_MELEE'
    local sid, net = attackerInfo(ped, attacker)
    local region = regionFor(ped, bone, weapon, attacker)
    lastHit = { weapon = weapon, bone = bone, region = region, attacker = attacker, sid = sid, net = net, at = GetGameTimer() }

    -- continuous sources are reported by their own ticks
    if FIRE_WEAPONS[weapon] and IsEntityOnFire(ped) then
        fireAcc = fireAcc + dmg
        return
    end
    if DROWN_WEAPONS[weapon] then
        drownAcc = drownAcc + dmg
        return
    end

    queue({
        weapon = weapon, group = group, bone = bone, region = region,
        damage = dmg, armour = arm, hits = 1, attacker = sid, attackerNet = net,
        melee = melee == true, fatal = fatal or nil,
        attacker_is_gun = GUN_GROUPS[group or ''] or nil,
    })
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or type(args) ~= 'table' then return end
    local ped = PlayerPedId()
    if args[1] ~= ped then return end
    onDamage(ped, args)
end)

-- ════════════════════════════════════════════════════════════════════════
-- SEATBELT
-- ════════════════════════════════════════════════════════════════════════

local BELT_BAGS = { 'seatbelt', 'seatbeltOn', 'isSeatbeltOn', 'harness', 'belt' }
local qbBelt = false

-- qb-smallresources / ps-hud style toggle event
AddEventHandler('seatbelt:client:ToggleSeatbelt', function(state)
    if type(state) == 'boolean' then qbBelt = state else qbBelt = not qbBelt end
end)

function D.IsBelted(ped, veh)
    ped = ped or PlayerPedId()
    veh = veh or GetVehiclePedIsIn(ped, false)
    if veh == 0 then return false end
    local class = GetVehicleClass(veh)
    if class == 8 or class == 13 then return false end   -- motorcycles, bicycles

    local cfg = Config.Damage and Config.Damage.vehicle and Config.Damage.vehicle.seatbeltExport
    if type(cfg) == 'function' then
        local ok, res = pcall(cfg)
        if ok and res ~= nil then return res == true end
    elseif type(cfg) == 'table' and cfg.resource and cfg.fn and GetResourceState(cfg.resource) == 'started' then
        local ok, res = pcall(function() return exports[cfg.resource][cfg.fn]() end)
        if ok and res ~= nil then return res == true end
    end

    local st = LocalPlayer.state
    for i = 1, #BELT_BAGS do
        local v = st[BELT_BAGS[i]]
        if v ~= nil then return v == true end
    end

    if GetResourceState('qb-smallresources') == 'started' then
        local ok, res = pcall(function() return exports['qb-smallresources']:HasHarness() end)
        if ok and res then return true end
    end
    if qbBelt then return true end

    -- universal fallback: seatbelt scripts turn off "can fly through windscreen" (flag 32)
    return GetPedConfigFlag(ped, 32, true) == false
end

-- ════════════════════════════════════════════════════════════════════════
-- FALLS
-- ════════════════════════════════════════════════════════════════════════

local function airborne(ped)
    if IsPedInAnyVehicle(ped, false) then return false end
    if IsPedFalling(ped) or IsPedInParachuteFreeFall(ped) then return true end
    return IsPedRagdoll(ped) and IsEntityInAir(ped)
end

local function fallRegion(height)
    local frac = (Config.Damage.fall and Config.Damage.fall.fractureHeight) or 7.0
    local pool = { 'l_lower_leg', 'r_lower_leg', 'l_lower_leg', 'r_lower_leg', 'l_upper_leg', 'r_upper_leg' }
    if height >= frac then pool[#pool + 1] = 'pelvis' end
    if height >= frac * 1.5 then pool[#pool + 1] = 'back'; pool[#pool + 1] = 'l_lower_arm'; pool[#pool + 1] = 'r_lower_arm' end
    return pool[math.random(#pool)]
end

local function onLanded(ped, height)
    local minH = (Config.Damage.fall and Config.Damage.fall.minHeight) or 4.0
    if IsEntityInWater(ped) or IsPedSwimming(ped) then
        if height < 20.0 then return end
        height = height * 0.3                        -- water breaks the fall
    end
    if height < minH then return end
    local fall = { h = height, at = GetGameTimer(), reported = false }
    lastFall = fall
    -- if GTA did not hurt us (no WEAPON_FALL damage event) report the height on its own
    SetTimeout(450, function()
        if fall.reported then return end
        fall.reported = true
        send({ weapon = W.FALL, group = nil, bone = 0, region = fallRegion(height), damage = 0, armour = 0,
               hits = 1, attacker = 0, melee = false, fall = U.round(height, 1) })
    end)
end

-- on the ground: poll every 150 ms only when a fall is likely to start, else every 500 ms
local function fallLikely(ped)
    if IsPedJumpingOutOfVehicle(ped) then return true end
    if IsPedInAnyVehicle(ped, false) then return false end
    if IsPedJumping(ped) or IsPedClimbing(ped) or IsPedVaulting(ped) or IsPedRagdoll(ped) then return true end
    return not IsEntityInWater(ped) and GetEntityHeightAboveGround(ped) > 1.5
end

local GRAVITY = 9.81

CreateThread(function()
    local top = nil
    local lastPoll = GetGameTimer()
    while true do
        local ped = PlayerPedId()
        if airborne(ped) then
            local z = GetEntityCoords(ped).z
            local chute = GetPedParachuteState(ped)
            if not top then
                -- add the drop already fallen before this first airborne poll: free-fall height
                -- for the current sink speed, capped to what the time since the last ground poll
                -- (+ 0.1 s for GTA's fall task to start) allows
                top = z
                local vz = GetEntityVelocity(ped).z
                if vz < 0 then
                    local w = math.max(0, GetGameTimer() - lastPoll) / 1000 + 0.1
                    top = z + math.min(vz * vz / (2 * GRAVITY), 0.5 * GRAVITY * w * w)
                end
            end
            if z > top or chute == 1 or chute == 2 then top = z end   -- canopy open = slow descent
            Wait(0)
        else
            if top then
                local drop = top - GetEntityCoords(ped).z
                top = nil
                onLanded(ped, drop)
            end
            lastPoll = GetGameTimer()
            Wait(fallLikely(ped) and 150 or 500)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- VEHICLE CRASHES
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local lastSpeed, lastBody, lastEngine, lastVeh = nil, nil, nil, 0
    local cooldownUntil = 0
    while true do
        local vcfg = Config.Damage and Config.Damage.vehicle
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and vcfg and vcfg.enabled ~= false and enabled() then
            local speed = GetEntitySpeed(veh) * 3.6
            local body, engine = GetVehicleBodyHealth(veh), GetVehicleEngineHealth(veh)
            if veh == lastVeh and lastSpeed then
                local drop = lastSpeed - speed
                local now = GetGameTimer()
                if drop >= (vcfg.minSpeedDrop or 45.0) and now >= cooldownUntil then
                    local hit = HasEntityCollidedWithAnything(veh) or body < lastBody - 1.0 or engine < lastEngine - 1.0
                    if hit then
                        cooldownUntil = now + 1500
                        local crash = { drop = drop, belted = D.IsBelted(ped, veh), at = now, reported = false }
                        lastCrash = crash
                        -- no crash damage event from GTA within 400 ms → report the impact alone
                        SetTimeout(400, function()
                            if crash.reported then return end
                            crash.reported = true
                            send({ weapon = W.RAMMED, bone = 0, region = 'chest', damage = 0, armour = 0, hits = 1,
                                   attacker = 0, melee = false, speedDrop = U.round(crash.drop, 1),
                                   belted = crash.belted, seatbelt = crash.belted })
                        end)
                    end
                end
            end
            lastSpeed, lastBody, lastEngine, lastVeh = speed, body, engine, veh
            Wait(100)
        else
            if veh == 0 then qbBelt = false end
            lastSpeed, lastBody, lastEngine, lastVeh = nil, nil, nil, 0
            Wait(500)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- FIRE & DROWNING TICKS
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local nextFire, nextDrown = 0, 0
    while true do
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local fireCfg = Config.Damage and Config.Damage.fire or {}
        local drownCfg = Config.Damage and Config.Damage.drowning or {}

        -- fire
        if fireCfg.enabled ~= false and IsEntityOnFire(ped) and not IsEntityDead(ped) then
            if not burning then
                burning = true
                nextFire = now + (fireCfg.tick or 2000)
            elseif now >= nextFire then
                nextFire = now + (fireCfg.tick or 2000)
                send({ weapon = W.FIRE, bone = 0, region = U.weightedPick(FIRE_REGIONS), damage = fireAcc, armour = 0,
                       hits = 1, attacker = 0, melee = false, fire = true })
                fireAcc = 0
            end
        elseif burning then
            burning = false
            send({ weapon = W.FIRE, bone = 0, region = U.weightedPick(FIRE_REGIONS), damage = fireAcc, armour = 0,
                   hits = 1, attacker = 0, melee = false, fire = true })
            fireAcc = 0
        end

        -- drowning
        local under = false
        if drownCfg.enabled ~= false then
            if IsPedSwimmingUnderWater(ped) then
                under = true
            else
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and IsEntityInWater(veh) and GetEntitySubmergedLevel(veh) > 0.95 then under = true end
            end
        end
        if under and GetPlayerUnderwaterTimeRemaining(PlayerId()) <= 0.0 then
            if not drowning then
                drowning = true
                nextDrown = now
            end
            if now >= nextDrown then
                nextDrown = now + 2000
                send({ weapon = IsPedInAnyVehicle(ped, false) and W.DROWN_VEH or W.DROWN, bone = 0, region = 'chest',
                       damage = drownAcc, armour = 0, hits = 1, attacker = 0, melee = false, drown = true })
                drownAcc = 0
            end
        elseif drowning then
            drowning = false
            drownAcc = 0
        end

        Wait((burning or drowning or under) and 250 or 600)
    end
end)

-- Health changes that came without a damage event (scripts, regen, sync) move the baseline
CreateThread(function()
    Wait(0)
    D.SyncBaseline()
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local hp, ar = GetEntityHealth(ped), GetPedArmour(ped)
        -- healing / armour pickup: always safe to follow at once
        if hp > base.hp then base.hp = hp end
        if ar > base.ar then base.ar = ar end
        if hp < base.hp or ar < base.ar then
            -- a drop no damage event has explained yet: give the event a second to arrive
            local now = GetGameTimer()
            if not base.pendingSince then
                base.pendingSince = now
            elseif now - base.pendingSince > 1000 then
                base.hp, base.ar, base.pendingSince = hp, ar, nil
            end
        else
            base.pendingSince = nil
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- GTA DEATH → RESURRECT IN PLACE + nza:down
-- ════════════════════════════════════════════════════════════════════════

local lastDownAt = -60000
local resurrects = {}
local DEATH_FX = {
    'DeathFailOut', 'DeathFailMPIn', 'DeathFailMPDark', 'DeathFailNeutralIn',
    'DeathFailFranklinIn', 'DeathFailMichaelIn', 'DeathFailTrevorIn',
}

local function disableAutoSpawn()
    if GetResourceState('spawnmanager') ~= 'started' then return end
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
end

local function disableNativeRestart()
    PauseDeathArrestRestart(true)
    SetFadeOutAfterDeath(false)
    SetFadeInAfterDeathArrest(false)
end

local function vehicleSeat(veh, ped)
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        if GetPedInVehicleSeat(veh, seat) == ped then return seat end
    end
    return -1
end

-- Where to stand the body back up: next to the vehicle door, on the ground or the water surface
local function revivePosition(ped)
    local c = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    local inVehicle = veh ~= 0
    if inVehicle then
        local seat = vehicleSeat(veh, ped)
        local left = seat == -1 or seat == 1 or seat == 3
        local minDim, maxDim = GetModelDimensions(GetEntityModel(veh))
        local x = left and (minDim.x - 0.7) or (maxDim.x + 0.7)
        c = GetOffsetFromEntityInWorldCoords(veh, x, 0.0, 0.0)
        heading = GetEntityHeading(veh)
    end

    local x, y, z = c.x, c.y, c.z
    local water, wz = GetWaterHeight(x, y, z)
    if (IsEntityInWater(ped) or IsPedSwimming(ped) or (inVehicle and IsEntityInWater(veh))) and water and wz > z - 0.5 then
        z = wz + 0.2
    elseif inVehicle then
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
        if found then z = gz end
    end
    return vector3(x, y, z), heading, inVehicle
end

local function stopDeathEffects()
    for _, name in ipairs(DEATH_FX) do
        if AnimpostfxIsRunning(name) then AnimpostfxStop(name) end
    end
end

handleDeath = function(ped)
    if downing then return end
    downing = true

    local now = GetGameTimer()
    for i = #resurrects, 1, -1 do
        if now - resurrects[i] > 15000 then table.remove(resurrects, i) end
    end
    if #resurrects >= 4 then Wait(1500 * (#resurrects - 3)) end   -- something keeps killing us: back off
    resurrects[#resurrects + 1] = GetGameTimer()

    -- cause, read before the ped is resurrected
    local weapon = s32(GetPedCauseOfDeath(ped))
    local killer = GetPedSourceOfDeath(ped)
    local okBone, bone = GetPedLastDamageBone(ped)
    if not okBone then bone = 0 end
    local recent = lastHit and GetGameTimer() - lastHit.at < 3000 and lastHit or nil
    if weapon == 0 and recent then weapon = recent.weapon end
    if (not killer or killer == 0) and recent then killer = recent.attacker end
    local sid, net = attackerInfo(ped, killer)
    local region
    if bone == 0 and recent then
        bone, region = recent.bone, recent.region
        if sid == 0 then sid, net = recent.sid, recent.net end
    else
        region = regionFor(ped, bone, weapon, killer)
    end
    local drowned = DROWN_WEAPONS[weapon] == true or IsPedSwimmingUnderWater(ped)

    -- let a falling body land first (max 2 s) so we do not resurrect in mid-air
    local t = GetGameTimer()
    while IsEntityInAir(ped) and not IsPedInAnyVehicle(ped, false) and GetGameTimer() - t < 2000 do Wait(50) end

    local pos, heading, wasInVehicle = revivePosition(ped)
    IgnoreNextRestart(true)
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading, 0, false)
    stopDeathEffects()

    local np = PlayerPedId()
    local maxHp = GetEntityMaxHealth(np)
    SetEntityHealth(np, math.floor(100 + (maxHp - 100) * 0.5))
    ClearPedTasksImmediately(np)
    D.SyncBaseline()

    local alive = not (NZA.Self and NZA.Self.State) or NZA.Self.State() == 'alive'
    if alive then
        -- fall over naturally until the wounded module takes over (state bag arrives in ~250 ms)
        SetPedToRagdoll(np, 2500, 2500, 0, false, false, false)
        if GetGameTimer() - lastDownAt > 5000 then
            lastDownAt = GetGameTimer()
            flush()   -- injuries first, then the down report
            local info = {
                weapon = weapon, weaponName = D.WeaponName(weapon), group = weaponGroup(weapon),
                attacker = sid, attackerNet = net, region = region, bone = bone,
                drown = drowned or nil, vehicle = wasInVehicle or nil,
                fall = (weapon == W.FALL and lastFall and GetGameTimer() - lastFall.at < 3000) and U.round(lastFall.h, 1) or nil,
                fire = FIRE_WEAPONS[weapon] or nil,
            }
            TriggerServerEvent('nza:down', info)
            NZA.Bus.Emit('self:down', info)
            NZA.Debug('down', info)
        end
    end
    -- the ped stands again after a resurrect: modules that hold a pose (wounded) re-apply it
    NZA.Bus.Emit('self:resurrected', alive)

    Wait(500)
    downing = false
end

CreateThread(function()
    Wait(0)
    disableAutoSpawn()
    disableNativeRestart()
    while true do
        local ped = PlayerPedId()
        if not downing and (IsEntityDead(ped) or IsPedDeadOrDying(ped, true)) then
            handleDeath(ped)
        end
        -- fatal hits wake handleDeath at once (kickDeathCheck); this catches the rest
        Wait(downing and 250 or 500)
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'spawnmanager' then disableAutoSpawn() end
end)

CreateThread(function()
    Wait(0)
    if Bridge and Bridge.OnPlayerLoaded then
        Bridge.OnPlayerLoaded(function()
            -- frameworks sometimes re-enable auto spawn while loading the character
            CreateThread(function()
                Wait(2000)
                disableAutoSpawn()
                disableNativeRestart()
                D.SyncBaseline()
            end)
        end)
    end
end)
