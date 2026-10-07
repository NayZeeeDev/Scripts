-----------------------------------------------------------------
-- Robbery
--
-- The bag is already visible on the victim's back, so this makes
-- carrying one a social decision rather than a free upgrade.
-----------------------------------------------------------------

if not Config.Robbery or not Config.Robbery.enabled then return end

local cfg = Config.Robbery
local robbing = false

--- Does the victim's ped qualify right now?
local function victimEligible(ped)
    if IsPedDeadOrDying(ped, true) then
        return cfg.allowDead, 'dead'
    end

    if cfg.requireCuffed and not IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3) then
        return false
    end

    if cfg.requireHandsUp then
        local up = IsEntityPlayingAnim(ped, 'random@mugging3', 'handsup_standing_base', 3)
                or IsEntityPlayingAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 3)
        if not up and not cfg.requireCuffed then return false end
    end

    return true
end

--- Is the robber holding a weapon on them?
local function robberArmed()
    if not cfg.requireWeapon then return true end
    local ped = PlayerPedId()
    if not IsPedArmed(ped, 4) then return false end
    return IsPlayerFreeAiming(PlayerId()) or IsPedInCover(ped, false) or true
end

local function targetHasBag(serverId)
    local ply = GetPlayerFromServerId(serverId)
    if ply == -1 then return nil end

    local state = Player(serverId).state.nayzeee_backpack
    if not state or not state.bag then return nil end

    -- taken-off bags are hidden; allowStowed decides if they can still be taken
    if state.stowed and not cfg.allowStowed then return nil end

    return state.bag
end

local function attemptRob(targetPed, serverId)
    if robbing then return end

    local bagKey = targetHasBag(serverId)
    if not bagKey then
        return Config.Notify('They are not carrying a bag.', 'error')
    end

    local dead = IsPedDeadOrDying(targetPed, true)
    local ok = victimEligible(targetPed)

    if not ok then
        return Config.Notify('They need to be restrained first.', 'error')
    end

    if not dead and not robberArmed() then
        return Config.Notify('You need a weapon out.', 'error')
    end

    robbing = true

    local startCoords = GetEntityCoords(targetPed)

    local success = lib.progressBar({
        duration = cfg.duration or 5000,
        label = Strings.rob_started,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },
    })

    robbing = false

    if not success then
        return Config.Notify(Strings.rob_failed, 'error')
    end

    -- did they get away mid-grab?
    if #(GetEntityCoords(targetPed) - startCoords) > 3.0 then
        return Config.Notify(Strings.rob_moved, 'error')
    end

    TriggerServerEvent('nayzeee-backpack:rob', serverId)
end

-----------------------------------------------------------------
-- target integration
-----------------------------------------------------------------

CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then
        print('^3[nayzeee-backpack] ox_target not running; robbery uses /robbag instead^0')
        return
    end

    exports.ox_target:addGlobalPlayer({
        {
            name  = 'nayzeee_backpack_rob',
            label = 'Take backpack',
            icon  = 'fa-solid fa-bag-shopping',
            distance = cfg.distance or 2.0,

            canInteract = function(entity)
                if robbing then return false end
                local ply = NetworkGetPlayerIndexFromPed(entity)
                if ply == -1 then return false end

                local serverId = GetPlayerServerId(ply)
                if not targetHasBag(serverId) then return false end

                return victimEligible(entity)
            end,

            onSelect = function(data)
                local ply = NetworkGetPlayerIndexFromPed(data.entity)
                if ply == -1 then return end
                attemptRob(data.entity, GetPlayerServerId(ply))
            end,
        }
    })
end)

-- fallback for servers without ox_target
RegisterCommand('robbag', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, cfg.distance or 2.0

    for _, ply in ipairs(GetActivePlayers()) do
        local other = GetPlayerPed(ply)
        if other ~= ped then
            local d = #(GetEntityCoords(other) - coords)
            if d < closestDist then
                closest, closestDist = ply, d
            end
        end
    end

    if not closest then
        return Config.Notify('Nobody close enough.', 'error')
    end

    attemptRob(GetPlayerPed(closest), GetPlayerServerId(closest))
end, false)

RegisterNetEvent('nayzeee-backpack:robbed', function()
    if cfg.notifyVictim then
        Config.Notify(Strings.rob_victim, 'error')
    end
end)
