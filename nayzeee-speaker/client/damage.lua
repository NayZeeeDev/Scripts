-- Watches for hits on nearby speakers and reports them to the server.
if not Config.Damage.enabled then return end

local D = Config.Damage
local lastSent = 0

local function emitterEntity(e)
    local ent = select(1, LocateEmitter(e))
    return ent
end

local function report(id, kind)
    local t = GetGameTimer()
    if t - lastSent < D.cooldown then return end
    lastSent = t
    TriggerServerEvent(RES .. ':damage', id, kind)
end

-- bullets and melee: ask the game what the player last damaged
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local wait = 500
        local shooting = IsPedShooting(ped)
        local melee = IsPedInMeleeCombat(ped)
        if shooting or melee then
            wait = 0
            for id, e in pairs(Emitters) do
                if e.kind == 'boombox' and e.state == 'placed' then
                    local ent = emitterEntity(e)
                    if ent and DoesEntityExist(ent) and HasEntityBeenDamagedByEntity(ent, ped, true) then
                        ClearEntityLastDamageEntity(ent)
                        report(id, shooting and 'bullet' or 'melee')
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- vehicles running one over
CreateThread(function()
    while true do
        Wait(250)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetEntitySpeed(veh) > 4.0 then
            local vpos = GetEntityCoords(veh)
            for id, e in pairs(Emitters) do
                if e.kind == 'boombox' and e.state == 'placed' then
                    local ent, pos = LocateEmitter(e)
                    if pos and #(vpos - pos) < 3.2 and ent and DoesEntityExist(ent) then
                        if HasEntityCollidedWithAnything(ent) or HasEntityBeenDamagedByEntity(ent, veh, true) then
                            ClearEntityLastDamageEntity(ent)
                            report(id, 'vehicle')
                        end
                    end
                end
            end
        end
    end
end)

-- explosions near a speaker
CreateThread(function()
    while true do
        Wait(400)
        local me = GetEntityCoords(PlayerPedId())
        for id, e in pairs(Emitters) do
            if e.kind == 'boombox' and e.state == 'placed' then
                local _, pos = LocateEmitter(e)
                if pos and #(me - pos) < 120.0 then
                    if IsExplosionInSphere(-1, pos.x, pos.y, pos.z, 6.0) then
                        report(id, 'explosion')
                    end
                end
            end
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

RegisterNetEvent(RES .. ':client:hit', function(id, pos, pct)
    if not pos then return end
    local me = GetEntityCoords(PlayerPedId())
    if #(me - pos) > 60.0 then return end
    ptfx('core', 'bul_metal', pos, 0.6)
    if pct and pct < 0.4 then ptfx('core', 'exp_grd_bzgas_smoke', pos, 0.3) end
end)

RegisterNetEvent(RES .. ':client:broke', function(id, pos)
    ForgetEmitter(id)
    if not pos then return end
    local me = GetEntityCoords(PlayerPedId())
    if #(me - pos) > 90.0 then return end
    ptfx('core', 'exp_grd_petrol_pump', pos, 0.5)
    PlaySoundFromCoord(-1, 'Explosion_Metal', pos.x, pos.y, pos.z, 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false, 25, false)
end)
