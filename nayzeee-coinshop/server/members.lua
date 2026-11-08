if not NAYZEEE_LOCK_OK then return end

--[[
    Memberships: packages that grant an ACE group (group.<name>) for a number of days.
    Buying again adds the days on top of the time left. Groups are put back after a server restart,
    and removed when the time runs out. They apply to the player's account (license).
]]

Members = {}

local ADMIN = { admin = true }
local RES = GetCurrentResourceName()

function Members.CanAce()
    return IsPrincipalAceAllowed('resource.' .. RES, 'command.add_principal') and IsPrincipalAceAllowed('resource.' .. RES, 'command.remove_principal')
end

-- Both values go into a console command, so only plain characters are allowed
local function safeGroup(g) return type(g) == 'string' and #g <= 60 and g:match('^[%w_%-%.]+$') ~= nil end
local function safeLicense(l) return type(l) == 'string' and #l <= 80 and l:match('^[%w]+:[%w]+$') ~= nil end

local function addPrincipal(license, group)
    if safeLicense(license) and safeGroup(group) then ExecuteCommand(('add_principal identifier.%s group.%s'):format(license, group)) end
end

local function removePrincipal(license, group)
    if safeLicense(license) and safeGroup(group) then ExecuteCommand(('remove_principal identifier.%s group.%s'):format(license, group)) end
end

-- Give (or extend) a membership. Returns true when it was granted.
function Members.Grant(src, it, days)
    local id = Identify(src)
    if not id then return false end
    local license = GetPlayerIdentifierByType(src, 'license')
    local group = it.aceGroup and it.aceGroup ~= '' and it.aceGroup or nil
    if group then
        if not safeGroup(group) then Log('^1Membership %s has an invalid ACE group "%s"^0', it.id, tostring(group)) return false end
        if not Members.CanAce() then
            Log('^1Membership %s not given: add these lines to server.cfg^0\n    add_ace resource.%s command.add_principal allow\n    add_ace resource.%s command.remove_principal allow', it.id, RES, RES)
            return false
        end
        if not safeLicense(license) then return false end
    end
    days = math.max(1, math.floor(tonumber(days) or tonumber(it.days) or 30))
    -- expires_at is set before ended so an expired membership restarts from now
    MySQL.insert.await([[INSERT INTO nayzeee_coinshop_memberships (identifier, license, item_id, name, ace_group, expires_at, ended)
        VALUES (?, ?, ?, ?, ?, NOW() + INTERVAL ? DAY, 0)
        ON DUPLICATE KEY UPDATE license = VALUES(license), name = VALUES(name), ace_group = VALUES(ace_group),
            expires_at = IF(ended = 0 AND expires_at > NOW(), expires_at, NOW()) + INTERVAL ? DAY, ended = 0]],
        { id, license, it.id, it.name, group, days, days })
    if group then addPrincipal(license, group) end
    local expires = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(expires_at) FROM nayzeee_coinshop_memberships WHERE identifier = ? AND item_id = ?', { id, it.id })
    TriggerEvent('nayzeee-coinshop:membershipStarted', src, id, it.id, expires)
    return true
end

-- End every membership whose time is up
function Members.Expire()
    local rows = MySQL.query.await([[SELECT id, identifier, license, item_id, name, ace_group FROM nayzeee_coinshop_memberships
        WHERE ended = 0 AND expires_at <= NOW()]]) or {}
    for _, r in ipairs(rows) do
        local n = MySQL.update.await('UPDATE nayzeee_coinshop_memberships SET ended = 1 WHERE id = ? AND ended = 0 AND expires_at <= NOW()', { r.id })
        if n == 1 then
            if r.ace_group and r.license then
                local still = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM nayzeee_coinshop_memberships
                    WHERE license = ? AND ace_group = ? AND ended = 0 AND expires_at > NOW()]], { r.license, r.ace_group })) or 0
                if still == 0 then removePrincipal(r.license, r.ace_group) end
            end
            local src = Core.Online[r.identifier]
            if src then Notify(src, T('N_MEMBER_ENDED', r.name or r.item_id), 'inform') end
            TriggerEvent('nayzeee-coinshop:membershipEnded', src, r.identifier, r.item_id)
        end
    end
end

-- add_principal does not survive a restart, so put active groups back
function Members.Restore()
    for _, r in ipairs(MySQL.query.await([[SELECT DISTINCT license, ace_group FROM nayzeee_coinshop_memberships
        WHERE ended = 0 AND expires_at > NOW() AND ace_group IS NOT NULL]]) or {}) do
        addPrincipal(r.license, r.ace_group)
    end
end

function Members.ForPlayer(id)
    local rows = MySQL.query.await([[SELECT id, item_id AS itemId, name, ended, TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS remaining,
        UNIX_TIMESTAMP(expires_at) AS expires FROM nayzeee_coinshop_memberships
        WHERE identifier = ? AND (ended = 0 OR expires_at > NOW() - INTERVAL 30 DAY) ORDER BY ended ASC, expires_at DESC]], { id }) or {}
    for _, r in ipairs(rows) do
        r.remaining = math.max(0, tonumber(r.remaining) or 0)
        r.active = (r.ended == 0 or r.ended == false) and r.remaining > 0
        r.ended = nil
        local it = Catalog.Get(r.itemId)
        r.perks = it and it.perks or {}
        r.image = it and it.images[1] or nil
    end
    return rows
end

AddEventHandler('nzc:dbReady', function()
    local used = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM nayzeee_coinshop_items WHERE category = 'membership' AND ace_group IS NOT NULL AND ace_group <> '']])) or 0
    if used > 0 and not Members.CanAce() then
        Log('^3Membership packages need these lines in server.cfg to give ACE groups:^0\n    add_ace resource.%s command.add_principal allow\n    add_ace resource.%s command.remove_principal allow', RES, RES)
    end
    Members.Expire()
    Members.Restore()
    CreateThread(function()
        while true do
            Wait(math.max(10, Config.Memberships.CheckEvery or 60) * 1000)
            Members.Expire()
        end
    end)
end)

-- ── exports for other resources ─────────────────────────────────────────
-- exports['nayzeee-coinshop']:HasMembership(source, 'vip_monthly')  -> true / false
exports('HasMembership', function(src, itemId)
    local id = Identify(tonumber(src) or -1)
    if not id then return false end
    return (tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM nayzeee_coinshop_memberships
        WHERE identifier = ? AND item_id = ? AND ended = 0 AND expires_at > NOW()]], { id, tostring(itemId) })) or 0) > 0
end)
-- exports['nayzeee-coinshop']:GetMemberships(source)  -> { { itemId, name, remaining (seconds), active }, ... }
exports('GetMemberships', function(src)
    local id = Identify(tonumber(src) or -1)
    return id and Members.ForPlayer(id) or {}
end)

-- ── admin ───────────────────────────────────────────────────────────────
Handle('admin:members', function(_, _, d)
    local q = NZC.Trim(d.q)
    local like = '%' .. q:gsub('[%%_]', '') .. '%'
    local rows = MySQL.query.await([[SELECT m.id, m.identifier, w.name AS player, m.item_id AS itemId, m.name, m.ace_group AS aceGroup, m.ended,
        TIMESTAMPDIFF(SECOND, NOW(), m.expires_at) AS remaining, UNIX_TIMESTAMP(m.created_at) AS created
        FROM nayzeee_coinshop_memberships m LEFT JOIN nayzeee_coinshop_wallets w ON w.identifier = m.identifier
        WHERE (? = '' OR w.name LIKE ? OR m.identifier LIKE ? OR m.name LIKE ? OR m.ace_group LIKE ?)
        ORDER BY m.ended ASC, m.expires_at DESC LIMIT 150]], { q, like, like, like, like }) or {}
    for _, r in ipairs(rows) do
        r.remaining = math.max(0, tonumber(r.remaining) or 0)
        r.active = (r.ended == 0 or r.ended == false) and r.remaining > 0
        r.online = Core.Online[r.identifier] ~= nil
        r.ended = nil
    end
    return { rows = rows, aceReady = Members.CanAce() }
end, ADMIN)

Handle('admin:member:extend', function(src, _, d)
    local days = NZC.Int(d.days, 1, 3650, 7)
    local id = tonumber(d.id) or 0
    local n = MySQL.update.await([[UPDATE nayzeee_coinshop_memberships SET expires_at = GREATEST(expires_at, NOW()) + INTERVAL ? DAY, ended = 0
        WHERE id = ?]], { days, id })
    if n ~= 1 then return nil, 'ERR_NOT_FOUND' end
    local r = MySQL.single.await('SELECT identifier, license, ace_group, name FROM nayzeee_coinshop_memberships WHERE id = ?', { id })
    if r and r.ace_group then addPrincipal(r.license, r.ace_group) end
    local t = r and Core.Online[r.identifier]
    if t then Notify(t, T('N_MEMBER_EXTENDED', r.name, days), 'success') end
    AdminLog(src, T('LOG_MEMBER_EXTENDED'), { { 'Membership', ('%s (#%d)'):format(r and r.name or '?', id) }, { 'Player', r and r.identifier or '?' }, { 'Days', days } })
    return true
end, ADMIN)

Handle('admin:member:end', function(src, _, d)
    local id = tonumber(d.id) or 0
    local n = MySQL.update.await('UPDATE nayzeee_coinshop_memberships SET expires_at = NOW() WHERE id = ? AND ended = 0', { id })
    if n ~= 1 then return nil, 'ERR_NOT_FOUND' end
    Members.Expire()
    AdminLog(src, T('LOG_MEMBER_ENDED'), { { 'Membership', '#' .. id } })
    return true
end, ADMIN)

Handle('admin:member:grant', function(src, _, d)
    local target = tonumber(d.target)
    if not target or not GetPlayerName(target) or not Identify(target) then return nil, 'ERR_TARGET_OFFLINE' end
    local it = Catalog.Get(d.itemId)
    if not it or it.category ~= Categories.MEMBERSHIP then return nil, 'ERR_ITEM_NOT_FOUND' end
    local days = NZC.Int(d.days, 1, 3650, it.days or 30)
    if not Members.Grant(target, it, days) then return nil, 'ERR_DELIVERY' end
    Notify(target, T('N_MEMBER_GRANTED', it.name, days), 'success')
    AdminLog(src, T('LOG_MEMBER_GRANTED'), { { 'Membership', it.name }, { 'Target', Who(target) }, { 'Days', days } })
    return true
end, ADMIN)
