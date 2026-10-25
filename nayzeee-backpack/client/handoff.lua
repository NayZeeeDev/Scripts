-----------------------------------------------------------------
-- Handing a bag to someone (client)
--
-- Every client near the giver draws the hand-off from the giver's
-- `nb_hand` statebag: the worn bag comes off, sits in the giver's
-- right hand, then in the taker's. The prop is placed from its mesh
-- (top of the bag at the hand), so any model works without tuning.
-- Runs per frame only for the ~3 seconds a hand-off lasts.
-----------------------------------------------------------------

local cfg = Config.Handoff
if not cfg or not cfg.enabled then return end

Handoff = {}

local myId = GetPlayerServerId(PlayerId())
local running = {} -- [giverId] = true while drawing a hand-off
local HAND = 57005 -- right hand

local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end

local function pedFor(serverId)
    if serverId == myId then return PlayerPedId() end
    local ply = GetPlayerFromServerId(serverId)
    return ply == -1 and 0 or GetPlayerPed(ply)
end

local function play(ped, a, duration)
    if a and Util.loadDict(a.dict) then
        TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, duration or -1, 0, 0, false, false, false)
    end
end

--- Bag hanging from a hand: top of the mesh at the palm, upright,
--- side-on to the holder.
local function holdIn(entity, ped, top)
    local hand = GetPedBoneCoords(ped, HAND, 0.0, 0.0, 0.0)
    local h = (GetEntityHeading(ped) + 90.0) % 360.0
    local r = math.rad(h)
    local c, s = math.cos(r), math.sin(r)
    SetEntityRotation(entity, 0.0, 0.0, h, 2, false)
    SetEntityCoordsNoOffset(entity,
        hand.x - (top.x * c - top.y * s),
        hand.y - (top.x * s + top.y * c),
        hand.z - top.z - 0.03, false, false, false)
end

--- Draw one hand-off, start to finish. Runs on every client in range.
local function draw(giverId, h)
    if running[giverId] then return end
    running[giverId] = true

    local giver, taker = pedFor(giverId), pedFor(h.to)
    if giver == 0 or taker == 0 then running[giverId] = nil return end

    local takeOff = h.worn and cfg.takeOff or 0
    local swapAt, doneAt = takeOff + cfg.swap, takeOff + cfg.finish
    local start = GetGameTimer()

    -- our own part of it
    if giverId == myId then
        QuietBagAnims(doneAt + 2500)
        TaskTurnPedToFaceEntity(giver, taker, 600)
        if h.worn then
            local a = Config.Animations and Config.Animations.unequip
            if a then play(giver, { dict = a.dict, clip = a.anim }, takeOff) end
        end
        SetTimeout(takeOff, function() play(PlayerPedId(), cfg.giveAnim, cfg.finish) end)
    elseif h.to == myId then
        TaskTurnPedToFaceEntity(taker, giver, 600)
        SetTimeout(takeOff, function() play(PlayerPedId(), cfg.takeAnim, cfg.finish) end)
    end

    local entity, top
    while running[giverId] and GetGameTimer() - start < doneAt + 3000 do
        local t = GetGameTimer() - start
        if t >= takeOff then
            if not entity then
                SetHandoffHidden(giverId, true)
                local hash
                entity, hash = Util.spawnModel(h.model, h.texture, GetEntityCoords(giver))
                if not entity then break end
                local c, _, mx = Util.modelCentre(hash)
                top = vector3(c.x, c.y, mx.z)
            end
            local holder = t < swapAt and giver or taker
            if DoesEntityExist(holder) then holdIn(entity, holder, top) end
        end
        Wait(0)
    end

    Util.delete(entity)
    SetHandoffHidden(giverId, false)
    running[giverId] = nil
end

AddStateBagChangeHandler('nb_hand', nil, function(bagName, _, value)
    local ply = GetPlayerFromStateBagName(bagName)
    if ply == 0 then return end
    local giverId = GetPlayerServerId(ply)

    if not value then
        running[giverId] = nil -- the loop cleans up on its next frame
        return
    end

    -- only draw what we could actually see
    local ped = pedFor(giverId)
    if ped == 0 or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) > 80.0 then return end
    CreateThread(function() draw(giverId, value) end)
end)

-----------------------------------------------------------------
-- offering
-----------------------------------------------------------------

--- Offer a bag to a player. `slot` nil = the bag you carry.
function Handoff.offer(targetId, slot)
    if not targetId then return Config.Notify(S('ho_nobody'), 'error') end
    if Open and Open.active then return Config.Notify(S('ho_close_first'), 'error') end
    TriggerServerEvent('nayzeee-backpack:handoff:offer', targetId, slot)
end

--- Offer to whoever's closest.
function Handoff.offerNearest(slot)
    local ply = lib.getClosestPlayer(GetEntityCoords(PlayerPedId()), cfg.distance, false)
    Handoff.offer(ply and GetPlayerServerId(ply), slot)
end

RegisterCommand('handbag', function() Handoff.offerNearest() end, false)

-- third-eye another player
if cfg.target and Config.Prompts.useTarget then
    CreateThread(function()
        if GetResourceState('ox_target') ~= 'started' then return end
        exports.ox_target:addGlobalPlayer({
            {
                name = 'nayzeee_handoff',
                icon = 'fa-solid fa-hand-holding',
                label = Config.Prompts.handoffTarget,
                distance = cfg.distance,
                canInteract = function()
                    return LocalPlayer.state.nayzeee_backpack ~= nil and not (Open and Open.active)
                end,
                onSelect = function(data)
                    local ply = NetworkGetPlayerIndexFromPed(data.entity)
                    if ply ~= -1 then Handoff.offer(GetPlayerServerId(ply)) end
                end,
            },
        })
    end)
end

-----------------------------------------------------------------
-- being offered one
-----------------------------------------------------------------

local asking = false

RegisterNetEvent('nayzeee-backpack:handoff:ask', function(label, timeout)
    if asking then return end
    asking = true
    CreateThread(function()
        local answered = false
        SetTimeout((timeout or cfg.timeout) * 1000, function()
            if not answered then lib.closeAlertDialog() end
        end)
        local r = lib.alertDialog({
            header = S('ho_ask_title'),
            content = S('ho_ask_text', label),
            centered = true,
            cancel = true,
            labels = { confirm = S('ho_take'), cancel = S('ho_refuse') },
        })
        answered = true
        asking = false
        TriggerServerEvent('nayzeee-backpack:handoff:answer', r == 'confirm')
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(running) do running[id] = nil end
end)
