-- Framework bridge (server). Auto-detects ESX / QBCore / Qbox, falls back to standalone.
-- Everything framework-specific lives here, so this is the only file to touch for a custom setup.
Bridge = { name = 'standalone' }

local ESX, QB
local ox = GetResourceState('ox_inventory') == 'started'

local want = (Config.Framework or 'auto'):lower()
local function has(res) return GetResourceState(res) ~= 'missing' end

if want == 'esx' or (want == 'auto' and has('es_extended')) then
    Bridge.name = 'esx'
    ESX = exports['es_extended']:getSharedObject()
elseif want == 'qbx' or (want == 'auto' and has('qbx_core')) then
    Bridge.name = 'qbx'
elseif want == 'qbcore' or want == 'qb' or (want == 'auto' and has('qb-core')) then
    Bridge.name = 'qb'
    QB = exports['qb-core']:GetCoreObject()
end

local function qbPlayer(src)
    if Bridge.name == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if Bridge.name == 'qb' then return QB.Functions.GetPlayer(src) end
    return nil
end

---@param src number
---@return string
function Bridge.GetName(src)
    if Config.UseCharacterName then
        if Bridge.name == 'esx' then
            local xPlayer = ESX.GetPlayerFromId(src)
            local n = xPlayer and xPlayer.getName and xPlayer.getName()
            if n and n ~= '' then return n end
        else
            local p = qbPlayer(src)
            if p and p.PlayerData and p.PlayerData.charinfo then
                return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname)
            end
        end
    end
    return GetPlayerName(src) or ('Player %s'):format(src)
end

--- Stable per-character id. Membership, ranks and stats are stored against this.
---@param src number
---@return string|nil
function Bridge.GetIdentifier(src)
    if Bridge.name == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then return xPlayer.identifier end
    else
        local p = qbPlayer(src)
        if p then return p.PlayerData.citizenid end
    end
    return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifierByType(src, 'fivem')
end

--- Gate who can use squads (jobs, VIP, etc).
---@param src number
---@return boolean
function Bridge.CanUse(src)
    return true
end

---@return boolean
function Bridge.HasItem(src, item, count)
    count = count or 1
    if ox then
        return (exports.ox_inventory:GetItemCount(src, item) or 0) >= count
    elseif Bridge.name == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        local it = xPlayer and xPlayer.getInventoryItem(item)
        return it ~= nil and it.count >= count
    else
        local p = qbPlayer(src)
        local it = p and p.Functions.GetItemByName(item)
        return it ~= nil and (it.amount or it.count or 0) >= count
    end
end

---@return boolean removed
function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if ox then
        return exports.ox_inventory:RemoveItem(src, item, count) == true
    elseif Bridge.name == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.removeInventoryItem(item, count)
        return true
    else
        local p = qbPlayer(src)
        if not p then return false end
        return p.Functions.RemoveItem(item, count) == true
    end
end

--- Puts a downed player back on their feet. Point this at your ambulance job if you use one.
---@param src number
---@param health number 0-100 scale
function Bridge.Revive(src, health)
    TriggerClientEvent('nz_squads:client:revive', src, health)
    local p = qbPlayer(src)
    if p then
        p.Functions.SetMetaData('isdead', false)
        p.Functions.SetMetaData('inlaststand', false)
    end
end
