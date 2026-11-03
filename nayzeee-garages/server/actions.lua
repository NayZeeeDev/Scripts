--[[
  nayzeee-garages — server/actions.lua (NZ.Actions)

  Garage menu actions on a single vehicle: favourite, rename, transfer (to another garage
  or another player), share / unshare, sell to a nearby player (offer + buyer
  confirmation) and finance payments. Callback names: ARCHITECTURE.md §5.4; payloads and
  responses: §8.2 and web/src/lib/types.ts.
]]

local Actions = NZ.Actions
local Utils = NZ.Utils

local OFFER_SECONDS = 60          -- how long a sale offer stays valid
local SELL_RANGE = 10.0           -- max metres between seller and buyer
local SELL_VEHICLE_RANGE = 15.0   -- max metres between seller and an out vehicle being sold
local MAX_PRICE = 10000000
local MAX_PLATE_LENGTH = 16
local MAX_KEY_LENGTH = 72
local MAX_IDENTIFIER_LENGTH = 64

---@type table<number, table> offerId -> { offerId, seller, sellerIdentifier, sellerName, buyer, buyerIdentifier, buyerName, plate, price, expires }
local offers = {}
local nextOfferId = 0

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function setting(path, default)
  local value
  if NZ.Settings and NZ.Settings.get then value = NZ.Settings.get(path, default) end
  if value == nil then return default end
  return value
end

local function maxDistance()
  return tonumber(setting('garages.maxDistance', 25.0)) or 25.0
end

local function log(event, src, data)
  if not (NZ.Logs and NZ.Logs.add) then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then
    lib.print.warn(('[nayzeee-garages] could not log %s: %s'):format(event, err))
  end
end

local function toInt(value, min, max)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = math.floor(n)
  if min and n < min then return nil end
  if max and n > max then return nil end
  return n
end

local function readPlate(value)
  local plate = Utils.plate(value)
  if plate and #plate <= MAX_PLATE_LENGTH then return plate end
  return nil
end

local function money(amount)
  local digits = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
  local grouped = (digits:reverse():gsub('(%d%d%d)', '%1,')):reverse()
  grouped = grouped:gsub('^,', '')
  return tostring(setting('interface.currency', '$') or '$') .. grouped
end

local function garageFee() return math.max(0, toInt(setting('transfers.garageFee', 0)) or 0) end
local function playerFee() return math.max(0, toInt(setting('transfers.playerFee', 0)) or 0) end
local function maxShares() return math.max(0, toInt(setting('transfers.maxShares', 5)) or 0) end

local function notify(target, kind, message)
  if not target then return end
  TriggerClientEvent('nz:client:notify', target, { type = kind, message = message })
end

local function charge(src, amount, reason)
  if amount <= 0 then return true, nil end
  local paid, account = NZ.Bridge.pay(src, amount, reason)
  if not paid then return false, nil end
  return true, account
end

local function refund(src, amount, account, reason)
  if amount <= 0 then return end
  if not NZ.Bridge.addMoney(src, account or 'bank', amount, reason) then
    log('security.refund', src, { amount = amount, account = account, reason = reason })
  end
end

local function pedCoords(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

local function playersClose(a, b, range)
  if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
  local pa, pb = pedCoords(a), pedCoords(b)
  if not pa or not pb then return false end
  return Utils.dist(pa, pb) <= range
end

--- Online, loaded player by server id: { source, identifier, name } or nil.
local function onlinePlayer(serverId)
  local id = toInt(serverId, 1)
  if not id or not GetPlayerName(id) then return nil end
  local identifier = NZ.Bridge.getIdentifier(id)
  if not identifier then return nil end
  return { source = id, identifier = identifier, name = NZ.Bridge.getName(id) or GetPlayerName(id) or ('#' .. id) }
end

--- PlayerOption[] of online players except `src` and the identifiers in `exclude`.
local function playerOptions(src, exclude)
  local list = {}
  for _, player in ipairs(NZ.Bridge.getOnlinePlayers() or {}) do
    local serverId = tonumber(player.source)
    if serverId and serverId ~= src and not (exclude and player.identifier and exclude[player.identifier]) then
      list[#list + 1] = {
        serverId = serverId,
        name = tostring(player.name or GetPlayerName(serverId) or ('#' .. serverId)),
      }
    end
  end
  table.sort(list, function(a, b)
    local an, bn = a.name:lower(), b.name:lower()
    if an == bn then return a.serverId < b.serverId end
    return an < bn
  end)
  return list
end

local function sourceOf(location)
  if location.kind == 'garage' then return location.source == 'spawner' and 'spawner' or 'personal' end
  if location.kind == 'job' then return location.source == 'spawner' and 'spawner' or 'owned' end
  return 'personal'
end

local function financed(row)
  return type(row.finance) == 'table' and (tonumber(row.finance.balance) or 0) > 0
end

local function loadRow(plate)
  local row = NZ.DB.getVehicle(plate)
  if not row then return nil, L('Vehicle not found') end
  return row, nil
end

local function ownedRow(plate, identifier)
  local row, err = loadRow(plate)
  if not row then return nil, err end
  if row.owner ~= identifier then return nil, L('You do not own this vehicle') end
  return row, nil
end

--- Can `player` ({ source, identifier }) open the garage `garageKey`? Used before a vehicle
--- changes hands so the new owner is never locked out of where it is parked.
local function keyAccessibleBy(garageKey, player)
  local kind, id = Utils.key.parse(garageKey)
  if kind == 'G' then return NZ.Private.role(id, player.identifier) ~= nil end
  if kind == 'H' then
    if NZ.Housing and NZ.Housing.hasAccess then return NZ.Housing.hasAccess(player.identifier, id) == true end
    return false
  end
  if kind == 'L' then
    local location = NZ.Locations.get(id)
    if type(location) == 'table' and location.kind == 'garage' then
      return NZ.Access.canUse(player.source, location) == true
    end
  end
  return true
end

--- Common prologue: open session (with distance check), rate limit and identifier.
local function begin(src, bucket, ms)
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return nil, err or L('The garage is not open') end
  if not NZ.Access.rateLimit(src, bucket, ms) then return nil, L('Please wait a moment before trying again') end
  local identifier = NZ.Bridge.getIdentifier(src)
  if not identifier then return nil, L('Your character is not loaded') end
  return { session = session, identifier = identifier }, nil
end

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(src, payload)
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

--- Shares cleared, old owner's favourite removed, ownership history entry added.
local function afterOwnerChange(row, newOwner, via, price)
  NZ.DB.shares.clear(row.plate)
  if row.owner then NZ.DB.favourites.set(row.owner, row.plate, false) end
  local entry = { identifier = newOwner.identifier, name = newOwner.name, via = via, at = os.time() }
  if price then entry.price = price end
  NZ.DB.events.add(row.plate, 'owner', entry)
  local tracked = NZ.Vehicles.out and NZ.Vehicles.out[row.plate]
  if tracked then tracked.identifier = newOwner.identifier end
end

---------------------------------------------------------------------------------------
-- Transfer destinations
---------------------------------------------------------------------------------------

local function spacesLeft(location, key, identifier)
  local capacity = NZ.Locations.capacity(location, key, identifier)
  if type(capacity) ~= 'table' or capacity.mode == 'unlimited' then return nil end
  local total = tonumber(capacity.total)
  if not total then return nil end
  return math.max(0, math.floor(total - (tonumber(capacity.used) or 0)))
end

--- Validate a transfer destination for the player. Returns location, display name or nil.
local function destination(src, identifier, key, vtype)
  local kind, id = Utils.key.parse(key)
  if kind == 'L' then
    local location = NZ.Locations.get(id)
    if type(location) ~= 'table' or location.kind ~= 'garage' or location.enabled == false then return nil, nil end
    if sourceOf(location) == 'spawner' or (location.vehicleType or 'car') ~= vtype then return nil, nil end
    if not NZ.Access.canUse(src, location) then return nil, nil end
    return location, location.name
  elseif kind == 'G' then
    local group = NZ.Private.getGroup(id)
    if type(group) ~= 'table' or not NZ.Private.role(id, identifier) then return nil, nil end
    local location = NZ.Locations.get(tonumber(group.locationId))
    if type(location) ~= 'table' or location.kind ~= 'private' or location.enabled == false then return nil, nil end
    if (location.vehicleType or 'car') ~= vtype then return nil, nil end
    return location, group.label or location.name
  elseif kind == 'H' then
    local location = NZ.Locations.get(key)
    if type(location) ~= 'table' or location.enabled == false then return nil, nil end
    if (location.vehicleType or 'car') ~= vtype then return nil, nil end
    if not NZ.Access.canUse(src, location) then return nil, nil end
    return location, location.name
  end
  return nil, nil
end

--- Every garage the player may move `row` to (TransferOptions.garages).
local function garageDestinations(src, identifier, row)
  local vtype = NZ.Vehicles.vehicleTypeOf(row)
  local fee = garageFee()
  local list, seen = {}, {}

  local function add(key)
    if seen[key] or key == row.garageKey then return end
    seen[key] = true
    local location, name = destination(src, identifier, key, vtype)
    if not location then return end
    list[#list + 1] = {
      key = key,
      name = tostring(NZ.Locations.keyName(key) or name or key),
      spacesLeft = spacesLeft(location, key, identifier),
      fee = fee,
    }
  end

  for _, location in ipairs(NZ.Locations.all('garage') or {}) do
    if location.id then add(Utils.key.location(location.id)) end
  end
  for _, group in ipairs(NZ.Private.groupsFor(identifier, nil) or {}) do
    if group.id then add(Utils.key.group(group.id)) end
  end
  if NZ.Housing and NZ.Housing.viewsFor then
    for _, view in ipairs(NZ.Housing.viewsFor(identifier) or {}) do
      if type(view) == 'table' and type(view.id) == 'string' and view.id:sub(1, 1) == 'H' then add(view.id) end
    end
  end

  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return list
end

---------------------------------------------------------------------------------------
-- Shares
---------------------------------------------------------------------------------------

--- ShareData for the viewer. Owners see everything; a shared player only sees themselves.
local function shareData(src, identifier, row)
  local max = maxShares()
  if row.owner ~= identifier then
    local own = {}
    if NZ.Vehicles.isSharedWith(row.plate, identifier) then
      own[1] = { identifier = identifier, name = NZ.Bridge.getName(src) or '' }
    end
    return { sharedWith = own, players = {}, max = max }
  end
  local sharedWith, exclude = {}, { [identifier] = true }
  for _, share in ipairs(NZ.DB.shares.forPlate(row.plate) or {}) do
    if type(share) == 'table' and share.identifier then
      exclude[share.identifier] = true
      local name = share.name
      if type(name) ~= 'string' or name == '' then name = NZ.Bridge.getCharacterName(share.identifier) or '' end
      sharedWith[#sharedWith + 1] = { identifier = share.identifier, name = name }
    end
  end
  return { sharedWith = sharedWith, players = playerOptions(src, exclude), max = max }
end

---------------------------------------------------------------------------------------
-- Sale offers
---------------------------------------------------------------------------------------

local function pruneOffers()
  local now = os.time()
  for id, offer in pairs(offers) do
    if offer.expires < now then offers[id] = nil end
  end
end

--- Cancel every pending sale offer involving `src` (seller or buyer) and tell the other
--- party. Called on playerDropped; safe to call any time.
---@param src number
function Actions.cancelOffers(src)
  for id, offer in pairs(offers) do
    if offer.seller == src or offer.buyer == src then
      offers[id] = nil
      local other = offer.seller == src and offer.buyer or offer.seller
      if other ~= src and GetPlayerName(other) then
        notify(other, 'info', L('The sale of {plate} was cancelled', { plate = offer.plate }))
      end
    end
  end
end

--- playerDropped hook (server/main.lua calls NZ.<Module>.onPlayerDropped for every module).
---@param src number
function Actions.onPlayerDropped(src)
  Actions.cancelOffers(src)
end

local function completeSale(src, offer)
  local seller = offer.seller
  if not GetPlayerName(seller) or NZ.Bridge.getIdentifier(seller) ~= offer.sellerIdentifier then
    return fail(L('The seller is no longer available'))
  end
  local row = NZ.DB.getVehicle(offer.plate)
  if not row or row.owner ~= offer.sellerIdentifier or financed(row) or row.blocked
    or row.state == 'impounded' or NZ.Vehicles.fleetOf(row) then
    notify(seller, 'error', L('The sale of {plate} could not be completed', { plate = offer.plate }))
    return fail(L('This vehicle is no longer for sale'))
  end

  local buyer = { source = src, identifier = offer.buyerIdentifier, name = NZ.Bridge.getName(src) or offer.buyerName }
  if row.garageKey and not keyAccessibleBy(row.garageKey, buyer) then
    return fail(L('This vehicle is no longer for sale'))
  end

  local price = offer.price
  local paid, account = charge(src, price, 'nayzeee-garages:vehicle-purchase')
  if not paid then
    notify(seller, 'error', L('{name} could not afford {plate}', { name = buyer.name, plate = offer.plate }))
    return fail(L('You cannot afford this ({amount})', { amount = money(price) }))
  end

  if not NZ.DB.updateVehicle(offer.plate, { owner = buyer.identifier }) then
    refund(src, price, account, 'nayzeee-garages:vehicle-purchase-refund')
    return fail(L('Something went wrong'))
  end

  if not NZ.Bridge.addMoney(seller, 'bank', price, 'nayzeee-garages:vehicle-sale') then
    NZ.DB.updateVehicle(offer.plate, { owner = offer.sellerIdentifier })
    refund(src, price, account, 'nayzeee-garages:vehicle-purchase-refund')
    log('security.sell', src, {
      plate = offer.plate, seller = offer.sellerIdentifier, price = price,
      reason = 'seller payout failed, sale reverted',
    })
    return fail(L('Something went wrong'))
  end

  afterOwnerChange(row, buyer, 'sale', price)
  notify(seller, 'success', L('You sold {plate} to {name} for {amount}', {
    plate = offer.plate, name = buyer.name, amount = money(price),
  }))
  -- The buyer's client shows its own confirmation toast after accepting.
  log('vehicle.sell', src, {
    plate = offer.plate, action = 'sold', price = price,
    seller = offer.sellerIdentifier, sellerName = offer.sellerName,
    buyer = buyer.identifier, buyerName = buyer.name,
  })
  return ok(nil)
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

-- { plate, value } -> null
register('nz:garage:favourite', function(src, payload)
  local ctx, err = begin(src, 'garage:favourite', 300)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate or type(payload.value) ~= 'boolean' then return fail(L('Invalid request')) end
  local row, rowErr = loadRow(plate)
  if not row then return fail(rowErr) end
  if not NZ.Vehicles.accessOf(src, row, ctx.session, { identifier = ctx.identifier }) then
    return fail(L('You do not have access to this vehicle'))
  end
  if not NZ.DB.favourites.set(ctx.identifier, plate, payload.value) then return fail(L('Something went wrong')) end
  log('vehicle.favourite', src, { plate = plate, value = payload.value })
  return ok(nil)
end)

-- { plate, name|null } -> null
register('nz:garage:rename', function(src, payload)
  local ctx, err = begin(src, 'garage:rename', 1000)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate or (payload.name ~= nil and type(payload.name) ~= 'string') then return fail(L('Invalid request')) end
  local row, rowErr = ownedRow(plate, ctx.identifier)
  if not row then return fail(rowErr) end
  local nickname = Utils.cleanText(payload.name, 32)
  if not NZ.DB.updateVehicle(plate, { nickname = nickname or false }) then return fail(L('Something went wrong')) end
  log('vehicle.rename', src, { plate = plate, from = row.nickname, to = nickname })
  return ok(nil)
end)

-- { plate } -> TransferOptions
register('nz:garage:transferOptions', function(src, payload)
  local ctx, err = begin(src, 'garage:transferOptions', 300)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid request')) end
  local row, rowErr = ownedRow(plate, ctx.identifier)
  if not row then return fail(rowErr) end
  local garages, players = {}, {}
  if setting('transfers.garageEnabled', true) then garages = garageDestinations(src, ctx.identifier, row) end
  -- The Sell modal reuses this list, so fill it when either player feature is enabled.
  if setting('transfers.playerEnabled', true) or setting('transfers.sellEnabled', true) then
    players = playerOptions(src, { [ctx.identifier] = true })
  end
  return ok({ garages = garages, players = players, garageFee = garageFee(), playerFee = playerFee() })
end)

local function transferToGarage(src, ctx, plate, target)
  if not setting('transfers.garageEnabled', true) then return fail(L('Garage transfers are disabled')) end
  if type(target) ~= 'string' or #target < 2 or #target > MAX_KEY_LENGTH then return fail(L('Invalid garage')) end

  return NZ.Vehicles.withLock(plate, function()
    local row, rowErr = ownedRow(plate, ctx.identifier)
    if not row then return fail(rowErr) end
    if row.blocked then return fail(L('This vehicle is blocked')) end
    if NZ.Vehicles.fleetOf(row) then return fail(L('Fleet vehicles cannot be transferred')) end
    if row.state ~= 'garaged' then return fail(L('The vehicle must be parked in a garage to transfer it')) end
    if target == row.garageKey then return fail(L('The vehicle is already in that garage')) end

    local location, name = destination(src, ctx.identifier, target, NZ.Vehicles.vehicleTypeOf(row))
    if not location then return fail(L('You cannot move this vehicle to that garage')) end
    local left = spacesLeft(location, target, ctx.identifier)
    if left and left <= 0 then return fail(L('That garage is full')) end

    local fee = garageFee()
    local paid, account = charge(src, fee, 'nayzeee-garages:transfer')
    if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(fee) })) end

    local garageName = NZ.Locations.keyName(target) or name
    if not NZ.DB.updateVehicle(plate, { garageKey = target, garageName = garageName }) then
      refund(src, fee, account, 'nayzeee-garages:transfer-refund')
      return fail(L('Something went wrong'))
    end
    log('vehicle.transfer', src, {
      plate = plate, type = 'garage', from = row.garageKey, to = target, toName = garageName, fee = fee,
    })
    return ok(nil)
  end)
end

local function transferToPlayer(src, ctx, plate, target)
  if not setting('transfers.playerEnabled', true) then return fail(L('Player transfers are disabled')) end
  local player = onlinePlayer(target)
  if not player then return fail(L('That player is not available')) end
  if player.source == src or player.identifier == ctx.identifier then
    return fail(L('You cannot transfer a vehicle to yourself'))
  end

  return NZ.Vehicles.withLock(plate, function()
    local row, rowErr = ownedRow(plate, ctx.identifier)
    if not row then return fail(rowErr) end
    if row.blocked then return fail(L('This vehicle is blocked')) end
    if NZ.Vehicles.fleetOf(row) then return fail(L('Fleet vehicles cannot be transferred')) end
    if financed(row) then return fail(L('Pay off the finance before transferring')) end
    if row.state == 'out' then return fail(L('Park the vehicle before transferring it')) end
    if row.garageKey and not keyAccessibleBy(row.garageKey, player) then
      return fail(L('Move the vehicle to a public garage first'))
    end

    local fee = playerFee()
    local paid, account = charge(src, fee, 'nayzeee-garages:transfer')
    if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(fee) })) end

    if not NZ.DB.updateVehicle(plate, { owner = player.identifier }) then
      refund(src, fee, account, 'nayzeee-garages:transfer-refund')
      return fail(L('Something went wrong'))
    end

    afterOwnerChange(row, player, 'transfer', nil)
    local fromName = NZ.Bridge.getName(src) or ''
    notify(player.source, 'info', L('{name} transferred a vehicle to you ({plate})', { name = fromName, plate = plate }))
    log('vehicle.transfer', src, {
      plate = plate, type = 'player', fee = fee,
      from = ctx.identifier, fromName = fromName, to = player.identifier, toName = player.name,
    })
    return ok(nil)
  end)
end

-- { plate, type = 'garage'|'player', target = garageKey|serverId } -> null
register('nz:garage:transfer', function(src, payload)
  local ctx, err = begin(src, 'garage:transfer', 1500)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid request')) end
  if payload.type == 'garage' then return transferToGarage(src, ctx, plate, payload.target) end
  if payload.type == 'player' then return transferToPlayer(src, ctx, plate, payload.target) end
  return fail(L('Invalid request'))
end)

-- { plate } -> ShareData
register('nz:garage:shares', function(src, payload)
  local ctx, err = begin(src, 'garage:shares', 500)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid request')) end
  local row, rowErr = loadRow(plate)
  if not row then return fail(rowErr) end
  if row.owner ~= ctx.identifier and not NZ.Vehicles.isSharedWith(plate, ctx.identifier) then
    return fail(L('You do not have access to this vehicle'))
  end
  return ok(shareData(src, ctx.identifier, row))
end)

-- { plate, serverId } -> ShareData
register('nz:garage:share', function(src, payload)
  local ctx, err = begin(src, 'garage:share', 1000)
  if not ctx then return fail(err) end
  if not setting('transfers.shareEnabled', true) then return fail(L('Sharing vehicles is disabled')) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid request')) end
  local row, rowErr = ownedRow(plate, ctx.identifier)
  if not row then return fail(rowErr) end
  if NZ.Vehicles.fleetOf(row) then return fail(L('Fleet vehicles cannot be shared')) end

  local player = onlinePlayer(payload.serverId)
  if not player then return fail(L('That player is not available')) end
  if player.source == src or player.identifier == ctx.identifier then
    return fail(L('You cannot share a vehicle with yourself'))
  end

  local current = NZ.DB.shares.forPlate(plate) or {}
  for _, share in ipairs(current) do
    if type(share) == 'table' and share.identifier == player.identifier then
      return fail(L('This vehicle is already shared with that player'))
    end
  end
  local max = maxShares()
  if #current >= max then
    return fail(L('You can share a vehicle with at most {max} players', { max = max }))
  end

  if not NZ.DB.shares.add(plate, player.identifier, player.name, ctx.identifier) then
    return fail(L('Something went wrong'))
  end
  local ownerName = NZ.Bridge.getName(src) or ''
  notify(player.source, 'info', L('{name} shared a vehicle with you ({plate})', { name = ownerName, plate = plate }))
  log('vehicle.share', src, { plate = plate, action = 'add', target = player.identifier, targetName = player.name })
  return ok(shareData(src, ctx.identifier, row))
end)

-- { plate, identifier } -> ShareData
register('nz:garage:unshare', function(src, payload)
  local ctx, err = begin(src, 'garage:unshare', 500)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  local identifier = payload.identifier
  if not plate or type(identifier) ~= 'string' or identifier == '' or #identifier > MAX_IDENTIFIER_LENGTH then
    return fail(L('Invalid request'))
  end
  local row, rowErr = loadRow(plate)
  if not row then return fail(rowErr) end
  local isOwner = row.owner == ctx.identifier
  if not isOwner and identifier ~= ctx.identifier then return fail(L('You do not have access to this vehicle')) end
  if not NZ.Vehicles.isSharedWith(plate, identifier) then
    return fail(L('This vehicle is not shared with that player'))
  end

  if not NZ.DB.shares.remove(plate, identifier) then return fail(L('Something went wrong')) end
  if isOwner then
    local removed = NZ.Bridge.getSourceByIdentifier(identifier)
    if removed then notify(removed, 'info', L('You no longer have access to {plate}', { plate = plate })) end
  elseif row.owner then
    local owner = NZ.Bridge.getSourceByIdentifier(row.owner)
    if owner then
      notify(owner, 'info', L('{name} gave back access to {plate}', { name = NZ.Bridge.getName(src) or '', plate = plate }))
    end
  end
  log('vehicle.share', src, { plate = plate, action = 'remove', target = identifier, byOwner = isOwner })
  return ok(shareData(src, ctx.identifier, row))
end)

-- { plate, serverId, price } -> null (offer sent, buyer confirms with nz:garage:sellRespond)
register('nz:garage:sell', function(src, payload)
  local ctx, err = begin(src, 'garage:sell', 2000)
  if not ctx then return fail(err) end
  if not setting('transfers.sellEnabled', true) then return fail(L('Selling vehicles is disabled')) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid request')) end

  local price = tonumber(payload.price)
  if not price or price ~= price or price ~= math.floor(price) or price < 1 or price > MAX_PRICE then
    return fail(L('Enter a price between {min} and {max}', { min = money(1), max = money(MAX_PRICE) }))
  end
  price = math.floor(price)

  local buyer = onlinePlayer(payload.serverId)
  if not buyer then return fail(L('That player is not available')) end
  if buyer.source == src or buyer.identifier == ctx.identifier then
    return fail(L('You cannot sell a vehicle to yourself'))
  end
  if not playersClose(src, buyer.source, SELL_RANGE) then return fail(L('The buyer must be standing next to you')) end

  local row, rowErr = ownedRow(plate, ctx.identifier)
  if not row then return fail(rowErr) end
  if row.blocked then return fail(L('This vehicle is blocked')) end
  if NZ.Vehicles.fleetOf(row) then return fail(L('Fleet vehicles cannot be sold')) end
  if financed(row) then return fail(L('Pay off the finance before selling')) end
  if row.state == 'impounded' then return fail(L('This vehicle is impounded')) end
  if row.state == 'out' then
    local out, entity = NZ.Vehicles.isOut(plate)
    local pos = pedCoords(src)
    if not (out and entity and pos and Utils.dist(GetEntityCoords(entity), pos) <= SELL_VEHICLE_RANGE) then
      return fail(L('Bring the vehicle here or park it in a garage first'))
    end
  end
  if row.garageKey and not keyAccessibleBy(row.garageKey, buyer) then
    return fail(L('Move the vehicle to a public garage first'))
  end

  pruneOffers()
  for _, offer in pairs(offers) do
    if offer.plate == plate then return fail(L('An offer for this vehicle is already pending')) end
    if offer.buyer == buyer.source then return fail(L('That player already has a pending offer')) end
  end

  nextOfferId = nextOfferId + 1
  local offerId = nextOfferId
  local sellerName = NZ.Bridge.getName(src) or ''
  local offer = {
    offerId = offerId,
    seller = src,
    sellerIdentifier = ctx.identifier,
    sellerName = sellerName,
    buyer = buyer.source,
    buyerIdentifier = buyer.identifier,
    buyerName = buyer.name,
    plate = plate,
    price = price,
    expires = os.time() + OFFER_SECONDS,
  }
  offers[offerId] = offer

  SetTimeout((OFFER_SECONDS + 1) * 1000, function()
    if offers[offerId] ~= offer then return end
    offers[offerId] = nil
    if GetPlayerName(offer.seller) then
      notify(offer.seller, 'info', L('Your offer for {plate} expired', { plate = offer.plate }))
    end
  end)

  local hash = tonumber(row.hash)
  if (not hash or hash == 0) and type(row.model) == 'string' and row.model ~= '' then hash = joaat(row.model) end
  TriggerClientEvent('nz:client:sellOffer', buyer.source, {
    offerId = offerId,
    plate = plate,
    hash = hash,
    model = row.model or '',
    label = (type(row.nickname) == 'string' and row.nickname ~= '') and row.nickname or (row.model or plate),
    price = price,
    sellerName = sellerName,
    expires = offer.expires,
  })
  log('vehicle.sell', src, {
    plate = plate, action = 'offer', price = price, buyer = buyer.identifier, buyerName = buyer.name,
  })
  return ok(nil)
end)

-- { offerId, accept } -> null (buyer only)
register('nz:garage:sellRespond', function(src, payload)
  if not NZ.Access.rateLimit(src, 'garage:sellRespond', 1000) then
    return fail(L('Please wait a moment before trying again'))
  end
  local offerId = toInt(payload.offerId, 1)
  if not offerId or type(payload.accept) ~= 'boolean' then return fail(L('Invalid request')) end
  local offer = offers[offerId]
  if not offer or offer.buyer ~= src then return fail(L('This offer is no longer available')) end
  offers[offerId] = nil

  if NZ.Bridge.getIdentifier(src) ~= offer.buyerIdentifier then
    return fail(L('This offer is no longer available'))
  end
  if os.time() > offer.expires then
    notify(offer.seller, 'info', L('Your offer for {plate} expired', { plate = offer.plate }))
    return fail(L('This offer has expired'))
  end

  if not payload.accept then
    notify(offer.seller, 'info', L('{name} declined your offer for {plate}', { name = offer.buyerName, plate = offer.plate }))
    log('vehicle.sell', src, {
      plate = offer.plate, action = 'declined', price = offer.price,
      seller = offer.sellerIdentifier, buyer = offer.buyerIdentifier,
    })
    return ok(nil)
  end

  return NZ.Vehicles.withLock(offer.plate, completeSale, src, offer)
end)

-- { plate, full } -> Finance|null (null once paid off)
register('nz:garage:payFinance', function(src, payload)
  local ctx, err = begin(src, 'garage:payFinance', 1500)
  if not ctx then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate or (payload.full ~= nil and type(payload.full) ~= 'boolean') then return fail(L('Invalid request')) end
  local full = payload.full == true

  return NZ.Vehicles.withLock(plate, function()
    local row, rowErr = ownedRow(plate, ctx.identifier)
    if not row then return fail(rowErr) end
    local finance = row.finance
    local balance = type(finance) == 'table' and math.floor(tonumber(finance.balance) or 0) or 0
    if balance <= 0 then return fail(L('This vehicle has no outstanding finance')) end

    local payment = math.max(0, math.floor(tonumber(finance.payment) or 0))
    local payAll = full or payment <= 0 or payment >= balance
    local amount = payAll and balance or payment

    local paid, account = charge(src, amount, 'nayzeee-garages:finance')
    if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(amount) })) end

    local updated = nil
    if not payAll then
      -- A paid instalment restarts the payment timer with the full interval, exactly like
      -- qb-vehicleshop / qbx_vehicleshop do (their repossession check is financetime < 1).
      -- Never reuse the time that was left: an overdue vehicle would stay overdue.
      local interval = tonumber(finance.intervalHours)
      if not interval or interval <= 0 then interval = tonumber(NZ.DB.financeIntervalHours()) or 24 end
      local newBalance = balance - amount
      local left = math.max(0, (toInt(finance.paymentsLeft) or 1) - 1)
      local nextPayment = payment
      if left == 0 and newBalance > 0 then
        -- rounding left a remainder: one more payment of exactly what is owed
        left, nextPayment = 1, newBalance
      end
      updated = {
        balance = newBalance,
        payment = nextPayment,
        paymentsLeft = left,
        -- First payment through us records the plan length for the progress display.
        paymentsTotal = finance.paymentsTotal or toInt(finance.paymentsLeft),
        intervalHours = interval,
        nextPaymentHours = interval,
        overdue = false,
      }
    end

    if not NZ.DB.updateVehicle(plate, { finance = updated or false }) then
      refund(src, amount, account, 'nayzeee-garages:finance-refund')
      return fail(L('Something went wrong'))
    end
    log('vehicle.finance', src, {
      plate = plate, amount = amount, paidOff = updated == nil, balance = updated and updated.balance or 0,
    })
    return ok(updated)
  end)
end)
