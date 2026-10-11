--[[
    Server bridge: everything framework / inventory / keys specific lives here.
    Supports ESX Legacy, QBCore and Qbox out of the box. Edit freely.
]]

Bridge = {}

local fw = Config.Framework
if fw == 'auto' then
    if GetResourceState('qbx_core') == 'started' then fw = 'qbx'
    elseif GetResourceState('es_extended') == 'started' then fw = 'esx'
    elseif GetResourceState('qb-core') == 'started' then fw = 'qb'
    else fw = 'none' end
end
Bridge.Framework = fw

local ESX, QB
if fw == 'esx' then ESX = exports.es_extended:getSharedObject()
elseif fw == 'qb' then QB = exports['qb-core']:GetCoreObject() end

local useOx = GetResourceState('ox_inventory') == 'started'

local function qbPlayer(src)
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    return QB and QB.Functions.GetPlayer(src)
end

--------------------------------------------------------------------- players

function Bridge.GetPlayer(src)
    if fw == 'esx' then return ESX.GetPlayerFromId(src) end
    return qbPlayer(src)
end

function Bridge.GetIdentifier(src)
    local p = Bridge.GetPlayer(src)
    if not p then return nil end
    if fw == 'esx' then return p.identifier end
    return p.PlayerData.citizenid
end

function Bridge.GetName(src)
    local p = Bridge.GetPlayer(src)
    if not p then return GetPlayerName(src) or ('#' .. src) end
    if fw == 'esx' then return p.getName and p.getName() or p.name end
    local ci = p.PlayerData.charinfo or {}
    return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', '')
end

function Bridge.GetSourceFromIdentifier(identifier)
    if fw == 'esx' then
        local p = ESX.GetPlayerFromIdentifier(identifier)
        return p and p.source
    elseif fw == 'qbx' then
        local p = exports.qbx_core:GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source
    elseif QB then
        local p = QB.Functions.GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source
    end
end

-- { name, label, grade, gradeLabel, onDuty }
function Bridge.GetJob(src)
    local p = Bridge.GetPlayer(src)
    if not p then return { name = 'none', label = 'None', grade = 0, gradeLabel = '', onDuty = false } end
    if fw == 'esx' then
        local j = p.job
        return { name = j.name, label = j.label, grade = j.grade, gradeLabel = j.grade_label, onDuty = j.onDuty ~= false }
    end
    local j = p.PlayerData.job
    return { name = j.name, label = j.label, grade = j.grade and j.grade.level or 0, gradeLabel = j.grade and j.grade.name or '', onDuty = j.onduty ~= false }
end

function Bridge.SetJob(src, job, grade)
    local p = Bridge.GetPlayer(src)
    if not p then return false end
    if fw == 'esx' then p.setJob(job, grade) return true end
    p.Functions.SetJob(job, grade)
    return true
end

function Bridge.SetJobOffline(identifier, job, grade)
    if fw == 'esx' then
        MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { job, grade, identifier })
    else
        local jobs = Bridge.GetJobs()
        local jd = jobs[job] or {}
        local g = jd.grades and jd.grades[grade] or {}
        local data = json.encode({ name = job, label = jd.label or job, onduty = false, payment = g.payment or 0,
            grade = { level = grade, name = g.label or tostring(grade) }, isboss = g.isboss or false })
        MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { data, identifier })
    end
end

-- { [job] = { label, grades = { [level] = { label, payment, isboss } } } }
function Bridge.GetJobs()
    local out = {}
    if fw == 'esx' then
        for name, j in pairs(ESX.GetJobs()) do
            local grades = {}
            for lvl, g in pairs(j.grades or {}) do
                grades[tonumber(lvl)] = { label = g.label, payment = g.salary, isboss = g.name == 'boss' }
            end
            out[name] = { label = j.label, grades = grades }
        end
    else
        local jobs = fw == 'qbx' and exports.qbx_core:GetJobs() or (QB and QB.Shared.Jobs) or {}
        for name, j in pairs(jobs) do
            local grades = {}
            for lvl, g in pairs(j.grades or {}) do
                grades[tonumber(lvl)] = { label = g.name, payment = g.payment, isboss = g.isboss }
            end
            out[name] = { label = j.label, grades = grades }
        end
    end
    return out
end

-- every character with a job (online + offline): { identifier, name, grade, online, source }
function Bridge.GetEmployees(job)
    local list = {}
    if fw == 'esx' then
        local rows = MySQL.query.await('SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ?', { job }) or {}
        for _, r in ipairs(rows) do
            list[#list + 1] = { identifier = r.identifier, name = ((r.firstname or '') .. ' ' .. (r.lastname or '')), grade = r.job_grade }
        end
    elseif fw ~= 'none' then
        local rows = MySQL.query.await("SELECT citizenid, charinfo, job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?", { job }) or {}
        for _, r in ipairs(rows) do
            local ci, jb = json.decode(r.charinfo or '{}') or {}, json.decode(r.job or '{}') or {}
            list[#list + 1] = { identifier = r.citizenid, name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')), grade = jb.grade and jb.grade.level or 0 }
        end
    end
    for i = #list, 1, -1 do
        local e = list[i]
        e.source = Bridge.GetSourceFromIdentifier(e.identifier)
        e.online = e.source ~= nil
        if e.online then
            local j = Bridge.GetJob(e.source)
            -- the DB job column lags behind (saved on an interval): trust the live job for online players
            if j.name ~= job then table.remove(list, i) else e.grade, e.onDuty = j.grade, j.onDuty end
        end
    end
    return list
end

function Bridge.GetPlayersWithJob(job, dutyOnly)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local j = Bridge.GetJob(src)
        if j.name == job and (not dutyOnly or j.onDuty) then out[#out + 1] = src end
    end
    return out
end

function Bridge.CountJobs(jobs)
    local set, n = {}, 0
    for _, j in ipairs(jobs) do set[j] = true end
    for _, id in ipairs(GetPlayers()) do
        local j = Bridge.GetJob(tonumber(id))
        if set[j.name] and j.onDuty then n = n + 1 end
    end
    return n
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.Admin.Ace) then return true end
    if fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        return p and (p.getGroup() == 'admin' or p.getGroup() == 'superadmin')
    end
    return false
end

--------------------------------------------------------------------- money

local accountMap = { cash = { esx = 'money', qb = 'cash' }, bank = { esx = 'bank', qb = 'bank' } }

function Bridge.GetMoney(src, account)
    local p = Bridge.GetPlayer(src)
    if not p then return 0 end
    if fw == 'esx' then
        local acc = p.getAccount(accountMap[account].esx)
        return acc and acc.money or 0
    end
    return p.PlayerData.money[accountMap[account].qb] or 0
end

function Bridge.RemoveMoney(src, account, amount, reason)
    if not NZ.Num(amount) or not accountMap[account] then return false end
    if amount <= 0 then return true end
    if Bridge.GetMoney(src, account) < amount then return false end
    local p = Bridge.GetPlayer(src)
    if not p then return false end
    if fw == 'esx' then p.removeAccountMoney(accountMap[account].esx, amount, reason) return true end
    return p.Functions.RemoveMoney(accountMap[account].qb, amount, reason) ~= false
end

function Bridge.AddMoney(src, account, amount, reason)
    if not NZ.Num(amount) or not accountMap[account] then return false end
    if amount <= 0 then return true end
    local p = Bridge.GetPlayer(src)
    if not p then return false end
    if fw == 'esx' then p.addAccountMoney(accountMap[account].esx, amount, reason) return true end
    p.Functions.AddMoney(accountMap[account].qb, amount, reason)
    return true
end

-- used for refunds / wages when the player is offline
function Bridge.AddBankOffline(identifier, amount)
    local src = Bridge.GetSourceFromIdentifier(identifier)
    if src then return Bridge.AddMoney(src, 'bank', amount, 'nayzeee-tuning') end
    if fw == 'esx' then
        local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ?', { identifier })
        if not row then return false end
        local acc = json.decode(row.accounts or '{}') or {}
        acc.bank = (acc.bank or 0) + amount
        MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(acc), identifier })
    else
        local row = MySQL.single.await('SELECT money FROM players WHERE citizenid = ?', { identifier })
        if not row then return false end
        local m = json.decode(row.money or '{}') or {}
        m.bank = (m.bank or 0) + amount
        MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(m), identifier })
    end
    return true
end

--------------------------------------------------------------------- society (only used when Config.Business.UseBuiltInBalance = false)

function Bridge.SocietyGet(society)
    if not society then return 0 end
    if fw == 'esx' then
        local p = promise.new()
        TriggerEvent('esx_addonaccount:getSharedAccount', society, function(acc) p:resolve(acc and acc.money or 0) end)
        return Citizen.Await(p)
    end
    local name = society:gsub('^society_', '')
    if GetResourceState('Renewed-Banking') == 'started' then return exports['Renewed-Banking']:getAccountMoney(name) or 0 end
    if GetResourceState('qb-management') == 'started' then return exports['qb-management']:GetAccount(name) or 0 end
    return 0
end

function Bridge.SocietyAdd(society, amount)
    if not society or amount <= 0 then return end
    if fw == 'esx' then
        TriggerEvent('esx_addonaccount:getSharedAccount', society, function(acc) if acc then acc.addMoney(amount) end end)
        return
    end
    local name = society:gsub('^society_', '')
    if GetResourceState('Renewed-Banking') == 'started' then exports['Renewed-Banking']:addAccountMoney(name, amount)
    elseif GetResourceState('qb-management') == 'started' then exports['qb-management']:AddMoney(name, amount) end
end

function Bridge.SocietyRemove(society, amount)
    if not society or amount <= 0 then return true end
    if Bridge.SocietyGet(society) < amount then return false end
    if fw == 'esx' then
        TriggerEvent('esx_addonaccount:getSharedAccount', society, function(acc) if acc then acc.removeMoney(amount) end end)
        return true
    end
    local name = society:gsub('^society_', '')
    if GetResourceState('Renewed-Banking') == 'started' then return exports['Renewed-Banking']:removeAccountMoney(name, amount) ~= false end
    if GetResourceState('qb-management') == 'started' then return exports['qb-management']:RemoveMoney(name, amount) ~= false end
    return false
end

--------------------------------------------------------------------- items

function Bridge.ItemCount(src, item)
    if useOx then return exports.ox_inventory:Search(src, 'count', item) or 0 end
    local p = Bridge.GetPlayer(src)
    if not p then return 0 end
    if fw == 'esx' then local i = p.getInventoryItem(item) return i and i.count or 0 end
    local i = p.Functions.GetItemByName(item)
    return i and i.amount or 0
end

function Bridge.RemoveItem(src, item, count)
    if Bridge.ItemCount(src, item) < count then return false end
    if useOx then return exports.ox_inventory:RemoveItem(src, item, count) end
    local p = Bridge.GetPlayer(src)
    if fw == 'esx' then p.removeInventoryItem(item, count) return true end
    return p.Functions.RemoveItem(item, count)
end

function Bridge.AddItem(src, item, count)
    if useOx then
        if not exports.ox_inventory:CanCarryItem(src, item, count) then return false end
        return exports.ox_inventory:AddItem(src, item, count)
    end
    local p = Bridge.GetPlayer(src)
    if fw == 'esx' then p.addInventoryItem(item, count) return true end
    return p.Functions.AddItem(item, count)
end

local labelCache = {}
function Bridge.ItemLabel(item)
    if labelCache[item] then return labelCache[item] end
    local label
    if useOx then
        local data = exports.ox_inventory:Items(item)
        label = data and data.label
    elseif fw == 'esx' then
        label = ESX.GetItemLabel and ESX.GetItemLabel(item)
    elseif fw == 'qbx' or QB then
        local items = fw == 'qbx' and exports.ox_inventory:Items() or (QB and QB.Shared.Items) or {}
        label = items[item] and items[item].label
    end
    label = label or item:gsub('_', ' '):gsub('^%l', string.upper)
    labelCache[item] = label
    return label
end

function Bridge.RegisterUsableItem(item, cb)
    if fw == 'esx' then ESX.RegisterUsableItem(item, cb)
    elseif fw == 'qbx' then exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    elseif QB then QB.Functions.CreateUseableItem(item, function(src) cb(src) end) end
end

--------------------------------------------------------------------- vehicles

local vehTable = fw == 'esx' and 'owned_vehicles' or 'player_vehicles'
local ownerCol = fw == 'esx' and 'owner' or 'citizenid'
local propsCol = fw == 'esx' and 'vehicle' or 'mods'
Bridge.VehicleTable, Bridge.OwnerColumn, Bridge.PropsColumn = vehTable, ownerCol, propsCol

function Bridge.GetVehicleOwner(plate)
    plate = NZ.TrimPlate(plate)
    if plate == '' then return nil end
    local row = MySQL.single.await(('SELECT %s AS owner FROM %s WHERE plate = ? OR plate = ? LIMIT 1'):format(ownerCol, vehTable), { plate, ('%-8s'):format(plate) })
    return row and row.owner
end

function Bridge.GetVehicleProps(plate)
    local row = MySQL.single.await(('SELECT %s AS props FROM %s WHERE plate = ? OR plate = ? LIMIT 1'):format(propsCol, vehTable), { NZ.TrimPlate(plate), ('%-8s'):format(NZ.TrimPlate(plate)) })
    return row and json.decode(row.props or '{}') or nil
end

function Bridge.SaveVehicleProps(plate, props)
    plate = NZ.TrimPlate(plate)
    return MySQL.update.await(('UPDATE %s SET %s = ? WHERE plate = ? OR plate = ?'):format(vehTable, propsCol), { json.encode(props), plate, ('%-8s'):format(plate) }) > 0
end

function Bridge.PlateExists(plate)
    plate = NZ.TrimPlate(plate)
    return MySQL.scalar.await(('SELECT 1 FROM %s WHERE plate = ? OR plate = ? LIMIT 1'):format(vehTable), { plate, ('%-8s'):format(plate) }) ~= nil
end

function Bridge.UpdatePlate(oldPlate, newPlate)
    oldPlate = NZ.TrimPlate(oldPlate)
    MySQL.update.await(('UPDATE %s SET plate = ? WHERE plate = ? OR plate = ?'):format(vehTable), { newPlate, oldPlate, ('%-8s'):format(oldPlate) })
    for _, t in ipairs(Config.Plates.ExtraTables) do
        MySQL.update.await(('UPDATE %s SET %s = ? WHERE %s = ?'):format(t.table, t.column, t.column), { newPlate, oldPlate })
    end
end

function Bridge.GiveKeys(src, plate, netId)
    if GetResourceState('wasabi_carlock') == 'started' then
        pcall(function() exports.wasabi_carlock:GiveKey(src, plate) end)
    elseif GetResourceState('qbx_vehiclekeys') == 'started' then
        local veh = netId and NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 then pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end) end
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    elseif GetResourceState('MrNewbVehicleKeys') == 'started' then
        pcall(function() exports.MrNewbVehicleKeys:GiveKeysByPlate(src, plate) end)
    end
end

-- model name -> price, loaded once from the framework tables
function Bridge.LoadVehiclePrices()
    local out = {}
    if fw == 'esx' then
        local ok, rows = pcall(MySQL.query.await, 'SELECT model, price FROM vehicles')
        if ok and rows then for _, r in ipairs(rows) do out[r.model:lower()] = r.price end end
    elseif fw == 'qbx' then
        local ok, vehicles = pcall(function() return exports.qbx_core:GetVehiclesByName() end)
        if ok and vehicles then for model, v in pairs(vehicles) do out[model:lower()] = v.price end end
    elseif QB then
        for model, v in pairs(QB.Shared.Vehicles or {}) do out[model:lower()] = v.price end
    end
    return out
end

-- plates of every vehicle the identifier owns
function Bridge.GetOwnedPlates(identifier)
    local rows = MySQL.query.await(('SELECT plate FROM %s WHERE %s = ?'):format(vehTable, ownerCol), { identifier }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = NZ.TrimPlate(r.plate) end
    return out
end

-- { { plate, model (hash) } } for every vehicle an identifier owns
function Bridge.GetOwnedVehicles(identifier)
    local rows = MySQL.query.await(('SELECT plate, %s AS props FROM %s WHERE %s = ?'):format(propsCol, vehTable, ownerCol), { identifier }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ok, props = pcall(json.decode, r.props or '{}')
        out[#out + 1] = { plate = NZ.TrimPlate(r.plate), model = ok and props and props.model or 0 }
    end
    return out
end
