--[[
  nayzeee-garages — framework detection (shared).
  Sets NZ.Framework to 'qbx' | 'qb' | 'esx' | 'standalone'. The framework must be started
  before this resource (ensure it earlier in server.cfg).
]]

local function started(name)
  local state = GetResourceState(name)
  return state == 'started' or state == 'starting'
end

local function detect()
  local forced = Config.Framework
  if forced and forced ~= 'auto' then return forced end
  -- qbx_core also provides 'qb-core', so check it first.
  if started('qbx_core') then return 'qbx' end
  if started('qb-core') then return 'qb' end
  if started('es_extended') then return 'esx' end
  return 'standalone'
end

NZ.Framework = detect()

--- True when a resource is running (used by integrations).
function NZ.Utils.resourceStarted(name)
  return started(name)
end

if NZ.Framework == 'standalone' then
  CreateThread(function()
    Wait(2000)
    lib.print.warn('[nayzeee-garages] No supported framework detected (qbx_core, qb-core, es_extended). Make sure it starts before nayzeee-garages.')
  end)
end
