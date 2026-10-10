--[[
    NAYZEEE BILLING - Cash Registers (client)
    Register zones, employee POS, customer display.
]]

local Registers = {}   -- [id] = register
local Zones = {}       -- [id] = { target = handle } | { point = lib.point } + blip
local ActiveRegister = nil

local function IsEmployee(register)
    return ClientBridge.job ~= nil and Shared.TableContains(register.jobs, ClientBridge.job)
end

-- ██████╗  ██████╗ ███████╗
-- ██╔══██╗██╔═══██╗██╔════╝
-- ██████╔╝██║   ██║███████╗
-- ██╔═══╝ ██║   ██║╚════██║
-- ██║     ╚██████╔╝███████║
-- ╚═╝      ╚═════╝ ╚══════╝

local function OpenPos(register)
    if UI.open then return end
    local ok, data = Rpc('register:open', { registerId = register.id })
    if not ok then
        ClientBridge.Notify('Register', data, 'error')
        return
    end
    ActiveRegister = register.id
    UI.Focus('pos')
    UI.Send('posOpen', data)
end

local function ViewOrder(register)
    local ok, err = Rpc('display:view', { registerId = register.id })
    if not ok then ClientBridge.Notify('Register', err, 'info') end
end

RegisterNUICallback('posClose', function(_, cb)
    if ActiveRegister then
        Rpc('register:cancel', { registerId = ActiveRegister })
        ActiveRegister = nil
    end
    UI.Focus(nil)
    cb('ok')
end)

RegisterNetEvent('nayzeee-billing:client:posState', function(state)
    if UI.mode == 'pos' then
        UI.Send('posState', state)
    elseif state.status == 'paid' then
        ClientBridge.Notify('Register', ('%s paid %s'):format(state.customer or 'Customer', Shared.FormatCurrency(state.amount or 0)), 'success')
    end
end)

-- ██████╗ ██╗███████╗██████╗ ██╗      █████╗ ██╗   ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝
-- ██║  ██║██║███████╗██████╔╝██║     ███████║ ╚████╔╝
-- ██║  ██║██║╚════██║██╔═══╝ ██║     ██╔══██║  ╚██╔╝
-- ██████╔╝██║███████║██║     ███████╗██║  ██║   ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝

-- Customer display: passive (no focus) while the order is built, focused at checkout
RegisterNetEvent('nayzeee-billing:client:display', function(data)
    if data.action == 'open' then
        UI.display = true
        UI.Send('displayOpen', data)
    elseif data.action == 'update' then
        UI.Send('displayUpdate', data)
    elseif data.action == 'checkout' then
        UI.display = true
        if not UI.open or UI.mode ~= 'checkout' then
            if UI.open then UI.Send('close') end
            UI.Focus('checkout')
        end
        UI.Send('displayCheckout', data)
    elseif data.action == 'close' then
        UI.display = false
        if UI.mode == 'checkout' then UI.Focus(nil) end
        UI.Send('displayClose')
    end
end)

RegisterNUICallback('displayDecline', function(_, cb)
    Rpc('display:decline')
    UI.display = false
    if UI.mode == 'checkout' then UI.Focus(nil) end
    UI.Send('displayClose')
    cb('ok')
end)

RegisterNUICallback('displayDone', function(_, cb)
    UI.display = false
    if UI.mode == 'checkout' then UI.Focus(nil) end
    cb('ok')
end)

-- Dismiss the passive display
CreateThread(function()
    while true do
        if UI.display and not UI.open then
            if IsControlJustReleased(0, Config.CashRegister.DismissKey or 177) then
                Rpc('display:decline')
                UI.display = false
                UI.Send('displayClose')
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ███████╗ ██████╗ ███╗   ██╗███████╗███████╗
-- ╚══███╔╝██╔═══██╗████╗  ██║██╔════╝██╔════╝
--   ███╔╝ ██║   ██║██╔██╗ ██║█████╗  ███████╗
--  ███╔╝  ██║   ██║██║╚██╗██║██╔══╝  ╚════██║
-- ███████╗╚██████╔╝██║ ╚████║███████╗███████║
-- ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚══════╝

local function RemoveRegisterZone(id)
    local z = Zones[id]
    if not z then return end
    if z.target then ClientBridge.RemoveZone(z.target) end
    if z.point then z.point:remove() end
    if z.blip then RemoveBlip(z.blip) end
    Zones[id] = nil
end

local function CreateRegisterZone(register)
    local coords = vector3(register.coords.x, register.coords.y, register.coords.z)
    local cfg = Config.CashRegister
    local zone = {}

    if cfg.InteractionMethod == 'target' and ClientBridge.HasTarget() then
        zone.target = ClientBridge.AddSphereZone('billing_register_' .. register.id, coords, register.radius, {
            {
                name = 'register_employee_' .. register.id,
                icon = cfg.Target.EmployeeIcon, label = cfg.Target.EmployeeLabel,
                canInteract = function() return IsEmployee(register) end,
                onSelect = function() OpenPos(register) end,
            },
            {
                name = 'register_customer_' .. register.id,
                icon = cfg.Target.CustomerIcon, label = cfg.Target.CustomerLabel,
                canInteract = function() return not IsEmployee(register) end,
                onSelect = function() ViewOrder(register) end,
            },
        }, cfg.Debug)
    else
        zone.point = lib.points.new({
            coords = coords,
            distance = register.radius,
            onEnter = function()
                lib.showTextUI(IsEmployee(register) and cfg.TextUI.EmployeeText or cfg.TextUI.CustomerText)
            end,
            onExit = function() lib.hideTextUI() end,
            nearby = function()
                if not UI.open and IsControlJustReleased(0, cfg.TextUI.Key or 38) then
                    if IsEmployee(register) then OpenPos(register) else ViewOrder(register) end
                end
            end,
        })
    end

    if cfg.Blip and cfg.Blip.Enabled then
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, cfg.Blip.Sprite or 52)
        SetBlipColour(blip, cfg.Blip.Color or 2)
        SetBlipScale(blip, cfg.Blip.Scale or 0.6)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(register.label or 'Cash Register')
        EndTextCommandSetBlipName(blip)
        zone.blip = blip
    end

    Zones[register.id] = zone
end

local function SyncRegisters(list)
    if not Config.CashRegister.Enabled then return end
    local incoming = {}
    for _, r in ipairs(list or {}) do incoming[r.id] = r end

    for id in pairs(Zones) do
        local old, new = Registers[id], incoming[id]
        if not new or json.encode(old) ~= json.encode(new) then RemoveRegisterZone(id) end
    end
    Registers = incoming
    for id, r in pairs(Registers) do
        if not Zones[id] then CreateRegisterZone(r) end
    end
    Shared.Debug('Registers synced:', Shared.Count(Registers))
end

RegisterNetEvent('nayzeee-billing:client:registers', SyncRegisters)

AddEventHandler('nayzeee-billing:client:playerReady', function()
    local ok, list = Rpc('getRegisters')
    if ok then SyncRegisters(list) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(Zones) do RemoveRegisterZone(id) end
end)
