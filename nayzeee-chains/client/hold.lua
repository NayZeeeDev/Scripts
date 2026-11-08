-----------------------------------------------------------------
-- Holding a chain up, and throwing it
--
-- While holding: [G] throw where you look, [E] set it down,
-- [BACKSPACE] put it back on. Everyone sees it in your hand (the
-- statebag's h flag moves the prop to the hold fit).
--
-- A throw is worked out once on the thrower's client: the arc,
-- raycasts against the world, a bounce off walls. The server checks
-- the path and plays it on every client nearby.
-----------------------------------------------------------------

Hold = {}

local holding = false
local cfg = Config.Hold
local TC = Config.Throw
local DT = 1 / 30

local function anim()
    return cfg.Anims[cfg.Anim] or select(2, next(cfg.Anims))
end
Hold.anim = anim

function Hold.active() return holding end

local function playHold(ped)
    local a = anim()
    if a and Util.loadDict(a.dict) and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
        TaskPlayAnim(ped, a.dict, a.clip, 3.0, -3.0, -1, a.flag or 49, 0.0, false, false, false)
    end
end

function Hold.stop(silent)
    if not holding then return end
    holding = false
    NUI.hint(nil)
    local a = anim()
    if a then StopAnimTask(PlayerPedId(), a.dict, a.clip, 2.0) end
    if not silent then TriggerServerEvent('nzc:s:hold', false) end
end

-----------------------------------------------------------------
-- the flight
-----------------------------------------------------------------

local function ray(a, b, ped)
    local h = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 1 | 2 | 16, ped, 7)
    local _, hit, pos, normal = GetShapeTestResult(h)
    return hit == 1, pos, normal
end

--- Add points toward `to` so no step is longer than 2 m (the server checks every step).
local function lineTo(pts, to)
    local from = pts[#pts]
    local n = math.ceil(#(to - from) / 2.0)
    for i = 1, n do pts[#pts + 1] = from + (to - from) * (i / n) end
end

--- Path from `from` with velocity `vel`. Returns the points (every 1/30 s) and the rest rotation.
local function simulate(from, vel, ped)
    local pts = { from }
    local p, v = from, vel
    local bounces = 0
    for _ = 1, 240 do
        local nv = v + vector3(0.0, 0.0, -9.81 * DT)
        nv = nv * 0.995
        local np = p + (v + nv) * 0.5 * DT
        local hit, pos, normal = ray(p, np, ped)
        if hit then
            if normal.z > 0.6 or bounces >= 2 then
                pts[#pts + 1] = pos + vector3(0.0, 0.0, 0.035)
                return pts
            end
            -- off a wall: reflect and lose most of the speed
            bounces = bounces + 1
            local d = Util.dot(nv, normal)
            nv = (nv - normal * (2 * d)) * 0.35
            np = pos + normal * 0.05
        end
        pts[#pts + 1] = np
        p, v = np, nv
    end
    -- still falling after 8 s (off a cliff): drop it straight down
    local hit, pos = ray(p, p - vector3(0.0, 0.0, 200.0), ped)
    if hit then lineTo(pts, pos + vector3(0.0, 0.0, 0.035)) end
    return pts
end

local function throw()
    local key = WornProps.mine()
    if not key then return Hold.stop(true) end
    local ped = PlayerPedId()
    local a = TC.Anim
    holding = false
    NUI.hint(nil)
    local ha = anim()
    if ha then StopAnimTask(ped, ha.dict, ha.clip, 4.0) end
    -- face where we throw
    local camRot = GetGameplayCamRot(2)
    SetEntityHeading(ped, camRot.z)
    if Util.loadDict(a.dict) then
        TaskPlayAnim(ped, a.dict, a.clip, 6.0, -4.0, 1400, 48, 0.0, false, false, false)
    end
    Wait(a.release or 380)

    local dir = Util.rotToDir(GetGameplayCamRot(2))
    local from = GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0) + dir * 0.25
    local vel = dir * (TC.Speed or 11.0) + vector3(0.0, 0.0, TC.Lift or 2.2)
    local pts = simulate(from, vel, ped)
    -- the server refuses throws that land further than MaxDistance (measured flat): cut a long one
    -- short and let it fall straight down from there, all the way to the ground
    local max = (TC.MaxDistance or 30.0) - 0.5
    local function flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
    for i = 2, #pts do
        if flat(pts[i], pts[1]) > max then
            for j = #pts, i, -1 do pts[j] = nil end
            local hit, pos = ray(pts[#pts], pts[#pts] - vector3(0.0, 0.0, 300.0), ped)
            if hit then lineTo(pts, pos + vector3(0.0, 0.0, 0.035)) end
            break
        end
    end
    if #pts > 400 then return CB.Notify(Config.Text.bad_spot, 'error') end
    TriggerServerEvent('nzc:s:throw', pts, { x = 0.0, y = 0.0, z = math.random() * 360.0 })
    -- the server refused it (too far, too fast): it's still ours, back on the neck
    SetTimeout(1500, function()
        local st = LocalPlayer.state.nzc_worn
        if st and st.h and not holding then TriggerServerEvent('nzc:s:hold', false) end
    end)
end

-----------------------------------------------------------------
-- hold mode
-----------------------------------------------------------------

local BLOCK = { 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264, 177, 194, 200, 38, 51 }

function Hold.start()
    if holding or Snatch.tug then return end
    local key, letter = WornProps.mine()
    if not key then return CB.Notify(Config.Text.no_chain, 'error') end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
    holding = true
    TriggerServerEvent('nzc:s:hold', true)
    NUI.hint(TC.Enabled and Config.Text.hint_hold or Config.Text.hint_hold:gsub('<kc>G</kc> [^<]*', ''), 'hold')

    CreateThread(function()
        local nextAnim = 0
        while holding do
            ped = PlayerPedId()
            for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
            if GetGameTimer() > nextAnim then playHold(ped); nextAnim = GetGameTimer() + 1000 end

            if not WornProps.mine() or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) then
                Hold.stop(not WornProps.mine())
                break
            end
            if TC.Enabled and IsDisabledControlJustPressed(0, 47) then -- G
                throw()
                break
            elseif Config.Place.Enabled and IsDisabledControlJustPressed(0, 38) then -- E
                Hold.stop(false)
                Wait(100)
                key, letter = WornProps.mine()
                if key then Place.start(key, letter, 'worn') end
                break
            elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then -- BACKSPACE
                Hold.stop(false)
                break
            end
            Wait(0)
        end
    end)
end

if cfg.Command then
    RegisterCommand(cfg.Command, function() if holding then Hold.stop(false) else Hold.start() end end, false)
    if cfg.Keybind then RegisterKeyMapping(cfg.Command, 'Hold your chain up', 'keyboard', cfg.Keybind) end
end

-----------------------------------------------------------------
-- everyone sees the throw
-----------------------------------------------------------------

RegisterNetEvent('nzc:c:throwFx', function(fx)
    local path = fx.path
    if type(path) ~= 'table' or #path < 2 then return end
    local entity = Util.spawnChain(fx.chain, fx.variant, path[1])
    if not entity then return end
    FreezeEntityPosition(entity, true)
    local dt = (fx.dt or DT) * 1000
    local total = (#path - 1) * dt
    local start = GetGameTimer()
    local spinZ, spinX = math.random(500, 900), math.random(250, 500)
    local rest = fx.rest or { x = 0.0, y = 0.0, z = 0.0 }
    CreateThread(function()
        while true do
            local t = GetGameTimer() - start
            if t >= total then break end
            local f = t / dt
            local i = math.floor(f) + 1
            local a, b = path[i], path[math.min(#path, i + 1)]
            local k = f - (i - 1)
            local p = a + (b - a) * k
            SetEntityCoordsNoOffset(entity, p.x, p.y, p.z, false, false, false)
            local s = t / 1000
            local ease = 1.0 - math.min(1.0, t / total)
            SetEntityRotation(entity, rest.x + spinX * s * ease, 0.0, rest.z + spinZ * s * ease, 2, false)
            Wait(0)
        end
        Util.delete(entity)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Hold.stop(true) end
end)
