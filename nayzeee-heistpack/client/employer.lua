--[[ Employer / fence NPCs. Peds exist only while a player is within 80m. ]]

local peds = {}

local function options(e)
    local list = {
        { name = 'nzh_emp_tablet', label = locale('employer_tablet'), icon = 'fas fa-tablet-screen-button', onSelect = function() Menu.open() end },
    }
    if e.fence then
        list[#list + 1] = { name = 'nzh_emp_fence', label = locale('employer_fence'), icon = 'fas fa-sack-dollar', onSelect = function() Menu.open('fence') end }
    end
    if Config.Outfit.enabled then
        list[#list + 1] = {
            name = 'nzh_emp_outfit', label = locale('employer_outfit'), icon = 'fas fa-shirt',
            canInteract = function() return Heist.active ~= nil end,
            onSelect = function()
                if Heist.hasOutfit() then Heist.restoreOutfit() UI.notify(locale('outfit_off'), 'info') else Heist.applyOutfit() end
            end,
        }
    end
    if Config.HeistVehicle.enabled and e.vehicleSpawn then
        list[#list + 1] = {
            name = 'nzh_emp_vehicle', label = locale('employer_vehicle'), icon = 'fas fa-van-shuttle',
            canInteract = function() return Heist.active ~= nil and Heist.active.leader == cache.serverId end,
            onSelect = function()
                local ok, res = lib.callback.await('nzh:heist:vehicle', false)
                if not ok then return UI.notify(res or locale('vehicle_failed'), 'error') end
                UI.notify(locale('vehicle_ready'), 'success')
            end,
        }
    end
    return list
end

local function spawn(i, e)
    local hash = joaat(e.model)
    lib.requestModel(hash, 10000)
    local c = e.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    if e.scenario then TaskStartScenarioInPlace(ped, e.scenario, 0, true) end
    SetModelAsNoLongerNeeded(hash)
    peds[i] = { ped = ped, target = Target.addEntity(ped, options(e)) }
end

local function despawn(i)
    local p = peds[i]
    if not p then return end
    Target.removeEntity(p.target)
    if DoesEntityExist(p.ped) then DeleteEntity(p.ped) end
    peds[i] = nil
end

CreateThread(function()
    for i = 1, #Config.Employers do
        local e = Config.Employers[i]
        if e.blip then
            local b = AddBlipForCoord(e.coords.x, e.coords.y, e.coords.z)
            SetBlipSprite(b, e.blip.sprite) SetBlipColour(b, e.blip.color) SetBlipScale(b, e.blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(e.blip.label) EndTextCommandSetBlipName(b)
        end
        lib.points.new({
            coords = vec3(e.coords.x, e.coords.y, e.coords.z), distance = 80.0,
            onEnter = function() spawn(i, e) end,
            onExit = function() despawn(i) end,
        })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for i in pairs(peds) do despawn(i) end
end)
