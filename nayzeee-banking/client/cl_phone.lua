if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  PHONE APP
--
--  Registers the banking app with whichever phone is running:
--  lb-phone, qs-smartphone-pro, okokPhone or a YSeries phone.
--  Every phone loads the same page, and everything phone-specific
--  is kept in this one file.
--
--  The app talks to the same server callbacks as the bank UI, so
--  there is no second set of rules to keep in step — a limit or a
--  permission set in config applies on the phone too.
-- ═══════════════════════════════════════════════════════════

local Phone = { registered = false, adapter = nil }

local APP = {
    identifier  = 'nayzeee-banking',
    name        = 'Banking',
    developer   = 'NAYZEEE Development',
}

local RESOURCE = GetCurrentResourceName()
local ICON = ('https://cfx-nui-%s/web/phone/icon.png'):format(RESOURCE)

--- The same page serves every phone; ?phone= tells it which bridge to use.
local function pageUrl(kind)
    return ('https://cfx-nui-%s/web/phone/index.html?phone=%s'):format(RESOURCE, kind)
end

local function appName() return Config.Phone.appName or APP.name end

-- ═══════════════════════════════════════════════════════════
--  ADAPTERS
--  One per phone. `add` returns true, or false and a reason.
--  `remove` takes the app back off and `push` nudges an open app.
--  Only what a phone documents is used — one without a documented
--  remove or push simply has none here. Links are in the README.
-- ═══════════════════════════════════════════════════════════
local function lbPhone(resource)
    return {
        resource = resource,
        add = function()
            return exports[resource]:AddCustomApp({
                identifier  = APP.identifier,
                name        = appName(),
                description = L('phone_app_description'),
                developer   = APP.developer,
                defaultApp  = Config.Phone.preinstalled ~= false,
                size        = 48210,
                price       = Config.Phone.price or 0,
                ui          = pageUrl('lb'),
                icon        = ICON,
            })
        end,
        remove = function() exports[resource]:RemoveCustomApp(APP.identifier) end,
        push   = function(data) exports[resource]:SendCustomAppMessage(APP.identifier, data) end,
    }
end

local function qsPhone(resource)
    return {
        resource = resource,
        add = function()
            return exports[resource]:addCustomApp({
                app         = APP.identifier,
                image       = ICON,
                ui          = pageUrl('qs'),
                label       = appName(),
                job         = false,
                blockedJobs = {},
                timeout     = 5000,
                creator     = APP.developer,
                category    = 'social',   -- the one Quasar's own template uses
                isGame      = false,
                description = L('phone_app_description'),
                age         = '16+',
                extraDescription = {{
                    header = appName(),
                    head   = appName(),
                    image  = ICON,
                    footer = L('phone_app_description'),
                }},
            })
        end,
        remove = function() exports[resource]:removeCustomApp(APP.identifier) end,
    }
end

local function okokPhone(resource)
    return {
        resource = resource,
        add = function()
            -- loadApp documents no answer, so getting through it
            -- without an error is the only success there is
            exports[resource]:loadApp({
                id                 = APP.identifier,
                label              = appName(),
                description        = L('phone_app_description'),
                custom             = true,
                icon               = ICON,
                previewImagesCount = 0,
                notifications      = true,
                resourceName       = RESOURCE,
                webUrl             = pageUrl('okok'),
            })
            return true
        end,
    }
end

local function ySeries(resource)
    return {
        resource = resource,
        add = function()
            -- the phone turns apps away until its own data has loaded
            local waited = 0
            while not exports[resource]:GetDataLoaded() do
                if waited >= 30000 then return false, 'phone data never finished loading' end
                Wait(500)
                waited = waited + 500
            end

            exports[resource]:AddCustomApp({
                key        = APP.identifier,
                name       = appName(),
                defaultApp = Config.Phone.preinstalled ~= false,
                ui         = pageUrl('ys'),
                icon       = { yos = ICON, humanoid = ICON },
            })
            return true
        end,
        remove = function() exports[resource]:RemoveCustomApp(APP.identifier) end,
    }
end

-- tried in this order when Config.Phone.resource = 'auto'
local SUPPORTED = {
    { resource = 'lb-phone',          make = lbPhone },
    { resource = 'qs-smartphone-pro', make = qsPhone },
    { resource = 'okokPhone',         make = okokPhone },
    { resource = 'yseries',           make = ySeries },
    { resource = 'yphone',            make = ySeries },
    { resource = 'yflip-phone',       make = ySeries },
}

--- The entry for this resource, if the config lets us use it.
local function wanted(resource)
    local pick = Config.Phone.resource or 'auto'
    for _, p in ipairs(SUPPORTED) do
        if p.resource == resource and (pick == 'auto' or pick == resource) then return p end
    end
end

--- The configured phone, or the first supported one that is running.
local function pickPhone()
    for _, p in ipairs(SUPPORTED) do
        if wanted(p.resource) and GetResourceState(p.resource) == 'started' then return p end
    end
end

-- ═══════════════════════════════════════════════════════════
--  REGISTRATION
-- ═══════════════════════════════════════════════════════════
local function register(entry)
    if not Config.Phone or not Config.Phone.enabled then return end

    entry = entry or pickPhone()
    if not entry then
        Bank.debug('no supported phone running — app not registered')
        return
    end

    local adapter = entry.make(entry.resource)
    local ok, added, reason = pcall(adapter.add)

    if not ok or not added then
        print(('^3[nayzeee-banking]^7 %s did not add the banking app: %s'):format(
            entry.resource, tostring(ok and (reason or 'no reason given') or added)))
        return
    end

    Phone.registered = true
    Phone.adapter = adapter
    Bank.debug(('banking app registered with %s'):format(entry.resource))
end

AddEventHandler('onClientResourceStart', function(resource)
    if not Config.Phone or not Config.Phone.enabled then return end

    -- our own start: register with whichever phone is already up
    if resource == RESOURCE then
        return CreateThread(function() register() end)
    end

    -- a phone that starts after us, or restarts and forgets its apps
    local entry = wanted(resource)
    if not entry then return end
    if Phone.registered and Phone.adapter.resource ~= resource then return end

    -- if we got in first while it was still coming up, take that copy
    -- off so the phone does not turn the second one away as a duplicate
    local stale = Phone.adapter
    Phone.registered, Phone.adapter = false, nil
    CreateThread(function()
        Wait(1000)   -- its exports are not there the instant it starts
        if stale and stale.remove then pcall(stale.remove) end
        register(entry)
    end)
end)

AddEventHandler('onClientResourceStop', function(resource)
    local adapter = Phone.adapter
    if not adapter then return end

    -- we are stopping: take the icon off the phone rather than leave a dead app
    if resource == RESOURCE and adapter.remove and GetResourceState(adapter.resource) == 'started' then
        pcall(adapter.remove)
    end

    if resource == RESOURCE or resource == adapter.resource then
        Phone.registered, Phone.adapter = false, nil
    end
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

RegisterNUICallback('phone:savePayee', function(data, cb)
    cb(lib.callback.await('nz_bank:savePayee', false, data.label, tostring(data.number or '')))
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
    local adapter = Phone.registered and Phone.adapter
    -- only lb-phone documents a way in; the other phones refresh on open
    if not adapter or not adapter.push then return end
    pcall(adapter.push, { action = 'refresh' })
end)

exports('phoneAppRegistered', function()
    return Phone.registered
end)
