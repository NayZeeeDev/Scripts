--[[ Admin panel callbacks — every one re-checks permission server side ]]

local Event = AJ.Event

local function register(name, fn)
    lib.callback.register(Event('server:admin:' .. name), function(src, data)
        if not Bridge.HasPermission(src) then
            return { ok = false, msg = locale('no_permission') }
        end
        return fn(src, type(data) == 'table' and data or {})
    end)
end

local function adminName(src)
    return Bridge.GetAccountName(src)
end

local function midnight()
    local d = os.date('*t')
    return os.time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

local function inmate(e)
    local loc = AJ.GetLocation(e.location)
    return {
        identifier = e.identifier,
        id = e.source,
        name = e.name,
        account = e.account,
        reason = e.reason,
        admin = e.admin,
        location = e.location,
        locationName = loc and loc.name or e.location,
        remaining = Sentences.Remaining(e),
        total = e.total,
        ticking = Sentences.Ticking(e),
        state = e.state,
        escapes = e.escapes,
        cycles = e.cycles,
        reduced = e.reduced,
        jailedAt = e.jailedAt,
    }
end

local function inmates()
    local list = {}
    for _, e in pairs(Sentences.All()) do list[#list + 1] = inmate(e) end
    table.sort(list, function(a, b) return a.jailedAt > b.jailedAt end)
    return list
end

local function stats()
    local since = midnight()
    local today = DB.TodayStats(since)
    local serving, offline, sentenced, escapes = 0, 0, today.sentenced or 0, today.escapes or 0
    for _, e in pairs(Sentences.All()) do
        if e.source then serving = serving + 1 else offline = offline + 1 end
        if e.jailedAt >= since then
            sentenced = sentenced + 1
            escapes = escapes + e.escapes
        end
    end
    return { serving = serving, offline = offline, sentenced = sentenced, escapes = escapes }
end

register('open', function(src)
    local locations = {}
    for i = 1, #Config.Locations do
        local loc = Config.Locations[i]
        locations[i] = {
            id = loc.id, name = loc.name, description = loc.description, image = loc.image,
            tasks = loc.work and #loc.work or 0,
        }
    end
    return {
        ok = true,
        version = GetResourceMetadata(AJ.Resource, 'version', 0),
        admin = { name = adminName(src), id = src },
        locations = locations,
        defaultLocation = AJ.DefaultLocation().id,
        presets = Config.Sentence.presets,
        durations = Config.Sentence.quickDurations,
        maxMinutes = Config.Sentence.maxMinutes,
        stats = stats(),
        inmates = inmates(),
        recent = DB.Recent(6),
    }
end)

register('overview', function()
    return { ok = true, stats = stats(), inmates = inmates(), recent = DB.Recent(6) }
end)

register('inmates', function()
    return { ok = true, inmates = inmates() }
end)

register('players', function()
    local players, identifiers = {}, {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local info = Sentences.Known(src)
        local identifier = info and info.identifier
        players[#players + 1] = {
            id = src,
            name = info and info.name or Bridge.GetName(src),
            account = Bridge.GetAccountName(src),
            identifier = identifier,
            jailed = identifier and Sentences.Get(identifier) ~= nil or false,
        }
        if identifier then identifiers[#identifiers + 1] = identifier end
    end

    local priors = DB.Priors(identifiers)
    for i = 1, #players do
        players[i].priors = players[i].identifier and priors[players[i].identifier] or 0
        players[i].identifier = nil
    end
    table.sort(players, function(a, b) return a.id < b.id end)

    local recent, recentIds = Sentences.Recent(), {}
    for i = 1, #recent do recentIds[i] = recent[i].identifier end
    local recentPriors = DB.Priors(recentIds)
    local out = {}
    for i = 1, #recent do
        local r = recent[i]
        out[i] = {
            identifier = r.identifier, name = r.name, account = r.account, droppedAt = r.droppedAt,
            jailed = Sentences.Get(r.identifier) ~= nil, priors = recentPriors[r.identifier] or 0,
        }
    end

    return { ok = true, players = players, recent = out, now = os.time() }
end)

register('history', function(_, data)
    local rows, more = DB.History({ field = data.field, query = data.query }, data.page)
    return { ok = true, rows = rows, more = more }
end)

register('jail', function(src, data)
    local ok, res = Sentences.Jail({
        source = data.target,
        identifier = not data.target and data.identifier or nil,
        name = data.name,
        minutes = data.minutes,
        reason = data.reason,
        location = data.location,
        admin = adminName(src),
    })
    if not ok then return { ok = false, msg = res } end
    local msg = res.source and locale('jailed_admin', res.name, data.minutes) or locale('jailed_offline_admin', res.name)
    return { ok = true, msg = msg }
end)

local function withInmate(fn)
    return function(src, data)
        local e = data.identifier and Sentences.Get(data.identifier)
        if not e then return { ok = false, msg = locale('not_jailed') } end
        return fn(src, data, e)
    end
end

register('release', withInmate(function(src, _, e)
    Sentences.Release(e, 'released', adminName(src))
    return { ok = true, msg = locale('released_admin', e.name) }
end))

register('adjust', withInmate(function(src, data, e)
    local ok, err = Sentences.Adjust(e, data.minutes, adminName(src))
    if not ok then return { ok = false, msg = err } end
    return { ok = true, msg = locale('adjusted_admin', e.name, ('%+d'):format(math.floor(tonumber(data.minutes) or 0))) }
end))

register('transfer', withInmate(function(src, data, e)
    local ok, err = Sentences.Transfer(e, data.location, adminName(src))
    if not ok then return { ok = false, msg = err } end
    return { ok = true, msg = locale('transferred_admin', e.name, AJ.GetLocation(data.location).name) }
end))
