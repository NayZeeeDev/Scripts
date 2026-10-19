--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: framework (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). ESX / QBCore / Qbox / ox_core / standalone player
    data. Everything is event driven, nothing polls the framework.

      Bridge.Framework
      Bridge.PlayerData() → table                 raw framework player data (standalone: { name, job },
                                                  ox_core: { userId, charId, stateId, groups, activeGroup, job })
      Bridge.IsLoaded()   → bool                  a character is selected
      Bridge.OnPlayerLoaded(fn, replay?)          replay = call fn now if already loaded
      Bridge.OnPlayerUnloaded(fn)                 Bridge.OnJobChanged(fn(job))
      Bridge.GetJob() → { name, label, grade, gradeLabel, onDuty, isBoss }
      Bridge.IsMedic() Bridge.IsPolice() Bridge.IsOnDuty()

    BUS EVENTS (NZA.Bus): 'bridge:playerLoaded', 'bridge:playerUnloaded', 'bridge:jobChanged' (job)
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

local PD = {}
local loaded = false
local lastJobKey = nil
local handlers = { loaded = {}, unloaded = {}, job = {} }

local function fire(list, ...)
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then print(('^1[nayzeee-ambulance:bridge]^7 player hook failed: %s'):format(tostring(err))) end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- JOB NORMALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

local UNEMPLOYED = { name = 'unemployed', label = 'Unemployed', grade = 0, gradeLabel = '0', onDuty = false, isBoss = false }

local function jobFromQB(j)
    if type(j) ~= 'table' then return nil end
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

local function jobFromESX(j)
    if type(j) ~= 'table' then return nil end
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

local function jobFromState(j)
    if type(j) ~= 'table' then return nil end
    return {
        name = j.name, label = j.label or j.name, grade = tonumber(j.grade) or 0,
        gradeLabel = j.gradeLabel or tostring(j.grade or 0), onDuty = j.onDuty == true, isBoss = j.isBoss == true,
    }
end

local readJob

local function jobKey(job)
    if not job then return 'none' end
    return ('%s|%s|%s'):format(tostring(job.name), tostring(job.grade), tostring(job.onDuty))
end

local function checkJob()
    if not loaded then return end
    local job = Bridge.GetJob()
    local key = jobKey(job)
    if key == lastJobKey then return end
    lastJobKey = key
    fire(handlers.job, job)
    if NZA and NZA.Bus then NZA.Bus.Emit('bridge:jobChanged', job) end
end

local function setLoaded(state)
    if loaded == state then return end
    loaded = state
    if state then
        lastJobKey = jobKey(Bridge.GetJob())
        fire(handlers.loaded)
        if NZA and NZA.Bus then NZA.Bus.Emit('bridge:playerLoaded') end
    else
        lastJobKey = nil
        fire(handlers.unloaded)
        if NZA and NZA.Bus then NZA.Bus.Emit('bridge:playerUnloaded') end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- QBCORE / QBOX
-- ═══════════════════════════════════════════════════════════════════════════

local function setupQB(isQbox)
    local getPD
    if isQbox then
        getPD = function() return exports.qbx_core:GetPlayerData() end
    else
        getPD = function()
            local QBCore = Bridge.Core()
            return QBCore and QBCore.Functions.GetPlayerData() or {}
        end
    end
    readJob = function() return jobFromQB(PD.job) end

    local function refresh()
        local ok, data = pcall(getPD)
        if ok and type(data) == 'table' then PD = data end
    end

    refresh()
    if LocalPlayer.state.isLoggedIn or (PD and PD.citizenid) then setLoaded(true) end

    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        refresh()
        setLoaded(true)
        checkJob()
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        setLoaded(false)
        PD = {}
    end)
    RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
        if type(data) == 'table' then PD = data end
        checkJob()
    end)
    -- newer qb-core pushes single keys
    RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, value)
        if key == 'all' and type(value) == 'table' then
            PD = value
        elseif type(key) == 'string' then
            PD[key] = value
        end
        checkJob()
    end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
        if type(job) == 'table' then PD.job = job end
        checkJob()
    end)
    RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
        if PD.job then PD.job.onduty = duty == true end
        checkJob()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ESX
-- ═══════════════════════════════════════════════════════════════════════════

local function setupESX()
    local ESX = Bridge.Core()
    readJob = function() return jobFromESX(PD.job) end
    if not ESX then return end

    local ok, data = pcall(ESX.GetPlayerData)
    if ok and type(data) == 'table' then PD = data end
    if (ESX.IsPlayerLoaded and ESX.IsPlayerLoaded()) or PD.identifier then setLoaded(true) end

    RegisterNetEvent('esx:playerLoaded', function(xPlayer)
        if type(xPlayer) == 'table' then PD = xPlayer end
        setLoaded(true)
        checkJob()
    end)
    RegisterNetEvent('esx:onPlayerLogout', function()
        setLoaded(false)
        PD = {}
    end)
    RegisterNetEvent('esx:setJob', function(job)
        if type(job) == 'table' then PD.job = job end
        checkJob()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- OX_CORE
-- The server builds the job with Bridge.OxJob and keeps duty (ox_core has
-- none), and publishes both in the 'nzaJob' state bag. Until that bag exists
-- the job is built here from the character's groups with the same Bridge.OxJob.
-- Groups follow ox_core's own events: ox:setActiveCharacter, ox:setGroup and
-- ox:setPlayerData (net), ox:playerLoaded / ox:playerLogout (local).
-- ═══════════════════════════════════════════════════════════════════════════

local function setupOx()
    PD = { groups = {} }

    readJob = function()
        if not PD.charId then return nil end   -- character selection: the bag still holds the last character
        local st = LocalPlayer.state.nzaJob
        if type(st) == 'table' and st.name then return jobFromState(st) end
        return Bridge.OxJob(PD.groups or {}, PD.activeGroup, Bridge.Cfg('oxOnDuty', true) == true)
    end

    local function oxCall(method, ...)
        local args = table.pack(...)
        local ok, value = pcall(function()
            return exports.ox_core:CallPlayer(method, table.unpack(args, 1, args.n))
        end)
        return ok and value or nil
    end

    local function refresh()
        local ok, data = pcall(function() return exports.ox_core:GetPlayer() end)
        if ok and type(data) == 'table' then
            PD.userId, PD.charId, PD.stateId = data.userId, data.charId, data.stateId
        end
        if not PD.charId then return end
        local groups = oxCall('getGroups')
        if type(groups) == 'table' then
            PD.groups = {}
            for name, grade in pairs(groups) do PD.groups[name] = grade end
        end
        PD.activeGroup = oxCall('get', 'activeGroup')
        PD.job = LocalPlayer.state.nzaJob
    end

    local function reset()
        setLoaded(false)
        PD = { groups = {} }
    end

    refresh()
    if PD.charId then setLoaded(true) end

    AddEventHandler('ox:playerLoaded', function(data)
        if type(data) == 'table' and data.charId then
            PD.userId, PD.charId, PD.stateId = data.userId, data.charId, data.stateId
        end
        refresh()
        setLoaded(true)
        checkJob()
    end)
    AddEventHandler('ox:playerLogout', reset)
    RegisterNetEvent('ox:startCharacterSelect', function()
        if loaded then reset() end
    end)
    RegisterNetEvent('ox:setActiveCharacter', function(character, groups)
        if type(character) == 'table' then PD.charId, PD.stateId = character.charId, character.stateId end
        PD.groups = {}
        if type(groups) == 'table' then
            for name, grade in pairs(groups) do PD.groups[name] = grade end
        end
    end)
    RegisterNetEvent('ox:setGroup', function(name, grade)
        if type(name) ~= 'string' then return end
        grade = tonumber(grade)
        PD.groups = PD.groups or {}
        PD.groups[name] = (grade and grade > 0) and grade or nil
        checkJob()
    end)
    RegisterNetEvent('ox:setPlayerData', function(key, value)
        if key ~= 'activeGroup' then return end
        PD.activeGroup = value
        checkJob()
    end)
    AddStateBagChangeHandler('nzaJob', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
        PD.job = value
        -- the handler runs before LocalPlayer.state is updated
        SetTimeout(0, checkJob)
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STANDALONE (job comes from the server through the 'nzaJob' state bag)
-- ═══════════════════════════════════════════════════════════════════════════

local function setupStandalone()
    readJob = function() return jobFromState(LocalPlayer.state.nzaJob) end
    PD = { name = GetPlayerName(PlayerId()), job = LocalPlayer.state.nzaJob }

    AddStateBagChangeHandler('nzaJob', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
        PD.job = value
        -- the handler runs before LocalPlayer.state is updated
        SetTimeout(0, checkJob)
    end)

    CreateThread(function()
        while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
        setLoaded(true)
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.PlayerData()
    return PD
end

function Bridge.IsLoaded()
    return loaded
end

function Bridge.OnPlayerLoaded(fn, replay)
    handlers.loaded[#handlers.loaded + 1] = fn
    if replay and loaded then
        CreateThread(function()
            local ok, err = pcall(fn)
            if not ok then print(('^1[nayzeee-ambulance:bridge]^7 player hook failed: %s'):format(tostring(err))) end
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

function Bridge.GetJob()
    local ok, job = pcall(readJob or function() return nil end)
    if ok and job and job.name then return job end
    return UNEMPLOYED
end

function Bridge.IsMedic()
    return Bridge.IsMedicJob(Bridge.GetJob().name)
end

function Bridge.IsPolice()
    return Bridge.IsPoliceJob(Bridge.GetJob().name)
end

function Bridge.IsOnDuty()
    return Bridge.GetJob().onDuty == true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETUP
-- ═══════════════════════════════════════════════════════════════════════════

if Bridge.Framework == 'qbcore' then
    setupQB(false)
elseif Bridge.Framework == 'qbox' then
    setupQB(true)
elseif Bridge.Framework == 'esx' then
    setupESX()
elseif Bridge.Framework == 'ox' then
    setupOx()
else
    setupStandalone()
end
