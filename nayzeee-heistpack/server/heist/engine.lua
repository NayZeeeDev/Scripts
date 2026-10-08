--[[
    Heist engine (server-authoritative)

    The client never decides anything that pays out. It asks to `claim` a node
    (server checks membership, stage, distance, items, busy state) and later
    `finish`es it (server checks the same claimer, minimum time, distance again),
    and only then are doors opened, flags set and loot rolled.
]]

Engine = { instances = {}, byIdentifier = {} }

local seq = 0
local OPTIONAL_TYPES = { portal = true, scan = true, tracker = true, prop = true, hazard = true }
local CLAIM_TIMEOUT = 90000

--[[ ------------------------------ helpers ------------------------------ ]]

local function trace(inst, ...)
    Utils.debug(('[%s:%s]'):format(inst and inst.uid or '-', inst and inst.heistId or '-'), ...)
end

local function sendAll(inst, event, ...)
    for i = 1, #inst.members do
        TriggerClientEvent(event, inst.members[i], ...)
    end
end

local function isMember(inst, src)
    for i = 1, #inst.members do
        if inst.members[i] == src then return true end
    end
    return false
end

local function getInst(src, uid)
    local inst = Engine.instances[uid]
    if not inst or inst.finished or not isMember(inst, src) then return nil end
    return inst
end

local function isRequired(node)
    if node.required ~= nil then return node.required end
    if OPTIONAL_TYPES[node.type] then return false end
    if node.reward and not node.unlocks and not node.flag then return false end
    return true
end

local function publicNode(inst, node)
    local st = inst.nodeState[node.id] or {}
    local out = {}
    for k, v in pairs(node) do out[k] = v end
    out.done = st.done or false
    out.uses = st.uses or 0
    out.busy = st.busy ~= nil
    out.required = isRequired(node)
    return out
end

--- node coords on the server, resolving entity-attached nodes
local function nodeCoords(inst, node)
    if node.attach then
        local netId = inst.entities[node.attach.entity]
        local ent = netId and NetworkGetEntityFromNetworkId(netId) or 0
        if ent ~= 0 and DoesEntityExist(ent) then return GetEntityCoords(ent) end
        return nil
    end
    return node.coords and Utils.vec3(node.coords)
end

local function stageData(inst)
    local stage = inst.stages[inst.stageIndex]
    local nodes = {}
    for _, node in pairs(inst.nodes) do nodes[#nodes + 1] = publicNode(inst, node) end
    return {
        index = inst.stageIndex,
        count = #inst.stages,
        id = stage.id,
        task = stage.task,
        blip = stage.blip,
        noise = stage.noise,
        spawns = Engine.pendingSpawns(inst),
        nodes = nodes,
    }
end

--- every stage up to the current one whose spawn hasn't happened yet
function Engine.pendingSpawns(inst)
    local list = {}
    for i = 1, inst.stageIndex do
        local st = inst.stages[i]
        if st and st.spawn and not inst.spawned[i] then
            list[#list + 1] = { index = i, at = st.spawn.at or (inst.loc and inst.loc.center), distance = st.spawn.distance or 180.0 }
        end
    end
    return list
end

local function memberList(inst)
    local list = {}
    for i = 1, #inst.members do
        local src = inst.members[i]
        local p = Profile.public(src)
        list[i] = { source = src, nickname = p and p.nickname or GetPlayerName(src), avatar = p and p.avatar or 1, leader = src == inst.leader }
    end
    return list
end

function Engine.clientData(inst)
    local def = Heists.defs[inst.heistId]
    return {
        uid = inst.uid,
        heistId = inst.heistId,
        label = def.label,
        icon = def.icon,
        ipls = def.ipls,
        leader = inst.leader,
        members = memberList(inst),
        loc = inst.loc and { label = inst.loc.label, center = inst.loc.center } or nil,
        stage = stageData(inst),
        flags = inst.flags,
        entities = inst.entities,
        guards = inst.guards,
        remaining = inst.deadline and math.max(0, inst.deadline - os.time()) or nil,
        elapsed = os.time() - inst.startedAt,
        lootTotal = inst.lootTotal,
        lootCount = inst.lootCount or 0,
    }
end

function Engine.publicSummary(uid)
    local inst = Engine.instances[uid]
    if not inst then return nil end
    local def = Heists.defs[inst.heistId]
    local stage = inst.stages[inst.stageIndex]
    return { uid = uid, heistId = inst.heistId, label = def.label, task = stage and stage.task, stage = inst.stageIndex, stages = #inst.stages }
end

function Engine.syncCrew(uid)
    local inst = Engine.instances[uid]
    if not inst then return end
    local crew = Crew.byId[inst.crewId]
    if crew then inst.leader = crew.leader end
    sendAll(inst, 'nzh:heist:members', memberList(inst), inst.leader)
end

--[[ ------------------------------ doors ------------------------------ ]]

local doorState = {}

local function pushDoors()
    GlobalState:set('nzh:doors', doorState, true)
end

local function doorKey(inst, id)
    return ('%s:%s:%s'):format(inst.heistId, inst.locIndex, id)
end

local function registerDoors(inst)
    if not inst.loc or not inst.loc.doors then return end
    for id, d in pairs(inst.loc.doors) do
        local key = doorKey(inst, id)
        local resetTimer = inst.doorTimers and inst.doorTimers[key]
        if resetTimer then inst.doorTimers[key] = nil end
        doorState[key] = {
            models = d.models or { d.model }, coords = Utils.vec3(d.coords), radius = d.radius or 3.0,
            kind = d.kind or 'gate', delta = d.delta or -90.0, open = false, at = os.time(),
        }
        inst.doorKeys[#inst.doorKeys + 1] = key
    end
    pushDoors()
end

function Engine.openDoor(inst, id)
    local key = doorKey(inst, id)
    local d = doorState[key]
    if not d or d.open then return end
    d.open = true
    d.at = os.time()
    pushDoors()
    trace(inst, 'door open', id)
end

local function scheduleDoorReset(keys)
    SetTimeout(Config.Gameplay.doorResetMinutes * 60000, function()
        for i = 1, #keys do doorState[keys[i]] = nil end
        pushDoors()
    end)
end

--[[ ------------------------------ stages ------------------------------ ]]

local function addNode(inst, node, stageIdx)
    if not node.id then
        seq = seq + 1
        node.id = 'n' .. seq
    end
    node.stage = stageIdx
    inst.nodes[node.id] = node
    inst.nodeState[node.id] = { done = false, uses = 0 }
    return node
end

local function buildStages(inst)
    local def = Heists.defs[inst.heistId]
    local ok, stages = pcall(def.stages, inst.loc, inst)
    if not ok or type(stages) ~= 'table' then
        print(('^1[nzh] heist %s stages() error: %s^7'):format(inst.heistId, tostring(stages)))
        return false
    end
    if def.escape then
        stages[#stages + 1] = {
            id = 'escape',
            task = locale('task_escape', math.floor(def.escape)),
            blip = { coords = inst.loc.center, radius = def.escape, label = locale('blip_escape') },
            nodes = { { id = 'escape', type = 'escape', coords = inst.loc.escapeFrom or inst.loc.center, radius = def.escape } },
        }
    end
    for i = 1, #stages do
        stages[i].index = i
        stages[i].nodeIds = {}
    end
    return stages
end

local function stageComplete(inst)
    local stage = inst.stages[inst.stageIndex]
    local total, done = 0, 0
    for i = 1, #stage.nodeIds do
        local node = inst.nodes[stage.nodeIds[i]]
        if node and isRequired(node) then
            total = total + 1
            if inst.nodeState[node.id].done then done = done + 1 end
        end
    end
    local need = total
    if type(stage.complete) == 'number' then need = math.min(stage.complete, total) end
    return done >= need
end

function Engine.beginStage(inst, idx, silent)
    if inst.finished then return end
    local stage = inst.stages[idx]
    if not stage then return Engine.finish(inst, true) end
    inst.stageIndex = idx
    for i = 1, #(stage.nodes or {}) do
        local node = addNode(inst, Utils.copy(stage.nodes[i]), idx)
        stage.nodeIds[#stage.nodeIds + 1] = node.id
    end
    if stage.alert then
        local c = stage.blip and stage.blip.coords or inst.loc.center
        Engine.alert(inst, inst.leader, c)
    end
    trace(inst, 'stage', idx, stage.id)
    if not silent then sendAll(inst, 'nzh:heist:stage', stageData(inst)) end
    local crew = Crew.byId[inst.crewId]
    if crew then Crew.broadcast(crew) end
    Watchers.ensure()
    -- stages without required nodes (pure loot stages) chain straight through
    if stageComplete(inst) and #stage.nodeIds > 0 then
        return Engine.advance(inst)
    end
end

function Engine.advance(inst)
    if inst.finished then return end
    if not stageComplete(inst) then return end
    local stage = inst.stages[inst.stageIndex]
    if stage.onComplete and stage.onComplete.flag then Engine.setFlag(inst, stage.onComplete.flag) end
    if inst.stageIndex >= #inst.stages then
        return Engine.finish(inst, true)
    end
    Engine.beginStage(inst, inst.stageIndex + 1)
end

--[[ ------------------------------ node completion ------------------------------ ]]

function Engine.setFlag(inst, flag)
    if inst.flags[flag] then return end
    inst.flags[flag] = true
    for _, v in ipairs(inst.vehicleLocks) do
        if v.flag == flag then
            local ent = NetworkGetEntityFromNetworkId(v.netId)
            if ent ~= 0 then SetVehicleDoorsLocked(ent, 1) end
        end
    end
    sendAll(inst, 'nzh:heist:flags', inst.flags)
end

local function selectLocation(inst, idx)
    local def = Heists.defs[inst.heistId]
    inst.locIndex = idx
    inst.loc = def.locations[idx]
    Cooldowns.setLocation(inst.heistId, idx, def.locationCooldown or def.cooldown)
    local stages = buildStages(inst)
    if not stages then return Engine.fail(inst, 'config') end
    -- keep the finished select stage at index 1
    local first = inst.stages[1]
    inst.stages = { first }
    for i = 1, #stages do
        stages[i].index = i + 1
        inst.stages[i + 1] = stages[i]
    end
    registerDoors(inst)
    -- drop every other location marker
    for id, node in pairs(inst.nodes) do
        if node.select and node.select ~= idx then
            inst.nodes[id] = nil
            inst.nodeState[id] = nil
        end
    end
    sendAll(inst, 'nzh:heist:location', { label = inst.loc.label, center = inst.loc.center })
end

--- Marks a node done (or one more use) and applies its effects. Returns loot given.
function Engine.complete(inst, node, src)
    local st = inst.nodeState[node.id]
    st.uses = st.uses + 1
    st.busy = nil
    local maxUses = node.uses or 1
    if st.uses >= maxUses then st.done = true end

    local given
    if node.unlocks then
        for i = 1, #node.unlocks do Engine.openDoor(inst, node.unlocks[i]) end
    end
    if node.flag then Engine.setFlag(inst, node.flag) end
    if node.reward and src then
        given = Rewards.roll(inst, src, node.reward, node.rolls)
        if node.notifyLoot ~= false and given and #given > 0 then
            TriggerClientEvent('nzh:heist:loot', src, given)
        end
    end
    if node.select then selectLocation(inst, node.select) end
    if node.message then sendAll(inst, 'nzh:notify', node.message, 'info') end

    sendAll(inst, 'nzh:heist:node', node.id, { done = st.done, uses = st.uses, busy = false, by = src })
    trace(inst, 'node done', node.id, st.uses .. '/' .. maxUses)

    if node.select then
        Engine.beginStage(inst, 2)
    else
        Engine.advance(inst)
    end
    return given
end

--[[ ------------------------------ police ------------------------------ ]]

function Engine.alert(inst, src, coords)
    if inst.alerted and GetGameTimer() - inst.alerted < 60000 then return end
    inst.alerted = GetGameTimer()
    local def = Heists.defs[inst.heistId]
    Dispatch.alert(src or inst.leader, {
        coords = coords or inst.loc.center,
        title = def.alertTitle or def.label,
        message = def.alertMessage or locale('alert_message', def.label),
        heist = inst.heistId,
    })
end

--[[ ------------------------------ start ------------------------------ ]]

local function runningCount(heistId)
    local n = 0
    for _, inst in pairs(Engine.instances) do
        if inst.heistId == heistId and not inst.finished then n = n + 1 end
    end
    return n
end

local function locationBusy(heistId, idx)
    for _, inst in pairs(Engine.instances) do
        if inst.heistId == heistId and not inst.finished and inst.locIndex == idx then return true end
    end
    return Cooldowns.locationRemaining(heistId, idx) > 0
end

local function freeLocations(def)
    local list = {}
    for i = 1, #def.locations do
        if not locationBusy(def.id, i) then list[#list + 1] = i end
    end
    return list
end

local function canAccessMenu(src)
    local job = FW.job(src)
    if Utils.contains(Config.Menu.forbiddenJobs, job.name) then return false end
    if #Config.Menu.allowedJobs > 0 then
        return Utils.contains(Config.Menu.allowedJobs, job.name) or Utils.contains(Config.Menu.allowedJobs, job.gang)
    end
    return true
end
Engine.canAccessMenu = canAccessMenu

--- Full validation. Returns ok, errorMessage
function Engine.canStart(src, heistId)
    local def = Heists.defs[heistId]
    if not def then return false, locale('heist_invalid') end
    local crew = Crew.ensure(src)
    if crew.leader ~= src then return false, locale('only_leader') end
    if crew.heist then return false, locale('crew_busy') end
    local n = #crew.members
    if n < def.members.min then return false, locale('heist_min_members', def.members.min) end
    if n > def.members.max then return false, locale('heist_max_members', def.members.max) end
    if not Crew.allReady(crew) then return false, locale('crew_not_ready') end

    local cd = Cooldowns.heistRemaining(heistId)
    if cd > 0 then return false, locale('heist_cooldown', math.ceil(cd / 60)) end
    if runningCount(heistId) >= def.simultaneous then return false, locale('heist_running') end
    if #freeLocations(def) == 0 then return false, locale('heist_no_location') end
    if def.police > 0 and FW.policeCount() < def.police then return false, locale('heist_police', def.police) end

    for i = 1, n do
        local m = crew.members[i]
        local p = Profile.get(m)
        local name = p and p.nickname or GetPlayerName(m)
        if not canAccessMenu(m) then return false, locale('member_job', name) end
        if Profile.level(m) < def.level then return false, locale('member_level', name, def.level) end
        local pcd = p and Cooldowns.playerRemaining(p.identifier) or 0
        if pcd > 0 then return false, locale('member_cooldown', name, math.ceil(pcd / 60)) end
        if Engine.byIdentifier[p and p.identifier or ''] then return false, locale('member_busy', name) end
    end

    for i = 1, #def.requiredItems do
        local req = def.requiredItems[i]
        local found = false
        for j = 1, n do
            if Inv.has(crew.members[j], req.name, req.count or 1) then found = true break end
        end
        if not found then return false, locale('missing_item', req.label or req.name) end
    end
    return true
end

function Engine.start(src, heistId)
    local ok, err = Engine.canStart(src, heistId)
    if not ok then return false, err end
    local def = Heists.defs[heistId]
    local crew = Crew.get(src)

    seq = seq + 1
    local inst = {
        uid = 'h' .. seq,
        heistId = heistId,
        crewId = crew.id,
        leader = crew.leader,
        members = {},
        identifiers = {},
        nodes = {}, nodeState = {},
        flags = {}, entities = {}, guards = {}, vehicleLocks = {},
        spawned = {}, spawnClaims = {},
        doorKeys = {}, doorTimers = {},
        earned = {}, lootCount = 0,
        startedAt = os.time(),
        deadline = def.timeLimit > 0 and (os.time() + def.timeLimit * 60) or nil,
        bucket = 7000 + seq,
    }
    for i = 1, #crew.members do
        local m = crew.members[i]
        inst.members[i] = m
        local p = Profile.get(m)
        if p then
            inst.identifiers[p.identifier] = m
            Engine.byIdentifier[p.identifier] = inst.uid
        end
    end

    if def.locationMode == 'select' then
        local free = freeLocations(def)
        local nodes = {}
        for i = 1, #free do
            local loc = def.locations[free[i]]
            nodes[i] = {
                id = 'select_' .. free[i], type = 'zone', select = free[i], coords = loc.select or loc.center,
                radius = loc.selectRadius or 12.0, label = loc.label, blip = { label = loc.label, sprite = def.blipSprite },
            }
        end
        inst.loc = { label = def.label, center = def.locations[free[1]].center }
        inst.stages = { { id = 'select', index = 1, nodeIds = {}, task = def.selectLabel or locale('task_select'), nodes = nodes, complete = 1 } }
    else
        local free = freeLocations(def)
        inst.locIndex = free[math.random(#free)]
        inst.loc = def.locations[inst.locIndex]
        Cooldowns.setLocation(heistId, inst.locIndex, def.locationCooldown or def.cooldown)
        local stages = buildStages(inst)
        if not stages then return false, locale('heist_config_error') end
        inst.stages = stages
        registerDoors(inst)
    end

    inst.lootTotal = 0
    SetRoutingBucketPopulationEnabled(inst.bucket, false)
    Engine.instances[inst.uid] = inst
    crew.heist = inst.uid
    crew.ready = {}
    Cooldowns.setHeist(heistId, def.cooldown)

    inst.stageIndex = 1
    -- stage 1 nodes are added before the first sync so the client gets everything in one payload
    Engine.beginStage(inst, 1, true)
    sendAll(inst, 'nzh:heist:begin', Engine.clientData(inst))
    Crew.broadcast(crew)

    Logs.send('Heist started', ('**%s** started by %s (%d members) at %s'):format(def.label, GetPlayerName(src), #inst.members, inst.loc.label or '?'))
    trace(inst, 'started with', #inst.members, 'members')
    return true
end

--[[ ------------------------------ end ------------------------------ ]]

local function cleanupEntities(inst)
    local list = {}
    for _, netId in pairs(inst.entities) do list[#list + 1] = netId end
    for _, group in pairs(inst.guards) do
        for i = 1, #group do list[#list + 1] = group[i] end
    end
    SetTimeout(inst.success and 45000 or 15000, function()
        for i = 1, #list do
            local ent = NetworkGetEntityFromNetworkId(list[i])
            if ent ~= 0 and DoesEntityExist(ent) then
                local occupied = false
                if GetEntityType(ent) == 2 then
                    for seat = -1, 6 do
                        local ped = GetPedInVehicleSeat(ent, seat)
                        if ped ~= 0 and IsPedAPlayer(ped) then occupied = true break end
                    end
                end
                if not occupied then DeleteEntity(ent) end
            end
        end
    end)
end

local function teardown(inst)
    inst.finished = true
    for identifier, _ in pairs(inst.identifiers) do
        if Engine.byIdentifier[identifier] == inst.uid then Engine.byIdentifier[identifier] = nil end
    end
    for i = 1, #inst.members do
        local src = inst.members[i]
        if GetPlayerRoutingBucket(src) == inst.bucket then SetPlayerRoutingBucket(src, 0) end
    end
    scheduleDoorReset(inst.doorKeys)
    cleanupEntities(inst)
    local crew = Crew.byId[inst.crewId]
    if crew and crew.heist == inst.uid then
        crew.heist = nil
        Crew.broadcast(crew)
    end
    SetTimeout(5000, function() Engine.instances[inst.uid] = nil end)
end

function Engine.finish(inst, success, reason)
    if inst.finished then return end
    local def = Heists.defs[inst.heistId]
    inst.success = success
    local duration = os.time() - inst.startedAt
    local results = {}
    local members = inst.members

    if success then
        results = Rewards.completion(inst, members)
    end

    local crewIds, payout = {}, 0
    for i = 1, #members do
        local src = members[i]
        local p = Profile.get(src)
        if p then
            crewIds[#crewIds + 1] = p.identifier
            Cooldowns.setPlayer(p.identifier, def.playerCooldown)
        end
        local earned = inst.earned[src] or 0
        payout = payout + earned
        Profile.record(src, inst.heistId, success, earned, duration)
        local r = results[src] or {}
        TriggerClientEvent('nzh:heist:ended', src, {
            success = success, reason = reason, label = def.label, duration = duration,
            xp = r.xp or 0, money = r.money or 0, earned = earned, leveled = r.leveled, level = r.level,
            loot = inst.lootCount or 0,
        })
    end

    DB.addHistory({ heist = inst.heistId, location = inst.loc and inst.loc.label, crew = crewIds, success = success, payout = payout, duration = duration, reason = reason })
    Logs.send(success and 'Heist completed' or 'Heist failed',
        ('**%s** %s in %ds - total $%s%s'):format(def.label, success and 'completed' or 'failed', duration, Utils.money(payout), reason and (' (' .. reason .. ')') or ''),
        success and 3066993 or 15158332)
    trace(inst, success and 'completed' or ('failed: ' .. tostring(reason)))
    teardown(inst)
end

function Engine.fail(inst, reason)
    Engine.finish(inst, false, reason)
end

--[[ ------------------------------ membership ------------------------------ ]]

function Engine.memberLeft(uid, src, why)
    local inst = Engine.instances[uid]
    if not inst or inst.finished then return end
    for i = #inst.members, 1, -1 do
        if inst.members[i] == src then table.remove(inst.members, i) end
    end
    for _, st in pairs(inst.nodeState) do
        if st.busy == src then st.busy = nil end
    end
    if why ~= 'disconnect' then
        for identifier, s in pairs(inst.identifiers) do
            if s == src then
                inst.identifiers[identifier] = nil
                Engine.byIdentifier[identifier] = nil
            end
        end
        TriggerClientEvent('nzh:heist:ended', src, { success = false, reason = 'left', label = Heists.defs[inst.heistId].label, quiet = true })
        if GetPlayerRoutingBucket(src) == inst.bucket then SetPlayerRoutingBucket(src, 0) end
    else
        for identifier, s in pairs(inst.identifiers) do
            if s == src then inst.identifiers[identifier] = false end
        end
    end
    if inst.spawnClaims then
        for idx, claimer in pairs(inst.spawnClaims) do
            if claimer == src and not inst.spawned[idx] then inst.spawnClaims[idx] = nil end
        end
    end
    if #inst.members == 0 then
        for _, s in pairs(inst.identifiers) do
            if s == false then
                inst.emptySince = os.time()
                return
            end
        end
        return Engine.fail(inst, 'abandoned')
    end
    Engine.syncCrew(uid)
end

--- Called when a character loads; puts them back into their running heist
function Engine.restore(src)
    local identifier = FW.identifier(src)
    local uid = identifier and Engine.byIdentifier[identifier]
    local inst = uid and Engine.instances[uid]
    if not inst or inst.finished or inst.identifiers[identifier] ~= false then return end
    local crew = Crew.byId[inst.crewId]
    if not crew then
        crew = Crew.ensure(src)
        inst.crewId = crew.id
        crew.heist = uid
    end
    inst.identifiers[identifier] = src
    inst.members[#inst.members + 1] = src
    inst.emptySince = nil
    if Crew.of[src] ~= crew.id then Crew.join(src, crew) end
    if #crew.members == 1 then crew.leader = src end
    inst.leader = crew.leader
    TriggerClientEvent('nzh:heist:begin', src, Engine.clientData(inst))
    FW.notify(src, locale('heist_restored'), 'success')
    Engine.syncCrew(uid)
end

--[[ ------------------------------ callbacks ------------------------------ ]]

Guard.callback('nzh:heist:list', function(src)
    local list = {}
    local level = Profile.level(src)
    for i = 1, #Heists.order do
        local id = Heists.order[i]
        local s = Heists.summary(id)
        s.cooldown = Cooldowns.heistRemaining(id)
        s.running = runningCount(id)
        s.simultaneous = Heists.defs[id].simultaneous
        s.locked = level < s.level
        s.featured = GlobalState['nzh:featured'] == id
        list[#list + 1] = s
    end
    local p = Profile.get(src)
    return { heists = list, police = FW.policeCount(), playerCooldown = p and Cooldowns.playerRemaining(p.identifier) or 0 }
end)

Guard.callback('nzh:heist:start', function(src, heistId)
    if not Guard.rate(src, 'start', 2000) then return false, locale('slow_down') end
    return Engine.start(src, heistId)
end)

Guard.callback('nzh:heist:stop', function(src)
    local crew = Crew.get(src)
    if not crew or not crew.heist then return false end
    if crew.leader ~= src then return false, locale('only_leader') end
    local inst = Engine.instances[crew.heist]
    if inst then Engine.fail(inst, 'stopped') end
    return true
end)

Guard.callback('nzh:heist:claim', function(src, uid, nodeId, extra)
    local inst = getInst(src, uid)
    if not inst then return false end
    local node = inst.nodes[nodeId]
    local st = node and inst.nodeState[nodeId]
    if not node or not st or st.done then return false, locale('node_unavailable') end
    if st.busy and st.busy ~= src and GetGameTimer() - st.claimAt < CLAIM_TIMEOUT then return false, locale('node_busy') end
    if node.requires then
        for i = 1, #node.requires do
            local r = inst.nodeState[node.requires[i]]
            if not r or not r.done then return false, locale('node_locked') end
        end
    end
    if node.requiresFlag and not inst.flags[node.requiresFlag] then return false, locale('node_locked') end

    local coords
    if node.dynamic then
        coords = type(extra) == 'table' and extra.coords and vec3(extra.coords.x, extra.coords.y, extra.coords.z)
        if not coords then return false end
        local key = ('%d:%d'):format(math.floor(coords.x), math.floor(coords.y))
        if (inst.usedSpots or {})[key] or Engine.spotCooldown(key) then return false, locale('node_used') end
        st.spot = key
        st.spotCoords = coords
    else
        coords = nodeCoords(inst, node)
    end
    local claimRange = node.claimRange or (node.type == 'dronedrop' and 300.0) or 6.0
    if coords and not Guard.near(src, coords, (node.radius or 2.0) + claimRange) then
        return false, locale('too_far')
    end

    if node.item then
        local name = node.item.name
        if not Inv.has(src, name, node.item.count or 1) then return false, locale('missing_item', node.item.label or Inv.label(name)) end
    end
    if type(extra) == 'table' and extra.method and node.methods then
        local m = node.methods[extra.method]
        if not m then return false end
        if m.item and not Inv.has(src, m.item, 1) then return false, locale('missing_item', m.label or Inv.label(m.item)) end
        st.method = extra.method
    end

    st.busy = src
    st.claimAt = GetGameTimer()
    if node.alert and math.random() < node.alert then Engine.alert(inst, src, coords) end
    sendAll(inst, 'nzh:heist:node', nodeId, { done = false, uses = st.uses, busy = true })
    return true, { speed = Utils.perks(Profile.level(src)).speed }
end)

Guard.callback('nzh:heist:finish', function(src, uid, nodeId, success)
    local inst = getInst(src, uid)
    if not inst then return false end
    local node = inst.nodes[nodeId]
    local st = node and inst.nodeState[nodeId]
    if not node or not st or st.busy ~= src then return false end

    local elapsed = GetGameTimer() - st.claimAt
    local minTime = node.minTime or math.min((node.duration or 2000) * 0.35, 6000)
    if success and elapsed < minTime then
        Guard.flag(src, ('node %s finished too fast (%dms < %dms)'):format(nodeId, elapsed, minTime))
        success = false
    end
    local coords = st.spotCoords or nodeCoords(inst, node)
    local range = (node.radius or 2.0) + (node.finishRange or (node.type == 'dronedrop' and 300.0) or 8.0)
    if success and coords and not node.carry and not Guard.near(src, coords, range) then success = false end
    if success and node.carry and coords and not Guard.near(src, coords, node.carry.maxDistance or 120.0) then success = false end

    local item = node.item
    local method = st.method and node.methods and node.methods[st.method]
    if method and method.item then item = { name = method.item, remove = method.remove } end

    if not success then
        st.busy = nil
        if item and item.removeOnFail then Inv.remove(src, item.name, 1) end
        if node.failAlert then Engine.alert(inst, src, coords) end
        sendAll(inst, 'nzh:heist:node', nodeId, { done = false, uses = st.uses, busy = false })
        return false
    end

    if item and item.remove then
        if item.remove == true or math.random() < item.remove then
            Inv.remove(src, item.name, item.count or 1)
        end
    end
    if st.spot then
        inst.usedSpots = inst.usedSpots or {}
        inst.usedSpots[st.spot] = true
        Engine.spotCooldown(st.spot, node.spotCooldown or 60)
        st.spot = nil
    end
    local saveReward = node.reward
    if method and method.reward then node.reward = method.reward end
    local given = Engine.complete(inst, node, src)
    node.reward = saveReward
    return true, given
end)

--- `zone` nodes: reaching an area
Guard.callback('nzh:heist:reach', function(src, uid, nodeId)
    local inst = getInst(src, uid)
    if not inst then return false end
    local node = inst.nodes[nodeId]
    local st = node and inst.nodeState[nodeId]
    if not node or node.type ~= 'zone' or st.done then return false end
    if not Guard.near(src, node.coords, (node.radius or 10.0) + 10.0) then return false end
    if node.requiresFlag and not inst.flags[node.requiresFlag] then return false end
    Engine.complete(inst, node, src)
    return true, node.decoy
end)

--- `portal` nodes: enter / exit interiors (optionally into a private routing bucket)
Guard.callback('nzh:heist:portal', function(src, uid, nodeId)
    local inst = getInst(src, uid)
    if not inst then return false end
    local node = inst.nodes[nodeId]
    if not node or node.type ~= 'portal' then return false end
    if not Guard.near(src, node.coords, 4.0) then return false end
    if node.requires then
        for i = 1, #node.requires do
            local r = inst.nodeState[node.requires[i]]
            if not r or not r.done then return false, locale('node_locked') end
        end
    end
    local ped = GetPlayerPed(src)
    local t = node.target
    if node.bucket == 'enter' then
        SetPlayerRoutingBucket(src, inst.bucket)
    elseif node.bucket == 'exit' then
        SetPlayerRoutingBucket(src, 0)
    end
    SetEntityCoords(ped, t.x, t.y, t.z, false, false, false, false)
    if t.w then SetEntityHeading(ped, t.w) end
    return true
end)

--- `scan` nodes: client reports searchable props found in an interior; server turns them into loot nodes
Guard.callback('nzh:heist:scan', function(src, uid, nodeId, found)
    local inst = getInst(src, uid)
    if not inst then return false end
    local node = inst.nodes[nodeId]
    local st = node and inst.nodeState[nodeId]
    if not node or node.type ~= 'scan' or st.done or type(found) ~= 'table' then return false end
    if not Guard.near(src, node.coords, node.radius + 5.0) then return false end
    st.done = true
    local added = {}
    local max = node.max or 12
    for i = 1, math.min(#found, max) do
        local f = found[i]
        local spec = node.models[f.model]
        if spec and f.coords and #(Utils.vec3(f.coords) - Utils.vec3(node.coords)) <= node.radius then
            local child = addNode(inst, {
                id = nodeId .. '_' .. i, type = spec.carry and 'carry' or 'interact', label = spec.label, icon = spec.icon,
                coords = Utils.vec3(f.coords), radius = 1.0, action = spec.action or 'search', duration = spec.duration or 5000,
                reward = spec.reward, carry = spec.carry, prop = spec.carry and { model = f.model, existing = true } or nil,
                noise = spec.noise, required = false,
            }, inst.stageIndex)
            added[#added + 1] = publicNode(inst, child)
        end
    end
    sendAll(inst, 'nzh:heist:nodesAdded', added)
    sendAll(inst, 'nzh:heist:node', nodeId, { done = true, uses = 1, busy = false })
    return true
end)

--- house noise meter maxed
Guard.callback('nzh:heist:noise', function(src, uid)
    local inst = getInst(src, uid)
    if not inst or inst.noiseAlerted then return false end
    inst.noiseAlerted = true
    Engine.alert(inst, src, inst.loc.center)
    sendAll(inst, 'nzh:notify', locale('noise_alert'), 'error')
    return true
end)

--[[ ------------------------------ spawns ------------------------------ ]]

RegisterNetEvent('nzh:heist:spawnReady', function(uid, idx)
    local src = source
    local inst = getInst(src, uid)
    if not inst or inst.spawned[idx] or inst.spawnClaims[idx] then return end
    local stage = inst.stages[idx]
    if not stage or not stage.spawn or idx > inst.stageIndex then return end
    inst.spawnClaims[idx] = src
    TriggerClientEvent('nzh:heist:doSpawn', src, uid, idx, stage.spawn)
    -- if the spawner never answers, let someone else try
    SetTimeout(25000, function()
        if not inst.spawned[idx] and inst.spawnClaims[idx] == src then inst.spawnClaims[idx] = nil end
    end)
end)

local function validNet(netId)
    if type(netId) ~= 'number' then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not DoesEntityExist(ent) then return nil end
    return ent
end

Guard.callback('nzh:heist:spawned', function(src, uid, idx, result)
    local inst = getInst(src, uid)
    if not inst or inst.spawned[idx] or inst.spawnClaims[idx] ~= src or type(result) ~= 'table' then return false end
    local stage = inst.stages[idx]
    inst.spawned[idx] = true

    for group, list in pairs(result.guards or {}) do
        inst.guards[group] = inst.guards[group] or {}
        for i = 1, #list do
            local ent = validNet(list[i])
            if ent then
                SetEntityOrphanMode(ent, 2)
                Entity(ent).state:set('nzhGuard', inst.uid, true)
                local g = inst.guards[group]
                g[#g + 1] = list[i]
            end
        end
    end
    for key, netId in pairs(result.entities or {}) do
        local ent = validNet(netId)
        if ent then
            SetEntityOrphanMode(ent, 2)
            inst.entities[key] = netId
            Entity(ent).state:set('nzhHeist', inst.uid, true)
        end
    end
    -- vehicle locks are applied server-side so they sync for everyone
    for _, v in ipairs(stage.spawn.vehicles or {}) do
        local ent = v.key and inst.entities[v.key] and validNet(inst.entities[v.key])
        if ent then
            if v.lockedUntil and not inst.flags[v.lockedUntil] then
                SetVehicleDoorsLocked(ent, 2)
                inst.vehicleLocks[#inst.vehicleLocks + 1] = { netId = inst.entities[v.key], flag = v.lockedUntil }
            elseif v.locked then
                SetVehicleDoorsLocked(ent, 2)
            end
        end
    end
    sendAll(inst, 'nzh:heist:entities', inst.entities, inst.guards)
    trace(inst, 'spawned stage', idx)
    Watchers.ensure()
    return true
end)

--- deliver nodes may need to know the vehicle is a heist vehicle for qbx keys
RegisterNetEvent('nzh:keys:qbx', function(netId)
    local src = source
    local ent = validNet(netId)
    if not ent then return end
    local state = Entity(ent).state
    if not state.nzhHeist and not state.nzhCrewVehicle then return end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, ent) end)
end)

--[[ dynamic spot cooldowns (ATMs etc.) ]]
local spotCd = {}
function Engine.spotCooldown(key, minutes)
    if minutes then spotCd[key] = os.time() + minutes * 60 return end
    local t = spotCd[key]
    if t and t > os.time() then return true end
    spotCd[key] = nil
    return false
end
