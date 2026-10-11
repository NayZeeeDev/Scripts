local lastReport = {}   -- license -> os.time()

local function canSeeRoom(src, room)
    if room.is_report == 1 or room.is_report == true then return NZ.HasPerm(src, 'reports.view') end
    if not NZ.HasPerm(src, 'chats.view') then return false end
    local groups = room.groups and json.decode(room.groups) or {}
    if #groups == 0 then return true end
    local s = NZ.Staff[src]
    if s.group.all then return true end
    for _, g in ipairs(groups) do if g == s.group.name then return true end end
    return false
end

local function authorSrc(lic)
    for src, o in pairs(NZ.Online) do if o.license == lic then return src end end
end

local function room(id) return MySQL.single.await('SELECT * FROM nz_admin_chats WHERE id = ?', { id }) end

--- Save a message and push it to everyone who can see the room (and the report author).
local function postMessage(chat, lic, name, isStaff, text)
    local id = MySQL.insert.await('INSERT INTO nz_admin_messages (chat_id, author_license, author_name, is_staff, message) VALUES (?, ?, ?, ?, ?)',
        { chat.id, lic, name, isStaff and 1 or 0, text })
    MySQL.update('UPDATE nz_admin_chats SET updated_at = NOW() WHERE id = ?', { chat.id })
    local msg = { id = id, chat = chat.id, author = name, staff = isStaff, message = text, time = os.time(), mine = false }
    for src in pairs(NZ.Staff) do
        if canSeeRoom(src, chat) then TriggerClientEvent('nzadmin:cl:push', src, 'chat:message', msg) end
    end
    if NZ.IsTrue(chat.is_report) then
        local a = authorSrc(chat.author_license)
        if a and not NZ.Staff[a] then TriggerClientEvent('nzadmin:cl:report', a, 'message', msg) end
    end
    return msg
end

local function messages(chatId)
    local rows = MySQL.query.await('SELECT id, author_name AS author, is_staff AS staff, message, UNIX_TIMESTAMP(created_at) AS time, author_license FROM nz_admin_messages WHERE chat_id = ? ORDER BY id DESC LIMIT ?',
        { chatId, Config.Chats.HistoryPerRoom }) or {}
    local out = {}
    for i = #rows, 1, -1 do out[#out + 1] = rows[i] end
    return out
end

-- ═══ player side ════════════════════════════════════════════════════════
NZ.Route('report:mine', 'public', function(src)
    local lic = NZ.License(src)
    local list = MySQL.query.await("SELECT id, label, category, status, claimed_name, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_chats WHERE is_report = 1 AND author_license = ? AND status <> 'closed' ORDER BY id DESC", { lic }) or {}
    for _, r in ipairs(list) do
        r.messages = messages(r.id)
        for _, m in ipairs(r.messages) do m.mine = m.author_license == lic; m.author_license = nil end
    end
    return { reports = list, categories = Config.Reports.Categories, max = Config.Reports.MaxLength }
end)

NZ.Route('report:create', 'public', function(src, d)
    if not Config.Reports.Enabled then return false, 'Reports are turned off.' end
    local lic = NZ.License(src)
    local text = NZ.Trim(d.message, Config.Reports.MaxLength)
    if #text < 3 then return false, 'Describe what you need help with.' end
    if lastReport[lic] and os.time() - lastReport[lic] < Config.Reports.Cooldown then
        return false, ('Wait %ds before making another report.'):format(Config.Reports.Cooldown - (os.time() - lastReport[lic]))
    end
    local open = MySQL.scalar.await("SELECT COUNT(*) FROM nz_admin_chats WHERE is_report = 1 AND author_license = ? AND status <> 'closed'", { lic }) or 0
    if open >= Config.Reports.MaxOpen then return false, 'You already have an open report.' end
    local cat = Config.Reports.Categories[1] or 'General'
    for _, c in ipairs(Config.Reports.Categories) do if c == d.category then cat = c end end
    local title = NZ.Trim(d.title, 60)
    local id = MySQL.insert.await('INSERT INTO nz_admin_chats (label, is_report, category, author_license, author_name) VALUES (?, 1, ?, ?, ?)',
        { title ~= '' and title or NZ.Trim(text, 60), cat, lic, GetPlayerName(src) })
    lastReport[lic] = os.time()
    local chat = room(id)
    postMessage(chat, lic, GetPlayerName(src), false, text)
    NZ.ToStaff('nzadmin:cl:push', { 'report:new', { id = id, player = GetPlayerName(src), src = src, category = cat, message = text, sound = Config.Reports.SoundForStaff } }, 'reports.view', true)
    NZ.Log('reports', 'report_created', nil, src, ('[%s] %s'):format(cat, text))
    return id
end)

NZ.Route('report:send', 'public', function(src, d)
    local chat = room(tonumber(d.id)); local lic = NZ.License(src)
    if not chat or not NZ.IsTrue(chat.is_report) or chat.author_license ~= lic or chat.status == 'closed' then return false, 'That report is closed.' end
    local text = NZ.Trim(d.message, Config.Reports.MaxLength); if text == '' then return false end
    local m = postMessage(chat, lic, GetPlayerName(src), false, text); m.mine = true
    return m
end)

NZ.Route('report:close_mine', 'public', function(src, d)
    local chat = room(tonumber(d.id))
    if not chat or not NZ.IsTrue(chat.is_report) or chat.author_license ~= NZ.License(src) then return false end
    MySQL.update.await("UPDATE nz_admin_chats SET status = 'closed' WHERE id = ?", { chat.id })
    NZ.ToStaff('nzadmin:cl:push', { 'report:update', { id = chat.id, status = 'closed' } }, 'reports.view')
    NZ.Log('reports', 'report_closed', nil, src, ('closed own report #%d'):format(chat.id))
    return true
end)

-- ═══ staff side ═════════════════════════════════════════════════════════
NZ.Route('reports:list', 'reports.view', function(src, d)
    local status = d.status or 'active'
    local where = status == 'closed' and "status = 'closed'" or "status <> 'closed'"
    local rows = MySQL.query.await(([[SELECT c.id, c.label, c.category, c.author_license, c.author_name, c.status, c.claimed_name, c.claimed_license,
        UNIX_TIMESTAMP(c.created_at) AS time, UNIX_TIMESTAMP(c.updated_at) AS updated,
        (SELECT COUNT(*) FROM nz_admin_messages m WHERE m.chat_id = c.id) AS count
        FROM nz_admin_chats c WHERE is_report = 1 AND %s ORDER BY c.updated_at DESC LIMIT 100]]):format(where)) or {}
    for _, r in ipairs(rows) do r.online = authorSrc(r.author_license) end
    return rows
end)

NZ.Route('reports:get', 'reports.view', function(src, d)
    local chat = room(tonumber(d.id)); if not chat then return false end
    local msgs = messages(chat.id)
    for _, m in ipairs(msgs) do m.author_license = nil end
    chat.online = authorSrc(chat.author_license)
    return { chat = chat, messages = msgs }
end)

NZ.Route('reports:claim', 'reports.view', function(src, d)
    local chat = room(tonumber(d.id)); if not chat or not NZ.IsTrue(chat.is_report) then return false end
    if chat.status == 'closed' then return false, 'That report is closed.' end
    local mine = chat.claimed_license == NZ.License(src)
    MySQL.update.await("UPDATE nz_admin_chats SET status = ?, claimed_license = ?, claimed_name = ? WHERE id = ?",
        { mine and 'open' or 'claimed', (not mine) and NZ.License(src) or nil, (not mine) and NZ.Name(src) or nil, chat.id })
    NZ.ToStaff('nzadmin:cl:push', { 'report:update', { id = chat.id, status = mine and 'open' or 'claimed', claimed = (not mine) and NZ.Name(src) or nil } }, 'reports.view')
    if not mine then
        postMessage(chat, NZ.License(src), NZ.Name(src), true, ('%s is handling your report.'):format(NZ.Name(src)))
        NZ.Log('reports', 'report_claimed', src, { name = chat.author_name, license = chat.author_license }, 'claimed report #' .. chat.id)
    end
    return not mine
end)

NZ.Route('reports:close', 'reports.close', function(src, d)
    local chat = room(tonumber(d.id)); if not chat or not NZ.IsTrue(chat.is_report) then return false end
    MySQL.update.await("UPDATE nz_admin_chats SET status = 'closed' WHERE id = ?", { chat.id })
    NZ.ToStaff('nzadmin:cl:push', { 'report:update', { id = chat.id, status = 'closed' } }, 'reports.view')
    local a = authorSrc(chat.author_license)
    if a then TriggerClientEvent('nzadmin:cl:report', a, 'closed', { id = chat.id, by = NZ.Name(src) }) end
    NZ.Log('reports', 'report_closed', src, { name = chat.author_name, license = chat.author_license }, 'closed report #' .. chat.id)
    return true
end)

NZ.Route('reports:reopen', 'reports.close', function(src, d)
    local chat = room(tonumber(d.id)); if not chat or not NZ.IsTrue(chat.is_report) then return false end
    MySQL.update.await("UPDATE nz_admin_chats SET status = 'open', claimed_license = NULL, claimed_name = NULL WHERE id = ?", { chat.id })
    NZ.ToStaff('nzadmin:cl:push', { 'report:update', { id = chat.id, status = 'open' } }, 'reports.view')
    NZ.Log('reports', 'report_reopened', src, { name = chat.author_name, license = chat.author_license }, 'reopened report #' .. chat.id)
    return true
end)

-- ─── rooms ──────────────────────────────────────────────────────────────
NZ.Route('chats:list', 'chats.view', function(src)
    local rows = MySQL.query.await([[SELECT c.id, c.label, c.groups, UNIX_TIMESTAMP(c.updated_at) AS updated,
        (SELECT message FROM nz_admin_messages m WHERE m.chat_id = c.id ORDER BY m.id DESC LIMIT 1) AS last
        FROM nz_admin_chats c WHERE is_report = 0 ORDER BY c.updated_at DESC]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        r.is_report = 0
        if canSeeRoom(src, r) then r.groups = r.groups and json.decode(r.groups) or {}; out[#out + 1] = r end
    end
    return out
end)

NZ.Route('chats:get', 'chats.view', function(src, d)
    local chat = room(tonumber(d.id)); if not chat or not canSeeRoom(src, chat) then return false end
    local lic = NZ.License(src)
    local msgs = messages(chat.id)
    for _, m in ipairs(msgs) do m.mine = m.author_license == lic; m.author_license = nil end
    return { chat = chat, messages = msgs }
end)

NZ.Route('chats:save', { 'chats.create', 'chats.update' }, function(src, d)
    local label = NZ.Trim(d.label, 60); if label == '' then return false, 'Give the room a name.' end
    local list = {}
    for _, g in ipairs(type(d.groups) == 'table' and d.groups or {}) do if NZ.Groups[g] then list[#list + 1] = g end end
    local groups = json.encode(list)
    if d.id then
        if not NZ.HasPerm(src, 'chats.update') then return false, 'No permission.' end
        MySQL.update.await('UPDATE nz_admin_chats SET label = ?, `groups` = ? WHERE id = ? AND is_report = 0', { label, groups, d.id })
    else
        if not NZ.HasPerm(src, 'chats.create') then return false, 'No permission.' end
        MySQL.insert.await('INSERT INTO nz_admin_chats (label, is_report, author_license, author_name, `groups`) VALUES (?, 0, ?, ?, ?)', { label, NZ.License(src), NZ.Name(src), groups })
    end
    NZ.ToStaff('nzadmin:cl:push', { 'chats:changed', {} }, 'chats.view')
    return true
end)

NZ.Route('chats:delete', 'chats.delete', function(src, d)
    local chat = room(tonumber(d.id)); if not chat or NZ.IsTrue(chat.is_report) or not canSeeRoom(src, chat) then return false end
    MySQL.update.await('DELETE FROM nz_admin_chats WHERE id = ? AND is_report = 0', { chat.id })
    NZ.Log('staff', 'room_deleted', src, nil, 'deleted chat room ' .. chat.label)
    NZ.ToStaff('nzadmin:cl:push', { 'chats:changed', {} }, 'chats.view')
    return true
end)

NZ.Route('chats:send', { 'chats.view', 'reports.view' }, function(src, d)
    local chat = room(tonumber(d.id)); if not chat or not canSeeRoom(src, chat) then return false end
    local text = NZ.Trim(d.message, Config.Chats.MaxLength); if text == '' then return false end
    if NZ.IsTrue(chat.is_report) and chat.status == 'closed' then return false, 'Report is closed.' end
    local m = postMessage(chat, NZ.License(src), NZ.Name(src), true, text)
    m.mine = true
    return m
end)
