--[[
    NAYZEEE MULTIJOB - Framework Bridge
    Supports: ESX, QBCore, QBox
]]

if not NAYZEEE_LOCK_OK then return end

Shared = {}

local framework = nil
local frameworkObj = nil

-- Detect framework
function Shared.GetFramework()
    if framework then return framework end
    
    if Config.Framework ~= 'auto' then
        framework = Config.Framework
        return framework
    end
    
    -- qbx_core first: it provides 'qb-core' for compatibility
    if GetResourceState('es_extended') == 'started' then
        framework = 'esx'
    elseif GetResourceState('qbx_core') == 'started' then
        framework = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        framework = 'qbcore'
    else
        framework = 'standalone'
    end
    
    return framework
end

-- Get framework object
function Shared.GetFrameworkObject()
    if frameworkObj then return frameworkObj end
    
    local fw = Shared.GetFramework()
    
    if fw == 'esx' then
        frameworkObj = exports['es_extended']:getSharedObject()
    elseif fw == 'qbcore' then
        frameworkObj = exports['qb-core']:GetCoreObject()
    elseif fw == 'qbox' then
        frameworkObj = exports['qbx_core']:GetCoreObject()
    end
    
    return frameworkObj
end

-- Debug function
function Shared.Debug(...)
    if Config.Debug then
        print('[nayzeee-multijob]', ...)
    end
end

-- Notification helper
-- Routing follows Config.Notifications.output:
--   'notify' -> rendered locally, no server round trip
--   'phone'  -> handed to the server so the phone can take it
--   'both'   -> rendered locally AND handed to the server for the phone
function Shared.Notify(title, message, type)
    if IsDuplicityVersion() then
        return
    end

    local output = (Config.Notifications and Config.Notifications.output) or 'notify'

    if output == 'notify' then
        NayNotify.Send({ title = title, message = message, type = type })
        return
    end

    -- phoneOnly stops the server sending a second on-screen notify for 'both'
    TriggerServerEvent('nayzeee-multijob:notifyRequest', {
        title = title,
        message = message,
        type = type,
        phoneOnly = (output == 'both'),
    })

    if output == 'both' then
        NayNotify.Send({ title = title, message = message, type = type })
    end
end

-- Format time helper
function Shared.FormatTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format('%02d:%02d:%02d', hours, minutes, secs)
    else
        return string.format('%02d:%02d', minutes, secs)
    end
end

-- Format currency helper
function Shared.FormatCurrency(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount >= 1000000 then
        return string.format('$%.1fM', amount / 1000000)
    elseif amount >= 1000 then
        return string.format('$%.1fK', amount / 1000)
    else
        return string.format('$%d', amount)
    end
end

function Shared.InList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

-- Locale lookup with string.format arguments
function Shared.L(key, ...)
    local str = Config.Locale[key] or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, str, ...)
        if ok then return out end
    end
    return str
end

-- The job everyone falls back to (always held, always on duty)
function Shared.IsDefaultJob(jobName)
    return jobName == Config.DefaultJob.name
end

-- Check if job is blacklisted
function Shared.IsBlacklisted(jobName)
    return Shared.InList(Config.BlacklistedJobs, jobName)
end

-- Check if job is non-removable
function Shared.IsNonRemovable(jobName)
    return Shared.IsDefaultJob(jobName) or Shared.InList(Config.NonRemovableJobs, jobName)
end

-- Get job category
function Shared.GetJobCategory(jobName)
    for catId, category in pairs(Config.Categories) do
        for _, job in ipairs(category.jobs) do
            if job == jobName then
                return catId, category
            end
        end
    end
    return 'civilian', Config.Categories.civilian
end

-- Check cooldown exempt
function Shared.IsCooldownExempt(jobName)
    return Shared.IsDefaultJob(jobName) or Shared.InList(Config.Cooldowns.exempt, jobName)
end

-- Get job cooldown
function Shared.GetJobCooldown(jobName)
    if not Config.Cooldowns.enabled then return 0 end
    if Shared.IsCooldownExempt(jobName) then return 0 end
    
    return Config.Cooldowns.jobCooldowns[jobName] or Config.Cooldowns.globalCooldown
end
