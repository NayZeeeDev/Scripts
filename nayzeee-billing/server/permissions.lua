--[[
    NAYZEEE BILLING - Permissions (society groups & employee assignments)
]]

local Colors = { blue = true, red = true, amber = true, teal = true, cyan = true, violet = true, gray = true, rainbow = true }
local Access = { full = true, high = true, normal = true, limited = true }

local function validKeys()
    local keys = {}
    for _, s in ipairs(Config.PermissionSections) do for _, p in ipairs(s.perms) do keys[p.key] = true end end
    return keys
end

local function manager(source)
    local ctx = GetCtx(source)
    if not ctx or not ctx.society then return nil, L('error.no_society', 'You are not in a billing society') end
    if not Can(ctx, 'permissions') then return nil, L('error.no_permission', 'You do not have permission') end
    return ctx
end

local function snapshot(ctx)
    local groups = LoadGroups(ctx.society)
    local assigned = LoadMembers(ctx.society)
    local members = {}
    for _, m in ipairs(Framework.GetSocietyMembers(ctx.job.name) or {}) do
        local groupId = assigned[m.identifier] or DefaultGroupFor(ctx.society, m.grade, m.isBoss)
        members[#members + 1] = {
            identifier = m.identifier, name = m.name, grade = m.grade, gradeLabel = m.gradeLabel, online = m.online,
            group = groupId, assigned = assigned[m.identifier] ~= nil, isMe = m.identifier == ctx.identifier,
        }
    end
    table.sort(members, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.name or '') < (b.name or '')
    end)
    local defaults = {}
    for _, g in ipairs(Config.PermissionGroups) do defaults[g.id] = true end
    local list = {}
    for _, g in ipairs(groups.list) do
        list[#list + 1] = { id = g.id, label = g.label, access = g.access, icon = g.icon, color = g.color, perms = g.perms, builtin = defaults[g.id] == true }
    end
    return { groups = list, members = members, sections = Config.PermissionSections, society = SocietyLabel(ctx.society) }
end

RPC('perms:get', function(source)
    local ctx, err = manager(source)
    if not ctx then return Err(err) end
    return snapshot(ctx)
end)

RPC('perms:assign', function(source, payload)
    local ctx, err = manager(source)
    if not ctx then return Err(err) end
    local identifier = Shared.Sanitize(payload.identifier, 64)
    local groups = LoadGroups(ctx.society)
    if not groups.byId[payload.group] then return Err(L('error.group_missing', 'Group not found')) end
    if identifier == ctx.identifier and payload.group ~= ctx.group.id and not groups.byId[payload.group].perms.permissions then
        return Err(L('error.lock_out', 'You would lock yourself out of permissions'))
    end
    local isMember = false
    for _, m in ipairs(Framework.GetSocietyMembers(ctx.job.name) or {}) do
        if m.identifier == identifier then isMember = true break end
    end
    if not isMember then return Err(L('error.not_member', 'That person does not work here')) end

    MySQL.insert.await('INSERT INTO nayzeee_billing_members (society, identifier, group_id) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE group_id = VALUES(group_id)',
        { ctx.society, identifier, payload.group })
    InvalidateMembers(ctx.society)
    Log(source, 'member_assigned', { name = Framework.GetCharacterName(identifier) or identifier, group = groups.byId[payload.group].label }, ctx.society)
    local src = Framework.GetSource(identifier)
    if src then Refresh(src) end
    return snapshot(ctx)
end)

RPC('perms:saveGroup', function(source, payload)
    local ctx, err = manager(source)
    if not ctx then return Err(err) end
    local g = type(payload.group) == 'table' and payload.group or {}
    local groups = LoadGroups(ctx.society)
    local keys = validKeys()

    local perms = {}
    for k, v in pairs(type(g.perms) == 'table' and g.perms or {}) do
        if keys[k] and v == true then perms[k] = true end
    end
    local label = Shared.Sanitize(g.label, 40)
    local icon = Shared.Sanitize(g.icon, 30):gsub('[^%w_%-]', '')
    local color = Colors[g.color] and g.color or 'gray'
    local access = Access[g.access] and g.access or 'normal'

    if g.id and groups.byId[g.id] then
        -- Don't let a manager strip their own group's permissions access
        if ctx.group and ctx.group.id == g.id and not perms.permissions then
            return Err(L('error.lock_out', 'You would lock yourself out of permissions'))
        end
        MySQL.update.await('UPDATE nayzeee_billing_groups SET label = ?, access = ?, icon = ?, color = ?, perms = ? WHERE society = ? AND group_id = ?',
            { label ~= '' and label or groups.byId[g.id].label, access, icon ~= '' and icon or 'users', color, json.encode(perms), ctx.society, g.id })
        InvalidateGroups(ctx.society)
        Log(source, 'group_updated', { group = label ~= '' and label or g.id }, ctx.society)
    else
        if label == '' then return Err(L('error.group_name', 'Give the group a name')) end
        if #groups.list >= 12 then return Err(L('error.group_limit', 'Group limit reached')) end
        local id = Shared.Slug(label)
        if id == '' or groups.byId[id] then id = id .. '_' .. Shared.RandomCode(3):lower() end
        MySQL.insert.await('INSERT INTO nayzeee_billing_groups (society, group_id, label, access, icon, color, perms, sort) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { ctx.society, id, label, access, icon ~= '' and icon or 'users', color, json.encode(perms), #groups.list + 1 })
        InvalidateGroups(ctx.society)
        Log(source, 'group_created', { group = label }, ctx.society)
    end
    return snapshot(ctx)
end)

RPC('perms:deleteGroup', function(source, payload)
    local ctx, err = manager(source)
    if not ctx then return Err(err) end
    for _, g in ipairs(Config.PermissionGroups) do
        if g.id == payload.id then return Err(L('error.builtin_group', 'Built-in groups cannot be deleted')) end
    end
    local groups = LoadGroups(ctx.society)
    local g = groups.byId[payload.id]
    if not g then return Err(L('error.group_missing', 'Group not found')) end
    MySQL.query.await('DELETE FROM nayzeee_billing_members WHERE society = ? AND group_id = ?', { ctx.society, g.id })
    MySQL.query.await('DELETE FROM nayzeee_billing_groups WHERE society = ? AND group_id = ?', { ctx.society, g.id })
    InvalidateGroups(ctx.society)
    InvalidateMembers(ctx.society)
    Log(source, 'group_deleted', { group = g.label }, ctx.society)
    return snapshot(ctx)
end)
