--[[
  nayzeee-garages — housing loader: ps-housing (server). House ids 'ps:<property id>'.

  Reads `properties` (owner_citizenid + has_access, garage_data {x,y,z,h,length,width}); houses
  only (apartments have no garage zone in ps-housing). Fully automatic: we draw the garage point.
  Live refresh hints: ps-housing:server:updateProperty (realtor edits, purchases),
  ps-housing:server:addAccess / removeAccess (key changes; client-triggered, so only a
  rate-limited reload hint: Housing.netHint), resource start. Live access: exports IsOwner(src, id) for online
  players (owner or key holder). Confidence: high (open source, archived at v2.0.8).
]]

local Housing = NZ.Housing

local COLUMNS = 'SELECT `property_id`, `owner_citizenid`, `has_access`, `garage_data`, `street` FROM `properties`'
local TIGHT = COLUMNS .. " WHERE `garage_data` IS NOT NULL AND JSON_LENGTH(`garage_data`) > 0 AND (`apartment` IS NULL OR `apartment` = '')"
local LOOSE = COLUMNS .. ' WHERE `garage_data` IS NOT NULL'
local tightWorks = true

-- Property changes that can move, add or remove a garage or change who may use it.
local KINDS = {
  UpdateGarage = true, UpdateDoor = true, UpdateApartment = true,
  DeleteProperty = true, UpdateHas_access = true,
}

Housing.addLoader({
  prefix = 'ps',
  resources = { 'ps-housing' },
  hook = 'never',

  load = function(ctx)
    local rows
    if tightWorks then rows = ctx.query(TIGHT) end
    if not rows then
      rows = ctx.query(LOOSE)
      -- Only give up on the tight query when the simple one works (not a database outage).
      if rows and tightWorks then
        tightWorks = false
        ctx.debug('housing: ps-housing JSON_LENGTH query failed, using the simple query')
      end
    end
    if not rows then return nil end

    local out = {}
    for i, row in ipairs(rows) do
      ctx.yield(i)
      local id = ctx.int(row.property_id)
      local coords = id and ctx.point(row.garage_data)
      if coords then
        local set = {}
        local owner = ctx.identifier(row.owner_citizenid)
        if owner then set[owner] = true end
        ctx.addAny(set, row.has_access)
        out[id] = {
          id = id,
          name = ('%s %d'):format(ctx.text(row.street, 50) or L('Property'), id),
          coords = coords,
          access = set,
        }
      end
    end
    return out
  end,

  --- IsOwner(src, id): owner or key holder. Only for a loaded player (ps-housing answers true
  --- for unowned properties when the player cannot be resolved).
  check = function(ctx, identifier, rawId, src)
    src = src or ctx.sourceOf(identifier)
    if not src or ctx.identifierOf(src) ~= identifier then return nil end
    local id = ctx.int(rawId)
    if not id then return nil end
    if ctx.export('IsOwner', src, tostring(id)) == true then return true end
    return nil
  end,
})

-- ps-realtor relays every property edit through this server event (type, property_id, data).
AddEventHandler('ps-housing:server:updateProperty', function(kind)
  if kind == 'UpdateOwner' then
    -- The new owner is written only after the buyer confirms the purchase.
    Housing.hint('ps', 3000)
    Housing.hint('ps', 30000)
    Housing.hint('ps', 120000)
  elseif KINDS[kind] then
    Housing.hint('ps', 1500)
  end
end)

-- Key changes (net events from the ps-housing client; payload ignored). Any client can send
-- them: rate limited per player, at most one reload of this loader per 30 s through them.
RegisterNetEvent('ps-housing:server:addAccess', function() Housing.netHint(source, 'ps', 1500) end)
RegisterNetEvent('ps-housing:server:removeAccess', function() Housing.netHint(source, 'ps', 1500) end)
