-----------------------------------------------------------------
-- Weight affects movement
--
-- Scales off how full the bag is, so an empty duffel costs nothing
-- and a stuffed one hurts. Server pushes the load; client applies it.
-----------------------------------------------------------------

if not Config.WeightEffects or not Config.WeightEffects.enabled then return end

local cfg = Config.WeightEffects
local load = 0.0        -- 0.0 to 1.0, how full the bag is
local warned = false

--- 0.0 when under the threshold, ramping to 1.0 at completely full.
local function penalty()
    local t = cfg.threshold or 0.5
    if load <= t then return 0.0 end
    return (load - t) / (1.0 - t)
end

RegisterNetEvent('nayzeee-backpack:setLoad', function(value)
    load = math.max(0.0, math.min(1.0, tonumber(value) or 0.0))

    if load >= 0.95 and not warned then
        warned = true
        Config.Notify(Strings.too_heavy, 'inform')
    elseif load < 0.8 then
        warned = false
    end
end)

-- Only runs per-frame while the player is genuinely over the threshold.
-- An empty or light bag costs nothing: the loop sits at updateInterval.
CreateThread(function()
    local interval = cfg.updateInterval or 1000

    while true do
        local p = penalty()

        if p > 0 then
            local ped = PlayerPedId()

            if IsPedInAnyVehicle(ped, false) then
                -- no penalties while driving, so back off entirely
                Wait(1000)
                goto continue
            end

            do
                -- movement
                local rate = 1.0 - (1.0 - (cfg.minMoveRate or 0.88)) * p
                SetPedMoveRateOverride(ped, rate)

                -- stamina: drain faster by giving back less of it
                local drain = cfg.staminaDrain or 2.0
                if drain > 1.0 and IsPedSprinting(ped) then
                    local sprint = GetPlayerSprintStaminaRemaining(PlayerId())
                    if sprint then
                        RestorePlayerStamina(PlayerId(), -(drain - 1.0) * p * 0.01)
                    end
                end

                -- hard sprint block
                local cap = cfg.noSprintAbove or 0.0
                if cap > 0 and load >= cap then
                    DisableControlAction(0, 21, true) -- sprint
                end
            end

            Wait(0)
        else
            Wait(interval)
        end

        ::continue::
    end
end)

-- reset the override when the bag goes
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetPedMoveRateOverride(PlayerPedId(), 1.0)
    end
end)
