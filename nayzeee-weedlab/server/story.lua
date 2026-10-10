--[[
    Story: find Uncle Benson -> steal the RV from the Ballas -> lose them -> collect the seeds
    from a dead drop -> gear up at a hardware store -> first harvest -> first package.

    stage: none -> steal -> escape -> deaddrop -> hardware -> setup -> pack -> sell -> done
]]

Story = {}

local S, B = Config.Story, Config.Benson
local mission = {}   -- src -> { veh, net, spot }
local drops = {}     -- src -> searching since (game timer)
local escaping = false

--[[ Benson's spot: one for the whole server, picked on start ]]
Story.spot = B.rotate and math.random(1, #B.spots) or math.min(B.fixed or 1, #B.spots)
GlobalState.nzwlBenson = Story.spot
print(('^2[%s]^7 Uncle Benson is at spot %d this restart'):format(RES, Story.spot))

local function bensonCoords()
    return B.spots[Story.spot]
end

local function forbidden(src)
    return Config.Police.forbidden and FW.isPolice(src)
end

local function text(src, lines, title)
    TriggerClientEvent('nzwl:text', src, { from = B.name, lines = lines, title = title })
end

--[[ ─────────────── the RV mission ─────────────── ]]
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
    local c = S.rv.spots[P.story.rvSpot].vehicle
    local veh = CreateVehicleServerSetter(joaat(S.rv.model), 'automobile', c.x, c.y, c.z, c.w)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(veh) then
        print('^1[nzwl] could not spawn the story RV (is OneSync on?)^7')
        return
    end
    SetVehicleDoorsLocked(veh, 1)
    Entity(veh).state:set('nzwlMission', Profile.identifier(src), true)
    mission[src] = { veh = veh, net = NetworkGetNetworkIdFromEntity(veh), spot = P.story.rvSpot }
    TriggerClientEvent('nzwl:story:mission', src, { net = mission[src].net, spot = P.story.rvSpot })
end

function Story.missionNet(src)
    return mission[src] and mission[src].net
end

local function escaped(src)
    local P = Profile.get(src)
    local m = mission[src]
    if not P or not m or P.story.stage ~= 'escape' then return end
    m.adopted = true
    Labs.adoptRV(src, m.veh)
    mission[src] = nil
    P.story.stage = 'deaddrop'
    P.story.drop = math.random(1, #S.deadDrop.spots)
    Profile.dirty(src)
    Profile.addXp(src, Config.Levels.xp.rv, 'RV stolen')
    TriggerClientEvent('nzwl:story:clearMission', src)
    text(src, {
        "Ha! Look at you. The RV's yours now, kid. That's your lab.",
        "Seeds are in a dead drop. Pin's on your map. Go get 'em.",
    }, 'Unknown number')
    Profile.sync(src)
end

-- runs only while somebody is escaping in the stolen RV
local function watchEscapes()
    if escaping then return end
    escaping = true
    CreateThread(function()
        while next(mission) do
            for src, m in pairs(mission) do
                local P = Profile.get(src)
                if P and P.story.stage == 'escape' and DoesEntityExist(m.veh) then
                    local spot = S.rv.spots[m.spot].vehicle
                    if #(GetEntityCoords(m.veh) - Utils.vec3(spot)) >= S.rv.escapeDistance then escaped(src) end
                end
            end
            Wait(2000)
        end
        escaping = false
    end)
end

RegisterNetEvent('nzwl:story:stolen', function()
    local src = source
    local P = Profile.get(src)
    local m = mission[src]
    if not P or P.story.stage ~= 'steal' or not m then return end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= m.veh then return end
    P.story.stage = 'escape'
    Profile.dirty(src)
    if math.random(100) <= S.rv.alertChance then
        Dispatch.alert(src, { coords = GetEntityCoords(m.veh), title = 'Stolen RV', message = 'Shots fired. An RV was taken from a gang hangout.', code = '10-60' })
    end
    text(src, { "That's my kid! Now lose those Ballas before they follow you home." })
    Profile.sync(src)
    watchEscapes()
end)

--[[ ─────────────── talking to Benson ─────────────── ]]
Guard.callback('nzwl:story:talk', function(src)
    local P = Profile.get(src)
    if not P then return false end
    if not Guard.near(src, bensonCoords(), B.talkDistance + 3.0) then return false end
    if forbidden(src) then return 'cop' end
    local st = P.story.stage
    if st == 'none' then return 'intro' end
    if st == 'steal' or st == 'escape' then return 'waiting' end
    if st == 'deaddrop' then return 'drop' end
    if st == 'hardware' then return 'hardware' end
    return 'idle'
end)

Guard.callback('nzwl:story:accept', function(src)
    local P = Profile.get(src)
    if not P or P.story.stage ~= 'none' or forbidden(src) or not Guard.rate(src, 'storyaccept', 2000) then return false end
    if not Guard.near(src, bensonCoords(), B.talkDistance + 3.0) then return false end
    P.story.stage = 'steal'
    P.story.met = os.time()
    Profile.dirty(src)
    spawnMission(src)
    Profile.sync(src)
    return true
end)

--[[ ─────────────── dead drop ─────────────── ]]
local function dropCoords(P)
    return S.deadDrop.spots[P.story.drop or 1]
end

Guard.callback('nzwl:story:search', function(src)
    local P = Profile.get(src)
    if not P or P.story.stage ~= 'deaddrop' then return false end
    if not Guard.near(src, dropCoords(P), 3.0) then return false end
    drops[src] = GetGameTimer()
    return true, S.deadDrop.searchSeconds
end)

Guard.callback('nzwl:story:searched', function(src)
    local P = Profile.get(src)
    local t = drops[src]
    drops[src] = nil
    if not P or P.story.stage ~= 'deaddrop' or not t then return false end
    if GetGameTimer() - t < (S.deadDrop.searchSeconds - 0.5) * 1000 then
        Guard.flag(src, 'searched the dead drop too fast')
        return false
    end
    if not Guard.near(src, dropCoords(P), 3.5) then return false end
    local n = Utils.range(S.deadDrop.seeds)
    if not Inv.add(src, S.deadDrop.seed, n) then return false end
    if S.starterCash > 0 then FW.addMoney(src, 'cash', S.starterCash, 'weedlab-start') end
    P.story.stage = 'hardware'
    P.story.drop = nil
    Profile.dirty(src)
    Profile.addXp(src, Config.Levels.xp.deaddrop, 'Dead drop')
    text(src, {
        ("%d seeds. Don't waste 'em."):format(n),
        "You'll need pots, soil, a watering can, trimmers and a packaging station. Hardware store sells all of it.",
    })
    Profile.sync(src)
    return true, n
end)

--[[ ─────────────── tutorial progress ─────────────── ]]
local NEXT = {
    buy = { from = 'hardware', to = 'setup', lines = { "Good. Get in the RV and set up. Pot, soil, seed, water. Don't drown it." } },
    harvest = { from = 'setup', to = 'pack', lines = { "Smells like money. Bag it up at the packaging station." } },
    pack = { from = 'pack', to = 'sell', lines = { "That's a real product now. Go sell it. Walk up to people on the street, they'll tell you if they want it." } },
    sell = { from = 'sell', to = 'done', lines = { "First money. Keep growing, keep learning. Bigger places come with time." } },
}

function Story.progress(src, event)
    local P = Profile.get(src)
    local n = NEXT[event]
    if not P or not n or P.story.stage ~= n.from then return end
    P.story.stage = n.to
    Profile.dirty(src)
    text(src, n.lines)
    Profile.sync(src)
end

--- profile loaded: put the story back where it was
function Story.restore(src)
    local P = Profile.get(src)
    if not P then return end
    local st = P.story.stage
    if st == 'steal' or st == 'escape' then
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
        TriggerClientEvent('nzwl:notify', src, 'The RV is gone. The Ballas parked another one at the same spot.', 'error')
        spawnMission(src)
        Profile.sync(src)
    end
end

AddEventHandler('nzwl:server:unload', function(src)
    despawnMission(src)
    drops[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for src in pairs(mission) do despawnMission(src) end
end)
