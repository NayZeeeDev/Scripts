--[[
    DISPATCH   Config.Dispatch
    data = { title, message, coords = vector3, code, blip = { sprite, colour }, src }
    src is the player the alert is about (client-side dispatch resources raise it from their client).
]]

local D = Config.Dispatch

local function policeJobs()
    local set = {}
    for _, j in ipairs(D.PoliceJobs) do set[j] = true end
    return set
end

function Bridge.CountPolice()
    local jobs, n = policeJobs(), 0
    for _, id in ipairs(GetPlayers()) do
        local job, duty = Bridge.GetJob(tonumber(id))
        if job and jobs[job] and duty then n = n + 1 end
    end
    return n
end

local function dispatchSystem()
    local want = D.System
    if want ~= 'auto' then return want end
    for _, r in ipairs({ 'ps-dispatch', 'cd_dispatch', 'rcore_dispatch', 'qs-dispatch' }) do
        if GetResourceState(r) == 'started' then return r end
    end
    return 'builtin'
end

local function builtin(data)
    local jobs = policeJobs()
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local job, duty = Bridge.GetJob(id)
        if job and jobs[job] and duty then TriggerClientEvent('nayzeee-sneakers:dispatch', id, data) end
    end
end

-- Server-side systems. Client-side ones (ps, cd, qs) go through nayzeee-sneakers:dispatchOut.
local serverSide = {
    ['rcore_dispatch'] = function(data)
        TriggerEvent('rcore_dispatch:server:sendAlert', {
            code = data.code, default_priority = 'medium', coords = data.coords, job = D.PoliceJobs,
            text = ('%s - %s'):format(data.title, data.message), type = 'alerts',
            blip_time = math.max(1, math.floor(D.BlipTime / 60)),
            blip = { sprite = data.blip.sprite, colour = data.blip.colour, scale = 1.0, text = data.title, flashes = true, radius = 0 },
        })
        return true
    end,
}
local clientSide = { ['ps-dispatch'] = true, ['cd_dispatch'] = true, ['qs-dispatch'] = true }

--- Your own dispatch. Return true when handled.
function Bridge.CustomDispatch(data)
    return false
end

function Bridge.Dispatch(data)
    local c = data.coords
    data.coords = vector3(c.x, c.y, c.z)
    data.code = data.code or Config.SellPolice.Code
    data.blip = data.blip or Config.SellPolice.Blip
    data.jobs = D.PoliceJobs
    data.blipTime = D.BlipTime
    local sys = dispatchSystem()
    local handled = false
    if sys == 'custom' then
        local ok, r = pcall(Bridge.CustomDispatch, data)
        handled = ok and r
    elseif serverSide[sys] then
        local ok, r = pcall(serverSide[sys], data)
        handled = ok and r
    elseif clientSide[sys] then
        local from = data.src or tonumber(GetPlayers()[1])
        if from then
            TriggerClientEvent('nayzeee-sneakers:dispatchOut', from, sys, data)
            handled = true
        end
    end
    if not handled then builtin(data) end
end
