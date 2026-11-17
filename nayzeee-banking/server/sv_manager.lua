if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BANKING MANAGER
--
--  /bankingmanager opens one panel for staff: the bank at a glance,
--  every player's money and accounts, the societies, the branches
--  and their tellers on a map, the money counter on each counter,
--  every setting in config.lua, the market, and a log of what staff
--  did. Every callback checks the permission again on its own, so
--  a client that fakes its way into the panel gets nothing back.
--
--  From the server console (txAdmin): bankingmanager give|take
--  <playerId|account number> <amount> · check <playerId|account>
-- ═══════════════════════════════════════════════════════════

local function adminCfg() return Config.Admin or {} end

function Bank.isAdmin(src)
    if src == 0 then return true end
    local ace = adminCfg().ace or 'nayzeee.banking'
    if IsPlayerAceAllowed(src, ace) then return true end
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer or not xPlayer.getGroup then return false end
    local group = xPlayer.getGroup()
    for _, g in ipairs(adminCfg().allowGroups or {}) do
        if group == g then return true end
    end
    return false
end

local function who(src)
    if src == 0 then return 'console', 'Console' end
    local x = Bank.getPlayer(src)
    return x and x.identifier or ('player:' .. src), x and Bank.fullName(x) or GetPlayerName(src) or 'Staff'
end

--- Everything staff do is written down, in the database and the Discord log.
local function audit(src, action, target, detail)
    local id, name = who(src)
    MySQL.insert('INSERT INTO nz_bank_audit (admin, admin_name, action, target, detail) VALUES (?, ?, ?, ?, ?)',
        { id, Bank.cut(name, 64), Bank.cut(action, 48), target and Bank.cut(tostring(target), 96) or nil,
          detail and Bank.cut(tostring(detail), 255) or nil })
    Bank.log('admin', 'Banking Manager · ' .. action,
        ('**%s** · %s%s'):format(name, tostring(target or ''), detail and (' · ' .. tostring(detail)) or ''))
end

--- A manager callback: refused unless the caller is staff.
local function staff(name, fn)
    Bank.callback('nz_bank:mgr:' .. name, function(src, ...)
        if not Bank.isAdmin(src) then return { ok = false, msg = 'You do not have access to the Banking Manager.' } end
        return fn(src, ...)
    end)
end

local function fail(msg) return { ok = false, msg = msg } end

-- ═══════════════════════════════════════════════════════════
--  PEOPLE
-- ═══════════════════════════════════════════════════════════
local function online()
    local out = {}
    for _, x in pairs(ESX.GetExtendedPlayers() or {}) do
        if x and x.identifier then out[x.identifier] = x end
    end
    return out
end

local function jobOf(x)
    local j = x and x.job
    if not j then return nil end
    return ('%s · %s'):format(j.label or j.name or '?', j.grade_label or j.grade_name or tostring(j.grade or ''))
end

--- A character's name while they are offline, from the framework's own table.
local function offlineName(identifier)
    local ok, name = pcall(function()
        if Framework.name == 'esx' then
            local r = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
            return r and ('%s %s'):format(r.firstname or '', r.lastname or '') or nil
        end
        local r = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
        local info = r and r.charinfo and json.decode(r.charinfo)
        return info and ('%s %s'):format(info.firstname or '', info.lastname or '') or nil
    end)
    name = ok and name and name:match('^%s*(.-)%s*$') or nil
    return name ~= '' and name or nil
end

--- Characters, online or not, whose name matches. Empty when the framework's
--- table is not where it usually is; the account search still works then.
local function searchNames(q)
    local like = '%' .. q .. '%'
    local ok, rows = pcall(function()
        if Framework.name == 'esx' then
            return MySQL.query.await([[SELECT identifier, CONCAT(firstname, ' ', lastname) AS name FROM users
                WHERE CONCAT(firstname, ' ', lastname) LIKE ? LIMIT 20]], { like })
        end
        return MySQL.query.await([[SELECT citizenid AS identifier, charinfo FROM players WHERE charinfo LIKE ? LIMIT 20]], { like })
    end)
    local out = {}
    for _, r in ipairs(ok and rows or {}) do
        local name = r.name
        if not name and r.charinfo then
            local good, info = pcall(json.decode, r.charinfo)
            name = good and info and ('%s %s'):format(info.firstname or '', info.lastname or '') or nil
        end
        out[#out + 1] = { identifier = r.identifier, name = name }
    end
    return out
end

local function personalBalance(identifier)
    return MySQL.scalar.await([[SELECT balance FROM nz_bank_accounts WHERE owner = ? AND type = 'personal' LIMIT 1]],
        { identifier })
end

staff('players', function(src, query)
    query = tostring(query or ''):sub(1, 48):match('^%s*(.-)%s*$')
    local live = online()
    local rows, seen = {}, {}

    local function add(identifier, name, x)
        if not identifier or seen[identifier] then return end
        seen[identifier] = true
        rows[#rows + 1] = {
            identifier = identifier,
            name   = (x and Bank.fullName(x)) or name or offlineName(identifier) or identifier,
            src    = x and x.source or nil,
            job    = jobOf(x),
            cash   = x and (Bank.getCash(x) or 0) or nil,
            bank   = personalBalance(identifier),
        }
    end

    if query == '' then
        for identifier, x in pairs(live) do add(identifier, nil, x) end
    else
        local q = query:lower()
        local asId = tonumber(query)
        for identifier, x in pairs(live) do
            if (asId and x.source == asId) or Bank.fullName(x):lower():find(q, 1, true)
                or identifier:lower():find(q, 1, true) then
                add(identifier, nil, x)
            end
        end
        for _, r in ipairs(searchNames(query)) do add(r.identifier, r.name, live[r.identifier]) end
        for _, r in ipairs(MySQL.query.await([[SELECT DISTINCT owner FROM nz_bank_accounts
            WHERE type IN ('personal','savings') AND (account_number LIKE ? OR owner = ?) LIMIT 20]],
            { '%' .. query .. '%', query }) or {}) do
            add(r.owner, nil, live[r.owner])
        end
    end

    table.sort(rows, function(a, b)
        if (a.src ~= nil) ~= (b.src ~= nil) then return a.src ~= nil end
        return tostring(a.name) < tostring(b.name)
    end)
    while #rows > 60 do rows[#rows] = nil end
    return { ok = true, rows = rows }
end)

local BY_TYPE = [[ORDER BY FIELD(type, 'personal', 'savings', 'shared', 'society'), id]]

local function accountRows(where, args, tail)
    local rows = MySQL.query.await(([[SELECT id, account_number, type, owner, label, balance, frozen
        FROM nz_bank_accounts WHERE %s %s]]):format(where, tail or BY_TYPE), args) or {}
    for _, r in ipairs(rows) do r.frozen = Bank.flag(r.frozen) end
    return rows
end

staff('player', function(src, identifier)
    identifier = tostring(identifier or '')
    if identifier == '' then return fail('No player.') end
    local x = online()[identifier]

    local accounts = accountRows('owner = ?', { identifier })
    -- shared accounts they are on but do not own
    for _, r in ipairs(accountRows([[id IN (SELECT account_id FROM nz_bank_members WHERE identifier = ?) AND owner <> ?]],
        { identifier, identifier })) do
        r.member = true
        accounts[#accounts + 1] = r
    end
    if #accounts == 0 and not x then return fail('Nobody with that identifier has banked here.') end

    local credit = Bank.getCredit(identifier)
    local ids = {}
    for _, a in ipairs(accounts) do ids[#ids + 1] = a.id end

    local tx = {}
    if #ids > 0 then
        tx = MySQL.query.await(([[SELECT t.id, t.account_id, a.account_number, t.category, t.direction, t.amount,
            t.balance_after, t.label, t.actor_name, UNIX_TIMESTAMP(t.created_at) AS at
            FROM nz_bank_transactions t JOIN nz_bank_accounts a ON a.id = t.account_id
            WHERE t.account_id IN (%s) ORDER BY t.id DESC LIMIT 40]]):format(table.concat(ids, ',')), {}) or {}
    end

    local cards = MySQL.query.await([[SELECT c.id, c.card_number, c.card_type, c.kind, c.holder, c.status, c.balance,
        c.credit_limit, a.account_number FROM nz_bank_cards c JOIN nz_bank_accounts a ON a.id = c.account_id
        WHERE a.owner = ? OR c.holder_identifier = ? ORDER BY c.id]], { identifier, identifier }) or {}
    for _, c in ipairs(cards) do c.card_number = '•••• ' .. tostring(c.card_number):sub(-4) end

    local loans = MySQL.query.await([[SELECT id, tier, principal, remaining, payment, missed, status, next_payment
        FROM nz_bank_loans WHERE identifier = ? ORDER BY FIELD(status, 'active', 'defaulted', 'paid'), id DESC LIMIT 12]],
        { identifier }) or {}

    local bills = MySQL.query.await([[SELECT id, issuer_label, amount, reason, status FROM nz_bank_bills
        WHERE identifier = ? AND status IN ('pending', 'overdue') ORDER BY id DESC LIMIT 12]], { identifier }) or {}

    return { ok = true, player = {
        identifier = identifier,
        name   = x and Bank.fullName(x) or offlineName(identifier) or identifier,
        src    = x and x.source or nil,
        job    = jobOf(x),
        cash   = x and (Bank.getCash(x) or 0) or nil,
        credit = { score = credit.score, band = Bank.creditBand(credit.score),
                   min = Config.Credit.min, max = Config.Credit.max },
        accounts = accounts, tx = tx, cards = cards, loans = loans, bills = bills,
    } }
end)

-- ── money ────────────────────────────────────────────────
staff('adjust', function(src, accountId, mode, amount, reason)
    local acc = Bank.getAccountById(tonumber(accountId))
    if not acc then return fail('That account is gone.') end
    amount = Bank.round(tonumber(amount) or 0)
    reason = Bank.cut(tostring(reason or ''):match('^%s*(.-)%s*$'), 60)
    local label = reason ~= '' and ('Adjustment · ' .. reason) or 'Adjustment'
    local _, name = who(src)
    local opts = { category = 'admin', label = label, actorName = name, force = true, noOverdraft = true }

    if mode == 'set' then
        if amount < 0 then return fail('A balance cannot be set below zero here.') end
        local delta = amount - acc.balance
        if delta == 0 then return { ok = true, msg = 'That is already the balance.' } end
        mode, amount = delta > 0 and 'add' or 'remove', math.abs(delta)
    end
    if amount <= 0 then return fail('Enter an amount above zero.') end

    local ok, why
    if mode == 'add' then ok, why = Bank.credit(acc.id, amount, opts)
    elseif mode == 'remove' then
        if acc.balance < amount then return fail(('Only %s%s in that account.'):format(Config.Currency, acc.balance)) end
        ok, why = Bank.debit(acc.id, amount, opts)
    else return fail('Unknown action.') end
    if not ok then return fail(why == 'busy' and 'The account is busy; try again.' or 'That did not go through.') end

    audit(src, mode == 'add' and 'Added money' or 'Removed money', acc.account_number,
        ('%s%s%s'):format(Config.Currency, amount, reason ~= '' and (' · ' .. reason) or ''))
    return { ok = true, msg = ('%s %s%s %s %s.'):format(mode == 'add' and 'Added' or 'Removed', Config.Currency, amount,
        mode == 'add' and 'to' or 'from', acc.account_number) }
end)

staff('freeze', function(src, accountId, frozen)
    local acc = Bank.getAccountById(tonumber(accountId))
    if not acc then return fail('That account is gone.') end
    MySQL.update.await('UPDATE nz_bank_accounts SET frozen = ? WHERE id = ?', { frozen and 1 or 0, acc.id })
    Bank.pushRefresh(acc)
    audit(src, frozen and 'Froze account' or 'Unfroze account', acc.account_number)
    return { ok = true, msg = ('%s %s.'):format(acc.account_number, frozen and 'frozen' or 'unfrozen') }
end)

staff('rename', function(src, accountId, label)
    local acc = Bank.getAccountById(tonumber(accountId))
    label = Bank.cut(tostring(label or ''):match('^%s*(.-)%s*$'), 40)
    if not acc then return fail('That account is gone.') end
    if label == '' then return fail('Give the account a name.') end
    MySQL.update.await('UPDATE nz_bank_accounts SET label = ? WHERE id = ?', { label, acc.id })
    audit(src, 'Renamed account', acc.account_number, label)
    return { ok = true, msg = 'Account renamed.' }
end)

staff('wallet', function(src, target, mode, amount)
    local x = Bank.getPlayer(tonumber(target))
    if not x then return fail('That player is not in the city.') end
    amount = Bank.round(tonumber(amount) or 0)
    if amount <= 0 then return fail('Enter an amount above zero.') end
    local ok
    if mode == 'add' then ok = Bank.addCash(x, amount) ~= false
    else
        if (Bank.getCash(x) or 0) < amount then return fail('They are not carrying that much.') end
        ok = Bank.removeCash(x, amount) ~= false
    end
    if not ok then return fail('Their inventory did not take it.') end
    audit(src, mode == 'add' and 'Gave cash' or 'Took cash', Bank.fullName(x), Config.Currency .. amount)
    return { ok = true, msg = ('%s %s%s %s %s.'):format(mode == 'add' and 'Gave' or 'Took', Config.Currency, amount,
        mode == 'add' and 'to' or 'from', Bank.fullName(x)) }
end)

staff('credit', function(src, identifier, score)
    score = math.floor(tonumber(score) or -1)
    if score < Config.Credit.min or score > Config.Credit.max then
        return fail(('A score runs from %s to %s.'):format(Config.Credit.min, Config.Credit.max))
    end
    local row = Bank.getCredit(identifier)
    MySQL.update.await('UPDATE nz_bank_credit SET score = ? WHERE identifier = ?', { score, identifier })
    MySQL.insert('INSERT INTO nz_bank_credit_history (identifier, score, delta, reason) VALUES (?, ?, ?, ?)',
        { identifier, score, score - row.score, 'Set by the bank' })
    audit(src, 'Set credit score', identifier, ('%s → %s'):format(row.score, score))
    return { ok = true, msg = ('Credit score set to %s.'):format(score) }
end)

staff('loan', function(src, loanId, action)
    local loan = MySQL.single.await('SELECT id, identifier, remaining, status FROM nz_bank_loans WHERE id = ?', { tonumber(loanId) })
    if not loan then return fail('That loan is gone.') end
    if action == 'forgive' then
        MySQL.update.await([[UPDATE nz_bank_loans SET status = 'paid', remaining = 0, closed_at = ? WHERE id = ?]],
            { os.time(), loan.id })
        audit(src, 'Forgave loan', loan.identifier, ('#%s · %s%s left'):format(loan.id, Config.Currency, loan.remaining))
        return { ok = true, msg = 'Loan written off.' }
    elseif action == 'missed' then
        MySQL.update.await('UPDATE nz_bank_loans SET missed = 0 WHERE id = ?', { loan.id })
        audit(src, 'Cleared missed payments', loan.identifier, '#' .. loan.id)
        return { ok = true, msg = 'Missed payments cleared.' }
    end
    return fail('Unknown action.')
end)

staff('card', function(src, cardId, status)
    if status ~= 'active' and status ~= 'blocked' then return fail('Unknown status.') end
    local card = MySQL.single.await('SELECT id, card_number FROM nz_bank_cards WHERE id = ?', { tonumber(cardId) })
    if not card then return fail('That card is gone.') end
    MySQL.update.await('UPDATE nz_bank_cards SET status = ? WHERE id = ?', { status, card.id })
    audit(src, status == 'active' and 'Unblocked card' or 'Blocked card', '•••• ' .. tostring(card.card_number):sub(-4))
    return { ok = true, msg = status == 'active' and 'Card unblocked.' or 'Card blocked.' }
end)

staff('bill', function(src, billId)
    local bill = MySQL.single.await('SELECT id, identifier, amount, reason FROM nz_bank_bills WHERE id = ?', { tonumber(billId) })
    if not bill then return fail('That bill is gone.') end
    MySQL.update.await([[UPDATE nz_bank_bills SET status = 'void' WHERE id = ?]], { bill.id })
    audit(src, 'Cancelled bill', bill.identifier, ('%s%s · %s'):format(Config.Currency, bill.amount, bill.reason))
    return { ok = true, msg = 'Bill cancelled.' }
end)

staff('transactions', function(src, accountId)
    local rows = MySQL.query.await([[SELECT id, category, direction, amount, balance_after, label, actor_name,
        UNIX_TIMESTAMP(created_at) AS at FROM nz_bank_transactions WHERE account_id = ? ORDER BY id DESC LIMIT 60]],
        { tonumber(accountId) }) or {}
    return { ok = true, rows = rows }
end)

staff('societies', function()
    local rows = accountRows([[type = 'society']], {})
    for _, r in ipairs(rows) do
        r.members = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_members WHERE account_id = ?', { r.id }) or 0
    end
    return { ok = true, rows = rows }
end)

local KINDS = { personal = true, savings = true, shared = true, society = true }

staff('accounts', function(src, query, kind)
    query = tostring(query or ''):sub(1, 40)
    local like = '%' .. query .. '%'
    local where, args = '(account_number LIKE ? OR label LIKE ? OR owner LIKE ?)', { like, like, like }
    if KINDS[kind] then
        where = where .. ' AND type = ?'
        args[#args + 1] = kind
    end
    local rows = accountRows(where, args, 'ORDER BY balance DESC LIMIT 60')
    local counts = {}
    for _, r in ipairs(MySQL.query.await([[SELECT type, COUNT(*) AS n FROM nz_bank_accounts
        WHERE account_number LIKE ? OR label LIKE ? OR owner LIKE ? GROUP BY type]], { like, like, like }) or {}) do
        counts[r.type] = tonumber(r.n) or 0
    end
    return { ok = true, rows = rows, counts = counts }
end)

-- ═══════════════════════════════════════════════════════════
--  THE BANK AT A GLANCE
-- ═══════════════════════════════════════════════════════════
staff('overview', function(src, range)
    range = ({ [7] = 7, [14] = 14, [30] = 30 })[tonumber(range) or 7] or 7
    local byType, total = {}, 0
    for _, r in ipairs(MySQL.query.await([[SELECT type, COUNT(*) AS n, COALESCE(SUM(balance), 0) AS sum
        FROM nz_bank_accounts GROUP BY type]]) or {}) do
        byType[r.type] = { n = r.n, sum = tonumber(r.sum) or 0 }
        total = total + (tonumber(r.sum) or 0)
    end

    local loans = MySQL.single.await([[SELECT COUNT(*) AS n, COALESCE(SUM(remaining), 0) AS owed,
        SUM(status = 'defaulted') AS bad FROM nz_bank_loans WHERE status IN ('active', 'defaulted')]]) or {}
    local bills = MySQL.single.await([[SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS sum,
        SUM(status = 'overdue') AS late FROM nz_bank_bills WHERE status IN ('pending', 'overdue')]]) or {}
    local cards = MySQL.single.await([[SELECT SUM(status = 'active') AS live, SUM(status <> 'active') AS stopped,
        COALESCE(SUM(balance), 0) AS owed FROM nz_bank_cards]]) or {}

    -- money in and out, day by day over the range
    local days = {}
    for i = range - 1, 0, -1 do days[#days + 1] = { d = os.date('%Y-%m-%d', os.time() - i * 86400), inn = 0, out = 0, n = 0 } end
    local index = {}
    for i, d in ipairs(days) do index[d.d] = i end
    for _, r in ipairs(MySQL.query.await([[SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS d, direction,
        COUNT(*) AS n, COALESCE(SUM(amount), 0) AS sum FROM nz_bank_transactions
        WHERE created_at >= CURDATE() - INTERVAL ? DAY AND category NOT IN ('transfer') GROUP BY d, direction]], { range - 1 }) or {}) do
        local d = days[index[r.d] or 0]
        if d then
            if r.direction == 'in' then d.inn = tonumber(r.sum) or 0 else d.out = tonumber(r.sum) or 0 end
            d.n = d.n + (tonumber(r.n) or 0)
        end
    end

    local top = accountRows('1 = 1', {}, 'ORDER BY balance DESC LIMIT 8')

    -- how the bank is doing: what is stuck, what is below zero, what is new
    local health = MySQL.single.await([[SELECT SUM(frozen = 1) AS frozen, SUM(balance < 0) AS overdrawn,
        COALESCE(SUM(CASE WHEN balance < 0 THEN balance END), 0) AS below,
        SUM(created_at >= CURDATE() - INTERVAL 6 DAY) AS fresh FROM nz_bank_accounts]]) or {}
    local today = MySQL.single.await([[SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS sum,
        COUNT(DISTINCT account_id) AS accounts FROM nz_bank_transactions WHERE created_at >= CURDATE()]]) or {}
    local audits = MySQL.query.await([[SELECT admin_name, action, target, detail, UNIX_TIMESTAMP(created_at) AS at
        FROM nz_bank_audit ORDER BY id DESC LIMIT 8]]) or {}

    local playersOnline = 0
    for _ in pairs(online()) do playersOnline = playersOnline + 1 end

    return { ok = true, data = {
        total = total, byType = byType, online = playersOnline, branches = #Config.Banks,
        loans = { n = tonumber(loans.n) or 0, owed = tonumber(loans.owed) or 0, bad = tonumber(loans.bad) or 0 },
        bills = { n = tonumber(bills.n) or 0, sum = tonumber(bills.sum) or 0, late = tonumber(bills.late) or 0 },
        cards = { live = tonumber(cards.live) or 0, stopped = tonumber(cards.stopped) or 0, owed = tonumber(cards.owed) or 0 },
        days = days, top = top, audits = audits, range = range,
        health = { frozen = tonumber(health.frozen) or 0, overdrawn = tonumber(health.overdrawn) or 0,
                   below = tonumber(health.below) or 0, fresh = tonumber(health.fresh) or 0 },
        today = { n = tonumber(today.n) or 0, sum = tonumber(today.sum) or 0, accounts = tonumber(today.accounts) or 0 },
    } }
end)

staff('audit', function(src, page)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local rows = MySQL.query.await([[SELECT admin_name, action, target, detail, UNIX_TIMESTAMP(created_at) AS at
        FROM nz_bank_audit ORDER BY id DESC LIMIT 16 OFFSET ?]], { (page - 1) * 16 }) or {}
    local total = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_audit') or 0
    return { ok = true, rows = rows, pages = math.max(1, math.ceil(total / 16)), page = page, total = total }
end)

-- ═══════════════════════════════════════════════════════════
--  SETTINGS
-- ═══════════════════════════════════════════════════════════
local function settingsPayload()
    local values, overridden = {}, {}
    for path, it in pairs(NZManager.items) do
        local v = NZManager.plain(NZManager.get(path))
        -- a secret (the webhook) is only ever said to be set, never sent
        if it.s then v = (v and v ~= '') and '••••••••' or '' end
        values[path] = v
        overridden[path] = NZManager.overrides[path] ~= nil
    end
    return { groups = NZManager.groups, values = values, overridden = overridden }
end

staff('settings', function() return { ok = true, data = settingsPayload() } end)

local function copy(t)
    local o = {}
    for k, v in pairs(t or {}) do o[k] = v end
    return o
end

staff('setting', function(src, path, value, reset)
    local it = NZManager.items[tostring(path)]
    if not it then return fail('Unknown setting.') end
    local over = copy(NZManager.overrides)
    local before = NZManager.plain(NZManager.get(path))

    if reset then
        over[path] = nil
    else
        local v = NZManager.coerce(it, value)
        if v == nil then return fail('That value does not fit this setting.') end
        over[path] = v
    end
    NZManager.save(over)

    local after = NZManager.plain(NZManager.get(path))
    audit(src, reset and 'Reset setting' or 'Changed setting', path,
        it.s and 'hidden' or ('%s → %s'):format(tostring(before), tostring(after)))
    if it.s then after = (after and after ~= '') and '••••••••' or '' end
    return { ok = true, restart = it.r == true, value = after, overridden = over[path] ~= nil,
             msg = it.r and 'Saved. It takes hold when the resource restarts.' or 'Saved.' }
end)

staff('resetSettings', function(src)
    local over = {}
    -- branches and counters are kept: they have their own reset
    over['Banks'] = NZManager.overrides['Banks']
    over['Teller.banks'] = NZManager.overrides['Teller.banks']
    NZManager.save(over)
    audit(src, 'Reset every setting', 'config.lua')
    return { ok = true, msg = 'Every setting is back to config.lua.', data = settingsPayload() }
end)

--- The changes made here as Lua, to paste into config.lua for good.
staff('export', function()
    local function lua(v, indent)
        indent = indent or ''
        local tv = type(v)
        if tv == 'string' then return ('%q'):format(v) end
        if tv ~= 'table' then return tostring(v) end
        if v.x and v.y and v.z and v.w then return ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(v.x, v.y, v.z, v.w) end
        if v.x and v.y and v.z then return ('vec3(%.2f, %.2f, %.2f)'):format(v.x, v.y, v.z) end
        local parts = {}
        for k, x in pairs(v) do
            local key = type(k) == 'number' and ('[%d]'):format(k) or k
            parts[#parts + 1] = ('%s    %s = %s,'):format(indent, key, lua(x, indent .. '    '))
        end
        table.sort(parts)
        return '{\n' .. table.concat(parts, '\n') .. '\n' .. indent .. '}'
    end

    local lines = { '-- Changes made in /bankingmanager. Paste below the matching section of config.lua.' }
    local paths = {}
    for path in pairs(NZManager.overrides) do
        if NZManager.items[path] and not NZManager.items[path].s then paths[#paths + 1] = path end
    end
    table.sort(paths)
    for _, path in ipairs(paths) do lines[#lines + 1] = ('Config.%s = %s'):format(path, lua(NZManager.get(path))) end

    if NZManager.overrides['Banks'] then
        lines[#lines + 1] = 'Config.Banks = {'
        for _, b in ipairs(NZManager.banksPlain()) do
            lines[#lines + 1] = ('    { label = %q, coords = vector4(%.2f, %.2f, %.2f, %.2f), ped = %q },')
                :format(b.label, b.x, b.y, b.z, b.w, b.ped)
        end
        lines[#lines + 1] = '}'
    end
    if NZManager.overrides['Teller.banks'] then
        local per = {}
        for _, c in ipairs(NZManager.countersPlain()) do per[c.i] = { machine = c.machine,
            machineHeading = c.machineHeading, counter = c.counter } end
        lines[#lines + 1] = 'Config.Teller.banks = ' .. lua(per)
    end
    if #lines == 1 then lines[#lines + 1] = '-- nothing changed yet' end
    return { ok = true, text = table.concat(lines, '\n') }
end)

-- ═══════════════════════════════════════════════════════════
--  BRANCHES, TELLERS AND THE MONEY COUNTER
-- ═══════════════════════════════════════════════════════════
local function branchesPayload()
    local counters = {}
    for _, c in ipairs(NZManager.countersPlain()) do counters[c.i] = c end
    local out = {}
    for i, b in ipairs(NZManager.banksPlain()) do
        b.i = i
        b.counter = counters[i]
        out[i] = b
    end
    local T = Config.Teller or {}
    return { rows = out, edited = NZManager.overrides['Banks'] ~= nil,
             default = { machine = NZManager.plain(T.machine), machineHeading = T.machineHeading,
                         counter = NZManager.plain(T.counter) } }
end

staff('branches', function() return { ok = true, data = branchesPayload() } end)

local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.max(lo, math.min(hi, v))
end

local function saveBranches(src, rows, counters, action, target)
    local over = copy(NZManager.overrides)
    over['Banks'] = rows
    if counters then over['Teller.banks'] = counters end
    NZManager.save(over)
    audit(src, action, target)
    return { ok = true, data = branchesPayload() }
end

--- Add a branch (index nil) or change one: name, teller model, where they stand.
staff('branchSave', function(src, index, row)
    if type(row) ~= 'table' then return fail('Nothing to save.') end
    local clean = {
        label = Bank.cut(tostring(row.label or 'Bank'):match('^%s*(.-)%s*$'), 40),
        ped   = tostring(row.ped or 'ig_bankman'):match('^[%w_]+$') or 'ig_bankman',
        x = num(row.x, -10000, 10000), y = num(row.y, -10000, 10000),
        z = num(row.z, -500, 3000), w = num(row.w, -360, 360),
    }
    if not (clean.x and clean.y and clean.z and clean.w) then return fail('That position is not on the map.') end
    if clean.label == '' then clean.label = 'Bank' end

    local rows = NZManager.banksPlain()
    index = tonumber(index)
    if index and index < 1 then index = nil end   -- 0: a new branch
    if index then
        if not rows[index] then return fail('That branch is gone.') end
        rows[index] = clean
    else
        rows[#rows + 1] = clean
    end
    return saveBranches(src, rows, nil, index and 'Moved or edited branch' or 'Added branch',
        ('%s (%.1f, %.1f, %.1f)'):format(clean.label, clean.x, clean.y, clean.z))
end)

staff('branchDelete', function(src, index)
    index = tonumber(index)
    local rows = NZManager.banksPlain()
    if not index or not rows[index] then return fail('That branch is gone.') end
    local gone = table.remove(rows, index)
    -- each counter is filed under its branch's place in the list: move the later ones up
    local counters = {}
    for _, c in ipairs(NZManager.countersPlain()) do
        if c.i < index then counters[#counters + 1] = c
        elseif c.i > index then c.i = c.i - 1 counters[#counters + 1] = c end
    end
    return saveBranches(src, rows, counters, 'Removed branch', gone.label)
end)

staff('branchesReset', function(src)
    local over = copy(NZManager.overrides)
    over['Banks'], over['Teller.banks'] = nil, nil
    NZManager.save(over)
    audit(src, 'Reset branches', 'config.lua')
    return { ok = true, data = branchesPayload() }
end)

--- The money counter and the cash spot on one branch's counter, from the teller.
staff('counterSave', function(src, index, c)
    index = tonumber(index)
    if not index or not Config.Banks[index] or type(c) ~= 'table' then return fail('That branch is gone.') end
    local function v3(t)
        if type(t) ~= 'table' then return nil end
        local x, y, z = num(t.x, -3, 3), num(t.y, -3, 3), num(t.z, -1, 2)
        return (x and y and z) and { x = x, y = y, z = z } or nil
    end
    local entry = { i = index, machine = v3(c.machine), machineHeading = num(c.machineHeading, -360, 360), counter = v3(c.counter) }
    local counters = {}
    for _, old in ipairs(NZManager.countersPlain()) do
        if old.i ~= index then counters[#counters + 1] = old end
    end
    if c.reset ~= true then counters[#counters + 1] = entry end
    local over = copy(NZManager.overrides)
    over['Teller.banks'] = counters
    NZManager.save(over)
    audit(src, c.reset and 'Reset money counter' or 'Placed money counter', Config.Banks[index].label .. ' #' .. index)
    return { ok = true, data = branchesPayload() }
end)

-- ═══════════════════════════════════════════════════════════
--  MARKET
-- ═══════════════════════════════════════════════════════════
staff('market', function()
    local rows = {}
    for _, a in ipairs(Config.Market.assets or {}) do
        local m = Bank.market and Bank.market[a.id]
        local held = MySQL.single.await([[SELECT COUNT(*) AS n, COALESCE(SUM(units), 0) AS units
            FROM nz_bank_holdings WHERE asset = ? AND units > 0]], { a.id }) or {}
        local hist = {}
        local h = m and m.history or {}
        for i = math.max(1, #h - 59), #h do hist[#hist + 1] = h[i] end
        local price = m and m.price or a.start
        rows[#rows + 1] = { id = a.id, label = a.label, kind = a.kind, price = price,
            open = m and m.open or a.start, floor = a.floor, ceiling = a.ceiling, start = a.start,
            volatility = a.volatility, history = hist, holders = tonumber(held.n) or 0,
            units = tonumber(held.units) or 0, invested = math.floor((tonumber(held.units) or 0) * price) }
    end
    return { ok = true, rows = rows }
end)

staff('marketSet', function(src, id, price)
    if not Bank.setMarketPrice then return fail('The market is not running.') end
    local ok, set = Bank.setMarketPrice(tostring(id), price)
    if not ok then return fail('That asset or price is not valid.') end
    audit(src, 'Set market price', id, Config.Currency .. set)
    return { ok = true, msg = ('%s is now %s%s.'):format(id, Config.Currency, set) }
end)

-- ═══════════════════════════════════════════════════════════
--  OPENING IT
-- ═══════════════════════════════════════════════════════════
staff('boot', function(src)
    local _, name = who(src)
    return { ok = true, data = {
        me = name, currency = Config.Currency, ui = Bank.uiConfig(), version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0),
        framework = Framework.name, inventory = Bank.inventory(),
    } }
end)

local function console(args)
    local action = (args[1] or ''):lower()
    local target = args[2]
    local function account()
        local asId = tonumber(target)
        local x = asId and Bank.getPlayer(asId)
        if x then return Bank.getPersonal(x.identifier), Bank.fullName(x) end
        local acc = target and Bank.getAccountByNumber and Bank.getAccountByNumber(target)
        return acc, acc and acc.label
    end

    if action == 'give' or action == 'take' then
        local acc, name = account()
        local amount = Bank.round(tonumber(args[3]) or 0)
        if not acc or amount <= 0 then return Console.log('warn', 'usage: bankingmanager %s <playerId|account> <amount>', action) end
        local opts = { category = 'admin', label = 'Adjustment', actorName = 'Console', force = true, noOverdraft = true }
        local ok = action == 'give' and Bank.credit(acc.id, amount, opts) or Bank.debit(acc.id, amount, opts)
        audit(0, action == 'give' and 'Added money' or 'Removed money', acc.account_number, Config.Currency .. amount)
        Console.log(ok and 'ok' or 'error', '%s %s%s %s %s', ok and (action == 'give' and 'added' or 'removed') or 'could not move',
            Config.Currency, amount, action == 'give' and 'to' or 'from', name or acc.account_number)
    elseif action == 'check' then
        local acc, name = account()
        if not acc then return Console.log('warn', 'usage: bankingmanager check <playerId|account>') end
        Console.log('info', '%s · %s · %s%s%s', name or acc.label, acc.account_number, Config.Currency, acc.balance,
            Bank.flag(acc.frozen) and ' · frozen' or '')
    else
        Console.log('info', 'in game: /%s opens the panel · console: %s give|take <playerId|account> <amount> · check <playerId|account>',
            adminCfg().command or 'bankingmanager', adminCfg().command or 'bankingmanager')
    end
end

-- the startup block says when the live settings are not config.lua's
do
    local n = 0
    for path in pairs(NZManager.overrides or {}) do if NZManager.items[path] then n = n + 1 end end
    local parts = {}
    if n > 0 then parts[#parts + 1] = ('%d setting%s changed'):format(n, n == 1 and '' or 's') end
    if NZManager.overrides['Banks'] then parts[#parts + 1] = ('%d branches set'):format(#Config.Banks) end
    if NZManager.overrides['Teller.banks'] then parts[#parts + 1] = 'counters placed' end
    Console.check('manager', 'info', 'Manager', #parts > 0
        and (table.concat(parts, ', ') .. ' in /' .. (adminCfg().command or 'bankingmanager'))
        or ('/' .. (adminCfg().command or 'bankingmanager') .. ' for staff; running on config.lua'))
end

RegisterCommand(adminCfg().command or 'bankingmanager', function(src, args)
    if src == 0 then return console(args) end
    if not Bank.isAdmin(src) then
        return Bank.notify(src, 'Banking Manager', 'You do not have access to that.', 'error')
    end
    TriggerClientEvent('nz_bank:mgrOpen', src)
end, false)

-- ── society payout: /paysociety <amount> (boss only, society to personal) ──
RegisterCommand('paysociety', function(src, args)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return end
    if not Bank.canUseSociety(xPlayer.job.name, xPlayer.job.grade_name, xPlayer.job.isboss) then
        return Bank.notify(src, 'Banking', 'You cannot move society funds.', 'error')
    end

    local amount = Bank.round(tonumber(args[1]) or 0)
    if amount <= 0 then return Bank.notify(src, 'Banking', 'Usage: /paysociety <amount>', 'error') end

    local soc = Bank.getSociety(xPlayer.job.name)
    local personal = Bank.getPersonal(xPlayer.identifier)
    if not soc or not personal then return end

    local ok = Bank.debit(soc.id, amount, {
        category = 'transfer', label = ('Payout · %s'):format(Bank.fullName(xPlayer)),
        actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
    })
    if not ok then return Bank.notify(src, 'Banking', 'Not enough in the society account.', 'error') end

    Bank.creditOwed(personal.id, amount, {
        category = 'payroll', label = ('Payout · %s'):format(soc.label)
    })
    Bank.notify(src, 'Banking', ('Moved %s%s to your account.'):format(Config.Currency, amount), 'success')
end, false)
