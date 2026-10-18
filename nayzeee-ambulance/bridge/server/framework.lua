--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: framework (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). One adapter per framework: es_extended (ESX
    Legacy), qb-core, qbx_core (Qbox) and standalone (license identifier, ace
    based medic job). Fix or extend an adapter here if your framework fork
    differs - nothing else in the resource talks to the framework directly.

    API
      Bridge.Framework                          'esx' | 'qbcore' | 'qbox' | 'standalone'
      Bridge.OnPlayerLoaded(fn(src), replay?)   replay = also call fn for players already loaded
      Bridge.OnPlayerUnloaded(fn(src))          Bridge.OnJobChanged(fn(src, job))
      Bridge.IsLoaded(src)                      Bridge.GetPlayer(src) → raw framework player
      Bridge.GetIdentifier(src)                 Bridge.GetSourceFromIdentifier(id)
      Bridge.GetName(src)                       Bridge.GetCharInfo(src) → { firstname, lastname, dob, sex, phone }
      Bridge.GetJob(src) → { name, label, grade, gradeLabel, onDuty, isBoss }
      Bridge.IsMedic(src) Bridge.IsPolice(src) Bridge.IsOnDuty(src) Bridge.SetDuty(src, bool)
      Bridge.SetJob(src, job, grade) → bool     Bridge.HasLicense(src, name) → bool
      Bridge.IsAdmin(src)                       Bridge.GetPlayers() Bridge.GetMedics(onDutyOnly)
      Bridge.GetMoney(src, account)             account: 'cash' | 'bank' (ESX 'money' works too)
      Bridge.RemoveMoney(src, account, amount, reason) → bool
      Bridge.AddMoney(src, account, amount, reason)    → bool

    STATE BAG
      Player(src).state.nzaJob = { name, label, grade, gradeLabel, onDuty, isBoss, medic, police }
      (replicated, refreshed on load / job change / duty change)

    BUS EVENTS (NZA.Bus)
      'bridge:playerLoaded' (src)  'bridge:playerUnloaded' (src)  'bridge:jobChanged' (src, job)
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

local FW = {}
Bridge.FrameworkAdapters = FW

local function core() return Bridge.Core() end

local function toSource(value)
    local src = tonumber(value)
    if not src or src <= 0 then return nil end
    return math.floor(src)
end

local function normalizeSex(value)
    if value == 1 or value == '1' or value == 'f' or value == 'F' or value == 'female' or value == 'Female' then
        return 'f'
    end
    return 'm'
end

local function splitName(full)
    full = tostring(full or '')
    local first, last = full:match('^(%S+)%s+(.+)$')
    return first or full, last or ''
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ESX (es_extended / ESX Legacy)
-- ═══════════════════════════════════════════════════════════════════════════

local ESX_ACCOUNTS = { cash = 'money', money = 'money', bank = 'bank', black_money = 'black_money', dirty = 'black_money' }

FW.esx = {}

function FW.esx.player(src)
    local ESX = core()
    return ESX and ESX.GetPlayerFromId(src) or nil
end

function FW.esx.identifier(src)
    local x = FW.esx.player(src)
    if not x then return nil end
    return x.identifier or (x.getIdentifier and x.getIdentifier())
end

function FW.esx.sourceFromIdentifier(identifier)
    local ESX = core()
    local x = ESX and ESX.GetPlayerFromIdentifier(identifier)
    return x and toSource(x.source or (x.getSource and x.getSource())) or nil
end

function FW.esx.charInfo(src)
    local x = FW.esx.player(src)
    if not x then return nil end
    local get = x.get
    local first = get and get('firstName') or nil
    local last = get and get('lastName') or nil
    if not first or first == '' then
        first, last = splitName(x.getName and x.getName() or GetPlayerName(src))
    end
    return {
        firstname = first,
        lastname = last or '',
        dob = get and (get('dateofbirth') or get('dateOfBirth')) or nil,
        sex = normalizeSex(get and get('sex') or nil),
        phone = get and (get('phone_number') or get('phoneNumber')) or nil,
    }
end

function FW.esx.job(src)
    local x = FW.esx.player(src)
    if not x then return nil end
    local j = (x.getJob and x.getJob()) or x.job
    if not j then return nil end
    local name, offPrefix = Bridge.SplitDutyJob(j.name)
    local onDuty
    if offPrefix == false then
        onDuty = false
    elseif j.onDuty ~= nil then
        onDuty = j.onDuty == true
    else
        onDuty = true
    end
    return {
        name = name,
        rawName = j.name,
        label = j.label or name,
        grade = tonumber(j.grade) or 0,
        gradeLabel = j.grade_label or j.grade_name or tostring(j.grade or 0),
        onDuty = onDuty,
        isBoss = j.grade_name == 'boss',
    }
end

function FW.esx.setDuty(src, onDuty)
    local ESX = core()
    local x = FW.esx.player(src)
    if not (ESX and x) then return false end
    local j = (x.getJob and x.getJob()) or x.job
    local base, offPrefix = Bridge.SplitDutyJob(j.name)

    -- ESX Legacy with a real duty flag
    if j.onDuty ~= nil and offPrefix == nil then
        x.setJob(j.name, j.grade, onDuty == true)
        return true
    end

    -- 'off<job>' convention
    local prefix = Bridge.Cfg('offDutyPrefix', 'off')
    local target = onDuty and base or (prefix .. base)
    if target == j.name then return true end
    if ESX.DoesJobExist and not ESX.DoesJobExist(target, j.grade) then
        if j.onDuty ~= nil then
            x.setJob(base, j.grade, onDuty == true)
            return true
        end
        Bridge.Warn(('ESX job "%s" grade %s does not exist - cannot toggle duty for %s'):format(target, tostring(j.grade), base))
        return false
    end
    x.setJob(target, j.grade, onDuty == true)
    return true
end

-- Same job with a new grade keeps the duty state the player has now.
function FW.esx.setJob(src, job, grade)
    local ESX = core()
    local x = FW.esx.player(src)
    if not (ESX and x and x.setJob) then return false end
    local cur = (x.getJob and x.getJob()) or x.job or {}
    local base, offPrefix = Bridge.SplitDutyJob(cur.name)
    local target, onDuty = job, nil
    if base == job then
        if offPrefix == false then
            local off = Bridge.Cfg('offDutyPrefix', 'off') .. job
            if not ESX.DoesJobExist or ESX.DoesJobExist(off, grade) then target = off end
        elseif cur.onDuty ~= nil then
            onDuty = cur.onDuty == true
        end
    end
    if ESX.DoesJobExist and not ESX.DoesJobExist(target, grade) then
        Bridge.Warn(('ESX job "%s" grade %d does not exist - cannot give it to player %d'):format(target, grade, src))
        return false
    end
    x.setJob(target, grade, onDuty)
    -- old ESX setJob returns nothing, so read the job back
    local now = (x.getJob and x.getJob()) or x.job
    return type(now) == 'table' and now.name == target and tonumber(now.grade) == grade
end

-- esx_license answers through a callback; without it the ace fallback decides
function FW.esx.hasLicense(src, name)
    if not Bridge.Started('esx_license') then return nil end
    local p, settled = promise.new(), false
    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value == true)
    end
    TriggerEvent('esx_license:checkLicense', src, name, settle)
    if not settled then SetTimeout(2000, function() settle(false) end) end
    return Citizen.Await(p) == true
end

function FW.esx.getMoney(src, account)
    local x = FW.esx.player(src)
    if not x then return 0 end
    local acc = x.getAccount(ESX_ACCOUNTS[account] or account)
    return acc and tonumber(acc.money) or 0
end

function FW.esx.removeMoney(src, account, amount, reason)
    local x = FW.esx.player(src)
    if not x then return false end
    local name = ESX_ACCOUNTS[account] or account
    if FW.esx.getMoney(src, name) < amount then return false end
    x.removeAccountMoney(name, amount, reason)
    return true
end

function FW.esx.addMoney(src, account, amount, reason)
    local x = FW.esx.player(src)
    if not x then return false end
    x.addAccountMoney(ESX_ACCOUNTS[account] or account, amount, reason)
    return true
end

function FW.esx.isAdmin(src)
    local x = FW.esx.player(src)
    if not x then return false end
    local group = x.getGroup and x.getGroup() or x.group
    return Bridge.InList((Config.Admin and Config.Admin.groups) or {}, group)
end

function FW.esx.players()
    local ESX = core()
    local out = {}
    if not ESX then return out end
    if ESX.GetExtendedPlayers then
        for _, x in pairs(ESX.GetExtendedPlayers()) do
            local src = toSource(x.source)
            if src then out[#out + 1] = src end
        end
    else
        for _, src in pairs(ESX.GetPlayers()) do
            src = toSource(src)
            if src then out[#out + 1] = src end
        end
    end
    return out
end

function FW.esx.hooks(emit)
    AddEventHandler('esx:playerLoaded', function(playerId) emit.loaded(toSource(playerId)) end)
    AddEventHandler('esx:playerLogout', function(playerId) emit.unloaded(toSource(playerId)) end)
    AddEventHandler('esx:playerDropped', function(playerId) emit.unloaded(toSource(playerId)) end)
    AddEventHandler('esx:setJob', function(playerId) emit.job(toSource(playerId)) end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- QBCORE (qb-core)
-- ═══════════════════════════════════════════════════════════════════════════

FW.qbcore = {}

function FW.qbcore.player(src)
    local QBCore = core()
    return QBCore and QBCore.Functions.GetPlayer(src) or nil
end

local function qbIdentifier(p)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

function FW.qbcore.identifier(src)
    return qbIdentifier(FW.qbcore.player(src))
end

function FW.qbcore.sourceFromIdentifier(identifier)
    local QBCore = core()
    local p = QBCore and QBCore.Functions.GetPlayerByCitizenId(identifier)
    return p and p.PlayerData and toSource(p.PlayerData.source) or nil
end

local function qbCharInfo(p, src)
    if not p then return nil end
    local c = p.PlayerData.charinfo or {}
    local first, last = c.firstname, c.lastname
    if not first or first == '' then first, last = splitName(GetPlayerName(src)) end
    return {
        firstname = first,
        lastname = last or '',
        dob = c.birthdate,
        sex = normalizeSex(c.gender),
        phone = c.phone,
    }
end

function FW.qbcore.charInfo(src)
    return qbCharInfo(FW.qbcore.player(src), src)
end

local function qbJob(p)
    local j = p and p.PlayerData and p.PlayerData.job
    if not j then return nil end
    local grade = j.grade or {}
    return {
        name = j.name,
        label = j.label or j.name,
        grade = tonumber(type(grade) == 'table' and grade.level or grade) or 0,
        gradeLabel = type(grade) == 'table' and (grade.name or grade.label) or tostring(grade),
        onDuty = j.onduty == true,
        isBoss = (j.isboss == true) or (type(grade) == 'table' and grade.isboss == true) or false,
        type = j.type,
    }
end

function FW.qbcore.job(src)
    return qbJob(FW.qbcore.player(src))
end

function FW.qbcore.setDuty(src, onDuty)
    local p = FW.qbcore.player(src)
    if not p then return false end
    onDuty = onDuty == true
    p.Functions.SetJobDuty(onDuty)
    TriggerEvent('QBCore:Server:SetDuty', src, onDuty)
    TriggerClientEvent('QBCore:Client:SetDuty', src, onDuty)
    return true
end

-- QBCore and Qbox reset duty to the job's defaultDuty on SetJob: a grade change on the
-- same job puts the old duty state back.
local function qbDutyToKeep(p, job)
    local j = p and p.PlayerData and p.PlayerData.job
    if j and j.name == job then return j.onduty == true end
    return nil
end

local function qbHasGrade(def, grade)
    local grades = type(def) == 'table' and def.grades
    if type(grades) ~= 'table' then return false end
    return grades[tostring(grade)] ~= nil or grades[grade] ~= nil
end

function FW.qbcore.setJob(src, job, grade)
    local QBCore = core()
    local p = FW.qbcore.player(src)
    if not (QBCore and p and p.Functions and p.Functions.SetJob) then return false end
    job = job:lower()
    local jobs = QBCore.Shared and QBCore.Shared.Jobs
    -- qb-core accepts a missing grade and makes it 'No Grades' level 0: refuse instead
    if type(jobs) == 'table' and not qbHasGrade(jobs[job], grade) then
        Bridge.Warn(('QBCore job "%s" grade %d does not exist - cannot give it to player %d'):format(job, grade, src))
        return false
    end
    local keepDuty = qbDutyToKeep(p, job)
    if p.Functions.SetJob(job, grade) == false then return false end
    local now = FW.qbcore.player(src)
    local j = now and now.PlayerData and now.PlayerData.job
    if keepDuty ~= nil and j and j.onduty ~= keepDuty and now.Functions.SetJobDuty then
        now.Functions.SetJobDuty(keepDuty)
    end
    return true
end

-- QBCore and Qbox keep licences in the player's metadata (licences = { weapon = true, ... })
local function qbHasLicense(p, name)
    local md = p and p.PlayerData and p.PlayerData.metadata
    local list = type(md) == 'table' and (md.licences or md.licenses) or nil
    return type(list) == 'table' and list[name] == true
end

function FW.qbcore.hasLicense(src, name)
    return qbHasLicense(FW.qbcore.player(src), name)
end

local function qbGetMoney(p, account)
    if not p then return 0 end
    account = (account == 'money') and 'cash' or account
    local money = p.PlayerData.money or {}
    return tonumber(money[account]) or 0
end

function FW.qbcore.getMoney(src, account)
    return qbGetMoney(FW.qbcore.player(src), account)
end

function FW.qbcore.removeMoney(src, account, amount, reason)
    local p = FW.qbcore.player(src)
    if not p then return false end
    account = (account == 'money') and 'cash' or account
    return p.Functions.RemoveMoney(account, amount, reason) == true
end

function FW.qbcore.addMoney(src, account, amount, reason)
    local p = FW.qbcore.player(src)
    if not p then return false end
    account = (account == 'money') and 'cash' or account
    return p.Functions.AddMoney(account, amount, reason) ~= false
end

function FW.qbcore.isAdmin(src)
    local QBCore = core()
    if not QBCore then return false end
    for _, group in ipairs((Config.Admin and Config.Admin.groups) or {}) do
        if QBCore.Functions.HasPermission(src, group) then return true end
    end
    return false
end

function FW.qbcore.players()
    local QBCore = core()
    local out = {}
    if not QBCore then return out end
    for _, src in pairs(QBCore.Functions.GetPlayers()) do
        src = toSource(src)
        if src then out[#out + 1] = src end
    end
    return out
end

local function qbHooks(emit)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = player and player.PlayerData and player.PlayerData.source
        emit.loaded(toSource(src))
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) emit.unloaded(toSource(src)) end)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src) emit.job(toSource(src)) end)
    AddEventHandler('QBCore:Server:SetDuty', function(src) emit.job(toSource(src)) end)
end

FW.qbcore.hooks = qbHooks

-- ═══════════════════════════════════════════════════════════════════════════
-- QBOX (qbx_core)
-- ═══════════════════════════════════════════════════════════════════════════

FW.qbox = {}

function FW.qbox.player(src)
    return exports.qbx_core:GetPlayer(src)
end

function FW.qbox.identifier(src)
    return qbIdentifier(FW.qbox.player(src))
end

function FW.qbox.sourceFromIdentifier(identifier)
    local p = exports.qbx_core:GetPlayerByCitizenId(identifier)
    return p and p.PlayerData and toSource(p.PlayerData.source) or nil
end

function FW.qbox.charInfo(src)
    return qbCharInfo(FW.qbox.player(src), src)
end

function FW.qbox.job(src)
    return qbJob(FW.qbox.player(src))
end

function FW.qbox.setDuty(src, onDuty)
    if not FW.qbox.player(src) then return false end
    exports.qbx_core:SetJobDuty(src, onDuty == true)
    return true
end

-- qbx_core SetJob checks the job and grade itself and returns true / false, err.
-- Whether the old job stays in the player's job list is qbx's 'qbx:setjob_replaces' convar.
function FW.qbox.setJob(src, job, grade)
    local p = FW.qbox.player(src)
    if not p then return false end
    job = job:lower()
    local keepDuty = qbDutyToKeep(p, job)
    if exports.qbx_core:SetJob(src, job, grade) ~= true then return false end
    if keepDuty ~= nil then
        local now = FW.qbox.player(src)
        local j = now and now.PlayerData and now.PlayerData.job
        if j and j.onduty ~= keepDuty then exports.qbx_core:SetJobDuty(src, keepDuty) end
    end
    return true
end

function FW.qbox.hasLicense(src, name)
    return qbHasLicense(FW.qbox.player(src), name)
end

function FW.qbox.getMoney(src, account)
    account = (account == 'money') and 'cash' or account
    return tonumber(exports.qbx_core:GetMoney(src, account)) or 0
end

function FW.qbox.removeMoney(src, account, amount, reason)
    account = (account == 'money') and 'cash' or account
    return exports.qbx_core:RemoveMoney(src, account, amount, reason) == true
end

function FW.qbox.addMoney(src, account, amount, reason)
    account = (account == 'money') and 'cash' or account
    return exports.qbx_core:AddMoney(src, account, amount, reason) ~= false
end

function FW.qbox.isAdmin(src)
    for _, group in ipairs((Config.Admin and Config.Admin.groups) or {}) do
        if exports.qbx_core:HasPermission(src, group) then return true end
    end
    return false
end

function FW.qbox.players()
    local out = {}
    for src in pairs(exports.qbx_core:GetQBPlayers() or {}) do
        src = toSource(src)
        if src then out[#out + 1] = src end
    end
    return out
end

function FW.qbox.hooks(emit)
    qbHooks(emit)
    AddEventHandler('qbx_core:server:playerLoggedOut', function(src) emit.unloaded(toSource(src)) end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STANDALONE (license identifier, ace based medic job)
-- ═══════════════════════════════════════════════════════════════════════════

FW.standalone = {}

local saDuty = {}   -- [src] = bool

local function licenseOf(src)
    local id = GetPlayerIdentifierByType and GetPlayerIdentifierByType(tostring(src), 'license')
    if id and id ~= '' then return id end
    for _, ident in ipairs(GetPlayerIdentifiers(tostring(src)) or {}) do
        if ident:sub(1, 8) == 'license:' then return ident end
    end
    local fallback = GetPlayerIdentifiers(tostring(src))
    return fallback and fallback[1] or nil
end

function FW.standalone.player(src)
    if not GetPlayerName(tostring(src)) then return nil end
    return { source = src, identifier = licenseOf(src), name = GetPlayerName(tostring(src)) }
end

function FW.standalone.identifier(src)
    return licenseOf(src)
end

function FW.standalone.sourceFromIdentifier(identifier)
    for _, s in ipairs(GetPlayers()) do
        local src = toSource(s)
        if src then
            for _, ident in ipairs(GetPlayerIdentifiers(s) or {}) do
                if ident == identifier then return src end
            end
        end
    end
    return nil
end

function FW.standalone.charInfo(src)
    local first, last = splitName(GetPlayerName(tostring(src)))
    return { firstname = first, lastname = last, dob = nil, sex = 'm', phone = nil }
end

local function aceGrade(src, ace)
    for grade = Bridge.Cfg('standaloneMaxGrade', 10), 0, -1 do
        if IsPlayerAceAllowed(tostring(src), ('%s.%d'):format(ace, grade)) then return grade end
    end
    return nil
end

function FW.standalone.job(src)
    local s = tostring(src)
    local medicAce = Bridge.Cfg('standaloneMedicAce', 'nza.medic')
    local policeAce = Bridge.Cfg('standalonePoliceAce', 'nza.police')
    local onDuty = saDuty[src]
    if onDuty == nil then onDuty = Bridge.Cfg('standaloneOnDuty', true) == true end

    if medicAce and IsPlayerAceAllowed(s, medicAce) then
        local name = Bridge.MedicJobs()[1] or 'ambulance'
        local grade = aceGrade(src, medicAce) or Bridge.Cfg('standaloneGrade', 1)
        return {
            name = name, label = 'EMS', grade = grade, gradeLabel = tostring(grade),
            onDuty = onDuty, isBoss = IsPlayerAceAllowed(s, medicAce .. '.boss') == true,
        }
    end
    if policeAce and IsPlayerAceAllowed(s, policeAce) then
        local name = Bridge.PoliceJobs()[1] or 'police'
        local grade = aceGrade(src, policeAce) or 0
        return {
            name = name, label = 'Police', grade = grade, gradeLabel = tostring(grade),
            onDuty = onDuty, isBoss = IsPlayerAceAllowed(s, policeAce .. '.boss') == true,
        }
    end
    return { name = 'unemployed', label = 'Civilian', grade = 0, gradeLabel = '0', onDuty = true, isBoss = false }
end

function FW.standalone.setDuty(src, onDuty)
    saDuty[src] = onDuty == true
    return true
end

-- standalone jobs come from aces, which a script cannot hand out
function FW.standalone.setJob()
    return false
end

local function oxMoneyItem()
    if not Bridge.Started('ox_inventory') then return nil end
    return Bridge.Cfg('standaloneMoneyItem', 'money')
end

function FW.standalone.getMoney(src)
    local item = oxMoneyItem()
    if item then return tonumber(exports.ox_inventory:GetItemCount(src, item)) or 0 end
    return 0
end

function FW.standalone.removeMoney(src, _, amount)
    local item = oxMoneyItem()
    if item then
        if FW.standalone.getMoney(src) < amount then return false end
        return exports.ox_inventory:RemoveItem(src, item, amount) == true
    end
    return Bridge.Cfg('standaloneFreeBills', true) == true
end

function FW.standalone.addMoney(src, _, amount)
    local item = oxMoneyItem()
    if item then return exports.ox_inventory:AddItem(src, item, amount) == true end
    return false
end

function FW.standalone.isAdmin()
    return false
end

function FW.standalone.players()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local src = toSource(s)
        if src then out[#out + 1] = src end
    end
    return out
end

function FW.standalone.hooks(emit)
    AddEventHandler('playerJoining', function()
        local src = toSource(source)
        if src then emit.loaded(src) end
    end)
    -- aces can be changed at runtime: re-check jobs every minute
    CreateThread(function()
        while true do
            Wait(60000)
            for _, src in ipairs(FW.standalone.players()) do emit.job(src) end
        end
    end)
end

AddEventHandler('playerDropped', function()
    saDuty[source] = nil
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIVE ADAPTER
-- ═══════════════════════════════════════════════════════════════════════════

local A = FW[Bridge.Framework] or FW.standalone
if not FW[Bridge.Framework] then Bridge.Framework = 'standalone' end

local function call(method, ...)
    local fn = A[method]
    if not fn then return false end
    return Bridge.Try(Bridge.Framework .. '.' .. method, fn, ...)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LIFECYCLE HOOKS
-- ═══════════════════════════════════════════════════════════════════════════

local loaded = {}       -- [src] = true
local lastJobKey = {}   -- [src] = 'name|grade|duty'
local handlers = { loaded = {}, unloaded = {}, job = {} }
Bridge.Ready = false

local function fire(list, ...)
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            print(('^1[nayzeee-ambulance:bridge]^7 player hook failed: %s'):format(tostring(err)))
        end
    end
end

local function jobKey(job)
    if not job then return 'none' end
    return ('%s|%s|%s'):format(tostring(job.name), tostring(job.grade), tostring(job.onDuty))
end

local function publishJob(src, job)
    if not job or not GetPlayerName(tostring(src)) then return end
    pcall(function()
        Player(src).state:set('nzaJob', {
            name = job.name, label = job.label, grade = job.grade, gradeLabel = job.gradeLabel,
            onDuty = job.onDuty == true, isBoss = job.isBoss == true,
            medic = Bridge.IsMedicJob(job.name), police = Bridge.IsPoliceJob(job.name),
        }, true)
    end)
end

local emit = {}

function emit.loaded(src)
    if not src or loaded[src] then return end
    loaded[src] = true
    local job = Bridge.GetJob(src)
    lastJobKey[src] = jobKey(job)
    publishJob(src, job)
    fire(handlers.loaded, src)
    if NZA and NZA.Bus then NZA.Bus.Emit('bridge:playerLoaded', src) end
end

function emit.unloaded(src)
    if not src or not loaded[src] then return end
    loaded[src] = nil
    lastJobKey[src] = nil
    fire(handlers.unloaded, src)
    if NZA and NZA.Bus then NZA.Bus.Emit('bridge:playerUnloaded', src) end
end

function emit.job(src)
    if not src then return end
    -- defer one tick: frameworks fire the event before every field is updated
    SetTimeout(0, function()
        if not loaded[src] then return end
        local job = Bridge.GetJob(src)
        local key = jobKey(job)
        if key == lastJobKey[src] then return end
        lastJobKey[src] = key
        publishJob(src, job)
        fire(handlers.job, src, job)
        if NZA and NZA.Bus then NZA.Bus.Emit('bridge:jobChanged', src, job) end
    end)
end

if A.hooks then A.hooks(emit) end

AddEventHandler('playerDropped', function()
    local src = toSource(source)
    if not src then return end
    emit.unloaded(src)
    Bridge.ClearThrottle(src)
end)

-- Players that were already in the server when the resource (re)started
CreateThread(function()
    Wait(0)
    for _, src in ipairs(Bridge.GetPlayers()) do
        if not loaded[src] then
            loaded[src] = true
            local job = Bridge.GetJob(src)
            lastJobKey[src] = jobKey(job)
            publishJob(src, job)
        end
    end
    Bridge.Ready = true
    print(('^5[nayzeee-ambulance]^7 Bridge | framework: ^3%s^7'):format(Bridge.Framework))
end)

function Bridge.OnPlayerLoaded(fn, replay)
    handlers.loaded[#handlers.loaded + 1] = fn
    if replay then
        CreateThread(function()
            while not Bridge.Ready do Wait(50) end
            for src in pairs(loaded) do
                local ok, err = pcall(fn, src)
                if not ok then print(('^1[nayzeee-ambulance:bridge]^7 player hook failed: %s'):format(tostring(err))) end
            end
        end)
    end
    return fn
end

function Bridge.OnPlayerUnloaded(fn)
    handlers.unloaded[#handlers.unloaded + 1] = fn
    return fn
end

function Bridge.OnJobChanged(fn)
    handlers.job[#handlers.job + 1] = fn
    return fn
end

function Bridge.IsLoaded(src)
    return loaded[tonumber(src)] == true
end

-- Re-read the job right now (e.g. after an external script changed it silently)
function Bridge.RefreshJob(src)
    emit.job(toSource(src))
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.GetPlayer(src)
    local ok, p = call('player', src)
    return ok and p or nil
end

function Bridge.GetIdentifier(src)
    src = toSource(src)
    if not src then return nil end
    local ok, id = call('identifier', src)
    return ok and id or nil
end

function Bridge.GetSourceFromIdentifier(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return nil end
    local ok, src = call('sourceFromIdentifier', identifier)
    return ok and src or nil
end

function Bridge.GetCharInfo(src)
    src = toSource(src)
    if not src then return nil end
    local ok, info = call('charInfo', src)
    if not ok or not info then
        local first, last = splitName(GetPlayerName(tostring(src)))
        info = { firstname = first, lastname = last, sex = 'm' }
    end
    if not info.phone and Bridge.Phone and Bridge.Phone.Number then
        local okPhone, number = pcall(Bridge.Phone.Number, src)
        if okPhone then info.phone = number end
    end
    return info
end

function Bridge.GetName(src)
    local info = Bridge.GetCharInfo(src)
    if not info then return GetPlayerName(tostring(src)) or ('#' .. tostring(src)) end
    local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return GetPlayerName(tostring(src)) or ('#' .. tostring(src)) end
    return name
end

local UNEMPLOYED = { name = 'unemployed', label = 'Unemployed', grade = 0, gradeLabel = '0', onDuty = false, isBoss = false }

function Bridge.GetJob(src)
    src = toSource(src)
    if not src then return UNEMPLOYED end
    local ok, job = call('job', src)
    if not ok or not job then return UNEMPLOYED end
    return job
end

function Bridge.IsMedic(src)
    return Bridge.IsMedicJob(Bridge.GetJob(src).name)
end

function Bridge.IsPolice(src)
    return Bridge.IsPoliceJob(Bridge.GetJob(src).name)
end

function Bridge.IsOnDuty(src)
    return Bridge.GetJob(src).onDuty == true
end

function Bridge.SetDuty(src, onDuty)
    src = toSource(src)
    if not src then return false end
    local ok, done = call('setDuty', src, onDuty == true)
    if ok and done then
        emit.job(src)
        return true
    end
    return false
end

-- Give the player a framework job. False when the job or grade does not exist, the
-- player is not loaded, or the framework has no jobs to give (standalone aces).
function Bridge.SetJob(src, job, grade)
    src = toSource(src)
    if not src or type(job) ~= 'string' or job == '' then return false end
    grade = math.max(0, math.floor(tonumber(grade) or 0))
    local ok, done = call('setJob', src, job, grade)
    if ok and done == true then
        emit.job(src)
        return true
    end
    return false
end

-- Framework licence check: QBCore / Qbox metadata.licences, ESX esx_license.
-- Where the framework cannot tell (standalone, ESX without esx_license) the ace
-- 'nza.license.<name>' decides. ESX waits for esx_license: call it from a thread.
function Bridge.HasLicense(src, name)
    src = toSource(src)
    if not src or type(name) ~= 'string' or name == '' then return false end
    local ok, has = call('hasLicense', src, name)
    if ok and has ~= nil then return has == true end
    return IsPlayerAceAllowed(tostring(src), 'nza.license.' .. name) == true
end

function Bridge.IsAdmin(src)
    src = toSource(src)
    if not src then return false end
    local ace = (Config.Admin and Config.Admin.ace) or 'nza.admin'
    if IsPlayerAceAllowed(tostring(src), ace) then return true end
    local ok, admin = call('isAdmin', src)
    return ok and admin == true
end

function Bridge.GetPlayers()
    local ok, list = call('players')
    return ok and list or {}
end

function Bridge.GetMedics(onDutyOnly)
    local out = {}
    for _, src in ipairs(Bridge.GetPlayers()) do
        local job = Bridge.GetJob(src)
        if Bridge.IsMedicJob(job.name) and (not onDutyOnly or job.onDuty) then
            out[#out + 1] = src
        end
    end
    return out
end

local function validAmount(amount)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount < 0 then return nil end
    return math.floor(amount + 0.5)
end

function Bridge.GetMoney(src, account)
    src = toSource(src)
    if not src then return 0 end
    local ok, money = call('getMoney', src, account or 'cash')
    return ok and tonumber(money) or 0
end

function Bridge.RemoveMoney(src, account, amount, reason)
    src = toSource(src)
    amount = validAmount(amount)
    if not src or not amount then return false end
    if amount == 0 then return true end
    local ok, done = call('removeMoney', src, account or 'cash', amount, reason or 'nayzeee-ambulance')
    return ok and done == true
end

function Bridge.AddMoney(src, account, amount, reason)
    src = toSource(src)
    amount = validAmount(amount)
    if not src or not amount then return false end
    if amount == 0 then return true end
    local ok, done = call('addMoney', src, account or 'cash', amount, reason or 'nayzeee-ambulance')
    return ok and done ~= false
end
