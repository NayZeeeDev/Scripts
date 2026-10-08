--[[
    Special mechanics that need per-frame logic. Every loop here starts only when a
    node that needs it becomes active and exits as soon as it isn't, so idle cost is 0.
]]

Special = {}

local loops = {}       -- name -> true while running
local entityBlips = {} -- key -> blip
local atmHandle
local noiseLevel = 0

local function active(fn)
    for _, n in pairs(Nodes.all) do
        if not n.done and fn(n) then return n end
    end
    return nil
end

local function startLoop(name, fn)
    if loops[name] then return end
    loops[name] = true
    CreateThread(function()
        local ok, err = pcall(fn)
        if not ok then print(('^1[nzh] %s loop error: %s^7'):format(name, tostring(err))) end
        loops[name] = nil
    end)
end

local function requestControl(ent)
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    local t = GetGameTimer()
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() - t < 1500 do
        Wait(50)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

--[[ ------------------------------ status (escape / guards / tracker) ------------------------------ ]]

local function statusLoop()
    local last = ''
    while Heist.active do
        local escape = active(function(n) return n.type == 'escape' end)
        local elim = active(function(n) return n.type == 'eliminate' end)
        local tracker = active(function(n) return n.type == 'tracker' and not (Heist.active.flags or {})[n.flag] end)
        if not escape and not elim and not tracker then break end
        local extra = {}
        if escape then
            local d = #(GetEntityCoords(cache.ped) - Utils.vec3(escape.coords))
            extra.distance = { current = math.floor(d), target = math.floor(escape.radius) }
        end
        if elim then
            local group = Heist.active.guards[elim.group or 'guards'] or {}
            local alive = 0
            for i = 1, #group do
                local netId = group[i]
                local ped = NetworkDoesNetworkIdExist(netId) and NetToPed(netId) or 0
                if ped ~= 0 and DoesEntityExist(ped) then
                    if not IsPedDeadOrDying(ped, true) then
                        alive = alive + 1
                        if not entityBlips['g' .. netId] then
                            local b = AddBlipForEntity(ped)
                            SetBlipSprite(b, Config.Blips.guard.sprite)
                            SetBlipColour(b, Config.Blips.guard.color)
                            SetBlipScale(b, Config.Blips.guard.scale)
                            entityBlips['g' .. netId] = b
                        end
                    elseif entityBlips['g' .. netId] then
                        RemoveBlip(entityBlips['g' .. netId])
                        entityBlips['g' .. netId] = nil
                    end
                else
                    alive = alive + 1 -- out of scope, assume alive
                end
            end
            extra.guards = { alive = alive, total = #group }
        end
        if tracker then extra.tracker = true end
        local sig = json.encode(extra)
        if sig ~= last then
            last = sig
            Heist.refreshHud(extra)
        end
        Wait(1000)
    end
    Heist.refreshHud()
end

--[[ ------------------------------ store clerk intimidation ------------------------------ ]]

local function intimidate(n)
    local clerk = Heist.entity(n.ped)
    if not clerk then return end
    local uid = Heist.active.uid
    LocalPlayer.state:set('nzhBusy', true, false)
    local ok, err = lib.callback.await('nzh:heist:claim', false, uid, n.id)
    if not ok then
        LocalPlayer.state:set('nzhBusy', false, false)
        if err then UI.notify(err, 'error') end
        return
    end
    if requestControl(clerk) then
        ClearPedTasksImmediately(clerk)
        lib.requestAnimDict('mp_am_hold_up')
        TaskPlayAnim(clerk, 'mp_am_hold_up', 'holdup_victim_20s', 8.0, -8.0, -1, 2, 0, false, false, false)
    end
    local duration = n.duration or 12000
    UI.send('progress', { label = n.progressLabel or locale('intimidating'), duration = duration })
    local start, success = GetGameTimer(), true
    while GetGameTimer() - start < duration do
        if not IsPlayerFreeAimingAtEntity(PlayerId(), clerk) and not IsPlayerTargettingEntity(PlayerId(), clerk) then
            -- short grace window to re-aim
            local grace = GetGameTimer()
            while GetGameTimer() - grace < 1200 and not IsPlayerFreeAimingAtEntity(PlayerId(), clerk) do Wait(0) end
            if not IsPlayerFreeAimingAtEntity(PlayerId(), clerk) then success = false break end
        end
        if IsEntityDead(cache.ped) or IsEntityDead(clerk) then success = false break end
        Wait(0)
    end
    UI.send('progress', false)
    if success and requestControl(clerk) then
        ClearPedTasks(clerk)
        lib.requestAnimDict('missminuteman_1ig_2')
        TaskPlayAnim(clerk, 'missminuteman_1ig_2', 'handsup_base', 8.0, -8.0, -1, 49, 0, false, false, false)
    end
    lib.callback.await('nzh:heist:finish', false, uid, n.id, success)
    if not success then UI.notify(locale('intimidate_failed'), 'error') end
    LocalPlayer.state:set('nzhBusy', false, false)
end

local function intimidateLoop()
    while Heist.active do
        local n = active(function(x) return x.type == 'intimidate' and not x.busy end)
        if not n then break end
        local clerk = Heist.entity(n.ped)
        local wait = 500
        if clerk and not LocalPlayer.state.nzhBusy then
            local d = #(GetEntityCoords(cache.ped) - GetEntityCoords(clerk))
            if d < 12.0 then
                wait = 0
                if IsPlayerFreeAimingAtEntity(PlayerId(), clerk) then intimidate(n) end
            end
        end
        Wait(wait)
    end
end

--[[ ------------------------------ ATM ------------------------------ ]]

local ATM_MODELS = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' }

local function atmRope(n, atm)
    local pc = GetEntityCoords(cache.ped)
    local veh = lib.getClosestVehicle(pc, 12.0, false)
    if not veh then UI.notify(locale('atm_need_vehicle'), 'error') return false end
    if not Anim.run('rope', { coords = GetEntityCoords(atm) }) then return false end

    local origin = GetEntityCoords(atm)
    local model = GetEntityModel(atm)
    CreateModelHide(origin.x, origin.y, origin.z, 1.5, model, true)
    local copy = Props.spawn('atm_copy', model, origin, GetEntityHeading(atm), { freeze = false })
    if not copy then return false end
    SetEntityDynamic(copy, true)
    ActivatePhysics(copy)

    RopeLoadTextures()
    local t = GetGameTimer()
    while not RopeAreTexturesLoaded() and GetGameTimer() - t < 3000 do Wait(0) end
    local vc = GetOffsetFromEntityInWorldCoords(veh, 0.0, -2.5, 0.0)
    local length = #(vc - origin) + 1.0
    local okRope, rope = pcall(AddRope, origin.x, origin.y, origin.z, 0.0, 0.0, 0.0, length, 4, length, 0.5, 0.5, false, false, false, 1.0, false, 0)
    if okRope and rope then
        pcall(AttachEntitiesToRope, rope, veh, copy, vc.x, vc.y, vc.z, origin.x, origin.y, origin.z + 0.5, length, false, false, nil, nil)
    end
    UI.notify(locale('atm_pull'), 'info')
    local success = false
    t = GetGameTimer()
    while GetGameTimer() - t < 90000 do
        if #(GetEntityCoords(copy) - origin) > 4.0 then success = true break end
        if #(GetEntityCoords(cache.ped) - origin) > 80.0 then break end
        Wait(250)
    end
    if okRope and rope then DeleteRope(rope) end
    if success then
        local c = GetEntityCoords(copy)
        Anim.ptfx('core', 'ent_brk_banknotes', c, 2.0)
        SetTimeout(20000, function() Props.delete('atm_copy') end)
    else
        Props.delete('atm_copy')
        RemoveModelHide(origin.x, origin.y, origin.z, 1.5, model, false)
    end
    return success
end

local function atmOptions(n)
    local opts = {}
    for key, m in pairs(n.methods or {}) do
        opts[#opts + 1] = {
            name = 'nzh_atm_' .. key, label = m.label, icon = m.icon or 'fas fa-money-bill',
            canInteract = function() return Nodes.canUse(Nodes.all[n.id] or n) end,
            onSelect = function(entity)
                local cur = Nodes.all[n.id]
                if not cur or not entity then return end
                local coords = GetEntityCoords(entity)
                if key == 'rope' then
                    -- custom flow: claim, rope + drag, finish
                    if LocalPlayer.state.nzhBusy then return end
                    LocalPlayer.state:set('nzhBusy', true, false)
                    local uid = Heist.active.uid
                    local ok, err = lib.callback.await('nzh:heist:claim', false, uid, cur.id, { coords = coords, method = key })
                    if ok then
                        local success = atmRope(cur, entity)
                        lib.callback.await('nzh:heist:finish', false, uid, cur.id, success)
                    elseif err then UI.notify(err, 'error') end
                    LocalPlayer.state:set('nzhBusy', false, false)
                    return
                end
                Nodes.run(cur, { coords = coords, method = key, action = m.action, minigame = m.minigame })
            end,
        }
    end
    table.sort(opts, function(a, b) return a.name < b.name end)
    return opts
end

local function syncAtm()
    local n = active(function(x) return x.type == 'atm' or x.type == 'objects' end)
    if n and not atmHandle then
        atmHandle = Target.addModels(n.models or ATM_MODELS, atmOptions(n))
    elseif not n and atmHandle then
        Target.removeModels(atmHandle)
        atmHandle = nil
    end
end

--[[ ------------------------------ skylift + handler ------------------------------ ]]

local function liftLoop()
    local shown
    while Heist.active do
        local n = active(function(x) return x.type == 'deliver' and (x.skylift or x.handler) end)
        if not n then break end
        local wait = 500
        local veh = cache.vehicle
        local container = Heist.entity(n.entity)
        local prompt

        if veh and container and GetPedInVehicleSeat(veh, -1) == cache.ped then
            if n.skylift and veh == Heist.entity(n.skylift.heli) then
                wait = 0
                local attached = IsEntityAttachedToEntity(container, veh)
                local below = #(GetEntityCoords(veh) - GetEntityCoords(container)) < 14.0
                if attached then prompt = locale('lift_release')
                elseif below then prompt = locale('lift_attach') end
                if prompt and IsControlJustReleased(0, 38) and requestControl(container) then
                    if attached then
                        DetachEntity(container, true, true)
                        ActivatePhysics(container)
                    else
                        AttachEntityToEntity(container, veh, 0, 0.0, 0.0, -(n.skylift.drop or 4.5), 0.0, 0.0, 0.0, false, false, true, false, 2, true)
                    end
                    Wait(300)
                end
            elseif n.handler and veh == Heist.entity(n.handler.handler) then
                wait = 0
                local trailer = Heist.entity(n.handler.trailer)
                local onFrame = IsEntityAttachedToEntity(container, veh)
                if onFrame and trailer and #(GetEntityCoords(container) - GetEntityCoords(trailer)) < (n.handler.loadRange or 7.0) then
                    prompt = locale('handler_load')
                    if IsControlJustReleased(0, 38) and requestControl(container) then
                        DetachContainerFromHandlerFrame(veh)
                        local o = n.handler.offset or vec3(0.0, -0.6, 1.1)
                        AttachEntityToEntity(container, trailer, 0, o.x, o.y, o.z, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
                        UI.notify(locale('handler_loaded'), 'success')
                        Wait(500)
                    end
                elseif not onFrame and IsHandlerFrameAboveContainer(veh, container) then
                    prompt = locale('handler_pick')
                    if IsControlJustReleased(0, 38) and requestControl(container) then
                        AttachContainerToHandlerFrame(veh, container)
                        Wait(500)
                    end
                end
            end
        end

        if prompt ~= shown then
            if prompt then UI.textui(prompt) else UI.hideTextui() end
            shown = prompt
        end
        Wait(wait)
    end
    if shown then UI.hideTextui() end
end

--[[ ------------------------------ house noise ------------------------------ ]]

local function noiseLoop()
    noiseLevel = 0
    local alerted = false
    while Heist.active and Heist.active.noise do
        local ped = cache.ped
        if GetInteriorFromEntity(ped) == 0 then
            UI.send('noise', false)
            Wait(1000)
            goto continue
        end
        local add = 0
        if IsPedSprinting(ped) then add = add + 3 elseif IsPedRunning(ped) then add = add + 1.5 end
        if IsPedJumping(ped) then add = add + 4 end
        if IsPedShooting(ped) then add = add + 40 end
        if IsPedInMeleeCombat(ped) then add = add + 6 end
        if add == 0 then noiseLevel = math.max(0, noiseLevel - 1.2) else noiseLevel = math.min(100, noiseLevel + add) end
        UI.send('noise', { value = math.floor(noiseLevel) })
        if noiseLevel >= 100 and not alerted then
            alerted = true
            lib.callback.await('nzh:heist:noise', false, Heist.active.uid)
        end
        Wait(250)
        ::continue::
    end
    UI.send('noise', false)
end

--[[ ------------------------------ gas / hazard zones ------------------------------ ]]

local function hasMask(ped)
    return GetPedDrawableVariation(ped, 1) ~= 0
end

local function hazardLoop()
    local fxAt = 0
    while Heist.active do
        local n = active(function(x) return x.type == 'hazard' end)
        if not n then break end
        local wait = 1000
        if not n.requiresFlag or (Heist.active.flags or {})[n.requiresFlag] then
            local center = Utils.vec3(n.coords)
            local d = #(GetEntityCoords(cache.ped) - center)
            if d < 80.0 and GetGameTimer() - fxAt > 9000 then
                fxAt = GetGameTimer()
                Anim.ptfx('core', 'exp_grd_bzgas_smoke', center, 2.5)
            end
            if d <= n.radius and not hasMask(cache.ped) and not IsEntityDead(cache.ped) then
                ApplyDamageToPed(cache.ped, n.damage or 4, false)
                if not loops.gasWarned then
                    loops.gasWarned = true
                    UI.notify(locale('gas_no_mask'), 'error')
                    SetTimeout(10000, function() loops.gasWarned = nil end)
                end
            end
        end
        Wait(wait)
    end
end

--[[ ------------------------------ interior scan ------------------------------ ]]

function Special.scan(n)
    if not Heist.active then return end
    local hashes = {}
    for name in pairs(n.models or {}) do hashes[joaat(name)] = name end
    local center = Utils.vec3(n.coords)
    local found = {}
    for _, obj in ipairs(GetGamePool('CObject')) do
        local name = hashes[GetEntityModel(obj)]
        if name then
            local c = GetEntityCoords(obj)
            if #(c - center) <= n.radius then
                found[#found + 1] = { model = name, coords = c }
            end
        end
    end
    -- shuffle so repeat visits differ
    for i = #found, 2, -1 do
        local j = math.random(i)
        found[i], found[j] = found[j], found[i]
    end
    lib.callback.await('nzh:heist:scan', false, Heist.active.uid, n.id, found)
end

--[[ ------------------------------ drone zones ------------------------------ ]]

function Special.droneZones()
    local zones = {}
    for _, n in pairs(Nodes.all) do
        if n.type == 'dronedrop' and not n.done then
            local node = n
            zones[#zones + 1] = {
                id = n.id, coords = Utils.vec3(n.coords), radius = n.radius or 3.0, label = n.label,
                onDrop = function(_, pos)
                    local ok = Nodes.instant(node)
                    if ok then
                        Anim.ptfx(node.effect and node.effect.asset or 'core', node.effect and node.effect.name or 'exp_grd_bzgas_smoke', vec3(pos.x, pos.y, node.coords.z), 1.5)
                        UI.notify(node.dropMessage or locale('drone_dropped'), 'success')
                    end
                end,
            }
        end
    end
    Drone.setZones(zones)
end

--[[ ------------------------------ entity blips ------------------------------ ]]

function Special.onEntities()
    for key, b in pairs(entityBlips) do
        if key:sub(1, 1) == 'e' then RemoveBlip(b) entityBlips[key] = nil end
    end
    if not Heist.active then return end
    for _, n in pairs(Nodes.all) do
        if not n.done and (n.type == 'deliver' or n.blipEntity) then
            local keys = n.entities or { n.entity or n.blipEntity }
            for i = 1, #keys do
                local ent = Heist.entity(keys[i])
                if ent and not entityBlips['e' .. keys[i]] then
                    local b = AddBlipForEntity(ent)
                    SetBlipSprite(b, Config.Blips.vehicle.sprite)
                    SetBlipColour(b, Config.Blips.vehicle.color)
                    SetBlipScale(b, Config.Blips.vehicle.scale)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(n.entityLabel or locale('blip_target'))
                    EndTextCommandSetBlipName(b)
                    entityBlips['e' .. keys[i]] = b
                end
            end
        end
    end
    -- crew vehicle keys
    local crewVeh = Heist.entity('crewVehicle')
    if crewVeh and not entityBlips.crewKeys then
        entityBlips.crewKeys = AddBlipForEntity(crewVeh)
        SetBlipSprite(entityBlips.crewKeys, 67)
        SetBlipColour(entityBlips.crewKeys, 3)
        FW.giveKeys(crewVeh)
    end
    Special.onNode()
end

--[[ ------------------------------ dispatch ------------------------------ ]]

--- called for every node change; starts whatever loops are needed
function Special.onNode()
    if not Heist.active then return end
    syncAtm()
    if active(function(n) return n.type == 'escape' or n.type == 'eliminate' or n.type == 'tracker' end) then startLoop('status', statusLoop) end
    if active(function(n) return n.type == 'intimidate' end) then startLoop('intimidate', intimidateLoop) end
    if active(function(n) return n.type == 'deliver' and (n.skylift or n.handler) end) then startLoop('lift', liftLoop) end
    if active(function(n) return n.type == 'hazard' end) then startLoop('hazard', hazardLoop) end
    -- explicit `keys = { 'entityKey' }` on any active node
    for _, n in pairs(Nodes.all) do
        if not n.done and n.keys then
            for i = 1, #n.keys do
                local ent = Heist.entity(n.keys[i])
                if ent and not entityBlips['k' .. n.keys[i]] then
                    entityBlips['k' .. n.keys[i]] = true
                    FW.giveKeys(ent)
                end
            end
        end
    end
    -- give keys for any spawned vehicle a deliver node wants us to drive
    for _, n in pairs(Nodes.all) do
        if n.type == 'deliver' and not n.done and n.keys ~= false and not (Heist.active.flags or {})['keys_' .. n.id] then
            local keys = n.entities or { n.entity }
            for i = 1, #keys do
                local ent = Heist.entity(keys[i])
                if ent and GetEntityType(ent) == 2 and not entityBlips['k' .. keys[i]] then
                    entityBlips['k' .. keys[i]] = true
                    FW.giveKeys(ent)
                end
            end
        end
    end
end

function Special.onStage(stage)
    if stage.noise and Heist.active then Heist.active.noise = true end
    if Heist.active and Heist.active.noise then startLoop('noise', noiseLoop) end
    Special.onNode()
end

function Special.clear()
    for key, b in pairs(entityBlips) do
        if type(b) == 'number' then RemoveBlip(b) end
        entityBlips[key] = nil
    end
    if atmHandle then Target.removeModels(atmHandle) atmHandle = nil end
    noiseLevel = 0
end
