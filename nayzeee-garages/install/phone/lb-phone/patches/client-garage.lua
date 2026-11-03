--[[
  nayzeee-garages: OPTIONAL patch for lb-phone/client/apps/framework/garage.lua
  (an escrow_ignore'd, editable lb-phone file; keep a backup).

  WHY      With the vehicles.lua adapter alone nayzeee finds the valet vehicle by its plate
           within ~2 s, and puts a vehicle that never appears back in its garage after
           Config.Phone.claimTimeout (60 s). These two lines report the result at once:
           the vehicle is tracked immediately (keys from server-side key systems, duplicate
           protection, storing it later), and a failed delivery goes back at once.
  WORKS    for both Config.ServerSideSpawn = false and true (BringCar runs in both modes).
  CONFIRMED against lb-phone 2.9.0 (github.com/lbphone/files): local function BringCar(data, cb),
           its locals `plate` and `vehicle`, and the existing jg-advancedgarages line.

  -----------------------------------------------------------------------------------------
  1) In BringCar, find this block (the vehicle could not be created):

        if not vehicle or not DoesEntityExist(vehicle) then
            debugprint("BringCar: vehicle does not exist")
            return cb(false)
        end

     and add the marked line ABOVE `return cb(false)`:
]]

-- context only (lb-phone's locals inside BringCar); do NOT paste this line:
local plate, vehicle = ...

-- >>> 1) paste above `return cb(false)` in the block shown above
if GetResourceState("nayzeee-garages") == "started" then
    TriggerServerEvent("nz:phone:failed", plate)
end
-- <<<

--[[
  2) Right after that block, next to lb-phone's existing

        if GetResourceState("jg-advancedgarages") == "started" then ... end

     add:
]]

-- >>> 2) paste after the block shown above
if GetResourceState("nayzeee-garages") == "started" then
    TriggerServerEvent("nz:phone:spawned", plate, VehToNet(vehicle))
end
-- <<<

--[[
  3) (only with Config.ServerSideSpawn = true) In BringCar, the server could not create the
     vehicle / driver:

        if not vehNetId or (Config.Valet.Drive and not pedNetId) then
            debugprint("BringCar: Server did not create vehicle/ped (no vehNetId/pedNetId)")
            return cb(false)
        end

     add the same line as in 1) above `return cb(false)`. (patches/server-garage.lua does the
     same on the server side; either one is enough, both are harmless.)

  The server checks every report: only the player who requested the valet can report, the
  entity must carry the vehicle's plate and model, and a failure report is refused while
  any copy of the vehicle exists.
]]
