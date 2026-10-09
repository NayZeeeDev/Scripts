if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  WHERE A PLAYER IS BANKING FROM
--
--  Cash only goes in or out at a branch the player is standing in,
--  or at an ATM the server watched them start a session at. The
--  ATM fee, the ATM cap and the PIN are decided here from that
--  session, never from what the client says it is.
-- ═══════════════════════════════════════════════════════════
Bank.where = {}   -- [src] = { kind = 'atm', coords, cardId, accountId, foreign, since }

local function sec() return Config.Security or {} end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--- The branch a player is stood in, or nil.
function Bank.nearBranch(src)
    local pos = pedCoords(src)
    if not pos then return nil end

    local range = sec().branchRange or 12.0
    for i, bank in ipairs(Config.Banks or {}) do
        if #(pos - vec3(bank.coords.x, bank.coords.y, bank.coords.z)) <= range then return i end
    end
end

--- Is the player close enough to these coords to be using a machine there?
function Bank.nearPoint(src, coords, range)
    local pos = pedCoords(src)
    if not pos or not coords then return false end
    return #(pos - vec3(coords.x, coords.y, coords.z)) <= (range or sec().atmRange or 3.5)
end

--- Start an ATM session. Coords are where the client says the machine is;
--- the player has to be stood at them for the session to count.
function Bank.startATM(src, coords, card)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return false end
    coords = vec3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    if not Bank.nearPoint(src, coords) then return false end

    Bank.where[src] = {
        kind      = 'atm',
        coords    = coords,
        cardId    = card and card.id or nil,
        accountId = card and card.account_id or nil,
        foreign   = card and card.foreign or false,
        since     = os.time()
    }
    return true
end

function Bank.endATM(src)
    Bank.where[src] = nil
end

--- The ATM session, if the player is still stood at it.
function Bank.atmSession(src)
    local w = Bank.where[src]
    if not w or w.kind ~= 'atm' then return nil end
    -- a little slack over the start range, for the idle animation shuffling the ped
    if not Bank.nearPoint(src, w.coords, (sec().atmRange or 3.5) + 1.5) then
        Bank.where[src] = nil
        return nil
    end
    return w
end

--- Where cash can move for this player right now: 'atm', 'bank', or nil + a reason.
function Bank.cashPoint(src)
    local atm = Bank.atmSession(src)
    if atm then
        if atm.cardId and Config.ATM.requirePin then
            local s = Bank.session[src]
            if not (s and s.pinOk and s.pinOk[atm.cardId]) then
                return nil, 'Enter your PIN first.'
            end
        end
        return 'atm', atm
    end

    if Bank.nearBranch(src) then
        if Bank.branchOpen and not Bank.branchOpen() then
            return nil, 'The bank is closed. Use an ATM.'
        end
        return 'bank'
    end

    return nil, 'Cash goes in and out at a branch or an ATM.'
end

--- Access to an account through the card in the machine. A card and its PIN
--- open the card's own account at an ATM, whoever is holding it.
function Bank.cardAccess(src, accountId)
    local atm = Bank.atmSession(src)
    if not atm or not atm.accountId or Bank.id(accountId) ~= atm.accountId then return nil end
    if Config.ATM.requirePin then
        local s = Bank.session[src]
        if not (s and s.pinOk and s.pinOk[atm.cardId]) then return nil end
    end

    local acc = Bank.getAccountById(atm.accountId)
    if not acc then return nil end
    return acc, { role = 'card', deposit = true, withdraw = true, transfer = true }, atm
end

AddEventHandler('playerDropped', function()
    Bank.where[source] = nil
end)

-- ═══════════════════════════════════════════════════════════
--  SAVED PAYEES
--  People you pay often, so a transfer is a pick instead of an
--  account number typed out. The ATM keypad has no letters, so
--  this is the only way to transfer from a machine.
-- ═══════════════════════════════════════════════════════════
MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nz_bank_payees` (
          `id`             INT(11) NOT NULL AUTO_INCREMENT,
          `identifier`     VARCHAR(64) NOT NULL,
          `label`          VARCHAR(32) NOT NULL,
          `account_number` VARCHAR(24) NOT NULL,
          `last_used`      BIGINT(20) NOT NULL DEFAULT 0,
          `created_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `payee` (`identifier`, `account_number`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

local MAX_PAYEES = 12

function Bank.getPayees(identifier)
    local rows = MySQL.query.await([[
        SELECT id, label, account_number, last_used FROM nz_bank_payees
        WHERE identifier = ? ORDER BY last_used DESC, label ASC LIMIT ?
    ]], { identifier, MAX_PAYEES }) or {}
    return rows
end

--- A transfer to a saved payee moves them up the list.
function Bank.touchPayee(identifier, accountNumber)
    MySQL.update('UPDATE nz_bank_payees SET last_used = ? WHERE identifier = ? AND account_number = ?',
        { os.time(), identifier, accountNumber })
end

Bank.callback('nz_bank:getPayees', function(src)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return {} end
    return Bank.getPayees(xPlayer.identifier)
end)

Bank.callback('nz_bank:savePayee', function(src, label, accountNumber)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    accountNumber = tostring(accountNumber or ''):upper():gsub('%s', '')
    local target = Bank.getAccountByNumber(accountNumber)
    if not target then return { ok = false, msg = 'No account with that number.' } end
    if target.type == 'personal' and target.owner == xPlayer.identifier then
        return { ok = false, msg = 'That is your own account.' }
    end

    label = tostring(label or ''):gsub('[^%w%s%-&\'.]', ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 32)
    if #label < 2 then label = target.label:sub(1, 32) end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_payees WHERE identifier = ?',
        { xPlayer.identifier }) or 0
    local exists = MySQL.scalar.await('SELECT id FROM nz_bank_payees WHERE identifier = ? AND account_number = ?',
        { xPlayer.identifier, accountNumber })
    if not exists and count >= MAX_PAYEES then
        return { ok = false, msg = ('You can keep up to %s payees. Remove one first.'):format(MAX_PAYEES) }
    end

    if exists then
        MySQL.update.await('UPDATE nz_bank_payees SET label = ? WHERE id = ?', { label, exists })
        return { ok = true, msg = 'Payee updated.', id = exists }
    end

    local id = MySQL.insert.await(
        'INSERT INTO nz_bank_payees (identifier, label, account_number, last_used) VALUES (?, ?, ?, ?)',
        { xPlayer.identifier, label, accountNumber, os.time() })
    return { ok = true, msg = ('%s saved as a payee.'):format(label), id = id }
end)

Bank.callback('nz_bank:deletePayee', function(src, id)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer or not Bank.id(id) then return { ok = false, msg = 'Payee not found.' } end
    local gone = MySQL.update.await('DELETE FROM nz_bank_payees WHERE id = ? AND identifier = ?',
        { Bank.id(id), xPlayer.identifier })
    if gone == 0 then return { ok = false, msg = 'Payee not found.' } end
    return { ok = true, msg = 'Payee removed.' }
end)
