--[[
  nayzeee-garages — police dispatch integration (client): NZ.Dispatch. docs/CARLOCK.md §6.
  Open file: edit the CUSTOM adapter below (Config.CarLock.dispatch.system = 'custom').

  Two server events, both carrying an alert the SERVER built (bridge/server/dispatch.lua):
    'nz:client:dispatch'        on the offender's client, for dispatch resources whose API is
                                client side (ps-dispatch 2.x CustomAlert, cd_dispatch
                                GetPlayerInfo + AddNotification, custom). The payload decides the
                                system, the jobs and the position; this file only adds the street
                                name and the model label. A system that fails here is reported
                                back once ('nz:dispatch:failed') and the server sends the alert
                                through 'internal' instead. (qs-dispatch, ps-dispatch 3.x and the
                                others are sent by the server: bridge/server/dispatch.lua.)
    'nz:client:dispatch:alert'  'internal' system, on the clients of on-duty officers: a
                                notification and a temporary map blip (+ radius, sound). Street
                                and model text the offender's client sent is replaced by this
                                client's own lookup (streetFromClient / modelFromClient).
]]

local Dispatch = NZ.Dispatch
local Utils = NZ.Utils

---------------------------------------------------------------------------------------
-- CUSTOM ADAPTER (client) — used when Config.CarLock.dispatch.system = 'custom' and the server
-- adapter sets CUSTOM.client = true. Runs on the offender's client. Return false when it
-- could not send (the server then uses 'internal').
---------------------------------------------------------------------------------------

local CUSTOM = {
  client = function(alert) -- luacheck: ignore 212
    -- Example:
    -- exports.my_dispatch:SendAlert({ coords = vector3(alert.coords.x, alert.coords.y, alert.coords.z),
    --   title = alert.code .. ' - ' .. alert.title, message = alert.message, jobs = alert.jobs })
    -- return true
    return false
  end,
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local MAX_BLIPS = 24
local FADE_SHARE = 0.25          -- the last quarter of a blip's life fades out

local blips = {}                 -- { { blip, radius, expires, total } }

local function vec(c) return vector3((tonumber(c.x) or 0.0) + 0.0, (tonumber(c.y) or 0.0) + 0.0, (tonumber(c.z) or 0.0) + 0.0) end
local function minutes(seconds) return math.max(1, math.ceil((tonumber(seconds) or 60) / 60)) end

--- "Street / Crossing" at a position, or nil.
---@param coords table {x,y,z}
---@return string|nil
function Dispatch.streetAt(coords)
  if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return nil end
  local ok, street, crossing = pcall(GetStreetNameAtCoord, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
  if not ok then return nil end
  local a = street and street ~= 0 and GetStreetNameFromHashKey(street) or nil
  local b = crossing and crossing ~= 0 and GetStreetNameFromHashKey(crossing) or nil
  if a == '' then a = nil end
  if b == '' then b = nil end
  if a and b then return ('%s / %s'):format(a, b) end
  return a or b
end

--- "Karin Sultan" of a model hash, or nil.
---@param hash number|nil
---@return string|nil
function Dispatch.modelLabel(hash)
  hash = tonumber(hash)
  if not hash then return nil end
  if NZ.Veh and type(NZ.Veh.label) == 'function' then
    local ok, label = pcall(NZ.Veh.label, hash)
    if ok and type(label) == 'string' and label ~= '' then return label end
  end
  local ok, name = pcall(GetDisplayNameFromVehicleModel, hash)
  if not ok or type(name) ~= 'string' or name == '' or name == 'CARNOTFOUND' then return nil end
  local label = GetLabelText(name)
  if type(label) ~= 'string' or label == '' or label == 'NULL' then return name end
  return label
end

--- Fill the details a client knows better than the server (street, model label). Text the
--- offender's client sent (streetFromClient / modelFromClient) is replaced by this client's own
--- lookup at the server's position and model hash whenever it finds one.
local function complete(alert)
  if alert.streetFromClient or not alert.street then
    alert.street = Dispatch.streetAt(alert.coords) or alert.street
  end
  if alert.modelFromClient or not alert.model then
    local own = Dispatch.modelLabel(alert.modelHash)
    if own and type(alert.model) == 'string' and alert.model ~= '' and own ~= alert.model
      and type(alert.message) == 'string' then
      -- the server built the message with the offender's label: show ours there too. The
      -- message reads '{color} {model} · plate {plate}', so search after the colour (a crafted
      -- label that matches part of the colour must not rewrite the colour)
      local from = 1
      if type(alert.color) == 'string' and alert.color ~= '' then
        local _, ce = alert.message:find(alert.color, 1, true)
        if ce then from = ce + 1 end
      end
      local i, j = alert.message:find(alert.model, from, true)
      if i then alert.message = alert.message:sub(1, i - 1) .. own .. alert.message:sub(j + 1) end
    end
    alert.model = own or alert.model
  end
  return alert
end

local function report(name, alert, ok, reason)
  local id = tonumber(alert.id)
  if not id then return end
  lib.callback(ok and 'nz:dispatch:sent' or 'nz:dispatch:failed', false, function() end,
    { id = id, reason = not ok and tostring(reason or name) or nil })
end

---------------------------------------------------------------------------------------
-- Offender-side delivery
---------------------------------------------------------------------------------------

local CLIENT = {}

CLIENT['ps-dispatch'] = function(alert)
  exports['ps-dispatch']:CustomAlert({
    message = alert.title, information = alert.message, dispatchCode = 'nz_' .. tostring(alert.kind),
    code = alert.code, icon = 'fas fa-car', priority = alert.priority, coords = vec(alert.coords),
    model = alert.model, plate = alert.plate, firstColor = alert.color,
    radius = alert.blip.radius, sprite = alert.blip.sprite, color = alert.blip.color, scale = alert.blip.scale,
    length = minutes(alert.blip.seconds), flash = alert.blip.flash, offset = false, jobs = alert.jobs,
  })
  return true
end

CLIENT.cd_dispatch = function(alert)
  local resource = alert.resource == 'cd_dispatch3d' and 'cd_dispatch3d' or 'cd_dispatch'
  local okInfo, info = pcall(function() return exports[resource]:GetPlayerInfo(vec(alert.coords)) end)
  local uniqueId = okInfo and type(info) == 'table' and info.unique_id or nil
  TriggerServerEvent('cd_dispatch:AddNotification', {
    job_table = alert.jobs, coords = vec(alert.coords), title = ('%s - %s'):format(alert.code, alert.title),
    message = alert.street and ('%s · %s'):format(alert.message, alert.street) or alert.message,
    flash = alert.priority == 1 and 1 or 0,
    unique_id = uniqueId or tostring(math.random(1000000, 9999999)), sound = 1,
    blip = { sprite = alert.blip.sprite, scale = alert.blip.scale, colour = alert.blip.color, flashes = alert.blip.flash,
      text = alert.title, time = minutes(alert.blip.seconds), radius = alert.blip.radius },
  })
  return true
end

CLIENT.custom = function(alert)
  return CUSTOM.client(alert) ~= false
end

local function validAlert(alert)
  return type(alert) == 'table' and type(alert.coords) == 'table' and type(alert.blip) == 'table'
    and type(alert.jobs) == 'table' and type(alert.title) == 'string'
end

RegisterNetEvent('nz:client:dispatch', function(alert)
  if not validAlert(alert) then return end
  local system = alert.system
  local send = CLIENT[system]
  if not send then return report(system, alert, false, 'no client adapter') end
  if system ~= 'custom' and alert.resource and not Utils.resourceStarted(alert.resource) then
    return report(system, alert, false, alert.resource .. ' is not started on this client')
  end
  local ok, res = pcall(send, complete(alert))
  report(system, alert, ok and res ~= false, not ok and res or nil)
end)

---------------------------------------------------------------------------------------
-- 'internal': notification + blip for on-duty officers
---------------------------------------------------------------------------------------

local function removeBlip(entry)
  if entry.blip and DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
  if entry.radius and DoesBlipExist(entry.radius) then RemoveBlip(entry.radius) end
end

local fader = false

local function startFader()
  if fader then return end
  fader = true
  CreateThread(function()
    while #blips > 0 do
      local now = GetGameTimer()
      for i = #blips, 1, -1 do
        local entry = blips[i]
        local left = entry.expires - now
        if left <= 0 then
          removeBlip(entry)
          table.remove(blips, i)
        elseif left < entry.total * FADE_SHARE then
          local share = left / (entry.total * FADE_SHARE)
          if DoesBlipExist(entry.blip) then SetBlipAlpha(entry.blip, math.floor(255 * share)) end
          if entry.radius and DoesBlipExist(entry.radius) then SetBlipAlpha(entry.radius, math.floor(90 * share)) end
        end
      end
      Wait(1000)
    end
    fader = false
  end)
end

local function addBlip(alert)
  local c, b = alert.coords, alert.blip
  local x, y, z = (tonumber(c.x) or 0.0) + 0.0, (tonumber(c.y) or 0.0) + 0.0, (tonumber(c.z) or 0.0) + 0.0
  local seconds = Utils.clamp(tonumber(b.seconds) or 90, 5, 3600)
  local entry = { expires = GetGameTimer() + seconds * 1000, total = seconds * 1000 }
  local radius = tonumber(b.radius) or 0.0
  if radius > 0.0 then
    entry.radius = AddBlipForRadius(x, y, z, radius + 0.0)
    SetBlipColour(entry.radius, math.floor(tonumber(b.color) or 1))
    SetBlipAlpha(entry.radius, 90)
  end
  local blip = AddBlipForCoord(x, y, z)
  entry.blip = blip
  SetBlipSprite(blip, math.floor(tonumber(b.sprite) or 225))
  SetBlipColour(blip, math.floor(tonumber(b.color) or 1))
  SetBlipScale(blip, (tonumber(b.scale) or 1.0) + 0.0)
  SetBlipFlashes(blip, b.flash ~= false)
  SetBlipAsShortRange(blip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(('%s · %s'):format(tostring(alert.code or ''), tostring(alert.title or '')))
  EndTextCommandSetBlipName(blip)
  blips[#blips + 1] = entry
  while #blips > MAX_BLIPS do
    removeBlip(blips[1])
    table.remove(blips, 1)
  end
  startFader()
end

RegisterNetEvent('nz:client:dispatch:alert', function(alert)
  if type(alert) ~= 'table' or type(alert.coords) ~= 'table' or type(alert.blip) ~= 'table' then return end
  complete(alert)
  local title = ('%s · %s'):format(tostring(alert.code or ''), tostring(alert.title or ''))
  local message = tostring(alert.message or '')
  if alert.street then message = ('%s\n%s'):format(message, alert.street) end
  NZ.NUI.notify('warning', message, title)
  local ok, err = pcall(addBlip, alert)
  if not ok then Utils.debug(('dispatch: blip failed: %s'):format(tostring(err))) end
  if alert.sound ~= false then
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', true)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for _, entry in ipairs(blips) do removeBlip(entry) end
  blips = {}
end)
