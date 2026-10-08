-----------------------------------------------------------------
-- Admin: vehicle pool, locations, interior layout, players
-----------------------------------------------------------------
local function guard(src)
    return Bridge.IsAdmin(src)
end

local function previewInterior()
    local i = Server.Interior()
    i.lowerOpen = true
    return i
end

local function adminData()
    local whs = {}
    local stockCounts = {}
    for _, r in ipairs(MySQL.query.await('SELECT warehouse, COUNT(*) AS c FROM nz_cargo_stock GROUP BY warehouse') or {}) do
        stockCounts[r.warehouse] = r.c
    end
    for id, w in pairs(DB.Warehouses) do
        local loc = DB.Locations[w.location]
        whs[#whs + 1] = { id = id, owner = w.owner_name, identifier = w.owner, location = loc and loc.name or '?', stock = stockCounts[id] or 0, upgrades = w.upgrades, associates = #w.associates }
    end
    table.sort(whs, function(a, b) return a.id < b.id end)

    local locs = {}
    for id, l in pairs(DB.Locations) do
        local owners = 0
        for _, w in pairs(DB.Warehouses) do if w.location == id then owners = owners + 1 end end
        locs[#locs + 1] = { id = id, name = l.name, price = l.price, enabled = l.enabled, door = l.door, garage = l.garage, garageExit = l.garageExit, spawn = l.spawn, owners = owners }
    end
    table.sort(locs, function(a, b) return a.id < b.id end)

    local players = MySQL.query.await('SELECT identifier, name, xp, sourced, sold, failed, earned, source_cd, sell_cd FROM nz_cargo_profiles ORDER BY earned DESC LIMIT 100') or {}
    for _, p in ipairs(players) do p.level = Cargo.LevelFromXp(p.xp) end

    local totals = MySQL.single.await('SELECT COALESCE(SUM(earned),0) AS earned, COALESCE(SUM(sold),0) AS sold, COALESCE(SUM(sourced),0) AS sourced FROM nz_cargo_profiles') or {}
    local presets = {}
    for _, pr in ipairs(Server.Presets()) do presets[#presets + 1] = { id = pr.id, label = pr.label, admin = pr.admin, count = #pr.slots } end
    local set = {}
    for k, v in pairs(DB.Settings.interior or {}) do set[k] = type(v) == 'table' and (k ~= 'slots' or #v > 0) end
    return { floor = Server.FloorArea(), vehicles = Server.Pool(), warehouses = whs, locations = locs, players = players, totals = totals, interior = Server.Interior(), interiorSet = set,
             brokers = DB.Settings.brokers or {}, presets = presets, rarities = (function()
                local r = {} for _, x in ipairs(Config.Rarities) do r[#r + 1] = x.id end r[#r + 1] = Config.Illegal.id return r end)() }
end

lib.callback.register('nz_cargo:admin:data', function(src)
    if not guard(src) then return nil end
    return adminData()
end)

lib.callback.register('nz_cargo:admin:saveVehicle', function(src, v)
    if not guard(src) or type(v) ~= 'table' then return nil end
    local model = tostring(v.model or ''):lower():gsub('[^%w_%-]', '')
    if model == '' or not Cargo.Rarity[v.rarity] then return nil end
    local label = tostring(v.label or model):sub(1, 64)
    local value = math.max(0, math.floor(tonumber(v.value) or 0))
    local enabled = v.enabled ~= false
    MySQL.query.await([[INSERT INTO nz_cargo_custom_vehicles (model, label, rarity, value, enabled) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), rarity = VALUES(rarity), value = VALUES(value), enabled = VALUES(enabled)]],
        { model, label, v.rarity, value, enabled and 1 or 0 })
    DB.Custom[model] = { model = model, label = label, rarity = v.rarity, value = value, enabled = enabled, custom = true }
    Server.RebuildPool()
    return adminData()
end)

lib.callback.register('nz_cargo:admin:deleteVehicle', function(src, model)
    if not guard(src) then return nil end
    MySQL.query.await('DELETE FROM nz_cargo_custom_vehicles WHERE model = ?', { model })
    DB.Custom[model] = nil
    Server.RebuildPool()
    return adminData()
end)

lib.callback.register('nz_cargo:admin:wipeWarehouse', function(src, id)
    if not guard(src) then return nil end
    id = tonumber(id)
    for _, o in ipairs(Server.Occupants(id)) do TriggerClientEvent('nz_cargo:kick', o) end
    local w = DB.Warehouses[id]
    DB.DeleteWarehouse(id)
    if w then
        for tsrc, st in pairs(Server.Players) do
            if st.identifier == w.owner then TriggerClientEvent('nz_cargo:accessChanged', tsrc, Server.Accessible(tsrc)) end
        end
    end
    return adminData()
end)

local function adjustProfile(identifier, fn)
    local online
    for psrc, st in pairs(Server.Players) do if st.identifier == identifier then online = psrc end end
    local p = DB.GetProfile(identifier)
    fn(p)
    DB.SaveProfile(p)
    if not online then DB.DropProfile(identifier) end
    return online
end

lib.callback.register('nz_cargo:admin:giveXp', function(src, identifier, amount)
    if not guard(src) then return nil end
    amount = math.floor(tonumber(amount) or 0)
    adjustProfile(identifier, function(p) p.xp = math.max(0, p.xp + amount) end)
    return adminData()
end)

lib.callback.register('nz_cargo:admin:resetCooldowns', function(src, identifier)
    if not guard(src) then return nil end
    adjustProfile(identifier, function(p) p.source_cd = 0 p.sell_cd = 0 end)
    return adminData()
end)

-----------------------------------------------------------------
-- Locations
-----------------------------------------------------------------
local function validV4(t) return type(t) == 'table' and tonumber(t.x) and tonumber(t.y) and tonumber(t.z) end

lib.callback.register('nz_cargo:admin:saveLocation', function(src, l)
    if not guard(src) or type(l) ~= 'table' then return nil end
    if not (validV4(l.door) and validV4(l.garage) and validV4(l.spawn)) then return nil end
    local name = tostring(l.name or 'Warehouse'):sub(1, 64)
    local price = math.max(0, math.floor(tonumber(l.price) or 0))
    local enabled = l.enabled ~= false
    local door, garage, spawn = DB.V4(l.door), DB.V4(l.garage), DB.V4(l.spawn)
    local gexit = validV4(l.garageExit) and DB.V4(l.garageExit) or nil
    local ge = gexit and json.encode(gexit) or ''
    local id = tonumber(l.id)
    if id and DB.Locations[id] then
        MySQL.update.await('UPDATE nz_cargo_locations SET name = ?, price = ?, door = ?, garage = ?, spawn = ?, garage_exit = ?, enabled = ? WHERE id = ?', {
            name, price, json.encode(door), json.encode(garage), json.encode(spawn), ge, enabled and 1 or 0, id })
    else
        id = MySQL.insert.await('INSERT INTO nz_cargo_locations (name, price, door, garage, spawn, garage_exit, enabled) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            name, price, json.encode(door), json.encode(garage), json.encode(spawn), ge, enabled and 1 or 0 })
    end
    DB.Locations[id] = { id = id, name = name, price = price, enabled = enabled, door = door, garage = garage, spawn = spawn, garageExit = gexit }
    TriggerClientEvent('nz_cargo:locationsChanged', -1)
    return adminData()
end)

-- Re-read Config.SeedWarehouses: same name = updated, new name = added
lib.callback.register('nz_cargo:admin:importSeeds', function(src)
    if not guard(src) then return nil end
    DB.ImportSeeds()
    TriggerClientEvent('nz_cargo:locationsChanged', -1)
    return adminData()
end)

lib.callback.register('nz_cargo:admin:deleteLocation', function(src, id)
    if not guard(src) then return nil end
    id = tonumber(id)
    for _, w in pairs(DB.Warehouses) do
        if w.location == id then
            -- owned somewhere: disable instead of delete so owners keep access
            MySQL.update.await('UPDATE nz_cargo_locations SET enabled = 0 WHERE id = ?', { id })
            if DB.Locations[id] then DB.Locations[id].enabled = false end
            TriggerClientEvent('nz_cargo:locationsChanged', -1)
            return adminData()
        end
    end
    MySQL.query.await('DELETE FROM nz_cargo_locations WHERE id = ?', { id })
    DB.Locations[id] = nil
    TriggerClientEvent('nz_cargo:locationsChanged', -1)
    return adminData()
end)

-----------------------------------------------------------------
-- Interior layout (/cargoslots)
-----------------------------------------------------------------
lib.callback.register('nz_cargo:admin:isAdmin', function(src) return guard(src) end)

lib.callback.register('nz_cargo:admin:saveInterior', function(src, data)
    if not guard(src) or type(data) ~= 'table' then return false end
    local cur = DB.Settings.interior or {}
    for _, k in ipairs({ 'entry', 'exit', 'laptop', 'design' }) do
        if validV4(data[k]) then cur[k] = DB.V4(data[k]) end
    end
    local function list(src, max)
        local out = {}
        for _, s in ipairs(src) do if validV4(s) and #out < max then out[#out + 1] = DB.V4(s) end end
        return out
    end
    if type(data.slots) == 'table' then cur.slots = list(data.slots, Config.Layout.MaxSlots) end
    if type(data.lowerSlots) == 'table' then
        -- always 4: each one can be moved, none can be removed
        local moved = cur.lowerSlots or {}
        for k = 1, 4 do if validV4(data.lowerSlots[k]) then moved[k] = DB.V4(data.lowerSlots[k]) end end
        cur.lowerSlots = moved
    end
    if type(data.clear) == 'table' then
        for _, k in ipairs(data.clear) do if type(k) == 'string' then cur[k] = nil end end
    end
    if type(data.preset) == 'string' and data.preset ~= '' and type(data.slots) == 'table' then
        -- also keep these spots as a named preset owners can pick
        local presets = DB.Settings.presets or {}
        local id = 'admin_' .. data.preset:lower():gsub('[^%w]', '_')
        for i = #presets, 1, -1 do if presets[i].id == id then table.remove(presets, i) end end
        presets[#presets + 1] = { id = id, label = data.preset:sub(1, 32), slots = list(data.slots, Config.Layout.MaxSlots) }
        DB.SetSetting('presets', presets)
    end
    -- open floor + obstacles (presets are fitted inside it)
    local function box(b)
        if type(b) ~= 'table' or type(b.min) ~= 'table' or type(b.max) ~= 'table' then return nil end
        local x0, y0, x1, y1 = tonumber(b.min.x), tonumber(b.min.y), tonumber(b.max.x), tonumber(b.max.y)
        if not (x0 and y0 and x1 and y1) or math.abs(x1 - x0) < 1.0 or math.abs(y1 - y0) < 1.0 then return nil end
        return { min = { x = math.min(x0, x1), y = math.min(y0, y1) }, max = { x = math.max(x0, x1), y = math.max(y0, y1) } }
    end
    if data.floor or data.obstacle or data.clearObstacles then
        local f = cur.floor or Server.FloorArea()
        local fb = box(data.floor)
        if fb then f.min, f.max, f.z = fb.min, fb.max, tonumber(data.floor.z) or f.z end
        local ob = box(data.obstacle)
        if ob then f.obstacles = f.obstacles or {} if #f.obstacles < 24 then f.obstacles[#f.obstacles + 1] = ob end end
        if data.clearObstacles then f.obstacles = {} end
        cur.floor = f
    end
    if data.reset then cur = {} end
    DB.SetSetting('interior', cur)
    for psrc, st in pairs(Server.Players) do
        if st.inside and DB.Warehouses[st.inside] then
            TriggerClientEvent('nz_cargo:interior', psrc, Server.InteriorFor(DB.Warehouses[st.inside]))
            TriggerClientEvent('nz_cargo:display', psrc, Warehouse.Display(st.inside))
        elseif st.preview then
            TriggerClientEvent('nz_cargo:interior', psrc, previewInterior())
        end
    end
    return adminData()
end)

-----------------------------------------------------------------
-- Setup copy: an empty private copy of the interior for admins to
-- place spots and points in, without owning a warehouse.
-----------------------------------------------------------------
lib.callback.register('nz_cargo:admin:preview', function(src, back)
    if not guard(src) or not validV4(back) then return nil end
    local s = Server.Get(src)
    if not s or s.inside or s.preview then return nil end
    s.preview = DB.V4(back)
    local b = Config.BucketBase - 1
    SetRoutingBucketPopulationEnabled(b, false)
    SetRoutingBucketEntityLockdownMode(b, 'relaxed')
    SetPlayerRoutingBucket(src, b)
    return {
        id = 0, role = 'admin', interior = previewInterior(), style = 'basic_style_set',
        display = { main = {}, lower = {} }, capacity = Config.Layout.MaxSlots, workshopMode = Config.Workshop.Mode,
    }
end)

lib.callback.register('nz_cargo:admin:deletePreset', function(src, id)
    if not guard(src) then return nil end
    local presets = DB.Settings.presets or {}
    for i = #presets, 1, -1 do if presets[i].id == id then table.remove(presets, i) end end
    DB.SetSetting('presets', presets)
    return adminData()
end)

-----------------------------------------------------------------
-- Warehouse brokers (NPCs)
-----------------------------------------------------------------
lib.callback.register('nz_cargo:admin:addBroker', function(src, coords)
    if not guard(src) or not validV4(coords) then return nil end
    local list = DB.Settings.brokers or {}
    list[#list + 1] = DB.V4(coords)
    DB.SetSetting('brokers', list)
    TriggerClientEvent('nz_cargo:brokers', -1, list)
    return adminData()
end)

lib.callback.register('nz_cargo:admin:removeBroker', function(src, index)
    if not guard(src) then return nil end
    local list = DB.Settings.brokers or {}
    local i = tonumber(index)
    if i and list[i] then table.remove(list, i) end
    DB.SetSetting('brokers', list)
    TriggerClientEvent('nz_cargo:brokers', -1, list)
    return adminData()
end)
