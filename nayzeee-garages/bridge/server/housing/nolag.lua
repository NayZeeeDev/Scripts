--[[
  nayzeee-garages — housing loader: nolag_properties (NoLag / TeamsGG) (server).
  House ids 'nolag:<property id>'.

  Hook-driven: nolag_properties loads one garage adapter, custom/garages/<Config.Garage>.lua;
  install/housing/nolag_properties adds Config.Functions.OpenGarageMenu, an interactable point
  players place in their property, whose onSelect calls OpenHouseGarage / StoreHouseGarage. The
  garage is registered (hidden) where the point is used. nolag has no export listing every
  property, so access is checked live: GetPropertyData(id) owner / renter (user owners) or the
  player's job (society owners), then HasKey(identifier, id); the houses already known are
  re-read on every reload (GetPropertyData + GetKeyHolders) for the cached sets.
  Confidence: medium (adapter interface from nolag's own bundled adapters, 2.4.x; 3.x unconfirmed).
]]

local Housing = NZ.Housing

local function propertyOf(ctx, rawId)
  local pid = ctx.int(rawId)
  if not pid then return nil, nil end
  local p = ctx.export('GetPropertyData', pid)
  if type(p) ~= 'table' then return nil, pid end
  return p, pid
end

Housing.addLoader({
  prefix = 'nolag',
  resources = { 'nolag_properties' },
  hook = 'always',

  load = function(ctx)
    local out = {}
    for _, raw in ipairs(ctx.known(ctx)) do
      local p, pid = propertyOf(ctx, raw)
      if p then
        local set = {}
        if p.ownerType ~= 'society' then
          local owner = ctx.identifier(p.owner)
          if owner then set[owner] = true end
        end
        local renter = ctx.identifier(p.renter)
        if renter then set[renter] = true end
        ctx.addAny(set, p.keyHolders)
        ctx.addAny(set, ctx.export('GetKeyHolders', pid))
        out[pid] = { id = pid, name = ctx.text(p.label) or ctx.text(p.address), access = set }
      end
    end
    return out, false -- only the known houses: never remove the others
  end,

  check = function(ctx, identifier, rawId, src)
    local p, pid = propertyOf(ctx, rawId)
    if not p then return nil end
    if p.ownerType == 'society' then
      local job = ctx.jobOf(src or ctx.sourceOf(identifier))
      if job and p.owner == job then return true end
    elseif (p.owner ~= nil and tostring(p.owner) == identifier) or (p.renter ~= nil and tostring(p.renter) == identifier) then
      return true
    end
    if ctx.export('HasKey', identifier, pid) == true then return true end
    return false
  end,

  --- Entrance of the property (metadata.enterData / managePoint; unconfirmed shapes).
  anchors = function(ctx, rawId)
    local p = propertyOf(ctx, rawId)
    local meta = p and ctx.decode(p.metadata) or nil
    if not meta then return nil end
    return { ctx.point(meta.enterData), ctx.point(meta.managePoint) }
  end,
})
