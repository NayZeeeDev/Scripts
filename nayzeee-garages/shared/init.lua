--[[
  nayzeee-garages — shared bootstrap: the NZ namespace, translation helper and locale table.
  Loaded first on both sides. Every other file adds functions to the tables declared here.
]]

NZ = {
  ResourceName = GetCurrentResourceName(),
  IsServer = IsDuplicityVersion(),
  Utils = {},
  CarLock = {},
  Inventory = {},
  Dispatch = {},
  Contracts = {},
  FakePlates = {},
  Tow = {},
  Framework = 'standalone',
}

if NZ.IsServer then
  NZ.Bridge = {}
  NZ.KeysServer = {}
  NZ.Housing = {}
  NZ.Logs = {}
  NZ.DB = {}
  NZ.Settings = {}
  NZ.Locations = {}
  NZ.Access = {}
  NZ.Vehicles = {}
  NZ.Actions = {}
  NZ.Impound = {}
  NZ.Jobs = {}
  NZ.Private = {}
  NZ.Interiors = {}
  NZ.Admin = {}
  NZ.Import = {}
  NZ.Phone = {}
else
  NZ.Bridge = {}
  NZ.Keys = {}
  NZ.Fuel = {}
  NZ.Target = {}
  NZ.Notify = {}
  NZ.Peds = {}
  NZ.NUI = {}
  NZ.Points = {}
  NZ.Garage = {}
  NZ.ImpoundClient = {}
  NZ.JobsClient = {}
  NZ.PrivateClient = {}
  NZ.Veh = {}
  NZ.Damage = {}
  NZ.Placement = {}
  NZ.Camera = {}
  NZ.Preview = {}
  NZ.Interior = {}
  NZ.Creator = {}
  NZ.AdminClient = {}
  NZ.State = {
    ready = false,
    locations = {},
    settings = {},
    groups = {},
    houses = {},
    job = nil,
    gang = nil,
  }
end

-- Translation tables: locales/<lang>.lua fill Locales['<lang>'] = { ['English'] = 'Translation' }
Locales = {}

--- Translate an English source string. Placeholders use {name}.
---@param text string
---@param vars table|nil
---@return string
function L(text, vars)
  local dict = Locales[Config.Locale]
  local out = (dict and dict[text]) or text
  if vars then
    out = out:gsub('{(%w+)}', function(k)
      local v = vars[k]
      if v == nil then return '{' .. k .. '}' end
      return tostring(v)
    end)
  end
  return out
end
