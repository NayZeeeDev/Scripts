NZ.World = { blips = {}, props = {}, zones = {} }

local function started(r) return GetResourceState(r) == 'started' end

-- ═══ weather / time ═════════════════════════════════════════════════════
local function weatherMode()
    if Config.Weather.Builtin then return 'builtin' end
    local r = Config.Weather.Resource
    if r == 'auto' then r = started('qb-weathersync') and 'qb-weathersync' or 'builtin' end
    return r
end

if Config.Weather.Builtin then
    GlobalState.nzWeather = { weather = 'EXTRASUNNY', hour = 12, minute = 0, setAt = os.time(), freeze = false, blackout = false }
end

NZ.Route('weather:get', false, function()
    local w = GlobalState.nzWeather or GlobalState.nzWeatherView
    return { mode = weatherMode(), types = Config.Weather.Types, state = w }
end)

NZ.Route('weather:set', 'weather.change', function(src, d)
    local mode = weatherMode()
    local cur = GlobalState.nzWeather or { weather = 'CLEAR', hour = 12, minute = 0, setAt = os.time() }
    local w = { weather = cur.weather, hour = cur.hour, minute = cur.minute, setAt = cur.setAt, freeze = cur.freeze == true, blackout = cur.blackout == true }
    if d.weather then
        local want, valid = tostring(d.weather):upper(), false
        for _, t in ipairs(Config.Weather.Types) do if t == want then valid = true end end
        if not valid then return false, 'Unknown weather type.' end
        w.weather = want
    end
    if d.hour then w.hour = math.floor(tonumber(d.hour) or 12) % 24; w.minute = math.floor(tonumber(d.minute) or 0) % 60; w.setAt = os.time() end
    if d.freeze ~= nil then
        if d.freeze and not w.freeze then -- lock the clock where it is right now
            local elapsed = math.floor((os.time() - w.setAt) / 2)
            local total = (w.hour * 60 + w.minute + elapsed) % 1440
            w.hour, w.minute, w.setAt = total // 60, total % 60, os.time()
        elseif not d.freeze and w.freeze then w.setAt = os.time() end
        w.freeze = d.freeze == true
    end
    if d.blackout ~= nil then w.blackout = d.blackout == true end

    if mode == 'qb-weathersync' then
        local ws = exports['qb-weathersync']
        if d.weather then ws:setWeather(w.weather) end
        if d.hour then ws:setTime(w.hour, w.minute) end
        if d.blackout ~= nil then ws:setBlackout(w.blackout) end
        if d.freeze ~= nil then ws:setTimeFreeze(w.freeze) end
    elseif mode == 'builtin' then
        GlobalState.nzWeather = w
    elseif Hooks and Hooks.SetWeather then
        pcall(Hooks.SetWeather, w, d)
    end
    GlobalState.nzWeatherView = w -- shown in the panel either way
    NZ.Log('staff', 'weather', src, nil, ('weather %s · %02d:%02d · freeze %s · blackout %s'):format(w.weather, w.hour, w.minute, tostring(w.freeze), tostring(w.blackout)))
    return w
end)

-- ═══ announcements ══════════════════════════════════════════════════════
local function announce(src, d)
    local msg = NZ.Trim(d.message, 500); if msg == '' then return false end
    local title = NZ.Trim(d.title, 60); if title == '' then title = 'Announcement' end
    local kinds = { info = true, success = true, warning = true, error = true }
    local sender = nil
    if not d.anonymous then sender = d.sender or NZ.Name(src) end
    local payload = { title = title, message = msg, sender = sender,
        seconds = math.min(60, math.max(3, tonumber(d.seconds) or Config.UI.AnnouncementSeconds)), kind = kinds[d.kind] and d.kind or 'info' }
    local target = tonumber(d.target) or -1
    if Config.Integrations.Notify == 'nayzeee-notify' or (Config.Integrations.Notify == 'auto' and started('nayzeee-notify')) then
        exports['nayzeee-notify']:TopNotify(target, { title = payload.title, message = payload.message, sender = payload.sender, duration = payload.seconds * 1000 })
    else
        TriggerClientEvent('nzadmin:cl:announce', target, payload)
    end
    NZ.Log('staff', 'announcement', src, nil, ('%s: %s'):format(payload.title, msg))
    return true
end
NZ.Announce = announce

NZ.Route('announce', 'announcements.create', function(src, d)
    d.sender = nil -- only set by the server
    if NZ.Trim(d.message, 500) == '' then return false, 'Write a message first.' end
    local delay = math.min(1440, math.floor(tonumber(d.delay) or 0))
    if delay > 0 then
        d.sender = NZ.Name(src) -- keep the name, they may log off before it goes out
        SetTimeout(delay * 60000, function() announce(src, d) end)
        NZ.Log('staff', 'announcement_scheduled', src, nil, ('in %d min: %s'):format(delay, NZ.Trim(d.message, 200)))
        return 'scheduled'
    end
    return announce(src, d)
end)

-- ═══ blips ══════════════════════════════════════════════════════════════
local function loadBlips()
    NZ.World.blips = MySQL.query.await('SELECT * FROM nz_admin_blips') or {}
    TriggerClientEvent('nzadmin:cl:world', -1, 'blips', NZ.World.blips)
end

NZ.Route('blips:list', false, function() return NZ.World.blips end)

NZ.Route('blips:save', 'blips.create', function(src, d)
    local c = d.coords
    if type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) then c = NZ.CoordsOf(src) end
    local vals = { NZ.Trim(d.label, 60), tonumber(c.x), tonumber(c.y), tonumber(c.z) or 0.0, math.max(0, math.floor(tonumber(d.sprite) or 1)),
        math.max(0, math.floor(tonumber(d.color) or 0)), math.min(5.0, math.max(0.1, tonumber(d.scale) or 0.8)),
        math.max(0, math.min(10, math.floor(tonumber(d.display) or 4))), d.short_range and 1 or 0, NZ.Trim(d.category or '', 40) }
    if vals[1] == '' then return false, 'Blip needs a label.' end
    if d.id then
        vals[#vals + 1] = d.id
        MySQL.update.await('UPDATE nz_admin_blips SET label = ?, x = ?, y = ?, z = ?, sprite = ?, color = ?, scale = ?, display = ?, short_range = ?, category = ? WHERE id = ?', vals)
    else
        MySQL.insert.await('INSERT INTO nz_admin_blips (label, x, y, z, sprite, color, scale, display, short_range, category) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', vals)
    end
    NZ.Log('staff', 'blip_saved', src, nil, 'saved blip ' .. vals[1])
    loadBlips()
    return NZ.World.blips
end)

NZ.Route('blips:delete', 'blips.delete', function(src, d)
    MySQL.update.await('DELETE FROM nz_admin_blips WHERE id = ?', { tonumber(d.id) or 0 })
    NZ.Log('staff', 'blip_deleted', src, nil, 'deleted blip #' .. tostring(d.id))
    loadBlips()
    return NZ.World.blips
end)

-- ═══ props ══════════════════════════════════════════════════════════════
local function loadProps()
    NZ.World.props = MySQL.query.await('SELECT id, name, type, model, x, y, z, rx, ry, rz, frozen, collision, anim FROM nz_admin_props') or {}
    TriggerClientEvent('nzadmin:cl:world', -1, 'props', NZ.World.props)
end

NZ.Route('props:list', 'props.view', function() return NZ.World.props end)

NZ.Route('props:save', 'props.create', function(src, d)
    local p = d.pos or {}
    if not tonumber(p.x) or not tonumber(p.y) or not tonumber(p.z) then return false, 'Invalid position.' end
    local t = (d.type == 'ped' or d.type == 'vehicle') and d.type or 'object'
    local model = NZ.Trim(d.model, 64); if model == '' then return false, 'Enter a model.' end
    local name = NZ.Trim(d.name, 60); if name == '' then name = model end
    local anim = NZ.Trim(d.anim, 90)
    local vals = { name, t, model, tonumber(p.x), tonumber(p.y), tonumber(p.z), tonumber(p.rx) or 0, tonumber(p.ry) or 0, tonumber(p.rz) or 0,
        d.frozen == false and 0 or 1, d.collision == false and 0 or 1, anim ~= '' and anim or nil }
    if d.id then
        vals[#vals + 1] = d.id
        MySQL.update.await('UPDATE nz_admin_props SET name = ?, type = ?, model = ?, x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ?, frozen = ?, collision = ?, anim = ? WHERE id = ?', vals)
    else
        vals[#vals + 1] = NZ.Name(src)
        MySQL.insert.await('INSERT INTO nz_admin_props (name, type, model, x, y, z, rx, ry, rz, frozen, collision, anim, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', vals)
    end
    NZ.Log('staff', 'prop_saved', src, nil, ('%s %s'):format(t, vals[3]), p)
    loadProps()
    return NZ.World.props
end)

NZ.Route('props:delete', 'props.delete', function(src, d)
    MySQL.update.await('DELETE FROM nz_admin_props WHERE id = ?', { d.id })
    NZ.Log('staff', 'prop_deleted', src, nil, 'deleted prop #' .. tostring(d.id))
    loadProps()
    return NZ.World.props
end)

-- ═══ zones ══════════════════════════════════════════════════════════════
local function loadZones()
    local rows = MySQL.query.await('SELECT * FROM nz_admin_zones') or {}
    for _, z in ipairs(rows) do z.points = json.decode(z.points) or {}; z.options = z.options and json.decode(z.options) or {} end
    NZ.World.zones = rows
    TriggerClientEvent('nzadmin:cl:world', -1, 'zones', rows)
end

NZ.Route('zones:list', 'zones.view', function() return { zones = NZ.World.zones, handlers = ZoneHandlerList or {} } end)

NZ.Route('zones:save', 'zones.create', function(src, d)
    local name = NZ.Trim(d.name, 60); if name == '' then return false, 'Zone needs a name.' end
    if type(d.points) ~= 'table' or #d.points < 3 then return false, 'A zone needs at least 3 points.' end
    local pts = {}
    for _, pt in ipairs(d.points) do
        if type(pt) ~= 'table' or not tonumber(pt.x) or not tonumber(pt.y) or not tonumber(pt.z) then return false, 'Invalid zone point.' end
        pts[#pts + 1] = { x = tonumber(pt.x), y = tonumber(pt.y), z = tonumber(pt.z) }
    end
    local handler = (type(d.handler) == 'string' and ZoneHandlers and ZoneHandlers[d.handler]) and d.handler or nil
    local color = tostring(d.color or ''):match('^#%x%x%x%x%x%x$') and d.color or '#08afa2'
    local vals = { name, json.encode(pts), math.max(1.0, math.min(500.0, tonumber(d.thickness) or 10)), handler, color, d.debug and 1 or 0,
        json.encode(type(d.options) == 'table' and d.options or {}) }
    if d.id then
        vals[#vals + 1] = d.id
        MySQL.update.await('UPDATE nz_admin_zones SET name = ?, points = ?, thickness = ?, handler = ?, color = ?, debug = ?, options = ? WHERE id = ?', vals)
    else
        MySQL.insert.await('INSERT INTO nz_admin_zones (name, points, thickness, handler, color, debug, options) VALUES (?, ?, ?, ?, ?, ?, ?)', vals)
    end
    NZ.Log('staff', 'zone_saved', src, nil, 'saved zone ' .. name)
    loadZones()
    return { zones = NZ.World.zones, handlers = ZoneHandlerList or {} }
end)

NZ.Route('zones:delete', 'zones.delete', function(src, d)
    MySQL.update.await('DELETE FROM nz_admin_zones WHERE id = ?', { tonumber(d.id) or 0 })
    NZ.Log('staff', 'zone_deleted', src, nil, 'deleted zone #' .. tostring(d.id))
    loadZones()
    return { zones = NZ.World.zones, handlers = ZoneHandlerList or {} }
end)

-- ═══ events calendar ════════════════════════════════════════════════════
NZ.Route('events:list', 'events.view', function(src, d)
    return MySQL.query.await([[SELECT id, title, description, UNIX_TIMESTAMP(date) AS date, author FROM nz_admin_events
        WHERE date >= FROM_UNIXTIME(?) AND date < FROM_UNIXTIME(?) ORDER BY date]], { tonumber(d.from) or 0, tonumber(d.to) or 4102444800 })
end)

NZ.Route('events:save', 'events.create', function(src, d)
    local title = NZ.Trim(d.title, 90); if title == '' or not tonumber(d.date) then return false, 'Event needs a title and date.' end
    if d.id then
        MySQL.update.await('UPDATE nz_admin_events SET title = ?, description = ?, date = FROM_UNIXTIME(?) WHERE id = ?', { title, NZ.Trim(d.description, 2000), math.floor(tonumber(d.date)), d.id })
    else
        MySQL.insert.await('INSERT INTO nz_admin_events (title, description, date, author) VALUES (?, ?, FROM_UNIXTIME(?), ?)', { title, NZ.Trim(d.description, 2000), math.floor(tonumber(d.date)), NZ.Name(src) })
    end
    NZ.Log('staff', 'event_saved', src, nil, ('%s · %s'):format(title, os.date('%Y-%m-%d %H:%M', math.floor(tonumber(d.date)))))
    return true
end)

NZ.Route('events:delete', 'events.delete', function(src, d)
    MySQL.update.await('DELETE FROM nz_admin_events WHERE id = ?', { tonumber(d.id) or 0 })
    NZ.Log('staff', 'event_deleted', src, nil, 'deleted event #' .. tostring(d.id))
    return true
end)

-- ═══ world sync for clients ═════════════════════════════════════════════
lib.callback.register('nzadmin:world', function()
    return { blips = NZ.World.blips, props = NZ.World.props, zones = NZ.World.zones }
end)

AddEventHandler('nzadmin:sv:booted', function()
    loadBlips(); loadProps(); loadZones()
end)
