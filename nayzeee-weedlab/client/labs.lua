--[[
    Labs: the RV (enter through its side door), the small warehouse and the weed warehouse
    (enter through their doors in the world). Inside, the server puts you in your own routing
    bucket. The weed farm's entity sets are switched off so the place is empty.
]]

Labs = { inside = false, lab = nil, mode = nil, cfg = nil, origin = nil, rvNet = nil, rvVeh = nil }

local shell
local zones = {}
local rvTarget
local watching = false
local doors = {}          -- lab -> { point, zone, blip }

local function rvMode()
    local m = Config.Labs.rv.interior
    if m == 'shell' or m == 'ipl' then return m end
    return IsModelInCdimage(joaat(Config.Labs.rv.shell.model)) and 'shell' or 'ipl'
end

--[[ interiors ]]
local function prepareInterior(cfg)
    if cfg.ipls then
        for _, name in ipairs(cfg.ipls.remove or {}) do if IsIplActive(name) then RemoveIpl(name) end end
        for _, name in ipairs(cfg.ipls.request or {}) do RequestIpl(name) end
    end
    if cfg.entitySetsOff or cfg.entitySetsOn then
        local o = cfg.origin
        local interior = GetInteriorAtCoords(o.x, o.y, o.z)
        if interior ~= 0 then
            local t = GetGameTimer() + 3000
            while not IsInteriorReady(interior) and GetGameTimer() < t do Wait(0) end
            for _, set in ipairs(cfg.entitySetsOff or {}) do
                if IsInteriorEntitySetActive(interior, set) then DeactivateInteriorEntitySet(interior, set) end
            end
            for _, set in ipairs(cfg.entitySetsOn or {}) do ActivateInteriorEntitySet(interior, set) end
            RefreshInterior(interior)
        end
    end
end

--[[ entering / leaving ]]
function Labs.enter(lab)
    if Labs.inside or LocalPlayer.state.nzwlBusy then return end
    local mode = lab == 'rv' and rvMode() or nil
    local ok, data = lib.callback.await('nzwl:lab:enter', false, lab, mode)
    if not ok then
        if data then UI.notify(data, 'error') end
        return
    end
    Util.fade(true, 350)
    local cfg = Utils.labInterior(lab, mode)
    Labs.lab, Labs.mode, Labs.cfg, Labs.origin = lab, mode, cfg, cfg.origin
    if lab == 'rv' and mode == 'shell' then
        shell = Util.prop(cfg.model, cfg.origin, 0.0, { fallback = false })
    end
    prepareInterior(cfg)
    local sp = cfg.spawn
    local spawnAt = (lab == 'rv') and Util.rel(cfg.origin, sp) or vec3(sp.x, sp.y, sp.z)
    Util.teleport(spawnAt, sp.w)
    Labs.inside = lab
    Main.water = data.water or Main.water

    local exitAt = (lab == 'rv') and Util.rel(cfg.origin, cfg.exit) or cfg.exit
    zones[#zones + 1] = Target.addZone(exitAt, 0.9, {
        { name = 'nzwl_lab_exit', label = 'Leave', icon = 'fa-solid fa-door-open', onSelect = function() Labs.exit() end },
        { name = 'nzwl_lab_place', label = 'Set up equipment', icon = 'fa-solid fa-screwdriver-wrench', onSelect = function() Placement.menu() end },
    })
    if cfg.tap then
        zones[#zones + 1] = Target.addZone(Util.rel(cfg.origin, cfg.tap), 0.7, {
            { name = 'nzwl_lab_tap', label = 'Fill watering can', icon = 'fa-solid fa-faucet-drip', onSelect = function() Stations.fillCan() end,
              canInteract = function() return (Main.water or 0) < Config.WateringCan.capacity end },
        })
    end
    Stations.load(data.objects or {}, data.now)
    Util.fade(false, 500)
    UI.notify(('%s · %s'):format(Config.Labs[lab].label, 'Use the door to set up equipment'), 'info', 4500)
    Main.refreshHud()
end

function Labs.exit()
    if not Labs.inside or LocalPlayer.state.nzwlBusy then return end
    local pos = lib.callback.await('nzwl:lab:exit', false)
    Util.fade(true, 350)
    Stations.unload()
    for _, z in ipairs(zones) do Target.removeZone(z) end
    zones = {}
    Util.delete(shell)
    shell = nil
    Labs.inside, Labs.lab, Labs.mode = false, nil, nil
    if pos then Util.teleport(vec3(pos.x, pos.y, Util.groundZ(pos.x, pos.y, pos.z)), pos.w) end
    Util.fade(false, 500)
    Main.refreshHud()
end

--[[ the RV out in the world: its side door is the way in ]]
local function doorPoint(veh)
    return Util.off(veh, Config.RV.entryOffset)
end

local function registerRV(veh)
    if rvTarget then Target.removeEntity(rvTarget) rvTarget = nil end
    Labs.rvVeh = veh
    if not veh then return end
    FW.giveKeys(veh)
    rvTarget = Target.addEntity(veh, {
        { name = 'nzwl_rv_enter', label = 'Go inside', icon = 'fa-solid fa-caravan', distance = 3.5,
          canInteract = function(ent) return not cache.vehicle and #(GetEntityCoords(cache.ped) - doorPoint(ent or veh)) <= Config.RV.entryRadius + 0.6 end,
          onSelect = function() Labs.enter('rv') end },
    }, Config.RV.entryOffset)
end

local function watchRV()
    if watching then return end
    watching = true
    CreateThread(function()
        -- 1s poll only while we own an RV and are outside: the entity streams in and out
        while Labs.rvNet do
            if not Labs.inside then
                local veh = NetworkDoesEntityExistWithNetworkId(Labs.rvNet) and NetworkGetEntityFromNetworkId(Labs.rvNet) or nil
                if veh ~= Labs.rvVeh then registerRV(veh) end
            end
            Wait(1000)
        end
        registerRV(nil)
        watching = false
    end)
end

function Labs.setRV(net)
    Labs.rvNet = net
    if net then watchRV() end
end

RegisterNetEvent('nzwl:rv:net', function(net)
    if GetInvokingResource() then return end
    Labs.setRV(net)
end)

lib.onCache('vehicle', function(veh, old)
    if old and Labs.rvVeh and old == Labs.rvVeh and not veh then TriggerServerEvent('nzwl:rv:parked') end
end)

--[[ warehouse doors: a blip and an [E] point at the entrance of every lab you own ]]
local function clearDoor(lab)
    local d = doors[lab]
    if not d then return end
    if d.zone then Target.removeZone(d.zone) end
    if d.point then d.point:remove() end
    Util.removeBlip(d.blip)
    doors[lab] = nil
end

function Labs.refreshDoors(st)
    for _, lab in ipairs({ 'small', 'warehouse' }) do
        local info = st.labs and st.labs[lab]
        local L = Config.Labs[lab]
        local e = info and info.owned and L.entrances[info.entrance or 1]
        local key = e and (lab .. (info.entrance or 1)) or nil
        if not e then
            clearDoor(lab)
        elseif not doors[lab] or doors[lab].key ~= key then
            clearDoor(lab)
            local d = { key = key }
            d.blip = Util.blip(e.door, Config.LabBlip, L.label, false)
            d.point = lib.points.new({
                coords = vec3(e.door.x, e.door.y, e.door.z), distance = 25.0,
                onEnter = function()
                    d.zone = Target.addZone(vec3(e.door.x, e.door.y, e.door.z), 1.2, {
                        { name = 'nzwl_door_' .. lab, label = 'Enter ' .. L.label, icon = 'fa-solid fa-warehouse', onSelect = function() Labs.enter(lab) end },
                    })
                end,
                onExit = function() if d.zone then Target.removeZone(d.zone) d.zone = nil end end,
            })
            doors[lab] = d
        end
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    Util.delete(shell)
    if Labs.inside then DoScreenFadeIn(0) end
    for lab in pairs(doors) do clearDoor(lab) end
end)
