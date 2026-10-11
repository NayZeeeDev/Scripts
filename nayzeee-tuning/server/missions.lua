--------------------------------------------------------------------- roadside callouts

local Callouts, seq = {}, 0

local TW = Config.Towing

local function newCallout(shopId)
    local m = Config.Missions
    seq = seq + 1
    local loc = m.Locations[math.random(1, #m.Locations)]
    Callouts[shopId] = Callouts[shopId] or {}
    if TW.Enabled and math.random(1, 100) <= TW.Chance then
        Callouts[shopId][seq] = {
            id = seq, kind = 'tow', coords = loc, fault = 'wreck', faultLabel = L('tow_label'), icon = 'fa-truck-ramp-box',
            vehicle = TW.Wrecks[math.random(1, #TW.Wrecks)], ped = m.Peds[math.random(1, #m.Peds)],
            reward = math.random(TW.Reward[1], TW.Reward[2]), created = os.time(),
        }
        return
    end
    local fault = m.Faults[math.random(1, #m.Faults)]
    Callouts[shopId][seq] = {
        id = seq, kind = 'fix', coords = loc, fault = fault.id, faultLabel = fault.label, icon = fault.icon,
        vehicle = m.Vehicles[math.random(1, #m.Vehicles)], ped = m.Peds[math.random(1, #m.Peds)],
        reward = math.random(m.Reward[1], m.Reward[2]), created = os.time(),
    }
end

-- where tow jobs and supply runs end: shop.drop, else the shop centre
function Missions_DropOf(shopId)
    local s = Config.Shops[shopId]
    return s and (s.drop or s.center)
end

if Config.Missions.Enabled then
    CreateThread(function()
        while not Core.Ready do Wait(500) end
        for id, shop in pairs(Config.Shops) do
            if shop.job then
                for _ = 1, 2 do newCallout(id) end
            end
        end
        while true do
            Wait(Config.Missions.Refresh * 60000)
            for id, shop in pairs(Config.Shops) do      -- includes shops added with the editor
                if shop.job and NZ.Count(Callouts[id] or {}) < Config.Missions.MaxActive then newCallout(id) end
            end
        end
    end)
end

local function public(c, src)
    return { id = c.id, kind = c.kind, fault = c.faultLabel, icon = c.icon, reward = c.reward, taken = c.taken ~= nil,
        mine = c.taken == src, takenBy = c.takenName, x = c.coords.x, y = c.coords.y, age = os.time() - c.created }
end

lib.callback.register('nayzeee-tuning:callouts', function(src, shopId)
    if not Callouts[shopId] or not Core.IsEmployee(src, shopId) then return {} end
    local out = {}
    for _, c in pairs(Callouts[shopId]) do out[#out + 1] = public(c, src) end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end)

local function findTaken(src)
    for shopId, list in pairs(Callouts) do
        for _, c in pairs(list) do if c.taken == src then return c, shopId end end
    end
end

lib.callback.register('nayzeee-tuning:takeCallout', function(src, shopId, id)
    local list = Callouts[shopId]
    local c = list and list[tonumber(id)]
    if not c or not Core.IsEmployee(src, shopId) then return false, L('no_permission') end
    if c.taken and c.taken ~= src then return false, L('callout_taken') end
    if findTaken(src) and not c.taken then return false, L('callout_busy') end
    c.taken, c.takenName = src, Bridge.GetName(src)
    local shop = Config.Shops[shopId]
    return true, { id = c.id, kind = c.kind, coords = { x = c.coords.x, y = c.coords.y, z = c.coords.z, w = c.coords.w },
        fault = c.fault, faultLabel = c.faultLabel, vehicle = c.vehicle, ped = c.ped, reward = c.reward,
        drop = NZ.Plain(Missions_DropOf(shopId)), truckSpawn = NZ.Plain(shop.truckSpawn), shop = shopId }
end)

lib.callback.register('nayzeee-tuning:finishCallout', function(src, id)
    local c, shopId = findTaken(src)
    if not c or c.id ~= tonumber(id) or c.kind == 'tow' then return false end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - c.coords.xyz) > 30.0 then return false, L('too_far') end
    Callouts[shopId][c.id] = nil
    local shopCut = math.floor(c.reward * Config.Missions.ShopCut / 100)
    Bridge.AddMoney(src, 'bank', c.reward - shopCut, 'Roadside callout')
    Core.ShopAdd(shopId, shopCut, 'callout', Bridge.GetName(src), c.faultLabel)
    Core.AddStats(shopId, c.reward, 1)
    Core.AddMechanicStats(src, shopId, 1, c.reward - shopCut)
    return true, { paid = c.reward - shopCut }
end)

-- tow job delivered: the wreck has to be at the shop's drop point
lib.callback.register('nayzeee-tuning:finishTow', function(src, id, netId)
    local c, shopId = findTaken(src)
    if not c or c.id ~= tonumber(id) or c.kind ~= 'tow' then return false end
    local drop = Missions_DropOf(shopId)
    local wreck = Core.VehicleFromNet(netId)
    if not drop or not wreck then return false, L('tow_no_wreck') end
    if #(GetEntityCoords(GetPlayerPed(src)) - drop) > TW.DropRadius + 10.0 or #(GetEntityCoords(wreck) - drop) > TW.DropRadius + 6.0 then
        return false, L('tow_not_at_drop')
    end
    Callouts[shopId][c.id] = nil
    local shopCut = math.floor(c.reward * TW.ShopCut / 100)
    Bridge.AddMoney(src, 'bank', c.reward - shopCut, 'Tow job')
    Core.ShopAdd(shopId, shopCut, 'tow', Bridge.GetName(src), ('Recovered %s'):format(c.vehicle))
    Core.AddStats(shopId, c.reward, 1)
    Core.AddMechanicStats(src, shopId, 1, c.reward - shopCut)
    Core.Log('order', 'Tow job delivered', { Shop = Config.Shops[shopId].label, Paid = '$' .. (c.reward - shopCut) }, src)
    SetTimeout(TW.WreckDespawn * 1000, function() if DoesEntityExist(wreck) then DeleteEntity(wreck) end end)
    return true, { paid = c.reward - shopCut }
end)

-- work trucks (tow jobs / supply runs) get keys like any car you own
lib.callback.register('nayzeee-tuning:workTruck', function(src, netId)
    local veh = Core.VehicleFromNet(netId)
    if not veh or not Shops_IsAnyEmployee(src) then return false end
    Bridge.GiveKeys(src, NZ.TrimPlate(GetVehicleNumberPlateText(veh)), netId)
    return true
end)

lib.callback.register('nayzeee-tuning:abandonCallout', function(src)
    local c = findTaken(src)
    if c then c.taken, c.takenName = nil, nil end
    return true
end)

AddEventHandler('playerDropped', function()
    local c = findTaken(source)
    if c then c.taken, c.takenName = nil, nil end
end)

--------------------------------------------------------------------- scrapyard

local Scrapping = {}   -- [netId] = { src, done = {}, last = 0 }

local function inYard(src)
    local z = Config.Scrapyard.Zone
    return #(GetEntityCoords(GetPlayerPed(src)) - z.coords) <= z.radius + 5.0
end

lib.callback.register('nayzeee-tuning:scrapStart', function(src, netId)
    local cfg = Config.Scrapyard
    if not cfg.Enabled or not inYard(src) then return false, L('not_in_yard') end
    if cfg.BlockedJobs[Bridge.GetJob(src).name] then return false, L('no_permission') end
    if cfg.MinPolice > 0 and Bridge.CountJobs(Config.Police.Jobs) < cfg.MinPolice then return false, L('need_police') end
    local veh = Core.VehicleFromNet(netId)
    if not veh then return false, L('no_vehicle') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    if Bridge.GetVehicleOwner(plate) then return false, L('scrap_owned') end
    local s = Scrapping[netId]
    if s and s.src ~= src and GetPlayerName(s.src) then return false, L('scrap_busy') end
    Scrapping[netId] = s and s.src == src and s or { src = src, done = {}, last = 0 }
    return true, Scrapping[netId].done
end)

lib.callback.register('nayzeee-tuning:scrapPart', function(src, netId, index)
    local s = Scrapping[netId]
    local part = Config.Scrapyard.Parts[tonumber(index) or -1]
    if not s or s.src ~= src or not part or s.done[index] then return false end
    local now = GetGameTimer()
    if now - s.last < part.time - 500 then return false end
    local veh = Core.VehicleFromNet(netId)
    if not veh or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 6.0 then return false, L('too_far') end
    if part.last then
        for i, p in ipairs(Config.Scrapyard.Parts) do
            if not p.last and not s.done[i] then return false, L('scrap_order') end
        end
    end
    s.done[index], s.last = true, now
    local amount = math.random(part.give[1], part.give[2])
    Bridge.AddItem(src, Config.Economy.Components.Item, amount)
    if part.last then
        Scrapping[netId] = nil
        SetTimeout(1500, function() if DoesEntityExist(veh) then DeleteEntity(veh) end end)
    end
    return true, { amount = amount, finished = part.last == true }
end)
