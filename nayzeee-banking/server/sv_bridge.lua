if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BILLING BRIDGE
--  Invoices raised by other creators' resources land in this
--  bank's bills table instead of their own. Each handler stands
--  aside while the resource it is named after is running, since
--  that resource bills the player itself. Event names differ
--  between forks — adjust them in Config.Bridge if yours uses
--  something else.
-- ═══════════════════════════════════════════════════════════

local function resolveIdentifier(target)
    if type(target) == 'string' and not tonumber(target) and Bank.isCharacterId(target) then return target end

    local xTarget = ESX.GetPlayerFromId(tonumber(target))
    if xTarget then return xTarget.identifier end
    return nil
end

--- A player's server id when the event came off the network, nil when
--- another server script raised it with TriggerEvent.
local function clientSource(src)
    src = tonumber(src)
    if src and src > 0 and GetPlayerName(src) then return src end
    return nil
end

local function senderName(src)
    local xPlayer = clientSource(src) and Bank.getPlayer(src)
    return xPlayer and Bank.fullName(xPlayer) or nil
end

--- 'society_police' and 'police' are the same issuer.
local function jobName(job)
    if type(job) ~= 'string' or job == '' then return nil end
    return (job:gsub('^society_', ''))
end

--- Server-side calls only. Anything that came from a client goes
--- through fromClient below first.
local function raise(target, issuerJob, amount, reason, sender)
    local identifier = resolveIdentifier(target)
    if not identifier then
        Bank.debug('bridge: could not resolve target', tostring(target))
        return false
    end

    amount = Bank.round(amount)
    if amount <= 0 then return false end

    reason = type(reason) == 'string' and reason or 'Invoice'
    local ok = Bank.createBill(identifier, jobName(issuerJob) or Config.Bridge.fallbackJob,
        amount, reason, type(sender) == 'string' and sender or nil)

    if ok then
        Bank.debug(('bridge: billed %s %s%s for %s'):format(identifier, Config.Currency, amount, reason))
    end
    return ok
end

Bank.bridgeBill = raise

-- ═══════════════════════════════════════════════════════════
--  BILLS RAISED FROM A CLIENT
--  A net event can be fired by any client with any arguments, so
--  nothing it says about who is billing is believed. The sender
--  must hold the job, at the grade, near the person billed, and
--  not faster than the rate limit.
-- ═══════════════════════════════════════════════════════════
local sent = {}   -- [src] = { times of recent bills, ms }

local function rateLimited(src)
    local rl = Config.Bridge.rateLimit or {}
    local now = GetGameTimer()
    local list = sent[src] or {}

    -- keep only the last minute
    local kept = {}
    for _, t in ipairs(list) do
        if now - t < 60000 then kept[#kept + 1] = t end
    end
    sent[src] = kept

    local last = kept[#kept]
    if last and now - last < (rl.gapSeconds or 5) * 1000 then return true end
    if #kept >= (rl.perMinute or 6) then return true end

    kept[#kept + 1] = now
    return false
end

AddEventHandler('playerDropped', function()
    sent[source] = nil
end)

--- Does this player hold `job`, at a grade allowed to bill?
local function canBill(xPlayer, job)
    if not job then return false end

    local listed = false
    for _, j in ipairs(Config.Bills.issuers or {}) do
        if j == job then listed = true break end
    end
    if not listed then return false end

    local need = (Config.Bridge.jobMinGrade or {})[job] or Config.Bridge.minGrade or 0
    for _, held in ipairs(Bank.jobsFor(xPlayer)) do
        if held.name == job and (held.active or Config.MultiJob.allowInactiveJobs) then
            return (tonumber(held.grade) or 0) >= need
        end
    end
    return false
end

local function onlineTarget(target)
    if type(target) == 'string' and not tonumber(target) and Bank.isCharacterId(target) then
        return ESX.GetPlayerFromIdentifier(target)
    end
    local id = tonumber(target)
    return id and ESX.GetPlayerFromId(id) or nil
end

local function nearEnough(a, b)
    local max = Config.Bridge.maxDistance or 0
    if max <= 0 then return true end

    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return true end   -- no OneSync, nothing to measure
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= max
end

local function fromClient(src, target, issuerJob, amount, reason)
    local xSender = Bank.getPlayer(src)
    if not xSender then return false end

    if rateLimited(src) then
        Bank.notify(src, 'Billing', 'You are sending bills too quickly.', 'error')
        return false
    end

    -- the job the event names, or the sender's own
    local job = jobName(issuerJob) or xSender.job.name
    if not canBill(xSender, job) then
        Bank.log('bills', 'Bill refused',
            ('**%s** (`%s`) tried to bill as %s without the job or grade for it')
                :format(Bank.fullName(xSender), xSender.identifier, tostring(job)))
        return false
    end

    local xTarget = onlineTarget(target)
    if not xTarget then
        Bank.notify(src, 'Billing', 'That person is not in the city.', 'error')
        return false
    end
    if not nearEnough(src, xTarget.source) then
        Bank.notify(src, 'Billing', 'You need to be with them to bill them.', 'error')
        return false
    end

    amount = Bank.round(amount)
    if amount <= 0 or amount > Config.Bills.maxAmount then return false end

    return raise(xTarget.source, job, amount, reason, Bank.fullName(xSender))
end

--- Server scripts are trusted as they were; a client goes through the checks.
local function handle(src, target, job, amount, reason, sender)
    local from = clientSource(src)
    if from then return fromClient(from, target, job, amount, reason) end
    return raise(target, job, amount, reason, sender)
end

-- server scripts: TriggerEvent('nz_bank:bridgeBill', identifier, issuerJob, amount, reason, senderName)
RegisterNetEvent('nz_bank:bridgeBill', function(target, issuerJob, amount, reason, sender)
    handle(source, target, issuerJob, amount, reason, sender)
end)

-- ── every configured billing event, one handler shape ──────
--  esx_billing  : (playerId, societyAccount, label, amount)
--  okokBilling  : (playerId, society, amount, reason)
--  qb / lb-phone: (table)

--- Pull target, job, amount, reason and sender out of whichever shape arrived.
local function parse(src, a, b, c, d)
    -- table payload (okokBilling, qb, lb-phone and most modern forks)
    if type(a) == 'table' then
        -- okokBilling: { authorPlayer = { source }, receiverPlayer = { source }, item, price, note }
        if a.receiverPlayer or a.authorPlayer then
            local receiver = type(a.receiverPlayer) == 'table' and a.receiverPlayer.source or nil
            local author   = type(a.authorPlayer) == 'table' and a.authorPlayer.source or nil
            local xAuthor  = author and ESX.GetPlayerFromId(tonumber(author))

            return receiver,
                a.society or (xAuthor and xAuthor.job.name),
                a.price or a.amount,
                a.item or a.note or 'Invoice',
                xAuthor and Bank.fullName(xAuthor) or senderName(src)
        end

        return a.citizenid or a.identifier or a.playerId or a.target or a.to,
            a.society or a.job,
            a.amount or a.price,
            a.label or a.reason or a.message or a.item,
            a.sender or a.from or senderName(src)
    end

    -- positional payload, amount sits in different slots per resource
    local amount = tonumber(d) or tonumber(c)
    local reason = type(c) == 'string' and c or (type(d) == 'string' and d or 'Invoice')
    return a, jobName(b), amount, reason, senderName(src)
end

for _, eventName in ipairs(Config.Bridge.events or {}) do
    -- the resource the event belongs to, e.g. esx_billing
    local owner = eventName:match('^([^:]+):')

    RegisterNetEvent(eventName, function(a, b, c, d)
        local src = source

        -- that resource is running and bills the player itself
        if owner and GetResourceState(owner) == 'started' then return end

        local target, job, amount, reason, sender = parse(src, a, b, c, d)
        handle(src, target, job, amount, reason, sender)
    end)
end

-- ═══════════════════════════════════════════════════════════
--  EXPORTS for other creators
--  exports['nayzeee-banking']:sendBill(playerId, job, amount, reason, sender)
-- ═══════════════════════════════════════════════════════════
exports('sendBill', function(target, issuerJob, amount, reason, sender)
    return raise(target, issuerJob, amount, reason, sender)
end)

exports('getAccountByNumber', function(number)
    local acc = Bank.getAccountByNumber(number)
    if not acc then return nil end
    return { id = acc.id, number = acc.account_number, type = acc.type,
             label = acc.label, balance = acc.balance, frozen = acc.frozen == 1 }
end)

--- Move money between any two accounts by number. Useful for shops,
--- rentals and anything that needs a paper trail on both sides.
exports('transferBetween', function(fromNumber, toNumber, amount, label)
    local from = Bank.getAccountByNumber(fromNumber)
    if not from then return false, 'Unknown source account.' end
    return Bank.doTransfer(from.id, toNumber, amount, nil, label or 'Transfer', label)
end)

--- Read-only summary another resource can render (phones, MDTs).
exports('getSummary', function(identifier)
    local personal = Bank.getPersonal(identifier)
    local savings  = Bank.getSavings(identifier)
    local credit   = Bank.getCredit(identifier)
    local bills    = Bank.getBills(identifier)

    return {
        account = personal and personal.account_number or nil,
        balance = personal and personal.balance or 0,
        savings = savings and savings.balance or 0,
        credit  = credit.score,
        band    = Bank.creditBand(credit.score),
        billsDue= bills.count,
        billsTotal = bills.total
    }
end)
