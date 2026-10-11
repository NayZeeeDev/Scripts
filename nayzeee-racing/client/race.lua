if not NAYZEEE_LOCK_OK then return end

--[[
    Race client: gate visuals (posts, blips, GPS, 3D billboards), crossing detection,
    ghost mode, drift scoring, respawn and street clutter cleanup.
    One thread while racing, nothing running when you are not.
]]

Race = { phase = nil }   -- nil | mobilize | countdown | racing | done
local R = nil            -- current race data
local holding = false    -- respawn key held

local accent = { 8, 175, 162 }
do
    local h = (Config.UI.Accent or '#08afa2'):gsub('#', '')
    accent = { tonumber(h:sub(1, 2), 16) or 8, tonumber(h:sub(3, 4), 16) or 175, tonumber(h:sub(5, 6), 16) or 162 }
end

function Race.Busy() return R ~= nil and Race.phase ~= 'done' end

-- ── DUI billboards ──────────────────────────────────────────────────────
local dui = { obj = nil, txd = 'nzr_dui', tex = 'gates', ready = false, last = '' }
local SLOTS = 5

local function duiInit()
    if dui.obj then return end
    dui.obj = CreateDui(('nui://%s/web/dui.html'):format(NZR.Resource), 1920, 384)
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while not IsDuiAvailable(dui.obj) and GetGameTimer() < deadline do Wait(50) end
        local txd = CreateRuntimeTxd(dui.txd)
        CreateRuntimeTextureFromDuiHandle(txd, dui.tex, GetDuiHandle(dui.obj))
        SendDuiMessage(dui.obj, json.encode({ accent = Config.UI.Accent, label = L('HUD_CHECKPOINT'), finish = L('HUD_FINISH'), units = Settings.units }))
        dui.ready = true
    end)
end

local function duiSend(slots)
    if not dui.ready then return end
    local s = json.encode(slots)
    if s == dui.last then return end
    dui.last = s
    SendDuiMessage(dui.obj, s)
end

-- Billboard facing the camera (yaw only), drawn from one slot of the atlas
local function billboard(slot, c, camRight, dist, scale)
    local size = math.max(1.8, dist * 0.11) * scale
    local hw = size * 0.5
    local hh = hw
    local lift = 1.2 + math.min(dist, 250.0) * 0.12
    local cx, cy, cz = c.x, c.y, c.z + lift + hh
    local rx, ry = camRight.x * hw, camRight.y * hw
    local u0, u1 = slot / SLOTS, (slot + 1) / SLOTS
    local tlx, tly, tlz = cx - rx, cy - ry, cz + hh
    local trx, try, trz = cx + rx, cy + ry, cz + hh
    local blx, bly, blz = cx - rx, cy - ry, cz - hh
    local brx, bry, brz = cx + rx, cy + ry, cz - hh
    DrawSpritePoly(tlx, tly, tlz, blx, bly, blz, trx, try, trz, 255, 255, 255, 255, dui.txd, dui.tex, u0, 0.0, 1.0, u0, 1.0, 1.0, u1, 0.0, 1.0)
    DrawSpritePoly(trx, try, trz, blx, bly, blz, brx, bry, brz, 255, 255, 255, 255, dui.txd, dui.tex, u1, 0.0, 1.0, u0, 1.0, 1.0, u1, 1.0, 1.0)
    DrawSpritePoly(trx, try, trz, blx, bly, blz, tlx, tly, tlz, 255, 255, 255, 255, dui.txd, dui.tex, u1, 0.0, 1.0, u0, 1.0, 1.0, u0, 0.0, 1.0)
    DrawSpritePoly(brx, bry, brz, blx, bly, blz, trx, try, trz, 255, 255, 255, 255, dui.txd, dui.tex, u1, 1.0, 1.0, u0, 1.0, 1.0, u1, 0.0, 1.0)
    local col = slot == 0 and accent or { 255, 255, 255 }
    DrawLine(c.x, c.y, c.z + 0.2, cx, cy, cz - hh, col[1], col[2], col[3], slot == 0 and 220 or 120)
end

-- ── world visuals for gates ─────────────────────────────────────────────
local posts, blips = {}, {}

local function spawnPost(model, p)
    local obj = CreateObjectNoOffset(model, p.x, p.y, p.z, false, false, false)
    SetEntityCollision(obj, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityAlpha(obj, 215, false)
    return obj
end

local function clearGate(k)
    if posts[k] then for _, o in ipairs(posts[k]) do if DoesEntityExist(o) then DeleteEntity(o) end end posts[k] = nil end
    if blips[k] then RemoveBlip(blips[k]) blips[k] = nil end
end

local function showGate(k)
    if not R or posts[k] or not R.route[k] then return end
    local idx = R.route[k]
    local g = R.gates[idx]
    local finish = k == #R.route
    local model = joaat((idx == 1 or finish) and Config.Trackbuilder.StartpointModel or Config.Trackbuilder.CheckpointModel)
    if lib.requestModel(model, 2000) then
        posts[k] = { spawnPost(model, g.left), spawnPost(model, g.right) }
    end
    local b = AddBlipForCoord(g.center.x, g.center.y, g.center.z)
    SetBlipSprite(b, finish and 38 or 1)
    SetBlipColour(b, Config.UI.BlipColor)
    SetBlipScale(b, k == R.k + 1 and 1.0 or 0.75)
    if not finish then ShowNumberOnBlip(b, k) end
    SetBlipAsShortRange(b, false)
    blips[k] = b
end

local function route()
    ClearGpsMultiRoute()
    if not R then SetGpsMultiRouteRender(false) return end
    StartGpsMultiRoute(Config.UI.RouteColor, true, true)
    for i = R.k + 1, math.min(R.k + 2, #R.route) do
        local g = R.gates[R.route[i]]
        AddPointToGpsMultiRoute(g.center.x, g.center.y, g.center.z)
    end
    SetGpsMultiRouteRender(true)
end

local function refreshGates()
    for k in pairs(posts) do if k <= R.k or k > R.k + 2 then clearGate(k) end end
    for k in pairs(blips) do if k <= R.k or k > R.k + 2 then clearGate(k) end end
    for k = R.k + 1, math.min(R.k + 2, #R.route) do showGate(k) end
    route()
end

local function clearAllGates()
    for k in pairs(posts) do clearGate(k) end
    for k in pairs(blips) do clearGate(k) end
    posts, blips = {}, {}
    ClearGpsMultiRoute()
    SetGpsMultiRouteRender(false)
    SetModelAsNoLongerNeeded(joaat(Config.Trackbuilder.CheckpointModel))
    SetModelAsNoLongerNeeded(joaat(Config.Trackbuilder.StartpointModel))
end

-- ── crossing test (2D segment intersection) ─────────────────────────────
local function crossed(a, b, g)
    local px, py = a.x, a.y
    local rx, ry = b.x - a.x, b.y - a.y
    local qx, qy = g.left.x, g.left.y
    local sx, sy = g.right.x - g.left.x, g.right.y - g.left.y
    local den = rx * sy - ry * sx
    if den == 0 then return false end
    local t = ((qx - px) * sy - (qy - py) * sx) / den
    local u = ((qx - px) * ry - (qy - py) * rx) / den
    return t >= 0 and t <= 1 and u >= 0 and u <= 1
end

-- ── ghost mode ──────────────────────────────────────────────────────────
local near = {}

local function ghostScan()
    if not R or not R.ghost then return end
    local me = cache.vehicle
    if not me then return end
    local pos = GetEntityCoords(me)
    local dist = Config.Races.Ghostmode.distance
    local seen = {}
    for _, net in ipairs(R.ghost) do
        if net ~= R.myNet and NetworkDoesEntityExistWithNetworkId(net) then
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent ~= 0 and ent ~= me then
                if #(GetEntityCoords(ent) - pos) < dist then
                    seen[ent] = true
                    if not near[ent] then SetEntityAlpha(ent, Config.Races.Ghostmode.alpha, false) end
                    near[ent] = GetPedInVehicleSeat(ent, -1)
                end
            end
        end
    end
    for ent in pairs(near) do
        if not seen[ent] then
            if DoesEntityExist(ent) then ResetEntityAlpha(ent) end
            near[ent] = nil
        end
    end
end

local function ghostFrame()
    local me = cache.vehicle
    if not me then return end
    local ped = cache.ped
    for ent, driver in pairs(near) do
        SetEntityNoCollisionEntity(me, ent, true)
        SetEntityNoCollisionEntity(ent, me, true)
        SetEntityNoCollisionEntity(ped, ent, true)
        if driver and driver ~= 0 then SetEntityNoCollisionEntity(me, driver, true) end
    end
end

local function ghostClear()
    for ent in pairs(near) do if DoesEntityExist(ent) then ResetEntityAlpha(ent) end end
    near = {}
end

-- ── clutter cleanup ─────────────────────────────────────────────────────
local onRoad = {}
for _, m in ipairs(Config.Races.Cleanup.OnRoadModels or {}) do onRoad[m] = true end

-- Spread over frames (40 objects per frame) so a big object pool never causes a spike
local pool, poolIdx = nil, 1
local function cleanup()
    if not pool then pool, poolIdx = GetGamePool('CObject'), 1 end
    local pos = GetEntityCoords(cache.ped)
    local r2 = Config.Races.Cleanup.Radius ^ 2
    local last = math.min(#pool, poolIdx + 39)
    for i = poolIdx, last do
        local obj = pool[i]
        if DoesEntityExist(obj) then
            local c = GetEntityCoords(obj)
            local dx, dy = c.x - pos.x, c.y - pos.y
            if dx * dx + dy * dy < r2 and not NetworkGetEntityIsNetworked(obj) and not IsEntityAttached(obj) and not IsEntityAMissionEntity(obj) then
                if (onRoad[GetEntityModel(obj)] and IsPointOnRoad(c.x, c.y, c.z, 0)) or HasObjectBeenBroken(obj) then
                    SetEntityAsMissionEntity(obj, true, true)
                    DeleteObject(obj)
                end
            end
        end
    end
    poolIdx = last + 1
    if poolIdx > #pool then pool = nil return true end
    return false
end

-- ── modded vehicle check ────────────────────────────────────────────────
-- Live power / top speed against the model's base handling. Returns reason, info or nil
local ignoreModels = {}
for _, m in ipairs(Config.AntiCheat.IgnoreModels or {}) do ignoreModels[m] = true end

local function modded(veh)
    local AC = Config.AntiCheat
    local model = GetEntityModel(veh)
    if ignoreModels[model] then return nil end
    if GetVehicleCheatPowerIncrease then
        local p = GetVehicleCheatPowerIncrease(veh)
        if p and p > 1.01 then return 'power', ('x%.2f'):format(p) end
    end
    if GetVehicleTopSpeedModifier then
        local m = GetVehicleTopSpeedModifier(veh)
        if m and m > (AC.MaxTopSpeedModifier or 0.0) + 0.01 then return 'topspeed', ('+%.1f'):format(m) end
    end
    local baseSpeed, speed = GetVehicleModelEstimatedMaxSpeed(model), GetVehicleEstimatedMaxSpeed(veh)
    if baseSpeed and baseSpeed > 0 and speed > baseSpeed * AC.SpeedTolerance then return 'speed', ('%.1f/%.1f'):format(speed, baseSpeed) end
    local baseAcc, acc = GetVehicleModelAcceleration(model), GetVehicleAcceleration(veh)
    if baseAcc and baseAcc > 0 and acc > baseAcc * AC.AccelTolerance then return 'accel', ('%.3f/%.3f'):format(acc, baseAcc) end
    return nil
end

local function modCheck()
    if not Config.AntiCheat.ModdedVehicles or not R or R.flagged then return end
    local veh = cache.vehicle
    if not veh or GetPedInVehicleSeat(veh, -1) ~= cache.ped then return end
    local reason, info = modded(veh)
    if reason then
        R.flagged = true
        TriggerServerEvent('nzr:race:flag', reason, info)
    end
end

-- ── drift score ─────────────────────────────────────────────────────────
local function driftTick(veh, dt)
    local v = GetEntityVelocity(veh)
    local speed = math.sqrt(v.x * v.x + v.y * v.y)
    if speed < 8.3 or GetVehicleCurrentGear(veh) == 0 or not IsVehicleOnAllWheels(veh) then return end
    local yaw = math.rad(GetEntityHeading(veh))
    local fx, fy = -math.sin(yaw), math.cos(yaw)
    local dot = (fx * v.x + fy * v.y) / speed
    if dot < 0 or dot > 0.966 then return end
    local angle = math.deg(math.acos(dot))
    R.drift = math.min(999999999, R.drift + angle * speed * dt * 0.6)
end

-- ── lifecycle ───────────────────────────────────────────────────────────
local function vec(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local function stopRace(keepHud)
    if not R or Race.phase == 'done' then return end
    Race.phase = 'done'
    holding = false
    pool = nil
    clearAllGates()
    ghostClear()
    duiSend({})
    -- unfreeze the car frozen for the countdown, even if we are no longer in it
    if R.frozen and DoesEntityExist(R.frozen) then FreezeEntityPosition(R.frozen, false) end
    R.frozen = nil
    if R.driftVeh and DoesEntityExist(R.driftVeh) then SetDriftTyresEnabled(R.driftVeh, false) end
    ClearLobbyMarkers()
    pcall(Config.Hud.OnRaceEnd)
    if not keepHud then UI('race', { phase = 'hide' }) end
end

local function endRace()
    stopRace(true)
    R = nil
    Race.phase = nil
end

local function passGate()
    R.k = R.k + 1
    local k = R.k
    TriggerServerEvent('nzr:race:gate', k)
    local finish = k >= #R.route
    local lapDone = R.circuit and R.route[k] == 1
    if not finish then
        PlaySound(lapDone and Config.Races.Sounds.Lap or Config.Races.Sounds.Checkpoint)
        R.lastGate = k
        refreshGates()
    else
        PlaySound(Config.Races.Sounds.Finish)
        clearAllGates()
    end
    if lapDone then R.lap = math.min(R.lap + 1, R.laps) end
    UI('race', { phase = 'progress', k = k, total = #R.route, lap = R.lap, laps = R.laps })
end

-- Own thread so the race loop (billboards, crossing) keeps running during the fade
local function respawn()
    if R.respawning then return end
    local veh = cache.vehicle
    if not veh or GetPedInVehicleSeat(veh, -1) ~= cache.ped then return end
    local race = R
    race.respawning = true
    CreateThread(function()
        local k = race.lastGate or 0
        local fromIdx = k > 0 and race.route[k] or 1
        local toIdx = race.route[k + 1] or race.route[#race.route]
        local from, to = race.gates[fromIdx].center, race.gates[toIdx].center
        DoScreenFadeOut(250)
        local t = GetGameTimer() + 600
        while not IsScreenFadedOut() and GetGameTimer() < t do Wait(0) end
        if R == race and Race.phase == 'racing' and DoesEntityExist(veh) then
            local heading = math.deg(math.atan(to.y - from.y, to.x - from.x)) - 90.0
            SetEntityCoords(veh, from.x, from.y, from.z + 0.5, false, false, false, false)
            SetEntityHeading(veh, heading)
            SetVehicleOnGroundProperly(veh)
            SetEntityVelocity(veh, 0.0, 0.0, 0.0)
            SetVehicleFixed(veh)
            race.lastPos = GetEntityCoords(veh)
            Wait(250)
            TriggerServerEvent('nzr:race:respawn')
            UI('race', { phase = 'respawned', penalty = Config.Races.Respawn.Penalty })
        end
        DoScreenFadeIn(350)
        race.respawning = false
    end)
end

-- Respawn key (hold)
if Config.Races.Respawn.Enabled then
    RegisterCommand('+nzr_respawn', function() if Race.phase == 'racing' then holding = true end end, false)
    RegisterCommand('-nzr_respawn', function() holding = false end, false)
    RegisterKeyMapping('+nzr_respawn', L('KEY_RESPAWN'), 'keyboard', Config.Races.Respawn.Key)
end

local function mainThread()
    CreateThread(function()
        local lastScan, lastClean, lastHud, lastDrift, lastWatch, lastMod = 0, 0, 0, 0, 0, 0
        local holdStart, lastRespawn, holdSent = nil, 0, 0
        local cleaning = false
        local lastFrame = GetGameTimer()
        local camRight = vector3(1.0, 0.0, 0.0)
        while R and Race.phase ~= 'done' do
            local now = GetGameTimer()
            local dt = (now - lastFrame) / 1000
            lastFrame = now
            local veh = cache.vehicle
            local racing = Race.phase == 'racing'

            -- ghost
            if R.ghost then
                if now - lastScan >= Config.Races.Ghostmode.scanInterval then lastScan = now ghostScan() end
                ghostFrame()
            end

            -- billboards
            if Settings.checkpointDui and dui.ready then
                local rot = GetFinalRenderedCamRot(2)
                local yaw = math.rad(rot.z)
                camRight = vector3(math.cos(yaw), math.sin(yaw), 0.0)
                local pos = GetEntityCoords(cache.ped)
                local count = Settings.checkpointDuiShowNext and math.max(1, math.min(SLOTS, Settings.checkpointDuiCount)) or 1
                local scale = (Settings.checkpointDuiScale or 60) / 60
                local slots = {}
                for i = 0, count - 1 do
                    local k = R.k + 1 + i
                    local idx = R.route[k]
                    if idx then
                        local c = R.gates[idx].center
                        local d = #(c - pos)
                        slots[i + 1] = { d = math.floor(d), f = k == #R.route, n = k }
                        billboard(i, c, camRight, d, scale)
                    end
                end
                if now - lastHud > 120 then duiSend(slots) end
            end

            if racing and veh then
                -- crossing
                local p = GetEntityCoords(veh)
                local idx = R.route[R.k + 1]
                if idx and R.lastPos then
                    local g = R.gates[idx]
                    if #(p - g.center) < 60.0 and crossed(R.lastPos, p, g) then
                        if GetPedInVehicleSeat(veh, -1) ~= cache.ped then
                            TriggerServerEvent('nzr:race:dq', 'vehicle')
                        else
                            passGate()
                        end
                    end
                end
                R.lastPos = p
                if Config.Debug and idx then
                    local g = R.gates[idx]
                    DrawLine(g.left.x, g.left.y, g.left.z + 1.0, g.right.x, g.right.y, g.right.z + 1.0, 255, 0, 0, 255)
                end

                if R.mode == RaceMode.DRIFT then driftTick(veh, dt) end

                -- respawn hold (HUD updated at most every 50ms, not every frame)
                if holding then
                    holdStart = holdStart or now
                    local pct = (now - holdStart) / Config.Races.Respawn.HoldMs
                    if now - holdSent >= 50 or pct >= 1 then
                        holdSent = now
                        UI('race', { phase = 'hold', pct = math.min(1, pct) })
                    end
                    if pct >= 1 then
                        holding, holdStart = false, nil
                        UI('race', { phase = 'hold', pct = 0 })
                        if now - lastRespawn >= Config.Races.Respawn.Cooldown then
                            lastRespawn = now
                            respawn()
                        else
                            UI('race', { phase = 'cooldown' })
                        end
                    end
                elseif holdStart then
                    holdStart = nil
                    UI('race', { phase = 'hold', pct = 0 })
                end
            end

            -- HUD feed (speed / drift) ~8 times a second
            if now - lastHud > 120 then
                lastHud = now
                local speed = veh and GetEntitySpeed(veh) or 0.0
                UI('race', { phase = 'tick', speed = math.floor(speed * (Settings.units == 'mph' and 2.236936 or 3.6)),
                    drift = R.mode == RaceMode.DRIFT and math.floor(R.drift) or nil })
            end
            if racing and R.mode == RaceMode.DRIFT and now - lastDrift > 1000 then
                lastDrift = now
                TriggerServerEvent('nzr:race:drift', math.floor(R.drift))
            end

            -- watchdog + cleanup
            if racing and now - lastWatch > 500 then
                lastWatch = now
                if IsEntityDead(cache.ped) then TriggerServerEvent('nzr:race:dq', 'dead') end
            end
            if racing and Config.Races.Cleanup.Enable and (cleaning or now - lastClean > 1500) then
                lastClean = now
                cleaning = not cleanup()
            end
            if (racing or Race.phase == 'countdown') and now - lastMod > 5000 then
                lastMod = now
                modCheck()
            end
            Wait(0)
        end
    end)
end

-- ── server events ───────────────────────────────────────────────────────
local handlers = {}

function handlers.mobilize(d)
    if App.open then CloseApp() end
    if Spectate and Spectate.on then Spectate.Stop(true) end
    if Builder and Builder.active then Builder.Stop(false) end
    ClearLobbyMarkers()
    local gates = {}
    for i, g in ipairs(d.gates) do gates[i] = { left = vec(g.left), center = vec(g.center), right = vec(g.right) } end
    R = {
        id = d.id, mode = d.mode, circuit = d.circuit, laps = d.circuit and d.laps or 1, lap = 1, gates = gates, route = d.route,
        k = 0, drift = 0, ghost = d.ghost, myNet = d.myNet, practice = d.practice,
    }
    Race.phase = 'mobilize'
    pcall(Config.Hud.OnRaceStart)
    if Settings.checkpointDui then duiInit() end
    refreshGates()
    UI('race', {
        phase = 'mobilize', name = d.name, track = d.track, mode = d.mode, type = d.type, laps = R.laps, circuit = d.circuit,
        total = #d.route, racers = d.racers, me = d.me, pb = d.pb, ms = d.mobilizeMs, settings = Settings, practice = d.practice, pinkSlip = d.pinkSlip,
    })
    mainThread()
end

function handlers.countdown(ms)
    if not R then return end
    Race.phase = 'countdown'
    if Config.Races.FreezeDuringCountdown and cache.vehicle then
        FreezeEntityPosition(cache.vehicle, true)
        R.frozen = cache.vehicle
    end
    UI('race', { phase = 'countdown', ms = ms })
    CreateThread(function()
        local steps = math.floor(ms / 1000)
        for _ = 1, steps do
            if Race.phase ~= 'countdown' then return end
            PlaySound(Config.Races.Sounds.Countdown)
            Wait(1000)
        end
    end)
end

function handlers.start()
    if not R then return end
    if R.frozen and DoesEntityExist(R.frozen) then FreezeEntityPosition(R.frozen, false) end
    R.frozen = nil
    local veh = cache.vehicle
    if veh then
        if R.mode == RaceMode.DRIFT and Config.Races.ToggleVehicleDrift and not GetDriftTyresEnabled(veh) then
            SetDriftTyresEnabled(veh, true)
            R.driftVeh = veh
        end
        R.lastPos = GetEntityCoords(veh)
    end
    Race.phase = 'racing'
    PlaySound(Config.Races.Sounds.Start)
    UI('race', { phase = 'start' })
end

function handlers.lap(d) UI('race', { phase = 'lap', time = d.time, best = d.best, lap = d.lap }) end
function handlers.deadline(ms) UI('race', { phase = 'deadline', ms = ms }) end
function handlers.split(d) if R and Settings.showSplits then UI('race', { phase = 'split', k = d.k, pb = d.pb, wr = d.wr }) end end
function handlers.eliminated(d) UI('race', { phase = 'eliminated', alias = d.alias, lap = d.lap }) end

function handlers.resync(k)
    if not R then return end
    R.k = k
    refreshGates()
    UI('race', { phase = 'progress', k = k, total = #R.route, lap = R.lap, laps = R.laps })
end

-- Banner for a few seconds, then watch the rest of the field (or the HUD goes away).
-- The results card arrives when everyone is done.
local function wrapUp()
    local mine = R
    SetTimeout(3500, function()
        if R ~= mine or Race.phase ~= 'done' then return end
        local id = R.id
        endRace()
        local watch = Config.Spectate.Enabled and Config.Spectate.AutoOnFinish and Settings.autoSpectate and not mine.practice and not mine.results
        local res = watch and lib.callback.await('nzr:req', false, 'lobby:spectate', { id = id })
        if not (res and res.data) and not (Spectate and Spectate.on) and not mine.results then UI('race', { phase = 'hide' }) end
    end)
end

function handlers.finished(result)
    if not R then return end
    stopRace(true)
    UI('race', { phase = 'finished', result = result })
    wrapUp()
end

function handlers.dq(reason)
    if not R then return end
    stopRace(true)
    PlaySound(Config.Races.Sounds.DNF)
    UI('race', { phase = 'dnf', reason = reason })
    wrapUp()
end

-- Practice: press the retry key while the results card is up to run it again
local function practiceRetry(p)
    local key = Config.Practice.RetryKey
    if not key then return end
    CreateThread(function()
        local untilT = GetGameTimer() + Config.Races.ResultsTime
        while GetGameTimer() < untilT and not Race.Busy() do
            if IsControlJustPressed(0, key) and not App.open then
                local res = StartPractice({ trackId = p.trackId, laps = p.laps, mode = p.mode })
                if res and res.error then Config.Notify(L(res.error), 'error') end
                return
            end
            Wait(0)
        end
    end)
end

function handlers.results(d)
    -- results of an earlier race while we are already racing the next one: just the card
    if R and d.id and R.id ~= d.id and Race.Busy() then
        UI('results', { results = d.results, me = d.me, track = d.track, lobby = d.lobby, ms = Config.Races.ResultsTime })
        return
    end
    if R then
        R.results = true
        if Race.phase ~= 'done' then stopRace(true) end
    end
    if Spectate and Spectate.on then Spectate.Stop(true) end
    UI('race', { phase = 'hide' })
    UI('results', { results = d.results, me = d.me, track = d.track, lobby = d.lobby, ms = Config.Races.ResultsTime,
        practice = d.practice ~= nil, retryKey = Config.Practice.RetryKey and true or false })
    if d.practice then practiceRetry(d.practice) end
end

function handlers.positions(board)
    if R then UI('race', { phase = 'positions', board = board }) end
    if Spectate and Spectate.on then Spectate.Board(board) end
end

RegisterNetEvent('nzr:race', function(event, data)
    local fn = handlers[event] or LobbyEvents[event] or (SpectateEvents and SpectateEvents[event])
    if fn then fn(data) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    if R then stopRace() end
    if dui.obj then DestroyDui(dui.obj) end
end)
