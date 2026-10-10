--[[ THE WASH — client bridge: framework data, inventory checks, targeting ]]

CBridge = {}
local FW, INV, TGT
local ESX, QBCore

local function started(res) return GetResourceState(res) == 'started' end

if Config.Framework ~= 'auto' then FW = Config.Framework
elseif started('qbx_core') then FW = 'qbx'
elseif started('qb-core') then FW = 'qb'
elseif started('es_extended') then FW = 'esx' end

if FW == 'esx' then ESX = exports['es_extended']:getSharedObject()
elseif FW == 'qb' then QBCore = exports['qb-core']:GetCoreObject() end

if Config.Inventory ~= 'auto' then INV = Config.Inventory
elseif started('ox_inventory') then INV = 'ox'
else INV = 'qb' end

if Config.Target ~= 'auto' then TGT = Config.Target
elseif started('ox_target') then TGT = 'ox'
elseif started('qb-target') then TGT = 'qb'
else TGT = 'none' end

CBridge.framework, CBridge.inventory, CBridge.target = FW, INV, TGT

local function playerData()
    if FW == 'esx' then return ESX.GetPlayerData() or {} end
    if FW == 'qb' then return QBCore.Functions.GetPlayerData() or {} end
    if FW == 'qbx' then return exports.qbx_core:GetPlayerData() or {} end
    return {}
end

function CBridge.getJob()
    local pd = playerData()
    local j = pd.job or {}
    if FW == 'esx' then
        local onduty = j.onDuty
        if onduty == nil then onduty = true end
        return { name = j.name, grade = tonumber(j.grade) or 0, onduty = onduty }
    end
    local grade = type(j.grade) == 'table' and j.grade.level or j.grade
    return { name = j.name, grade = tonumber(grade) or 0, onduty = j.onduty ~= false }
end

function CBridge.getGang()
    if FW == 'esx' then return nil end
    local g = playerData().gang
    if not g or not g.name or g.name == 'none' then return nil end
    local grade = type(g.grade) == 'table' and g.grade.level or g.grade
    return { name = g.name, grade = tonumber(grade) or 0 }
end

function CBridge.getIdentifier()
    local pd = playerData()
    if FW == 'esx' then return pd.identifier end
    return pd.citizenid
end

function CBridge.hasItem(name, amount)
    amount = amount or 1
    if INV == 'ox' then
        return (exports.ox_inventory:Search('count', name) or 0) >= amount
    end
    if QBCore then return QBCore.Functions.HasItem(name, amount) end
    if FW == 'qbx' then
        local n = 0
        for _, it in pairs(playerData().items or {}) do
            if it.name == name then n = n + (it.amount or it.count or 1) end
        end
        return n >= amount
    end
    return false
end

function CBridge.hasAny(list)
    for _, item in ipairs(list) do
        if CBridge.hasItem(item) then return true end
    end
    return false
end

function CBridge.isPolice() return NZ.isPoliceJob(CBridge.getJob()) end
function CBridge.isAuditor() return NZ.isAuditJob(CBridge.getJob()) end

---------------------------------------------------------------------------------------------------
-- Targeting
-- option = { name, label, icon, distance, canInteract = fn() -> bool, onSelect = fn() }
---------------------------------------------------------------------------------------------------
Target = {}
local fallbackZones = {}

function Target.addZone(id, coords, radius, options)
    if TGT == 'ox' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                name = id .. ':' .. o.name,
                label = o.label,
                icon = o.icon,
                distance = o.distance or 2.0,
                canInteract = function() return o.canInteract == nil or o.canInteract() end,
                onSelect = function() o.onSelect() end,
            }
        end
        return exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = Config.Debug, options = opts })
    elseif TGT == 'qb' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                label = o.label,
                icon = o.icon,
                action = function() o.onSelect() end,
                canInteract = function() return o.canInteract == nil or o.canInteract() end,
            }
        end
        exports['qb-target']:AddCircleZone(id, coords, radius, { name = id, debugPoly = Config.Debug, useZ = true },
            { options = opts, distance = 2.0 })
        return id
    end
    fallbackZones[id] = { coords = coords, radius = radius, options = options }
    return id
end

function Target.removeZone(handle)
    if not handle then return end
    if TGT == 'ox' then exports.ox_target:removeZone(handle)
    elseif TGT == 'qb' then exports['qb-target']:RemoveZone(handle)
    else fallbackZones[handle] = nil end
end

function Target.addGlobalPlayer(options)
    if TGT == 'ox' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                name = 'nzmw:' .. o.name, label = o.label, icon = o.icon, distance = o.distance or 2.0,
                canInteract = function(entity) return o.canInteract == nil or o.canInteract(entity) end,
                onSelect = function(data) o.onSelect(data.entity) end,
            }
        end
        exports.ox_target:addGlobalPlayer(opts)
    elseif TGT == 'qb' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                label = o.label, icon = o.icon,
                canInteract = function(entity) return o.canInteract == nil or o.canInteract(entity) end,
                action = function(entity) o.onSelect(entity) end,
            }
        end
        exports['qb-target']:AddGlobalPlayer({ options = opts, distance = 2.0 })
    end
    -- fallback: /uvscan command (client/police.lua)
end

-- Built-in prompt when no target resource exists: [E] opens a context menu of available options
if TGT == 'none' then
    CreateThread(function()
        local shown = false
        while true do
            local sleep = 500
            local pos = GetEntityCoords(PlayerPedId())
            local best, bestDist
            for id, z in pairs(fallbackZones) do
                local d = #(pos - z.coords)
                if d < z.radius + 1.2 and (not bestDist or d < bestDist) then best, bestDist = id, d end
            end
            if best then
                sleep = 0
                if not shown then lib.showTextUI('[E] Interact', { position = 'left-center' }); shown = true end
                if IsControlJustReleased(0, 38) then
                    local menu = {}
                    for _, o in ipairs(fallbackZones[best].options) do
                        if o.canInteract == nil or o.canInteract() then
                            menu[#menu + 1] = { title = o.label, icon = o.icon, onSelect = o.onSelect }
                        end
                    end
                    if #menu > 0 then
                        lib.registerContext({ id = 'nzmw_ctx', title = Config.UI.brand, options = menu })
                        lib.showContext('nzmw_ctx')
                    end
                end
            elseif shown then
                lib.hideTextUI(); shown = false
            end
            Wait(sleep)
        end
    end)
end
