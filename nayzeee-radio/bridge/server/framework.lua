--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE RADIO - Bridge: framework (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). One adapter per framework: es_extended (ESX
    Legacy), qb-core, qbx_core (Qbox) and standalone (license identifier, ace
    based jobs). Fix or extend an adapter here if your framework fork differs -
    nothing else in the resource talks to the framework directly.

    API
      Bridge.Framework                          'esx' | 'qbcore' | 'qbox' | 'standalone'
      Bridge.OnPlayerLoaded(fn(src), replay?)   replay = also call fn for players already loaded
      Bridge.OnPlayerUnloaded(fn(src))          Bridge.OnJobChanged(fn(src, job))
      Bridge.IsLoaded(src)                      Bridge.RefreshJob(src)
      Bridge.GetPlayer(src) → raw framework player
      Bridge.GetIdentifier(src)                 Bridge.GetSourceFromIdentifier(id)
      Bridge.GetName(src) → 'First Last'        Bridge.GetCharInfo(src) → { firstname, lastname, dob, sex, phone }
      Bridge.GetJob(src) → { name, label, grade, gradeLabel, onDuty, isBoss }
      Bridge.IsOnDuty(src)                      Bridge.IsAdmin(src)
      Bridge.GetPlayers() → { src, ... }        players with a loaded character
      Bridge.GetJobs() → { { name, label, grades = { { grade, label }, ... } }, ... }
                                                every job the framework knows (admin job picker),
                                                sorted by label, grades ascending

    STATE BAG
      Player(src).state.nzr_job = { name, label, grade, gradeLabel, onDuty, isBoss }
      (replicated, refreshed on load / job change / duty change, cleared when the resource stops)

    BUS EVENTS (NZR.Bus)
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

-- Job lists come in as { [name] = def } maps or arrays; grades as { [grade] = def } maps.
local function sortJobs(list)
    table.sort(list, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    for _, job in ipairs(list) do
        table.sort(job.grades, function(a, b) return a.grade < b.grade end)
    end
    return list
end

-- ════════════════════════════════════════════════════════════════════════
-- ESX (es_extended / ESX Legacy)
-- ════════════════════════════════════════════════════════════════════════

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

-- ESX.GetJobs() → { [name] = { name, label, grades = { [grade] = { grade, name, label } } } }.
-- Off-duty twins ('offpolice') are folded into their base job.
function FW.esx.jobs()
    local ESX = core()
    if not (ESX and ESX.GetJobs) then return nil end
    local out = {}
    for key, def in pairs(ESX.GetJobs() or {}) do
        local name = type(def) == 'table' and def.name or key
        local base, off = Bridge.SplitDutyJob(name)
        if type(base) == 'string' and off == nil then
            local grades = {}
            for g, gd in pairs(type(def) == 'table' and def.grades or {}) do
                local grade = tonumber(type(gd) == 'table' and gd.grade or g)
                if grade then
                    grades[#grades + 1] = { grade = grade, label = type(gd) == 'table' and (gd.label or gd.name) or tostring(grade) }
                end
            end
            out[#out + 1] = { name = base, label = def.label or base, grades = grades }
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

-- ════════════════════════════════════════════════════════════════════════
-- QBCORE (qb-core)
-- ════════════════════════════════════════════════════════════════════════

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

-- QBCore.Shared.Jobs / qbx GetJobs(): { [name] = { label, grades = { ['0'] = { name }, ... } } }
local function qbJobList(jobs)
    if type(jobs) ~= 'table' then return nil end
    local out = {}
    for name, def in pairs(jobs) do
        if type(name) == 'string' and type(def) == 'table' then
            local grades = {}
            for g, gd in pairs(def.grades or {}) do
                local grade = tonumber(g)
                if grade then
                    grades[#grades + 1] = { grade = grade, label = type(gd) == 'table' and (gd.name or gd.label) or tostring(grade) }
                end
            end
            out[#out + 1] = { name = name, label = def.label or name, grades = grades }
        end
    end
    return out
end

function FW.qbcore.jobs()
    local QBCore = core()
    return qbJobList(QBCore and QBCore.Shared and QBCore.Shared.Jobs)
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

-- ════════════════════════════════════════════════════════════════════════
-- QBOX (qbx_core)
-- ════════════════════════════════════════════════════════════════════════

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

function FW.qbox.jobs()
    return qbJobList(exports.qbx_core:GetJobs())
end

function FW.qbox.hooks(emit)
    qbHooks(emit)
    AddEventHandler('qbx_core:server:playerLoggedOut', function(src) emit.unloaded(toSource(src)) end)
end

-- ════════════════════════════════════════════════════════════════════════
-- STANDALONE (license identifier, ace based jobs)
-- The first job of Config.Bridge.standaloneJobs the player has is theirs:
-- 'nzr.job.police' gives the job, 'nzr.grade.police.<n>' grade n (and the job),
-- 'nzr.grade.police.boss' the boss flag. Grades sit outside 'nzr.job.police' on
-- purpose: aces are inherited, so 'nzr.job.police.3' would pass for everyone
-- who has 'nzr.job.police' and every officer would get the highest grade.
-- ════════════════════════════════════════════════════════════════════════

FW.standalone = {}

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

local function standaloneJobs()
    local list = Bridge.Cfg('standaloneJobs', {})
    return type(list) == 'table' and list or {}
end

function FW.standalone.job(src)
    local s = tostring(src)
    local jobPrefix = Bridge.Cfg('standaloneJobAce', 'nzr.job')
    local gradePrefix = Bridge.Cfg('standaloneGradeAce', 'nzr.grade')
    local onDuty = Bridge.Cfg('standaloneOnDuty', true) == true
    for _, def in ipairs(standaloneJobs()) do
        local name = type(def) == 'table' and def.name or def
        if type(name) == 'string' and name ~= '' then
            local gradeAce = ('%s.%s'):format(gradePrefix, name)
            local grade = aceGrade(src, gradeAce)
            if grade or IsPlayerAceAllowed(s, ('%s.%s'):format(jobPrefix, name)) then
                grade = grade or 0
                return {
                    name = name,
                    label = type(def) == 'table' and def.label or name,
                    grade = grade,
                    gradeLabel = tostring(grade),
                    onDuty = onDuty,
                    isBoss = IsPlayerAceAllowed(s, gradeAce .. '.boss') == true,
                }
            end
        end
    end
    return { name = 'unemployed', label = 'Civilian', grade = 0, gradeLabel = '0', onDuty = true, isBoss = false }
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

function FW.standalone.jobs()
    local out = {}
    local max = Bridge.Cfg('standaloneMaxGrade', 10)
    for _, def in ipairs(standaloneJobs()) do
        local name = type(def) == 'table' and def.name or def
        if type(name) == 'string' and name ~= '' then
            local grades = {}
            for g = 0, max do grades[#grades + 1] = { grade = g, label = tostring(g) } end
            out[#out + 1] = { name = name, label = type(def) == 'table' and def.label or name, grades = grades }
        end
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

-- ════════════════════════════════════════════════════════════════════════
-- ACTIVE ADAPTER
-- ════════════════════════════════════════════════════════════════════════

local A = FW[Bridge.Framework] or FW.standalone
if not FW[Bridge.Framework] then Bridge.Framework = 'standalone' end

local function call(method, ...)
    local fn = A[method]
    if not fn then return false end
    return Bridge.Try(Bridge.Framework .. '.' .. method, fn, ...)
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE HOOKS
-- ════════════════════════════════════════════════════════════════════════

local loaded = {}       -- [src] = true
local lastJobKey = {}   -- [src] = 'name|grade|duty'
local handlers = { loaded = {}, unloaded = {}, job = {} }
Bridge.Ready = false

local function fire(list, ...)
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            print(('^1[nayzeee-radio:bridge]^7 player hook failed: %s'):format(tostring(err)))
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
        Player(src).state:set('nzr_job', {
            name = job.name, label = job.label, grade = job.grade, gradeLabel = job.gradeLabel,
            onDuty = job.onDuty == true, isBoss = job.isBoss == true,
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
    if NZR and NZR.Bus then NZR.Bus.Emit('bridge:playerLoaded', src) end
end

function emit.unloaded(src)
    if not src or not loaded[src] then return end
    loaded[src] = nil
    lastJobKey[src] = nil
    fire(handlers.unloaded, src)
    if NZR and NZR.Bus then NZR.Bus.Emit('bridge:playerUnloaded', src) end
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
        if NZR and NZR.Bus then NZR.Bus.Emit('bridge:jobChanged', src, job) end
    end)
end

if A.hooks then A.hooks(emit) end

AddEventHandler('playerDropped', function()
    local src = toSource(source)
    if not src then return end
    emit.unloaded(src)
    Bridge.ClearThrottle(src)
end)

-- our state bags go away with the resource (SPEC §2)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, s in ipairs(GetPlayers()) do
        pcall(function() Player(tonumber(s)).state:set('nzr_job', nil, true) end)
    end
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
    Bridge.Debug('framework:', Bridge.Framework)
end)

function Bridge.OnPlayerLoaded(fn, replay)
    handlers.loaded[#handlers.loaded + 1] = fn
    if replay then
        CreateThread(function()
            while not Bridge.Ready do Wait(50) end
            for src in pairs(loaded) do
                local ok, err = pcall(fn, src)
                if not ok then print(('^1[nayzeee-radio:bridge]^7 player hook failed: %s'):format(tostring(err))) end
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

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ════════════════════════════════════════════════════════════════════════

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

function Bridge.IsOnDuty(src)
    return Bridge.GetJob(src).onDuty == true
end

function Bridge.IsAdmin(src)
    src = toSource(src)
    if not src then return false end
    local ace = (Config.Admin and Config.Admin.ace) or 'nzr.admin'
    if IsPlayerAceAllowed(tostring(src), ace) then return true end
    local ok, admin = call('isAdmin', src)
    return ok and admin == true
end

function Bridge.GetPlayers()
    local ok, list = call('players')
    return ok and list or {}
end

-- Never nil: a framework without a job list (or a failing export) gives the standalone
-- list from Config.Bridge.standaloneJobs, so the admin job picker always has something.
function Bridge.GetJobs()
    local ok, list = call('jobs')
    if not ok or type(list) ~= 'table' or #list == 0 then
        list = FW.standalone.jobs()
    end
    return sortJobs(list)
end
