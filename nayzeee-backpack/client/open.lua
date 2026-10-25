-----------------------------------------------------------------
-- Opening your bag
--
-- Instead of a stash just popping up, you set the bag down in front
-- of you and open it: kneel and rummage through a backpack, stand
-- over a duffel. Bags with an open model unzip on the ground, and a
-- cash model shows the money inside. Everyone nearby sees it (the
-- `nb_open` statebag drives client/main.lua's renderer).
--
-- Closing the inventory picks the bag back up. Getting knocked down,
-- dying or getting in a car closes it for you.
-----------------------------------------------------------------

Open = { active = false }

local cfg = Config.OpenBag or {}
local kneel = cfg.kneel or {}

local info, grabbing = nil, false

local function setState(value)
    LocalPlayer.state:set('nb_open', value, true)
end

local function play(a, flag, duration, blendIn)
    if not a or not Util.loadDict(a.dict) then return false end
    TaskPlayAnim(PlayerPedId(), a.dict, a.clip, blendIn or 4.0, -4.0, duration or -1, flag or 0, 0, false, false, false)
    return true
end

--- Somewhere you can actually put a bag down.
local function canOpenHere(ped)
    return not IsPedInAnyVehicle(ped, true) and not IsPedSwimming(ped) and not IsPedRagdoll(ped)
       and not IsPedFalling(ped) and not IsPedClimbing(ped) and not IsEntityDead(ped)
       and not IsPedInParachuteFreeFall(ped)
end

local function playGrab()
    if grabbing or not info or not info.grabAnim then return end
    grabbing = true
    CreateThread(function()
        local a = info.grabAnim
        -- 48: upper body + player control, no loop (as the clip was made for)
        if play(a, 48, a.time or 4200, 8.0) then Wait(a.time or 4200) end
        grabbing = false
    end)
end

local function finish()
    if not Open.active then return end
    local ped = PlayerPedId()

    if info and info.style == 'kneel' and canOpenHere(ped) then
        if kneel.loop then StopAnimTask(ped, kneel.loop.dict, kneel.loop.clip, 2.0) end
        if play(kneel.exit, 0, kneel.exit and kneel.exit.time or 900) then
            Wait(math.floor((kneel.exit.time or 900) * 0.7))
        end
    end

    setState(nil)
    Open.active = false
    info, grabbing = nil, false
end

--- Returns false when this bag should just open the quick way.
function Open.start(stashId, opening)
    local ped = PlayerPedId()
    if Open.active then return true end
    if not opening or opening.style == 'quick' or not canOpenHere(ped) then return false end
    if Studio and Studio.isOpen and Studio.isOpen() then return false end

    Open.active = true
    info = opening
    info.cash = opening.cash == true

    CreateThread(function()
        ClearPedTasks(ped)
        setState({ style = info.style, cash = info.cash })

        if info.style == 'kneel' then
            if play(kneel.enter, 2, -1) then Wait(kneel.enter.time or 900) end
            play(kneel.loop, 1, -1)
        else
            Wait(250)
        end

        exports.ox_inventory:openInventory('stash', stashId)

        -- ox_inventory flags the open inventory on the player's statebag
        local deadline = GetGameTimer() + 2500
        while not LocalPlayer.state.invOpen and GetGameTimer() < deadline do Wait(50) end

        while Open.active and LocalPlayer.state.invOpen do
            if not canOpenHere(ped) then
                exports.ox_inventory:closeInventory()
                break
            end
            -- something (an emote, a bump) cleared the rummage: pick it back up
            if info.style == 'kneel' and not grabbing and kneel.loop
               and not IsEntityPlayingAnim(ped, kneel.loop.dict, kneel.loop.clip, 3) then
                play(kneel.loop, 1, -1)
            end
            Wait(250)
        end

        finish()
    end)

    return true
end

--- The server tells us when cash goes in or out of the open bag.
RegisterNetEvent('nayzeee-backpack:openCash', function(hasCash, withdrew)
    if not Open.active or not info then return end
    if hasCash ~= info.cash then
        info.cash = hasCash
        setState({ style = info.style, cash = hasCash })
    end
    if withdrew and info.style == 'stand' then playGrab() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Open.active then
        setState(nil)
        ClearPedTasks(PlayerPedId())
    end
end)

-- never leave a stale "bag on the floor" behind after a relog
CreateThread(function()
    if LocalPlayer.state.nb_open then setState(nil) end
end)
