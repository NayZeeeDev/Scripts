--[[
  nayzeee-garages — housing loader: tk_housing (TK Scripts) (server). House ids 'tk:<property id>'.

  Hook-driven: with tk_housing's custom garage menu option on, its OpenGarageMenu(propertyIndex)
  (client/main_editable.lua) calls OpenHouseGarage / StoreHouseGarage (install/housing/tk_housing);
  tk_housing has no garage coordinates, so the garage is registered (hidden) where it is used.
  Access from exports getProperties(): owner + the keys of property.permissions (only when a
  build has no permissions field, getPropertyKeyholders(id) of owned properties); unowned
  properties are listed without access (no export call; their hook garage survives reloads)
  and 'job:' style keys are not identifiers. Live access (authoritative):
  getPropertyData(id) owner / permissions[identifier]. The property door (property.coords)
  bounds where a hook garage may be placed. No change events known: periodic reload + the
  live check. Ids are integers ('tk:1.0' from a hook becomes 'tk:1').
  Confidence: medium (server exports as used by an open-source phone bridge; untested in game).
]]

local Housing = NZ.Housing

--- Owner identifier of a property (nil when unowned).
local function ownerOf(ctx, p)
  return ctx.identifier(p.owner)
end

Housing.addLoader({
  prefix = 'tk',
  resources = { 'tk_housing' },
  hook = 'always',
  numericIds = true,
  authoritative = true,

  load = function(ctx)
    local props = ctx.export('getProperties')
    if type(props) ~= 'table' then return nil end

    local out, n = {}, 0
    for _, p in pairs(props) do
      n = n + 1
      ctx.yield(n)
      local pid = type(p) == 'table' and ctx.int(p.id) or nil
      local owner = pid and pid > 0 and ownerOf(ctx, p) or nil
      if pid and pid > 0 and not owner then
        -- Unowned: listed without access (nobody gave keys, no export call).
        out[pid] = { id = pid, name = ctx.text(p.name), access = {} }
      elseif owner then
        local set = {}
        if not ctx.isJobKey(owner) then set[owner] = true end
        local list = {}
        local permissions = ctx.decode(p.permissions)
        if permissions then
          ctx.addAny(list, permissions)
        else
          ctx.addAny(list, ctx.export('getPropertyKeyholders', pid))
        end
        for who in pairs(list) do
          if not ctx.isJobKey(who) then set[who] = true end
        end
        out[pid] = { id = pid, name = ctx.text(p.name), access = set }
      end
    end
    return out
  end,

  check = function(ctx, identifier, rawId)
    local pid = ctx.int(rawId)
    if not pid then return nil end
    local p = ctx.export('getPropertyData', pid)
    if type(p) ~= 'table' then return nil end
    if ownerOf(ctx, p) == identifier then return true end
    local permissions = ctx.decode(p.permissions)
    if not permissions then return nil end -- build without the field: the cached key holders decide
    local set = {}
    ctx.addAny(set, permissions)
    return set[identifier] == true
  end,

  anchors = function(ctx, rawId)
    local pid = ctx.int(rawId)
    local p = pid and ctx.export('getPropertyData', pid)
    if type(p) ~= 'table' then return nil end
    return { ctx.point(p.coords) }
  end,
})
