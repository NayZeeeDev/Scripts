--[[
    NAYZEEE BILLING - Templates
    Global presets (presets.lua, read-only), society templates (seeded from presets.lua, edited in-game)
    and personal templates. Invoice items picked from a template use the template's price.
]]

Templates = {}

local Colors = { blue = true, red = true, amber = true, teal = true, cyan = true, violet = true, gray = true, rainbow = true }

local function decode(raw)
    local ok, t = pcall(json.decode, raw or '[]')
    return ok and type(t) == 'table' and t or {}
end

local function cleanItems(items)
    local out = {}
    for _, it in ipairs(items or {}) do
        local label = Shared.Sanitize(it.label, 60)
        local amount = Shared.Round(it.amount)
        if label ~= '' and amount > 0 then
            out[#out + 1] = { id = it.id or Shared.RandomCode(6), label = label, amount = amount }
        end
    end
    return out
end

-- Global templates from presets.lua (society = nil)
local GlobalCache
function Templates.Global()
    if GlobalCache then return GlobalCache end
    GlobalCache = {}
    for i, p in ipairs(Config.Presets or {}) do
        if not p.society then
            local items = {}
            for j, it in ipairs(p.items or {}) do items[#items + 1] = { id = 'i' .. j, label = it.label, amount = Shared.Round(it.amount) } end
            GlobalCache[#GlobalCache + 1] = { id = 'g' .. i, name = p.name, icon = p.icon or 'file', color = p.color or 'gray', items = items, global = true }
        end
    end
    return GlobalCache
end

-- Society templates are seeded from presets.lua once, then owned by the database
function Templates.Seed(society)
    local key = 'templates_seeded:' .. society
    if DB.Meta(key) then return end
    DB.Meta(key, '1')
    local sort = 0
    for _, p in ipairs(Config.Presets or {}) do
        if p.society == society then
            sort = sort + 1
            MySQL.insert.await('INSERT INTO nayzeee_billing_templates (owner_type, owner, name, icon, color, items, sort) VALUES (?, ?, ?, ?, ?, ?, ?)',
                { 'society', society, p.name, p.icon or 'file', p.color or 'teal', json.encode(cleanItems(p.items)), sort })
        end
    end
end

local function format(row)
    return { id = row.id, name = row.name, icon = row.icon, color = row.color, items = decode(row.items), ownerType = row.owner_type }
end

function Templates.ForOwner(ownerType, owner)
    if ownerType == 'society' then Templates.Seed(owner) end
    local rows = MySQL.query.await('SELECT * FROM nayzeee_billing_templates WHERE owner_type = ? AND owner = ? ORDER BY sort ASC, id ASC',
        { ownerType, owner }) or {}
    for i, r in ipairs(rows) do rows[i] = format(r) end
    return rows
end

local function ownerFor(ctx, account)
    if account == 'society' then
        if not ctx.society then return nil end
        return 'society', ctx.society
    end
    return 'personal', ctx.identifier
end

-- Templates a player can bill from in an account
function Templates.Usable(ctx, account)
    local list = {}
    for _, t in ipairs(Templates.Global()) do list[#list + 1] = t end
    local ot, owner = ownerFor(ctx, account)
    if ot == 'society' and not (Can(ctx, 'create') or Can(ctx, 'templates_view')) then return list end
    if ot then for _, t in ipairs(Templates.ForOwner(ot, owner)) do list[#list + 1] = t end end
    return list
end

-- Server-side price lookup for an invoice line
function Templates.FindItem(ctx, account, templateId, itemId)
    if type(templateId) == 'string' and templateId:sub(1, 1) == 'g' then
        for _, t in ipairs(Templates.Global()) do
            if t.id == templateId then
                for _, it in ipairs(t.items) do if it.id == itemId then return it, t end end
            end
        end
        return nil
    end
    local ot, owner = ownerFor(ctx, account)
    local row = ot and MySQL.single.await('SELECT * FROM nayzeee_billing_templates WHERE id = ? AND owner_type = ? AND owner = ?',
        { tonumber(templateId) or -1, ot, owner })
    if not row then return nil end
    local t = format(row)
    for _, it in ipairs(t.items) do if it.id == itemId then return it, t end end
    return nil
end

local function editable(ctx, account, perm)
    if account == 'society' then return ctx.society ~= nil and Can(ctx, perm) end
    return true
end

local function getOwned(ctx, account, id)
    local ot, owner = ownerFor(ctx, account)
    if not ot then return nil end
    local row = MySQL.single.await('SELECT * FROM nayzeee_billing_templates WHERE id = ? AND owner_type = ? AND owner = ?', { tonumber(id) or -1, ot, owner })
    return row and format(row) or nil
end

local function saveItems(id, items)
    MySQL.update.await('UPDATE nayzeee_billing_templates SET items = ? WHERE id = ?', { json.encode(items), id })
end

local function logTpl(source, ctx, account, action, data)
    Log(source, action, data, account == 'society' and ctx.society or nil)
end

-- ██████╗ ██████╗  ██████╗
-- ██╔══██╗██╔══██╗██╔════╝
-- ██████╔╝██████╔╝██║
-- ██╔══██╗██╔═══╝ ██║
-- ██║  ██║██║     ╚██████╗
-- ╚═╝  ╚═╝╚═╝      ╚═════╝

RPC('templates:list', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    if account == 'society' and not ctx.society then return Err(L('error.no_society', 'You are not in a billing society')) end
    local canView = account == 'personal' or Can(ctx, 'templates_view') or Can(ctx, 'create')
    return {
        templates = canView and Templates.Usable(ctx, account) or Templates.Global(),
        canCreate = editable(ctx, account, 'templates_create'),
        canEdit = editable(ctx, account, 'templates_edit'),
        canDelete = editable(ctx, account, 'templates_delete'),
    }
end)

RPC('templates:save', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    local t = type(payload.template) == 'table' and payload.template or {}
    local name = Shared.Sanitize(t.name, 60)
    if name == '' then return Err(L('error.template_name', 'Give the template a name')) end
    local icon = Shared.Sanitize(t.icon, 30):gsub('[^%w_%-]', '')
    local color = Colors[t.color] and t.color or 'teal'

    if t.id then
        if not editable(ctx, account, 'templates_edit') then return Err(L('error.no_permission', 'You do not have permission')) end
        local row = getOwned(ctx, account, t.id)
        if not row then return Err(L('error.template_missing', 'Template not found')) end
        MySQL.update.await('UPDATE nayzeee_billing_templates SET name = ?, icon = ?, color = ? WHERE id = ?', { name, icon ~= '' and icon or 'file', color, row.id })
        logTpl(source, ctx, account, 'template_updated', { name = name })
        return { id = row.id }
    end

    if not editable(ctx, account, 'templates_create') then return Err(L('error.no_permission', 'You do not have permission')) end
    local ot, owner = ownerFor(ctx, account)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_billing_templates WHERE owner_type = ? AND owner = ?', { ot, owner })
    if (tonumber(count) or 0) >= 30 then return Err(L('error.template_limit', 'Template limit reached')) end
    if ot == 'society' then Templates.Seed(owner) end
    local id = MySQL.insert.await('INSERT INTO nayzeee_billing_templates (owner_type, owner, name, icon, color, items, sort) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { ot, owner, name, icon ~= '' and icon or 'file', color, '[]', (tonumber(count) or 0) + 1 })
    logTpl(source, ctx, account, 'template_created', { name = name })
    return { id = id }
end)

RPC('templates:delete', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    if not editable(ctx, account, 'templates_delete') then return Err(L('error.no_permission', 'You do not have permission')) end
    local row = getOwned(ctx, account, payload.id)
    if not row then return Err(L('error.template_missing', 'Template not found')) end
    MySQL.query.await('DELETE FROM nayzeee_billing_templates WHERE id = ?', { row.id })
    logTpl(source, ctx, account, 'template_deleted', { name = row.name })
    return true
end)

RPC('templates:saveItem', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    if not editable(ctx, account, 'templates_edit') then return Err(L('error.no_permission', 'You do not have permission')) end
    local row = getOwned(ctx, account, payload.templateId)
    if not row then return Err(L('error.template_missing', 'Template not found')) end
    local it = type(payload.item) == 'table' and payload.item or {}
    local label = Shared.Sanitize(it.label, 60)
    local amount = Shared.Round(it.amount)
    if label == '' then return Err(L('error.item_name', 'Give the item a name')) end
    if amount <= 0 or amount > Config.Invoices.MaxAmount then return Err(L('error.amount', 'Enter a valid amount')) end

    local found = false
    for _, existing in ipairs(row.items) do
        if it.id and existing.id == it.id then existing.label, existing.amount, found = label, amount, true end
    end
    if not found then
        if #row.items >= 50 then return Err(L('error.item_limit', 'Item limit reached')) end
        row.items[#row.items + 1] = { id = Shared.RandomCode(6), label = label, amount = amount }
    end
    saveItems(row.id, row.items)
    logTpl(source, ctx, account, found and 'item_updated' or 'item_added', { name = label, template = row.name, amount = amount })
    return row.items
end)

RPC('templates:deleteItem', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    if not editable(ctx, account, 'templates_edit') then return Err(L('error.no_permission', 'You do not have permission')) end
    local row = getOwned(ctx, account, payload.templateId)
    if not row then return Err(L('error.template_missing', 'Template not found')) end
    for i, it in ipairs(row.items) do
        if it.id == payload.itemId then
            table.remove(row.items, i)
            saveItems(row.id, row.items)
            logTpl(source, ctx, account, 'item_deleted', { name = it.label, template = row.name })
            return row.items
        end
    end
    return Err(L('error.item_missing', 'Item not found'))
end)

RPC('templates:reorder', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    if not editable(ctx, account, 'templates_edit') then return Err(L('error.no_permission', 'You do not have permission')) end
    local row = getOwned(ctx, account, payload.templateId)
    if not row or type(payload.order) ~= 'table' then return Err(L('error.template_missing', 'Template not found')) end
    local byId, ordered = {}, {}
    for _, it in ipairs(row.items) do byId[it.id] = it end
    for _, id in ipairs(payload.order) do
        if byId[id] then ordered[#ordered + 1] = byId[id]; byId[id] = nil end
    end
    for _, it in ipairs(row.items) do if byId[it.id] then ordered[#ordered + 1] = it end end
    saveItems(row.id, ordered)
    return ordered
end)
