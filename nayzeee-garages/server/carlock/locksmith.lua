--[[
  nayzeee-garages — car lock: locksmith services (server, NZ.CarLock). docs/CARLOCK.md §9.

  Locations: Config.CarLock.locksmiths (the list index is the id). The player must stand at
  the counter (SERVER ped position within COUNTER_RANGE of the location, in the location's
  routing bucket: `bucket`, default 0); vehicles count as "nearby" when they are within the
  location's `range` (default 25 m) of the locksmith in the player's routing bucket. Vehicles
  on the impound tow truck (NZ.Tow.isTowing) are refused.

  Services (per location: enabled, price paid from Config.CarLock.locksmithAccount, materials
  taken through NZ.Inventory):
    duplicate  physical mode only: a copy of a key item, cut for the current key version.
               Legal: you carry a valid key item of that plate, or you own the vehicle (papers).
               Illegal: you carry a valid key item. Virtual mode: not offered (owners give
               virtual keys from the key ring). A copy keeps the origin of the key it copies.
    program    a new key for a vehicle parked nearby. Legal: the owner, or a holder of a real
               key (a key item without a crime origin, or a virtual key the owner gave). A
               temporary key (hotwired, robbed...), a crime's key item (back-alley copy, spare
               key found in a search) and the access of a garage share / job or gang fleet never
               make a registered key. Illegal: any vehicle nearby. Physical mode: a key / fob
               item; virtual mode: a temporary key (Config.CarLock.tempKeyHours), at an illegal
               shop only (a legal shop does not offer it: owners give keys from the key ring).
    rekey      change of locks of a vehicle parked nearby (NZ.CarLock.rekey: every other key
               stops working, virtual and temporary keys of others are removed). OWNER ONLY, at
               every location (an illegal shop never locks an owner out of their vehicle).
               Physical mode: a new key item, the old key items of that plate the owner carries
               are taken back.
  Keys of an illegal shop are a crime's keys: key items carry metadata.origin = 'locksmith'
  (players cannot edit item metadata; it is not part of the signature), temporary keys the
  reason 'locksmith'. They open the vehicle like any key but give no tracker access and no
  owner's nickname (NZ.CarLock.isServiceKey, server/carlock/tracker.lua) unless the holder
  owns the vehicle.
  Illegal locations: each service has the location's alertChance (%) of a police alert through
  NZ.Dispatch.alert (when the dispatch integration provides it). The alert names the plate the
  vehicle WEARS (a fake plate stays fake for the police, docs/CARLOCK.md §13); a duplicate of a
  key whose vehicle is not there names no plate. Strangers' vehicles never show the owner's
  nickname.

  A service: validate everything -> money and materials checked -> materials taken -> money
  taken -> the service -> on any failure the money and materials are given back.

  Callbacks (lib.callback, { ok, data, error }):
    nz:carlock:locksmith:open    { id }                   -> LocksmithOpenData
    nz:carlock:locksmith:service { id, service, plate }   -> { message, data = LocksmithOpenData }
  LocksmithOpenData = { id, name, illegal, account, mode, money, tempHours, range,
    services = { { id, enabled, offered, reason?, price, materials = { { item, label, count, have } } } },
    vehicles = { { plate, model?, hash?, vehicleType, nickname?, isOwner, hasKey, keyKind?, keyItems,
                   unregistered (every key item carried is a crime's), keyType, nearby, distance?,
                   towing, blocked = { duplicate?, program?, rekey? } } } }
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local COUNTER_RANGE = 5.0       -- m: the player stands at the locksmith (server ped position)
local DEFAULT_RANGE = 25.0      -- m: vehicles this close to the locksmith count as nearby
local MAX_NEARBY = 12           -- nearby vehicles listed (closest first)
local MAX_LISTED = 48           -- vehicles listed in total
local SERVICES = { 'duplicate', 'program', 'rekey' }
local SERVICE_SET = { duplicate = true, program = true, rekey = true }
local RATE = { open = 800, service = 1500 }

local busy = {}                 -- [src] = true while a service runs

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function cfg() return CarLock.cfg() end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

local function normPlate(plate)
  if type(plate) ~= 'string' or #plate > 16 then return nil end
  return Utils.plate(plate)
end

local function limited(src, bucket)
  return not NZ.Access.rateLimit(src, 'carlock:locksmith:' .. bucket, RATE[bucket] or 1000)
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, id = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function pedOf(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return ped
end

local function towing(entity)
  if type(NZ.Tow.isTowing) ~= 'function' then return false end
  local ok, res = pcall(NZ.Tow.isTowing, entity)
  return ok and res == true
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  pcall(NZ.Logs.add, event, src, data)
end

local function account()
  local a = cfg().locksmithAccount
  return (a == 'bank') and 'bank' or 'cash'
end

local function hashOf(model)
  if type(model) == 'number' then return math.tointeger(model) or model end
  if type(model) ~= 'string' or model == '' then return nil end
  return joaat(model:lower())
end

--- Location `id` of Config.CarLock.locksmiths: loc, coords {x,y,z,w}, id.
local function locationOf(id)
  id = tonumber(id)
  if not id or id ~= math.floor(id) or id < 1 then return nil end
  id = math.tointeger(id)
  local list = cfg().locksmiths
  local loc = type(list) == 'table' and list[id] or nil
  if type(loc) ~= 'table' then return nil end
  local c = Utils.v4(loc.coords)
  if not c then return nil end
  return loc, c, id
end

local function centerOf(c) return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) end

local function rangeOf(loc)
  return Utils.clamp(tonumber(loc.range) or DEFAULT_RANGE, 5.0, 100.0)
end

--- Is the player at the counter (server ped position, in the location's routing bucket)?
local function atCounter(src, c, loc)
  local ped = pedOf(src)
  if not ped then return false end
  if GetPlayerRoutingBucket(tostring(src)) ~= (math.tointeger(tonumber(loc.bucket)) or 0) then return false end
  return #(GetEntityCoords(ped) - centerOf(c)) <= COUNTER_RANGE
end

local function vehicleTypeOfEntity(entity)
  local ok, vtype = pcall(GetVehicleType, entity)
  if ok and (vtype == 'heli' or vtype == 'plane' or vtype == 'blimp') then return 'air' end
  if ok and (vtype == 'boat' or vtype == 'submarine') then return 'sea' end
  return 'car'
end

local function vehicleTypeOfRow(row)
  if type(NZ.Vehicles.vehicleTypeOf) == 'function' then
    local ok, vtype = pcall(NZ.Vehicles.vehicleTypeOf, row)
    if ok and (vtype == 'car' or vtype == 'sea' or vtype == 'air') then return vtype end
  end
  local vtype = row.vehicleType
  return (vtype == 'sea' or vtype == 'air') and vtype or 'car'
end

---------------------------------------------------------------------------------------
-- Services: price and materials
---------------------------------------------------------------------------------------

local ITEM_LABELS = { blank = 'Key blank', key = 'Vehicle key', fob = 'Key fob', lockpick = 'Lockpick',
  advancedLockpick = 'Advanced lockpick', screwdriver = 'Screwdriver', hackingDevice = 'Hacking device' }

local function serviceCfg(loc, service)
  local list = type(loc.services) == 'table' and loc.services or {}
  local s = list[service]
  return type(s) == 'table' and s or nil
end

local function enabled(loc, service)
  local s = serviceCfg(loc, service)
  return s ~= nil and s.enabled ~= false
end

local function priceOf(loc, service)
  local s = serviceCfg(loc, service)
  return math.tointeger(Utils.clamp(math.floor(tonumber(s and s.price) or 0), 0, 100000000)) or 0
end

--- Label of a material: its config label, a known item label, else the item name made readable.
local function materialLabel(entry, key, item)
  if type(entry.label) == 'string' and entry.label ~= '' then return L(entry.label) end
  if ITEM_LABELS[key] then return L(ITEM_LABELS[key]) end
  local text = tostring(item):gsub('[_%-]+', ' ')
  return text:sub(1, 1):upper() .. text:sub(2)
end

--- Materials of a service: { { item, label, count, have } } (have = what the player carries).
local function materialsOf(src, loc, service)
  local out = {}
  local s = serviceCfg(loc, service)
  for _, entry in ipairs(type(s) == 'table' and type(s.materials) == 'table' and s.materials or {}) do
    if type(entry) == 'table' and type(entry.item) == 'string' and entry.item ~= '' then
      local item = CarLock.itemName(entry.item)
      local count = math.tointeger(Utils.clamp(math.floor(tonumber(entry.count) or 1), 1, 100)) or 1
      local have = 0
      if src then
        local ok, n = pcall(NZ.Inventory.count, src, item)
        have = ok and math.tointeger(math.floor(tonumber(n) or 0)) or 0
      end
      out[#out + 1] = { item = item, label = materialLabel(entry, entry.item, item), count = count, have = have }
    end
  end
  return out
end

local function moneyOf(src)
  local ok, n = pcall(NZ.Bridge.getMoney, src, account())
  return ok and math.floor(tonumber(n) or 0) or 0
end

---------------------------------------------------------------------------------------
-- Vehicles
---------------------------------------------------------------------------------------

--- Nearest vehicle with `plate` near the locksmith in the player's bucket: entity, distance.
local function nearbyEntity(src, plate, loc, c)
  local entity = CarLock.findVehicle(plate, src)
  if not entity then return nil, nil end
  local dist = #(GetEntityCoords(entity) - centerOf(c))
  return entity, dist
end

--- Reason a service is not available for a vehicle (translated), nil when it is.
local function blockOf(loc, service, v, mode)
  if not enabled(loc, service) then return L('Not offered here') end
  local illegal = loc.illegal == true
  -- virtual mode: owners give keys from the key ring, a legal shop programs none
  if service == 'program' and mode == 'virtual' and not illegal then return L('Owners give keys from the key ring') end
  if v.towing then return L('This vehicle is being towed') end
  if service == 'duplicate' then
    if mode ~= 'physical' then return L('Give virtual keys from your key ring') end
    if v.keyItems > 0 then return nil end
    if not illegal and v.isOwner then return nil end
    return illegal and L('Bring a key of this vehicle to copy') or L('Bring a key or the papers of this vehicle')
  end
  -- program / rekey work on the vehicle itself
  if not v.nearby then return L('Park the vehicle near the locksmith') end
  if v.otherDriver and not v.isOwner then return L('Someone else is driving this vehicle') end
  if service == 'program' then
    if mode == 'virtual' and v.hasKey and v.keyKind ~= 'temp' then return L('You already have a key for this vehicle') end
    if illegal or v.isOwner then return nil end
    -- a real key only: a key item you carry that is not a crime's, or a virtual key the owner
    -- gave you. A temporary key, a back-alley / found key item or the 'owner' access of a
    -- garage share / fleet must never turn into a registered key.
    if (v.keyItems > 0 and not v.unregistered) or v.keyKind == 'virtual' then return nil end
    if v.unregistered then return L('An unregistered key is not enough: only the owner or a key holder') end
    if v.keyKind == 'temp' then return L('A temporary key is not enough: only the owner or a key holder') end
    if v.keyKind == 'owner' then return L('Garage or job access is not enough: only the owner or a key holder') end
    return L('Only the owner or a key holder can order a key')
  end
  if service == 'rekey' then
    -- owner only, legal or not: new locks lock everybody else out for good
    if v.isOwner then return nil end
    return L('Only the owner can change the locks')
  end
  return L('Invalid request')
end

--- Everything the locksmith shows about one vehicle. entity / dist: known nearby vehicle.
local function vehicleInfo(src, ctx, plate, entity, dist, keyKind)
  local row = CarLock.vehicleRow(plate)
  local has, kind = keyKind ~= nil, keyKind
  if keyKind == nil then has, kind = CarLock.hasKey(src, plate) end
  local _, profile
  if entity then
    _, profile = CarLock.profileOfEntity(entity)
  elseif row then
    _, profile = CarLock.profileOf(row.hash or row.model, nil)
  else
    _, profile = CarLock.profile('standard')
  end
  local nearby = entity ~= nil and dist ~= nil and dist <= ctx.range
  local driver = entity and GetPedInVehicleSeat(entity, -1) or 0
  local items = ctx.items[plate]
  local isOwner = row ~= nil and ctx.identifier ~= nil and row.owner == ctx.identifier
  -- a real key: the owner, a virtual key / garage share / fleet access, a key item without a
  -- crime origin (a temporary key or a back-alley copy is not one)
  local real = isOwner or (has == true and kind ~= 'temp' and kind ~= 'item') or (items ~= nil and items.real > 0)
  local v = {
    plate = plate,
    model = row and row.model or nil,
    hash = entity and GetEntityModel(entity) or (row and (tonumber(row.hash) or hashOf(row.model))) or nil,
    vehicleType = entity and vehicleTypeOfEntity(entity) or (row and vehicleTypeOfRow(row)) or 'car',
    -- the owner's private nickname: only for the owner and holders of a real key, never for a
    -- stranger's car parked at an illegal shop, a hotwired / robbed one or a back-alley copy
    nickname = real and row and type(row.nickname) == 'string' and row.nickname ~= '' and row.nickname or nil,
    isOwner = isOwner,
    owned = row ~= nil,
    hasKey = has == true,
    keyKind = has and kind or nil,
    keyItems = items and items.count or 0,
    unregistered = items ~= nil and items.count > 0 and items.real == 0,
    -- the crime origin a copy keeps (only when no key item carried is a real one)
    itemOrigin = items and items.origin or nil,
    keyType = (items and items.kind) or CarLock.keyKindOf(profile),
    nearby = nearby,
    distance = nearby and math.floor(dist + 0.5) or nil,
    towing = entity ~= nil and towing(entity),
    otherDriver = driver ~= 0 and driver ~= ctx.ped and IsPedAPlayer(driver) == true,
  }
  v.blocked = {}
  for _, service in ipairs(SERVICES) do v.blocked[service] = blockOf(ctx.loc, service, v, ctx.mode) end
  return v
end

local function newContext(src, loc, c)
  return {
    loc = loc, c = c, center = centerOf(c), range = rangeOf(loc), mode = CarLock.mode(),
    identifier = identifierOf(src), ped = pedOf(src), items = CarLock.keyItemSummary(src),
    bucket = GetPlayerRoutingBucket(tostring(src)),
  }
end

--- Vehicles the locksmith offers: nearby first (closest), then the player's keys and owned
--- vehicles (garaged ones too: a duplicate needs no vehicle).
local function vehicleList(src, ctx)
  local list, seen = {}, {}
  local function add(v)
    if #list < MAX_LISTED and not seen[v.plate] then
      seen[v.plate] = true
      list[#list + 1] = v
    end
  end

  local near = {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and GetEntityRoutingBucket(entity) == ctx.bucket then
      local dist = #(GetEntityCoords(entity) - ctx.center)
      if dist <= ctx.range then near[#near + 1] = { entity = entity, dist = dist } end
    end
  end
  table.sort(near, function(a, b) return a.dist < b.dist end)
  local kept = 0
  for _, n in ipairs(near) do
    if kept >= MAX_NEARBY then break end
    local plate = CarLock.realPlate(n.entity)
    if plate and not seen[plate] then
      local v = vehicleInfo(src, ctx, plate, n.entity, n.dist)
      -- a legal locksmith only deals with your own vehicles and the ones you have a key for
      if ctx.loc.illegal == true or v.hasKey or v.isOwner or v.keyItems > 0 then
        kept = kept + 1
        add(v)
      end
    end
  end

  for _, key in ipairs(CarLock.keysOf(src)) do
    local plate = normPlate(key.plate)
    if plate and not seen[plate] then add(vehicleInfo(src, ctx, plate, nil, nil, key.kind)) end
  end
  if ctx.identifier then
    local ok, rows = pcall(NZ.DB.getVehiclesByOwner, ctx.identifier)
    for _, row in ipairs(ok and type(rows) == 'table' and rows or {}) do
      local plate = normPlate(row.plate)
      if plate and not seen[plate] then add(vehicleInfo(src, ctx, plate, nil, nil)) end
    end
  end
  for _, v in ipairs(list) do v.otherDriver, v.itemOrigin = nil, nil end
  return list
end

--- LocksmithOpenData for a player at location `id`.
local function openData(src, loc, c, id)
  local ctx = newContext(src, loc, c)
  local services = {}
  for _, service in ipairs(SERVICES) do
    local offered, reason = true, nil
    if service == 'duplicate' and ctx.mode ~= 'physical' then
      offered, reason = false, L('Give virtual keys from your key ring')
    elseif service == 'program' and ctx.mode == 'virtual' and loc.illegal ~= true then
      offered, reason = false, L('Owners give keys from the key ring')
    end
    services[#services + 1] = {
      id = service,
      enabled = enabled(loc, service),
      offered = offered,
      reason = reason,
      price = priceOf(loc, service),
      materials = materialsOf(src, loc, service),
    }
  end
  return {
    id = id,
    name = type(loc.name) == 'string' and loc.name or L('Locksmith'),
    illegal = loc.illegal == true,
    account = account(),
    mode = ctx.mode,
    money = moneyOf(src),
    tempHours = CarLock.tempHours(),
    range = ctx.range,
    services = services,
    vehicles = vehicleList(src, ctx),
  }
end

---------------------------------------------------------------------------------------
-- Performing a service
---------------------------------------------------------------------------------------

local function giveBack(src, taken)
  for _, m in ipairs(taken) do
    if not NZ.Inventory.addItem(src, m.item, m.count) then
      lib.print.warn(('[nayzeee-garages] locksmith: could not give %dx %s back to %s'):format(m.count, m.item, tostring(src)))
    end
  end
end

--- Take the materials (all or nothing). Returns the taken list or nil.
local function takeMaterials(src, materials)
  local taken = {}
  for _, m in ipairs(materials) do
    if not NZ.Inventory.removeItem(src, m.item, m.count) then
      giveBack(src, taken)
      return nil
    end
    taken[#taken + 1] = m
  end
  return taken
end

local function refund(src, price, taken, reason)
  if price > 0 and not NZ.Bridge.addMoney(src, account(), price, reason) then
    lib.print.warn(('[nayzeee-garages] locksmith: could not refund %d to %s'):format(price, tostring(src)))
  end
  giveBack(src, taken)
end

--- Optional police alert of an illegal locksmith (the dispatch integration may be absent).
--- entity: the vehicle when it is parked there. The police get the plate it WEARS (a fake
--- plate stays fake, docs/CARLOCK.md §13), never the real one behind it.
local function maybeAlert(src, loc, v, service, entity)
  if loc.illegal ~= true then return false end
  local chance = Utils.clamp(tonumber(loc.alertChance) or 0, 0, 100)
  if chance <= 0 or math.random(1, 100) > chance then return false end
  -- NZ.Dispatch.alert comes with the dispatch integration (bridge/server/dispatch.lua)
  local alertFn = type(NZ.Dispatch) == 'table' and rawget(NZ.Dispatch, 'alert') or nil
  if type(alertFn) ~= 'function' then return false end
  local ped = pedOf(src)
  local dispatch = type(cfg().dispatch) == 'table' and cfg().dispatch or {}
  local codes = type(dispatch.codes) == 'table' and dispatch.codes or {}
  local there = isVehicle(entity)
  local shown = there and Utils.plate(GetVehicleNumberPlateText(entity)) or nil
  local ok, err = pcall(alertFn, src, {
    kind = 'locksmith',
    code = codes.locksmith,
    title = L('Illegal key cutting'),
    message = shown and L('Keys are being made for a vehicle that may be stolen ({plate})', { plate = shown })
      or L('Keys are being made for a vehicle that may be stolen'),
    coords = ped and GetEntityCoords(ped) or nil,
    plate = shown,
    model = there and v.model or nil,
    modelHash = there and GetEntityModel(entity) or nil,
    service = service,
  })
  if not ok then lib.print.warn(('[nayzeee-garages] locksmith: dispatch alert failed: %s'):format(tostring(err))) end
  return ok
end

--- Key items of `plate` the player carries (valid or not), for taking them back on a rekey.
local function oldKeyItems(src, plate)
  local out = {}
  for _, item in pairs(CarLock.keyItems()) do
    for _, entry in ipairs(NZ.Inventory.find(src, item, function(md) return Utils.plate(md and md.plate) == plate end)) do
      out[#out + 1] = { item = item, slot = entry.slot, metadata = entry.metadata, count = tonumber(entry.count) or 1 }
    end
  end
  return out
end

local function removeOldKeys(src, list)
  for _, e in ipairs(list) do
    local md = type(e.metadata) == 'table' and e.metadata or {}
    local match = md.id and { id = md.id } or { plate = md.plate }
    pcall(NZ.Inventory.removeItem, src, e.item, e.count, match, e.slot)
  end
end

local function kindWord(kind) return kind == 'fob' and L('fob') or L('key') end

--- A key item of `plate` (opts = { kind, model, origin? }). An item with an origin (a crime's
--- key) is cut from the core's signed metadata (NZ.CarLock.keyMetadata) with the origin
--- written next to it; every other key goes through NZ.CarLock.giveKeyItem.
local function giveKey(src, plate, opts)
  if opts.origin == nil then return CarLock.giveKeyItem(src, plate, opts) end
  if not NZ.Inventory.supportsMetadata() then return false, L('Your inventory cannot hold vehicle keys') end
  if CarLock.mode() ~= 'physical' then return false, L('This server does not use key items') end
  local md = CarLock.keyMetadata(plate, { kind = opts.kind, model = opts.model, origin = opts.origin })
  if not md then return false, L('Something went wrong') end
  md.origin = opts.origin
  if not NZ.Inventory.addItem(src, CarLock.itemName(md.kind), 1, md) then return false, L('You cannot carry the key') end
  -- the client's key cache (client/carlock/lock.lua) learns about the new key
  TriggerClientEvent('nz:client:carlock:keys', src, { plate = plate })
  return true, nil
end

--- Run the service itself (money and materials already taken). Returns ok, message.
local function run(src, ctx, service, v)
  local mode = ctx.mode
  local opts = { kind = v.keyType, model = v.model, reason = 'locksmith' }
  if ctx.loc.illegal == true and service ~= 'rekey' then
    -- a back-alley key: opens the vehicle, but no tracker and no owner's nickname
    opts.origin = 'locksmith'
  elseif service == 'duplicate' then
    -- a copy keeps the origin of the key it copies (a found or back-alley key stays one)
    opts.origin = v.itemOrigin
  end
  if service == 'duplicate' then
    local ok, err = giveKey(src, v.plate, opts)
    if not ok then return false, err end
    return true, L('Spare {kind} for {plate} cut', { kind = kindWord(v.keyType), plate = v.plate })
  end
  if service == 'program' then
    if mode == 'physical' then
      local ok, err = giveKey(src, v.plate, opts)
      if not ok then return false, err end
      return true, L('New {kind} for {plate} programmed', { kind = kindWord(v.keyType), plate = v.plate })
    end
    if not CarLock.grantTemp(src, v.plate, 'locksmith') then return false, L('Something went wrong') end
    return true, L('Temporary key for {plate} programmed ({hours} h)', { plate = v.plate, hours = math.floor(CarLock.tempHours() + 0.5) })
  end
  -- rekey
  local old = mode == 'physical' and oldKeyItems(src, v.plate) or {}
  local version = CarLock.rekey(v.plate, ctx.identifier)
  if not version then return false, L('Something went wrong') end
  -- (owner only, blockOf): in virtual mode the owner keeps the key ownership gives
  if mode == 'physical' then
    removeOldKeys(src, old)
    local ok = CarLock.giveKeyItem(src, v.plate, { kind = v.keyType, model = v.model, reason = 'locksmith' })
    if not ok then
      -- the locks are changed already: never leave the customer without a key (the owner's)
      CarLock.grantTemp(src, v.plate, 'rekey')
      return true, L('Locks of {plate} changed. You cannot carry the new key: you got a temporary key instead', { plate = v.plate })
    end
  end
  return true, L('Locks of {plate} changed: every other key stops working', { plate = v.plate })
end

local function perform(src, loc, c, id, service, plate)
  local ctx = newContext(src, loc, c)
  local entity, dist = nearbyEntity(src, plate, loc, c)
  local v = vehicleInfo(src, ctx, plate, entity, dist)
  -- a vehicle the player knows nothing about and that is not nearby: nothing to work on
  if not v.nearby and not v.hasKey and not v.isOwner and v.keyItems == 0 then
    return Utils.fail(L('Vehicle not found'))
  end
  local reason = v.blocked[service]
  if reason then return Utils.fail(reason) end

  local price = priceOf(loc, service)
  local materials = materialsOf(src, loc, service)
  local missing = {}
  for _, m in ipairs(materials) do
    if m.have < m.count then missing[#missing + 1] = ('%dx %s'):format(m.count - m.have, m.label) end
  end
  if #missing > 0 then
    return Utils.fail(L('Missing materials: {list}', { list = table.concat(missing, ', ') }))
  end
  if price > 0 and moneyOf(src) < price then
    return Utils.fail(L('You cannot afford this'))
  end
  local givesItem = ctx.mode == 'physical'
  if givesItem and not NZ.Inventory.canCarry(src, CarLock.itemName(v.keyType), 1) then
    return Utils.fail(L('You cannot carry the key'))
  end

  local taken = takeMaterials(src, materials)
  if not taken then return Utils.fail(L('Missing materials')) end
  local reasonText = ('locksmith %s %s'):format(service, plate)
  if price > 0 and not NZ.Bridge.removeMoney(src, account(), price, reasonText) then
    giveBack(src, taken)
    return Utils.fail(L('You cannot afford this'))
  end

  local okRun, ok, message = pcall(run, src, ctx, service, v)
  if not okRun or not ok then
    refund(src, price, taken, reasonText)
    if not okRun then lib.print.error(('[nayzeee-garages] locksmith %s failed: %s'):format(service, tostring(ok))) end
    return Utils.fail(okRun and message or L('Something went wrong'))
  end

  -- only a vehicle parked at the shop is seen (a duplicate needs no vehicle)
  local alerted = maybeAlert(src, loc, v, service, v.nearby and entity or nil)
  log('vehicle.locksmith', src, { plate = plate, service = service, location = loc.name, illegal = loc.illegal == true,
    price = price, owner = v.isOwner, alert = alerted or nil })
  return Utils.ok({ message = message, data = openData(src, loc, c, id) })
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

lib.callback.register('nz:carlock:locksmith:open', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'open') then return Utils.fail(L('Please wait a moment')) end
  local loc, c, id = locationOf(payload.id)
  if not loc then return Utils.fail(L('Invalid request')) end
  if not atCounter(src, c, loc) then return Utils.fail(L('You are too far from the locksmith')) end
  return Utils.ok(openData(src, loc, c, id))
end))

lib.callback.register('nz:carlock:locksmith:service', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'service') then return Utils.fail(L('Please wait a moment')) end
  local loc, c, id = locationOf(payload.id)
  local service = type(payload.service) == 'string' and SERVICE_SET[payload.service] and payload.service or nil
  local plate = normPlate(payload.plate)
  if not loc or not service or not plate then return Utils.fail(L('Invalid request')) end
  if not atCounter(src, c, loc) then return Utils.fail(L('You are too far from the locksmith')) end
  if busy[src] then return Utils.fail(L('Please wait a moment')) end
  busy[src] = true
  local ok, res = pcall(perform, src, loc, c, id, service, plate)
  busy[src] = nil
  if not ok then
    lib.print.error(('[nayzeee-garages] locksmith: %s'):format(tostring(res)))
    return Utils.fail(L('Something went wrong'))
  end
  return res
end))

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then busy[math.tointeger(src) or src] = nil end
end)
