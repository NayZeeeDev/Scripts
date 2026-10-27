--[[
    NAYZEEE RADIO - Database (server): oxmysql or JSON files

    Everything the radio keeps between restarts goes through here: memory presets and the
    callsign per character, the channel locks set with /radioadmin and the admin list of
    radio vehicles. Two backends, picked once at start:

      mysql  oxmysql is started: its exports, wrapped in promises. The three tables are
             created on start with CREATE TABLE IF NOT EXISTS (sql/install.sql has the same
             statements for servers whose database user may not create tables).
      json   no oxmysql: data/players.json, data/channels.json and data/vehicles.json in
             this resource. The data/ folder must be writable by the server. FiveM does not
             create folders, so when data/ is missing the files go to the resource folder
             itself (nzr_players.json ...) and the console says so once.

    Every query failure is logged with NZR.Warn and answered with an empty result, so a
    broken database never breaks the radio itself (people just lose their presets).

    API (the Load* functions yield: call them from a thread, event or callback)
      NZR.DB.Ready()                       → true once the backend can be used
      NZR.DB.Await(timeoutMs?)             → Ready() after waiting for it (default 15 s)
      NZR.DB.Mode()                        → 'mysql' | 'json' | nil (still starting)
      NZR.DB.LoadPlayer(identifier)        → { presets = { 155.5 | false, ... } | nil, callsign = 'X' | nil }
      NZR.DB.SavePlayer(identifier, data)  data = { presets, callsign }   (fire and forget)
      NZR.DB.LoadChannels()                → { { freq = '155.50', access, code, jobs = { police = 0 }, label, updated_by }, ... }
      NZR.DB.SaveChannels(list, by)        → true | false   replaces every admin channel entry
      NZR.DB.LoadVehicles()                → { { model, label, range_mult }, ... }
      NZR.DB.SaveVehicles(list)            → true | false   replaces the admin vehicle list
      NZR.DB.Flush()                       write pending JSON files now (done on resource stop)

    Tables: nzr_players (identifier PK, presets JSON, callsign), nzr_channels (freq PK,
    access, code, jobs JSON, label, updated_by), nzr_vehicles (model PK, label, range_mult).
]]

if not NAYZEEE_LOCK_OK then return end

NZR.DB = NZR.DB or {}
local DB = NZR.DB

local RESOURCE = GetCurrentResourceName()
local QUERY_TIMEOUT = 10000      -- ms before a query that never answered counts as failed
local JSON_SAVE_DELAY = 2000     -- ms: several preset changes in a row become one file write

local mode = nil                 -- 'mysql' | 'json'
local ready = false

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `nzr_players` (
        `identifier` VARCHAR(80) NOT NULL,
        `presets` LONGTEXT NULL,
        `callsign` VARCHAR(16) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nzr_channels` (
        `freq` VARCHAR(8) NOT NULL,
        `access` VARCHAR(8) NOT NULL DEFAULT 'open',
        `code` VARCHAR(8) NULL,
        `jobs` LONGTEXT NULL,
        `label` VARCHAR(32) NULL,
        `updated_by` VARCHAR(80) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`freq`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nzr_vehicles` (
        `model` VARCHAR(64) NOT NULL,
        `label` VARCHAR(32) NULL,
        `range_mult` FLOAT NOT NULL DEFAULT 1.0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`model`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    if ok then return v end
    return nil
end

local function encode(v)
    local ok, s = pcall(json.encode, v)
    if ok then return s end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- OXMYSQL (exports wrapped in promises)
-- oxmysql is optional, so its lib/MySQL.lua is not in the manifest and the
-- exports are called directly. A query that errors may never call back, so
-- every wait has a timeout.
-- ════════════════════════════════════════════════════════════════════════

local function sql(method, query, params)
    local p = promise.new()
    local done = false
    local function finish(result)
        if done then return end
        done = true
        p:resolve(result)
    end
    local ok, err = pcall(function()
        exports.oxmysql[method](exports.oxmysql, query, params or {}, function(result) finish(result) end)
    end)
    if not ok then
        NZR.Warn(('database %s failed: %s'):format(method, tostring(err)))
        return nil
    end
    SetTimeout(QUERY_TIMEOUT, function()
        if not done then
            NZR.Warn(('database %s gave no answer within %d s: %s'):format(method, QUERY_TIMEOUT // 1000, query:sub(1, 80)))
            finish(nil)
        end
    end)
    return Citizen.Await(p)
end

-- Several statements as one transaction (all or nothing).
local function transaction(queries)
    local p = promise.new()
    local done = false
    local function finish(result)
        if done then return end
        done = true
        p:resolve(result)
    end
    local ok, err = pcall(function()
        exports.oxmysql:transaction(queries, function(success) finish(success == true) end)
    end)
    if not ok then
        NZR.Warn(('database transaction failed: %s'):format(tostring(err)))
        return false
    end
    SetTimeout(QUERY_TIMEOUT, function()
        if not done then
            NZR.Warn('database transaction gave no answer within ' .. (QUERY_TIMEOUT // 1000) .. ' s')
            finish(false)
        end
    end)
    return Citizen.Await(p) == true
end

local function startMysql()
    for _, statement in ipairs(SCHEMA) do
        local res = sql('query', statement, {})
        if res == nil then
            NZR.Warn('could not create a radio table (see the error above). Run sql/install.sql by hand if your database user may not create tables.')
        end
    end
    mode = 'mysql'
    ready = true
    NZR.Debug('database: oxmysql')
end

-- ════════════════════════════════════════════════════════════════════════
-- JSON FILES
-- ════════════════════════════════════════════════════════════════════════

local FILES = { players = 'players.json', channels = 'channels.json', vehicles = 'vehicles.json' }
local store = { players = {}, channels = {}, vehicles = {} }
local dirty = {}
local flushQueued = false
local useRoot = false            -- data/ could not be written: files live in the resource folder
local warnedRoot = false

local function pathOf(kind, root)
    if root then return 'nzr_' .. FILES[kind] end
    return 'data/' .. FILES[kind]
end

local function readFile(kind)
    local raw = LoadResourceFile(RESOURCE, pathOf(kind, false))
    if not raw or raw == '' then
        raw = LoadResourceFile(RESOURCE, pathOf(kind, true))
        if raw and raw ~= '' then useRoot = true end
    end
    return decode(raw)
end

local function writeFile(kind)
    local data = encode(store[kind])
    if not data then
        NZR.Warn(('could not encode %s for saving'):format(FILES[kind]))
        return false
    end
    if not useRoot then
        if SaveResourceFile(RESOURCE, pathOf(kind, false), data, -1) then return true end
        useRoot = true
    end
    if not warnedRoot then
        warnedRoot = true
        NZR.Warn(('the folder %s/data/ is missing or not writable: saving to %s/nzr_*.json instead. '
            .. 'Create data/ (writable by the server) to keep them there.'):format(RESOURCE, RESOURCE))
    end
    local ok = SaveResourceFile(RESOURCE, pathOf(kind, true), data, -1)
    if not ok then NZR.Warn(('could not save %s - check the folder permissions'):format(pathOf(kind, true))) end
    return ok == true
end

function DB.Flush()
    if mode ~= 'json' then return end
    for kind in pairs(dirty) do writeFile(kind) end
    dirty = {}
    flushQueued = false
end

local function markDirty(kind, now)
    dirty[kind] = true
    if now then
        writeFile(kind)
        dirty[kind] = nil
        return
    end
    if flushQueued then return end
    flushQueued = true
    SetTimeout(JSON_SAVE_DELAY, DB.Flush)
end

local function startJson()
    for kind in pairs(FILES) do
        local data = readFile(kind)
        if type(data) == 'table' then store[kind] = data end
    end
    mode = 'json'
    ready = true
    NZR.Debug('database: json files')
end

-- ════════════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    -- give a resource that is still starting a moment (ensure order oxmysql → radio)
    local t = GetGameTimer()
    while GetResourceState('oxmysql') == 'starting' and GetGameTimer() - t < 10000 do Wait(100) end
    if GetResourceState('oxmysql') == 'started' then
        startMysql()
    else
        startJson()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    DB.Flush()
end)

function DB.Ready()
    return ready
end

function DB.Mode()
    return mode
end

function DB.Await(timeout)
    local t = GetGameTimer()
    timeout = timeout or 15000
    while not ready and GetGameTimer() - t < timeout do Wait(50) end
    return ready
end

-- ════════════════════════════════════════════════════════════════════════
-- PLAYERS (presets, callsign)
-- ════════════════════════════════════════════════════════════════════════

local function cleanPresets(list)
    if type(list) ~= 'table' then return nil end
    local out = {}
    local n = math.max(0, math.floor(tonumber(Config.Radios and Config.Radios.presets) or 6))
    for i = 1, n do
        local f = NZR.Freq.Parse(list[i])
        out[i] = (f and NZR.Freq.Valid(f)) and f or false
    end
    return out
end

function DB.LoadPlayer(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    if not DB.Await() then return {} end
    if mode == 'mysql' then
        local row = sql('single', 'SELECT `presets`, `callsign` FROM `nzr_players` WHERE `identifier` = ?', { identifier })
        if type(row) ~= 'table' then return {} end
        return { presets = cleanPresets(decode(row.presets)), callsign = type(row.callsign) == 'string' and row.callsign or nil }
    end
    local row = store.players[identifier]
    if type(row) ~= 'table' then return {} end
    return { presets = cleanPresets(row.presets), callsign = type(row.callsign) == 'string' and row.callsign or nil }
end

function DB.SavePlayer(identifier, data)
    if type(identifier) ~= 'string' or identifier == '' or type(data) ~= 'table' then return end
    local presets = cleanPresets(data.presets) or {}
    local callsign = type(data.callsign) == 'string' and data.callsign or nil
    if mode == 'mysql' then
        local ok, err = pcall(function()
            exports.oxmysql:query(
                'INSERT INTO `nzr_players` (`identifier`, `presets`, `callsign`) VALUES (?, ?, ?) '
                .. 'ON DUPLICATE KEY UPDATE `presets` = VALUES(`presets`), `callsign` = VALUES(`callsign`)',
                { identifier, encode(presets) or '[]', callsign })
        end)
        if not ok then NZR.Warn(('saving radio presets failed: %s'):format(tostring(err))) end
        return
    end
    if mode == 'json' then
        store.players[identifier] = { presets = presets, callsign = callsign }
        markDirty('players')
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CHANNELS (admin locks)
-- ════════════════════════════════════════════════════════════════════════

local function channelRow(row)
    if type(row) ~= 'table' then return nil end
    local fkey = NZR.Freq.Key(row.freq)
    if not fkey then return nil end
    local jobs = row.jobs
    if type(jobs) == 'string' then jobs = decode(jobs) end
    return {
        freq = fkey,
        access = type(row.access) == 'string' and row.access or 'open',
        code = row.code ~= nil and tostring(row.code) or nil,
        jobs = type(jobs) == 'table' and jobs or nil,
        label = type(row.label) == 'string' and row.label or nil,
        updated_by = type(row.updated_by) == 'string' and row.updated_by or nil,
    }
end

function DB.LoadChannels()
    if not DB.Await() then return {} end
    local rows
    if mode == 'mysql' then
        rows = sql('query', 'SELECT `freq`, `access`, `code`, `jobs`, `label`, `updated_by` FROM `nzr_channels`', {})
    else
        rows = store.channels
    end
    local out = {}
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do
        local c = channelRow(row)
        if c then out[#out + 1] = c end
    end
    return out
end

function DB.SaveChannels(list, by)
    if type(list) ~= 'table' then return false end
    if not DB.Await() then return false end
    by = by and tostring(by):sub(1, 80) or nil
    if mode == 'mysql' then
        local queries = { { query = 'DELETE FROM `nzr_channels`', values = {} } }
        for _, c in ipairs(list) do
            queries[#queries + 1] = {
                query = 'INSERT INTO `nzr_channels` (`freq`, `access`, `code`, `jobs`, `label`, `updated_by`) VALUES (?, ?, ?, ?, ?, ?)',
                values = { c.freq, c.access or 'open', c.code, c.jobs and encode(c.jobs) or nil, c.label, by },
            }
        end
        return transaction(queries)
    end
    local rows = {}
    for _, c in ipairs(list) do
        rows[#rows + 1] = { freq = c.freq, access = c.access or 'open', code = c.code, jobs = c.jobs, label = c.label, updated_by = by }
    end
    store.channels = rows
    markDirty('channels', true)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- VEHICLES (admin radio vehicle list)
-- ════════════════════════════════════════════════════════════════════════

function DB.LoadVehicles()
    if not DB.Await() then return {} end
    local rows
    if mode == 'mysql' then
        rows = sql('query', 'SELECT `model`, `label`, `range_mult` FROM `nzr_vehicles`', {})
    else
        rows = store.vehicles
    end
    local out = {}
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do
        if type(row) == 'table' and type(row.model) == 'string' and row.model ~= '' then
            out[#out + 1] = {
                model = row.model,
                label = type(row.label) == 'string' and row.label or nil,
                range_mult = tonumber(row.range_mult) or 1.0,
            }
        end
    end
    return out
end

function DB.SaveVehicles(list)
    if type(list) ~= 'table' then return false end
    if not DB.Await() then return false end
    if mode == 'mysql' then
        local queries = { { query = 'DELETE FROM `nzr_vehicles`', values = {} } }
        for _, v in ipairs(list) do
            queries[#queries + 1] = {
                query = 'INSERT INTO `nzr_vehicles` (`model`, `label`, `range_mult`) VALUES (?, ?, ?)',
                values = { v.model, v.label, tonumber(v.range_mult) or 1.0 },
            }
        end
        return transaction(queries)
    end
    local rows = {}
    for _, v in ipairs(list) do
        rows[#rows + 1] = { model = v.model, label = v.label, range_mult = tonumber(v.range_mult) or 1.0 }
    end
    store.vehicles = rows
    markDirty('vehicles', true)
    return true
end
