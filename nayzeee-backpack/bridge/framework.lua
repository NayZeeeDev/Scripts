-----------------------------------------------------------------
-- Framework bridge
--
-- ESX Legacy, Qbox and QBCore behind one small API, so nothing else
-- in the script cares which one the server runs. Standalone works
-- too: jobs are just empty and money falls back to ox_inventory's
-- 'money' item.
-----------------------------------------------------------------

Framework = { name = 'standalone' }

local IS_SERVER = IsDuplicityVersion()
local ESX, QBCore

local function started(res) return GetResourceState(res) == 'started' end

local function detect()
    local want = Config.Framework or 'auto'

    if (want == 'auto' or want == 'esx') and started('es_extended') then
        local ok, obj = pcall(function() return exports.es_extended:getSharedObject() end)
        if ok and obj then ESX = obj; return 'esx' end
    end
    if (want == 'auto' or want == 'qbx') and started('qbx_core') then
        return 'qbx'
    end
    if (want == 'auto' or want == 'qb') and started('qb-core') then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and obj then QBCore = obj; return 'qb' end
    end
    return 'standalone'
end

Framework.name = detect()
Bags.debug('framework:', Framework.name)

--- Normalise every framework's job into { name, label, grade, onDuty }
local function normaliseJob(job)
    if not job then return nil end
    local grade = job.grade
    if type(grade) == 'table' then grade = grade.level or grade.grade or 0 end
    local onDuty = job.onDuty
    if onDuty == nil then onDuty = job.onduty end
    if onDuty == nil then onDuty = true end
    return {
        name   = job.name,
        label  = job.label or job.name,
        grade  = tonumber(grade) or 0,
        onDuty = onDuty and true or false,
    }
end

if IS_SERVER then
    ---------------------------------------------------------------
    -- SERVER
    ---------------------------------------------------------------

    local function qbPlayer(src)
        if Framework.name == 'qbx' then
            local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
            return ok and p or nil
        elseif QBCore then
            return QBCore.Functions.GetPlayer(src)
        end
    end

    function Framework.getPlayer(src)
        if ESX then return ESX.GetPlayerFromId(src) end
        return qbPlayer(src)
    end

    function Framework.getIdentifier(src)
        if ESX then
            local x = ESX.GetPlayerFromId(src)
            if x then return x.identifier end
        else
            local p = qbPlayer(src)
            if p then return p.PlayerData.citizenid end
        end
        for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
            if id:find('^license:') then return id end
        end
        return ('src:%s'):format(src)
    end

    function Framework.getJob(src)
        if ESX then
            local x = ESX.GetPlayerFromId(src)
            return x and normaliseJob(x.job)
        end
        local p = qbPlayer(src)
        return p and normaliseJob(p.PlayerData.job)
    end

    --- 'cash' or 'bank'
    function Framework.getMoney(src, account)
        account = account or 'cash'
        if ESX then
            local x = ESX.GetPlayerFromId(src)
            if not x then return 0 end
            if account == 'bank' then return x.getAccount('bank').money end
            return x.getMoney()
        end
        local p = qbPlayer(src)
        if p then return p.Functions.GetMoney(account) or 0 end
        if account == 'cash' then
            return exports.ox_inventory:Search(src, 'count', 'money') or 0
        end
        return 0
    end

    function Framework.removeMoney(src, account, amount)
        account = account or 'cash'
        if amount <= 0 then return true end
        if Framework.getMoney(src, account) < amount then return false end

        if ESX then
            local x = ESX.GetPlayerFromId(src)
            if account == 'bank' then x.removeAccountMoney('bank', amount) else x.removeMoney(amount) end
            return true
        end
        local p = qbPlayer(src)
        if p then return p.Functions.RemoveMoney(account, amount, 'bag-store') ~= false end
        if account == 'cash' then return exports.ox_inventory:RemoveItem(src, 'money', amount) end
        return false
    end

    function Framework.addMoney(src, account, amount)
        account = account or 'cash'
        if amount <= 0 then return end
        if ESX then
            local x = ESX.GetPlayerFromId(src)
            if not x then return end
            if account == 'bank' then x.addAccountMoney('bank', amount) else x.addMoney(amount) end
            return
        end
        local p = qbPlayer(src)
        if p then return p.Functions.AddMoney(account, amount, 'bag-store') end
        if account == 'cash' then exports.ox_inventory:AddItem(src, 'money', amount) end
    end

    function Framework.isAdmin(src)
        if src == 0 then return true end
        local admin = Config.Admin or {}
        if admin.ace and IsPlayerAceAllowed(src, admin.ace) then return true end
        if IsPlayerAceAllowed(src, 'command') then return true end

        local groups = admin.groups or {}
        if ESX then
            local x = ESX.GetPlayerFromId(src)
            local g = x and x.getGroup and x.getGroup()
            for _, want in ipairs(groups) do if g == want then return true end end
        elseif QBCore then
            for _, want in ipairs(groups) do
                if QBCore.Functions.HasPermission(src, want) then return true end
            end
        end
        for _, want in ipairs(groups) do
            if IsPlayerAceAllowed(src, 'group.' .. want) then return true end
        end
        return false
    end

    --- Fires cb(src, job) whenever a player's job (or duty) changes.
    local jobListeners = {}
    function Framework.onJobChange(cb) jobListeners[#jobListeners + 1] = cb end

    local function fireJob(src)
        if type(src) ~= 'number' then return end
        local job = Framework.getJob(src)
        for _, cb in ipairs(jobListeners) do cb(src, job) end
    end

    AddEventHandler('esx:setJob', function(src) fireJob(src) end)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src) fireJob(src) end)
    AddEventHandler('QBCore:Server:SetDuty', function(src) fireJob(src) end)
    AddEventHandler('qbx_core:server:onJobUpdate', function(src) fireJob(src) end)
    RegisterNetEvent('QBCore:ToggleDuty', function() local s = source; SetTimeout(250, function() fireJob(s) end) end)

    -- some job scripts only toggle duty client-side; the client nudges us
    RegisterNetEvent('nayzeee-backpack:jobPing', function()
        fireJob(source)
    end)

    --- Fires cb(src) once the player's character is loaded.
    local loadListeners = {}
    function Framework.onPlayerLoaded(cb) loadListeners[#loadListeners + 1] = cb end
    local function fireLoad(src)
        for _, cb in ipairs(loadListeners) do cb(src) end
    end
    AddEventHandler('esx:playerLoaded', function(src) fireLoad(src) end)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(p)
        local src = type(p) == 'table' and p.PlayerData and p.PlayerData.source or p
        if type(src) == 'number' then fireLoad(src) end
    end)
else
    ---------------------------------------------------------------
    -- CLIENT
    ---------------------------------------------------------------

    Framework.job = nil
    local jobListeners, loadListeners = {}, {}

    function Framework.onJobChange(cb) jobListeners[#jobListeners + 1] = cb end
    function Framework.onPlayerLoaded(cb) loadListeners[#loadListeners + 1] = cb end

    local function setJob(job)
        Framework.job = normaliseJob(job)
        for _, cb in ipairs(jobListeners) do cb(Framework.job) end
    end

    local function loaded()
        for _, cb in ipairs(loadListeners) do cb() end
    end

    function Framework.getJob() return Framework.job end

    function Framework.getPlayerData()
        if ESX then return ESX.GetPlayerData() end
        if Framework.name == 'qbx' then
            local ok, d = pcall(function() return exports.qbx_core:GetPlayerData() end)
            return ok and d or {}
        end
        if QBCore then return QBCore.Functions.GetPlayerData() end
        return {}
    end

    --- QB metadata, used for cuffed / dead checks
    function Framework.getMeta(key)
        if ESX then return nil end
        local d = Framework.getPlayerData()
        return d and d.metadata and d.metadata[key]
    end

    CreateThread(function()
        local d = Framework.getPlayerData()
        if d and d.job then setJob(d.job) end
    end)

    RegisterNetEvent('esx:setJob', function(job) setJob(job) end)
    RegisterNetEvent('esx:playerLoaded', function(x)
        if x and x.job then setJob(x.job) end
        loaded()
    end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) setJob(job) end)
    RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
        if Framework.job then
            Framework.job.onDuty = duty and true or false
            for _, cb in ipairs(jobListeners) do cb(Framework.job) end
        end
        TriggerServerEvent('nayzeee-backpack:jobPing')
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        local d = Framework.getPlayerData()
        if d and d.job then setJob(d.job) end
        loaded()
    end)
    RegisterNetEvent('qbx_core:client:playerLoaded', loaded)
end
