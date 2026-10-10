--[[ Story client: Uncle Benson (hidden, in a wheelchair), the Ballas RV job, the dead drop ]]

Story = { mission = nil }

local B, S = Config.Benson, Config.Story

--[[ ─────────────── Uncle Benson ─────────────── ]]
local DIALOGUE = {
    intro = { start = 'a', nodes = {
        a = { text = "Well, well. Nobody finds me by accident. Either you're lost, or you're looking for work.", choices = {
            { label = 'Who are you?', go = 'b' }, { label = "I'm looking for work.", go = 'c' } } },
        b = { text = "Benson. Uncle Benson. I grew the best weed in this county before these legs quit on me. Now I need someone who can still walk.", next = 'c' },
        c = { text = "I've got the know-how and the seeds. What you need is somewhere to grow that nobody looks twice at.", choices = {
            { label = 'Like where?', go = 'd' }, { label = "What's in it for you?", go = 'e' } } },
        e = { text = "A cut, eventually. Right now I just want to see a green thumb that isn't mine.", next = 'd' },
        d = { text = "An RV. The Ballas have one parked on their turf. Mobile, private, perfect for a first grow.", next = 'f' },
        f = { text = "They'll have guns and they'll use them. Take the RV, lose them, and it's yours. Then I'll tell you where the seeds are.", choices = {
            { label = "I'll get it.", go = false, tag = 'accept' }, { label = 'Ballas? Are you crazy?', go = 'g' } } },
        g = { text = "Crazy got me this chair. Smart gets you an RV. Be quick, be quiet, or be good with a gun.", choices = {
            { label = "Fine. I'll get it.", go = false, tag = 'accept' }, { label = 'Not today.', go = false } } },
    } },
    waiting = { start = 'a', nodes = {
        a = { text = "Why are you back here? The RV, kid. And when you've got it, lose the Ballas before you come anywhere near me.", choices = { { label = "I'm on it.", go = false } } },
    } },
    drop = { start = 'a', nodes = {
        a = { text = "The seeds are in the dead drop. I put the pin on your map. Go.", choices = { { label = 'Going.', go = false } } },
    } },
    hardware = { start = 'a', nodes = {
        a = { text = "Pots, soil, a watering can, trimmers and a packaging station. Any hardware store. Don't buy anything fancy yet, you haven't earned it.", choices = { { label = 'Got it.', go = false } } },
    } },
    cop = { start = 'a', nodes = {
        a = { text = "I'm just an old man enjoying the air, officer.", choices = { { label = 'Right.', go = false } } },
    } },
}

local TIPS = {
    "Water before you leave. Dry soil grows nothing.",
    "Hang a light over your pots. Halogen's cheap, LEDs are better, full spectrum is what the pros run.",
    "Fertilizer makes it better. PGR makes more of it but worse. Speed Growth makes it faster and worse. Pick your poison.",
    "Hang your buds on a drying rack. Patience is a quality bump.",
    "A grow tent is fast, but the plants come out small.",
    "Mix your product with the right stuff and it sells for a lot more.",
    "You start in the RV. Prove yourself and you'll outgrow it. Warehouses come later.",
    "Nobody pays top dollar for trash. Better quality, more buyers, better prices.",
    "Press it into bricks and Leon down at the docks buys them by the stack. He doesn't deal with beginners.",
}

local benson = { ped = nil, chair = nil, target = nil, point = nil, spot = nil }

local function despawnBenson()
    if benson.target then Target.removeEntity(benson.target) benson.target = nil end
    Util.delete(benson.ped)
    Util.delete(benson.chair)
    benson.ped, benson.chair = nil, nil
end

local function talk()
    local which = lib.callback.await('nzwl:story:talk', false)
    if not which then return end
    local who = { name = B.name, role = Main.state.stage == 'none' and 'A man in a wheelchair' or 'Contact' }
    if which == 'idle' then
        Dialogue.play(benson.ped, { start = 'a', nodes = { a = { text = TIPS[math.random(#TIPS)], choices = { { label = 'Thanks, Benson.', go = false } } } } }, who)
        return
    end
    local tag = Dialogue.play(benson.ped, DIALOGUE[which], who)
    if which == 'intro' and tag == 'accept' then
        if lib.callback.await('nzwl:story:accept', false) then
            UI.notify('Steal the RV from the Ballas. It\'s marked on your map.', 'info', 8000, B.name)
        end
    end
end

local function spawnBenson()
    if benson.ped then return end
    local c = benson.spot
    local z = Util.groundZ(c.x, c.y, c.z)
    benson.chair = Util.prop(B.wheelchair, vec3(c.x, c.y, z), c.w, { fallback = false })
    local seat = B.seat.offset
    local sx, sy = Utils.rotate(seat.x, seat.y, c.w)
    benson.ped = Util.ped(B.model, vec4(c.x, c.y, z, c.w))
    FreezeEntityPosition(benson.ped, false)
    SetEntityCoordsNoOffset(benson.ped, c.x + sx, c.y + sy, z + seat.z, false, false, false)
    TaskStartScenarioAtPosition(benson.ped, B.seat.scenario, c.x + sx, c.y + sy, z + seat.z, c.w, 0, true, true)
    SetTimeout(1500, function() if benson.ped then FreezeEntityPosition(benson.ped, true) end end)
    benson.target = Target.addEntity(benson.ped, {
        { name = 'nzwl_benson', label = 'Talk to the man in the wheelchair', icon = 'fa-solid fa-wheelchair', distance = B.talkDistance, onSelect = talk },
    })
end

local function placeBenson(idx)
    local spot = B.spots[idx or 1]
    if not spot or benson.spot == spot then return end
    if benson.point then benson.point:remove() end
    despawnBenson()
    benson.spot = spot
    benson.point = lib.points.new({ coords = vec3(spot.x, spot.y, spot.z), distance = 60.0, onEnter = spawnBenson, onExit = despawnBenson })
end

CreateThread(function()
    while not GlobalState.nzwlBenson do Wait(500) end
    placeBenson(GlobalState.nzwlBenson)
end)
AddStateBagChangeHandler('nzwlBenson', 'global', function(_, _, value) if value then placeBenson(value) end end)

--[[ ─────────────── the Ballas RV ─────────────── ]]
local guards, rvBlip, rvPoint = {}, nil, nil
local GROUP = joaat('NZWL_BALLAS')
AddRelationshipGroup('NZWL_BALLAS')

local function clearGuards()
    for _, g in ipairs(guards) do
        if DoesEntityExist(g) then
            SetEntityAsNoLongerNeeded(g)
            if not IsEntityDead(g) then DeletePed(g) end
        end
    end
    guards = {}
end

local function spawnGuards(spot)
    if #guards > 0 then return end
    local cfg = S.rv
    SetRelationshipBetweenGroups(5, GROUP, joaat('PLAYER'))
    SetRelationshipBetweenGroups(5, joaat('PLAYER'), GROUP)
    SetRelationshipBetweenGroups(0, GROUP, GROUP)
    local v = spot.vehicle
    for _, off in ipairs(cfg.guards) do
        local ox, oy = Utils.rotate(off.x, off.y, v.w)
        local x, y = v.x + ox, v.y + oy
        local hash = Util.model(cfg.guardModels[math.random(#cfg.guardModels)], 'g_m_y_ballaeast_01')
        local z = Util.groundZ(x, y, v.z)
        local ped = CreatePed(4, hash, x, y, z, (v.w + off.w) % 360.0, true, false)
        SetModelAsNoLongerNeeded(hash)
        SetPedRelationshipGroupHash(ped, GROUP)
        GiveWeaponToPed(ped, joaat(cfg.guardWeapons[math.random(#cfg.guardWeapons)]), 250, false, true)
        SetPedAccuracy(ped, cfg.guardAccuracy)
        SetPedArmour(ped, cfg.guardArmour)
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatAttributes(ped, 5, true)
        SetPedCombatAbility(ped, 1)
        SetPedCombatRange(ped, 1)
        SetPedSeeingRange(ped, 70.0)
        SetPedHearingRange(ped, 70.0)
        SetPedDropsWeaponsWhenDead(ped, false)
        if math.random() < 0.5 then
            TaskStartScenarioInPlace(ped, Utils.pick({ 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_STAND_IMPATIENT' }), 0, true)
        else
            TaskGuardCurrentPosition(ped, 10.0, 10.0, true)
        end
        guards[#guards + 1] = ped
    end
end

local function missionVehicle()
    local m = Story.mission
    if not m or not NetworkDoesEntityExistWithNetworkId(m.net) then return nil end
    return NetworkGetEntityFromNetworkId(m.net)
end

function Story.refreshMission(st)
    local m = Story.mission
    Util.removeBlip(rvBlip)
    rvBlip = nil
    if not m or (st.stage ~= 'steal' and st.stage ~= 'escape') then
        if rvPoint then rvPoint:remove() rvPoint = nil end
        if st.stage ~= 'steal' and st.stage ~= 'escape' then Story.mission = nil end
        return
    end
    local spot = S.rv.spots[m.spot]
    if st.stage == 'steal' then
        rvBlip = Util.blip(spot.vehicle, S.rv.blip, S.rv.blip.label, true)
        if not rvPoint then
            rvPoint = lib.points.new({
                coords = vec3(spot.vehicle.x, spot.vehicle.y, spot.vehicle.z), distance = S.rv.spawnDistance,
                onEnter = function()
                    spawnGuards(spot)
                    local veh = missionVehicle()
                    if veh then FW.giveKeys(veh) end
                end,
            })
        end
    elseif rvPoint then
        rvPoint:remove()
        rvPoint = nil
    end
end

RegisterNetEvent('nzwl:story:mission', function(data)
    if GetInvokingResource() then return end
    Story.mission = data
    Story.refreshMission(Main.state)
end)

RegisterNetEvent('nzwl:story:clearMission', function()
    if GetInvokingResource() then return end
    Story.mission = nil
    Story.refreshMission(Main.state)
    SetTimeout(20000, clearGuards)
end)

lib.onCache('vehicle', function(veh)
    if not veh or not Story.mission or Main.state.stage ~= 'steal' then return end
    SetTimeout(300, function()
        if veh == missionVehicle() and GetPedInVehicleSeat(veh, -1) == cache.ped then
            TriggerServerEvent('nzwl:story:stolen')
            if S.rv.wantedLevel > 0 then
                SetPlayerWantedLevel(PlayerId(), S.rv.wantedLevel, false)
                SetPlayerWantedLevelNow(PlayerId(), false)
            end
            -- the crew comes after you
            for _, g in ipairs(guards) do
                if DoesEntityExist(g) and not IsEntityDead(g) then TaskCombatPed(g, cache.ped, 0, 16) end
            end
        end
    end)
end)

--[[ ─────────────── dead drop ─────────────── ]]
local drop = { blip = nil, prop = nil, point = nil, zone = nil, idx = nil }

local function clearDrop()
    Util.removeBlip(drop.blip)
    if drop.point then drop.point:remove() end
    if drop.zone then Target.removeZone(drop.zone) end
    Util.delete(drop.prop)
    drop = { idx = nil }
end

local function search()
    local ok, secs = lib.callback.await('nzwl:story:search', false)
    if not ok then return end
    local done = UI.progress('Searching the dead drop', secs * 1000, { dict = 'amb@prop_human_bum_bin@base', clip = 'base', flag = 1 })
    if not done then return end
    local got, n = lib.callback.await('nzwl:story:searched', false)
    if got then UI.notify(('Found %d seeds'):format(n), 'success', 6000, 'Dead drop') end
end

local function refreshDrop(st)
    local idx = st.stage == 'deaddrop' and st.drop or nil
    if drop.idx == idx then return end
    clearDrop()
    if not idx then return end
    local c = S.deadDrop.spots[idx]
    drop.idx = idx
    drop.blip = Util.blip(c, S.deadDrop.blip, S.deadDrop.blip.label, true)
    drop.point = lib.points.new({
        coords = vec3(c.x, c.y, c.z), distance = 40.0,
        onEnter = function()
            drop.prop = Util.prop(S.deadDrop.prop, vec3(c.x, c.y, Util.groundZ(c.x, c.y, c.z)), c.w, { fallback = 'prop_cs_cardbox_01' })
            drop.zone = Target.addZone(vec3(c.x, c.y, c.z), 1.4, {
                { name = 'nzwl_drop', label = 'Search the dead drop', icon = 'fa-solid fa-box-open', onSelect = search },
            })
        end,
        onExit = function()
            Util.delete(drop.prop)
            drop.prop = nil
            if drop.zone then Target.removeZone(drop.zone) drop.zone = nil end
        end,
    })
end

function Story.refresh(st)
    Story.refreshMission(st)
    refreshDrop(st)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    despawnBenson()
    clearGuards()
    clearDrop()
end)
