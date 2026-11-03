--[[
  nayzeee-garages — housing loader: tk_housing (TK Scripts) (server). House ids 'tk:<property id>'.

  Hook-driven: with tk_housing's custom garage menu option on, its OpenGarageMenu(propertyIndex)
  (client/main_editable.lua) calls OpenHouseGarage / StoreHouseGarage (install/housing/tk_housing);
  tk_housing has no garage coordinates, so the garage is registered (hidden) where it is used.
  Access from exports getProperties() (owner) + getPropertyKeyholders(id) (falls back to the
  keys of property.permissions); 'job:' style keys are skipped. Live access:
  getPropertyData(id) owner / permissions[identifier]. The property door (property.coords)
  bounds where a hook garage may be placed. No change events known: periodic reload.
  Confidence: medium (server exports as used by an open-source phone bridge; untested in game).
]]

local Housing = NZ.Housing

Housing.addLoader({
  prefix = 'tk',
  resources = { 'tk_housing' },
  hook = 'always',

  load = function(ctx)
    local props = ctx.export('getProperties')
    if type(props) ~= 'table' then return nil end

    local out = {}
    for _, p in pairs(props) do
      local pid = type(p) == 'table' and ctx.int(p.id) or nil
      if pid and pid > 0 then
        local set = {}
        if not ctx.isJobKey(p.owner) then
          local owner = ctx.identifier(p.owner)
          if owner then set[owner] = true end
        end
        local holders = ctx.export('getPropertyKeyholders', pid)
        local list = {}
        if type(holders) == 'table' then
          ctx.addAny(list, holders)
        elseif type(p.permissions) == 'table' then
          ctx.addKeys(list, p.permissions)
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
    if type(p.owner) == 'string' and p.owner ~= '' and p.owner == identifier then return true end
    if type(p.permissions) == 'table' and p.permissions[identifier] ~= nil then return true end
    return false
  end,

  anchors = function(ctx, rawId)
    local pid = ctx.int(rawId)
    local p = pid and ctx.export('getPropertyData', pid)
    if type(p) ~= 'table' then return nil end
    return { ctx.point(p.coords) }
  end,
})
