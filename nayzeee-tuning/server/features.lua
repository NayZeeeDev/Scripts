--------------------------------------------------------------------- saved builds

local function newBuildCode()
    for _ = 1, 10 do
        local code = ('%s-%s'):format(Config.Builds.CodePrefix, Business.RandomCode(6))
        if not MySQL.scalar.await('SELECT 1 FROM nz_tuning_builds WHERE code = ?', { code }) then return code end
    end
end

lib.callback.register('nayzeee-tuning:saveBuild', function(src, name, model, items)
    if not Config.Builds.Enabled or not Core.Throttle(src, 'build', 3000) then return false, L('slow_down') end
    if type(name) ~= 'string' or #name < 1 or type(items) ~= 'table' or #items == 0 or #items > 80 then return false, L('build_invalid') end
    name = name:gsub('[<>]', ''):sub(1, 32)
    local clean = {}
    for _, it in ipairs(items) do
        local kind = type(it) == 'table' and Config.Parts[it.id] and Config.Parts[it.id].kind
        local skip = { plateText = true, repair = true, clean = true, service = true }
        if kind and not skip[kind] and NZ.Validate(it.id, it.value) then
            clean[#clean + 1] = { id = it.id, value = it.value }
        end
    end
    if #clean == 0 then return false, L('build_invalid') end
    local id = Bridge.GetIdentifier(src)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_tuning_builds WHERE owner = ?', { id }) or 0
    if count >= Config.Builds.MaxPerPlayer then return false, L('build_limit', Config.Builds.MaxPerPlayer) end
    local code = newBuildCode()
    MySQL.insert.await('INSERT INTO nz_tuning_builds (code, owner, owner_name, name, model, items) VALUES (?, ?, ?, ?, ?, ?)',
        { code, id, Bridge.GetName(src), name, tostring(model or ''), json.encode(clean) })
    return true, code
end)

lib.callback.register('nayzeee-tuning:myBuilds', function(src)
    local rows = MySQL.query.await('SELECT code, name, model, items, uses, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_builds WHERE owner = ? ORDER BY created_at DESC', { Bridge.GetIdentifier(src) }) or {}
    for _, r in ipairs(rows) do r.count = #DB.Decode(r.items, {}) r.items = nil end
    return rows
end)

lib.callback.register('nayzeee-tuning:getBuild', function(src, code)
    if type(code) ~= 'string' or not Core.Throttle(src, 'getbuild', 1000) then return false end
    code = code:upper():gsub('%s', '')
    local row = MySQL.single.await('SELECT code, name, model, items, owner_name FROM nz_tuning_builds WHERE code = ?', { code })
    if not row then return false, L('build_not_found') end
    MySQL.update('UPDATE nz_tuning_builds SET uses = uses + 1 WHERE code = ?', { code })
    return true, { code = row.code, name = row.name, model = row.model, author = row.owner_name, items = DB.Decode(row.items, {}) }
end)

lib.callback.register('nayzeee-tuning:deleteBuild', function(src, code)
    MySQL.update.await('DELETE FROM nz_tuning_builds WHERE code = ? AND owner = ?', { code, Bridge.GetIdentifier(src) })
    return true
end)

--------------------------------------------------------------------- performance lab

local testIds = {}
for _, t in ipairs(Config.PerfTest.Tests) do testIds[t.id] = t end

lib.callback.register('nayzeee-tuning:perfSubmit', function(src, test, time, netId, label)
    if not Config.PerfTest.Enabled or not Core.Throttle(src, 'perf', 4000) then return false end
    time = tonumber(time)
    if not testIds[test] or not time or time < (Config.PerfTest.MinTimes[test] or 0) or time > Config.PerfTest.Timeout then return false, L('perf_rejected') end
    local veh = Core.VehicleFromNet(netId)
    if not veh or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return false end
    local model = Core.ModelName(GetEntityModel(veh)) or tostring(GetEntityModel(veh))
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local id = Bridge.GetIdentifier(src)
    local prevBest = MySQL.scalar.await('SELECT MIN(time) FROM nz_tuning_perf WHERE identifier = ? AND model = ? AND test = ?', { id, model, test })
    MySQL.insert.await('INSERT INTO nz_tuning_perf (identifier, name, model, label, plate, test, time) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { id, Bridge.GetName(src), model, tostring(label or model):sub(1, 60), plate, test, NZ.Round(time, 3) })
    local rank = MySQL.scalar.await('SELECT COUNT(*) + 1 FROM (SELECT MIN(time) AS t FROM nz_tuning_perf WHERE test = ? GROUP BY identifier, model) x WHERE x.t < ?', { test, time })
    return true, { rank = rank, pb = prevBest == nil or time < prevBest, prev = prevBest }
end)

lib.callback.register('nayzeee-tuning:perfBoard', function(src, test, model)
    if not testIds[test] then return {} end
    local q = 'SELECT name, model, label, MIN(time) AS t FROM nz_tuning_perf WHERE test = ? %s GROUP BY identifier, model, name, label ORDER BY t ASC LIMIT ?'
    local rows
    if model and model ~= '' then
        rows = MySQL.query.await(q:format('AND model = ?'), { test, model, Config.PerfTest.Leaderboard })
    else
        rows = MySQL.query.await(q:format(''), { test, Config.PerfTest.Leaderboard })
    end
    return rows or {}
end)

--------------------------------------------------------------------- police

local function isPolice(src)
    return NZ.InList(Config.Police.Jobs, Bridge.GetJob(src).name)
end

lib.callback.register('nayzeee-tuning:canInspect', function(src) return Config.Police.Enabled and isPolice(src) end)

lib.callback.register('nayzeee-tuning:inspectLog', function(src, netId, found)
    if not isPolice(src) then return false end
    local veh = Core.VehicleFromNet(netId)
    if not veh then return false end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    Core.Log('police', 'Vehicle inspected', { Plate = plate, Illegal = tonumber(found) or 0 }, src)
    local owner = Bridge.GetVehicleOwner(plate)
    return true, { registered = owner ~= nil, km = Vehicles.Get(plate).km or 0 }
end)

lib.callback.register('nayzeee-tuning:strip', function(src, netId, ids)
    if not Config.Police.AllowStrip or not isPolice(src) or type(ids) ~= 'table' then return false, L('no_permission') end
    local veh = Core.VehicleFromNet(netId)
    if not veh or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 6.0 then return false, L('too_far') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end

    Vehicles.Update(plate, veh, function(d)
        if set.nitrous then d.nitrous = nil end
        if set.antilag then d.antilag = nil end
        if set.launch then d.launch = nil end
        if set.swap then d.swap = nil end
        if set.airride then d.airride, d.air = nil, nil end
        if set.neonPattern then d.neonPattern = nil end
        if set.xenonRGB then d.xenonRGB = nil end
        if set.bulletproof then d.bulletproof = nil end
        if set.camber and d.stance then d.stance.cF, d.stance.cR = 0, 0 end
        if set.height then d.height = nil end
    end)

    local partial = {}
    if set.neon then partial.neonEnabled = { false, false, false, false } end
    if set.tint then partial.windowTint = 0 end
    if set.xenon or set.xenonRGB then partial.xenonColor = 255 end
    if next(partial) then
        Vehicles.SendProps(veh, partial)
        local stored = Bridge.GetVehicleProps(plate)
        if stored then
            for k, v in pairs(partial) do stored[k] = v end
            Bridge.SaveVehicleProps(plate, stored)
        end
    end
    Core.Log('police', 'Illegal parts removed', { Plate = plate, Parts = table.concat(ids, ', ') }, src)
    return true
end)

--------------------------------------------------------------------- diagnostics

local function canScan(src)
    local d = Config.Diagnostics
    if not d.Enabled then return false end
    if d.Jobs and not NZ.InList(d.Jobs, Bridge.GetJob(src).name) then return false end
    if d.Item and Bridge.ItemCount(src, d.Item) > 0 then return true end
    for id, shop in pairs(Config.Shops) do
        if shop.job and Core.IsEmployee(src, id) then return true end
    end
    return false
end

lib.callback.register('nayzeee-tuning:diagnose', function(src, netId)
    if not canScan(src) then return false, L('no_permission') end
    local veh = Core.VehicleFromNet(netId)
    if not veh or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 6.0 then return false, L('too_far') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local d = Vehicles.Get(plate)
    local jobs = MySQL.scalar.await('SELECT COUNT(*) FROM nz_tuning_history WHERE plate = ?', { plate }) or 0
    local last = MySQL.single.await('SELECT shop, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_history WHERE plate = ? ORDER BY id DESC LIMIT 1', { plate })
    return true, {
        plate = plate, registered = Bridge.GetVehicleOwner(plate) ~= nil, km = d.km or 0,
        wear = d.wear or { engine = 100, transmission = 100, brakes = 100, suspension = 100, tyres = 100, turbo = 100 },
        nitrous = d.nitrous, ecu = d.ecu ~= nil, swap = d.swap and NZ.SwapBySound[d.swap] and NZ.SwapBySound[d.swap].label,
        antilag = d.antilag, launch = d.launch, airride = d.airride, locator = d.locator,
        jobs = jobs, lastShop = last and (Config.Shops[last.shop] and Config.Shops[last.shop].label or last.shop), lastTime = last and last.t,
    }
end)

if Config.Diagnostics.Enabled and Config.Diagnostics.Item then
    CreateThread(function()
        while not Core.Ready do Wait(500) end
        Bridge.RegisterUsableItem(Config.Diagnostics.Item, function(src)
            TriggerClientEvent('nayzeee-tuning:useScanner', src)
        end)
    end)
end

--------------------------------------------------------------------- test drives

local TestDrives = {}

RegisterNetEvent('nayzeee-tuning:testDrive', function(netId, active)
    local src = source
    if not Config.TestDrive.Enabled then return end
    local s = Sessions[src]
    if active then
        if not s or s.netId ~= netId then return end
        TestDrives[src] = { netId = netId, started = os.time() }
        local veh = Core.VehicleFromNet(netId)
        if veh then Entity(veh).state:set('nzTestDrive', true, true) end
    else
        local td = TestDrives[src]
        TestDrives[src] = nil
        local veh = td and Core.VehicleFromNet(td.netId)
        if veh then Entity(veh).state:set('nzTestDrive', nil, true) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local td = TestDrives[src]
    if not td then return end
    TestDrives[src] = nil
    -- a car mid test-drive carries parts nobody paid for: remove it so nothing saves those parts
    local veh = Core.VehicleFromNet(td.netId)
    if veh then DeleteEntity(veh) end
end)

exports('IsInTestDrive', function(veh)
    return veh and DoesEntityExist(veh) and Entity(veh).state.nzTestDrive == true or false
end)
