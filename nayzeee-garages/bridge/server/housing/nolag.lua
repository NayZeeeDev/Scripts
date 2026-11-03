--[[
  nayzeee-garages — housing loader: nolag_properties (NoLag / TeamsGG) (server).
  House ids 'nolag:<property id>' (integers: 'nolag:021' from a hook becomes 'nolag:21').

  Hook-driven: nolag_properties loads one garage adapter, custom/garages/<Config.Garage>.lua;
  install/housing/nolag_properties adds Config.Functions.OpenGarageMenu, an interactable point
  players place in their property, whose onSelect calls OpenHouseGarage / StoreHouseGarage. The
  garage is registered (hidden) where the point is used. nolag has no export listing every
  property, so access is checked live (authoritative): GetPropertyData(id) owner / renter (user
  owners), keyHolders, then HasKey(identifier, id); a property GetPropertyData does not know is
  a "no". Society properties: the key holders, and every member of the owning job only when
  HasKey fails or the server opts in with  set nayzeee_housing_nolag_society 1  (nolag's own
  garage point requires keys; unverified whether society members hold them). The houses already
  known are re-read on every reload (GetPropertyData + GetKeyHolders) for the cached sets; a
  property nolag no longer has (GetPropertyData answers nothing) is dropped when a read at least
  a minute later agrees (not within 2 minutes of nolag_properties starting, when it answers
  nothing for every property, while it may still be loading them).
  Police lockdown (metadata.lockdown) denies the garage on the server too, like nolag's
  Config.PoliceLockdown.DisableGarage (default on); servers that turned that off mirror it with
  set nayzeee_housing_nolag_lockdown 0  in server.cfg.
  Where the property is (hook garages must be near it): GetPropertyData(id).coords, the
  `coords` of its item in GetAllProperties(owner, ownerType, true), metadata.enterData /
  managePoint.
  Confidence: medium (adapter interface from nolag's own bundled adapters, 2.4.x; 3.x unconfirmed).
]]

local Housing = NZ.Housing

local LOCKDOWN_CONVAR = 'nayzeee_housing_nolag_lockdown'
local SOCIETY_CONVAR = 'nayzeee_housing_nolag_society'
local MEMO_MS = 1000         -- one hook call asks for the same property up to three times
local START_GRACE_MS = 120000 -- after nolag_properties (or this resource) starts, "every known
                              -- property is missing" means "still loading"

local memo = {} -- [pid] = { at, p, failed }
local lastPrune = 0
local startedAt = GetGameTimer()

AddEventHandler('onResourceStart', function(resource)
  if resource == 'nolag_properties' then startedAt = GetGameTimer() end
end)

--- GetPropertyData(id): property, id, failed (true when the export call itself failed).
local function propertyOf(ctx, rawId)
  local pid = ctx.int(rawId)
  if not pid then return nil, nil, false end
  local now = GetGameTimer()
  local m = memo[pid]
  if m and now - m.at < MEMO_MS then return m.p, pid, m.failed end
  local p, err = ctx.export('GetPropertyData', pid)
  if type(p) ~= 'table' then p = nil end
  local failed = p == nil and err ~= nil
  -- Pruned at most once per MEMO_MS (a reload over N properties adds N entries).
  if now - lastPrune >= MEMO_MS then
    lastPrune = now
    for k, v in pairs(memo) do
      if now - v.at >= MEMO_MS then memo[k] = nil end
    end
  end
  memo[pid] = { at = now, p = p, failed = failed }
  return p, pid, failed
end

local function convarOn(name, default)
  local ok, value = pcall(GetConvar, name, default)
  if not ok or type(value) ~= 'string' or value == '' then value = default end
  value = value:lower()
  return value ~= '0' and value ~= 'false' and value ~= 'no'
end

local function lockdownDenies()
  return convarOn(LOCKDOWN_CONVAR, '1')
end

local function same(a, b)
  return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

Housing.addLoader({
  prefix = 'nolag',
  resources = { 'nolag_properties' },
  hook = 'always',
  numericIds = true,
  authoritative = true,

  load = function(ctx)
    local out, found, missing = {}, 0, {}
    for i, raw in ipairs(ctx.known()) do
      ctx.yield(i)
      local p, pid, failed = propertyOf(ctx, raw)
      if failed then return nil end -- keep what was loaded before
      if not p and pid then missing[#missing + 1] = pid end
      if p then
        found = found + 1
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
    -- Nothing answered right after nolag (or this resource) started: probably still loading.
    -- Later, "every known property is gone" is believed (after the usual confirming read).
    if found == 0 and #missing > 0 and GetGameTimer() - startedAt < START_GRACE_MS then return nil end
    -- Properties nolag no longer has (deleted): dropped when a later read agrees.
    for i = 1, #missing do out[missing[i]] = { id = missing[i], gone = true } end
    return out, false -- only the known houses: the others are kept
  end,

  check = function(ctx, identifier, rawId, src)
    local p, pid, failed = propertyOf(ctx, rawId)
    if not p then
      if failed or not pid then return nil end -- the export failed: unknown
      return false -- nolag answered: no such property
    end
    local society = p.ownerType == 'society'
    if not society and (same(p.owner, identifier) or same(p.renter, identifier)) then return true end
    local holders = {}
    ctx.addAny(holders, p.keyHolders)
    if holders[identifier] then return true end
    local has, err = ctx.export('HasKey', identifier, pid)
    if has == true then return true end
    -- Society property: the owning job's members, when HasKey cannot tell or the server opted in.
    if society and (err ~= nil or convarOn(SOCIETY_CONVAR, '0')) then
      local job = ctx.jobOf(src or ctx.sourceOf(identifier))
      if job and same(p.owner, job) then return true end
    end
    if err ~= nil then return nil end -- unknown: the cached key holders decide
    return false
  end,

  --- Police lockdown (metadata.lockdown) closes the garage for everyone.
  blocked = function(ctx, rawId)
    if not lockdownDenies() then return false end
    local p = propertyOf(ctx, rawId)
    local meta = p and ctx.decode(p.metadata) or nil
    return type(meta) == 'table' and meta.lockdown ~= nil and meta.lockdown ~= false
  end,

  --- Where the property is: its own coords, its GetAllProperties item, the entrance metadata.
  anchors = function(ctx, rawId)
    local p, pid = propertyOf(ctx, rawId)
    if not p then return nil end
    local list = {}
    list[#list + 1] = ctx.point(p.coords)
    local meta = ctx.decode(p.metadata)
    if type(meta) == 'table' then
      list[#list + 1] = ctx.point(meta.enterData)
      list[#list + 1] = ctx.point(meta.managePoint)
    end
    -- GetAllProperties(owner, ownerType, includeRented) items carry `coords` (the entrance,
    -- building entrance first): ask for the owner, then the renter.
    local ownerType = p.ownerType == 'society' and 'society' or 'user'
    for _, who in ipairs({ { p.owner, ownerType }, { p.renter, 'user' } }) do
      if #list > 0 then break end
      local identifier = ctx.identifier(who[1])
      local items = identifier and ctx.tryExport('GetAllProperties', identifier, who[2], true) or nil
      if type(items) == 'table' then
        for _, item in pairs(items) do
          if type(item) == 'table' and ctx.int(item.id) == pid then
            list[#list + 1] = ctx.point(item.coords)
            break
          end
        end
      end
    end
    return list
  end,
})
