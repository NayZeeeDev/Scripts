-----------------------------------------------------------------
-- Robbery (server)
--
-- The client only asks. Everything that matters is checked here.
-----------------------------------------------------------------

if not Config.Robbery or not Config.Robbery.enabled then return end

local ox = exports.ox_inventory
local cfg = Config.Robbery
local cooldowns = {}  -- [victimId] = os.time()

RegisterNetEvent('nayzeee-backpack:rob', function(victimId)
    local src = source
    victimId = tonumber(victimId)

    if not victimId or victimId == src then return end

    local robberPed = GetPlayerPed(src)
    local victimPed = GetPlayerPed(victimId)

    if not robberPed or not victimPed or robberPed == 0 or victimPed == 0 then return end

    -- distance is authoritative here, never trusted from the client
    local dist = #(GetEntityCoords(robberPed) - GetEntityCoords(victimPed))
    if dist > (cfg.distance or 2.0) + 1.5 then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_failed, 'error')
    end

    -- cooldown per victim, so nobody gets farmed
    local now = os.time()
    if cooldowns[victimId] and now - cooldowns[victimId] < (cfg.cooldown or 30) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_cooldown, 'error')
    end

    local state = Player(victimId).state.nayzeee_backpack
    local bagKey = state and state.bag
    if not bagKey or not Config.Backpacks[bagKey] then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_failed, 'error')
    end

    -- a stowed bag isn't on their back; allowStowed decides if it's still fair game
    if state.stowed and not cfg.allowStowed then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_failed, 'error')
    end

    if cfg.protectJobBags and Bags.isJobBag(bagKey) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_job, 'error')
    end

    -- confirm they really hold it
    local item = FindBagItem(victimId)
    if not item or item.name ~= bagKey then
        RefreshBagState(victimId)
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_failed, 'error')
    end

    cooldowns[victimId] = now

    local metadata = item.metadata or {}
    metadata.stowed = nil

    if Config.Drop.enabled and Config.Drop.onRob then
        -- snapshot contents before the bag changes hands
        if Logs then Logs.rob(src, victimId, bagKey, metadata, true) end

        -- hits the floor as a physical bag; the robber still has to pick it up
        if not Drop.bag(victimId, bagKey, GetEntityCoords(victimPed), true) then
            return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_failed, 'error')
        end
    else
        if Logs then Logs.rob(src, victimId, bagKey, metadata, false) end

        if not ox:RemoveItem(victimId, bagKey, 1, metadata, item.slot) then
            return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_failed, 'error')
        end

        if (Config.OneBagOnly and FindBagItem(src)) or not ox:AddItem(src, bagKey, 1, metadata) then
            -- robber already has a bag or is full, so it lands on the ground instead
            ox:CustomDrop(Bags.label(bagKey), { { bagKey, 1, metadata } }, GetEntityCoords(robberPed),
                1, Bags.storage(bagKey).weight, nil, joaat((Bags.resolve(bagKey, metadata.variant))))
        end

        RefreshBagState(victimId)
    end

    TriggerClientEvent('nayzeee-backpack:notify', src, Strings.rob_success, 'success')
    TriggerClientEvent('nayzeee-backpack:robbed', victimId)
    TriggerEvent('nayzeee-backpack:server:robbed', src, victimId, bagKey)
    Integrations.each('onRobbed', src, victimId, bagKey)

    -- police alert
    local coords = GetEntityCoords(victimPed)
    if cfg.dispatch and math.random(100) <= (cfg.dispatchChance or 100) then
        if type(cfg.dispatch) == 'string' and cfg.dispatch ~= 'auto' then
            TriggerEvent(cfg.dispatch, src, victimId, coords)
        else
            TriggerClientEvent('nayzeee-backpack:dispatch', src, coords)
        end
    end
    if cfg.policeEvent then
        TriggerEvent(cfg.policeEvent, src, victimId, coords)
    end
end)

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)
