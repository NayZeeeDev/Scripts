if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby scene: streams a theme, parks the hidden player, spawns props / vehicles / crew.
      Scene.Load(themeId, moodId)   fade-safe rebuild (does not fade itself; callers fade first)
      Scene.Teardown()              deletes every lobby entity and releases cams, lights, timecycle, interior, focus
    Scene.main is the grounded main mark (vec4, root height). Everything else in a theme is rel space of it.
    In-flight themes (theme.flight, contract §10): the airborne vehicle is spawned at altitude, never frozen,
    and its crew pilot loops flight.route while the lobby is open. The hidden player rides attached to it and
    the streaming focus follows it (SetFocusEntity).
]]

Scene = { id = nil, theme = nil, main = nil, vehicles = {}, crew = {}, props = {}, interior = 0, loaded = false,
    flying = nil, flightToken = 0 }

local function stream(at)
    SetFocusPosAndVel(at.x, at.y, at.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(at.x, at.y, at.z, 80.0, 0)
    local deadline = GetGameTimer() + 6000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()
end

-- Interiors (MLOs, clubs, penthouses) must be fully streamed before peds are placed or they drop through the floor
local function pinInterior(at, wanted)
    local interior = GetInteriorAtCoords(at.x, at.y, at.z)
    if interior == 0 and wanted then
        local deadline = GetGameTimer() + 2000
        while interior == 0 and GetGameTimer() < deadline do
            Wait(100)
            interior = GetInteriorAtCoords(at.x, at.y, at.z)
        end
    end
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local deadline = GetGameTimer() + 5000
        while not IsInteriorReady(interior) and GetGameTimer() < deadline do Wait(50) end
    end
    return interior
end

-- ── props ────────────────────────────────────────────────────────────────
local function spawnProps(theme, base)
    for _, p in ipairs(theme.props or {}) do
        local hash = U.Model(p.model)
        if hash then
            local at = NZ.Place(base, p)
            local floor = U.Floor(at.x, at.y, at.z) or (base.z - (Config.Scene.footHeight or 1.0))
            local z = p.coords and at.z or (floor + ((p.offset and p.offset.z) or 0.0))
            local o = CreateObjectNoOffset(hash, at.x, at.y, z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            U.Track(o)
            SetEntityHeading(o, at.w)
            if p.collision == false then SetEntityCollision(o, false, false) end
            FreezeEntityPosition(o, true)
            Scene.props[#Scene.props + 1] = o
        end
    end
end

-- ── vehicles ─────────────────────────────────────────────────────────────
local PERF_MODS = { 11, 12, 13, 15, 16 }                 -- engine, brakes, transmission, suspension, armour
local COSMETIC_MODS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } -- spoiler .. roof

local function maxMods(veh)
    SetVehicleModKit(veh, 0)   -- required before any SetVehicleMod
    for _, t in ipairs(COSMETIC_MODS) do
        local n = GetNumVehicleMods(veh, t)
        if n > 0 then SetVehicleMod(veh, t, n - 1, false) end
    end
    for _, t in ipairs(PERF_MODS) do
        local n = GetNumVehicleMods(veh, t)
        if n > 0 then SetVehicleMod(veh, t, n - 1, false) end
    end
    ToggleVehicleMod(veh, 18, true)   -- turbo
    ToggleVehicleMod(veh, 22, true)   -- xenon headlights
    SetVehicleWindowTint(veh, 1)
end

local function spawnCrew(veh, crew)
    local list = {}
    for _, c in ipairs(crew or {}) do
        local pos = GetEntityCoords(veh)
        local ped = U.Ped(c.model, vec4(pos.x, pos.y, pos.z + 2.0, 0.0), 26)
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetPedIntoVehicle(ped, veh, c.seat or -1)   -- instant warp
        SetPedStayInVehicleWhenJacked(ped, true)
        SetPedCanBeDraggedOut(ped, false)
        SetPedConfigFlag(ped, 184, true)              -- never shuffle seats
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        SetDriverAbility(ped, 1.0)
        SetDriverAggressiveness(ped, 0.0)
        list[#list + 1] = { ped = ped, seat = c.seat or -1 }
    end
    return list
end

local function spawnVehicles(theme, base)
    local flight = theme.flight
    for i, v in ipairs(theme.vehicles or {}) do
        local hash = U.Model(v.model)
        if hash then
            local at = NZ.Place(base, v)
            local air = v.airborne == true
            local z, h = at.z, at.w
            if air then
                z = (flight and flight.altitude) or at.z
                -- Face the first leg of the route so the pilot doesn't start with a U-turn
                local r = flight and flight.route
                if r and r[2] and (flight.vehicle or 1) == i then h = NZ.HeadingTo(r[1], r[2]) end
            else
                z = (U.Floor(at.x, at.y, at.z) or (base.z - (Config.Scene.footHeight or 1.0))) + 0.6
            end
            local veh = CreateVehicle(hash, at.x, at.y, z, h, false, false)
            SetModelAsNoLongerNeeded(hash)
            U.Track(veh)
            SetEntityAsMissionEntity(veh, true, true)
            if not air then SetVehicleOnGroundProperly(veh) end   -- collision is loaded at this point (Scene.Load waits for it)
            SetEntityInvincible(veh, true)
            SetVehicleCanBeVisiblyDamaged(veh, false)
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleEngineOn(veh, air, true, not air)
            SetVehicleHasBeenOwnedByPlayer(veh, true)
            SetVehicleNeedsToBeHotwired(veh, false)
            SetVehRadioStation(veh, 'OFF')
            if v.mods then maxMods(veh) end
            if v.color then SetVehicleColours(veh, v.color[1] or 0, v.color[2] or v.color[1] or 0) end
            if v.livery then SetVehicleLivery(veh, v.livery) end
            if type(v.extras) == 'table' then
                for k, on in pairs(v.extras) do
                    -- { [id] = true/false } or a list of ids to enable
                    if type(k) == 'number' and type(on) == 'boolean' then SetVehicleExtra(veh, k, not on)
                    elseif type(on) == 'number' then SetVehicleExtra(veh, on, false) end
                end
            end
            if v.lights then
                SetVehicleLights(veh, 2)          -- 2 = forced on
            end
            for _, d in ipairs(v.doorsOpen or {}) do SetVehicleDoorOpen(veh, d, false, true) end
            SetVehicleDoorsLocked(veh, v.locked and 2 or 1)
            Scene.vehicles[i] = veh
            Scene.crew[i] = spawnCrew(veh, v.crew)
            if air then
                SetHeliBladesFullSpeed(veh)           -- rotors at full speed instantly (no spool-up drop)
                SetVehicleForwardSpeed(veh, (flight and flight.speed or 12.0) + 0.0)
            else
                FreezeEntityPosition(veh, true)
            end
        end
    end
end

-- ── in-flight lobby ──────────────────────────────────────────────────────
local function heliGoto(pilot, veh, p, f)
    local alt = (f.altitude or p.z) + 0.0
    -- TaskHeliMission(ped, heli, targetVeh, targetPed, x, y, z, missionFlag 4 = goto, maxSpeed, radius,
    --                 targetHeading (-1 = any), flightHeight, minHeightAboveTerrain, slowDownDistance, behaviorFlags)
    TaskHeliMission(pilot, veh, 0, 0, p.x, p.y, alt, 4, (f.speed or 16.0) + 0.0, 20.0, -1.0, math.floor(alt), 60, -1.0, 0)
    SetPedKeepTask(pilot, true)
end

local function startFlight(theme)
    local f = theme.flight
    if not f or not f.route or #f.route == 0 then return end
    local veh = Scene.Vehicle(f.vehicle or 1)
    if not veh then return end
    Scene.flying = veh

    -- The hidden player rides along (keeps physics / LOD around the heli) and the streaming focus follows it
    local ped = PlayerPedId()
    AttachEntityToEntity(ped, veh, 0, 0.0, 0.0, -2.5, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetFocusEntity(veh)

    local pilot = GetPedInVehicleSeat(veh, -1)
    if pilot == 0 then return end
    Scene.flightToken = Scene.flightToken + 1
    local my, route = Scene.flightToken, f.route
    local idx = #route > 1 and 2 or 1
    heliGoto(pilot, veh, route[idx], f)
    CreateThread(function()
        while Scene.flightToken == my and DoesEntityExist(veh) and (Main.open or (Editor and Editor.active)) do
            Wait(500)
            if Scene.flightToken ~= my then break end
            local c, p = GetEntityCoords(veh), route[idx]
            if U.Dist2D(c, p) < 60.0 then
                idx = idx % #route + 1
                heliGoto(pilot, veh, route[idx], f)
            end
        end
    end)
end

-- Re-hide the player after SetPlayerModel (a new ped spawns visible, unattached)
function Scene.ParkPlayer()
    if Scene.flying and DoesEntityExist(Scene.flying) then
        U.HidePlayer()
        AttachEntityToEntity(PlayerPedId(), Scene.flying, 0, 0.0, 0.0, -2.5, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    else
        U.HidePlayer(Scene.theme and Scene.theme.main or nil)
    end
end

-- Spawn selector moved the focus away: put it back on the lobby (heli or mark)
function Scene.Refocus()
    if Scene.flying and DoesEntityExist(Scene.flying) then
        SetFocusEntity(Scene.flying)
        Wait(600)
        return
    end
    local m = Scene.main
    if not m then return end
    SetFocusPosAndVel(m.x, m.y, m.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(m.x, m.y, m.z, 60.0, 0)
    local deadline = GetGameTimer() + 2500
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()
    deadline = GetGameTimer() + 1500
    repeat
        RequestCollisionAtCoord(m.x, m.y, m.z)
        Wait(50)
    until HasCollisionLoadedAroundEntity(PlayerPedId()) or GetGameTimer() > deadline
end

-- ── load / teardown ──────────────────────────────────────────────────────
function Scene.Load(themeId, moodId)
    local theme = NZ.Theme(themeId) or NZ.Theme(Config.Scene.defaultTheme)
    if not theme then
        local ids = NZ.ThemeIds()
        themeId = ids[1]
        theme = NZ.Theme(themeId)
    elseif not NZ.Theme(themeId) then
        themeId = Config.Scene.defaultTheme
    end
    Scene.Teardown(true)

    local raw = theme.main
    Scene.id, Scene.theme = themeId, theme

    -- Hidden, frozen, collision-less player parked on the mark keeps the area streamed
    U.HidePlayer(raw)
    stream(raw)
    Scene.interior = pinInterior(raw, theme.interior)

    -- Collision under the mark and every vehicle, so ground snapping and vehicles find the floor
    local deadline = GetGameTimer() + (theme.flight and 0 or 5000)
    repeat
        RequestCollisionAtCoord(raw.x, raw.y, raw.z)
        for _, v in ipairs(theme.vehicles or {}) do
            local p = NZ.Place(raw, v)
            RequestCollisionAtCoord(p.x, p.y, p.z)
        end
        Wait(50)
    until HasCollisionLoadedAroundEntity(PlayerPedId()) or GetGameTimer() > deadline
    Wait(150)

    Scene.main = theme.flight and vec4(raw.x, raw.y, raw.z, raw.w) or U.Snap(raw)
    Lights.SetMood(moodId)
    spawnProps(theme, Scene.main)
    spawnVehicles(theme, Scene.main)
    startFlight(theme)
    Scene.loaded = true
    NZ.Debug('scene loaded', themeId, moodId or theme.mood)
    return true
end

-- vehicle n (1-based theme index) and its crew
function Scene.Vehicle(n)
    local veh = Scene.vehicles[n or 1]
    if veh and DoesEntityExist(veh) then return veh, Scene.crew[n or 1] or {} end
end

-- rebuilding = true while switching themes: keep the scripted camera rendering (screen is faded anyway)
function Scene.Teardown(rebuilding)
    if Actors and Actors.Clear then Actors.Clear() end
    if Couple and Couple.Stop then Couple.Stop() end
    Scene.flightToken = Scene.flightToken + 1
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    Scene.flying = nil
    U.DeleteAll()
    Scene.vehicles, Scene.crew, Scene.props = {}, {}, {}
    if not rebuilding then Cam.Stop() end
    Lights.Stop()
    U.ReleaseAnims()
    if Scene.interior and Scene.interior ~= 0 then UnpinInterior(Scene.interior) end
    ClearTimecycleModifier()
    ClearFocus()
    Scene.id, Scene.theme, Scene.main, Scene.interior, Scene.loaded = nil, nil, nil, 0, false
end
