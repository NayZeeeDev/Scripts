--[[
  nayzeee-garages — housing loader: loaf_housing (Loaf Scripts) (server). House ids 'loaf:<property id>'
  (one garage per property, shared by every owner of it: house garages only list each
  player's own and shared vehicles).

  Owners from `loaf_properties` (owner, propertyid, id = instance id), key holders from
  loaf_keysystem's `loaf_keys` (key_id 'housing_key_<propertyid>_<instance id>'). Garage from
  exports GetHouse(propertyid).garage { entrance (walk-up point), exit (vector4: spawn and
  store) }, else from loaf_realtor's `loaf_houses` (garage_entrance / garage_exit) when that
  table exists. Set Garage = false in loaf_housing's config so loaf draws no garage marker of its
  own (it only dispatches to loaf_garage / cd_garage / jg): we draw ours. Clients ask for a
  refresh on loaf_housing / loaf_keysystem events (bridge/client/housing.lua).
  Confidence: medium (escrowed; keysystem and converter are open source).
]]

local Housing = NZ.Housing

local KEYS = "SELECT `identifier`, `key_id` FROM `loaf_keys` WHERE `key_id` LIKE 'housing\\_key\\_%'"

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

Housing.addLoader({
  prefix = 'loaf',
  resources = { 'loaf_housing' },
  hook = 'whenUsed',

  load = function(ctx)
    local owners = ctx.query('SELECT `owner`, `propertyid`, `id` FROM `loaf_properties`')
    if not owners then return nil end

    local access, instances = {}, {}
    for _, row in ipairs(owners) do
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
    for _, row in ipairs((ctx.tableExists('loaf_keys') and ctx.query(KEYS)) or {}) do
      local pid, uid = tostring(row.key_id or ''):match('^housing_key_(%d+)_(.+)$')
      pid = ctx.int(pid)
      local who = ctx.identifier(row.identifier)
      if pid and who and access[pid] and instances[pid .. ':' .. uid] then access[pid][who] = true end
    end

    local realtor = nil
    local out = {}
    for pid, set in pairs(access) do
      local label, entrance, exit
      local house = ctx.export('GetHouse', pid)
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
