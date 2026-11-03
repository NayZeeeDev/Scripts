--[[
  nayzeee-garages — housing loader: qs-housing (Quasar Housing) (server). House ids 'qs:<house name>'.

  qs-housing keeps the qb-houses tables: houselocations (name, label/adress, garage JSON
  { coords = {x,y,z,h}, slots = {...} } or a flat {x,y,z,h}) and player_houses (house, owner /
  citizenid / identifier, keyholders JSON). qs-housing itself draws no garage prompt (its
  per-garage bridge files do), so we draw our own point: automatic. The optional files in
  install/housing/qs-housing call OpenHouseGarage / StoreHouseGarage and the RefreshHousing
  export. Live access (online players): exports CheckHasKey(license, citizenid, house, src),
  falling back to hasKey(license, citizenid, house) (both unconfirmed beyond third-party use).
  Confidence: medium (escrowed; schema confirmed by several third-party readers).
]]

local Housing = NZ.Housing

local HOUSES = "SELECT `name`, `label`, `garage` FROM `houselocations` WHERE `garage` IS NOT NULL AND `garage` <> '' AND `garage` NOT IN ('[]', '{}', 'null')"
local HOUSES_ANY = "SELECT * FROM `houselocations` WHERE `garage` IS NOT NULL AND `garage` <> ''"
local SLOT_MIN_GAP = 2.5 -- metres: a parking slot this far from the garage point is the spawn
local labelWorks = true  -- false once the build turned out to have no `label` column

Housing.addLoader({
  prefix = 'qs',
  resources = { 'qs-housing' },
  hook = 'never',

  load = function(ctx)
    -- Builds differ in the label column: fall back to every column, and remember it (oxmysql
    -- prints its own error for every failed query).
    local houses = labelWorks and ctx.query(HOUSES) or nil
    if not houses then
      houses = ctx.query(HOUSES_ANY)
      -- Only give up on the label query when the simple one works (not a database outage).
      if houses and labelWorks then
        labelWorks = false
        ctx.debug('housing: qs-housing has no label column, using SELECT *')
      end
    end
    if not houses then return nil end
    local owners = ctx.query('SELECT * FROM `player_houses`')
    if not owners then return nil end

    local access = {}
    for i, row in ipairs(owners) do
      ctx.yield(i)
      local house = type(row.house) == 'string' and row.house or nil
      if house then
        local set = access[house]
        if not set then
          set = {}
          access[house] = set
        end
        -- Column meaning differs between builds: only the framework identifier ever matches.
        for _, column in ipairs({ 'citizenid', 'owner', 'identifier' }) do
          local who = ctx.identifier(row[column])
          if who then set[who] = true end
        end
        ctx.addAny(set, row.keyholders)
      end
    end

    local out = {}
    for i, row in ipairs(houses) do
      ctx.yield(i)
      local garage = type(row.name) == 'string' and ctx.decode(row.garage) or nil
      local coords = garage and ctx.point(garage)
      if coords then
        local spawn
        local slots = ctx.decode(garage.slots)
        if type(slots) == 'table' then
          local slot = ctx.v4(slots[1])
          if slot and ctx.dist(slot, coords) > SLOT_MIN_GAP then spawn = slot end
        end
        out[row.name] = {
          name = ctx.text(row.label) or ctx.text(row.adress) or ctx.text(row.name),
          coords = coords,
          spawn = spawn,
          access = access[row.name] or {},
        }
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId, src)
    src = src or ctx.sourceOf(identifier)
    if not src then return nil end
    local license = GetPlayerIdentifierByType(src, 'license')
    if type(license) ~= 'string' then return nil end
    -- CheckHasKey is the newer name; hasKey the older one (a failure of the first is expected
    -- on older builds and only debug-logged).
    local has = ctx.tryExport('CheckHasKey', license, identifier, rawId, src)
    if has == nil then has = ctx.export('hasKey', license, identifier, rawId) end
    if has == true then return true end
    return nil
  end,
})
