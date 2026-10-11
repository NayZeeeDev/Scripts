ESX = exports['es_extended']:getSharedObject()

MDT = {}
MDT.online   = {}     -- [src] = { identifier, name, department, rank, callsign, onDuty, status, lastOn }
MDT.viewers  = {}     -- [src] = true while the tablet is open
MDT.positions= {}     -- [identifier] = { x, y, z, heading, street, at }

local CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'

-- ═══════════════════════════════════════════════════════════
--  UTIL
-- ═══════════════════════════════════════════════════════════
function MDT.debug(...)
    if Config.Debug then print('^3[nayzeee-mdt]^7', ...) end
end

function MDT.rand(len)
    local out = {}
    for i = 1, len do
        local r = math.random(#CHARS)
        out[i] = CHARS:sub(r, r)
    end
    return table.concat(out)
end

function MDT.trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

function MDT.clean(s, len)
    s = MDT.trim(s):gsub('[%c]', '')
    if len and #s > len then s = s:sub(1, len) end
    return s
end

--- oxmysql hands TINYINT(1) columns back as booleans; older setups give 1/0.
--- Accept both so flags like on_duty and stolen read the same everywhere.
function MDT.bool(v)
    return v == true or v == 1 or v == '1'
end

--- oxmysql hands TIMESTAMP columns back as milliseconds; turn one into a date.
function MDT.date(v, fmt)
    if type(v) == 'number' then
        return os.date(fmt or '%d %b %Y', math.floor(v > 1e11 and v / 1000 or v))
    end
    return v and tostring(v):sub(1, 10) or nil
end

--- Clean a value and turn an empty result into nil, for optional columns.
function MDT.opt(s, len)
    if s == nil then return nil end
    local v = MDT.clean(s, len)
    return v ~= '' and v or nil
end

function MDT.now()
    return os.time()
end

function MDT.decode(raw, fallback)
    if not raw or raw == '' then return fallback or {} end
    local ok, out = pcall(json.decode, raw)
    if not ok or out == nil then return fallback or {} end
    return out
end

function MDT.fullName(xPlayer)
    if not xPlayer then return 'Unknown' end
    local n = xPlayer.getName and xPlayer.getName() or nil
    if n and n ~= '' then return n end
    return MDT.trim(('%s %s'):format(xPlayer.get('firstName') or '', xPlayer.get('lastName') or ''))
end

function MDT.notify(src, title, description, kind)
    if Config.Notify == 'ox_lib' then
        TriggerClientEvent('ox_lib:notify', src, {
            title = title, description = description,
            type = kind or 'inform', position = 'top-right'
        })
    else
        TriggerClientEvent('esx:showNotification', src, ('%s: %s'):format(title, description or ''))
    end
end

--- Make a reference like DISP-0042 from the row id, so two calls never collide.
function MDT.refFor(prefix, id, width)
    return ('%s-%0' .. (width or 4) .. 'd'):format(prefix, id)
end

--- Insert with a throwaway ref, then stamp the real one from the new row id.
--- Avoids the MAX(id)+1 race when two officers file at the same moment.
function MDT.insertWithRef(tbl, prefix, width, sql, args)
    args[1] = 'TMP-' .. MDT.rand(16)
    local id = MySQL.insert.await(sql, args)
    if not id then return nil end
    local ref = MDT.refFor(prefix, id, width)
    MySQL.update.await(('UPDATE %s SET ref = ? WHERE id = ?'):format(tbl), { ref, id })
    return id, ref
end

-- ═══════════════════════════════════════════════════════════
--  DEPARTMENT / PERMISSIONS
-- ═══════════════════════════════════════════════════════════
function MDT.getDepartment(job)
    return Config.Departments[job]
end

function MDT.isLEO(job)
    return Config.Departments[job] ~= nil
end

--- Resolve the permission list for a job + grade name.
--- Grades can be keyed by name ('sergeant') or by number (3), whichever
--- your job_grades table is easier to read. Numbers win if both exist.
function MDT.permissionsFor(job, gradeName, gradeNumber)
    local set = Config.Ranks[job]
    if not set then set = Config.Ranks.default end
    if not set then return {} end

    local list
    if gradeNumber ~= nil and set[gradeNumber] then
        list = set[gradeNumber]
    elseif gradeName and set[gradeName] then
        list = set[gradeName]
    elseif gradeNumber ~= nil and set[tostring(gradeNumber)] then
        list = set[tostring(gradeNumber)]
    else
        list = set.default or {}
    end

    local out = {}
    for _, p in ipairs(list) do
        if p == '*' then
            for _, all in ipairs(Config.Permissions) do out[all] = true end
        elseif p:sub(-2) == '.*' then
            -- 'view.*' grants every permission in that group
            local prefix = p:sub(1, -2)
            for _, all in ipairs(Config.Permissions) do
                if all:sub(1, #prefix) == prefix then out[all] = true end
            end
        else
            out[p] = true
        end
    end
    return out
end

--- Jobs listed in Config.IgnoredJobs never reach the MDT.
function MDT.jobIgnored(job)
    for _, name in ipairs(Config.IgnoredJobs or {}) do
        if name == job then return true end
    end
    return false
end

--- Staff access for the admin panel, by ace or ESX group.
function MDT.isStaff(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'nayzeee.mdt') then return true end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    local group = xPlayer.getGroup()
    for _, g in ipairs(Config.StaffGroups or {}) do
        if group == g then return true end
    end
    return false
end

function MDT.getSession(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not xPlayer.job then return nil end

    if MDT.jobIgnored(xPlayer.job.name) then return nil end

    local dept = MDT.getDepartment(xPlayer.job.name)
    if not dept then return nil end

    return {
        source     = src,
        identifier = xPlayer.identifier,
        name       = MDT.fullName(xPlayer),
        job        = xPlayer.job.name,
        department = xPlayer.job.name,
        deptLabel  = dept.label,
        rank       = xPlayer.job.grade_label or xPlayer.job.grade_name,
        gradeName  = xPlayer.job.grade_name,
        grade      = xPlayer.job.grade,
        staff      = MDT.isStaff(src),
        perms      = MDT.permissionsFor(xPlayer.job.name, xPlayer.job.grade_name, xPlayer.job.grade),
        xPlayer    = xPlayer
    }
end

function MDT.can(src, permission)
    local s = MDT.getSession(src)
    if not s then return false, nil end
    return s.perms[permission] == true, s
end

--- Wrap a callback so it only runs when the caller holds `permission`.
function MDT.guard(permission, fn)
    return function(src, ...)
        local ok, session = MDT.can(src, permission)
        if not ok then
            return { ok = false, msg = session and 'Your rank does not allow that.' or 'You are not on a department roster.' }
        end
        return fn(session, ...)
    end
end

-- ═══════════════════════════════════════════════════════════
--  OFFICER RECORD
-- ═══════════════════════════════════════════════════════════
function MDT.ensureOfficer(session)
    if not session then return nil end

    local row = MySQL.single.await('SELECT * FROM nz_mdt_officers WHERE identifier = ?', { session.identifier })
    if not row then
        local dept = MDT.getDepartment(session.department) or {}
        MySQL.insert.await([[
            INSERT INTO nz_mdt_officers (identifier, name, department, rank, badge, callsign)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            session.identifier, session.name, session.department, session.rank,
            ('%s-%s'):format(dept.short or 'PD', MDT.rand(4)),
            nil
        })
        row = MySQL.single.await('SELECT * FROM nz_mdt_officers WHERE identifier = ?', { session.identifier })
    elseif row.name ~= session.name or row.department ~= session.department or row.rank ~= session.rank then
        MySQL.update('UPDATE nz_mdt_officers SET name = ?, department = ?, rank = ? WHERE identifier = ?',
            { session.name, session.department, session.rank, session.identifier })
        row.name, row.department, row.rank = session.name, session.department, session.rank
    end

    return row
end

function MDT.getOfficer(identifier)
    return MySQL.single.await('SELECT * FROM nz_mdt_officers WHERE identifier = ?', { identifier })
end

--- Online entry for an identifier, if they are connected.
function MDT.onlineBy(identifier)
    for src, info in pairs(MDT.online) do
        if info.identifier == identifier then return src, info end
    end
    return nil
end

--- Everyone clocked in right now, from memory — no database round trip.
function MDT.activeOfficers(departmentFilter)
    local out = {}
    local now = os.time()
    for _, o in pairs(MDT.online) do
        if o.onDuty and (not departmentFilter or o.department == departmentFilter) then
            local pos = MDT.positions[o.identifier]
            out[#out + 1] = {
                identifier = o.identifier,
                name       = o.name,
                department = o.department,
                rank       = o.rank,
                callsign   = o.callsign,
                status     = o.status or 'available',
                onDuty     = true,
                street     = pos and pos.street or nil,
                x          = pos and pos.x or nil,
                y          = pos and pos.y or nil,
                z          = pos and pos.z or nil,
                since      = o.lastOn and math.max(0, math.floor((now - o.lastOn) / 60)) or 0
            }
        end
    end
    table.sort(out, function(a, b) return (a.callsign or a.name or '') < (b.callsign or b.name or '') end)
    return out
end

--- Sources for everyone on duty in the given departments. '*' = all.
function MDT.sourcesFor(departments)
    local wantAll = false
    local want = {}
    for _, d in ipairs(departments or {}) do
        if d == '*' then wantAll = true end
        want[d] = true
    end

    local out = {}
    for src, info in pairs(MDT.online) do
        if info.onDuty and (wantAll or want[info.department]) then
            out[#out + 1] = src
        end
    end
    return out
end

--- Keep the in-memory roster in step with a status change.
function MDT.setStatus(identifier, status)
    local _, info = MDT.onlineBy(identifier)
    if info then info.status = status end
end

-- ═══════════════════════════════════════════════════════════
--  AUDIT + DISCORD
-- ═══════════════════════════════════════════════════════════
function MDT.audit(session, action, subject, subjectId, detail)
    if not Config.Audit.enabled then return end
    MySQL.insert('INSERT INTO nz_mdt_audit (actor, actor_id, department, action, subject, subject_id, detail) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        session and session.name or 'System',
        session and session.identifier or nil,
        session and session.department or nil,
        action, subject, subjectId and tostring(subjectId):sub(1, 48) or nil,
        detail and MDT.clean(detail, 250) or nil
    })
end

function MDT.log(channel, title, description, fields)
    if not Config.Logs.enabled then return end
    local url = Config.Logs.webhooks[channel]
    if not url or url == '' then return end

    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = Config.Logs.name,
        embeds = {{
            title = title,
            description = description,
            color = Config.Logs.colour,
            fields = fields,
            footer = { text = ('%s · %s'):format(Config.Logs.name, os.date('%Y-%m-%d %H:%M:%S')) }
        }}
    }), { ['Content-Type'] = 'application/json' })
end

--- One call to record + broadcast an action.
function MDT.record(session, channel, action, subject, subjectId, title, description)
    MDT.audit(session, action, subject, subjectId, description)
    MDT.log(channel, title, description)
end

-- ═══════════════════════════════════════════════════════════
--  PUSH — keep every open tablet in sync
-- ═══════════════════════════════════════════════════════════
local function deptFilter(departments)
    if not departments then return nil end
    local want = {}
    for _, d in ipairs(departments) do
        if d == '*' then return nil end
        want[d] = true
    end
    return want
end

--- Send a live event to everyone with the tablet open (optionally by department).
function MDT.push(event, payload, departments)
    local want = deptFilter(departments)
    for src in pairs(MDT.viewers) do
        local info = MDT.online[src]
        if not want or (info and want[info.department]) then
            TriggerClientEvent('nz_mdt:live', src, event, payload)
        end
    end
end

--- Like push, but also reaches on-duty units with the tablet put away, so the
--- on-screen card and the call blips stay correct.
function MDT.broadcast(event, payload, departments)
    local want = deptFilter(departments)
    local sent = {}
    for src in pairs(MDT.viewers) do
        local info = MDT.online[src]
        if not want or (info and want[info.department]) then
            sent[src] = true
            TriggerClientEvent('nz_mdt:live', src, event, payload)
        end
    end
    for src, info in pairs(MDT.online) do
        if not sent[src] and info.onDuty and (not want or want[info.department]) then
            TriggerClientEvent('nz_mdt:live', src, event, payload)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
--  PRESENCE
-- ═══════════════════════════════════════════════════════════
local function trackPlayer(src, xPlayer)
    local previous = MDT.online[src]

    if not xPlayer or not xPlayer.job or not MDT.isLEO(xPlayer.job.name) or MDT.jobIgnored(xPlayer.job.name) then
        -- left the department while clocked in: bank the shift and take them off the board
        if previous and previous.onDuty then
            MDT.clockOut(previous.identifier)
            TriggerClientEvent('nz_mdt:dutyChanged', src, false)
        end
        MDT.online[src] = nil
        MDT.viewers[src] = nil
        return
    end

    local officer = MySQL.single.await('SELECT on_duty, callsign, status, last_on FROM nz_mdt_officers WHERE identifier = ?',
        { xPlayer.identifier })

    MDT.online[src] = {
        identifier = xPlayer.identifier,
        name       = MDT.fullName(xPlayer),
        department = xPlayer.job.name,
        rank       = xPlayer.job.grade_label or xPlayer.job.grade_name,
        callsign   = officer and officer.callsign or nil,
        onDuty     = officer and MDT.bool(officer.on_duty) or false,
        status     = officer and officer.status or 'available',
        lastOn     = officer and officer.last_on or nil
    }

    TriggerClientEvent('nz_mdt:dutyChanged', src, MDT.online[src].onDuty, MDT.online[src].status)
end

AddEventHandler('esx:playerLoaded', function(src, xPlayer)
    CreateThread(function()
        Wait(1500)
        local session = MDT.getSession(src)
        if session then MDT.ensureOfficer(session) end
        trackPlayer(src, xPlayer)
    end)
end)

AddEventHandler('esx:setJob', function(src)
    CreateThread(function()
        local session = MDT.getSession(src)
        if session then MDT.ensureOfficer(session) end
        trackPlayer(src, ESX.GetPlayerFromId(src))
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local info = MDT.online[src]
    if info then
        -- bank the shift time and clock them out
        MDT.clockOut(info.identifier, true)
        MDT.positions[info.identifier] = nil
    end
    MDT.online[src] = nil
    MDT.viewers[src] = nil
end)

RegisterNetEvent('nz_mdt:viewing', function(open)
    local src = source
    if open and MDT.online[src] then MDT.viewers[src] = true else MDT.viewers[src] = nil end
end)

--- Clients report their position while on duty so the live map works.
RegisterNetEvent('nz_mdt:position', function(x, y, z, heading, street)
    local src = source
    local info = MDT.online[src]
    if not info or not info.onDuty then return end
    if type(x) ~= 'number' or type(y) ~= 'number' then return end

    MDT.positions[info.identifier] = {
        x = x, y = y, z = tonumber(z) or 0.0, heading = tonumber(heading) or 0.0,
        street = type(street) == 'string' and street:sub(1, 48) or nil,
        at = os.time()
    }
end)

--- Cheap duty lookup for the client on start / load.
lib.callback.register('nz_mdt:duty:state', function(src)
    local info = MDT.online[src]
    if not info then return { onDuty = false } end
    return { onDuty = info.onDuty, status = info.status, identifier = info.identifier }
end)

-- boot: catch anyone already connected on a resource restart, and clock out
-- anyone the database still thinks is on duty but is not here any more
CreateThread(function()
    Wait(4000)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local session = MDT.getSession(src)
            if session then MDT.ensureOfficer(session) end
            trackPlayer(src, xPlayer)
        end
    end

    local stale = MySQL.query.await('SELECT identifier FROM nz_mdt_officers WHERE on_duty = 1') or {}
    for _, row in ipairs(stale) do
        if not MDT.onlineBy(row.identifier) then MDT.clockOut(row.identifier, true) end
    end
end)

-- audit housekeeping
CreateThread(function()
    while true do
        Wait(3600000)
        local days = Config.Audit.keepDays or Config.Audit.retentionDays or 0
        if Config.Audit.enabled and days > 0 then
            MySQL.update('DELETE FROM nz_mdt_audit WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  BOOTSTRAP PAYLOAD
-- ═══════════════════════════════════════════════════════════
local function mapStylesFor()
    if Config.Map.allowStyleSwitch then return Config.Map.styles end
    for _, s in ipairs(Config.Map.styles) do
        if s.id == Config.Map.style then return { s } end
    end
    return { { id = 'grid', label = 'Grid', file = false } }
end

lib.callback.register('nz_mdt:boot', function(src)
    local session = MDT.getSession(src)
    if not session then return nil end

    local officer = MDT.ensureOfficer(session)
    local dept = MDT.getDepartment(session.department) or {}
    if not MDT.online[src] then trackPlayer(src, session.xPlayer) end

    local perms = {}
    for k in pairs(session.perms) do perms[#perms + 1] = k end

    local tablet = Config.Tablet or {}

    return {
        me = {
            identifier = session.identifier,
            name       = session.name,
            department = session.department,
            deptLabel  = dept.label,
            deptShort  = dept.short,
            deptSub    = dept.sub,
            rank       = session.rank,
            badge      = officer and officer.badge or nil,
            callsign   = officer and officer.callsign or nil,
            onDuty     = officer and MDT.bool(officer.on_duty) or false,
            status     = officer and officer.status or 'available',
            dutySeconds= officer and officer.duty_seconds or 0,
            medical    = dept.medical == true
        },
        perms  = perms,
        config = {
            version     = GetResourceMetadata(GetCurrentResourceName(), 'version', 0),
            currency    = Config.Currency,
            callTypes   = Config.CallTypes,
            unitStatus  = Config.UnitStatus,
            charges     = Config.Charges,
            chargeClasses = Config.ChargeClasses,
            warrantTypes= Config.Warrant.types,
            evidenceTypes = Config.Evidence.types,
            lockers     = Config.Evidence.lockers,
            licences    = Config.Registry.licences,
            mapBounds   = Config.Map.bounds,
            mapEnabled  = Config.Map.enabled,
            mapStyle    = Config.Map.style,
            mapStyles   = mapStylesFor(),
            maxUnits    = Config.Dispatch.maxUnitsPerCall,
            emergency   = dept.emergencyNumber or '911',
            departments = Config.Departments,
            linkTypes   = Config.Links.enabled and Config.Links.types or {},
            weaponList  = Config.WeaponList,
            photos      = Config.Photos.enabled == true,
            cameraModels= Config.Cameras.models,
            staff       = session.staff == true,
            statsDays   = Config.Incident.statsDays or 30,
            maxCharges  = Config.Incident.maxCharges,
            maxCitizens = Config.Incident.maxCitizens,
            bulletinDays= Config.Announcement and Config.Announcement.expireDays or 7,
            panicEnabled= Config.Panic.enabled == true,
            backupForAll= Config.Backup and Config.Backup.enabled and not Config.Backup.requirePerm or false,
            tenCodes    = Config.TenCodes or {},
            tablet      = {
                lockScreen = tablet.lockScreen or 'first',
                wallpaper  = tablet.wallpaper,
                wallpapers = tablet.wallpapers
            }
        }
    }
end)

-- ═══════════════════════════════════════════════════════════
--  ITEM ACCESS
--  Works with ox_inventory, qs-inventory and plain ESX counts.
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:item:check', function(src)
    local cfg = Config.Access.item
    if not cfg or not cfg.enabled then return true end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    local count = 0

    if GetResourceState('ox_inventory') == 'started' then
        count = exports.ox_inventory:GetItemCount(src, cfg.name) or 0
    elseif GetResourceState('qs-inventory') == 'started' then
        count = exports['qs-inventory']:GetItemTotalAmount(src, cfg.name) or 0
    else
        local item = xPlayer.getInventoryItem(cfg.name)
        count = item and item.count or 0
    end

    if count < 1 then return false end

    if cfg.consume then
        if GetResourceState('ox_inventory') == 'started' then
            exports.ox_inventory:RemoveItem(src, cfg.name, 1)
        elseif GetResourceState('qs-inventory') == 'started' then
            exports['qs-inventory']:RemoveItem(src, cfg.name, 1)
        else
            xPlayer.removeInventoryItem(cfg.name, 1)
        end
    end

    return true
end)

-- Let the item itself open the tablet.
CreateThread(function()
    Wait(1500)
    local cfg = Config.Access.item
    if not cfg or not cfg.enabled then return end

    if GetResourceState('ox_inventory') == 'started' then
        pcall(function()
            exports.ox_inventory:registerHook('usingItem', function(payload)
                if payload.item and payload.item.name == cfg.name then
                    TriggerClientEvent('nz_mdt:openFromItem', payload.source)
                    return false
                end
            end, { itemFilter = { [cfg.name] = true } })
        end)
    else
        -- ESX and qs-inventory both honour ESX usable items
        pcall(function()
            ESX.RegisterUsableItem(cfg.name, function(src)
                TriggerClientEvent('nz_mdt:openFromItem', src)
            end)
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  EXPORTS
-- ═══════════════════════════════════════════════════════════
exports('isOnDuty', function(src)
    local info = MDT.online[tonumber(src)]
    return info ~= nil and info.onDuty == true
end)

exports('getOfficer', function(src)
    local info = MDT.online[tonumber(src)]
    if not info then return nil end
    return {
        identifier = info.identifier, name = info.name, department = info.department,
        rank = info.rank, callsign = info.callsign, onDuty = info.onDuty, status = info.status
    }
end)

exports('onDutyCount', function(department)
    local n = 0
    for _, info in pairs(MDT.online) do
        if info.onDuty and (not department or info.department == department) then n = n + 1 end
    end
    return n
end)
