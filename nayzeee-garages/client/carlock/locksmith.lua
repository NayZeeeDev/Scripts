--[[
  nayzeee-garages — car lock: locksmith locations (client, NZ.CarLock). docs/CARLOCK.md §9.

  Config.CarLock.locksmiths (the list index is the id): a blip (blip.enabled), a local NPC at
  the counter (created while the player is within Config.Peds.spawnDistance, frozen,
  invincible, scenario, put on the ground) and the interaction of the interface setting
  settings.interface.interaction like the garages: 'target' (a "Locksmith" option on the NPC,
  ox_target / qb-target), 'prompt' (press the interaction key next to it) or 'both'. Without a
  running target resource the prompt is used.

  The 'locksmith' NUI app lists the services and vehicles the server allows
  ('nz:carlock:locksmith:open'); every service runs on the server
  ('nz:carlock:locksmith:service'), which re-checks the counter distance, the vehicle, the
  rules, money and materials. NUI callbacks:
    locksmith:refresh { locksmithId }                  -> LocksmithOpenData
    locksmith:service { locksmithId, service, plate }  -> { message, data = LocksmithOpenData }
  The window closes when the player walks away from the counter or goes down.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local APP = 'locksmith'
local PROMPT_RADIUS = 2.0        -- m: press-E prompt next to the counter
local TARGET_DISTANCE = 2.5      -- m: target option reach
local LEAVE_DISTANCE = 4.5       -- m: the open window closes beyond this (below the server's counter range, 5 m)
local MODEL_TIMEOUT = 5000

local shops = {}                 -- [id] = shop record
local blips = {}
local promptShop = nil           -- shop whose prompt is shown
local openShop = nil             -- id of the shop whose window is open
local acting = false
local keybind = nil

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function interfaceMode()
  local s = NZ.State.settings
  local mode = type(s) == 'table' and type(s.interface) == 'table' and s.interface.interaction or nil
  if mode ~= 'target' and mode ~= 'both' then mode = 'prompt' end
  if mode ~= 'prompt' and not (type(NZ.Target.available) == 'function' and NZ.Target.available() == true) then
    return 'prompt'
  end
  return mode
end

local function usesPrompt() return interfaceMode() ~= 'target' end
local function usesTarget() return interfaceMode() ~= 'prompt' end

local function spawnDistance()
  local d = tonumber(Config.Peds and Config.Peds.spawnDistance) or 60.0
  return Utils.clamp(d, 20.0, 150.0)
end

local function ready()
  return NZ.State.ready == true and not NZ.NUI.isOpen() and not IsPauseMenuActive() and not NZ.Points.incapacitated()
    and GetVehiclePedIsIn(PlayerPedId(), false) == 0
end

local function currentKey()
  if keybind and keybind.getCurrentKey then
    local ok, key = pcall(keybind.getCurrentKey, keybind)
    if ok and type(key) == 'string' and key:match('^[%w_]+$') then return key end
  end
  return Config.Keys.interact or 'E'
end

local function showPrompt(shop)
  promptShop = shop
  if shop then
    NZ.NUI.prompt(L('Locksmith'), currentKey())
  else
    NZ.NUI.prompt(nil)
  end
end

---------------------------------------------------------------------------------------
-- Opening the window
---------------------------------------------------------------------------------------

local function watch(id, center)
  CreateThread(function()
    while openShop == id and NZ.NUI.isOpen(APP) do
      Wait(500)
      if openShop ~= id or not NZ.NUI.isOpen(APP) then break end
      if #(GetEntityCoords(PlayerPedId()) - center) > LEAVE_DISTANCE or NZ.Points.incapacitated() then
        NZ.NUI.close(APP)
        break
      end
    end
  end)
end

--- Open the locksmith window of shop `id` (yields: server round trip).
---@param id number
---@return boolean
function CarLock.openLocksmith(id)
  local shop = shops[id]
  if not shop or acting or NZ.NUI.isOpen() then return false end
  acting = true
  local res = NZ.NUI.await('nz:carlock:locksmith:open', { id = id })
  acting = false
  if not res.ok then
    NZ.NUI.notify('error', res.error)
    return false
  end
  if NZ.NUI.isOpen() then return false end
  showPrompt(nil)
  openShop = id
  NZ.NUI.open(APP, NZ.Veh.enrichDeep(res.data))
  watch(id, shop.center)
  return true
end

NZ.NUI.onClose(APP, function()
  openShop = nil
end)

local function tryOpen(id)
  CreateThread(function() CarLock.openLocksmith(id) end)
end

---------------------------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------------------------

local function groundZ(c)
  RequestCollisionAtCoord(c.x, c.y, c.z)
  for _ = 1, 10 do
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    if found and math.abs(z - c.z) < 3.0 then return z end
    Wait(100)
  end
  return c.z - 1.0
end

local function targetOptions(shop)
  return {
    {
      label = L('Locksmith'),
      icon = 'fas fa-key',
      distance = TARGET_DISTANCE,
      canInteract = function() return not acting and ready() end,
      onSelect = function() if ready() then tryOpen(shop.id) end end,
    },
  }
end

local function removePed(shop)
  shop.gen = shop.gen + 1
  pcall(NZ.Target.remove, shop.targetId)
  if shop.ped and DoesEntityExist(shop.ped) then
    SetEntityAsMissionEntity(shop.ped, true, true)
    DeleteEntity(shop.ped)
  end
  shop.ped = nil
end

local function spawnPed(shop)
  shop.gen = shop.gen + 1
  local gen = shop.gen
  CreateThread(function()
    local model = type(shop.cfg.ped) == 'string' and shop.cfg.ped ~= '' and shop.cfg.ped or 's_m_m_autoshop_01'
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then
      lib.print.warn(('[nayzeee-garages] locksmith NPC model "%s" does not exist'):format(model))
      if shop.gen == gen and usesTarget() then pcall(NZ.Target.addSphere, shop.targetId, shop.center, TARGET_DISTANCE, targetOptions(shop)) end
      return
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + MODEL_TIMEOUT
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    if shop.gen ~= gen or not HasModelLoaded(hash) then
      SetModelAsNoLongerNeeded(hash)
      return
    end
    local z = groundZ(shop.center)
    if shop.gen ~= gen then
      SetModelAsNoLongerNeeded(hash)
      return
    end
    local c = shop.center
    local ped = CreatePed(4, hash, c.x, c.y, z, shop.heading, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return end
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, shop.heading)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetPedDefaultComponentVariation(ped)
    local scenario = shop.cfg.scenario
    if scenario == nil then scenario = 'WORLD_HUMAN_CLIPBOARD' end
    if type(scenario) == 'string' and scenario ~= '' then TaskStartScenarioInPlace(ped, scenario, 0, true) end
    shop.ped = ped
    if usesTarget() then
      local ok, added = pcall(NZ.Target.addLocalEntity, shop.targetId, ped, targetOptions(shop))
      if not ok or not added then pcall(NZ.Target.addSphere, shop.targetId, shop.center, TARGET_DISTANCE, targetOptions(shop)) end
    end
  end)
end

---------------------------------------------------------------------------------------
-- Points, blips, keybind
---------------------------------------------------------------------------------------

local function addBlip(shop)
  local b = shop.cfg.blip
  if type(b) ~= 'table' or b.enabled == false then return end
  local c = shop.center
  local blip = AddBlipForCoord(c.x, c.y, c.z)
  SetBlipSprite(blip, math.floor(tonumber(b.sprite) or 134))
  SetBlipColour(blip, math.floor(tonumber(b.color) or 3))
  SetBlipScale(blip, (tonumber(b.scale) or 0.7) + 0.0)
  SetBlipAsShortRange(blip, true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(type(shop.cfg.name) == 'string' and shop.cfg.name or L('Locksmith'))
  EndTextCommandSetBlipName(blip)
  blips[#blips + 1] = blip
end

local function build()
  local list = CarLock.cfg().locksmiths
  for id, cfg in ipairs(type(list) == 'table' and list or {}) do
    local c = type(cfg) == 'table' and Utils.v4(cfg.coords) or nil
    if c then
      local shop = {
        id = id, cfg = cfg, center = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), heading = (tonumber(c.w) or 0.0) + 0.0,
        targetId = 'nz_locksmith_' .. id, gen = 0, ped = nil, atCounter = false,
      }
      shops[id] = shop
      addBlip(shop)
      shop.area = lib.points.new({
        coords = shop.center,
        distance = spawnDistance(),
        onEnter = function() spawnPed(shop) end,
        onExit = function() removePed(shop) end,
      })
      shop.counter = lib.points.new({
        coords = shop.center,
        distance = PROMPT_RADIUS,
        onEnter = function()
          shop.atCounter = true
          shop.promptGen = (shop.promptGen or 0) + 1
          local gen = shop.promptGen
          -- the prompt waits until no window is open and the player is on foot
          CreateThread(function()
            while shop.atCounter and shop.promptGen == gen do
              local want = usesPrompt() and ready() and not acting
              if want and promptShop ~= shop then
                showPrompt(shop)
              elseif not want and promptShop == shop then
                showPrompt(nil)
              end
              Wait(250)
            end
            if promptShop == shop then showPrompt(nil) end
          end)
        end,
        onExit = function()
          shop.atCounter = false
          if promptShop == shop then showPrompt(nil) end
        end,
      })
    end
  end
  if next(shops) ~= nil then
    keybind = lib.addKeybind({
      name = 'nz_locksmith',
      description = L('Locksmith'),
      defaultKey = Config.Keys.interact or 'E',
      onPressed = function()
        local shop = promptShop
        if shop and not acting and ready() then tryOpen(shop.id) end
      end,
    })
  end
end

if CarLock.enabled() then
  CreateThread(function()
    local ok, err = pcall(build)
    if not ok then lib.print.error(('[nayzeee-garages] locksmiths failed: %s'):format(tostring(err))) end
  end)
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

local function shopId(data)
  local id = tonumber(type(data) == 'table' and data.locksmithId or nil)
  if not id or id ~= math.floor(id) or not shops[math.tointeger(id)] then return nil end
  return math.tointeger(id)
end

NZ.NUI.register('locksmith:refresh', function(data)
  local id = shopId(data)
  if not id then return Utils.fail(L('Invalid request')) end
  local res = NZ.NUI.await('nz:carlock:locksmith:open', { id = id })
  if res.ok then res.data = NZ.Veh.enrichDeep(res.data) end
  return res
end)

NZ.NUI.register('locksmith:service', function(data)
  local id = shopId(data)
  local plate = Utils.plate(data.plate)
  local service = data.service
  if not id or not plate or (service ~= 'duplicate' and service ~= 'program' and service ~= 'rekey') then
    return Utils.fail(L('Invalid request'))
  end
  local res = NZ.NUI.await('nz:carlock:locksmith:service', { id = id, service = service, plate = plate })
  if res.ok and type(res.data) == 'table' and type(res.data.data) == 'table' then
    res.data.data = NZ.Veh.enrichDeep(res.data.data)
  end
  return res
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for _, shop in pairs(shops) do
    if shop.ped and DoesEntityExist(shop.ped) then DeleteEntity(shop.ped) end
  end
  for i = 1, #blips do
    if DoesBlipExist(blips[i]) then RemoveBlip(blips[i]) end
  end
end)
