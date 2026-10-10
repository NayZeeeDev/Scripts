-- Reports the player's own death, plus whoever damaged them recently (for assists).
-- The victim reports, so this costs one network event per death instead of one per hit.
if not Config.Features.Combat then return end

local attackers = {}      -- [serverId] = gameTimer of the last hit taken from them
local window = Config.Elo.AssistWindow * 1000
local wasDead = false

local function noteAttacker(ped)
    if ped == 0 or ped == cache.ped then return end
    local player = NetworkGetPlayerIndexFromPed(ped)
    if player == -1 then return end
    local serverId = GetPlayerServerId(player)
    if serverId <= 0 or serverId == cache.serverId then return end
    attackers[serverId] = GetGameTimer()
end

local function recentAttackers(exclude)
    local now, list = GetGameTimer(), {}
    for id, at in pairs(attackers) do
        if now - at > window then
            attackers[id] = nil
        elseif id ~= exclude then
            list[#list + 1] = { id = id, at = at }
        end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    local out = {}
    for i = 1, math.min(#list, 5) do out[i] = list[i].id end
    return out
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if args[1] ~= cache.ped then return end
    noteAttacker(args[2] or 0)
end)

CreateThread(function()
    while true do
        Wait(300)
        local dead = IsPedDeadOrDying(cache.ped, true)

        if dead and not wasDead then
            wasDead = true
            if Squad then
                local killerPed = GetPedSourceOfDeath(cache.ped)
                local killer
                if killerPed ~= 0 and killerPed ~= cache.ped and DoesEntityExist(killerPed) then
                    if IsEntityAVehicle(killerPed) then
                        local driver = GetPedInVehicleSeat(killerPed, -1)
                        if driver ~= 0 then killerPed = driver end
                    end
                    local player = NetworkGetPlayerIndexFromPed(killerPed)
                    if player ~= -1 then
                        local id = GetPlayerServerId(player)
                        if id > 0 and id ~= cache.serverId then killer = id end
                    end
                end
                if not killer then killer = recentAttackers(nil)[1] end
                TriggerServerEvent('nz_squads:reportDeath', killer, recentAttackers(killer))
            end
            attackers = {}
        elseif not dead and wasDead then
            wasDead = false
            attackers = {}
        end
    end
end)
