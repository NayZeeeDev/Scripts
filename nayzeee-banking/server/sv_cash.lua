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
local MONEY = Config.MoneyItem or 'money'   -- the framework's loose cash item, counted and turned into notes

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
    -- loose `money` counts too: during an ox shop it is where the cash is
    return total + (MONEY and count(xPlayer.source, MONEY) or 0)
end

function Bank.removeCash(xPlayer, amount)
    if Bank.cashSettle then Bank.cashSettle(xPlayer.source) end
    local ok, res = pay(xPlayer.source, amount)
    if Bank.cashSync then SetTimeout(0, function() Bank.cashSync(xPlayer.source) end) end
    if ok and res.change > 0 then
        Bank.notify(xPlayer.source, 'Cash', ('Paid %s%s · %s%s change'):format(
            Config.Currency, math.floor(amount) + res.change, Config.Currency, res.change), 'inform')
    end
    return ok
end

function Bank.addCash(xPlayer, amount)
    local ok = receive(xPlayer.source, amount)
    if Bank.cashSync then SetTimeout(0, function() Bank.cashSync(xPlayer.source) end) end
    return ok
end
end

-- ═══════════════════════════════════════════════════════════
--  THE FRAMEWORK'S CASH FOLLOWS THE NOTES  (Config.Cash.mirror)
--
--  Shops, garages, fines and job scripts take and pay cash through the
--  framework (xPlayer.removeMoney, Player.Functions.RemoveMoney('cash')
--  …). So the framework's cash figure is kept equal to the notes the
--  player carries, both ways:
--
--    · something takes framework cash   → those notes are taken, with change
--    · something adds framework cash    → that much is handed out in notes
--    · notes move in the inventory      → the figure follows
--
--  ox_inventory shops charge the `money` item rather than the framework,
--  so while a shop is open the player's notes are changed into `money`,
--  and whatever is left is changed back into notes when it closes.
--
--  On an ox_inventory server cash must not also be an ox account item, or
--  the figure would be the `money` item and every dollar would exist twice:
--  set `setr inventory:accounts []` (Qbox) or `["black_money"]` (ESX).
-- ═══════════════════════════════════════════════════════════
local REASON   = 'nayzeee-cash'
local mirrorOn = false
local last     = {}   -- [src] = the framework figure as we last left it
local writing  = {}   -- [src] = true while we set the figure ourselves
local shopping = {}   -- [src] = true while an ox shop is open (notes held as `money`)
local due      = {}   -- [src] = cash owed in notes that did not fit yet

local function isOx() return Bank.inventory() == 'ox_inventory' end

--- Loose `money` items: during an ox shop that is where the cash is, and at any
--- other time it is cash that has not been turned into notes yet.
local function loose(src) return MONEY and count(src, MONEY) or 0 end

--- Every dollar the player carries: notes, plus any loose `money`.
local function carried(src)
    local _, notes = wallet(src)
    return notes + loose(src)
end

--- Loose `money` into notes, notes first so a full inventory loses nothing.
local function settleLoose(src)
    if shopping[src] then return end
    local n = loose(src)
    if n <= 0 then return end
    if receive(src, n) then
        if not take(src, MONEY, n) then takeSet(src, notesFor(n)) end
    end
end

-- ── the framework's own cash figure ──────────────────────
local function figure(src)
    local x = Bank.getPlayer(src)
    if not x then return nil end
    if Framework.name == 'esx' then
        local a = x.getAccount and x.getAccount('money')
        return a and tonumber(a.money) or 0, x
    end
    local P = x.raw
    return P and tonumber(P.Functions.GetMoney('cash')) or 0, x
end

local function setFigure(x, v)
    writing[x.source] = true
    local ok = pcall(function()
        if Framework.name == 'esx' then x.setAccountMoney('money', v, REASON)
        else x.raw.Functions.SetMoney('cash', v, REASON) end
    end)
    writing[x.source] = nil
    return ok
end

local function owedKey(x) return 'nz_cash_due:' .. tostring(x.identifier) end

--- Bring the framework figure and the notes back in step, settling whatever
--- changed on either side since the last look. One player at a time.
local function syncNow(src)
    if not mirrorOn or not GetPlayerName(src) then return end
    local f, x = figure(src)
    if not x then return end

    settleLoose(src)

    -- cash owed from a payment whose notes did not fit, kept across a relog
    if due[src] == nil then due[src] = tonumber(GetResourceKvpString(owedKey(x)) or '') or 0 end

    local was = last[src]
    if was == nil then
        -- first look: a server switching notes on part way has players with a
        -- framework cash figure and no notes; that cash becomes notes, once
        local key = 'nz_cash_ok:' .. tostring(x.identifier)
        if not GetResourceKvpString(key) then
            if carried(src) == 0 and f > 0 and not receive(src, f) then due[src] = due[src] + f end
            SetResourceKvp(key, '1')
        end
    elseif f ~= was then
        -- something outside took or paid framework cash: the notes follow
        local d = f - was
        if d < 0 then
            local ok, res = pay(src, -d)
            if ok then
                if res.change > 0 then
                    Bank.notify(src, 'Cash', ('Paid %s%s · %s%s change'):format(
                        Config.Currency, -d + res.change, Config.Currency, res.change), 'inform')
                end
            elseif res == 'no_room' then
                -- no room for the change: the notes go, the change is owed
                local have, total = wallet(src)
                local set, change = choose(have, total, -d)
                if set and takeSet(src, set) then due[src] = due[src] + change end
            else
                -- spent more than the notes in hand (moved a moment before): all of it
                local have = wallet(src)
                takeSet(src, have)
            end
        elseif not receive(src, d) then
            due[src] = due[src] + d
        end
    end

    -- hand over what is owed once there is room
    if due[src] > 0 and receive(src, due[src]) then due[src] = 0 end
    if due[src] > 0 then SetResourceKvp(owedKey(x), tostring(due[src])) else DeleteResourceKvp(owedKey(x)) end

    local want = carried(src) + due[src]
    if f ~= want then setFigure(x, want) end
    last[src] = want
end

local function sync(src)
    if not mirrorOn then return end
    local ok, err = pcall(Bank.serial, 'cash:' .. tostring(src), syncNow, src)
    if not ok then Bank.debug('cash sync failed', err) end
end
Bank.cashSync = sync
Bank.cashSettle = function(src) pcall(settleLoose, src) end

-- ── turned on only where it is safe ──────────────────────
CreateThread(function()
    if not active or C.mirror == false then return end
    if isOx() then
        local ok, list = pcall(json.decode, GetConvar('inventory:accounts', '["money"]'))
        for _, name in ipairs(ok and type(list) == 'table' and list or { 'money' }) do
            if name == MONEY then
                print(('^1[nayzeee-banking]^7 Config.Cash: ox_inventory still treats "%s" as the cash account, so ' ..
                    'shops cannot see banknotes and every dollar would exist twice. Add to server.cfg: ' ..
                    '^3setr inventory:accounts []^7 (Qbox) or ^3setr inventory:accounts ["black_money"]^7 (ESX), ' ..
                    'then restart.'):format(MONEY))
                return
            end
        end
    end
    mirrorOn = true

    -- the framework says when its cash moves
    if Framework.name == 'esx' then
        local function onEsx(src, account, _, reason)
            if account == 'money' and reason ~= REASON and not writing[src] then CreateThread(function() sync(src) end) end
        end
        AddEventHandler('esx:addAccountMoney', onEsx)
        AddEventHandler('esx:removeAccountMoney', onEsx)
        AddEventHandler('esx:setAccountMoney', onEsx)
    else
        AddEventHandler('QBCore:Server:OnMoneyChange', function(src, moneyType, _, _, reason)
            if moneyType == 'cash' and reason ~= REASON and not writing[src] then CreateThread(function() sync(src) end) end
        end)
    end

    -- ox_inventory: notes moved by hand, and its shops
    if isOx() then
        local filter = {}
        for _, n in ipairs(NOTES) do filter[n.item] = true end
        filter[MONEY] = true
        pcall(function()
            exports.ox_inventory:registerHook('swapItems', function(payload)
                SetTimeout(150, function()
                    for _, inv in ipairs({ payload.fromInventory, payload.toInventory }) do
                        if type(inv) == 'number' then sync(inv) end
                    end
                end)
                return true
            end, { itemFilter = filter })

            -- a shop charges `money`: the notes become `money` while it is open
            exports.ox_inventory:registerHook('openShop', function(payload)
                local src = payload.source
                local have, total = wallet(src)
                if total > 0 and takeSet(src, have) then
                    if add(src, MONEY, total) then shopping[src] = true
                    else giveSet(src, have) end
                end
                return true
            end)
        end)
        -- and back into notes when it closes
        RegisterNetEvent('ox_inventory:closeInventory', function()
            local src = source
            if not shopping[src] then return end
            shopping[src] = nil
            SetTimeout(100, function() sync(src) end)
        end)
    end

    -- notes picked up, given, dropped or robbed: the figure follows
    local every = math.max(1, tonumber(C.syncSeconds) or 2) * 1000
    while true do
        Wait(every)
        for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
            if xPlayer.source then sync(xPlayer.source) end
        end
    end
end)

Framework.onPlayerLoaded(function(src)
    if not active then return end
    SetTimeout(4000, function()   -- let the inventory finish loading
        if not GetPlayerName(src) then return end
        if mirrorOn then sync(src)
        elseif C.convertOnJoin ~= false then pcall(settleLoose, src) end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    last[src], writing[src], shopping[src], due[src] = nil, nil, nil, nil
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
    return total + (MONEY and count(src, MONEY) or 0), have
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
    if Bank.cashSettle then Bank.cashSettle(src) end
    local ok, res = pay(src, amount)
    if Bank.cashSync then SetTimeout(0, function() Bank.cashSync(src) end) end
    return ok, res
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
    local ok, set = receive(src, amount)
    if Bank.cashSync then SetTimeout(0, function() Bank.cashSync(src) end) end
    return ok, set
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
