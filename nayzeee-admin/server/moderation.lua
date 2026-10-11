NZ.Bans, NZ.BanIndex = {}, {}   -- id -> ban | identifier/token -> id
NZ.Jailed = {}                   -- src -> jail session

local skip = {}
for _, k in ipairs(Config.Bans.SkipIdentifiers) do skip[k] = true end

local function indexBan(b)
    NZ.Bans[b.id] = b
    for _, i in ipairs(b.identifiers) do NZ.BanIndex[i] = b.id end
    for _, t in ipairs(b.tokens) do NZ.BanIndex[t] = b.id end
end

local function unindexBan(id)
    local b = NZ.Bans[id]; if not b then return end
    for k, v in pairs(NZ.BanIndex) do if v == id then NZ.BanIndex[k] = nil end end
    NZ.Bans[id] = nil
end

AddEventHandler('nzadmin:sv:booted', function()
    local rows = MySQL.query.await('SELECT id, name, license, identifiers, tokens, reason, staff_name, UNIX_TIMESTAMP(expires_at) AS expires FROM nz_admin_bans WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW())') or {}
    for _, r in ipairs(rows) do
        indexBan({ id = r.id, name = r.name, license = r.license, reason = r.reason, staff = r.staff_name, expires = r.expires,
            identifiers = json.decode(r.identifiers) or {}, tokens = json.decode(r.tokens) or {} })
    end
    MySQL.update('UPDATE nz_admin_bans SET active = 0 WHERE active = 1 AND expires_at IS NOT NULL AND expires_at <= NOW()')
end)

local function banMessage(b)
    return Config.Bans.Message:format(b.reason, b.expires and os.date('%Y-%m-%d %H:%M', b.expires) or 'Never', b.id)
end

local function findBan(identifiers, tokens)
    for _, list in ipairs({ identifiers, tokens }) do
        for _, i in ipairs(list) do
            local id = NZ.BanIndex[i]
            if id then
                local b = NZ.Bans[id]
                if b and b.expires and b.expires <= os.time() then unindexBan(id); MySQL.update('UPDATE nz_admin_bans SET active = 0 WHERE id = ?', { id })
                elseif b then return b end
            end
        end
    end
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Checking ban list...')
    local ids, toks = {}, {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do ids[#ids + 1] = GetPlayerIdentifier(src, i) end
    for i = 0, GetNumPlayerTokens(src) - 1 do toks[#toks + 1] = GetPlayerToken(src, i) end
    local b = findBan(ids, Config.Bans.UseTokens and toks or {})
    Wait(0)
    if b then deferrals.done(banMessage(b)) else deferrals.done() end
end)

local function collect(src)
    local ids, toks = {}, {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        local kind = id and id:match('^(%w+):')
        if kind and not skip[kind] then ids[#ids + 1] = id end
    end
    if Config.Bans.UseTokens then for i = 0, GetNumPlayerTokens(src) - 1 do toks[#toks + 1] = GetPlayerToken(src, i) end end
    return ids, toks
end

--- Create a ban. info = { name, license, identifiers, tokens, reason, duration (seconds or nil for perm) }
function NZ.CreateBan(staff, info)
    local expires = info.duration and (os.time() + info.duration) or nil
    local sName = type(staff) == 'number' and (staff == 0 and 'Console' or NZ.Name(staff)) or (staff and staff.name) or 'System'
    local sLic = type(staff) == 'number' and staff ~= 0 and NZ.License(staff) or nil
    local id = MySQL.insert.await('INSERT INTO nz_admin_bans (name, license, identifiers, tokens, reason, expires_at, staff_name, staff_license) VALUES (?, ?, ?, ?, ?, IF(? IS NULL, NULL, FROM_UNIXTIME(?)), ?, ?)',
        { info.name, info.license, json.encode(info.identifiers), json.encode(info.tokens or {}), info.reason, expires, expires, sName, sLic })
    local b = { id = id, name = info.name, license = info.license, reason = info.reason, staff = sName, expires = expires, identifiers = info.identifiers, tokens = info.tokens or {} }
    indexBan(b)
    TriggerEvent('nzadmin:server:playerBanned', b)
    if Hooks and Hooks.OnBan then pcall(Hooks.OnBan, b) end
    return b
end

function NZ.Ban(src, id, reason, duration)
    local tid, err = NZ.Target(src, id); if not tid then return false, err end
    if tid == src then return false, 'You cannot ban yourself.' end
    reason = NZ.Trim(reason, 250); if reason == '' then reason = 'No reason given' end
    local ids, toks = collect(tid)
    local b = NZ.CreateBan(src, { name = GetPlayerName(tid), license = NZ.License(tid), identifiers = ids, tokens = toks, reason = reason, duration = duration })
    NZ.Log('moderation', 'ban', src, tid, ('banned for %s: %s'):format(NZ.FormatDuration(duration), reason))
    DropPlayer(tid, banMessage(b))
    return b.id
end

function NZ.Kick(src, id, reason)
    local tid, err = NZ.Target(src, id); if not tid then return false, err end
    if tid == src then return false, 'You cannot kick yourself.' end
    reason = NZ.Trim(reason, 250); if reason == '' then reason = 'No reason given' end
    NZ.Log('moderation', 'kick', src, tid, 'kicked: ' .. reason)
    DropPlayer(tid, ('Kicked by %s\nReason: %s'):format(NZ.Name(src), reason))
    return true
end

function NZ.Warn(src, id, reason)
    local tid, err = NZ.Target(src, id); if not tid then return false, err end
    reason = NZ.Trim(reason, 250); if reason == '' then return false, 'Give a reason.' end
    local lic = NZ.License(tid)
    MySQL.insert.await('INSERT INTO nz_admin_warnings (license, name, reason, staff_name, staff_license) VALUES (?, ?, ?, ?, ?)',
        { lic, GetPlayerName(tid), reason, NZ.Name(src), src ~= 0 and NZ.License(src) or nil })
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_warnings WHERE license = ?', { lic }) or 1
    TriggerClientEvent('nzadmin:cl:warned', tid, { reason = reason, staff = NZ.Name(src), count = count, max = Config.Warnings.MaxBeforeBan, seconds = Config.Warnings.ScreenSeconds })
    NZ.Log('moderation', 'warn', src, tid, ('warning %d: %s'):format(count, reason))
    if Hooks and Hooks.OnWarn then pcall(Hooks.OnWarn, tid, reason, count) end
    local max = Config.Warnings.MaxBeforeBan
    if max > 0 and count >= max then
        local lic2 = lic
        SetTimeout(Config.Warnings.ScreenSeconds * 1000, function()
            -- same person still on that id (ids get reused after a drop)
            if GetPlayerName(tid) and NZ.License(tid) == lic2 then
                local dur = NZ.ParseDuration(Config.Warnings.AutoBanDuration)
                NZ.Ban(0, tid, Config.Warnings.AutoBanReason, dur ~= false and dur or nil)
            end
        end)
    end
    return true
end

NZ.Route('player:kick', 'player.kick', function(src, d)
    local ok, err = NZ.Kick(src, d.id, d.reason)
    if not ok then return false, err or 'Could not kick that player.' end
    return true
end)
NZ.Route('player:warn', 'player.warn', function(src, d)
    local ok, err = NZ.Warn(src, d.id, d.reason)
    if not ok then return false, err or 'Could not warn that player.' end
    return true
end)

NZ.Route('player:ban', 'player.ban', function(src, d)
    local dur = NZ.ParseDuration(d.duration)
    if dur == false then return false, 'Invalid duration. Use 1d2h30m or perm.' end
    local id, err = NZ.Ban(src, d.id, d.reason, dur)
    if not id then return false, err or 'Could not ban that player.' end
    return id
end)

--- Hierarchy for a license that may be offline (staff member table).
local function licenseHierarchy(lic)
    for s, st in pairs(NZ.Staff) do if st.license == lic then return NZ.Hierarchy(s) end end
    local m = MySQL.single.await('SELECT group_name FROM nz_admin_members WHERE license = ?', { lic })
    local g = m and NZ.Groups[m.group_name]
    return g and g.hierarchy or 0
end

NZ.Route('offline:ban', 'offline_player.ban', function(src, d)
    local lic = NZ.Trim(d.license, 64)
    if not lic:find(':') then return false, 'Enter a full identifier, like license:abc...' end
    local dur = NZ.ParseDuration(d.duration)
    if dur == false then return false, 'Invalid duration.' end
    if src ~= 0 and Config.HierarchyProtection then
        local th = licenseHierarchy(lic)
        if th > 0 and th >= NZ.Hierarchy(src) then return false, 'That staff member is above you.' end
    end
    local seen = MySQL.single.await('SELECT name, discord FROM nz_admin_players WHERE license = ?', { lic })
    local ids = { lic }
    if seen and seen.discord then ids[#ids + 1] = 'discord:' .. seen.discord end
    local reason = NZ.Trim(d.reason, 250); if reason == '' then reason = 'No reason given' end
    local name = NZ.Trim(d.name, 128); if name == '' then name = (seen and seen.name) or lic end
    local b = NZ.CreateBan(src, { name = name, license = lic, identifiers = ids, reason = reason, duration = dur })
    NZ.Log('moderation', 'ban_offline', src, { name = b.name, license = lic }, ('banned offline for %s: %s'):format(NZ.FormatDuration(dur), b.reason))
    -- they may be online after all (license typed by hand)
    for id, o in pairs(NZ.Online) do
        if o.license == lic and id ~= src then DropPlayer(id, banMessage(b)) end
    end
    return b.id
end)

NZ.Route('ban:remove', 'player.unban', function(src, d)
    local id = tonumber(d.id); if not id then return false end
    local row = MySQL.single.await('SELECT name, license FROM nz_admin_bans WHERE id = ?', { id }); if not row then return false, 'Ban not found.' end
    MySQL.update.await('UPDATE nz_admin_bans SET active = 0 WHERE id = ?', { id })
    unindexBan(id)
    TriggerEvent('nzadmin:server:playerUnbanned', id)
    if Hooks and Hooks.OnUnban then pcall(Hooks.OnUnban, id) end
    NZ.Log('moderation', 'unban', src, { name = row.name, license = row.license }, 'unbanned ban #' .. id)
    return true
end)

NZ.Route('ban:edit', 'player.ban', function(src, d)
    local id = tonumber(d.id); if not id then return false end
    local row = MySQL.single.await('SELECT id, name, license, identifiers, tokens, reason, staff_name, active, UNIX_TIMESTAMP(expires_at) AS expires FROM nz_admin_bans WHERE id = ?', { id })
    if not row then return false, 'Ban not found.' end
    local reason = NZ.Trim(d.reason, 250); if reason == '' then reason = row.reason end
    local expires = row.expires -- blank duration keeps the current expiry
    if d.duration ~= nil and NZ.Trim(d.duration) ~= '' then
        local dur = NZ.ParseDuration(d.duration)
        if dur == false then return false, 'Invalid duration. Use 1d2h30m or perm.' end
        expires = dur and (os.time() + dur) or nil
    end
    MySQL.update.await('UPDATE nz_admin_bans SET reason = ?, expires_at = IF(? IS NULL, NULL, FROM_UNIXTIME(?)) WHERE id = ?', { reason, expires, expires, id })
    unindexBan(id)
    if NZ.IsTrue(row.active) and (not expires or expires > os.time()) then
        indexBan({ id = id, name = row.name, license = row.license, reason = reason, staff = row.staff_name, expires = expires,
            identifiers = json.decode(row.identifiers or '[]') or {}, tokens = json.decode(row.tokens or '[]') or {} })
    end
    NZ.Log('moderation', 'ban_edit', src, { name = row.name, license = row.license }, ('edited ban #%d · %s · %s'):format(id, expires and ('until ' .. os.date('%Y-%m-%d %H:%M', expires)) or 'permanent', reason))
    return true
end)

NZ.Route('warning:remove', 'player.warn_remove', function(src, d)
    local id = tonumber(d.id); if not id then return false end
    local row = MySQL.single.await('SELECT name, license, reason FROM nz_admin_warnings WHERE id = ?', { id })
    if not row then return false, 'Warning not found.' end
    MySQL.update.await('DELETE FROM nz_admin_warnings WHERE id = ?', { id })
    NZ.Log('moderation', 'warning_removed', src, { name = row.name, license = row.license }, ('removed warning #%d: %s'):format(id, row.reason))
    return true
end)

NZ.Route('moderation:bans', 'moderation.view.bans', function(src, d)
    local q = '%' .. (d.search or '') .. '%'
    return MySQL.query.await([[SELECT id, name, license, reason, staff_name, active, UNIX_TIMESTAMP(expires_at) AS expires, UNIX_TIMESTAMP(created_at) AS time
        FROM nz_admin_bans WHERE (name LIKE ? OR license LIKE ? OR reason LIKE ? OR id = ?) ORDER BY id DESC LIMIT 200]], { q, q, q, tonumber(d.search) or 0 })
end)

NZ.Route('moderation:warnings', 'moderation.view.warnings', function(src, d)
    local q = '%' .. (d.search or '') .. '%'
    return MySQL.query.await([[SELECT id, name, license, reason, staff_name, UNIX_TIMESTAMP(created_at) AS time
        FROM nz_admin_warnings WHERE (name LIKE ? OR license LIKE ? OR reason LIKE ?) ORDER BY id DESC LIMIT 200]], { q, q, q })
end)

-- ═══ jail ═══════════════════════════════════════════════════════════════
local function cellByName(name)
    for _, c in ipairs(Config.Jail.Cells) do if c.name == name then return c end end
    return Config.Jail.Cells[1]
end

local function freeCell()
    local used = {}
    for _, j in pairs(NZ.Jailed) do used[j.cell] = (used[j.cell] or 0) + 1 end
    local best, n = Config.Jail.Cells[1], math.huge
    for _, c in ipairs(Config.Jail.Cells) do if (used[c.name] or 0) < n then best, n = c, used[c.name] or 0 end end
    return best
end

function NZ.JailInfo(src)
    local j = NZ.Jailed[src]; if not j then return nil end
    local left = j.mode == 'date' and math.max(0, j.expires - os.time()) or j.remaining
    return { reason = j.reason, cell = j.cell, remaining = left, staff = j.staff, mode = j.mode }
end

local countdown -- started on demand, see below

local function startJail(src, j)
    NZ.Jailed[src] = j
    countdown()
    local c = cellByName(j.cell)
    TriggerClientEvent('nzadmin:cl:jail', src, { cell = { x = c.coords.x, y = c.coords.y, z = c.coords.z, w = c.coords.w, radius = c.radius }, info = NZ.JailInfo(src) })
end

function NZ.Release(src, by)
    local j = NZ.Jailed[src]; if not j then return false end
    NZ.Jailed[src] = nil
    MySQL.update.await('DELETE FROM nz_admin_jail WHERE char_id = ?', { j.charId })
    local back = j.lastCoords or { x = Config.Jail.ReleaseAt.x, y = Config.Jail.ReleaseAt.y, z = Config.Jail.ReleaseAt.z, w = Config.Jail.ReleaseAt.w }
    TriggerClientEvent('nzadmin:cl:jail', src, false, back)
    NZ.Log('moderation', 'jail_release', by, src, by and 'released from jail' or 'sentence served')
    return true
end

function NZ.Jail(src, id, duration, reason)
    local tid, err = NZ.Target(src, id); if not tid then return false, err or 'Player not found.' end
    if not Config.Jail.Enabled then return false, 'Jail is turned off.' end
    if NZ.Jailed[tid] then return false, 'Already jailed.' end
    if not duration then return false, 'Jail needs a duration.' end
    reason = NZ.Trim(reason, 250); if reason == '' then reason = 'No reason given' end
    local cell = freeCell()
    local c = NZ.CoordsOf(tid)
    local j = { charId = Bridge.CharId(tid), cell = cell.name, reason = reason, staff = NZ.Name(src), mode = Config.Jail.TimeMode,
        remaining = duration, expires = os.time() + duration, lastCoords = c }
    MySQL.insert.await([[INSERT INTO nz_admin_jail (char_id, license, name, reason, cell, last_coords, time_mode, duration, remaining, expires_at, staff_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?) ON DUPLICATE KEY UPDATE license = VALUES(license), name = VALUES(name), reason = VALUES(reason), cell = VALUES(cell),
        last_coords = VALUES(last_coords), time_mode = VALUES(time_mode), duration = VALUES(duration), remaining = VALUES(remaining), expires_at = VALUES(expires_at), staff_name = VALUES(staff_name), created_at = NOW()]],
        { j.charId, NZ.License(tid), GetPlayerName(tid), reason, cell.name, json.encode(c), j.mode, duration, duration, j.expires, j.staff })
    startJail(tid, j)
    NZ.Log('moderation', 'jail', src, tid, ('jailed for %s: %s'):format(NZ.FormatDuration(duration), reason))
    return true
end

NZ.Route('player:jail', 'player.jail', function(src, d)
    local dur = NZ.ParseDuration(d.duration)
    if not dur then return false, 'Invalid duration. Use 30m, 2h, 1d...' end
    return NZ.Jail(src, d.id, dur, d.reason)
end)

NZ.Route('player:unjail', 'player.jail_remove', function(src, d)
    local tid = tonumber(d.id)
    if tid and NZ.Jailed[tid] then return NZ.Release(tid, src) end
    if d.charId then -- offline row
        MySQL.update.await('DELETE FROM nz_admin_jail WHERE char_id = ?', { d.charId })
        NZ.Log('moderation', 'jail_release', src, { name = d.name, license = d.license }, 'released offline jail')
        return true
    end
    return false, 'Not jailed.'
end)

NZ.Route('moderation:jail', 'moderation.view.jail', function()
    local rows = MySQL.query.await('SELECT char_id, license, name, reason, cell, time_mode, duration, remaining, UNIX_TIMESTAMP(expires_at) AS expires, staff_name, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_jail ORDER BY created_at DESC') or {}
    for _, r in ipairs(rows) do
        for src, j in pairs(NZ.Jailed) do
            if j.charId == r.char_id then r.online = src; r.remaining = NZ.JailInfo(src).remaining end
        end
        if r.time_mode == 'date' and not r.online then r.remaining = math.max(0, r.expires - os.time()) end
    end
    return rows
end)

--- Called once the character is loaded so the jail row is found by character id.
local checking = {}
function NZ.CheckJail(src)
    src = tonumber(src)
    if not src or not Config.Jail.Enabled or NZ.Jailed[src] or checking[src] then return end
    if not GetPlayerName(src) then return end
    local charId = Bridge.CharId(src); if not charId then return end
    checking[src] = true
    local r = MySQL.single.await('SELECT *, UNIX_TIMESTAMP(expires_at) AS exp FROM nz_admin_jail WHERE char_id = ?', { charId })
    checking[src] = nil
    if not r or NZ.Jailed[src] or not GetPlayerName(src) then return end
    if r.time_mode == 'date' and (r.exp or 0) <= os.time() then
        MySQL.update('DELETE FROM nz_admin_jail WHERE char_id = ?', { charId }); return
    end
    local last = nil
    if r.last_coords then local ok, c = pcall(json.decode, r.last_coords); if ok then last = c end end
    startJail(src, { charId = charId, cell = r.cell, reason = r.reason, staff = r.staff_name, mode = r.time_mode,
        remaining = r.remaining, expires = r.exp, lastCoords = last })
end

AddEventHandler('esx:playerLoaded', function(src) SetTimeout(2000, function() NZ.CheckJail(src) end) end)
AddEventHandler('QBCore:Server:PlayerLoaded', function(p) local s = p and p.PlayerData and p.PlayerData.source; if s then SetTimeout(2000, function() NZ.CheckJail(s) end) end end)
RegisterNetEvent('nzadmin:sv:loaded', function() local s = source; SetTimeout(1500, function() NZ.CheckJail(s) end) end)
-- standalone has no "character loaded" event, the client ready ping is the earliest safe point
AddEventHandler('nzadmin:sv:clientReady', function(src) SetTimeout(1500, function() NZ.CheckJail(src) end) end)
AddEventHandler('nzadmin:sv:booted', function()
    for _, id in ipairs(GetPlayers()) do NZ.CheckJail(tonumber(id)) end
end)

-- countdown: one timer that only exists while someone is jailed
local ticking = false
countdown = function()
    if ticking then return end
    ticking = true
    CreateThread(function()
        local tick, save = 10, 0
        while next(NZ.Jailed) do
            Wait(tick * 1000)
            save = save + tick
            local done = {}
            for src, j in pairs(NZ.Jailed) do
                if j.mode == 'playtime' then j.remaining = math.max(0, j.remaining - tick) end
                local left = j.mode == 'date' and (j.expires - os.time()) or j.remaining
                if left <= 0 then done[#done + 1] = src
                elseif save >= 60 and j.mode == 'playtime' then MySQL.update('UPDATE nz_admin_jail SET remaining = ? WHERE char_id = ?', { j.remaining, j.charId }) end
            end
            for _, src in ipairs(done) do NZ.Release(src) end
            if save >= 60 then save = 0 end
        end
        ticking = false
    end)
end

RegisterNetEvent('nzadmin:sv:sentence', function()
    local src = source
    local info = NZ.JailInfo(src)
    TriggerClientEvent('nzadmin:cl:sentence', src, info)
end)

AddEventHandler('nzadmin:sv:dropped', function(src)
    local j = NZ.Jailed[src]
    if j then
        if j.mode == 'playtime' then MySQL.update('UPDATE nz_admin_jail SET remaining = ? WHERE char_id = ?', { j.remaining, j.charId }) end
        NZ.Jailed[src] = nil
    end
end)

-- ─── exports ────────────────────────────────────────────────────────────
exports('BanPlayer', function(src, reason, duration, by) return NZ.Ban(by or 0, src, reason, NZ.ParseDuration(duration)) end)
exports('CreateBan', function(info) return NZ.CreateBan(0, info) end)
exports('RemoveBan', function(id)
    id = tonumber(id); if not id then return false end
    local changed = MySQL.update.await('UPDATE nz_admin_bans SET active = 0 WHERE id = ? AND active = 1', { id }) or 0
    unindexBan(id)
    if changed > 0 then
        TriggerEvent('nzadmin:server:playerUnbanned', id)
        if Hooks and Hooks.OnUnban then pcall(Hooks.OnUnban, id) end
        NZ.Log('moderation', 'unban', 0, nil, 'unbanned ban #' .. id .. ' (export)')
    end
    return changed > 0
end)
exports('WarnPlayer', function(src, reason, by) return NZ.Warn(by or 0, src, reason) end)
exports('JailPlayer', function(src, duration, reason, by) local d = NZ.ParseDuration(duration); return NZ.Jail(by or 0, src, d or nil, reason) end)
exports('UnjailPlayer', function(src) return NZ.Release(tonumber(src)) end)
exports('IsJailed', function(src) return NZ.Jailed[tonumber(src)] ~= nil end)
