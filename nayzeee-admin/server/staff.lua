local function reloadAll()
    NZ.LoadGroups()
    for src in pairs(NZ.Online) do NZ.LoadStaff(src) end
end

local function hexColor(c)
    c = tostring(c or '')
    return c:match('^#%x%x%x%x%x%x$') and c or '#08afa2'
end

--- src can manage a group at this level (config owners can manage everything)
local function above(src, level) return NZ.Hierarchy(src) >= 255 or NZ.Hierarchy(src) > (level or 0) end

local function cleanPerms(list)
    local out = {}
    for _, p in ipairs(list or {}) do
        if p == '*' or NZ.PermissionSet[p] then out[#out + 1] = p end
    end
    return out
end

-- ─── overview ───────────────────────────────────────────────────────────
NZ.Route('staff:online', false, function()
    local out = {}
    for src, s in pairs(NZ.Staff) do
        out[#out + 1] = { id = src, name = NZ.Name(src), group = s.group.label, color = s.group.color, hierarchy = s.group.hierarchy,
            duty = s.duty, dutyFor = s.duty and (os.time() - s.dutyStart) or 0, spectating = NZ.SpectateBucket[src] ~= nil }
    end
    table.sort(out, function(a, b) return a.hierarchy > b.hierarchy end)
    return out
end)

NZ.Route('staff:overview', 'staff.view', function()
    local members = MySQL.query.await([[SELECT m.id, m.license, m.name, m.nickname, m.group_name, m.discord, m.total_duty, UNIX_TIMESTAMP(m.last_seen) AS last_seen,
        (SELECT COALESCE(SUM(seconds), 0) FROM nz_admin_duty d WHERE d.license = m.license AND d.started >= NOW() - INTERVAL 7 DAY) AS week,
        (SELECT COALESCE(SUM(seconds), 0) FROM nz_admin_duty d WHERE d.license = m.license AND d.started >= CURDATE()) AS today,
        (SELECT COUNT(*) FROM nz_admin_logs l WHERE l.staff_license = m.license AND l.created_at >= NOW() - INTERVAL 7 DAY) AS actions
        FROM nz_admin_members m ORDER BY m.total_duty DESC]]) or {}
    local online = {}
    for src, s in pairs(NZ.Staff) do online[s.license] = { id = src, duty = s.duty, since = s.dutyStart } end
    for _, m in ipairs(members) do
        local o = online[m.license]
        if o then
            m.online, m.duty = o.id, o.duty
            if o.duty then local live = os.time() - o.since; m.week = m.week + live; m.today = m.today + live; m.total_duty = m.total_duty + live end
        end
    end
    -- last 14 days of total duty for the chart
    local daily = MySQL.query.await([[SELECT DATE_FORMAT(started, '%m-%d') AS day, SUM(seconds) AS secs FROM nz_admin_duty
        WHERE started >= CURDATE() - INTERVAL 13 DAY GROUP BY DATE(started) ORDER BY DATE(started)]]) or {}
    return { members = members, groups = NZ.GroupList(), daily = daily }
end)

NZ.Route('staff:sessions', 'staff.view', function(src, d)
    return MySQL.query.await('SELECT UNIX_TIMESTAMP(started) AS started, UNIX_TIMESTAMP(ended) AS ended, seconds FROM nz_admin_duty WHERE license = ? ORDER BY id DESC LIMIT 50', { d.license })
end)

NZ.Route('staff:duty', false, function(src, d)
    local s = NZ.Staff[src]
    local state = d.state
    if state == nil then state = not s.duty end
    NZ.SetDuty(src, state == true)
    return s.duty
end)

-- ─── groups ─────────────────────────────────────────────────────────────
NZ.Route('groups:list', false, function() return { groups = NZ.GroupList(), catalog = NZ.Permissions } end)

NZ.Route('groups:save', 'staff.manage', function(src, d)
    local name = NZ.Trim(d.name, 32):lower():gsub('[^%w_]', '')
    if name == '' then return false, 'Group needs a name.' end
    local hierarchy = math.max(1, math.min(254, math.floor(tonumber(d.hierarchy) or 1)))
    if not above(src, hierarchy) then return false, 'You can only manage groups below your own level.' end
    local existing = NZ.Groups[name]
    if existing and not above(src, existing.hierarchy) then return false, 'That group is above you.' end
    local label = NZ.Trim(d.label, 48); if label == '' then label = name end
    local color = hexColor(d.color)
    local perms = cleanPerms(d.permissions)
    local mine = NZ.Staff[src].group
    if not mine.all then -- can't hand out permissions you don't have
        for _, p in ipairs(perms) do if p == '*' or not mine.perms[p] then return false, 'You cannot grant ' .. p .. '.' end end
    end
    local role = d.discord_role and NZ.Trim(d.discord_role, 32) or nil
    if role == '' then role = nil end
    local sprite = math.max(1, math.floor(tonumber(d.sprite) or 280))
    if d.id and existing then
        MySQL.update.await('UPDATE nz_admin_groups SET label = ?, color = ?, hierarchy = ?, permissions = ?, discord_role = ?, sprite = ? WHERE id = ?',
            { label, color, hierarchy, json.encode(perms), role, sprite, existing.id })
    else
        if existing then return false, 'A group with that name exists.' end
        MySQL.insert.await('INSERT INTO nz_admin_groups (name, label, color, hierarchy, permissions, discord_role, sprite) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { name, label, color, hierarchy, json.encode(perms), role, sprite })
    end
    NZ.Log('staff', 'group_saved', src, nil, ('saved group %s (%d permissions)'):format(name, #perms))
    reloadAll()
    return NZ.GroupList()
end)

NZ.Route('groups:delete', 'staff.manage', function(src, d)
    local g = NZ.Groups[d.name]; if not g then return false end
    if not above(src, g.hierarchy) then return false, 'That group is above you.' end
    if NZ.Staff[src] and NZ.Staff[src].group.name == g.name and NZ.Hierarchy(src) < 255 then return false, 'You cannot delete your own group.' end
    MySQL.update.await('DELETE FROM nz_admin_members WHERE group_name = ?', { d.name })
    MySQL.update.await('DELETE FROM nz_admin_groups WHERE name = ?', { d.name })
    NZ.Log('staff', 'group_deleted', src, nil, 'deleted group ' .. d.name)
    reloadAll()
    return NZ.GroupList()
end)

--- Save the caller's current look as the group duty outfit.
NZ.Route('groups:outfit', 'staff.manage', function(src, d)
    local g = NZ.Groups[d.name]; if not g then return false end
    if not above(src, g.hierarchy) and not (NZ.Staff[src] and NZ.Staff[src].group.name == g.name) then return false, 'That group is above you.' end
    if d.clear then
        MySQL.update.await('UPDATE nz_admin_groups SET outfit = NULL WHERE name = ?', { d.name })
    else
        local look = lib.callback.await('nzadmin:getAppearance', src)
        if not look then return false, 'Your clothing resource does not support saving outfits.' end
        MySQL.update.await('UPDATE nz_admin_groups SET outfit = ? WHERE name = ?', { json.encode(look), d.name })
    end
    NZ.LoadGroups()
    for s, st in pairs(NZ.Staff) do -- keep live sessions pointing at the fresh group
        if st.group.name == g.name and NZ.Groups[g.name] then
            st.group = NZ.Hierarchy(s) >= 255 and setmetatable({ all = true, hierarchy = 255 }, { __index = NZ.Groups[g.name] }) or NZ.Groups[g.name]
        end
    end
    NZ.Log('staff', 'group_outfit', src, nil, ('%s duty outfit for %s'):format(d.clear and 'cleared' or 'saved', g.name))
    return true
end)

-- ─── members ────────────────────────────────────────────────────────────
NZ.Route('members:save', 'staff.manage', function(src, d)
    local g = NZ.Groups[d.group]; if not g then return false, 'Pick a group.' end
    if not above(src, g.hierarchy) then return false, 'You can only assign groups below your own.' end
    local lic, name = d.license, d.name
    if d.id and tonumber(d.id) and GetPlayerName(tonumber(d.id)) then
        lic, name = NZ.License(tonumber(d.id)), GetPlayerName(tonumber(d.id))
    end
    lic = NZ.Trim(lic, 64)
    if not lic:find('^license2?:') then return false, 'Enter a license identifier or pick an online player.' end
    local cur = MySQL.single.await('SELECT group_name FROM nz_admin_members WHERE license = ?', { lic })
    if cur and NZ.Groups[cur.group_name] and not above(src, NZ.Groups[cur.group_name].hierarchy) then
        return false, 'That member is above you.'
    end
    name = NZ.Trim(name, 64)
    if name == '' then
        local seen = MySQL.single.await('SELECT name FROM nz_admin_players WHERE license = ?', { lic })
        name = seen and seen.name or ''
    end
    local nick = NZ.Trim(d.nickname, 64)
    MySQL.query.await('INSERT INTO nz_admin_members (license, name, nickname, group_name) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE group_name = VALUES(group_name), nickname = VALUES(nickname)',
        { lic, name, nick ~= '' and nick or nil, d.group })
    NZ.Log('staff', 'member_saved', src, { name = name, license = lic }, 'set staff group ' .. d.group)
    for s, o in pairs(NZ.Online) do if o.license == lic then NZ.LoadStaff(s) end end
    return true
end)

NZ.Route('members:delete', 'staff.manage', function(src, d)
    local cur = MySQL.single.await('SELECT group_name, name FROM nz_admin_members WHERE license = ?', { d.license }); if not cur then return false end
    local g = NZ.Groups[cur.group_name]
    if g and not above(src, g.hierarchy) then return false, 'That member is above you.' end
    MySQL.update.await('DELETE FROM nz_admin_members WHERE license = ?', { d.license })
    NZ.Log('staff', 'member_removed', src, { name = cur.name, license = d.license }, 'removed from staff')
    for s, o in pairs(NZ.Online) do if o.license == d.license then NZ.LoadStaff(s) end end
    return true
end)

-- ─── staff sprites (on duty staff see each other on the map) ────────────
lib.callback.register('nzadmin:staffSprites', function(src)
    local me = NZ.Staff[src]
    if not me or not me.duty or not Config.Staff.Sprites then return nil end
    local out = {}
    for id, s in pairs(NZ.Staff) do
        if id ~= src and s.duty then
            local c = GetEntityCoords(GetPlayerPed(id))
            out[#out + 1] = { id = id, name = NZ.Name(id), x = c.x, y = c.y, z = c.z, sprite = s.group.sprite or 280 }
        end
    end
    return out
end)
