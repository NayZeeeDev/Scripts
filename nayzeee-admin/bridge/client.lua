-- Client integrations. Everything that touches another resource on the client lives here.
Bridge = {}

local function started(r) return GetResourceState(r) == 'started' end

local function pick(setting, list)
    if setting ~= 'auto' then return setting end
    for _, r in ipairs(list) do if started(r) then return r end end
    return 'none'
end

-- ─── notify ─────────────────────────────────────────────────────────────
function Bridge.Notify(msg, kind, title, duration)
    kind = kind or 'info'
    local mode = pick(Config.Integrations.Notify, { 'nayzeee-notify', 'ox_lib' })
    if mode == 'nayzeee-notify' then
        exports['nayzeee-notify']:Notify({ title = title, message = msg, type = kind, duration = duration })
    elseif mode == 'esx' then
        TriggerEvent('esx:showNotification', msg, kind, duration)
    elseif mode == 'qb' then
        TriggerEvent('QBCore:Notify', msg, kind == 'info' and 'primary' or kind, duration)
    else
        lib.notify({ title = title, description = msg, type = kind == 'info' and 'inform' or kind, duration = duration })
    end
end

-- ─── keys ───────────────────────────────────────────────────────────────
function Bridge.GiveKeys(veh, plate)
    plate = plate or GetVehicleNumberPlateText(veh)
    local mode = pick(Config.Integrations.Keys, { 'wasabi_carlock', 'qbx_vehiclekeys', 'qb-vehiclekeys', 'MrNewbVehicleKeys' })
    if mode == 'wasabi_carlock' then exports.wasabi_carlock:GiveKey(plate)
    elseif mode == 'qbx_vehiclekeys' then TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
    elseif mode == 'qb-vehiclekeys' then TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif mode == 'MrNewbVehicleKeys' then exports.MrNewbVehicleKeys:GiveKeys(veh) end
end

-- ─── fuel ───────────────────────────────────────────────────────────────
function Bridge.SetFuel(veh, amount)
    local mode = pick(Config.Integrations.Fuel, { 'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'ps-fuel' })
    if mode == 'ox_fuel' then Entity(veh).state.fuel = amount
    elseif mode == 'LegacyFuel' or mode == 'cdn-fuel' or mode == 'ps-fuel' then exports[mode]:SetFuel(veh, amount) end
    SetVehicleFuelLevel(veh, amount + 0.0)
end

-- ─── clothing ───────────────────────────────────────────────────────────
local function clothingRes() return pick(Config.Integrations.Clothing, { 'illenium-appearance', 'fivem-appearance', 'qb-clothing', 'esx_skin' }) end

function Bridge.OpenClothing()
    local mode = clothingRes()
    if mode == 'illenium-appearance' or mode == 'fivem-appearance' then
        local cfg = { ped = true, headBlend = true, faceFeatures = true, headOverlays = true, components = true, props = true, tattoos = true }
        exports[mode]:startPlayerCustomization(function(appearance)
            if appearance then TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance) end
        end, cfg)
    elseif mode == 'qb-clothing' then TriggerEvent('qb-clothing:client:openMenu')
    elseif mode == 'esx_skin' then TriggerEvent('esx_skin:openSaveableMenu') end
end

function Bridge.GetAppearance()
    local mode = clothingRes()
    if mode == 'illenium-appearance' or mode == 'fivem-appearance' then
        return exports[mode]:getPedAppearance(cache.ped)
    end
end

function Bridge.SetAppearance(data)
    local mode = clothingRes()
    if mode == 'illenium-appearance' or mode == 'fivem-appearance' then
        exports[mode]:setPlayerAppearance(data)
        return true
    end
end

--- Put the player's saved character look back (after a ped change or staff outfit).
function Bridge.ReloadSkin()
    local mode = clothingRes()
    if mode == 'illenium-appearance' then TriggerEvent('illenium-appearance:client:reloadSkin')
    elseif mode == 'qb-clothing' then TriggerServerEvent('qb-clothes:loadPlayerSkin')
    elseif mode == 'esx_skin' then
        TriggerEvent('skinchanger:loadDefaultModel', true)
        local ok, ESX = pcall(function() return exports.es_extended:getSharedObject() end)
        if ok and ESX then ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin) TriggerEvent('skinchanger:loadSkin', skin) end) end
    end
end
