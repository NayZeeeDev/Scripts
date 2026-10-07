-----------------------------------------------------------------
-- Job tracking
--
-- Cached from ESX events rather than polled, so it costs nothing
-- to ask "what job am I on" anywhere else in the script.
-----------------------------------------------------------------

Job = { name = nil, grade = 0 }

local function set(job)
    if not job then return end
    Job.name  = job.name
    Job.grade = job.grade or 0
end

CreateThread(function()
    while not ESX do Wait(200) end

    local data = ESX.GetPlayerData and ESX.GetPlayerData()
    if data and data.job then set(data.job) end
end)

RegisterNetEvent('esx:setJob', function(job) set(job) end)
RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    if xPlayer and xPlayer.job then set(xPlayer.job) end
end)

--- Can this player use a bag with a `job` restriction?
function CanUseBag(bag)
    if not bag or not bag.job then return true end

    local allowed = type(bag.job) == 'table' and bag.job or { bag.job }
    for _, j in ipairs(allowed) do
        if j == Job.name then
            return (Job.grade or 0) >= (bag.grade or 0)
        end
    end

    return false
end
