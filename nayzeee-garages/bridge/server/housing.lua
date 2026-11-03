--[[
  nayzeee-garages — housing integration core (server): NZ.Housing.

  House garages are runtime-only locations (NZ.Locations.registerHouse, garage key
  'H' .. houseId). This core
    - runs the loaders registered by bridge/server/housing/<script>.lua (NZ.Housing.addLoader)
      for every housing script Config.Integrations.housing allows ('auto' = every supported
      script that is started, 'none', one resource name or a list). A loader returns houses
      '<prefix>:<id>' with their owners + key holders and, when the script stores them, the
      garage coordinates. Reloads every 5 minutes, on hints from the housing scripts (events,
      resource start, the RefreshHousing export) and when a client asks ('nz:housing:refresh',
      at most one reload per minute for those; client-triggered housing events at most one per
      30 s and loader). A loader that fails keeps the houses it loaded before; an empty read is
      only trusted when a read at least a minute later confirms it;
    - answers hasAccess (live check through the script's key export when the loader has one,
      then the cached owner / key holder sets; a definitive "no" from a loader whose check is
      authoritative overrides the cached sets) and viewsFor;
    - backs the RegisterHouseGarage / RemoveHouseGarage / SetHouseAccess / RefreshHousing exports;
    - serves 'nz:housing:hook' for housing scripts that own the garage interaction and call the
      OpenHouseGarage / StoreHouseGarage client exports (bridge/client/housing.lua): checks access
      live, registers the garage at the player's SERVER-SIDE position when the house has no known
      garage coordinates (hidden: the housing script draws the interaction, positions are kept in
      resource KVP across restarts, within 'nayzeee_housing_hook_range' metres of the property
      when the loader knows where it is; an existing garage never moves while the property's
      position is unknown) and returns the player's house views. Only hook-driven loaders
      (hook = 'always', or 'whenUsed' with create = true) get new garages this way, under their
      canonical id (numeric ids normalised: 'tk:1.0' -> 'tk:1'); the others only open / store at
      garages that already exist;
    - pushes 'nz:client:houses' (list of client views) to online players whose houses changed.
  Ids stay compatible with older versions: 'qb:<house name>' (qb-houses), 'ps:<property id>'
  (ps-housing); vehicles stored under 'H..' keys keep working.
]]

local Housing = NZ.Housing
local Utils = NZ.Utils

local REFRESH_MS = 5 * 60 * 1000   -- periodic reload of every loader
local MIN_RELOAD_MS = 10000        -- minimum gap between two reloads (any trigger)
local CLIENT_RELOAD_MS = 60000     -- minimum gap before a client request reloads
local PUSH_DELAY_MS = 500          -- coalesce change pushes
local LOAD_WAIT_MS = 15000         -- max wait for a reload already running
local CLIENT_RATE_MS = 2000        -- per player rate limit of the refresh callback
local HOOK_RATE_MS = 1500          -- per player rate limit of the hook callback
local TICK_MS = 15000              -- housekeeping (grants, caches, per-loader intervals)
local LIVE_TTL_MS = 10000          -- cache of live access checks
local LIVE_GRANT_MS = 30 * 60 * 1000 -- a successful hook keeps the house in the player's list
local HOOK_MOVE_DIST = 6.0         -- metres: a hook garage moves when used this far away (at most
                                   -- half of the garages.maxDistance setting)
local HOOK_RANGE = 200.0           -- metres: a hook garage must be this close to the property
local NET_HINT_GAP_MS = 30000      -- minimum gap between two reloads of a loader from client events
local NET_HINT_RATE_MS = 5000      -- per player rate limit of those events
local EMPTY_CONFIRM_MS = 60000     -- an empty read (or a "gone" answer) needs a confirming read this much later
local YIELD_EVERY = 200            -- long loops yield (Wait(0)) after this many items
local MAX_ACCESS = 200             -- identifiers per house and per access source
local MAX_ID_LENGTH = 60
local KVP_SPOT = 'nz_housing:spot:'
local HOOK_CONVAR = 'nayzeee_housing_hooked'      -- scripts whose hook file is installed
local RANGE_CONVAR = 'nayzeee_housing_hook_range' -- metres (0 = no property distance check)

local loaders = {}        -- ordered loader definitions
local byPrefix = {}       -- [prefix] = definition
Housing.loaders = byPrefix

local registry = {}       -- [houseId] = { source, origin = 'loader'|'hook'|'export', sig, name, hidden, coords }
local loaderAccess = {}   -- [houseId] = { [identifier] = true } (from the loaders)
local exportAccess = {}   -- [houseId] = { [identifier] = true } (from SetHouseAccess)
local liveAccess = {}     -- [houseId] = { [identifier] = true } (granted by a successful hook)
local liveExpiry = {}     -- [houseId .. '\n' .. identifier] = GetGameTimer() expiry
local index = {}          -- [identifier] = { [houseId] = true } (union of the access sources)
local dirty = {}          -- [identifier] = true, players whose house list must be re-sent
local lastSent = {}       -- [src] = fingerprint of the last 'nz:client:houses' push

local entries = {}        -- [houseId] = last loader entry { name, coords, spawn, store }
local rawIds = {}         -- [houseId] = id exactly as the housing script returned it
local loaderIds = {}      -- [prefix] = { [houseId] = true } houses the loader reported
local spots = {}          -- [houseId] = { x, y, z, w } hook positions (persisted)
local hookSeen = {}       -- [prefix] = true once its hook was used (console hint printed)
local liveCache = {}      -- [identifier .. '\n' .. houseId] = { at, result }
local emptySince = {}     -- [prefix] = GetGameTimer() of the first of consecutive empty reads
local goneSince = {}      -- [houseId] = GetGameTimer() of the first "does not exist" answer (incomplete loaders)
local lastLoaderLoad = {} -- [prefix] = GetGameTimer() of the last successful read
local lastReadAt = {}     -- [prefix] = GetGameTimer() of the last read attempt
local netHintPending = {} -- [prefix] = true while a reload asked for by a client event is scheduled
local netHintAt = {}      -- [prefix] = GetGameTimer() when the last such reload was asked for
local warned = {}         -- warnOnce keys

local booted = false
local loading = false
local lastLoadAt = nil
local trailingAt = nil       -- GetGameTimer() when the scheduled trailing reload runs
local trailingGen = 0
local pushScheduled = false
local pendingAll, pendingSet = false, {}
local hintTimers = {}

---------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------

--- House id normalisation; mirrors NZ.Locations so both modules use the same strings.
---@param value string|number
---@return string|nil
local function canonicalId(value)
  if type(value) == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    value = tostring(math.tointeger(value) or value)
  end
  if type(value) ~= 'string' then return nil end
  local s = Utils.cleanText(value, MAX_ID_LENGTH)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

local function known(id)
  return registry[id] ~= nil or loaderAccess[id] ~= nil or exportAccess[id] ~= nil or liveAccess[id] ~= nil
end

--- Resolve an id that may carry the 'H' garage-key prefix.
local function knownId(value)
  local id = canonicalId(value)
  if not id then return nil end
  if known(id) then return id end
  if id:sub(1, 1) == 'H' and #id > 1 then
    local stripped = id:sub(2)
    if known(stripped) then return stripped end
    local prefix = stripped:match('^([%w_]+):.')
    if prefix and byPrefix[prefix] then return stripped end
  end
  return id
end

--- '<prefix>:<raw>' -> prefix, raw (nil for ids without a loader prefix).
local function splitId(id)
  if type(id) ~= 'string' then return nil, nil end
  local prefix, raw = id:match('^([%w_]+):(.+)$')
  if prefix and byPrefix[prefix] then return prefix, raw end
  return nil, nil
end

local function cleanIdentifier(value)
  if type(value) == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    value = tostring(math.tointeger(value) or value)
  end
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' or #s > 64 or s:find('%c') then return nil end
  return s
end

local function decodeJson(value)
  if type(value) == 'table' then return value end
  if type(value) ~= 'string' or value == '' or value == 'null' then return nil end
  local ok, res = pcall(json.decode, value)
  if ok and type(res) == 'table' then return res end
  return nil
end

local function isArray(t)
  if type(t) ~= 'table' then return false end
  if next(t) == nil then return true end
  return t[1] ~= nil and Utils.isArray(t)
end

local function identifierFields(entry)
  return entry.citizenid or entry.identifier or entry.cid or entry.citizenId or entry.charid
end

--- Add identifiers from a list (strings or { citizenid / identifier / cid = ... } entries).
local function addValues(set, list)
  list = decodeJson(list)
  if not list then return end
  local count = Utils.count(set)
  for _, entry in pairs(list) do
    if count >= MAX_ACCESS then break end
    local id
    if type(entry) == 'table' then
      id = cleanIdentifier(identifierFields(entry))
    else
      id = cleanIdentifier(entry)
    end
    if id and not set[id] then
      set[id] = true
      count = count + 1
    end
  end
end

--- Add identifiers from a map keyed by identifier ({ [identifier] = anything }).
local function addKeys(set, map)
  map = decodeJson(map)
  if not map then return end
  local count = Utils.count(set)
  for key, value in pairs(map) do
    if count >= MAX_ACCESS then break end
    local id = type(key) == 'string' and cleanIdentifier(key) or nil
    if not id and type(value) == 'table' then id = cleanIdentifier(identifierFields(value)) end
    if id and value ~= false and not set[id] then
      set[id] = true
      count = count + 1
    end
  end
end

--- Add identifiers from a list or a map keyed by identifier (whichever shape arrives).
local function addAny(set, value)
  local decoded = decodeJson(value)
  if not decoded then return end
  if isArray(decoded) then addValues(set, decoded) else addKeys(set, decoded) end
end

local function coordOk(n, limit)
  return type(n) == 'number' and n == n and n > -limit and n < limit
end

--- Plain {x,y,z,w} from a vector / table / JSON string; nil for unusable or (0,0) points.
local function vec4Of(value)
  local v = Utils.v4(decodeJson(value) or value)
  if not v then return nil end
  if not (coordOk(v.x, 20000) and coordOk(v.y, 20000) and coordOk(v.z, 5000)) then return nil end
  if math.abs(v.x) < 0.01 and math.abs(v.y) < 0.01 then return nil end
  if not coordOk(v.w, 1e6) then v.w = 0.0 end
  return v
end

local function round(n)
  return ('%.2f'):format(tonumber(n) or 0)
end

local function coordSig(v)
  if not v then return '-' end
  return table.concat({ round(v.x), round(v.y), round(v.z), round(v.w) }, ',')
end

local function registrationSig(name, coords, spawn, store, hidden)
  return table.concat({ tostring(name or ''), coordSig(coords), coordSig(spawn), coordSig(store), tostring(hidden == true) }, '|')
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(message)
end

local function lower(s)
  return type(s) == 'string' and Utils.trim(s):lower() or nil
end

--- Yield every YIELD_EVERY items of a long loop (only inside a thread; loops over local data).
local function yieldEvery(i)
  if i % YIELD_EVERY == 0 and coroutine.isyieldable() then Wait(0) end
end

---------------------------------------------------------------------------------------
-- Configuration (Config.Integrations.housing)
---------------------------------------------------------------------------------------

--- 'auto' | 'none' | set of lower-case names (resource names or loader prefixes).
local function housingMode()
  local mode = Config.Integrations and Config.Integrations.housing
  if mode == nil or mode == true then return 'auto' end
  if mode == false then return 'none' end
  if type(mode) == 'string' then
    local s = lower(mode)
    if s == '' or s == 'auto' then return 'auto' end
    if s == 'none' or s == 'off' or s == 'false' then return 'none' end
    return { [s] = true }
  end
  if type(mode) == 'table' then
    local set = {}
    for _, value in pairs(mode) do
      local s = lower(value)
      if s and s ~= '' then set[s] = true end
    end
    if set.auto then return 'auto' end
    if next(set) == nil then return 'none' end
    return set
  end
  return 'auto'
end

local function firstStarted(def)
  for i = 1, #def.resources do
    if Utils.resourceStarted(def.resources[i]) then return def.resources[i] end
  end
  return nil
end

--- Is the loader allowed by the config, and which of its resources is started?
---@return boolean allowed, string|nil resource
local function loaderState(def, mode)
  mode = mode or housingMode()
  if mode == 'none' then return false, nil end
  if mode ~= 'auto' then
    local listed = mode[def.prefix:lower()] == true
    if not listed then
      for i = 1, #def.resources do
        if mode[def.resources[i]:lower()] then listed = true break end
      end
    end
    if not listed then return false, nil end
  end
  local resource = firstStarted(def)
  if not resource then return true, nil end
  if mode == 'auto' and type(def.autoSkip) == 'function' then
    local ok, skip = pcall(def.autoSkip, def.ctx)
    if ok and skip == true then return false, nil end
  end
  return true, resource
end

---------------------------------------------------------------------------------------
-- Access index
---------------------------------------------------------------------------------------

local function effectiveAccess(id)
  local out = {}
  for _, store in ipairs({ loaderAccess, exportAccess, liveAccess }) do
    local set = store[id]
    if set then for identifier in pairs(set) do out[identifier] = true end end
  end
  return out
end

--- Update the identifier index after the access of one house changed.
local function reindex(id, before, after)
  for identifier in pairs(before) do
    if not after[identifier] then
      local set = index[identifier]
      if set then
        set[id] = nil
        if next(set) == nil then index[identifier] = nil end
      end
      dirty[identifier] = true
    end
  end
  for identifier in pairs(after) do
    if not before[identifier] then
      local set = index[identifier]
      if not set then
        set = {}
        index[identifier] = set
      end
      set[id] = true
      dirty[identifier] = true
    end
  end
end

local function sameSet(a, b)
  a, b = a or {}, b or {}
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

local function setAccessSource(store, id, set)
  if set and next(set) == nil then set = nil end
  if sameSet(store[id], set) then return end
  local before = effectiveAccess(id)
  store[id] = set
  reindex(id, before, effectiveAccess(id))
end

local function markHouseDirty(id)
  for identifier in pairs(effectiveAccess(id)) do dirty[identifier] = true end
end

--- Keep `identifier` in the house's access for LIVE_GRANT_MS (refreshed on every hook call).
local function grantLive(id, identifier)
  liveExpiry[id .. '\n' .. identifier] = GetGameTimer() + LIVE_GRANT_MS
  local current = liveAccess[id]
  if current and current[identifier] then return end
  local set = {}
  if current then for k in pairs(current) do set[k] = true end end
  set[identifier] = true
  setAccessSource(liveAccess, id, set)
end

local function pruneLiveGrants(now)
  for key, expiry in pairs(liveExpiry) do
    if expiry <= now then
      liveExpiry[key] = nil
      local id, identifier = key:match('^(.-)\n(.*)$')
      local current = id and liveAccess[id]
      if current and current[identifier] then
        local set = {}
        for k in pairs(current) do if k ~= identifier then set[k] = true end end
        setAccessSource(liveAccess, id, set)
      end
    end
  end
end

---------------------------------------------------------------------------------------
-- Pushing house lists to players
---------------------------------------------------------------------------------------

local function viewsFingerprint(views)
  local parts = {}
  for i = 1, #views do
    local view = views[i]
    local rec = registry[view.houseId or '']
    parts[#parts + 1] = tostring(view.id) .. '=' .. (rec and rec.sig or tostring(view.name))
  end
  return table.concat(parts, ';')
end

local function pushTo(src, identifier)
  local views = Housing.viewsFor(identifier)
  local fp = viewsFingerprint(views)
  if lastSent[src] == fp then return end
  lastSent[src] = fp
  TriggerClientEvent('nz:client:houses', src, views)
end

local function flushPush()
  pushScheduled = false
  if next(dirty) == nil then return end
  local targets = dirty
  dirty = {}
  -- During boot server/main.lua sends every player its full list (incl. houses).
  if NZ.Ready == false then return end
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    local identifier = src and identifierOf(src)
    if identifier and targets[identifier] then
      local ok, err = pcall(pushTo, src, identifier)
      if not ok then lib.print.warn(('housing: push to %s failed: %s'):format(id, tostring(err))) end
    end
  end
end

local function schedulePush()
  if pushScheduled or next(dirty) == nil then return end
  pushScheduled = true
  SetTimeout(PUSH_DELAY_MS, flushPush)
end

---------------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------------

--- Register / update one house garage. Returns the canonical id or nil, error.
---@param data table { name, coords, spawn?, store?, hidden? }
---@param source string loader prefix or 'export'
---@param origin string 'loader' | 'hook' | 'export'
local function registerInternal(id, data, source, origin)
  local coords = Utils.v4(data.coords)
  if not coords then return nil, L('Invalid house coordinates') end
  local spawn = data.spawn ~= nil and Utils.v4(data.spawn) or nil
  local store = data.store ~= nil and Utils.v4(data.store) or nil
  local name = type(data.name) == 'string' and data.name or nil
  local hidden = data.hidden == true
  local sig = registrationSig(name, coords, spawn, store, hidden)

  local rec = registry[id]
  if rec and rec.sig == sig and NZ.Locations.get(Utils.key.house(id)) then
    rec.source, rec.origin = source, origin
    return id
  end

  local loc, err = NZ.Locations.registerHouse(id, {
    name = name, coords = coords, spawn = spawn, store = store, hidden = hidden,
  })
  if type(loc) ~= 'table' then return nil, err or L('Invalid house data') end
  local canonical = type(loc.houseId) == 'string' and loc.houseId or id
  if canonical ~= id then
    -- Should not happen (same normalisation), but never lose track of a registration.
    registry[id] = nil
  end
  registry[canonical] = { source = source, origin = origin, sig = sig, name = loc.name, hidden = hidden, coords = coords }
  markHouseDirty(canonical)
  return canonical
end

--- Forget a registration (access is kept). Returns true when something was removed.
local function unregister(id)
  if not registry[id] then return false end
  markHouseDirty(id)
  registry[id] = nil
  NZ.Locations.removeHouse(id)
  return true
end

---------------------------------------------------------------------------------------
-- Hook positions (resource KVP) & hooked scripts (server convar)
---------------------------------------------------------------------------------------

local function saveSpot(id, spot)
  local ok, err = pcall(function()
    if spot then
      SetResourceKvp(KVP_SPOT .. id, json.encode({ x = spot.x, y = spot.y, z = spot.z, w = spot.w }))
    else
      DeleteResourceKvp(KVP_SPOT .. id)
    end
  end)
  if not ok then Utils.debug('housing: kvp write failed:', tostring(err)) end
end

local function forgetSpot(id)
  if spots[id] == nil then return end
  spots[id] = nil
  saveSpot(id, nil)
end

local function loadSpots()
  local ok, err = pcall(function()
    local handle = StartFindKvp(KVP_SPOT)
    if handle == nil or handle == -1 then return end
    local count = 0
    while count < 5000 do
      local key = FindKvp(handle)
      if not key then break end
      count = count + 1
      local id = canonicalId(key:sub(#KVP_SPOT + 1))
      local spot = id and vec4Of(GetResourceKvpString(key))
      if spot then spots[id] = spot end
    end
    EndFindKvp(handle)
  end)
  if not ok then lib.print.warn(('housing: could not read saved garage positions: %s'):format(tostring(err))) end
end

--- Resources / prefixes named in the 'nayzeee_housing_hooked' server convar.
local function convarHooked(def)
  local ok, value = pcall(GetConvar, HOOK_CONVAR, '')
  if not ok or type(value) ~= 'string' or value == '' then return false end
  for name in value:gmatch('[^,%s]+') do
    local s = name:lower()
    if s == def.prefix:lower() then return true end
    for i = 1, #def.resources do
      if s == def.resources[i]:lower() then return true end
    end
  end
  return false
end

--- Should the house garages of this loader be hidden (the housing script draws the interaction)?
--- 'always': hook-only scripts. 'whenUsed': only when the server owner says the hook file is
--- installed (convar): a player could otherwise hide every marker of a script by calling the hook.
local function hiddenFor(def)
  if def.hook == 'always' then return true end
  if def.hook ~= 'whenUsed' then return false end
  return convarHooked(def)
end

---------------------------------------------------------------------------------------
-- Loader helpers (Housing.lib; passed to every loader as its `ctx`)
---------------------------------------------------------------------------------------

local tableCache = {}

local H = {}
Housing.lib = H

--- oxmysql query; nil on error (logged under Config.Debug).
function H.query(sql, params)
  local ok, rows = pcall(MySQL.query.await, sql, params or {})
  if not ok then
    Utils.debug('housing: query failed:', tostring(rows))
    return nil
  end
  if type(rows) ~= 'table' then return nil end
  return rows
end

--- Does this database table exist? (cached; probed once per resource start)
function H.tableExists(name)
  if tableCache[name] ~= nil then return tableCache[name] end
  local rows = H.query('SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1', { name })
  if rows == nil then return false end
  tableCache[name] = #rows > 0
  return tableCache[name]
end

--- pcall'd export call: ok, results...
function H.call(resource, name, ...)
  local args = table.pack(...)
  return pcall(function()
    local res = exports[resource]
    return res[name](res, table.unpack(args, 1, args.n))
  end)
end

local function exportCall(ctx, quiet, name, ...)
  local resource = ctx.resource or (ctx.def and firstStarted(ctx.def))
  if not resource then return nil end
  local key = 'export:' .. resource .. ':' .. tostring(name)
  local ok, res = H.call(resource, name, ...)
  if not ok then
    if not quiet then
      warnOnce(key, ('housing: %s export %s failed; that part of the integration is skipped until it works again (Config.Debug for details)'):format(
        resource, tostring(name)))
    end
    Utils.debug(('housing: %s:%s failed: %s'):format(resource, tostring(name), tostring(res)))
    return nil, res
  end
  if warned[key] then warned[key] = nil end -- recovered: a new failure warns again
  return res
end

--- Export call on the loader's running resource: the first result, or nil + error (a failure is
--- warned once per export until it works again; details under Config.Debug).
function H.export(ctx, name, ...)
  return exportCall(ctx, false, name, ...)
end

--- Same as H.export for probes that have a fallback: failures are only debug-logged.
function H.tryExport(ctx, name, ...)
  return exportCall(ctx, true, name, ...)
end

H.decode = decodeJson
H.identifier = cleanIdentifier
H.addValues = addValues
H.addKeys = addKeys
H.addAny = addAny
H.isArray = isArray
H.v4 = vec4Of
H.dist = Utils.dist
H.started = Utils.resourceStarted
H.debug = Utils.debug
H.warnOnce = warnOnce
H.identifierOf = identifierOf
H.yield = yieldEvery

function H.text(value, maxLen)
  if type(value) == 'number' then value = tostring(value) end
  local s = Utils.cleanText(value, maxLen or 60)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

--- Garage point from a value that is a point itself or holds one under one of `keys`
--- (default coords / takeVehicle / spawn / position / pos); a heading stored next to the
--- coordinates (heading / h / w) is used when the point has none.
function H.point(value, keys)
  local decoded = decodeJson(value) or value
  local v = vec4Of(decoded)
  if v then return v end
  if type(decoded) ~= 'table' then return nil end
  for _, key in ipairs(keys or { 'coords', 'takeVehicle', 'spawn', 'position', 'pos' }) do
    if decoded[key] ~= nil then
      v = vec4Of(decoded[key])
      if v then
        local w = tonumber(decoded.heading or decoded.h or decoded.w)
        if w and v.w == 0.0 then v.w = w end
        return v
      end
    end
  end
  return nil
end

--- Integer from a number or numeric string (nil otherwise).
function H.int(value)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return math.tointeger(n) or (n == math.floor(n) and math.floor(n)) or nil
end

--- Framework keys ('job:police' style) are not player identifiers.
function H.isJobKey(value)
  return type(value) == 'string' and (value:find('^job:') ~= nil or value:find('^gang:') ~= nil)
end

--- Server id of an online player by identifier (nil when offline).
function H.sourceOf(identifier)
  if type(NZ.Bridge.getSourceByIdentifier) ~= 'function' or type(identifier) ~= 'string' then return nil end
  local ok, src = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
  src = ok and tonumber(src) or nil
  if src and src > 0 then return src end
  return nil
end

--- Job name of an online player (nil when unknown).
function H.jobOf(src)
  if not src or type(NZ.Bridge.getJob) ~= 'function' then return nil end
  local ok, job = pcall(NZ.Bridge.getJob, src)
  if ok and type(job) == 'table' and type(job.name) == 'string' then return job.name end
  return nil
end

--- Raw ids this loader knows (reported before, registered or with a saved hook position).
function H.known(ctx)
  local prefix = ctx.def and ctx.def.prefix
  local out, seen = {}, {}
  local function add(id)
    local p, raw = splitId(id)
    if p == prefix and not seen[id] then
      seen[id] = true
      out[#out + 1] = rawIds[id] ~= nil and rawIds[id] or raw
    end
  end
  for id in pairs(loaderIds[prefix] or {}) do add(id) end
  for id in pairs(spots) do add(id) end
  for id in pairs(registry) do add(id) end
  return out
end

--- Ask for a reload of one loader after `delayMs` (debounced; also clears its live cache).
function H.hint(ctx, delayMs)
  Housing.hint(ctx and ctx.def and ctx.def.prefix or nil, delayMs)
end

--- Same for an event a client can trigger: rate limited per player and per loader.
function H.netHint(ctx, src, delayMs)
  Housing.netHint(src, ctx and ctx.def and ctx.def.prefix or nil, delayMs)
end

--- Register a loader (called at load time by bridge/server/housing/<script>.lua).
--- def = {
---   prefix = 'vms',                    -- house ids '<prefix>:<id>' (letters, digits, _)
---   resources = { 'vms_housing' },     -- resource names (the first started one is used)
---   load = function(ctx) return houses, complete end,
---          -- houses = { [rawId] = { id?, name?, coords?, spawn?, store?, access = set|list } },
---          -- nil on failure (the previous houses are kept); complete = false when the list
---          -- only covers some houses (nothing is removed then, except entries { id, gone = true }:
---          -- houses the script answered "does not exist" for, removed when a read at least a
---          -- minute later still says so).
---   check = function(ctx, identifier, rawId, src) return true|false|nil end,  -- optional live check
---          -- nil = unknown (export failed / player offline): the cached sets decide
---   authoritative = false,             -- true: a live `false` overrides the cached owners / key holders
---   blocked = function(ctx, rawId) return true|false|nil end, -- optional: true denies everyone
---          -- (e.g. a police lockdown), checked before any access source
---   anchors = function(ctx, rawId, src) return { coords... } end,  -- optional: hook garages must be near
---          -- these points; nil / nothing usable = property position unknown
---   hook = 'never' | 'whenUsed' | 'always',  -- does the script draw its own garage interaction?
---   create = false,                    -- 'whenUsed': may a hook call create a garage for a house
---                                      -- the loader knows without one ('always' always may)
---   trustCoords = true,                -- false: a hook call may move loader coordinates
---   numericIds = false,                -- true: the script's ids are integers (hook ids must be numbers)
---   interval = ms,                     -- optional extra reload interval for this loader
---   autoSkip = function(ctx) return boolean end, -- optional: skip in 'auto' mode
---   startDelay = ms,                   -- reload delay after the resource (re)starts
--- }
--- Every function gets the loader's ctx: the Housing.lib helpers (ctx.query, ctx.decode, ctx.point,
--- ctx.addAny, ctx.yield(i) ...) plus ctx.export('Name', ...) (pcall'd export call on the running
--- resource: the first result, or nil + error; a failure is warned once), ctx.tryExport (the same,
--- debug-logged only: probes with a fallback), ctx.known(), ctx.hint(delayMs) and
--- ctx.netHint(src, delayMs) (client-triggered events), all called with a dot.
---@return boolean
function Housing.addLoader(def)
  if type(def) ~= 'table' or type(def.prefix) ~= 'string' or not def.prefix:match('^[%a][%w_]*$')
    or #def.prefix > 12 or type(def.load) ~= 'function' then
    lib.print.error('housing: invalid loader definition')
    return false
  end
  if byPrefix[def.prefix] then
    lib.print.warn(('housing: loader "%s" registered twice'):format(def.prefix))
    return false
  end
  local resources = {}
  if type(def.resources) == 'table' then
    for _, name in ipairs(def.resources) do
      if type(name) == 'string' and name ~= '' then resources[#resources + 1] = name end
    end
  end
  if #resources == 0 then
    lib.print.error(('housing: loader "%s" names no resource'):format(def.prefix))
    return false
  end
  def.resources = resources
  def.label = type(def.label) == 'string' and def.label or resources[1]
  if def.hook ~= 'always' and def.hook ~= 'whenUsed' then def.hook = 'never' end
  -- ctx: the helpers below plus export / known / hint bound to this loader, so loaders call
  -- them with a dot (ctx.export('Name', ...)); a colon call works too.
  local ctx = setmetatable({ def = def }, { __index = H })
  ctx.export = function(first, ...)
    if first == ctx then return H.export(ctx, ...) end
    return H.export(ctx, first, ...)
  end
  ctx.tryExport = function(first, ...)
    if first == ctx then return H.tryExport(ctx, ...) end
    return H.tryExport(ctx, first, ...)
  end
  ctx.known = function() return H.known(ctx) end
  ctx.hint = function(first, delayMs)
    if first ~= ctx then delayMs = first end
    return H.hint(ctx, delayMs)
  end
  ctx.netHint = function(first, ...)
    if first == ctx then return H.netHint(ctx, ...) end
    return H.netHint(ctx, first, ...)
  end
  def.ctx = ctx
  loaders[#loaders + 1] = def
  byPrefix[def.prefix] = def
  return true
end

---------------------------------------------------------------------------------------
-- Live access checks
---------------------------------------------------------------------------------------

local function clearLiveCache(prefix)
  if not prefix then
    liveCache = {}
    return
  end
  local tag = '\n' .. prefix .. ':'
  for key in pairs(liveCache) do
    if key:find(tag, 1, true) then liveCache[key] = nil end
  end
end

--- Ask the housing script directly.
--- Returns result (true / false / nil = unknown, unavailable or failed), blocked (true when the
--- script denies everyone right now, e.g. a police lockdown) and the loader definition.
local function liveCheck(identifier, id, src)
  local prefix, raw = splitId(id)
  local def = prefix and byPrefix[prefix]
  if not def or not def.active then return nil, false, nil end
  if type(def.check) ~= 'function' and type(def.blocked) ~= 'function' then return nil, false, def end
  local resource = firstStarted(def)
  if not resource then return nil, false, def end
  local key = identifier .. '\n' .. id
  local now = GetGameTimer()
  local cached = liveCache[key]
  if cached and now - cached.at < LIVE_TTL_MS then return cached.result, cached.blocked, def end
  def.ctx.resource = resource
  local rawId = rawIds[id]
  if rawId == nil then rawId = raw end

  local blocked = false
  if type(def.blocked) == 'function' then
    local okB, res = pcall(def.blocked, def.ctx, rawId)
    if not okB then
      warnOnce('blocked:' .. prefix, ('housing: %s lockdown check failed: %s'):format(def.label, tostring(res)))
    else
      blocked = res == true
    end
  end

  local result = nil
  if not blocked and type(def.check) == 'function' then
    local ok, res = pcall(def.check, def.ctx, identifier, rawId, src)
    if not ok then
      warnOnce('check:' .. prefix, ('housing: %s access check failed (using the cached owners / key holders): %s'):format(def.label, tostring(res)))
    elseif res == true or res == false then
      result = res
    end
  end
  liveCache[key] = { at = now, result = result, blocked = blocked }
  return result, blocked, def
end

---------------------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------------------

--- Normalized loader output: list of { id, raw, name, coords, spawn, store, access }.
local function normalize(def, houses)
  local list, seen, n = {}, {}, 0
  for key, entry in pairs(houses) do
    n = n + 1
    yieldEvery(n) -- `houses` is the loader's own table: safe to traverse across a yield
    if type(entry) == 'table' then
      local raw = entry.id
      if raw == nil then raw = key end
      local rawText = raw
      if type(rawText) == 'number' then rawText = tostring(math.tointeger(rawText) or rawText) end
      rawText = type(rawText) == 'string' and Utils.cleanText(rawText, MAX_ID_LENGTH - #def.prefix - 1) or nil
      local id = rawText and canonicalId(def.prefix .. ':' .. rawText)
      if id and not seen[id] and entry.gone == true then
        seen[id] = true
        list[#list + 1] = { id = id, raw = raw, gone = true }
      elseif id and not seen[id] then
        seen[id] = true
        local access = {}
        if type(entry.access) == 'table' then
          if isArray(entry.access) then addValues(access, entry.access) else addKeys(access, entry.access) end
        end
        list[#list + 1] = {
          id = id,
          raw = raw,
          name = H.text(entry.name, 60),
          coords = vec4Of(entry.coords),
          spawn = vec4Of(entry.spawn),
          store = vec4Of(entry.store),
          access = access,
        }
      end
    end
  end
  return list
end

local function defaultName(def, id)
  local _, raw = splitId(id)
  return ('%s %s'):format(L('Property'), tostring(raw or id))
end

--- Register / move / hide the garage of one loader house from what is known about it.
local function place(def, id)
  local rec = registry[id]
  if rec and rec.origin == 'export' then return end -- an export registration wins
  local entry = entries[id] or {}
  local name = entry.name or (rec and rec.name) or defaultName(def, id)
  local spot = spots[id]
  local canonical, err
  if entry.coords and (not spot or def.trustCoords ~= false) then
    if spot then forgetSpot(id) end
    canonical, err = registerInternal(id, {
      name = name, coords = entry.coords, spawn = entry.spawn, store = entry.store, hidden = hiddenFor(def),
    }, def.prefix, 'loader')
  elseif spot then
    canonical, err = registerInternal(id, { name = name, coords = spot, spawn = spot, hidden = true }, def.prefix, 'hook')
  elseif rec then
    unregister(id) -- the garage was removed from the house
    return
  else
    return -- access only: registered when the housing script calls the hook
  end
  if not canonical then Utils.debug(('housing: skipped %s: %s'):format(id, tostring(err))) end
end

--- Forget everything a loader reported about one house (its 'H..' vehicles keep their key).
local function dropLoaderHouse(id)
  setAccessSource(loaderAccess, id, nil)
  entries[id], rawIds[id], goneSince[id] = nil, nil, nil
  local rec = registry[id]
  if rec and rec.origin ~= 'export' then unregister(id) end
  forgetSpot(id)
end

--- Apply one loader read. Returns the number of houses with a garage (nil: read not trusted).
--- Shared tables (registry, spots, loaderIds) are never traversed across a yield: the hook
--- callback may change them meanwhile, so those loops work on snapshots.
local function apply(def, houses, complete)
  local prefix = def.prefix
  local list = normalize(def, houses)
  local before = loaderIds[prefix] or {}
  local now = GetGameTimer()

  -- Incomplete loaders name houses that no longer exist: removed when a read at least
  -- EMPTY_CONFIRM_MS after the first such answer still says so.
  local gone = {}
  for i = #list, 1, -1 do
    local item = list[i]
    if item.gone then
      table.remove(list, i)
      if not complete then
        goneSince[item.id] = goneSince[item.id] or now
        if now - goneSince[item.id] >= EMPTY_CONFIRM_MS then gone[#gone + 1] = item.id end
      end
    else
      goneSince[item.id] = nil
    end
  end

  -- A read that suddenly finds nothing (script still loading its data after a restart, failed
  -- query) is only trusted when a read at least EMPTY_CONFIRM_MS later confirms it.
  if #list == 0 and next(before) ~= nil then
    emptySince[prefix] = emptySince[prefix] or now
    if now - emptySince[prefix] < EMPTY_CONFIRM_MS then
      warnOnce('empty:' .. prefix, ('housing: %s returned no houses; keeping the previous ones unless a read a minute later confirms it'):format(def.label))
      return nil
    end
  end
  emptySince[prefix] = nil
  warned['empty:' .. prefix] = nil

  local seen = {}
  for i = 1, #list do
    local item = list[i]
    seen[item.id] = true
    rawIds[item.id] = item.raw
    entries[item.id] = { name = item.name, coords = item.coords, spawn = item.spawn, store = item.store }
    setAccessSource(loaderAccess, item.id, item.access)
    yieldEvery(i)
  end

  if complete then
    local dropped = {}
    for id in pairs(before) do
      if not seen[id] then dropped[#dropped + 1] = id end
    end
    for i = 1, #dropped do dropLoaderHouse(dropped[i]) end
    -- Hook positions of houses the script no longer has.
    local stale = {}
    for id, rec in pairs(registry) do
      if rec.source == prefix and rec.origin == 'hook' and not seen[id] then stale[#stale + 1] = id end
    end
    for id in pairs(spots) do
      if not seen[id] and splitId(id) == prefix then stale[#stale + 1] = id end
    end
    for i = 1, #stale do
      unregister(stale[i])
      forgetSpot(stale[i])
    end
    loaderIds[prefix] = seen
  else
    for id in pairs(seen) do before[id] = true end
    for i = 1, #gone do
      local id = gone[i]
      before[id] = nil
      dropLoaderHouse(id)
      Utils.debug(('housing: %s no longer has %s'):format(def.label, id))
    end
    loaderIds[prefix] = before
  end

  local ids = {}
  for id in pairs(loaderIds[prefix]) do ids[#ids + 1] = id end
  if not complete then
    for id in pairs(spots) do
      if splitId(id) == prefix and not loaderIds[prefix][id] then ids[#ids + 1] = id end
    end
  end
  for i = 1, #ids do
    place(def, ids[i])
    yieldEvery(i)
  end

  local count = 0
  for _, rec in pairs(registry) do
    if rec.source == prefix then count = count + 1 end
  end
  return count
end

--- Reload the given loaders (nil = all) and apply the differences.
local function doReload(only)
  local mode = housingMode()
  local total = 0
  for i = 1, #loaders do
    local def = loaders[i]
    if only == nil or only[def.prefix] then
      local allowed, resource = loaderState(def, mode)
      def.enabled = allowed
      if allowed and resource then
        def.active = true
        def.ctx.resource = resource
        lastReadAt[def.prefix] = GetGameTimer()
        local ok, houses, complete = pcall(def.load, def.ctx)
        if ok and type(houses) == 'table' then
          local count = apply(def, houses, complete ~= false)
          if count then
            lastLoaderLoad[def.prefix] = GetGameTimer()
            warned['load:' .. def.prefix] = nil
            Utils.debug(('housing: %s -> %d house garage(s)'):format(def.label, count))
            total = total + count
          end
        else
          local kept = Utils.count(loaderIds[def.prefix])
          warnOnce('load:' .. def.prefix, ('housing: could not read %s data, keeping the %d house(s) loaded before%s'):format(
            resource, kept, ok and '' or (': ' .. tostring(houses))))
        end
      elseif not allowed then
        def.active = false
      end
      -- Allowed but not started (restarting?): keep what was loaded, nothing to read now.
    end
  end
  return total
end

local function reload(only)
  if loading then return false end
  loading = true
  local ok, res = pcall(doReload, only)
  loading = false
  lastLoadAt = GetGameTimer()
  if not ok then
    lib.print.error(('housing: reload failed: %s'):format(tostring(res)))
    return false
  end
  schedulePush()
  return true
end

local function markPending(prefix)
  if prefix == nil then pendingAll = true else pendingSet[prefix] = true end
end

local function takePending()
  if pendingAll then
    pendingAll, pendingSet = false, {}
    return true, nil
  end
  if next(pendingSet) == nil then return false, nil end
  local set = pendingSet
  pendingSet = {}
  return true, set
end

local scheduleTrailing

local function reloadPending()
  if loading then
    scheduleTrailing(MIN_RELOAD_MS)
    return false
  end
  local any, only = takePending()
  if not any then return false end
  return reload(only)
end

--- One trailing reload at a time; a request for an earlier one moves it forward.
function scheduleTrailing(delay)
  delay = math.max(0, math.floor(tonumber(delay) or 0))
  local at = GetGameTimer() + delay
  if trailingAt and trailingAt <= at then return end
  trailingAt = at
  trailingGen = trailingGen + 1
  local gen = trailingGen
  SetTimeout(delay, function()
    if gen ~= trailingGen then return end -- replaced by an earlier one
    trailingAt = nil
    if loading then
      scheduleTrailing(MIN_RELOAD_MS)
      return
    end
    reloadPending()
  end)
end

--- Reload now when allowed, otherwise schedule one trailing reload.
---@param wait boolean wait for the reload (or one already running) to finish
---@param minGap number|nil minimum ms since the last reload (default MIN_RELOAD_MS)
---@param prefix string|nil only this loader (nil = all)
local function requestReload(wait, minGap, prefix)
  markPending(prefix)
  minGap = math.max(MIN_RELOAD_MS, tonumber(minGap) or MIN_RELOAD_MS)
  if loading and wait then
    local deadline = GetGameTimer() + LOAD_WAIT_MS
    while loading and GetGameTimer() < deadline do Wait(50) end
  end
  if loading then
    scheduleTrailing(MIN_RELOAD_MS)
    return
  end
  local since = lastLoadAt and (GetGameTimer() - lastLoadAt) or math.huge
  if since >= minGap then
    if wait then
      reloadPending()
    else
      CreateThread(reloadPending)
    end
    return
  end
  scheduleTrailing(minGap - since)
end

--- Prefix of a loader from a prefix or one of its resource names (case-insensitive).
local function prefixOf(which)
  if type(which) ~= 'string' or which == '' then return nil end
  if byPrefix[which] then return which end
  local s = which:lower()
  for i = 1, #loaders do
    local def = loaders[i]
    if def.prefix:lower() == s then return def.prefix end
    for j = 1, #def.resources do
      if def.resources[j]:lower() == s then return def.prefix end
    end
  end
  return nil
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Load house garages from the supported housing resources and start the periodic refresh.
--- Called once by server/main.lua during boot (inside a thread).
function Housing.boot()
  if booted then return end
  booted = true
  loadSpots()
  markPending(nil)
  reloadPending()
  -- server/main.lua syncs every online player right after boot (houses included).
  dirty = {}
  lastSent = {}

  local count, names = 0, {}
  for _ in pairs(registry) do count = count + 1 end
  for i = 1, #loaders do
    if loaders[i].active then names[#names + 1] = loaders[i].label end
  end
  if count > 0 or #names > 0 then
    lib.print.info(('housing: %d house garage(s) loaded%s'):format(count,
      #names > 0 and (' (' .. table.concat(names, ', ') .. ')') or ''))
  end

  CreateThread(function()
    while true do
      Wait(REFRESH_MS)
      local ok, err = pcall(requestReload, true)
      if not ok then lib.print.warn(('housing: periodic refresh failed: %s'):format(tostring(err))) end
    end
  end)

  -- Housekeeping: expired hook grants, live check cache, per-loader reload intervals.
  CreateThread(function()
    while true do
      Wait(TICK_MS)
      local ok, err = pcall(function()
        local now = GetGameTimer()
        pruneLiveGrants(now)
        for key, cached in pairs(liveCache) do
          if now - cached.at >= LIVE_TTL_MS then liveCache[key] = nil end
        end
        for i = 1, #loaders do
          local def = loaders[i]
          local interval = tonumber(def.interval)
          if def.active and interval and interval >= MIN_RELOAD_MS then
            local last = lastLoaderLoad[def.prefix]
            if not last or now - last >= interval then requestReload(false, nil, def.prefix) end
          end
        end
        schedulePush()
      end)
      if not ok then lib.print.warn(('housing: housekeeping failed: %s'):format(tostring(err))) end
    end
  end)
end

--- Ask for a reload of the housing data (throttled; runs asynchronously).
---@param which string|nil loader prefix or resource name (nil = every loader)
---@return boolean known false when `which` names no supported housing script
function Housing.refresh(which)
  if not booted then return false end
  if which == nil then
    clearLiveCache(nil)
    requestReload(false)
    return true
  end
  local prefix = prefixOf(which)
  if not prefix then return false end
  clearLiveCache(prefix)
  requestReload(false, nil, prefix)
  return true
end

--- Reload hint from a housing script event (server-side events only: see Housing.netHint for
--- events a client can trigger): reloads that loader after `delayMs` (default 1500 ms,
--- debounced) and drops its cached live checks.
---@param prefix string|nil loader prefix (nil = every loader)
---@param delayMs number|nil
---@param minGap number|nil minimum ms since the last reload (default MIN_RELOAD_MS)
function Housing.hint(prefix, delayMs, minGap)
  if not booted then return end
  if prefix ~= nil then
    local def = byPrefix[prefix]
    if not def or def.enabled == false then return end
  end
  clearLiveCache(prefix)
  local delay = math.floor(math.max(0, math.min(600000, tonumber(delayMs) or 1500)))
  local gap = math.max(MIN_RELOAD_MS, tonumber(minGap) or MIN_RELOAD_MS)
  -- Hints for the same loader and delay coalesce; the shortest gap asked for wins.
  local key = tostring(prefix or '*') .. '@' .. delay
  local timer = hintTimers[key]
  if timer then
    timer.minGap = math.min(timer.minGap, gap)
    return
  end
  timer = { minGap = gap }
  hintTimers[key] = timer
  SetTimeout(delay, function()
    hintTimers[key] = nil
    requestReload(false, timer.minGap, prefix)
  end)
end

--- Reload hint from an event a client can trigger (key given / removed through the housing
--- script's client): at most one per NET_HINT_RATE_MS per player, and the loader is reloaded at
--- most once per NET_HINT_GAP_MS through these, however many players send them.
---@param src number|string server id of the sender (`source` in the event handler)
---@param prefix string loader prefix
---@param delayMs number|nil
function Housing.netHint(src, prefix, delayMs)
  if not booted or type(prefix) ~= 'string' then return end
  local def = byPrefix[prefix]
  if not def or def.enabled == false then return end
  src = tonumber(src)
  if not src or src <= 0 then return end
  if not NZ.Access.rateLimit(src, 'housing:nethint:' .. prefix, NET_HINT_RATE_MS) then return end
  if netHintPending[prefix] then return end
  netHintPending[prefix] = true
  -- Counted from the last read of the loader or the last reload asked for this way (which may
  -- still be waiting for its turn), whichever is later.
  local last = math.max(lastReadAt[prefix] or -math.huge, netHintAt[prefix] or -math.huge)
  local since = GetGameTimer() - last
  local delay = math.max(tonumber(delayMs) or 1500, NET_HINT_GAP_MS - since)
  delay = math.floor(math.max(0, math.min(600000, delay)))
  SetTimeout(delay, function()
    netHintPending[prefix] = nil
    netHintAt[prefix] = GetGameTimer()
    Housing.hint(prefix, 0)
  end)
end

--- May this identifier use the garage of this house? Asks the housing script first when its
--- loader has a live check, then falls back to the cached owners / key holders.
---@param identifier string
---@param houseId string|number house id (with or without the 'H' key prefix)
---@param src number|nil server id of the player when known
---@return boolean
function Housing.hasAccess(identifier, houseId, src)
  if type(identifier) ~= 'string' or identifier == '' then return false end
  local id = knownId(houseId)
  if not id then return false end
  local live, blocked, def = liveCheck(identifier, id, tonumber(src))
  if blocked then return false end
  if live == true then return true end
  local a, b = loaderAccess[id], exportAccess[id]
  -- The script answered "no" and its answer is final: only an export grant still counts.
  if live == false and def and def.authoritative == true then
    return b ~= nil and b[identifier] == true
  end
  if (a ~= nil and a[identifier] == true) or (b ~= nil and b[identifier] == true) then return true end
  -- Hook grants only count while the housing script cannot be asked.
  if live == nil then
    local g = liveAccess[id]
    local expiry = liveExpiry[id .. '\n' .. identifier]
    if g and g[identifier] and expiry and expiry > GetGameTimer() then return true end
  end
  return false
end

--- Client views (NZ.Locations.clientView) of every house garage this identifier may use.
---@param identifier string
---@return table[] views sorted by id
function Housing.viewsFor(identifier)
  local views = {}
  if type(identifier) ~= 'string' then return views end
  local set = index[identifier]
  if not set then return views end
  local ids = {}
  for id in pairs(set) do
    if registry[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for i = 1, #ids do
    local loc = NZ.Locations.get(Utils.key.house(ids[i]))
    if loc then
      local view = NZ.Locations.clientView(loc)
      if view then views[#views + 1] = view end
    end
  end
  return views
end

--- Register (or move / rename) a house garage. Backs the RegisterHouseGarage export.
---@param houseId string|number
---@param data table { name, coords = vec4, spawn = vec4|nil, hidden = boolean|nil }
---@return boolean ok, string|nil error (translated)
function Housing.register(houseId, data)
  local id = canonicalId(houseId)
  if not id then return false, L('Invalid house id') end
  if type(data) ~= 'table' then return false, L('Invalid house data') end
  local canonical, err = registerInternal(id, data, 'export', 'export')
  if not canonical then return false, err end
  schedulePush()
  return true
end

--- Remove a house garage. Vehicles stored there keep their 'H..' garage key.
---@param houseId string|number
---@return boolean ok
function Housing.remove(houseId)
  local id = knownId(houseId)
  if not id then return false, L('Invalid house id') end
  if not unregister(id) then NZ.Locations.removeHouse(id) end
  setAccessSource(loaderAccess, id, nil)
  forgetSpot(id)
  schedulePush()
  return true
end

--- Replace the identifiers allowed to use a house garage (owner + key holders). Merged with
--- what the loaders know. May be called before RegisterHouseGarage.
---@param houseId string|number
---@param identifiers string[]
---@return boolean ok, string|nil error (translated)
function Housing.setAccess(houseId, identifiers)
  local id = knownId(houseId)
  if not id then return false, L('Invalid house id') end
  if type(identifiers) ~= 'table' then return false, L('Invalid identifier list') end
  local set, count = {}, 0
  for _, value in pairs(identifiers) do
    if count >= MAX_ACCESS then break end
    local identifier = cleanIdentifier(value)
    if identifier and not set[identifier] then
      set[identifier] = true
      count = count + 1
    end
  end
  setAccessSource(exportAccess, id, set)
  schedulePush()
  return true
end

--- Player cleanup (called by server/main.lua through the onPlayerDropped hook).
---@param src number
function Housing.onPlayerDropped(src)
  src = tonumber(src)
  if src then lastSent[src] = nil end
end

-- A (re)loaded character gets its full list from server-core: forget what we pushed.
AddEventHandler('nz:server:playerLoaded', function(src)
  src = tonumber(src)
  if src then lastSent[src] = nil end
end)

AddEventHandler('nz:server:playerUnloaded', function(src)
  src = tonumber(src)
  if src then lastSent[src] = nil end
end)

-- A housing script (re)started: read it again once it had time to load its data.
AddEventHandler('onResourceStart', function(resource)
  if not booted or type(resource) ~= 'string' then return end
  for i = 1, #loaders do
    local def = loaders[i]
    for j = 1, #def.resources do
      if def.resources[j] == resource then
        Housing.hint(def.prefix, tonumber(def.startDelay) or 5000)
        return
      end
    end
  end
end)

---------------------------------------------------------------------------------------
-- Hook: OpenHouseGarage / StoreHouseGarage (housing scripts that own the interaction)
---------------------------------------------------------------------------------------

local function hookId(value)
  local id = canonicalId(value)
  if not id then return nil end
  if registry[id] or splitId(id) then return id end
  if id:sub(1, 1) == 'H' and #id > 1 then
    local stripped = id:sub(2)
    if registry[stripped] or splitId(stripped) then return stripped end
  end
  return id
end

--- Server-side position of the player (their vehicle when driving).
local function playerSpot(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  local entity = ped
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle and vehicle ~= 0 then entity = vehicle end
  local pos = GetEntityCoords(entity)
  if not pos then return nil end
  local spot = vec4Of({ x = pos.x, y = pos.y, z = pos.z, w = GetEntityHeading(entity) or 0.0 })
  if not spot then return nil end
  return { x = Utils.round(spot.x, 3), y = Utils.round(spot.y, 3), z = Utils.round(spot.z, 3), w = Utils.round(spot.w % 360.0, 2) }
end

--- Distance from its saved position at which a hook garage moves to where it is used.
local function hookMoveDist()
  local ok, value = pcall(NZ.Settings.get, 'garages.maxDistance', 25.0)
  local max = ok and tonumber(value) or 25.0
  return math.max(1.0, math.min(HOOK_MOVE_DIST, max * 0.5))
end

--- May a hook call create a garage for a house of this loader that has none yet?
local function hookCreates(def)
  return def ~= nil and (def.hook == 'always' or (def.hook == 'whenUsed' and def.create == true))
end

local function hookRange()
  local ok, value = pcall(GetConvar, RANGE_CONVAR, '')
  local n = ok and tonumber(value) or nil
  if n and n >= 0 then return n end
  return HOOK_RANGE
end

--- Is the spot near the property? true = near (or no range check), false = too far,
--- nil = the property's position is unknown (no anchors, or they could not be read).
local function nearProperty(def, id, spot, src)
  local range = hookRange()
  if range <= 0 then return true end
  if type(def.anchors) ~= 'function' then return nil end
  local _, raw = splitId(id)
  local rawId = rawIds[id]
  if rawId == nil then rawId = raw end
  def.ctx.resource = firstStarted(def)
  local ok, anchors = pcall(def.anchors, def.ctx, rawId, src)
  if not ok then
    warnOnce('anchors:' .. def.prefix, ('housing: %s: could not read where a property is (%s)'):format(def.label, tostring(anchors)))
    return nil
  end
  if type(anchors) ~= 'table' then return nil end
  local nearest
  for _, anchor in pairs(anchors) do
    local v = vec4Of(anchor)
    if v then
      local d = Utils.dist(v, spot)
      if d <= range then return true end
      nearest = math.min(nearest or d, d)
    end
  end
  if not nearest then return nil end
  warnOnce('range:' .. id, ('housing: refused a garage for %s %.0f m from the property (limit %.0f m, convar %s)'):format(
    id, nearest, range, RANGE_CONVAR))
  return false
end

--- Canonical id for a hook call: numeric raw ids become plain integers ('tk:1.0', 'nolag:021' ->
--- 'tk:1', 'nolag:21'), so one property never gets several garages (or a garage under an id
--- the loader does not report, removed again by its next read). nil when a loader whose ids
--- are integers (numericIds) gets something else.
local function canonicalHookId(id, def)
  local prefix, raw = splitId(id)
  if not prefix or not def or def.prefix ~= prefix then return id end
  local n = H.int(raw)
  if not n then
    if def.numericIds then return nil end
    return id
  end
  local canonical = prefix .. ':' .. tostring(n)
  if canonical == id or def.numericIds then return canonical end
  -- A string id that only looks numeric ('0012') and that the loader reported as such: keep it.
  local ids = loaderIds[prefix] or {}
  if (known(id) or ids[id]) and not (known(canonical) or ids[canonical]) then return id end
  return canonical
end

--- First hook call of a script that also has loader coordinates: say how to hide our points.
local function noteHook(def)
  if hookSeen[def.prefix] or def.hook ~= 'whenUsed' then return end
  hookSeen[def.prefix] = true
  if not hiddenFor(def) then
    lib.print.info(('housing: %s uses the OpenHouseGarage / StoreHouseGarage hook. To hide our own markers / targets at its garages, add  set %s "%s"  to server.cfg'):format(
      def.label, HOOK_CONVAR, def.resources[1]))
  end
end

-- { houseId, action = 'open'|'store', name? } -> { houseId, garageKey, action, views }
lib.callback.register('nz:housing:hook', Utils.safe(function(source, payload)
  local src = tonumber(source)
  if not src or src <= 0 then return Utils.fail(L('Invalid request')) end
  if not booted or NZ.Ready == false then return Utils.fail(L('Garages are still loading')) end
  if type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not NZ.Access.rateLimit(src, 'housing:hook', HOOK_RATE_MS) then
    return Utils.fail(L('Please wait a moment before trying again'))
  end

  local id = hookId(payload.houseId)
  if not id then return Utils.fail(L('Invalid house id')) end
  local action = payload.action == 'store' and 'store' or 'open'
  local identifier = identifierOf(src)
  if not identifier then return Utils.fail(L('Your character is not loaded')) end

  local prefix = splitId(id)
  local def = prefix and byPrefix[prefix] or nil
  if def and not def.active then def = nil end
  id = canonicalHookId(id, def)
  if not id then return Utils.fail(L('Invalid house id')) end
  if not def and not registry[id] then
    Utils.debug(('housing: hook for unknown house %s'):format(id))
    return Utils.fail(L('This garage is not available'))
  end

  -- Scripts whose garage points we draw (or know) never get a new garage from a hook call:
  -- only houses that already have one may be opened / stored through it.
  local rec = registry[id]
  if not rec and not hookCreates(def) then
    Utils.debug(('housing: hook for %s, which has no garage'):format(id))
    return Utils.fail(L('This garage is not available'))
  end

  if not Housing.hasAccess(identifier, id, src) then
    return Utils.fail(L('You do not have access to this house garage'))
  end

  rec = registry[id]
  local movable = (not rec and hookCreates(def)) or (rec ~= nil and def ~= nil
    and (rec.origin == 'hook' or (rec.origin == 'loader' and def.trustCoords == false)))
  local spot
  if movable then
    spot = playerSpot(src)
    if not spot then return Utils.fail(L('Something went wrong')) end
    if rec and Utils.dist(rec.coords, spot) <= hookMoveDist() then movable = false end
  end
  if movable then
    local near = true
    if def then near = nearProperty(def, id, spot, src) end
    if near == false then return Utils.fail(L('You are too far from the garage')) end
    if near == nil and rec then
      -- Where the property is cannot be read: never move an existing garage (a key holder could
      -- otherwise carry it anywhere). It stays where it is and the usual distance check of the
      -- garage menu applies. A first placement is allowed: it happens at the housing script's
      -- own garage point, and the id is canonical, so there is one garage per property.
      warnOnce('noanchor:' .. id, ('housing: %s: property position unknown, garage not moved'):format(id))
      movable = false
    end
  end
  if movable then
    local entry = entries[id] or {}
    local name = entry.name or (rec and rec.name) or H.text(payload.name, 60)
      or (def and defaultName(def, id)) or L('House garage')
    local canonical, err = registerInternal(id, { name = name, coords = spot, spawn = spot, hidden = true },
      def and def.prefix or 'export', 'hook')
    if not canonical then return Utils.fail(err or L('Something went wrong')) end
    spots[canonical] = spot
    saveSpot(canonical, spot)
    id = canonical
  end
  if def then noteHook(def) end

  grantLive(id, identifier)
  local views = Housing.viewsFor(identifier)
  lastSent[src] = viewsFingerprint(views)
  schedulePush()
  return Utils.ok({ houseId = id, garageKey = Utils.key.house(id), action = action, views = views })
end))

---------------------------------------------------------------------------------------
-- Callback
---------------------------------------------------------------------------------------

lib.callback.register('nz:housing:refresh', Utils.safe(function(source)
  local src = tonumber(source)
  if not src or src <= 0 then return Utils.fail(L('Invalid request')) end
  if not booted or NZ.Ready == false then return Utils.fail(L('Garages are still loading')) end

  -- Client requests reload the housing data at most once per CLIENT_RELOAD_MS (a keyed house
  -- without a garage keeps asking). Otherwise answer from memory; the trailing reload pushes
  -- any change ('nz:client:houses').
  if NZ.Access.rateLimit(src, 'housing:refresh', CLIENT_RATE_MS) then
    requestReload(true, CLIENT_RELOAD_MS)
  else
    requestReload(false, CLIENT_RELOAD_MS)
  end

  local identifier = identifierOf(src)
  if not identifier then return Utils.ok({}) end
  local views = Housing.viewsFor(identifier)
  lastSent[src] = viewsFingerprint(views)
  return Utils.ok(views)
end))
