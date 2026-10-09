Bridge = {}

lib.locale(Config.Locale)

local framework = Config.Framework
if framework == 'qbox' then framework = 'qbx' end
if framework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then framework = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then framework = 'qb'
    elseif GetResourceState('es_extended') == 'started' then framework = 'esx'
    else framework = 'standalone' end
end
Bridge.Framework = framework

local QB, ESX
if framework == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
elseif framework == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

local function getPlayer(src)
    if framework == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if framework == 'qb' then return QB.Functions.GetPlayer(src) end
    if framework == 'esx' then return ESX.GetPlayerFromId(src) end
end

function Bridge.GetLicense(src)
    return GetPlayerIdentifierByType(src, 'license')
        or GetPlayerIdentifierByType(src, 'license2')
        or GetPlayerIdentifierByType(src, 'fivem')
end

--- The key a sentence is stored under (see Config.Scope). nil = not ready yet (no character loaded).
function Bridge.GetIdentifier(src)
    if Config.Scope ~= 'character' or framework == 'standalone' then
        return Bridge.GetLicense(src)
    end
    local player = getPlayer(src)
    if not player then return nil end
    if framework == 'esx' then return player.identifier end
    return player.PlayerData and player.PlayerData.citizenid
end

--- In-character name if a character is loaded, otherwise the account name.
function Bridge.GetName(src)
    local player = getPlayer(src)
    if player then
        if framework == 'esx' then
            local name = player.getName and player.getName()
            if name and name ~= '' then return name end
        else
            local info = player.PlayerData and player.PlayerData.charinfo
            if info and info.firstname then return ('%s %s'):format(info.firstname, info.lastname or '') end
        end
    end
    return GetPlayerName(src) or ('Player %s'):format(src)
end

function Bridge.GetAccountName(src)
    if src == 0 then return 'Console' end
    return GetPlayerName(src) or ('Player %s'):format(src)
end

function Bridge.HasPermission(src)
    if src == 0 then return true end
    local perms = Config.Permissions

    for i = 1, #perms.aces do
        if IsPlayerAceAllowed(src, perms.aces[i]) then return true end
    end

    for i = 1, #perms.groups do
        local group = perms.groups[i]
        if IsPlayerAceAllowed(src, 'group.' .. group) then return true end

        if framework == 'qb' then
            if QB.Functions.HasPermission(src, group) then return true end
        elseif framework == 'qbx' then
            local ok, allowed = pcall(exports.qbx_core.HasPermission, exports.qbx_core, src, 'group.' .. group)
            if ok and allowed then return true end
        end
    end

    if framework == 'esx' then
        local player = getPlayer(src)
        local group = player and player.getGroup and player.getGroup()
        if group then
            for i = 1, #perms.groups do
                if perms.groups[i] == group then return true end
            end
        end
    end

    return false
end

function Bridge.Notify(src, msg, kind)
    if src == 0 then
        print(('^5[%s]^7 %s'):format(AJ.Resource, msg))
        return
    end
    TriggerClientEvent(AJ.Event('client:notify'), src, msg, kind)
end

--- Framework "character loaded / unloaded" hooks. Spawn handling itself happens client side.
function Bridge.OnLoaded(cb)
    if framework == 'qb' or framework == 'qbx' then
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            local src = player and player.PlayerData and player.PlayerData.source
            if src then cb(src) end
        end)
    elseif framework == 'esx' then
        AddEventHandler('esx:playerLoaded', function(playerId) cb(playerId) end)
    end
end

function Bridge.OnUnloaded(cb)
    if framework == 'qb' or framework == 'qbx' then
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) cb(src) end)
    elseif framework == 'esx' then
        AddEventHandler('esx:playerLogout', function(playerId) cb(playerId) end)
    end
end
