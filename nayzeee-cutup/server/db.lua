-- Storage: oxmysql when available, otherwise data/db.json. Everything is kept in memory
-- and written through, so leaderboards never hit the database.
DB = { mode = 'json', players = {}, crews = {}, recent = {}, nextCrewId = 1, ready = false }

local RES, FILE = GetCurrentResourceName(), 'data/db.json'
local dirty = false

local function q(query, params)
    local p = promise.new()
    exports.oxmysql:query(query, params or {}, function(res) p:resolve(res or {}) end)
    return Citizen.Await(p)
end

local function decode(str)
    if type(str) ~= 'string' or str == '' then return nil end
    local ok, val = pcall(json.decode, str)
    return ok and val or nil
end

function DB.Init()
    local want = Config.Storage
    local hasSql = GetResourceState('oxmysql') == 'started'
    if want == 'mysql' and not hasSql then
        print('^3[nayzeee-cutup] Config.Storage is mysql but oxmysql is not started, using data/db.json^7')
    end
    DB.mode = ((want == 'mysql' or want == 'auto') and hasSql) and 'mysql' or 'json'

    if DB.mode == 'mysql' then
        q([[CREATE TABLE IF NOT EXISTS `cutup_players` (
            `identifier` VARCHAR(64) NOT NULL PRIMARY KEY,
            `name` VARCHAR(64) NOT NULL DEFAULT '',
            `data` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )]])
        q([[CREATE TABLE IF NOT EXISTS `cutup_crews` (
            `id` INT NOT NULL PRIMARY KEY,
            `data` LONGTEXT NOT NULL
        )]])
        q([[CREATE TABLE IF NOT EXISTS `cutup_runs` (
            `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(64) NOT NULL,
            `points` BIGINT NOT NULL,
            `crew_run` TINYINT(1) NOT NULL DEFAULT 0,
            `data` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX (`identifier`), INDEX (`points`)
        )]])
        for _, row in ipairs(q('SELECT `identifier`, `data` FROM `cutup_players`')) do
            local d = decode(row.data)
            if d then DB.players[row.identifier] = d end
        end
        for _, row in ipairs(q('SELECT `id`, `data` FROM `cutup_crews`')) do
            local d = decode(row.data)
            if d then
                d.id = tonumber(row.id)
                DB.crews[d.id] = d
                if d.id >= DB.nextCrewId then DB.nextCrewId = d.id + 1 end
            end
        end
    else
        local raw = LoadResourceFile(RES, FILE)
        local d = decode(raw) or {}
        DB.players = d.players or {}
        DB.recent = d.recent or {}
        DB.nextCrewId = d.nextCrewId or 1
        for id, c in pairs(d.crews or {}) do
            c.id = tonumber(id)
            DB.crews[c.id] = c
        end
    end

    local pc, cc = 0, 0
    for _ in pairs(DB.players) do pc = pc + 1 end
    for _ in pairs(DB.crews) do cc = cc + 1 end
    print(('^5[nayzeee-cutup]^7 storage: %s | %d drivers | %d crews'):format(DB.mode, pc, cc))
    DB.ready = true
end

local function flush()
    if DB.mode ~= 'json' or not dirty then return end
    dirty = false
    local crews = {}
    for id, c in pairs(DB.crews) do crews[tostring(id)] = c end
    SaveResourceFile(RES, FILE, json.encode({
        players = DB.players, crews = crews, recent = DB.recent, nextCrewId = DB.nextCrewId,
    }), -1)
end

function DB.SavePlayer(p)
    if DB.mode == 'mysql' then
        exports.oxmysql:query('INSERT INTO `cutup_players` (`identifier`, `name`, `data`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `data` = VALUES(`data`)',
            { p.identifier, p.name or '', json.encode(p) })
    else
        dirty = true
    end
end

function DB.SaveCrew(c)
    if DB.mode == 'mysql' then
        exports.oxmysql:query('INSERT INTO `cutup_crews` (`id`, `data`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
            { c.id, json.encode(c) })
    else
        dirty = true
    end
end

function DB.DeleteCrew(id)
    if DB.mode == 'mysql' then
        exports.oxmysql:query('DELETE FROM `cutup_crews` WHERE `id` = ?', { id })
    else
        dirty = true
    end
end

function DB.AddRun(identifier, run)
    if DB.mode == 'mysql' then
        exports.oxmysql:query('INSERT INTO `cutup_runs` (`identifier`, `points`, `crew_run`, `data`) VALUES (?, ?, ?, ?)',
            { identifier, run.points, run.crewRun and 1 or 0, json.encode(run) })
    else
        table.insert(DB.recent, 1, { identifier = identifier, run = run })
        while #DB.recent > 200 do table.remove(DB.recent) end
        dirty = true
    end
end

function DB.ResetBoards()
    for _, p in pairs(DB.players) do
        p.bestSolo, p.bestCrew = nil, nil
        DB.SavePlayer(p)
    end
    for _, c in pairs(DB.crews) do
        c.points = 0
        DB.SaveCrew(c)
    end
    DB.recent = {}
    if DB.mode == 'mysql' then exports.oxmysql:query('DELETE FROM `cutup_runs`') end
    dirty = true
end

CreateThread(function()
    while true do
        Wait(30000)
        flush()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES then flush() end
end)
