--[[
    NAYZEEE BILLING - Cash registers (server)
    The employee rings items up from the society's templates; the customer watches a live
    display and pays from their own screen.
]]

Registers = {}
local Sessions = {}          -- [registerId] = { employee, customer?, items = {}, invoice? = { id, ref } }
local CustomerSessions = {}  -- [customer] = registerId

local function jobsOf(society)
    local s = Config.Societies[society] or {}
    local jobs = { society }
    for _, j in ipairs(type(s.jobs) == 'table' and s.jobs or {}) do jobs[#jobs + 1] = j end
    return jobs
end

local function public(r)
    return { id = r.id, label = r.label, society = r.society, societyLabel = SocietyLabel(r.society), jobs = jobsOf(r.society),
        coords = r.coords, radius = r.radius, source = r.source }
end

function RegisterList()
    local list = {}
    for _, r in pairs(Registers) do list[#list + 1] = public(r) end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function broadcast() TriggerClientEvent('nayzeee-billing:client:registers', -1, RegisterList()) end

local function load()
    Registers = {}
    if not Config.Registers.Enabled then return end
    for _, r in ipairs(Config.Registers.List or {}) do
        if r.id and r.coords and Config.Societies[r.society] then
            Registers[r.id] = { id = r.id, label = r.label or r.id, society = r.society,
                coords = { x = r.coords.x, y = r.coords.y, z = r.coords.z }, radius = tonumber(r.radius) or 2.0, source = 'config' }
        end
    end
    for _, row in ipairs(MySQL.query.await('SELECT * FROM nayzeee_billing_registers') or {}) do
        Registers[row.id] = { id = row.id, label = row.label, society = row.company,
            coords = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) }, radius = tonumber(row.radius) or 2.0, source = 'db' }
    end
end

function AddRegister(data)
    local id = 'reg_' .. Shared.Slug(data.label) .. '_' .. Shared.RandomCode(4):lower()
    MySQL.insert.await('INSERT INTO nayzeee_billing_registers (id, label, company, x, y, z, heading, radius) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { id, data.label, data.society, data.coords.x, data.coords.y, data.coords.z, data.heading or 0, data.radius })
    Registers[id] = { id = id, label = data.label, society = data.society, coords = data.coords, radius = data.radius, source = 'db' }
    broadcast()
    return Registers[id]
end

function DeleteRegister(id)
    local r = Registers[id]
    if not r then return false, L('error.not_found_generic', 'Not found') end
    if r.source == 'config' then return false, L('error.config_register', 'This register is defined in config.lua') end
    MySQL.query.await('DELETE FROM nayzeee_billing_registers WHERE id = ?', { id })
    Registers[id] = nil
    broadcast()
    return true
end

RPC('getRegisters', function() return RegisterList() end)

-- ███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
-- ███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
-- ╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
-- ███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║███████║
-- ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

local function nearby(register, employee)
    local max = (Config.Registers.MaxCustomerDistance or 5.0) + register.radius
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src ~= employee and Framework.GetIdentifier(src) then
            local d = DistanceTo(src, register.coords)
            if d <= max then list[#list + 1] = { id = src, name = Framework.GetName(src), distance = Shared.Round(d, 1) } end
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

local function totals(session)
    return Shared.Totals(session.items, Shared.VatRate(session.society))
end

local function push(session)
    if not session.customer then return end
    local t = totals(session)
    TriggerClientEvent('nayzeee-billing:client:display', session.customer, {
        action = 'update', items = session.items, subtotal = t.subtotal, vat = t.vat, total = t.total, vatRate = Shared.VatRate(session.society),
    })
end

local function posState(session, state)
    if session.employee then TriggerClientEvent('nayzeee-billing:client:posState', session.employee, state) end
end

local function cancelPending(session, reason)
    if not session.invoice then return end
    local row = GetInvoiceRow(session.invoice.id)
    if row and row.status == 'pending' and (tonumber(row.amount_paid) or 0) == 0 then CancelInvoice(row, reason, session.employee) end
end

local function release(session, closeDisplay)
    if session.customer then
        CustomerSessions[session.customer] = nil
        if closeDisplay then TriggerClientEvent('nayzeee-billing:client:display', session.customer, { action = 'close' }) end
    end
    session.customer, session.invoice = nil, nil
end

local function endSession(registerId, reason)
    local session = Sessions[registerId]
    if not session then return end
    cancelPending(session, reason or 'Register order cancelled')
    release(session, true)
    Sessions[registerId] = nil
end

-- The caller's session; ends it if they no longer have register access or the register is gone
local function own(source, registerId)
    local session = Sessions[registerId]
    if not session or session.employee ~= source then return nil end
    local register = Registers[registerId]
    local ctx = GetCtx(source)
    if not register or not ctx or not Can(ctx, 'register', register.society) then
        endSession(registerId, 'Register closed')
        return nil
    end
    return session, register, ctx
end

local function menu(ctx)
    local list = {}
    for _, t in ipairs(Templates.Usable(ctx, 'society')) do
        if not t.global then list[#list + 1] = t end
    end
    return list
end

RPC('register:open', function(source, payload)
    local register = Registers[payload.registerId]
    if not register then return Err(L('error.not_found_generic', 'Not found')) end
    local ctx = GetCtx(source)
    if not Can(ctx, 'register', register.society) then return Err(L('error.not_employee', 'You do not work here')) end
    if DistanceTo(source, register.coords) > register.radius + 3.0 then return Err(L('error.too_far_register', 'You are too far from the register')) end

    local existing = Sessions[register.id]
    if existing and existing.employee ~= source and GetPlayerPing(existing.employee) > 0 then
        return Err(L('error.register_busy', 'This register is in use by {name}', { name = Framework.GetName(existing.employee) }))
    end
    if existing then endSession(register.id) end

    Sessions[register.id] = { employee = source, society = register.society, items = {} }
    return { register = public(register), menu = menu(ctx), vatRate = Shared.VatRate(register.society), nearby = nearby(register, source) }
end)

RPC('register:nearby', function(source, payload)
    local session, register = own(source, payload.registerId)
    if not session then return Err(L('error.session_expired', 'Register session expired')) end
    return nearby(register, source)
end)

RPC('register:assign', function(source, payload)
    local session, register = own(source, payload.registerId)
    if not session then return Err(L('error.session_expired', 'Register session expired')) end
    if session.invoice then return Err(L('error.checkout_active', 'Finish or void the current checkout first')) end
    local customer = tonumber(payload.customerId)
    if not customer or customer == source or not Framework.GetIdentifier(customer) then return Err(L('error.recipient_gone', 'That person is not available')) end
    if DistanceTo(customer, register.coords) > (Config.Registers.MaxCustomerDistance or 5.0) + register.radius then
        return Err(L('error.customer_far', 'The customer is too far from the register'))
    end
    if CustomerSessions[customer] and CustomerSessions[customer] ~= register.id then return Err(L('error.customer_busy', 'That customer is at another register')) end

    release(session, true)
    session.customer = customer
    CustomerSessions[customer] = register.id
    TriggerClientEvent('nayzeee-billing:client:display', customer, {
        action = 'open', register = register.label, society = SocietyLabel(register.society), employee = Framework.GetName(source),
    })
    push(session)
    return { customer = { id = customer, name = Framework.GetName(customer) } }
end)

local function setItems(session, ctx, raw)
    if type(raw) ~= 'table' or #raw == 0 then session.items = {} return true end
    local items, err = BuildInvoiceItems(ctx, 'society', raw, false)
    if not items then return nil, err end
    session.items = items
    return true
end

RPC('register:update', function(source, payload)
    local session, _, ctx = own(source, payload.registerId)
    if not session then return Err(L('error.session_expired', 'Register session expired')) end
    if session.invoice then return Err(L('error.checkout_active', 'Finish or void the current checkout first')) end
    local ok, err = setItems(session, ctx, payload.items)
    if not ok then return Err(err) end
    push(session)
    return totals(session)
end)

RPC('register:charge', function(source, payload)
    local session, register, ctx = own(source, payload.registerId)
    if not session then return Err(L('error.session_expired', 'Register session expired')) end
    if not session.customer then return Err(L('error.pick_customer', 'Select a customer first')) end
    if session.invoice then return Err(L('error.checkout_active', 'Finish or void the current checkout first')) end
    if payload.items then
        local ok, err = setItems(session, ctx, payload.items)
        if not ok then return Err(err) end
        push(session)
    end
    if #session.items == 0 then return Err(L('error.no_items', 'Add at least one item')) end

    local customerId = Framework.GetIdentifier(session.customer)
    if not customerId then return Err(L('error.recipient_gone', 'That person is not available')) end
    local row, err = CreateInvoice({
        source = source, senderIdentifier = ctx.identifier, senderName = ctx.name, senderJob = ctx.job.name,
        society = register.society, recipientType = 'citizen', targetIdentifier = customerId, targetSource = session.customer,
        targetName = Framework.GetName(session.customer), items = session.items, dueDays = 1, registerId = register.id, silent = true,
    })
    if not row then return Err(err) end
    session.invoice = { id = row.id, ref = row.invoice_id }
    TriggerClientEvent('nayzeee-billing:client:display', session.customer, {
        action = 'checkout', invoice = FormatInvoice(row, { identifier = customerId }),
    })
    return { ref = row.invoice_id, total = tonumber(row.total) }
end)

RPC('register:cancel', function(source, payload)
    local session = own(source, payload.registerId)
    if not session then return true end
    if session.customer then Notify(session.customer, L('notify.order_cancelled', 'Order cancelled'), L('notify.order_cancelled_body', 'The cashier cancelled your order'), 'info') end
    endSession(payload.registerId, 'Cancelled at register')
    return true
end)

RPC('register:next', function(source, payload)
    local session, register = own(source, payload.registerId)
    if not session then return Err(L('error.session_expired', 'Register session expired')) end
    cancelPending(session, 'Register order voided')
    release(session, true)
    session.items = {}
    return { nearby = nearby(register, source) }
end)

-- ██████╗ ██╗███████╗██████╗ ██╗      █████╗ ██╗   ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝
-- ██║  ██║██║███████╗██████╔╝██║     ███████║ ╚████╔╝
-- ██║  ██║██║╚════██║██╔═══╝ ██║     ██╔══██║  ╚██╔╝
-- ██████╔╝██║███████║██║     ███████╗██║  ██║   ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝

local function customerSession(source)
    local id = CustomerSessions[source]
    local session = id and Sessions[id]
    if not session or session.customer ~= source then return nil end
    return session, Registers[id]
end

RPC('display:pay', function(source, payload)
    local session = customerSession(source)
    if not session or not session.invoice then return Err(L('error.nothing_to_pay', 'Nothing to pay')) end
    local result, err = ProcessPayment({ source = source, id = session.invoice.id, method = payload.method, tip = payload.tip, kind = 'register' })
    if not result then return Err(err) end
    posState(session, { status = 'paid', amount = result.amount, tip = result.tip, customer = Framework.GetName(source) })
    CustomerSessions[source] = nil
    session.customer, session.invoice, session.items = nil, nil, {}
    return result
end)

RPC('display:decline', function(source)
    local session = customerSession(source)
    if not session then return true end
    if session.invoice and Config.Registers.DeclineCancelsInvoice then
        cancelPending(session, 'Declined at register')
    elseif session.invoice then
        local row = GetInvoiceRow(session.invoice.id)
        if row then TriggerClientEvent('nayzeee-billing:client:newInvoice', source, FormatInvoice(row, { identifier = row.target_identifier })) end
    end
    posState(session, { status = session.invoice and 'declined' or 'left', customer = Framework.GetName(source) })
    CustomerSessions[source] = nil
    session.customer, session.invoice = nil, nil
    return true
end)

RPC('display:view', function(source, payload)
    local session, register = customerSession(source)
    if not session or (payload.registerId and register.id ~= payload.registerId) then return Err(L('error.no_order', 'There is no order waiting for you here')) end
    TriggerClientEvent('nayzeee-billing:client:display', source, {
        action = 'open', register = register.label, society = SocietyLabel(register.society), employee = Framework.GetName(session.employee) })
    push(session)
    if session.invoice then
        local row = GetInvoiceRow(session.invoice.id)
        TriggerClientEvent('nayzeee-billing:client:display', source, { action = 'checkout', invoice = FormatInvoice(row, { identifier = row.target_identifier }) })
    end
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, session in pairs(Sessions) do
        if session.employee == src then
            endSession(id, 'Cashier left')
        elseif session.customer == src then
            cancelPending(session, 'Customer left during checkout')
            posState(session, { status = 'left' })
            CustomerSessions[src] = nil
            session.customer, session.invoice = nil, nil
        end
    end
end)

AddEventHandler('nayzeee-billing:server:ready', function()
    load()
    broadcast()
end)
