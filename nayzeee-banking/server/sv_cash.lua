if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  PHYSICAL CASH  (Config.Cash)
--
--  Every dollar is a banknote item. With this on, Bank.getCash,
--  Bank.removeCash and Bank.addCash count, take and hand out notes,
--  so every cash move in the resource uses them without knowing.
--
--  Paying: the exact notes when the player has them (fewest notes),
--  otherwise the smallest overpay, with the change given straight back
--  in the largest notes that make it up. Notes are taken before change
--  is given, and either step failing puts everything back.
--
--  Other resources: exports in the README (getCash, payCash, addCash…).
-- ═══════════════════════════════════════════════════════════
local C = Config.Cash or {}

local NOTES = {}
for _, n in ipairs(C.notes or {}) do
    if type(n.item) == 'string' and tonumber(n.value) and n.value > 0 then
        NOTES[#NOTES + 1] = { item = n.item, value = math.floor(n.value) }
    end
end
table.sort(NOTES, function(a, b) return a.value > b.value end)

local function usable()
    local inv = Bank.inventory()
    return #NOTES > 0 and (inv == 'ox_inventory' or inv == 'qs-inventory' or inv == 'qb-inventory'), inv
end

-- on only when asked for and the inventory can hold notes; the exports below
-- answer either way, with plain cash when this is off
local active = false
if C.enabled then
    local ok, inv = usable()
    if not ok then
        print(('^3[nayzeee-banking]^7 Config.Cash is on but %s cannot hold banknote items; ' ..
               'physical cash stays off (it needs ox_inventory, qs-inventory or qb-inventory).'):format(tostring(inv)))
    else
        active = true
    end
    if active and NOTES[#NOTES].value ~= 1 then
        print('^3[nayzeee-banking]^7 Config.Cash has no $1 note: amounts that are not a multiple of '
              .. NOTES[#NOTES].value .. ' cannot be paid or changed exactly.')
    end
end

-- ── the inventory, one note type at a time ───────────────
local function count(src, item)
    local inv = Bank.inventory()
    local ok, n = pcall(function()
        if inv == 'ox_inventory' then return exports.ox_inventory:GetItemCount(src, item) end
        if inv == 'qs-inventory' then return exports['qs-inventory']:GetItemTotalAmount(src, item) end
        -- qb-inventory: GetItemCount where it exists, else the stack it finds
        local c = exports['qb-inventory']:GetItemCount(src, item)
        if c then return c end
        local it = exports['qb-inventory']:GetItemByName(src, item)
        return it and it.amount
    end)
    return ok and tonumber(n) or 0
end

local function add(src, item, n)
    if n <= 0 then return true end
    local inv = Bank.inventory()
    local ok, res = pcall(function()
        if inv == 'ox_inventory' then return exports.ox_inventory:AddItem(src, item, n) end
        if inv == 'qs-inventory' then return exports['qs-inventory']:AddItem(src, item, n) end
        return exports['qb-inventory']:AddItem(src, item, n, false, false, 'nayzeee-banking')
    end)
    return ok and res and true or false
end

local function take(src, item, n)
    if n <= 0 then return true end
    local inv = Bank.inventory()
    local ok, res = pcall(function()
        if inv == 'ox_inventory' then return exports.ox_inventory:RemoveItem(src, item, n) end
        if inv == 'qs-inventory' then return exports['qs-inventory']:RemoveItem(src, item, n) end
        return exports['qb-inventory']:RemoveItem(src, item, n, false, 'nayzeee-banking')
    end)
    return ok and res and true or false
end

--- What the player is carrying, note by note: { [item] = count }, and the total.
local function wallet(src)
    local have, total = {}, 0
    for _, n in ipairs(NOTES) do
        local c = count(src, n.item)
        have[n.item] = c
        total = total + c * n.value
    end
    return have, total
end

-- ── choosing the notes ───────────────────────────────────
--- The fewest notes that make `amount` exactly, from what is held. Bounded
--- knapsack with each note type split into powers of two. nil when no exact
--- set exists.
local function exact(have, amount)
    local parts = {}
    for _, n in ipairs(NOTES) do
        local left, k = math.min(have[n.item] or 0, math.floor(amount / n.value)), 1
        while left > 0 do
            local take = math.min(k, left)
            parts[#parts + 1] = { item = n.item, value = n.value * take, notes = take }
            left = left - take
            k = k * 2
        end
    end

    local best, from = { [0] = 0 }, {}
    for p, part in ipairs(parts) do
        for s = amount, part.value, -1 do
            local prev = best[s - part.value]
            if prev and (best[s] == nil or prev + part.notes < best[s]) then
                best[s] = prev + part.notes
                from[s] = from[s] or {}
                from[s][p] = true
            end
        end
    end
    if best[amount] == nil then return nil end

    -- walk back which parts made it: from[s][p] says part p improved s when
    -- it was considered, which is exactly when it belongs to the answer
    local pay, s = {}, amount
    for p = #parts, 1, -1 do
        local part = parts[p]
        if s >= part.value and from[s] and from[s][p] then
            pay[part.item] = (pay[part.item] or 0) + part.notes
            s = s - part.value
        end
    end
    if s ~= 0 then return nil end
    return pay
end

--- Largest notes first; whatever is left is covered by the smallest single
--- note big enough, and that overpay comes back as change.
local function greedy(have, amount)
    local pay, rest, left = {}, amount, {}
    for _, n in ipairs(NOTES) do
        local use = math.min(have[n.item] or 0, math.floor(rest / n.value))
        pay[n.item] = use
        left[n.item] = (have[n.item] or 0) - use
        rest = rest - use * n.value
    end
    if rest <= 0 then return pay, 0 end
    for i = #NOTES, 1, -1 do
        local n = NOTES[i]
        if left[n.item] > 0 and n.value >= rest then
            pay[n.item] = pay[n.item] + 1
            return pay, n.value - rest
        end
    end
    return nil
end

--- Which notes to hand over for `amount`, and the change due back.
local function choose(have, total, amount)
    if total < amount then return nil end
    if amount <= (tonumber(C.exactUpTo) or 5000) then
        local pay = exact(have, amount)
        if pay then return pay, 0 end
    end
    return greedy(have, amount)
end

--- `amount` broken into notes, largest first: { [item] = count }.
local function notesFor(amount)
    local out, rest = {}, math.floor(amount)
    for _, n in ipairs(NOTES) do
        local k = math.floor(rest / n.value)
        if k > 0 then out[n.item] = k rest = rest - k * n.value end
    end
    return out, rest   -- rest > 0 only if there is no $1 note
end

-- ── giving and taking, all or nothing ────────────────────
local function giveSet(src, set)
    local given = {}
    for item, k in pairs(set) do
        if k > 0 then
            if not add(src, item, k) then
                for gi, gk in pairs(given) do take(src, gi, gk) end
                return false
            end
            given[item] = k
        end
    end
    return true
end

local function takeSet(src, set)
    local taken = {}
    for item, k in pairs(set) do
        if k > 0 then
            if not take(src, item, k) then
                for ti, tk in pairs(taken) do add(src, ti, tk) end
                return false
            end
            taken[item] = k
        end
    end
    return true
end

--- Pay `amount` in notes. ok, { paid = { [item] = n }, change = n, given = { [item] = n } }
--- or false, reason ('not_enough' / 'no_room' / 'inventory').
local function pay(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'bad_amount' end

    local have, total = wallet(src)
    local set, change = choose(have, total, amount)
    if not set then return false, 'not_enough' end

    if not takeSet(src, set) then return false, 'inventory' end

    local back = {}
    if change > 0 then
        back = notesFor(change)
        if not giveSet(src, back) then
            giveSet(src, set)   -- the notes go back where they came from
            return false, 'no_room'
        end
    end
    return true, { paid = set, change = change, given = back }
end

--- Hand out `amount` in notes. false (nothing given) if they will not fit.
local function receive(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local set = notesFor(amount)
    return giveSet(src, set), set
end

-- ═══════════════════════════════════════════════════════════
--  THE BANK USES NOTES
--  Same names and returns as the versions in sv_core.lua.
-- ═══════════════════════════════════════════════════════════
local plain = { get = Bank.getCash, remove = Bank.removeCash, add = Bank.addCash }

if active then
function Bank.getCash(xPlayer)
    local _, total = wallet(xPlayer.source)
    return total
end

function Bank.removeCash(xPlayer, amount)
    local ok, res = pay(xPlayer.source, amount)
    if ok and res.change > 0 then
        Bank.notify(xPlayer.source, 'Cash', ('Paid %s%s · %s%s change'):format(
            Config.Currency, math.floor(amount) + res.change, Config.Currency, res.change), 'inform')
    end
    return ok
end

function Bank.addCash(xPlayer, amount)
    return (receive(xPlayer.source, amount))
end
end

-- ═══════════════════════════════════════════════════════════
--  LOOSE CASH INTO NOTES
--  A server switching this on part way has players carrying the old
--  cash item; it is changed into notes when they load in.
-- ═══════════════════════════════════════════════════════════
Framework.onPlayerLoaded(function(src)
    if not active or C.convertOnJoin == false or not Config.MoneyItem then return end
    SetTimeout(4000, function()   -- let the inventory finish loading them
        if not GetPlayerName(src) then return end
        local loose = count(src, Config.MoneyItem)
        if loose <= 0 then return end
        -- notes first, so a full inventory leaves the loose cash where it was
        if receive(src, loose) then
            if not take(src, Config.MoneyItem, loose) then
                local set = notesFor(loose)
                takeSet(src, set)
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════
--  EXPORTS for shops, jobs, robberies, fines, anything that takes
--  or hands out cash. All server side; `src` is a player's server id.
-- ═══════════════════════════════════════════════════════════

--- With physical cash off, the same exports move the server's ordinary cash.
local function player(src) return Bank.getPlayer(src) end

--- Total cash carried, and the notes that make it: total, { [item] = count }
exports('getCash', function(src)
    if not active then
        local x = player(src)
        return x and plain.get(x) or 0, {}
    end
    local have, total = wallet(src)
    return total, have
end)

--- Take `amount`, choosing the notes and giving change.
--- ok, details { paid, change, given } | false, 'not_enough' / 'no_room' / 'inventory'
local function payExport(src, amount)
    if not active then
        local x = player(src)
        amount = math.floor(tonumber(amount) or 0)
        if not x or amount <= 0 then return false, 'bad_amount' end
        if plain.get(x) < amount then return false, 'not_enough' end
        if not plain.remove(x, amount) then return false, 'inventory' end
        return true, { paid = {}, change = 0, given = {} }
    end
    return pay(src, amount)
end
exports('payCash', payExport)
exports('removeCash', payExport)

--- Hand out `amount` in notes. ok, { [item] = count }
exports('addCash', function(src, amount)
    if not active then
        local x = player(src)
        amount = math.floor(tonumber(amount) or 0)
        if not x or amount <= 0 then return false end
        return plain.add(x, amount) and true or false, {}
    end
    return receive(src, amount)
end)

--- Is every dollar a banknote on this server?
exports('physicalCash', function() return active end)

--- How `amount` breaks into notes, without moving anything: { [item] = count }
exports('cashNotes', function(amount) return (notesFor(amount)) end)

--- The note types in use, largest first: { { item, value }, … }
exports('cashDenominations', function()
    local out = {}
    for i, n in ipairs(NOTES) do out[i] = { item = n.item, value = n.value } end
    return out
end)

Bank.cash = { pay = pay, receive = receive, wallet = wallet, notesFor = notesFor, choose = choose }
