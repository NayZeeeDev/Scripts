--[[
  nayzeee-garages — housing loader: bcs_housing (BagusCodeStudio) (server). House ids 'bcs:<home id>'.

  Reads exports GetHomes() (fields at the top level or under `properties`): the garage point
  data.garage (vector4: interaction and spawn), skipped when configuration.garage == false;
  access = owner + GetKeyHolders(id) holders whose key has the 'Garage' permission
  (HasKey(id, identifier, 'Garage'); a holder is kept when that call fails). Every name and
  argument order is from documentation excerpts only (unconfirmed): all calls are pcall'd.
  We draw our own point by default. bcs_housing also draws a garage prompt (GaragePrompt in its
  client/garage.lua): install/housing/bcs_housing routes it to OpenHouseGarage /
  StoreHouseGarage; then set the 'nayzeee_housing_hooked' convar to hide our own point.
  No change events are documented: periodic reload + resource start.
  Live access: HasKey(id, identifier, 'Garage'). Confidence: low.
]]

local Housing = NZ.Housing

local PERMISSION = 'Garage'

local function homeFields(home)
  return type(home.properties) == 'table' and home.properties or home
end

Housing.addLoader({
  prefix = 'bcs',
  resources = { 'bcs_housing' },
  hook = 'whenUsed',

  load = function(ctx)
    local homes = ctx.export('GetHomes')
    if type(homes) ~= 'table' then return nil end

    local out = {}
    for key, home in pairs(homes) do
      if type(home) == 'table' then
        local p = homeFields(home)
        local homeId = home.identifier or p.identifier or home.id or key
        if homeId ~= nil then
          local data = ctx.decode(p.data) or ctx.decode(home.data) or {}
          local conf = ctx.decode(home.configuration) or ctx.decode(p.configuration)
          local enabled = not (type(conf) == 'table' and (conf.garage == false or conf.Garage == false))
          local coords = enabled and data.garage ~= nil and ctx.point(data.garage) or nil

          local set = {}
          local owner = ctx.identifier(p.owner or home.owner)
          if owner then set[owner] = true end
          local holders = {}
          ctx.addAny(holders, ctx.export('GetKeyHolders', homeId))
          for who in pairs(holders) do
            if not set[who] and ctx.export('HasKey', homeId, who, PERMISSION) ~= false then set[who] = true end
          end

          out[tostring(homeId)] = {
            id = homeId,
            name = ctx.text(p.name) or ctx.text(home.name),
            coords = coords,
            access = set,
          }
        end
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId)
    if ctx.export('HasKey', rawId, identifier, PERMISSION) == true then return true end
    return nil
  end,

  --- Entrance (Flat homes: data.flat.coords). Used for homes without a garage point.
  anchors = function(ctx, rawId)
    local home = ctx.export('GetHome', rawId)
    if type(home) ~= 'table' then return nil end
    local p = homeFields(home)
    local data = ctx.decode(p.data) or ctx.decode(home.data) or {}
    local flat = ctx.decode(data.flat)
    return { ctx.point(p.entry or home.entry), flat and ctx.point(flat) or nil }
  end,
})
