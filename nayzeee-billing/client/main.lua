--[[
    NAYZEEE BILLING - Client Main
    Discord: discord.gg/nayzeeedev
]]

UI = {
    open = false,      -- a focused view (billing / admin / pos / checkout) is open
    mode = nil,
    display = false,   -- passive customer display visible (no focus)
}

-- ███╗   ██╗██╗   ██╗██╗
-- ████╗  ██║██║   ██║██║
-- ██╔██╗ ██║██║   ██║██║
-- ██║╚██╗██║██║   ██║██║
-- ██║ ╚████║╚██████╔╝██║
-- ╚═╝  ╚═══╝ ╚═════╝ ╚═╝

function UI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function UI.Focus(mode)
    UI.open = mode ~= nil
    UI.mode = mode
    SetNuiFocus(UI.open, UI.open)
    SetNuiFocusKeepInput(false)
end

function UI.Close()
    UI.Focus(nil)
    UI.Send('close')
end

function UI.Toast(title, message, notifType)
    if UI.open then
        UI.Send('toast', { title = title, message = message, type = notifType or 'info' })
    else
        ClientBridge.Notify(title, message, notifType)
    end
end

-- Server RPC from Lua (returns ok, data|error)
function Rpc(name, payload)
    local res = lib.callback.await('nayzeee-billing:' .. name, false, payload or {})
    if type(res) ~= 'table' then return false, 'No response from server' end
    if not res.ok then return false, res.error end
    return true, res.data
end

--  ██████╗ ██████╗ ███████╗███╗   ██╗
-- ██╔═══██╗██╔══██╗██╔════╝████╗  ██║
-- ██║   ██║██████╔╝█████╗  ██╔██╗ ██║
-- ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║
-- ╚██████╔╝██║     ███████╗██║ ╚████║
--  ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝

function OpenBilling(tab, invoiceId)
    if UI.open then return end
    local ok, ctx = Rpc('getContext')
    if not ok then
        ClientBridge.Notify('Billing', ctx or 'Unable to open billing', 'error')
        return
    end
    ctx.tab = tab
    ctx.openInvoice = invoiceId
    UI.Focus('billing')
    UI.Send('open', ctx)
end

function OpenAdmin()
    if UI.open then return end
    if not lib.callback.await('nayzeee-billing:isAdmin', false) then
        ClientBridge.Notify('Access denied', 'You do not have billing admin access', 'error')
        return
    end
    local ok, data = Rpc('admin:getData')
    if not ok then
        ClientBridge.Notify('Billing', data, 'error')
        return
    end
    UI.Focus('admin')
    UI.Send('openAdmin', data)
end

RegisterCommand(Config.Command, function() OpenBilling() end, false)
if Config.OpenKey then
    RegisterKeyMapping(Config.Command, 'Open Billing', 'keyboard', Config.OpenKey)
end
RegisterCommand(Config.AdminCommand, function() OpenAdmin() end, false)

-- /invoice BS-000142 → opens that invoice (if you're allowed to see it)
local invoiceCommand = Config.Invoices.InvoiceCommand
if invoiceCommand then
    RegisterCommand(invoiceCommand, function(_, args)
        local reference = args[1]
        if not reference then
            OpenBilling('history')
            return
        end
        local ok, data = Rpc('findInvoice', { reference = reference })
        if not ok then
            ClientBridge.Notify('Billing', data, 'error')
            return
        end
        if UI.open and UI.mode == 'billing' then
            UI.Send('openInvoice', data.invoiceId)
        elseif not UI.open then
            OpenBilling(nil, data.invoiceId)
        end
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. invoiceCommand, 'Open an invoice by its reference number', {
        { name = 'reference', help = 'e.g. BS-000142 or BS-142' },
    })
end

--  ██████╗ █████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗███████╗
-- ██╔════╝██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
-- ██║     ███████║██║     ██║     ██████╔╝███████║██║     █████╔╝ ███████╗
-- ██║     ██╔══██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ╚════██║
-- ╚██████╗██║  ██║███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗███████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

-- Allowed server RPCs from the UI (server re-checks every permission anyway)
local AllowedRpc = {}
for _, name in ipairs({
    'getContext', 'getNearby', 'searchPlayers', 'getItems', 'createInvoice', 'payInvoice', 'getHistory', 'findInvoice',
    'getInvoice', 'cancelInvoice', 'disputeInvoice',
    'boss:getDashboard', 'boss:getInvoices', 'boss:refund', 'boss:resolveDispute',
    'catalog:saveProduct', 'catalog:deleteProduct', 'catalog:saveCategory', 'catalog:deleteCategory',
    'catalog:saveQuickBill', 'catalog:deleteQuickBill',
    'admin:getData', 'admin:saveCompany', 'admin:deleteCompany', 'admin:saveRegister', 'admin:deleteRegister',
    'admin:teleport', 'admin:getInvoices', 'admin:getLogs',
    'register:nearby', 'register:assign', 'register:update', 'register:charge', 'register:next',
    'display:pay',
}) do AllowedRpc[name] = true end

RegisterNUICallback('rpc', function(data, cb)
    if type(data) ~= 'table' or not AllowedRpc[data.name] then
        cb({ ok = false, error = 'Unknown action' })
        return
    end
    local res = lib.callback.await('nayzeee-billing:' .. data.name, false, data.payload or {})
    cb(type(res) == 'table' and res or { ok = false, error = 'No response from server' })
end)

RegisterNUICallback('close', function(_, cb)
    -- A late close (e.g. from a receipt that was open) must not steal focus from a register checkout
    if UI.mode ~= 'checkout' then UI.Focus(nil) end
    cb('ok')
end)

RegisterNUICallback('notify', function(data, cb)
    ClientBridge.Notify(data.title or 'Billing', data.message or '', data.type)
    cb('ok')
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    if data and data.x and data.y then SetNewWaypoint(data.x + 0.0, data.y + 0.0) end
    cb('ok')
end)

-- ███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
-- ██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
-- █████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
-- ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
-- ███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
-- ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

RegisterNetEvent('nayzeee-billing:client:notify', function(data)
    UI.Toast(data.title, data.message, data.type)
end)

RegisterNetEvent('nayzeee-billing:client:newInvoice', function(invoice)
    if Config.Notifications.EnableSounds then
        PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', false)
    end
    UI.Toast('New invoice', ('%s · %s from %s'):format(invoice.id, Shared.FormatCurrency(invoice.total), invoice.company), 'info')
    if UI.open then UI.Send('invoiceNew', invoice) end
end)

RegisterNetEvent('nayzeee-billing:client:invoicePaid', function(data)
    local msg = ('%s paid %s'):format(data.playerName, Shared.FormatCurrency(data.amount))
    if (data.tip or 0) > 0 then msg = msg .. (' + %s tip'):format(Shared.FormatCurrency(data.tip)) end
    if (data.commission or 0) > 0 then msg = msg .. (' · you earned %s'):format(Shared.FormatCurrency(data.commission)) end
    UI.Toast('Payment received', msg, 'success')
    if Config.Notifications.EnableSounds then
        PlaySoundFrontend(-1, 'PICKUP_WEAPON_SMOKEGRENADE', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    end
    if UI.open then UI.Send('refresh') end
end)

RegisterNetEvent('nayzeee-billing:client:invoiceChanged', function()
    if UI.open then UI.Send('refresh') end
end)

RegisterNetEvent('nayzeee-billing:client:companiesChanged', function()
    if UI.open and UI.mode == 'billing' then UI.Send('refresh') end
end)

RegisterNetEvent('nayzeee-billing:client:showReceipt', function(invoice)
    if not UI.open then UI.Focus('receipt') end
    UI.Send('receipt', invoice)
end)

-- ██████╗ ███████╗ ██████╗███████╗██╗██████╗ ████████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔════╝██║██╔══██╗╚══██╔══╝██╔════╝
-- ██████╔╝█████╗  ██║     █████╗  ██║██████╔╝   ██║   ███████╗
-- ██╔══██╗██╔══╝  ██║     ██╔══╝  ██║██╔═══╝    ██║   ╚════██║
-- ██║  ██║███████╗╚██████╗███████╗██║██║        ██║   ███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝╚══════╝╚═╝╚═╝        ╚═╝   ╚══════╝

-- ox_inventory: item definition `client = { export = 'nayzeee-billing.useReceipt' }`
exports('useReceipt', function(_, slot)
    local invoiceId = slot and slot.metadata and slot.metadata.invoiceId
    if not invoiceId then
        ClientBridge.Notify('Receipt', 'This receipt is unreadable', 'error')
        return
    end
    local ok, invoice = Rpc('getInvoice', { invoiceId = invoiceId })
    if not ok then
        ClientBridge.Notify('Receipt', invoice, 'error')
        return
    end
    if not UI.open then UI.Focus('receipt') end
    UI.Send('receipt', invoice)
end)

-- ████████╗███████╗██╗     ██╗     ███████╗██████╗
-- ╚══██╔══╝██╔════╝██║     ██║     ██╔════╝██╔══██╗
--    ██║   █████╗  ██║     ██║     █████╗  ██████╔╝
--    ██║   ██╔══╝  ██║     ██║     ██╔══╝  ██╔══██╗
--    ██║   ███████╗███████╗███████╗███████╗██║  ██║
--    ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝

local tellerZones = {}

local function CollectCash()
    local ok, data = Rpc('collectCash')
    if not ok then
        ClientBridge.Notify('Bank teller', data, 'error')
    elseif (data.amount or 0) > 0 then
        ClientBridge.Notify('Cash collected', 'You collected ' .. Shared.FormatCurrency(data.amount), 'success')
    else
        ClientBridge.Notify('Bank teller', 'You have no cash payments to collect', 'info')
    end
end

local function SetupTellers()
    if not (Config.Payment.PersonalInvoice and Config.Payment.PersonalInvoice.CashRequiresCollection) then return end
    for i, teller in ipairs(Config.Payment.BankTellers or {}) do
        if ClientBridge.HasTarget() then
            tellerZones[#tellerZones + 1] = ClientBridge.AddSphereZone('billing_teller_' .. i, teller.coords, 1.5, {
                { name = 'billing_collect_' .. i, label = 'Collect Cash Payments', icon = 'fa-solid fa-money-bill-wave', onSelect = CollectCash },
            })
        else
            lib.points.new({
                coords = teller.coords,
                distance = 2.0,
                onEnter = function() lib.showTextUI('[E] Collect Cash Payments') end,
                onExit = function() lib.hideTextUI() end,
                nearby = function(point)
                    if point.currentDistance < 1.6 and IsControlJustReleased(0, 38) then CollectCash() end
                end,
            })
        end
    end
end

-- ██╗███╗   ██╗██╗████████╗
-- ██║████╗  ██║██║╚══██╔══╝
-- ██║██╔██╗ ██║██║   ██║
-- ██║██║╚██╗██║██║   ██║
-- ██║██║ ╚████║██║   ██║
-- ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝

CreateThread(function()
    ClientBridge.Init()
    Wait(1500)
    SetupTellers()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if UI.open then SetNuiFocus(false, false) end
    for _, zone in ipairs(tellerZones) do ClientBridge.RemoveZone(zone) end
end)

exports('OpenBilling', OpenBilling)
exports('OpenAdmin', OpenAdmin)
exports('IsOpen', function() return UI.open end)
