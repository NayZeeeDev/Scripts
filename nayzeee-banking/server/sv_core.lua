if BankLocked then return end

ESX = exports['es_extended']:getSharedObject()

Bank = {}
Bank.locks = {}          -- [accountId] = true while a write is in flight
Bank.session = {}        -- [src] = { pinOk = {}, atm = false }

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS
--
--  Every callback in this resource is registered through here.
--
--  ox_lib does not reply when a callback throws — it logs and stops.
--  The client is left in lib.callback.await forever, which on screen
--  looks like a spinner that never finishes and no error anywhere.
--  That is the worst way for something to break: nothing to read and
--  nothing to report.
--
--  So a callback that errors returns a failure instead, and says
--  what went wrong in the console.
-- ═══════════════════════════════════════════════════════════
function Bank.callback(name, fn)
    lib.callback.register(name, function(src, ...)
        local ok, result = pcall(fn, src, ...)
        if ok then return result end

        print(('^1[nayzeee-banking]^7 %s errored and returned a failure instead of hanging:'):format(name))
        print('^1[nayzeee-banking]^7   ' .. tostring(result))

        return { ok = false, msg = 'The bank hit an error. The server console has the details.' }
    end)
end

-- ═══════════════════════════════════════════════════════════
--  SCHEMA
--
--  Some columns arrived after the first release. A server that has
--  not imported install/update.sql will not have them, and a query
--  against a column that is not there does not fail quietly — it
--  throws, and it takes down whatever was calling it.
--
--  So the columns are checked once at start. Anything missing
--  switches its own feature off and says so in the console. The
--  bank keeps working; one feature sits out until the SQL is run.
-- ═══════════════════════════════════════════════════════════
Bank.schema = {}
Bank.schemaChecked = false

--- Wait for the schema check to finish. Anything that decides once,
--- at start, whether to run at all must call this first — otherwise
--- it reads the flags before they are set and switches itself off on
--- a database that was perfectly fine.
function Bank.awaitSchema()
    local waited = 0
    while not Bank.schemaChecked and waited < 15000 do
        Wait(100)
        waited = waited + 100
    end
    return Bank.schemaChecked
end

local REQUIRED = {
    counterparty = {
        { table = 'nz_bank_transactions', column = 'counterparty' },
        { table = 'nz_bank_transactions', column = 'counterparty_name' },
        feature = 'the phone app\'s Recent list'
    },
    overdraft = {
        { table = 'nz_bank_accounts',  column = 'od_since' },
        { table = 'nz_bank_accounts',  column = 'od_fees'  },
        { table = 'nz_bank_settings',  column = 'overdraft' },
        feature = 'overdraft protection'
    },
    loanChurn = {
        { table = 'nz_bank_loans', column = 'paid_count'  },
        { table = 'nz_bank_loans', column = 'started_at'  },
        { table = 'nz_bank_loans', column = 'last_credit' },
        feature = 'loan anti-churn and credit from repayments'
    },
}

CreateThread(function()
    Wait(1500)   -- let oxmysql finish connecting

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT TABLE_NAME AS t, COLUMN_NAME AS c
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME LIKE 'nz_bank_%'
        ]])
    end)

    if not ok then
        print('^1[nayzeee-banking]^7 could not read the database schema. ' ..
              'Check your oxmysql connection string.')
        Bank.schemaChecked = true
        return
    end

    local have = {}
    for _, r in ipairs(rows or {}) do
        have[(r.t .. '.' .. r.c):lower()] = true
    end

    local missing = {}
    for group, spec in pairs(REQUIRED) do
        Bank.schema[group] = true
        for _, col in ipairs(spec) do
            if not have[(col.table .. '.' .. col.column):lower()] then
                Bank.schema[group] = false
                missing[#missing + 1] = ('%s.%s'):format(col.table, col.column)
            end
        end
        if not Bank.schema[group] then
            print(('^3[nayzeee-banking]^7 %s is switched off — the database is missing columns it needs.')
                :format(spec.feature))
        end
    end

    if #missing > 0 then
        print('^3[nayzeee-banking]^7 import ^5install/update.sql^7 to switch these back on. Missing: ' ..
              table.concat(missing, ', '))
    else
        Bank.debug('schema is up to date')
    end

    Bank.schemaChecked = true
end)

-- ═══════════════════════════════════════════════════════════
--  UTIL
-- ═══════════════════════════════════════════════════════════
local CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'

function Bank.debug(...)
    if Config.Debug then print('^3[nayzeee-banking]^7', ...) end
end

--- NaN and infinity round to 0, so every `amount <= 0` check turns them away.
function Bank.round(n)
    n = tonumber(n)
    if not n or n ~= n or n == math.huge or n == -math.huge then return 0 end
    return math.floor(n + 0.5)
end

--- A row id as an integer, or nil. '5', '05' and 5.0 are all the same account,
--- so they have to be the same lock too.
function Bank.id(v)
    v = tonumber(v)
    return v and math.tointeger(v) or nil
end

function Bank.randomString(len)
    local out = {}
    for i = 1, len do
        local r = math.random(#CHARS)
        out[i] = CHARS:sub(r, r)
    end
    return table.concat(out)
end

function Bank.newAccountNumber(kind)
    for _ = 1, 12 do
        local n = ('%s-%s-%s'):format(Config.AccountPrefix, kind, Bank.randomString(8))
        local hit = MySQL.scalar.await('SELECT id FROM nz_bank_accounts WHERE account_number = ?', { n })
        if not hit then return n end
    end
    return ('%s-%s-%s'):format(Config.AccountPrefix, kind, os.time())
end

function Bank.getPlayer(src)
    return ESX.GetPlayerFromId(src)
end

function Bank.identifier(src)
    local x = ESX.GetPlayerFromId(src)
    return x and x.identifier or nil
end

function Bank.fullName(xPlayer)
    if not xPlayer then return 'Unknown' end
    local n = xPlayer.getName and xPlayer.getName() or nil
    if n and n ~= '' then return n end
    return ('%s %s'):format(xPlayer.get('firstName') or '', xPlayer.get('lastName') or '')
end

function Bank.notify(src, title, description, kind)
    TriggerClientEvent('nz_bank:notify', src, title, description, kind or 'inform')
end

-- ── cash helpers ────────────────────────────────────────────
--- Which inventory is actually running. Falls back to ESX money when the
--- configured one is missing, so a wrong setting never eats someone's cash.
local function inventory()
    local want = Config.Inventory or 'esx'
    if want ~= 'esx' and GetResourceState(want) ~= 'started' then
        return 'esx'
    end
    return want
end
Bank.inventory = inventory

function Bank.getCash(xPlayer)
    local inv = inventory()

    if inv == 'ox_inventory' then
        return exports.ox_inventory:GetItemCount(xPlayer.source, Config.MoneyItem) or 0
    elseif inv == 'qs-inventory' then
        return exports['qs-inventory']:GetItemTotalAmount(xPlayer.source, Config.MoneyItem) or 0
    elseif inv == 'qb-inventory' then
        local item = exports['qb-inventory']:GetItemByName(xPlayer.source, Config.MoneyItem)
        return item and item.amount or 0
    end

    return xPlayer.getMoney()
end

function Bank.removeCash(xPlayer, amount)
    if Bank.getCash(xPlayer) < amount then return false end
    local inv = inventory()

    if inv == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(xPlayer.source, Config.MoneyItem, amount)
    elseif inv == 'qs-inventory' then
        return exports['qs-inventory']:RemoveItem(xPlayer.source, Config.MoneyItem, amount)
    elseif inv == 'qb-inventory' then
        return exports['qb-inventory']:RemoveItem(xPlayer.source, Config.MoneyItem, amount)
    end

    xPlayer.removeMoney(amount)
    return true
end

function Bank.addCash(xPlayer, amount)
    local inv = inventory()

    if inv == 'ox_inventory' then
        return exports.ox_inventory:AddItem(xPlayer.source, Config.MoneyItem, amount)
    elseif inv == 'qs-inventory' then
        return exports['qs-inventory']:AddItem(xPlayer.source, Config.MoneyItem, amount)
    elseif inv == 'qb-inventory' then
        return exports['qb-inventory']:AddItem(xPlayer.source, Config.MoneyItem, amount)
    end

    xPlayer.addMoney(amount)
    return true
end

-- ── branch opening hours ────────────────────────────────────
function Bank.branchOpen()
    local w = Config.WorkingHours
    if not w or not w.enabled then return true end

    local hour = tonumber(os.date('%H'))
    if w.openHour == w.closeHour then return true end

    if w.openHour < w.closeHour then
        return hour >= w.openHour and hour < w.closeHour
    end
    -- window crosses midnight
    return hour >= w.openHour or hour < w.closeHour
end

-- ── locks: never let two writes race on one account ─────────
function Bank.lock(id)
    id = Bank.id(id) or id
    local tries = 0
    while Bank.locks[id] do
        Wait(25)
        tries = tries + 1
        if tries > 200 then return false end
    end
    Bank.locks[id] = true
    return true
end

function Bank.unlock(id)
    Bank.locks[Bank.id(id) or id] = nil
end

--- Run fn while holding `key`, so two requests for the same thing (one card, one
--- player's trades) can't both read the old state and both act on it.
--- Returns false + a message when the key stays busy.
function Bank.serial(key, fn, ...)
    if not Bank.lock(key) then return false, 'The bank is busy. Try again in a moment.' end
    local res = table.pack(pcall(fn, ...))
    Bank.unlock(key)
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end

--- Lock key for one card. '05' and 5 are the same card.
function Bank.cardKey(cardId)
    return 'card:' .. tostring(Bank.id(cardId))
end

-- ═══════════════════════════════════════════════════════════
--  ACCOUNTS — read helpers
-- ═══════════════════════════════════════════════════════════
function Bank.getAccountById(id)
    id = tonumber(id)
    if not id then return nil end
    return MySQL.single.await('SELECT * FROM nz_bank_accounts WHERE id = ?', { id })
end

function Bank.getAccountByNumber(number)
    return MySQL.single.await('SELECT * FROM nz_bank_accounts WHERE account_number = ?', { number })
end

function Bank.getPersonal(identifier)
    local acc = MySQL.single.await(
        'SELECT * FROM nz_bank_accounts WHERE owner = ? AND type = "personal" LIMIT 1', { identifier })
    return acc
end

function Bank.getSavings(identifier)
    return MySQL.single.await(
        'SELECT * FROM nz_bank_accounts WHERE owner = ? AND type = "savings" LIMIT 1', { identifier })
end

function Bank.getSociety(job)
    return MySQL.single.await(
        'SELECT * FROM nz_bank_accounts WHERE owner = ? AND type = "society" LIMIT 1', { job })
end

--- Every account this identifier can see, with their role on it.
--- `jobs` may be a single job name or a list from Bank.societyJobs.
function Bank.getAccessible(identifier, jobs, grade)
    local list = MySQL.query.await([[
        SELECT a.*, 'owner' AS role, 1 AS can_deposit, 1 AS can_withdraw, 1 AS can_transfer
        FROM nz_bank_accounts a
        WHERE a.owner = ? AND a.type IN ('personal','savings','shared')
        UNION
        SELECT a.*, m.role, m.can_deposit, m.can_withdraw, m.can_transfer
        FROM nz_bank_accounts a
        JOIN nz_bank_members m ON m.account_id = a.id
        WHERE m.identifier = ? AND a.type = 'shared'
    ]], { identifier, identifier })

    local jobList = {}
    if type(jobs) == 'table' then
        jobList = jobs
    elseif type(jobs) == 'string' and Bank.canUseSociety(jobs, grade) then
        jobList = { jobs }
    end

    for _, jobName in ipairs(jobList) do
        local soc = Bank.getSociety(jobName)
        if soc then
            soc.role = 'manager'
            soc.can_deposit, soc.can_withdraw, soc.can_transfer = 1, 1, 1
            list[#list + 1] = soc
        end
    end
    return list
end

function Bank.canUseSociety(job, grade)
    local rule = Config.Accounts.societyAccess[job]
    if not rule then return false end
    if rule == true then return true end
    for _, g in ipairs(rule) do
        if g == grade then return true end
    end
    return false
end

--- Permission check for an account+player pair. Returns account, role table or nil, reason.
function Bank.access(src, accountId)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return nil, nil, 'no_player' end

    local acc = Bank.getAccountById(accountId)
    if not acc then return nil, nil, 'no_account' end

    if acc.type == 'personal' or acc.type == 'savings' then
        if acc.owner ~= xPlayer.identifier then return nil, nil, 'not_yours' end
        return acc, { role = 'owner', deposit = true, withdraw = true, transfer = true }, nil
    end

    if acc.type == 'society' then
        local allowed = false
        for _, jobName in ipairs(Bank.societyJobs(xPlayer)) do
            if jobName == acc.owner then allowed = true break end
        end
        if not allowed then return nil, nil, 'no_rank' end
        return acc, { role = 'manager', deposit = true, withdraw = true, transfer = true }, nil
    end

    -- shared
    if acc.owner == xPlayer.identifier then
        return acc, { role = 'owner', deposit = true, withdraw = true, transfer = true }, nil
    end

    local m = MySQL.single.await(
        'SELECT * FROM nz_bank_members WHERE account_id = ? AND identifier = ?',
        { accountId, xPlayer.identifier })
    if not m then return nil, nil, 'not_member' end

    return acc, {
        role     = m.role,
        deposit  = m.can_deposit == 1,
        withdraw = m.can_withdraw == 1,
        transfer = m.can_transfer == 1
    }, nil
end

--- Bank.access for an identifier that may be offline, for things that run
--- on a timer (standing orders). Same rules; with nobody online to ask,
--- the society check reads the job ESX last saved for them.
function Bank.accessByIdentifier(identifier, accountId)
    if not identifier then return nil, nil, 'no_player' end

    local acc = Bank.getAccountById(accountId)
    if not acc then return nil, nil, 'no_account' end

    local full = { role = 'owner', deposit = true, withdraw = true, transfer = true }

    if acc.type == 'personal' or acc.type == 'savings' then
        if acc.owner ~= identifier then return nil, nil, 'not_yours' end
        return acc, full, nil
    end

    if acc.type == 'society' then
        local allowed = false
        local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
        if xPlayer then
            for _, jobName in ipairs(Bank.societyJobs(xPlayer)) do
                if jobName == acc.owner then allowed = true break end
            end
        else
            local ok, row = pcall(MySQL.single.await,
                'SELECT job, job_grade FROM users WHERE identifier = ?', { identifier })
            if ok and row and row.job == acc.owner then
                local jobs = ESX.GetJobs()
                local grades = jobs and jobs[row.job] and jobs[row.job].grades
                local g = grades and grades[tostring(row.job_grade)]
                allowed = Bank.canUseSociety(row.job, g and g.name)
            end
        end
        if not allowed then return nil, nil, 'no_rank' end
        return acc, { role = 'manager', deposit = true, withdraw = true, transfer = true }, nil
    end

    -- shared
    if acc.owner == identifier then return acc, full, nil end

    local m = MySQL.single.await(
        'SELECT * FROM nz_bank_members WHERE account_id = ? AND identifier = ?', { acc.id, identifier })
    if not m then return nil, nil, 'not_member' end

    return acc, {
        role     = m.role,
        deposit  = m.can_deposit == 1,
        withdraw = m.can_withdraw == 1,
        transfer = m.can_transfer == 1
    }, nil
end

-- ═══════════════════════════════════════════════════════════
--  BALANCE MUTATION — the only place balances change
-- ═══════════════════════════════════════════════════════════
--- @param opts table { category, label, actor, actorName, silent }
function Bank.credit(accountId, amount, opts)
    accountId = Bank.id(accountId)
    if not accountId then return false, 'no_account' end
    amount = Bank.round(amount)
    if amount <= 0 then return false, 'bad_amount' end
    if not Bank.lock(accountId) then return false, 'busy' end

    local acc = Bank.getAccountById(accountId)
    if not acc then Bank.unlock(accountId) return false, 'no_account' end
    if acc.frozen == 1 then Bank.unlock(accountId) return false, 'frozen' end

    local newBal = acc.balance + amount
    local wrote = pcall(MySQL.update.await, 'UPDATE nz_bank_accounts SET balance = ? WHERE id = ?', { newBal, accountId })
    Bank.unlock(accountId)
    if not wrote then return false, 'db_error' end

    Bank.logTx(accountId, 'in', amount, newBal, opts)
    Bank.pushRefresh(acc)

    -- money coming in may have cleared an overdraft
    if newBal >= 0 and acc.balance < 0 and Bank.overdraftSettle then
        Bank.overdraftSettle(accountId)
    end

    return true, newBal
end

--- @param opts table { category, label, actor, actorName, noOverdraft, force }
--- force: the money has already gone (a shop took it through ESX, a fee
--- or interest the bank is owed). Record it even when that takes the
--- account below zero or the account is frozen.
function Bank.debit(accountId, amount, opts)
    opts = opts or {}
    accountId = Bank.id(accountId)
    if not accountId then return false, 'no_account' end
    amount = Bank.round(amount)
    if amount <= 0 then return false, 'bad_amount' end

    -- Overdraft cover is decided BEFORE the lock is taken, because
    -- covering may move money out of savings and that is a second
    -- account. Holding two locks at once is how a deadlock starts.
    --
    -- It answers one question: how far below zero this particular
    -- debit is permitted to go. Nothing, unless the account is
    -- personal, the feature is on, and its owner opted in.
    local allowance = 0
    if not Config.Accounts.allowNegative and not opts.noOverdraft and not opts.force and Bank.overdraftCover then
        local peek = Bank.getAccountById(accountId)
        if peek and peek.frozen ~= 1 and peek.balance < amount then
            allowance = Bank.overdraftCover(peek, amount) or 0
        end
    end

    if not Bank.lock(accountId) then return false, 'busy' end

    local acc = Bank.getAccountById(accountId)
    if not acc then Bank.unlock(accountId) return false, 'no_account' end
    if acc.frozen == 1 and not opts.force then Bank.unlock(accountId) return false, 'frozen' end

    -- The authoritative check, inside the lock. Cover above may have
    -- topped the account up from savings, so this is re-made against
    -- the real balance rather than trusting the earlier read.
    if acc.balance < amount and not Config.Accounts.allowNegative and not opts.force then
        if (amount - acc.balance) > allowance then
            Bank.unlock(accountId) return false, 'insufficient'
        end
    end

    local newBal = acc.balance - amount
    local wrote = pcall(MySQL.update.await, 'UPDATE nz_bank_accounts SET balance = ? WHERE id = ?', { newBal, accountId })
    Bank.unlock(accountId)
    if not wrote then return false, 'db_error' end

    Bank.logTx(accountId, 'out', amount, newBal, opts)
    Bank.pushRefresh(acc)
    return true, newBal
end

local txSinceTrim = {}   -- [accountId] = inserts since we last trimmed

--- Keep only the newest Config.MaxSavedTransactions rows per account.
local function trimTransactions(accountId)
    local keep = Config.MaxSavedTransactions or 0
    if keep <= 0 then return end

    txSinceTrim[accountId] = (txSinceTrim[accountId] or 0) + 1
    if txSinceTrim[accountId] < 10 then return end
    txSinceTrim[accountId] = 0

    MySQL.query([[
        DELETE FROM nz_bank_transactions
        WHERE account_id = ? AND id < (
            SELECT id FROM (
                SELECT id FROM nz_bank_transactions
                WHERE account_id = ? ORDER BY id DESC LIMIT 1 OFFSET ?
            ) AS cutoff
        )
    ]], { accountId, accountId, keep - 1 })
end

function Bank.logTx(accountId, direction, amount, balanceAfter, opts)
    opts = opts or {}
    trimTransactions(accountId)
    -- Who the money went to is written only when the columns are
    -- there. Writing to a column that does not exist would fail the
    -- whole insert, and losing the transaction row is far worse than
    -- losing the name on it.
    if Bank.schema.counterparty then
        MySQL.insert('INSERT INTO nz_bank_transactions (account_id, category, direction, amount, balance_after, label, actor, actor_name, counterparty, counterparty_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            accountId,
            opts.category or 'deposit',
            direction,
            amount,
            balanceAfter,
            opts.label or 'Transaction',
            opts.actor,
            opts.actorName,
            opts.counterparty,
            opts.counterpartyName
        })
        return
    end

    MySQL.insert('INSERT INTO nz_bank_transactions (account_id, category, direction, amount, balance_after, label, actor, actor_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        accountId,
        opts.category or 'deposit',
        direction,
        amount,
        balanceAfter,
        opts.label or 'Transaction',
        opts.actor,
        opts.actorName
    })
end

--- The UI block, with the logo turned into something every page can
--- actually load.
---
--- The bank, the ATM screen and the phone app sit at three different
--- depths in the resource, so no single relative path works for all
--- of them. A bare filename is resolved to a full URL here, once,
--- and anything that already looks like a URL is left alone.
function Bank.uiConfig()
    local ui = {}
    for k, v in pairs(Config.UI or {}) do ui[k] = v end

    -- a bare file name lives in web/images/; a full URL is used as given
    for _, key in ipairs({ 'logo', 'mark' }) do
        local file = ui[key]
        if type(file) == 'string' and file ~= '' and not file:find('^%a[%w+.-]*://') then
            ui[key] = ('https://cfx-nui-%s/web/images/%s'):format(GetCurrentResourceName(), file)
        end
    end

    return ui
end

--- Tell anyone with this account open to refresh.
function Bank.pushRefresh(acc)
    if not acc then return end

    -- let the ESX mirror push the new figure out straight away
    if acc.type == 'personal' then
        local fresh = Bank.getAccountById(acc.id)
        if fresh then TriggerEvent('nz_bank:balanceChanged', acc.owner, fresh.balance) end
    end
    if acc.type == 'personal' or acc.type == 'savings' then
        local xPlayer = ESX.GetPlayerFromIdentifier(acc.owner)
        if xPlayer then TriggerClientEvent('nz_bank:refresh', xPlayer.source) end
        return
    end
    if acc.type == 'society' then
        for _, xp in pairs(ESX.GetExtendedPlayers('job', acc.owner)) do
            TriggerClientEvent('nz_bank:refresh', xp.source)
        end
        return
    end
    -- shared: owner + members
    local ids = MySQL.query.await('SELECT identifier FROM nz_bank_members WHERE account_id = ?', { acc.id }) or {}
    ids[#ids + 1] = { identifier = acc.owner }
    for _, row in ipairs(ids) do
        local xp = ESX.GetPlayerFromIdentifier(row.identifier)
        if xp then TriggerClientEvent('nz_bank:refresh', xp.source) end
    end
end

-- ═══════════════════════════════════════════════════════════
--  DISCORD LOGS
-- ═══════════════════════════════════════════════════════════
function Bank.log(channel, title, description, fields)
    if not Config.Logs.enabled then return end
    local url = Config.Logs.webhook
    if not url or url == '' then return end

    local embed = {{
        title = title,
        description = description,
        color = Config.Logs.colour,
        fields = fields,
        footer = { text = ('%s · %s'):format(Config.Logs.name, os.date('%Y-%m-%d %H:%M:%S')) }
    }}

    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = Config.Logs.name, embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end

-- ═══════════════════════════════════════════════════════════
--  BOOTSTRAP — make sure every player has a personal account
-- ═══════════════════════════════════════════════════════════
local function ensurePlayerNow(xPlayer)
    local identifier = xPlayer.identifier
    local acc = Bank.getPersonal(identifier)

    if not acc then
        local number = Bank.newAccountNumber('PSL')
        -- IGNORE so the unique owner+type key turns a second account away
        -- instead of erroring. The re-read picks up whichever one exists.
        local id = MySQL.insert.await(
            'INSERT IGNORE INTO nz_bank_accounts (account_number, type, owner, label, balance) VALUES (?, "personal", ?, ?, ?)',
            { number, identifier, Bank.fullName(xPlayer), Config.Accounts.startingBalance })
        acc = Bank.getPersonal(identifier)
        if id and id > 0 then
            Bank.debug(('created personal account %s for %s'):format(number, identifier))
        end
    end

    MySQL.insert('INSERT IGNORE INTO nz_bank_credit (identifier, score) VALUES (?, ?)',
        { identifier, Config.Credit.starting })
    MySQL.insert('INSERT IGNORE INTO nz_bank_settings (identifier) VALUES (?)', { identifier })

    return acc
end

--- One at a time per player. getData and playerLoaded both land here on
--- join, and two of them racing would each open an account with the
--- starting money in it.
function Bank.ensurePlayer(xPlayer)
    local acc = Bank.serial('player:' .. tostring(xPlayer.identifier), ensurePlayerNow, xPlayer)
    return acc or Bank.getPersonal(xPlayer.identifier)
end

AddEventHandler('esx:playerLoaded', function(src, xPlayer)
    CreateThread(function()
        Bank.ensurePlayer(xPlayer)
    end)
end)

AddEventHandler('playerDropped', function()
    Bank.session[source] = nil
end)

-- Society accounts for every configured job
CreateThread(function()
    Wait(2500)
    for job in pairs(Config.Accounts.societyAccess) do
        if not Bank.getSociety(job) then
            local number = Bank.newAccountNumber('SOC')
            MySQL.insert.await(
                'INSERT INTO nz_bank_accounts (account_number, type, owner, label, balance) VALUES (?, "society", ?, ?, 0)',
                { number, job, (job:gsub('^%l', string.upper)) })
            Bank.debug('created society account for ' .. job)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  UPDATE CHECK
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    if not Config.UpdateCheck or not Config.UpdateCheck.enabled then return end
    if not Config.UpdateCheck.url or Config.UpdateCheck.url == '' then return end

    Wait(8000)
    local current = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)

    PerformHttpRequest(Config.UpdateCheck.url, function(code, body)
        if code ~= 200 or not body then return end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' or not data.version then return end

        if data.version ~= current then
            print(('^3[nayzeee-banking]^7 update available: ^2%s^7 (running %s)'):format(data.version, current))
            if data.notes then print('^3[nayzeee-banking]^7 ' .. tostring(data.notes)) end
        end
    end, 'GET')
end)

-- ═══════════════════════════════════════════════════════════
--  EXPORTS for other resources
-- ═══════════════════════════════════════════════════════════
exports('getBalance', function(identifier)
    local acc = Bank.getPersonal(identifier)
    return acc and acc.balance or 0
end)

exports('addMoney', function(identifier, amount, label, category)
    local acc = Bank.getPersonal(identifier)
    if not acc then return false end
    return Bank.credit(acc.id, amount, {
        category = category or 'deposit', label = label or 'Deposit'
    })
end)

exports('removeMoney', function(identifier, amount, label, category)
    local acc = Bank.getPersonal(identifier)
    if not acc then return false end
    return Bank.debit(acc.id, amount, {
        category = category or 'withdraw', label = label or 'Withdrawal'
    })
end)

exports('getSocietyBalance', function(job)
    local acc = Bank.getSociety(job)
    return acc and acc.balance or 0
end)

exports('addSocietyMoney', function(job, amount, label)
    local acc = Bank.getSociety(job)
    if not acc then return false end
    return Bank.credit(acc.id, amount, { category = 'deposit', label = label or 'Society deposit' })
end)

exports('removeSocietyMoney', function(job, amount, label)
    local acc = Bank.getSociety(job)
    if not acc then return false end
    return Bank.debit(acc.id, amount, { category = 'withdraw', label = label or 'Society withdrawal' })
end)

exports('createBill', function(identifier, issuerJob, amount, reason, senderName)
    return Bank.createBill(identifier, issuerJob, amount, reason, senderName)
end)
