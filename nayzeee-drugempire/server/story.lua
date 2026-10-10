--[[
    Story: unknown text -> Uncle Benson -> steal the RV -> starter kit + app.
    stage: none -> texted -> meet -> steal -> return -> setup
]]

Story = {}

local S = Config.Story
local mission = {}   -- src -> { veh, net }
local pending = {}   -- src -> true while a text timer is running

local function bensonSpot(P)
    return S.benson.spots[P.story.spot or 1] or S.benson.spots[1]
end
Story.bensonSpot = bensonSpot

local function forbidden(src)
    return Config.Police.forbidden and FW.isPolice(src)
end

--[[ the text ]]
function Story.sendText(src)
    local P = Profile.get(src)
    if not P or forbidden(src) then return end
    if P.story.stage ~= 'none' and P.story.stage ~= 'texted' then return end
    P.story.stage = 'texted'
    P.story.spot = P.story.spot or math.random(1, #S.benson.spots)
    P.story.textAt = os.time()
    Profile.dirty(src)
    local lines = {
        "Hey. Word is you're broke and not too picky about work.",
        "I can fix the first part. Come see me, I'll send you a pin. Come alone.",
    }
    for i = 1, #lines do Messages.push(src, 'benson', { f = 'them', m = lines[i] }, false) end
    TriggerClientEvent('nzde:story:text', src, { from = S.unknownNumber, lines = lines, timeout = S.textTimeout })
    Profile.sync(src)
end

--- arm the first (or next) text for a player
function Story.schedule(src)
    if not S.enabled or pending[src] then return end
    local P = Profile.get(src)
    if not P then return end
    local st = P.story.stage
    if st ~= 'none' and st ~= 'texted' then return end
    local delay
    if st == 'none' then
        delay = math.random(S.firstTextDelay[1], S.firstTextDelay[2])
    else
        local since = os.time() - (P.story.ignoredAt or P.story.textAt or 0)
        delay = math.max(10, S.retextMinutes * 60 - since)
    end
    pending[src] = true
    SetTimeout(delay * 1000, function()
        pending[src] = nil
        local p = Profile.get(src)
        if p and (p.story.stage == 'none' or (p.story.stage == 'texted' and p.story.ignoredAt)) then
            p.story.ignoredAt = nil
            Story.sendText(src)
        end
    end)
end

RegisterNetEvent('nzde:story:answer', function(go)
    local src = source
    local P = Profile.get(src)
    if not P or P.story.stage ~= 'texted' or not Guard.rate(src, 'story', 1000) then return end
    if go then
        P.story.stage = 'meet'
        P.story.ignoredAt = nil
        Messages.push(src, 'benson', { f = 'me', m = "On my way." }, false)
        Messages.push(src, 'benson', { f = 'them', m = "Good. Pin's on your map. Don't bring friends." }, false)
        Quests.progress(src, 'story:go')
    else
        P.story.ignoredAt = os.time()
        Messages.push(src, 'benson', { f = 'me', m = "Not interested." }, false)
        Story.schedule(src)
    end
    Profile.dirty(src)
    Profile.sync(src)
end)

--[[ RV mission ]]
local function despawnMission(src)
    local m = mission[src]
    if not m then return end
    if DoesEntityExist(m.veh) and not m.adopted then DeleteEntity(m.veh) end
    mission[src] = nil
end

local function spawnMission(src)
    local P = Profile.get(src)
    despawnMission(src)
    P.story.rvSpot = P.story.rvSpot or math.random(1, #S.rv.spots)
    local spot = S.rv.spots[P.story.rvSpot]
    local c = spot.vehicle
    local veh = CreateVehicleServerSetter(joaat(S.rv.model), 'automobile', c.x, c.y, c.z, c.w)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(veh) then
        print('^1[nzde] could not spawn the story RV (is OneSync on?)^7')
        return
    end
    SetVehicleDoorsLocked(veh, 1)
    Entity(veh).state:set('nzdeMission', Profile.identifier(src), true)
    mission[src] = { veh = veh, net = NetworkGetNetworkIdFromEntity(veh) }
    TriggerClientEvent('nzde:story:mission', src, { net = mission[src].net, spot = P.story.rvSpot })
end

function Story.missionNet(src)
    return mission[src] and mission[src].net
end

RegisterNetEvent('nzde:story:stolen', function()
    local src = source
    local P = Profile.get(src)
    local m = mission[src]
    if not P or P.story.stage ~= 'steal' or not m then return end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= m.veh then return end
    P.story.stage = 'return'
    Profile.dirty(src)
    Quests.progress(src, 'story:steal')
    Messages.push(src, 'benson', { f = 'them', m = "That's my kid. Bring her home in one piece." }, true)
    if math.random(100) <= S.rv.alertChance then
        Dispatch.alert(src, { coords = GetEntityCoords(m.veh), title = 'Stolen RV', message = 'An RV was taken by force. Armed suspects on scene.', code = '10-60' })
    end
    Profile.sync(src)
end)

--[[ talking to Benson. returns which conversation to play ]]
Guard.callback('nzde:story:talk', function(src)
    local P = Profile.get(src)
    if not P then return false end
    local spot = bensonSpot(P)
    if not Guard.near(src, spot, S.benson.talkDistance + 3.0) then return false end
    local st = P.story.stage
    if st == 'meet' then return 'intro' end
    if st == 'steal' then return 'waiting' end
    if st == 'return' then
        local m = mission[src]
        if not m or not DoesEntityExist(m.veh) then return 'waiting' end
        if #(GetEntityCoords(m.veh) - Utils.vec3(spot)) > S.rv.returnDistance then return 'noRv' end
        return 'rv'
    end
    if st == 'setup' then return 'idle' end
    return false
end)

--- the client finished a conversation. Server re-checks everything before acting.
Guard.callback('nzde:story:done', function(src, which)
    local P = Profile.get(src)
    if not P or not Guard.rate(src, 'storydone', 2000) then return false end
    local spot = bensonSpot(P)
    if not Guard.near(src, spot, S.benson.talkDistance + 3.0) then return false end

    if which == 'intro' and P.story.stage == 'meet' then
        P.story.stage = 'steal'
        P.story.met = true
        Profile.dirty(src)
        Quests.progress(src, 'story:meet')
        spawnMission(src)
        local spotCfg = S.rv.spots[P.story.rvSpot]
        Messages.push(src, 'benson', { f = 'them', m = ('The RV is at the %s. Lost boys are sitting on it. Be quick.'):format(spotCfg.label) }, false)
        Profile.sync(src)
        return true
    end

    if which == 'rv' and P.story.stage == 'return' then
        local m = mission[src]
        if not m or not DoesEntityExist(m.veh) or #(GetEntityCoords(m.veh) - Utils.vec3(spot)) > S.rv.returnDistance then return false end
        for _, it in ipairs(S.starterKit) do Inv.add(src, it.item, it.count) end
        if S.starterCash > 0 then FW.addMoney(src, 'cash', S.starterCash, 'drugempire-start') end
        P.story.stage = 'setup'
        P.story.app = true
        for _, cid in ipairs(S.starterCustomers) do Customers.unlock(src, cid, true) end
        Products.discover(src, 'ogkush')
        m.adopted = true
        RV.adopt(src, m.veh)
        mission[src] = nil
        Profile.dirty(src)
        Quests.progress(src, 'story:return')
        Profile.addXp(src, Config.Ranks.xp.rv, 'RV delivered')
        Messages.push(src, 'benson', { f = 'them', m = "The app's on your phone. Messages, contacts, deliveries, all of it. Don't lose that phone." }, false)
        Messages.push(src, 'benson', { f = 'them', m = "Go in the back of the RV and set up. Pots, soil, seed, water. Call me if you get stuck. Actually, don't." }, true)
        TriggerClientEvent('nzde:story:installed', src)
        Profile.sync(src)
        return true
    end
    return false
end)

--- called when a profile loads: put the story back where it was
function Story.restore(src)
    local P = Profile.get(src)
    if not P or not S.enabled then return end
    local st = P.story.stage
    if st == 'none' or st == 'texted' then
        Story.schedule(src)
    elseif st == 'steal' or st == 'return' then
        P.story.stage = 'steal'   -- the RV went back to its spot
        spawnMission(src)
    end
end

--- heartbeat: the mission RV blew up / sank -> put a new one at the spot
function Story.tick(src)
    local P = Profile.get(src)
    local m = mission[src]
    if not P or not m then return end
    if not DoesEntityExist(m.veh) or GetVehicleEngineHealth(m.veh) <= -3000.0 then
        P.story.stage = 'steal'
        TriggerClientEvent('nzde:notify', src, 'The RV is gone. Benson found another one at the same spot.', 'error')
        spawnMission(src)
        Profile.sync(src)
    end
end

AddEventHandler('nzde:server:unload', function(src)
    despawnMission(src)
    pending[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for src in pairs(mission) do despawnMission(src) end
end)
