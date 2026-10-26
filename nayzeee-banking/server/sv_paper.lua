if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  PAPER
--
--  Receipts, statements and credit reports printed as items. The
--  whole document rides in the item's metadata, so it can be handed
--  over, kept, shown to a landlord or a cop, and read back by using
--  it — long after the account itself has moved on.
--
--  Printed at a branch or an ATM, where a printer would be.
-- ═══════════════════════════════════════════════════════════
local function cfg() return Config.Paper or {} end

local KINDS = { receipt = true, statement = true, credit = true }
local STATEMENT_LINES = 14   -- what fits on the page; the summary covers the rest

local function itemFor(kind)
    return (cfg().items or {})[kind]
end

--- Give an item with metadata, through whichever inventory is running.
function Bank.giveItem(src, name, meta)
    local inv = Bank.inventory()
    if inv == 'ox_inventory' then return exports.ox_inventory:AddItem(src, name, 1, meta) end
    if inv == 'qs-inventory' then return exports['qs-inventory']:AddItem(src, name, 1, nil, meta) end
    if inv == 'qb-inventory' then return exports['qb-inventory']:AddItem(src, name, 1, false, meta, 'nayzeee-banking') end
    return false
end

local function bankName()
    return (Config.UI and Config.UI.name) or 'Bank'
end

local function last4(number)
    return tostring(number or ''):sub(-4)
end

--- The account a player may read here: their own, or the card in the machine.
local function readable(src, accountId)
    local acc = Bank.access(src, accountId)
    if not acc and Bank.cardAccess then acc = Bank.cardAccess(src, accountId) end
    return acc
end

-- ── what goes on each sheet ──────────────────────────────
local BUILD = {}

function BUILD.receipt(src, txId)
    local row = Bank.id(txId) and MySQL.single.await([[
        SELECT id, account_id, category, direction, amount, balance_after, label, actor_name,
               DATE_FORMAT(created_at, '%d %b %Y - %H:%i') AS stamp
        FROM nz_bank_transactions WHERE id = ?
    ]], { Bank.id(txId) })
    if not row then return nil, 'That transaction is gone.' end

    local acc = readable(src, row.account_id)
    if not acc then return nil, 'You cannot read that account.' end

    return {
        account = { label = acc.label, last4 = last4(acc.account_number) },
        ref       = ('TX-%06d'):format(row.id),
        label     = row.label,
        category  = row.category,
        direction = row.direction,
        amount    = row.amount,
        balance   = row.balance_after,
        by        = row.actor_name,
        stamp     = row.stamp,
    }, ('Receipt · %s%s'):format(Config.Currency, row.amount), ('%s · %s'):format(row.label, row.stamp)
end

function BUILD.statement(src, accountId, periodId)
    accountId = Bank.id(accountId)
    local acc = accountId and readable(src, accountId)
    if not acc then return nil, 'You cannot read that account.' end

    local st = Bank.buildStatement(accountId, periodId, 250)
    if not st then return nil, 'No statement available.' end

    -- the latest lines, newest last, as a real statement reads down
    local rows = {}
    for i = math.max(1, #st.rows - STATEMENT_LINES + 1), #st.rows do
        local r = st.rows[i]
        rows[#rows + 1] = { label = r.label, stamp = r.stamp, direction = r.direction, amount = r.amount, balance = r.balance_after }
    end

    return {
        account  = { label = acc.label, last4 = last4(acc.account_number) },
        period   = st.period and st.period.label,
        opening  = st.opening, closing = st.closing,
        income   = st.income, spending = st.spending,
        count    = #st.rows, shown = #rows,
        rows     = rows,
        issued   = st.issued,
    }, ('Statement · %s'):format(acc.label), ('%s · %s'):format(st.period and st.period.label or '', st.issued)
end

function BUILD.credit(src)
    local xPlayer = Bank.getPlayer(src)
    local r = Bank.creditReport(xPlayer.identifier)
    -- the last dozen points are plenty for the little chart on the page
    local history = {}
    for i = math.max(1, #r.history - 11), #r.history do history[#history + 1] = r.history[i] end
    r.history = history
    r.bands = nil
    return r, ('Credit report · %d'):format(r.score), ('%s · %s'):format(r.band, r.issued)
end

-- ── printing ─────────────────────────────────────────────
Bank.callback('nz_bank:printPaper', function(src, kind, a, b)
    if not cfg().enabled then return { ok = false, msg = 'Printing is switched off.' } end
    if not KINDS[kind] or not itemFor(kind) then return { ok = false, msg = 'That cannot be printed.' } end
    if Bank.inventory() == 'esx' then
        return { ok = false, msg = 'This server\'s inventory cannot hold printed papers.' }
    end

    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    -- a printer is at the branch and in every machine
    local point = Bank.cashPoint and Bank.cashPoint(src)
    if not point then return { ok = false, msg = 'Print it at a branch or an ATM.' } end

    local doc, label, description = BUILD[kind](src, a, b)
    if not doc then return { ok = false, msg = label } end

    local price = cfg().price or 0
    if price > 0 then
        local acc = Bank.getPersonal(xPlayer.identifier)
        if not acc or not Bank.debit(acc.id, price, { category = 'fee', label = 'Printing', actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer) }) then
            return { ok = false, msg = ('Printing costs %s%s.'):format(Config.Currency, price) }
        end
    end

    doc.kind, doc.bank, doc.holder, doc.server = kind, bankName(), Bank.fullName(xPlayer), Config.ServerName
    doc.currency, doc.currencyRight = Config.Currency, Config.CurrencyRight or false
    local meta = { paper = doc, label = label, description = description }

    if not Bank.giveItem(src, itemFor(kind), meta) then
        return { ok = false, msg = 'You have no room for it.' }
    end
    return { ok = true, msg = ('Printed: %s.'):format(label) }
end)

-- ox_inventory calls the client export straight from the item (install/items.md);
-- qs-inventory and the framework route need the items registered as usable here.
CreateThread(function()
    if not cfg().enabled then return end
    Wait(1000)
    local inv = Bank.inventory()
    if inv == 'ox_inventory' or inv == 'esx' then return end

    for _, name in pairs(cfg().items or {}) do
        local use = function(source, item)
            local meta = type(item) == 'table' and (item.info or item.metadata) or {}
            TriggerClientEvent('nz_bank:showPaper', source, meta.paper)
        end
        if inv == 'qs-inventory' and GetResourceState('qs-inventory') == 'started' then
            pcall(function() exports['qs-inventory']:CreateUsableItem(name, use) end)
        elseif ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(name, use)
        end
    end
end)
