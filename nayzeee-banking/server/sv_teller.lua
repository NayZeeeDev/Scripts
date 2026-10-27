if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  THE TELLER'S COUNTER
--
--  A withdrawal at a branch is checked when it is asked for, then
--  held while the teller counts the notes out and slides them across.
--  The money only leaves the account when the player picks them up,
--  so cash left on the counter, a player who walks off, or one who
--  disconnects costs nothing and needs nothing put back.
--
--  Deposits are taken and credited as they always were; the teller
--  scene on the client is the notes being counted after the fact.
-- ═══════════════════════════════════════════════════════════
local T = Config.Teller or {}
local held = {}   -- [src] = { token, accountId, amount, expires }

function Bank.tellerOn()
    return T.enabled ~= false and Config.SpawnPeds == true
end

local function lifetime()
    return math.ceil((tonumber(T.countSeconds) or 4) + (tonumber(T.collectSeconds) or 60) + 10)
end

--- Put a checked withdrawal on hold for the teller to count out.
function Bank.tellerHold(src, accountId, amount)
    local now = os.time()
    local h = held[src]
    if h and h.expires > now then
        return { ok = false, msg = 'Pick up the cash on the counter first.' }
    end

    local token = ('%d:%d:%d'):format(src, now, math.random(100000, 999999))
    held[src] = { token = token, accountId = accountId, amount = amount, expires = now + lifetime() }
    return {
        ok = true,
        msg = 'The teller is counting out your cash.',
        teller = { kind = 'withdraw', amount = amount, token = token },
    }
end

--- The player picked the notes up: now the money leaves the account.
Bank.callback('nz_bank:tellerCollect', function(src, token)
    local h = held[src]
    if not h or h.token ~= token then return { ok = false, msg = 'There is nothing on the counter for you.' } end
    held[src] = nil

    if os.time() > h.expires then return { ok = false, msg = 'The teller put it away. Nothing was taken.' } end
    if Bank.cashPoint(src) ~= 'bank' then
        return { ok = false, msg = 'You walked away from the counter. Nothing was taken.' }
    end

    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end
    return Bank.withdrawAt(src, xPlayer, h.accountId, h.amount, 'bank')
end)

--- Left on the counter or walked away from: forget it.
Bank.callback('nz_bank:tellerCancel', function(src, token)
    if held[src] and held[src].token == token then held[src] = nil end
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    held[source] = nil
end)
