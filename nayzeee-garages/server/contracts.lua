--[[
  nayzeee-garages — car sale contracts (server): NZ.Contracts. docs/CARLOCK.md §12.

  1. The seller uses a blank contract item (Config.CarLock.items.contract, registered in
     bridge/server/listeners.lua -> NZ.Contracts.useItem): the `contract` app opens in draft
     mode with the seller's own vehicles standing nearby (or the one they sit in) and the
     players nearby (Config.Contracts.maxDistance, measured from the SERVER ped positions).
  2. 'nz:contract:send' { plate, buyer, price, terms, signature }: everything is checked on the
     server (draft session from a real item use, blank contract still carried, own vehicle,
     not a fleet vehicle, not financed / impounded / blocked / towed / wearing a fake plate,
     buyer and vehicle in range, one pending contract per seller, buyer and vehicle) and the
     buyer's client opens the review. The contract expires after Config.Contracts.expireSeconds.
  3. 'nz:contract:sign' { contractId, signature } (buyer, ONE attempt per contract): the whole
     sale is validated again, then: blank contract consumed -> buyer charged from
     Config.Contracts.account -> owner changed -> seller paid (NZ.Actions.sellVehicle: a step
     that fails undoes the ones before it; shares cleared, ownership history entry
     via = 'contract', NZ.CarLock.rekey for the buyer) -> buyer key (key item in physical mode,
     temporary key otherwise) -> signed copies (Config.Contracts.signedCopies).
  4. 'nz:contract:decline' { contractId }: the buyer declines, or the seller withdraws.
     Expiry, a party leaving and every outcome are told to both players
     ('nz:client:contract:status' + notification).
  5. Signed copies (Config.CarLock.items.signedContract) carry the contract in their metadata;
     using one opens the read-only `view` (`verified` = the ownership history of the plate
     holds that contract: metadata edited through an inventory is never shown as genuine).

  Signatures are SVG path data in a 400x140 box (M / L commands only, <= 4000 characters),
  rebuilt by the server from the numbers it accepts.
]]

local Contracts = NZ.Contracts
local Utils = NZ.Utils

local DRAFT_SECONDS = 900          -- a draft session lasts this long after the item use
local MAX_TERMS = 600              -- characters of the terms
local MAX_TERMS_LINES = 12
local MAX_SIGNATURE = 4000         -- characters of SVG path data
local SIG_W, SIG_H = 400, 140      -- signature pad box
local MIN_INK = 40                 -- total stroke length (pad units) of a real signature
local MAX_VEHICLES = 8             -- vehicles offered in the draft
local MAX_BUYERS = 12
local MAX_NAME = 60
local HISTORY_LOOKUP = 100         -- ownership history entries searched to verify a copy
local RATE = { use = 1000, refresh = 1000, send = 2500, sign = 2000, decline = 800 }

local contracts = {}               -- [id] = contract (pending or being signed)
local drafts = {}                  -- [src] = { identifier, slot, at }
local usedIds = {}                 -- ids handed out this session

---------------------------------------------------------------------------------------
-- Config and small helpers
---------------------------------------------------------------------------------------

local function num(value, min, max, default)
  local n = tonumber(value)
  if not n or n ~= n then return default end
  return math.max(min, math.min(max, n))
end

--- Config.Contracts with defaults and bounds.
local function cfg()
  local c = type(Config.Contracts) == 'table' and Config.Contracts or {}
  return {
    enabled = c.enabled ~= false,
    maxDistance = num(c.maxDistance, 2.0, 50.0, 10.0) + 0.0,
    expireSeconds = math.floor(num(c.expireSeconds, 30, 1800, 120)),
    account = c.account == 'cash' and 'cash' or 'bank',
    signedCopies = c.signedCopies ~= false,
    maxPrice = math.floor(num(c.maxPrice, 1, 2000000000, 10000000)),
  }
end

local function itemName(key)
  if NZ.CarLock and type(NZ.CarLock.itemName) == 'function' then
    local ok, name = pcall(NZ.CarLock.itemName, key)
    if ok and type(name) == 'string' and name ~= '' then return name end
  end
  return key == 'signedContract' and 'signed_contract' or 'vehicle_contract'
end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

local function identifierOf(src)
  local ok, id = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

local function cleanName(value)
  return Utils.cleanText(type(value) == 'string' and value or nil, MAX_NAME)
end

local function nameOf(src)
  local ok, name = pcall(NZ.Bridge.getName, src)
  return cleanName(ok and name or nil) or cleanName(GetPlayerName(tostring(src))) or ('#' .. tostring(src))
end

local function notify(target, kind, message)
  if not validSrc(target) then return end
  TriggerClientEvent('nz:client:notify', target, { type = kind, message = message })
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('[nayzeee-garages] contracts: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function setting(path, default)
  local value = nil
  if NZ.Settings and type(NZ.Settings.get) == 'function' then
    local ok, res = pcall(NZ.Settings.get, path, default)
    if ok then value = res end
  end
  if value == nil then return default end
  return value
end

local function money(amount)
  local digits = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
  local grouped = (digits:reverse():gsub('(%d%d%d)', '%1,')):reverse():gsub('^,', '')
  return tostring(setting('interface.currency', '$') or '$') .. grouped
end

local function limited(src, bucket)
  return not NZ.Access.rateLimit(src, 'contract:' .. bucket, RATE[bucket] or 1000)
end

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function pedOf(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return ped
end

local function posOf(src)
  local ped = pedOf(src)
  return ped and GetEntityCoords(ped) or nil
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function toSigned(hash)
  local n = tonumber(hash)
  if not n or n ~= n then return nil end
  n = math.floor(n) % 4294967296
  if n >= 2147483648 then n = n - 4294967296 end
  return math.tointeger(n) or n
end

local function rowHash(row)
  local h = tonumber(row.hash)
  if h and h ~= 0 then return toSigned(h) end
  if type(row.model) == 'string' and row.model ~= '' then return toSigned(joaat(row.model)) end
  return nil
end

--- Are two players in the same routing bucket and within `range` metres (server peds)?
local function playersClose(a, b, range)
  if GetPlayerRoutingBucket(tostring(a)) ~= GetPlayerRoutingBucket(tostring(b)) then return false end
  local pa, pb = posOf(a), posOf(b)
  if not pa or not pb then return false end
  return #(pa - pb) <= range
end

--- Real plate of a vehicle entity: the plate under a fake plate, the plate the server
--- recorded for garage vehicles, else the plate text.
local function identityOf(entity)
  local fake = NZ.FakePlates
  if type(fake) == 'table' and type(fake.plateOf) == 'function' then
    local okP, plate = pcall(fake.plateOf, entity)
    if okP then return plate end
  end
  local carLock = NZ.CarLock
  if type(carLock) == 'table' and type(carLock.realPlate) == 'function' then
    local okR, plate = pcall(carLock.realPlate, entity)
    if okR then return plate end
  end
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

local function wearsFakePlate(entity)
  local fake = NZ.FakePlates
  if type(fake) ~= 'table' or type(fake.isFake) ~= 'function' then return false end
  local okF, res = pcall(fake.isFake, entity)
  return okF and res == true
end

local function towing(entity)
  if type(NZ.Tow) ~= 'table' or type(NZ.Tow.isTowing) ~= 'function' then return false end
  local okT, res = pcall(NZ.Tow.isTowing, entity)
  return okT and res == true
end

local function financed(row)
  return type(row.finance) == 'table' and (tonumber(row.finance.balance) or 0) > 0
end

local function fleetOf(row)
  if type(NZ.Vehicles.fleetOf) == 'function' then
    local okF, kind = pcall(NZ.Vehicles.fleetOf, row)
    if okF and kind then return true end
  end
  return (row.ownerType ~= nil and row.ownerType ~= 'player') or row.job ~= nil or row.gang ~= nil
end

local function percent(value)
  local n = tonumber(value)
  if not n or n ~= n then return nil end
  return math.floor(math.max(0, math.min(100, n)) + 0.5)
end

--- Dead, downed, cuffed or escorted (NZ.Vehicles.incapacitated).
local function incapacitated(src)
  if type(NZ.Vehicles.incapacitated) ~= 'function' then return false end
  local okI, res = pcall(NZ.Vehicles.incapacitated, src)
  return okI and res == true
end

local function vehicleTypeOf(row)
  if type(NZ.Vehicles.vehicleTypeOf) == 'function' then
    local okT, vtype = pcall(NZ.Vehicles.vehicleTypeOf, row)
    if okT and (vtype == 'car' or vtype == 'sea' or vtype == 'air') then return vtype end
  end
  return 'car'
end

--- Kilometres for the document: the stored value, or the live counter of the entity when it
--- is plausible (the counter is written by the driver's client).
local function mileageOf(row, entity)
  local stored = math.max(0, tonumber(row.mileage) or 0)
  local live = isVehicle(entity) and tonumber(Entity(entity).state.nzMileage) or nil
  if live and live == live and live >= stored and live <= stored + 5000 then stored = live end
  return Utils.round(stored, 1)
end

---------------------------------------------------------------------------------------
-- Text, signatures, ids
---------------------------------------------------------------------------------------

--- Terms: printable text (line breaks kept, at most MAX_TERMS_LINES lines), no markup
--- characters, at most MAX_TERMS characters. '' when empty, nil when not valid UTF-8 / too long.
local function cleanTerms(value)
  if value == nil then return '' end
  if type(value) ~= 'string' or #value > MAX_TERMS * 4 then return nil end
  if not utf8.len(value) then return nil end
  local text = value:gsub('\r\n?', '\n'):gsub('[\0-\9\11-\31\127]', ''):gsub('[<>]', '')
  local lines = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    line = line:gsub('%s+$', '')
    if line ~= '' or (#lines > 0 and lines[#lines] ~= '') then lines[#lines + 1] = line end
  end
  while #lines > 0 and lines[#lines] == '' do lines[#lines] = nil end
  if #lines > MAX_TERMS_LINES then return nil end
  text = table.concat(lines, '\n')
  if (utf8.len(text) or MAX_TERMS + 1) > MAX_TERMS then return nil end
  return text
end

--- A signature drawn on the 400x140 pad as SVG path data ("M x y L x y ..."). The server
--- keeps only M / L commands with numbers inside the box (rounded to whole units) and
--- rebuilds the string itself. nil when empty, malformed, a dot or too long.
---@param value any
---@return string|nil
local function cleanSignature(value)
  if type(value) ~= 'string' or #value < 7 or #value > MAX_SIGNATURE then return nil end
  local parts, pos, len = {}, 1, #value
  local ink, lastX, lastY, points, sawLine = 0, nil, nil, 0, false
  while pos <= len do
    local s, e, cmd, xs, ys = value:find('^[%s,]*([ML])[%s,]*(%-?%d+%.?%d*)[%s,]+(%-?%d+%.?%d*)', pos)
    if not s then
      if value:find('^[%s,]*$', pos) then break end
      return nil
    end
    pos = e + 1
    local x, y = tonumber(xs), tonumber(ys)
    if not x or not y or x < -2 or y < -2 or x > SIG_W + 2 or y > SIG_H + 2 then return nil end
    x = math.floor(math.max(0, math.min(SIG_W, x)) + 0.5)
    y = math.floor(math.max(0, math.min(SIG_H, y)) + 0.5)
    if #parts == 0 and cmd ~= 'M' then return nil end
    if cmd == 'L' then
      sawLine = true
      if lastX then ink = ink + math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2) end
    end
    lastX, lastY = x, y
    points = points + 1
    parts[#parts + 1] = ('%s%d %d'):format(cmd, x, y)
  end
  if points < 2 or not sawLine or ink < MIN_INK then return nil end
  local out = table.concat(parts)
  if #out > MAX_SIGNATURE then return nil end
  return out
end

local function newId()
  for _ = 1, 20 do
    local id = ('%04X%04X'):format(math.random(0, 0xFFFF), math.random(0, 0xFFFF))
    if not usedIds[id] and not contracts[id] then
      usedIds[id] = true
      return id
    end
  end
  return nil
end

local function readId(value)
  if type(value) ~= 'string' or not value:match('^%x%x%x%x%x%x%x%x$') then return nil end
  return value:upper()
end

---------------------------------------------------------------------------------------
-- Vehicles and buyers near the seller
---------------------------------------------------------------------------------------

--- Why this owned vehicle cannot be sold right now (translated), or nil.
local function blockReason(row, entity, buyer)
  if fleetOf(row) then return L('Fleet vehicles cannot be sold') end
  if row.blocked then return L('This vehicle is blocked') end
  if row.state == 'impounded' then return L('This vehicle is impounded') end
  if financed(row) then return L('Pay off the finance before selling') end
  if isVehicle(entity) then
    if towing(entity) then return L('This vehicle is being towed') end
    if wearsFakePlate(entity) then return L('Remove the fake plate first') end
  end
  if buyer and row.garageKey and type(NZ.Actions.garageAccessibleBy) == 'function' then
    local okA, accessible = pcall(NZ.Actions.garageAccessibleBy, row.garageKey, buyer)
    if okA and accessible == false then
      return L('Its last garage is private: store it in a public garage first')
    end
  end
  return nil
end

--- The seller's own vehicles within range (the one they sit in first), nearest first:
--- { { entity, row, dist } }.
local function nearbyOwned(src, identifier, range)
  local ped = pedOf(src)
  if not ped then return {} end
  local origin = GetEntityCoords(ped)
  local bucket = GetPlayerRoutingBucket(tostring(src))
  local inside = GetVehiclePedIsIn(ped, false)
  local found, plates, seen = {}, {}, {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and GetEntityRoutingBucket(entity) == bucket then
      local dist = entity == inside and 0.0 or #(GetEntityCoords(entity) - origin)
      if dist <= range then
        local plate = identityOf(entity)
        if plate and not seen[plate] then
          seen[plate] = true
          found[#found + 1] = { entity = entity, plate = plate, dist = dist }
          plates[#plates + 1] = plate
        end
      end
    end
  end
  if #plates == 0 then return {} end
  local okRows, rows = pcall(NZ.DB.getVehiclesByPlates, plates)
  local byPlate = {}
  for _, row in ipairs(okRows and type(rows) == 'table' and rows or {}) do
    if type(row) == 'table' and row.plate then byPlate[row.plate] = row end
  end
  local out = {}
  for _, entry in ipairs(found) do
    local row = byPlate[entry.plate]
    if row and row.owner == identifier then
      out[#out + 1] = { entity = entry.entity, row = row, dist = entry.dist }
    end
  end
  table.sort(out, function(a, b) return a.dist < b.dist end)
  while #out > MAX_VEHICLES do out[#out] = nil end
  return out
end

--- The entity of `plate` nearest to `src` within `range` (same routing bucket), or nil.
local function vehicleNear(src, plate, range)
  local ped = pedOf(src)
  if not ped then return nil end
  local origin = GetEntityCoords(ped)
  local bucket = GetPlayerRoutingBucket(tostring(src))
  local inside = GetVehiclePedIsIn(ped, false)
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and GetEntityRoutingBucket(entity) == bucket and identityOf(entity) == plate then
      local dist = entity == inside and 0.0 or #(GetEntityCoords(entity) - origin)
      if dist < bestDist then best, bestDist = entity, dist end
    end
  end
  if best and bestDist <= range then return best, bestDist end
  return nil
end

--- ContractVehicle for the interface (labels are added by the client from `hash`).
local function vehicleView(row, entity, dist, blocked)
  local hash = rowHash(row) or (isVehicle(entity) and toSigned(GetEntityModel(entity))) or 0
  local engine, body = nil, nil
  if isVehicle(entity) then
    engine = percent((tonumber(GetVehicleEngineHealth(entity)) or 1000) / 10)
    body = percent((tonumber(GetVehicleBodyHealth(entity)) or 1000) / 10)
  end
  local nickname = type(row.nickname) == 'string' and row.nickname ~= '' and cleanName(row.nickname) or nil
  return {
    plate = row.plate,
    model = type(row.model) == 'string' and row.model:sub(1, 32) or '',
    hash = hash,
    vehicleType = vehicleTypeOf(row),
    nickname = nickname,
    mileage = mileageOf(row, entity),
    engine = engine or percent(row.engine) or 100,
    body = body or percent(row.body) or 100,
    distance = dist and Utils.round(dist, 1) or nil,
    blocked = blocked,
  }
end

--- Players near the seller who can sign: { { serverId, name } }, nearest first.
local function nearbyBuyers(src, identifier, range)
  local list = {}
  for _, id in ipairs(GetPlayers() or {}) do
    local other = validSrc(id)
    if other and other ~= src and playersClose(src, other, range) then
      local otherId = identifierOf(other)
      if otherId and otherId ~= identifier then
        list[#list + 1] = { serverId = other, name = nameOf(other), dist = #(posOf(other) - posOf(src)) }
      end
    end
  end
  table.sort(list, function(a, b) return a.dist < b.dist end)
  local out = {}
  for i = 1, math.min(#list, MAX_BUYERS) do out[i] = { serverId = list[i].serverId, name = list[i].name } end
  return out
end

---------------------------------------------------------------------------------------
-- Contracts: lookup, outcome, clean-up
---------------------------------------------------------------------------------------

local function pendingWhere(fn)
  for id, c in pairs(contracts) do
    if fn(c) then return id, c end
  end
  return nil
end

--- Tell one party about the outcome: status for its open window + a notification.
local function tellStatus(target, c, status)
  if validSrc(target) then
    TriggerClientEvent('nz:client:contract:status', target, { contractId = c.id, status = status })
  end
end

--- End a contract that was not signed: status + notifications for both parties.
--- status: 'declined' | 'expired' | 'withdrawn' | 'cancelled' | 'failed'
local function finish(c, status, actor, messages)
  if contracts[c.id] ~= c then return end
  contracts[c.id] = nil
  c.state = status
  tellStatus(c.seller, c, status)
  tellStatus(c.buyer, c, status)
  if messages then
    if messages.seller then notify(c.seller, messages.kind or 'info', messages.seller) end
    if messages.buyer then notify(c.buyer, messages.kind or 'info', messages.buyer) end
  end
  log('vehicle.contract', actor, {
    action = status, contractId = c.id, plate = c.plate, price = c.price,
    seller = c.sellerIdentifier, buyer = c.buyerIdentifier,
  })
end

local function expire(c)
  if contracts[c.id] ~= c or c.state ~= 'pending' then return end
  finish(c, 'expired', nil, {
    seller = L('Your contract for {plate} expired before {name} signed it', { plate = c.plate, name = c.buyerName }),
    buyer = L('The contract for {plate} expired', { plate = c.plate }),
  })
end

--- Cancel every pending contract of a player who left (or switched character).
---@param src number
function Contracts.onPlayerDropped(src)
  drafts[src] = nil
  for _, c in pairs(contracts) do
    if c.state == 'pending' and (c.seller == src or c.buyer == src) then
      local sellerLeft = c.seller == src
      finish(c, 'cancelled', nil, sellerLeft and {
        buyer = L('{name} left: the contract for {plate} is void', { name = c.sellerName, plate = c.plate }),
      } or {
        seller = L('{name} left: the contract for {plate} is void', { name = c.buyerName, plate = c.plate }),
      })
    end
  end
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then Contracts.onPlayerDropped(math.tointeger(src) or src) end
end)

AddEventHandler('nz:server:playerUnloaded', function(src)
  src = tonumber(src)
  if src then Contracts.onPlayerDropped(math.tointeger(src) or src) end
end)

---------------------------------------------------------------------------------------
-- Draft (blank contract item)
---------------------------------------------------------------------------------------

local function draftOf(src, identifier)
  local d = drafts[src]
  if not d or d.identifier ~= identifier or os.time() - d.at > DRAFT_SECONDS then return nil end
  return d
end

local function draftLists(src, identifier, c)
  local vehicles = {}
  for _, entry in ipairs(nearbyOwned(src, identifier, c.maxDistance)) do
    vehicles[#vehicles + 1] = vehicleView(entry.row, entry.entity, entry.dist, blockReason(entry.row, entry.entity, nil))
  end
  return vehicles, nearbyBuyers(src, identifier, c.maxDistance)
end

local function openDraft(src, slot)
  local c = cfg()
  local identifier = identifierOf(src)
  if not identifier then
    notify(src, 'error', L('Your character is not loaded'))
    return true
  end
  local _, pending = pendingWhere(function(x) return x.seller == src end)
  if pending then
    notify(src, 'info', L('Your contract for {plate} is still waiting for {name}', { plate = pending.plate, name = pending.buyerName }))
    return true
  end
  if pendingWhere(function(x) return x.buyer == src end) then
    notify(src, 'info', L('Answer the contract you received first'))
    return true
  end
  local vehicles, buyers = draftLists(src, identifier, c)
  if #vehicles == 0 then
    notify(src, 'error', L('None of your vehicles is nearby: stand next to the vehicle you want to sell'))
    return true
  end
  drafts[src] = { identifier = identifier, slot = tonumber(slot), at = os.time() }
  TriggerClientEvent('nz:client:contract:open', src, {
    mode = 'draft',
    seller = { name = nameOf(src), serverId = src },
    vehicles = vehicles,
    buyers = buyers,
    maxPrice = c.maxPrice,
    account = c.account,
    expireSeconds = c.expireSeconds,
  })
  return true
end

---------------------------------------------------------------------------------------
-- Signed copies (view mode)
---------------------------------------------------------------------------------------

local function dateOf(ts)
  local okD, text = pcall(os.date, '%Y-%m-%d', math.floor(tonumber(ts) or os.time()))
  return okD and text or ''
end

local function copyMetadata(c, role)
  local v = c.vehicle
  local modelName = (v.model ~= '' and (v.model:sub(1, 1):upper() .. v.model:sub(2))) or c.plate
  return {
    contractId = c.id,
    copy = role,
    plate = c.plate,
    model = v.model,
    hash = v.hash,
    vehicleType = v.vehicleType,
    nickname = v.nickname,
    mileage = v.mileage,
    engine = v.engine,
    body = v.body,
    seller = c.sellerName,
    buyer = c.buyerName,
    price = c.price,
    account = c.account,
    terms = c.terms,
    createdAt = c.createdAt,
    signedAt = c.signedAt,
    sellerSignature = c.sellerSignature,
    buyerSignature = c.buyerSignature,
    label = L('Sale contract · {plate}', { plate = c.plate }),
    description = L('{model} · {seller} to {buyer} · {amount} · {date}', {
      model = modelName, seller = c.sellerName, buyer = c.buyerName,
      amount = money(c.price), date = dateOf(c.signedAt),
    }),
    display = false, -- qb-inventory: show the description only
  }
end

--- Was this contract recorded in the ownership history of its plate?
local function verifyCopy(contractId, plate, price)
  local okList, list = pcall(NZ.DB.events.list, plate, 'owner', HISTORY_LOOKUP)
  if not okList or type(list) ~= 'table' then return false end
  for _, entry in ipairs(list) do
    local data = type(entry) == 'table' and entry.data or nil
    if type(data) == 'table' and data.via == 'contract' and data.contractId == contractId then
      return math.floor(tonumber(data.price) or -1) == price
    end
  end
  return false
end

--- Read-only view of a signed copy. Every field is cleaned again (metadata can be edited
--- through some inventories); nil when it is not a contract at all.
local function viewOf(md)
  if type(md) ~= 'table' then return nil end
  local plate = Utils.plate(md.plate)
  local contractId = readId(md.contractId)
  if not plate or #plate > 16 or not contractId then return nil end
  local price = math.floor(tonumber(md.price) or -1)
  if price < 0 or price > 2000000000 then return nil end
  local hash = toSigned(md.hash) or 0
  local vtype = (md.vehicleType == 'sea' or md.vehicleType == 'air') and md.vehicleType or 'car'
  return {
    mode = 'view',
    contractId = contractId,
    copy = (md.copy == 'seller' or md.copy == 'buyer') and md.copy or nil,
    vehicle = {
      plate = plate,
      model = type(md.model) == 'string' and md.model:sub(1, 32):gsub('[^%w_%-]', '') or '',
      hash = hash,
      vehicleType = vtype,
      nickname = cleanName(md.nickname),
      mileage = Utils.round(math.max(0, num(md.mileage, 0, 10000000, 0)), 1),
      engine = percent(md.engine) or 100,
      body = percent(md.body) or 100,
    },
    seller = { name = cleanName(md.seller) or L('Unknown') },
    buyer = { name = cleanName(md.buyer) or L('Unknown') },
    price = price,
    account = md.account == 'cash' and 'cash' or 'bank',
    terms = cleanTerms(type(md.terms) == 'string' and md.terms or '') or '',
    createdAt = math.floor(num(md.createdAt, 0, 4102444800, 0)),
    signedAt = math.floor(num(md.signedAt, 0, 4102444800, 0)),
    sellerSignature = cleanSignature(md.sellerSignature) or '',
    buyerSignature = cleanSignature(md.buyerSignature) or '',
    verified = verifyCopy(contractId, plate, price),
  }
end

local function openCopy(src, metadata)
  local view = viewOf(metadata)
  if not view then
    notify(src, 'error', L('This contract is blank or unreadable'))
    return true
  end
  TriggerClientEvent('nz:client:contract:open', src, view)
  return true
end

--- Usable item handler (bridge/server/listeners.lua): a blank contract opens a draft, a
--- signed copy opens its read-only view. Items are never consumed here.
---@param src number
---@param _ string item name
---@param slot number|nil
---@param metadata table|nil
---@param key string 'contract' | 'signedContract'
---@return boolean handled
function Contracts.useItem(src, _, slot, metadata, key)
  src = validSrc(src)
  if not src then return false end
  if limited(src, 'use') then return true end
  if key == 'signedContract' then return openCopy(src, metadata) end
  if not cfg().enabled then
    notify(src, 'error', L('Sale contracts are disabled'))
    return true
  end
  if incapacitated(src) then
    notify(src, 'error', L('You cannot do that right now'))
    return true
  end
  return openDraft(src, slot)
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(src, payload)
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    src = validSrc(src)
    if not src then return fail(L('Invalid request')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

local function readPrice(value, max)
  local n = tonumber(value)
  if not n or n ~= n or n ~= math.floor(n) or n < 1 or n > max then return nil end
  return math.tointeger(n) or math.floor(n)
end

local function hasBlank(src)
  local okHas, has = pcall(NZ.Inventory.hasItem, src, itemName('contract'), 1)
  return okHas and has == true
end

-- {} -> { vehicles, buyers } (draft window: look around again)
register('nz:contract:refresh', function(src)
  if limited(src, 'refresh') then return fail(L('Please wait a moment before trying again')) end
  local identifier = identifierOf(src)
  if not identifier or not draftOf(src, identifier) then return fail(L('Use a blank contract first')) end
  local vehicles, buyers = draftLists(src, identifier, cfg())
  return ok({ vehicles = vehicles, buyers = buyers })
end)

-- { plate, buyer, price, terms, signature } -> { contractId, expiresIn }
register('nz:contract:send', function(src, payload)
  local c = cfg()
  if not c.enabled then return fail(L('Sale contracts are disabled')) end
  if limited(src, 'send') then return fail(L('Please wait a moment before trying again')) end
  local identifier = identifierOf(src)
  if not identifier then return fail(L('Your character is not loaded')) end
  local draft = draftOf(src, identifier)
  if not draft then return fail(L('Use a blank contract first')) end
  if not hasBlank(src) then return fail(L('You need a blank contract')) end

  local plate = type(payload.plate) == 'string' and #payload.plate <= 16 and Utils.plate(payload.plate) or nil
  if not plate then return fail(L('Choose a vehicle')) end
  local price = readPrice(payload.price, c.maxPrice)
  if not price then
    return fail(L('Enter a price between {min} and {max}', { min = money(1), max = money(c.maxPrice) }))
  end
  local terms = cleanTerms(payload.terms)
  if not terms then return fail(L('The terms are too long')) end
  local signature = cleanSignature(payload.signature)
  if not signature then return fail(L('Sign the contract first')) end

  local buyer = validSrc(payload.buyer)
  if not buyer or buyer == src then return fail(L('Choose a buyer')) end
  local buyerId = identifierOf(buyer)
  if not buyerId then return fail(L('That player is not available')) end
  if buyerId == identifier then return fail(L('You cannot sell a vehicle to yourself')) end
  if not playersClose(src, buyer, c.maxDistance) then return fail(L('The buyer must be standing next to you')) end

  if pendingWhere(function(x) return x.seller == src end) then
    return fail(L('You already have a contract waiting for a signature'))
  end
  if pendingWhere(function(x) return x.buyer == src end) then
    return fail(L('Answer the contract you received first'))
  end
  if pendingWhere(function(x) return x.plate == plate end) then
    return fail(L('A contract for this vehicle is already pending'))
  end
  if pendingWhere(function(x) return x.buyer == buyer or x.seller == buyer end) then
    return fail(L('That player already has a contract to sign'))
  end

  local entity, dist = vehicleNear(src, plate, c.maxDistance)
  if not entity then return fail(L('The vehicle must be next to you')) end
  local row = NZ.DB.getVehicle(plate)
  if not row or row.owner ~= identifier then return fail(L('You do not own this vehicle')) end
  local buyerInfo = { source = buyer, identifier = buyerId, name = nameOf(buyer) }
  local blocked = blockReason(row, entity, buyerInfo)
  if blocked then return fail(blocked) end

  local id = newId()
  if not id then return fail(L('Something went wrong')) end
  local now = os.time()
  local contract = {
    id = id,
    state = 'pending',
    seller = src, sellerIdentifier = identifier, sellerName = nameOf(src),
    buyer = buyer, buyerIdentifier = buyerId, buyerName = buyerInfo.name,
    plate = plate,
    vehicle = vehicleView(row, entity, nil, nil),
    price = price,
    account = c.account,
    terms = terms,
    sellerSignature = signature,
    createdAt = now,
    expiresAt = now + c.expireSeconds,
    slot = draft.slot,
  }
  contracts[id] = contract
  SetTimeout(c.expireSeconds * 1000 + 250, function() expire(contract) end)

  local okMoney, balance = pcall(NZ.Bridge.getMoney, buyer, c.account)
  TriggerClientEvent('nz:client:contract:open', buyer, {
    mode = 'review',
    contractId = id,
    vehicle = contract.vehicle,
    seller = { name = contract.sellerName, serverId = src },
    buyer = { name = contract.buyerName, serverId = buyer },
    price = price,
    terms = terms,
    sellerSignature = signature,
    createdAt = now,
    expiresIn = c.expireSeconds,
    canAfford = okMoney and (tonumber(balance) or 0) >= price,
    account = c.account,
  })
  notify(buyer, 'info', L('{name} wants to sell you {plate} for {amount}', {
    name = contract.sellerName, plate = plate, amount = money(price),
  }))
  log('vehicle.contract', src, {
    action = 'offer', contractId = id, plate = plate, price = price, account = c.account,
    buyer = buyerId, buyerName = buyerInfo.name, distance = dist and Utils.round(dist, 1) or nil,
  })
  return ok({ contractId = id, expiresIn = c.expireSeconds })
end)

--- Physical key item for the buyer (temporary key when the inventory refuses it), or the key
--- of the external key resource when the built-in car lock is off.
local function giveBuyerKey(buyer, plate, row, entity)
  local carLock = NZ.CarLock
  local okOn, on = pcall(carLock.enabled)
  if okOn and on == true then
    local okMode, mode = pcall(carLock.mode)
    if okMode and mode == 'physical' then
      local okGive, given = pcall(carLock.giveKeyItem, buyer, plate, { model = row.model, reason = 'contract' })
      if okGive and given then return 'item' end
      notify(buyer, 'warning', L('You cannot carry the key: you got a temporary key instead'))
    end
    pcall(carLock.grantTemp, buyer, plate, 'contract')
    return 'temp'
  end
  if NZ.KeysServer and type(NZ.KeysServer.give) == 'function' and isVehicle(entity) then
    pcall(NZ.KeysServer.give, buyer, NetworkGetNetworkIdFromEntity(entity), plate)
    return 'external'
  end
  return nil
end

local function giveCopies(c)
  if not cfg().signedCopies then return end
  local okMeta, meta = pcall(NZ.Inventory.supportsMetadata)
  if not okMeta or meta ~= true then return end
  local item = itemName('signedContract')
  for _, party in ipairs({ { c.seller, 'seller' }, { c.buyer, 'buyer' } }) do
    local target, role = party[1], party[2]
    if validSrc(target) then
      local okAdd, added = pcall(NZ.Inventory.addItem, target, item, 1, copyMetadata(c, role))
      if not okAdd or not added then
        notify(target, 'warning', L('You cannot carry your copy of the contract'))
      end
    end
  end
end

--- Consume the blank contract the seller used (that slot when it still holds one).
local function takeBlank(c)
  local item = itemName('contract')
  if c.slot then
    local okSlot, removed = pcall(NZ.Inventory.removeItem, c.seller, item, 1, nil, c.slot)
    if okSlot and removed then return true end
  end
  local okAny, removed = pcall(NZ.Inventory.removeItem, c.seller, item, 1)
  return okAny and removed == true
end

local function giveBlankBack(c)
  local okAdd, added = pcall(NZ.Inventory.addItem, c.seller, itemName('contract'), 1)
  if not okAdd or not added then
    log('security.contract', c.seller, { contractId = c.id, plate = c.plate, reason = 'blank contract could not be given back' })
  end
end

--- The sale itself (inside NZ.Vehicles.withLock(plate)). Returns a callback result.
local function complete(c, signature)
  local cf = cfg()
  local function void(sellerMsg, buyerMsg)
    finish(c, 'failed', c.buyer, {
      kind = 'error', seller = sellerMsg or L('The sale of {plate} failed', { plate = c.plate }),
    })
    return fail(buyerMsg)
  end

  if not cf.enabled then return void(nil, L('Sale contracts are disabled')) end
  if not validSrc(c.seller) or identifierOf(c.seller) ~= c.sellerIdentifier then
    return void(nil, L('The seller is no longer available'))
  end
  if identifierOf(c.buyer) ~= c.buyerIdentifier then return void(nil, L('This contract is no longer valid')) end
  if not playersClose(c.seller, c.buyer, cf.maxDistance) then
    return void(L('{name} was too far away to sign the contract for {plate}', { name = c.buyerName, plate = c.plate }),
      L('Stand next to the seller to sign'))
  end
  local entity = vehicleNear(c.seller, c.plate, cf.maxDistance)
  if not entity then
    return void(L('The sale of {plate} failed: the vehicle was not next to you', { plate = c.plate }),
      L('The vehicle is no longer here'))
  end
  local row = NZ.DB.getVehicle(c.plate)
  if not row or row.owner ~= c.sellerIdentifier then
    return void(L('The sale of {plate} failed: you no longer own it', { plate = c.plate }),
      L('The seller no longer owns this vehicle'))
  end
  local buyer = { source = c.buyer, identifier = c.buyerIdentifier, name = c.buyerName }
  local blocked = blockReason(row, entity, buyer)
  if blocked then
    return void(L('The sale of {plate} failed: {reason}', { plate = c.plate, reason = blocked }), blocked)
  end
  if incapacitated(c.buyer) or incapacitated(c.seller) then
    return void(nil, L('You cannot do that right now'))
  end

  if not takeBlank(c) then
    return void(L('The sale of {plate} failed: you no longer carry a blank contract', { plate = c.plate }),
      L('The seller no longer has a blank contract'))
  end

  local seller = { source = c.seller, identifier = c.sellerIdentifier, name = c.sellerName }
  local signedAt = os.time()
  local sold, err, code = NZ.Actions.sellVehicle(row, seller, buyer, {
    via = 'contract', price = c.price, account = c.account, payAccount = c.account,
    history = { contractId = c.id, from = c.sellerIdentifier, fromName = c.sellerName },
  })
  if not sold then
    giveBlankBack(c)
    if code == 'afford' then
      return void(L('{name} could not afford {plate}', { name = c.buyerName, plate = c.plate }), err)
    end
    return void(L('The sale of {plate} failed', { plate = c.plate }), err)
  end

  contracts[c.id] = nil
  c.state = 'signed'
  c.signedAt = signedAt
  c.buyerSignature = signature
  local keyKind = giveBuyerKey(c.buyer, c.plate, row, entity)
  giveCopies(c)
  tellStatus(c.seller, c, 'signed')
  notify(c.seller, 'success', L('You sold {plate} to {name} for {amount}', {
    plate = c.plate, name = c.buyerName, amount = money(c.price),
  }))
  notify(c.buyer, 'success', L('You bought {plate} for {amount}', { plate = c.plate, amount = money(c.price) }))
  log('vehicle.sell', c.buyer, {
    plate = c.plate, action = 'contract', contractId = c.id, price = c.price, account = c.account,
    seller = c.sellerIdentifier, sellerName = c.sellerName, buyer = c.buyerIdentifier, buyerName = c.buyerName,
    key = keyKind,
  })
  return ok({ signedAt = signedAt })
end

-- { contractId, signature } -> { signedAt } (buyer; one attempt per contract)
register('nz:contract:sign', function(src, payload)
  if limited(src, 'sign') then return fail(L('Please wait a moment before trying again')) end
  local id = readId(payload.contractId)
  local c = id and contracts[id] or nil
  if not c or c.buyer ~= src then return fail(L('This contract is no longer valid')) end
  if c.state ~= 'pending' then return fail(L('This contract is no longer valid')) end
  if os.time() > c.expiresAt then
    expire(c)
    return fail(L('This contract has expired'))
  end
  local signature = cleanSignature(payload.signature)
  if not signature then return fail(L('Sign the contract first')) end

  -- from here on the contract is used up, whatever happens
  c.state = 'signing'
  local okRun, result = pcall(NZ.Vehicles.withLock, c.plate, complete, c, signature)
  if contracts[id] == c then
    -- the plate was busy (another operation on this vehicle) or an error: the attempt is over
    finish(c, 'failed', src, { kind = 'error', seller = L('The sale of {plate} failed', { plate = c.plate }) })
  end
  if not okRun then error(result, 0) end
  return result
end)

-- { contractId } -> null (the buyer declines, the seller withdraws)
register('nz:contract:decline', function(src, payload)
  if limited(src, 'decline') then return fail(L('Please wait a moment before trying again')) end
  local id = readId(payload.contractId)
  local c = id and contracts[id] or nil
  if not c or (c.buyer ~= src and c.seller ~= src) then return fail(L('This contract is no longer valid')) end
  if c.state ~= 'pending' then return fail(L('This contract is being signed')) end
  if c.buyer == src then
    finish(c, 'declined', src, {
      seller = L('{name} declined your contract for {plate}', { name = c.buyerName, plate = c.plate }),
    })
  else
    finish(c, 'withdrawn', src, {
      buyer = L('{name} withdrew the contract for {plate}', { name = c.sellerName, plate = c.plate }),
    })
  end
  return ok(nil)
end)

--- Pending contracts (diagnostics / other scripts): { { id, plate, seller, buyer, price, expiresAt, state } }.
---@return table[]
function Contracts.pending()
  local out = {}
  for _, c in pairs(contracts) do
    out[#out + 1] = { id = c.id, plate = c.plate, seller = c.seller, buyer = c.buyer, price = c.price,
      expiresAt = c.expiresAt, state = c.state }
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
