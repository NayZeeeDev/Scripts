--[[ Admin menu backend ]]

local function vec(c) return vector3(c.x, c.y, c.z) end

local function watchers(tv)
    if not tv.power or not tv.media then return 0 end
    local n, c = 0, vec(tv.coords)
    for _, pid in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(pid)
        if ped ~= 0 and #(GetEntityCoords(ped) - c) <= tv.range then n = n + 1 end
    end
    return n
end

local function row(tv)
    local m = tv.media
    return {
        id = tv.id, label = tv.label, model = tv.model, kind = tv.kind, coords = tv.coords,
        owner = tv.ownerName, permanent = tv.permanent, power = tv.power, locked = tv.locked,
        group = tv.group, range = tv.range, style = tv.style,
        playing = m and (m.title or Utils.fallbackTitle(m)) or nil,
        source = m and m.kind or nil, live = m and m.live or false, paused = m and m.paused or false,
        thumb = m and m.thumb or nil, watchers = watchers(tv),
        defaultUrl = tv.defaultUrl, autoplay = tv.autoplay, perms = tv.perms,
    }
end

local Admin = {}

Admin.dashboard = function()
    local list, playing, viewers, groups, permanent = {}, 0, 0, {}, 0
    for _, tv in pairs(TV.list) do
        local r = row(tv)
        list[#list + 1] = r
        if r.playing and tv.power then playing = playing + 1 end
        viewers = viewers + r.watchers
        if tv.group then groups[tv.group] = true end
        if tv.permanent then permanent = permanent + 1 end
    end
    table.sort(list, function(a, b) return (a.label or '') < (b.label or '') end)
    local g = 0
    for _ in pairs(groups) do g = g + 1 end
    return {
        screens = list,
        stats = { total = #list, playing = playing, viewers = viewers, groups = g, permanent = permanent, players = #GetPlayers() },
        storage = Storage.mode, framework = Bridge.framework,
        calibration = TV.calibration,
    }
end

Admin.create = function(src, d)
    if type(d) ~= 'table' or type(d.coords) ~= 'table' then return false end
    if d.kind ~= 'wall' and not Props.Get(d.model or '') then return false end
    local tv = TV.create({
        model = d.model, kind = d.kind or 'prop', coords = d.coords, heading = d.heading, pitch = d.pitch, roll = d.roll,
        wall = d.wall, label = d.label, range = tonumber(d.range), permanent = true, perms = d.perms,
        defaultUrl = d.defaultUrl ~= '' and d.defaultUrl or nil, autoplay = d.autoplay, loop = d.loop,
        aspect = d.aspect, style = d.style, hd = d.hd, remote = d.remote, power = d.autoplay == true,
        ownerName = 'Server',
    })
    TV.spawn(tv)
    Logs.add('admin', src, 'Created ' .. tv.label, tv.kind .. (tv.model and (' · ' .. tv.model) or ''), tv)
    if tv.autoplay and tv.defaultUrl then Media.play(tv, tv.defaultUrl, nil, { by = 'Autoplay' }) end
    return tv.id, 'created'
end

Admin.update = function(src, d)
    local tv = type(d) == 'table' and TV.get(d.id)
    if not tv then return false end
    if type(d.label) == 'string' then tv.label = d.label:sub(1, 40) end
    if tonumber(d.range) then tv.range = Utils.clamp(tonumber(d.range), 2.0, 250.0) end
    if d.defaultUrl ~= nil then tv.defaultUrl = (d.defaultUrl ~= '' and d.defaultUrl) or nil end
    if d.autoplay ~= nil then tv.autoplay = d.autoplay == true end
    if d.locked ~= nil then tv.locked = d.locked == true end
    if type(d.perms) == 'table' then
        tv.perms = {
            public = d.perms.public == true, jobs = d.perms.jobs or {}, gangs = d.perms.gangs or {},
            ace = (d.perms.ace ~= '' and d.perms.ace) or nil, allowed = tv.perms and tv.perms.allowed or {},
        }
    end
    local fields = { 'label', 'range', 'defaultUrl', 'autoplay', 'locked', 'perms' }
    -- geometry only goes out when the screen actually moved (it respawns the prop)
    if type(d.coords) == 'table' then
        tv.coords = { x = d.coords.x + 0.0, y = d.coords.y + 0.0, z = d.coords.z + 0.0 }
        tv.heading = (d.heading or tv.heading) + 0.0
        if d.pitch then tv.pitch = d.pitch + 0.0 end
        if d.roll then tv.roll = d.roll + 0.0 end
        if d.wall then tv.wall = d.wall end
        for _, k in ipairs({ 'coords', 'heading', 'pitch', 'roll', 'wall' }) do fields[#fields + 1] = k end
    end
    TV.save(tv)
    TV.patch(tv, fields)
    return true, 'saved'
end

Admin.delete = function(src, id)
    local tv = TV.get(id)
    if not tv then return false end
    Logs.add('danger', src, 'Deleted ' .. tv.label, nil, tv)
    TV.remove(id)
    return true, 'deleted'
end

Admin.stop = function(_, id)
    local tv = TV.get(id)
    if tv then Media.stop(tv) end
    return true, 'stopped'
end

Admin.logs = function() return Logs.list end

Admin.stopAll = function(src)
    Logs.add('danger', src, 'Stopped every screen')
    for _, tv in pairs(TV.list) do if tv.media then tv.media = nil TV.patch(tv, { 'media' }) end end
    return true, 'stopped'
end

Admin.lock = function(_, id)
    local tv = TV.get(id)
    if not tv then return false end
    tv.locked = not tv.locked
    TV.patch(tv, { 'locked' })
    TV.save(tv)
    return true, 'saved'
end

Admin.power = function(_, id)
    local tv = TV.get(id)
    if not tv then return false end
    for _, t in ipairs(TV.members(tv)) do
        t.power = not tv.power
        TV.patch(t, { 'power' })
    end
    return true
end

Admin.play = function(src, d)
    local tv = type(d) == 'table' and TV.get(d.id)
    if not tv then return false end
    return Media.play(tv, d.url, nil, { by = 'Admin' })
end

Admin.tp = function(_, id)
    local tv = TV.get(id)
    return tv and tv.coords or false
end

Admin.group = function(_, ids)
    if type(ids) ~= 'table' or #ids < 2 then return false end
    local group = 'g' .. Utils.id(6)
    local first = TV.get(ids[1])
    for _, id in ipairs(ids) do
        local t = TV.get(id)
        if t then
            t.group = group
            if first and t ~= first then
                t.media, t.queue, t.loop, t.power = Utils.copy(first.media), Utils.copy(first.queue), first.loop, first.power
            end
            TV.patch(t, { 'group', 'media', 'queue', 'loop', 'power' })
            TV.save(t)
        end
    end
    return group, 'linked'
end

Admin.ungroup = function(_, group)
    for _, t in pairs(TV.list) do
        if t.group == group then t.group = nil TV.patch(t, { 'group' }) TV.save(t) end
    end
    return true, 'unlinked'
end

Admin.calibrate = function(src, d)
    if type(d) ~= 'table' or type(d.model) ~= 'string' then return false end
    local s = d.screen
    if type(s) ~= 'table' then return false end
    TV.calibration[d.model] = {
        x = tonumber(s.x) or 0.0, y = tonumber(s.y) or 0.0, z = tonumber(s.z) or 0.0,
        w = Utils.clamp(tonumber(s.w) or 1.0, 0.05, 60.0), h = Utils.clamp(tonumber(s.h) or 0.6, 0.05, 40.0),
        face = (s.face == '+y' or s.face == '-y' or s.face == '+x' or s.face == '-x') and s.face or '-y',
        tilt = Utils.clamp(tonumber(s.tilt) or 0.0, -60.0, 60.0),
    }
    Storage.saveCalibration(TV.calibration)
    TriggerClientEvent('nztv:calibration', -1, d.model, TV.calibration[d.model])
    Logs.add('admin', src, 'Calibrated ' .. d.model)
    return true, 'saved'
end

Admin.calibReset = function(_, model)
    TV.calibration[model] = nil
    Storage.saveCalibration(TV.calibration)
    TriggerClientEvent('nztv:calibration', -1, model, nil)
    return true, 'saved'
end

RPC.admin = function(src, op, data)
    if not Perms.isAdmin(src) then return false, 'no_admin' end
    local fn = Admin[op]
    if not fn then return false end
    return fn(src, data)
end
