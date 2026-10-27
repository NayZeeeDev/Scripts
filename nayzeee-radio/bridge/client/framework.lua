--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE RADIO - Bridge: framework (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). ESX / QBCore / Qbox / standalone player data.
    Everything is event driven, nothing polls the framework.

      Bridge.Framework
      Bridge.PlayerData() → table                 raw framework player data (standalone: { name, job })
      Bridge.IsLoaded()   → bool                  a character is selected
      Bridge.OnPlayerLoaded(fn, replay?)          replay = call fn now if already loaded
      Bridge.OnPlayerUnloaded(fn)                 Bridge.OnJobChanged(fn(job))
      Bridge.GetJob() → { name, label, grade, gradeLabel, onDuty, isBoss }
      Bridge.IsOnDuty()

    STATE BAG read: LocalPlayer.state.nzr_job (standalone; published by bridge/server/framework.lua)
    BUS EVENTS (NZR.Bus): 'bridge:playerLoaded', 'bridge:playerUnloaded', 'bridge:jobChanged' (job)
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
        if not ok then print(('^1[nayzeee-radio:bridge]^7 player hook failed: %s'):format(tostring(err))) end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- JOB NORMALIZATION
-- ════════════════════════════════════════════════════════════════════════

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
    if NZR and NZR.Bus then NZR.Bus.Emit('bridge:jobChanged', job) end
end

local function setLoaded(state)
    if loaded == state then return end
    loaded = state
    if state then
        lastJobKey = jobKey(Bridge.GetJob())
        fire(handlers.loaded)
        if NZR and NZR.Bus then NZR.Bus.Emit('bridge:playerLoaded') end
    else
        lastJobKey = nil
        fire(handlers.unloaded)
        if NZR and NZR.Bus then NZR.Bus.Emit('bridge:playerUnloaded') end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- QBCORE / QBOX
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- ESX
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- STANDALONE (job comes from the server through the 'nzr_job' state bag)
-- ════════════════════════════════════════════════════════════════════════

local function setupStandalone()
    readJob = function() return jobFromState(LocalPlayer.state.nzr_job) end
    PD = { name = GetPlayerName(PlayerId()), job = LocalPlayer.state.nzr_job }

    AddStateBagChangeHandler('nzr_job', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
        PD.job = value
        -- the handler runs before LocalPlayer.state is updated
        SetTimeout(0, checkJob)
    end)

    CreateThread(function()
        while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
        setLoaded(true)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ════════════════════════════════════════════════════════════════════════

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
            if not ok then print(('^1[nayzeee-radio:bridge]^7 player hook failed: %s'):format(tostring(err))) end
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

function Bridge.IsOnDuty()
    return Bridge.GetJob().onDuty == true
end

-- ════════════════════════════════════════════════════════════════════════
-- SETUP
-- ════════════════════════════════════════════════════════════════════════

if Bridge.Framework == 'qbcore' then
    setupQB(false)
elseif Bridge.Framework == 'qbox' then
    setupQB(true)
elseif Bridge.Framework == 'esx' then
    setupESX()
else
    setupStandalone()
end
