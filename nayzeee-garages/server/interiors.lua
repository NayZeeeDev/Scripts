--[[
  nayzeee-garages — garage interiors (NZ.Interiors), server side.

  Interior definitions (table `nz_interiors`, docs/ARCHITECTURE.md §4.3) are cached and
  normalized here. An interior made from an IPL profile without vehicle positions uses the
  profile's preset positions (Config.IplProfiles[key].presets).

  Players who "Go inside" a garage are placed in a private routing bucket per instance
  (§7.7). Config.InteriorOptions.instances:
  - 'player' (default): one instance per player and garage, showing that player's own
    vehicles (fleet garages: the fleet); no invitations.
  - 'shared': one instance per garage key and owner, or one per private group when the
    group stores its vehicles together; owners and members invite nearby players (guests)
    and remove guests.
  Members browse pages of display vehicles and drive one straight out. Purchasable private
  garages can be toured in a temporary guest instance.

  Callbacks: nz:garage:goInside, nz:forSale:tour, nz:interior:page, nz:interior:driveOut,
  nz:interior:leave, nz:interior:invite, nz:interior:inviteRespond, nz:interior:kick,
  nz:interior:players, nz:creator:save.
]]

local Interiors = NZ.Interiors
local Utils = NZ.Utils

---@type table<string, table> instanceKey -> instance (see §5.6)
Interiors.instances = Interiors.instances or {}

local cache = {}          -- [interiorId] = Interior
local playerKey = {}      -- [src] = instanceKey
local joinedAt = {}       -- [src] = os.time() the player was put in its instance
local awayStrikes = {}    -- [src] = consecutive sweeps that found the player outside
local bucketOwner = {}    -- [bucket] = instanceKey
local invites = {}        -- [inviteId] = { from, to, key, expires, garageName }
local nextInviteId = 0

local MAX_NAME = 60
local MAX_SLOTS = 60
local MAX_CAMERA_POINTS = 12
local MAX_MEMBERS = 32
local TOUR_SECONDS = 120
local INVITE_SECONDS = 60
local INVITE_RANGE = 30.0
local SPAWN_CLEARANCE = 3.0
local MAX_PLATE_LENGTH = 16

local ROLE_ORDER = { owner = 1, member = 2, guest = 3 }
-- Client hint only: NZ.Vehicles.retrieve derives the type it spawns with server-side.
local ENTITY_TYPES = {
  automobile = true, bike = true, boat = true, heli = true,
  plane = true, submarine = true, trailer = true,
}

---------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then lib.print.warn(('interiors: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function setting(path, default)
  if type(NZ.Settings.get) ~= 'function' then return default end
  local value = NZ.Settings.get(path, default)
  if value == nil then return default end
  return value
end

local function maxDistance()
  return tonumber(setting('garages.maxDistance', 25.0)) or 25.0
end

local function notify(src, kind, message)
  TriggerClientEvent('nz:client:notify', src, { type = kind, message = message })
end

--- Clean text and drop a truncated trailing UTF-8 sequence.
local function safeText(value, maxLen)
  local s = Utils.cleanText(value, maxLen)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

local function bool(value, default)
  if type(value) == 'boolean' then return value end
  if value == 1 then return true end
  if value == 0 then return false end
  return default
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

--- Positive integer (database ids, server ids) or nil. Never clamps.
local function positiveId(value, max)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not finite(n) or n < 1 or n > (max or 2147483647) or n ~= math.floor(n) then return nil end
  return math.tointeger(n)
end

local function coordOk(n, limit)
  return finite(n) and n > -limit and n < limit
end

local function vec3(value)
  local v = Utils.v3(value)
  if not v then return nil end
  if not (coordOk(v.x, 20000) and coordOk(v.y, 20000) and coordOk(v.z, 5000)) then return nil end
  return { x = Utils.round(v.x, 3), y = Utils.round(v.y, 3), z = Utils.round(v.z, 3) }
end

local function vec4(value)
  local v = Utils.v4(value)
  if not v then return nil end
  if not (coordOk(v.x, 20000) and coordOk(v.y, 20000) and coordOk(v.z, 5000)) then return nil end
  local w = coordOk(v.w, 1e6) and v.w or 0.0
  w = w % 360.0
  return { x = Utils.round(v.x, 3), y = Utils.round(v.y, 3), z = Utils.round(v.z, 3), w = Utils.round(w, 2) }
end

local function vec4List(list, maxCount)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, item in ipairs(list) do
    if #out >= maxCount then break end
    local v = vec4(item)
    if v then out[#out + 1] = v end
  end
  return out
end

local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function percent(value, default)
  local n = tonumber(value)
  if not finite(n) then return default end
  return Utils.round(Utils.clamp(n, 0, 100), 1)
end

--- GTA model hashes are signed 32-bit integers.
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

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local success, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if success and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function online(src)
  return type(src) == 'number' and src > 0 and GetPlayerName(src) ~= nil
end

local function nameOf(src)
  if type(NZ.Bridge.getName) == 'function' then
    local success, name = pcall(NZ.Bridge.getName, src)
    if success and type(name) == 'string' and name ~= '' then return name end
  end
  return GetPlayerName(src) or ('#' .. tostring(src))
end

local function inVehicle(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  return GetVehiclePedIsIn(ped, false) ~= 0
end

--- Dead, downed, cuffed or escorted players cannot slip into a private routing bucket.
local function incapacitated(src)
  return type(NZ.Vehicles.incapacitated) == 'function' and NZ.Vehicles.incapacitated(src) == true
end

local function setBucket(src, bucket)
  if not online(src) then return end
  local success, err = pcall(SetPlayerRoutingBucket, src, bucket)
  if not success then lib.print.warn(('interiors: could not set routing bucket of %s: %s'):format(src, tostring(err))) end
end

local function currentBucket(src)
  local success, bucket = pcall(GetPlayerRoutingBucket, src)
  if success then return tonumber(bucket) or 0 end
  return 0
end

--- 'job' | 'gang' and its name when the row is a fleet vehicle.
local function fleetOf(row)
  if row.ownerType == 'gang' and row.gang then return 'gang', row.gang end
  if row.ownerType == 'job' and row.job then return 'job', row.job end
  return nil, nil
end

---------------------------------------------------------------------------------------
-- Normalization (types.ts Interior)
---------------------------------------------------------------------------------------

local function profileOf(key)
  if type(key) ~= 'string' or type(Config.IplProfiles) ~= 'table' then return nil end
  local profile = Config.IplProfiles[key]
  if type(profile) ~= 'table' then return nil end
  return profile
end

--- Instance mode (Config.InteriorOptions.instances): 'player' (default) or 'shared'.
---@return 'player'|'shared'
function Interiors.instanceMode()
  local opts = type(Config.InteriorOptions) == 'table' and Config.InteriorOptions or {}
  return opts.instances == 'shared' and 'shared' or 'player'
end

--- Preset vehicle positions of a profile ({x,y,z,w} copies, [] when it has none).
---@param key string|nil
---@return table[]
function Interiors.profilePresets(key)
  local profile = profileOf(key)
  if not profile or type(profile.presets) ~= 'table' then return {} end
  return vec4List(profile.presets, MAX_SLOTS)
end

local presetCache = {}   -- [profileKey] = { {x,y,z,w}, ... }

--- Vehicle positions players use: the interior's own, else its profile's presets.
---@return table[] (read-only)
local function slotsOf(interior)
  if type(interior) ~= 'table' then return {} end
  if type(interior.slots) == 'table' and #interior.slots > 0 then return interior.slots end
  local key = interior.profile
  if type(key) ~= 'string' then return {} end
  if not presetCache[key] then presetCache[key] = Interiors.profilePresets(key) end
  return presetCache[key]
end

--- True when players can use the interior: it has vehicle positions of its own, or its
--- IPL profile has presets (an older interior saved before presets existed).
---@param interior table|nil
---@return boolean
function Interiors.hasSlots(interior)
  return #slotsOf(interior) > 0
end

--- Option values for the keys the profile defines (unknown keys / values are dropped).
local function profileOptions(profile, raw)
  local out = {}
  if type(profile) ~= 'table' or type(profile.options) ~= 'table' then return out end
  raw = type(raw) == 'table' and raw or {}
  for _, def in ipairs(profile.options) do
    if type(def) == 'table' and type(def.key) == 'string' and type(def.choices) == 'table' then
      local valid, first = {}, nil
      for _, choice in ipairs(def.choices) do
        if type(choice) == 'table' and type(choice.value) == 'string' then
          valid[choice.value] = true
          first = first or choice.value
        end
      end
      local value = raw[def.key]
      if type(value) ~= 'string' or not valid[value] then
        value = (type(def.default) == 'string' and valid[def.default]) and def.default or first
      end
      if value then out[def.key] = value end
    end
  end
  return out
end

local function angle(value)
  local n = tonumber(value)
  if not finite(n) then return 0.0 end
  return Utils.round(((n + 180.0) % 360.0) - 180.0, 2)
end

local function cameraPoint(point)
  if type(point) ~= 'table' then return nil end
  local coords = vec3(point.coords)
  if not coords then return nil end
  local rot = type(point.rot) == 'table' and point.rot or {}
  local function axis(name, index)
    local v = rot[name]
    if v == nil then v = rot[index] end
    return angle(v)
  end
  return {
    coords = coords,
    rot = { x = axis('x', 1), y = axis('y', 2), z = axis('z', 3) },
    fov = Utils.round(num(point.fov, 1.0, 130.0, 50.0), 1),
  }
end

local function cutsceneConfig(value)
  value = type(value) == 'table' and value or {}
  local points = {}
  if type(value.points) == 'table' then
    for _, point in ipairs(value.points) do
      if #points >= MAX_CAMERA_POINTS then break end
      local clean = cameraPoint(point)
      if clean then points[#points + 1] = clean end
    end
  end
  return {
    enabled = bool(value.enabled, false) and #points > 0,
    transition = num(value.transition, 500, 15000, 3000, true),
    returnTime = num(value.returnTime, 0, 10000, 1000, true),
    points = points,
  }
end

--- Build a complete, sanitized Interior (types.ts Interior).
---@param raw table untrusted interior table
---@return table|nil interior, string|nil error (translated)
function Interiors.normalize(raw)
  if type(raw) ~= 'table' then return nil, L('Invalid interior data') end
  local name = safeText(raw.name, MAX_NAME)
  if not name then return nil, L('A name is required') end

  local profileKey = profileOf(raw.profile) and raw.profile or nil
  local profile = profileOf(profileKey)

  local entry = vec4(raw.entry)
  if not entry and profile then entry = vec4(profile.coords) end
  if not entry then return nil, L('Set the entry point of the interior first') end

  local id = positiveId(raw.id)
  local slots = vec4List(raw.slots, MAX_SLOTS)
  -- A new interior from a profile starts with the profile's vehicle positions.
  if not id and #slots == 0 and profileKey then slots = Interiors.profilePresets(profileKey) end

  return {
    id = id,
    name = name,
    enabled = bool(raw.enabled, true),
    profile = profileKey,
    options = profileOptions(profile, raw.options),
    entry = entry,
    gtaInteriorId = positiveId(raw.gtaInteriorId),
    cutscene = cutsceneConfig(raw.cutscene),
    slots = slots,
    exit = vec4(raw.exit),
  }
end

--- Everything except the columns goes into the JSON `data` column.
local function dataOf(interior)
  local data = {}
  for k, v in pairs(interior) do
    if k ~= 'id' and k ~= 'name' and k ~= 'enabled' then data[k] = v end
  end
  return data
end

--- True when players inside an instance would see a different room / slot layout.
local function layoutChanged(old, new)
  if new.enabled == false then return true end
  return old.profile ~= new.profile
    or not deepEqual(old.options, new.options)
    or not deepEqual(old.entry, new.entry)
    or not deepEqual(old.slots, new.slots)
    or not deepEqual(old.exit, new.exit)
end

---------------------------------------------------------------------------------------
-- Instance helpers
---------------------------------------------------------------------------------------

local function pageSizeOf(interior)
  return math.max(1, #slotsOf(interior))
end

local function memberCount(inst)
  local n = 0
  for _ in pairs(inst.members) do n = n + 1 end
  return n
end

local function hasHost(inst)
  for _, role in pairs(inst.members) do
    if role ~= 'guest' then return true end
  end
  return false
end

--- Outside point players return to: first open point of the location, facing the first
--- parking spot when there is one.
local function returnPointOf(location)
  if type(location) ~= 'table' or type(location.openPoints) ~= 'table' then return nil end
  for _, point in ipairs(location.openPoints) do
    local coords = Utils.v3(type(point) == 'table' and point.coords or point)
    if coords then
      local heading = 0.0
      local spawn = type(location.spawnPoints) == 'table' and Utils.v3(location.spawnPoints[1]) or nil
      if spawn then
        local dx, dy = spawn.x - coords.x, spawn.y - coords.y
        if dx ~= 0 or dy ~= 0 then heading = Utils.round(math.deg(math.atan(-dx, dy)) % 360.0, 2) end
      end
      return { x = coords.x, y = coords.y, z = coords.z, w = heading }
    end
  end
  return nil
end

local function returnToOf(inst)
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  return returnPointOf(location) or inst.returnTo
end

local function garageNameOf(inst, location)
  if inst.garageKey and not inst.tour then
    local name = NZ.Locations.keyName(inst.garageKey)
    if name then return name end
  end
  return type(location) == 'table' and location.name or L('Garage')
end

--- Session-like table used for drive permission checks of an instance member.
local function memberSession(inst, location)
  location = location or (inst.locationId and NZ.Locations.get(inst.locationId)) or nil
  if type(location) ~= 'table' or not inst.garageKey then return nil end
  return {
    garageKey = inst.garageKey,
    location = location,
    locationId = location.id,
    groupId = inst.groupId,
    fromInterior = true,
  }
end

local function allocateBucket(key)
  local base = math.floor(tonumber(Config.BucketBase) or 7400)
  local n = 1
  while bucketOwner[base + n] do n = n + 1 end
  local bucket = base + n
  bucketOwner[bucket] = key
  -- No ambient population. Entity lockdown follows the server-wide setting: display
  -- vehicles are local, and forcing 'strict' / 'relaxed' would block other resources'
  -- networked props (phones, emotes, attachments) for players inside the garage.
  SetRoutingBucketPopulationEnabled(bucket, false)
  local lockdown = GetConvar('sv_entityLockdown', 'inactive')
  if lockdown ~= 'strict' and lockdown ~= 'relaxed' then lockdown = 'inactive' end
  SetRoutingBucketEntityLockdownMode(bucket, lockdown)
  return bucket
end

local function createInstance(key, fields)
  local inst = {
    bucket = allocateBucket(key),
    garageKey = fields.garageKey,
    ownerIdentifier = fields.ownerIdentifier,
    groupId = fields.groupId,
    interiorId = fields.interiorId,
    locationId = fields.locationId,
    shared = fields.shared == true,
    fleet = fields.fleet == true,
    private = fields.private == true,  -- per-player instance: nobody else can join
    tour = fields.tour == true,
    page = 1,
    members = {},
    names = {},
    identifiers = {},
    pending = 0,
    closed = false,
    returnTo = fields.returnTo,
    createdAt = os.time(),
  }
  Interiors.instances[key] = inst
  Utils.debug('interior instance created', key, inst.bucket)
  return inst
end

--- Free the bucket and forget the instance (members must already be gone).
local function release(key, inst)
  if Interiors.instances[key] == inst then Interiors.instances[key] = nil end
  if bucketOwner[inst.bucket] == key then bucketOwner[inst.bucket] = nil end
  for id, invite in pairs(invites) do
    if invite.key == key then invites[id] = nil end
  end
  Utils.debug('interior instance released', key, inst.bucket)
end

local function attach(src, key, inst, role)
  inst.members[src] = role
  inst.names[src] = nameOf(src)
  inst.identifiers[src] = identifierOf(src)
  playerKey[src] = key
  joinedAt[src] = os.time()
  awayStrikes[src] = nil
  setBucket(src, inst.bucket)
end

--- Remove a player from its instance and put it back in the public bucket.
--- Does not release the instance (see settle).
---@return string|nil key, table|nil instance, string|nil role
local function detach(src)
  local key = playerKey[src]
  if not key then return nil, nil, nil end
  playerKey[src] = nil
  joinedAt[src] = nil
  awayStrikes[src] = nil
  local inst = Interiors.instances[key]
  local role = nil
  if inst then
    role = inst.members[src]
    inst.members[src] = nil
    inst.names[src] = nil
    inst.identifiers[src] = nil
  end
  setBucket(src, 0)
  return key, inst, role
end

---------------------------------------------------------------------------------------
-- Instance content (display vehicles, pages, members)
---------------------------------------------------------------------------------------

--- Garaged vehicles shown in the instance, sorted by plate.
local function instanceRows(inst)
  if inst.tour or not inst.garageKey then return {} end
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  local rows = {}

  if inst.shared then
    for _, row in ipairs(NZ.DB.getVehiclesInGarage(inst.garageKey) or {}) do
      if row.state == 'garaged' then rows[#rows + 1] = row end
    end
  elseif inst.fleet then
    local served = {}
    local ownerKind = type(location) == 'table' and location.owner == 'gang' and 'gang' or 'job'
    for _, rule in ipairs(type(location) == 'table' and type(location.jobs) == 'table' and location.jobs or {}) do
      if type(rule) == 'table' and type(rule.name) == 'string' then served[rule.name] = true end
    end
    for _, row in ipairs(NZ.DB.getVehiclesInGarage(inst.garageKey) or {}) do
      local kind, name = fleetOf(row)
      if row.state == 'garaged' and kind == ownerKind and served[name] then rows[#rows + 1] = row end
    end
  elseif inst.ownerIdentifier then
    for _, row in ipairs(NZ.DB.getVehiclesByOwner(inst.ownerIdentifier) or {}) do
      if row.state == 'garaged' and row.garageKey == inst.garageKey then rows[#rows + 1] = row end
    end
  end

  table.sort(rows, function(a, b) return tostring(a.plate) < tostring(b.plate) end)
  return rows
end

--- Clamp the instance page to the available pages. Returns pageSize, pages.
local function clampPage(inst, total, interior)
  local size = pageSizeOf(interior)
  local pages = math.max(1, math.ceil(total / size))
  local page = math.floor(tonumber(inst.page) or 1)
  if page > pages then page = pages end
  if page < 1 then page = 1 end
  inst.page = page
  return size, pages
end

local function jobLabel(ctx, kind, name)
  if not ctx.labels then
    ctx.labels = { job = {}, gang = {} }
    local function fill(target, getter)
      if type(getter) ~= 'function' then return end
      local success, list = pcall(getter)
      if not success or type(list) ~= 'table' then return end
      for _, entry in ipairs(list) do
        if type(entry) == 'table' and type(entry.name) == 'string' then
          target[entry.name] = type(entry.label) == 'string' and entry.label or entry.name
        end
      end
    end
    fill(ctx.labels.job, NZ.Bridge.getJobs)
    if NZ.Bridge.hasGangs then fill(ctx.labels.gang, NZ.Bridge.getGangs) end
  end
  return (ctx.labels[kind] and ctx.labels[kind][name]) or name
end

local function ownerNameOf(row, ctx)
  local kind, name = fleetOf(row)
  if kind then return jobLabel(ctx, kind, name) end
  if not row.owner then return '' end
  local cached = ctx.names[row.owner]
  if cached == nil then
    local success, res = pcall(NZ.Bridge.getCharacterName, row.owner)
    cached = success and type(res) == 'string' and res or ''
    ctx.names[row.owner] = cached
  end
  return cached
end

local function displayVehicle(row, slot, canDrive, ctx)
  return {
    slot = slot,
    plate = row.plate,
    hash = rowHash(row),
    model = row.model or '',
    vehicleType = Utils.vehicleTypes[row.vehicleType] and row.vehicleType or 'car',
    nickname = (type(row.nickname) == 'string' and row.nickname ~= '') and row.nickname or nil,
    props = type(row.props) == 'table' and row.props or {},
    damage = ctx.withDamage and type(row.damage) == 'table' and row.damage or nil,
    fuel = percent(row.fuel, 100),
    engine = percent(row.engine, 100),
    body = percent(row.body, 100),
    mileage = Utils.round(tonumber(row.mileage) or 0, 1),
    ownerName = ownerNameOf(row, ctx),
    canDrive = canDrive == true,
  }
end

local function newViewContext(inst)
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  return {
    location = location,
    session = memberSession(inst, location),
    names = {},
    withDamage = setting('vehicles.saveDamage', true) == true,
  }
end

--- Display vehicles of the current page as seen by one member.
local function vehiclesFor(inst, src, role, rows, size, ctx)
  local list = {}
  local first = (inst.page - 1) * size
  local session = (role ~= 'guest' and not inst.tour) and ctx.session or nil
  local opts = nil
  if session and type(NZ.Vehicles.newContext) == 'function' then
    local success, driveCtx = pcall(NZ.Vehicles.newContext, src, session, inst.identifiers[src])
    if success and type(driveCtx) == 'table' then opts = { cache = driveCtx } end
  end
  for i = 1, size do
    local row = rows[first + i]
    if not row then break end
    local canDrive = false
    if session and type(NZ.Vehicles.canDrive) == 'function' then
      local success, allowed = pcall(NZ.Vehicles.canDrive, src, row, session, opts)
      canDrive = success and allowed == true
    end
    list[#list + 1] = displayVehicle(row, i, canDrive, ctx)
  end
  return list
end

local function membersOf(inst)
  local list = {}
  for member, role in pairs(inst.members) do
    list[#list + 1] = { serverId = member, name = inst.names[member] or nameOf(member), role = role, you = false }
  end
  table.sort(list, function(a, b)
    local ra, rb = ROLE_ORDER[a.role] or 9, ROLE_ORDER[b.role] or 9
    if ra ~= rb then return ra < rb end
    return a.serverId < b.serverId
  end)
  return list
end

--- Owners and members of a shared instance may invite players (never on a tour).
local function canInvite(inst, role)
  return role ~= 'guest' and not inst.tour and not inst.private
end

--- 'nz:client:interior:sync' payload for one member.
local function syncView(inst, src, rows, size, pages, ctx, members)
  local role = inst.members[src] or 'guest'
  return {
    vehicles = vehiclesFor(inst, src, role, rows, size, ctx),
    page = inst.page,
    pages = pages,
    members = members,
    role = role,
    canInvite = canInvite(inst, role),
    total = #rows,
  }
end

--- InteriorEnterData (§7.7) for one member.
local function enterData(key, inst, src, interior, rows)
  rows = rows or instanceRows(inst)
  local ctx = newViewContext(inst)
  local size, pages = clampPage(inst, #rows, interior)
  local role = inst.members[src] or 'guest'
  local view = Utils.deepCopy(interior)
  view.slots = Utils.deepCopy(slotsOf(interior))
  return {
    instanceKey = key,
    interior = view,
    garageName = garageNameOf(inst, ctx.location),
    garageKey = inst.garageKey,
    locationId = inst.locationId,
    page = inst.page,
    pages = pages,
    slots = size,
    pageSize = size,
    total = #rows,
    vehicles = vehiclesFor(inst, src, role, rows, size, ctx),
    members = membersOf(inst),
    role = role,
    canInvite = canInvite(inst, role),
    returnTo = returnToOf(inst),
    tour = inst.tour,
    tourSeconds = inst.tour and TOUR_SECONDS or nil,
  }
end

--- Send the current vehicle list / page / members to every member (except `skip`).
local function broadcast(key, rows, skip)
  local inst = Interiors.instances[key]
  if not inst or next(inst.members) == nil then return end
  local interior = cache[inst.interiorId]
  rows = rows or instanceRows(inst)
  local size, pages = clampPage(inst, #rows, interior)
  local ctx = newViewContext(inst)
  local members = membersOf(inst)
  for member in pairs(inst.members) do
    if member ~= skip then
      TriggerClientEvent('nz:client:interior:sync', member, syncView(inst, member, rows, size, pages, ctx, members))
    end
  end
end

--- After someone left: release an empty instance, send remaining guests out when no host
--- is left, otherwise update the remaining members.
local function settle(key)
  local inst = Interiors.instances[key]
  if not inst then return end
  local busy = (inst.pending or 0) > 0

  if next(inst.members) == nil then
    if not busy then release(key, inst) end
    return
  end

  if not inst.tour and not busy and not hasHost(inst) then
    local guests = {}
    for member in pairs(inst.members) do guests[#guests + 1] = member end
    local returnTo = returnToOf(inst)
    for _, member in ipairs(guests) do
      detach(member)
      TriggerClientEvent('nz:client:interior:kicked', member, { returnTo = returnTo })
      notify(member, 'info', L('The garage owner left, you were taken outside'))
    end
    release(key, inst)
    log('interior.close', nil, { instance = key, reason = 'host left', guests = #guests })
    return
  end

  broadcast(key)
end

--- Take a player out of its instance and tell its client.
local function kickOut(src, returnTo, message)
  if not playerKey[src] then return false end
  Interiors.leave(src)
  TriggerClientEvent('nz:client:interior:kicked', src, { returnTo = returnTo })
  if message then notify(src, 'warning', message) end
  return true
end

---------------------------------------------------------------------------------------
-- Interior definitions
---------------------------------------------------------------------------------------

--- Load (or reload) every interior from the database into the cache.
function Interiors.load()
  local rows = NZ.DB.interiors.all()
  local fresh, loaded, skipped = {}, 0, 0
  for _, row in ipairs(type(rows) == 'table' and rows or {}) do
    local raw = row.data
    if type(raw) == 'string' then
      local success, decoded = pcall(json.decode, raw)
      raw = success and decoded or nil
    end
    raw = type(raw) == 'table' and Utils.deepCopy(raw) or {}
    raw.id, raw.name, raw.enabled = row.id, row.name, row.enabled
    local interior, err = Interiors.normalize(raw)
    if interior and interior.id then
      fresh[interior.id] = interior
      loaded = loaded + 1
    else
      skipped = skipped + 1
      lib.print.warn(('interiors: skipped interior #%s (%s): %s'):format(tostring(row.id), tostring(row.name), tostring(err or 'invalid id')))
    end
  end
  cache = fresh
  lib.print.info(('interiors: %d loaded%s'):format(loaded, skipped > 0 and (', %d skipped'):format(skipped) or ''))
end

--- Every interior, sorted by id (copies, safe to modify / send).
---@return table[]
function Interiors.all()
  local list = {}
  for _, interior in pairs(cache) do list[#list + 1] = Utils.deepCopy(interior) end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

--- One interior by id. Read-only reference to the cached table.
---@param id number
---@return table|nil
function Interiors.get(id)
  id = positiveId(id)
  return id and cache[id] or nil
end

--- Kick every player out of the instances matching `filter`.
--- filter = { interiorId?, locationId?, groupId?, identifier? } (all given fields must match;
--- `identifier` limits the kick to that character).
---@param filter table
---@param message string|nil toast shown to the kicked players (translated)
---@return number kicked
function Interiors.closeWhere(filter, message)
  if type(filter) ~= 'table' then return 0 end
  local targets = {}
  for _, inst in pairs(Interiors.instances) do
    local match = (filter.interiorId == nil or inst.interiorId == filter.interiorId)
      and (filter.locationId == nil or inst.locationId == filter.locationId)
      and (filter.groupId == nil or inst.groupId == filter.groupId)
    if match then
      if filter.identifier == nil then inst.closed = true end
      local returnTo = returnToOf(inst)
      for member in pairs(inst.members) do
        if filter.identifier == nil or inst.identifiers[member] == filter.identifier then
          targets[#targets + 1] = { src = member, returnTo = returnTo }
        end
      end
    end
  end
  local kicked = 0
  for _, target in ipairs(targets) do
    if kickOut(target.src, target.returnTo, message) then kicked = kicked + 1 end
  end
  return kicked
end

--- Insert (id == nil) or update an interior. Normalizes, persists, refreshes the cache and
--- logs. Players inside instances of a changed layout are sent outside.
---@param interior table
---@param src number|nil admin (for logs)
---@return table|nil interior copy, string|nil error (translated)
function Interiors.save(interior, src)
  if type(interior) ~= 'table' then return nil, L('Invalid interior data') end
  local clean, err = Interiors.normalize(interior)
  if not clean then return nil, err end
  if interior.id ~= nil and not clean.id then return nil, L('Interior not found') end

  local existing = clean.id and cache[clean.id] or nil
  if clean.id and not existing then return nil, L('Interior not found') end

  local data = dataOf(clean)
  if existing then
    if not NZ.DB.interiors.update(clean.id, clean.name, clean.enabled, data) then
      return nil, L('Could not save the interior')
    end
  else
    local id = tonumber(NZ.DB.interiors.insert(clean.name, clean.enabled, data))
    if not id or id < 1 then return nil, L('Could not save the interior') end
    clean.id = math.floor(id)
  end

  cache[clean.id] = clean
  log(existing and 'admin.interior.update' or 'admin.interior.create', src, {
    id = clean.id, name = clean.name, profile = clean.profile, slots = #clean.slots,
    cameraPoints = #clean.cutscene.points, enabled = clean.enabled,
  })
  if existing and layoutChanged(existing, clean) then
    Interiors.closeWhere({ interiorId = clean.id }, L('This garage interior was changed by an admin'))
  end
  return Utils.deepCopy(clean)
end

--- Enable or disable an interior. Disabling sends everybody inside outside.
---@param id number
---@param enabled boolean
---@param src number|nil admin (for logs)
---@return boolean ok, string|nil error (translated)
function Interiors.setEnabled(id, enabled, src)
  id = positiveId(id)
  local interior = id and cache[id]
  if not interior then return false, L('Interior not found') end
  enabled = bool(enabled, false)
  if interior.enabled == enabled then return true end
  if not NZ.DB.interiors.update(id, interior.name, enabled, dataOf(interior)) then
    return false, L('Could not save the interior')
  end
  interior.enabled = enabled
  local kicked = 0
  if not enabled then
    kicked = Interiors.closeWhere({ interiorId = id }, L('This garage interior is no longer available'))
  end
  log('admin.interior.toggle', src, { id = id, name = interior.name, enabled = enabled, playersMoved = kicked })
  return true
end

--- Delete an interior. Locations using it fall back to the quick garage menu.
---@param id number
---@param src number|nil admin (for logs)
---@return boolean ok, string|nil error (translated)
function Interiors.delete(id, src)
  id = positiveId(id)
  local interior = id and cache[id]
  if not interior then return false, L('Interior not found') end
  if not NZ.DB.interiors.delete(id) then return false, L('Could not delete the interior') end
  cache[id] = nil
  local kicked = Interiors.closeWhere({ interiorId = id }, L('This garage interior is no longer available'))

  local updated = 0
  for _, location in ipairs(NZ.Locations.all() or {}) do
    if type(location.access) == 'table' and location.access.interiorId == id then
      local copy = Utils.deepCopy(location)
      copy.access = { mode = 'quick' }
      local saved, err = NZ.Locations.save(copy, src)
      if saved then
        updated = updated + 1
      else
        lib.print.warn(('interiors: could not detach interior #%d from location #%s: %s'):format(id, tostring(location.id), tostring(err)))
      end
    end
  end

  log('admin.interior.delete', src, { id = id, name = interior.name, locationsUpdated = updated, playersMoved = kicked })
  return true
end

---------------------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------------------

--- Instance key of the player, or nil when it is not inside a garage interior.
---@param src number
---@return string|nil
function Interiors.playerInstance(src)
  return playerKey[tonumber(src) or -1]
end

--- The interior of a location when players may go inside it (enabled, not quick-only).
---@return table|nil interior, string|nil error (translated)
local function interiorOfLocation(location)
  local access = type(location) == 'table' and location.access or nil
  if type(access) ~= 'table' or access.mode == 'quick' or not access.interiorId then
    return nil, L('This garage has no interior')
  end
  local interior = cache[tonumber(access.interiorId) or -1]
  if not interior or interior.enabled == false then return nil, L('This garage interior is not available') end
  return interior, nil
end

--- Put the player inside the interior of its open garage (routing bucket instance).
--- opts is reserved for callers that need extra behaviour (currently unused).
---@param src number
---@param session table NZ.Access session { garageKey, location, groupId }
---@param opts table|nil
---@return table|nil InteriorEnterData, string|nil error (translated)
function Interiors.enter(src, session, opts)
  src = tonumber(src)
  if not src or type(session) ~= 'table' or type(session.garageKey) ~= 'string' or type(session.location) ~= 'table' then
    return nil, L('No garage is open')
  end
  local location = NZ.Locations.get(session.location.id) or session.location
  if location.kind ~= 'garage' and location.kind ~= 'job' and location.kind ~= 'private' then
    return nil, L('This garage has no interior')
  end
  if location.enabled == false then return nil, L('This garage is closed') end
  local interior, err = interiorOfLocation(location)
  if not interior then return nil, err end
  -- Vehicles are shown (and driven out) on slots only: an interior without any is unusable.
  if #slotsOf(interior) == 0 then
    return nil, L('This garage interior has no vehicle slots')
  end

  local identifier = identifierOf(src)
  if not identifier then return nil, L('Your character is not loaded') end

  local kind, keyId = Utils.key.parse(session.garageKey)
  local groupId = tonumber(session.groupId) or (kind == 'G' and keyId) or nil
  local private = Interiors.instanceMode() == 'player'
  local role = 'owner'
  local shared = false
  if location.kind == 'private' then
    if not groupId then return nil, L('You do not own this garage') end
    local success, groupRole = pcall(NZ.Private.role, groupId, identifier)
    if not success or (groupRole ~= 'owner' and groupRole ~= 'member') then
      return nil, L('You do not have access to this garage')
    end
    -- Per-player instances: a group that stores its vehicles together still gives every
    -- member a copy of its own, with that member's vehicles.
    shared = location.storage == 'shared' and not private
    if shared then role = groupRole end
  end
  local fleet = location.kind == 'job' and location.source == 'owned'

  local key = session.garageKey .. ':' .. (shared and tostring(groupId) or identifier)
  if playerKey[src] and playerKey[src] ~= key then Interiors.leave(src) end
  local alreadyInside = playerKey[src] == key
  if not alreadyInside and currentBucket(src) ~= 0 then
    return nil, L('You cannot enter the garage right now')
  end

  local inst = Interiors.instances[key]
  if inst and (inst.interiorId ~= interior.id or inst.closed) then
    Interiors.closeWhere({ interiorId = inst.interiorId, locationId = inst.locationId, groupId = inst.groupId },
      L('This garage interior was changed by an admin'))
    if Interiors.instances[key] == inst then release(key, inst) end
    inst = nil
    alreadyInside = false
  end
  if not inst then
    inst = createInstance(key, {
      garageKey = session.garageKey,
      ownerIdentifier = (not shared) and identifier or nil,
      groupId = groupId,
      interiorId = interior.id,
      locationId = location.id,
      shared = shared,
      fleet = fleet,
      private = private,
      returnTo = returnPointOf(location),
    })
  elseif not alreadyInside and memberCount(inst) >= MAX_MEMBERS then
    return nil, L('This garage is full of visitors')
  end

  attach(src, key, inst, role)
  local data = enterData(key, inst, src, interior)
  broadcast(key, nil, src)
  if not alreadyInside then
    log('interior.enter', src, { instance = key, garage = session.garageKey, interior = interior.id, role = role })
  end
  return data, nil
end

--- Temporary guest instance (no vehicles) to visit a purchasable private garage.
---@param src number
---@param location table PrivateLocation
---@return table|nil InteriorEnterData, string|nil error (translated)
function Interiors.tour(src, location)
  src = tonumber(src)
  if not src or type(location) ~= 'table' then return nil, L('Garage not found') end
  local interior, err = interiorOfLocation(location)
  if not interior then return nil, err end

  if playerKey[src] then Interiors.leave(src) end
  if currentBucket(src) ~= 0 then return nil, L('You cannot enter the garage right now') end

  local key = ('tour:%d:%d'):format(location.id, src)
  local previous = Interiors.instances[key]
  if previous then release(key, previous) end
  local inst = createInstance(key, {
    interiorId = interior.id,
    locationId = location.id,
    tour = true,
    returnTo = returnPointOf(location),
  })
  attach(src, key, inst, 'guest')

  SetTimeout(TOUR_SECONDS * 1000, function()
    if Interiors.instances[key] ~= inst or not inst.members[src] then return end
    local returnTo = returnToOf(inst)
    TriggerClientEvent('nz:client:interior:kicked', src, { returnTo = returnTo })
    Interiors.leave(src)
    notify(src, 'info', L('The garage tour has ended'))
  end)

  log('interior.tour', src, { location = location.id, name = location.name, interior = interior.id })
  return enterData(key, inst, src, interior, {}), nil
end

--- Take the player out of its instance (back to the public routing bucket). Releases the
--- instance when it becomes empty and updates the remaining members.
---@param src number
---@return table|nil returnTo {x,y,z,w}
function Interiors.leave(src)
  src = tonumber(src)
  if not src then return nil end
  local key, inst, role = detach(src)
  if not key then return nil end
  local returnTo = inst and returnToOf(inst) or nil
  if inst then settle(key) end
  log('interior.leave', src, { instance = key, role = role })
  return returnTo
end

--- Drop pending invitations of a player that disconnected (main.lua drop hook).
---@param src number
function Interiors.onPlayerDropped(src)
  src = tonumber(src)
  if not src then return end
  for id, invite in pairs(invites) do
    if invite.from == src or invite.to == src then invites[id] = nil end
  end
end

---------------------------------------------------------------------------------------
-- Members who left without the exit (admin bring / teleport, respawn) while their client
-- did not notice (client state lost): back to the public bucket where they are.
---------------------------------------------------------------------------------------

local SWEEP_MS = 5000
local SWEEP_GRACE = 30           -- seconds after joining (fade, IPL loading, teleport in)
local AWAY_XY = 100.0            -- metres outside the entry / exit / slots box. Loose on
local AWAY_Z = 50.0              -- purpose: the server cannot tell which GTA interior the
                                 -- player is in (large garages); the client reacts first

local function outsideInterior(interior, pos)
  local points = { interior.entry, interior.exit }
  for _, slot in ipairs(slotsOf(interior)) do points[#points + 1] = slot end
  local minX, minY, minZ = math.huge, math.huge, math.huge
  local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
  local any = false
  for _, value in pairs(points) do
    local p = Utils.v3(value)
    if p then
      any = true
      minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
      minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
      minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
    end
  end
  if not any then return false end
  local dx = math.max(minX - pos.x, 0.0, pos.x - maxX)
  local dy = math.max(minY - pos.y, 0.0, pos.y - maxY)
  local dz = math.max(minZ - pos.z, 0.0, pos.z - maxZ)
  return math.sqrt(dx * dx + dy * dy) > AWAY_XY or dz > AWAY_Z
end

local function sweepMembers()
  local now = os.time()
  local away = {}
  for src, key in pairs(playerKey) do
    local inst = Interiors.instances[key]
    local interior = inst and cache[inst.interiorId] or nil
    local pos = nil
    if interior and (inst.pending or 0) == 0 and now - (joinedAt[src] or now) >= SWEEP_GRACE and online(src) then
      local ped = GetPlayerPed(src)
      if ped and ped ~= 0 then pos = Utils.v3(GetEntityCoords(ped)) end
    end
    if pos and outsideInterior(interior, pos) then
      awayStrikes[src] = (awayStrikes[src] or 0) + 1
      if awayStrikes[src] >= 2 then away[#away + 1] = { src = src, key = key } end
    else
      awayStrikes[src] = nil
    end
  end
  for _, member in ipairs(away) do
    if playerKey[member.src] == member.key then
      Interiors.leave(member.src)
      -- `stay`: forget the visit without moving the player back to the garage
      TriggerClientEvent('nz:client:interior:kicked', member.src, { stay = true })
      log('interior.away', member.src, { instance = member.key })
    end
  end
end

CreateThread(function()
  while true do
    Wait(SWEEP_MS)
    if next(playerKey) ~= nil then
      local success, err = pcall(sweepMembers)
      if not success then lib.print.warn(('interiors: member sweep failed: %s'):format(tostring(err))) end
    end
  end
end)

-- Players still inside when the resource stops would stay in a private bucket.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for src, key in pairs(playerKey) do
    local inst = Interiors.instances[key]
    setBucket(src, 0)
    local returnTo = inst and returnToOf(inst) or nil
    local ped = GetPlayerPed(src)
    if returnTo and ped and ped ~= 0 then
      pcall(SetEntityCoords, ped, returnTo.x + 0.0, returnTo.y + 0.0, returnTo.z + 0.0, false, false, false, false)
    end
  end
end)

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local function register(name, bucket, ms, handler)
  lib.callback.register(name, Utils.safe(function(source, payload)
    local src = tonumber(source)
    if not src or src <= 0 then return fail(L('Something went wrong')) end
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if not NZ.Access.rateLimit(src, bucket, ms) then return fail(L('Please wait a moment before trying again')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

--- The player's instance: key, instance, role (all nil when outside).
local function current(src)
  local key = playerKey[src]
  local inst = key and Interiors.instances[key] or nil
  if not inst or not inst.members[src] then return nil, nil, nil end
  return key, inst, inst.members[src]
end

local function readPlate(value)
  local plate = Utils.plate(value)
  if plate and #plate <= MAX_PLATE_LENGTH then return plate end
  return nil
end

--- First spawn point of the location with no vehicle (public bucket) within 3 m.
local function freeSpawnIndex(points)
  if type(points) ~= 'table' or #points == 0 then return nil end
  local positions = {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if DoesEntityExist(entity) and GetEntityRoutingBucket(entity) == 0 then
      positions[#positions + 1] = GetEntityCoords(entity)
    end
  end
  for i = 1, #points do
    local point = Utils.v3(points[i])
    if point then
      local free = true
      for j = 1, #positions do
        if Utils.dist(point, positions[j]) < SPAWN_CLEARANCE then
          free = false
          break
        end
      end
      if free then return i end
    end
  end
  return nil
end

local function onlinePlayers()
  if type(NZ.Bridge.getOnlinePlayers) == 'function' then
    local success, list = pcall(NZ.Bridge.getOnlinePlayers)
    if success and type(list) == 'table' then return list end
  end
  local list = {}
  for _, id in ipairs(GetPlayers()) do
    local s = tonumber(id)
    if s then list[#list + 1] = { source = s, name = GetPlayerName(s) or ('#' .. id) } end
  end
  return list
end

-- {} -> InteriorEnterData
register('nz:garage:goInside', 'interior:goInside', 1500, function(src)
  local session, err = NZ.Access.requireSession(src)
  if not session then return fail(err or L('No garage is open')) end
  if inVehicle(src) then return fail(L('Leave your vehicle first')) end
  if incapacitated(src) then return fail(L('You cannot do that right now')) end
  local data, enterErr = Interiors.enter(src, session)
  if not data then return fail(enterErr) end
  return ok(data)
end)

-- { locationId } -> InteriorEnterData (guest tour, no vehicles)
register('nz:forSale:tour', 'forSale:tour', 3000, function(src, payload)
  local id = positiveId(payload.locationId)
  local location = id and NZ.Locations.get(id) or nil
  if type(location) ~= 'table' or location.kind ~= 'private' or location.enabled == false or not location.purchasable then
    return fail(L('This garage is not for sale'))
  end
  if not NZ.Access.nearLocation(src, location, maxDistance()) then
    return fail(L('You are too far from the garage'))
  end
  if inVehicle(src) then return fail(L('Leave your vehicle first')) end
  if incapacitated(src) then return fail(L('You cannot do that right now')) end
  local data, err = Interiors.tour(src, location)
  if not data then return fail(err) end
  return ok(data)
end)

-- { page } -> null (members receive nz:client:interior:sync)
register('nz:interior:page', 'interior:page', 300, function(src, payload)
  local key, inst, role = current(src)
  if not inst then return fail(L('You are not inside a garage')) end
  if inst.tour or role == 'guest' then return fail(L('Only the garage owner and members can do that')) end
  local page = tonumber(payload.page)
  if not finite(page) then return fail(L('Invalid page')) end
  local interior = cache[inst.interiorId]
  if not interior then return fail(L('This garage interior is not available')) end
  local rows = instanceRows(inst)
  inst.page = math.floor(page)
  clampPage(inst, #rows, interior)
  broadcast(key, rows)
  Utils.debug('interior page', key, inst.page)
  return ok(nil)
end)

-- { plate, entityType } -> retrieve result { spawn, spawnIndex, vehicle, netId? }
register('nz:interior:driveOut', 'interior:driveOut', 1500, function(src, payload)
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  local entityType = type(payload.entityType) == 'string' and ENTITY_TYPES[payload.entityType] and payload.entityType or nil

  local key, inst, role = current(src)
  if not inst then return fail(L('You are not inside a garage')) end
  if inst.tour or role == 'guest' then return fail(L('You cannot drive this vehicle')) end
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  if type(location) ~= 'table' or location.enabled == false then return fail(L('This garage is no longer available')) end
  local interior = cache[inst.interiorId]
  if not interior then return fail(L('This garage interior is not available')) end

  local rows = instanceRows(inst)
  local size = clampPage(inst, #rows, interior)
  local first = (inst.page - 1) * size
  local onPage = false
  for i = first + 1, math.min(#rows, first + size) do
    if rows[i].plate == plate then
      onPage = true
      break
    end
  end
  if not onPage then return fail(L('This vehicle is not in the garage')) end

  local spawnIndex = freeSpawnIndex(location.spawnPoints)
  if not spawnIndex then return fail(L('All parking spots are occupied')) end
  local session = memberSession(inst, location)
  if not session then return fail(L('This garage is no longer available')) end

  -- Leave the instance first so the vehicle and the player end up in the public world.
  inst.pending = (inst.pending or 0) + 1
  detach(src)
  local called, result = pcall(NZ.Vehicles.retrieve, src, plate, session, {
    fromInterior = true,
    entityType = entityType,
    spawnIndex = spawnIndex,
  })
  inst.pending = math.max(0, inst.pending - 1)

  if not called then lib.print.error(('interiors: drive out of %s failed: %s'):format(plate, tostring(result))) end
  if not called or type(result) ~= 'table' or not result.ok then
    if Interiors.instances[key] == inst and not inst.closed and online(src) and not playerKey[src] then
      attach(src, key, inst, role)
    else
      TriggerClientEvent('nz:client:interior:kicked', src, { returnTo = returnToOf(inst) })
      settle(key)
    end
    if called and type(result) == 'table' then return result end
    return fail(L('Something went wrong'))
  end

  -- 'vehicle.retrieve' (fromInterior) already carries the plate; keep this one out of the
  -- vehicle's activity history (nz_logs.plate) so the drive-out is not listed twice
  log('interior.driveOut', src, { instance = key, vehiclePlate = plate, spawnIndex = spawnIndex })
  settle(key)
  return result
end)

-- {} -> { returnTo }
register('nz:interior:leave', 'interior:leave', 500, function(src)
  if playerKey[src] then return ok({ returnTo = Interiors.leave(src) }) end
  local session = NZ.Access.getSession(src)
  local location = type(session) == 'table' and session.location or nil
  return ok({ returnTo = returnPointOf(location) })
end)

-- { serverId } -> null (target receives nz:client:interior:invite)
register('nz:interior:invite', 'interior:invite', 2000, function(src, payload)
  local target = positiveId(payload.serverId, 65535)
  if not target or target == src then return fail(L('Invalid player')) end
  local key, inst, role = current(src)
  if not inst then return fail(L('You are not inside a garage')) end
  if inst.private then return fail(L('Invitations are turned off on this server')) end
  if inst.tour or role == 'guest' then return fail(L('Only the garage owner and members can invite players')) end
  if not online(target) then return fail(L('That player is not online')) end
  if playerKey[target] then return fail(L('That player is already inside a garage')) end
  if memberCount(inst) >= MAX_MEMBERS then return fail(L('This garage is full of visitors')) end
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  if type(location) ~= 'table' then return fail(L('This garage is no longer available')) end
  if not NZ.Access.isNear(target, location.openPoints, INVITE_RANGE) then
    return fail(L('That player is not near the garage entrance'))
  end

  for id, invite in pairs(invites) do
    if invite.to == target and invite.key == key then invites[id] = nil end
  end
  nextInviteId = nextInviteId + 1
  local inviteId = nextInviteId
  local garageName = garageNameOf(inst, location)
  local invite = { from = src, to = target, key = key, expires = os.time() + INVITE_SECONDS, garageName = garageName }
  invites[inviteId] = invite
  SetTimeout(INVITE_SECONDS * 1000, function()
    if invites[inviteId] ~= invite then return end
    invites[inviteId] = nil
    -- never answered (the dialog could not be shown, or was ignored)
    if online(invite.from) then
      notify(invite.from, 'info', L('{name} did not answer your invitation', { name = nameOf(target) }))
    end
  end)

  TriggerClientEvent('nz:client:interior:invite', target, {
    inviteId = inviteId,
    fromName = nameOf(src),
    garageName = garageName,
  })
  log('interior.invite', src, { instance = key, target = target })
  return ok(nil)
end)

-- { inviteId, accept } -> null (accepted: nz:client:interior:enter with the guest view)
register('nz:interior:inviteRespond', 'interior:inviteRespond', 500, function(src, payload)
  local inviteId = positiveId(payload.inviteId)
  local invite = inviteId and invites[inviteId] or nil
  if not invite or invite.to ~= src then return fail(L('This invitation is no longer valid')) end
  invites[inviteId] = nil
  if os.time() > invite.expires then return fail(L('This invitation has expired')) end

  if payload.accept ~= true then
    if online(invite.from) then
      notify(invite.from, 'info', L('{name} declined your invitation', { name = nameOf(src) }))
    end
    log('interior.inviteDeclined', src, { instance = invite.key, from = invite.from })
    return ok(nil)
  end

  local inst = Interiors.instances[invite.key]
  if not inst or inst.closed or inst.private or not hasHost(inst) then return fail(L('This garage is no longer open')) end
  if playerKey[src] then return fail(L('You are already inside a garage')) end
  if currentBucket(src) ~= 0 then return fail(L('You cannot enter the garage right now')) end
  if inVehicle(src) then return fail(L('Leave your vehicle first')) end
  if incapacitated(src) then return fail(L('You cannot do that right now')) end
  if memberCount(inst) >= MAX_MEMBERS then return fail(L('This garage is full of visitors')) end
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  if type(location) ~= 'table' or location.enabled == false then return fail(L('This garage is no longer available')) end
  if not NZ.Access.isNear(src, location.openPoints, INVITE_RANGE) then return fail(L('You are too far from the garage')) end
  local interior = cache[inst.interiorId]
  if not interior or interior.enabled == false then return fail(L('This garage interior is not available')) end

  attach(src, invite.key, inst, 'guest')
  TriggerClientEvent('nz:client:interior:enter', src, enterData(invite.key, inst, src, interior))
  broadcast(invite.key, nil, src)
  if online(invite.from) then
    notify(invite.from, 'success', L('{name} joined your garage', { name = nameOf(src) }))
  end
  log('interior.join', src, { instance = invite.key, from = invite.from })
  return ok(nil)
end)

-- { serverId } -> null (owner only)
register('nz:interior:kick', 'interior:kick', 1000, function(src, payload)
  local target = positiveId(payload.serverId, 65535)
  local key, inst, role = current(src)
  if not inst then return fail(L('You are not inside a garage')) end
  if role ~= 'owner' then return fail(L('Only the garage owner can do that')) end
  if not target or target == src or playerKey[target] ~= key then return fail(L('That player is not in your garage')) end
  if inst.members[target] == 'owner' then return fail(L('You cannot remove another owner')) end
  local targetRole = inst.members[target]
  kickOut(target, returnToOf(inst), L('You were asked to leave the garage'))
  log('interior.kick', src, { instance = key, target = target, role = targetRole })
  return ok(nil)
end)

-- {} -> PlayerOption[] (players near the entrance who are not inside)
register('nz:interior:players', 'interior:players', 1000, function(src)
  local key, inst, role = current(src)
  if not inst then return fail(L('You are not inside a garage')) end
  if inst.private then return fail(L('Invitations are turned off on this server')) end
  if inst.tour or role == 'guest' then return fail(L('Only the garage owner and members can invite players')) end
  local location = inst.locationId and NZ.Locations.get(inst.locationId) or nil
  if type(location) ~= 'table' then return ok({}) end
  local list = {}
  for _, player in ipairs(onlinePlayers()) do
    local s = tonumber(type(player) == 'table' and player.source)
    if s and s ~= src and playerKey[s] ~= key and NZ.Access.isNear(s, location.openPoints, INVITE_RANGE) then
      list[#list + 1] = { serverId = s, name = type(player.name) == 'string' and player.name or nameOf(s) }
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return ok(list)
end)

-- { interior } -> Interior (admin only)
register('nz:creator:save', 'creator:save', 1000, function(src, payload)
  if not NZ.Access.isAdmin(src) then
    log('security.admin', src, { callback = 'nz:creator:save' })
    return fail(L('No permission'))
  end
  if type(payload.interior) ~= 'table' then return fail(L('Invalid interior data')) end
  local saved, err = Interiors.save(payload.interior, src)
  if not saved then return fail(err) end
  return ok(saved)
end)
