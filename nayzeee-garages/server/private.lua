--[[
  nayzeee-garages — server/private.lua (NZ.Private)

  Private garages (§4.6, §5.5): the cache of groups (garage instances 'G<id>') and their
  members, purchase of purchasable locations ("for sale" card), member management
  (add / role / remove / leave), selling an empty garage for a refund, switching between
  the player's copies at one location, and the 'nz:client:groups' sync used by client
  prompts.
]]

local Private = NZ.Private
local Utils = NZ.Utils

local MAX_MEMBERS = 25
local MAX_IDENTIFIER = 64
local UNLIMITED_AVAILABLE = 999

local groups = {}     -- [groupId] = { id, locationId, label, owner, price, createdAt, members = { [identifier] = { name, role } } }
local busy = {}       -- [lockKey] = true while a purchase / sale / member change runs

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then lib.print.warn(('private: could not log %s: %s'):format(event, tostring(err))) end
end

local function setting(path, default)
  if type(NZ.Settings.get) ~= 'function' then return default end
  local success, value = pcall(NZ.Settings.get, path, default)
  if not success or value == nil then return default end
  return value
end

local function maxDistance()
  return tonumber(setting('garages.maxDistance', 25.0)) or 25.0
end

local function notify(src, kind, message)
  if not src then return end
  TriggerClientEvent('nz:client:notify', src, { type = kind, message = message })
end

--- Integer within [min, max] or nil (NaN / infinity rejected).
local function toInt(value, min, max)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = math.floor(n)
  if min and n < min then return nil end
  if max and n > max then return nil end
  return n
end

local function identifierOf(src)
  if not src or type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local success, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if success and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function sourceOf(identifier)
  if type(identifier) ~= 'string' or type(NZ.Bridge.getSourceByIdentifier) ~= 'function' then return nil end
  local success, src = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
  if success then return tonumber(src) end
  return nil
end

local function playerName(src)
  if type(NZ.Bridge.getName) == 'function' then
    local success, name = pcall(NZ.Bridge.getName, src)
    if success and type(name) == 'string' and name ~= '' then return name end
  end
  return GetPlayerName(tostring(src)) or ''
end

local function characterName(identifier)
  if type(NZ.Bridge.getCharacterName) == 'function' then
    local success, name = pcall(NZ.Bridge.getCharacterName, identifier)
    if success and type(name) == 'string' then return name end
  end
  return ''
end

local function money(amount)
  local digits = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
  local grouped = (digits:reverse():gsub('(%d%d%d)', '%1,')):reverse():gsub('^,', '')
  return tostring(setting('interface.currency', '$') or '$') .. grouped
end

local function readIdentifier(value)
  if type(value) ~= 'string' or value == '' or #value > MAX_IDENTIFIER then return nil end
  if value:find('%c') then return nil end
  return value
end

local function firstOpenPoint(location)
  local points = type(location) == 'table' and location.openPoints or nil
  if type(points) ~= 'table' then return nil end
  for _, point in ipairs(points) do
    local coords = Utils.v3(type(point) == 'table' and point.coords or point)
    if coords then return coords end
  end
  return nil
end

local function vehicleTypeOf(row)
  if type(NZ.Vehicles.vehicleTypeOf) == 'function' then return NZ.Vehicles.vehicleTypeOf(row) end
  local vtype = type(row) == 'table' and row.vehicleType or nil
  return Utils.vehicleTypes[vtype] and vtype or 'car'
end

--- Run fn() exclusively per key; concurrent calls get a "please wait" failure result.
local function exclusive(key, fn)
  if busy[key] then return fail(L('Please wait a moment before trying again')) end
  busy[key] = true
  local results = table.pack(pcall(fn))
  busy[key] = nil
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

---------------------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------------------

local function newGroup(row)
  local id = toInt(row.id, 1)
  if not id then return nil end
  return {
    id = id,
    locationId = toInt(row.locationId) or 0,
    label = type(row.label) == 'string' and row.label or '',
    owner = type(row.owner) == 'string' and row.owner ~= '' and row.owner or nil,
    price = math.max(0, toInt(row.price) or 0),
    createdAt = toInt(row.createdAt) or 0,
    members = {},
  }
end

local function addMember(group, identifier, name, role)
  group.members[identifier] = {
    name = type(name) == 'string' and name or '',
    role = role == 'owner' and 'owner' or 'member',
  }
end

local function copyGroup(group)
  local members = {}
  for identifier, member in pairs(group.members) do
    members[identifier] = { name = member.name, role = member.role }
  end
  return {
    id = group.id, locationId = group.locationId, label = group.label, owner = group.owner,
    price = group.price, createdAt = group.createdAt, members = members,
  }
end

--- Owner identifiers of a group, sorted (stable choice for the primary owner).
local function ownersOf(group)
  local owners = {}
  for identifier, member in pairs(group.members) do
    if member.role == 'owner' then owners[#owners + 1] = identifier end
  end
  table.sort(owners)
  return owners
end

--- A group without any owner member gets its `owner` column back as owner (data repair).
local function repairOwner(group)
  if #ownersOf(group) > 0 or not group.owner then return end
  local existing = group.members[group.owner]
  local name = existing and existing.name ~= '' and existing.name or characterName(group.owner)
  if NZ.DB.groups.setMember(group.id, group.owner, name, 'owner') then
    addMember(group, group.owner, name, 'owner')
    lib.print.warn(('private: group #%d had no owner member, restored %s as owner'):format(group.id, group.owner))
  end
end

--- Keep nz_groups.owner pointing at a current owner after role changes / removals.
local function syncPrimaryOwner(group)
  local member = group.owner and group.members[group.owner] or nil
  if member and member.role == 'owner' then return end
  local owners = ownersOf(group)
  if not owners[1] then return end
  if NZ.DB.groups.update(group.id, { owner = owners[1] }) then group.owner = owners[1] end
end

local function displayName(group, location)
  if type(group) == 'table' and group.label ~= '' then return group.label end
  if type(location) == 'table' and type(location.name) == 'string' then return location.name end
  return L('Private garage')
end

--- (Re)load every group and member from the database into the cache.
function Private.load()
  local fresh, groupCount, memberCount = {}, 0, 0
  for _, row in ipairs(NZ.DB.groups.all() or {}) do
    local group = type(row) == 'table' and newGroup(row) or nil
    if group then
      fresh[group.id] = group
      groupCount = groupCount + 1
    end
  end
  for _, row in ipairs(NZ.DB.groups.allMembers() or {}) do
    local group = type(row) == 'table' and fresh[toInt(row.groupId) or -1] or nil
    local identifier = group and readIdentifier(row.identifier) or nil
    if identifier then
      addMember(group, identifier, row.name, row.role)
      memberCount = memberCount + 1
    end
  end
  for _, group in pairs(fresh) do repairOwner(group) end
  groups = fresh
  lib.print.info(('private garages: %d group(s), %d member(s) loaded'):format(groupCount, memberCount))
end

--- Groups (copies) the identifier belongs to, optionally at one location. Groups the player
--- owns come first. Each copy carries `role` (the identifier's role) for convenience.
---@param identifier string
---@param locationId number|nil
---@return table[]
function Private.groupsFor(identifier, locationId)
  local list = {}
  if type(identifier) ~= 'string' or identifier == '' then return list end
  local wanted = nil
  if locationId ~= nil then
    wanted = toInt(locationId)
    if not wanted then return list end
  end
  for _, group in pairs(groups) do
    local member = group.members[identifier]
    if member and (not wanted or group.locationId == wanted) then
      local copy = copyGroup(group)
      copy.role = member.role
      list[#list + 1] = copy
    end
  end
  table.sort(list, function(a, b)
    if a.role ~= b.role then return a.role == 'owner' end
    return a.id < b.id
  end)
  return list
end

--- One group (copy) with its members map, or nil.
---@param id number
---@return table|nil { id, locationId, label, owner, price, createdAt, members = { [identifier] = { name, role } } }
function Private.getGroup(id)
  local group = groups[toInt(id) or -1]
  return group and copyGroup(group) or nil
end

--- Role of an identifier in a group: 'owner' | 'member' | nil.
---@param groupId number
---@param identifier string
---@return string|nil
function Private.role(groupId, identifier)
  local group = groups[toInt(groupId) or -1]
  local member = group and type(identifier) == 'string' and group.members[identifier] or nil
  return member and member.role or nil
end

--- How many groups (sold / assigned copies) exist for a location.
---@param locationId number
---@return number
function Private.copiesUsed(locationId)
  local id = toInt(locationId)
  local count = 0
  if not id then return 0 end
  for _, group in pairs(groups) do
    if group.locationId == id then count = count + 1 end
  end
  return count
end

--- Private locations the identifier belongs to: { [locationId] = true }.
---@param identifier string
---@return table
function Private.memberLocations(identifier)
  local out = {}
  if type(identifier) ~= 'string' or identifier == '' then return out end
  for _, group in pairs(groups) do
    if group.members[identifier] and group.locationId > 0 then out[group.locationId] = true end
  end
  return out
end

--- Send the player's private locations to their client ('nz:client:groups').
---@param src number
function Private.syncMember(src)
  src = tonumber(src)
  if not src or src <= 0 then return end
  TriggerClientEvent('nz:client:groups', src, Private.memberLocations(identifierOf(src)))
end

--- Sync every online player in an identifier set ({ [identifier] = true }).
local function syncIdentifiers(set)
  for identifier in pairs(set) do
    local src = sourceOf(identifier)
    if src then Private.syncMember(src) end
  end
end

--- Reload the cache and resync every online player (e.g. after bulk admin changes).
function Private.reload()
  Private.load()
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if src then Private.syncMember(src) end
  end
end

--- Reload one group (and its members) from the database, syncing affected online players.
--- Use after admin changes to a single group. Returns the fresh copy, or nil when deleted.
---@param id number
---@return table|nil
function Private.refreshGroup(id)
  id = toInt(id, 1)
  if not id then return nil end
  local affected = {}
  local before = groups[id]
  if before then
    for identifier in pairs(before.members) do affected[identifier] = true end
  end
  local fresh = nil
  for _, row in ipairs(NZ.DB.groups.all() or {}) do
    if type(row) == 'table' and toInt(row.id) == id then
      fresh = newGroup(row)
      break
    end
  end
  if fresh then
    for _, member in ipairs(NZ.DB.groups.members(id) or {}) do
      local identifier = type(member) == 'table' and readIdentifier(member.identifier) or nil
      if identifier then
        addMember(fresh, identifier, member.name, member.role)
        affected[identifier] = true
      end
    end
    repairOwner(fresh)
  end
  groups[id] = fresh
  syncIdentifiers(affected)
  return fresh and copyGroup(fresh) or nil
end

--- Nearest enabled public garage (personal vehicles, open to everyone) for a vehicle type.
--- Used when a vehicle must leave a garage its owner can no longer use.
---@param coords table|nil reference position (nearest wins; first by id when nil)
---@param vehicleType string|nil 'car' | 'sea' | 'air'
---@return string|nil garageKey, string|nil name
function Private.fallbackGarage(coords, vehicleType)
  vehicleType = Utils.vehicleTypes[vehicleType] and vehicleType or 'car'
  local origin = Utils.v3(coords)
  local best, bestDist = nil, math.huge
  for _, location in ipairs(NZ.Locations.all('garage') or {}) do
    local restriction = type(location.restriction) == 'table' and location.restriction.type or 'everyone'
    if location.enabled ~= false and location.source ~= 'spawner' and (location.vehicleType or 'car') == vehicleType
      and restriction == 'everyone' then
      local point = firstOpenPoint(location)
      local dist = (origin and point) and Utils.dist(origin, point) or math.huge
      if not best or dist < bestDist then best, bestDist = location, dist end
    end
  end
  if not best then return nil, nil end
  return Utils.key.location(best.id), best.name
end

--- Move an ex-member's vehicles parked in a group garage to a public garage they can use.
---@return string[] plates moved
local function evictVehicles(group, identifier, location)
  local moved = {}
  local key = Utils.key.group(group.id)
  local origin = firstOpenPoint(location)
  for _, row in ipairs(NZ.DB.getVehiclesInGarage(key) or {}) do
    if type(row) == 'table' and row.plate and row.owner == identifier and row.state == 'garaged' then
      local targetKey, targetName = Private.fallbackGarage(origin, vehicleTypeOf(row))
      local fields = { garageKey = targetKey or false }
      if targetKey and targetName then fields.garageName = targetName end
      if NZ.DB.updateVehicle(row.plate, fields) then moved[#moved + 1] = row.plate end
    end
  end
  return moved
end

---------------------------------------------------------------------------------------
-- Member data
---------------------------------------------------------------------------------------

local function ownerCount(group)
  return #ownersOf(group)
end

local function memberCount(group)
  return Utils.count(group.members)
end

local function onlinePlayers()
  if type(NZ.Bridge.getOnlinePlayers) ~= 'function' then return {} end
  local success, list = pcall(NZ.Bridge.getOnlinePlayers)
  return success and type(list) == 'table' and list or {}
end

local function byName(a, b)
  local an, bn = tostring(a.name or ''):lower(), tostring(b.name or ''):lower()
  if an ~= bn then return an < bn end
  return tostring(a.identifier or a.serverId) < tostring(b.identifier or b.serverId)
end

--- MemberData for the viewer (types.ts MemberData). Only owners receive the list of
--- online players they can add.
local function memberData(group, viewer)
  local viewerMember = group.members[viewer]
  local canManage = viewerMember ~= nil and viewerMember.role == 'owner'

  local members = {}
  for identifier, member in pairs(group.members) do
    members[#members + 1] = {
      identifier = identifier,
      name = member.name ~= '' and member.name or L('Unknown'),
      role = member.role,
      you = identifier == viewer,
      online = sourceOf(identifier) ~= nil,
    }
  end
  table.sort(members, function(a, b)
    if a.role ~= b.role then return a.role == 'owner' end
    return byName(a, b)
  end)

  local players = {}
  if canManage then
    for _, player in ipairs(onlinePlayers()) do
      local serverId = type(player) == 'table' and tonumber(player.source) or nil
      if serverId and type(player.identifier) == 'string' and not group.members[player.identifier] then
        players[#players + 1] = {
          serverId = serverId,
          name = type(player.name) == 'string' and player.name ~= '' and player.name or GetPlayerName(tostring(serverId)) or '',
        }
      end
    end
    table.sort(players, byName)
  end

  return { members = members, players = players, canManage = canManage }
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(source, payload)
    local src = tonumber(source)
    if not src or src <= 0 then return fail(L('Something went wrong')) end
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

local function rateLimited(src, bucket, ms)
  return not NZ.Access.rateLimit(src, bucket, ms)
end

local function waitMessage()
  return L('Please wait a moment before trying again')
end

--- Enabled, purchasable private location by id, or nil.
local function saleLocation(id)
  id = toInt(id, 1)
  local location = id and NZ.Locations.get(id) or nil
  if type(location) ~= 'table' or location.kind ~= 'private' or location.enabled == false then return nil end
  if location.purchasable ~= true then return nil end
  return location
end

local function availableCopies(location)
  local max = math.max(0, toInt(location.maxCopies) or 0)
  if max == 0 then return UNLIMITED_AVAILABLE, 0 end
  return math.max(0, max - Private.copiesUsed(location.id)), max
end

--- Can the player pay `price` the way NZ.Bridge.pay charges (settings.economy.account)?
local function canAfford(src, price)
  if price <= 0 then return true end
  local function balance(account)
    local success, value = pcall(NZ.Bridge.getMoney, src, account)
    return success and tonumber(value) or 0
  end
  local account = setting('economy.account', 'bank')
  if account == 'both' then return balance('cash') >= price or balance('bank') >= price end
  return balance(account == 'cash' and 'cash' or 'bank') >= price
end

local function ownsCopy(identifier, locationId)
  for _, group in pairs(groups) do
    local member = group.locationId == locationId and group.members[identifier] or nil
    if member and member.role == 'owner' then return true end
  end
  return false
end

--- The player's open private garage session: { session, location, group, groupId, identifier, role }.
local function groupContext(src)
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return nil, err or L('The garage is not open') end
  local location = session.location
  local gid = toInt(session.groupId, 1)
  if type(location) ~= 'table' or location.kind ~= 'private' or not gid then
    return nil, L('This is not a private garage')
  end
  local group = groups[gid]
  if not group or group.locationId ~= location.id then return nil, L('This garage is no longer available') end
  local identifier = identifierOf(src)
  if not identifier then return nil, L('Your character is not loaded') end
  local member = group.members[identifier]
  if not member then return nil, L('You are not a member of this garage') end
  return {
    session = session, location = location, group = group, groupId = gid,
    identifier = identifier, role = member.role,
  }, nil
end

local function closeGroupSession(src, gid)
  local session = NZ.Access.getSession(src)
  if type(session) == 'table' and toInt(session.groupId) == gid then NZ.Access.closeSession(src) end
end

--- Is anyone inside a garage interior instance of this group?
local function interiorInUse(gid)
  local instances = NZ.Interiors.instances
  if type(instances) ~= 'table' then return false end
  local key = Utils.key.group(gid)
  for _, instance in pairs(instances) do
    if type(instance) == 'table' and (toInt(instance.groupId) == gid or instance.garageKey == key)
      and type(instance.members) == 'table' and next(instance.members) ~= nil then
      return true
    end
  end
  return false
end

local function roleLabel(role)
  return role == 'owner' and L('Owner') or L('Member')
end

-- { locationId } -> ForSaleData
register('nz:forSale:info', function(src, payload)
  if rateLimited(src, 'forSale:info', 750) then return fail(waitMessage()) end
  local location = saleLocation(payload.locationId)
  if not location then return fail(L('This garage is not for sale')) end
  if not NZ.Access.isNear(src, location.openPoints or {}, maxDistance()) then
    return fail(L('You are too far from the garage'))
  end

  local available, total = availableCopies(location)
  local capacity = type(location.capacity) == 'table' and location.capacity or {}
  local access = type(location.access) == 'table' and location.access or {}
  local interior = nil
  if access.interiorId and type(NZ.Interiors.get) == 'function' then
    local success, found = pcall(NZ.Interiors.get, access.interiorId)
    if success and type(found) == 'table' then interior = found end
  end
  local price = math.max(0, toInt(location.price) or 0)

  return ok({
    locationId = location.id,
    name = location.name,
    price = price,
    available = available,
    total = total,
    storage = location.storage == 'personal' and 'personal' or 'shared',
    spaces = capacity.mode == 'limited' and toInt(capacity.spaces) or nil,
    interiorName = interior and type(interior.name) == 'string' and interior.name or nil,
    canTour = interior ~= nil and interior.enabled ~= false and access.mode ~= 'quick',
    canAfford = canAfford(src, price),
  })
end)

-- { locationId } -> null (the client then opens the garage)
register('nz:forSale:buy', function(src, payload)
  if rateLimited(src, 'forSale:buy', 2000) then return fail(waitMessage()) end
  local location = saleLocation(payload.locationId)
  if not location then return fail(L('This garage is not for sale')) end
  local identifier = identifierOf(src)
  if not identifier then return fail(L('Your character is not loaded')) end
  if not NZ.Access.isNear(src, location.openPoints or {}, maxDistance()) then
    return fail(L('You are too far from the garage'))
  end

  return exclusive('L' .. location.id, function()
    if ownsCopy(identifier, location.id) then return fail(L('You already own this garage')) end
    local available = availableCopies(location)
    if available <= 0 then return fail(L('This garage is sold out')) end

    local price = math.max(0, toInt(location.price) or 0)
    local account = nil
    if price > 0 then
      local paid, used = NZ.Bridge.pay(src, price, 'nayzeee-garages:garage-purchase')
      if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(price) })) end
      account = used
    end

    local function refund(why)
      if price <= 0 then return end
      local success, added = pcall(NZ.Bridge.addMoney, src, account or 'bank', price, 'nayzeee-garages:garage-purchase-refund')
      if not success or not added then
        log('security.refund', src, { amount = price, account = account, location = location.id, reason = why })
      end
    end

    local id = NZ.DB.groups.create(location.id, location.name, identifier, price)
    id = toInt(id, 1)
    if not id then
      refund('group insert failed')
      return fail(L('Something went wrong'))
    end
    local name = playerName(src)
    if not NZ.DB.groups.setMember(id, identifier, name, 'owner') then
      NZ.DB.groups.delete(id)
      refund('owner insert failed')
      return fail(L('Something went wrong'))
    end

    local group = newGroup({
      id = id, locationId = location.id, label = location.name, owner = identifier,
      price = price, createdAt = os.time(),
    })
    addMember(group, identifier, name, 'owner')
    groups[id] = group

    log('garage.purchase', src, {
      group = id, location = location.id, name = location.name, price = price, account = account,
      copies = Private.copiesUsed(location.id), maxCopies = location.maxCopies,
    })
    Private.syncMember(src)
    return ok(nil)
  end)
end)

-- {} -> MemberData of the open private garage
register('nz:garage:members', function(src)
  if rateLimited(src, 'garage:members', 500) then return fail(waitMessage()) end
  local gc, err = groupContext(src)
  if not gc then return fail(err) end
  return ok(memberData(gc.group, gc.identifier))
end)

-- { serverId, role } (owners) -> MemberData
register('nz:garage:memberAdd', function(src, payload)
  if rateLimited(src, 'garage:memberAdd', 1000) then return fail(waitMessage()) end
  local gc, err = groupContext(src)
  if not gc then return fail(err) end
  if gc.role ~= 'owner' then return fail(L('Only owners can manage members')) end

  local role = payload.role == nil and 'member' or payload.role
  if role ~= 'owner' and role ~= 'member' then return fail(L('Invalid request')) end
  local target = toInt(payload.serverId, 1)
  if not target or not GetPlayerName(tostring(target)) then return fail(L('Player not found')) end
  local targetId = identifierOf(target)
  if not targetId then return fail(L('Player not found')) end

  return exclusive('G' .. gc.groupId, function()
    local group = groups[gc.groupId]
    if not group then return fail(L('This garage is no longer available')) end
    if group.members[targetId] then return fail(L('This player is already a member')) end
    if memberCount(group) >= MAX_MEMBERS then
      return fail(L('A garage cannot have more than {max} members', { max = MAX_MEMBERS }))
    end
    local name = playerName(target)
    if not NZ.DB.groups.setMember(group.id, targetId, name, role) then return fail(L('Something went wrong')) end
    addMember(group, targetId, name, role)

    local label = displayName(group, gc.location)
    Private.syncMember(target)
    notify(target, 'info', L('You now have access to the garage {garage}', { garage = label }))
    log('garage.members', src, {
      action = 'add', group = group.id, location = group.locationId, identifier = targetId, name = name,
      role = role, by = gc.identifier,
    })
    return ok(memberData(group, gc.identifier))
  end)
end)

-- { identifier, role } (owners) -> MemberData
register('nz:garage:memberRole', function(src, payload)
  if rateLimited(src, 'garage:memberRole', 1000) then return fail(waitMessage()) end
  local gc, err = groupContext(src)
  if not gc then return fail(err) end
  if gc.role ~= 'owner' then return fail(L('Only owners can manage members')) end
  local targetId = readIdentifier(payload.identifier)
  if not targetId then return fail(L('Invalid request')) end
  local role = payload.role
  if role ~= 'owner' and role ~= 'member' then return fail(L('Invalid request')) end

  return exclusive('G' .. gc.groupId, function()
    local group = groups[gc.groupId]
    if not group then return fail(L('This garage is no longer available')) end
    local member = group.members[targetId]
    if not member then return fail(L('This player is not a member')) end
    if member.role == role then return ok(memberData(group, gc.identifier)) end
    if member.role == 'owner' and role == 'member' and ownerCount(group) <= 1 then
      return fail(L('Add another owner before changing your own role'))
    end
    if not NZ.DB.groups.setMember(group.id, targetId, member.name, role) then return fail(L('Something went wrong')) end
    local previous = member.role
    member.role = role
    syncPrimaryOwner(group)

    local targetSrc = sourceOf(targetId)
    if targetSrc then
      Private.syncMember(targetSrc)
      if targetSrc ~= src then
        notify(targetSrc, 'info', L('Your role in {garage} is now {role}', {
          garage = displayName(group, gc.location), role = roleLabel(role),
        }))
      end
    end
    log('garage.members', src, {
      action = 'role', group = group.id, location = group.locationId, identifier = targetId, name = member.name,
      role = role, previousRole = previous, by = gc.identifier,
    })
    return ok(memberData(group, gc.identifier))
  end)
end)

-- { identifier } (owners, or a member leaving) -> MemberData
register('nz:garage:memberRemove', function(src, payload)
  if rateLimited(src, 'garage:memberRemove', 1000) then return fail(waitMessage()) end
  local gc, err = groupContext(src)
  if not gc then return fail(err) end
  local targetId = readIdentifier(payload.identifier)
  if not targetId then return fail(L('Invalid request')) end
  local leaving = targetId == gc.identifier
  if not leaving and gc.role ~= 'owner' then return fail(L('Only owners can manage members')) end

  return exclusive('G' .. gc.groupId, function()
    local group = groups[gc.groupId]
    if not group then return fail(L('This garage is no longer available')) end
    local member = group.members[targetId]
    if not member then return fail(L('This player is not a member')) end
    if member.role == 'owner' and ownerCount(group) <= 1 then
      if leaving then return fail(L('Add another owner before leaving this garage')) end
      return fail(L('A garage needs at least one owner'))
    end
    if not NZ.DB.groups.removeMember(group.id, targetId) then return fail(L('Something went wrong')) end
    group.members[targetId] = nil
    syncPrimaryOwner(group)

    -- Their vehicles must not stay locked in a garage they can no longer open.
    local moved = evictVehicles(group, targetId, gc.location)

    local label = displayName(group, gc.location)
    local targetSrc = sourceOf(targetId)
    if targetSrc then
      Private.syncMember(targetSrc)
      closeGroupSession(targetSrc, group.id)
      if not leaving then
        notify(targetSrc, 'warning', L('You were removed from the garage {garage}', { garage = label }))
      end
      if #moved > 0 then
        notify(targetSrc, 'info', L('Your vehicles there were moved to a public garage'))
      end
    end
    log('garage.members', src, {
      action = leaving and 'leave' or 'remove', group = group.id, location = group.locationId,
      identifier = targetId, name = member.name, role = member.role, by = gc.identifier, movedVehicles = moved,
    })
    return ok(memberData(group, gc.identifier))
  end)
end)

-- {} (owner) -> null
register('nz:garage:sellGarage', function(src)
  if rateLimited(src, 'garage:sellGarage', 3000) then return fail(waitMessage()) end
  local gc, err = groupContext(src)
  if not gc then return fail(err) end
  if gc.role ~= 'owner' then return fail(L('Only owners can sell this garage')) end

  return exclusive('G' .. gc.groupId, function()
    local group = groups[gc.groupId]
    if not group then return fail(L('This garage is no longer available')) end
    local key = Utils.key.group(group.id)
    if (tonumber(NZ.DB.countInGarage(key, nil)) or 0) > 0 then
      return fail(L('Remove every vehicle from this garage before selling it'))
    end
    for _, entry in pairs(type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out or {}) do
      if type(entry) == 'table' and entry.garageKey == key then
        return fail(L('Remove every vehicle from this garage before selling it'))
      end
    end
    if interiorInUse(group.id) then return fail(L('Someone is inside this garage, try again later')) end

    local percent = Utils.clamp(toInt(gc.location.sellRefund) or 0, 0, 100)
    local refund = math.floor(group.price * percent / 100)
    if not NZ.DB.groups.delete(group.id) then return fail(L('Something went wrong')) end
    groups[group.id] = nil

    local refunded = true
    if refund > 0 then
      local success, added = pcall(NZ.Bridge.addMoney, src, 'bank', refund, 'nayzeee-garages:garage-sale')
      refunded = success and added == true
      if not refunded then
        log('security.refund', src, { amount = refund, account = 'bank', group = group.id, reason = 'garage sale refund failed' })
      end
    end

    local label = displayName(group, gc.location)
    local memberList = {}
    for identifier in pairs(group.members) do
      memberList[#memberList + 1] = identifier
      local memberSrc = sourceOf(identifier)
      if memberSrc then
        Private.syncMember(memberSrc)
        closeGroupSession(memberSrc, group.id)
        if memberSrc ~= src then
          notify(memberSrc, 'warning', L('The garage {garage} was sold by its owner', { garage = label }))
        end
      end
    end
    if refund > 0 and refunded then
      notify(src, 'success', L('Garage sold for {amount}', { amount = money(refund) }))
    else
      notify(src, 'success', L('Garage sold'))
    end

    log('garage.sell', src, {
      group = group.id, location = group.locationId, label = label, price = group.price,
      refundPercent = percent, refund = refund, refunded = refunded, members = memberList,
    })
    return ok(nil)
  end)
end)

-- { groupId } -> GarageOpenData of another copy at the same location
register('nz:garage:switchGroup', function(src, payload)
  if rateLimited(src, 'garage:switchGroup', 750) then return fail(waitMessage()) end
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return fail(err or L('The garage is not open')) end
  local location = session.location
  if type(location) ~= 'table' or location.kind ~= 'private' then return fail(L('This is not a private garage')) end
  local gid = toInt(payload.groupId, 1)
  local group = gid and groups[gid] or nil
  if not group or group.locationId ~= location.id then return fail(L('Garage not found')) end
  local identifier = identifierOf(src)
  if not identifier then return fail(L('Your character is not loaded')) end
  if not group.members[identifier] then return fail(L('You are not a member of this garage')) end

  local fresh = NZ.Access.openSession(src, Utils.key.group(gid), location, { groupId = gid })
  if type(fresh) ~= 'table' then return fail(L('Something went wrong')) end
  return ok(NZ.Vehicles.buildGarageData(src, fresh))
end)
