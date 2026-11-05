--[[
    NAYZEEE BILLING - Cash registers (client)
]]

local Registers, Zones = {}, {}
local ActiveRegister = nil

local function isEmployee(r) return ClientBridge.job ~= nil and Shared.Contains(r.jobs, ClientBridge.job) end

-- ██████╗  ██████╗ ███████╗
-- ██╔══██╗██╔═══██╗██╔════╝
-- ██████╔╝██║   ██║███████╗
-- ██╔═══╝ ██║   ██║╚════██║
-- ██║     ╚██████╔╝███████║
-- ╚═╝      ╚═════╝ ╚══════╝

local function openPos(r)
    if UI.open then return end
    local ok, data = Rpc('register:open', { registerId = r.id })
    if not ok then ClientBridge.Notify(Config.UI.Title, data, 'error') return end
    ActiveRegister = r.id
    UI.Focus('pos')
    UI.Send('posOpen', data)
end

local function viewOrder(r)
    local ok, err = Rpc('display:view', { registerId = r.id })
    if not ok then ClientBridge.Notify(Config.UI.Title, err, 'info') end
end

RegisterNUICallback('posClose', function(_, cb)
    if ActiveRegister then Rpc('register:cancel', { registerId = ActiveRegister }) ActiveRegister = nil end
    UI.Focus(nil)
    cb('ok')
end)

RegisterNetEvent('nayzeee-billing:client:posState', function(state)
    if UI.mode == 'pos' then UI.Send('posState', state)
    elseif state.status == 'paid' then
        ClientBridge.Notify(Config.UI.Title, L('notify.paid_body', '{name} paid {amount} · {ref}', { name = state.customer or '', amount = Shared.Money(state.amount or 0), ref = '' }), 'success')
    end
end)

-- ██████╗ ██╗███████╗██████╗ ██╗      █████╗ ██╗   ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝
-- ██║  ██║██║███████╗██████╔╝██║     ███████║ ╚████╔╝
-- ██║  ██║██║╚════██║██╔═══╝ ██║     ██╔══██║  ╚██╔╝
-- ██████╔╝██║███████║██║     ███████╗██║  ██║   ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝

RegisterNetEvent('nayzeee-billing:client:display', function(d)
    if d.action == 'open' then
        UI.display = true
        UI.Send('displayOpen', d)
    elseif d.action == 'update' then
        UI.Send('displayUpdate', d)
    elseif d.action == 'checkout' then
        UI.display = true
        if UI.mode == 'pos' and ActiveRegister then
            -- Our own register session can't stay open behind the checkout
            Rpc('register:cancel', { registerId = ActiveRegister })
            ActiveRegister = nil
        end
        if UI.mode ~= 'checkout' then
            if UI.open then UI.Send('close') end
            UI.Focus('checkout')
        end
        UI.Send('displayCheckout', d)
    elseif d.action == 'close' then
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
    if UI.mode == 'checkout' or UI.mode == 'paper' then UI.Focus(nil) end
    cb('ok')
end)

RegisterCommand('billing_leave_counter', function()
    if UI.display and not UI.open then
        Rpc('display:decline')
        UI.display = false
        UI.Send('displayClose')
    end
end, false)
RegisterKeyMapping('billing_leave_counter', 'Billing: leave the register counter', 'keyboard', Config.Registers.LeaveKey or 'BACK')

-- ███████╗ ██████╗ ███╗   ██╗███████╗███████╗
-- ╚══███╔╝██╔═══██╗████╗  ██║██╔════╝██╔════╝
--   ███╔╝ ██║   ██║██╔██╗ ██║█████╗  ███████╗
--  ███╔╝  ██║   ██║██║╚██╗██║██╔══╝  ╚════██║
-- ███████╗╚██████╔╝██║ ╚████║███████╗███████║
-- ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚══════╝

-- Till props for registers placed with "Spawn prop": local objects, created only when a player is near
local function spawnProp(r, zone)
    local model = joaat(r.model)
    if not IsModelInCdimage(model) then return end
    zone.propPoint = lib.points.new({
        coords = vector3(r.coords.x, r.coords.y, r.coords.z), distance = Config.Registers.Placement.PropDistance or 60.0,
        onEnter = function()
            if zone.prop and DoesEntityExist(zone.prop) then return end
            RequestModel(model)
            local timeout = GetGameTimer() + 8000
            while not HasModelLoaded(model) do
                if GetGameTimer() > timeout then print(('^1[NAYZEEE-BILLING]^7 Register prop %s failed to load'):format(r.model)) return end
                Wait(10)
            end
            if zone.prop and DoesEntityExist(zone.prop) then return end
            local obj = CreateObject(model, r.coords.x, r.coords.y, r.coords.z, false, false, false)
            SetEntityCoordsNoOffset(obj, r.coords.x, r.coords.y, r.coords.z, false, false, false)
            SetEntityHeading(obj, (r.heading or 0.0) + 0.0)
            FreezeEntityPosition(obj, true)
            SetEntityInvincible(obj, true)
            SetModelAsNoLongerNeeded(model)
            zone.prop = obj
        end,
        onExit = function()
            if zone.prop and DoesEntityExist(zone.prop) then DeleteEntity(zone.prop) end
            zone.prop = nil
        end,
    })
end

local function removeZone(id)
    local z = Zones[id]
    if not z then return end
    if z.target then ClientBridge.RemoveZone(z.target) end
    if z.point then z.point:remove() end
    if z.propPoint then z.propPoint:remove() end
    if z.prop and DoesEntityExist(z.prop) then DeleteEntity(z.prop) end
    if z.blip then RemoveBlip(z.blip) end
    Zones[id] = nil
end

local function createZone(r)
    local coords = vector3(r.coords.x, r.coords.y, r.coords.z)
    local cfg = Config.Registers
    local zone = {}
    if r.model then spawnProp(r, zone) end
    if cfg.InteractionMethod == 'target' and ClientBridge.HasTarget() then
        zone.target = ClientBridge.AddSphereZone('billing_register_' .. r.id, coords, r.radius, {
            { name = 'register_employee_' .. r.id, icon = cfg.Target.EmployeeIcon, label = cfg.Target.EmployeeLabel,
              canInteract = function() return isEmployee(r) end, onSelect = function() openPos(r) end },
            { name = 'register_customer_' .. r.id, icon = cfg.Target.CustomerIcon, label = cfg.Target.CustomerLabel,
              canInteract = function() return not isEmployee(r) end, onSelect = function() viewOrder(r) end },
        }, cfg.Debug)
    else
        zone.point = lib.points.new({
            coords = coords, distance = r.radius,
            onEnter = function() lib.showTextUI(isEmployee(r) and cfg.TextUI.EmployeeText or cfg.TextUI.CustomerText) end,
            onExit = function() lib.hideTextUI() end,
            nearby = function()
                if not UI.open and IsControlJustReleased(0, cfg.TextUI.Key or 38) then
                    if isEmployee(r) then openPos(r) else viewOrder(r) end
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
        AddTextComponentSubstringPlayerName(r.label or 'Register')
        EndTextCommandSetBlipName(blip)
        zone.blip = blip
    end
    Zones[r.id] = zone
end

local function sync(list)
    if not Config.Registers.Enabled then return end
    local incoming = {}
    for _, r in ipairs(list or {}) do incoming[r.id] = r end
    for id in pairs(Zones) do
        if not incoming[id] or json.encode(Registers[id]) ~= json.encode(incoming[id]) then removeZone(id) end
    end
    Registers = incoming
    for id, r in pairs(Registers) do if not Zones[id] then createZone(r) end end
end

RegisterNetEvent('nayzeee-billing:client:registers', sync)
AddEventHandler('nayzeee-billing:client:playerReady', function()
    local ok, list = Rpc('getRegisters')
    if ok then sync(list) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Zones) do removeZone(id) end
end)
