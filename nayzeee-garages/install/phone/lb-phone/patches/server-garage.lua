--[[
  nayzeee-garages: OPTIONAL patch for lb-phone/server/apps/framework/garage.lua
  (an escrow_ignore'd, editable lb-phone file; keep a backup).

  WHY      lb-phone's "garage:valetVehicle" calls GetVehicle (= nayzeee's
           ClaimVehicleForValet, which marks the vehicle out) BEFORE it takes the valet
           price and before it creates the server vehicle / driver. When one of those later
           steps fails, lb-phone refunds the money but nothing puts the vehicle back: without
           this patch nayzeee does it itself after Config.Phone.claimTimeout (60 s); with it,
           at once. Part B makes the Garage app's "mark" button point at the garage or impound
           of a vehicle that is not out (lb-phone alone only finds vehicles in the world).
  CONFIRMED against lb-phone 2.9.0 (github.com/lbphone/files): the "garage:valetVehicle" and
           "garage:findCar" callbacks, their failure branches and locals (source, plate).

  -----------------------------------------------------------------------------------------
  A) Paste the two helper functions below near the top of the file (after lb-phone's
     `local function IsVehicleOut(...) ... end`):
]]

-- context only (the callbacks' arguments in lb-phone); do NOT paste this line:
local source, plate = ...

-- >>> A) helpers
local NAYZEEE = "nayzeee-garages"

--- Put a vehicle claimed by GetVehicle back in its garage (the valet could not deliver it).
local function NayzeeeRelease(source, plate)
    if GetResourceState(NAYZEEE) ~= "started" then return end
    pcall(function()
        exports[NAYZEEE]:ReleaseValetClaim(source, plate)
    end)
end

--- Garage / impound position of one of the player's vehicles that is not in the world.
local function NayzeeeVehicleCoords(source, plate)
    if GetResourceState(NAYZEEE) ~= "started" or type(plate) ~= "string" then return nil end
    local ok, list = pcall(function()
        return exports[NAYZEEE]:GetPhoneVehicles(source)
    end)
    if not ok or type(list) ~= "table" then return nil end
    local wanted = plate:gsub("%s+", ""):upper()
    for i = 1, #list do
        local v = list[i]
        if type(v) == "table" and type(v.plate) == "string" and v.plate:gsub("%s+", "") == wanted then
            local c = v.coords
            if type(c) == "table" and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then
                return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
            end
            return nil
        end
    end
    return nil
end
-- <<<

--[[
  B) In BaseCallback("garage:findCar", ...), above `SendNotification(phoneNumber, {` add:
]]

-- >>> B) paste in "garage:findCar" above its SendNotification
local nayzeeeCoords = NayzeeeVehicleCoords(source, plate)
if nayzeeeCoords then
    return nayzeeeCoords
end
-- <<<

--[[
  C) In BaseCallback("garage:valetVehicle", ...) add this line in the three failure branches
     that come AFTER `local vehicleData = GetVehicle(source, plate)` (shown below):
]]

-- >>> C) paste in each of the three branches
NayzeeeRelease(source, plate)
-- <<<

--[[

        if Config.Valet.Price and not RemoveMoney(source, Config.Valet.Price) then
            NayzeeeRelease(source, plate)                     -- <<< add
            SendNotification(phoneNumber, { ... NO_MONEY ... })
            return
        end

        if not vehicle then                                   -- CreateServerVehicle failed
            AddMoney(source, Config.Valet.Price)
            NayzeeeRelease(source, plate)                     -- <<< add
            debugprint("Failed to create vehicle")
            return
        end

        if not ped then                                       -- CreateServerPed failed
            AddMoney(source, Config.Valet.Price)
            DeleteEntity(vehicle)
            NayzeeeRelease(source, plate)                     -- <<< add (after DeleteEntity)
            debugprint("Failed to create ped")
            return
        end

  Do NOT report the server-created vehicle from this file (MarkValetSpawned): its plate is
  only applied by the client after this callback returns. patches/client-garage.lua reports
  it from BringCar in both spawn modes.
]]
