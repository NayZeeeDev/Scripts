-----------------------------------------------------------------
-- Job checks (server)
--
-- The client filters the shop for convenience; this is what
-- actually stops someone buying or wearing a job bag.
-----------------------------------------------------------------

--- Can this player use a bag with a `job` restriction?
function ServerCanUseBag(src, bagKey)
    local bag = Config.Backpacks[bagKey]
    if not bag then return false end
    if not bag.job then return true end

    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if not xPlayer or not xPlayer.job then return false end

    local allowed = type(bag.job) == 'table' and bag.job or { bag.job }
    for _, j in ipairs(allowed) do
        if j == xPlayer.job.name then
            return (xPlayer.job.grade or 0) >= (bag.grade or 0)
        end
    end

    return false
end

-----------------------------------------------------------------
-- losing the job takes the bag off your back
-----------------------------------------------------------------

RegisterNetEvent('esx:setJob', function(source, job)
    -- ESX passes source as the first arg server-side
    local src = source
    if type(src) ~= 'number' then return end

    local state = Player(src).state.nayzeee_backpack
    if not state or not state.bag then return end

    if not ServerCanUseBag(src, state.bag) then
        Player(src).state:set('nayzeee_backpack', nil, true)
        TriggerClientEvent('nayzeee-backpack:notify', src, Strings.job_only, 'error')
    end
end)
