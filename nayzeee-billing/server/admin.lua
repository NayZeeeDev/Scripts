--[[
    NAYZEEE BILLING - Inspect & admin tools
    Admins see everything. Society members with the "inspect" permission see invoices that involve their society.
]]

local function inspector(source)
    local ctx = GetCtx(source)
    if not ctx then return nil end
    if ctx.isAdmin or Can(ctx, 'inspect') then return ctx end
    return nil
end

-- Non-admins are always scoped to their own society ("job view")
local function scope(ctx, jobView)
    if not ctx.isAdmin then return ctx.society end
    if jobView and ctx.society then return ctx.society end
    return nil
end

RPC('inspect:search', function(source, payload)
    local ctx = inspector(source)
    if not ctx then return Err(L('error.no_permission', 'You do not have permission')) end
    if Throttle(source, 'inspect', 0.4) then return {} end
    local query = Shared.Sanitize(payload.query, 40)

    if payload.type == 'society' then
        local out, q = {}, query:lower()
        for _, s in ipairs(PublicSocieties()) do
            if q == '' or s.label:lower():find(q, 1, true) or s.id:find(q, 1, true) then
                out[#out + 1] = { id = s.id, name = s.label, short = s.short, color = s.color }
            end
        end
        return out
    end

    if #query < 2 then return {} end
    local out, seen, lower = {}, {}, query:lower()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local identifier = Framework.GetIdentifier(src)
        local name = identifier and Framework.GetName(src) or ''
        if identifier and (identifier == query or tostring(src) == query or name:lower():find(lower, 1, true)) then
            seen[identifier] = true
            out[#out + 1] = { id = identifier, name = name, online = true, serverId = src }
        end
    end
    for _, r in ipairs(Framework.SearchCharacters(query, 10) or {}) do
        if not seen[r.identifier] then out[#out + 1] = { id = r.identifier, name = r.name, online = false } end
    end
    return out
end)

RPC('inspect:profile', function(source, payload)
    local ctx = inspector(source)
    if not ctx then return Err(L('error.no_permission', 'You do not have permission')) end
    local scoped = scope(ctx, payload.jobView)
    local params, where, recipientWhere = { x = Shared.Sanitize(payload.id, 64), soc = scoped }, nil, nil
    local name

    if payload.type == 'society' then
        if not Config.Societies[params.x] then return Err(L('error.not_found_generic', 'Not found')) end
        name = SocietyLabel(params.x)
        where = "(company_id = @x OR (recipient_type = 'society' AND target_society = @x))"
        recipientWhere = "recipient_type = 'society' AND target_society = @x"
    else
        name = Framework.GetCharacterName(params.x)
        if not name then return Err(L('error.not_found_generic', 'Not found')) end
        where = '(sender_identifier = @x OR target_identifier = @x)'
        recipientWhere = 'target_identifier = @x'
    end
    if scoped and not (payload.type == 'society' and params.x == scoped) then
        where = where .. " AND (company_id = @soc OR (recipient_type = 'society' AND target_society = @soc))"
    end

    local stats = MySQL.single.await(([[SELECT COUNT(*) AS total,
        COALESCE(SUM(CASE WHEN %s AND status IN ('pending','partial','overdue') THEN total + late_fee - amount_paid ELSE 0 END), 0) AS outstanding,
        COALESCE(SUM(CASE WHEN %s THEN amount_paid ELSE 0 END), 0) AS paid
        FROM nayzeee_billing_invoices WHERE %s]]):format(recipientWhere, recipientWhere, where), params) or {}

    local viewer = payload.type == 'society' and { identifier = '-', society = params.x } or { identifier = params.x }
    local list = QueryInvoices(where, params, payload, viewer)
    list.subject = { type = payload.type == 'society' and 'society' or 'citizen', id = params.x, name = name, scoped = scoped ~= nil }
    list.stats = { total = tonumber(stats.total) or 0, outstanding = tonumber(stats.outstanding) or 0, paid = tonumber(stats.paid) or 0 }
    if ctx.isAdmin then
        list.subject.identifier = params.x
        list.canClear = payload.type ~= 'society' and Config.Admin.AllowClearIdentifier
    end
    if payload.type == 'society' and (ctx.isAdmin or params.x == ctx.society) then
        list.subject.balance = Banking.SocietyBalance(params.x)
    end
    return list
end)

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

local function admin(source)
    if not IsAdmin(source) then
        Log(source, 'admin_denied', {})
        return false
    end
    return true
end

RPC('admin:delete', function(source, payload)
    if not admin(source) or not Config.Admin.AllowDelete then return Err(L('error.no_permission', 'You do not have permission')) end
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row then return Err(L('error.not_found', 'Invoice not found')) end
    MySQL.query.await('DELETE FROM nayzeee_billing_invoices WHERE id = ?', { row.id })
    MySQL.query.await('DELETE FROM nayzeee_billing_payments WHERE invoice_id = ?', { row.invoice_id })
    Log(source, 'admin_delete', { ref = row.invoice_id, amount = tonumber(row.total) })
    return true
end)

RPC('admin:clear', function(source, payload)
    if not admin(source) or not Config.Admin.AllowClearIdentifier then return Err(L('error.no_permission', 'You do not have permission')) end
    local identifier = Shared.Sanitize(payload.identifier, 64)
    if identifier == '' or identifier:sub(1, 8) == 'society:' then return Err(L('error.not_found_generic', 'Not found')) end
    local refs = MySQL.query.await('SELECT invoice_id FROM nayzeee_billing_invoices WHERE sender_identifier = ? OR target_identifier = ?', { identifier, identifier }) or {}
    local n = MySQL.update.await('DELETE FROM nayzeee_billing_invoices WHERE sender_identifier = ? OR target_identifier = ?', { identifier, identifier }) or 0
    for _, r in ipairs(refs) do MySQL.query.await('DELETE FROM nayzeee_billing_payments WHERE invoice_id = ?', { r.invoice_id }) end
    Log(source, 'admin_clear', { identifier = identifier, deleted = n })
    return { deleted = n }
end)

RPC('admin:registers', function(source)
    if not admin(source) then return Err(L('error.no_permission', 'You do not have permission')) end
    return RegisterList()
end)

RPC('admin:addRegister', function(source, payload)
    if not admin(source) then return Err(L('error.no_permission', 'You do not have permission')) end
    local label = Shared.Sanitize(payload.label, 100)
    if label == '' then return Err(L('error.register_label', 'Give the register a label')) end
    if not Config.Societies[payload.society] then return Err(L('error.pick_society', 'Pick a society')) end
    local ped = GetPlayerPed(source)
    local c = GetEntityCoords(ped)
    AddRegister({ label = label, society = payload.society, coords = { x = Shared.Round(c.x), y = Shared.Round(c.y), z = Shared.Round(c.z) },
        heading = Shared.Round(GetEntityHeading(ped), 1), radius = Shared.Clamp(payload.radius or 2.0, 0.5, 10.0) })
    Log(source, 'admin_register_added', { label = label, society = payload.society })
    return RegisterList()
end)

RPC('admin:deleteRegister', function(source, payload)
    if not admin(source) then return Err(L('error.no_permission', 'You do not have permission')) end
    local ok, err = DeleteRegister(payload.id)
    if not ok then return Err(err) end
    Log(source, 'admin_register_deleted', { register = payload.id })
    return RegisterList()
end)

RPC('admin:teleport', function(source, payload)
    if not admin(source) then return Err(L('error.no_permission', 'You do not have permission')) end
    local r = Registers[payload.id]
    if not r then return Err(L('error.not_found_generic', 'Not found')) end
    SetEntityCoords(GetPlayerPed(source), r.coords.x, r.coords.y, r.coords.z, false, false, false, false)
    return true
end)

lib.callback.register('nayzeee-billing:isAdmin', function(source) return IsAdmin(source) end)
