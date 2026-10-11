--[[
    Tuning tablet. One per player: their own accent + wallpaper, their own work and cars.
    Apps depend on job and rank (server decides, see server/tablet.lua). The workshop apps
    reuse the business callbacks, so the tablet IS the boss menu for owners.
]]

Tablet = { open = false }

local T = Config.Tablet
local prop, shopId, holding = nil, nil, false

--------------------------------------------------------------------- holding the tablet

local function hold()
    if holding then return end
    holding = true
    CreateThread(function()
        local dict, clip = T.Anim[1], T.Anim[2]
        lib.requestAnimDict(dict)
        lib.requestModel(T.Prop)
        prop = CreateObject(joaat(T.Prop), GetEntityCoords(cache.ped), true, true, false)
        AttachEntityToEntity(prop, cache.ped, GetPedBoneIndex(cache.ped, 28422), 0.0, -0.03, 0.0, 20.0, -90.0, 0.0, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(joaat(T.Prop))
        while holding do
            if not IsEntityPlayingAnim(cache.ped, dict, clip, 3) and not cache.vehicle then
                TaskPlayAnim(cache.ped, dict, clip, 3.0, 3.0, -1, 49, 0, false, false, false)
            end
            Wait(500)
        end
        StopAnimTask(cache.ped, dict, clip, 1.0)
        RemoveAnimDict(dict)
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end)
end

local function unhold() holding = false end

--------------------------------------------------------------------- nearby car (diagnostics / ECU)

local function nearbyCar()
    local veh = cache.vehicle or VehUtil.Closest(5.0)
    if not veh or veh == 0 then return nil, nil end
    local label, make = VehUtil.Label(veh)
    return veh, { netId = VehToNet(veh), plate = VehUtil.Plate(veh), label = (make ~= '' and make .. ' ' or '') .. label,
        class = GetVehicleClass(veh), driver = cache.vehicle == veh and cache.seat == -1 }
end

local function estHp(veh)
    local acc = GetVehicleModelAcceleration(GetEntityModel(veh)) * (1 + 0.055 * (GetVehicleMod(veh, 11) + 1))
    return math.floor(acc * GetVehicleHandlingFloat(veh, 'CHandlingData', 'fMass') * 0.9)
end

local function modelLabel(model)
    local hash = tonumber(model) or joaat(tostring(model or ''))
    local name = GetDisplayNameFromVehicleModel(hash)
    if not name or name == 'CARNOTFOUND' then return tostring(model or '?') end
    local lbl = GetLabelText(name)
    return lbl ~= 'NULL' and lbl or name
end

--------------------------------------------------------------------- open / close

function Tablet.Open(opts)
    opts = opts or {}
    if Tablet.open or Menu.open or Install.Active() then return end
    if IsPedRagdoll(cache.ped) or IsEntityDead(cache.ped) then return end
    local ok, d = lib.callback.await('nayzeee-tuning:tablet:open', false, opts.viaItem == true)
    if not ok then return Notify(d or L('no_permission'), 'error') end
    shopId = d.shop and d.shop.id or nil
    if shopId then
        local okB, biz = lib.callback.await('nayzeee-tuning:business', false, shopId)
        if okB then d.biz = biz end
    end
    local _, car = nearbyCar()
    d.car = car
    Tablet.open = true
    hold()
    UI.Send('tablet:open', { data = d, app = opts.app })
    UI.Focus(true)
end

function Tablet.Close()
    if not Tablet.open then return end
    Tablet.open = false
    unhold()
    UI.Send('tablet:close')
    UI.Focus(false)
end

UI.On('tab:close', function() Tablet.Close() return true end)

RegisterNetEvent('nayzeee-tuning:useTablet', function() Tablet.Open({ viaItem = true }) end)

if T.Enabled and T.Command then
    RegisterCommand(T.Command, function() Tablet.Open({}) end, false)
end

RegisterNetEvent('nayzeee-tuning:avatar', function(url)
    if Tablet.open then UI.Send('tablet:avatar', { url = url }) end
end)

RegisterNetEvent('nayzeee-tuning:message', function(m)
    UI.Send('sound', { name = 'ping', volume = 0.35 })
    if Tablet.open then UI.Send('tablet:message', m)
    else Notify(L('new_message', m.order, m.from), 'inform') end
end)

--------------------------------------------------------------------- personal apps

local function cb(name, ...) return lib.callback.await('nayzeee-tuning:' .. name, false, ...) end
local function wrap(ok, res) return { ok = ok == true, data = ok and res or nil, error = not ok and res or nil } end

UI.On('tab:settings', function(d) return wrap(cb('tablet:settings', d.accent, d.wallpaper)) end)

UI.On('tab:myWork', function() return cb('tablet:myWork') end)

UI.On('tab:myCars', function()
    local list = cb('tablet:myCars') or {}
    for _, c in ipairs(list) do c.label = modelLabel(c.model) end
    return list
end)

UI.On('tab:myOrders', function() return cb('myOrders') or {} end)
UI.On('tab:cancelOrder', function(d) return wrap(cb('orderCancel', d.id)) end)

UI.On('tab:threads', function() return cb('tablet:threads') or {} end)
UI.On('tab:messages', function(d) return wrap(cb('tablet:messages', d.id)) end)
UI.On('tab:send', function(d) return wrap(cb('tablet:send', d.id, d.body)) end)

UI.On('tab:supplier', function() return wrap(cb('tablet:supplier')) end)

-- supply storage
UI.On('tab:storage', function() return wrap(cb('stock:list')) end)
UI.On('tab:storageTake', function(d) return wrap(cb('stock:take', d.item, d.qty)) end)
UI.On('tab:storagePut', function(d) return wrap(cb('stock:put', d.item, d.qty)) end)
UI.On('tab:storageRoute', function()
    if not shopId then return false end
    local at = NZ.StorageOf(shopId)
    if at then SetNewWaypoint(at.x, at.y) end
    return at ~= nil
end)
RegisterNetEvent('nayzeee-tuning:stockChanged', function()
    if Tablet.open then UI.Send('tablet:refresh', { app = 'storage' }) end
end)

-- bays
UI.On('tab:bays', function() return wrap(cb('bays')) end)
UI.On('tab:bayClaim', function(d) return wrap(cb('bayClaim', d.bay)) end)
UI.On('tab:bayRelease', function(d) return wrap(cb('bayRelease', d.bay)) end)
UI.On('tab:bayRoute', function(d)
    local shop = shopId and Config.Shops[shopId]
    local b = shop and shop.bays and shop.bays[tonumber(d.bay) or 0]
    if b then SetNewWaypoint(b.x, b.y) end
    return b ~= nil
end)
UI.On('tab:buy', function(d) return wrap(cb('tablet:buy', d.cart)) end)

-- supply run: pay less, fetch it yourself with a box truck
UI.On('tab:supplyRun', function(d)
    if Supply.active then return { ok = false, error = L('supply_busy') } end
    local ok, res = cb('supply:start', d.cart)
    if not ok then return { ok = false, error = res } end
    Tablet.Close()
    SetTimeout(250, function() Supply.Start(res) end)
    return { ok = true }
end)

UI.On('tab:locate', function(d) return Locator.Ping(d.plate, d.route) end)

UI.On('tab:assist', function(d)
    if not Driving.Vehicle() then return { ok = false, error = L('must_drive') } end
    Driving.ToggleAssist(d.which == 'esc' and 'esc' or 'tcs')
    return { ok = true }
end)

--------------------------------------------------------------------- car apps (diagnostics, ECU)

UI.On('tab:car', function()
    local _, car = nearbyCar()
    return car or false
end)

UI.On('tab:scan', function()
    local veh = nearbyCar()
    if not veh then return { ok = false, error = L('no_vehicle') } end
    return wrap(Diagnostics.Build(veh))
end)

UI.On('tab:ecuRead', function()
    local veh, car = nearbyCar()
    if not veh then return { ok = false, error = L('no_vehicle') } end
    local ok, res = cb('tablet:ecuRead', car.netId)
    if not ok then return { ok = false, error = res } end
    res.label, res.hp = car.label, estHp(veh)
    res.params = res.params or {}
    res.rpm = GetVehicleCurrentRpm(veh)
    return { ok = true, data = res }
end)

UI.On('tab:ecuFlash', function(d)
    local veh, car = nearbyCar()
    if not veh then return { ok = false, error = L('no_vehicle') } end
    local cells = d.stock and false or d.cells
    local params = d.stock and false or d.params
    return wrap(cb('tablet:ecuFlash', car.netId, cells, d.fuel, params))
end)

UI.On('tab:rev', function()
    local veh = nearbyCar()
    if not veh or cache.vehicle ~= veh or cache.seat ~= -1 then return false end
    CreateThread(function()
        SetVehicleEngineOn(veh, true, true, false)
        local stop = GetGameTimer() + 1400
        while GetGameTimer() < stop and Tablet.open do SetControlNormal(0, 71, 1.0) Wait(0) end
    end)
    return true
end)

--------------------------------------------------------------------- workshop apps (business callbacks)

UI.On('biz:refresh', function()
    if not shopId then return false end
    local ok, data = cb('business', shopId)
    return ok and data or false
end)

-- NUI name -> { server callback, argument keys }
local passthrough = {
    ['biz:orders']        = { 'orders', {} },
    ['biz:orderAccept']   = { 'orderAccept', { 'id' } },
    ['biz:orderRelease']  = { 'orderRelease', { 'id' } },
    ['biz:orderCancel']   = { 'orderCancel', { 'id' } },
    ['biz:announce']      = { 'announce', { 'message' } },
    ['biz:delAnnounce']   = { 'deleteAnnouncement', { 'id' } },
    ['biz:nearby']        = { 'nearbyPlayers', {} },
    ['biz:hire']          = { 'hire', { 'target' } },
    ['biz:fire']          = { 'fire', { 'identifier' } },
    ['biz:grade']         = { 'setGrade', { 'identifier', 'grade' } },
    ['biz:bonus']         = { 'bonus', { 'identifier', 'amount' } },
    ['biz:withdraw']      = { 'withdraw', { 'amount' } },
    ['biz:deposit']       = { 'deposit', { 'amount' } },
    ['biz:rates']         = { 'setRates', { 'margin', 'commission', 'labour' } },
    ['biz:createCode']    = { 'createCode', { 'percent', 'uses' } },
    ['biz:deleteCode']    = { 'deleteCode', { 'code' } },
    ['biz:buyUpgrade']    = { 'buyUpgrade', { 'key' } },
    ['biz:callouts']      = { 'callouts', {} },
}
local noShop = { orderRelease = true, orderCancel = true, orderAccept = true }

for nui, def in pairs(passthrough) do
    UI.On(nui, function(d)
        if not shopId then return { ok = false, error = L('no_permission') } end
        local args = {}
        if not noShop[def[1]] then args[1] = shopId end
        for _, k in ipairs(def[2]) do args[#args + 1] = d[k] end
        local ok, res = cb(def[1], table.unpack(args))
        if type(ok) == 'table' then return ok end   -- list results
        return { ok = ok == true, data = res, error = ok ~= true and res or nil }
    end)
end

UI.On('biz:startOrder', function(d)
    Tablet.Close()
    Wait(250)
    Install.Begin(d.id)
    return true
end)

UI.On('biz:takeCallout', function(d)
    local ok, res = cb('takeCallout', shopId, d.id)
    if not ok then return { ok = false, error = res } end
    Tablet.Close()
    Missions.Start(res)
    return { ok = true }
end)

UI.On('biz:waypoint', function(d)
    if d.x and d.y then SetNewWaypoint(d.x + 0.0, d.y + 0.0) end
    return true
end)

-- (new orders refresh the open board through the orderEvent handler in client/install.lua)

-- getting hurt or entering water puts the tablet away
CreateThread(function()
    while true do
        if Tablet.open and (IsPedRagdoll(cache.ped) or IsEntityDead(cache.ped) or IsPedSwimming(cache.ped)) then Tablet.Close() end
        Wait(Tablet.open and 400 or 1500)
    end
end)
