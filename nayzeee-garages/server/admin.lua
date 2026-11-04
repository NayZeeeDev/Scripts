--[[
  nayzeee-garages — admin panel callbacks (NZ.Admin), server side.

  Every 'nz:admin:*' callback forwarded by the admin NUI (docs/ARCHITECTURE.md §8.2):
  panel data, locations (save / delete / toggle / import), private garage groups and their
  members, interiors (delete / toggle), settings, the player vehicle manager (search,
  list, detail, assign, edit, delete). Each callback requires NZ.Access.isAdmin, is rate
  limited, validates its payload and logs the change ('admin.<action>'). Changes that go
  through NZ.Locations / NZ.Interiors / NZ.Settings are logged by those modules.
]]

local Admin = NZ.Admin
local Utils = NZ.Utils

local PAGE_SIZE = 10
local MAX_SERVICE = 100
local MAX_PROPS_BYTES = 65535
local MAX_MONEY = 10000000
local MAX_MILEAGE = 10000000
local MAX_PLATE_LOOKUP = 16
local PLATE_TRIES = 25
local MAX_IMPOUND_SECONDS = 365 * 24 * 3600

local IMPORT_LABELS = {
  ['qb-garages'] = 'QBCore garages (qb-garages)',
  ['qbx_garages'] = 'Qbox garages (qbx_garages)',
  json = 'JSON',
}
local STATES = { garaged = true, out = true, impounded = true }
local OWNER_TYPES = { player = true, job = true, gang = true }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then lib.print.warn(('admin: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function num(value, min, max, default, integer)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not finite(n) then return default end
  if n < min then n = min elseif n > max then n = max end
  if integer then n = math.floor(n) end
  return n
end

--- Positive integer id or nil (never clamps).
local function positiveId(value)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not finite(n) or n < 1 or n > 2147483647 or n ~= math.floor(n) then return nil end
  return math.tointeger(n)
end

--- Clean text and drop a truncated trailing UTF-8 sequence.
local function safeText(value, maxLen)
  local s = Utils.cleanText(value, maxLen)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

--- Character identifier (citizenid / ESX identifier).
local function identifierArg(value)
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if #s < 1 or #s > 64 or s:find('[%s%c<>"\'`]') then return nil end
  return s
end

--- Job / gang name.
local function groupNameArg(value)
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if #s < 1 or #s > 64 or not s:match('^[%w_%-]+$') then return nil end
  return s
end

--- Spawn name: 1-32 letters, digits or underscores (lower-cased).
local function modelArg(value)
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if #s < 1 or #s > 32 or not s:match('^[%w_]+$') then return nil end
  return s:lower()
end

--- A new plate: 1-8 characters A-Z, 0-9 or spaces (trimmed, upper-cased).
local function plateArg(value)
  local p = Utils.plate(value)
  if not p or #p > 8 or not p:match('^[A-Z0-9 ]+$') then return nil end
  return p
end

--- An existing plate to look up (stored plates may contain other characters).
local function readPlate(value)
  local p = Utils.plate(value)
  if p and #p <= MAX_PLATE_LOOKUP then return p end
  return nil
end

local function signedHash(value)
  local n = tonumber(value)
  if not finite(n) then return nil end
  n = math.floor(n) % 4294967296
  if n >= 2147483648 then n = n - 4294967296 end
  return math.tointeger(n) or n
end

local function rowHash(row)
  local h = signedHash(row.hash)
  if h and h ~= 0 then return h end
  if type(row.model) == 'string' and row.model ~= '' then return signedHash(joaat(row.model)) end
  return 0
end

local function percent(value, default)
  local n = tonumber(value)
  if not finite(n) then return default end
  return Utils.round(Utils.clamp(n, 0, 100), 1)
end

local function sourceOf(identifier)
  if type(identifier) ~= 'string' or type(NZ.Bridge.getSourceByIdentifier) ~= 'function' then return nil end
  local success, src = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
  if success then return tonumber(src) end
  return nil
end

local function charName(identifier)
  if type(identifier) ~= 'string' or identifier == '' then return '' end
  local success, name = pcall(NZ.Bridge.getCharacterName, identifier)
  if success and type(name) == 'string' then return name end
  return identifier
end

local function adminName(src)
  local success, name = pcall(NZ.Bridge.getName, src)
  if success and type(name) == 'string' and name ~= '' then return name end
  return GetPlayerName(src) or L('Admin')
end

local function adminIdentifier(src)
  local success, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if success and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

--- True when the character exists (online, or found by the bridge character search).
--- When the framework cannot be asked, the identifier is accepted.
local function characterExists(identifier)
  if sourceOf(identifier) then return true end
  if type(NZ.Bridge.searchCharacters) ~= 'function' then return true end
  local success, rows = pcall(NZ.Bridge.searchCharacters, identifier, 50, 0)
  if not success or type(rows) ~= 'table' then return true end
  for _, row in ipairs(rows) do
    if type(row) == 'table' and row.identifier == identifier then return true end
  end
  return false
end

local function safeList(fn)
  if type(fn) ~= 'function' then return {} end
  local success, list = pcall(fn)
  if success and type(list) == 'table' then return list end
  return {}
end

local function keyName(key, ctx)
  if type(key) ~= 'string' then return nil end
  if ctx and ctx[key] ~= nil then return ctx[key] or nil end
  local name = NZ.Locations.keyName(key)
  if ctx then ctx[key] = name or false end
  return name
end

local function isPlayerOnline(identifier)
  return sourceOf(identifier) ~= nil
end

---------------------------------------------------------------------------------------
-- Vehicle entities
---------------------------------------------------------------------------------------

--- The registration of a vehicle: the real plate under a fake plate (NZ.FakePlates), else
--- the plate text.
local function registrationOf(entity)
  local fake = NZ.FakePlates
  if type(fake) == 'table' and type(fake.realPlateOf) == 'function' then
    local okReal, real = pcall(fake.realPlateOf, entity)
    if okReal and real then return real end
  end
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

local function findEntityByPlate(plate)
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if DoesEntityExist(entity) and registrationOf(entity) == plate then return entity end
  end
  return nil
end

--- Live entity of a vehicle (tracked out entry first, then a world scan).
local function liveEntity(plate)
  local entity = nil
  if type(NZ.Vehicles.isOut) == 'function' then
    local success, _, tracked = pcall(NZ.Vehicles.isOut, plate)
    if success and tracked and DoesEntityExist(tracked) then entity = tracked end
  end
  return entity or findEntityByPlate(plate)
end

local function occupied(entity)
  for seat = -1, 14 do
    local ped = GetPedInVehicleSeat(entity, seat)
    if ped and ped ~= 0 then return true end
  end
  return false
end

local function forgetOut(plate)
  if type(NZ.Vehicles.clearOut) == 'function' then
    pcall(NZ.Vehicles.clearOut, plate)
  elseif type(NZ.Vehicles.out) == 'table' then
    NZ.Vehicles.out[plate] = nil
  end
end

local function withLock(plate, fn, ...)
  if type(NZ.Vehicles.withLock) == 'function' then return NZ.Vehicles.withLock(plate, fn, ...) end
  return fn(...)
end

---------------------------------------------------------------------------------------
-- Groups (private garages)
---------------------------------------------------------------------------------------

local function allGroups()
  return NZ.DB.groups.all() or {}
end

local function findGroup(id)
  for _, group in ipairs(allGroups()) do
    if group.id == id then return group end
  end
  return nil
end

local function groupsOfLocation(locationId)
  local list = {}
  for _, group in ipairs(allGroups()) do
    if group.locationId == locationId then list[#list + 1] = group end
  end
  return list
end

local function memberName(member)
  if type(member.name) == 'string' and member.name ~= '' then return member.name end
  return charName(member.identifier)
end

--- GroupInfo (types.ts) of a group row.
local function groupInfo(group, members)
  members = members or NZ.DB.groups.members(group.id) or {}
  local list, ownerName = {}, nil
  for _, member in ipairs(members) do
    if type(member.identifier) == 'string' then
      local name = memberName(member)
      list[#list + 1] = { identifier = member.identifier, name = name, role = member.role == 'owner' and 'owner' or 'member' }
      if member.identifier == group.owner then ownerName = name end
    end
  end
  table.sort(list, function(a, b)
    if a.role ~= b.role then return a.role == 'owner' end
    return a.name:lower() < b.name:lower()
  end)
  return {
    id = group.id,
    locationId = group.locationId,
    label = group.label or '',
    owner = group.owner or '',
    ownerName = ownerName or charName(group.owner),
    members = list,
    vehicles = tonumber(NZ.DB.countInGarage(Utils.key.group(group.id))) or 0,
    createdAt = tonumber(group.createdAt) or 0,
  }
end

--- Reload the private garage cache and push group membership to affected online players.
local function reloadPrivate(identifiers)
  if type(NZ.Private.load) == 'function' then
    local success, err = pcall(NZ.Private.load)
    if not success then lib.print.error(('admin: private garages reload failed: %s'):format(tostring(err))) end
  end
  if type(NZ.Private.syncMember) ~= 'function' then return end
  for identifier in pairs(identifiers or {}) do
    local src = sourceOf(identifier)
    if src then
      local success, err = pcall(NZ.Private.syncMember, src)
      if not success then lib.print.warn(('admin: group sync failed: %s'):format(tostring(err))) end
    end
  end
end

local function addMembersTo(set, groupId)
  for _, member in ipairs(NZ.DB.groups.members(groupId) or {}) do
    if type(member.identifier) == 'string' then set[member.identifier] = true end
  end
  return set
end

---------------------------------------------------------------------------------------
-- Admin panel data
---------------------------------------------------------------------------------------

--- IplProfile list for the NUI (no IPL / entity set names).
local function profileList()
  local list = {}
  for key, profile in pairs(type(Config.IplProfiles) == 'table' and Config.IplProfiles or {}) do
    if type(key) == 'string' and type(profile) == 'table' then
      local options = {}
      for _, option in ipairs(type(profile.options) == 'table' and profile.options or {}) do
        if type(option) == 'table' and type(option.key) == 'string' then
          local choices = {}
          for _, choice in ipairs(type(option.choices) == 'table' and option.choices or {}) do
            if type(choice) == 'table' and type(choice.value) == 'string' then
              choices[#choices + 1] = { value = choice.value, label = L(tostring(choice.label or choice.value)) }
            end
          end
          options[#options + 1] = {
            key = option.key,
            label = L(tostring(option.label or option.key)),
            default = type(option.default) == 'string' and option.default or (choices[1] and choices[1].value) or '',
            choices = choices,
          }
        end
      end
      list[#list + 1] = {
        key = key,
        label = L(tostring(profile.label or key)),
        coords = profile.coords ~= nil and Utils.v4(profile.coords) or nil,
        slots = math.floor(tonumber(profile.slots) or 0),
        options = options,
      }
    end
  end
  table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  return list
end

local function importSources()
  local list = {}
  for _, key in ipairs(type(ServerConfig.ImportSources) == 'table' and ServerConfig.ImportSources or {}) do
    if type(key) == 'string' then
      list[#list + 1] = {
        key = key,
        label = L(IMPORT_LABELS[key] or key),
        available = key == 'json' or Utils.resourceStarted(key),
      }
    end
  end
  return list
end

--- AdminOpenData (types.ts) for the admin panel.
---@return table
--- Vehicle counts per location id (string keys): garages and job garages count their L key,
--- private locations the G keys of every owned copy, impounds the vehicles they hold.
---@return table<string, { parked: number, out: number, impounded: number, held: number }>
local function locationStats()
  local success, stats = pcall(NZ.DB.garageStats)
  if not success or type(stats) ~= 'table' then return {} end
  local groupLocation = {}
  for _, group in ipairs(allGroups()) do groupLocation[group.id] = group.locationId end
  local out = {}
  local function entry(id)
    local k = tostring(id)
    out[k] = out[k] or { parked = 0, out = 0, impounded = 0, held = 0 }
    return out[k]
  end
  for key, counts in pairs(stats.garages or {}) do
    local kind, id = Utils.key.parse(key)
    local locationId = (kind == 'L' and id) or (kind == 'G' and groupLocation[id]) or nil
    if locationId then
      local e = entry(locationId)
      e.parked = e.parked + (counts.parked or 0)
      e.out = e.out + (counts.out or 0)
      e.impounded = e.impounded + (counts.impounded or 0)
    end
  end
  for id, count in pairs(stats.impounds or {}) do
    entry(id).held = count
  end
  return out
end

function Admin.openData()
  local hasGangs = NZ.Bridge.hasGangs == true
  return {
    locationStats = locationStats(),
    page = 'garages',
    settings = NZ.Settings.all(),
    locations = Utils.deepCopy(NZ.Locations.all() or {}),
    interiors = NZ.Interiors.all(),
    profiles = profileList(),
    jobs = safeList(NZ.Bridge.getJobs),
    gangs = hasGangs and safeList(NZ.Bridge.getGangs) or {},
    framework = NZ.Framework,
    gangsSupported = hasGangs,
    importSources = importSources(),
    -- Config.Peds defaults shown by the location editor's NPC fields
    peds = {
      defaultModel = type(Config.Peds) == 'table' and Config.Peds.defaultModel or nil,
      defaultScenario = type(Config.Peds) == 'table' and Config.Peds.defaultScenario or nil,
    },
  }
end

---------------------------------------------------------------------------------------
-- Vehicle views
---------------------------------------------------------------------------------------

--- AdminVehicleRow (types.ts, label/make/image are added by the client).
local function vehicleRow(row, names)
  return {
    plate = row.plate,
    model = row.model or '',
    hash = rowHash(row),
    vehicleType = Utils.vehicleTypes[row.vehicleType] and row.vehicleType or 'car',
    garageKey = row.garageKey,
    garageName = keyName(row.garageKey, names),
    state = STATES[row.state] and row.state or 'garaged',
    financed = row.finance ~= nil,
    fuel = percent(row.fuel, 100),
    engine = percent(row.engine, 100),
    body = percent(row.body, 100),
    blocked = row.blocked == true,
  }
end

local function jobLabels(kind)
  local map = {}
  local list = kind == 'gang' and (NZ.Bridge.hasGangs and safeList(NZ.Bridge.getGangs) or {}) or safeList(NZ.Bridge.getJobs)
  for _, entry in ipairs(list) do
    if type(entry) == 'table' and type(entry.name) == 'string' then
      map[entry.name] = type(entry.label) == 'string' and entry.label or entry.name
    end
  end
  return map
end

local function ownerNameOf(row)
  if row.ownerType == 'job' and row.job then return jobLabels('job')[row.job] or row.job end
  if row.ownerType == 'gang' and row.gang then return jobLabels('gang')[row.gang] or row.gang end
  return charName(row.owner)
end

--- Every garage a vehicle can be assigned to: locations and private garage instances.
local function garageChoices(currentKey)
  local list, seen = {}, {}
  local byLocation = {}
  for _, group in ipairs(allGroups()) do
    byLocation[group.locationId] = byLocation[group.locationId] or {}
    table.insert(byLocation[group.locationId], group)
  end
  for _, location in ipairs(NZ.Locations.all() or {}) do
    if location.kind == 'private' then
      for _, group in ipairs(byLocation[location.id] or {}) do
        local key = Utils.key.group(group.id)
        local label = (type(group.label) == 'string' and group.label ~= '') and group.label or location.name
        list[#list + 1] = { key = key, name = ('%s (%s)'):format(label, charName(group.owner)) }
        seen[key] = true
      end
    elseif location.kind ~= 'impound' then
      local key = Utils.key.location(location.id)
      list[#list + 1] = { key = key, name = location.name }
      seen[key] = true
    end
  end
  if type(currentKey) == 'string' and not seen[currentKey] then
    list[#list + 1] = { key = currentKey, name = NZ.Locations.keyName(currentKey) or currentKey }
  end
  return list
end

local function impoundChoices()
  local list = {}
  for _, location in ipairs(NZ.Locations.all('impound') or {}) do
    list[#list + 1] = { id = location.id, name = location.name }
  end
  return list
end

local function textField(value, maxLen)
  return type(value) == 'string' and (safeText(value, maxLen) or '') or ''
end

--- AdminVehicleDetail (types.ts) of a plate, or nil when the vehicle does not exist.
local function vehicleDetail(plate)
  local row = NZ.DB.getVehicle(plate)
  if not row then return nil end
  local vehicle = vehicleRow(row, {})
  vehicle.owner = row.owner
  vehicle.ownerName = ownerNameOf(row)
  vehicle.ownerType = OWNER_TYPES[row.ownerType] and row.ownerType or 'player'
  vehicle.job = row.job
  vehicle.gang = row.gang
  vehicle.nickname = (type(row.nickname) == 'string' and row.nickname ~= '') and row.nickname or nil
  vehicle.mileage = Utils.round(tonumber(row.mileage) or 0, 1)
  vehicle.props = type(row.props) == 'table' and row.props or {}

  local ownership = {}
  for _, entry in ipairs(NZ.DB.events.list(row.plate, 'owner', 50) or {}) do
    local data = type(entry.data) == 'table' and entry.data or {}
    ownership[#ownership + 1] = {
      identifier = type(data.identifier) == 'string' and data.identifier or nil,
      name = type(data.name) == 'string' and data.name or '',
      via = type(data.via) == 'string' and data.via or 'unknown',
      at = tonumber(entry.at) or tonumber(data.at) or 0,
      price = tonumber(data.price),
    }
  end

  local service = {}
  for _, entry in ipairs(NZ.DB.events.list(row.plate, 'service', MAX_SERVICE) or {}) do
    local data = type(entry.data) == 'table' and entry.data or {}
    service[#service + 1] = {
      id = tonumber(entry.id),
      item = textField(data.item, 64),
      mileage = Utils.round(math.max(tonumber(data.mileage) or 0, 0), 1),
      shop = textField(data.shop, 64),
      at = tonumber(entry.at) or tonumber(data.at) or 0,
    }
  end

  return {
    vehicle = vehicle,
    impound = type(row.impound) == 'table' and row.impound or nil,
    finance = type(row.finance) == 'table' and row.finance or nil,
    ownership = ownership,
    service = service,
    garages = garageChoices(row.garageKey),
    impounds = impoundChoices(),
    damage = NZ.Vehicles.damageSummary(row.damage),
    lastUsed = tonumber(row.lastOut),
  }
end

local function uniquePlate()
  for _ = 1, PLATE_TRIES do
    local candidate = Utils.generatePlate()
    if not NZ.DB.plateExists(candidate, true) then return candidate end
  end
  return nil
end

--- Validate a garage key for storage: L / G keys must resolve (not an impound), H keys need
--- a plausible house id (the house may not be registered right now).
---@return string|nil key, table|nil resolved, string|nil error
local function garageKeyArg(value)
  if type(value) ~= 'string' or #value > 64 then return nil, nil, L('Select a garage') end
  local kind = Utils.key.parse(value)
  if not kind then return nil, nil, L('Select a garage') end
  local resolved = NZ.Locations.resolveKey(value)
  if kind == 'H' then
    if value:find('[%c<>]') then return nil, nil, L('Select a garage') end
    return value, resolved, nil
  end
  if not resolved or type(resolved.location) ~= 'table' then return nil, nil, L('Garage not found') end
  if resolved.location.kind == 'impound' then return nil, nil, L('Vehicles cannot be parked at an impound') end
  return value, resolved, nil
end

---------------------------------------------------------------------------------------
-- Vehicle patch (admin:vehicle:update)
-- JSON null cannot cross the NUI -> Lua bridge, so "clear" is also accepted as `false`
-- (and as an empty object for impound / finance).
---------------------------------------------------------------------------------------

local function isClear(value)
  return value == false or (type(value) == 'table' and next(value) == nil)
end

local function financeArg(value)
  if type(value) ~= 'table' then return nil, L('Invalid finance data') end
  if NZ.Framework == 'esx' then return nil, L('Vehicle finance is not available on this framework') end
  local balance = num(value.balance, 0, MAX_MONEY * 10, nil, true)
  local payment = num(value.payment, 0, MAX_MONEY, nil, true)
  local left = num(value.paymentsLeft, 0, 1000, nil, true)
  if not balance or not payment or not left then return nil, L('Invalid finance data') end
  if balance == 0 then return false, nil end
  return {
    balance = balance,
    payment = payment,
    paymentsLeft = left,
    paymentsTotal = num(value.paymentsTotal, 0, 1000, nil, true),
    intervalHours = num(value.intervalHours, 0, 8760, nil),
    nextPaymentHours = num(value.nextPaymentHours, 0, 8760, nil),
    overdue = value.overdue == true,
  }, nil
end

local function impoundArg(src, value, row)
  if type(value) ~= 'table' then return nil, L('Invalid impound data') end
  local locationId = positiveId(value.locationId)
  local location = locationId and NZ.Locations.get(locationId) or nil
  if type(location) ~= 'table' or location.kind ~= 'impound' then return nil, L('Select an impound') end
  local now = os.time()
  local previous = type(row.impound) == 'table' and row.impound or {}
  local releaseAt
  local hours = tonumber(value.hours)
  if hours then
    -- Hold time from now, measured with the server clock (the admin PC clock may differ).
    releaseAt = now + math.floor(math.max(0, math.min(hours * 3600, MAX_IMPOUND_SECONDS)) + 0.5)
  else
    releaseAt = num(value.releaseAt, 0, now + MAX_IMPOUND_SECONDS, nil, true)
    if not releaseAt or releaseAt < now then releaseAt = now end
  end
  local reason
  if value.reason == '' then
    reason = '' -- explicitly cleared by the admin
  else
    reason = safeText(value.reason, 120) or (type(previous.reason) == 'string' and previous.reason) or ''
  end
  return {
    locationId = location.id,
    locationName = location.name,
    reason = reason,
    fee = num(value.fee, 0, MAX_MONEY, num(location.defaultFee, 0, MAX_MONEY, 0, true), true),
    by = adminIdentifier(src),
    byName = adminName(src),
    at = now,
    releaseAt = releaseAt,
    retrievable = value.retrievable ~= false,
  }, nil
end

local function serviceList(list)
  if type(list) ~= 'table' then return nil, L('Invalid service history') end
  local out = {}
  local now = os.time()
  for _, entry in ipairs(list) do
    if #out >= MAX_SERVICE then break end
    if type(entry) == 'table' then
      local item = safeText(entry.item, 64)
      if item then
        out[#out + 1] = {
          item = item,
          mileage = Utils.round(num(entry.mileage, 0, MAX_MILEAGE, 0), 1),
          shop = safeText(entry.shop, 64) or '',
          at = num(entry.at, 1, now + 86400, now, true),
        }
      end
    end
  end
  return out, nil
end

--- Validate every part of the patch, then apply it. Runs under the vehicle lock.
local function applyPatch(src, plate, patch)
  local row = NZ.DB.getVehicle(plate)
  if not row then return fail(L('Vehicle not found')) end
  plate = row.plate

  local fields, changed = {}, {}
  local ownerEvent, newPlate, service = nil, nil, nil
  local stateTarget = nil

  -- plate
  if patch.plate ~= nil then
    local p = plateArg(patch.plate)
    if not p then return fail(L('Plates have 1 to 8 letters, digits or spaces')) end
    if p ~= plate then
      if liveEntity(plate) then return fail(L('Store the vehicle before changing its plate')) end
      if NZ.DB.plateExists(p) then return fail(L('This plate is already in use')) end
      newPlate = p
      changed[#changed + 1] = 'plate'
    end
  end

  -- details
  local details = patch.details
  if details ~= nil then
    if type(details) ~= 'table' then return fail(L('Invalid vehicle details')) end
    if details.garageKey ~= nil then
      if isClear(details.garageKey) or details.garageKey == '' then
        fields.garageKey, fields.garageName = false, false
      else
        local key, resolved, err = garageKeyArg(details.garageKey)
        if not key then return fail(err) end
        fields.garageKey = key
        fields.garageName = NZ.Locations.keyName(key) or (resolved and resolved.location and resolved.location.name) or false
      end
    end
    if details.state ~= nil then
      if not STATES[details.state] then return fail(L('Invalid vehicle state')) end
      stateTarget = details.state
    end
    if details.nickname ~= nil then
      local nickname = type(details.nickname) == 'string' and safeText(details.nickname, 32) or nil
      if details.nickname ~= false and type(details.nickname) ~= 'string' then return fail(L('Invalid name')) end
      fields.nickname = nickname or false
    end
    if details.mileage ~= nil then
      local mileage = num(details.mileage, 0, MAX_MILEAGE, nil)
      if not mileage then return fail(L('Invalid mileage')) end
      fields.mileage = Utils.round(mileage, 2)
    end
    for _, key in ipairs({ 'fuel', 'engine', 'body' }) do
      if details[key] ~= nil then
        local value = num(details[key], 0, 100, nil)
        if not value then return fail(L('Fuel, engine and body must be between 0 and 100')) end
        fields[key] = Utils.round(value, 1)
      end
    end
    changed[#changed + 1] = 'details'
  end

  -- owner
  local owner = patch.owner
  local ownerChangedTo = nil
  if owner ~= nil then
    if type(owner) ~= 'table' or not OWNER_TYPES[owner.type] then return fail(L('Invalid owner')) end
    local identifier = owner.identifier ~= nil and identifierArg(owner.identifier) or nil
    if owner.identifier ~= nil and owner.identifier ~= '' and not identifier then return fail(L('Invalid identifier')) end
    if owner.type == 'player' then
      if not identifier then return fail(L('Enter the identifier of the new owner')) end
      if identifier ~= row.owner and not characterExists(identifier) then return fail(L('Character not found')) end
      fields.ownerType = 'player'
      if identifier ~= row.owner then
        fields.owner = identifier
        ownerChangedTo = identifier
      end
      if identifier ~= row.owner or row.ownerType ~= 'player' then
        ownerEvent = { identifier = identifier, name = charName(identifier), via = 'admin' }
      end
    else
      local kind = owner.type
      if kind == 'gang' and not NZ.Bridge.hasGangs then return fail(L('Gangs are not supported on this framework')) end
      local name = groupNameArg(kind == 'gang' and owner.gang or owner.job)
      if not name then return fail(kind == 'gang' and L('Select a gang') or L('Select a job')) end
      fields.ownerType = kind
      fields[kind] = name
      if identifier and identifier ~= row.owner then
        if not characterExists(identifier) then return fail(L('Character not found')) end
        fields.owner = identifier
        ownerChangedTo = identifier
      end
      if row.ownerType ~= kind or row[kind] ~= name or ownerChangedTo then
        ownerEvent = { identifier = ownerChangedTo or row.owner, name = jobLabels(kind)[name] or name, via = 'admin' }
      end
    end
    changed[#changed + 1] = 'owner'
  end

  -- props
  if patch.props ~= nil then
    if type(patch.props) ~= 'table' then return fail(L('Vehicle properties must be an object')) end
    local encoded, result = pcall(json.encode, patch.props)
    if not encoded or type(result) ~= 'string' then return fail(L('Vehicle properties could not be read')) end
    if #result > MAX_PROPS_BYTES then return fail(L('Vehicle properties are too large')) end
    local props = Utils.deepCopy(patch.props)
    props.plate = newPlate or plate
    props.model = rowHash(row)
    fields.props = props
    changed[#changed + 1] = 'props'
  end

  -- impound
  if patch.impound ~= nil then
    if isClear(patch.impound) then
      fields.impound = false
      if row.state == 'impounded' and not stateTarget then stateTarget = 'garaged' end
    else
      local info, err = impoundArg(src, patch.impound, row)
      if not info then return fail(err) end
      fields.impound = info
      stateTarget = 'impounded'
    end
    changed[#changed + 1] = 'impound'
  end
  if stateTarget == 'impounded' and fields.impound == nil and type(row.impound) ~= 'table' then
    return fail(L('Choose the impound for this vehicle'))
  end
  if stateTarget then fields.state = stateTarget end

  -- finance
  if patch.finance ~= nil then
    if isClear(patch.finance) then
      fields.finance = false
    else
      local finance, err = financeArg(patch.finance)
      if finance == nil then return fail(err) end
      fields.finance = finance
    end
    changed[#changed + 1] = 'finance'
  end

  -- blocked
  if patch.blocked ~= nil then
    if type(patch.blocked) ~= 'boolean' then return fail(L('Invalid request')) end
    fields.blocked = patch.blocked
    changed[#changed + 1] = 'blocked'
  end

  -- service history
  if patch.service ~= nil then
    local err
    service, err = serviceList(patch.service)
    if not service then return fail(err) end
    changed[#changed + 1] = 'service'
  end

  if #changed == 0 then return fail(L('Nothing to change')) end

  -- A vehicle sent back to a garage or the impound must not stay in the world.
  local entity = nil
  if (fields.state == 'garaged' or fields.state == 'impounded') and row.state ~= fields.state then
    entity = liveEntity(plate)
    if entity and occupied(entity) then return fail(L('Someone is using this vehicle')) end
  end

  -- apply
  if next(fields) ~= nil and not NZ.DB.updateVehicle(plate, fields) then
    return fail(L('Could not save the vehicle'))
  end
  if entity or fields.state == 'garaged' or fields.state == 'impounded' then
    -- The saved trailer it was towing out in the world goes back with it (no duplicate).
    if type(NZ.Vehicles.removeTrailerOf) == 'function' then pcall(NZ.Vehicles.removeTrailerOf, plate, row) end
  end
  if entity then
    if DoesEntityExist(entity) then DeleteEntity(entity) end
    forgetOut(plate)
  elseif fields.state == 'garaged' or fields.state == 'impounded' then
    forgetOut(plate)
  end

  if ownerChangedTo then
    NZ.DB.shares.clear(plate)
    if row.owner then NZ.DB.favourites.set(row.owner, plate, false) end
    local tracked = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
    if type(tracked) == 'table' then tracked.identifier = ownerChangedTo end
  end
  if ownerEvent then
    ownerEvent.at = os.time()
    NZ.DB.events.add(plate, 'owner', ownerEvent)
  end
  -- built-in car lock: keys cut for the old owner stop working now (before a plate change)
  local carLock = NZ.CarLock
  if (ownerChangedTo or ownerEvent) and type(carLock) == 'table' and type(carLock.enabled) == 'function'
    and type(carLock.rekey) == 'function' and carLock.enabled() then
    local okRekey, rekeyErr = pcall(carLock.rekey, plate, ownerChangedTo or row.owner)
    if not okRekey then lib.print.warn(('[nayzeee-garages] rekey of %s failed: %s'):format(plate, tostring(rekeyErr))) end
  end
  if service and not NZ.DB.events.replace(plate, 'service', service) then
    return fail(L('Could not save the service history'))
  end
  if newPlate and not NZ.DB.changePlate(plate, newPlate) then
    return fail(L('The plate could not be changed'))
  end

  log('admin.vehicle.update', src, {
    plate = plate,
    newPlate = newPlate,
    changed = changed,
    owner = ownerChangedTo,
    state = fields.state,
    garage = fields.garageKey or nil,
    blocked = fields.blocked,
    removedEntity = entity ~= nil,
  })

  local detail = vehicleDetail(newPlate or plate)
  if not detail then return fail(L('Vehicle not found')) end
  return ok(detail)
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local function register(name, ms, handler)
  local bucket = name:gsub('^nz:', '')
  lib.callback.register(name, Utils.safe(function(source, payload)
    local src = tonumber(source)
    if not src or src <= 0 or not NZ.Access.isAdmin(src) then
      log('security.admin', src, { callback = name })
      return fail(L('No permission'))
    end
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if not NZ.Access.rateLimit(src, bucket, ms) then
      return fail(L('Please wait a moment before trying again'))
    end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

-- {} -> AdminOpenData
register('nz:admin:refresh', 500, function()
  return ok(Admin.openData())
end)

-- { location } -> Location
register('nz:admin:location:save', 500, function(src, payload)
  local location = payload.location
  if type(location) ~= 'table' then return fail(L('Invalid location data')) end
  local id, previousAccess = nil, nil
  if location.id ~= nil then
    id = positiveId(location.id)
    local existing = id and NZ.Locations.get(id) or nil
    if not existing then return fail(L('Location not found')) end
    if existing.kind == 'private' and location.kind ~= 'private' and #groupsOfLocation(id) > 0 then
      return fail(L('Remove the owned garages of this location before changing its type'))
    end
    previousAccess = type(existing.access) == 'table' and Utils.deepCopy(existing.access) or {}
  end
  local saved, err = NZ.Locations.save(location, src)
  if not saved then return fail(err) end
  if id then
    local access = type(saved.access) == 'table' and saved.access or {}
    if saved.enabled == false then
      NZ.Interiors.closeWhere({ locationId = id }, L('This garage is closed'))
    elseif access.mode == 'quick' or access.interiorId ~= previousAccess.interiorId then
      NZ.Interiors.closeWhere({ locationId = id }, L('This garage interior was changed by an admin'))
    end
  end
  return ok(saved)
end)

-- { id } -> null
register('nz:admin:location:delete', 1000, function(src, payload)
  local id = positiveId(payload.id)
  local location = id and NZ.Locations.get(id) or nil
  if not location then return fail(L('Location not found')) end

  local groups = location.kind == 'private' and groupsOfLocation(id) or {}
  local parked = 0
  for _, group in ipairs(groups) do
    parked = parked + (tonumber(NZ.DB.countInGarage(Utils.key.group(group.id))) or 0)
  end
  if parked > 0 then
    return fail(L('{count} vehicles are still parked in garages of this location. Move them first.', { count = parked }))
  end

  local deleted, err = NZ.Locations.delete(id, src)
  if not deleted then return fail(err) end
  NZ.Interiors.closeWhere({ locationId = id }, L('This garage is no longer available'))

  if #groups > 0 then
    local affected = {}
    for _, group in ipairs(groups) do
      addMembersTo(affected, group.id)
      if type(group.owner) == 'string' then affected[group.owner] = true end
      if not NZ.DB.groups.delete(group.id) then
        lib.print.warn(('admin: could not delete group #%d of location #%d'):format(group.id, id))
      end
    end
    reloadPrivate(affected)
    log('admin.group.delete', src, { location = id, groups = #groups, reason = 'location deleted' })
  end
  return ok(nil)
end)

-- { id, enabled } -> null
register('nz:admin:location:toggle', 500, function(src, payload)
  local id = positiveId(payload.id)
  if not id then return fail(L('Location not found')) end
  if type(payload.enabled) ~= 'boolean' then return fail(L('Invalid request')) end
  local success, err = NZ.Locations.setEnabled(id, payload.enabled, src)
  if not success then return fail(err) end
  if not payload.enabled then NZ.Interiors.closeWhere({ locationId = id }, L('This garage is closed')) end
  return ok(nil)
end)

-- { source, json? } -> { imported, skipped }
register('nz:admin:location:import', 3000, function(src, payload)
  if type(payload.source) ~= 'string' or #payload.source > 64 then return fail(L('Unknown import source')) end
  if payload.json ~= nil and type(payload.json) ~= 'string' then return fail(L('The JSON could not be read')) end
  local result, err = NZ.Import.run(payload.source, payload.json, src)
  if not result then return fail(err) end
  log('admin.import', src, { source = payload.source, imported = result.imported, skipped = result.skipped })
  return ok(result)
end)

-- { locationId } -> GroupInfo[]
register('nz:admin:groups', 300, function(_, payload)
  local locationId = positiveId(payload.locationId)
  local location = locationId and NZ.Locations.get(locationId) or nil
  if not location then return fail(L('Location not found')) end
  local membersOf = {}
  for _, member in ipairs(NZ.DB.groups.allMembers() or {}) do
    membersOf[member.groupId] = membersOf[member.groupId] or {}
    table.insert(membersOf[member.groupId], member)
  end
  local list = {}
  for _, group in ipairs(groupsOfLocation(locationId)) do
    list[#list + 1] = groupInfo(group, membersOf[group.id] or {})
  end
  return ok(list)
end)

-- { group = { id?, locationId, label, owner } } -> GroupInfo
register('nz:admin:group:save', 500, function(src, payload)
  local data = payload.group
  if type(data) ~= 'table' then return fail(L('Invalid garage data')) end
  local owner = identifierArg(data.owner)
  if not owner then return fail(L('Enter the identifier of the owner')) end

  if data.id ~= nil then
    local id = positiveId(data.id)
    local group = id and findGroup(id) or nil
    if not group then return fail(L('Garage not found')) end
    local label = safeText(data.label, 60) or group.label
    local fields = { label = label }
    local previousOwner = group.owner
    if owner ~= previousOwner then
      if not characterExists(owner) then return fail(L('Character not found')) end
      fields.owner = owner
    end
    if not NZ.DB.groups.update(id, fields) then return fail(L('Could not save the garage')) end
    local affected = addMembersTo({ [owner] = true }, id)
    if fields.owner then
      NZ.DB.groups.setMember(id, owner, charName(owner), 'owner')
      if type(previousOwner) == 'string' and previousOwner ~= '' then
        NZ.DB.groups.setMember(id, previousOwner, charName(previousOwner), 'member')
        affected[previousOwner] = true
      end
      NZ.Interiors.closeWhere({ groupId = id }, L('The owner of this garage changed'))
    end
    reloadPrivate(affected)
    log('admin.group.update', src, {
      id = id, location = group.locationId, label = label, owner = fields.owner, previousOwner = fields.owner and previousOwner or nil,
    })
    return ok(groupInfo(findGroup(id) or { id = id, locationId = group.locationId, label = label, owner = owner, createdAt = group.createdAt }))
  end

  local locationId = positiveId(data.locationId)
  local location = locationId and NZ.Locations.get(locationId) or nil
  if not location or location.kind ~= 'private' then return fail(L('Select a private garage location')) end
  if not characterExists(owner) then return fail(L('Character not found')) end
  local maxCopies = tonumber(location.maxCopies) or 0
  if maxCopies > 0 and #groupsOfLocation(locationId) >= maxCopies then
    return fail(L('No copies of this garage are left'))
  end
  local label = safeText(data.label, 60) or location.name
  local id = positiveId(NZ.DB.groups.create(locationId, label, owner, 0))
  if not id then return fail(L('Could not save the garage')) end
  NZ.DB.groups.setMember(id, owner, charName(owner), 'owner')
  reloadPrivate({ [owner] = true })
  log('admin.group.create', src, { id = id, location = locationId, label = label, owner = owner })
  return ok(groupInfo(findGroup(id) or { id = id, locationId = locationId, label = label, owner = owner, createdAt = os.time() }))
end)

-- { id } -> null
register('nz:admin:group:delete', 1000, function(src, payload)
  local id = positiveId(payload.id)
  local group = id and findGroup(id) or nil
  if not group then return fail(L('Garage not found')) end
  local parked = tonumber(NZ.DB.countInGarage(Utils.key.group(id))) or 0
  if parked > 0 then
    return fail(L('{count} vehicles are still parked in this garage. Move them first.', { count = parked }))
  end
  local affected = addMembersTo({}, id)
  if type(group.owner) == 'string' then affected[group.owner] = true end
  if not NZ.DB.groups.delete(id) then return fail(L('Could not delete the garage')) end
  NZ.Interiors.closeWhere({ groupId = id }, L('This garage is no longer available'))
  reloadPrivate(affected)
  log('admin.group.delete', src, { id = id, location = group.locationId, label = group.label, owner = group.owner })
  return ok(nil)
end)

-- { groupId, identifier, role|null } -> GroupInfo  (role nil = remove the member)
register('nz:admin:group:member', 500, function(src, payload)
  local groupId = positiveId(payload.groupId)
  local group = groupId and findGroup(groupId) or nil
  if not group then return fail(L('Garage not found')) end
  local identifier = identifierArg(payload.identifier)
  if not identifier then return fail(L('Invalid identifier')) end
  local role = payload.role
  if role ~= nil and role ~= 'owner' and role ~= 'member' then return fail(L('Invalid role')) end

  local members = NZ.DB.groups.members(groupId) or {}
  local existing = nil
  for _, member in ipairs(members) do
    if member.identifier == identifier then existing = member end
  end
  local affected = addMembersTo({ [identifier] = true }, groupId)

  if role == nil then
    if identifier == group.owner then return fail(L('The owner cannot be removed. Choose a new owner first.')) end
    if not existing then return fail(L('This player is not a member of the garage')) end
    if not NZ.DB.groups.removeMember(groupId, identifier) then return fail(L('Could not save the garage')) end
    NZ.Interiors.closeWhere({ groupId = groupId, identifier = identifier }, L('You no longer have access to this garage'))
  else
    if not existing and not characterExists(identifier) then return fail(L('Character not found')) end
    local name = existing and memberName(existing) or charName(identifier)
    if role == 'owner' then
      if identifier ~= group.owner then
        if not NZ.DB.groups.update(groupId, { owner = identifier }) then return fail(L('Could not save the garage')) end
        if type(group.owner) == 'string' and group.owner ~= '' then
          NZ.DB.groups.setMember(groupId, group.owner, charName(group.owner), 'member')
          affected[group.owner] = true
        end
        NZ.Interiors.closeWhere({ groupId = groupId }, L('The owner of this garage changed'))
      end
      if not NZ.DB.groups.setMember(groupId, identifier, name, 'owner') then return fail(L('Could not save the garage')) end
    else
      if identifier == group.owner then return fail(L('Choose a new owner before changing this role')) end
      if not NZ.DB.groups.setMember(groupId, identifier, name, 'member') then return fail(L('Could not save the garage')) end
    end
  end

  reloadPrivate(affected)
  log('admin.group.member', src, { group = groupId, identifier = identifier, role = role or 'removed' })
  local fresh = findGroup(groupId)
  if not fresh then return fail(L('Garage not found')) end
  return ok(groupInfo(fresh))
end)

-- { id } -> null
register('nz:admin:interior:delete', 1000, function(src, payload)
  local id = positiveId(payload.id)
  if not id then return fail(L('Interior not found')) end
  local success, err = NZ.Interiors.delete(id, src)
  if not success then return fail(err) end
  return ok(nil)
end)

-- { id, enabled } -> null
register('nz:admin:interior:toggle', 500, function(src, payload)
  local id = positiveId(payload.id)
  if not id then return fail(L('Interior not found')) end
  if type(payload.enabled) ~= 'boolean' then return fail(L('Invalid request')) end
  local success, err = NZ.Interiors.setEnabled(id, payload.enabled, src)
  if not success then return fail(err) end
  return ok(nil)
end)

-- { settings } -> Settings
register('nz:admin:settings:save', 1000, function(src, payload)
  if type(payload.settings) ~= 'table' then return fail(L('Invalid settings')) end
  local saved, persisted = NZ.Settings.save(payload.settings, src)
  if type(saved) ~= 'table' then
    return fail(type(persisted) == 'string' and persisted or L('Invalid settings'))
  end
  if persisted ~= true then
    TriggerClientEvent('nz:client:notify', src, {
      type = 'warning',
      message = L('The settings are active but could not be saved to the database'),
    })
  end
  return ok(saved)
end)

-- { query, page } -> Paged<PlayerSearchRow>
register('nz:admin:players:search', 300, function(_, payload)
  local query = type(payload.query) == 'string' and Utils.trim((payload.query:gsub('%c', ''))) or ''
  if #query > 64 then query = query:sub(1, 64) end
  local page = num(payload.page, 1, 100000, 1, true)
  local offset = (page - 1) * PAGE_SIZE

  -- Owners of matching plates are listed first.
  local plateOwners, platesOf = {}, {}
  local upper = query:upper()
  if #upper >= 2 and #upper <= 8 and upper:match('^[A-Z0-9 ]+$') then
    for _, hit in ipairs(NZ.DB.searchPlates(upper, 50) or {}) do
      local owner = type(hit) == 'table' and hit.owner or nil
      if type(owner) == 'string' and owner ~= '' then
        if not platesOf[owner] then
          platesOf[owner] = {}
          plateOwners[#plateOwners + 1] = owner
        end
        table.insert(platesOf[owner], hit.plate)
      end
    end
  end

  local rows = {}
  local prefix = #plateOwners
  for i = offset + 1, math.min(prefix, offset + PAGE_SIZE) do
    local identifier = plateOwners[i]
    rows[#rows + 1] = { identifier = identifier, name = charName(identifier) }
  end

  local need = PAGE_SIZE - #rows
  local charOffset = math.max(0, offset - prefix)
  local found, charTotal = {}, 0
  if type(NZ.Bridge.searchCharacters) == 'function' then
    local success, list, total = pcall(NZ.Bridge.searchCharacters, query, math.max(need, 1), charOffset)
    if success and type(list) == 'table' then
      found = list
      charTotal = tonumber(total) or #list
    end
  end
  if need > 0 then
    for _, character in ipairs(found) do
      if #rows >= PAGE_SIZE then break end
      if type(character) == 'table' and type(character.identifier) == 'string' and not platesOf[character.identifier] then
        rows[#rows + 1] = { identifier = character.identifier, name = character.name }
      end
    end
  end

  for i, row in ipairs(rows) do
    rows[i] = {
      identifier = row.identifier,
      name = (type(row.name) == 'string' and row.name ~= '') and row.name or charName(row.identifier),
      online = isPlayerOnline(row.identifier),
      matchedPlates = platesOf[row.identifier] or {},
    }
  end

  return ok({ rows = rows, total = prefix + charTotal, page = page, pageSize = PAGE_SIZE })
end)

-- { identifier } -> { player, vehicles = AdminVehicleRow[] }
register('nz:admin:players:vehicles', 300, function(_, payload)
  local identifier = identifierArg(payload.identifier)
  if not identifier then return fail(L('Invalid identifier')) end
  local names = {}
  local vehicles = {}
  for _, row in ipairs(NZ.DB.getVehiclesByOwner(identifier) or {}) do
    vehicles[#vehicles + 1] = vehicleRow(row, names)
  end
  table.sort(vehicles, function(a, b) return a.plate < b.plate end)
  return ok({
    player = { identifier = identifier, name = charName(identifier), online = isPlayerOnline(identifier) },
    vehicles = vehicles,
  })
end)

-- { plate } -> AdminVehicleDetail
register('nz:admin:vehicle:get', 250, function(_, payload)
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  local detail = vehicleDetail(plate)
  if not detail then return fail(L('Vehicle not found')) end
  return ok(detail)
end)

-- { identifier, model, plate|'', garageKey } -> AdminVehicleRow
-- { plate, page } -> Paged<VehicleActivity>
local ACTIVITY_PAGE = 25
register('nz:admin:vehicle:activity', 250, function(_, payload)
  local plate = Utils.plate(payload.plate)
  if not plate then return fail(L('Vehicle not found')) end
  local page = math.max(1, math.floor(tonumber(payload.page) or 1))
  local result = NZ.DB.logs.forPlate(plate, ACTIVITY_PAGE, (page - 1) * ACTIVITY_PAGE)
  local names, rows = {}, {}
  for _, row in ipairs(result.rows) do
    local actorName = nil
    if row.identifier then
      if names[row.identifier] == nil then names[row.identifier] = charName(row.identifier) end
      actorName = names[row.identifier]
    end
    rows[#rows + 1] = {
      id = row.id, event = row.event, at = row.at,
      actor = row.identifier, actorName = actorName, data = row.data,
    }
  end
  return ok({ rows = rows, total = result.total, page = page, pageSize = ACTIVITY_PAGE })
end)

register('nz:admin:vehicle:assign', 1000, function(src, payload)
  local identifier = identifierArg(payload.identifier)
  if not identifier then return fail(L('Invalid identifier')) end
  local model = modelArg(payload.model)
  if not model then return fail(L('Enter a valid model name (letters, digits and underscores)')) end
  local garageKey, resolved, keyErr = garageKeyArg(payload.garageKey)
  if not garageKey then return fail(keyErr) end
  if not characterExists(identifier) then return fail(L('Character not found')) end

  local plate
  local requested = type(payload.plate) == 'string' and Utils.trim(payload.plate) or ''
  if requested == '' then
    plate = uniquePlate()
    if not plate then return fail(L('Could not generate a free plate, try again')) end
  else
    plate = plateArg(requested)
    if not plate then return fail(L('Plates have 1 to 8 letters, digits or spaces')) end
    if NZ.DB.plateExists(plate) then return fail(L('This plate is already in use')) end
  end

  local hash = signedHash(joaat(model))
  local location = resolved and resolved.location or nil
  local vehicleType = type(location) == 'table' and Utils.vehicleTypes[location.vehicleType] and location.vehicleType or 'car'
  local garageName = NZ.Locations.keyName(garageKey) or (type(location) == 'table' and location.name) or nil

  local inserted = NZ.DB.insertVehicle({
    owner = identifier,
    model = model,
    hash = hash,
    plate = plate,
    props = { plate = plate, model = hash },
    garageKey = garageKey,
    garageName = garageName,
    state = 'garaged',
    vehicleType = vehicleType,
    ownerType = 'player',
  })
  if not inserted then return fail(L('Could not add the vehicle')) end
  NZ.DB.events.add(plate, 'owner', { identifier = identifier, name = charName(identifier), via = 'admin', at = os.time() })
  log('admin.vehicle.assign', src, { plate = plate, model = model, identifier = identifier, garage = garageKey })

  local row = NZ.DB.getVehicle(plate)
  if row then return ok(vehicleRow(row, {})) end
  return ok({
    plate = plate, model = model, hash = hash, vehicleType = vehicleType, garageKey = garageKey,
    garageName = garageName, state = 'garaged', financed = false, fuel = 100, engine = 100, body = 100, blocked = false,
  })
end)

-- { plate, patch } -> AdminVehicleDetail
register('nz:admin:vehicle:update', 500, function(src, payload)
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  if type(payload.patch) ~= 'table' then return fail(L('Nothing to change')) end
  return withLock(plate, applyPatch, src, plate, payload.patch)
end)

-- { plate } -> null
register('nz:admin:vehicle:delete', 1000, function(src, payload)
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  return withLock(plate, function()
    local row = NZ.DB.getVehicle(plate)
    if not row then return fail(L('Vehicle not found')) end
    local entity = liveEntity(row.plate)
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    forgetOut(row.plate)
    if not NZ.DB.deleteVehicle(row.plate) then return fail(L('Could not delete the vehicle')) end
    log('admin.vehicle.delete', src, {
      plate = row.plate, owner = row.owner, model = row.model, hash = row.hash, state = row.state,
      garage = row.garageKey, removedEntity = entity ~= nil,
    })
    return ok(nil)
  end)
end)
