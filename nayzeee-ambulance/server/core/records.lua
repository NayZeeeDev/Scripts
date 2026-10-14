--[[
    NAYZEEE AMBULANCE - Treatment records (NZA.Records)            ARCHITECTURE §12

    Every treatment and procedure on a PLAYER patient is written to `nza_records`
    (NPC patients are not logged). Writes are fire-and-forget.

    API
      NZA.Records.Add(pid, { medic = src, action = 'bandage', summary = 'text' | table }) → bool
      NZA.Records.Get(identifier, limit, cb?) → rows (await) | nil (when cb is given, async)
        row = { id, identifier, medic, medicName, action, summary (decoded when JSON), created }
    Table: nza_records (id INT AI PK, identifier, medic, medic_name, action, summary LONGTEXT, created)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Records = NZA.Records or {}
NZA.Core = NZA.Core or {}
local R = NZA.Records
local Core = NZA.Core

local ready = false

function R.Add(pid, entry)
    if not MySQL or type(entry) ~= 'table' then return false end
    local p
    if type(pid) == 'table' then
        p = (pid.pid and pid.identifier) and pid or NZA.Patients.Resolve(pid)
    else
        p = NZA.Patients.Get(pid)
    end
    local identifier = p and p.identifier
    if not identifier and type(pid) == 'string' and pid:sub(1, 2) == 'p:' then identifier = pid:sub(3) end
    if not identifier then return false end

    local medic = tonumber(entry.medic)
    local medicId, medicName = 'system', 'System'
    if medic and medic > 0 then
        medicId = Core.Identifier(medic) or ('src:' .. medic)
        medicName = Core.Name(medic)
    elseif type(entry.medic) == 'string' then
        medicId, medicName = entry.medic, entry.medicName or entry.medic
    end

    local summary = entry.summary
    if type(summary) == 'table' then
        local ok, enc = pcall(json.encode, summary)
        summary = ok and enc or ''
    end
    summary = tostring(summary or '')
    if #summary > 60000 then summary = summary:sub(1, 60000) end

    local function insert()
        MySQL.insert('INSERT INTO nza_records (identifier, medic, medic_name, action, summary) VALUES (?, ?, ?, ?, ?)',
            { identifier, medicId:sub(1, 64), tostring(medicName):sub(1, 64), tostring(entry.action or 'treat'):sub(1, 64), summary })
    end
    if ready then insert() else CreateThread(function()
        local waited = 0
        while not ready and waited < 20000 do Wait(250); waited = waited + 250 end
        if ready then insert() end
    end) end
    return true
end

local function decodeRows(rows)
    for _, row in ipairs(rows or {}) do
        local s = row.summary
        if type(s) == 'string' and (s:sub(1, 1) == '{' or s:sub(1, 1) == '[') then
            local ok, dec = pcall(json.decode, s)
            if ok then row.summary = dec end
        end
        row.medicName = row.medic_name
        row.medic_name = nil
    end
    return rows or {}
end

function R.Get(identifier, limit, cb)
    if not MySQL or not identifier then
        if cb then cb({}) end
        return {}
    end
    limit = math.max(1, math.min(500, math.floor(tonumber(limit) or 25)))
    local q = 'SELECT id, identifier, medic, medic_name, action, summary, UNIX_TIMESTAMP(created) AS created FROM nza_records WHERE identifier = ? ORDER BY id DESC LIMIT ?'
    if cb then
        MySQL.query(q, { identifier, limit }, function(rows) cb(decodeRows(rows)) end)
        return nil
    end
    return decodeRows(MySQL.query.await(q, { identifier, limit }))
end

CreateThread(function()
    Wait(0)
    if not MySQL or not MySQL.ready then return end
    MySQL.ready(function()
        local ok, err = pcall(MySQL.query.await, [[
            CREATE TABLE IF NOT EXISTS `nza_records` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `identifier` VARCHAR(64) NOT NULL,
                `medic` VARCHAR(64) NOT NULL DEFAULT 'system',
                `medic_name` VARCHAR(64) NULL,
                `action` VARCHAR(64) NOT NULL,
                `summary` LONGTEXT NULL,
                `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                INDEX `idx_identifier` (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        if not ok then NZA.Warn('nza_records table: ' .. tostring(err)) end
        ready = true
    end)
end)
