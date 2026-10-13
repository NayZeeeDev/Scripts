--[[
    NAYZEEE MULTIJOB - Notification Dispatcher (Client)
    Resolves which notify resource to use and renders through it.
]]

if not NAYZEEE_LOCK_OK then return end

local resolvedSystem = nil
local systemResolved = false

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE NOTIFY SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

local function ResolveSystem()
    if systemResolved then return resolvedSystem end
    systemResolved = true

    local cfg = Config.Notifications or {}
    local wanted = cfg.system

    if wanted == false or wanted == 'false' or wanted == 'none' then
        resolvedSystem = nil
        return nil
    end

    if wanted and wanted ~= 'auto' then
        if not NayNotify.Systems[wanted] then
            print(('^1[nayzeee-multijob]^7 Unknown notify adapter "%s" - falling back to native'):format(tostring(wanted)))
            resolvedSystem = 'native'
            return resolvedSystem
        end

        local res = NayNotify.SystemResources[wanted]
        if res and GetResourceState(res) ~= 'started' then
            print(('^3[nayzeee-multijob]^7 Notify resource "%s" is not started - falling back to native'):format(res))
            resolvedSystem = 'native'
            return resolvedSystem
        end

        resolvedSystem = wanted
        return resolvedSystem
    end

    -- auto detect
    for _, name in ipairs(NayNotify.SystemPriority) do
        local res = NayNotify.SystemResources[name] or name
        if GetResourceState(res) == 'started' then
            resolvedSystem = name
            if Config.Debug then
                print(('^2[nayzeee-multijob]^7 Notify auto-detected: ^5%s^7'):format(res))
            end
            return resolvedSystem
        end
    end

    resolvedSystem = 'native'
    return resolvedSystem
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RENDER
-- ═══════════════════════════════════════════════════════════════════════════

--- @param data table { title, message, type, duration, icon, color }
function NayNotify.Send(data)
    if type(data) ~= 'table' or not data.message then return end

    local cfg = Config.Notifications or {}
    local meta = NayNotify.Meta(data.type)

    data.type     = data.type or 'info'
    data.duration = data.duration or cfg.duration or 5000
    data.icon     = data.icon or meta.icon
    data.color    = data.color or meta.color

    local system = ResolveSystem()
    if not system then return end

    local adapter = NayNotify.Systems[system]
    if not adapter then return end

    local ok, err = pcall(adapter, data)
    if not ok then
        print(('^1[nayzeee-multijob]^7 Notify adapter "%s" errored: %s'):format(system, tostring(err)))
        pcall(NayNotify.Systems['native'], data)
    end
end

RegisterNetEvent('nayzeee-multijob:notify', function(data)
    NayNotify.Send(data)
end)

-- SystemResources is keyed by adapter name, so match on the resource value
local function IsNotifyResource(res)
    for _, resource in pairs(NayNotify.SystemResources) do
        if resource == res then return true end
    end
    return false
end

local function ResetSystem(res)
    if res == GetCurrentResourceName() then return end
    if IsNotifyResource(res) then
        systemResolved = false
        resolvedSystem = nil
    end
end

AddEventHandler('onClientResourceStart', ResetSystem)
AddEventHandler('onClientResourceStop', ResetSystem)
