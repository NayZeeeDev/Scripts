--[[
  Headless test for garage interiors, server side (no FiveM needed): config/interiors.lua
  and server/interiors.lua in a stubbed server runtime.

    preset vehicle positions of every IPL profile (inside their interior, spaced, valid
    headings, presetsFrom references) -> a new interior from a profile gets the presets,
    an older one without positions uses them when players enter -> per-player instances
    (Config.InteriorOptions.instances = 'player'): every member of a private group that
    stores its vehicles together gets an own routing bucket with only their own vehicles,
    invitations refused -> 'shared' mode keeps one instance per group with invitations.

  Usage (from the resource root):  lua5.4 tools/smoke/interiors.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

-- Runtime stubs -----------------------------------------------------------------------
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'nayzeee-garages' end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, { __name = 'vector3' }) end
function vector4(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, { __name = 'vector4' }) end
function joaat(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return h end
function CreateThread() end
function Wait() end
function SetTimeout() end
function AddEventHandler() end
function RegisterNetEvent() end
local clientEvents = {}
function TriggerClientEvent(name, target, payload) clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload } end
function GetConvar(_, d) return d end
local names = { [1] = 'Ana', [2] = 'Ben', [3] = 'Cleo' }
function GetPlayerName(src) return names[src] end
function GetPlayers() return { '1', '2', '3' } end
function GetPlayerPed(src) return src end
function GetVehiclePedIsIn() return 0 end
function GetEntityCoords() return vector3(0, 0, 0) end
local buckets = {}
function SetPlayerRoutingBucket(src, b) buckets[src] = b end
function GetPlayerRoutingBucket(src) return buckets[src] or 0 end
function SetRoutingBucketPopulationEnabled() end
function SetRoutingBucketEntityLockdownMode() end
function GetAllVehicles() return {} end
json = { encode = function() return '{}' end, decode = function() return {} end }

local callbacks = {}
lib = {
  callback = { register = function(name, fn) callbacks[name] = fn end },
  print = { info = function() end, warn = function() end, error = function(...) failures[#failures + 1] = 'lib.print.error: ' .. table.concat({ ... }, ' ') end, debug = function() end },
}

local function load_(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local ok, err = xpcall(assert(load(src, '@' .. file, 't', _ENV)), debug.traceback)
  if not ok then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end

load_('config/config.lua')
load_('config/interiors.lua')
load_('shared/init.lua')
load_('shared/utils.lua')
local Utils = NZ.Utils

-- 1. preset vehicle positions ---------------------------------------------------------
local profiles = Config.IplProfiles
local count = 0
for key, p in pairs(profiles) do
  count = count + 1
  local presets = p.presets
  if presets then
    check(#presets > 0 and #presets <= 60, key .. ': 1-60 presets')
    check(p.slots == #presets, key .. ': slots = number of presets (' .. tostring(p.slots) .. ' vs ' .. #presets .. ')')
    local entry = Utils.v4(p.coords)
    local origin = Utils.v3(p.interiorCoords) or entry
    check(entry ~= nil, key .. ': arrival coords')
    for i, v in ipairs(presets) do
      local s = Utils.v4(v)
      check(s and s.w >= 0 and s.w < 360, ('%s #%d: heading 0-360'):format(key, i))
      -- inside the interior: near its placement and the arrival point (the car meet hall is
      -- far from its placement point, ~200 m)
      check(Utils.dist(s, origin) < 230 and Utils.dist(s, entry) < 80, ('%s #%d: inside the interior'):format(key, i))
      check(s.z > entry.z - 3.0 and s.z < entry.z + 13.0, ('%s #%d: on a floor of the interior'):format(key, i))
      for j = i + 1, #presets do
        local o = Utils.v4(presets[j])
        if math.abs(o.z - s.z) < 2.0 then
          local d = math.sqrt((o.x - s.x) ^ 2 + (o.y - s.y) ^ 2)
          check(d >= 2.9, ('%s #%d/#%d: %.2f m apart (cars need room)'):format(key, i, j, d))
        end
      end
    end
  else
    local ref = p.presetsFrom and profiles[p.presetsFrom]
    check(ref and ref.presets and #ref.presets > 0, key .. ': presetsFrom names a profile with presets')
    check(ref and ref.slots == p.slots, key .. ': same capacity as its reference')
    check(Utils.dist(ref.interiorCoords, p.interiorCoords) > 40, key .. ': reference interior does not overlap it')
    -- the reference is loaded for a moment and read in game: keep it close (streaming)
    check(Utils.dist(ref.interiorCoords, p.interiorCoords) < 300, key .. ': reference interior is nearby (< 300 m)')
  end
end
check(count == 18, 'all 18 profiles present (' .. count .. ')')
check(Config.InteriorOptions.instances == 'player', 'per-player instances by default')
check(Config.InteriorOptions.cinematic.enabled and Config.InteriorOptions.cinematic.auto, 'arrival ride on by default')
check(Config.InteriorOptions.vehicleTag.enabled, 'vehicle card on by default')

-- 2. server: stubs of the other modules ----------------------------------------------
local Interiors = NZ.Interiors
NZ.Ready = true
NZ.Logs.add = function() end
NZ.Settings.get = function(_, d) return d end
local identifiers = { [1] = 'CID1', [2] = 'CID2', [3] = 'CID3' }
NZ.Bridge.getIdentifier = function(src) return identifiers[src] end
NZ.Bridge.getName = function(src) return names[src] end
NZ.Bridge.getCharacterName = function(id) return id end
NZ.Bridge.getJobs = function() return {} end
NZ.Bridge.getOnlinePlayers = function() return { { source = 1, name = 'Ana' }, { source = 2, name = 'Ben' }, { source = 3, name = 'Cleo' } } end
NZ.Access.rateLimit = function() return true end
NZ.Access.isNear = function() return true end
NZ.Access.isAdmin = function() return true end
NZ.Vehicles.canDrive = function(src, row) return row.owner == identifiers[src] end
NZ.Vehicles.incapacitated = function() return false end
NZ.Private.role = function(_, identifier) return identifier == 'CID1' and 'owner' or 'member' end

local interiorRows, nextId = {}, 0
NZ.DB.interiors = {
  all = function() return interiorRows end,
  insert = function(name, enabled, data) nextId = nextId + 1 interiorRows[#interiorRows + 1] = { id = nextId, name = name, enabled = enabled, data = data } return nextId end,
  update = function() return true end,
  delete = function() return true end,
}
local location = {
  id = 7, kind = 'private', name = 'Del Perro Lofts', enabled = true, storage = 'shared',
  openPoints = { { coords = { x = 10, y = 10, z = 30 }, radius = 2 } },
  spawnPoints = { { x = 12, y = 10, z = 30, w = 0 } },
  access = { mode = 'interior', interiorId = nil },
}
NZ.Locations.get = function(id) return id == 7 and location or nil end
NZ.Locations.keyName = function() return 'Del Perro Lofts' end
NZ.Locations.all = function() return { location } end
local vehicles = {
  { plate = 'AAA111', owner = 'CID1', garageKey = 'G4', state = 'garaged', model = 'neon', hash = 1 },
  { plate = 'BBB222', owner = 'CID2', garageKey = 'G4', state = 'garaged', model = 'elegy', hash = 2 },
  { plate = 'CCC333', owner = 'CID2', garageKey = 'G4', state = 'garaged', model = 'comet', hash = 3 },
}
NZ.DB.getVehiclesInGarage = function(key)
  local out = {}
  for _, v in ipairs(vehicles) do if v.garageKey == key then out[#out + 1] = v end end
  return out
end
NZ.DB.getVehiclesByOwner = function(owner)
  local out = {}
  for _, v in ipairs(vehicles) do if v.owner == owner then out[#out + 1] = v end end
  return out
end
NZ.Access.getSession = function() return nil end
local function session() return { garageKey = 'G4', groupId = 4, location = location } end
NZ.Access.requireSession = function() return session() end

load_('server/interiors.lua')

-- 3. a new interior from a profile gets its presets; older ones use them on entry ------
local saved = Interiors.save({ name = 'Six car', profile = 'garage_6car', options = {} }, 1)
check(saved and #saved.slots == 6, 'new interior from a profile gets the 6 preset positions')
check(saved and saved.entry and math.abs(saved.entry.x - 207.188) < 0.01, 'new interior arrives at the profile coords')
local custom = Interiors.save({ name = 'Custom', profile = 'garage_6car', slots = { { x = 200, y = -1000, z = -99, w = 90 } } }, 1)
check(custom and #custom.slots == 1, 'positions placed by the admin are kept')
local derived = Interiors.save({ name = 'Level 2', profile = 'ceo_lom_bank_garage_2', entry = { x = -1568, y = -562, z = 85.5, w = 0 } }, 1)
check(derived and #derived.slots == 0, 'presetsFrom profiles get their positions in the creator (not on the server)')

-- an interior saved before presets existed: no slots in the row, profile set
interiorRows[#interiorRows + 1] = { id = 50, name = 'Old ten car', enabled = 1,
  data = { profile = 'garage_10car', options = {}, entry = { x = 228, y = -1003.7, z = -99, w = 0 }, slots = {} } }
json.decode = function(t) return t end
Interiors.load()
check(Interiors.get(50) and #Interiors.get(50).slots == 0, 'stored interior keeps its empty slot list')
check(Interiors.hasSlots(Interiors.get(50)) == true, 'old profile interior without positions has slots (presets)')
check(Interiors.hasSlots({ slots = {} }) == false, 'interior without positions or profile has no slots')
check(Interiors.hasSlots({ profile = 'ceo_lom_bank_garage_2', slots = {} }) == false, 'presetsFrom profile without saved positions has no slots')
check(Interiors.hasSlots(nil) == false, 'hasSlots(nil) is false')
-- the garage menu's "Go inside" check (server/vehicles.lua) uses hasSlots
local menuInterior = Interiors.get(50)
check(menuInterior.enabled ~= false and Interiors.hasSlots(menuInterior), 'garage menu offers "Go inside" for the old interior')
location.access.interiorId = 50

-- 4. per-player instances -------------------------------------------------------------
local data1, err1 = Interiors.enter(1, session())
local data2, err2 = Interiors.enter(2, session())
check(data1 ~= nil, 'owner enters (' .. tostring(err1) .. ')')
check(data2 ~= nil, 'member enters (' .. tostring(err2) .. ')')
if data1 and data2 then
  check(#data1.interior.slots == 10 and data1.slots == 10, 'old interior uses the profile presets (10 positions)')
  check(data1.instanceKey ~= data2.instanceKey, 'each player has an own instance')
  check(buckets[1] ~= 0 and buckets[2] ~= 0 and buckets[1] ~= buckets[2], 'each player has an own routing bucket')
  check(#data1.vehicles == 1 and data1.vehicles[1].plate == 'AAA111', 'owner sees only their own vehicle')
  check(#data2.vehicles == 2 and data2.vehicles[1].plate == 'BBB222', 'member sees only their own vehicles')
  check(data1.role == 'owner' and data2.role == 'owner', 'everybody owns their copy')
  check(data1.canInvite == false and data2.canInvite == false, 'no invitations in per-player mode')
  check(#data1.members == 1, 'nobody else inside')
  local res = callbacks['nz:interior:invite'](1, { serverId = 3 })
  check(res and res.ok == false, 'invite refused in per-player mode')
  res = callbacks['nz:interior:players'](1, {})
  check(res and res.ok == false, 'player list refused in per-player mode')
end
Interiors.leave(1)
Interiors.leave(2)
check((buckets[1] or 0) == 0 and (buckets[2] or 0) == 0, 'leaving restores the public bucket')
check(next(Interiors.instances) == nil, 'empty instances released')

-- 5. shared mode keeps the group instance and invitations ------------------------------
Config.InteriorOptions.instances = 'shared'
local s1 = Interiors.enter(1, session())
local s2 = Interiors.enter(2, session())
check(s1 and s2 and s1.instanceKey == s2.instanceKey, 'shared mode: one instance per group')
check(s1 and #s1.vehicles == 3, 'shared mode: every group vehicle shown')
check(s1 and s1.canInvite == true, 'shared mode: owner may invite')
local res = callbacks['nz:interior:players'](1, {})
check(res and res.ok == true and #res.data == 1 and res.data[1].serverId == 3, 'shared mode: nearby players listed')
res = callbacks['nz:interior:invite'](1, { serverId = 3 })
check(res and res.ok == true, 'shared mode: invitation sent')
Interiors.leave(1)
Interiors.leave(2)
Config.InteriorOptions.instances = 'player'

if #failures > 0 then
  print(('interiors: %d/%d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('interiors: %d checks OK'):format(checks))
