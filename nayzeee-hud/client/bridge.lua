-- Framework bridge. Everything here is event driven: no polling of framework data.

Bridge = {
    framework = 'standalone',
    data = { cash = 0, bank = 0, job = 'Civilian', grade = false, hunger = 100, thirst = 100, stress = 0 },
}

local D = Bridge.data

local function num(v, fallback)
    v = tonumber(v)
    return v or fallback
end

local function detect()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

local function fromQB(pd)
    if type(pd) ~= 'table' then return end
    if pd.money then
        D.cash = num(pd.money.cash, D.cash)
        D.bank = num(pd.money.bank, D.bank)
    end
    if pd.job then
        D.job = pd.job.label or pd.job.name or D.job
        D.grade = pd.job.grade and (pd.job.grade.name or pd.job.grade.label) or false
    end
    local m = pd.metadata
    if m then
        D.hunger = num(m.hunger, D.hunger)
        D.thirst = num(m.thirst, D.thirst)
        D.stress = num(m.stress, D.stress)
    end
end

local function fromESXAccounts(accounts)
    if type(accounts) ~= 'table' then return end
    for _, a in pairs(accounts) do
        if a.name == 'money' then D.cash = num(a.money, D.cash)
        elseif a.name == 'bank' then D.bank = num(a.money, D.bank) end
    end
end

local function fromESXJob(job)
    if type(job) ~= 'table' then return end
    D.job = job.label or job.name or D.job
    D.grade = job.grade_label or false
end

local function setupQB(fw)
    local getPD
    if fw == 'qbx' then
        getPD = function() return exports.qbx_core:GetPlayerData() end
    else
        local QBCore = exports['qb-core']:GetCoreObject()
        getPD = function() return QBCore.Functions.GetPlayerData() end
    end

    local ok, pd = pcall(getPD)
    if ok then fromQB(pd) end

    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        local ok2, p = pcall(getPD)
        if ok2 then fromQB(p) end
    end)
    RegisterNetEvent('QBCore:Player:SetPlayerData', fromQB)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) fromQB({ job = job }) end)
    RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst)
        D.hunger = num(hunger, D.hunger)
        D.thirst = num(thirst, D.thirst)
    end)
    RegisterNetEvent('hud:client:UpdateStress', function(stress) D.stress = num(stress, D.stress) end)

    -- qbx keeps needs in player state bags
    local bag = ('player:%s'):format(GetPlayerServerId(PlayerId()))
    for _, key in ipairs({ 'hunger', 'thirst', 'stress' }) do
        local current = LocalPlayer.state[key]
        if current then D[key] = num(current, D[key]) end
        AddStateBagChangeHandler(key, bag, function(_, _, value) D[key] = num(value, D[key]) end)
    end
end

local function setupESX()
    local ESX = exports['es_extended']:getSharedObject()
    local pd = ESX.GetPlayerData()
    if pd then
        fromESXAccounts(pd.accounts)
        fromESXJob(pd.job)
    end
    RegisterNetEvent('esx:playerLoaded', function(xPlayer)
        fromESXAccounts(xPlayer.accounts)
        fromESXJob(xPlayer.job)
    end)
    RegisterNetEvent('esx:setAccountMoney', function(account) fromESXAccounts({ account }) end)
    RegisterNetEvent('esx:setJob', fromESXJob)
    AddEventHandler('esx_status:onTick', function(list)
        for _, s in pairs(list) do
            if s.name == 'hunger' or s.name == 'thirst' or s.name == 'stress' then
                D[s.name] = num(s.percent, D[s.name])
            end
        end
    end)
end

CreateThread(function()
    local fw = detect()
    Bridge.framework = fw
    if fw == 'qb' or fw == 'qbx' then
        setupQB(fw)
    elseif fw == 'esx' then
        setupESX()
    end
end)

-- Standalone / custom integrations
exports('SetStatus', function(name, value)
    if name == 'hunger' or name == 'thirst' or name == 'stress' then D[name] = num(value, D[name]) end
end)

exports('SetMoney', function(account, value)
    if account == 'cash' or account == 'bank' then D[account] = num(value, D[account]) end
end)

exports('SetJob', function(label, grade)
    D.job = label or D.job
    D.grade = grade or false
end)
