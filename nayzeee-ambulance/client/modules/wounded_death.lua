--[[
    NAYZEEE AMBULANCE - Wounded (client): death screen & respawn

      NZA.Wounded.Death.Open() / Close()      'death' NUI app (no focus) + death camera
      NZA.Wounded.Death.Push()                live part of the screen (timer, call, body bag)
      NZA.Wounded.Death.CanRespawn()          timer over and no respawn running
      NZA.Wounded.Death.Respawn()             'nza:respawn' → server
      NZA.Wounded.Death.Revived(opts)         finishes a respawn after the core revive

    Respawn sequence (server: server/modules/wounded_respawn.lua)
      hold E (Config.Death.respawnHold) → 'nza:respawn' → server replies 'nza:wounded:respawn'
      { token, coords, bed, label, fadeMs, bedTime } → fade out, teleport, wait for collision,
      'nza:wounded:arrived' (token) → the server revives → we lie in the bed for bedTime (when
      a bed was reserved), fade, stand up next to it and fade back in.
      If the revive never comes the screen fades back in and the death screen returns.

    Net events handled: nza:wounded:respawn
    Net events sent:    nza:respawn, nza:wounded:arrived
    NUI app 'death': actions open, info, state, hold, flash, close
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Wounded = NZA.Wounded or {}
local W = NZA.Wounded
W.Death = W.Death or {}
local D = W.Death
local U = NZA.Util

local APP = 'death'
local open = false
local info = nil            -- server 'dead' block of nza:wounded:info
local respawnAt = nil       -- GetGameTimer() when respawning becomes possible
local deadSince = nil       -- GetGameTimer() at the time of death
local respawning = false
local lastJson = nil
local runToken = nil

local function S() return W.S or {} end

local function respawnLeft()
    if not respawnAt then
        return math.floor(tonumber(Config.Death and Config.Death.respawnTimer) or 300)
    end
    return math.max(0, math.ceil((respawnAt - GetGameTimer()) / 1000))
end

local function liveState()
    local sum = S().sum or {}
    return {
        respawnIn = respawnLeft(),
        ready = respawnAt ~= nil and respawnLeft() <= 0,
        loading = info == nil,
        respawning = respawning,
        bagged = sum.bag == true or (info and info.bagged) or false,
        carried = sum.carried == true,
        deadFor = deadSince and math.floor((GetGameTimer() - deadSince) / 1000) or 0,
        call = {
            allowed = W.CanCall and W.CanCall() or false,
            left = W.CallLeft and W.CallLeft() or 0,
            called = S().called == true,
            pending = S().callPending == true,
        },
        keys = W.Keys and W.Keys() or {},
    }
end

local function payload()
    local p = liveState()
    p.L = NZA.LocaleTable('wounded')
    if info then
        p.name = info.name
        p.tod = info.tod
        p.cause = info.cause
        p.hold = info.hold
        p.respawn = info.respawn
    else
        p.hold = tonumber(Config.Death and Config.Death.respawnHold) or 3
    end
    p.recovery = W.ui and W.ui('bodyRecoveryCall', true) ~= false
    p.timer = math.max(1, math.floor(tonumber(Config.Death and Config.Death.respawnTimer) or 300))
    return p
end

function D.Push(force)
    if not open then return end
    local st = liveState()
    local ok, enc = pcall(json.encode, st)
    if not force and ok and enc == lastJson then return end
    lastJson = ok and enc or nil
    NZA.UI.Send(APP, 'state', st)
end

function D.Open()
    if open then return end
    open = true
    respawning = false
    info = nil
    respawnAt = nil
    deadSince = GetGameTimer()
    lastJson = nil
    if W.Fx and W.Fx.DeathCam then W.Fx.DeathCam(true) end
    NZA.UI.Open(APP, payload(), { focus = false })
    W.FetchInfo(function(all)
        if not open or type(all) ~= 'table' or type(all.dead) ~= 'table' then return end
        info = all.dead
        local now = GetGameTimer()
        respawnAt = now + (tonumber(info.respawnIn) or 0) * 1000
        deadSince = now - (tonumber(info.deadFor) or 0) * 1000
        local p = payload()
        p.L = nil
        NZA.UI.Send(APP, 'info', p)
        D.Push(true)
    end)
end

function D.Close()
    if not open then return end
    open = false
    lastJson = nil
    NZA.UI.Close(APP)
    if W.Fx and W.Fx.DeathCam then W.Fx.DeathCam(false) end
end

function D.IsOpen()
    return open
end

function D.Hold(p)
    if open then NZA.UI.Send(APP, 'hold', { p = p }) end
end

function D.Flash(kind, text, ms)
    if open then NZA.UI.Send(APP, 'flash', { kind = kind, text = text, ms = ms or 3200 }) end
end

function D.CanRespawn()
    return open and not respawning and respawnAt ~= nil and GetGameTimer() >= respawnAt and S().mode == 'dead'
end

function D.Respawn()
    if not D.CanRespawn() then return end
    respawning = true
    D.Push(true)
    TriggerServerEvent('nza:respawn')
    local token = {}
    runToken = token
    SetTimeout(15000, function()
        -- the server refused (it sends a toast) or never answered: allow another try
        if runToken == token and respawning and S().mode == 'dead' and not S().respawn then
            respawning = false
            D.Push(true)
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- RESPAWN SEQUENCE
-- ════════════════════════════════════════════════════════════════════════

local function v4(t)
    if type(t) ~= 'table' then return nil end
    return vector4((tonumber(t.x) or 0) + 0.0, (tonumber(t.y) or 0) + 0.0, (tonumber(t.z) or 0) + 0.0, (tonumber(t.w) or 0) + 0.0)
end

local function waitFade(out, ms)
    local t = GetGameTimer()
    if out then
        while not IsScreenFadedOut() and GetGameTimer() - t < ms + 1500 do Wait(10) end
    else
        while not IsScreenFadedIn() and GetGameTimer() - t < ms + 1500 do Wait(10) end
    end
end

local function bedOffset()
    local o = Config.Respawn and Config.Respawn.bedOffset
    if type(o) == 'vector3' or type(o) == 'table' then
        return (tonumber(o.x) or 0.0), (tonumber(o.y) or 0.0), (tonumber(o.z) or 0.0)
    end
    return 0.0, 0.0, 0.0
end

local function placeInBed(ped, bed)
    local ox, oy, oz = bedOffset()
    SetEntityCoordsNoOffset(ped, bed.x + ox, bed.y + oy, bed.z + oz, false, false, false)
    SetEntityHeading(ped, bed.w)
    FreezeEntityPosition(ped, true)
    local e = W.Pose and W.Pose.Resolve and (W.Pose.Resolve('bed') or W.Pose.Resolve('still'))
    if e and W.Pose.Load(e.dict) then
        TaskPlayAnim(ped, e.dict, e.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end
end

local function groundAt(c)
    local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.5, false)
    if ok then return gz end
    return c.z
end

local function loadArea(ped, c)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 6000 do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        Wait(50)
    end
end

function D.Run(plan)
    local fade = math.floor(tonumber(plan.fadeMs) or 900)
    local spot = v4(plan.coords)
    local bed = v4(plan.bed)
    if not spot then return end
    DoScreenFadeOut(fade)
    waitFade(true, fade)

    local ped = PlayerPedId()
    W.S.respawn = { bed = bed, spot = spot, bedTime = tonumber(plan.bedTime) or 8, fade = fade, label = plan.label }
    D.Close()
    if W.Pose and W.Pose.Suspend then W.Pose.Suspend('respawn', true) end

    local target = bed or spot
    SetEntityCoordsNoOffset(ped, target.x, target.y, target.z, false, false, false)
    FreezeEntityPosition(ped, true)
    loadArea(ped, target)
    if bed then
        placeInBed(ped, bed)
    else
        SetEntityCoordsNoOffset(ped, spot.x, spot.y, groundAt(spot), false, false, false)
        SetEntityHeading(ped, spot.w)
    end

    TriggerServerEvent('nza:wounded:arrived', plan.token)

    local waitMs = ((tonumber(Config.Respawn and Config.Respawn.ackTimeout) or 20) + 6) * 1000
    local t = GetGameTimer()
    while S().mode == 'dead' and GetGameTimer() - t < waitMs do Wait(100) end

    if S().mode == 'dead' then
        -- no revive came: put things back the way they were
        W.S.respawn = nil
        respawning = false
        FreezeEntityPosition(PlayerPedId(), false)
        if W.Pose and W.Pose.Suspend then W.Pose.Suspend('respawn', false) end
        DoScreenFadeIn(fade)
        D.Open()
    end
end

RegisterNetEvent('nza:wounded:respawn', function(plan)
    if type(plan) ~= 'table' or type(plan.token) ~= 'string' then return end
    if S().mode ~= 'dead' then return end
    CreateThread(function() D.Run(plan) end)
end)

-- after the core revive (bus 'self:revived', wounded.lua forwards it)
function D.Revived()
    local r = W.S.respawn
    if not r then return end
    W.S.respawn = nil
    respawning = false
    CreateThread(function()
        local ped = PlayerPedId()
        if r.bed then
            placeInBed(ped, r.bed)
            DoScreenFadeIn(r.fade)
            Wait(math.floor(r.bedTime * 1000))
            DoScreenFadeOut(500)
            waitFade(true, 500)
            ped = PlayerPedId()
            ClearPedTasksImmediately(ped)
            FreezeEntityPosition(ped, false)
            -- stand up beside the bed, facing away from it
            local h = math.rad(r.bed.w)
            local sx, sy = r.bed.x + math.cos(h) * 1.0, r.bed.y + math.sin(h) * 1.0
            local gz = groundAt(vector3(sx, sy, r.bed.z))
            SetEntityCoordsNoOffset(ped, sx, sy, gz, false, false, false)
            SetEntityHeading(ped, (r.bed.w - 90.0) % 360.0)
            Wait(250)
            DoScreenFadeIn(700)
        else
            ped = PlayerPedId()
            FreezeEntityPosition(ped, false)
            SetEntityCoordsNoOffset(ped, r.spot.x, r.spot.y, groundAt(r.spot), false, false, false)
            SetEntityHeading(ped, r.spot.w)
            Wait(200)
            DoScreenFadeIn(r.fade)
        end
        -- release the anim dicts the respawn used
        if W.Pose and W.Pose.UnloadAll then W.Pose.UnloadAll() end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    if W.S and W.S.respawn then
        FreezeEntityPosition(PlayerPedId(), false)
        DoScreenFadeIn(0)
    end
end)
