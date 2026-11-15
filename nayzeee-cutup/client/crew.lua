-- Crew ghosting (non-crew players pass through you), flow state / sync and crew gap.
Crew = {}

local ghosted = {}       -- [entity] = true while we keep it see-through
local wasFlow = false
local breakTimer = 0.0

local function myCrewId()
    local c = LocalPlayer.state.cutupCrew
    return c and c.id or nil
end

function Crew.SameCrew(serverId)
    local mine = myCrewId()
    if not mine then return false end
    local theirs = Player(serverId).state.cutupCrew
    return theirs ~= nil and theirs.id == mine
end

local function isActive(serverId)
    return Player(serverId).state.cutupActive == true
end

-- others in a car near us: { serverId, ped, veh, dist, crew, active, name }
local others = {}
function Crew.Others() return others end

local function refreshOthers()
    local list = {}
    local myPed = CU.Ped
    local myPos = GetEntityCoords(myPed)
    local me = PlayerId()
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= me then
            local ped = GetPlayerPed(pid)
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                local dist = #(GetEntityCoords(veh) - myPos)
                if dist < 220.0 then
                    local sid = GetPlayerServerId(pid)
                    list[#list + 1] = {
                        serverId = sid, ped = ped, veh = veh, dist = dist,
                        crew = Crew.SameCrew(sid), active = isActive(sid), name = GetPlayerName(pid),
                        driver = GetPedInVehicleSeat(veh, -1) == ped,
                    }
                end
            end
        end
    end
    others = list
end

local function unghostAll(keep)
    for ent in pairs(ghosted) do
        if not keep or not keep[ent] then
            if DoesEntityExist(ent) then ResetEntityAlpha(ent) end
            ghosted[ent] = nil
        end
    end
end

-- every frame
function Crew.TickGhost()
    if not Config.Crew.GhostNonCrew then return end
    local myVeh = CU.Veh
    local myActive = CU.Active
    local keep = {}
    for _, o in ipairs(others) do
        if DoesEntityExist(o.veh) and o.dist < 150.0 and not o.crew and (myActive or o.active) then
            if myVeh ~= 0 then
                SetEntityNoCollisionEntity(myVeh, o.veh, true)
                SetEntityNoCollisionEntity(o.veh, myVeh, true)
                SetEntityNoCollisionEntity(myVeh, o.ped, true)
            end
            SetEntityNoCollisionEntity(CU.Ped, o.veh, true)
            if CU.Settings.gameplay.ghostAlpha then
                SetEntityAlpha(o.veh, Config.Crew.GhostAlpha, false)
                SetEntityAlpha(o.ped, Config.Crew.GhostAlpha, false)
                ghosted[o.veh], ghosted[o.ped] = true, true
                keep[o.veh], keep[o.ped] = true, true
            end
        end
    end
    unghostAll(keep)
end

-- every 250 ms
function Crew.UpdateSync(dt)
    refreshOthers()
    local s, cs = Config.Sync, Config.Crew
    local sync = CU.Sync
    local myVeh = CU.Veh
    if myVeh == 0 or not CU.Active or not CU.IsDriver then
        sync.pct, sync.flow, sync.partner, sync.crew, sync.mates = 0.0, false, nil, false, 0
        CU.Bonus.sync = 0.0
        wasFlow = false
        return
    end

    -- crewmates on the road with you set the crew gap
    local mates = 0
    for _, o in ipairs(others) do
        if o.crew and o.driver and o.active and o.dist < cs.MaxGap * 1.3 then mates = mates + 1 end
    end
    local crewGap = math.min(cs.MaxGap, cs.BaseGap + math.max(0, mates - 1) * cs.GapPerMember)

    local myHeading, mySpeed = GetEntityHeading(myVeh), CU.Speed
    local best
    for _, o in ipairs(others) do
        if o.driver and o.active and DoesEntityExist(o.veh) then
            local limit = o.crew and crewGap or s.SoloGap
            local theirSpeed = GetEntitySpeed(o.veh)
            if o.dist <= limit and mySpeed >= s.MinSpeed and theirSpeed >= s.MinSpeed
                and math.abs(Util.AngleDiff(GetEntityHeading(o.veh), myHeading)) <= s.MaxHeading
                and math.abs(theirSpeed - mySpeed) <= s.MaxSpeedDiff then
                if not best or (o.crew and not best.crew) or (o.crew == best.crew and o.dist < best.dist) then
                    best = o
                    best.limit = limit
                end
            end
        end
    end

    if best then
        breakTimer = 0.0
        sync.pct = math.min(100.0, sync.pct + dt / s.BuildTime * 100.0)
        sync.partner, sync.crew, sync.gap, sync.gapMax = best.name, best.crew, best.dist, best.limit
    else
        breakTimer = breakTimer + dt
        if breakTimer > s.BreakGrace then
            sync.pct = math.max(0.0, sync.pct - dt * 60.0)
        end
        if sync.pct <= 0.0 then sync.partner, sync.crew = nil, false end
    end
    sync.mates = mates
    sync.flow = sync.pct >= 100.0 or (wasFlow and sync.pct > 0.0 and breakTimer <= s.BreakGrace)

    if sync.flow and not wasFlow then
        UI.Popup(sync.crew and L('crew_flow') or L('flow_state'), sync.partner, CU.Settings.ui.accent)
        UI.Send('sound', 'flow')
    elseif not sync.flow and wasFlow then
        UI.Popup(L('flow_broken'), nil, CU.Settings.ui.alert)
    end
    wasFlow = sync.flow

    local sc = Config.Scoring
    if sync.flow then
        CU.Bonus.sync = sync.crew and (sc.CrewSyncBonus + math.max(0, mates - 1) * sc.CrewSyncPerMate) or sc.SyncBonus
    else
        CU.Bonus.sync = 0.0
    end
    if CU.Run and sync.flow and sync.crew then
        CU.Run.crewFlowTime = CU.Run.crewFlowTime + dt
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then unghostAll() end
end)
