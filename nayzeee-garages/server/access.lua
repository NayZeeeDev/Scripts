--[[
  nayzeee-garages — access control (NZ.Access), server side.

  Who may use a location (restrictions, job / gang rules, private group membership,
  house keys), server-side proximity checks, per-player garage sessions and rate limits.
  Never trusts client coordinates: distances use GetEntityCoords(GetPlayerPed(src)).
]]

local Access = NZ.Access
local Utils = NZ.Utils

local sessions = {}   -- [src] = session
local limits = {}     -- [src] = { [bucket] = lastAllowedAt (ms) }
local abuse = {}      -- [src] = { count, windowStart, loggedAt }

local ABUSE_WINDOW = 10000   -- ms
local ABUSE_THRESHOLD = 15   -- denied calls inside the window before it is logged
local ABUSE_LOG_EVERY = 60000

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('access: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function contains(list, value)
  if type(list) ~= 'table' then return false end
  for i = 1, #list do
    if list[i] == value then return true end
  end
  return false
end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  return src
end

--- Squared distance check between the player position and one point-like value.
local function pointWithin(point, px, py, pz, maxSq)
  local target = point
  if type(point) == 'table' and point.coords ~= nil then target = point.coords end
  local v = Utils.v3(target)
  if not v then return false end
  local dx, dy, dz = v.x - px, v.y - py, v.z - pz
  return dx * dx + dy * dy + dz * dz <= maxSq
end

local function isSinglePoint(points)
  local t = type(points)
  if t == 'vector3' or t == 'vector4' then return true end
  return t == 'table' and (points.coords ~= nil or points.x ~= nil)
end

--- True when the player is inside a garage interior instance that belongs to garageKey.
local function insideInterior(src, garageKey)
  local Interiors = NZ.Interiors
  if type(Interiors.playerInstance) ~= 'function' or type(Interiors.instances) ~= 'table' then return false end
  local ok, key = pcall(Interiors.playerInstance, src)
  if not ok or key == nil then return false end
  local instance = Interiors.instances[key]
  return type(instance) == 'table' and instance.garageKey ~= nil and instance.garageKey == garageKey
end

---------------------------------------------------------------------------------------
-- Permissions
---------------------------------------------------------------------------------------

--- True when the player's job (or gang) matches one of the rules with a high enough grade.
---@param src number
---@param rules table[] { { name, minGrade } }
---@param kind 'job'|'gang'
---@return boolean
function Access.jobAllowed(src, rules, kind)
  if type(rules) ~= 'table' or #rules == 0 then return false end
  src = validSrc(src)
  if not src then return false end
  local getter = kind == 'gang' and NZ.Bridge.getGang or NZ.Bridge.getJob
  if type(getter) ~= 'function' then return false end
  local ok, data = pcall(getter, src)
  if not ok or type(data) ~= 'table' or type(data.name) ~= 'string' then return false end
  local name = data.name:lower()
  local grade = tonumber(data.grade) or 0
  for i = 1, #rules do
    local rule = rules[i]
    if type(rule) == 'table' and type(rule.name) == 'string' and rule.name:lower() == name
        and grade >= (tonumber(rule.minGrade) or 0) then
      return true
    end
  end
  return false
end

--- May this player use the location (open the menu, store, retrieve)?
--- Proximity is NOT checked here (see isNear / requireSession).
---@param src number
---@param location table Location or house location
---@return boolean allowed, string|nil reason (translated)
function Access.canUse(src, location)
  src = validSrc(src)
  if not src or type(location) ~= 'table' then return false, L('Garage not found') end
  if location.enabled == false then return false, L('This garage is closed') end

  local kind = location.kind
  if kind == 'impound' then return true end

  if kind == 'garage' then
    local restriction = type(location.restriction) == 'table' and location.restriction or {}
    local rtype = restriction.type or 'everyone'
    if rtype == 'everyone' then return true end
    if rtype == 'job' or rtype == 'gang' then
      if Access.jobAllowed(src, restriction.rules, rtype) then return true end
      if rtype == 'gang' then return false, L('This garage is reserved for another gang') end
      return false, L('This garage is reserved for another job')
    end
    if rtype == 'identifier' then
      local identifier = identifierOf(src)
      if identifier and contains(restriction.identifiers, identifier) then return true end
    end
    return false, L('You do not have access to this garage')
  end

  if kind == 'job' then
    local ownerKind = location.owner == 'gang' and 'gang' or 'job'
    if Access.jobAllowed(src, location.jobs, ownerKind) then return true end
    if ownerKind == 'gang' then return false, L('This garage is reserved for another gang') end
    return false, L('This garage is reserved for another job')
  end

  if kind == 'private' then
    local identifier = identifierOf(src)
    if identifier and type(NZ.Private.groupsFor) == 'function' then
      local ok, groups = pcall(NZ.Private.groupsFor, identifier, location.id)
      if ok and type(groups) == 'table' and next(groups) ~= nil then return true end
    end
    return false, L('You do not have a garage here')
  end

  if kind == 'house' then
    local identifier = identifierOf(src)
    if identifier and type(NZ.Housing.hasAccess) == 'function' then
      local ok, allowed = pcall(NZ.Housing.hasAccess, identifier, location.houseId)
      if ok and allowed == true then return true end
    end
    return false, L('You do not have access to this house garage')
  end

  return false, L('You do not have access to this garage')
end

--- Is the player's ped within maxDist of any point?
---@param src number
---@param points table list of { coords = vec } / vectors / {x,y,z} tables, or a single point
---@param maxDist number|nil default settings garages.maxDistance
---@return boolean
function Access.isNear(src, points, maxDist)
  src = validSrc(src)
  if not src or points == nil then return false end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  local pos = GetEntityCoords(ped)
  if not pos then return false end
  maxDist = tonumber(maxDist) or tonumber(NZ.Settings.get('garages.maxDistance', 25.0)) or 25.0
  local maxSq = maxDist * maxDist
  local px, py, pz = pos.x, pos.y, pos.z

  if isSinglePoint(points) then return pointWithin(points, px, py, pz, maxSq) end
  if type(points) ~= 'table' then return false end
  for i = 1, #points do
    if pointWithin(points[i], px, py, pz, maxSq) then return true end
  end
  return false
end

--- Admin permission (ace 'nayzeee-garages.admin' or ServerConfig.AdminGroups via the bridge).
---@param src number
---@return boolean
function Access.isAdmin(src)
  src = validSrc(src)
  if not src then return false end
  if type(NZ.Bridge.isAdmin) == 'function' then
    local ok, res = pcall(NZ.Bridge.isAdmin, src)
    if ok then return res == true end
    lib.print.warn(('access: isAdmin failed: %s'):format(tostring(res)))
  end
  return IsPlayerAceAllowed(tostring(src), 'nayzeee-garages.admin') == true
end

---------------------------------------------------------------------------------------
-- Sessions (the garage a player currently has open)
---------------------------------------------------------------------------------------

--- Remember which garage the player opened. Replaces any previous session.
---@param src number
---@param garageKey string 'L..' | 'G..' | 'H..'
---@param location table|nil resolved from garageKey when nil
---@param extra table|nil merged into the session (module specific fields)
---@return table|nil session
function Access.openSession(src, garageKey, location, extra)
  src = validSrc(src)
  if not src then return nil end
  if type(location) ~= 'table' and type(garageKey) == 'string' then
    local resolved = NZ.Locations.resolveKey(garageKey)
    location = resolved and resolved.location or nil
  end
  local kind, id = Utils.key.parse(garageKey)
  local session = {
    garageKey = garageKey,
    location = location,
    locationId = type(location) == 'table' and location.id or nil,
    groupId = kind == 'G' and id or nil,
    houseId = kind == 'H' and id or nil,
    openedAt = os.time(),
  }
  if type(extra) == 'table' then
    for k, v in pairs(extra) do session[k] = v end
  end
  sessions[src] = session
  return session
end

--- The player's open session (no distance check).
---@param src number
---@return table|nil
function Access.getSession(src)
  src = validSrc(src)
  return src and sessions[src] or nil
end

--- Forget the player's session.
---@param src number
function Access.closeSession(src)
  src = validSrc(src)
  if src then sessions[src] = nil end
end

--- The player's session, only while the garage still exists / is enabled and the player is
--- near its open, store or spawn points (or inside an interior instance of that garage).
--- Refreshes session.location from the cache so admin edits apply immediately.
---@param src number
---@param maxDist number|nil default settings garages.maxDistance
---@return table|nil session, string|nil error (translated)
function Access.requireSession(src, maxDist)
  src = validSrc(src)
  local session = src and sessions[src]
  if not session then return nil, L('No garage is open') end

  if session.locationId ~= nil then
    local fresh = NZ.Locations.get(session.locationId)
    if not fresh then
      sessions[src] = nil
      return nil, L('This garage is no longer available')
    end
    if fresh.enabled == false then return nil, L('This garage is closed') end
    session.location = fresh
  end

  if session.groupId ~= nil and type(NZ.Private.getGroup) == 'function' then
    local ok, group = pcall(NZ.Private.getGroup, session.groupId)
    if ok and group == nil then
      sessions[src] = nil
      return nil, L('This garage is no longer available')
    end
  end

  if insideInterior(src, session.garageKey) then return session end

  local loc = session.location
  if type(loc) == 'table' and (Access.isNear(src, loc.openPoints, maxDist)
      or Access.isNear(src, loc.storePoints, maxDist)
      or Access.isNear(src, loc.spawnPoints, maxDist)) then
    return session
  end
  return nil, L('You are too far from the garage')
end

---------------------------------------------------------------------------------------
-- Rate limiting
---------------------------------------------------------------------------------------

--- Throttle an action per player and bucket.
---@param src number
---@param bucket string e.g. 'garage:retrieve'
---@param ms number|nil minimum interval between allowed calls (default 500)
---@return boolean allowed
function Access.rateLimit(src, bucket, ms)
  src = validSrc(src)
  if not src then return true end
  bucket = tostring(bucket or 'default')
  ms = tonumber(ms) or 500
  local now = GetGameTimer()
  local perPlayer = limits[src]
  if not perPlayer then
    perPlayer = {}
    limits[src] = perPlayer
  end
  local last = perPlayer[bucket]
  if last and now - last < ms then
    local a = abuse[src]
    if not a or now - a.windowStart > ABUSE_WINDOW then
      a = { count = 0, windowStart = now, loggedAt = a and a.loggedAt or nil }
      abuse[src] = a
    end
    a.count = a.count + 1
    if a.count >= ABUSE_THRESHOLD and (not a.loggedAt or now - a.loggedAt > ABUSE_LOG_EVERY) then
      a.loggedAt = now
      log('security.rateLimit', src, { bucket = bucket, denied = a.count, windowMs = ABUSE_WINDOW })
    end
    return false
  end
  perPlayer[bucket] = now
  return true
end

--- Drop every rate-limit entry of a player (called when the player leaves).
---@param src number
function Access.clearRateLimits(src)
  src = validSrc(src)
  if not src then return end
  limits[src] = nil
  abuse[src] = nil
end
