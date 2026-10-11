-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Team HUD feed: your own health, armour and weapon, who is talking (mic or radio), the shots you fire,
-- and pause-menu visibility. Light loops that only run while you're in a squad; the NUI only hears about changes.
local running = false
local talking = {}        -- [serverId] = false | 'mic' | 'radio'
local radioTalk = {}      -- [serverId] = true while pma-voice says they're transmitting

-- weapon hash -> name / label, shared with the vitals handler in main.lua
local weaponNames, weaponLabels = {}, {}
for _, name in ipairs(Data.Weapons) do
    local hash = GetHashKey(name) & 0xFFFFFFFF
    weaponNames[hash] = name
    weaponLabels[hash] = Data.WeaponLabels[name]
        or name:gsub('^WEAPON_', ''):gsub('_', ' '):lower():gsub('(%a)(%w*)', function(a, b) return a:upper() .. b end)
end

--- Weapon name and label for a hash, or false when unarmed / unknown.
function SquadWeapon(hash)
    hash = tonumber(hash)
    if not hash or hash == 0 then return false, nil end
    local h = hash & 0xFFFFFFFF
    return weaponNames[h] or false, weaponLabels[h]
end

-- vehicle model -> kind (for the icon) and display name
local vehicles = {}
local KIND = { [8] = 'bike', [13] = 'bicycle', [14] = 'boat', [15] = 'heli', [16] = 'plane', [10] = 'truck', [11] = 'truck', [20] = 'truck', [21] = 'train' }

--- Vehicle kind ('car' | 'truck' | 'bike' | 'bicycle' | 'boat' | 'plane' | 'heli' | 'train') and name for a model, or false.
function SquadVehicle(model)
    model = tonumber(model)
    if not model or model == 0 then return false, nil end
    local c = vehicles[model]
    if not c then
        local disp = GetDisplayNameFromVehicleModel(model)
        local label = GetLabelText(disp)
        if not label or label == 'NULL' or label == '' then
            label = disp ~= 'CARNOTFOUND' and (disp:sub(1, 1):upper() .. disp:sub(2):lower()) or 'Vehicle'
        end
        c = { KIND[GetVehicleClassFromName(model)] or 'car', label }
        vehicles[model] = c
    end
    return c[1], c[2]
end

--- Clip, clip size and total rounds for the weapon in hand (nil when it doesn't use ammo).
local function ammoOf(ped, w)
    if not w or w == 0 or not IsPedArmed(ped, 4) then return nil end
    local max = GetMaxAmmoInClip(ped, w, true)
    if not max or max <= 0 then return nil end
    local _, clip = GetAmmoInClip(ped, w)
    return clip or 0, max, GetAmmoInPedWeapon(ped, w)
end

-- ─── hits ──────────────────────────────────────────────────
-- Taking damage flashes your card on everyone's team HUD. Throttled; one tiny event per hit burst.
local lastHit, hitSent = 0, 0
local function hit(dmg)
    local now = GetGameTimer()
    if now - lastHit < 150 then return end
    lastHit = now
    if Settings.hud and Settings.hudHits ~= false and Settings.hudShowSelf ~= false then
        NUI('hit', { id = Me(), d = dmg })
    end
    if now - hitSent >= 200 then
        hitSent = now
        TriggerServerEvent('nz_squads:hit', math.floor(dmg or 0))
    end
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not Squad or args[1] ~= cache.ped then return end
    hit(10)
end)

RegisterNetEvent('nz_squads:hit', function(src, dmg)
    if not Squad or not Settings.hud or Settings.hudHits == false then return end
    NUI('hit', { id = src, d = dmg })
end)

RegisterNetEvent('nz_squads:reviving', function(target, by, ms)
    if not Squad or not Settings.hud then return end
    NUI('reviving', { id = target, by = by, ms = ms })
end)

local function healthPct(ped)
    local hp, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
    if max <= 100 then return hp > 0 and 100 or 0 end
    return math.floor(math.max(0, math.min(1, (hp - 100) / (max - 100))) * 100)
end

local function talkState(id, isMe)
    if radioTalk[id] then return 'radio' end
    if isMe then return NetworkIsPlayerTalking(PlayerId()) and 'mic' or false end
    local player = GetPlayerFromServerId(id)
    return player ~= -1 and NetworkIsPlayerTalking(player) and 'mic' or false
end

local function pushTalk(id, t)
    if talking[id] == t then return end
    talking[id] = t
    if Settings.hud and Settings.hudTalking then NUI('talking', { [tostring(id)] = t }) end
end

-- pma-voice: radio transmissions reach everyone on the channel, so squadmates light up wherever they are
RegisterNetEvent('pma-voice:setTalkingOnRadio', function(src, on)
    radioTalk[src] = on and true or nil
    if Squad then pushTalk(src, talkState(src, src == Me())) end
end)
AddEventHandler('pma-voice:radioActive', function(on)
    local me = Me()
    radioTalk[me] = on and true or nil
    if Squad then pushTalk(me, talkState(me, true)) end
end)

local function loop()
    if running then return end
    running = true
    CreateThread(function()
        local paused = nil
        local selfH, selfA, selfW, selfVeh, selfSeat, selfClip, selfMax, selfTotal = -1, -1, -1, -1, nil, -1, -1, -1

        while Squad and SquadsConfig.Features.Hud do
            local p = IsPauseMenuActive()
            if p ~= paused then
                paused = p
                NUI('hudHidden', p)
            end

            if Settings.hud and not p then
                -- your own card: read locally every 250 ms (the squad sync also carries yours, but it's older)
                local ped = cache.ped
                local h, a, w = healthPct(ped), GetPedArmour(ped), GetSelectedPedWeapon(ped)
                local veh = cache.vehicle or 0
                local model = veh ~= 0 and GetEntityModel(veh) or 0
                local seat = veh ~= 0 and (GetPedInVehicleSeat(veh, -1) == ped and 'd' or 'p') or nil
                local clip, max, total = ammoOf(ped, w)
                clip, max, total = clip or 0, max or 0, total or 0

                -- lost health or armour since the last look (falls, fire, bullets the damage event missed)
                if selfH >= 0 and (h < selfH or a < selfA) then hit((selfH - h) + (selfA - a)) end

                if h ~= selfH or a ~= selfA or w ~= selfW or model ~= selfVeh or seat ~= selfSeat
                    or clip ~= selfClip or max ~= selfMax or total ~= selfTotal then
                    selfH, selfA, selfW, selfVeh, selfSeat = h, a, w, model, seat
                    selfClip, selfMax, selfTotal = clip, max, total
                    local name, label = SquadWeapon(w)
                    local kind, vname = SquadVehicle(model)
                    NUI('selfVitals', { h = h, a = a, w = name, wl = label, c = clip, m = max, t = total,
                        vk = kind, vn = vname, vs = seat or false })
                end

                if Settings.hudTalking then
                    local me = Me()
                    for i = 1, #Squad.members do
                        local m = Squad.members[i]
                        -- offline members have no server id; skip them instead of indexing with nil
                        if m.online and m.id then pushTalk(m.id, talkState(m.id, m.id == me)) end
                    end
                end
            end
            Wait(250)
        end
        running = false
        talking = {}
    end)
end

-- ─── shot feed ─────────────────────────────────────────────
-- Times every shot you fire so squadmates' cards flash in step with the gunfire they hear.
-- Idle cost: one IsPedArmed every 250 ms. Per-frame checks only run while you're aiming or firing.
local Shots = SquadsConfig.TeamHudShots or {}
local shotsRunning = false

local function othersOnline()
    local me = Me()
    for i = 1, #Squad.members do
        local m = Squad.members[i]
        if m.online and m.id and m.id ~= me then return true end
    end
    return false
end

local function shotLoop()
    if shotsRunning or Shots.Enabled == false then return end
    shotsRunning = true
    CreateThread(function()
        local batchMs = Shots.BatchMs or 100
        local burst, t0, lastShot, lastFlush, fresh = 0, 0, -10000, 0, false
        local pending = {}
        local hotUntil, lastW, lastAmmo = 0, 0, -1
        local playerId = PlayerId()
        local sentAmmo, ammoAt = '', 0

        -- squadmates see your clip / reserve (and RELOAD / EMPTY); sent when it changes, at most every 600 ms
        local function reportAmmo(now, ped, w)
            if now - ammoAt < 600 or not othersOnline() then return end
            local clip, max, total = ammoOf(ped, w)
            local key = clip and ('%d:%d:%d'):format(clip, max, total) or 'none'
            if key == sentAmmo then return end
            ammoAt, sentAmmo = now, key
            TriggerServerEvent('nz_squads:ammo', clip or 0, max or 0, total or 0)
        end

        local function flush(now)
            if #pending == 0 then return end
            if othersOnline() then TriggerServerEvent('nz_squads:shots', burst, pending) end
            pending, lastFlush, fresh = {}, now, false
        end

        local function record(now, count, weapon)
            if now - lastShot > (Shots.BurstGapMs or 700) then
                flush(now)
                burst, t0, fresh = (burst + 1) % 65536, now, true
            end
            lastShot = now
            local spacing = count > 1 and 90 or 0
            local own = {}
            for i = 1, count do
                pending[#pending + 1] = now - t0 + (i - 1) * spacing
                own[i] = (i - 1) * spacing
            end
            -- your own card flashes straight away
            if Settings.hud and Settings.hudShots ~= false and Settings.hudShowSelf ~= false then
                NUI('shots', { id = Me(), b = -1, o = own })
            end
            -- first shot of a burst goes out at once, the rest ride in small batches
            if fresh or now - lastFlush >= batchMs then flush(now) end
        end

        while Squad and SquadsConfig.Features.Hud do
            local ped = cache.ped
            if IsPedArmed(ped, 4) then
                local now = GetGameTimer()
                local w = GetSelectedPedWeapon(ped)
                if w ~= lastW then lastW, lastAmmo = w, GetAmmoInPedWeapon(ped, w) end

                -- per-frame shot timing only matters when someone will see it (your own card, or squadmates online)
                if (Settings.hud or othersOnline())
                    and (IsPlayerFreeAiming(playerId) or IsControlPressed(0, 24) or IsControlPressed(0, 69) or IsControlPressed(0, 92)) then
                    hotUntil = now + 900
                end

                if now < hotUntil then
                    if IsPedShooting(ped) then
                        record(now, 1, w)
                        lastAmmo = GetAmmoInPedWeapon(ped, w)
                    elseif #pending > 0 and now - lastFlush >= batchMs then
                        flush(now)
                    end
                    Wait(0)
                else
                    -- a quick tap between polls: count it from the ammo instead
                    local ammo = GetAmmoInPedWeapon(ped, w)
                    if lastAmmo > ammo and ammo >= 0 then record(now, math.min(lastAmmo - ammo, 6), w) end
                    lastAmmo = ammo
                    flush(now)
                    reportAmmo(now, ped, w)
                    Wait(100)
                end
                if now < hotUntil then reportAmmo(now, ped, w) end
            else
                if sentAmmo ~= 'none' and sentAmmo ~= '' and othersOnline() then
                    sentAmmo, ammoAt = 'none', GetGameTimer()
                    TriggerServerEvent('nz_squads:ammo', 0, 0, 0)
                end
                lastW, lastAmmo = 0, -1
                if #pending > 0 then flush(GetGameTimer()) end
                Wait(250)
            end
        end
        shotsRunning = false
    end)
end

RegisterNetEvent('nz_squads:shots', function(src, burst, offsets)
    if not Squad or not Settings.hud or Settings.hudShots == false then return end
    NUI('shots', { id = src, b = burst, o = offsets })
end)

AddEventHandler('nz_squads:client:changed', function(_, now)
    if now then
        loop()
        if SquadsConfig.Features.Hud then shotLoop() end
    end
end)
