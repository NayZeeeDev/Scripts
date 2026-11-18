if not NAYZEEE_LOCK_OK then return end
if NZ.Framework ~= 'esx' then return end

--[[
    ESX Legacy bridge.
    es_extended must run in multicharacter mode. In es_extended/config.lua (or shared config) set:
        Config.Multichar = true
    Characters are stored as users.identifier = "char<slot>:<license>".
]]

local ESX
local PREFIX = 'char'          -- must match es_extended's multichar prefix
local jobsCache

CreateThread(function()
    while GetResourceState('es_extended') ~= 'started' do Wait(100) end
    ESX = exports.es_extended:getSharedObject()
end)

function Bridge.Ready() return ESX ~= nil end

local function jobs()
    if not jobsCache or not next(jobsCache) then
        jobsCache = (ESX.GetJobs and ESX.GetJobs()) or ESX.Jobs or {}
    end
    return jobsCache
end

-- Refresh job labels if jobs are edited at runtime
AddEventHandler('esx:jobsRefreshed', function() jobsCache = nil end)

function Bridge.Owner(src)
    if ESX and ESX.GetIdentifier then
        local id = ESX.GetIdentifier(src)
        if id then return id end
    end
    local lic = GetPlayerIdentifierByType(src, 'license')
    return lic and lic:gsub('^license:', '') or nil
end

local function slotOf(identifier)
    return tonumber(identifier:match('^' .. PREFIX .. '(%d+):'))
end

local function normalise(row)
    local accounts = NZ.Decode(row.accounts) or {}
    local jobName = row.job or 'unemployed'
    local grade = tonumber(row.job_grade) or 0
    local j = ESX and jobs()[jobName]
    local jobLabel, gradeLabel = jobName, tostring(grade)
    if j then
        jobLabel = j.label or jobName
        local g = j.grades and (j.grades[tostring(grade)] or j.grades[grade])
        gradeLabel = g and g.label or gradeLabel
    end
    local skin = NZ.Decode(row.skin)
    local gender = (row.sex == 'f' or row.sex == 'F' or row.sex == 1 or row.sex == '1') and 'f' or 'm'
    return {
        id          = row.identifier,
        slot        = slotOf(row.identifier),
        owner       = row.identifier:match('^' .. PREFIX .. '%d+:(.+)$'),
        firstname   = row.firstname or '',
        lastname    = row.lastname or '',
        dob         = Bridge.ISO(row.dateofbirth, Config.Registration.dob.storage),
        gender      = gender,
        height      = tonumber(row.height),
        nationality = row.nationality,
        job         = { name = jobName, label = jobLabel, grade = grade, gradeLabel = gradeLabel },
        cash        = tonumber(accounts.money) or 0,
        bank        = tonumber(accounts.bank) or 0,
        phone       = row.phone_number or row.phone,
        position    = NZ.Vec(NZ.Decode(row.position)),
        skin        = skin,
        model       = Bridge.SkinModel(skin, gender),
        raw         = row,
    }
end

function Bridge.Fetch(_, owner)
    local rows = MySQL.query.await('SELECT * FROM `users` WHERE `identifier` LIKE ?', { PREFIX .. '%:' .. Bridge.LikeEscape(owner) }) or {}
    local list = {}
    for i = 1, #rows do
        local c = normalise(rows[i])
        if c.slot then list[#list + 1] = c end
    end
    return list
end

function Bridge.FetchByIds(ids)
    if #ids == 0 then return {} end
    local rows = MySQL.query.await(('SELECT * FROM `users` WHERE `identifier` IN (%s)'):format(Bridge.Marks(#ids)), ids) or {}
    local list = {}
    for i = 1, #rows do list[#list + 1] = normalise(rows[i]) end
    return list
end

-- Squad search. exact = identifier / stateid match, otherwise full-name LIKE
function Bridge.Search(query, exact)
    local rows
    if exact then
        rows = {}
        if Config.Squad.searchBy.citizenid then
            rows = MySQL.query.await('SELECT identifier, firstname, lastname FROM `users` WHERE `identifier` = ? LIMIT 1', { query }) or {}
        end
        if #rows == 0 and Config.Squad.searchBy.stateid and Bridge.TableExists('users', 'stateid') then
            rows = MySQL.query.await('SELECT identifier, firstname, lastname FROM `users` WHERE `stateid` = ? LIMIT 1', { query }) or {}
        end
    else
        rows = MySQL.query.await([[SELECT identifier, firstname, lastname FROM `users`
            WHERE `identifier` LIKE ? AND CONCAT(firstname, ' ', lastname) LIKE ? LIMIT 25]],
            { PREFIX .. '%:%', '%' .. Bridge.LikeEscape(query) .. '%' }) or {}
    end
    local out = {}
    for i = 1, #rows do
        if slotOf(rows[i].identifier) then
            out[#out + 1] = { id = rows[i].identifier, firstname = rows[i].firstname or '', lastname = rows[i].lastname or '' }
        end
    end
    return out
end

local function waitPlayer(src, ms)
    local deadline = GetGameTimer() + (ms or 8000)
    while not ESX.GetPlayerFromId(src) and GetGameTimer() < deadline do Wait(50) end
    return ESX.GetPlayerFromId(src) ~= nil
end

function Bridge.Load(src, char)
    if ESX.GetPlayerFromId(src) then return true end
    TriggerEvent('esx:onPlayerJoined', src, PREFIX .. char.slot)
    return waitPlayer(src)
end

function Bridge.Create(src, slot, data)
    local owner = Bridge.Owner(src)
    TriggerEvent('esx:onPlayerJoined', src, PREFIX .. slot, {
        firstname   = data.firstname,
        lastname    = data.lastname,
        dateofbirth = Bridge.FormatDate(data.dobY, data.dobM, data.dobD, Config.Registration.dob.storage),
        sex         = data.gender,
        height      = data.height or Config.Registration.height.default,
    })
    if not waitPlayer(src) then return false end
    return true, PREFIX .. slot .. ':' .. owner
end

function Bridge.Delete(_, charId)
    local queries = {}
    for _, t in ipairs(ServerConfig.DeleteTables.esx or {}) do
        if Bridge.TableExists(t.table, t.column) then
            queries[#queries + 1] = { query = ('DELETE FROM `%s` WHERE `%s` = ?'):format(t.table, t.column), values = { charId } }
        end
    end
    return MySQL.transaction.await(queries) == true
end

function Bridge.Logout(src)
    local p = promise.new()
    TriggerEvent('esx:playerLogout', src, function() p:resolve(true) end)
    SetTimeout(4000, function() if p.state == 0 then p:resolve(true) end end)
    return Citizen.Await(p)
end

function Bridge.IsLoaded(src)
    return ESX ~= nil and ESX.GetPlayerFromId(src) ~= nil
end

function Bridge.ActiveId(src)
    local x = ESX.GetPlayerFromId(src)
    return x and x.identifier
end

function Bridge.ActiveJob(src)
    local x = ESX.GetPlayerFromId(src)
    if not x then return nil, 0 end
    return x.job.name, tonumber(x.job.grade) or 0
end

function Bridge.NameTaken(first, last)
    return MySQL.scalar.await('SELECT 1 FROM `users` WHERE LOWER(firstname) = LOWER(?) AND LOWER(lastname) = LOWER(?) LIMIT 1', { first, last }) ~= nil
end

function Bridge.AddMoney(src, account, amount)
    local x = ESX.GetPlayerFromId(src)
    if not x or amount <= 0 then return end
    x.addAccountMoney(account == 'cash' and 'money' or account, amount, 'starter')
end

function Bridge.FrameworkAddItem(src, name, count)
    local x = ESX.GetPlayerFromId(src)
    if not x then return false end
    x.addInventoryItem(name, count)
    return true
end

function Bridge.FrameworkStarter() end

function Bridge.Position(charId)
    local pos = MySQL.scalar.await('SELECT `position` FROM `users` WHERE `identifier` = ?', { charId })
    return NZ.Vec(NZ.Decode(pos))
end

-- ── Weapons (ESX default loadout) ─────────────────────────────────────────
function Bridge.FrameworkWeaponLabel(name)
    if not ESX or not ESX.GetWeaponLabel then return nil end
    local ok, label = pcall(ESX.GetWeaponLabel, name)
    return ok and label or nil
end

-- 'flashlight' on WEAPON_PISTOL -> component hash
function Bridge.ESXComponentHash(weapon, component)
    if not ESX or not ESX.GetWeaponComponent then return nil end
    local ok, c = pcall(ESX.GetWeaponComponent, weapon, component)
    return ok and type(c) == 'table' and c.hash or nil
end

-- ESX multichar flag, read by the install doctor
function Bridge.MulticharEnabled()
    if not ESX then return nil end
    local cfg = ESX.GetConfig and ESX.GetConfig()
    if type(cfg) ~= 'table' then return nil end
    return cfg.Multichar == true
end
