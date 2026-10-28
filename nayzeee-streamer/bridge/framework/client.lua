-- Framework bridge (client): ESX Legacy, QBCore and Qbox. Open under escrow.
-- Bridge.Framework, Bridge.IsLoaded(), Bridge.OnLoaded(fn), Bridge.OnUnloaded(fn)

Bridge = Bridge or {}

local function started(name)
    return GetResourceState(name) == 'started'
end

local function detectFramework()
    local wanted = Config.Framework
    if wanted == 'qbx' or wanted == 'qbx_core' then wanted = 'qbox' end
    if wanted == 'qb' or wanted == 'qb-core' then wanted = 'qbcore' end
    if wanted == 'es_extended' then wanted = 'esx' end
    if wanted == 'esx' or wanted == 'qbcore' or wanted == 'qbox' then return wanted end

    local order = { { 'qbx_core', 'qbox' }, { 'qb-core', 'qbcore' }, { 'es_extended', 'esx' } }
    for _, entry in ipairs(order) do
        if started(entry[1]) then return entry[2] end
    end
    for _, entry in ipairs(order) do
        if GetResourceState(entry[1]) == 'starting' then return entry[2] end
    end
    return 'none'
end

Bridge.Framework = detectFramework()

local ESX, QBCore

local function getESX()
    if not ESX and started('es_extended') then
        local ok, obj = pcall(function() return exports.es_extended:getSharedObject() end)
        if ok then ESX = obj end
    end
    return ESX
end

local function getQB()
    if not QBCore and started('qb-core') then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then QBCore = obj end
    end
    return QBCore
end

function Bridge.GetCore()
    if Bridge.Framework == 'esx' then return getESX() end
    if Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then return getQB() end
    return nil
end

---------------------------------------------------------------------------------------------------
-- Loaded state

local loaded = false
local booted = false
local loadedHooks, unloadedHooks = {}, {}

local function runHook(fn)
    CreateThread(function()
        local ok, err = pcall(fn)
        if not ok then Utils.Print('error', ('loaded hook failed: %s'):format(err)) end
    end)
end

local function setLoaded(value)
    value = value == true
    if loaded == value then return end
    loaded = value
    DebugPrint('character', value and 'loaded' or 'unloaded')
    local hooks = value and loadedHooks or unloadedHooks
    for i = 1, #hooks do runHook(hooks[i]) end
end

local function alreadyLoaded()
    local fw = Bridge.Framework
    if fw == 'esx' then
        local core = getESX()
        if not core then return false end
        if core.IsPlayerLoaded then
            local ok, value = pcall(core.IsPlayerLoaded)
            if ok then return value == true end
        end
        return core.PlayerLoaded == true
    elseif fw == 'qbcore' or fw == 'qbox' then
        return LocalPlayer.state.isLoggedIn == true
    end
    return NetworkIsPlayerActive(PlayerId()) == true
end

function Bridge.IsLoaded()
    return loaded
end

function Bridge.OnLoaded(fn)
    if type(fn) ~= 'function' then return end
    loadedHooks[#loadedHooks + 1] = fn
    if loaded then runHook(fn) end
end

function Bridge.OnUnloaded(fn)
    if type(fn) ~= 'function' then return end
    unloadedHooks[#unloadedHooks + 1] = fn
end

if Bridge.Framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function()
        setLoaded(true)
    end)
    RegisterNetEvent('esx:onPlayerLogout', function()
        setLoaded(false)
    end)
elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        setLoaded(true)
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        setLoaded(false)
    end)
    AddStateBagChangeHandler('isLoggedIn', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
        if booted then setLoaded(value == true) end
    end)
else
    AddEventHandler('playerSpawned', function()
        setLoaded(true)
    end)
end

-- Restart support: if the character is already in, hooks run once everything has loaded.
CreateThread(function()
    if not loaded and alreadyLoaded() then
        loaded = true
        DebugPrint('character already loaded')
        for i = 1, #loadedHooks do runHook(loadedHooks[i]) end
    end
    booted = true
end)
