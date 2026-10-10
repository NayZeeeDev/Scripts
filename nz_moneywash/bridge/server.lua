--[[ THE WASH — server bridge: ESX · QBCore · Qbox  /  ox_inventory · qb-inventory ]]

Bridge = {}
local FW, INV
local ESX, QBCore

local function started(res) return GetResourceState(res) == 'started' end

---------------------------------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------------------------------
if Config.Framework ~= 'auto' then
    FW = Config.Framework
elseif started('qbx_core') then
    FW = 'qbx'
elseif started('qb-core') then
    FW = 'qb'
elseif started('es_extended') then
    FW = 'esx'
end

if FW == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
elseif FW == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
end

if Config.Inventory ~= 'auto' then
    INV = Config.Inventory
elseif started('ox_inventory') then
    INV = 'ox'
else
    INV = 'qb'
end

Bridge.framework = FW
Bridge.inventory = INV

if not FW then
    print('^1[nz_moneywash] No supported framework found (es_extended / qb-core / qbx_core).^7')
end
if FW == 'esx' and INV ~= 'ox' then
    print('^3[nz_moneywash] ESX needs ox_inventory for batch metadata. Please install ox_inventory.^7')
end

---------------------------------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------------------------------
function Bridge.getPlayer(src)
    if FW == 'esx' then return ESX.GetPlayerFromId(src) end
    if FW == 'qb' then return QBCore.Functions.GetPlayer(src) end
    if FW == 'qbx' then return exports.qbx_core:GetPlayer(src) end
end

function Bridge.getIdentifier(src)
    local p = Bridge.getPlayer(src)
    if not p then return nil end
    if FW == 'esx' then return p.identifier end
    return p.PlayerData.citizenid
end

function Bridge.getName(src)
    local p = Bridge.getPlayer(src)
    if not p then return GetPlayerName(src) or 'Unknown' end
    if FW == 'esx' then return p.getName() end
    local ci = p.PlayerData.charinfo or {}
    return ('%s %s'):format(ci.firstname or '?', ci.lastname or '?')
end

function Bridge.getJob(src)
    local p = Bridge.getPlayer(src)
    if not p then return { name = 'unemployed', grade = 0, onduty = false } end
    if FW == 'esx' then
        local j = p.job or {}
        local onduty = j.onDuty
        if onduty == nil then onduty = true end
        return { name = j.name, grade = tonumber(j.grade) or 0, onduty = onduty, label = j.label }
    end
    local j = p.PlayerData.job or {}
    local grade = type(j.grade) == 'table' and j.grade.level or j.grade
    return { name = j.name, grade = tonumber(grade) or 0, onduty = j.onduty ~= false, label = j.label }
end

function Bridge.getGang(src)
    if FW == 'esx' then return nil end
    local p = Bridge.getPlayer(src)
    local g = p and p.PlayerData.gang
    if not g or not g.name or g.name == 'none' then return nil end
    local grade = type(g.grade) == 'table' and g.grade.level or g.grade
    return { name = g.name, grade = tonumber(grade) or 0 }
end

function Bridge.getSourceByIdentifier(identifier)
    if FW == 'esx' then
        local p = ESX.GetPlayerFromIdentifier(identifier)
        return p and p.source
    elseif FW == 'qb' then
        local p = QBCore.Functions.GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source
    elseif FW == 'qbx' then
        local p = exports.qbx_core:GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source
    end
end

function Bridge.addMoney(src, account, amount, reason)
    local p = Bridge.getPlayer(src)
    if not p or amount <= 0 then return false end
    if FW == 'esx' then
        p.addAccountMoney(account == 'cash' and 'money' or account, amount, reason)
        return true
    end
    return p.Functions.AddMoney(account, amount, reason) ~= false
end

function Bridge.getAccount(src, account)
    local p = Bridge.getPlayer(src)
    if not p then return 0 end
    if FW == 'esx' then
        local acc = p.getAccount(account)
        return acc and acc.money or 0
    end
    return (p.PlayerData.money and p.PlayerData.money[account]) or 0
end

function Bridge.removeAccount(src, account, amount, reason)
    local p = Bridge.getPlayer(src)
    if not p then return false end
    if FW == 'esx' then
        p.removeAccountMoney(account, amount, reason)
        return true
    end
    return p.Functions.RemoveMoney(account, amount, reason) ~= false
end

function Bridge.countPolice()
    local n = 0
    for _, id in ipairs(GetPlayers()) do
        if NZ.isPoliceJob(Bridge.getJob(tonumber(id))) then n = n + 1 end
    end
    return n
end

function Bridge.eachPlayer(fn)
    for _, id in ipairs(GetPlayers()) do fn(tonumber(id)) end
end

function Bridge.registerUsable(item, cb)
    if FW == 'esx' then
        ESX.RegisterUsableItem(item, function(src) cb(src) end)
    elseif FW == 'qb' then
        QBCore.Functions.CreateUseableItem(item, function(src) cb(src) end)
    elseif FW == 'qbx' then
        exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    end
end

---------------------------------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------------------------------
Inv = {}

local function qbItems(src)
    local p = Bridge.getPlayer(src)
    return p and p.PlayerData.items or {}
end

function Inv.count(src, name)
    if INV == 'ox' then
        return exports.ox_inventory:Search(src, 'count', name) or 0
    end
    local n = 0
    for _, it in pairs(qbItems(src)) do
        if it and it.name == name then n = n + (it.amount or it.count or 1) end
    end
    return n
end

-- returns { { slot = n, count = n, metadata = {} }, ... }
function Inv.slots(src, name)
    local out = {}
    if INV == 'ox' then
        for _, s in pairs(exports.ox_inventory:Search(src, 'slots', name) or {}) do
            out[#out + 1] = { slot = s.slot, count = s.count, metadata = s.metadata or {} }
        end
        return out
    end
    for _, it in pairs(qbItems(src)) do
        if it and it.name == name then
            out[#out + 1] = { slot = it.slot, count = it.amount or it.count or 1, metadata = it.info or {} }
        end
    end
    return out
end

function Inv.canCarry(src, name, count, meta)
    if INV == 'ox' then
        return exports.ox_inventory:CanCarryItem(src, name, count, meta) ~= false
    end
    if started('qb-inventory') then
        local ok, res = pcall(function() return exports['qb-inventory']:CanAddItem(src, name, count) end)
        if ok and res == false then return false end
    end
    return true
end

function Inv.add(src, name, count, meta)
    if INV == 'ox' then
        local ok = exports.ox_inventory:AddItem(src, name, count, meta)
        return ok and true or false
    end
    local p = Bridge.getPlayer(src)
    if not p then return false end
    local ok = p.Functions.AddItem(name, count, false, meta)
    if ok and QBCore then
        local shared = QBCore.Shared.Items[name]
        if shared then TriggerClientEvent('qb-inventory:client:ItemBox', src, shared, 'add', count) end
    end
    return ok and true or false
end

function Inv.remove(src, name, count, slot)
    if INV == 'ox' then
        return exports.ox_inventory:RemoveItem(src, name, count, nil, slot) and true or false
    end
    local p = Bridge.getPlayer(src)
    if not p then return false end
    return p.Functions.RemoveItem(name, count, slot) and true or false
end

-- every slot of `name` that carries a batch id, newest data from the server-side batch table
function Inv.batchSlots(src, name)
    local out = {}
    for _, s in ipairs(Inv.slots(src, name)) do
        if s.metadata and s.metadata.batch then out[#out + 1] = s end
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- Notify / Log
---------------------------------------------------------------------------------------------------
function Bridge.notify(src, title, message, kind, duration)
    TriggerClientEvent('nzmw:notify', src, { title = title, message = message, type = kind or 'info', duration = duration })
end

function Bridge.log(title, fields)
    if not SvConfig.Webhook or SvConfig.Webhook == '' then return end
    local list = {}
    for _, f in ipairs(fields or {}) do
        list[#list + 1] = { name = f[1], value = tostring(f[2]), inline = f[3] ~= false }
    end
    PerformHttpRequest(SvConfig.Webhook, function() end, 'POST', json.encode({
        username = SvConfig.WebhookName,
        embeds = { {
            title = title,
            color = SvConfig.WebhookColour,
            fields = list,
            footer = { text = 'nz_moneywash' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end
