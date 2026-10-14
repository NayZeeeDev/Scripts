--[[
    NAYZEEE AMBULANCE - Dispatch (server): call log in the database (nza_calls)

    Every call is written when it is created and again when it closes (final status,
    units, response times). Calls still open when the resource stopped are closed with
    reason 'restart' on the next start. Rows older than Config.Dispatch.log.keepDays are
    deleted on start.

      NZA.DispatchLog.Insert(call)            new call
      NZA.DispatchLog.Close(call)             final state (status, units, reason, times)
      NZA.DispatchLog.Recent(opts) → rows     opts = { limit = 60, priority = 1..3, search = 'text' }
                                              (awaits the database; call from a handler/thread)
      NZA.DispatchLog.Ready() → bool

    Table (also in docs/modules/dispatch.md for sql/install.sql):
      nza_calls (id PK, code, priority, title, type, x, y, z, street, zone, caller, message,
                 source, npc, status, units LONGTEXT (json), reason, created, responded,
                 arrived, closed)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.DispatchLog = NZA.DispatchLog or {}
local Log = NZA.DispatchLog

local ready = false
local pending = {}

local CREATE = [[
CREATE TABLE IF NOT EXISTS `nza_calls` (
  `id` VARCHAR(16) NOT NULL,
  `code` VARCHAR(16) DEFAULT NULL,
  `priority` TINYINT NOT NULL DEFAULT 2,
  `title` VARCHAR(64) DEFAULT NULL,
  `type` VARCHAR(24) DEFAULT NULL,
  `x` FLOAT NOT NULL DEFAULT 0,
  `y` FLOAT NOT NULL DEFAULT 0,
  `z` FLOAT NOT NULL DEFAULT 0,
  `street` VARCHAR(80) DEFAULT NULL,
  `zone` VARCHAR(64) DEFAULT NULL,
  `caller` VARCHAR(64) DEFAULT NULL,
  `message` VARCHAR(255) DEFAULT NULL,
  `source` VARCHAR(12) DEFAULT NULL,
  `npc` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(8) NOT NULL DEFAULT 'DSP',
  `units` LONGTEXT DEFAULT NULL,
  `reason` VARCHAR(32) DEFAULT NULL,
  `created` INT UNSIGNED NOT NULL,
  `responded` INT UNSIGNED DEFAULT NULL,
  `arrived` INT UNSIGNED DEFAULT NULL,
  `closed` INT UNSIGNED DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `created` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

local function enabled()
    local c = Config.Dispatch and Config.Dispatch.log
    return MySQL ~= nil and (type(c) ~= 'table' or c.enabled ~= false)
end

local function run(fn)
    if not enabled() then return end
    if ready then
        local ok, err = pcall(fn)
        if not ok then NZA.Warn('dispatch log: ' .. tostring(err)) end
    else
        pending[#pending + 1] = fn
    end
end

local function unitsJson(c)
    local list = {}
    local hist = {}
    for _, h in ipairs(c.history or {}) do
        if h.u then hist[h.u] = true end
    end
    for name in pairs(hist) do list[#list + 1] = name end
    table.sort(list)
    return json.encode(list)
end

function Log.Ready() return ready end

function Log.Insert(c)
    run(function()
        MySQL.insert([[INSERT INTO nza_calls (id, code, priority, title, type, x, y, z, street, zone, caller, message, source, npc, status, created)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                       ON DUPLICATE KEY UPDATE code = VALUES(code), priority = VALUES(priority), title = VALUES(title), type = VALUES(type),
                         x = VALUES(x), y = VALUES(y), z = VALUES(z), street = VALUES(street), zone = VALUES(zone), caller = VALUES(caller),
                         message = VALUES(message), source = VALUES(source), npc = VALUES(npc), status = VALUES(status),
                         created = VALUES(created), responded = NULL, arrived = NULL, closed = NULL, reason = NULL, units = NULL]], {
            c.id, c.code, c.priority, c.title, c.type, c.coords.x, c.coords.y, c.coords.z, c.street, c.zone,
            c.caller, c.message, c.source, c.npc and 1 or 0, c.status, c.created,
        })
    end)
end

function Log.Close(c)
    run(function()
        MySQL.update([[UPDATE nza_calls SET code = ?, priority = ?, title = ?, type = ?, street = ?, zone = ?, status = ?, units = ?,
                       reason = ?, responded = ?, arrived = ?, closed = ? WHERE id = ?]], {
            c.code, c.priority, c.title, c.type, c.street, c.zone, c.status, unitsJson(c),
            c.reason, c.respondedAt, c.arrivedAt, c.closed or os.time(), c.id,
        })
    end)
end

function Log.Recent(opts)
    opts = type(opts) == 'table' and opts or {}
    if not (enabled() and ready) then return nil end
    local limit = math.floor(NZA.Util.clamp(tonumber(opts.limit) or 60, 1, 200))
    local where, args = {}, {}
    local prio = tonumber(opts.priority)
    if prio and prio >= 1 and prio <= 3 then
        where[#where + 1] = 'priority = ?'
        args[#args + 1] = math.floor(prio)
    end
    if type(opts.search) == 'string' and opts.search ~= '' then
        local s = '%' .. opts.search:sub(1, 40):gsub('[%%_\\]', '') .. '%'
        where[#where + 1] = '(id LIKE ? OR title LIKE ? OR street LIKE ? OR zone LIKE ? OR caller LIKE ? OR units LIKE ?)'
        for _ = 1, 6 do args[#args + 1] = s end
    end
    args[#args + 1] = limit
    local q = 'SELECT id, code, priority, title, type, x, y, street, zone, caller, message, source, npc, status, units, reason, created, responded, arrived, closed FROM nza_calls'
        .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '') .. ' ORDER BY created DESC LIMIT ?'
    local ok, rows = pcall(MySQL.query.await, q, args)
    if not ok or type(rows) ~= 'table' then return nil end
    for _, r in ipairs(rows) do
        local okj, list = pcall(json.decode, r.units or '[]')
        r.units = okj and type(list) == 'table' and list or {}
        r.npc = r.npc == 1 or r.npc == true
    end
    return rows
end

CreateThread(function()
    if not MySQL or not MySQL.ready then return end
    MySQL.ready(function()
        if not enabled() then return end
        local ok, err = pcall(MySQL.query.await, CREATE)
        if not ok then
            NZA.Warn('dispatch: could not create nza_calls: ' .. tostring(err))
            return
        end
        pcall(MySQL.update.await, "UPDATE nza_calls SET closed = UNIX_TIMESTAMP(), reason = 'restart' WHERE closed IS NULL")
        local keep = tonumber(Config.Dispatch.log and Config.Dispatch.log.keepDays) or 30
        if keep > 0 then
            pcall(MySQL.update.await, 'DELETE FROM nza_calls WHERE created < ?', { os.time() - keep * 86400 })
        end
        ready = true
        local list = pending
        pending = {}
        for _, fn in ipairs(list) do
            local okf, errf = pcall(fn)
            if not okf then NZA.Warn('dispatch log: ' .. tostring(errf)) end
        end
    end)
end)
