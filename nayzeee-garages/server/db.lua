--[[
  nayzeee-garages — database access layer (NZ.DB).

  Wraps the framework vehicle table (QBCore/Qbox `player_vehicles`, ESX `owned_vehicles`)
  and every nz_* table behind normalized Lua tables (NZVehicleRow, docs/ARCHITECTURE.md
  §4.1 / §5.2). Statements are built only from columns that exist (NZ.DB.schema, filled
  by server/migrations.lua). Framework columns are mirrored for 3rd-party compatibility.
  Every function returns a sane empty value on errors and logs the failure.

  Plates stored in nz_* tables are always normalized (NZ.Utils.plate: trimmed, upper-case).
]]

local DB = NZ.DB
local Utils = NZ.Utils
local isEsx = NZ.Framework == 'esx'

DB.vehicleTable = DB.vehicleTable or (isEsx and 'owned_vehicles' or 'player_vehicles')
DB.schema = DB.schema or { loaded = false, exists = false, columns = {}, financeMode = 'none', financeColumns = {}, version = 0 }

local VT = DB.vehicleTable
local OWNER_COL = isEsx and 'owner' or 'citizenid'
local PROPS_COL = isEsx and 'vehicle' or 'mods'
local GARAGE_COL = isEsx and 'parking' or 'garage'

local PLATE_MAX = 8                 -- GTA plates
local CHUNK = 250                   -- plates per IN (?) query
local hashOf = joaat or GetHashKey

local STATE_CODE = { out = 0, garaged = 1, impounded = 2 }
local STATE_NAME = { [0] = 'out', [1] = 'garaged', [2] = 'impounded' }

local ESX_TYPE_CATEGORY = {
  car = 'car', automobile = 'car', bike = 'car', motorcycle = 'car', truck = 'car',
  boat = 'sea', submarine = 'sea', sea = 'sea',
  airplane = 'air', plane = 'air', helicopter = 'air', heli = 'air', aircraft = 'air', air = 'air',
}

local QB_SELECT = { 'citizenid', 'vehicle', 'hash', 'mods', 'plate', 'garage', 'fuel', 'engine', 'body', 'state', 'depotprice' }
local QB_FINANCE = { 'balance', 'paymentamount', 'paymentsleft', 'financetime' }
local ESX_SELECT = { 'owner', 'plate', 'vehicle', 'type', 'stored', 'parking', 'pound' }
local NZ_SELECT = {
  'nz_garage', 'nz_state', 'nz_nickname', 'nz_type', 'nz_job', 'nz_gang', 'nz_mileage',
  'nz_damage', 'nz_trailer', 'nz_impound', 'nz_blocked', 'nz_last_out', 'nz_finance_total',
  'nz_finance',
}
-- Our own finance record (JSON, every framework): the plan set through the finance API or
-- the garage, with its wall-clock due date. QBCore / Qbox also mirror the framework columns.
local FINANCE_COLUMN = 'nz_finance'

---------------------------------------------------------------------------------------
-- Low level helpers
---------------------------------------------------------------------------------------

local function oneLine(sql)
  return (tostring(sql):gsub('%s+', ' '):sub(1, 240))
end

--- Run an oxmysql await method inside pcall (oxmysql throws on query errors).
---@return any result, boolean ok
local function run(method, sql, params)
  local ok, res = pcall(MySQL[method].await, sql, params or {})
  if not ok then
    lib.print.error(('[db] %s failed: %s | %s'):format(method, tostring(res), oneLine(sql)))
    return nil, false
  end
  return res, true
end

--- Run several statements atomically. queries = { { query = sql, values = {...} }, ... }
local function transaction(queries)
  local ok, res = pcall(MySQL.transaction.await, queries)
  if not ok then
    lib.print.error(('[db] transaction failed: %s'):format(tostring(res)))
    return false
  end
  if res ~= true then
    lib.print.error(('[db] transaction rolled back (%d statements, first: %s)')
      :format(#queries, oneLine(queries[1] and queries[1].query or '')))
    return false
  end
  return true
end

local function has(column)
  return DB.schema.columns[column] == true
end

--- Ensure the vehicle table column map is known. Returns true when the table is usable.
local function ready()
  local s = DB.schema
  if not s.loaded and type(DB.loadSchema) == 'function' then DB.loadSchema() end
  return s.exists == true
end

local function num(v)
  if v == true then return 1 elseif v == false then return 0 end
  return tonumber(v)
end

local function truthy(v)
  return v == true or v == 1 or v == '1'
end

local function nonEmpty(v)
  if type(v) == 'string' and v ~= '' then return v end
  return nil
end

--- Plain string capped to `max` characters (nil for non-strings / empty).
local function str(v, max)
  if type(v) == 'number' then v = tostring(v) end
  if type(v) ~= 'string' then return nil end
  v = Utils.trim(v)
  if v == '' then return nil end
  if max and #v > max then v = v:sub(1, max) end
  return v
end

local function int(v, default)
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge then return default end
  return math.floor(n)
end

--- Percent 0-100 rounded to one decimal.
local function pct(v, default)
  local n = tonumber(v)
  if not n or n ~= n then return default end
  return Utils.round(Utils.clamp(n, 0, 100), 1)
end

--- Any hash representation -> signed 32-bit integer (as GTA natives return). nil if invalid.
local function toSigned(h)
  h = tonumber(h)
  if not h or h ~= h or h == math.huge or h == -math.huge then return nil end
  h = math.floor(h) % 4294967296
  if h > 2147483647 then h = h - 4294967296 end
  h = math.tointeger(h) or h
  if h == 0 then return nil end
  return h
end

--- Model name or hash -> signed hash.
local function hashFrom(model)
  if type(model) == 'number' then return toSigned(model) end
  if type(model) ~= 'string' or model == '' then return nil end
  local n = tonumber(model)
  if n then return toSigned(n) end
  return toSigned(hashOf(model))
end

local function padded(p)
  if #p >= PLATE_MAX then return p end
  return p .. string.rep(' ', PLATE_MAX - #p)
end

--- Normalized plate expression for the fallback lookups (plates stored with odd spacing /
--- case): the indexed virtual column nz_plate_norm when migrations could create it, else
--- UPPER(TRIM(plate)) (unindexed: a full scan).
---@param alias string|nil table alias ('v')
local function normPlate(alias)
  local prefix = alias and (alias .. '.') or ''
  if has('nz_plate_norm') then return prefix .. '`nz_plate_norm`' end
  return ('UPPER(TRIM(%s`plate`))'):format(prefix)
end

local function decodeTable(v)
  if type(v) == 'table' then return v end
  if type(v) ~= 'string' or v == '' then return nil end
  local ok, res = pcall(json.decode, v)
  if ok and type(res) == 'table' then return res end
  return nil
end

local function encode(v, what)
  if v == nil then return nil end
  local ok, res = pcall(json.encode, v)
  if ok and type(res) == 'string' then return res end
  lib.print.error(('[db] could not encode %s as JSON: %s'):format(what or 'value', tostring(res)))
  return nil
end

local function stateCode(v)
  if type(v) == 'string' then return STATE_CODE[v] end
  local n = num(v)
  if n == 0 or n == 1 or n == 2 then return math.floor(n) end
  return nil
end

local function esxTypeFor(vehicleType)
  if vehicleType == 'sea' then return 'boat' end
  if vehicleType == 'air' then return 'airplane' end
  return 'car'
end

--- Name written to the ESX `pound` column for an ImpoundInfo.
local function impoundName(info)
  if type(info) ~= 'table' then return nil end
  return str(info.locationName, 60) or (info.locationId and str('impound_' .. tostring(info.locationId), 60)) or nil
end

--- Framework `license` for a qb/qbx character: online player first, then the players table.
local function licenseFor(identifier)
  if type(identifier) ~= 'string' or identifier == '' then return nil end
  local getSource = NZ.Bridge and NZ.Bridge.getSourceByIdentifier
  if type(getSource) == 'function' then
    local okSrc, src = pcall(getSource, identifier)
    if okSrc and src then
      local license = NZ.Framework == 'qbx' and GetPlayerIdentifierByType(src, 'license2') or nil
      license = license or GetPlayerIdentifierByType(src, 'license')
      if license then return license end
    end
  end
  if NZ.Framework ~= 'qb' and NZ.Framework ~= 'qbx' then return nil end
  local res = run('scalar', 'SELECT `license` FROM `players` WHERE `citizenid` = ? LIMIT 1', { identifier })
  return nonEmpty(res)
end

---------------------------------------------------------------------------------------
-- Statement cache (rebuilt whenever the schema version changes)
---------------------------------------------------------------------------------------

local stmt = { version = -1, select = nil, effectiveState = nil }

local UNMANAGED_SQL = "(v.`nz_garage` IS NULL OR v.`nz_garage` = '')"

--- SQL expression of the effective state code (see effectiveState below; both must agree).
local function buildEffectiveStateSql()
  if not has('nz_state') then return nil end
  if not isEsx then
    if not has('state') then return 'v.`nz_state`' end
    -- Managed rows: an impound written into the mirrored framework columns by another
    -- resource (qb-policejob: state 2 = seized, state 0 + depotprice = depot) wins.
    local drift = 'WHEN v.`state` = 2 AND COALESCE(v.`nz_state`, 1) <> 2 THEN 2 '
    -- Unmanaged rows: a qb depot impound (state 0 + depotprice) is impounded as well.
    local depot = ''
    if has('depotprice') then
      drift = drift .. 'WHEN v.`state` = 0 AND COALESCE(v.`nz_state`, 1) = 0 AND v.`depotprice` > 0 THEN 2 '
      depot = 'WHEN v.`state` = 0 AND v.`depotprice` > 0 THEN 2 '
    end
    return ('(CASE WHEN %s AND v.`state` IS NOT NULL THEN (CASE %sWHEN v.`state` = 0 THEN 0 '
      .. 'WHEN v.`state` = 2 THEN 2 ELSE 1 END) %sELSE v.`nz_state` END)'):format(UNMANAGED_SQL, depot, drift)
  end
  if not has('stored') then return 'v.`nz_state`' end
  local inner, drift
  drift = ''
  if has('pound') then
    inner = "CASE WHEN v.`pound` IS NOT NULL AND v.`pound` <> '' THEN 2 WHEN v.`stored` = 1 THEN 1 ELSE 0 END"
    drift = "WHEN COALESCE(v.`nz_state`, 1) <> 2 AND v.`pound` IS NOT NULL AND v.`pound` <> '' THEN 2 "
  else
    inner = 'CASE WHEN v.`stored` = 1 THEN 1 WHEN v.`nz_state` = 2 THEN 2 ELSE 0 END'
  end
  return ('(CASE WHEN %s THEN (%s) %sELSE v.`nz_state` END)'):format(UNMANAGED_SQL, inner, drift)
end

local function statements()
  local s = DB.schema
  if stmt.version == s.version and stmt.select then return stmt end
  local cols = {}
  local function add(list)
    for _, name in ipairs(list) do
      if has(name) then cols[#cols + 1] = ('v.`%s` AS `%s`'):format(name, name) end
    end
  end
  add(isEsx and ESX_SELECT or QB_SELECT)
  add(NZ_SELECT)
  local join = ''
  if s.financeMode == 'columns' then
    add(QB_FINANCE)
  elseif s.financeMode == 'table' then
    for _, name in ipairs(QB_FINANCE) do
      cols[#cols + 1] = ('f.`%s` AS `nzf_%s`'):format(name, name)
    end
    join = ' LEFT JOIN `vehicle_financing` f ON f.`vehicleId` = v.`id`'
  end
  stmt.select = ('SELECT %s FROM `%s` v%s'):format(table.concat(cols, ', '), VT, join)
  stmt.effectiveState = buildEffectiveStateSql()
  stmt.version = s.version
  return stmt
end

---------------------------------------------------------------------------------------
-- Row mapping
---------------------------------------------------------------------------------------

--- Effective state code. nz_state is authoritative for rows this resource manages (they
--- have an nz_garage). Rows without nz_garage were never stored by nayzeee-garages (e.g.
--- inserted by a dealership after the migration, with the nz_state column default), so
--- their state comes from the framework columns, which we always mirror on writes (a qb
--- depot impound, `state = 0` with `depotprice > 0`, counts as impounded there too).
--- Because every state write mirrors those columns, a managed row whose framework columns
--- say "impounded" while nz_state does not was impounded by another resource (qb-policejob
--- seizure `state = 2` / depot `state = 0, depotprice > 0`, esx_garage `pound`): that wins.
--- Keep in sync with buildEffectiveStateSql.
local function effectiveState(r)
  local nz = num(r.nz_state)
  if not nonEmpty(r.nz_garage) then
    if not isEsx then
      if r.state ~= nil then
        local s = num(r.state)
        if s == 0 then
          return (has('depotprice') and (num(r.depotprice) or 0) > 0) and 2 or 0
        elseif s == 2 then
          return 2
        end
        return 1
      end
    elseif has('stored') then
      if has('pound') then
        if nonEmpty(r.pound) then return 2 end
        return truthy(r.stored) and 1 or 0
      end
      if truthy(r.stored) then return 1 end
      return nz == 2 and 2 or 0
    end
  elseif not isEsx then
    if has('state') then
      local s = num(r.state)
      if s == 2 and nz ~= 2 then return 2 end
      if s == 0 and nz == 0 and has('depotprice') and (num(r.depotprice) or 0) > 0 then return 2 end
    end
  elseif has('stored') and has('pound') and nz ~= 2 and nonEmpty(r.pound) then
    return 2
  end
  if nz == 0 or nz == 1 or nz == 2 then return math.floor(nz) end
  return 1
end

local intervalCache = nil   -- detected vehicle shop payment interval (false = none found)

--- Payment interval (hours) of the framework vehicle shop whose finance we mirror.
--- Order: ServerConfig.FinanceIntervalHours, settings `economy.financeIntervalHours`, the
--- running qbx_vehicleshop / qb-vehicleshop config, else 24 (both shops' default).
---@return number hours
function DB.financeIntervalHours()
  local configured = tonumber(type(ServerConfig) == 'table' and ServerConfig.FinanceIntervalHours or nil)
  if configured and configured > 0 then return configured end
  if type(NZ.Settings) == 'table' and type(NZ.Settings.get) == 'function' then
    local ok, value = pcall(NZ.Settings.get, 'economy.financeIntervalHours', nil)
    value = ok and tonumber(value) or nil
    if value and value > 0 then return value end
  end
  if intervalCache == nil then
    intervalCache = false
    local candidates = {
      { 'qbx_vehicleshop', { 'config/shared.lua', 'config/server.lua', 'config.lua' } },
      { 'qb-vehicleshop', { 'config.lua' } },
    }
    for _, candidate in ipairs(candidates) do
      if GetResourceState(candidate[1]) == 'started' then
        for _, file in ipairs(candidate[2]) do
          local ok, text = pcall(LoadResourceFile, candidate[1], file)
          local value = ok and type(text) == 'string' and tonumber(text:match('[Pp]aymentInterval%s*=%s*([%d%.]+)')) or nil
          if value and value > 0 then
            intervalCache = value
            break
          end
        end
      end
      if intervalCache then break end
    end
  end
  return intervalCache or 24
end

--- Finance of a raw row (docs §4.5), or nil when nothing is owed.
--- QBCore / Qbox: the framework columns (qb `player_vehicles`, qbx `vehicle_financing`) hold
--- balance / payment / payments left, so a payment or pay-off made by another script (the
--- vehicle shop's own menu) is always seen. Our nz_finance record adds the wall-clock due date,
--- the plan length and missed payments while it still matches those columns ("managed");
--- otherwise (a vehicle shop wrote the plan) the due date is the shop's `financetime` countdown
--- (minutes). ESX (no framework finance): the nz_finance record alone.
local function financeOf(r)
  local mode = DB.schema.financeMode
  local now = os.time()
  local meta = decodeTable(r.nz_finance)
  local balance, payment, left, minutes
  if mode == 'columns' then
    balance, payment, left, minutes = r.balance, r.paymentamount, r.paymentsleft, r.financetime
  elseif mode == 'table' then
    balance, payment, left, minutes = r.nzf_balance, r.nzf_paymentamount, r.nzf_paymentsleft, r.nzf_financetime
  end

  local managed
  if mode == 'columns' or mode == 'table' then
    balance = tonumber(balance) or 0
    if balance <= 0 then return nil end
    payment = tonumber(payment) or 0
    left = tonumber(left) or 0
    managed = meta ~= nil and int(meta.balance, -1) == math.floor(balance)
      and int(meta.paymentsLeft, -1) == math.floor(left)
  else
    if not meta then return nil end
    balance = tonumber(meta.balance) or 0
    if balance <= 0 then return nil end
    payment = tonumber(meta.payment) or 0
    left = tonumber(meta.paymentsLeft) or 0
    managed = true
  end

  -- Total payments are not stored by the vehicle shops: our record (or nz_finance_total,
  -- recorded on the first payment through this resource / by an admin) has it.
  local total = tonumber(meta and meta.paymentsTotal) or tonumber(r.nz_finance_total)
  if total and total < left then total = nil end

  local nextAt = managed and int(meta.nextPaymentAt, nil) or nil
  local interval = managed and tonumber(meta.intervalHours) or nil
  if not interval or interval <= 0 then interval = DB.financeIntervalHours() end
  local overdue
  if nextAt then
    overdue = now >= nextAt
  else
    minutes = tonumber(minutes) or 0
    nextAt = now + math.floor(math.max(minutes, 0) * 60)
    overdue = left > 0 and minutes <= 0
  end
  return {
    balance = math.floor(balance),
    payment = math.floor(payment),
    paymentsLeft = math.floor(left),
    paymentsTotal = total and math.floor(total) or nil,
    intervalHours = interval,
    nextPaymentHours = Utils.round(math.max(nextAt - now, 0) / 3600, 1),
    nextPaymentAt = nextAt,
    overdue = overdue,
    missed = managed and math.max(int(meta.missed, 0), 0) or 0,
    missedDue = managed and int(meta.missedDue, nil) or nil,
    since = managed and int(meta.since, nil) or nil,
    managed = managed == true,
  }
end

local function health(v)
  local n = tonumber(v)
  if not n then return nil end
  return pct(n / 10, 100)
end

--- ImpoundInfo for a vehicle impounded through the framework columns (no nz_impound):
--- pre-install / 3rd-party impounds (qb `state = 2` or depot, ESX `pound`). Points at an
--- enabled impound of the vehicle's category (ESX pound name, then garages.restartImpound,
--- then the lowest id) so owners and staff can find it. nil when no impound exists.
--- `memo` (one table per query, see fetchRows) keeps the impound list for every row.
local function legacyImpound(r, row, memo)
  local list, preferred
  if memo and memo.impounds ~= nil then
    list, preferred = memo.impounds, memo.preferred
  else
    local Locations = NZ.Locations
    if type(Locations) == 'table' and type(Locations.all) == 'function' then
      local okList, value = pcall(Locations.all, 'impound')
      list = okList and type(value) == 'table' and value or false
    else
      list = false
    end
    if type(NZ.Settings) == 'table' and type(NZ.Settings.get) == 'function' then
      local okSetting, value = pcall(NZ.Settings.get, 'garages.restartImpound', nil)
      preferred = okSetting and tonumber(value) or nil
    end
    if memo then memo.impounds, memo.preferred = list, preferred end
  end
  if not list then return nil end

  local vtype = row.vehicleType
  if type(NZ.Vehicles) == 'table' and type(NZ.Vehicles.vehicleTypeOf) == 'function' then
    local okType, value = pcall(NZ.Vehicles.vehicleTypeOf, row)
    if okType and Utils.vehicleTypes[value] then vtype = value end
  end
  local pound = isEsx and nonEmpty(r.pound) and r.pound:lower() or nil

  local best, bestScore = nil, -1
  for _, location in ipairs(list) do
    if type(location) == 'table' and location.kind == 'impound' and location.enabled ~= false and tonumber(location.id) then
      local score = 0
      if (location.vehicleType or 'car') == vtype then score = score + 4 end
      if pound and type(location.name) == 'string' and location.name:lower() == pound then score = score + 2 end
      if preferred and tonumber(location.id) == preferred then score = score + 1 end
      if score > bestScore or (score == bestScore and tonumber(location.id) < tonumber(best.id)) then
        best, bestScore = location, score
      end
    end
  end
  if not best then return nil end

  local depot = (not isEsx) and (num(r.depotprice) or 0) or 0
  local fee = depot > 0 and math.floor(depot) or math.max(int(best.defaultFee, 0), 0)
  -- qb `state = 2` is a police seizure: released by impound staff, when the impound has any.
  local seized = (not isEsx) and num(r.state) == 2
  local staffed = type(best.jobs) == 'table' and #best.jobs > 0
  return {
    locationId = best.id,
    locationName = type(best.name) == 'string' and best.name or '',
    reason = '',
    fee = fee,
    by = nil,
    byName = type(L) == 'function' and L('Impound service') or '',
    at = 0,
    releaseAt = 0,
    retrievable = not (seized and staffed),
  }
end

--- Raw DB row -> NZVehicleRow (docs §4.1). Returns nil for rows without a usable plate.
--- `memo`: per-query cache shared by the rows of one result (see legacyImpound).
local function mapRow(r, memo)
  local plate = Utils.plate(r.plate)
  if not plate then return nil end
  local props = decodeTable(r[PROPS_COL]) or {}
  if Utils.plate(props.plate) ~= plate then props.plate = plate end

  local model, hash, fuel, engine, body
  if isEsx then
    if type(props.model) == 'string' and not tonumber(props.model) then model = props.model end
    hash = hashFrom(props.model)
    fuel = pct(props.fuelLevel, 100)
    engine = health(props.engineHealth) or 100
    body = health(props.bodyHealth) or 100
  else
    model = nonEmpty(r.vehicle)
    hash = toSigned(r.hash) or hashFrom(model) or hashFrom(props.model)
    fuel = pct(r.fuel, nil) or pct(props.fuelLevel, 100)
    engine = health(r.engine) or health(props.engineHealth) or 100
    body = health(r.body) or health(props.bodyHealth) or 100
  end
  if hash and props.model == nil then props.model = hash end

  local vehicleType = r.nz_type
  local vehicleTypeKnown = Utils.vehicleTypes[vehicleType] ~= nil
  if not vehicleTypeKnown then
    local esxType = isEsx and type(r.type) == 'string' and ESX_TYPE_CATEGORY[r.type:lower()] or nil
    vehicleTypeKnown = esxType ~= nil
    vehicleType = esxType or 'car'
  end

  local job, gang = nonEmpty(r.nz_job), nonEmpty(r.nz_gang)
  local stateCodeNow = effectiveState(r)

  local row = {
    plate = plate,
    dbPlate = r.plate,
    owner = nonEmpty(r[OWNER_COL]),
    model = model,
    hash = hash,
    props = props,
    garageKey = nonEmpty(r.nz_garage),
    frameworkGarage = nonEmpty(r[GARAGE_COL]),
    state = STATE_NAME[stateCodeNow],
    nickname = nonEmpty(r.nz_nickname),
    vehicleType = vehicleType,
    vehicleTypeKnown = vehicleTypeKnown, -- false: no stored type (QBCore/Qbox rows never stored by us)
    ownerType = job and 'job' or (gang and 'gang') or 'player',
    job = job,
    gang = gang,
    mileage = Utils.round(math.max(tonumber(r.nz_mileage) or 0, 0), 2),
    fuel = fuel,
    engine = engine,
    body = body,
    damage = decodeTable(r.nz_damage),
    trailer = decodeTable(r.nz_trailer),
    impound = decodeTable(r.nz_impound),
    blocked = truthy(r.nz_blocked),
    finance = financeOf(r),
    lastOut = int(r.nz_last_out, nil),
  }
  if stateCodeNow == 2 and row.impound == nil then row.impound = legacyImpound(r, row, memo) end
  return row
end

--- SELECT normalized rows. `where` must use the `v.` alias.
local function fetchRows(where, params, suffix)
  local sql = statements().select .. ' WHERE ' .. where .. (suffix or '')
  local rows, ok = run('query', sql, params)
  local out = {}
  if not ok or type(rows) ~= 'table' then return out end
  local memo = {}
  for i = 1, #rows do
    local row = mapRow(rows[i], memo)
    if row then out[#out + 1] = row end
  end
  return out
end

--- Minimal raw row lookup by plate (exact stored `plate` + requested extra columns).
--- Matches the trimmed and the 8-char padded form, falling back to the normalized plate.
local function fetchRaw(p, extra)
  local cols = { 'v.`plate` AS `plate`' }
  for _, name in ipairs(extra or {}) do
    if has(name) then cols[#cols + 1] = ('v.`%s` AS `%s`'):format(name, name) end
  end
  local base = ('SELECT %s FROM `%s` v WHERE '):format(table.concat(cols, ', '), VT)
  local row = run('single', base .. '(v.`plate` = ? OR v.`plate` = ?) LIMIT 1', { p, padded(p) })
  if not row then
    row = run('single', base .. normPlate('v') .. ' = ? LIMIT 1', { p })
  end
  if type(row) ~= 'table' or type(row.plate) ~= 'string' then return nil end
  return row
end

--- Collects `col = ?` assignments for UPDATE statements (last write per column wins).
local function newSets()
  local list, pos = {}, {}
  local sets = {}
  --- Raw assignment SQL with its parameters (only existing columns).
  function sets.raw(column, sql, ...)
    if not has(column) then return end
    local entry = { sql = sql, params = { ... } }
    local i = pos[column]
    if i then list[i] = entry else
      list[#list + 1] = entry
      pos[column] = #list
    end
  end
  --- `column = value`; nil writes NULL.
  function sets.set(column, value)
    if value == nil then
      sets.raw(column, ('`%s` = NULL'):format(column))
    else
      sets.raw(column, ('`%s` = ?'):format(column), value)
    end
  end
  function sets.compile()
    if #list == 0 then return nil, nil end
    local parts, params = {}, {}
    for i = 1, #list do
      parts[i] = list[i].sql
      for _, v in ipairs(list[i].params) do params[#params + 1] = v end
    end
    return table.concat(parts, ', '), params
  end
  return sets
end

--- Finance table -> balance, payment, paymentsLeft, financetime minutes (nil = unchanged).
local function financeValues(fin)
  if fin == false then return 0, 0, 0, 0 end
  local balance = math.max(int(fin.balance, 0), 0)
  local payment = math.max(int(fin.payment, 0), 0)
  local left = math.max(int(fin.paymentsLeft, 0), 0)
  local minutes
  local nextAt = int(fin.nextPaymentAt, nil)
  if nextAt then
    minutes = math.max(math.ceil((nextAt - os.time()) / 60), 0)
  else
    local hours = tonumber(fin.nextPaymentHours) or tonumber(fin.intervalHours)
    minutes = hours and math.max(math.floor(hours * 60 + 0.5), 0) or nil
  end
  return balance, payment, left, minutes
end

--- The nz_finance record written for a Finance table (docs §4.5 + API fields). The due date
--- is wall-clock: nextPaymentAt, else now + nextPaymentHours / intervalHours.
local function financeRecord(fin)
  local now = os.time()
  local interval = tonumber(fin.intervalHours)
  if not interval or interval <= 0 then interval = DB.financeIntervalHours() end
  local nextAt = int(fin.nextPaymentAt, nil)
  if not nextAt then
    local hours = tonumber(fin.nextPaymentHours) or interval
    nextAt = now + math.floor(math.max(hours, 0) * 3600 + 0.5)
  end
  local total = int(fin.paymentsTotal, nil)
  return {
    v = 1,
    balance = math.max(int(fin.balance, 0), 0),
    payment = math.max(int(fin.payment, 0), 0),
    paymentsLeft = math.max(int(fin.paymentsLeft, 0), 0),
    paymentsTotal = (total and total > 0) and total or nil,
    intervalHours = interval,
    nextPaymentAt = nextAt,
    missed = math.max(int(fin.missed, 0), 0),
    missedDue = int(fin.missedDue, nil),
    since = int(fin.since, nil) or now,
    by = str(fin.by, 64),
  }
end

--- Is vehicle finance stored anywhere on this server (framework finance or nz_finance)?
---@return boolean
function DB.financeSupported()
  if not ready() then return false end
  return DB.schema.financeMode ~= 'none' or has(FINANCE_COLUMN)
end

--- Add the nz_finance column when an older install does not have it yet (idempotent;
--- server/migrations.lua creates it on fresh installs). Returns true when it exists.
---@return boolean
function DB.ensureFinanceColumn()
  if not ready() then return false end
  if has(FINANCE_COLUMN) then return true end
  local _, ok = run('query', ('ALTER TABLE `%s` ADD COLUMN `%s` LONGTEXT NULL'):format(VT, FINANCE_COLUMN))
  if ok and type(DB.loadSchema) == 'function' then DB.loadSchema(true) end
  return has(FINANCE_COLUMN)
end

--- qbx vehicle_financing write (row keyed by player_vehicles.id).
local function writeFinanceTable(vehicleId, fin)
  vehicleId = int(vehicleId, nil)
  if not vehicleId then
    lib.print.error('[db] cannot write vehicle_financing: vehicle has no id')
    return false
  end
  local balance, payment, left, minutes = financeValues(fin)
  local exists, ok = run('scalar', 'SELECT 1 FROM `vehicle_financing` WHERE `vehicleId` = ? LIMIT 1', { vehicleId })
  if not ok then return false end
  if exists then
    local sql = 'UPDATE `vehicle_financing` SET `balance` = ?, `paymentamount` = ?, `paymentsleft` = ?'
    local params = { balance, payment, left }
    if minutes then
      sql = sql .. ', `financetime` = ?'
      params[#params + 1] = minutes
    end
    params[#params + 1] = vehicleId
    local _, updated = run('update', sql .. ' WHERE `vehicleId` = ?', params)
    return updated
  end
  if fin == false then return true end
  local _, inserted = run('update', [[INSERT INTO `vehicle_financing`
    (`vehicleId`, `balance`, `paymentamount`, `paymentsleft`, `financetime`) VALUES (?, ?, ?, ?, ?)]],
    { vehicleId, balance, payment, left, minutes or 0 })
  return inserted
end

---------------------------------------------------------------------------------------
-- Vehicles: reads
---------------------------------------------------------------------------------------

--- Load one vehicle by plate (either stored form).
---@param plate string
---@return table|nil NZVehicleRow
function DB.getVehicle(plate)
  local p = Utils.plate(plate)
  if not p or not ready() then return nil end
  local rows = fetchRows('(v.`plate` = ? OR v.`plate` = ?)', { p, padded(p) }, ' LIMIT 1')
  if not rows[1] then
    rows = fetchRows(normPlate('v') .. ' = ?', { p }, ' LIMIT 1')
  end
  return rows[1]
end

--- Every vehicle owned by a character identifier.
---@param identifier string
---@return table[] NZVehicleRow list
function DB.getVehiclesByOwner(identifier)
  identifier = str(identifier, 64)
  if not identifier or not ready() or not has(OWNER_COL) then return {} end
  return fetchRows(('v.`%s` = ?'):format(OWNER_COL), { identifier })
end

--- Vehicles for a list of plates (one IN query per 250 plates, TRIM fallback for misses).
---@param plates string[]
---@return table[] NZVehicleRow list (at most one row per plate)
function DB.getVehiclesByPlates(plates)
  if type(plates) ~= 'table' or not ready() then return {} end
  local wanted, list = {}, {}
  for k, v in pairs(plates) do
    local candidate = type(v) == 'string' and v or (type(k) == 'string' and v == true and k) or nil
    local p = Utils.plate(candidate)
    if p and not wanted[p] then
      wanted[p] = true
      list[#list + 1] = p
    end
  end
  if #list == 0 then return {} end

  local out, found = {}, {}
  local function collect(rows)
    for _, row in ipairs(rows) do
      if wanted[row.plate] and not found[row.plate] then
        found[row.plate] = true
        out[#out + 1] = row
      end
    end
  end

  for i = 1, #list, CHUNK do
    local forms = {}
    for j = i, math.min(i + CHUNK - 1, #list) do
      local p = list[j]
      forms[#forms + 1] = p
      local pad = padded(p)
      if pad ~= p then forms[#forms + 1] = pad end
    end
    collect(fetchRows('v.`plate` IN (?)', { forms }))
  end

  local missing = {}
  for _, p in ipairs(list) do
    if not found[p] then missing[#missing + 1] = p end
  end
  for i = 1, #missing, CHUNK do
    local chunk = table.move(missing, i, math.min(i + CHUNK - 1, #missing), 1, {})
    collect(fetchRows(normPlate('v') .. ' IN (?)', { chunk }))
  end
  return out
end

--- Every vehicle whose nz_garage is `garageKey` (any state).
---@param garageKey string
---@return table[]
function DB.getVehiclesInGarage(garageKey)
  garageKey = str(garageKey, 64)
  if not garageKey or not ready() or not has('nz_garage') then return {} end
  return fetchRows('v.`nz_garage` = ?', { garageKey })
end

--- Job-owned fleet vehicles.
---@param job string
---@return table[]
function DB.getVehiclesByJob(job)
  job = str(job, 64)
  if not job or not ready() or not has('nz_job') then return {} end
  return fetchRows('v.`nz_job` = ?', { job })
end

--- Gang-owned fleet vehicles.
---@param gang string
---@return table[]
function DB.getVehiclesByGang(gang)
  gang = str(gang, 64)
  if not gang or not ready() or not has('nz_gang') then return {} end
  return fetchRows('v.`nz_gang` = ?', { gang })
end

--- Impounded vehicles, optionally only those at one impound location.
---@param locationId number|nil
---@return table[]
function DB.getImpounded(locationId)
  if not ready() or not has('nz_state') then return {} end
  local id = locationId ~= nil and tonumber(locationId) or nil
  if locationId ~= nil and not id then return {} end
  -- Effective state: also finds framework / 3rd-party impounds (see effectiveState). The
  -- CASE expression cannot use an index, so it is ANDed with an index-friendly superset:
  -- every way effectiveState can reach 2 (indexed nz_state / framework state columns).
  local any = { 'v.`nz_state` = 2' }
  if isEsx then
    if has('stored') and has('pound') then any[#any + 1] = "(v.`pound` IS NOT NULL AND v.`pound` <> '')" end
  elseif has('state') then
    any[#any + 1] = 'v.`state` = 2'
    if has('depotprice') then any[#any + 1] = '(v.`state` = 0 AND v.`depotprice` > 0)' end
  end
  local rows = fetchRows(('(%s) AND %s = 2'):format(table.concat(any, ' OR '), statements().effectiveState), {})
  local out = {}
  for _, row in ipairs(rows) do
    if row.state == 'impounded'
      and (not id or (type(row.impound) == 'table' and tonumber(row.impound.locationId) == id)) then
      out[#out + 1] = row
    end
  end
  return out
end

--- Every vehicle currently out (spawned or lost).
---@return table[]
function DB.getOutVehicles()
  if not ready() or not has('nz_state') then return {} end
  local rows = fetchRows(statements().effectiveState .. ' = 0', {})
  local out = {}
  for _, row in ipairs(rows) do
    if row.state == 'out' then out[#out + 1] = row end
  end
  return out
end

--- Every vehicle with an overdue finance payment (our record or the framework's), for the
--- finance due-date check. A light query (plate + finance columns only) finds the overdue
--- plans; only those are read in full. Rows carry the normalized `finance` (§4.5).
---@return table[]
function DB.getFinanced()
  if not ready() then return {} end
  local mode = DB.schema.financeMode
  local parts = {}
  if has(FINANCE_COLUMN) then parts[#parts + 1] = ('v.`%s` IS NOT NULL'):format(FINANCE_COLUMN) end
  if mode == 'columns' and has('balance') then
    parts[#parts + 1] = 'v.`balance` > 0'
  elseif mode == 'table' then
    parts[#parts + 1] = 'f.`balance` > 0'
  end
  if #parts == 0 then return {} end

  local cols = { 'v.`plate` AS `plate`' }
  for _, name in ipairs({ FINANCE_COLUMN, 'nz_finance_total' }) do
    if has(name) then cols[#cols + 1] = ('v.`%s` AS `%s`'):format(name, name) end
  end
  local join = ''
  if mode == 'columns' then
    for _, name in ipairs(QB_FINANCE) do
      if has(name) then cols[#cols + 1] = ('v.`%s` AS `%s`'):format(name, name) end
    end
  elseif mode == 'table' then
    for _, name in ipairs(QB_FINANCE) do cols[#cols + 1] = ('f.`%s` AS `nzf_%s`'):format(name, name) end
    join = ' LEFT JOIN `vehicle_financing` f ON f.`vehicleId` = v.`id`'
  end
  local sql = ('SELECT %s FROM `%s` v%s WHERE (%s)'):format(table.concat(cols, ', '), VT, join,
    table.concat(parts, ' OR '))
  local rows, ok = run('query', sql, {})
  local out = {}
  if not ok or type(rows) ~= 'table' then return out end
  for _, r in ipairs(rows) do
    local finance = financeOf(r)
    local plate = Utils.plate(r.plate)
    if plate and type(finance) == 'table' and finance.overdue and finance.balance > 0 then
      local row = DB.getVehicle(plate)
      if row and type(row.finance) == 'table' then out[#out + 1] = row end
    end
  end
  return out
end

--- Every saved trailer: { { plate, trailer = { hash, model, props, damage } }, ... }.
--- Used at boot so a trailer parked away from its vehicle is never taken by another one.
---@return table[]
function DB.getSavedTrailers()
  if not ready() or not has('nz_trailer') then return {} end
  local rows, ok = run('query', ('SELECT `plate`, `nz_trailer` FROM `%s` WHERE `nz_trailer` IS NOT NULL'):format(VT), {})
  local out = {}
  if not ok or type(rows) ~= 'table' then return out end
  for _, r in ipairs(rows) do
    local plate = Utils.plate(r.plate)
    local trailer = decodeTable(r.nz_trailer)
    if plate and type(trailer) == 'table' then out[#out + 1] = { plate = plate, trailer = trailer } end
  end
  return out
end

--- Number of vehicles parked (state garaged) in a garage, optionally for one owner.
---@param garageKey string
---@param ownerIdentifier string|nil
---@return number
function DB.countInGarage(garageKey, ownerIdentifier)
  garageKey = str(garageKey, 64)
  if not garageKey or not ready() or not has('nz_state') or not has('nz_garage') then return 0 end
  -- Effective state, so a vehicle impounded by another resource does not take a space.
  local sql = ('SELECT COUNT(*) FROM `%s` v WHERE v.`nz_garage` = ? AND %s = 1')
    :format(VT, statements().effectiveState)
  local params = { garageKey }
  if ownerIdentifier ~= nil then
    local owner = str(ownerIdentifier, 64)
    if not owner then return 0 end
    sql = sql .. (' AND v.`%s` = ?'):format(OWNER_COL)
    params[2] = owner
  end
  return tonumber((run('scalar', sql, params))) or 0
end

local STATS_TTL_MS = 30000
local garageStatsCache = { at = -STATS_TTL_MS, data = nil }

--- Vehicle counts per garage key and per impound location (admin location overview).
--- One grouped query each, cached for 30 seconds.
---@return { garages: table<string, { parked: number, out: number, impounded: number }>, impounds: table<string, number> }
function DB.garageStats()
  local now = GetGameTimer()
  if garageStatsCache.data and now - garageStatsCache.at < STATS_TTL_MS then return garageStatsCache.data end
  local result = { garages = {}, impounds = {} }
  if not ready() or not has('nz_state') or not has('nz_garage') then return result end
  local state = statements().effectiveState
  if not state then return result end
  local rows = run('query', ('SELECT v.`nz_garage` AS k, %s AS s, COUNT(*) AS n FROM `%s` v '
    .. "WHERE v.`nz_garage` IS NOT NULL AND v.`nz_garage` <> '' GROUP BY v.`nz_garage`, s"):format(state, VT), {})
  for _, row in ipairs(rows or {}) do
    local key = type(row.k) == 'string' and row.k or nil
    if key then
      local entry = result.garages[key] or { parked = 0, out = 0, impounded = 0 }
      local code, count = tonumber(row.s), tonumber(row.n) or 0
      if code == 0 then entry.out = entry.out + count
      elseif code == 2 then entry.impounded = entry.impounded + count
      else entry.parked = entry.parked + count end
      result.garages[key] = entry
    end
  end
  if has('nz_impound') then
    -- Vehicles held per impound location (nz_impound JSON). Older MySQL / MariaDB without
    -- JSON functions only lose this figure.
    local held = run('query', ("SELECT JSON_UNQUOTE(JSON_EXTRACT(v.`nz_impound`, '$.locationId')) AS l, "
      .. 'COUNT(*) AS n FROM `%s` v WHERE %s = 2 AND v.`nz_impound` IS NOT NULL GROUP BY l'):format(VT, state), {})
    for _, row in ipairs(held or {}) do
      local id = tonumber(row.l)
      if id then result.impounds[tostring(math.tointeger(id) or id)] = tonumber(row.n) or 0 end
    end
  end
  garageStatsCache.at, garageStatsCache.data = now, result
  return result
end

--- Whether a plate exists in the vehicle table (either stored form).
--- Returns true on database errors so callers never create duplicate plates.
--- `exactOnly`: only the indexed trimmed / 8-char padded forms (plate generators: their
--- candidates are trimmed upper-case; DB.insertVehicle still runs the full check).
---@param plate string
---@param exactOnly boolean|nil
---@return boolean
function DB.plateExists(plate, exactOnly)
  local p = Utils.plate(plate)
  if not p then return false end
  if not ready() then return true end
  local res, ok = run('scalar', ('SELECT 1 FROM `%s` WHERE `plate` = ? OR `plate` = ? LIMIT 1'):format(VT),
    { p, padded(p) })
  if not ok then return true end
  if res ~= nil then return true end
  if exactOnly == true then return false end
  res, ok = run('scalar', ('SELECT 1 FROM `%s` WHERE %s = ? LIMIT 1'):format(VT, normPlate(nil)), { p })
  if not ok then return true end
  return res ~= nil
end

--- Admin plate search (LIKE match anywhere in the plate).
---@param query string
---@param limit number|nil default 20, max 100
---@return table[] { { plate, owner } }
function DB.searchPlates(query, limit)
  local q = type(query) == 'string' and Utils.trim(query):upper() or nil
  if not q or q == '' or not ready() then return {} end
  q = q:sub(1, 16)
  local like = '%' .. q:gsub('[\\%%_]', '\\%0') .. '%'
  limit = math.floor(Utils.clamp(int(limit, 20), 1, 100))
  local ownerSql = has(OWNER_COL) and ('v.`%s`'):format(OWNER_COL) or 'NULL'
  local rows = run('query', ('SELECT v.`plate` AS `plate`, %s AS `owner` FROM `%s` v WHERE v.`plate` LIKE ? '
    .. 'ORDER BY v.`plate` LIMIT ?'):format(ownerSql, VT), { like, limit })
  local out = {}
  for _, r in ipairs(rows or {}) do
    local p = Utils.plate(r.plate)
    if p then out[#out + 1] = { plate = p, owner = nonEmpty(r.owner) } end
  end
  return out
end

---------------------------------------------------------------------------------------
-- Vehicles: writes
---------------------------------------------------------------------------------------

--- Update a vehicle. Every field is optional (see docs §5.2); `false` clears nullable ones.
---@param plate string
---@param fields table
---@return boolean
function DB.updateVehicle(plate, fields)
  local p = Utils.plate(plate)
  if not p or type(fields) ~= 'table' or not ready() then return false end
  local financeMode = DB.schema.financeMode
  local propsGiven = type(fields.props) == 'table'

  -- Current values needed: ESX keeps model/fuel/health inside the props JSON; qbx finance
  -- rows are keyed by player_vehicles.id.
  local extra = {}
  local esxNeedsProps = isEsx and (propsGiven or fields.hash ~= nil or fields.fuel ~= nil
    or fields.engine ~= nil or fields.body ~= nil)
  if esxNeedsProps then extra[#extra + 1] = PROPS_COL end
  if not isEsx and fields.finance ~= nil and financeMode == 'table' then extra[#extra + 1] = 'id' end
  local raw = fetchRaw(p, extra)
  if not raw then return false end
  local storedPlate = Utils.plate(raw.plate) or p

  local sets = newSets()
  local set = sets.set

  -- owner
  if fields.owner ~= nil then
    local owner = fields.owner ~= false and str(fields.owner, 64) or nil
    if isEsx then
      set('owner', owner or '')
    else
      set('citizenid', owner)
      -- '' instead of NULL: some framework versions declare `license` NOT NULL
      if has('license') then set('license', licenseFor(owner) or '') end
    end
  end

  -- model / hash
  local hash = fields.hash ~= nil and hashFrom(fields.hash) or nil
  if not isEsx then
    local model = str(fields.model, 50)
    if model then
      set('vehicle', model)
      hash = hash or hashFrom(model)
    end
    if hash then set('hash', tostring(hash)) end
  end

  -- props (+ keep plate/model/fuel/health inside them consistent)
  local props
  if propsGiven then props = Utils.deepCopy(fields.props) end
  if esxNeedsProps and not props then props = decodeTable(raw[PROPS_COL]) or {} end
  if props then
    props.plate = storedPlate
    if hash then
      props.model = hash
    elseif props.model == nil and isEsx then
      local current = decodeTable(raw[PROPS_COL])
      if current and current.model ~= nil then props.model = current.model end
    end
    if fields.fuel ~= nil and pct(fields.fuel) then props.fuelLevel = pct(fields.fuel) end
    if fields.engine ~= nil and pct(fields.engine) then props.engineHealth = pct(fields.engine) * 10 end
    if fields.body ~= nil and pct(fields.body) then props.bodyHealth = pct(fields.body) * 10 end
    local encoded = encode(props, 'props of ' .. storedPlate)
    if encoded then set(PROPS_COL, encoded) end
  end

  -- qb fuel / engine / body columns
  if not isEsx then
    if pct(fields.fuel) then set('fuel', math.floor(pct(fields.fuel) + 0.5)) end
    if pct(fields.engine) then set('engine', Utils.round(pct(fields.engine) * 10, 1)) end
    if pct(fields.body) then set('body', Utils.round(pct(fields.body) * 10, 1)) end
  end

  -- garage
  if fields.garageKey ~= nil then
    local key = fields.garageKey ~= false and str(fields.garageKey, 64) or nil
    if key and not Utils.key.parse(key) then
      lib.print.warn(('[db] updateVehicle %s: ignoring invalid garage key %s'):format(storedPlate, key))
    else
      set('nz_garage', key)
    end
  end
  if fields.garageName ~= nil then
    set(GARAGE_COL, fields.garageName ~= false and str(fields.garageName, 50) or nil)
  end

  -- state (+ framework mirrors) and impound info
  local code = fields.state ~= nil and stateCode(fields.state) or nil
  local impound = fields.impound
  if code then
    set('nz_state', code)
    if isEsx then set('stored', code == 1 and 1 or 0) else set('state', code) end
  end
  if impound == false then
    set('nz_impound', nil)
    set('depotprice', 0)
  elseif type(impound) == 'table' then
    local encoded = encode(impound, 'impound info of ' .. storedPlate)
    if encoded then set('nz_impound', encoded) end
    set('depotprice', math.max(int(impound.fee, 0), 0))
  end
  if isEsx then
    if code == 2 then
      local name = impoundName(impound)
      if name then
        set('pound', name)
      else
        sets.raw('pound', "`pound` = COALESCE(NULLIF(`pound`, ''), ?)", 'impound')
      end
    elseif code ~= nil or impound == false then
      set('pound', nil)
    end
  elseif code ~= nil and code ~= 2 and impound == nil then
    set('depotprice', 0)
  end

  -- descriptive fields
  if fields.nickname ~= nil then
    set('nz_nickname', fields.nickname ~= false and Utils.cleanText(fields.nickname, 64) or nil)
  end
  if Utils.vehicleTypes[fields.vehicleType] then
    set('nz_type', fields.vehicleType)
    if isEsx then
      if fields.vehicleType == 'air' then
        sets.raw('type', "`type` = IF(LOWER(`type`) IN ('airplane', 'helicopter', 'plane', 'heli'), `type`, ?)",
          'airplane')
      else
        set('type', esxTypeFor(fields.vehicleType))
      end
    end
  end

  -- ownership kind: nil = untouched, false = clear, string = set
  local job, gang
  if fields.job ~= nil then job = (fields.job ~= false and str(fields.job, 64)) or false end
  if fields.gang ~= nil then gang = (fields.gang ~= false and str(fields.gang, 64)) or false end
  if fields.ownerType == 'player' then
    job, gang = false, false
  elseif fields.ownerType == 'job' then
    gang = false
  elseif fields.ownerType == 'gang' then
    job = false
  end
  if job ~= nil then set('nz_job', job or nil) end
  if gang ~= nil then set('nz_gang', gang or nil) end

  -- runtime data
  if tonumber(fields.mileage) then
    set('nz_mileage', Utils.round(math.max(tonumber(fields.mileage), 0), 3))
  end
  if fields.damage == false then
    set('nz_damage', nil)
  elseif type(fields.damage) == 'table' then
    local encoded = encode(fields.damage, 'damage of ' .. storedPlate)
    if encoded then set('nz_damage', encoded) end
  end
  if fields.trailer == false then
    set('nz_trailer', nil)
  elseif type(fields.trailer) == 'table' then
    local encoded = encode(fields.trailer, 'trailer of ' .. storedPlate)
    if encoded then set('nz_trailer', encoded) end
  end
  if fields.blocked ~= nil then set('nz_blocked', truthy(fields.blocked) and 1 or 0) end
  if fields.lastOut == false then
    set('nz_last_out', nil)
  elseif int(fields.lastOut, nil) then
    set('nz_last_out', int(fields.lastOut, nil))
  end

  -- finance (qb columns go in the same statement; qbx table is written afterwards; our own
  -- record with the due date on every framework)
  if fields.finance == false then
    set('nz_finance_total', nil)
    set(FINANCE_COLUMN, nil)
  elseif type(fields.finance) == 'table' then
    if fields.finance.paymentsTotal ~= nil then
      local total = int(fields.finance.paymentsTotal, nil)
      set('nz_finance_total', (total and total > 0) and total or nil)
    end
    local record = financeRecord(fields.finance)
    if record.balance <= 0 then
      set(FINANCE_COLUMN, nil)
    else
      local encoded = encode(record, 'finance of ' .. storedPlate)
      if encoded then set(FINANCE_COLUMN, encoded) end
    end
  end
  local financeTable = false
  if not isEsx and (fields.finance == false or type(fields.finance) == 'table') then
    if financeMode == 'columns' then
      local balance, payment, left, minutes = financeValues(fields.finance)
      set('balance', balance)
      set('paymentamount', payment)
      set('paymentsleft', left)
      if minutes then set('financetime', minutes) end
    elseif financeMode == 'table' then
      financeTable = true
    end
  end

  local ok = true
  local assignments, params = sets.compile()
  if assignments then
    params[#params + 1] = raw.plate
    local _, success = run('update', ('UPDATE `%s` SET %s WHERE `plate` = ?'):format(VT, assignments), params)
    ok = success
  end
  if ok and financeTable then
    ok = writeFinanceTable(raw.id, fields.finance)
  end
  return ok
end

--- Insert a new owned vehicle. Fails when the plate already exists.
---@param data table { owner, model, hash, plate, props, garageKey, garageName, state, vehicleType, ownerType, job, gang }
---@return boolean
function DB.insertVehicle(data)
  if type(data) ~= 'table' or not ready() then return false end
  local plate = Utils.plate(data.plate)
  if not plate or #plate > PLATE_MAX then
    lib.print.warn(('[db] insertVehicle: invalid plate %s'):format(tostring(data.plate)))
    return false
  end
  local model = str(data.model, 50)
  local hash = hashFrom(data.hash) or hashFrom(model)
  if not hash then
    lib.print.warn(('[db] insertVehicle %s: missing model / hash'):format(plate))
    return false
  end
  if DB.plateExists(plate) then
    lib.print.warn(('[db] insertVehicle: plate %s already exists'):format(plate))
    return false
  end

  local props = type(data.props) == 'table' and Utils.deepCopy(data.props) or decodeTable(data.props) or {}
  props.plate = plate
  props.model = hash
  local fuel, engine, body = pct(data.fuel), pct(data.engine), pct(data.body)
  if fuel then props.fuelLevel = fuel end
  if engine then props.engineHealth = engine * 10 end
  if body then props.bodyHealth = body * 10 end
  local propsJson = encode(props, 'props of ' .. plate) or '{}'

  local code = stateCode(data.state) or 1
  local vehicleType = Utils.vehicleTypes[data.vehicleType] and data.vehicleType or 'car'
  local owner = str(data.owner, 64)
  local ownerType = data.ownerType
  local job = (ownerType == 'job' or ownerType == nil) and str(data.job, 64) or nil
  local gang = (ownerType == 'gang' or ownerType == nil) and not job and str(data.gang, 64) or nil
  local garageKey = str(data.garageKey, 64)
  if garageKey and not Utils.key.parse(garageKey) then garageKey = nil end
  local garageName = str(data.garageName, 50)
  local impound = type(data.impound) == 'table' and data.impound or nil

  local cols, marks, params = {}, {}, {}
  local function add(column, value)
    if value == nil or not has(column) then return end
    cols[#cols + 1] = ('`%s`'):format(column)
    marks[#marks + 1] = '?'
    params[#params + 1] = value
  end

  if isEsx then
    add('owner', owner or '')
    add('plate', plate)
    add('vehicle', propsJson)
    add('type', esxTypeFor(vehicleType))
    add('stored', code == 1 and 1 or 0)
    add('parking', garageName)
    if code == 2 then add('pound', impoundName(impound) or 'impound') end
  else
    if has('license') then add('license', licenseFor(owner) or '') end
    add('citizenid', owner)
    add('vehicle', model)
    add('hash', tostring(hash))
    add('mods', propsJson)
    add('plate', plate)
    add('garage', garageName)
    add('state', code)
    if fuel then add('fuel', math.floor(fuel + 0.5)) end
    if engine then add('engine', engine * 10) end
    if body then add('body', body * 10) end
    if impound then add('depotprice', math.max(int(impound.fee, 0), 0)) end
  end

  add('nz_garage', garageKey)
  add('nz_state', code)
  add('nz_type', vehicleType)
  add('nz_job', job)
  add('nz_gang', gang)
  add('nz_nickname', Utils.cleanText(data.nickname, 64))
  if tonumber(data.mileage) then add('nz_mileage', math.max(tonumber(data.mileage), 0)) end
  if impound then add('nz_impound', encode(impound, 'impound info of ' .. plate)) end

  local sql = ('INSERT INTO `%s` (%s) VALUES (%s)'):format(VT, table.concat(cols, ', '), table.concat(marks, ', '))
  local affected, ok = run('update', sql, params)
  return ok and (tonumber(affected) or 0) > 0
end

--- Delete a vehicle and its favourites, shares and history.
---@param plate string
---@return boolean
function DB.deleteVehicle(plate)
  local p = Utils.plate(plate)
  if not p or not ready() then return false end
  local financeTable = DB.schema.financeMode == 'table'
  local raw = fetchRaw(p, financeTable and { 'id' } or nil)
  if not raw then return false end
  local queries = {}
  if financeTable and int(raw.id, nil) then
    queries[#queries + 1] = { query = 'DELETE FROM `vehicle_financing` WHERE `vehicleId` = ?', values = { int(raw.id, nil) } }
  end
  queries[#queries + 1] = { query = ('DELETE FROM `%s` WHERE `plate` = ?'):format(VT), values = { raw.plate } }
  queries[#queries + 1] = { query = 'DELETE FROM `nz_favourites` WHERE `plate` = ?', values = { p } }
  queries[#queries + 1] = { query = 'DELETE FROM `nz_shares` WHERE `plate` = ?', values = { p } }
  queries[#queries + 1] = { query = 'DELETE FROM `nz_vehicle_events` WHERE `plate` = ?', values = { p } }
  queries[#queries + 1] = { query = 'DELETE FROM `nz_keys` WHERE `plate` = ?', values = { p } }
  if DB.keyTables then
    queries[#queries + 1] = { query = 'DELETE FROM `nz_key_security` WHERE `plate` = ?', values = { p } }
    queries[#queries + 1] = { query = 'DELETE FROM `nz_key_items` WHERE `plate` = ?', values = { p } }
  end
  return transaction(queries)
end

--- Change a plate everywhere (framework table + props.plate + every nz_* table), atomically.
--- Fails when the new plate is invalid (1-8 letters, digits, spaces) or already exists.
---@param oldPlate string
---@param newPlate string
---@return boolean
function DB.changePlate(oldPlate, newPlate)
  local old, new = Utils.plate(oldPlate), Utils.plate(newPlate)
  if not old or not new or #new > PLATE_MAX or not new:match('^[A-Z0-9 ]+$') then return false end
  if not ready() then return false end
  local raw = fetchRaw(old, { PROPS_COL })
  if not raw then return false end
  if new ~= old and DB.plateExists(new) then return false end

  local props = decodeTable(raw[PROPS_COL]) or {}
  props.plate = new
  local propsJson = encode(props, 'props of ' .. old)
  if not propsJson then return false end

  local queries = {
    { query = ('UPDATE `%s` SET `plate` = ?, `%s` = ? WHERE `plate` = ?'):format(VT, PROPS_COL),
      values = { new, propsJson, raw.plate } },
  }
  if new ~= old then
    local function add(sql, values) queries[#queries + 1] = { query = sql, values = values } end
    -- rows left behind by a vehicle deleted outside this resource would collide
    add('DELETE FROM `nz_favourites` WHERE `plate` = ?', { new })
    add('UPDATE `nz_favourites` SET `plate` = ? WHERE `plate` = ?', { new, old })
    add('DELETE FROM `nz_shares` WHERE `plate` = ?', { new })
    add('UPDATE `nz_shares` SET `plate` = ? WHERE `plate` = ?', { new, old })
    add('DELETE FROM `nz_vehicle_events` WHERE `plate` = ?', { new })
    add('UPDATE `nz_vehicle_events` SET `plate` = ? WHERE `plate` = ?', { new, old })
    add('UPDATE `nz_logs` SET `plate` = ? WHERE `plate` = ?', { new, old })
    add('DELETE FROM `nz_keys` WHERE `plate` = ?', { new })
    add('UPDATE `nz_keys` SET `plate` = ? WHERE `plate` = ?', { new, old })
    if DB.keyTables then
      -- key items are signed for the old plate (they stop working); the immobiliser moves along
      add('DELETE FROM `nz_key_security` WHERE `plate` = ?', { new })
      add('UPDATE `nz_key_security` SET `plate` = ? WHERE `plate` = ?', { new, old })
      add('DELETE FROM `nz_key_items` WHERE `plate` = ?', { old })
    end
  end
  return transaction(queries)
end

--- Server start handling of vehicles left out (settings garages.outOnRestart).
---  'garage'  -> back to their last garage. Rows never stored by this resource (no
---               nz_garage: dealership purchases, pre-install rows) become garaged without
---               a garage key, i.e. retrievable from any garage of their type.
---  'impound' -> impounded with `impoundInfo`
--- Rows impounded through the framework columns (qb depot / seizure, ESX pound) are not
--- "out" (see effectiveState) and are left alone.
---@param mode 'garage'|'impound'
---@param impoundInfo table|nil ImpoundInfo
---@return number affected rows
function DB.resetOutVehicles(mode, impoundInfo)
  if not ready() or not has('nz_state') then return 0 end
  local sets = newSets()
  local where
  if mode == 'garage' then
    if not has('nz_garage') then return 0 end
    sets.set('nz_state', 1)
    if isEsx then
      sets.set('stored', 1)
      sets.set('pound', nil)
    else
      sets.set('state', 1)
    end
    -- effective state: rows impounded by another resource (see effectiveState) stay impounded
    where = statements().effectiveState .. ' = 0'
    if not isEsx and has('depotprice') then
      -- belt and braces: never free a qb depot impound (effectiveState already says 2)
      where = where .. " AND ((v.`nz_garage` IS NOT NULL AND v.`nz_garage` <> '') OR COALESCE(v.`depotprice`, 0) = 0)"
    end
  elseif mode == 'impound' then
    local info = type(impoundInfo) == 'table' and impoundInfo or nil
    sets.set('nz_state', 2)
    sets.set('nz_impound', info and encode(info, 'impound info') or nil)
    if isEsx then
      sets.set('stored', 0)
      sets.set('pound', impoundName(info) or 'impound')
    else
      sets.set('state', 2)
      sets.set('depotprice', info and math.max(int(info.fee, 0), 0) or 0)
    end
    where = statements().effectiveState .. ' = 0'
  else
    return 0
  end
  local assignments, params = sets.compile()
  -- qualify assignments with the alias used by the WHERE expression
  assignments = assignments:gsub('`([%w_]+)` =', 'v.`%1` =')
  local affected = run('update', ('UPDATE `%s` v SET %s WHERE %s'):format(VT, assignments, where), params)
  return tonumber(affected) or 0
end

---------------------------------------------------------------------------------------
-- Generic row helpers for nz_* tables
---------------------------------------------------------------------------------------

--- True when an UPDATE matched (some drivers report 0 rows when nothing changed).
local function updatedOrExists(affected, ok, tableName, id)
  if not ok then return false end
  if (tonumber(affected) or 0) > 0 then return true end
  return run('scalar', ('SELECT 1 FROM `%s` WHERE `id` = ? LIMIT 1'):format(tableName), { id }) ~= nil
end

local function validId(id)
  id = int(id, nil)
  if id and id > 0 then return id end
  return nil
end

---------------------------------------------------------------------------------------
-- Locations / interiors
---------------------------------------------------------------------------------------

DB.locations = {}

--- Every location: { { id, kind, name, enabled, data = table } }
function DB.locations.all()
  local rows = run('query', 'SELECT `id`, `kind`, `name`, `enabled`, `data` FROM `nz_locations` ORDER BY `id`')
  local out = {}
  for _, r in ipairs(rows or {}) do
    local data = decodeTable(r.data)
    if not data then
      lib.print.warn(('[db] location %s has invalid JSON data, using defaults'):format(tostring(r.id)))
      data = {}
    end
    out[#out + 1] = { id = int(r.id, 0), kind = r.kind, name = r.name, enabled = truthy(r.enabled), data = data }
  end
  return out
end

--- Insert a location. Returns the new id or nil.
function DB.locations.insert(kind, name, enabled, data)
  kind, name = str(kind, 16), str(name, 100)
  local encoded = encode(type(data) == 'table' and data or {}, 'location data')
  if not kind or not name or not encoded then return nil end
  local id = run('insert', 'INSERT INTO `nz_locations` (`kind`, `name`, `enabled`, `data`) VALUES (?, ?, ?, ?)',
    { kind, name, enabled == false and 0 or 1, encoded })
  return validId(id)
end

--- Update a location row. Returns true when the row exists after the update.
function DB.locations.update(id, kind, name, enabled, data)
  id, kind, name = validId(id), str(kind, 16), str(name, 100)
  local encoded = encode(type(data) == 'table' and data or {}, 'location data')
  if not id or not kind or not name or not encoded then return false end
  local affected, ok = run('update',
    'UPDATE `nz_locations` SET `kind` = ?, `name` = ?, `enabled` = ?, `data` = ? WHERE `id` = ?',
    { kind, name, enabled == false and 0 or 1, encoded, id })
  return updatedOrExists(affected, ok, 'nz_locations', id)
end

function DB.locations.delete(id)
  id = validId(id)
  if not id then return false end
  local affected = run('update', 'DELETE FROM `nz_locations` WHERE `id` = ?', { id })
  return (tonumber(affected) or 0) > 0
end

DB.interiors = {}

--- Every interior: { { id, name, enabled, data = table } }
function DB.interiors.all()
  local rows = run('query', 'SELECT `id`, `name`, `enabled`, `data` FROM `nz_interiors` ORDER BY `id`')
  local out = {}
  for _, r in ipairs(rows or {}) do
    local data = decodeTable(r.data)
    if not data then
      lib.print.warn(('[db] interior %s has invalid JSON data, using defaults'):format(tostring(r.id)))
      data = {}
    end
    out[#out + 1] = { id = int(r.id, 0), name = r.name, enabled = truthy(r.enabled), data = data }
  end
  return out
end

function DB.interiors.insert(name, enabled, data)
  name = str(name, 100)
  local encoded = encode(type(data) == 'table' and data or {}, 'interior data')
  if not name or not encoded then return nil end
  local id = run('insert', 'INSERT INTO `nz_interiors` (`name`, `enabled`, `data`) VALUES (?, ?, ?)',
    { name, enabled == false and 0 or 1, encoded })
  return validId(id)
end

function DB.interiors.update(id, name, enabled, data)
  id, name = validId(id), str(name, 100)
  local encoded = encode(type(data) == 'table' and data or {}, 'interior data')
  if not id or not name or not encoded then return false end
  local affected, ok = run('update', 'UPDATE `nz_interiors` SET `name` = ?, `enabled` = ?, `data` = ? WHERE `id` = ?',
    { name, enabled == false and 0 or 1, encoded, id })
  return updatedOrExists(affected, ok, 'nz_interiors', id)
end

function DB.interiors.delete(id)
  id = validId(id)
  if not id then return false end
  local affected = run('update', 'DELETE FROM `nz_interiors` WHERE `id` = ?', { id })
  return (tonumber(affected) or 0) > 0
end

---------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------

DB.settings = {}

--- Stored settings table (nz_settings key 'settings') or nil when missing / malformed.
function DB.settings.load()
  local value = run('scalar', 'SELECT `value` FROM `nz_settings` WHERE `key` = ? LIMIT 1', { 'settings' })
  return decodeTable(value)
end

function DB.settings.save(tbl)
  if type(tbl) ~= 'table' then return false end
  local encoded = encode(tbl, 'settings')
  if not encoded then return false end
  local _, ok = run('update',
    'INSERT INTO `nz_settings` (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = ?',
    { 'settings', encoded, encoded })
  return ok
end

---------------------------------------------------------------------------------------
-- Private garage groups
---------------------------------------------------------------------------------------

DB.groups = {}

--- { { id, locationId, label, owner, price, createdAt } }
function DB.groups.all()
  local rows = run('query', [[SELECT `id`, `location_id`, `label`, `owner`, `price`,
    UNIX_TIMESTAMP(`created_at`) AS `created_at` FROM `nz_groups` ORDER BY `id`]])
  local out = {}
  for _, r in ipairs(rows or {}) do
    out[#out + 1] = {
      id = int(r.id, 0), locationId = int(r.location_id, 0), label = r.label, owner = r.owner,
      price = int(r.price, 0), createdAt = int(r.created_at, 0),
    }
  end
  return out
end

--- Create a group. Returns the new id or nil.
function DB.groups.create(locationId, label, owner, price)
  locationId, label, owner = validId(locationId), str(label, 100), str(owner, 64)
  if not locationId or not label or not owner then return nil end
  local id = run('insert', 'INSERT INTO `nz_groups` (`location_id`, `label`, `owner`, `price`) VALUES (?, ?, ?, ?)',
    { locationId, label, owner, math.max(int(price, 0), 0) })
  return validId(id)
end

--- Update label / owner (/ price) of a group.
function DB.groups.update(id, fields)
  id = validId(id)
  if not id or type(fields) ~= 'table' then return false end
  local parts, params = {}, {}
  local label, owner = str(fields.label, 100), str(fields.owner, 64)
  if label then parts[#parts + 1] = '`label` = ?'; params[#params + 1] = label end
  if owner then parts[#parts + 1] = '`owner` = ?'; params[#params + 1] = owner end
  if fields.price ~= nil and int(fields.price, nil) then
    parts[#parts + 1] = '`price` = ?'
    params[#params + 1] = math.max(int(fields.price, 0), 0)
  end
  if #parts == 0 then return true end
  params[#params + 1] = id
  local affected, ok = run('update', ('UPDATE `nz_groups` SET %s WHERE `id` = ?'):format(table.concat(parts, ', ')),
    params)
  return updatedOrExists(affected, ok, 'nz_groups', id)
end

--- Delete a group and its members.
function DB.groups.delete(id)
  id = validId(id)
  if not id then return false end
  return transaction({
    { query = 'DELETE FROM `nz_group_members` WHERE `group_id` = ?', values = { id } },
    { query = 'DELETE FROM `nz_groups` WHERE `id` = ?', values = { id } },
  })
end

--- { { identifier, name, role } } owners first.
function DB.groups.members(groupId)
  groupId = validId(groupId)
  if not groupId then return {} end
  local rows = run('query', [[SELECT `identifier`, `name`, `role` FROM `nz_group_members`
    WHERE `group_id` = ? ORDER BY (`role` = 'owner') DESC, `added_at`]], { groupId })
  local out = {}
  for _, r in ipairs(rows or {}) do
    out[#out + 1] = { identifier = r.identifier, name = r.name or '', role = r.role == 'owner' and 'owner' or 'member' }
  end
  return out
end

--- { { groupId, identifier, name, role } } for every group.
function DB.groups.allMembers()
  local rows = run('query', 'SELECT `group_id`, `identifier`, `name`, `role` FROM `nz_group_members`')
  local out = {}
  for _, r in ipairs(rows or {}) do
    out[#out + 1] = {
      groupId = int(r.group_id, 0), identifier = r.identifier, name = r.name or '',
      role = r.role == 'owner' and 'owner' or 'member',
    }
  end
  return out
end

--- Add or update a member.
function DB.groups.setMember(groupId, identifier, name, role)
  groupId, identifier = validId(groupId), str(identifier, 64)
  if not groupId or not identifier then return false end
  name = str(name, 100) or ''
  role = role == 'owner' and 'owner' or 'member'
  local _, ok = run('update', [[INSERT INTO `nz_group_members` (`group_id`, `identifier`, `name`, `role`)
    VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `name` = ?, `role` = ?]],
    { groupId, identifier, name, role, name, role })
  return ok
end

function DB.groups.removeMember(groupId, identifier)
  groupId, identifier = validId(groupId), str(identifier, 64)
  if not groupId or not identifier then return false end
  local _, ok = run('update', 'DELETE FROM `nz_group_members` WHERE `group_id` = ? AND `identifier` = ?',
    { groupId, identifier })
  return ok
end

---------------------------------------------------------------------------------------
-- Favourites & shares
---------------------------------------------------------------------------------------

DB.favourites = {}

--- { [plate] = true }
function DB.favourites.get(identifier)
  identifier = str(identifier, 64)
  if not identifier then return {} end
  local rows = run('query', 'SELECT `plate` FROM `nz_favourites` WHERE `identifier` = ?', { identifier })
  local out = {}
  for _, r in ipairs(rows or {}) do
    local p = Utils.plate(r.plate)
    if p then out[p] = true end
  end
  return out
end

function DB.favourites.set(identifier, plate, value)
  identifier, plate = str(identifier, 64), Utils.plate(plate)
  if not identifier or not plate or #plate > 16 then return false end
  local sql = value and 'INSERT IGNORE INTO `nz_favourites` (`identifier`, `plate`) VALUES (?, ?)'
    or 'DELETE FROM `nz_favourites` WHERE `identifier` = ? AND `plate` = ?'
  local _, ok = run('update', sql, { identifier, plate })
  return ok
end

DB.shares = {}

--- { { identifier, name, sharedBy } }
function DB.shares.forPlate(plate)
  plate = Utils.plate(plate)
  if not plate then return {} end
  local rows = run('query', [[SELECT `identifier`, `name`, `shared_by` FROM `nz_shares`
    WHERE `plate` = ? ORDER BY `created_at`]], { plate })
  local out = {}
  for _, r in ipairs(rows or {}) do
    out[#out + 1] = { identifier = r.identifier, name = r.name or '', sharedBy = r.shared_by or '' }
  end
  return out
end

--- Number of shares of several plates in one query per 250 plates: { [plate] = n }
--- (plates without shares are absent).
---@param plates string[]
---@return table<string, number>
function DB.shares.counts(plates)
  local list, seen = {}, {}
  for _, v in pairs(type(plates) == 'table' and plates or {}) do
    local p = Utils.plate(v)
    if p and #p <= 16 and not seen[p] then
      seen[p] = true
      list[#list + 1] = p
    end
  end
  local out = {}
  for i = 1, #list, CHUNK do
    local chunk = table.move(list, i, math.min(i + CHUNK - 1, #list), 1, {})
    local rows = run('query', 'SELECT `plate`, COUNT(*) AS `n` FROM `nz_shares` WHERE `plate` IN (?) GROUP BY `plate`',
      { chunk })
    for _, r in ipairs(rows or {}) do
      local p = Utils.plate(r.plate)
      if p and seen[p] then out[p] = math.max(int(r.n, 0), 0) end
    end
  end
  return out
end

--- Plates shared with an identifier: { plate, ... }
function DB.shares.forIdentifier(identifier)
  identifier = str(identifier, 64)
  if not identifier then return {} end
  local rows = run('query', 'SELECT `plate` FROM `nz_shares` WHERE `identifier` = ?', { identifier })
  local out = {}
  for _, r in ipairs(rows or {}) do
    local p = Utils.plate(r.plate)
    if p then out[#out + 1] = p end
  end
  return out
end

function DB.shares.add(plate, identifier, name, sharedBy)
  plate, identifier = Utils.plate(plate), str(identifier, 64)
  if not plate or #plate > 16 or not identifier then return false end
  name, sharedBy = str(name, 100) or '', str(sharedBy, 64) or ''
  local _, ok = run('update', [[INSERT INTO `nz_shares` (`plate`, `identifier`, `name`, `shared_by`)
    VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `name` = ?, `shared_by` = ?]],
    { plate, identifier, name, sharedBy, name, sharedBy })
  return ok
end

function DB.shares.remove(plate, identifier)
  plate, identifier = Utils.plate(plate), str(identifier, 64)
  if not plate or not identifier then return false end
  local _, ok = run('update', 'DELETE FROM `nz_shares` WHERE `plate` = ? AND `identifier` = ?', { plate, identifier })
  return ok
end

function DB.shares.clear(plate)
  plate = Utils.plate(plate)
  if not plate then return false end
  local _, ok = run('update', 'DELETE FROM `nz_shares` WHERE `plate` = ?', { plate })
  return ok
end

---------------------------------------------------------------------------------------
-- Car lock: persistent virtual keys (nz_keys), key versions (nz_key_version) and the owner
-- identity the keys were cut for (nz_key_owner)
---------------------------------------------------------------------------------------

DB.keys = {}

--- Virtual key holders of a plate: { { identifier, grantedBy, createdAt } } (oldest first).
---@param plate string
---@return table[]
function DB.keys.list(plate)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 then return {} end
  local rows = run('query', [[SELECT `identifier`, `granted_by`, UNIX_TIMESTAMP(`created_at`) AS `created`
    FROM `nz_keys` WHERE `plate` = ? ORDER BY `id`]], { plate })
  local out = {}
  for _, r in ipairs(rows or {}) do
    if type(r.identifier) == 'string' and r.identifier ~= '' then
      out[#out + 1] = { identifier = r.identifier, grantedBy = r.granted_by or '', createdAt = int(r.created, nil) }
    end
  end
  return out
end

--- Plates a character holds a virtual key for: { plate, ... }.
---@param identifier string
---@return string[]
function DB.keys.forIdentifier(identifier)
  identifier = str(identifier, 64)
  if not identifier then return {} end
  local rows = run('query', 'SELECT `plate` FROM `nz_keys` WHERE `identifier` = ?', { identifier })
  local out = {}
  for _, r in ipairs(rows or {}) do
    local p = Utils.plate(r.plate)
    if p then out[#out + 1] = p end
  end
  return out
end

--- Give a character a virtual key (idempotent).
---@param plate string
---@param identifier string
---@param grantedBy string|nil
---@return boolean
function DB.keys.add(plate, identifier, grantedBy)
  plate, identifier = Utils.plate(plate), str(identifier, 64)
  if not plate or #plate > 16 or not identifier then return false end
  grantedBy = str(grantedBy, 64) or ''
  local _, ok = run('update', [[INSERT INTO `nz_keys` (`plate`, `identifier`, `granted_by`) VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE `granted_by` = ?]], { plate, identifier, grantedBy, grantedBy })
  return ok
end

--- Remove one character's virtual key.
---@param plate string
---@param identifier string
---@return boolean
function DB.keys.remove(plate, identifier)
  plate, identifier = Utils.plate(plate), str(identifier, 64)
  if not plate or not identifier then return false end
  local _, ok = run('update', 'DELETE FROM `nz_keys` WHERE `plate` = ? AND `identifier` = ?', { plate, identifier })
  return ok
end

--- Remove every virtual key of a plate (change of locks, new owner).
---@param plate string
---@return boolean
function DB.keys.clear(plate)
  plate = Utils.plate(plate)
  if not plate then return false end
  local _, ok = run('update', 'DELETE FROM `nz_keys` WHERE `plate` = ?', { plate })
  return ok
end

--- Number of virtual keys of a plate.
---@param plate string
---@return integer
function DB.keys.count(plate)
  plate = Utils.plate(plate)
  if not plate then return 0 end
  local n = run('scalar', 'SELECT COUNT(*) FROM `nz_keys` WHERE `plate` = ?', { plate })
  return math.max(int(n, 0), 0)
end

--- Raw key columns of a vehicle row (exact stored plate first, then the normalized plate).
--- Returns the row, false when the plate is not in the vehicle table, or nil, 'error'.
local function keyRow(p)
  local cols = { 'v.`plate` AS `plate`', ('v.`%s` AS `owner`'):format(OWNER_COL) }
  for _, name in ipairs({ 'nz_key_version', 'nz_key_owner', 'nz_job', 'nz_gang' }) do
    if has(name) then cols[#cols + 1] = ('v.`%s` AS `%s`'):format(name, name) end
  end
  local base = ('SELECT %s FROM `%s` v WHERE '):format(table.concat(cols, ', '), VT)
  local row, ok = run('single', base .. '(v.`plate` = ? OR v.`plate` = ?) LIMIT 1', { p, padded(p) })
  if not ok then return nil, 'error' end
  if not row then
    row, ok = run('single', base .. normPlate('v') .. ' = ? LIMIT 1', { p })
    if not ok then return nil, 'error' end
  end
  if type(row) ~= 'table' or type(row.plate) ~= 'string' then return false end
  return row
end

--- Key state of an owned vehicle: { version, mark, owner, job, gang, markSupported }
--- (mark = owner identity the keys were cut for, nz_key_owner; nil = never keyed). false when
--- the plate is not in the vehicle table (NPC / spawned vehicles keep their version in
--- memory); nil, 'error' when the database cannot be read.
---@param plate string
---@return table|false|nil, string|nil
function DB.keys.state(plate)
  local p = Utils.plate(plate)
  if not p or not ready() then return nil, 'error' end
  local raw, err = keyRow(p)
  if raw == nil then return nil, err end
  if raw == false then return false end
  return {
    version = has('nz_key_version') and math.max(int(raw.nz_key_version, 0), 0) or 0,
    mark = nonEmpty(raw.nz_key_owner),
    owner = nonEmpty(raw.owner),
    job = nonEmpty(raw.nz_job),
    gang = nonEmpty(raw.nz_gang),
    markSupported = has('nz_key_version') and has('nz_key_owner'),
  }
end

--- Key version of an owned vehicle. nil when the plate is not in the vehicle table (NPC /
--- spawned vehicles keep their version in memory); nil, 'error' on a database error.
---@param plate string
---@return integer|nil, string|nil
function DB.keys.version(plate)
  local st, err = DB.keys.state(plate)
  if st == nil then return nil, err or 'error' end
  if st == false then return nil end
  return st.version
end

--- Record the owner identity `mark` the keys are cut for, with a new key version when it
--- differs from the stored one: `initial` when the row was never keyed (nz_key_owner NULL),
--- else version + 1. Only changes a row whose mark differs (concurrent calls change it once).
--- Returns true when the row changed, false when it already had this mark, nil on an error.
---@param plate string
---@param mark string
---@param initial integer
---@return boolean|nil
function DB.keys.claim(plate, mark, initial)
  local p = Utils.plate(plate)
  mark = str(mark, 64)
  initial = math.max(int(initial, 1), 1)
  if not p or not mark or not ready() or not has('nz_key_version') or not has('nz_key_owner') then return nil end
  local raw = keyRow(p)
  if raw == nil then return nil end
  if raw == false then return false end
  -- single-table UPDATE assignments run left to right: the IF() still sees the old mark
  local affected, ok = run('update', ([[UPDATE `%s` SET
      `nz_key_version` = IF(`nz_key_owner` IS NULL, ?, `nz_key_version` + 1),
      `nz_key_owner` = ?
    WHERE `plate` = ? AND (`nz_key_owner` IS NULL OR `nz_key_owner` <> ?)]]):format(VT),
    { initial, mark, raw.plate, mark })
  if not ok then return nil end
  return (tonumber(affected) or 0) > 0
end

--- New key version of an owned vehicle (version + 1, or `initial` when it was never keyed),
--- recording the owner identity `mark` when given. Returns the new version, or nil when the
--- plate is not in the vehicle table, the column is missing or the database failed.
---@param plate string
---@param mark string|nil
---@param initial integer|nil
---@return integer|nil
function DB.keys.bumpVersion(plate, mark, initial)
  local p = Utils.plate(plate)
  if not p or not ready() or not has('nz_key_version') then return nil end
  local raw = keyRow(p)
  if not raw then return nil end
  mark = has('nz_key_owner') and str(mark, 64) or nil
  local sql, params
  if mark then
    sql = ([[UPDATE `%s` SET `nz_key_version` = IF(`nz_key_owner` IS NULL, ?, `nz_key_version` + 1),
      `nz_key_owner` = ? WHERE `plate` = ?]]):format(VT)
    params = { math.max(int(initial, 1), 1), mark, raw.plate }
  else
    sql = ('UPDATE `%s` SET `nz_key_version` = `nz_key_version` + 1 WHERE `plate` = ?'):format(VT)
    params = { raw.plate }
  end
  local _, ok = run('update', sql, params)
  if not ok then return nil end
  local after = keyRow(p)
  if type(after) ~= 'table' then return nil end
  return math.max(int(after.nz_key_version, 0), 0)
end

local KEY_SECRET = 'carlock_secret'
local KEY_SECRET_MIN = 32

--- Signing secret of key items (nz_settings 'carlock_secret'). Returns the stored value; when
--- none is stored yet (first start) `candidate` is stored and returned. nil when the database
--- cannot be read or written (the caller falls back to another store).
---@param candidate string|nil new secret (at least 32 characters)
---@return string|nil
function DB.keys.secret(candidate)
  local value, ok = run('scalar', 'SELECT `value` FROM `nz_settings` WHERE `key` = ? LIMIT 1', { KEY_SECRET })
  if not ok then return nil end
  if type(value) == 'string' and #value >= KEY_SECRET_MIN then return value end
  if type(candidate) ~= 'string' or #candidate < KEY_SECRET_MIN then return nil end
  -- keeps a valid stored value when two servers race on the first start
  local _, written = run('update', [[INSERT INTO `nz_settings` (`key`, `value`) VALUES (?, ?)
    ON DUPLICATE KEY UPDATE `value` = IF(CHAR_LENGTH(`value`) >= ?, `value`, ?)]],
    { KEY_SECRET, candidate, KEY_SECRET_MIN, candidate })
  if not written then return nil end
  value = run('scalar', 'SELECT `value` FROM `nz_settings` WHERE `key` = ? LIMIT 1', { KEY_SECRET })
  if type(value) == 'string' and #value >= KEY_SECRET_MIN then return value end
  return candidate
end

---------------------------------------------------------------------------------------
-- Car lock v2 tables (docs/CARLOCK.md §3, §15-§18): key custody (nz_key_items), immobilisers
-- (nz_key_security), per-player key settings (nz_key_players), keys on the ground
-- (nz_ground_keys) and the admin key settings (nz_settings 'carlock_settings').
---------------------------------------------------------------------------------------

DB.keyTables = true

local CUSTODY = { player = true, stash = true, ground = true, unknown = true, lost = true }

local function keyItemRow(r)
  if type(r) ~= 'table' or type(r.key_id) ~= 'string' then return nil end
  return {
    id = r.key_id,
    plate = Utils.plate(r.plate),
    version = int(r.version, 0),
    kind = r.kind == 'fob' and 'fob' or 'key',
    origin = nonEmpty(r.origin),
    custody = CUSTODY[r.custody] and r.custody or 'unknown',
    holder = nonEmpty(r.holder),
    slot = int(r.slot, nil),
    createdBy = nonEmpty(r.created_by),
    createdAt = int(r.created, nil),
    updatedAt = int(r.updated, nil),
  }
end

local KEY_ITEM_SELECT = [[SELECT `key_id`, `plate`, `version`, `kind`, `origin`, `custody`, `holder`, `slot`,
  `created_by`, UNIX_TIMESTAMP(`created_at`) AS `created`, UNIX_TIMESTAMP(`updated_at`) AS `updated` FROM `nz_key_items` ]]

DB.keyItems = {}

--- Record (or update) a key item: { id, plate, version, kind, origin?, custody, holder?, slot?, createdBy? }.
---@param e table
---@return boolean
function DB.keyItems.upsert(e)
  if type(e) ~= 'table' then return false end
  local id, plate = str(e.id, 32), Utils.plate(e.plate)
  if not id or not plate or #plate > 16 then return false end
  local custody = CUSTODY[e.custody] and e.custody or 'unknown'
  local _, ok = run('update', [[INSERT INTO `nz_key_items`
      (`key_id`, `plate`, `version`, `kind`, `origin`, `custody`, `holder`, `slot`, `created_by`)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE `custody` = VALUES(`custody`), `holder` = VALUES(`holder`), `slot` = VALUES(`slot`)]],
    { id, plate, int(e.version, 0), e.kind == 'fob' and 'fob' or 'key', str(e.origin, 16), custody,
      str(e.holder, 64), int(e.slot, nil), str(e.createdBy, 64) })
  return ok
end

--- Move a recorded key item (custody / holder / slot). Returns true when a row changed.
---@param id string
---@param custody string
---@param holder string|nil
---@param slot number|nil
---@return boolean
function DB.keyItems.move(id, custody, holder, slot)
  id = str(id, 32)
  if not id or not CUSTODY[custody] then return false end
  local affected = run('update', 'UPDATE `nz_key_items` SET `custody` = ?, `holder` = ?, `slot` = ? WHERE `key_id` = ?',
    { custody, str(holder, 64), int(slot, nil), id })
  return (tonumber(affected) or 0) > 0
end

--- One recorded key item, or nil.
---@param id string
---@return table|nil
function DB.keyItems.get(id)
  id = str(id, 32)
  if not id then return nil end
  return keyItemRow(run('single', KEY_ITEM_SELECT .. 'WHERE `key_id` = ? LIMIT 1', { id }))
end

--- Recorded key items of a plate (every version), oldest first.
---@param plate string
---@return table[]
function DB.keyItems.forPlate(plate)
  plate = Utils.plate(plate)
  if not plate then return {} end
  local out = {}
  for _, r in ipairs(run('query', KEY_ITEM_SELECT .. 'WHERE `plate` = ? ORDER BY `created_at` LIMIT 500', { plate }) or {}) do
    out[#out + 1] = keyItemRow(r)
  end
  return out
end

--- Recorded key items a holder (character identifier, stash id, ground id) has.
---@param holder string
---@return table[]
function DB.keyItems.forHolder(holder)
  holder = str(holder, 64)
  if not holder then return {} end
  local out = {}
  for _, r in ipairs(run('query', KEY_ITEM_SELECT .. 'WHERE `holder` = ? ORDER BY `plate` LIMIT 500', { holder }) or {}) do
    out[#out + 1] = keyItemRow(r)
  end
  return out
end

--- Key items of a plate with this version whose custody is not 'lost' (copies of the current
--- locks that exist somewhere). nil on a database error.
---@param plate string
---@param version integer
---@return integer|nil
function DB.keyItems.countLive(plate, version)
  plate = Utils.plate(plate)
  if not plate then return 0 end
  local n, ok = run('scalar', [[SELECT COUNT(*) FROM `nz_key_items`
    WHERE `plate` = ? AND `version` = ? AND `custody` <> 'lost']], { plate, int(version, 0) })
  if not ok then return nil end
  return math.max(int(n, 0), 0)
end

--- Forget a recorded key item.
---@param id string
---@return boolean
function DB.keyItems.remove(id)
  id = str(id, 32)
  if not id then return false end
  local _, ok = run('update', 'DELETE FROM `nz_key_items` WHERE `key_id` = ?', { id })
  return ok
end

--- Totals for the admin key manager: { items, lost }.
---@return table
function DB.keyItems.totals()
  local row = run('single', [[SELECT COUNT(*) AS `items`, SUM(`custody` = 'lost') AS `lost` FROM `nz_key_items`]])
  return { items = int(row and row.items, 0), lost = int(row and row.lost, 0) }
end

DB.keySecurity = {}

--- Immobiliser of a plate: { immobiliser = 'none'|'standard'|'ghost', pinHash? }; nil on a
--- database error.
---@param plate string
---@return table|nil
function DB.keySecurity.get(plate)
  plate = Utils.plate(plate)
  if not plate then return { immobiliser = 'none' } end
  local row, ok = run('single', 'SELECT `immobiliser`, `pin_hash` FROM `nz_key_security` WHERE `plate` = ? LIMIT 1', { plate })
  if not ok then return nil end
  if type(row) ~= 'table' then return { immobiliser = 'none' } end
  local level = row.immobiliser
  if level ~= 'standard' and level ~= 'ghost' then level = 'none' end
  return { immobiliser = level, pinHash = nonEmpty(row.pin_hash) }
end

--- Store the immobiliser of a plate (pinHash false = clear the PIN, nil = keep it).
---@param plate string
---@param level 'none'|'standard'|'ghost'
---@param pinHash string|false|nil
---@return boolean
function DB.keySecurity.set(plate, level, pinHash)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 then return false end
  if level ~= 'standard' and level ~= 'ghost' then level = 'none' end
  local pin = pinHash == false and nil or str(pinHash, 64)
  local sql, params
  if pinHash == nil then
    sql = [[INSERT INTO `nz_key_security` (`plate`, `immobiliser`) VALUES (?, ?)
      ON DUPLICATE KEY UPDATE `immobiliser` = VALUES(`immobiliser`)]]
    params = { plate, level }
  else
    sql = [[INSERT INTO `nz_key_security` (`plate`, `immobiliser`, `pin_hash`) VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE `immobiliser` = VALUES(`immobiliser`), `pin_hash` = VALUES(`pin_hash`)]]
    params = { plate, level, pin }
  end
  local _, ok = run('update', sql, params)
  return ok
end

DB.keyPlayers = {}

--- Stored key settings of a character (table) or nil.
---@param identifier string
---@return table|nil
function DB.keyPlayers.get(identifier)
  identifier = str(identifier, 64)
  if not identifier then return nil end
  return decodeTable(run('scalar', 'SELECT `data` FROM `nz_key_players` WHERE `identifier` = ? LIMIT 1', { identifier }))
end

--- Store the key settings of a character.
---@param identifier string
---@param data table
---@return boolean
function DB.keyPlayers.set(identifier, data)
  identifier = str(identifier, 64)
  local encoded = type(data) == 'table' and encode(data, 'key settings') or nil
  if not identifier or not encoded then return false end
  local _, ok = run('update', [[INSERT INTO `nz_key_players` (`identifier`, `data`) VALUES (?, ?)
    ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)]], { identifier, encoded })
  return ok
end

DB.groundKeys = {}

--- Every stored ground key: { { id, plate, data, x, y, z, heading, bucket, expiresAt } }.
---@return table[]
function DB.groundKeys.all()
  local out = {}
  for _, r in ipairs(run('query', [[SELECT `id`, `plate`, `data`, `x`, `y`, `z`, `heading`, `bucket`, `expires_at`
    FROM `nz_ground_keys` LIMIT 2000]]) or {}) do
    local data = decodeTable(r.data)
    if type(r.id) == 'string' and data then
      out[#out + 1] = { id = r.id, plate = Utils.plate(r.plate), data = data, x = num(r.x) or 0.0, y = num(r.y) or 0.0,
        z = num(r.z) or 0.0, heading = num(r.heading) or 0.0, bucket = int(r.bucket, 0), expiresAt = int(r.expires_at, nil) }
    end
  end
  return out
end

--- Store a ground key (record of NZ.CarLock ground keys); again with the same id moves it.
---@param g table { id, plate, data, x, y, z, heading, bucket, expiresAt? }
---@return boolean
function DB.groundKeys.add(g)
  if type(g) ~= 'table' then return false end
  local id, plate = str(g.id, 32), Utils.plate(g.plate)
  local data = encode(g.data, 'ground key')
  if not id or not plate or not data then return false end
  local _, ok = run('update', [[INSERT INTO `nz_ground_keys` (`id`, `plate`, `data`, `x`, `y`, `z`, `heading`, `bucket`, `expires_at`)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `x` = VALUES(`x`),
    `y` = VALUES(`y`), `z` = VALUES(`z`)]],
    { id, plate, data, num(g.x) or 0.0, num(g.y) or 0.0, num(g.z) or 0.0, num(g.heading) or 0.0, int(g.bucket, 0), int(g.expiresAt, nil) })
  return ok
end

--- Remove a stored ground key.
---@param id string
---@return boolean
function DB.groundKeys.remove(id)
  id = str(id, 32)
  if not id then return false end
  local _, ok = run('update', 'DELETE FROM `nz_ground_keys` WHERE `id` = ?', { id })
  return ok
end

--- Remove every stored ground key (persistence switched off).
---@return boolean
function DB.groundKeys.clear()
  local _, ok = run('update', 'DELETE FROM `nz_ground_keys`')
  return ok
end

DB.keySettings = {}

local KEY_SETTINGS = 'carlock_settings'

--- The admin key settings ({ [id] = value }), {} when none are stored, nil on a database error.
---@return table|nil
function DB.keySettings.load()
  local value, ok = run('scalar', 'SELECT `value` FROM `nz_settings` WHERE `key` = ? LIMIT 1', { KEY_SETTINGS })
  if not ok then return nil end
  return decodeTable(value) or {}
end

--- Store the admin key settings.
---@param values table
---@return boolean
function DB.keySettings.save(values)
  local encoded = type(values) == 'table' and encode(values, 'key settings') or nil
  if not encoded then return false end
  local _, ok = run('update', [[INSERT INTO `nz_settings` (`key`, `value`) VALUES (?, ?)
    ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)]], { KEY_SETTINGS, encoded })
  return ok
end

---------------------------------------------------------------------------------------
-- Vehicle history (ownership / service records)
---------------------------------------------------------------------------------------

DB.events = {}

local EVENT_KINDS = { owner = true, service = true }

--- Copy of an entry without its row id; `at` (unix) becomes created_at when present.
local function eventPayload(data)
  local copy = type(data) == 'table' and Utils.deepCopy(data) or { value = data }
  copy.id = nil
  local at = int(copy.at, nil)
  if at and at <= 0 then at = nil end
  return copy, at
end

local function eventInsert(plate, kind, data)
  local payload, at = eventPayload(data)
  local encoded = encode(payload, 'vehicle event')
  if not encoded then return nil end
  if at then
    return 'INSERT INTO `nz_vehicle_events` (`plate`, `kind`, `data`, `created_at`) VALUES (?, ?, ?, FROM_UNIXTIME(?))',
      { plate, kind, encoded, at }
  end
  return 'INSERT INTO `nz_vehicle_events` (`plate`, `kind`, `data`) VALUES (?, ?, ?)', { plate, kind, encoded }
end

--- Add a history entry. Returns the new row id or nil.
---@param plate string
---@param kind 'owner'|'service'
---@param data table
function DB.events.add(plate, kind, data)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 or not EVENT_KINDS[kind] then return nil end
  local sql, params = eventInsert(plate, kind, data)
  if not sql then return nil end
  return validId((run('insert', sql, params)))
end

--- History entries, newest first: { { id, kind, data, at } }
---@param plate string
---@param kind 'owner'|'service'|nil nil = every kind
---@param limit number|nil default 50, max 500
function DB.events.list(plate, kind, limit)
  plate = Utils.plate(plate)
  if not plate then return {} end
  limit = math.floor(Utils.clamp(int(limit, 50), 1, 500))
  local sql, params
  if kind ~= nil then
    if not EVENT_KINDS[kind] then return {} end
    sql = [[SELECT `id`, `kind`, `data`, UNIX_TIMESTAMP(`created_at`) AS `at` FROM `nz_vehicle_events`
      WHERE `plate` = ? AND `kind` = ? ORDER BY `created_at` DESC, `id` DESC LIMIT ?]]
    params = { plate, kind, limit }
  else
    sql = [[SELECT `id`, `kind`, `data`, UNIX_TIMESTAMP(`created_at`) AS `at` FROM `nz_vehicle_events`
      WHERE `plate` = ? ORDER BY `created_at` DESC, `id` DESC LIMIT ?]]
    params = { plate, limit }
  end
  local rows = run('query', sql, params)
  local out = {}
  for _, r in ipairs(rows or {}) do
    out[#out + 1] = { id = int(r.id, 0), kind = r.kind, data = decodeTable(r.data) or {}, at = int(r.at, 0) }
  end
  return out
end

--- Replace every entry of one kind (admin editor). `list` is newest first (like list()).
---@return boolean
function DB.events.replace(plate, kind, list)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 or not EVENT_KINDS[kind] or type(list) ~= 'table' then return false end
  local queries = {
    { query = 'DELETE FROM `nz_vehicle_events` WHERE `plate` = ? AND `kind` = ?', values = { plate, kind } },
  }
  local count = math.min(#list, 500)
  for i = count, 1, -1 do
    local sql, params = eventInsert(plate, kind, list[i])
    if sql then queries[#queries + 1] = { query = sql, values = params } end
  end
  return transaction(queries)
end

---------------------------------------------------------------------------------------
-- Logs
---------------------------------------------------------------------------------------

DB.logs = {}

-- oxmysql reports query errors itself; the callback only keeps the call asynchronous.
local function logInserted() end

--- Insert into nz_logs without waiting (fire and forget). Honors ServerConfig.DatabaseLogs.
---@param event string
---@param identifier string|nil
---@param plate string|nil
---@param data table|nil
function DB.logs.add(event, identifier, plate, data)
  if ServerConfig and ServerConfig.DatabaseLogs == false then return end
  event = str(event, 48)
  if not event then return end
  local cols, marks, params = { '`event`' }, { '?' }, { event }
  local function add(column, value)
    if value == nil then return end
    cols[#cols + 1] = ('`%s`'):format(column)
    marks[#marks + 1] = '?'
    params[#params + 1] = value
  end
  add('identifier', str(identifier, 64))
  local p = Utils.plate(plate)
  if p then add('plate', p:sub(1, 16)) end
  if data ~= nil then add('data', encode(data, 'log data')) end
  local sql = ('INSERT INTO `nz_logs` (%s) VALUES (%s)'):format(table.concat(cols, ', '), table.concat(marks, ', '))
  local ok, err = pcall(MySQL.insert, sql, params, logInserted)
  if not ok then lib.print.error(('[db] log insert failed: %s'):format(tostring(err))) end
end

--- nz_logs rows of one plate, newest first (admin vehicle activity).
---@param plate string
---@param limit number
---@param offset number
---@return { rows: { id: number, event: string, identifier: string|nil, data: table|nil, at: number }[], total: number }
function DB.logs.forPlate(plate, limit, offset)
  local p = Utils.plate(plate)
  local out = { rows = {}, total = 0 }
  if not p or not ready() then return out end
  p = p:sub(1, 16)
  limit = math.max(1, math.min(int(limit, 25), 100))
  offset = math.max(0, int(offset, 0))
  out.total = tonumber((run('scalar', 'SELECT COUNT(*) FROM `nz_logs` WHERE `plate` = ?', { p }))) or 0
  if out.total == 0 then return out end
  local rows = run('query', 'SELECT `id`, `event`, `identifier`, `data`, UNIX_TIMESTAMP(`created_at`) AS `at` '
    .. 'FROM `nz_logs` WHERE `plate` = ? ORDER BY `id` DESC LIMIT ? OFFSET ?', { p, limit, offset })
  for _, row in ipairs(rows or {}) do
    out.rows[#out.rows + 1] = {
      id = tonumber(row.id) or 0,
      event = tostring(row.event or ''),
      identifier = type(row.identifier) == 'string' and row.identifier or nil,
      data = decodeTable(row.data),
      at = math.floor(tonumber(row.at) or 0),
    }
  end
  return out
end

local PRUNE_BATCH = 5000

--- Delete nz_logs rows older than `days` days, in batches of 5000 rows with a pause between
--- them (indexed on created_at). Awaits: call from a thread.
---@param days number
---@return number deleted
function DB.logs.prune(days)
  days = int(days, 0)
  if days <= 0 then return 0 end
  local total = 0
  for _ = 1, 2000 do -- at most 10M rows per run, the rest on the next one
    local affected, ok = run('update',
      'DELETE FROM `nz_logs` WHERE `created_at` < (NOW() - INTERVAL ? DAY) LIMIT ' .. PRUNE_BATCH, { days })
    if not ok then break end
    affected = tonumber(affected) or 0
    total = total + affected
    if affected < PRUNE_BATCH then break end
    Wait(1000)
  end
  return total
end
