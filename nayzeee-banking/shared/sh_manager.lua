if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BANKING MANAGER · SETTINGS
--
--  Everything /bankingmanager can change in game. config.lua stays
--  the starting point; what an admin changes in the panel is kept
--  as an override on top of it:
--
--    server   kept in this resource's KVP, so it survives restarts
--             and replacing the folder with a new version
--    clients  handed over in a GlobalState bag and applied the same
--             way, live, the moment it is saved
--
--  "Reset" in the panel drops the override and config.lua's value
--  comes back. Settings marked restart only take hold after the
--  resource restarts; the panel says so beside them.
-- ═══════════════════════════════════════════════════════════
NZManager = {}

local KVP = 'nz_manager:settings'

-- p = Config path · t = type · l = label · h = help
-- min / max / step for numbers, o = options for a select
-- r = needs a restart · s = server only (never sent to players)
-- pct = stored as a fraction (0.02), shown as a percentage (2)
NZManager.groups = {
    { id = 'general', label = 'General', items = {
        { p = 'ServerName',         t = 'text',   l = 'City name',         h = 'Under the bank title in the UI' },
        { p = 'UI.name',            t = 'text',   l = 'Bank name',         h = 'Title bar, intro and ATM screen' },
        { p = 'Currency',           t = 'text',   l = 'Currency symbol',   max = 3 },
        { p = 'CurrencyRight',      t = 'bool',   l = 'Symbol after the amount', h = '1 500$ instead of $1 500' },
        { p = 'UI.accent',          t = 'color',  l = 'Accent colour',     h = 'Buttons, highlights and charts' },
        { p = 'UI.accentLight',     t = 'color',  l = 'Accent hover' },
        { p = 'UI.accentDark',      t = 'color',  l = 'Accent shadow' },
        { p = 'UI.danger',          t = 'color',  l = 'Danger colour',     h = 'Money going out, warnings' },
        { p = 'Intro.enabled',      t = 'bool',   l = 'Boot intro',        h = 'The logo sequence when the bank opens' },
        { p = 'Intro.tagline',      t = 'text',   l = 'Intro tagline' },
        { p = 'Notify',             t = 'select', l = 'Notifications',     o = { 'ox_lib', 'esx', 'qb', 'custom' } },
        { p = 'Locale',             t = 'text',   l = 'Language file',     h = 'A file in locales/', r = true },
        { p = 'Debug',              t = 'bool',   l = 'Debug output',      h = 'Extra lines in the server console' },
        { p = 'MaxSavedTransactions', t = 'number', l = 'Rows kept per account', h = '0 keeps everything', min = 0, max = 100000 },
    } },

    { id = 'branches', label = 'Branches', items = {
        { p = 'SpawnPeds',          t = 'bool',   l = 'Tellers at branches', h = 'Off draws a marker instead of a teller' },
        { p = 'Blip.enabled',       t = 'bool',   l = 'Map blips' },
        { p = 'Blip.name',          t = 'text',   l = 'Blip name' },
        { p = 'Blip.sprite',        t = 'number', l = 'Blip sprite',       min = 0, max = 900 },
        { p = 'Blip.colour',        t = 'number', l = 'Blip colour',       min = 0, max = 85 },
        { p = 'Blip.scale',         t = 'number', l = 'Blip size',         min = 0.2, max = 2, step = 0.05 },
        { p = 'WorkingHours.enabled', t = 'bool', l = 'Opening hours',     h = 'Branches close overnight; ATMs never do' },
        { p = 'WorkingHours.openHour',  t = 'number', l = 'Opens at',      min = 0, max = 23 },
        { p = 'WorkingHours.closeHour', t = 'number', l = 'Closes at',     min = 0, max = 23 },
        { p = 'Security.branchRange', t = 'number', l = 'Branch reach (m)', h = 'How far from the teller still counts as inside', min = 2, max = 60, step = 0.5 },
        { p = 'TargetDistance',     t = 'number', l = 'Interaction reach (m)', min = 0.5, max = 10, step = 0.1 },
        { p = 'Target',             t = 'select', l = 'Third-eye',         o = { 'ox_target', 'qb-target', 'none' }, r = true },
    } },

    { id = 'teller', label = 'Teller counter', items = {
        { p = 'Teller.enabled',        t = 'bool',   l = 'Cash over the counter', h = 'The teller counts cash through a machine and slides it over' },
        { p = 'Teller.machineProp',    t = 'text',   l = 'Money counter model' },
        { p = 'Teller.cashProp',       t = 'text',   l = 'Cash model' },
        { p = 'Teller.machineHeading', t = 'number', l = 'Machine turned (°)',  min = -180, max = 180 },
        { p = 'Teller.machineTop',     t = 'number', l = 'Notes height on machine (m)', min = 0, max = 1, step = 0.01 },
        { p = 'Teller.notesHeading',   t = 'number', l = 'Notes turned on machine (°)', min = -180, max = 180 },
        { p = 'Teller.countSeconds',   t = 'number', l = 'Counting time (s)',  min = 0.5, max = 15, step = 0.1 },
        { p = 'Teller.collectSeconds', t = 'number', l = 'Cash waits on counter (s)', min = 10, max = 600 },
        { p = 'Teller.walkAway',       t = 'number', l = 'Walk-away distance (m)', min = 2, max = 30, step = 0.5 },
    } },

    { id = 'cash', label = 'Physical cash', items = {
        { p = 'Cash.enabled',       t = 'bool',   l = 'Banknotes',          h = 'Every dollar is a $1–$100 note in the inventory', r = true },
        { p = 'Cash.mirror',        t = 'bool',   l = 'Shops and other scripts', h = 'Keep framework cash equal to the notes carried', r = true },
        { p = 'Cash.syncSeconds',   t = 'number', l = 'Recount every (s)',  min = 1, max = 30 },
        { p = 'Cash.convertOnJoin', t = 'bool',   l = 'Change loose cash on join' },
        { p = 'Cash.exactUpTo',     t = 'number', l = 'Exact change up to', h = 'Above this the largest notes go first', min = 0, max = 100000 },
    } },

    { id = 'atm', label = 'ATMs', items = {
        { p = 'ATM.requireCard',    t = 'bool',   l = 'Card needed' },
        { p = 'ATM.requirePin',     t = 'bool',   l = 'PIN needed' },
        { p = 'ATM.pinEveryUse',    t = 'bool',   l = 'PIN every use',      h = 'Off asks once per session' },
        { p = 'ATM.pinAttempts',    t = 'number', l = 'Wrong PINs before block', min = 1, max = 10 },
        { p = 'ATM.withdrawFee',    t = 'number', l = 'Withdrawal fee',     pct = true, min = 0, max = 25, step = 0.1 },
        { p = 'ATM.maxWithdraw',    t = 'number', l = 'Most per withdrawal', min = 0, max = 10000000 },
        { p = 'ATM.holdCard',       t = 'bool',   l = 'Machine holds the card' },
        { p = 'ATM.targetDistance', t = 'number', l = 'Use reach (m)',      min = 0.5, max = 6, step = 0.1, r = true },
        { p = 'ATM.timeoutSeconds', t = 'number', l = 'Server timeout (s)', min = 3, max = 60 },
        { p = 'ATM.hideRadar',      t = 'bool',   l = 'Hide minimap at the machine' },
        { p = 'ATM.screen.enabled', t = 'bool',   l = 'In-world screen',    h = 'Off opens the regular bank window at ATMs' },
        { p = 'ATM.screen.camera.back', t = 'number', l = 'Camera distance (m)', min = 0.3, max = 2, step = 0.05 },
        { p = 'ATM.screen.camera.up',   t = 'number', l = 'Camera height (m)',   min = -0.5, max = 0.5, step = 0.01 },
        { p = 'ATM.screen.camera.fov',  t = 'number', l = 'Camera field of view', min = 20, max = 80 },
        { p = 'ATM.animation.enabled',  t = 'bool',   l = 'Card insert animation' },
        { p = 'ATM.slots.enabled',      t = 'bool',   l = 'Cash and receipts from the slots' },
        { p = 'Security.atmRange',      t = 'number', l = 'ATM reach (m)', min = 1, max = 10, step = 0.1 },
    } },

    { id = 'accounts', label = 'Accounts', items = {
        { p = 'Accounts.startingBalance',     t = 'number', l = 'Starting balance',     min = 0, max = 100000000 },
        { p = 'Accounts.transferFee',         t = 'number', l = 'Transfer fee',         pct = true, min = 0, max = 25, step = 0.1 },
        { p = 'Accounts.minTransfer',         t = 'number', l = 'Smallest transfer',    min = 1, max = 1000000 },
        { p = 'Accounts.maxTransfer',         t = 'number', l = 'Largest transfer',     min = 1, max = 1000000000 },
        { p = 'Accounts.allowNegative',       t = 'bool',   l = 'Allow negative balances' },
        { p = 'Accounts.maxShared',           t = 'number', l = 'Shared accounts per player', min = 0, max = 50 },
        { p = 'Accounts.maxSharedMembers',    t = 'number', l = 'People per shared account', min = 1, max = 100 },
        { p = 'Accounts.sharedCreationCost',  t = 'number', l = 'Shared account cost',  min = 0, max = 10000000 },
        { p = 'Accounts.savingsCreationCost', t = 'number', l = 'Savings account cost', min = 0, max = 10000000 },
        { p = 'Accounts.numberChangeCost',    t = 'number', l = 'New account number cost', min = 0, max = 10000000 },
        { p = 'Accounts.maxScheduled',        t = 'number', l = 'Standing orders per player', min = 0, max = 50 },
        { p = 'Accounts.withdrawLimits.personal', t = 'number', l = 'Personal withdrawal cap', h = '0 = no cap', min = 0, max = 1000000000 },
        { p = 'Accounts.withdrawLimits.shared',   t = 'number', l = 'Shared withdrawal cap',   min = 0, max = 1000000000 },
        { p = 'Accounts.withdrawLimits.society',  t = 'number', l = 'Society withdrawal cap',  min = 0, max = 1000000000 },
        { p = 'Accounts.withdrawLimits.savings',  t = 'number', l = 'Savings withdrawal cap',  min = 0, max = 1000000000 },
    } },

    { id = 'cards', label = 'Cards & credit', items = {
        { p = 'Cards.enabled',          t = 'bool',   l = 'Cards',                h = 'Off removes cards and the Cards tab' },
        { p = 'Cards.maxPerAccount',    t = 'number', l = 'Cards per account',    min = 1, max = 20 },
        { p = 'Cards.replacementPrice', t = 'number', l = 'Replacement price',    min = 0, max = 1000000 },
        { p = 'Cards.pinChangePrice',   t = 'number', l = 'PIN change price',     min = 0, max = 1000000 },
        { p = 'Cards.limitResetHours',  t = 'number', l = 'Spend limit window (h)', min = 1, max = 168 },
        { p = 'Cards.expiryMonths',     t = 'number', l = 'Card lifetime (months)', min = 1, max = 120 },
        { p = 'Cards.physicalItem',     t = 'bool',   l = 'Cards as items', r = true },
        { p = 'Cards.stealable',        t = 'bool',   l = 'Cards can be stolen' },
        { p = 'Cards.express.enabled',  t = 'bool',   l = 'Contactless' },
        { p = 'Cards.express.threshold', t = 'number', l = 'Contactless up to',   min = 0, max = 1000000 },
        { p = 'CreditCards.statementMinutes', t = 'number', l = 'Statement every (min)', min = 5, max = 100000 },
        { p = 'CreditCards.dueMinutes',       t = 'number', l = 'Time to pay (min)',     min = 5, max = 100000 },
        { p = 'CreditCards.minPaymentPct',    t = 'number', l = 'Minimum payment',       pct = true, min = 0, max = 100 },
        { p = 'CreditCards.lateFee',          t = 'number', l = 'Late fee',              min = 0, max = 1000000 },
        { p = 'CreditCards.missedBeforeFreeze', t = 'number', l = 'Missed before freeze', min = 1, max = 20 },
        { p = 'Credit.starting',  t = 'number', l = 'Starting credit score', min = 0, max = 2000 },
        { p = 'Credit.min',       t = 'number', l = 'Lowest score',          min = 0, max = 2000 },
        { p = 'Credit.max',       t = 'number', l = 'Highest score',         min = 1, max = 2000 },
    } },

    { id = 'loans', label = 'Loans', items = {
        { p = 'Loans.enabled',             t = 'bool',   l = 'Loans',               h = 'Off closes lending and removes the Loans tab' },
        { p = 'Loans.maxActive',           t = 'number', l = 'Loans per player',    min = 1, max = 10 },
        { p = 'Loans.cooldownMinutes',     t = 'number', l = 'Cooldown after paying (min)', min = 0, max = 100000 },
        { p = 'Loans.originationFee',      t = 'number', l = 'Origination fee',     pct = true, min = 0, max = 50, step = 0.1 },
        { p = 'Loans.paymentIntervalMin',  t = 'number', l = 'Instalment every (min)', min = 5, max = 100000 },
        { p = 'Loans.autoPay',             t = 'bool',   l = 'Take instalments automatically' },
        { p = 'Loans.chargeOffline',       t = 'bool',   l = 'Charge while offline' },
        { p = 'Loans.missedBeforeDefault', t = 'number', l = 'Missed before default', min = 1, max = 20 },
        { p = 'Loans.defaultPenalty',      t = 'number', l = 'Default penalty',     pct = true, min = 0, max = 200 },
        { p = 'Loans.earlyPayoffDiscount', t = 'number', l = 'Early payoff discount', pct = true, min = 0, max = 100 },
        { p = 'Loans.blacklistOnDefault',  t = 'bool',   l = 'No new loans after a default' },
    } },

    { id = 'savings', label = 'Savings & overdraft', items = {
        { p = 'Savings.enabled',        t = 'bool',   l = 'Savings',              h = 'Off removes the Savings tab' },
        { p = 'Savings.interestRate',   t = 'number', l = 'Interest per payout',  pct = true, min = 0, max = 10, step = 0.01 },
        { p = 'Savings.payoutMinutes',  t = 'number', l = 'Payout every (min)',   min = 5, max = 100000 },
        { p = 'Savings.maxBalance',     t = 'number', l = 'Most in savings',      min = 0, max = 10000000000 },
        { p = 'Savings.withdrawFee',    t = 'number', l = 'Withdrawal fee',       pct = true, min = 0, max = 25, step = 0.1 },
        { p = 'Savings.requireOnline',  t = 'bool',   l = 'Interest only while online' },
        { p = 'Overdraft.enabled',      t = 'bool',   l = 'Overdraft' },
        { p = 'Overdraft.optIn',        t = 'bool',   l = 'Players switch it on themselves' },
        { p = 'Overdraft.savingsFirst', t = 'bool',   l = 'Cover from savings first' },
        { p = 'Overdraft.limit',        t = 'number', l = 'Overdraft line',       min = 0, max = 100000000 },
        { p = 'Overdraft.minLimit',     t = 'number', l = 'Smallest line',        min = 0, max = 100000000 },
        { p = 'Overdraft.fee',          t = 'number', l = 'Overdrawn fee',        min = 0, max = 1000000 },
        { p = 'Overdraft.graceMinutes', t = 'number', l = 'Interest-free (min)',  min = 0, max = 100000 },
        { p = 'Overdraft.interestRate', t = 'number', l = 'Interest per charge',  pct = true, min = 0, max = 100, step = 0.1 },
    } },

    { id = 'bills', label = 'Bills & payroll', items = {
        { p = 'Bills.enabled',        t = 'bool',   l = 'Bills',               h = 'Off removes the Bills tab' },
        { p = 'Bills.overdueMinutes', t = 'number', l = 'Overdue after (min)', min = 5, max = 1000000 },
        { p = 'Bills.latePenalty',    t = 'number', l = 'Late penalty',        pct = true, min = 0, max = 200 },
        { p = 'Bills.maxAmount',      t = 'number', l = 'Largest bill',        min = 1, max = 1000000000 },
        { p = 'Bills.autoPay',        t = 'bool',   l = 'Auto-pay allowed' },
        { p = 'Bills.autoPayMax',     t = 'number', l = 'Auto-pay up to',      h = '0 = no cap', min = 0, max = 1000000000 },
        { p = 'Bridge.watch.enabled', t = 'bool',   l = 'Watch other billing scripts', r = true },
        { p = 'Bridge.watch.notify',  t = 'bool',   l = 'Tell players about new invoices' },
        { p = 'Bridge.maxDistance',   t = 'number', l = 'Bill reach (m)',      h = '0 = anywhere', min = 0, max = 500 },
        { p = 'Payroll.mode',         t = 'select', l = 'Who pays wages',      o = { 'esx', 'bank' }, h = 'esx = the framework, bank = this bank', r = true },
        { p = 'Payroll.maxWage',      t = 'number', l = 'Highest wage',        min = 0, max = 10000000 },
        { p = 'DirectDeposit.enabled', t = 'bool',  l = 'Players pick bank or cash wages' },
    } },

    { id = 'market', label = 'Investments', items = {
        { p = 'Market.enabled',     t = 'bool',   l = 'Investments',        h = 'Off removes the Investments tab' },
        { p = 'Market.tickMinutes', t = 'number', l = 'Prices move every (min)', min = 1, max = 1440, r = true },
        { p = 'Market.tradeFee',    t = 'number', l = 'Trade fee',          pct = true, min = 0, max = 25, step = 0.1 },
        { p = 'Market.minTrade',    t = 'number', l = 'Smallest order',     min = 1, max = 10000000 },
        { p = 'Market.maxHolding',  t = 'number', l = 'Most per asset',     min = 1, max = 10000000000 },
    } },

    { id = 'extras', label = 'Phone, papers & sound', items = {
        { p = 'Phone.enabled',      t = 'bool',   l = 'Phone app',          r = true },
        { p = 'Phone.business',     t = 'bool',   l = 'Business account on the phone' },
        { p = 'Phone.maxRequest',   t = 'number', l = 'Largest money request', min = 0, max = 100000000 },
        { p = 'Paper.enabled',      t = 'bool',   l = 'Printed papers',     h = 'Receipts, statements and credit reports as items', r = true },
        { p = 'Paper.price',        t = 'number', l = 'Print price',        min = 0, max = 100000 },
        { p = 'Statements.enabled', t = 'bool',   l = 'Statements' },
        { p = 'Statements.fee',     t = 'number', l = 'Statement fee',      min = 0, max = 100000 },
        { p = 'Sounds.enabled',     t = 'bool',   l = 'Sounds' },
        { p = 'Sounds.volume',      t = 'number', l = 'Volume',             pct = true, min = 0, max = 100 },
        { p = 'Logs.enabled',       t = 'bool',   l = 'Discord logs' },
        { p = 'Logs.webhook',       t = 'text',   l = 'Discord webhook',    h = 'Kept on the server, never sent to players', s = true },
    } },
}

-- path -> item, and the paths kept on the server only
NZManager.items = {}
for _, g in ipairs(NZManager.groups) do
    for _, it in ipairs(g.items) do NZManager.items[it.p] = it end
end

-- ── reading and writing Config by path ───────────────────
local function parts(path)
    local out = {}
    for k in path:gmatch('[^%.]+') do out[#out + 1] = tonumber(k) or k end
    return out
end

function NZManager.get(path)
    local t = Config
    for _, k in ipairs(parts(path)) do
        if type(t) ~= 'table' then return nil end
        t = t[k]
    end
    return t
end

local function set(path, value)
    local keys = parts(path)
    local t = Config
    for i = 1, #keys - 1 do
        if type(t[keys[i]]) ~= 'table' then t[keys[i]] = {} end
        t = t[keys[i]]
    end
    t[keys[#keys]] = value
end

local function vec(t, n)
    if type(t) ~= 'table' and type(t) ~= 'vector3' and type(t) ~= 'vector4' then return nil end
    local x, y, z, w = tonumber(t.x) or 0.0, tonumber(t.y) or 0.0, tonumber(t.z) or 0.0, tonumber(t.w) or 0.0
    return n == 4 and vector4(x, y, z, w) or vector3(x, y, z)
end

local function plain(v)
    local tv = type(v)
    if tv == 'vector3' then return { x = v.x, y = v.y, z = v.z } end
    if tv == 'vector4' then return { x = v.x, y = v.y, z = v.z, w = v.w } end
    if tv ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = plain(x) end
    return o
end
NZManager.plain = plain

--- A value from the panel, made the right type for its setting. nil = refused.
function NZManager.coerce(item, v)
    if item.t == 'bool' then
        if type(v) == 'boolean' then return v end
        return v == 1 or v == 'true'
    elseif item.t == 'number' then
        v = tonumber(v)
        if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
        if item.min and v < (item.pct and item.min / 100 or item.min) then v = item.pct and item.min / 100 or item.min end
        if item.max and v > (item.pct and item.max / 100 or item.max) then v = item.pct and item.max / 100 or item.max end
        -- no step means a whole number: hours, counts, money (7.5 o'clock breaks the opening-hours line)
        if not item.step and not item.pct then v = math.floor(v + 0.5) end
        return v
    elseif item.t == 'select' then
        for _, o in ipairs(item.o or {}) do if o == v then return v end end
        return nil
    elseif item.t == 'color' then
        v = tostring(v or '')
        return v:match('^#%x%x%x%x%x%x$') and v:lower() or nil
    else
        v = tostring(v == nil and '' or v)
        if item.max then v = v:sub(1, item.max) end
        return v:sub(1, 300)
    end
end

-- ── the branches, and each branch's counter ──────────────
--- Config.Banks as plain rows: { label, ped, x, y, z, w }
function NZManager.banksPlain()
    local out = {}
    for _, b in ipairs(Config.Banks or {}) do
        local c = b.coords or vector4(0, 0, 0, 0)
        out[#out + 1] = { label = b.label, ped = b.ped or 'ig_bankman', x = c.x, y = c.y, z = c.z, w = c.w or 0.0 }
    end
    return out
end

local function banksFrom(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        out[#out + 1] = {
            label  = tostring(r.label or 'Bank'),
            ped    = tostring(r.ped or 'ig_bankman'),
            coords = vector4(tonumber(r.x) or 0.0, tonumber(r.y) or 0.0, tonumber(r.z) or 0.0, tonumber(r.w) or 0.0),
        }
    end
    return out
end

--- Config.Teller.banks as a list: { i, machine, machineHeading, counter }
--- (a list, not a sparse map, so it survives JSON and state bags alike)
function NZManager.countersPlain()
    local out = {}
    for i, c in pairs((Config.Teller and Config.Teller.banks) or {}) do
        out[#out + 1] = { i = tonumber(i), machine = c.machine and plain(c.machine),
            machineHeading = c.machineHeading, counter = c.counter and plain(c.counter) }
    end
    table.sort(out, function(a, b) return a.i < b.i end)
    return out
end

local function countersFrom(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        local i = tonumber(r.i)
        if i then
            out[i] = {
                machine        = r.machine and vec(r.machine, 3) or nil,
                machineHeading = tonumber(r.machineHeading),
                counter        = r.counter and vec(r.counter, 3) or nil,
            }
        end
    end
    return out
end

-- config.lua's own values, kept before anything is laid over them
NZManager.defaults = {}
for path in pairs(NZManager.items) do NZManager.defaults[path] = plain(NZManager.get(path)) end
NZManager.defaults['Banks'] = NZManager.banksPlain()
NZManager.defaults['Teller.banks'] = NZManager.countersPlain()

NZManager.overrides = {}

--- Lay a set of overrides over config.lua. Anything not in it goes back to
--- config.lua's value, so a reset is just an apply without that key.
function NZManager.apply(over)
    over = type(over) == 'table' and over or {}
    for path, item in pairs(NZManager.items) do
        local v = over[path]
        if v ~= nil then v = NZManager.coerce(item, v) end
        if v == nil then v = plain(NZManager.defaults[path]) end
        set(path, v)
    end

    local rows = over['Banks'] or NZManager.defaults['Banks']
    local banks = banksFrom(rows)
    Config.Banks = Config.Banks or {}
    for k in pairs(Config.Banks) do Config.Banks[k] = nil end
    for i, b in ipairs(banks) do Config.Banks[i] = b end

    if Config.Teller then
        Config.Teller.banks = countersFrom(over['Teller.banks'] or NZManager.defaults['Teller.banks'])
    end
    NZManager.overrides = over
end

--- What players are sent: everything but the server-only settings.
function NZManager.public(over)
    local out = {}
    for k, v in pairs(over or {}) do
        local it = NZManager.items[k]
        if not (it and it.s) then out[k] = v end
    end
    return out
end

if IsDuplicityVersion() then
    -- ── server: read the saved overrides now, before any file uses Config ──
    local raw = GetResourceKvpString(KVP)
    local ok, saved = pcall(json.decode, raw or '{}')
    NZManager.apply(ok and type(saved) == 'table' and saved or {})
    GlobalState.nzBankSettings = NZManager.public(NZManager.overrides)

    --- Save a new set of overrides, apply them here and hand them to everyone.
    function NZManager.save(over)
        NZManager.apply(over)
        SetResourceKvp(KVP, json.encode(NZManager.overrides))
        GlobalState.nzBankSettings = NZManager.public(NZManager.overrides)
    end
else
    -- ── client: the server's overrides, now and whenever they change ──
    NZManager.apply(GlobalState.nzBankSettings or {})

    AddStateBagChangeHandler('nzBankSettings', 'global', function(_, _, value)
        local before = {}
        for k, v in pairs(NZManager.overrides or {}) do before[k] = json.encode(v) end
        NZManager.apply(value or {})
        local changed = {}
        for k, v in pairs(NZManager.overrides) do
            if before[k] ~= json.encode(v) then changed[k] = true end
            before[k] = nil
        end
        for k in pairs(before) do changed[k] = true end   -- reset to config.lua
        if next(changed) then TriggerEvent('nz_bank:settingsChanged', changed) end
    end)
end
