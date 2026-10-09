if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  PHONE
--
--  Everything the banking app needs that the bank UI does not:
--  finding somebody to pay, and asking somebody for money.
--
--  Three ways to pick a person, in the order a player reaches for
--  them: whoever is standing next to you, whoever you have paid
--  before, and a contact out of the phone. The first two are worked
--  out here and always work. Contacts come from the phone's own
--  table and are optional — see Config.Phone.contacts.
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
--  NEARBY
-- ═══════════════════════════════════════════════════════════
local function nearbyPlayers(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return {} end

  local origin = GetEntityCoords(ped)
  local radius = Config.Phone.nearbyRadius or 12.0
  local out = {}

  for _, id in ipairs(GetPlayers()) do
    id = tonumber(id)
    if id ~= src then
      local otherPed = GetPlayerPed(id)
      if otherPed and otherPed ~= 0 then
        local dist = #(origin - GetEntityCoords(otherPed))
        if dist <= radius then
          local xPlayer = Bank.getPlayer(id)
          if xPlayer then
            local acc = Bank.getPersonal(xPlayer.identifier)
            if acc then
              out[#out + 1] = {
                name    = Bank.fullName(xPlayer),
                account = acc.account_number,
                source  = id,
                dist    = math.floor(dist * 10) / 10
              }
            end
          end
        end
      end
    end
  end

  table.sort(out, function(a, b) return a.dist < b.dist end)
  return out
end

-- ═══════════════════════════════════════════════════════════
--  RECENT
--  Read back out of the player's own history, so it needs nothing
--  else running and it is the list they actually use.
-- ═══════════════════════════════════════════════════════════
local function recentPayees(identifier)
  -- the columns this reads are checked once at start
  if not Bank.schema.counterparty then return {} end

  local personal = Bank.getPersonal(identifier)
  if not personal then return {} end

  local ok, rows = pcall(function()
    return MySQL.query.await([[
        SELECT counterparty_name AS name, counterparty AS account, MAX(id) AS last
        FROM nz_bank_transactions
        WHERE account_id = ? AND direction = 'out' AND category = 'transfer'
          AND counterparty IS NOT NULL AND counterparty <> ''
        GROUP BY counterparty, counterparty_name
        ORDER BY last DESC
        LIMIT 8
    ]], { personal.id })
  end)

  if not ok then return {} end

  local out = {}
  for _, r in ipairs(rows or {}) do
    out[#out + 1] = { name = r.name or r.account, account = r.account }
  end
  return out
end

-- ═══════════════════════════════════════════════════════════
--  CONTACTS
--  The phone keeps its contacts in its own table, and a contact is
--  stored against a phone number rather than a bank account — so
--  the number has to be walked back to an owner before it means
--  anything here. Both table names are in config because they are
--  the phone's, not ours, and they move between versions.
--
--  If the tables are not there, this returns nothing and the other
--  two pickers carry on. It never takes the app down with it.
-- ═══════════════════════════════════════════════════════════
local contactsBroken = false

local function phoneContacts(identifier)
  local c = Config.Phone.contacts
  if not c or not c.enabled or contactsBroken then return {} end

  local ok, rows = pcall(function()
    return MySQL.query.await(([[
        SELECT c.name AS name, owner.%s AS identifier
        FROM %s c
        JOIN %s me    ON me.%s = c.%s
        JOIN %s owner ON owner.%s = c.%s
        WHERE me.%s = ?
        LIMIT 60
    ]]):format(
      c.phoneOwner,
      c.contactsTable,
      c.phonesTable, c.phoneNumber, c.contactOwner,
      c.phonesTable, c.phoneNumber, c.contactNumber,
      c.phoneOwner
    ), { identifier })
  end)

  if not ok then
    contactsBroken = true
    print('^3[nayzeee-banking]^7 phone contacts are switched on but the lookup failed — ' ..
          'check the table and column names in Config.Phone.contacts. ' ..
          'Nearby and recent still work; this will not be tried again until restart.')
    print('^3[nayzeee-banking]^7 ' .. tostring(rows))
    return {}
  end

  local out = {}
  for _, r in ipairs(rows or {}) do
    if r.identifier and r.identifier ~= identifier then
      local acc = Bank.getPersonal(r.identifier)
      if acc then
        out[#out + 1] = { name = r.name, account = acc.account_number }
      end
    end
  end
  return out
end

-- ═══════════════════════════════════════════════════════════
--  PICKER
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:phoneTargets', function(src)
  local identifier = Bank.identifier(src)
  if not identifier then return { nearby = {}, recent = {}, contacts = {} } end

  return {
    nearby   = nearbyPlayers(src),
    recent   = recentPayees(identifier),
    contacts = phoneContacts(identifier)
  }
end)

-- ═══════════════════════════════════════════════════════════
--  REQUEST MONEY
--  A request is a bill from one person to another. It goes through
--  the same bills table, so the other side pays it the same way
--  they pay anything else and the limits already apply.
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:requestMoney', function(src, accountNumber, amount, reason)
  if not Config.Bills.enabled then return { ok = false, msg = 'Requests are disabled.' } end

  local xPlayer = Bank.getPlayer(src)
  if not xPlayer then return { ok = false, msg = 'Player not found.' } end

  amount = Bank.round(tonumber(amount) or 0)
  if amount <= 0 then return { ok = false, msg = 'Enter an amount above zero.' } end

  local cap = Config.Phone.maxRequest or Config.Bills.maxAmount
  if amount > cap then
    return { ok = false, msg = ('The most you can request is %s%s.'):format(Config.Currency, cap) }
  end

  local mine = Bank.getPersonal(xPlayer.identifier)
  if not mine then return { ok = false, msg = 'You have no personal account.' } end

  local target = MySQL.single.await(
    'SELECT id, owner FROM nz_bank_accounts WHERE account_number = ? AND type = "personal"',
    { tostring(accountNumber) })
  if not target then return { ok = false, msg = 'No account with that number.' } end
  if target.owner == xPlayer.identifier then
    return { ok = false, msg = 'You cannot request money from yourself.' } end

  -- one open request per pair, so nobody gets buried
  local open = MySQL.scalar.await([[
      SELECT COUNT(*) FROM nz_bank_bills
      WHERE identifier = ? AND issuer_id = ? AND status IN ('pending','overdue')
  ]], { target.owner, mine.id }) or 0
  if open >= (Config.Phone.maxOpenRequests or 3) then
    return { ok = false, msg = 'You already have requests waiting with them.' }
  end

  local name = Bank.fullName(xPlayer)
  MySQL.insert.await([[
      INSERT INTO nz_bank_bills (identifier, issuer_id, issuer_label, sender_name, amount, reason, due_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], {
    target.owner, mine.id, name, name, amount,
    (reason ~= '' and reason or 'Money request'):sub(1, 120),
    os.time() + ((Config.Phone.requestMinutes or Config.Bills.overdueMinutes) * 60)
  })

  local other = ESX.GetPlayerFromIdentifier(target.owner)
  if other then
    Bank.notify(other.source, 'Money request',
      ('%s asked you for %s%s'):format(name, Config.Currency, amount), 'inform')
    TriggerClientEvent('nz_bank:refresh', other.source)
  end

  Bank.log('bills', 'Money requested',
    ('**%s%s** requested by %s'):format(Config.Currency, amount, name))

  return { ok = true, msg = ('Asked for %s%s.'):format(Config.Currency, amount) }
end)
