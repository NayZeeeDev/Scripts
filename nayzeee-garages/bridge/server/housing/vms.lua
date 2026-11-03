--[[
  nayzeee-garages — housing loader: vms_housing (VMS Store) (server). House ids 'vms:<property id>'.

  Hook-driven: vms_housing draws the garage point itself and calls the garage script's
  integration file (install/housing/vms_housing -> OpenHouseGarage / StoreHouseGarage). The
  garage is registered (hidden) where the player uses it, so this loader mainly provides access:
  exports GetAllProperties() (array or id-keyed map; falls back to SELECT * FROM `houses`),
  owner + renter + the identifier-keyed `keys` map (UseKeysOnItem = false; item keys cannot be
  read offline). Buildings are skipped. A garage point in `metadata` is probed under a few names
  (unconfirmed) and only used until the hook places the garage. Live access: owner / renter of
  GetProperty(id), then HasKeys(src, identifier, id), then HasAnyPermission(id, identifier).
  Refresh hints: vms_housing:sv:giveKey / buyKey / removeKey (net events), resource start.
  Confidence: medium (escrowed; exports seen in vendor-provided and third-party files).
]]

local Housing = NZ.Housing

local GARAGE_KEYS = { 'garage', 'garageCoords', 'garage_coords', 'parking' } -- unconfirmed names
local loggedMeta = false

local function asId(ctx, rawId)
  return ctx.int(rawId) or rawId
end

local function same(a, b)
  return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

Housing.addLoader({
  prefix = 'vms',
  resources = { 'vms_housing' },
  hook = 'always',
  trustCoords = false,

  load = function(ctx)
    local all = ctx.export('GetAllProperties')
    if type(all) ~= 'table' then
      -- `keys` is a reserved word: never name the columns, read every one.
      all = ctx.query('SELECT * FROM `houses`')
      if not all then return nil end
    end

    local out = {}
    for key, p in pairs(all) do
      p = ctx.decode(p)
      if type(p) == 'table' and p.type ~= 'building' then
        local raw = p.id
        if raw == nil then raw = key end
        local set = {}
        for _, who in ipairs({ p.owner, p.renter }) do
          local id = ctx.identifier(who)
          if id then set[id] = true end
        end
        local keys = ctx.decode(p.keys)
        if keys and not ctx.isArray(keys) then ctx.addKeys(set, keys) end

        local meta = ctx.decode(p.metadata) or {}
        if not loggedMeta and Config.Debug and next(meta) ~= nil then
          loggedMeta = true
          local names = {}
          for name in pairs(meta) do names[#names + 1] = tostring(name) end
          table.sort(names)
          ctx.debug(('housing: vms_housing metadata keys: %s'):format(table.concat(names, ', ')))
        end
        local coords
        for _, name in ipairs(GARAGE_KEYS) do
          coords = coords or (meta[name] ~= nil and ctx.point(meta[name]) or nil)
        end

        out[tostring(raw)] = {
          id = raw,
          name = ctx.text(p.name) or ctx.text(p.address),
          coords = coords,
          access = set,
        }
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId, src)
    local id = asId(ctx, rawId)
    local p = ctx.export('GetProperty', id)
    if type(p) ~= 'table' then return nil end
    if same(p.owner, identifier) or same(p.renter, identifier) then return true end
    src = src or ctx.sourceOf(identifier)
    if src and ctx.export('HasKeys', src, identifier, id) == true then return true end
    if ctx.export('HasAnyPermission', id, identifier) == true then return true end
    return false
  end,

  --- Entrance / menu of the property and of its parent building.
  anchors = function(ctx, rawId)
    local p = ctx.export('GetProperty', asId(ctx, rawId))
    if type(p) ~= 'table' then return nil end
    local list = {}
    local meta = ctx.decode(p.metadata) or {}
    list[#list + 1] = ctx.point(meta.enter)
    list[#list + 1] = ctx.point(meta.menu)
    if p.object_id ~= nil then
      local parent = ctx.export('GetProperty', p.object_id)
      local pmeta = type(parent) == 'table' and ctx.decode(parent.metadata) or nil
      if pmeta then list[#list + 1] = ctx.point(pmeta.enter) end
    end
    return list
  end,
})

-- Key changes come from vms_housing clients (TriggerServerEvent): they must be net events here
-- too. Payload ignored; any client can send them, so they only ask for a rate-limited reload.
for _, name in ipairs({ 'vms_housing:sv:giveKey', 'vms_housing:sv:buyKey', 'vms_housing:sv:removeKey' }) do
  RegisterNetEvent(name, function() Housing.hint('vms', 2000) end)
end
