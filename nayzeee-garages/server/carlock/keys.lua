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
  'nzLocked' (bool), 'nzLockFx' ({ n, locked }) and 'nzAlarm' ({ id, mode, seconds } | false)
  that every client applies (client/carlock/lock.lua).
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

local temp = {}                -- [holder] = { [plate] = { expires, reason, at } }
local unownedVersions = {}     -- [plate] = version of NPC / spawned vehicles
local versionCache = {}        -- [plate] = { v, at }
local rowCache = {}            -- [plate] = { row|false, at }
local accessCache = {}         -- [plate] = { [identifier] = { access|false, at } }
local virtualCache = {}        -- [identifier] = { set, at }
local knownPlates = {}         -- [entity] = real plate recorded by the server
local classVotes = {}          -- [modelHash] = { votes = { [class] = { [src] = true } }, best }
local classCount = 0
local sigCache = {}            -- [sig] = 'plate|version|kind|id' of verified items
local sigCount = 0
local fxCounter = 0
local alarmCounter = 0

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

local secret = nil

--- Server secret for key signatures: convar nz_carlock_secret (set it when several servers
--- share one database), else a random value kept in this resource's KVP store.
local function keySecret()
  if secret then return secret end
  local convar = GetConvar('nz_carlock_secret', '')
  if type(convar) == 'string' and #convar >= 16 then
    secret = convar
    return secret
  end
  local okRead, stored = pcall(GetResourceKvpString, SECRET_KVP)
  if okRead and type(stored) == 'string' and #stored >= 32 then
    secret = stored
    return secret
  end
  local entropy = { tostring(os.time()), tostring(GetGameTimer()), tostring(os.clock()), tostring({}) }
  for _ = 1, 8 do entropy[#entropy + 1] = tostring(math.random(0, 0x7fffffff)) end
  secret = hex(sha256(table.concat(entropy, '|')))
  local okWrite = pcall(SetResourceKvp, SECRET_KVP, secret)
  if not okWrite then
    lib.print.warn('[nayzeee-garages] carlock: could not store the key secret (KVP); key items will stop working after a restart. Set the convar nz_carlock_secret.')
  end
  return secret
end

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

--- Best known GTA class of a vehicle entity (nil when unknown).
---@param entity number
---@return number|nil
function CarLock.classOf(entity)
  if not isVehicle(entity) then return nil end
  local hash = GetEntityModel(entity)
  if sharedClasses == nil then pcall(loadSharedClasses) end
  if sharedClasses and sharedClasses[hash] then return sharedClasses[hash] end
  local entry = classVotes[hash]
  if entry and entry.best then return entry.best end
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

--- Effective key mode: 'physical' (key items) or 'virtual'.
---@return 'physical'|'virtual'
function CarLock.mode()
  local ok, meta = pcall(NZ.Inventory.supportsMetadata)
  return CarLock.resolveMode(ok and meta == true)
end

--- Current key version of a plate (owned: nz_key_version; others: memory).
---@param plate string
---@return integer
function CarLock.keyVersion(plate)
  plate = normPlate(plate)
  if not plate then return 0 end
  local hit = versionCache[plate]
  if hit and now() - hit.at < VERSION_TTL then return hit.v end
  local v = nil
  if NZ.DB.keys and type(NZ.DB.keys.version) == 'function' then
    local ok, res = pcall(NZ.DB.keys.version, plate)
    if ok then v = res end
  end
  if v == nil then v = unownedVersions[plate] or 0 end
  v = math.tointeger(v) or 0
  versionCache[plate] = { v = v, at = now() }
  return v
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
--- opts = { kind = 'key'|'fob', model = spawn name, label = model label }
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
  local version = CarLock.keyVersion(plate)
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
    display = false, -- qb-inventory: show only the description, not every field
  }
end

--- Is this key item metadata genuine and current? reason: 'invalid' | 'plate' | 'version'.
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
  if version ~= CarLock.keyVersion(p) then return false, 'version' end
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
--- opts = { kind = 'key'|'fob', model, label, reason }
---@param src number
---@param plate string
---@param opts table|nil
---@return boolean ok, string|nil error (translated)
function CarLock.giveKeyItem(src, plate, opts)
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate then return false, L('Invalid request') end
  if not NZ.Inventory.supportsMetadata() then return false, L('Your inventory cannot hold vehicle keys') end
  opts = type(opts) == 'table' and opts or {}
  local model = opts.model
  if type(model) ~= 'string' then
    local row = rowOf(plate)
    model = row and row.model or nil
  end
  local md = CarLock.keyMetadata(plate, { kind = opts.kind, model = model, label = opts.label })
  if not md then return false, L('Invalid request') end
  local item = CarLock.itemName(md.kind)
  if not NZ.Inventory.addItem(src, item, 1, md) then
    return false, L('You cannot carry the key')
  end
  push(src, plate)
  log('vehicle.keyItem', src, { plate = plate, kind = md.kind, version = md.version, reason = opts.reason })
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
---@param src number
---@param plate string
---@param reason string|nil
---@param hours number|nil
---@return boolean
function CarLock.grantTemp(src, plate, reason, hours)
  src, plate = validSrc(src), normPlate(plate)
  if not src or not plate then return false end
  hours = tonumber(hours) or CarLock.tempHours()
  if hours ~= hours or hours <= 0 then hours = CarLock.tempHours() end
  hours = math.min(hours, 24 * 30)
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
--- { { identifier, name, kind = 'virtual'|'temp', grantedBy?, createdAt?, expires? } }.
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
        grantedBy = row.grantedBy, createdAt = row.createdAt }
    end
  end
  for holder in pairs(temp) do
    local entry = tempEntry(holder, plate)
    if entry and not seen[holder] and not holder:match('^src:') then
      out[#out + 1] = { identifier = holder, name = nameOf(holder), kind = 'temp', expires = entry.expires,
        reason = entry.reason }
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
  local holder = holderOf(src)
  if tempEntry(holder, plate) then return true, 'temp' end
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
    if tempEntry(holder, plate) then add(plate, 'temp') end
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
    for _, plate in ipairs(okShares and shared or {}) do add(plate, 'owner') end
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

--- New key version for `plate`: older key items stop working, every virtual key and every
--- temporary key (except `keepIdentifier`'s) is removed. Returns the new version.
---@param plate string
---@param keepIdentifier string|nil
---@return integer|nil
function CarLock.rekey(plate, keepIdentifier)
  plate = normPlate(plate)
  if not plate then return nil end
  local newVersion = nil
  if NZ.DB.keys and type(NZ.DB.keys.bumpVersion) == 'function' then
    local ok, res = pcall(NZ.DB.keys.bumpVersion, plate)
    if ok then newVersion = res end
  end
  if newVersion == nil then
    newVersion = (unownedVersions[plate] or CarLock.keyVersion(plate)) + 1
    unownedVersions[plate] = newVersion
  end
  versionCache[plate] = { v = newVersion, at = now() }

  local affected = {}
  if NZ.DB.keys and type(NZ.DB.keys.list) == 'function' then
    for _, row in ipairs(NZ.DB.keys.list(plate) or {}) do affected[row.identifier] = true end
    NZ.DB.keys.clear(plate)
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
  log('vehicle.rekey', nil, { plate = plate, version = newVersion, resource = GetInvokingResource() })
  return newVersion
end

---------------------------------------------------------------------------------------
-- Locks and alarm
---------------------------------------------------------------------------------------

--- Lock / unlock a vehicle for everyone. fx = true plays the lock feedback (sound, lights,
--- horn chirp) on nearby clients and stops a sounding alarm when unlocking.
---@param entity number
---@param locked boolean
---@param fx boolean|nil
---@return boolean
function CarLock.setLocked(entity, locked, fx)
  if not isVehicle(entity) then return false end
  locked = locked == true
  pcall(SetVehicleDoorsLocked, entity, locked and 2 or 1)
  local bag = Entity(entity).state
  bag:set('nzLocked', locked, true)
  if fx then
    fxCounter = fxCounter + 1
    bag:set('nzLockFx', { n = fxCounter, locked = locked }, true)
    if not locked and bag.nzAlarm then bag:set('nzAlarm', false, true) end
  end
  return true
end

--- Is the vehicle locked (state bag, else the native lock status)?
---@param entity number
---@return boolean
function CarLock.isLocked(entity)
  if not isVehicle(entity) then return false end
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
  local bag = Entity(entity).state
  bag:set('nzAlarm', { id = id, mode = mode, seconds = seconds }, true)
  SetTimeout(seconds * 1000, function()
    if isVehicle(entity) then
      local cur = Entity(entity).state.nzAlarm
      if type(cur) == 'table' and cur.id == id then Entity(entity).state:set('nzAlarm', false, true) end
    end
  end)
  return true
end

--- Silence a sounding alarm.
---@param entity number
function CarLock.stopAlarm(entity)
  if isVehicle(entity) and Entity(entity).state.nzAlarm then
    Entity(entity).state:set('nzAlarm', false, true)
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
  if spawner then return CarLock.grantTemp(src, plate, 'spawner') end

  local has, kind = CarLock.hasKey(src, plate)
  if CarLock.mode() == 'physical' then
    if has and kind ~= 'temp' then return true end
    local row = rowOf(plate)
    local id = identifierOf(src)
    if cfg().giveKeyOnRetrieve ~= false and row and id and row.owner == id then
      local given = CarLock.giveKeyItem(src, plate, { model = row.model, reason = 'garage' })
      if given then return true end
      NZ.Bridge.notify(src, L('You cannot carry the key: you got a temporary key instead'), 'warning')
    end
  end
  if has then return true end
  return CarLock.grantTemp(src, plate, 'garage')
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
          keys[holder][plate] = { expires = entry.expires, reason = entry.reason, at = entry.at }
        end
      end
    end
  end
  local plates = {}
  for entity, plate in pairs(knownPlates) do
    if isVehicle(entity) then plates[tostring(NetworkGetNetworkIdFromEntity(entity))] = plate end
  end
  return { boot = serverBoot(), temp = keys, versions = unownedVersions, plates = plates }
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
        temp[holder][p] = { expires = expires, reason = tostring(entry.reason or 'other'), at = tonumber(entry.at) or nowTs }
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
  if knownPlates[entity] then knownPlates[entity] = nil end
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  temp['src:' .. tostring(math.tointeger(src) or src)] = nil
  for _, entry in pairs(classVotes) do
    for _, voters in pairs(entry.votes) do
      if voters[src] then voters[src] = nil end
    end
  end
end)

-- Character switch: the cached virtual keys / access of that character are refreshed lazily.
AddEventHandler('nz:server:playerUnloaded', function(src)
  local id = identifierOf(src)
  if id then virtualCache[id] = nil end
end)
