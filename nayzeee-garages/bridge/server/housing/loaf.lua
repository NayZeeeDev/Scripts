--[[
  nayzeee-garages — housing loader: loaf_housing (Loaf Scripts) (server). House ids 'loaf:<property id>'
  (one garage per property, shared by every owner of it: house garages only list each
  player's own and shared vehicles).

  Owners from `loaf_properties` (owner, propertyid, id = instance id), key holders from
  loaf_keysystem's `loaf_keys` (key_id 'housing_key_<propertyid>_<instance id>'). Garage from
  exports GetHouses()[propertyid].garage (one call per reload; GetHouse(propertyid) per owned
  property only when GetHouses fails) { entrance (walk-up point), exit (vector4: spawn and
  store) }, else from loaf_realtor's `loaf_houses` (garage_entrance / garage_exit) when that
  table exists. Set Garage = false in loaf_housing's config so loaf draws no garage marker of its
  own (it only dispatches to loaf_garage / cd_garage / jg): we draw ours. Clients ask for a
  refresh on loaf_housing / loaf_keysystem events (bridge/client/housing.lua). Key holders get
  the garage like loaf's AllowGarageKey = true (default); 'set nayzeee_housing_loaf_keys 0' in
  server.cfg mirrors AllowGarageKey = false. Hook (optional): loaf's own garage interaction can call
  OpenHouseGarage / StoreHouseGarage (install/housing/loaf_housing); then set the
  'nayzeee_housing_hooked' convar so we do not draw a second point.
  Confidence: medium (escrowed; keysystem and converter are open source).
]]

local Housing = NZ.Housing

local KEYS = "SELECT `identifier`, `key_id` FROM `loaf_keys` WHERE `key_id` LIKE 'housing\\_key\\_%'"
local KEYS_CONVAR = 'nayzeee_housing_loaf_keys'

--- loaf_housing's AllowGarageKey (default true) cannot be read from another resource: servers that
--- turned it off mirror it with  set nayzeee_housing_loaf_keys 0  (owners only).
local function keyHoldersAllowed()
  local ok, value = pcall(GetConvar, KEYS_CONVAR, '1')
  if not ok or type(value) ~= 'string' then return true end
  value = value:lower()
  return value ~= '0' and value ~= 'false' and value ~= 'no'
end

--- loaf_realtor's table: [propertyid] = row (only when the table exists).
local function realtorRows(ctx)
  if not ctx.tableExists('loaf_houses') then return {} end
  local out = {}
  for _, row in ipairs(ctx.query('SELECT `id`, `label`, `garage_entrance`, `garage_exit` FROM `loaf_houses`') or {}) do
    local id = ctx.int(row.id)
    if id then out[id] = row end
  end
  return out
end

--- Every house definition by property id (GetHouses returns loaf's Houses array: index = id).
--- nil when the export is missing or fails.
local function houseDefs(ctx)
  local all = ctx.tryExport('GetHouses')
  if type(all) ~= 'table' then return nil end
  local defs, n = {}, 0
  for key, house in pairs(all) do
    n = n + 1
    ctx.yield(n)
    local pid = ctx.int(key)
    if type(house) == 'table' then
      if not pid and house.id ~= nil then pid = ctx.int(house.id) end
      if pid then defs[pid] = house end
    end
  end
  return defs
end

Housing.addLoader({
  prefix = 'loaf',
  resources = { 'loaf_housing' },
  hook = 'whenUsed',

  load = function(ctx)
    local owners = ctx.query('SELECT `owner`, `propertyid`, `id` FROM `loaf_properties`')
    if not owners then return nil end

    local access, instances = {}, {}
    for i, row in ipairs(owners) do
      ctx.yield(i)
      local pid = ctx.int(row.propertyid)
      local owner = ctx.identifier(row.owner)
      if pid then
        local set = access[pid]
        if not set then
          set = {}
          access[pid] = set
        end
        if owner then set[owner] = true end
        if row.id ~= nil then instances[pid .. ':' .. tostring(row.id)] = true end
      end
    end

    -- Key holders of an existing instance (the keysystem table may not exist).
    local keyRows = keyHoldersAllowed() and ctx.tableExists('loaf_keys') and ctx.query(KEYS) or nil
    for i, row in ipairs(keyRows or {}) do
      ctx.yield(i)
      local pid, uid = tostring(row.key_id or ''):match('^housing_key_(%d+)_(.+)$')
      pid = ctx.int(pid)
      local who = ctx.identifier(row.identifier)
      if pid and who and access[pid] and instances[pid .. ':' .. uid] then access[pid][who] = true end
    end

    local defs = next(access) ~= nil and houseDefs(ctx) or nil
    local realtor = nil
    local out, n = {}, 0
    for pid, set in pairs(access) do -- `access` is local to this read: safe across a yield
      n = n + 1
      ctx.yield(n)
      local label, entrance, exit
      local house
      if defs then house = defs[pid] else house = ctx.export('GetHouse', pid) end
      if type(house) == 'table' then
        label = house.label
        local garage = ctx.decode(house.garage)
        if garage then
          entrance, exit = ctx.v4(garage.entrance), ctx.v4(garage.exit)
        end
      end
      if not entrance and not exit then
        realtor = realtor or realtorRows(ctx)
        local row = realtor[pid]
        if row then
          label = label or row.label
          entrance, exit = ctx.point(row.garage_entrance), ctx.point(row.garage_exit)
        end
      end
      if entrance or exit then
        local coords = entrance or exit
        if entrance and exit then coords = { x = entrance.x, y = entrance.y, z = entrance.z, w = exit.w } end
        out[pid] = {
          id = pid,
          name = ctx.text(label) or ('%s %d'):format(L('Property'), pid),
          coords = coords,
          spawn = exit,
          store = exit,
          access = set,
        }
      end
    end
    return out
  end,
})
