-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Framework bridge (server). Auto-detects ESX / QBCore / Qbox, falls back to standalone.
-- Everything framework-specific lives here, so this is the only file to touch for a custom setup.
Bridge = { name = 'standalone' }

local ESX, QB
local ox = GetResourceState('ox_inventory') == 'started'

-- SquadsConfig.Framework picks one; 'auto' takes the first framework that's installed.
local want = (SquadsConfig.Framework or 'auto'):lower()
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

---@param src number
---@return string
function Bridge.GetName(src)
    if SquadsConfig.UseCharacterName then
        if Bridge.name == 'esx' then
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer then
                local n = xPlayer.getName and xPlayer.getName()
                if n and n ~= '' then return n end
            end
        elseif Bridge.name == 'qbx' then
            local p = exports.qbx_core:GetPlayer(src)
            if p then return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) end
        elseif Bridge.name == 'qb' then
            local p = QB.Functions.GetPlayer(src)
            if p then return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) end
        end
    end
    return GetPlayerName(src) or ('Player %s'):format(src)
end

--- Stable per-character id. Squad membership, ranks and stats are stored against this.
---@param src number
---@return string|nil
function Bridge.GetIdentifier(src)
    if Bridge.name == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then return xPlayer.identifier end
    elseif Bridge.name == 'qbx' then
        local p = exports.qbx_core:GetPlayer(src)
        if p then return p.PlayerData.citizenid end
    elseif Bridge.name == 'qb' then
        local p = QB.Functions.GetPlayer(src)
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
    elseif Bridge.name == 'qbx' then
        local p = exports.qbx_core:GetPlayer(src)
        local it = p and exports.ox_inventory:GetItem(src, item, nil, false)
        return it ~= nil and (it.count or 0) >= count
    elseif Bridge.name == 'qb' then
        local p = QB.Functions.GetPlayer(src)
        local it = p and p.Functions.GetItemByName(item)
        return it ~= nil and it.amount >= count
    end
    return false
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
    elseif Bridge.name == 'qb' or Bridge.name == 'qbx' then
        local p = Bridge.name == 'qb' and QB.Functions.GetPlayer(src) or exports.qbx_core:GetPlayer(src)
        if not p then return false end
        return p.Functions.RemoveItem(item, count) == true
    end
    return false
end

--- Puts a downed player back on their feet. Point this at your ambulance job.
---@param src number
---@param health number 0-100 scale
function Bridge.Revive(src, health)
    TriggerClientEvent('nz_squads:client:revive', src, health)

    if Bridge.name == 'esx' then
        -- esx_ambulancejob / standalone handled client-side, nothing else needed here
    elseif Bridge.name == 'qbx' or Bridge.name == 'qb' then
        local p = Bridge.name == 'qb' and QB.Functions.GetPlayer(src) or exports.qbx_core:GetPlayer(src)
        if p then
            p.Functions.SetMetaData('isdead', false)
            p.Functions.SetMetaData('inlaststand', false)
        end
    end
end
