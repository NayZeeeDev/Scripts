--[[
  nayzeee-garages — housing loader: qb-houses (server). House ids 'qb:<house name>'.

  Reads houselocations (name, label, garage JSON) and player_houses (house, citizenid,
  keyholders JSON). Fully automatic: we draw the garage point; qb-houses' qb-garages client
  events ask for a refresh (bridge/client/housing.lua). Confidence: high (open source).
]]

local Housing = NZ.Housing

Housing.addLoader({
  prefix = 'qb',
  resources = { 'qb-houses' },
  hook = 'never',
  -- qs-housing uses the same tables: in 'auto' mode its own loader reads them.
  autoSkip = function(ctx) return ctx.started('qs-housing') end,

  load = function(ctx)
    local houses = ctx.query("SELECT `name`, `label`, `garage` FROM `houselocations` WHERE `garage` IS NOT NULL AND `garage` <> ''")
    if not houses then return nil end
    local owners = ctx.query('SELECT `house`, `citizenid`, `keyholders` FROM `player_houses`')
    if not owners then return nil end

    local access = {}
    for _, row in ipairs(owners) do
      if type(row.house) == 'string' then
        local set = access[row.house]
        if not set then
          set = {}
          access[row.house] = set
        end
        local owner = ctx.identifier(row.citizenid)
        if owner then set[owner] = true end
        ctx.addAny(set, row.keyholders)
      end
    end

    local out = {}
    for _, row in ipairs(houses) do
      local coords = type(row.name) == 'string' and ctx.point(row.garage) or nil
      if coords then
        out[row.name] = {
          name = ctx.text(row.label) or ctx.text(row.name),
          coords = coords,
          access = access[row.name] or {},
        }
      end
    end
    return out
  end,
})
