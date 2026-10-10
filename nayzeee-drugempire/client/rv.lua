--[[
    The RV: keys, "Enter RV" at the back (not the door), the lab interior and leaving it.
    The interior is the K4MB1 `shell_trevor` when it's streamed, otherwise the base-game
    interior of Trevor's trailer. The server puts you in your own routing bucket.
]]

RV = { net = nil, veh = nil, inside = false, mode = nil, cfg = nil, origin = nil }

local shell
local zones = {}
local vehTarget
local watching = false

local function interiorMode()
    local m = Config.RV.interior
    if m == 'shell' or m == 'ipl' then return m end
    return IsModelInCdimage(joaat(Config.RV.shell.model)) and 'shell' or 'ipl'
end

local function rearPoint(veh)
    local o = Config.RV.entryOffset
    return GetOffsetFromEntityInWorldCoords(veh, o.x, o.y, o.z)
end

local function nearRear(veh)
    return veh and DoesEntityExist(veh) and #(GetEntityCoords(cache.ped) - rearPoint(veh)) <= Config.RV.entryRadius + 0.6
end

--[[ entering / leaving ]]
function RV.enter()
    if RV.inside or LocalPlayer.state.nzdeBusy then return end
    local mode = interiorMode()
    local ok, data = lib.callback.await('nzde:rv:enter', false, mode)
    if not ok then
        if data then UI.notify(data, 'error') end
        return
    end
    Util.fade(true, 350)
    RV.mode, RV.cfg = mode, mode == 'ipl' and Config.RV.ipl or Config.RV.shell
    RV.origin = RV.cfg.origin
    if mode == 'shell' then
        shell = Util.prop(Config.RV.shell.model, RV.origin, 0.0, { fallback = false })
    end
    local sp = RV.cfg.spawn
    Util.teleport(Util.rel(RV.origin, sp), sp.w)
    RV.inside = true
    Main.water = data.water or Main.water

    zones[#zones + 1] = Target.addZone(Util.rel(RV.origin, RV.cfg.exit), 0.9, {
        { name = 'nzde_rv_exit', label = 'Leave the RV', icon = 'fa-solid fa-door-open', onSelect = function() RV.exit() end },
        { name = 'nzde_rv_place', label = 'Set up equipment', icon = 'fa-solid fa-screwdriver-wrench', onSelect = function() Placement.menu() end },
    })
    if RV.cfg.sink then
        zones[#zones + 1] = Target.addZone(Util.rel(RV.origin, RV.cfg.sink), 0.7, {
            { name = 'nzde_rv_sink', label = 'Fill watering can', icon = 'fa-solid fa-faucet-drip', onSelect = function() Stations.fillCan() end,
              canInteract = function() return (Main.water or 0) < Config.WateringCan.capacity end },
        })
    end
    Stations.load(data.objects or {}, data.now)
    Deliveries.rvBoxes(data.orders or {})
    Util.fade(false, 500)
    Main.refreshHud()
end

function RV.exit()
    if not RV.inside or LocalPlayer.state.nzdeBusy then return end
    local pos = lib.callback.await('nzde:rv:exit', false)
    Util.fade(true, 350)
    Stations.unload()
    Deliveries.rvBoxes({})
    for _, z in ipairs(zones) do Target.removeZone(z) end
    zones = {}
    Util.delete(shell)
    shell = nil
    RV.inside = false
    if pos then
        Util.teleport(vec3(pos.x, pos.y, Util.groundZ(pos.x, pos.y, pos.z)), pos.w)
    end
    Util.fade(false, 500)
end

--[[ the vehicle ]]
local function registerVehicle(veh)
    if vehTarget then Target.removeEntity(vehTarget) vehTarget = nil end
    RV.veh = veh
    if not veh then return end
    FW.giveKeys(veh)
    vehTarget = Target.addEntity(veh, {
        { name = 'nzde_rv_enter', label = 'Go in the back', icon = 'fa-solid fa-caravan', distance = 4.0,
          canInteract = function(ent) return not cache.vehicle and nearRear(ent or veh) end,
          onSelect = function() RV.enter() end },
    }, Config.RV.entryOffset)
end

local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        -- 1s poll only while we own an RV and are outside: the entity streams in and out
        while RV.net do
            if not RV.inside then
                local veh = NetworkDoesEntityExistWithNetworkId(RV.net) and NetworkGetEntityFromNetworkId(RV.net) or nil
                if veh ~= RV.veh then registerVehicle(veh) end
            end
            Wait(1000)
        end
        registerVehicle(nil)
        watching = false
    end)
end

function RV.setNet(net)
    RV.net = net
    if net then watch() end
end

RegisterNetEvent('nzde:rv:net', function(net)
    if GetInvokingResource() then return end
    RV.setNet(net)
end)

-- keep the parked position fresh on the server
lib.onCache('vehicle', function(veh, old)
    if old and RV.veh and old == RV.veh and not veh then
        TriggerServerEvent('nzde:rv:parked')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    Util.delete(shell)
    if RV.inside then
        DoScreenFadeIn(0)
    end
end)
