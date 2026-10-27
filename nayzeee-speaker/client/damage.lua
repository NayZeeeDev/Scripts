-- Watches for hits on nearby placed speakers and reports them to the server (which checks the
-- distance and a cooldown again). One slow thread: it rebuilds a short list of the placed speakers
-- around you once a second from the coords it already has, and only checks them while that list
-- isn't empty, so a player with no speaker around costs nothing.
if not Config.Damage.enabled then return end

local D = Config.Damage
local SCAN  = 1000       -- ms between rebuilding the list of nearby speakers
local TICK  = 250        -- ms between hit checks while one is near (the game keeps a hit until we clear it)
local RANGE = 150.0      -- the furthest the server takes a bullet / explosion report from
local NEAR_BLAST = 120.0 -- explosions are only checked around speakers this close
local RAM_DIST, RAM_SPEED = 3.2, 4.0

local near, nearN = {}, 0    -- { id, ent, d } per nearby speaker, reused between scans
local lastSent = 0

local function report(id, kind)
    local t = GetGameTimer()
    if t - lastSent < D.cooldown then return end
    lastSent = t
    TriggerServerEvent(RES .. ':damage', id, kind)
end

-- placed speakers with a prop here; the snapshot coords rule out far ones without a native
local function scan(me)
    local n = 0
    for id, e in pairs(Emitters) do
        local c = e.kind == 'boombox' and e.state == 'placed' and e.coords
        if c then
            local d = #(me - c)
            if d < RANGE then
                local ent = LocateEmitter(e)
                if ent then
                    n = n + 1
                    local s = near[n]
                    if not s then s = {} near[n] = s end
                    s.id, s.ent, s.d = id, ent, d
                end
            end
        end
    end
    for i = n + 1, nearN do near[i] = nil end
    nearN = n
end

-- what hit it: the car you are in (close by), else your weapon or fists
local function hitBy(ped, veh, vpos, fast, ent)
    local byMe = HasEntityBeenDamagedByEntity(ent, ped, true)
    if veh ~= 0 and not (byMe and IsPedDoingDriveby(ped)) then
        -- the impact stops the car, so a recorded hit doesn't need the speed; a touch does
        local rammed = byMe or HasEntityBeenDamagedByEntity(ent, veh, true) or (fast and IsEntityTouchingEntity(veh, ent))
        if rammed and #(vpos - GetEntityCoords(ent)) < RAM_DIST then return 'vehicle' end
    end
    if not byMe then return nil end
    if IsPedInMeleeCombat(ped) or GetWeaponDamageType(GetSelectedPedWeapon(ped)) == 2 then return 'melee' end
    return 'bullet'
end

CreateThread(function()
    local scanAt = 0
    while true do
        local t = GetGameTimer()
        local ped = PlayerPedId()
        if t - scanAt >= SCAN then
            scanAt = t
            scan(GetEntityCoords(ped))
        end
        if nearN == 0 then
            Wait(SCAN)
        else
            local veh = GetVehiclePedIsIn(ped, false)
            local vpos = veh ~= 0 and GetEntityCoords(veh) or nil
            local fast = veh ~= 0 and GetEntitySpeed(veh) > RAM_SPEED
            for i = 1, nearN do
                local s = near[i]
                local ent = s.ent
                if DoesEntityExist(ent) then
                    local kind = hitBy(ped, veh, vpos, fast, ent)
                    if kind then
                        ClearEntityLastDamageEntity(ent)
                        report(s.id, kind)
                    elseif s.d < NEAR_BLAST then
                        local p = GetEntityCoords(ent)
                        if IsExplosionInSphere(-1, p.x, p.y, p.z, 6.0) then report(s.id, 'explosion') end
                    end
                end
            end
            Wait(TICK)
        end
    end
end)

---------------------------------------------------------------- effects
local function ptfx(dict, name, pos, scale)
    if not D.effect then return end
    RequestNamedPtfxAsset(dict)
    local t = GetGameTimer()
    while not HasNamedPtfxAssetLoaded(dict) and GetGameTimer() - t < 2000 do Wait(0) end
    if not HasNamedPtfxAssetLoaded(dict) then return end
    UseParticleFxAssetNextCall(dict)
    StartParticleFxNonLoopedAtCoord(name, pos.x, pos.y, pos.z + 0.3, 0.0, 0.0, 0.0, scale or 1.0, false, false, false)
end

local function inView(pos, dist)
    return type(pos) == 'vector3' and #(GetEntityCoords(PlayerPedId()) - pos) <= dist
end

RegisterNetEvent(RES .. ':client:hit', function(_, pos, pct)
    if not inView(pos, 60.0) then return end
    ptfx('core', 'bul_metal', pos, 0.6)
    if pct and pct < 0.4 then ptfx('core', 'exp_grd_bzgas_smoke', pos, 0.3) end
end)

RegisterNetEvent(RES .. ':client:broke', function(id, pos)
    ForgetEmitter(id)
    if not inView(pos, 90.0) then return end
    ptfx('core', 'exp_grd_petrol_pump', pos, 0.5)
    PlaySoundFromCoord(-1, 'Explosion_Metal', pos.x, pos.y, pos.z, 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false, 25, false)
end)
