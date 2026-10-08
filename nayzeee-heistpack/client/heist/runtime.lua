--[[
    Client heist runtime: holds the active heist mirror sent by the server, keeps the
    task HUD, blips and spawn triggers in sync. Nodes are handled in nodes.lua.
]]

Heist = { active = nil }

local blips = {}
local spawnPoints = {}
local outfitBackup

--[[ ------------------------------ helpers ------------------------------ ]]

local function addBlip(key, data)
    if blips[key] then RemoveBlip(blips[key]) blips[key] = nil end
    if not data or not data.coords then return end
    local c = data.coords
    local blip
    if data.entity then
        blip = AddBlipForEntity(data.entity)
    elseif data.radius and data.radius > 0 and not data.sprite then
        blip = AddBlipForRadius(c.x, c.y, c.z, data.radius + 0.0)
        SetBlipColour(blip, data.color or Config.Blips.area.color)
        SetBlipAlpha(blip, Config.Blips.area.alpha)
        blips[key] = blip
        return blip
    else
        blip = AddBlipForCoord(c.x, c.y, c.z)
    end
    local def = Config.Blips.objective
    SetBlipSprite(blip, data.sprite or def.sprite)
    SetBlipColour(blip, data.color or def.color)
    SetBlipScale(blip, data.scale or def.scale)
    SetBlipAsShortRange(blip, false)
    if data.route then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, data.color or def.color)
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.label or 'Objective')
    EndTextCommandSetBlipName(blip)
    blips[key] = blip
    return blip
end
Heist.addBlip = addBlip

function Heist.removeBlip(key)
    if blips[key] then RemoveBlip(blips[key]) blips[key] = nil end
end

local function clearBlips()
    for key, b in pairs(blips) do RemoveBlip(b) blips[key] = nil end
end

function Heist.entity(key)
    local a = Heist.active
    local netId = a and a.entities and a.entities[key]
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local ent = NetToEnt(netId)
    if ent == 0 or not DoesEntityExist(ent) then return nil end
    return ent
end

--[[ ------------------------------ HUD ------------------------------ ]]

function Heist.refreshHud(extra)
    local a = Heist.active
    if not a then return UI.hud({ show = false }) end
    local stage = a.stage
    local objectives, seen = {}, {}
    local lootDone, lootTotal = 0, 0

    for _, node in pairs(Nodes.all) do
        if node.stage == stage.index and node.required and node.type ~= 'escape' then
            local label = node.objective or node.label or node.type
            local o = seen[label]
            if not o then
                o = { label = label, count = 0, total = 0 }
                seen[label] = o
                objectives[#objectives + 1] = o
            end
            o.total = o.total + 1
            if node.done then o.count = o.count + 1 end
        elseif node.reward and not node.required then
            lootTotal = lootTotal + 1
            if node.done then lootDone = lootDone + 1 end
        end
    end
    for i = 1, #objectives do objectives[i].done = objectives[i].count >= objectives[i].total end
    if lootTotal > 0 then
        objectives[#objectives + 1] = { label = locale('hud_loot'), count = lootDone, total = lootTotal, optional = true, done = lootDone >= lootTotal }
    end

    local data = {
        show = true,
        title = a.label,
        icon = a.icon,
        location = a.loc and a.loc.label,
        task = stage.task,
        stage = stage.index,
        stages = stage.count,
        objectives = objectives,
        members = a.members,
        remaining = a.remainingAt and math.max(0, math.floor((a.remainingAt - GetGameTimer()) / 1000)) or nil,
        leader = a.leader == cache.serverId,
    }
    if extra then for k, v in pairs(extra) do data[k] = v end end
    UI.hud(data)
end

--[[ ------------------------------ spawns ------------------------------ ]]

local function clearSpawnPoints()
    for i, p in pairs(spawnPoints) do p:remove() spawnPoints[i] = nil end
end

local function syncSpawnPoints(list)
    clearSpawnPoints()
    for _, s in ipairs(list or {}) do
        if s.at then
            spawnPoints[s.index] = lib.points.new({
                coords = Utils.vec3(s.at), distance = s.distance or 180.0, index = s.index,
                onEnter = function(self)
                    if Heist.active then TriggerServerEvent('nzh:heist:spawnReady', Heist.active.uid, self.index) end
                end,
            })
        end
    end
end

--[[ ------------------------------ outfit ------------------------------ ]]

function Heist.applyOutfit()
    if not Config.Outfit.enabled or outfitBackup then return end
    local ped = cache.ped
    local list = FW.isMale() and Config.Outfit.male or Config.Outfit.female
    outfitBackup = {}
    for i = 1, #list do
        local c = list[i]
        outfitBackup[i] = { component = c.component, drawable = GetPedDrawableVariation(ped, c.component), texture = GetPedTextureVariation(ped, c.component) }
        SetPedComponentVariation(ped, c.component, c.drawable, c.texture, 0)
    end
    UI.notify(locale('outfit_on'), 'success')
end

function Heist.restoreOutfit()
    if not outfitBackup then return end
    local ped = cache.ped
    for i = 1, #outfitBackup do
        local c = outfitBackup[i]
        SetPedComponentVariation(ped, c.component, c.drawable, c.texture, 0)
    end
    outfitBackup = nil
end

function Heist.hasOutfit() return outfitBackup ~= nil end

--[[ ------------------------------ lifecycle ------------------------------ ]]

local expandKey

local function applyStage(stage)
    local a = Heist.active
    a.stage = stage
    -- add new nodes, refresh known ones
    for i = 1, #stage.nodes do Nodes.upsert(stage.nodes[i]) end
    Heist.removeBlip('stage')
    if stage.blip then
        local b = stage.blip
        addBlip('stage', { coords = b.coords, label = b.label or stage.task, sprite = b.sprite, route = b.route ~= false and not b.radius, color = b.color })
        if b.radius then addBlip('stage_area', { coords = b.coords, radius = b.radius }) else Heist.removeBlip('stage_area') end
    else
        Heist.removeBlip('stage_area')
    end
    syncSpawnPoints(stage.spawns)
    Special.onStage(stage)
    Heist.refreshHud()
end

local function begin(data)
    Heist.teardown(true)
    data.remainingAt = data.remaining and (GetGameTimer() + data.remaining * 1000) or nil
    data.entities = data.entities or {}
    data.guards = data.guards or {}
    data.flags = data.flags or {}
    Heist.active = data
    for i = 1, #(data.ipls or {}) do
        if not IsIplActive(data.ipls[i]) then RequestIpl(data.ipls[i]) end
    end
    Anim.bag(true)
    expandKey = expandKey or lib.addKeybind({
        name = 'nzh_hud_expand', description = 'Heist HUD: expand / collapse', defaultKey = Config.UI.hud.expandKey,
        onPressed = function() if Heist.active then UI.send('hudToggle') end end,
    })
    applyStage(data.stage)
    Special.onEntities()
    PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false)
end

function Heist.teardown(silent)
    if not Heist.active and silent then return end
    Heist.active = nil
    Nodes.clear()
    Special.clear()
    clearSpawnPoints()
    clearBlips()
    Props.clear()
    Drone.setZones({})
    if Carry.entity then Carry.drop() end
    Anim.bag(false)
    UI.hideTextui()
    UI.hud({ show = false })
end

--[[ ------------------------------ events ------------------------------ ]]

local function fromServer() return not GetInvokingResource() end

RegisterNetEvent('nzh:heist:begin', function(data)
    if not fromServer() then return end
    begin(data)
end)

RegisterNetEvent('nzh:heist:stage', function(stage)
    if not fromServer() or not Heist.active then return end
    applyStage(stage)
    UI.notify(stage.task, 'info')
    PlaySoundFrontend(-1, 'Objective_Complete', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false)
end)

RegisterNetEvent('nzh:heist:node', function(id, state)
    if not fromServer() or not Heist.active then return end
    Nodes.setState(id, state)
    Heist.refreshHud()
end)

RegisterNetEvent('nzh:heist:nodesAdded', function(list)
    if not fromServer() or not Heist.active then return end
    for i = 1, #list do Nodes.upsert(list[i]) end
    Heist.refreshHud()
end)

RegisterNetEvent('nzh:heist:entities', function(entities, guards)
    if not fromServer() or not Heist.active then return end
    Heist.active.entities = entities or {}
    Heist.active.guards = guards or {}
    Special.onEntities()
    Nodes.onEntities()
end)

RegisterNetEvent('nzh:heist:flags', function(flags)
    if not fromServer() or not Heist.active then return end
    Heist.active.flags = flags
    Nodes.onFlags()
end)

RegisterNetEvent('nzh:heist:members', function(members, leader)
    if not fromServer() or not Heist.active then return end
    Heist.active.members = members
    Heist.active.leader = leader
    Heist.refreshHud()
end)

RegisterNetEvent('nzh:heist:location', function(loc)
    if not fromServer() or not Heist.active then return end
    Heist.active.loc = loc
    Nodes.removeWhere(function(n) return n.select ~= nil end)
end)

RegisterNetEvent('nzh:heist:loot', function(given)
    if not fromServer() then return end
    local parts = {}
    for i = 1, #given do
        local g = given[i]
        parts[#parts + 1] = g.money and ('$' .. Utils.money(g.amount)) or (g.amount .. 'x ' .. g.label)
    end
    if #parts > 0 then
        UI.notify(locale('loot_received', table.concat(parts, ', ')), 'success')
        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    end
end)

RegisterNetEvent('nzh:heist:ended', function(result)
    if not fromServer() then return end
    Heist.teardown()
    Heist.restoreOutfit()
    if result.quiet then return end
    UI.send('result', result)
    if result.success then
        PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false)
    else
        PlaySoundFrontend(-1, 'ScreenFlash', 'MissionFailedSounds', false)
    end
end)

--[[ gas mask item toggles mask slot 46 ]]
local maskBackup
RegisterNetEvent('nzh:gasmask', function()
    if GetInvokingResource() then return end
    local ped = cache.ped
    lib.requestAnimDict('mp_masks@standard_car@ds@')
    TaskPlayAnim(ped, 'mp_masks@standard_car@ds@', 'put_on_mask', 8.0, -8.0, 800, 49, 0, false, false, false)
    Wait(600)
    if maskBackup then
        SetPedComponentVariation(ped, 1, maskBackup[1], maskBackup[2], 0)
        maskBackup = nil
    else
        maskBackup = { GetPedDrawableVariation(ped, 1), GetPedTextureVariation(ped, 1) }
        SetPedComponentVariation(ped, 1, 46, 0, 0)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    Heist.restoreOutfit()
    Heist.teardown()
end)
