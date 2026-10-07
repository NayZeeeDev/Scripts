-----------------------------------------------------------------
-- Robbery + police search
--
-- The bag is already visible on the victim's back, so this makes
-- carrying one a social decision rather than a free upgrade.
-- Police get a separate "Search backpack" that opens the bag
-- without taking it.
-----------------------------------------------------------------

local cfg = Config.Robbery or {}
local search = Config.Jobs and Config.Jobs.policeSearch or {}
local busy = false

local function handsUp(ped)
    return IsEntityPlayingAnim(ped, 'random@mugging3', 'handsup_standing_base', 3)
        or IsEntityPlayingAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 3)
        or IsEntityPlayingAnim(ped, 'missminuteman_1ig_2', 'handsup_enter', 3)
end

local function serverIdOf(ped)
    local ply = NetworkGetPlayerIndexFromPed(ped)
    if ply == -1 then return nil end
    return GetPlayerServerId(ply)
end

local function wornBy(serverId, allowStowed)
    local st = Player(serverId).state.nayzeee_backpack
    if not st or not st.bag then return nil end
    if st.stowed and not allowStowed then return nil end
    return st.bag, st
end

--- Does the victim qualify right now?
local function victimEligible(ped, serverId)
    local status = GetPlayerStatus(serverId)

    if status.dead or IsPedDeadOrDying(ped, true) then
        return cfg.allowDead and true or false, 'dead'
    end

    local cuffed = status.cuffed or IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3)
    local up = handsUp(ped)

    if cfg.requireCuffed and cfg.requireHandsUp then return cuffed or up end
    if cfg.requireCuffed then return cuffed end
    if cfg.requireHandsUp then return up or cuffed end
    return true
end

local function robberArmed()
    if not cfg.requireWeapon then return true end
    return IsPedArmed(PlayerPedId(), 4)
end

local function canRob(ped, serverId)
    if busy or not cfg.enabled then return false end
    local bagKey = wornBy(serverId, cfg.allowStowed)
    if not bagKey then return false end
    if cfg.protectJobBags and Bags.isJobBag(bagKey) then return false end
    return victimEligible(ped, serverId)
end

local function attemptRob(targetPed, serverId)
    if busy then return end

    local bagKey = wornBy(serverId, cfg.allowStowed)
    if not bagKey then
        return Config.Notify('They are not carrying a bag.', 'error')
    end
    if cfg.protectJobBags and Bags.isJobBag(bagKey) then
        return Config.Notify(Strings.rob_job, 'error')
    end

    local ok, why = victimEligible(targetPed, serverId)
    if not ok then
        return Config.Notify('They need to be restrained first.', 'error')
    end
    if why ~= 'dead' and not robberArmed() then
        return Config.Notify('You need a weapon out.', 'error')
    end

    busy = true
    local startCoords = GetEntityCoords(targetPed)

    local success = lib.progressBar({
        duration = cfg.duration or 5000,
        label = Strings.rob_started,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },
    })

    busy = false

    if not success then
        return Config.Notify(Strings.rob_failed, 'error')
    end

    if #(GetEntityCoords(targetPed) - startCoords) > 3.0 then
        return Config.Notify(Strings.rob_moved, 'error')
    end

    TriggerServerEvent('nayzeee-backpack:rob', serverId)
end

-----------------------------------------------------------------
-- police search
-----------------------------------------------------------------

local function isPolice()
    local job = Framework.getJob()
    if not job or not search.enabled then return false end
    for _, j in ipairs(search.jobs or {}) do
        if j == job.name then return Config.Jobs.requireDuty ~= true or job.onDuty end
    end
    return false
end

local function canSearch(ped, serverId)
    if busy or not isPolice() then return false end
    if not wornBy(serverId, true) then return false end
    local status = GetPlayerStatus(serverId)
    return status.cuffed or status.dead or handsUp(ped)
        or IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3)
end

local function attemptSearch(ped, serverId)
    if busy then return end
    busy = true
    local ok = lib.progressBar({
        duration = search.duration or 3500,
        label = Strings.search_start,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', flag = 49 },
    })
    busy = false
    if ok then TriggerServerEvent('nayzeee-backpack:policeSearch', serverId) end
end

-----------------------------------------------------------------
-- target integration
-----------------------------------------------------------------

CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' or not Config.Prompts.useTarget then
        print('^3[nayzeee-backpack] ox_target not running; robbery uses /robbag instead^0')
        return
    end

    local opts = {}

    if cfg.enabled then
        opts[#opts + 1] = {
            name  = 'nayzeee_backpack_rob',
            label = Config.Prompts.rob,
            icon  = 'fa-solid fa-bag-shopping',
            distance = cfg.distance or 2.0,
            canInteract = function(entity)
                local sid = serverIdOf(entity)
                return sid ~= nil and canRob(entity, sid)
            end,
            onSelect = function(data)
                local sid = serverIdOf(data.entity)
                if sid then attemptRob(data.entity, sid) end
            end,
        }
    end

    if search.enabled then
        opts[#opts + 1] = {
            name  = 'nayzeee_backpack_search',
            label = Config.Prompts.search,
            icon  = 'fa-solid fa-magnifying-glass',
            distance = search.distance or 2.0,
            canInteract = function(entity)
                local sid = serverIdOf(entity)
                return sid ~= nil and canSearch(entity, sid)
            end,
            onSelect = function(data)
                local sid = serverIdOf(data.entity)
                if sid then attemptSearch(data.entity, sid) end
            end,
        }
    end

    if #opts > 0 then exports.ox_target:addGlobalPlayer(opts) end
end)

-- fallback for servers without ox_target
local function closestPlayer(maxDist)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, maxDist

    for _, ply in ipairs(GetActivePlayers()) do
        local other = GetPlayerPed(ply)
        if other ~= ped then
            local d = #(GetEntityCoords(other) - coords)
            if d < closestDist then closest, closestDist = ply, d end
        end
    end
    return closest
end

if cfg.enabled then
    RegisterCommand('robbag', function()
        local ply = closestPlayer(cfg.distance or 2.0)
        if not ply then return Config.Notify('Nobody close enough.', 'error') end
        attemptRob(GetPlayerPed(ply), GetPlayerServerId(ply))
    end, false)
end

if search.enabled then
    RegisterCommand('searchbag', function()
        if not isPolice() then return end
        local ply = closestPlayer(search.distance or 2.0)
        if not ply then return Config.Notify('Nobody close enough.', 'error') end
        local ped, sid = GetPlayerPed(ply), GetPlayerServerId(ply)
        if not canSearch(ped, sid) then return Config.Notify(Strings.search_none, 'error') end
        attemptSearch(ped, sid)
    end, false)
end

RegisterNetEvent('nayzeee-backpack:robbed', function()
    if cfg.notifyVictim then
        Config.Notify(Strings.rob_victim, 'error')
    end
end)

-----------------------------------------------------------------
-- dispatch (server tells the robber's client to raise it)
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:dispatch', function(coords)
    coords = vec3(coords.x, coords.y, coords.z)
    local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(s1)
    if s2 and s2 ~= 0 then street = street .. ' / ' .. GetStreetNameFromHashKey(s2) end

    local data = {
        coords  = coords,
        street  = street,
        code    = '10-31',
        title   = 'Bag Snatching',
        message = ('Someone just had their bag taken on %s.'):format(street),
        jobs    = search.jobs or { 'police' },
    }

    Integrations.first('dispatch', data)
end)
