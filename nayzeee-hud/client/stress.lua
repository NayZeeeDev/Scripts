-- Stress gain + screen effects (qb-hud compatible). No per-frame loops:
-- shots are counted from the ammo the main loop already reads, speeding is checked every 10s
-- and the effect thread sleeps for the whole interval between blurs.

local S = Config.Stress
if not S.enabled then return end

local noStressWeapon = {}
for _, name in ipairs(S.noStressWeapons) do noStressWeapon[GetHashKey(name)] = true end

local function whitelisted()
    local d = HudBridge.data
    return S.whitelistedJobs[d.jobName] or (d.jobType and S.whitelistedJobs[d.jobType])
end

function NHUD.onShots(weapon, count)
    if noStressWeapon[weapon] or whitelisted() then return end
    for _ = 1, math.min(count, 10) do
        if math.random() < S.shootingChance then
            TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
            return
        end
    end
end

-- speeding
CreateThread(function()
    while true do
        Wait(S.speedCheckMs)
        if HudBridge.loaded and not whitelisted() then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                local class = GetVehicleClass(veh)
                if not S.noStressClasses[class] then
                    local mph = GetEntitySpeed(veh) * 2.236936
                    local belted = class == 8 or NHUD.get('bl') == true
                    if mph >= (belted and S.speedBuckled or S.speedUnbuckled) then
                        TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                    end
                end
            end
        end
    end
end)

-- effects: blur gets longer and more frequent the higher stress is
local function effectFor(stress)
    if stress >= 90 then return 3000, 15000 end
    if stress >= 80 then return 2700, 30000 end
    if stress >= 70 then return 2500, 30000 end
    if stress >= 60 then return 2000, 60000 end
    return 1500, 300000
end

CreateThread(function()
    while true do
        local stress = HudBridge.data.stress or 0
        if HudBridge.loaded and stress >= S.blurFrom then
            local blur, interval = effectFor(stress)
            TriggerScreenblurFadeIn(1000.0)
            Wait(blur)
            TriggerScreenblurFadeOut(1000.0)
            if stress >= 100 then
                local ped = PlayerPedId()
                if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                    SetPedToRagdollWithFall(ped, 3500, 3500, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                end
                Wait(1000)
                DoScreenFadeOut(200)
                Wait(1000)
                DoScreenFadeIn(200)
            end
            Wait(interval)
        else
            Wait(10000)
        end
    end
end)
