--[[
    In-game shop editor (/mechaniceditor). Admins place bays, desks, booths, part racks, the tow /
    supply drop and the work-truck spawn without touching config files. Edits are stored in
    nz_tuning_shop_edits, layered over config.shops.lua and synced to everyone live.
]]

local E = Config.Editor
local edits = {}

local function publish()
    NZ.ApplyShopEdits(edits)
    for id, shop in pairs(Config.Shops) do
        if shop.job and not Core.Shops[id] then Core.EnsureShop(id) end
    end
    GlobalState.nzShopEdits = edits
end

CreateThread(function()
    while not DB.Ready do Wait(250) end
    local rows = MySQL.query.await('SELECT id, data FROM nz_tuning_shop_edits') or {}
    for _, r in ipairs(rows) do edits[r.id] = DB.Decode(r.data, nil) end
    while not Core.Ready do Wait(250) end
    publish()
end)

-- lib.addCommand grants 'command.<name>' to the restricted group, so the same check covers the callbacks
local function allowed(src) return E.Enabled and IsPlayerAceAllowed(src, 'command.' .. E.Command) end

-- what the editor shows: every shop with its current (merged) values as plain tables
local function snapshot()
    local out = {}
    for id, s in pairs(Config.Shops) do
        out[#out + 1] = {
            id = id, label = s.label, mode = s.mode, job = s.job, bayRadius = s.bayRadius, radius = s.radius,
            blip = s.blip, grades = s.grades, center = NZ.Plain(s.center), boss = NZ.Plain(s.boss), drop = NZ.Plain(s.drop),
            truckSpawn = NZ.Plain(s.truckSpawn), storage = NZ.Plain(s.storage), claimBays = s.claimBays, partSource = s.partSource,
            bays = (function()
                local out = NZ.Plain(s.bays or {})
                for i, b in ipairs(out) do b.r = (s.bayRadii or {})[i] end
                return out
            end)(), booths = NZ.Plain(s.booths or {}),
            stockpiles = NZ.Plain(s.stockpiles or {}), edited = edits[id] ~= nil, created = NZ.ShopBase[id] == nil,
        }
    end
    table.sort(out, function(a, b) return (a.label or a.id) < (b.label or b.id) end)
    return out
end

lib.callback.register('nayzeee-tuning:editor:open', function(src)
    if not allowed(src) then return false, L('no_permission') end
    return true, { shops = snapshot(), piles = NZ.EditorPiles }
end)

--------------------------------------------------------------------- validation

local function num(v, lo, hi) v = tonumber(v) return v and v == v and v >= lo and v <= hi end
local function isV3(t) return type(t) == 'table' and num(t.x, -10000, 10000) and num(t.y, -10000, 10000) and num(t.z, -500, 3000) end
local function isV4(t) return isV3(t) and num(t.w or 0, -720, 720) end
local function clean3(t) return { x = NZ.Round(t.x, 2), y = NZ.Round(t.y, 2), z = NZ.Round(t.z, 2) } end
local function clean4(t) return { x = NZ.Round(t.x, 2), y = NZ.Round(t.y, 2), z = NZ.Round(t.z, 2), w = NZ.Round(t.w or 0, 1) } end

local function validate(d)
    if type(d) ~= 'table' then return nil end
    local out = {}
    if d.label ~= nil then
        if type(d.label) ~= 'string' or #d.label < 2 or #d.label > 48 then return nil end
        out.label = d.label
    end
    if d.mode ~= nil then
        if d.mode ~= 'self' and d.mode ~= 'mechanic' and d.mode ~= 'hybrid' then return nil end
        out.mode = d.mode
    end
    if d.job ~= nil then
        if d.job == false or d.job == '' then out.job = false
        elseif type(d.job) == 'string' and d.job:match('^[%w_%-]+$') and #d.job <= 40 then out.job = d.job
        else return nil end
    end
    if d.bayRadius ~= nil then if not num(d.bayRadius, 1.0, 10.0) then return nil end out.bayRadius = d.bayRadius + 0.0 end
    if d.radius ~= nil then if not num(d.radius, 5.0, 200.0) then return nil end out.radius = d.radius + 0.0 end
    if d.grades ~= nil then
        local g = d.grades
        if type(g) ~= 'table' or not num(g.access, 0, 50) or not num(g.manager, 0, 50) or not num(g.boss, 0, 50) then return nil end
        out.grades = { access = math.floor(g.access), manager = math.floor(g.manager), boss = math.floor(g.boss) }
    end
    if d.blip ~= nil then
        local b = d.blip
        if type(b) ~= 'table' or not num(b.sprite or 0, 0, 1000) or not num(b.color or 0, 0, 100) then return nil end
        out.blip = { enabled = b.enabled ~= false, sprite = math.floor(b.sprite or 446), color = math.floor(b.color or 5), scale = NZ.Clamp(tonumber(b.scale) or 0.8, 0.3, 2.0) }
    end
    if d.claimBays ~= nil then
        if d.claimBays ~= true and d.claimBays ~= false and d.claimBays ~= 'auto' then return nil end
        out.claimBays = d.claimBays
    end
    if d.partSource ~= nil then
        if not NZ.InList({ 'default', 'supply', 'inventory', 'both' }, d.partSource) then return nil end
        out.partSource = d.partSource
    end
    for _, k in ipairs({ 'center', 'boss', 'drop', 'storage' }) do
        if d[k] ~= nil then
            if d[k] == false then out[k] = false elseif isV3(d[k]) then out[k] = clean3(d[k]) else return nil end
        end
    end
    if d.truckSpawn ~= nil then
        if d.truckSpawn == false then out.truckSpawn = false elseif isV4(d.truckSpawn) then out.truckSpawn = clean4(d.truckSpawn) else return nil end
    end
    if d.bays ~= nil then
        if type(d.bays) ~= 'table' or #d.bays > 20 then return nil end
        out.bays = {}
        for i, b in ipairs(d.bays) do
            if not isV4(b) or (b.r ~= nil and not num(b.r, 1.0, 10.0)) then return nil end
            out.bays[i] = clean4(b)
            if b.r ~= nil then out.bays[i].r = NZ.Round(b.r, 1) end
        end
    end
    if d.booths ~= nil then
        if type(d.booths) ~= 'table' or #d.booths > 10 then return nil end
        out.booths = {}
        for i, b in ipairs(d.booths) do
            if type(b) ~= 'table' or not isV3(b.coords) or not num(b.radius or 4.5, 1.0, 15.0) then return nil end
            out.booths[i] = { coords = clean3(b.coords), radius = (tonumber(b.radius) or 4.5) + 0.0 }
        end
    end
    if d.stockpiles ~= nil then
        if type(d.stockpiles) ~= 'table' then return nil end
        out.stockpiles = {}
        for pile, c in pairs(d.stockpiles) do
            if not NZ.InList(NZ.EditorPiles, pile) or not isV3(c) then return nil end
            out.stockpiles[pile] = clean3(c)
        end
    end
    return out
end

--------------------------------------------------------------------- save / reset / delete

lib.callback.register('nayzeee-tuning:editor:save', function(src, id, data)
    if not allowed(src) then return false, L('no_permission') end
    if type(id) ~= 'string' or not id:match('^[%w_]+$') or #id > 40 then return false, L('editor_bad_id') end
    local clean = validate(data)
    if not clean then return false, L('editor_invalid') end
    local creating = Config.Shops[id] == nil
    if creating and (not clean.label or not clean.center) then return false, L('editor_need_basics') end
    local e = edits[id] or {}
    for k, v in pairs(clean) do e[k] = v end
    e.deleted = nil
    edits[id] = e
    MySQL.insert.await('INSERT INTO nz_tuning_shop_edits (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)', { id, json.encode(e) })
    publish()
    Core.Log('admin', creating and 'Shop created in editor' or 'Shop edited', { Shop = id, By = Bridge.GetName(src) }, src)
    return true, snapshot()
end)

-- config shops go back to the file values, editor-made shops are removed
lib.callback.register('nayzeee-tuning:editor:reset', function(src, id)
    if not allowed(src) or type(id) ~= 'string' then return false, L('no_permission') end
    if NZ.ShopBase[id] then
        edits[id] = nil
        MySQL.update.await('DELETE FROM nz_tuning_shop_edits WHERE id = ?', { id })
    elseif edits[id] then
        edits[id] = nil
        MySQL.update.await('DELETE FROM nz_tuning_shop_edits WHERE id = ?', { id })
    else
        return false
    end
    publish()
    Core.Log('admin', 'Shop reset in editor', { Shop = id, By = Bridge.GetName(src) }, src)
    return true, snapshot()
end)

-- hide a config shop without editing the file
lib.callback.register('nayzeee-tuning:editor:disable', function(src, id)
    if not allowed(src) or not NZ.ShopBase[id] then return false, L('no_permission') end
    edits[id] = { deleted = true }
    MySQL.insert.await('INSERT INTO nz_tuning_shop_edits (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)', { id, json.encode(edits[id]) })
    publish()
    return true, snapshot()
end)

if E.Enabled then
    lib.addCommand(E.Command, { help = L('cmd_editor'), restricted = E.Ace or Config.Admin.Ace }, function(src)
        if src == 0 then return end
        TriggerClientEvent('nayzeee-tuning:editor', src)
    end)
end
