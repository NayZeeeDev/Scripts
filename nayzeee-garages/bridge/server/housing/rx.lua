--[[
  nayzeee-garages — housing loader: RxHousing (RX Scripts, "Advanced Housing") (server).
  House ids 'rx:<property id>'. Resource 'RxHousing' (also 'rxscripts_housing').

  Reads exports GetAllProperties() (array or id-keyed map): owner (identifier string, a table
  shape is tolerated), renter / tenant when present, keyholders (field, else
  GetPropertyKeyholders(id) for owned properties). Unowned properties are listed too (access
  from the renter / keyholders fields only, no export call), so a hook garage the live check
  allowed for them is kept across reloads. Ids are integers ('rx:9.0' from a hook becomes
  'rx:9'). The garage point is coords.garage when the property has one (documented only as an input of
  GiveApartmentToPlayer: unconfirmed, so a hook call may move it). RxHousing hands garages to
  RX's fmLib: install/housing/RxHousing adds a nayzeee garage adapter to fmLib that calls
  OpenHouseGarage / StoreHouseGarage (garage registered hidden where it is used when the property
  has no garage point, within range of its entrance). Refresh hints: rxhousing:on* server events, resource start.
  Live access (authoritative): HasKey(id, identifier), then the owner / renter / keyholders of
  GetProperty(id); unknown when HasKey fails.
  Confidence: medium (escrowed; exports and events from RX's documentation).
]]

local Housing = NZ.Housing

local function ownerOf(ctx, value)
  if type(value) == 'table' then value = value.identifier or value.citizenid or value.citizenId or value.id end
  return ctx.identifier(value)
end

local function idOf(ctx, rawId)
  return ctx.int(rawId) or rawId
end

Housing.addLoader({
  prefix = 'rx',
  resources = { 'RxHousing', 'rxscripts_housing' },
  hook = 'whenUsed',
  create = true,       -- most properties have no readable garage point
  trustCoords = false, -- coords.garage is unconfirmed: the hook may move it
  numericIds = true,   -- RX exports take numeric ids
  authoritative = true,

  load = function(ctx)
    local all = ctx.export('GetAllProperties')
    if type(all) ~= 'table' then return nil end

    local out, n = {}, 0
    for key, p in pairs(all) do
      n = n + 1
      ctx.yield(n)
      p = ctx.decode(p)
      local pid = type(p) == 'table' and (p.id or p.propertyId or p.property_id or key) or nil
      if pid ~= nil then
        local set = {}
        local owner = ownerOf(ctx, p.owner)
        if owner then set[owner] = true end
        for _, who in ipairs({ p.renter, p.tenant }) do
          local renter = ownerOf(ctx, who)
          if renter then set[renter] = true end
        end
        local holders = p.keyholders or p.keyHolders
        -- Unowned properties: no export call (nobody gave keys), only what the entry carries.
        if holders == nil and owner then holders = ctx.export('GetPropertyKeyholders', idOf(ctx, pid)) end
        ctx.addAny(set, holders)
        local coords = ctx.decode(p.coords)
        out[tostring(pid)] = {
          id = pid,
          name = ctx.text(p.label),
          coords = coords and coords.garage ~= nil and ctx.point(coords.garage) or nil,
          access = set,
        }
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId)
    local id = idOf(ctx, rawId)
    local has, err = ctx.export('HasKey', id, identifier)
    if has == true then return true end
    local p = ctx.decode(ctx.export('GetProperty', id))
    if type(p) ~= 'table' then return nil end
    if ownerOf(ctx, p.owner) == identifier or ownerOf(ctx, p.renter) == identifier
      or ownerOf(ctx, p.tenant) == identifier then return true end
    local holders = {}
    ctx.addAny(holders, p.keyholders or p.keyHolders)
    if holders[identifier] then return true end
    if err ~= nil then return nil end -- HasKey failed: the cached key holders decide
    return false
  end,

  --- The property's entrance (coords.entrance, or coords itself).
  anchors = function(ctx, rawId)
    local p = ctx.decode(ctx.export('GetProperty', idOf(ctx, rawId)))
    local coords = type(p) == 'table' and ctx.decode(p.coords) or nil
    if not coords then return nil end
    return { coords.entrance ~= nil and ctx.point(coords.entrance) or ctx.point(coords) }
  end,
})

-- Server events RxHousing fires for other resources (payload ignored). The opensource template
-- also uses the onHouse* spelling.
for _, name in ipairs({
  'rxhousing:onPropertyBought', 'rxhousing:onPropertyRented', 'rxhousing:onPropertyCreated',
  'rxhousing:onPropertyTransferred', 'rxhousing:onKeyholderAdded', 'rxhousing:onKeyholderRemoved',
  'rxhousing:onHouseBought', 'rxhousing:onHouseRented',
}) do
  AddEventHandler(name, function() Housing.hint('rx', 1000) end)
end
