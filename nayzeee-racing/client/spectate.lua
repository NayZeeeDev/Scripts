if not NAYZEEE_LOCK_OK then return end

--[[
    Spectate: chase camera on a racer of a live lobby. The server sends where every racer is
    (feed) so the camera can follow cars that are not streamed in yet. One thread while watching,
    nothing running otherwise.
]]

Spectate = { on = false }
SpectateEvents = {}

local SP = nil
local CFG = Config.Spectate

local function racing(board, id)
    for _, r in ipairs(board or {}) do if r.id == id then return r.status == PStatus.RACING or r.status == 'countdown' or r.status == 'mobilizing' end end
    return SP and SP.feed[id] ~= nil
end

-- Racers still on track, by position
local function order()
    local list = {}
    if SP.board and #SP.board > 0 then
        local sorted = {}
        for _, r in ipairs(SP.board) do sorted[#sorted + 1] = r end
        table.sort(sorted, function(a, b) return (a.pos or 99) < (b.pos or 99) end)
        for _, r in ipairs(sorted) do if r.status == PStatus.RACING then list[#list + 1] = r.id end end
    end
    if #list == 0 then
        for _, r in ipairs(SP.racers) do if SP.feed[r.id] then list[#list + 1] = r.id end end
    end
    return list
end

local function racer(id)
    for _, r in ipairs(SP.racers) do if r.id == id then return r end end
end

local function hud()
    local r = racer(SP.target)
    local pos
    for _, b in ipairs(SP.board or {}) do if b.id == SP.target then pos = b.pos end end
    UI('race', { phase = 'watch', id = SP.target, alias = r and r.alias or '?', color = r and r.color, pos = pos })
end

local function setTarget(id)
    if not id or id == SP.target then return end
    SP.target = id
    SP.focusEnt = nil
    hud()
end

local function cycle(dir)
    local list = order()
    if #list == 0 then return end
    local idx = 1
    for i, id in ipairs(list) do if id == SP.target then idx = i end end
    idx = ((idx - 1 + dir) % #list) + 1
    setTarget(list[idx])
end

local function lerp(a, b, f) return a + (b - a) * f end

local function loop()
    CreateThread(function()
        local camPos, last, lastFocus, lastTick = nil, GetGameTimer(), 0, 0
        local K = CFG.Keys
        while SP do
            local now = GetGameTimer()
            local dt = math.min((now - last) / 1000, 0.1)
            last = now

            DisableControlAction(0, K.next, true)
            DisableControlAction(0, K.prev, true)
            DisableControlAction(0, K.exit, true)
            if IsDisabledControlJustPressed(0, K.next) then cycle(1)
            elseif IsDisabledControlJustPressed(0, K.prev) then cycle(-1)
            elseif IsDisabledControlJustPressed(0, K.exit) then Spectate.Stop() break end

            -- target left the track: follow the leader
            if not racing(SP.board, SP.target) then
                if not SP.lostAt then SP.lostAt = now elseif now - SP.lostAt > 1500 then SP.lostAt = nil setTarget(order()[1]) end
            else
                SP.lostAt = nil
            end

            local f = SP.feed[SP.target]
            local pos, fwd, speed
            local ent = f and f.net and NetworkDoesEntityExistWithNetworkId(f.net) and NetworkGetEntityFromNetworkId(f.net) or nil
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                pos, fwd, speed = GetEntityCoords(ent), GetEntityForwardVector(ent), GetEntitySpeed(ent)
                if SP.focusEnt ~= ent then SetFocusEntity(ent) SP.focusEnt = ent end
            elseif f then
                -- not streamed in yet: move the focus there and extrapolate from the feed
                local age = (now - f.t) / 1000
                pos = f.pos + f.vel * math.min(age, 1.0)
                local h = math.rad(f.h)
                fwd = vector3(-math.sin(h), math.cos(h), 0.0)
                speed = #f.vel
                if now - lastFocus > 500 then lastFocus = now SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0) SP.focusEnt = nil end
            end

            if pos then
                local want = pos - fwd * CFG.Camera.distance + vector3(0.0, 0.0, CFG.Camera.height)
                if not camPos or #(want - camPos) > 150.0 then camPos = want end
                local k = math.min(1.0, dt * CFG.Camera.smooth)
                camPos = vector3(lerp(camPos.x, want.x, k), lerp(camPos.y, want.y, k), lerp(camPos.z, want.z, k))
                SetCamCoord(SP.cam, camPos.x, camPos.y, camPos.z)
                PointCamAtCoord(SP.cam, pos.x, pos.y, pos.z + 0.8)
                if now - lastTick > 150 then
                    lastTick = now
                    UI('race', { phase = 'tick', speed = math.floor((speed or 0) * (Settings.units == 'mph' and 2.236936 or 3.6)) })
                end
            end
            Wait(0)
        end
    end)
end

function Spectate.Start(d)
    if Race.Busy() then return end
    if SP then Spectate.Stop(true) end
    if App.open then CloseApp() end
    SP = { id = d.id, racers = d.racers or {}, board = d.board or {}, feed = {}, mode = d.mode }
    Spectate.on = true

    -- the world around us unloads while the camera is far away: hold our own ped / car in place
    local ped = cache.ped
    local veh = cache.vehicle
    SP.frozen = veh and GetPedInVehicleSeat(veh, -1) == ped and veh or ped
    FreezeEntityPosition(SP.frozen, true)

    SP.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local c = GetGameplayCamCoord()
    SetCamCoord(SP.cam, c.x, c.y, c.z)
    SetCamFov(SP.cam, 60.0)
    RenderScriptCams(true, true, 600, true, true)

    UI('race', { phase = 'spectate', name = d.name, track = d.track, mode = d.mode, laps = d.laps, circuit = d.circuit, total = d.total,
        racers = d.racers, board = d.board, settings = Settings })
    local first = order()[1] or (SP.racers[1] and SP.racers[1].id)
    if first then setTarget(first) end
    loop()
end

function Spectate.Stop(silent)
    if not SP then return end
    local sp = SP
    SP = nil
    Spectate.on = false
    RenderScriptCams(false, true, 500, true, true)
    if sp.cam then DestroyCam(sp.cam, false) end
    ClearFocus()
    if sp.frozen and DoesEntityExist(sp.frozen) then FreezeEntityPosition(sp.frozen, false) end
    if not silent then UI('race', { phase = 'hide' }) end
    lib.callback('nzr:req', false, function() end, 'lobby:unspectate', {})
end

function Spectate.Board(board)
    if not SP then return end
    SP.board = board
    if not SP.target or not racing(board, SP.target) then setTarget(order()[1]) else hud() end
end

-- ── server events ───────────────────────────────────────────────────────
function SpectateEvents.spectate(d) Spectate.Start(d) end

function SpectateEvents.feed(list)
    if not SP then return end
    local now = GetGameTimer()
    local seen = {}
    for _, r in ipairs(list) do
        local pos = vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0)
        local prev = SP.feed[r.id]
        local vel = vector3(0.0, 0.0, 0.0)
        if prev and now > prev.t then vel = (pos - prev.pos) / ((now - prev.t) / 1000) end
        SP.feed[r.id] = { pos = pos, vel = vel, h = r.h or 0.0, net = r.net, t = now }
        seen[r.id] = true
    end
    for id in pairs(SP.feed) do if not seen[id] then SP.feed[id] = nil end end
    if not SP.target or not SP.feed[SP.target] then setTarget(order()[1]) end
end

-- Watchers who are not racers get the elimination toast too
function SpectateEvents.eliminated(d)
    if SP then UI('race', { phase = 'eliminated', alias = d.alias, lap = d.lap }) end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource or not SP then return end
    RenderScriptCams(false, false, 0, true, true)
    if SP.cam then DestroyCam(SP.cam, false) end
    ClearFocus()
    if SP.frozen and DoesEntityExist(SP.frozen) then FreezeEntityPosition(SP.frozen, false) end
end)
