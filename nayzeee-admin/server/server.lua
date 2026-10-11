-- ═══ dashboard ══════════════════════════════════════════════════════════
local dashCache, dashAt = nil, 0

NZ.Route('dashboard', 'statistics.view', function()
    local now = os.time()
    local players = GetPlayers()
    local staffOnline, staffDuty = 0, 0
    for _, s in pairs(NZ.Staff) do staffOnline = staffOnline + 1; if s.duty then staffDuty = staffDuty + 1 end end

    local jobs = {}
    for _, id in ipairs(players) do
        local j = Bridge.GetJob(tonumber(id)).label or 'None'
        jobs[j] = (jobs[j] or 0) + 1
    end
    local jobList = {}
    for label, n in pairs(jobs) do jobList[#jobList + 1] = { label = label, count = n } end
    table.sort(jobList, function(a, b) return a.count > b.count end)

    local jailed = 0
    for _ in pairs(NZ.Jailed) do jailed = jailed + 1 end

    local live = {
        online = #players, max = GetConvarInt('sv_maxclients', 48), staffOnline = staffOnline, staffDuty = staffDuty,
        uptime = now - NZ.Started, jobs = jobList, jailed = jailed,
        server = { name = GetConvar('sv_projectName', GetConvar('sv_hostname', 'FiveM')), build = GetConvar('version', ''):match('v%d+%.%d+%.%d+%.(%d+)') or '?',
            framework = Bridge.fw, inventory = Bridge.inv, onesync = GetConvar('onesync', 'off') },
    }

    -- heavier numbers are cached for 60s
    if not dashCache or now - dashAt > 60 then
        dashCache = {
            unique = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_players') or 0,
            newToday = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_players WHERE first_seen >= CURDATE()') or 0,
            newWeek = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_players WHERE first_seen >= NOW() - INTERVAL 7 DAY') or 0,
            returning = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_players WHERE first_seen >= NOW() - INTERVAL 7 DAY AND sessions > 1') or 0,
            characters = Bridge.CharacterCount(),
            bans = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_bans WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW())') or 0,
            warnings = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_warnings') or 0,
            warningsWeek = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_warnings WHERE created_at >= NOW() - INTERVAL 7 DAY') or 0,
            reportsOpen = MySQL.scalar.await("SELECT COUNT(*) FROM nz_admin_chats WHERE is_report = 1 AND status <> 'closed'") or 0,
            reportsToday = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_chats WHERE is_report = 1 AND created_at >= CURDATE()') or 0,
            deathsToday = MySQL.scalar.await("SELECT COUNT(*) FROM nz_admin_logs WHERE category = 'deaths' AND created_at >= CURDATE()") or 0,
            chart = MySQL.query.await('SELECT ts, players, staff FROM nz_admin_stats WHERE ts >= ? ORDER BY ts', { now - 86400 }) or {},
            week = MySQL.query.await([[SELECT DATE_FORMAT(FROM_UNIXTIME(ts), '%a') AS day, MAX(players) AS peak, ROUND(AVG(players)) AS avg
                FROM nz_admin_stats WHERE ts >= ? GROUP BY DATE(FROM_UNIXTIME(ts)) ORDER BY DATE(FROM_UNIXTIME(ts))]], { now - 7 * 86400 }) or {},
            latest = MySQL.query.await('SELECT name, UNIX_TIMESTAMP(first_seen) AS time, sessions FROM nz_admin_players ORDER BY first_seen DESC LIMIT 8') or {},
            rich = Bridge.RichList(6),
            topStaff = MySQL.query.await([[SELECT m.name, m.nickname, m.group_name, COALESCE(SUM(d.seconds), 0) AS secs FROM nz_admin_members m
                LEFT JOIN nz_admin_duty d ON d.license = m.license AND d.started >= NOW() - INTERVAL 7 DAY GROUP BY m.id ORDER BY secs DESC LIMIT 5]]) or {},
            recent = MySQL.query.await("SELECT category, action, staff_name, target_name, message, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_logs WHERE category IN ('staff','moderation','reports') ORDER BY id DESC LIMIT 8") or {},
            events = MySQL.query.await('SELECT id, title, UNIX_TIMESTAMP(date) AS date FROM nz_admin_events WHERE date >= NOW() ORDER BY date LIMIT 4') or {},
        }
        dashAt = now
    end
    for k, v in pairs(dashCache) do live[k] = v end
    return live
end)

-- ═══ resources ══════════════════════════════════════════════════════════
NZ.Route('resources:list', 'resources.read', function()
    local out = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name then
            out[#out + 1] = { name = name, state = GetResourceState(name), version = GetResourceMetadata(name, 'version', 0),
                author = GetResourceMetadata(name, 'author', 0), description = GetResourceMetadata(name, 'description', 0) }
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end)

NZ.Route('resources:action', 'resources.manage', function(src, d)
    local name, a = d.name, d.action
    if type(name) ~= 'string' or name == '' then return false, 'Pick a resource.' end
    if name == NZ.Resource then return false, 'This resource cannot manage itself.' end
    if GetResourceState(name) == 'missing' then return false, 'Resource not found.' end
    if a == 'start' then StartResource(name)
    elseif a == 'stop' then StopResource(name)
    elseif a == 'restart' then StopResource(name); Wait(250); StartResource(name)
    else return false end
    NZ.Log('developer', 'resource_' .. a, src, nil, ('%s %s'):format(a, name))
    return GetResourceState(name)
end)

-- ═══ console ════════════════════════════════════════════════════════════
local consoleBuf, consoleSubs, pending = {}, {}, {}
local devPending = {} -- target src -> { staff = src, at = os.time() }
local flushQueued = false

local function flush()
    flushQueued = false
    if #pending == 0 then return end
    local batch = pending; pending = {}
    for src in pairs(consoleSubs) do
        if NZ.HasPerm(src, 'console.read') then TriggerClientEvent('nzadmin:cl:push', src, 'console', batch)
        else consoleSubs[src] = nil end -- lost the permission since subscribing
    end
end

RegisterConsoleListener(function(channel, message)
    local line = { c = channel, m = message, t = os.time() }
    consoleBuf[#consoleBuf + 1] = line
    if #consoleBuf > 500 then table.remove(consoleBuf, 1) end
    if next(consoleSubs) and #pending < 400 then
        pending[#pending + 1] = line
        if not flushQueued then flushQueued = true; SetTimeout(400, flush) end
    end
end)

NZ.Route('console:subscribe', 'console.read', function(src, d)
    consoleSubs[src] = d.on and true or nil
    return d.on and consoleBuf or true
end)

NZ.Route('console:exec', 'console.execute', function(src, d)
    local cmd = NZ.Trim(d.command, 400); if cmd == '' then return false end
    NZ.Log('developer', 'console', src, nil, cmd)
    ExecuteCommand(cmd)
    return true
end)

AddEventHandler('nzadmin:sv:dropped', function(src) consoleSubs[src] = nil; devPending[src] = nil end)

-- ═══ developer ══════════════════════════════════════════════════════════
local function dump(v, depth)
    depth = depth or 0
    if type(v) ~= 'table' then return tostring(v) end
    if depth > 3 then return '{...}' end
    local parts = {}
    for k, val in pairs(v) do parts[#parts + 1] = ('%s = %s'):format(tostring(k), dump(val, depth + 1)); if #parts > 60 then parts[#parts + 1] = '...'; break end end
    return '{ ' .. table.concat(parts, ', ') .. ' }'
end
NZ.Dump = dump

NZ.Route('dev:exec', 'developer.execute', function(src, d)
    local code = tostring(d.code or '')
    if code == '' then return false end
    local side = d.side == 'client' and 'client' or 'server'
    NZ.Log('developer', 'lua_' .. side, src, nil, code:sub(1, 1500))
    if side == 'client' then
        local target = tonumber(d.target) or src
        if target <= 0 or not GetPlayerName(target) then return false, 'That player is not online.' end -- never -1 (everyone)
        if target ~= src and not NZ.CanTarget(src, target) then return false, 'That staff member is above you.' end
        devPending[target] = { staff = src, at = os.time() }
        TriggerClientEvent('nzadmin:cl:devExec', target, code, src)
        return { output = { 'Sent to client ' .. target } }
    end
    local out = {}
    local env = setmetatable({ print = function(...)
        local t = {}
        for i = 1, select('#', ...) do t[#t + 1] = dump((select(i, ...))) end
        out[#out + 1] = table.concat(t, '  ')
    end, source = src }, { __index = _G })
    local fn, err = load(code, '=nzadmin', 't', env)
    if not fn then return { error = err } end
    local res = table.pack(pcall(fn))
    if not res[1] then return { error = tostring(res[2]), output = out } end
    local ret = {}
    for i = 2, res.n do ret[#ret + 1] = dump(res[i]) end
    return { output = out, result = table.concat(ret, ', ') }
end)

-- only accept a result we asked this client for
RegisterNetEvent('nzadmin:sv:devResult', function(_, result)
    local src = source
    local p = devPending[src]
    if not p or os.time() - p.at > 60 then return end
    devPending[src] = nil
    if NZ.HasPerm(p.staff, 'developer.execute') then
        TriggerClientEvent('nzadmin:cl:push', p.staff, 'dev:result', { from = src, result = tostring(result or ''):sub(1, 8000) })
    end
end)

-- ═══ offline characters ═════════════════════════════════════════════════
NZ.Route('offline:search', 'offline_player.search', function(src, d)
    local q = NZ.Trim(d.search, 64); if #q < 2 then return {} end
    local rows = Bridge.SearchCharacters(q, 50)
    local online = {}
    for id in pairs(NZ.Online) do online[Bridge.CharId(id) or ''] = id end
    for _, r in ipairs(rows) do r.online = online[r.charId] end
    return rows
end)

NZ.Route('offline:update', false, function(src, d)
    local need = ({ name = 'offline_player.update_name', job = 'offline_player.change_job', gang = 'offline_player.change_job', money = 'offline_player.change_money', delete = 'offline_player.delete' })[d.field]
    if not need or not NZ.HasPerm(src, need) then return false, 'No permission.' end
    if type(d.charId) ~= 'string' or d.charId == '' then return false, 'Missing character.' end
    local v = d.value
    if d.field == 'name' then
        if type(v) ~= 'table' then return false end
        v = { first = NZ.Trim(v.first, 40), last = NZ.Trim(v.last, 40) }
        if v.first == '' or v.last == '' then return false, 'Enter a first and last name.' end
    elseif d.field == 'job' or d.field == 'gang' then
        if type(v) ~= 'table' or NZ.Trim(v.name, 50) == '' then return false, 'Pick a job.' end
        v = { name = NZ.Trim(v.name, 50), grade = math.max(0, math.floor(tonumber(v.grade) or 0)) }
    elseif d.field == 'money' then
        if type(v) ~= 'table' or not tonumber(v.amount) or tonumber(v.amount) < 0 then return false, 'Invalid amount.' end
        local acc = tostring(v.account or '')
        if not acc:match('^[%w_]+$') then return false, 'Invalid account.' end
        v = { account = acc, amount = math.floor(tonumber(v.amount)) }
    end
    d.value = v
    for id in pairs(NZ.Online) do if Bridge.CharId(id) == d.charId then return false, 'That character is online. Use the online player tools.' end end
    if not Bridge.UpdateOffline(d.charId, d.field, d.value) then return false, 'Nothing was changed.' end
    NZ.Log(d.field == 'delete' and 'moderation' or 'staff', 'offline_' .. d.field, src, { name = d.name, license = d.license }, ('%s on %s'):format(d.field, d.charId))
    return true
end)

NZ.Route('players:seen', 'offline_player.search', function(src, d)
    local q = '%' .. NZ.Trim(d.search, 64) .. '%'
    return MySQL.query.await('SELECT license, name, discord, UNIX_TIMESTAMP(first_seen) AS first, UNIX_TIMESTAMP(last_seen) AS last, playtime, sessions FROM nz_admin_players WHERE name LIKE ? OR license LIKE ? OR discord LIKE ? ORDER BY last_seen DESC LIMIT 60', { q, q, q })
end)

-- ═══ logs ═══════════════════════════════════════════════════════════════
NZ.Route('logs:list', 'logs.view', function(src, d)
    local where, args = {}, {}
    if d.category and d.category ~= 'all' then where[#where + 1] = 'category = ?'; args[#args + 1] = d.category end
    if d.search and d.search ~= '' then
        local q = '%' .. d.search .. '%'
        where[#where + 1] = '(message LIKE ? OR staff_name LIKE ? OR target_name LIKE ? OR target_license = ? OR action LIKE ?)'
        args[#args + 1] = q; args[#args + 1] = q; args[#args + 1] = q; args[#args + 1] = d.search; args[#args + 1] = q
    end
    if tonumber(d.before) then where[#where + 1] = 'id < ?'; args[#args + 1] = tonumber(d.before) end
    local sql = 'SELECT id, category, action, staff_name, target_name, target_license, message, x, y, z, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_logs'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY id DESC LIMIT 80'
    local rows = MySQL.query.await(sql, args) or {}
    local counts = MySQL.query.await('SELECT category, COUNT(*) AS n FROM nz_admin_logs WHERE created_at >= NOW() - INTERVAL 1 DAY GROUP BY category') or {}
    return { rows = rows, counts = counts }
end)

-- deaths (killer, weapon, position) feed the log + heatmap
local lastDeath = {}
RegisterNetEvent('nzadmin:sv:died', function(killer, weapon, coords)
    local src = source
    if not Config.Logs.Deaths or type(coords) ~= 'table' or not tonumber(coords.x) then return end
    if lastDeath[src] and os.time() - lastDeath[src] < 3 then return end -- one per few seconds, no spam
    lastDeath[src] = os.time()
    killer = tonumber(killer)
    local msg = killer and killer ~= src and GetPlayerName(killer) and ('killed by %s (%s)'):format(GetPlayerName(killer), tostring(weapon)) or ('died (%s)'):format(tostring(weapon))
    NZ.Log('deaths', 'death', killer and killer ~= src and GetPlayerName(killer) and { name = GetPlayerName(killer), license = NZ.License(killer) } or nil, src, msg, coords)
end)
AddEventHandler('nzadmin:sv:dropped', function(src) lastDeath[src] = nil end)

-- ═══ map ════════════════════════════════════════════════════════════════
NZ.Route('map:data', 'map.view', function(src, d)
    local players = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local ped = GetPlayerPed(id)
        local c = GetEntityCoords(ped)
        local s = NZ.Staff[id]
        players[#players + 1] = { id = id, name = GetPlayerName(id), x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped),
            veh = GetVehiclePedIsIn(ped, false) ~= 0, staff = s and s.group.color or nil, bucket = GetPlayerRoutingBucket(id),
            dead = GetEntityHealth(ped) <= 0 }
    end
    local out = { players = players }
    if d.heatmap then
        out.deaths = MySQL.query.await("SELECT x, y FROM nz_admin_logs WHERE category = 'deaths' AND x IS NOT NULL AND created_at >= NOW() - INTERVAL ? DAY LIMIT 5000", { tonumber(d.days) or 7 }) or {}
    end
    if d.vehicles and NZ.HasPerm(src, 'vehicles.view') then
        local vehs = {}
        for _, veh in ipairs(GetAllVehicles()) do
            local c = GetEntityCoords(veh)
            vehs[#vehs + 1] = { x = c.x, y = c.y, net = NetworkGetNetworkIdFromEntity(veh), plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+$', '') }
        end
        out.vehicles = vehs
    end
    return out
end)

-- ═══ bootstrap for the panel ════════════════════════════════════════════
NZ.Route('boot', false, function(src)
    return {
        me = NZ.StaffPayload(src), groups = NZ.GroupList(), catalog = NZ.Permissions, flags = Config.Flags,
        bans = { presets = Config.Bans.Presets, durations = Config.Bans.Durations }, warnPresets = Config.Warnings.Presets, maxWarnings = Config.Warnings.MaxBeforeBan,
        jail = { enabled = Config.Jail.Enabled, cells = #Config.Jail.Cells }, framework = Bridge.fw, inventory = Bridge.inv,
        teleports = Teleports, weatherTypes = Config.Weather.Types, map = Config.Map, vehicleImages = Config.VehicleImages,
        itemImages = Config.ItemImages, reports = Config.Reports.Enabled, version = NZ.Version, commands = Config.Commands, mapRefresh = Config.Map.Refresh,
        keybinds = Config.Keybinds, wipe = Config.VehicleWipe.Countdown, propDistance = Config.Props.StreamDistance,
        server = GetConvar('sv_projectName', GetConvar('sv_hostname', 'FiveM')),
    }
end)
