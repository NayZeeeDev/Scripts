--[[
  nayzeee-garages <-> bcs_housing (BagusCodeStudio).            Support: automatic, optional edit (both)

  Without any edit nayzeee-garages reads every bcs_housing home through its exports (GetHomes:
  owner, the garage point data.garage; GetKeyHolders + HasKey(home, identifier, 'Garage') for key
  holders) and draws its own garage point there.

  This optional edit makes bcs_housing's own garage prompt open nayzeee-garages instead.

  WHERE IT GOES
    bcs_housing/client/garage.lua (newer builds may have it under modules/integration/garage/):
    replace the body of the function GaragePrompt(data, identifier) with the one below, and put
    the `local nzPromptActive = false` line above the function. Keep your copy's own declaration
    line (`function GaragePrompt(...)` or `local function GaragePrompt(...)`); it is shown below as
    `function _G.GaragePrompt`, the same as a global function.
    Then add  set nayzeee_housing_hooked "bcs_housing"  to server.cfg so nayzeee-garages does not
    draw a second point at the same garage.

  HOW IT WORKS
    When bcs_housing shows the garage prompt of home <identifier>, this shows a help text and on E
    opens the nayzeee-garages menu of house 'bcs:<identifier>' (stores the vehicle when the player
    drives). It works whether bcs calls GaragePrompt every frame or once when the player arrives:
    the prompt stays while the player is within 6 m of where it started. The server checks access
    with bcs_housing (HasKey 'Garage' permission, owner) and, when it could not read the home's
    garage point, places the garage there (server-side position, near the entrance).

  UNCONFIRMED (low confidence)
    bcs_housing is escrowed and its documentation could not be opened while writing this: the
    file, the function name, its arguments (data = the client Home object, identifier = the home
    id) and the call cadence are from documentation excerpts. Check your copy before replacing.
]]

local nzPromptActive = false

function _G.GaragePrompt(data, identifier)
    if nzPromptActive or identifier == nil then return end
    if GetResourceState('nayzeee-garages') ~= 'started' then return end
    nzPromptActive = true
    CreateThread(function()
        local houseId = 'bcs:' .. tostring(identifier)
        local origin = GetEntityCoords(PlayerPedId())
        while true do
            local ped = PlayerPedId()
            if #(GetEntityCoords(ped) - origin) > 6.0 or IsEntityDead(ped) then break end
            local inVehicle = IsPedInAnyVehicle(ped, false)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(inVehicle and '~INPUT_CONTEXT~ Store vehicle' or '~INPUT_CONTEXT~ Open garage')
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustReleased(0, 38) then
                -- OpenHouseGarage stores the vehicle instead when the player is driving.
                local ok, err = pcall(function() return exports['nayzeee-garages']:OpenHouseGarage(houseId) end)
                if not ok then print(('[bcs_housing] nayzeee-garages garage failed: %s'):format(tostring(err))) end
                Wait(1500)
            end
            Wait(0)
        end
        nzPromptActive = false
    end)
end
