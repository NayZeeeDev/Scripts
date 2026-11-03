--[[
  nayzeee-garages — housing loader: esx_property (ESX Legacy) (server). House ids 'esx:<property id>'
  (the property's index in esx_property's list).

  Reads exports GetProperties() (garage { enabled, pos, Heading }, Owner / Owned, Keys keyed by
  identifier); falls back to the `esx_properties` table (1.16.2+) and then properties.json
  (1.16.0 and older). An empty list means "not loaded yet" and keeps the previous houses.
  esx_property has no server events for other resources: it is re-read every 2 minutes, and
  clients ask for a refresh when esx_property syncs a garage change (bridge/client/housing.lua).
  esx_property always draws its own garage marker: install/housing/esx_property routes it to
  our garage (then set the 'nayzeee_housing_hooked' convar to hide our own point).
  Live access: exports DoesPlayerHaveKeys(id, identifier) (key holders; owners come from the list).
  Confidence: high (open source, GPL-3).
]]

local Housing = NZ.Housing

local function fromSql(ctx)
  if not ctx.tableExists('esx_properties') then return nil end
  local rows = ctx.query('SELECT `id`, `data` FROM `esx_properties`')
  if not rows then return nil end
  local list = {}
  for _, row in ipairs(rows) do
    local id = ctx.int(row.id)
    local data = ctx.decode(row.data)
    if id and data then list[id] = data end
  end
  return list
end

local function fromFile(ctx)
  local ok, raw = pcall(LoadResourceFile, ctx.resource or 'esx_property', 'properties.json')
  if not ok then return nil end
  return ctx.decode(raw)
end

Housing.addLoader({
  prefix = 'esx',
  resources = { 'esx_property' },
  hook = 'whenUsed',
  interval = 120000,

  load = function(ctx)
    local props = ctx.export('GetProperties')
    if type(props) ~= 'table' or next(props) == nil then props = fromSql(ctx) end
    if type(props) ~= 'table' or next(props) == nil then props = fromFile(ctx) end
    if type(props) ~= 'table' or next(props) == nil then return nil end

    local out = {}
    for index, p in pairs(props) do
      local id = ctx.int(index)
      local garage = id and type(p) == 'table' and ctx.decode(p.garage) or nil
      if garage and garage.enabled == true then
        local coords = ctx.v4(garage.pos)
        if coords then
          local heading = tonumber(garage.Heading or garage.heading)
          if heading then coords.w = heading end
          local set = {}
          if p.Owned ~= false then
            local owner = ctx.identifier(p.Owner)
            if owner then set[owner] = true end
          end
          ctx.addAny(set, p.Keys)
          local label = (type(p.setName) == 'string' and p.setName ~= '' and p.setName) or p.Name
          out[id] = {
            id = id,
            name = ('%s #%d'):format(ctx.text(label, 50) or L('Property'), id),
            coords = coords,
            access = set,
          }
        end
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId)
    local id = ctx.int(rawId)
    if not id then return nil end
    if ctx.export('DoesPlayerHaveKeys', id, identifier) == true then return true end
    return nil
  end,
})
