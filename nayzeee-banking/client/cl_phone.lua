if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  PHONE APP
--
--  Registers the banking app with whichever phone is running.
--  lb-phone is supported out of the box; the same UI is built to
--  drop onto other phones later, so everything phone-specific is
--  kept in this one file.
--
--  The app talks to the same server callbacks as the bank UI, so
--  there is no second set of rules to keep in step — a limit or a
--  permission set in config applies on the phone too.
-- ═══════════════════════════════════════════════════════════

local Phone = { registered = false }

local APP = {
    identifier  = 'nayzeee-banking',
    name        = 'Banking',
    description = 'Balance, transfers, cards and bills',
    developer   = 'NAYZEEE Development',
}

-- ═══════════════════════════════════════════════════════════
--  REGISTRATION
-- ═══════════════════════════════════════════════════════════
local function registerLbPhone()
    if GetResourceState('lb-phone') ~= 'started' then return false end

    local resource = GetCurrentResourceName()

    local ok, err = pcall(function()
        return exports['lb-phone']:AddCustomApp({
            identifier  = APP.identifier,
            name        = Config.Phone.appName or APP.name,
            description = APP.description,
            developer   = APP.developer,
            defaultApp  = Config.Phone.preinstalled ~= false,
            size        = 48210,
            price       = Config.Phone.price or 0,
            ui          = ('https://cfx-nui-%s/web/phone/index.html'):format(resource),
            icon        = ('https://cfx-nui-%s/web/phone/icon.png'):format(resource),
        })
    end)

    if not ok then
        print('^3[nayzeee-banking]^7 lb-phone rejected the app: ' .. tostring(err))
        return false
    end

    Phone.registered = true
    Bank.debug('banking app registered with lb-phone')
    return true
end

local function register()
    if not Config.Phone or not Config.Phone.enabled then return end
    if registerLbPhone() then return end
    Bank.debug('no supported phone running — app not registered')
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function() Wait(2500) register() end)
end)

-- the phone re-registers its apps whenever it restarts
AddEventHandler('lb-phone:resourceReady', function()
    Phone.registered = false
    CreateThread(function() Wait(500) register() end)
end)

-- ═══════════════════════════════════════════════════════════
--  NUI CALLBACKS
--  Only these names are reachable from the app, and each one maps
--  to a server callback that re-checks ownership and permissions.
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('phone:getData', function(_, cb)
    cb(lib.callback.await('nz_bank:getData', false, 'phone') or {})
end)

RegisterNUICallback('phone:transactions', function(data, cb)
    cb(lib.callback.await('nz_bank:getTransactions', false,
        data.account, data.page or 1, '', 'all') or {})
end)

RegisterNUICallback('phone:transfer', function(data, cb)
    cb(lib.callback.await('nz_bank:transfer', false,
        data.from, tostring(data.to or ''), tonumber(data.amount) or 0, data.note))
end)

RegisterNUICallback('phone:updateCard', function(data, cb)
    cb(lib.callback.await('nz_bank:updateCard', false, data.card, data.action, data.value))
end)

RegisterNUICallback('phone:reportCard', function(data, cb)
    cb(lib.callback.await('nz_bank:reportCard', false, data.card))
end)

RegisterNUICallback('phone:payBill', function(data, cb)
    cb(lib.callback.await('nz_bank:payBill', false, data.bill, data.account))
end)

-- Cash never moves on the phone — depositing and withdrawing stay at
-- a machine or a teller, so ATMs and branches keep their reason to exist.

RegisterNUICallback('phone:payLoan', function(data, cb)
    cb(lib.callback.await('nz_bank:payLoan', false, data.loan, nil))
end)

RegisterNUICallback('phone:payOffLoan', function(data, cb)
    cb(lib.callback.await('nz_bank:payOffLoan', false, data.loan))
end)

RegisterNUICallback('phone:requestLoan', function(data, cb)
    cb(lib.callback.await('nz_bank:requestLoan', false, data.tier))
end)

RegisterNUICallback('phone:trade', function(data, cb)
    cb(lib.callback.await('nz_bank:trade', false,
        data.side, data.asset, tonumber(data.amount) or 0, data.account))
end)

RegisterNUICallback('phone:targets', function(_, cb)
    cb(lib.callback.await('nz_bank:phoneTargets', false) or
        { nearby = {}, recent = {}, contacts = {} })
end)

RegisterNUICallback('phone:request', function(data, cb)
    cb(lib.callback.await('nz_bank:requestMoney', false,
        tostring(data.to or ''), tonumber(data.amount) or 0, data.note))
end)

RegisterNUICallback('phone:statement', function(data, cb)
    cb(lib.callback.await('nz_bank:accountStatement', false, data.account, data.period))
end)

RegisterNUICallback('phone:setOverdraft', function(data, cb)
    cb(lib.callback.await('nz_bank:setOverdraft', false, data.on and true or false))
end)

RegisterNUICallback('phone:saveSettings', function(data, cb)
    cb(lib.callback.await('nz_bank:saveSettings', false, data))
end)

-- ═══════════════════════════════════════════════════════════
--  PUSH
--  When a balance moves, nudge the app so an open screen updates.
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('nz_bank:refresh', function()
    if not Phone.registered then return end
    pcall(function()
        exports['lb-phone']:SendCustomAppMessage(APP.identifier, { action = 'refresh' })
    end)
end)

exports('phoneAppRegistered', function()
    return Phone.registered
end)
