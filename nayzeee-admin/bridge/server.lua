-- Framework + inventory bridge. Everything framework specific on the server lives here.
Bridge = { fw = 'standalone', inv = 'none' }
local ESX, QB

local function started(r) return GetResourceState(r) == 'started' end

CreateThread(function()
    local fw = Config.Framework
    if fw == 'auto' then
        if started('qbx_core') then fw = 'qbox'
        elseif started('es_extended') then fw = 'esx'
        elseif started('qb-core') then fw = 'qb'
        else fw = 'standalone' end
    end
    Bridge.fw = fw
    if fw == 'esx' then ESX = exports.es_extended:getSharedObject()
    elseif fw == 'qb' or fw == 'qbox' then
        if started('qb-core') then QB = exports['qb-core']:GetCoreObject() end
    end

    local inv = Config.Inventory
    if inv == 'auto' then
        if started('ox_inventory') then inv = 'ox_inventory'
        elseif started('qb-inventory') or started('ps-inventory') or started('lj-inventory') then inv = 'qb-inventory'
        elseif fw == 'esx' then inv = 'esx'
        elseif fw == 'qb' or fw == 'qbox' then inv = 'qb-inventory'
        else inv = 'none' end
    end
    Bridge.inv = inv
    print(('^6[nayzeee-admin]^7 framework: ^5%s^7 · inventory: ^5%s^7'):format(fw, inv))
end)

local function isQB() return Bridge.fw == 'qb' or Bridge.fw == 'qbox' end

-- ─── player object ──────────────────────────────────────────────────────
function Bridge.GetPlayer(src)
    src = tonumber(src)
    if Bridge.fw == 'esx' then return ESX and ESX.GetPlayerFromId(src)
    elseif Bridge.fw == 'qbox' then return exports.qbx_core:GetPlayer(src)
    elseif Bridge.fw == 'qb' then return QB and QB.Functions.GetPlayer(src) end
end

--- Character id (ESX identifier / QB citizenid). Falls back to license so standalone still works.
function Bridge.CharId(src)
    local p = Bridge.GetPlayer(src)
    if p then
        if Bridge.fw == 'esx' then return p.identifier end
        if isQB() then return p.PlayerData.citizenid end
    end
    return GetPlayerIdentifierByType(src, 'license')
end

function Bridge.CharName(src)
    local p = Bridge.GetPlayer(src)
    if p then
        if Bridge.fw == 'esx' then return p.getName() end
        if isQB() then local c = p.PlayerData.charinfo; return (c.firstname or '') .. ' ' .. (c.lastname or '') end
    end
    return GetPlayerName(src)
end

function Bridge.IsLoaded(src)
    if Bridge.fw == 'standalone' then return true end
    return Bridge.GetPlayer(src) ~= nil
end

function Bridge.GetJob(src)
    local p = Bridge.GetPlayer(src)
    if not p then return { name = 'none', label = 'None', grade = 0, gradeLabel = '' } end
    if Bridge.fw == 'esx' then
        return { name = p.job.name, label = p.job.label, grade = p.job.grade, gradeLabel = p.job.grade_label, onduty = p.job.onDuty }
    end
    local j = p.PlayerData.job
    return { name = j.name, label = j.label, grade = j.grade and j.grade.level or 0, gradeLabel = j.grade and j.grade.name or '', onduty = j.onduty }
end

function Bridge.GetGang(src)
    if not isQB() then return nil end
    local p = Bridge.GetPlayer(src); if not p then return nil end
    local g = p.PlayerData.gang
    return g and { name = g.name, label = g.label, grade = g.grade and g.grade.level or 0 } or nil
end

function Bridge.SetJob(src, name, grade)
    local p = Bridge.GetPlayer(src); if not p then return false end
    if Bridge.fw == 'esx' then
        if not ESX.DoesJobExist(name, grade) then return false end
        p.setJob(name, grade); return true
    end
    return p.Functions.SetJob(name, grade) ~= false
end

function Bridge.SetGang(src, name, grade)
    local p = Bridge.GetPlayer(src); if not p or not isQB() then return false end
    return p.Functions.SetGang(name, grade) ~= false
end

function Bridge.GetJobs()
    local out = {}
    if Bridge.fw == 'esx' then
        for name, j in pairs(ESX.GetJobs()) do
            local grades = {}
            for g, d in pairs(j.grades or {}) do grades[#grades + 1] = { grade = tonumber(g), label = d.label } end
            table.sort(grades, function(a, b) return a.grade < b.grade end)
            out[#out + 1] = { name = name, label = j.label, grades = grades }
        end
    elseif isQB() then
        local jobs = Bridge.fw == 'qbox' and exports.qbx_core:GetJobs() or QB.Shared.Jobs
        for name, j in pairs(jobs or {}) do
            local grades = {}
            for g, d in pairs(j.grades or {}) do grades[#grades + 1] = { grade = tonumber(g), label = d.name or d.label } end
            table.sort(grades, function(a, b) return a.grade < b.grade end)
            out[#out + 1] = { name = name, label = j.label, grades = grades }
        end
    end
    table.sort(out, function(a, b) return (a.label or a.name) < (b.label or b.name) end)
    return out
end

function Bridge.GetGangs()
    local out = {}
    if not isQB() then return out end
    local gangs = Bridge.fw == 'qbox' and exports.qbx_core:GetGangs() or (QB and QB.Shared.Gangs)
    for name, g in pairs(gangs or {}) do
        local grades = {}
        for gr, d in pairs(g.grades or {}) do grades[#grades + 1] = { grade = tonumber(gr), label = d.name or d.label } end
        table.sort(grades, function(a, b) return a.grade < b.grade end)
        out[#out + 1] = { name = name, label = g.label or name, grades = grades }
    end
    table.sort(out, function(a, b) return (a.label or a.name) < (b.label or b.name) end)
    return out
end

function Bridge.GetGroup(src)
    local p = Bridge.GetPlayer(src); if not p then return 'user' end
    if Bridge.fw == 'esx' then return p.getGroup() end
    if Bridge.fw == 'qb' and QB then
        for _, g in ipairs({ 'god', 'admin', 'mod' }) do if QB.Functions.HasPermission(src, g) then return g end end
    end
    return 'user'
end

function Bridge.SetGroup(src, group)
    local p = Bridge.GetPlayer(src); if not p then return false end
    if Bridge.fw == 'esx' then p.setGroup(group); return true end
    if Bridge.fw == 'qb' and QB then QB.Functions.AddPermission(src, group); return true end
    return false
end

-- ─── money ──────────────────────────────────────────────────────────────
function Bridge.GetAccounts(src)
    local p = Bridge.GetPlayer(src); if not p then return {} end
    local out = {}
    if Bridge.fw == 'esx' then
        for _, a in ipairs(p.getAccounts()) do out[#out + 1] = { name = a.name, label = a.label or a.name, money = a.money } end
    else
        for name, amount in pairs(p.PlayerData.money or {}) do out[#out + 1] = { name = name, label = name:gsub('^%l', string.upper), money = amount } end
        table.sort(out, function(a, b) return a.name < b.name end)
    end
    return out
end

function Bridge.SetAccount(src, account, amount)
    local p = Bridge.GetPlayer(src); if not p then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if Bridge.fw == 'esx' then
        if not p.getAccount(account) then return false end
        p.setAccountMoney(account, amount, 'admin'); return true
    end
    return p.Functions.SetMoney(account, amount, 'admin') ~= false
end

-- ─── needs / meta ───────────────────────────────────────────────────────
function Bridge.FeedPlayer(src)
    if Bridge.fw == 'esx' then
        TriggerClientEvent('esx_status:set', src, 'hunger', 1000000)
        TriggerClientEvent('esx_status:set', src, 'thirst', 1000000)
    elseif isQB() then
        local p = Bridge.GetPlayer(src)
        if p then
            p.Functions.SetMetaData('hunger', 100); p.Functions.SetMetaData('thirst', 100)
            TriggerClientEvent('hud:client:UpdateNeeds', src, 100, 100)
        end
    end
end

function Bridge.Revive(src)
    local mode = Config.Integrations.Revive
    if mode == 'auto' then
        if started('wasabi_ambulance') then mode = 'wasabi_ambulance'
        elseif started('qbx_medical') then mode = 'qbx_medical'
        elseif started('esx_ambulancejob') then mode = 'esx_ambulancejob'
        elseif started('qb-ambulancejob') then mode = 'qb-ambulancejob'
        else mode = 'native' end
    end
    if mode == 'wasabi_ambulance' then TriggerClientEvent('wasabi_ambulance:revive', src)
    elseif mode == 'qbx_medical' then TriggerClientEvent('qbx_medical:client:playerRevived', src); exports.qbx_medical:Revive(src)
    elseif mode == 'esx_ambulancejob' then TriggerClientEvent('esx_ambulancejob:revive', src)
    elseif mode == 'qb-ambulancejob' then TriggerClientEvent('hospital:client:Revive', src)
    else TriggerClientEvent('nzadmin:cl:do', src, 'nativeRevive') end
end

-- ─── inventory ──────────────────────────────────────────────────────────
function Bridge.GetItems(src)
    local out = {}
    if Bridge.inv == 'ox_inventory' then
        for _, it in pairs(exports.ox_inventory:GetInventoryItems(src) or {}) do
            out[#out + 1] = { name = it.name, label = it.label, count = it.count, slot = it.slot, metadata = it.metadata }
        end
    elseif Bridge.inv == 'qb-inventory' then
        local p = Bridge.GetPlayer(src)
        for _, it in pairs(p and p.PlayerData.items or {}) do
            out[#out + 1] = { name = it.name, label = it.label, count = it.amount, slot = it.slot, metadata = it.info }
        end
    elseif Bridge.inv == 'esx' then
        local p = Bridge.GetPlayer(src)
        for _, it in pairs(p and p.getInventory(true) or {}) do
            if type(it) == 'table' and (it.count or 0) > 0 then out[#out + 1] = { name = it.name, label = it.label, count = it.count } end
        end
        -- getInventory(true) returns name=count map on some builds
        if #out == 0 and p then
            for _, it in ipairs(p.getInventory()) do if it.count > 0 then out[#out + 1] = { name = it.name, label = it.label, count = it.count } end end
        end
    end
    table.sort(out, function(a, b) return (a.slot or 999) < (b.slot or 999) end)
    return out
end

function Bridge.AddItem(src, item, count, metadata)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if Bridge.inv == 'ox_inventory' then
        if not exports.ox_inventory:CanCarryItem(src, item, count) then return false, 'cannot_carry' end
        return exports.ox_inventory:AddItem(src, item, count, metadata) and true or false
    elseif Bridge.inv == 'qb-inventory' then
        local p = Bridge.GetPlayer(src); if not p then return false end
        local ok = p.Functions.AddItem(item, count, nil, metadata)
        if ok and QB then TriggerClientEvent('qb-inventory:client:ItemBox', src, QB.Shared.Items[item], 'add', count) end
        return ok
    elseif Bridge.inv == 'esx' then
        local p = Bridge.GetPlayer(src); if not p then return false end
        if not p.canCarryItem(item, count) then return false, 'cannot_carry' end
        p.addInventoryItem(item, count); return true
    end
    return false
end

function Bridge.RemoveItem(src, item, count, slot)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if Bridge.inv == 'ox_inventory' then return exports.ox_inventory:RemoveItem(src, item, count, nil, slot) and true or false
    elseif Bridge.inv == 'qb-inventory' then
        local p = Bridge.GetPlayer(src); return p and p.Functions.RemoveItem(item, count, slot) or false
    elseif Bridge.inv == 'esx' then
        local p = Bridge.GetPlayer(src); if not p then return false end
        p.removeInventoryItem(item, count); return true
    end
    return false
end

function Bridge.CountItem(src, item)
    if Bridge.inv == 'ox_inventory' then return exports.ox_inventory:Search(src, 'count', item) or 0 end
    local n = 0
    for _, it in ipairs(Bridge.GetItems(src)) do if it.name == item then n = n + (it.count or 0) end end
    return n
end

local itemCache
function Bridge.GetItemList()
    if itemCache then return itemCache end
    local out = {}
    if Bridge.inv == 'ox_inventory' then
        for name, it in pairs(exports.ox_inventory:Items() or {}) do out[#out + 1] = { name = name, label = it.label or name, weight = it.weight } end
    elseif isQB() then
        local items = QB and QB.Shared.Items or (Bridge.fw == 'qbox' and exports.ox_inventory:Items()) or {}
        for name, it in pairs(items) do out[#out + 1] = { name = name, label = it.label or name, weight = it.weight } end
    elseif Bridge.fw == 'esx' then
        for _, row in ipairs(MySQL.query.await('SELECT name, label, weight FROM items') or {}) do out[#out + 1] = row end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    itemCache = out
    return out
end

function Bridge.OpenInventory(staffSrc, targetSrc)
    if Bridge.inv == 'ox_inventory' then
        exports.ox_inventory:forceOpenInventory(staffSrc, 'player', targetSrc)
        return true
    elseif Bridge.inv == 'qb-inventory' and GetResourceState('qb-inventory') == 'started' then
        return pcall(function() exports['qb-inventory']:OpenInventoryById(staffSrc, targetSrc) end)
    end
    return false
end

-- ─── offline characters ─────────────────────────────────────────────────
function Bridge.SearchCharacters(q, limit)
    q = '%' .. q:gsub('[%%_]', '\\%0') .. '%'
    limit = limit or 40
    if Bridge.fw == 'esx' then
        local rows = MySQL.query.await(([[SELECT identifier, firstname, lastname, job, job_grade, accounts, `group`, dateofbirth
            FROM users WHERE identifier LIKE ? OR CONCAT(firstname, ' ', lastname) LIKE ? LIMIT %d]]):format(limit), { q, q }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            local acc = json.decode(r.accounts or '{}') or {}
            -- ESX stores the license hash without the "license:" prefix (char1:hash with multichar)
            out[#out + 1] = { charId = r.identifier, license = 'license:' .. (r.identifier:match(':(.+)$') or r.identifier),
                name = ('%s %s'):format(r.firstname or '', r.lastname or ''), job = r.job, grade = r.job_grade, group = r.group, dob = r.dateofbirth,
                money = { cash = acc.money or 0, bank = acc.bank or 0, black_money = acc.black_money or 0 } }
        end
        return out
    elseif isQB() then
        local rows = MySQL.query.await(([[SELECT citizenid, license, name, charinfo, money, job, gang FROM players
            WHERE citizenid LIKE ? OR license LIKE ? OR name LIKE ? OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) LIKE ?
            OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) LIKE ? LIMIT %d]]):format(limit), { q, q, q, q, q }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            local c = json.decode(r.charinfo or '{}') or {}
            local j = json.decode(r.job or '{}') or {}
            local g = json.decode(r.gang or '{}') or {}
            out[#out + 1] = { charId = r.citizenid, license = r.license, name = ('%s %s'):format(c.firstname or '', c.lastname or ''),
                job = j.name, grade = j.grade and j.grade.level or 0, gang = g.name, dob = c.birthdate, money = json.decode(r.money or '{}') or {} }
        end
        return out
    end
    return {}
end

function Bridge.UpdateOffline(charId, field, value)
    if Bridge.fw == 'esx' then
        if field == 'name' then
            return MySQL.update.await('UPDATE users SET firstname = ?, lastname = ? WHERE identifier = ?', { value.first, value.last, charId }) > 0
        elseif field == 'job' then
            return MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { value.name, value.grade, charId }) > 0
        elseif field == 'money' then
            local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ?', { charId }); if not row then return false end
            local acc = json.decode(row.accounts or '{}') or {}
            acc[value.account == 'cash' and 'money' or value.account] = math.max(0, math.floor(value.amount))
            return MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(acc), charId }) > 0
        elseif field == 'delete' then
            MySQL.update.await('DELETE FROM owned_vehicles WHERE owner = ?', { charId })
            return MySQL.update.await('DELETE FROM users WHERE identifier = ?', { charId }) > 0
        end
    elseif isQB() then
        if field == 'name' then
            local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { charId }); if not row then return false end
            local c = json.decode(row.charinfo) or {}; c.firstname, c.lastname = value.first, value.last
            return MySQL.update.await('UPDATE players SET charinfo = ? WHERE citizenid = ?', { json.encode(c), charId }) > 0
        elseif field == 'job' or field == 'gang' then
            local row = MySQL.single.await(('SELECT %s FROM players WHERE citizenid = ?'):format(field), { charId }); if not row then return false end
            local j = json.decode(row[field]) or {}
            j.name = value.name; j.grade = j.grade or {}; j.grade.level = value.grade
            return MySQL.update.await(('UPDATE players SET %s = ? WHERE citizenid = ?'):format(field), { json.encode(j), charId }) > 0
        elseif field == 'money' then
            local row = MySQL.single.await('SELECT money FROM players WHERE citizenid = ?', { charId }); if not row then return false end
            local m = json.decode(row.money) or {}; m[value.account] = math.max(0, math.floor(value.amount))
            return MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(m), charId }) > 0
        elseif field == 'delete' then
            MySQL.update.await('DELETE FROM player_vehicles WHERE citizenid = ?', { charId })
            return MySQL.update.await('DELETE FROM players WHERE citizenid = ?', { charId }) > 0
        end
    end
    return false
end

--- Delete an online character: kick first so the framework doesn't save it back.
function Bridge.DeleteCharacter(src)
    local charId = Bridge.CharId(src)
    DropPlayer(src, 'Your character was deleted by staff.')
    SetTimeout(3000, function() Bridge.UpdateOffline(charId, 'delete') end)
    return true
end

-- ─── rich list / stats ──────────────────────────────────────────────────
function Bridge.RichList(limit)
    limit = limit or 10
    if Bridge.fw == 'esx' then
        return MySQL.query.await(([[SELECT CONCAT(firstname, ' ', lastname) AS name,
            CAST(JSON_EXTRACT(accounts, '$.bank') AS UNSIGNED) + CAST(JSON_EXTRACT(accounts, '$.money') AS UNSIGNED) AS total
            FROM users ORDER BY total DESC LIMIT %d]]):format(limit)) or {}
    elseif isQB() then
        return MySQL.query.await(([[SELECT CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) AS name,
            CAST(JSON_EXTRACT(money, '$.bank') AS UNSIGNED) + CAST(JSON_EXTRACT(money, '$.cash') AS UNSIGNED) AS total
            FROM players ORDER BY total DESC LIMIT %d]]):format(limit)) or {}
    end
    return {}
end

function Bridge.CharacterCount()
    if Bridge.fw == 'esx' then return MySQL.scalar.await('SELECT COUNT(*) FROM users') or 0 end
    if isQB() then return MySQL.scalar.await('SELECT COUNT(*) FROM players') or 0 end
    return 0
end

-- ─── owned vehicles ─────────────────────────────────────────────────────
function Bridge.VT() return Config.VehicleTable[isQB() and 'qb' or 'esx'] end

function Bridge.GiveOwnedVehicle(src, model, plate, props)
    local vt = Bridge.VT()
    local charId = Bridge.CharId(src)
    if Bridge.fw == 'esx' then
        props = props or {}; props.model = props.model or joaat(model); props.plate = plate
        MySQL.insert.await(('INSERT INTO `%s` (`%s`, `%s`, `%s`, `%s`) VALUES (?, ?, ?, ?)'):format(vt.table, vt.owner, vt.plate, vt.props, vt.stored),
            { charId, plate, json.encode(props), vt.storedValue })
        return true
    elseif isQB() then
        props = props or {}; props.plate = plate
        MySQL.insert.await(('INSERT INTO `%s` (`%s`, `%s`, `%s`, `%s`, `%s`, `%s`, `%s`, `%s`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(
            vt.table, vt.license, vt.owner, vt.model, vt.hash, vt.props, vt.plate, vt.garage, vt.stored),
            { GetPlayerIdentifierByType(src, 'license'), charId, model, tostring(joaat(model)), json.encode(props), plate, vt.defaultGarage, vt.storedValue })
        return true
    end
    return false
end

function Bridge.PlateTaken(plate)
    if Bridge.fw == 'standalone' then return false end
    local vt = Bridge.VT()
    return (MySQL.scalar.await(('SELECT 1 FROM `%s` WHERE `%s` = ?'):format(vt.table, vt.plate), { plate }) or 0) == 1
end
