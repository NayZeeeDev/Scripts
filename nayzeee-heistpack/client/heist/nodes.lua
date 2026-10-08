--[[
    Heist nodes (client). A node is one objective/interaction sent by the server.

    TYPES
      interact   generic action (anim preset / minigame / thermite / c4 / drill ...)
      trolley    cash / gold / diamond trolley         (kind = 'cash' | 'gold' | 'diamond')
      smash      display case / register (needs a weapon in hand)
      carry      pick up a prop and put it in a vehicle trunk or at `carry.dropoff`
      zone       reach an area (select / decoy / goto)
      portal     enter / exit an interior (repeatable)
      scan       scans an interior for lootable props, server turns them into carry/interact nodes
      deliver    get entity/entities into `dropoff`     (server-checked)
      escape     get far away                           (server-checked)
      eliminate  kill a guard group                     (server-checked)
      intimidate aim at a ped (store clerk)             (special.lua)
      dronedrop  drop a drone payload over a zone       (drone.lua)
      atm        rob any ATM in the world, N times      (special.lua)
      tracker    vehicle tracker pinging police until a flag is set (server + HUD)

    Interaction points are ox_lib points: props and targets exist only while the
    player is within ~35m, so a running heist far away costs nothing either.
]]

Nodes = { all = {} }

local reg = {}          -- id -> { point, zone, entityHandle, entity }
local running = false
local INTERACTIVE = { interact = true, trolley = true, smash = true, carry = true, portal = true }

--[[ ------------------------------ helpers ------------------------------ ]]

local function flagsOk(n)
    if not n.requiresFlag then return true end
    local flags = Heist.active and Heist.active.flags
    return flags and flags[n.requiresFlag] == true
end

local function requiresOk(n)
    if not n.requires then return true end
    for i = 1, #n.requires do
        local r = Nodes.all[n.requires[i]]
        if not r or not r.done then return false end
    end
    return true
end

function Nodes.canUse(n)
    if not Heist.active or n.done or n.busy or running then return false end
    return requiresOk(n) and flagsOk(n)
end

local function nodeCoords(n)
    if n.attach then
        local ent = Heist.entity(n.attach.entity)
        if not ent then return nil end
        local o = n.attach.offset or vec3(0.0, 0.0, 0.0)
        return GetOffsetFromEntityInWorldCoords(ent, o.x, o.y, o.z)
    end
    return n.coords and Utils.vec3(n.coords)
end
Nodes.coords = nodeCoords

--- snap exterior nodes to the ground once collision is loaded (config coords can be rough)
local function ground(n)
    if not n.ground or n.grounded or not n.coords then return end
    local c = Utils.vec3(n.coords)
    local found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 4.0, false)
    if found then n.coords = vec3(c.x, c.y, gz + (n.groundOffset or 0.6)) end
    n.grounded = true
end

local function spawnProp(n)
    local p = n.prop
    if not p or p.existing then return end
    if n.done and p.removeOnDone then return end
    local model = (n.done and p.swap) or p.model
    local c = p.coords and Utils.vec3(p.coords) or Utils.vec3(n.coords)
    if p.offset then c = c + p.offset end
    if p.ground then c = vec3(c.x, c.y, c.z + 0.5) end
    Props.spawn(n.id, model, c, p.heading or n.heading or 0.0, { rotation = p.rotation, ground = p.ground, collision = p.collision })
end

local function setBusy(state)
    running = state
    LocalPlayer.state:set('nzhBusy', state, false)
end

--[[ ------------------------------ actions ------------------------------ ]]

local function minigameSpec(n)
    local m = n.minigame
    if not m then return nil end
    if type(m) == 'string' then return m, { difficulty = 2 } end
    return m.type, m
end

local function loopAnim(name)
    local p = Anim.presets[name]
    if not p then return nil end
    lib.requestAnimDict(p.dict)
    TaskPlayAnim(cache.ped, p.dict, p.clip, 3.0, 3.0, -1, 1, 0, false, false, false)
    local prop = p.prop and Props.attach(cache.ped, p.prop.model, p.prop.bone, p.prop.pos, p.prop.rot)
    return function()
        StopAnimTask(cache.ped, p.dict, p.clip, 1.0)
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    end
end

local Actions = {}

function Actions.trolley(n, speed, coords)
    return Anim.trolley(coords or nodeCoords(n), n.kind, speed)
end

function Actions.smash(n, speed, coords)
    return Anim.smash(coords or nodeCoords(n), speed)
end

function Actions.thermite(n, _, coords)
    return Anim.thermite(coords or nodeCoords(n), n.heading, n.burn)
end

function Actions.c4(n, _, coords)
    local c = coords or nodeCoords(n)
    if n.attach then
        -- stick the charge to the vehicle side instead of floating at the offset
        c = vec3(c.x, c.y, c.z + 0.3)
    end
    return Anim.c4(c, n.fuse)
end

--- default: preset animation (+ optional minigame)
local function perform(n, speed, extra)
    local action = (extra and extra.action) or n.action or (n.type ~= 'interact' and n.type) or 'search'
    local coords = (extra and extra.coords) and Utils.vec3(extra.coords) or nodeCoords(n)
    local mgType, mgOpts = minigameSpec(n)
    if extra and extra.minigame then mgType, mgOpts = extra.minigame.type, extra.minigame end

    if mgType then
        if coords then Anim.face(coords) end
        local stop = loopAnim(n.minigameAnim or (action ~= 'thermite' and action ~= 'c4' and action) or 'hack')
        local ok = UI.minigame(mgType, mgOpts)
        if stop then stop() end
        if not ok then return false end
        if action == 'thermite' or action == 'c4' then return Actions[action](n, speed, coords) end
        if n.duration and n.duration > 0 and n.progressAfter then
            return Anim.run(action, { duration = n.duration, speed = speed, label = n.progressLabel })
        end
        return true
    end

    if Actions[action] then return Actions[action](n, speed, coords) end
    return Anim.run(action, { coords = coords, duration = n.duration, speed = speed, label = n.progressLabel })
end

--[[ ------------------------------ carry ------------------------------ ]]

local function carryLoop(n, uid)
    CreateThread(function()
        local shown = false
        local drop = n.carry and n.carry.dropoff and Utils.vec3(n.carry.dropoff)
        local toVehicle = not n.carry or n.carry.vehicle ~= false
        while Carry.entity do
            local pc = GetEntityCoords(cache.ped)
            local can = (drop and #(pc - drop) <= 2.5) or (toVehicle and Carry.trunkVehicle(2.4) ~= nil)
            if can then
                if not shown then UI.textui({ { key = 'E', label = locale('place_loot') }, { key = 'G', label = locale('drop_loot') } }) shown = true end
                if IsControlJustReleased(0, 38) then
                    UI.hideTextui()
                    local veh = toVehicle and Carry.trunkVehicle(2.4)
                    if veh then
                        SetVehicleDoorOpen(veh, 5, false, false)
                        SetTimeout(1500, function() SetVehicleDoorShut(veh, 5, false) end)
                    end
                    Carry.stop()
                    lib.callback.await('nzh:heist:finish', false, uid, n.id, true)
                    return
                end
            else
                if shown then UI.hideTextui() shown = false end
            end
            if IsControlJustReleased(0, 47) then
                Carry.drop()
                break
            end
            Wait(can and 0 or 250)
        end
        if shown then UI.hideTextui() end
        -- dropped / died
        lib.callback.await('nzh:heist:finish', false, uid, n.id, false)
    end)
end

function Actions.carry(n)
    local coords = nodeCoords(n)
    if not Anim.run('pickup', { coords = coords }) then return false end
    local model = n.carry and n.carry.model or (n.prop and n.prop.model)
    if n.prop and n.prop.existing then
        -- world object (scan): hide the original, carry a copy
        local hash = type(model) == 'string' and joaat(model) or model
        CreateModelHide(coords.x, coords.y, coords.z, 0.6, hash, true)
    end
    local local_ = Props.get(n.id)
    if local_ then
        Props.list[n.id] = nil
        DeleteEntity(local_)
    end
    local obj = Carry.start(model, { pos = n.carry and n.carry.pos, rot = n.carry and n.carry.rot })
    if not obj then return false end
    return 'pending'
end

--[[ ------------------------------ run ------------------------------ ]]

function Nodes.run(n, extra)
    if running or not Heist.active then return end
    if Carry.entity then return UI.notify(locale('hands_full'), 'error') end
    if (n.type == 'smash' or n.needsWeapon) and not Anim.hasSmashWeapon() then
        return UI.notify(locale('need_weapon'), 'error')
    end
    setBusy(true)
    local uid = Heist.active.uid
    local ok, res = lib.callback.await('nzh:heist:claim', false, uid, n.id, extra)
    if not ok then
        UI.notify(res or locale('node_unavailable'), 'error')
        setBusy(false)
        return
    end
    local speed = type(res) == 'table' and res.speed or 1.0

    local success
    if n.type == 'carry' then
        success = Actions.carry(n)
        if success == 'pending' then
            setBusy(false)
            carryLoop(n, uid)
            return
        end
    else
        local okRun, result = pcall(perform, n, speed, extra)
        if not okRun then print('^1[nzh] action error: ' .. tostring(result) .. '^7') end
        success = okRun and result == true
    end

    lib.callback.await('nzh:heist:finish', false, uid, n.id, success)
    if not success then
        UI.notify(locale('action_failed'), 'error')
    elseif n.vehicleDoors and n.attach then
        local veh = Heist.entity(n.attach.entity)
        if veh then
            NetworkRequestControlOfEntity(veh)
            for i = 1, #n.vehicleDoors do SetVehicleDoorOpen(veh, n.vehicleDoors[i], false, false) end
        end
    end
    setBusy(false)
end

--- claim + finish without any animation (drone drops)
function Nodes.instant(n)
    if not Heist.active then return false end
    local uid = Heist.active.uid
    local ok, res = lib.callback.await('nzh:heist:claim', false, uid, n.id)
    if not ok then UI.notify(res or locale('node_unavailable'), 'error') return false end
    return lib.callback.await('nzh:heist:finish', false, uid, n.id, true)
end

--[[ ------------------------------ registration ------------------------------ ]]

local function targetOptions(n)
    local label = n.label or 'Interact'
    if n.item and n.item.label then label = ('%s (%s)'):format(label, n.item.label) end
    return {
        {
            name = 'nzh_' .. n.id, label = label, icon = n.icon or 'fas fa-hand', distance = (n.radius or 1.2) + 1.0,
            canInteract = function() return Nodes.canUse(Nodes.all[n.id] or n) end,
            onSelect = function()
                local cur = Nodes.all[n.id]
                if not cur then return end
                if cur.type == 'portal' then return Nodes.portal(cur) end
                Nodes.run(cur)
            end,
        },
    }
end

local function addTarget(n)
    local r = reg[n.id]
    if not r or r.zone or (n.done and n.type ~= 'portal') then return end
    r.zone = Target.addZone(nodeCoords(n), n.radius or 1.2, targetOptions(n))
end

local function removeTarget(n)
    local r = reg[n.id]
    if r and r.zone then Target.removeZone(r.zone) r.zone = nil end
end

local function registerAttached(n)
    local r = reg[n.id]
    local ent = Heist.entity(n.attach.entity)
    if r.entityHandle and r.entity == ent then return end
    if r.entityHandle then Target.removeEntity(r.entityHandle) r.entityHandle = nil end
    if not ent or n.done then return end
    local opts = targetOptions(n)
    local base = opts[1].canInteract
    opts[1].canInteract = function()
        local c = nodeCoords(Nodes.all[n.id] or n)
        return base() and c ~= nil and #(GetEntityCoords(cache.ped) - c) <= (n.radius or 1.5) + 0.8
    end
    r.entity = ent
    r.entityHandle = Target.addEntity(ent, opts)
end

local function register(n)
    local r = {}
    reg[n.id] = r

    if INTERACTIVE[n.type] then
        if n.attach then
            registerAttached(n)
        else
            r.point = lib.points.new({
                coords = Utils.vec3(n.coords), distance = n.streamDistance or 35.0, nodeId = n.id,
                onEnter = function(self)
                    local cur = Nodes.all[self.nodeId]
                    if not cur then return end
                    ground(cur)
                    spawnProp(cur)
                    addTarget(cur)
                end,
                onExit = function(self)
                    local cur = Nodes.all[self.nodeId]
                    if not cur then return end
                    removeTarget(cur)
                    Props.delete(cur.id)
                end,
            })
        end
        if n.blip and not n.done then
            Heist.addBlip('node_' .. n.id, { coords = n.coords, label = n.blip.label or n.label, sprite = n.blip.sprite, color = n.blip.color, scale = n.blip.scale })
        end
    elseif n.type == 'zone' then
        if not n.done then
            if n.blip ~= false then
                local b = type(n.blip) == 'table' and n.blip or {}
                Heist.addBlip('node_' .. n.id, { coords = n.coords, label = b.label or n.label, sprite = b.sprite, color = b.color, route = b.route })
            end
            r.point = lib.points.new({
                coords = Utils.vec3(n.coords), distance = n.radius or 10.0, nodeId = n.id,
                onEnter = function(self)
                    local cur = Nodes.all[self.nodeId]
                    if not cur or cur.done or not Heist.active or not flagsOk(cur) then return end
                    local ok, decoy = lib.callback.await('nzh:heist:reach', false, Heist.active.uid, cur.id)
                    if ok and decoy then UI.notify(locale('decoy_location'), 'error') end
                end,
            })
        end
    elseif n.type == 'scan' then
        if not n.done then
            r.point = lib.points.new({
                coords = Utils.vec3(n.coords), distance = n.radius or 15.0, nodeId = n.id,
                onEnter = function(self)
                    local cur = Nodes.all[self.nodeId]
                    if cur and not cur.done then Special.scan(cur) end
                end,
            })
        end
    elseif n.type == 'deliver' then
        if not n.done then
            Heist.addBlip('drop_' .. n.id, { coords = n.dropoff, label = n.label or locale('blip_dropoff'), sprite = Config.Blips.dropoff.sprite, color = Config.Blips.dropoff.color, route = true })
            r.point = lib.points.new({
                coords = Utils.vec3(n.dropoff), distance = 60.0, nodeId = n.id,
                nearby = function(self)
                    local cur = Nodes.all[self.nodeId]
                    if not cur or cur.done then return end
                    local d = self.coords
                    local rad = (cur.radius or 8.0) * 2
                    DrawMarker(1, d.x, d.y, d.z - 1.0, 0, 0, 0, 0, 0, 0, rad, rad, 1.2, 34, 197, 94, 90, false, false, 2, false, nil, nil, false)
                end,
            })
        end
    elseif n.type == 'prop' then
        r.point = lib.points.new({
            coords = Utils.vec3(n.coords), distance = n.streamDistance or 120.0, nodeId = n.id,
            onEnter = function(self)
                local cur = Nodes.all[self.nodeId]
                if cur then spawnProp(cur) end
            end,
            onExit = function(self) Props.delete(self.nodeId) end,
        })
    elseif n.type == 'dronedrop' then
        Special.droneZones()
    end
    Special.onNode(n)
end

local function unregister(n)
    local r = reg[n.id]
    if not r then return end
    if r.point then r.point:remove() end
    if r.zone then Target.removeZone(r.zone) end
    if r.entityHandle then Target.removeEntity(r.entityHandle) end
    Heist.removeBlip('node_' .. n.id)
    Heist.removeBlip('drop_' .. n.id)
    Props.delete(n.id)
    reg[n.id] = nil
end

--[[ ------------------------------ public ------------------------------ ]]

function Nodes.upsert(n)
    local old = Nodes.all[n.id]
    if old then unregister(old) end
    Nodes.all[n.id] = n
    register(n)
end

function Nodes.setState(id, state)
    local n = Nodes.all[id]
    if not n then return end
    local wasDone = n.done
    n.done, n.uses, n.busy = state.done, state.uses, state.busy
    if n.done and not wasDone then
        local r = reg[id]
        if n.type ~= 'portal' then
            removeTarget(n)
            if r and r.entityHandle then Target.removeEntity(r.entityHandle) r.entityHandle = nil end
        end
        Heist.removeBlip('node_' .. id)
        Heist.removeBlip('drop_' .. id)
        if r and r.point and (n.type == 'zone' or n.type == 'scan' or n.type == 'deliver') then
            r.point:remove()
            r.point = nil
        end
        if n.prop then
            if n.prop.swap and Props.get(id) then Props.swap(id, n.prop.swap)
            elseif n.prop.removeOnDone then Props.delete(id) end
        end
        if n.type == 'dronedrop' then Special.droneZones() end
    end
    Special.onNode(n)
end

function Nodes.removeWhere(fn)
    for id, n in pairs(Nodes.all) do
        if fn(n) then
            unregister(n)
            Nodes.all[id] = nil
        end
    end
    Heist.refreshHud()
end

function Nodes.onEntities()
    for _, n in pairs(Nodes.all) do
        if n.attach and INTERACTIVE[n.type] and reg[n.id] then registerAttached(n) end
    end
end

function Nodes.onFlags()
    Heist.refreshHud()
end

function Nodes.clear()
    for _, n in pairs(Nodes.all) do unregister(n) end
    Nodes.all = {}
    running = false
    LocalPlayer.state:set('nzhBusy', false, false)
end

function Nodes.portal(n)
    if running or not Heist.active then return end
    if not requiresOk(n) then return UI.notify(locale('node_locked'), 'error') end
    setBusy(true)
    DoScreenFadeOut(400)
    Wait(450)
    local ok, err = lib.callback.await('nzh:heist:portal', false, Heist.active.uid, n.id)
    if not ok and err then UI.notify(err, 'error') end
    Wait(600)
    DoScreenFadeIn(400)
    setBusy(false)
end
