--[[
  nayzeee-garages — housing loader: rtx_housing (RTX Development) (server). House ids 'rtx:<houseid>'.

  Reads exports GetAllProperties() (array or map; housedata may be flattened onto the property
  or still a JSON column), falling back to the `houses` table (owned houses). Garage =
  garage { enabled, coords {x,y,z}, heading } (rtx's own -2.0 z offset is not applied).
  Access = owner + players whose rtx permission set has garage = true. Tenants are not in the
  cached sets (rtx's TenantPropertyPermissions.garage cannot be read from another resource);
  while online they get access through the live GetPropertyPermission check, which follows it.
  Automatic: we draw the garage point (install/housing/rtx_housing turns rtx's own garage
  interaction off and adds the optional hook / refresh branches).
  Refresh hints: rtx_housing:Global:AddPermission / RemovePermission (net events, payload
  ignored, rate limited: Housing.netHint), rtx_housing:Global:AddLog (server event), resource
  start, the RefreshHousing export.
  Live access (online players): exports GetPropertyPermission(src, houseid, 'garage').
  Confidence: medium (escrowed; editable files and SQL read).
]]

local Housing = NZ.Housing

local DB_FALLBACK = "SELECT `houseid`, `owneridentifier`, `propertyname`, `housedata`, `permissions` FROM `houses` WHERE `owneridentifier` <> ''"

local function garageOf(ctx, p)
  local garage = ctx.decode(p.garage)
  if not garage then
    local data = ctx.decode(p.housedata)
    garage = data and ctx.decode(data.garage) or nil
  end
  if type(garage) ~= 'table' or garage.enabled == false then return nil end
  return ctx.point(garage)
end

Housing.addLoader({
  prefix = 'rtx',
  resources = { 'rtx_housing' },
  hook = 'whenUsed',

  load = function(ctx)
    local rows = ctx.export('GetAllProperties')
    if type(rows) ~= 'table' or next(rows) == nil then
      rows = ctx.query(DB_FALLBACK)
      if not rows then return nil end
    end

    local out, n = {}, 0
    for key, p in pairs(rows) do
      n = n + 1
      ctx.yield(n)
      p = ctx.decode(p)
      local houseid = type(p) == 'table' and (p.houseid or key) or nil
      if houseid ~= nil then
        local set = {}
        local owner = ctx.identifier(p.owner or p.owneridentifier)
        if owner then set[owner] = true end
        local permissions = ctx.decode(p.permissions)
        if permissions then
          for k, entry in pairs(permissions) do
            local flags = type(entry) == 'table' and ctx.decode(entry.permissions) or nil
            if flags and flags.garage == true then
              local who = ctx.identifier(entry.identifierdata) or (type(k) == 'string' and ctx.identifier(k) or nil)
              if who then set[who] = true end
            end
          end
        end
        out[tostring(houseid)] = {
          id = houseid,
          name = ctx.text(p.propertyname),
          coords = garageOf(ctx, p),
          access = set,
        }
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId, src)
    src = src or ctx.sourceOf(identifier)
    local id = ctx.int(rawId)
    if not src or not id then return nil end
    if ctx.export('GetPropertyPermission', src, id, 'garage') == true then return true end
    return nil
  end,
})

-- Permission changes from the rtx client (payload untrusted and ignored); rtx saves them in its
-- escrowed handler, so read a little later. Any client can send them: rate limited per player,
-- at most one reload of this loader per 30 s through them.
RegisterNetEvent('rtx_housing:Global:AddPermission', function() Housing.netHint(source, 'rtx', 1500) end)
RegisterNetEvent('rtx_housing:Global:RemovePermission', function() Housing.netHint(source, 'rtx', 1500) end)
-- Purchases, sales, transfers, rent changes (if rtx triggers its log event for them).
AddEventHandler('rtx_housing:Global:AddLog', function() Housing.hint('rtx', 1500) end)
