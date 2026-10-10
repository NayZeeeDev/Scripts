--[[
    NAYZEEE BILLING - Cash Registers (server)
    Registers from config + database, live POS sessions between employee and customer.
]]

Registers = {}
local Sessions = {}          -- [registerId] = { employee, customer?, items = {}, discount = 0, invoiceId? }
local CustomerSessions = {}  -- [customerSource] = registerId

-- ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
-- ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝███████╗
-- ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝

function CompanyJobs(company)
    local jobs = {}
    if company.job and company.job ~= '' then jobs[#jobs + 1] = company.job end
    for _, job in ipairs(type(company.jobs) == 'table' and company.jobs or {}) do
        if not Shared.TableContains(jobs, job) then jobs[#jobs + 1] = job end
    end
    return jobs
end

local function PublicRegister(r)
    local company = Companies[r.company]
    return {
        id = r.id, label = r.label, company = r.company,
        companyLabel = company and company.label or r.company,
        jobs = company and CompanyJobs(company) or {},
        coords = r.coords, radius = r.radius, source = r.source,
    }
end

function GetRegisterList()
    local list = {}
    for _, r in pairs(Registers) do list[#list + 1] = PublicRegister(r) end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function BroadcastRegisters()
    TriggerClientEvent('nayzeee-billing:client:registers', -1, GetRegisterList())
end

local function LoadRegisters()
    Registers = {}
    if not Config.CashRegister.Enabled then return end

    for _, r in ipairs(Config.CashRegisters or {}) do
        if r.id and r.coords then
            Registers[r.id] = {
                id = r.id, label = r.label or r.id, company = r.company,
                coords = { x = r.coords.x, y = r.coords.y, z = r.coords.z },
                radius = tonumber(r.radius) or 2.0, source = 'config',
            }
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM nayzeee_billing_registers') or {}) do
        Registers[row.id] = {
            id = row.id, label = row.label, company = row.company,
            coords = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) },
            radius = tonumber(row.radius) or 2.0, source = 'db',
        }
    end
end

function AddRegister(data)
    local id = 'reg_' .. Shared.Slug(data.label) .. '_' .. math.random(1000, 9999)
    MySQL.insert.await('INSERT INTO nayzeee_billing_registers (id, label, company, x, y, z, heading, radius) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { id, data.label, data.company, data.coords.x, data.coords.y, data.coords.z, data.heading or 0, data.radius })
    Registers[id] = { id = id, label = data.label, company = data.company, coords = data.coords, radius = data.radius, source = 'db' }
    BroadcastRegisters()
    return Registers[id]
end

function DeleteRegister(id)
    local r = Registers[id]
    if not r then return false, 'Register not found' end
    if r.source == 'config' then return false, 'This register is defined in config.lua' end
    MySQL.query.await('DELETE FROM nayzeee_billing_registers WHERE id = ?', { id })
    Registers[id] = nil
    BroadcastRegisters()
    return true
end

RPC('getRegisters', function()
    return GetRegisterList()
end)

-- ███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
-- ███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
-- ╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
-- ███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║███████║
-- ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

local function NearbyCustomers(register, employee)
    local maxDist = (Config.CashRegister.MaxCustomerDistance or 5.0) + register.radius
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if (src ~= employee or Config.Billing.AllowSelfBilling) and Bridge.GetIdentifier(src) then
            local dist = GetDistanceTo(src, register.coords)
            if dist <= maxDist then
                list[#list + 1] = { id = src, name = Bridge.GetName(src), distance = Shared.Round(dist, 1) }
            end
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

local function SessionTotals(session, company)
    return Shared.CalculateTotals(session.items, session.discount, company and company.taxRate or Config.DefaultTaxRate)
end

local function PushDisplay(session, register, company)
    if not session.customer then return end
    local totals = SessionTotals(session, company)
    TriggerClientEvent('nayzeee-billing:client:display', session.customer, {
        action = 'update',
        items = session.items,
        subtotal = totals.subtotal, discount = totals.discount, tax = totals.tax, total = totals.total,
    })
end

local function PosState(session, state)
    if session.employee then
        TriggerClientEvent('nayzeee-billing:client:posState', session.employee, state)
    end
end

local function ReleaseCustomer(session, closeDisplay)
    if session.customer then
        CustomerSessions[session.customer] = nil
        if closeDisplay then
            TriggerClientEvent('nayzeee-billing:client:display', session.customer, { action = 'close' })
        end
    end
    session.customer = nil
    session.invoiceId = nil
end

local EndSession

-- Returns the caller's session; ends it if they no longer work there or the register is gone
local function OwnSession(source, registerId)
    local session = Sessions[registerId]
    if not session or session.employee ~= source then return nil end
    local register = Registers[registerId]
    local company = register and Companies[register.company]
    local ctx = GetCtx(source)
    if not register or not company or not ctx or not ctx.canBill or not ctx.company or ctx.company.id ~= company.id then
        EndSession(registerId, 'Register closed')
        return nil
    end
    return session, register, company
end

function EndSession(registerId, reason)
    local session = Sessions[registerId]
    if not session then return end
    if session.invoiceId then
        local row = GetInvoiceRow(session.invoiceId)
        if row and row.status == 'pending' and (tonumber(row.amount_paid) or 0) == 0 then
            CancelInvoice(row, reason or 'Register order cancelled', session.employee)
        end
    end
    ReleaseCustomer(session, true)
    Sessions[registerId] = nil
end

RPC('register:open', function(source, payload)
    local register = Registers[payload.registerId]
    if not register then return Err('Register not found') end
    local ctx = GetCtx(source)
    if not ctx or not ctx.canBill or not ctx.company or ctx.company.id ~= register.company then
        return Err('You do not work here')
    end
    if GetDistanceTo(source, register.coords) > register.radius + 3.0 then return Err('You are too far from the register') end

    local existing = Sessions[register.id]
    if existing and existing.employee ~= source and GetPlayerPing(existing.employee) > 0 then
        return Err('This register is in use by ' .. Bridge.GetName(existing.employee))
    end
    if existing then EndSession(register.id) end

    Sessions[register.id] = { employee = source, items = {}, discount = 0 }
    return {
        register = PublicRegister(register),
        company = PublicCompany(ctx.company),
        nearby = NearbyCustomers(register, source),
        imagePath = Inventory.ImagePath(),
    }
end)

RPC('register:nearby', function(source, payload)
    local session, register = OwnSession(source, payload.registerId)
    if not session then return Err('Register session expired') end
    return NearbyCustomers(register, source)
end)

RPC('register:assign', function(source, payload)
    local session, register, company = OwnSession(source, payload.registerId)
    if not session then return Err('Register session expired') end
    if session.invoiceId then return Err('Finish or cancel the current checkout first') end

    local customer = tonumber(payload.customerId)
    if not customer or not Bridge.GetIdentifier(customer) then return Err('Customer not available') end
    if customer == source and not Config.Billing.AllowSelfBilling then return Err('You cannot ring yourself up') end
    if GetDistanceTo(customer, register.coords) > (Config.CashRegister.MaxCustomerDistance or 5.0) + register.radius then
        return Err('Customer is too far from the register')
    end
    if CustomerSessions[customer] and CustomerSessions[customer] ~= register.id then
        return Err('That customer is being served at another register')
    end

    ReleaseCustomer(session, true)
    session.customer = customer
    CustomerSessions[customer] = register.id

    TriggerClientEvent('nayzeee-billing:client:display', customer, {
        action = 'open',
        register = register.label,
        company = company and company.label or register.label,
        employee = Bridge.GetName(source),
    })
    PushDisplay(session, register, company)
    return { customer = { id = customer, name = Bridge.GetName(customer) } }
end)

RPC('register:update', function(source, payload)
    local session, register, company = OwnSession(source, payload.registerId)
    if not session then return Err('Register session expired') end
    if session.invoiceId then return Err('Checkout in progress') end

    local items = {}
    if type(payload.items) == 'table' and #payload.items > 0 then
        local built, err = BuildItems(company, payload.items)
        if not built then return Err(err) end
        items = built
    end
    session.items = items
    session.discount = (company and company.allowDiscounts) and Shared.Clamp(payload.discount, 0, company.maxDiscount or 100) or 0

    PushDisplay(session, register, company)
    return SessionTotals(session, company)
end)

RPC('register:charge', function(source, payload)
    local session, register, company = OwnSession(source, payload.registerId)
    if not session then return Err('Register session expired') end
    if not session.customer then return Err('Select a customer first') end
    if session.invoiceId then return Err('Already waiting on payment') end

    -- Charge exactly what the cashier sees (the debounced sync may not have landed yet)
    if type(payload.items) == 'table' then
        if #payload.items == 0 then return Err('Add items first') end
        local built, buildErr = BuildItems(company, payload.items)
        if not built then return Err(buildErr) end
        session.items = built
        session.discount = (company and company.allowDiscounts) and Shared.Clamp(payload.discount, 0, company.maxDiscount or 100) or 0
        PushDisplay(session, register, company)
    end
    if #session.items == 0 then return Err('Add items first') end

    local ctx = GetCtx(source)
    local customerIdentifier = Bridge.GetIdentifier(session.customer)
    if not customerIdentifier then return Err('Customer left') end

    local row, err = CreateInvoice({
        senderSource = source,
        senderIdentifier = ctx.identifier,
        senderName = ctx.name,
        senderJob = ctx.job.name,
        company = company,
        targetSource = session.customer,
        targetIdentifier = customerIdentifier,
        targetName = Bridge.GetName(session.customer),
        items = session.items,
        discount = session.discount,
        notes = payload.notes,
        dueDays = 1,
        registerId = register.id,
        silent = true,
    })
    if not row then return Err(err) end

    session.invoiceId = row.invoice_id
    TriggerClientEvent('nayzeee-billing:client:display', session.customer, {
        action = 'checkout',
        invoice = FormatInvoice(row, customerIdentifier),
        allowTips = company and company.allowTips and Config.Tips.Enabled,
    })
    return { invoiceId = row.invoice_id, total = tonumber(row.total) }
end)

RPC('register:cancel', function(source, payload)
    local session = OwnSession(source, payload.registerId)
    if not session then return true end
    if session.customer then
        Notify(session.customer, 'Order cancelled', 'The cashier cancelled your order', 'info')
    end
    EndSession(payload.registerId, 'Cancelled at register')
    return true
end)

-- Employee keeps the register but clears the customer/checkout (after payment or to serve the next person)
RPC('register:next', function(source, payload)
    local session, register, company = OwnSession(source, payload.registerId)
    if not session then return Err('Register session expired') end
    if session.invoiceId then
        local row = GetInvoiceRow(session.invoiceId)
        if row and row.status == 'pending' and (tonumber(row.amount_paid) or 0) == 0 then
            CancelInvoice(row, 'Register order voided', source)
        end
    end
    ReleaseCustomer(session, true)
    session.items, session.discount = {}, 0
    return { nearby = NearbyCustomers(register, source) }
end)

-- ██████╗ ██╗███████╗██████╗ ██╗      █████╗ ██╗   ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝
-- ██║  ██║██║███████╗██████╔╝██║     ███████║ ╚████╔╝
-- ██║  ██║██║╚════██║██╔═══╝ ██║     ██╔══██║  ╚██╔╝
-- ██████╔╝██║███████║██║     ███████╗██║  ██║   ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝

local function CustomerSession(source)
    local registerId = CustomerSessions[source]
    local session = registerId and Sessions[registerId]
    if not session or session.customer ~= source then return nil end
    return session, Registers[registerId], registerId
end

RPC('display:pay', function(source, payload)
    local session = CustomerSession(source)
    if not session or not session.invoiceId then return Err('Nothing to pay') end

    local result, err = ProcessPayment({
        source = source, invoiceId = session.invoiceId, method = payload.method, tip = payload.tip,
    })
    if not result then return Err(err) end

    PosState(session, { status = 'paid', amount = result.amount, tip = result.tip, customer = Bridge.GetName(source) })
    CustomerSessions[source] = nil
    session.customer, session.invoiceId = nil, nil
    session.items, session.discount = {}, 0
    return result
end)

RPC('display:decline', function(source)
    local session = CustomerSession(source)
    if not session then return true end
    if session.invoiceId and Config.CashRegister.DeclineCancelsInvoice then
        local row = GetInvoiceRow(session.invoiceId)
        if row and row.status == 'pending' and (tonumber(row.amount_paid) or 0) == 0 then
            CancelInvoice(row, 'Declined by customer at register', source)
        end
    elseif session.invoiceId then
        -- Invoice stays in their bills
        local row = GetInvoiceRow(session.invoiceId)
        if row then TriggerClientEvent('nayzeee-billing:client:newInvoice', source, FormatInvoice(row, row.target_identifier)) end
    end
    PosState(session, { status = session.invoiceId and 'declined' or 'left', customer = Bridge.GetName(source) })
    CustomerSessions[source] = nil
    session.customer, session.invoiceId = nil, nil
    return true
end)

-- Customer used "View Order" at a register: re-open their display if they have an order there
RPC('display:view', function(source, payload)
    local session, register = CustomerSession(source)
    if not session or (payload.registerId and register.id ~= payload.registerId) then
        return Err('There is no order waiting for you here')
    end
    local company = Companies[register.company]
    TriggerClientEvent('nayzeee-billing:client:display', source, {
        action = 'open', register = register.label,
        company = company and company.label or register.label,
        employee = Bridge.GetName(session.employee),
    })
    PushDisplay(session, register, company)
    if session.invoiceId then
        local row = GetInvoiceRow(session.invoiceId)
        TriggerClientEvent('nayzeee-billing:client:display', source, {
            action = 'checkout', invoice = FormatInvoice(row, row.target_identifier),
            allowTips = company and company.allowTips and Config.Tips.Enabled,
        })
    end
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    for registerId, session in pairs(Sessions) do
        if session.employee == src then
            EndSession(registerId, 'Cashier left')
        elseif session.customer == src then
            -- Don't leave a silent register invoice hanging on a player who left mid-checkout
            if session.invoiceId then
                local row = GetInvoiceRow(session.invoiceId)
                if row and row.status == 'pending' and (tonumber(row.amount_paid) or 0) == 0 then
                    CancelInvoice(row, 'Customer left during checkout', session.employee)
                end
            end
            PosState(session, { status = 'left' })
            CustomerSessions[src] = nil
            session.customer, session.invoiceId = nil, nil
        end
    end
end)

AddEventHandler('nayzeee-billing:server:ready', function()
    LoadRegisters()
    BroadcastRegisters()
end)
