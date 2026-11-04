--[[
  nayzeee-garages — car sale contracts (client): NZ.Contracts. docs/CARLOCK.md §12.

  Shows the `contract` app; the server decides everything.
    'nz:client:contract:open'   data = ContractOpenData (draft for the seller after a blank
                                contract use, review for the buyer, view of a signed copy)
    'nz:client:contract:status' { contractId, status }: the outcome of the contract shown
                                ('signed' | 'declined' | 'expired' | 'withdrawn' | 'cancelled' |
                                'failed'), pushed into the open window ('update')
  NUI callbacks forwarded 1:1 to the server: contract:refresh, contract:send, contract:sign,
  contract:decline. Closing a contract you were asked to sign declines it.
]]

local Contracts = NZ.Contracts

local APP = 'contract'
local DRIVE_SPEED = 3.0       -- m/s: a driver going faster gets the review once stopped

local current = nil           -- { id, role = 'seller'|'buyer'|'reader', status }
local opening = 0             -- generation of the newest open request

local function notify(kind, message)
  if type(message) == 'string' and message ~= '' then NZ.NUI.notify(kind, message) end
end

local function enrich(data)
  if NZ.Veh and type(NZ.Veh.enrichDeep) == 'function' then
    local ok, res = pcall(NZ.Veh.enrichDeep, data)
    if ok and type(res) == 'table' then return res end
  end
  return data
end

local function driving()
  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  return vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and GetEntitySpeed(vehicle) > DRIVE_SPEED
end

local function show(data)
  if data.mode == 'review' then
    current = { id = data.contractId, role = 'buyer', status = 'pending' }
  elseif data.mode == 'draft' then
    current = { id = nil, role = 'seller', status = 'draft' }
  else
    current = { id = data.contractId, role = 'reader', status = 'view' }
  end
  NZ.NUI.open(APP, enrich(data))
end

RegisterNetEvent('nz:client:contract:open', function(data)
  if type(data) ~= 'table' or (data.mode ~= 'draft' and data.mode ~= 'review' and data.mode ~= 'view') then return end
  opening = opening + 1
  local generation = opening
  if data.mode ~= 'review' or not driving() then
    show(data)
    return
  end
  -- never take the controls of a moving driver: the review opens once the vehicle stops
  notify('info', L('Stop your vehicle to read the contract'))
  CreateThread(function()
    local deadline = GetGameTimer() + math.max(5, tonumber(data.expiresIn) or 60) * 1000
    while driving() and GetGameTimer() < deadline do Wait(250) end
    if generation ~= opening or GetGameTimer() >= deadline then return end
    data.expiresIn = math.max(0, math.floor((deadline - GetGameTimer()) / 1000))
    show(data)
  end)
end)

RegisterNetEvent('nz:client:contract:status', function(data)
  if type(data) ~= 'table' or type(data.contractId) ~= 'string' or type(data.status) ~= 'string' then return end
  if not current or current.id ~= data.contractId then return end
  current.status = data.status
  if NZ.NUI.isOpen(APP) then NZ.NUI.send('update', { app = APP, data = { status = data.status } }) end
end)

NZ.NUI.forward('contract:refresh')

NZ.NUI.forward('contract:send', function(result)
  if result.ok and type(result.data) == 'table' and current and current.role == 'seller' then
    current.id = result.data.contractId
    current.status = 'pending'
  end
end)

NZ.NUI.forward('contract:sign', function(result)
  if current and current.role == 'buyer' then current.status = result.ok and 'signed' or 'failed' end
end)

NZ.NUI.forward('contract:decline', function(result)
  if not result.ok or not current then return end
  current.status = current.role == 'buyer' and 'declined' or 'withdrawn'
  if current.role == 'seller' then current.id = nil end
end)

-- Closing the review is a "no": the seller hears about it at once instead of at expiry.
NZ.NUI.onClose(APP, function()
  local closed = current
  current = nil
  if closed and closed.role == 'buyer' and closed.status == 'pending' and closed.id then
    CreateThread(function()
      local result = NZ.NUI.await('nz:contract:decline', { contractId = closed.id })
      if result.ok then notify('info', L('You declined the contract')) end
    end)
  end
end)

--- The contract shown right now (diagnostics): { id, role, status } | nil.
---@return table|nil
function Contracts.current()
  if not current then return nil end
  return { id = current.id, role = current.role, status = current.status }
end
