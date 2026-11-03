--[[
  nayzeee-garages <-> nolag_properties (NoLag / TeamsGG) garage adapter.   Support: hook file (required)

  WHERE IT GOES
    Copy this file to  nolag_properties/custom/garages/nayzeee-garages.lua
    (nolag loads every file of that folder as a shared script; this one only does something
    when it is the selected garage).

  WHAT TO SET
    1. nolag_properties/config.lua:  Garage = "nayzeee-garages",
       ("auto" never picks nayzeee-garages: its detection list is fixed.)
    2. server.cfg: ensure nayzeee-garages before nolag_properties.
    3. In game, owners place the "Garage" interaction point of their property (property menu ->
       interactable points), outside, where vehicles can stop.

  HOW IT WORKS
    nolag draws the point (zone / target, keys required) and calls onSelect below. On foot it
    opens the nayzeee-garages menu of house 'nolag:<property id>'; in a vehicle it stores it.
    The server asks nolag_properties who may use it (GetPropertyData owner / renter, society job,
    HasKey) and places the garage where the point is used (server-side position, never the
    client's coordinates); nayzeee-garages draws no marker / target of its own for these houses.
    Moving the point moves the garage the next time it is used there.

  POLICE LOCKDOWN
    This adapter refuses a locked-down property (metadata.lockdown) unless nolag's
    Config.PoliceLockdown.DisableGarage is false; the nayzeee-garages server refuses it too. If
    you set DisableGarage = false, also add  set nayzeee_housing_nolag_lockdown 0  to server.cfg.

  UNCONFIRMED
    Written for nolag_properties 2.4.x (adapter interface of its bundled garage files). On 3.x
    check that custom/garages still exists. The lockdown fields are read defensively.
]]

if Config == nil or Config.Garage ~= 'nayzeee-garages' then
    return
end

local RESOURCE = 'nayzeee-garages'

local function underLockdown(property)
    local meta = type(property) == 'table' and property.metadata or nil
    local lockdown = type(Config.PoliceLockdown) == 'table' and Config.PoliceLockdown or {}
    return type(meta) == 'table' and meta.lockdown and lockdown.DisableGarage ~= false
end

local function notify(message)
    if type(Framework) == 'table' and type(Framework.Notify) == 'function' then
        pcall(Framework.Notify, { description = message, type = 'error' })
    else
        print(('[nolag_properties] %s'):format(message))
    end
end

Config.Functions = Config.Functions or {}
Config.Functions['OpenGarageMenu'] = {
    type = 'outside',     -- placed outside the property
    zone = true,          -- a zone: works from inside a vehicle (targets do not)
    maxPerProperty = 1,
    radius = 3.0,
    requireKeys = true,
    label = 'Garage',
    icon = 'fas fa-warehouse',
    onSelect = function(property)
        if IsDuplicityVersion() then return end
        if type(property) ~= 'table' or property.id == nil then return end
        if underLockdown(property) then
            notify(type(locale) == 'function' and locale('property_under_police_lockdown') or 'This property is under police lockdown')
            return
        end
        if GetResourceState(RESOURCE) ~= 'started' then
            notify('The garage is not available right now')
            return
        end
        -- nolag ids are integers (21.0 and '21' both become 'nolag:21').
        local houseId = ('nolag:%s'):format(tostring(math.tointeger(tonumber(property.id)) or property.id))
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local ok, err = pcall(function()
            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                exports[RESOURCE]:StoreHouseGarage(houseId)
            else
                exports[RESOURCE]:OpenHouseGarage(houseId, { name = property.label })
            end
        end)
        if not ok then print(('[nolag_properties] nayzeee-garages garage failed: %s'):format(tostring(err))) end
    end,
}
