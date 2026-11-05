--[[
    NAYZEEE BILLING - Client
    Discord: discord.gg/nayzeeedev
]]

UI = { open = false, mode = nil, display = false }

-- ███╗   ██╗██╗   ██╗██╗
-- ████╗  ██║██║   ██║██║
-- ██╔██╗ ██║██║   ██║██║
-- ██║╚██╗██║██║   ██║██║
-- ██║ ╚████║╚██████╔╝██║
-- ╚═╝  ╚═══╝ ╚═════╝ ╚═╝

function UI.Send(action, data) SendNUIMessage({ action = action, data = data }) end

function UI.Focus(mode)
    local was = UI.open
    UI.open, UI.mode = mode ~= nil, mode
    SetNuiFocus(UI.open, UI.open)
    SetNuiFocusKeepInput(false)
    if was ~= UI.open or mode then TriggerEvent('nayzeee-billing:client:uiState', UI.open, mode) end
end

function UI.Toast(title, message, kind)
    if UI.open then UI.Send('toast', { title = title, message = message, type = kind or 'info' })
    else ClientBridge.Notify(title, message, kind) end
end

function Rpc(name, payload)
    local res = lib.callback.await('nayzeee-billing:' .. name, false, payload or {})
    if type(res) ~= 'table' then return false, L('error.no_response', 'No response from server') end
    if not res.ok then return false, res.error end
    return true, res.data
end

local function sendInit()
    UI.Send('init', {
        locale = Shared.LocaleTable(),
        colors = Config.UI.Colors,
        title = Config.UI.Title, brand = Config.UI.Brand, clock = Config.UI.ShowClock,
        currency = Config.Currency, currencyPosition = Config.CurrencyPosition,
        keybind = Config.Keybind.Key,
    })
end

RegisterNUICallback('uiReady', function(_, cb) sendInit() cb('ok') end)

--  ██████╗ ██████╗ ███████╗███╗   ██╗
-- ██╔═══██╗██╔══██╗██╔════╝████╗  ██║
-- ██║   ██║██████╔╝█████╗  ██╔██╗ ██║
-- ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║
-- ╚██████╔╝██║     ███████╗██║ ╚████║
--  ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝

-- page: overview / received / sent / templates / activity / permissions / inspect
-- extra: { invoiceId, payRef, create = { recipientId } }
function OpenBilling(page, extra)
    if UI.open then
        if extra or page then UI.Send('navigate', { page = page, extra = extra }) end
        return
    end
    local ok, ctx = Rpc('getContext')
    if not ok then ClientBridge.Notify(Config.UI.Title, ctx, 'error') return end
    sendInit()
    UI.Focus('billing')
    UI.Send('open', { ctx = ctx, page = page, extra = extra })
end

function CloseBilling()
    if not UI.open then return end
    UI.Focus(nil)
    UI.Send('close')
end

if Config.Keybind.Enabled then
    RegisterCommand(Config.Keybind.Command, function() OpenBilling() end, false)
    RegisterKeyMapping(Config.Keybind.Command, Config.Keybind.Description, 'keyboard', Config.Keybind.Key)
end

RegisterCommand(Config.AdminCommand, function()
    if not lib.callback.await('nayzeee-billing:isAdmin', false) then
        ClientBridge.Notify(Config.UI.Title, L('error.no_permission', 'You do not have permission'), 'error')
        return
    end
    OpenBilling('inspect')
end, false)

--  ██████╗ █████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗███████╗
-- ██╔════╝██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
-- ██║     ███████║██║     ██║     ██████╔╝███████║██║     █████╔╝ ███████╗
-- ██║     ██╔══██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ╚════██║
-- ╚██████╗██║  ██║███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗███████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

local Allowed = {}
for _, n in ipairs({
    'getContext', 'getNearby', 'invoices:create', 'invoices:list', 'invoices:get', 'invoices:lookup', 'invoices:pay', 'invoices:payMany',
    'invoices:cancel', 'invoices:dispute', 'invoices:resolve', 'invoices:refund', 'invoices:print',
    'dashboard:get', 'activity:list',
    'templates:list', 'templates:save', 'templates:delete', 'templates:saveItem', 'templates:deleteItem', 'templates:reorder',
    'perms:get', 'perms:assign', 'perms:saveGroup', 'perms:deleteGroup',
    'inspect:search', 'inspect:profile', 'admin:delete', 'admin:clear',
    'admin:registers', 'admin:addRegister', 'admin:deleteRegister', 'admin:teleport',
    'register:nearby', 'register:assign', 'register:update', 'register:charge', 'register:next', 'display:pay',
}) do Allowed[n] = true end

RegisterNUICallback('rpc', function(data, cb)
    if type(data) ~= 'table' or not Allowed[data.name] then cb({ ok = false, error = 'Unknown action' }) return end
    local res = lib.callback.await('nayzeee-billing:' .. data.name, false, data.payload or {})
    cb(type(res) == 'table' and res or { ok = false, error = L('error.no_response', 'No response from server') })
end)

RegisterNUICallback('close', function(_, cb)
    if UI.mode ~= 'checkout' then UI.Focus(nil) end
    cb('ok')
end)

RegisterNUICallback('setWaypoint', function(d, cb)
    if d and d.x and d.y then SetNewWaypoint(d.x + 0.0, d.y + 0.0) end
    cb('ok')
end)

-- ███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
-- ██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
-- █████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
-- ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
-- ███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
-- ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

RegisterNetEvent('nayzeee-billing:client:notify', function(d) UI.Toast(d.title, d.message, d.type) end)

RegisterNetEvent('nayzeee-billing:client:newInvoice', function(inv)
    if Config.Notify.Sounds then PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', false) end
    UI.Toast(L('notify.new_invoice', 'New invoice'), L('notify.new_invoice_body', '{amount} from {sender} · {ref}',
        { amount = Shared.Money(inv.total), sender = inv.sender, ref = inv.ref }), 'info')
    if UI.open then UI.Send('refresh') end
end)

RegisterNetEvent('nayzeee-billing:client:invoicePaid', function(d)
    local msg = L('notify.paid_body', '{name} paid {amount} · {ref}', { name = d.payer, amount = Shared.Money(d.amount), ref = d.ref })
    if (d.share or 0) > 0 then msg = msg .. ' · ' .. L('notify.your_share', 'you earned {amount}', { amount = Shared.Money(d.share) }) end
    UI.Toast(L('notify.paid', 'Payment received'), msg, 'success')
    if Config.Notify.Sounds then PlaySoundFrontend(-1, 'PICKUP_WEAPON_SMOKEGRENADE', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false) end
    if UI.open then UI.Send('refresh') end
end)

RegisterNetEvent('nayzeee-billing:client:refresh', function() if UI.open then UI.Send('refresh') end end)

-- Paper invoice / receipt view (item use)
local function showPaper(inv)
    sendInit()
    if not UI.open then UI.Focus('paper') end
    UI.Send('paper', inv)
end
RegisterNetEvent('nayzeee-billing:client:paper', showPaper)

-- ox_inventory: client = { export = 'nayzeee-billing.useInvoice' } on both the invoice and receipt items
exports('useInvoice', function(_, slot)
    local ref = slot and slot.metadata and slot.metadata.reference
    if not ref then ClientBridge.Notify(Config.UI.Title, L('error.unreadable', 'This paper is unreadable'), 'error') return end
    local ok, inv = Rpc('invoices:get', { ref = ref })
    if not ok then ok, inv = Rpc('invoices:lookup', { ref = ref }) end
    if not ok then ClientBridge.Notify(Config.UI.Title, inv, 'error') return end
    showPaper(inv)
end)

-- ████████╗███████╗██╗     ██╗     ███████╗██████╗ ███████╗
-- ╚══██╔══╝██╔════╝██║     ██║     ██╔════╝██╔══██╗██╔════╝
--    ██║   █████╗  ██║     ██║     █████╗  ██████╔╝███████╗
--    ██║   ██╔══╝  ██║     ██║     ██╔══╝  ██╔══██╗╚════██║
--    ██║   ███████╗███████╗███████╗███████╗██║  ██║███████║
--    ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝

local tellerZones = {}
local function collectCash()
    local ok, d = Rpc('collectCash')
    if not ok then ClientBridge.Notify(Config.UI.Title, d, 'error')
    elseif (d.amount or 0) > 0 then ClientBridge.Notify(Config.UI.Title, L('notify.cash_collected', 'You collected {amount}', { amount = Shared.Money(d.amount) }), 'success')
    else ClientBridge.Notify(Config.UI.Title, L('notify.no_cash', 'No cash payments to collect'), 'info') end
end

local function setupTellers()
    if not Config.Personal.CashRequiresCollection then return end
    for i, c in ipairs(Config.Payment.BankTellers or {}) do
        if ClientBridge.HasTarget() then
            tellerZones[#tellerZones + 1] = ClientBridge.AddSphereZone('billing_teller_' .. i, c, 1.5, {
                { name = 'billing_collect_' .. i, label = L('target.collect', 'Collect invoice cash'), icon = 'fa-solid fa-money-bill-wave', onSelect = collectCash },
            })
        else
            lib.points.new({
                coords = c, distance = 2.0,
                onEnter = function() lib.showTextUI(L('target.collect_key', '[E] Collect invoice cash')) end,
                onExit = function() lib.hideTextUI() end,
                nearby = function(p) if p.currentDistance < 1.6 and IsControlJustReleased(0, 38) then collectCash() end end,
            })
        end
    end
end

CreateThread(function()
    ClientBridge.Init()
    Wait(1500)
    sendInit()
    setupTellers()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if UI.open then SetNuiFocus(false, false) end
    for _, z in ipairs(tellerZones) do ClientBridge.RemoveZone(z) end
end)

-- ███████╗██╗  ██╗██████╗  ██████╗ ██████╗ ████████╗███████╗
-- ██╔════╝╚██╗██╔╝██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝
-- █████╗   ╚███╔╝ ██████╔╝██║   ██║██████╔╝   ██║   ███████╗
-- ██╔══╝   ██╔██╗ ██╔═══╝ ██║   ██║██╔══██╗   ██║   ╚════██║
-- ███████╗██╔╝ ██╗██║     ╚██████╔╝██║  ██║   ██║   ███████║
-- ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

exports('OpenBilling', OpenBilling)
exports('CloseBilling', CloseBilling)
exports('OpenCreate', function(recipientId) OpenBilling('received', { create = { recipientId = recipientId } }) end)
exports('OpenPayByReference', function(ref) OpenBilling('received', { payRef = ref or '' }) end)
exports('OpenInvoice', function(id) OpenBilling('received', { invoiceId = id }) end)
exports('IsOpen', function() return UI.open end)
