--[[ Story client: the text, Uncle Benson, the RV job ]]

Story = { mission = nil }

local S = Config.Story
local B = S.benson

--[[ ─────────────── the text from the unknown number ─────────────── ]]
local textOpen = false

local function answer(go)
    if not textOpen then return false end
    textOpen = false
    UI.send('text', false)
    TriggerServerEvent('nzde:story:answer', go)
    return true
end

lib.addKeybind({ name = 'nzde_yes', description = 'Drug empire: answer yes', defaultKey = 'Y', onPressed = function() answer(true) end })
lib.addKeybind({ name = 'nzde_no', description = 'Drug empire: answer no', defaultKey = 'BACK', onPressed = function() answer(false) end })

RegisterNetEvent('nzde:story:text', function(data)
    if GetInvokingResource() then return end
    textOpen = true
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    UI.send('text', { from = data.from, lines = data.lines, timeout = data.timeout, yes = 'Go', no = 'Ignore', yesKey = 'Y', noKey = 'Backspace' })
    SetTimeout(data.timeout * 1000, function()
        if textOpen then
            textOpen = false
            UI.send('text', false)
            UI.notify('The text is still in your messages. They\'ll write again.', 'info')
        end
    end)
end)

RegisterNUICallback('text', function(data, cb)
    cb(1)
    answer(data and data.go == true)
end)

--[[ ─────────────── Uncle Benson ─────────────── ]]
local DIALOGUE = {
    intro = { start = 'a', nodes = {
        a = { text = "Ah. You actually came. Most people ignore strange texts. Smart. Or desperate.", choices = {
            { label = 'Who are you?', go = 'b' }, { label = 'You said something about money.', go = 'c' } } },
        b = { text = "Name's Benson. Uncle Benson to people I like. I used to run half this county from a back room. Now I run it from this chair.", next = 'c' },
        c = { text = "Here's the deal. I've got the know-how, the seeds and the customers. What I don't have is legs. You've got legs.", choices = {
            { label = 'What do I have to do?', go = 'd' }, { label = "And what's in it for you?", go = 'e' } } },
        e = { text = "A cut, eventually. Right now I just want to see my operation breathing again.", next = 'd' },
        d = { text = "First you need somewhere to work that isn't your mom's kitchen. There's an RV I've had my eye on. The Lost boys have it parked and guarded.", next = 'f' },
        f = { text = "Go take it. Drive it back here in one piece. Then we talk product.", choices = {
            { label = 'Consider it done.', go = false, tag = 'accept' }, { label = 'Guarded? By how many?', go = 'g' } } },
        g = { text = "Enough that you shouldn't walk in waving. Take them out or be quick about it. Your call.", choices = {
            { label = "Fine. I'll get it.", go = false, tag = 'accept' } } },
    } },
    waiting = { start = 'a', nodes = {
        a = { text = "The RV. It's still not here. Clock's ticking, kid.", choices = { { label = "I'm on it.", go = false } } },
    } },
    noRv = { start = 'a', nodes = {
        a = { text = "Where's the RV? Park it right here where I can see it.", choices = { { label = 'One sec.', go = false } } },
    } },
    rv = { start = 'a', nodes = {
        a = { text = "Look at her. A little shot up, but she'll do.", next = 'b' },
        b = { text = "The back of that thing is your lab now. Nobody looks twice at an RV.", next = 'c' },
        c = { text = "Here's your starter kit. Two pots, soil, a seed, baggies, a watering can, trimmers and a packaging station.", next = 'd' },
        d = { text = "Pots go in the RV, soil in the pots, seed in the soil, water on top. Harvest it, bag it, sell it. Simple.", choices = {
            { label = 'And who do I sell to?', go = 'e' } } },
        e = { text = "I put an app on your phone. My old customers are in there. They'll text you. Don't keep them waiting.", next = 'f' },
        f = { text = "Start with weed. Prove you can move it and I'll open more doors.", choices = {
            { label = "Let's get to work.", go = false, tag = 'done' } } },
    } },
}

local TIPS = {
    "Customers pay more for their favourite effects. Mix ingredients in and watch the price climb.",
    "Water your plants. Dry soil means nothing grows.",
    "A grow light next to your pots and they grow faster. A tent's even better.",
    "Bag everything. Nobody buys loose product off a stranger.",
    "Keep your regulars happy and they'll introduce their friends.",
    "Dealers move product while you sleep. They take a cut. Everyone takes a cut.",
}

local benson = { ped = nil, chair = nil, target = nil, point = nil, spot = nil }

local function despawnBenson()
    if benson.target then Target.removeEntity(benson.target) benson.target = nil end
    Util.delete(benson.ped)
    Util.delete(benson.chair)
    benson.ped, benson.chair = nil, nil
end

local function talk()
    local which = lib.callback.await('nzde:story:talk', false)
    if not which then return end
    if which == 'idle' then
        Dialogue.play(benson.ped, { start = 'a', nodes = { a = { text = TIPS[math.random(#TIPS)], choices = { { label = 'Thanks, Benson.', go = false } } } } }, { name = B.name, role = 'Contact' })
        return
    end
    local tag = Dialogue.play(benson.ped, DIALOGUE[which], { name = B.name, role = Main.state.stage == 'meet' and 'Unknown number' or 'Contact' })
    if (which == 'intro' and tag == 'accept') or (which == 'rv' and tag == 'done') then
        local ok = lib.callback.await('nzde:story:done', false, which)
        if ok and which == 'rv' then
            UI.notify('Starter kit received. Check your inventory.', 'success', 7000, B.name)
        end
    end
end

local function spawnBenson()
    if benson.ped then return end
    local c = benson.spot
    local z = Util.groundZ(c.x, c.y, c.z)
    benson.chair = Util.prop(B.wheelchair, vec3(c.x, c.y, z), c.w, { fallback = false })
    local seat = B.seat.offset
    benson.ped = Util.ped(B.model, vec4(c.x, c.y, z, c.w))
    FreezeEntityPosition(benson.ped, false)
    SetEntityCoordsNoOffset(benson.ped, c.x + seat.x, c.y + seat.y, z + seat.z, false, false, false)
    TaskStartScenarioAtPosition(benson.ped, B.seat.scenario, c.x + seat.x, c.y + seat.y, z + seat.z, c.w, 0, true, true)
    SetTimeout(1500, function() if benson.ped then FreezeEntityPosition(benson.ped, true) end end)
    benson.target = Target.addEntity(benson.ped, {
        { name = 'nzde_benson', label = 'Talk to ' .. B.name, icon = 'fa-solid fa-wheelchair', distance = B.talkDistance,
          canInteract = function() return Main.state.stage ~= 'none' and Main.state.stage ~= 'texted' end,
          onSelect = talk },
    })
end

local bensonBlip

function Story.refresh(st)
    local stage = st.stage
    local idx = st.benson
    local spot = idx and B.spots[idx]
    -- Benson's ped exists for everyone who has been sent to him
    if spot and stage ~= 'none' and stage ~= 'texted' then
        if benson.spot ~= spot then
            if benson.point then benson.point:remove() end
            despawnBenson()
            benson.spot = spot
            benson.point = lib.points.new({ coords = vec3(spot.x, spot.y, spot.z), distance = 60.0, onEnter = spawnBenson, onExit = despawnBenson })
        end
    end
    -- blip: route while going to meet him / bringing the RV
    Util.removeBlip(bensonBlip)
    bensonBlip = nil
    if spot and (stage == 'meet' or stage == 'return') then
        bensonBlip = Util.blip(spot, B.blip, stage == 'meet' and B.blip.label or B.name, true)
    elseif spot and stage == 'setup' then
        bensonBlip = Util.blip(spot, { sprite = B.blip.sprite, color = B.blip.color, scale = 0.7 }, B.name, false)
    end
    Story.refreshMission(st)
end

--[[ ─────────────── the RV job ─────────────── ]]
local guards, rvBlip, rvPoint = {}, nil, nil
local GROUP = joaat('NZDE_GUARDS')
AddRelationshipGroup('NZDE_GUARDS')

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
    for _, c in ipairs(spot.guards) do
        local hash = Util.model(cfg.guardModels[math.random(#cfg.guardModels)], 'g_m_y_lost_01')
        local z = Util.groundZ(c.x, c.y, c.z)
        local ped = CreatePed(4, hash, c.x, c.y, z, c.w, true, false)
        SetModelAsNoLongerNeeded(hash)
        SetPedRelationshipGroupHash(ped, GROUP)
        GiveWeaponToPed(ped, joaat(cfg.guardWeapons[math.random(#cfg.guardWeapons)]), 250, false, true)
        SetPedAccuracy(ped, cfg.guardAccuracy)
        SetPedArmour(ped, cfg.guardArmour)
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatAttributes(ped, 5, true)
        SetPedCombatAbility(ped, 1)
        SetPedCombatRange(ped, 1)
        SetPedSeeingRange(ped, 60.0)
        SetPedHearingRange(ped, 60.0)
        SetPedDropsWeaponsWhenDead(ped, false)
        TaskGuardCurrentPosition(ped, 12.0, 12.0, true)
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
    if not m or (st.stage ~= 'steal' and st.stage ~= 'return') then
        if rvPoint then rvPoint:remove() rvPoint = nil end
        if st.stage ~= 'steal' and st.stage ~= 'return' then
            clearGuards()
            Story.mission = nil
        end
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

RegisterNetEvent('nzde:story:mission', function(data)
    if GetInvokingResource() then return end
    Story.mission = data
    Story.refreshMission(Main.state)
end)

lib.onCache('vehicle', function(veh)
    if not veh or not Story.mission or Main.state.stage ~= 'steal' then return end
    SetTimeout(300, function()
        if veh == missionVehicle() and GetPedInVehicleSeat(veh, -1) == cache.ped then
            TriggerServerEvent('nzde:story:stolen')
            if S.rv.wantedLevel > 0 then
                SetPlayerWantedLevel(PlayerId(), S.rv.wantedLevel, false)
                SetPlayerWantedLevelNow(PlayerId(), false)
            end
            SetTimeout(30000, clearGuards)
        end
    end)
end)

RegisterNetEvent('nzde:story:installed', function()
    if GetInvokingResource() then return end
    PhoneBridge.Install()
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    UI.notify(('The %s app was installed on your phone. /%s opens it too.'):format(Config.Phone.AppName, Config.Phone.Command or 'empire'), 'success', 9000, 'New app')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    despawnBenson()
    clearGuards()
end)
