--[[
  nayzeee-garages <-> tk_housing (TK Scripts) garage hook.            Support: hook edit (required)

  This is NOT a drop-in file: it replaces one function inside tk_housing's editable client file.

  WHERE IT GOES
    tk_housing/client/main_editable.lua: find the function OpenGarageMenu (it receives the
    property index / id) and replace its BODY with the body below. Keep the declaration line your
    copy has (if it is a local function, keep it local).

  WHAT TO SET
    In tk_housing's config turn on the custom garage menu option (reported as
    Config.UseCustomGarageMenu = true; the exact name may differ in your version), so tk_housing
    calls OpenGarageMenu instead of its built-in garage. server.cfg: ensure nayzeee-garages before
    tk_housing.

  HOW IT WORKS
    tk_housing draws its garage interaction and calls OpenGarageMenu(propertyIndex). That opens the
    nayzeee-garages menu of house 'tk:<property id>' (or stores the vehicle the player drives).
    tk_housing stores no garage coordinates, so the server places the garage where it is first used
    (server-side position, within 200 m of the property door; convar nayzeee_housing_hook_range)
    and checks access live with tk_housing (getPropertyData owner / permissions).

  UNCONFIRMED
    The function name, its argument and the config option come from TK's documentation excerpts
    (the docs could not be opened while writing this). If your OpenGarageMenu receives something
    other than the numeric property id, pass that id instead.
]]

-- (shown as `function _G.OpenGarageMenu`, the same as a global `function OpenGarageMenu`; keep your
-- copy's own declaration line and replace what is inside it)
function _G.OpenGarageMenu(propertyIndex)
    if GetResourceState('nayzeee-garages') ~= 'started' then return end
    if propertyIndex == nil then return end
    -- tk ids are integers; 10.0 and '10' both become 'tk:10'.
    local houseId = ('tk:%s'):format(tostring(math.tointeger(tonumber(propertyIndex)) or propertyIndex))
    local label
    local okData, data = pcall(function() return exports.tk_housing:getPropertyData(propertyIndex) end)
    if okData and type(data) == 'table' and type(data.name) == 'string' then label = data.name end
    -- OpenHouseGarage stores the vehicle instead when the player is driving.
    local ok, err = pcall(function()
        return exports['nayzeee-garages']:OpenHouseGarage(houseId, { name = label })
    end)
    if not ok then print(('[tk_housing] nayzeee-garages garage failed: %s'):format(tostring(err))) end
end
