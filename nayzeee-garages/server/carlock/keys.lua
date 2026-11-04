--[[
  nayzeee-garages — car lock: key store and rules (server, NZ.CarLock). docs/CARLOCK.md §3.

  The server is the only authority on keys. A player has a key for a plate when (first hit):
    1. a temporary key (memory, per character, expires after Config.CarLock.tempKeyHours;
       kept across a resource restart, dropped on a server restart),
    2. a physical key / fob item (physical mode) whose metadata plate + version match and whose
       signature is valid (key items are signed with a server secret: metadata edited or forged
       through an inventory never opens anything),
    3. a virtual shared key (virtual mode, table nz_keys),
    4. owner / garage share / job or gang fleet access (Config.CarLock.ownerHasKey).

  Plates are always the real plate (NZ.CarLock.realPlate): the identity the server recorded
  for the entity (garage vehicles, fake plates), else the plate text. A plate text copied
  onto another entity than the tracked garage vehicle is never trusted.

  Locks: SetVehicleDoorsLocked (server RPC to the entity owner) + replicated state bags
  'nzLocked' (bool) and 'nzAlarm' ({ id, mode, seconds } | false) that every client applies
  (client/carlock/lock.lua); the lock feedback is a server event to nearby players
  ('nz:client:carlock:fx'). The server keeps its own lock record and puts a bag value a
  client changed back (`set sv_stateBagStrictMode true` stops clients writing bags at all).
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local RESOURCE = GetCurrentResourceName()

local ROW_TTL = 15000          -- ms: cached vehicle rows / owner access
local VIRTUAL_TTL = 60000      -- ms: cached virtual key sets per character
local VERSION_TTL = 300000     -- ms: cached key versions
local MAX_PLATE = 16
local MAX_CLASS_HASHES = 4000
local SESSION_KVP = 'nz:carlock:session'
local SECRET_KVP = 'nz:carlock:secret'
local SIG_LENGTH = 24          -- hex characters of the HMAC kept in the item metadata

local temp = {}                -- [holder] = { [plate] = { expires, reason, at, access? } } (access: ends with the share / fleet access)
local unownedVersions = {}     -- [plate] = version of NPC / spawned vehicles
local versionCache = {}        -- [plate] = { v, owned, owner, job, gang, at }
local lockState = {}           -- [entity] = locked, as last set by the server
local rowCache = {}            -- [plate] = { row|false, at }
local accessCache = {}         -- [plate] = { [identifier] = { access|false, at } }
local virtualCache = {}        -- [identifier] = { set, at }
local knownPlates = {}         -- [entity] = real plate recorded by the server
local accessOut = {}           -- [entity] = identifier that took it out through a share / fleet access
local classVotes = {}          -- [modelHash] = { votes = { [class] = { [src] = true } }, best }
local classCount = 0
local sigCache = {}            -- [sig] = 'plate|version|kind|id' of verified items
local sigCount = 0
local alarmCounter = 0
local warnedItems = {}         -- [item] = true once warned that it is not defined

---------------------------------------------------------------------------------------
-- Small helpers
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
  local p = Utils.plate(plate)
  if not p or #p > MAX_PLATE then return nil end
  return p
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, id = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

--- Temporary keys belong to the character; players without one (not loaded) use their source.
local function holderOf(src)
  return identifierOf(src) or ('src:' .. tostring(src))
end

local function sourceOfIdentifier(identifier)
  if type(identifier) ~= 'string' then return nil end
  local src = identifier:match('^src:(%d+)$')
  if src then return validSrc(src) end
  if type(NZ.Bridge.getSourceByIdentifier) ~= 'function' then return nil end
  local ok, res = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
  return ok and validSrc(res) or nil
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('carlock: log "%s" failed: %s'):format(event, tostring(err))) end
end

--- Tell a player's client that its keys changed (plate = nil: everything).
local function push(src, plate)
  src = validSrc(src)
  if src then TriggerClientEvent('nz:client:carlock:keys', src, { plate = plate }) end
end

local function pushIdentifier(identifier, plate)
  local src = sourceOfIdentifier(identifier)
  if src then push(src, plate) end
end

local function now() return GetGameTimer() end

---------------------------------------------------------------------------------------
-- Another key resource next to the built-in car lock (shared/carlock.lua decides at load)
---------------------------------------------------------------------------------------

pcall(function() GlobalState.nzCarLockOther = CarLock.otherKeyResource() or false end)

local OTHER_KEYS = {}
for _, name in ipairs(CarLock.otherKeyResources()) do OTHER_KEYS[name] = true end

if CarLock.cfg().enabled == true then
  local other = CarLock.otherKeyResource()
  local setting = CarLock.keysSetting()
  if other and setting == 'auto' then
    lib.print.warn(('[nayzeee-garages] %s is running: the built-in car lock is off (Config.Integrations.keys = "auto"). Remove %s or set Config.Integrations.keys = "nayzeee".')
      :format(other, other))
  elseif other and setting == 'nayzeee' then
    lib.print.warn(('[nayzeee-garages] %s is running next to the built-in car lock (Config.Integrations.keys = "nayzeee"): both will lock vehicles and block engines. Stop %s or set Config.Integrations.keys = "auto".')
      :format(other, other))
  end
end

-- A key resource started after us. During the server boot (no player connected yet: the
-- start order inside a [category] of server.cfg is not guaranteed) 'auto' hands keys over to
-- it, like when it starts first; clients take the decision from GlobalState when they join.
-- Once players are online nothing flips under them: the change is only reported.
AddEventHandler('onResourceStart', function(resource)
  if not OTHER_KEYS[resource] or not CarLock.enabled() then return end
  local setting = CarLock.keysSetting()
  local okCount, players = pcall(GetNumPlayerIndices)
  if setting == 'auto' and okCount and tonumber(players) == 0 then
    CarLock.setOtherKeyResource(resource)
    pcall(function() GlobalState.nzCarLockOther = resource end)
    lib.print.warn(('[nayzeee-garages] %s started after nayzeee-garages: the built-in car lock is off (Config.Integrations.keys = "auto"). Start %s before nayzeee-garages in server.cfg.')
      :format(resource, resource))
    return
  end
  if setting == 'nayzeee' then
    lib.print.warn(('[nayzeee-garages] %s started while the built-in car lock runs (Config.Integrations.keys = "nayzeee"): both will lock vehicles and block engines. Stop %s or set Config.Integrations.keys = "auto".')
      :format(resource, resource))
    return
  end
  lib.print.warn(('[nayzeee-garages] %s started while the built-in car lock runs: both will lock vehicles and block engines until nayzeee-garages restarts. Start %s before nayzeee-garages in server.cfg or set Config.Integrations.keys = "%s".')
    :format(resource, resource, resource))
end)

---------------------------------------------------------------------------------------
-- Signed key items (HMAC-SHA256, pure Lua 5.4)
---------------------------------------------------------------------------------------

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local M32 = 0xffffffff

local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & M32 end

local function sha256(msg)
  local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local len = #msg
  msg = msg .. '\128' .. string.rep('\0', (55 - len) % 64) .. string.pack('>I8', len * 8)
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do w[i] = string.unpack('>I4', msg, chunk + i * 4) end
    for i = 16, 63 do
      local a, b = w[i - 15], w[i - 2]
      local s0 = rrot(a, 7) ~ rrot(a, 18) ~ (a >> 3)
      local s1 = rrot(b, 17) ~ rrot(b, 19) ~ (b >> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & M32
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 0, 63 do
      local s1 = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
      local ch = (e & f) ~ ((~e) & g)
      local t1 = (h + s1 + ch + K[i + 1] + w[i]) & M32
      local s0 = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = (s0 + maj) & M32
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) & M32, c, b, a, (t1 + t2) & M32
    end
    h0, h1, h2, h3 = (h0 + a) & M32, (h1 + b) & M32, (h2 + c) & M32, (h3 + d) & M32
    h4, h5, h6, h7 = (h4 + e) & M32, (h5 + f) & M32, (h6 + g) & M32, (h7 + h) & M32
  end
  return string.pack('>I4I4I4I4I4I4I4I4', h0, h1, h2, h3, h4, h5, h6, h7)
end

local function xorBytes(s, byte)
  return (s:gsub('.', function(c) return string.char(c:byte() ~ byte) end))
end

local function hmac(key, msg)
  if #key > 64 then key = sha256(key) end
  key = key .. string.rep('\0', 64 - #key)
  return sha256(xorBytes(key, 0x5c) .. sha256(xorBytes(key, 0x36) .. msg))
end

local function hex(s)
  return (s:gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end

local secret = nil              -- convar or database value (kept for the session)
local fallbackSecret = nil      -- local KVP copy while the database cannot be read (never cached as `secret`)
local secretRetryAt = -1        -- GetGameTimer() of the next database attempt after a failure
local SECRET_RETRY_MS = 30000

local function newSecret()
  local entropy = { tostring(os.time()), tostring(GetGameTimer()), tostring(os.clock()), tostring({}) }
  for _ = 1, 8 do entropy[#entropy + 1] = tostring(math.random(0, 0x7fffffff)) end
  return hex(sha256(table.concat(entropy, '|')))
end

local function kvpSecret()
  if fallbackSecret then return fallbackSecret end
  local okRead, stored = pcall(GetResourceKvpString, SECRET_KVP)
  if okRead and type(stored) == 'string' and #stored >= 32 then
    fallbackSecret = stored
  else
    fallbackSecret = newSecret()
    pcall(SetResourceKvp, SECRET_KVP, fallbackSecret)
  end
  return fallbackSecret
end

--- Server secret for key signatures: convar nz_carlock_secret (set the same value on servers
--- that share one database), else the value stored in nz_settings (created on the first
--- start). While the database cannot be read, this resource's KVP copy is used and the
--- database is tried again every 30 s (key items signed meanwhile stop working once it is
--- back; set the convar to avoid that).
local function keySecret()
  if secret then return secret end
  local convar = GetConvar('nz_carlock_secret', '')
  if type(convar) == 'string' and #convar >= 16 then
    secret = convar
    return secret
  end
  -- the very first start creates nz_settings during the boot: wait for it
  if not NZ.Ready and coroutine.isyieldable() then
    local deadline = GetGameTimer() + 30000
    while not NZ.Ready and GetGameTimer() < deadline do Wait(250) end
    if secret then return secret end
  end
  if GetGameTimer() >= secretRetryAt and NZ.DB.keys and type(NZ.DB.keys.secret) == 'function' then
    local ok, stored = pcall(NZ.DB.keys.secret, newSecret())
    if ok and type(stored) == 'string' and #stored >= 32 then
      secret = stored
      if fallbackSecret then
        sigCache, sigCount = {}, 0
        lib.print.info('[nayzeee-garages] carlock: the key secret was read from the database again.')
      end
      return secret
    end
    secretRetryAt = GetGameTimer() + SECRET_RETRY_MS
    if not fallbackSecret then
      lib.print.warn('[nayzeee-garages] carlock: the key secret could not be read from the database; using the local KVP copy and retrying every 30 s. Key items signed meanwhile stop working when the database is back. Set the convar nz_carlock_secret to avoid this.')
    end
  end
  return kvpSecret()
end

-- Load the secret once the database is migrated (server/main.lua sets NZ.Ready), so the first
-- key check never waits on it and a first start never signs with a temporary value.
CreateThread(function()
  local deadline = GetGameTimer() + 120000
  while not NZ.Ready and GetGameTimer() < deadline do Wait(500) end
  local ok, err = pcall(keySecret)
  if not ok then lib.print.warn(('[nayzeee-garages] carlock: key secret: %s'):format(tostring(err))) end
end)

local function signature(plate, version, kind, id)
  local msg = table.concat({ 'nzkey', plate, tostring(version), kind, id }, '|')
  return hex(hmac(keySecret(), msg)):sub(1, SIG_LENGTH)
end

local function randomId()
  return ('%08x'):format(math.random(0, 0x7fffffff))
end

---------------------------------------------------------------------------------------
-- Vehicles, plates and rows
---------------------------------------------------------------------------------------

--- The real plate of a vehicle entity (trimmed, upper-case), or nil.
---@param entity number
---@return string|nil
function CarLock.realPlate(entity)
  if not isVehicle(entity) then return nil end
  local known = knownPlates[entity]
  if known then return known end
  local text = normPlate(GetVehicleNumberPlateText(entity))
  if not text then return nil end
  -- the plate of a tracked garage vehicle on another entity: a copy / plate swap
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[text] or nil
  if type(out) == 'table' and out.entity and out.entity ~= entity and isVehicle(out.entity) then
    return nil
  end
  return text
end

--- Record (or clear with nil) the real plate of an entity. Garage hand-outs do it; the fake
--- plate feature calls it with the real plate before changing the plate text.
---@param entity number
---@param plate string|nil
function CarLock.setRealPlate(entity, plate)
  if type(entity) ~= 'number' then return end
  plate = normPlate(plate)
  if plate and not isVehicle(entity) then return end
  knownPlates[entity] = plate
end

--- Vehicle entity carrying `plate` (real plate), the nearest to `src` when given (same
--- routing bucket only).
---@param plate string
---@param src number|nil
---@return number|nil entity, number|nil distance
function CarLock.findVehicle(plate, src)
  plate = normPlate(plate)
  if not plate then return nil end
  local origin, bucket = nil, nil
  src = validSrc(src)
  if src then
    local ped = GetPlayerPed(tostring(src))
    if ped and ped ~= 0 then origin = GetEntityCoords(ped) end
    bucket = GetPlayerRoutingBucket(tostring(src))
  end
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and CarLock.realPlate(entity) == plate
      and (bucket == nil or GetEntityRoutingBucket(entity) == bucket) then
      local dist = origin and #(GetEntityCoords(entity) - origin) or 0.0
      if dist < bestDist then best, bestDist = entity, dist end
    end
  end
  return best, best and bestDist or nil
end

--- Owned-vehicle row (cached for a few seconds), nil for NPC / spawned vehicles.
local function rowOf(plate)
  local hit = rowCache[plate]
  if hit and now() - hit.at < ROW_TTL then return hit.row or nil end
  local row = nil
  if type(NZ.DB.getVehicle) == 'function' then
    local ok, res = pcall(NZ.DB.getVehicle, plate)
    if ok and type(res) == 'table' then row = res end
  end
  rowCache[plate] = { row = row or false, at = now() }
  return row
end

--- Owned vehicle row of a plate (cached), or nil.
---@param plate string
---@return table|nil
function CarLock.vehicleRow(plate)
  plate = normPlate(plate)
  return plate and rowOf(plate) or nil
end

--- Forget cached data of a plate (after an ownership change made outside this file).
---@param plate string|nil nil = every plate
function CarLock.invalidate(plate)
  plate = normPlate(plate)
  if not plate then
    rowCache, accessCache, versionCache, virtualCache = {}, {}, {}, {}
    return
  end
  rowCache[plate], accessCache[plate], versionCache[plate] = nil, nil, nil
end

--- Is `src` the owner (DB) of `plate`?
---@param src number
---@param plate string
---@return boolean
function CarLock.isOwner(src, plate)
  plate = normPlate(plate)
  local id = validSrc(src) and identifierOf(src)
  local row = plate and rowOf(plate)
  return id ~= nil and row ~= nil and row.owner == id
end

local function ownerAccess(src, plate)
  local id = identifierOf(src)
  if not id then return nil end
  local perPlate = accessCache[plate]
  local hit = perPlate and perPlate[id]
  if hit and now() - hit.at < ROW_TTL then return hit.access or nil end
  local row = rowOf(plate)
  local access = nil
  if row and type(NZ.Vehicles.accessOf) == 'function' then
    local ok, res = pcall(NZ.Vehicles.accessOf, src, row, nil, { identifier = id })
    if ok and type(res) == 'string' then access = res end
  end
  perPlate = perPlate or {}
  accessCache[plate] = perPlate
  perPlate[id] = { access = access or false, at = now() }
  return access
end

---------------------------------------------------------------------------------------
-- Vehicle class / security profile
---------------------------------------------------------------------------------------

local TYPE_CLASS = { heli = 15, plane = 16, boat = 14, submarine = 14, trailer = 11, train = 21 }
local QB_CATEGORY_CLASS = {
  compacts = 0, sedans = 1, suvs = 2, coupes = 3, muscle = 4, sportsclassics = 5, sports = 6,
  super = 7, motorcycles = 8, offroad = 9, industrial = 10, utility = 11, vans = 12, cycles = 13,
  boats = 14, helicopters = 15, planes = 16, service = 17, emergency = 18, military = 19,
  commercial = 20, trains = 21, openwheel = 22,
}

local sharedClasses = nil   -- [hash] = class from the QBCore / Qbox shared vehicle list

local function loadSharedClasses()
  sharedClasses = {}
  local list = nil
  if NZ.Framework == 'qbx' then
    local ok, res = pcall(function() return exports.qbx_core:GetVehiclesByHash() end)
    if ok and type(res) == 'table' then list = res end
  end
  if not list and (NZ.Framework == 'qb' or NZ.Framework == 'qbx') then
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and type(core) == 'table' and core.Shared and type(core.Shared.Vehicles) == 'table' then
      list = core.Shared.Vehicles
    end
  end
  for key, v in pairs(list or {}) do
    if type(v) == 'table' and type(v.category) == 'string' then
      local class = QB_CATEGORY_CLASS[v.category:lower()]
      local hash = tonumber(v.hash) or (type(v.model) == 'string' and joaat(v.model))
        or (type(key) == 'number' and key) or (type(key) == 'string' and joaat(key)) or nil
      if class and hash then
        hash = math.floor(hash) % 4294967296
        if hash > 2147483647 then hash = hash - 4294967296 end
        sharedClasses[math.tointeger(hash) or hash] = class
      end
    end
  end
end

--- Remember the class a client reports for a model (majority of distinct players wins).
---@param src number
---@param entity number
---@param class any
function CarLock.learnClass(src, entity, class)
  class = tonumber(class)
  if not class or class ~= math.floor(class) or class < 0 or class > 22 or not isVehicle(entity) then return end
  class = math.tointeger(class)
  local hash = GetEntityModel(entity)
  if not hash then return end
  local entry = classVotes[hash]
  if not entry then
    if classCount >= MAX_CLASS_HASHES then return end
    classCount = classCount + 1
    entry = { votes = {}, best = nil, bestCount = 0 }
    classVotes[hash] = entry
  end
  local voters = entry.votes[class]
  if not voters then
    voters = { n = 0 }
    entry.votes[class] = voters
  end
  if voters[src] then return end
  if voters.n >= 32 then return end
  voters[src] = true
  voters.n = voters.n + 1
  if voters.n > entry.bestCount then entry.best, entry.bestCount = class, voters.n end
end

--- The learned class of a model, trusted only when two players agree or nobody disagrees.
local function votedClass(entry)
  if not entry or not entry.best then return nil end
  if entry.bestCount >= 2 then return entry.best end
  for class, voters in pairs(entry.votes) do
    if class ~= entry.best and voters.n > 0 then return nil end
  end
  return entry.best
end

--- Best known GTA class of a vehicle entity (nil when unknown).
---@param entity number
---@return number|nil
function CarLock.classOf(entity)
  if not isVehicle(entity) then return nil end
  local hash = GetEntityModel(entity)
  if sharedClasses == nil then pcall(loadSharedClasses) end
  if sharedClasses and sharedClasses[hash] then return sharedClasses[hash] end
  local voted = votedClass(classVotes[hash])
  if voted then return voted end
  local okType, vtype = pcall(GetVehicleType, entity)
  if okType and type(vtype) == 'string' and TYPE_CLASS[vtype] then return TYPE_CLASS[vtype] end
  return nil
end

--- Security profile of a vehicle entity: name, profile table.
---@param entity number
---@return string name, table profile
function CarLock.profileOfEntity(entity)
  if not isVehicle(entity) then return CarLock.profile('standard') end
  return CarLock.profileOf(GetEntityModel(entity), CarLock.classOf(entity))
end

--- Security profile of a plate (its entity when spawned, else its stored model).
---@param plate string
---@return string name, table profile
function CarLock.profileOfPlate(plate)
  local entity = CarLock.findVehicle(plate)
  if entity then return CarLock.profileOfEntity(entity) end
  local row = rowOf(normPlate(plate) or '')
  if row then return CarLock.profileOf(row.hash or row.model, nil) end
  return CarLock.profile('standard')
end

---------------------------------------------------------------------------------------
-- Mode, versions
---------------------------------------------------------------------------------------

local MODE_TTL = 60000          -- ms: cached "are the key items defined in the inventory?"
local modeCache = { value = nil, at = -1e9 }

--- Effective key mode: 'physical' (key items) or 'virtual'. Physical needs an inventory with
--- item metadata AND the key / fob items defined in it (else every hand-out would fail).
---@return 'physical'|'virtual'
function CarLock.mode()
  local ok, meta = pcall(NZ.Inventory.supportsMetadata)
  local mode = CarLock.resolveMode(ok and meta == true)
  if mode ~= 'physical' then return mode end
  if modeCache.value and now() - modeCache.at < MODE_TTL then return modeCache.value end
  mode = 'physical'
  if type(NZ.Inventory.itemDefined) == 'function' then
    for _, item in pairs(CarLock.keyItems()) do
      local okDef, defined = pcall(NZ.Inventory.itemDefined, item)
      if okDef and defined == false then
        mode = 'virtual'
        if not warnedItems[item] then
          warnedItems[item] = true
          local okName, inv = pcall(NZ.Inventory.name)
          lib.print.warn(('[nayzeee-garages] carlock: the item "%s" is not defined in %s: using virtual keys. Add the items of install/items/ to your inventory.')
            :format(item, okName and tostring(inv) or 'the inventory'))
        end
        break
      end
    end
  end
  modeCache.value, modeCache.at = mode, now()
  return mode
end

--- Owner identity of a vehicle row / key state (owner, job, gang), hashed: stored with the key
--- version (nz_key_owner) so an ownership change made by ANY script retires the old keys.
local function ownerMarkOf(t)
  return hex(sha256(('%s|%s|%s'):format(t.owner or '', t.job or '', t.gang or ''))):sub(1, 32)
end

--- First key version of a vehicle row (random: a deleted vehicle's plate given to a new
--- vehicle never matches the old keys).
local function initialVersion()
  return math.random(1, 0x3fffffff)
end

local afterRekey -- defined with the change of locks below

--- Read the key state of an owned plate from the database and reconcile it with the current
--- owner: a row whose owner / job / gang differs from the one the keys were cut for (or that
--- was never keyed) gets a new version first (old key items stop working, virtual and
--- temporary keys of others are removed).
--- Returns entry ({ v, owned, owner, job, gang }) or nil, 'error'.
local function loadVersion(plate)
  if not (NZ.DB.keys and type(NZ.DB.keys.state) == 'function') then return nil, 'error' end
  local ok, st = pcall(NZ.DB.keys.state, plate)
  if not ok or st == nil then return nil, 'error' end
  if st == false then
    return { v = unownedVersions[plate] or 0, owned = false }
  end
  local version = math.tointeger(tonumber(st.version) or 0) or 0
  if st.markSupported then
    local mark, previous = ownerMarkOf(st), st.mark
    if previous ~= mark then
      local okC, changed = pcall(NZ.DB.keys.claim, plate, mark, initialVersion())
      if not okC or changed == nil then return nil, 'error' end
      local ok2, st2 = pcall(NZ.DB.keys.state, plate)
      if not ok2 or type(st2) ~= 'table' then return nil, 'error' end
      st = st2
      version = math.tointeger(tonumber(st.version) or 0) or 0
      if changed then afterRekey(plate, st.owner, version, previous ~= nil and 'owner' or 'first') end
    end
  end
  return { v = version, owned = true, owner = st.owner, job = st.job, gang = st.gang }
end

--- Is a cached version entry out of date with the (15 s cached) vehicle row?
local function versionStale(hit, plate)
  local row = rowOf(plate)
  if hit.owned ~= (row ~= nil) then return true end
  if row and (row.owner ~= hit.owner or row.job ~= hit.job or row.gang ~= hit.gang) then return true end
  return false
end

--- Current key version of a plate (owned: nz_key_version; others: memory). `fresh` skips the
--- cache. nil only when the database cannot be read and nothing is known yet (callers refuse
--- keys then); on a database error the last known value is kept.
---@param plate string
---@param fresh boolean|nil
---@return integer|nil
function CarLock.keyVersion(plate, fresh)
  plate = normPlate(plate)
  if not plate then return 0 end
  local hit = versionCache[plate]
  if not fresh and hit and now() - hit.at < (hit.owned and VERSION_TTL or ROW_TTL) and not versionStale(hit, plate) then
    return hit.v
  end
  local entry = loadVersion(plate)
  if not entry then
    -- database error: keep the last known value, do not cache (the next call tries again)
    return hit and hit.v or nil
  end
  entry.at = now()
  versionCache[plate] = entry
  return entry.v
end

---------------------------------------------------------------------------------------
-- Key items
---------------------------------------------------------------------------------------

local function descriptionOf(plate, opts)
  local name = type(opts.label) == 'string' and opts.label ~= '' and opts.label or nil
  if not name and type(opts.model) == 'string' and opts.model ~= '' then
    name = opts.model:sub(1, 1):upper() .. opts.model:sub(2)
  end
  if name then return L('{model} · Plate {plate}', { model = name, plate = plate }) end
  return L('Plate {plate}', { plate = plate })
end

--- Signed metadata of a new key item for the current version of `plate`.
--- opts = { kind = 'key'|'fob', model = spawn name, label = model label, origin = 'search'|'locksmith'|nil }
--- origin marks a crime's key (server-written, not part of the signature): it opens the vehicle
--- but gives no tracker access and no owner's nickname (server/carlock/tracker.lua).
---@param plate string
---@param opts table|nil
---@return table|nil metadata
function CarLock.keyMetadata(plate, opts)
  plate = normPlate(plate)
  if not plate then return nil end
  opts = type(opts) == 'table' and opts or {}
  local kind = opts.kind
  if kind ~= 'key' and kind ~= 'fob' then
    local _, profile = CarLock.profileOfPlate(plate)
    kind = CarLock.keyKindOf(profile)
  end
  local version = CarLock.keyVersion(plate, true) -- cut for the current owner's version
  if not version then return nil end
  local id = randomId()
  local model = type(opts.model) == 'string' and opts.model:sub(1, 32) or nil
  return {
    plate = plate,
    version = version,
    kind = kind,
    model = model,
    id = id,
    sig = signature(plate, version, kind, id),
    label = CarLock.keyLabel(kind, plate),
    description = descriptionOf(plate, { label = opts.label, model = model }),
    origin = type(opts.origin) == 'string' and opts.origin:sub(1, 16) or nil,
    display = false, -- qb-inventory: show only the description, not every field
  }
end

--- Is this key item metadata genuine and current? reason: 'invalid' | 'plate' | 'version' |
--- 'error' (the key version cannot be read right now).
---@param metadata table
---@param plate string|nil expected plate
---@return boolean valid, string|nil reason
function CarLock.verifyKeyItem(metadata, plate)
  if type(metadata) ~= 'table' then return false, 'invalid' end
  local p = normPlate(metadata.plate)
  if not p then return false, 'invalid' end
  if plate ~= nil and p ~= normPlate(plate) then return false, 'plate' end
  local version = tonumber(metadata.version)
  local kind, id, sig = metadata.kind, metadata.id, metadata.sig
  if sig == nil and cfg().trustUnsignedKeys == true then
    -- key items written by other scripts / inventory admin tools (no signature): owner's
    -- choice. A version, when written, must be the current one (GetKeyVersion); a key with
    -- just a plate fits every version (a change of locks cannot retire it).
    if version == nil then return true, nil end
    local current = CarLock.keyVersion(p)
    if current == nil then return false, 'error' end
    if math.tointeger(version) ~= current then return false, 'version' end
    return true, nil
  end
  if not version or version ~= math.floor(version) or (kind ~= 'key' and kind ~= 'fob')
    or type(id) ~= 'string' or #id > 32 or type(sig) ~= 'string' or #sig ~= SIG_LENGTH then
    return false, 'invalid'
  end
  version = math.tointeger(version)
  local fields = ('%s|%d|%s|%s'):format(p, version, kind, id)
  if sigCache[sig] ~= fields then
    if signature(p, version, kind, id) ~= sig then return false, 'invalid' end
    if sigCount > 5000 then sigCache, sigCount = {}, 0 end
    sigCache[sig] = fields
    sigCount = sigCount + 1
  end
  local current = CarLock.keyVersion(p)
  if current == nil then return false, 'error' end
  if version ~= current then return false, 'version' end
  return true, nil
end

--- Valid key / fob items of a plate the player carries: { { item, slot, metadata } }.
---@param src number
---@param plate string
---@return table[]
function CarLock.keyItemsOf(src, plate)
  src, plate = validSrc(src), normPlate(plate)
  local out = {}
  if not src or not plate then return out end
  for _, item in pairs(CarLock.keyItems()) do
    local found = NZ.Inventory.find(src, item, function(md) return normPlate(md and md.plate) == plate end)
    for _, entry in ipairs(found) do
      if CarLock.verifyKeyItem(entry.metadata, plate) then
        out[#out + 1] = { item = item, slot = entry.slot, metadata = entry.metadata }
      end
    end
  end
  return out
end

--- Give a physical key / fob item for the current version of `plate`.
--- opts = { kind = 'key'|'fob', model, label, reason, origin? } (origin: see keyMetadata)
---@param src number
---@param plate string
---@param opts table|nil
---@return boolean ok, string|nil error (translated)
function CarLock.giveKeyItem(src, plate, opts)
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate then return false, L('Invalid request') end
  if not NZ.Inventory.supportsMetadata() then return false, L('Your inventory cannot hold vehicle keys') end
  if CarLock.mode() ~= 'physical' then return false, L('This server does not use key items') end
  opts = type(opts) == 'table' and opts or {}
  local model = opts.model
  if type(model) ~= 'string' then
    local row = rowOf(plate)
    model = row and row.model or nil
  end
  local md = CarLock.keyMetadata(plate, { kind = opts.kind, model = model, label = opts.label, origin = opts.origin })
  if not md then return false, L('Something went wrong') end
  local item = CarLock.itemName(md.kind)
  if not NZ.Inventory.addItem(src, item, 1, md) then
    return false, L('You cannot carry the key')
  end
  push(src, plate)
  log('vehicle.keyItem', src, { plate = plate, kind = md.kind, version = md.version, reason = opts.reason, origin = md.origin })
  return true, nil
end

---------------------------------------------------------------------------------------
-- Temporary keys
---------------------------------------------------------------------------------------

local function tempEntry(holder, plate)
  local list = temp[holder]
  local entry = list and list[plate]
  if not entry then return nil end
  if entry.expires <= os.time() then
    list[plate] = nil
    if next(list) == nil then temp[holder] = nil end
    return nil
  end
  return entry
end

--- Give a temporary key (memory, expires after `hours`, default Config.CarLock.tempKeyHours).
--- reason: 'hotwire'|'robbery'|'assist'|'admin'|'compat'|'spawner'|'garage'|'search'|'contract'|...
--- access = true: the key was given because of a garage share / job or gang fleet access and
--- ends as soon as the player loses that access (checked on every key check).
---@param src number
---@param plate string
---@param reason string|nil
---@param hours number|nil
---@param access boolean|nil
---@return boolean
function CarLock.grantTemp(src, plate, reason, hours, access)
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate then return false end
  hours = tonumber(hours) or CarLock.tempHours()
  if hours ~= hours or hours <= 0 then hours = CarLock.tempHours() end
  hours = math.min(hours, 24 * 30)
  -- claim the first key version of an owned row BEFORE the key exists: that first claim
  -- removes every key of other players (a key stored before it would vanish at the next check)
  CarLock.keyVersion(plate)
  local holder = holderOf(src)
  local list = temp[holder]
  if not list then
    list = {}
    temp[holder] = list
  end
  list[plate] = {
    expires = os.time() + math.max(math.floor(hours * 3600), 60),
    reason = type(reason) == 'string' and reason:sub(1, 24) or 'other',
    at = os.time(),
    access = access == true or nil,
  }
  push(src, plate)
  Utils.debug(('carlock: temporary key %s -> %s (%s)'):format(plate, holder, tostring(reason)))
  return true
end

--- Remove a temporary key of a player (source) or character (identifier).
---@param who number|string
---@param plate string
---@return boolean removed
function CarLock.revokeTemp(who, plate)
  plate = normPlate(plate)
  if not plate then return false end
  local holder, src
  if type(who) == 'number' then
    src = validSrc(who)
    holder = src and holderOf(src) or nil
  elseif type(who) == 'string' and who ~= '' then
    holder = who
    src = sourceOfIdentifier(who)
  end
  if not holder then return false end
  local list = temp[holder]
  local had = list ~= nil and list[plate] ~= nil
  if list then
    list[plate] = nil
    if next(list) == nil then temp[holder] = nil end
  end
  if src then push(src, plate) end
  return had
end

---------------------------------------------------------------------------------------
-- Virtual shared keys (nz_keys)
---------------------------------------------------------------------------------------

local function virtualSet(identifier)
  local hit = virtualCache[identifier]
  if hit and now() - hit.at < VIRTUAL_TTL then return hit.set end
  local set = {}
  if NZ.DB.keys and type(NZ.DB.keys.forIdentifier) == 'function' then
    local ok, plates = pcall(NZ.DB.keys.forIdentifier, identifier)
    for _, p in ipairs(ok and plates or {}) do set[p] = true end
  end
  virtualCache[identifier] = { set = set, at = now() }
  return set
end

--- Give a persistent virtual key of an owned vehicle to another player (virtual mode).
---@param ownerSrc number
---@param targetSrc number
---@param plate string
---@return boolean ok, string|nil error (translated)
function CarLock.shareVirtual(ownerSrc, targetSrc, plate)
  ownerSrc, targetSrc, plate = validSrc(ownerSrc), validSrc(targetSrc), normPlate(plate)
  if not ownerSrc or not targetSrc or not plate then return false, L('Invalid request') end
  if CarLock.mode() ~= 'virtual' then return false, L('Hand over the key item instead') end
  local ownerId, targetId = identifierOf(ownerSrc), identifierOf(targetSrc)
  if not ownerId or not targetId then return false, L('Invalid request') end
  if ownerId == targetId then return false, L('You already have this key') end
  local row = rowOf(plate)
  if not row or row.owner ~= ownerId then return false, L('Only the owner can share this key') end
  -- claim the key version first: the first claim of a row (or the one after an ownership
  -- change) removes every shared key, so it must happen before this key is stored
  if CarLock.keyVersion(plate) == nil then return false, L('Something went wrong') end
  local max = math.max(math.floor(tonumber(cfg().maxVirtualKeys) or 10), 1)
  if virtualSet(targetId)[plate] then return true, nil end
  if NZ.DB.keys.count(plate) >= max then
    return false, L('This vehicle already has {count} shared keys', { count = max })
  end
  if not NZ.DB.keys.add(plate, targetId, ownerId) then return false, L('Something went wrong') end
  virtualCache[targetId] = nil
  push(targetSrc, plate)
  log('vehicle.keyShare', ownerSrc, { plate = plate, target = targetId })
  return true, nil
end

--- Remove a character's virtual key (and temporary key) of `plate`. ownerSrc nil = trusted
--- server call; otherwise the caller must own the vehicle (or be an admin).
---@param ownerSrc number|nil
---@param identifier string
---@param plate string
---@return boolean ok, string|nil error (translated)
function CarLock.revokeVirtual(ownerSrc, identifier, plate)
  plate = normPlate(plate)
  if type(identifier) ~= 'string' or identifier == '' or #identifier > 64 or not plate then
    return false, L('Invalid request')
  end
  if ownerSrc ~= nil then
    ownerSrc = validSrc(ownerSrc)
    if not ownerSrc then return false, L('Invalid request') end
    if not CarLock.isOwner(ownerSrc, plate) and not NZ.Access.isAdmin(ownerSrc) then
      return false, L('Only the owner can manage the keys of this vehicle')
    end
  end
  if NZ.DB.keys and type(NZ.DB.keys.remove) == 'function' then NZ.DB.keys.remove(plate, identifier) end
  virtualCache[identifier] = nil
  local list = temp[identifier]
  if list then
    list[plate] = nil
    if next(list) == nil then temp[identifier] = nil end
  end
  pushIdentifier(identifier, plate)
  log('vehicle.keyRevoke', ownerSrc, { plate = plate, identifier = identifier })
  return true, nil
end

--- Everyone with a virtual or temporary key of `plate`:
--- { { identifier, name, kind = 'virtual'|'temp', grantedBy?, at?, createdAt?, expires?, reason? } }.
---@param plate string
---@return table[]
function CarLock.holders(plate)
  plate = normPlate(plate)
  local out, seen = {}, {}
  if not plate then return out end
  local function nameOf(identifier)
    if identifier:match('^src:') then return L('Unknown') end
    local ok, name = pcall(NZ.Bridge.getCharacterName, identifier)
    return ok and type(name) == 'string' and name or L('Unknown')
  end
  if NZ.DB.keys and type(NZ.DB.keys.list) == 'function' then
    for _, row in ipairs(NZ.DB.keys.list(plate) or {}) do
      seen[row.identifier] = true
      out[#out + 1] = { identifier = row.identifier, name = nameOf(row.identifier), kind = 'virtual',
        grantedBy = row.grantedBy ~= '' and row.grantedBy or nil, createdAt = row.createdAt, at = row.createdAt }
    end
  end
  for holder in pairs(temp) do
    local entry = tempEntry(holder, plate)
    if entry and not seen[holder] and not holder:match('^src:') then
      out[#out + 1] = { identifier = holder, name = nameOf(holder), kind = 'temp', expires = entry.expires,
        reason = entry.reason, at = entry.at }
    end
  end
  return out
end

---------------------------------------------------------------------------------------
-- The rule
---------------------------------------------------------------------------------------

--- Does the player have a key for `plate`? kind: 'temp' | 'item' | 'virtual' | 'owner'.
---@param src number
---@param plate string
---@return boolean, string|nil kind
function CarLock.hasKey(src, plate)
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate then return false, nil end
  CarLock.keyVersion(plate) -- an ownership change made by another script retires old keys first
  local holder = holderOf(src)
  local entry = tempEntry(holder, plate)
  if entry then
    -- a temporary key handed out because of a share / fleet access ends with that access
    if entry.access and not ownerAccess(src, plate) then
      local list = temp[holder]
      list[plate] = nil
      if next(list) == nil then temp[holder] = nil end
    else
      return true, 'temp'
    end
  end
  local mode = CarLock.mode()
  if mode == 'physical' and #CarLock.keyItemsOf(src, plate) > 0 then return true, 'item' end
  local id = identifierOf(src)
  if mode == 'virtual' and id and virtualSet(id)[plate] then return true, 'virtual' end
  if CarLock.ownerHasKey(mode) and ownerAccess(src, plate) then return true, 'owner' end
  return false, nil
end

--- Every key of a player for the Keys app: { { plate, kind, label?, model?, netId? } }.
---@param src number
---@return table[]
function CarLock.keysOf(src)
  src = validSrc(src)
  if not src then return {} end
  local byPlate, order = {}, {}
  local rank = { owner = 4, item = 3, virtual = 2, temp = 1 }
  local function add(plate, kind, extra)
    plate = normPlate(plate)
    if not plate then return end
    local cur = byPlate[plate]
    if cur and rank[cur.kind] >= rank[kind] then return end
    if not cur then order[#order + 1] = plate end
    local entry = { plate = plate, kind = kind }
    for k, v in pairs(extra or {}) do entry[k] = v end
    byPlate[plate] = entry
  end

  local holder = holderOf(src)
  for plate in pairs(temp[holder] or {}) do
    local entry = tempEntry(holder, plate)
    if entry then add(plate, 'temp', { expires = entry.expires, reason = entry.reason }) end
  end
  local mode = CarLock.mode()
  local id = identifierOf(src)
  if mode == 'physical' then
    for _, item in pairs(CarLock.keyItems()) do
      for _, entry in ipairs(NZ.Inventory.find(src, item)) do
        local md = entry.metadata
        if CarLock.verifyKeyItem(md) then
          add(md.plate, 'item', { label = md.label, model = md.model, keyKind = md.kind })
        end
      end
    end
  elseif id then
    for plate in pairs(virtualSet(id)) do add(plate, 'virtual') end
  end
  if id and CarLock.ownerHasKey(mode) then
    local ok, rows = pcall(NZ.DB.getVehiclesByOwner, id)
    for _, row in ipairs(ok and rows or {}) do
      add(row.plate, 'owner', { label = row.nickname, model = row.model })
    end
    local okShares, shared = pcall(NZ.DB.shares.forIdentifier, id)
    for _, entry in ipairs(okShares and type(shared) == 'table' and shared or {}) do
      add(type(entry) == 'table' and entry.plate or entry, 'owner', { shared = true })
    end
  end

  -- net ids of the vehicles that exist right now (one pass over the world)
  local wanted = 0
  for _ in pairs(byPlate) do wanted = wanted + 1 end
  if wanted > 0 then
    local bucket = GetPlayerRoutingBucket(tostring(src))
    for _, entity in ipairs(GetAllVehicles() or {}) do
      local plate = isVehicle(entity) and CarLock.realPlate(entity) or nil
      local entry = plate and byPlate[plate]
      if entry and not entry.netId and GetEntityRoutingBucket(entity) == bucket then
        entry.netId = NetworkGetNetworkIdFromEntity(entity)
      end
    end
  end

  local out = {}
  for _, plate in ipairs(order) do out[#out + 1] = byPlate[plate] end
  return out
end

---------------------------------------------------------------------------------------
-- Change of locks
---------------------------------------------------------------------------------------

--- After a new key version: every virtual key and every temporary key except
--- `keepIdentifier`'s is removed, caches of the plate are reset and the players are told.
--- reason: 'rekey' (locksmith / export / owner change reported by a script), 'owner' (an
--- ownership change noticed on the vehicle row), 'first' (first key version of a row).
afterRekey = function(plate, keepIdentifier, newVersion, reason)
  local affected = {}
  if NZ.DB.keys and type(NZ.DB.keys.list) == 'function' then
    local okList, list = pcall(NZ.DB.keys.list, plate)
    for _, row in ipairs(okList and type(list) == 'table' and list or {}) do affected[row.identifier] = true end
    if next(affected) ~= nil then pcall(NZ.DB.keys.clear, plate) end
  end
  for holder, list in pairs(temp) do
    if list[plate] and holder ~= keepIdentifier then
      list[plate] = nil
      affected[holder] = true
      if next(list) == nil then temp[holder] = nil end
    end
  end
  for identifier in pairs(affected) do
    virtualCache[identifier] = nil
    pushIdentifier(identifier, plate)
  end
  rowCache[plate], accessCache[plate] = nil, nil
  local row = rowOf(plate)
  if row and row.owner then pushIdentifier(row.owner, plate) end
  if reason ~= 'first' then
    log('vehicle.rekey', nil, { plate = plate, version = newVersion, reason = reason, resource = GetInvokingResource() })
  end
end

--- New key version for `plate`: older key items stop working, every virtual key and every
--- temporary key (except `keepIdentifier`'s) is removed. Returns the new version (nil on a
--- database error). Call it after changing a vehicle's owner (sale, transfer, admin edit):
--- `NZ.CarLock.rekey(plate, newOwnerIdentifier)`; a change nobody reports is noticed on the
--- next key check of that plate (owner stored with the version, nz_key_owner).
---@param plate string
---@param keepIdentifier string|nil
---@return integer|nil
function CarLock.rekey(plate, keepIdentifier)
  plate = normPlate(plate)
  if not plate then return nil end
  if type(keepIdentifier) ~= 'string' or keepIdentifier == '' then keepIdentifier = nil end
  rowCache[plate], accessCache[plate] = nil, nil
  local okState, st = false, nil
  if NZ.DB.keys and type(NZ.DB.keys.state) == 'function' then okState, st = pcall(NZ.DB.keys.state, plate) end
  if not okState or st == nil then
    lib.print.warn(('[nayzeee-garages] carlock: rekey of %s failed: the database cannot be read'):format(plate))
    return nil
  end
  local newVersion, entry
  if type(st) == 'table' then
    local mark = st.markSupported and ownerMarkOf(st) or nil
    local okBump, res = pcall(NZ.DB.keys.bumpVersion, plate, mark, initialVersion())
    newVersion = okBump and math.tointeger(tonumber(res)) or nil
    if not newVersion then
      lib.print.warn(('[nayzeee-garages] carlock: rekey of %s failed: the key version could not be saved'):format(plate))
      return nil
    end
    entry = { v = newVersion, owned = true, owner = st.owner, job = st.job, gang = st.gang }
  else
    local hit = versionCache[plate]
    newVersion = (unownedVersions[plate] or (hit and not hit.owned and hit.v) or 0) + 1
    unownedVersions[plate] = newVersion
    entry = { v = newVersion, owned = false }
  end
  entry.at = now()
  versionCache[plate] = entry
  afterRekey(plate, keepIdentifier, newVersion, 'rekey')
  return newVersion
end

---------------------------------------------------------------------------------------
-- Locks and alarm
---------------------------------------------------------------------------------------

-- Values the server last wrote to the replicated state bags of a vehicle. Without
-- sv_stateBagStrictMode the entity owner's client can write them too: a different value is
-- put back (and the server never reads its decisions back from the bags).
local bagWritten = { nzLocked = {}, nzAlarm = {} }   -- [key][entity] = value

local function sameBag(a, b)
  if type(a) == 'table' and type(b) == 'table' then return a.id == b.id and a.mode == b.mode end
  return a == b
end

local function writeBag(entity, key, value)
  bagWritten[key][entity] = value
  Entity(entity).state:set(key, value, true)
end

for key, written in pairs(bagWritten) do
  AddStateBagChangeHandler(key, nil, function(bagName, _, value)
    local okE, entity = pcall(GetEntityFromStateBagName, bagName)
    if not okE or type(entity) ~= 'number' or entity == 0 then return end
    local mine = written[entity]
    if mine == nil then
      -- never written by the server: an alarm a client made up is switched off
      if key == 'nzAlarm' and type(value) == 'table' then
        SetTimeout(0, function() if isVehicle(entity) then writeBag(entity, key, false) end end)
      end
      return
    end
    if sameBag(mine, value) then return end
    SetTimeout(0, function()
      if isVehicle(entity) and written[entity] ~= nil then Entity(entity).state:set(key, written[entity], true) end
    end)
  end)
end

local FX_RANGE = 80.0          -- m: players who get the lock feedback (sound, chirp, lights)

--- Lock feedback for the players near the vehicle (a server event: clients cannot fake it).
local function lockFeedback(entity, locked)
  local netId = NetworkGetNetworkIdFromEntity(entity)
  if not netId or netId == 0 then return end
  local coords = GetEntityCoords(entity)
  local bucket = GetEntityRoutingBucket(entity)
  for _, id in ipairs(GetPlayers() or {}) do
    local src = tonumber(id)
    local ped = src and GetPlayerPed(tostring(src)) or 0
    if ped and ped ~= 0 and GetPlayerRoutingBucket(tostring(src)) == bucket
      and #(GetEntityCoords(ped) - coords) <= FX_RANGE then
      TriggerClientEvent('nz:client:carlock:fx', src, { netId = netId, locked = locked })
    end
  end
end

--- Lock / unlock a vehicle for everyone. fx = true plays the lock feedback (sound, lights,
--- horn chirp) on nearby clients and stops a sounding alarm when unlocking.
---@param entity number
---@param locked boolean
---@param fx boolean|nil
---@return boolean
function CarLock.setLocked(entity, locked, fx)
  if not isVehicle(entity) then return false end
  locked = locked == true
  lockState[entity] = locked
  pcall(SetVehicleDoorsLocked, entity, locked and 2 or 1)
  writeBag(entity, 'nzLocked', locked)
  if fx then
    pcall(lockFeedback, entity, locked)
    if not locked and Entity(entity).state.nzAlarm then writeBag(entity, 'nzAlarm', false) end
  end
  return true
end

--- Is the vehicle locked? The server's own record, else the state bag (a previous run of this
--- resource), else the native lock status.
---@param entity number
---@return boolean
function CarLock.isLocked(entity)
  if not isVehicle(entity) then return false end
  local known = lockState[entity]
  if known ~= nil then return known end
  local value = Entity(entity).state.nzLocked
  if value ~= nil then return value == true end
  local ok, status = pcall(GetVehicleDoorLockStatus, entity)
  return ok and (tonumber(status) or 0) >= 2
end

--- Sound the vehicle's alarm for `seconds` (native GTA alarm or the custom horn / lights
--- alarm per profile; clients near the vehicle play it).
---@param entity number
---@param seconds number|nil default Config.CarLock.alarm.seconds
---@param mode 'native'|'custom'|nil default: the vehicle profile's alarm
---@return boolean
function CarLock.alarm(entity, seconds, mode)
  if not isVehicle(entity) then return false end
  if mode ~= 'native' and mode ~= 'custom' then
    local _, profile = CarLock.profileOfEntity(entity)
    mode = profile.alarm
  end
  if mode ~= 'native' and mode ~= 'custom' then return false end
  local alarmCfg = type(cfg().alarm) == 'table' and cfg().alarm or {}
  seconds = Utils.clamp(math.floor(tonumber(seconds) or tonumber(alarmCfg.seconds) or 25), 1, 65)
  alarmCounter = alarmCounter + 1
  local id = alarmCounter
  writeBag(entity, 'nzAlarm', { id = id, mode = mode, seconds = seconds })
  SetTimeout(seconds * 1000, function()
    if isVehicle(entity) then
      local cur = bagWritten.nzAlarm[entity]
      if type(cur) == 'table' and cur.id == id then writeBag(entity, 'nzAlarm', false) end
    end
  end)
  return true
end

--- Silence a sounding alarm.
---@param entity number
function CarLock.stopAlarm(entity)
  if isVehicle(entity) and (bagWritten.nzAlarm[entity] or Entity(entity).state.nzAlarm) then
    writeBag(entity, 'nzAlarm', false)
  end
end

---------------------------------------------------------------------------------------
-- Request validation shared by the callbacks (server/carlock/main.lua, listeners)
---------------------------------------------------------------------------------------

--- Vehicle of a client request: entity, distance from the SERVER ped position, inside.
--- Fails for other routing buckets.
---@param src number
---@param netId any
---@return number|nil entity, number|nil distance, boolean|nil inside
function CarLock.vehicleFromNet(src, netId)
  src = validSrc(src)
  local id = tonumber(netId)
  if not src or not id or id <= 0 or id ~= math.floor(id) or id > 0x7FFFFFFF then return nil end
  local entity = NetworkGetEntityFromNetworkId(math.tointeger(id))
  if not isVehicle(entity) then return nil end
  if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(tostring(src)) then return nil end
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  local inside = GetVehiclePedIsIn(ped, false) == entity
  local dist = inside and 0.0 or #(GetEntityCoords(ped) - GetEntityCoords(entity))
  return entity, dist, inside
end

--- Ignition bypass for job / gang members in their fleet vehicles (on duty).
---@param src number
---@param plate string
---@return boolean
function CarLock.jobBypass(src, plate)
  local ignition = cfg().ignition
  if type(ignition) ~= 'table' or ignition.bypassJobVehicles ~= true then return false end
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate then return false end
  local okJob, job = pcall(NZ.Bridge.getJob, src)
  job = okJob and type(job) == 'table' and type(job.name) == 'string' and job.onDuty ~= false and job.name:lower() or nil
  local okGang, gang = pcall(NZ.Bridge.getGang, src)
  gang = okGang and type(gang) == 'table' and type(gang.name) == 'string' and gang.name:lower() or nil
  if not job and not gang then return false end
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
  if type(out) == 'table' and type(out.job) == 'string' then
    local name = out.job:lower()
    if name == job or name == gang then return true end
  end
  local row = rowOf(plate)
  if row and type(NZ.Vehicles.fleetOf) == 'function' then
    local kind, name = NZ.Vehicles.fleetOf(row)
    name = type(name) == 'string' and name:lower() or nil
    if (kind == 'job' and name == job) or (kind == 'gang' and name == gang) then return true end
  end
  return false
end

--- Real plate for a plate TEXT another script read from a vehicle (a fake plate becomes the
--- real one when a vehicle wearing that text stands near `src`). Unknown texts pass through.
---@param text string
---@param src number|nil
---@return string|nil
function CarLock.plateFromText(text, src)
  local wanted = normPlate(text)
  if not wanted then return nil end
  local origin, bucket = nil, nil
  src = validSrc(src)
  if src then
    local ped = GetPlayerPed(tostring(src))
    if ped and ped ~= 0 then origin = GetEntityCoords(ped) end
    bucket = GetPlayerRoutingBucket(tostring(src))
  end
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and normPlate(GetVehicleNumberPlateText(entity)) == wanted
      and (bucket == nil or GetEntityRoutingBucket(entity) == bucket) then
      local dist = origin and #(GetEntityCoords(entity) - origin) or 0.0
      if dist < bestDist then best, bestDist = entity, dist end
    end
  end
  if best and bestDist <= 50.0 then
    local real = CarLock.realPlate(best)
    if real then return real end
  end
  return wanted
end

--- Lock range of a vehicle for a player: fob range for remote profiles or when `fob` is
--- true (a fob item in hand), else the key range.
---@param entity number
---@param fob boolean|nil
---@return number
function CarLock.lockRangeOf(entity, fob)
  if fob then return CarLock.range('fob') end
  local _, profile = CarLock.profileOfEntity(entity)
  return CarLock.lockRange(profile)
end

local POP_MISSION = 7      -- GetEntityPopulationType: created by a script

--- May a CLIENT-originated request (another script's client event / export) give `src` a
--- temporary key of `entity`? Server-side calls never come here. Rules: inside or within
--- ranges.compat; nobody else drives it; a player-owned vehicle only for its owner / shared /
--- fleet players or the one who took it out; with compatAmbient = false only script-spawned
--- (mission) vehicles or vehicles this resource tracks. viaAccess = true: a player-owned
--- vehicle of someone else, allowed through a share / fleet access (pass it on to grantTemp:
--- the key then ends with that access).
---@param src number
---@param entity number
---@param dist number|nil distance from the server ped (vehicleFromNet)
---@param inside boolean|nil
---@return boolean ok, string|nil plate, string|nil error (translated), boolean|nil viaAccess
function CarLock.canAcquire(src, entity, dist, inside)
  src = validSrc(src)
  if not src or not isVehicle(entity) then return false, nil, L('Vehicle not found') end
  if not inside and (dist == nil or dist > CarLock.range('compat')) then
    return false, nil, L('You are too far from the vehicle')
  end
  local plate = CarLock.realPlate(entity)
  if not plate then return false, nil, L('Vehicle not found') end
  local ped = GetPlayerPed(tostring(src))
  local driver = GetPedInVehicleSeat(entity, -1)
  if driver and driver ~= 0 and driver ~= ped and IsPedAPlayer(driver) then
    return false, plate, L('Someone else is driving this vehicle')
  end
  -- temporary keys belong to a character: no character loaded, no key from another script
  local id = identifierOf(src)
  if not id then return false, plate, L('Invalid request') end
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
  local tracked = type(out) == 'table' and (out.entity == nil or out.entity == entity)
  -- the one who took it out: by character; the server id only when no character was recorded
  local mine = tracked and (out.identifier == id or (out.identifier == nil and out.src == src))
  local row = rowOf(plate)
  if row or (tracked and not out.spawner) then
    local access = ownerAccess(src, plate)
    -- taken out through a share / fleet access: counts only while that access lasts
    if mine and not access and accessOut[entity] == id then mine = false end
    if not mine and not access then
      return false, plate, L('You do not have access to this vehicle')
    end
    return true, plate, nil, row ~= nil and row.owner ~= id and access ~= nil
  end
  if tracked and out.spawner then
    if not mine then return false, plate, L('You do not have access to this vehicle') end
    return true, plate, nil
  end
  if cfg().compatAmbient ~= true then
    local okPop, pop = pcall(GetEntityPopulationType, entity)
    if not okPop or tonumber(pop) ~= POP_MISSION then
      return false, plate, L('You do not have the keys of this vehicle')
    end
  end
  return true, plate, nil
end

--- Physical mode: move one valid key item of `plate` from `src` to `target` (server copy of
--- the metadata; rolled back when the target cannot take it).
---@param src number
---@param target number
---@param plate string
---@return boolean ok, string|nil error (translated)
function CarLock.handOverKeyItem(src, target, plate)
  src, target, plate = validSrc(src), validSrc(target), normPlate(plate)
  if not src or not target or not plate or src == target then return false, L('Invalid request') end
  local entry = CarLock.keyItemsOf(src, plate)[1]
  if not entry then return false, L('You do not have a key item for this vehicle') end
  local md = entry.metadata
  if not NZ.Inventory.canCarry(target, entry.item, 1, md) then return false, L('They cannot carry the key') end
  local match = md.id and { id = md.id } or { plate = plate }
  if not NZ.Inventory.removeItem(src, entry.item, 1, match, entry.slot) then return false, L('Something went wrong') end
  if not NZ.Inventory.addItem(target, entry.item, 1, md) then
    if not NZ.Inventory.addItem(src, entry.item, 1, md) then
      lib.print.error(('[nayzeee-garages] carlock: key item %s of %s lost during a hand-over (inventory refused the rollback)'):format(entry.item, plate))
    end
    return false, L('They cannot carry the key')
  end
  push(src, plate)
  push(target, plate)
  log('vehicle.keyHandOver', src, { plate = plate, target = identifierOf(target), kind = md.kind })
  return true, nil
end

---------------------------------------------------------------------------------------
-- Garage hand-out (bridge/server/keys.lua)
---------------------------------------------------------------------------------------

--- A garage / spawner vehicle was created for `src`: it starts unlocked; spawner vehicles and
--- non-owners get a temporary key; in physical mode the owner gets a key item when they have
--- no valid key (Config.CarLock.giveKeyOnRetrieve); in virtual mode a temporary key unless the
--- player already has a key.
---@param src number
---@param entity number
---@param plate string
---@param opts table|nil { spawner = boolean }
---@return boolean
function CarLock.onVehicleOut(src, entity, plate, opts)
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate or not isVehicle(entity) then return false end
  knownPlates[entity] = plate
  CarLock.setLocked(entity, false)
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
  local spawner = (type(opts) == 'table' and opts.spawner == true) or (type(out) == 'table' and out.spawner == true)
  accessOut[entity] = nil
  if spawner then return CarLock.grantTemp(src, plate, 'spawner') end

  local has, kind = CarLock.hasKey(src, plate)
  local row = rowOf(plate)
  local id = identifierOf(src)
  -- not the owner, but a share / fleet access: keys from this hand-out end with that access
  -- (unshare, leaving the job), also the ones other scripts ask for later (canAcquire)
  local viaAccess = row ~= nil and id ~= nil and row.owner ~= id and ownerAccess(src, plate) ~= nil
  accessOut[entity] = viaAccess and id or nil
  if CarLock.mode() == 'physical' then
    if has and kind ~= 'temp' then return true end
    if cfg().giveKeyOnRetrieve ~= false and row and id and row.owner == id then
      local given = CarLock.giveKeyItem(src, plate, { model = row.model, reason = 'garage' })
      if given then return true end
      NZ.Bridge.notify(src, L('You cannot carry the key: you got a temporary key instead'), 'warning')
    end
  end
  if has then return true end
  return CarLock.grantTemp(src, plate, 'garage', nil, viaAccess)
end

---------------------------------------------------------------------------------------
-- Resource restart: temporary keys, unowned key versions and recorded plates survive a
-- restart of this resource (KVP snapshot written on stop, read once at start, only within
-- the same server session).
---------------------------------------------------------------------------------------

local function serverBoot()
  return os.time() - math.floor(GetGameTimer() / 1000)
end

local function snapshot()
  local keys = {}
  local nowTs = os.time()
  for holder, list in pairs(temp) do
    if not holder:match('^src:') then
      for plate, entry in pairs(list) do
        if entry.expires > nowTs then
          keys[holder] = keys[holder] or {}
          keys[holder][plate] = { expires = entry.expires, reason = entry.reason, at = entry.at, access = entry.access }
        end
      end
    end
  end
  local plates, locks = {}, {}
  for entity, plate in pairs(knownPlates) do
    if isVehicle(entity) then plates[tostring(NetworkGetNetworkIdFromEntity(entity))] = plate end
  end
  for entity, locked in pairs(lockState) do
    if isVehicle(entity) then locks[tostring(NetworkGetNetworkIdFromEntity(entity))] = locked end
  end
  local viaAccess = {}
  for entity, identifier in pairs(accessOut) do
    if isVehicle(entity) then viaAccess[tostring(NetworkGetNetworkIdFromEntity(entity))] = identifier end
  end
  return { boot = serverBoot(), temp = keys, versions = unownedVersions, plates = plates, locks = locks,
    accessOut = viaAccess }
end

local function restore()
  local ok, raw = pcall(GetResourceKvpString, SESSION_KVP)
  if not ok or type(raw) ~= 'string' or raw == '' then return end
  pcall(DeleteResourceKvp, SESSION_KVP)
  local okDecode, data = pcall(json.decode, raw)
  if not okDecode or type(data) ~= 'table' then return end
  if math.abs((tonumber(data.boot) or 0) - serverBoot()) > 15 then return end -- server restarted
  local nowTs, count = os.time(), 0
  for holder, list in pairs(type(data.temp) == 'table' and data.temp or {}) do
    for plate, entry in pairs(type(list) == 'table' and list or {}) do
      local p = normPlate(plate)
      local expires = type(entry) == 'table' and tonumber(entry.expires) or nil
      if p and expires and expires > nowTs and type(holder) == 'string' then
        temp[holder] = temp[holder] or {}
        temp[holder][p] = { expires = expires, reason = tostring(entry.reason or 'other'), at = tonumber(entry.at) or nowTs,
          access = entry.access == true or nil }
        count = count + 1
      end
    end
  end
  for plate, v in pairs(type(data.versions) == 'table' and data.versions or {}) do
    local p, n = normPlate(plate), tonumber(v)
    if p and n then unownedVersions[p] = math.tointeger(math.floor(n)) end
  end
  for netId, plate in pairs(type(data.plates) == 'table' and data.plates or {}) do
    local entity = NetworkGetEntityFromNetworkId(math.tointeger(tonumber(netId) or 0) or 0)
    local p = normPlate(plate)
    if p and isVehicle(entity) then knownPlates[entity] = p end
  end
  for netId, locked in pairs(type(data.locks) == 'table' and data.locks or {}) do
    local entity = NetworkGetEntityFromNetworkId(math.tointeger(tonumber(netId) or 0) or 0)
    if isVehicle(entity) and type(locked) == 'boolean' then
      lockState[entity] = locked
      bagWritten.nzLocked[entity] = locked
    end
  end
  for netId, identifier in pairs(type(data.accessOut) == 'table' and data.accessOut or {}) do
    local entity = NetworkGetEntityFromNetworkId(math.tointeger(tonumber(netId) or 0) or 0)
    if isVehicle(entity) and type(identifier) == 'string' and identifier ~= '' and #identifier <= 64 then
      accessOut[entity] = identifier
    end
  end
  if count > 0 then lib.print.info(('[nayzeee-garages] carlock: %d temporary key(s) kept across the restart'):format(count)) end
end

CreateThread(function()
  local ok, err = pcall(restore)
  if not ok then lib.print.warn(('[nayzeee-garages] carlock: restore failed: %s'):format(tostring(err))) end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  local ok, encoded = pcall(json.encode, snapshot())
  if ok and type(encoded) == 'string' then pcall(SetResourceKvp, SESSION_KVP, encoded) end
end)

AddEventHandler('entityRemoved', function(entity)
  knownPlates[entity] = nil
  accessOut[entity] = nil
  lockState[entity] = nil
  bagWritten.nzLocked[entity], bagWritten.nzAlarm[entity] = nil, nil
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  temp['src:' .. tostring(math.tointeger(src) or src)] = nil
  for _, entry in pairs(classVotes) do
    local changed = false
    for _, voters in pairs(entry.votes) do
      if voters[src] then
        voters[src] = nil
        voters.n = voters.n - 1
        changed = true
      end
    end
    if changed then
      entry.best, entry.bestCount = nil, 0
      for class, voters in pairs(entry.votes) do
        if voters.n > entry.bestCount then entry.best, entry.bestCount = class, voters.n end
      end
    end
  end
end)

-- Character switch: the cached virtual keys / access of that character are refreshed lazily.
AddEventHandler('nz:server:playerUnloaded', function(src)
  local id = identifierOf(src)
  if id then virtualCache[id] = nil end
end)
