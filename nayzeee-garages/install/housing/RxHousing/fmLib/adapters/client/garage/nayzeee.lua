--[[
  nayzeee-garages <-> RxHousing (RX Scripts) through fmLib's garage adapter.   Support: both

  nayzeee-garages reads every RxHousing property (GetAllProperties: owner + key holders) by
  itself. RxHousing hands its garage markers to RX's library fmLib (FM.garage.open /
  FM.garage.parkVehicle); this adapter routes those calls to nayzeee-garages.

  WHERE IT GOES
    fmLib/adapters/client/garage/nayzeee.lua      (fmLib, not RxHousing; fmLib loads every file
    of adapters/client/** by itself, no manifest or settings.lua edit needed)

  WHAT TO SET
    Nothing in RxHousing. Restart fmLib and RxHousing after copying the file. The adapter puts
    nayzeee-garages first in fmLib's garage detection, so every RX script that opens a garage
    through fmLib uses nayzeee-garages while it runs. Updating fmLib by replacing its folder
    removes this file: copy it again.
    Optional: when RxHousing shows its own garage markers for properties that also have a garage
    point nayzeee-garages can read (coords.garage), add  set nayzeee_housing_hooked "RxHousing"
    to server.cfg so nayzeee-garages does not draw a second one.

  HOW IT WORKS
    FM.garage.open(garageId, coords) opens the nayzeee-garages menu of house 'rx:<property id>';
    FM.garage.parkVehicle(garageId) stores the vehicle the player drives there. The server checks
    access with RxHousing (HasKey, owner) and places the garage where the marker is used
    (server-side position) when the property has no garage point of its own.

  UNCONFIRMED
    That RxHousing's (escrowed) garage markers call FM.garage at all, and the garageId it passes.
    Numbers, 'rx:<id>' and names that contain "house", "housing" or "property" and end in the
    property id ('property_12', 'house-12', 'rxhousing_12') are understood; anything else (for example another RX script's
    'rx_police_2') falls back to the nearest nayzeee-garages garage.
]]

local RESOURCE = 'nayzeee-garages'

-- First in fmLib's garage detection (first started resource wins).
do
    local list = type(AdapterResources) == 'table' and AdapterResources.garage or nil
    if type(list) == 'table' then
        local present = false
        for _, entry in ipairs(list) do
            if type(entry) == 'table' and entry.key == 'nayzeee' then present = true break end
        end
        if not present then table.insert(list, 1, { key = 'nayzeee', resource = RESOURCE }) end
    end
end

local warned = false

--- 'rx:<id>' from a property id ('012' and 12.0 become 'rx:12').
local function rxId(value)
    local n = math.tointeger(tonumber(value))
    if not n or n < 1 then return nil end
    return ('rx:%d'):format(n)
end

--- 'rx:<id>' house id from what RxHousing passes (nil when it is not a property id).
local function houseIdOf(garageId)
    if type(garageId) == 'number' then return rxId(garageId) end
    if type(garageId) ~= 'string' then return nil end
    local digits = garageId:match('^rx:(%d+)$') or garageId:match('^%s*(%d+)%s*$')
    if digits then return rxId(digits) end
    -- 'property_12', 'house-12', 'House Garage (12)', 'rxhousing_12': the trailing number, only
    -- for names that say they are a house / housing / property (other RX scripts' are not).
    local lower = garageId:lower()
    if lower:find('hous', 1, true) or lower:find('propert', 1, true) then
        digits = lower:match('(%d+)%)?%s*$')
        if digits then return rxId(digits) end
    end
    return nil
end

local function call(fn, fallback, garageId)
    if GetResourceState(RESOURCE) ~= 'started' then return false end
    local houseId = houseIdOf(garageId)
    if not houseId and not warned then
        warned = true
        print(('[fmLib] nayzeee-garages adapter: unknown garage id %q, using the nearest garage'):format(tostring(garageId)))
    end
    local ok, res = pcall(function()
        if houseId then return exports[RESOURCE][fn](exports[RESOURCE], houseId) end
        return exports[RESOURCE][fallback](exports[RESOURCE])
    end)
    if not ok then
        print(('[fmLib] nayzeee-garages %s failed: %s'):format(fn, tostring(res)))
        return false
    end
    return res == true
end

local adapter = {}

function adapter.init(resource)
    if type(resource) == 'string' and resource ~= '' then RESOURCE = resource end
end

function adapter.open(garageId)
    call('OpenHouseGarage', 'OpenGarage', garageId)
end

--- true = the request was accepted (the result is shown to the player by nayzeee-garages).
function adapter.parkVehicle(garageId)
    return call('StoreHouseGarage', 'StoreVehicle', garageId)
end

-- fmLib looks adapters up as globals named FM_Adapter_<side>_<category>_<key>.
_G.FM_Adapter_client_garage_nayzeee = adapter
