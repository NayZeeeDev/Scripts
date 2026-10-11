-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Reviving a downed squadmate, with an optional medical item.
if not SquadsConfig.Features.Revive then return end

local R = SquadsConfig.Revive
local nearest, prompting, busy, pickerOpen = nil, false, false, false
local holding = false -- the revive key is down (R.Hold)

local function downedMembers()
    local out = {}
    if not Squad then return out end
    for i = 1, #Squad.members do
        local m = Squad.members[i]
        if m.online and m.id ~= Me() then
            local v = Squad.vitals and Squad.vitals[tostring(m.id)]
            if m.downed or (v and v.h == 0) then out[#out + 1] = m end
        end
    end
    return out
end

local function findNearest()
    local list = downedMembers()
    if #list == 0 then return nil end
    local me = GetEntityCoords(cache.ped)
    local best, bestDist
    for i = 1, #list do
        local player = GetPlayerFromServerId(list[i].id)
        if player ~= -1 then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and DoesEntityExist(ped) then
                local d = #(GetEntityCoords(ped) - me)
                if d <= R.Distance and (not bestDist or d < bestDist) then
                    best, bestDist = { member = list[i], ped = ped }, d
                end
            end
        end
    end
    return best
end

local function playAnim(ped)
    RequestAnimDict(R.Animation.dict)
    local timeout = GetGameTimer() + 1500
    while not HasAnimDictLoaded(R.Animation.dict) and GetGameTimer() < timeout do Wait(10) end
    if HasAnimDictLoaded(R.Animation.dict) then
        TaskPlayAnim(ped, R.Animation.dict, R.Animation.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
    end
end

local function doRevive(option, viaKey)
    if busy or not nearest then return end
    busy = true

    local target = nearest.member
    local startCoords = GetEntityCoords(cache.ped)
    local holdMode = R.Hold and viaKey
    playAnim(cache.ped)

    -- let go while the animation loaded
    if holdMode and not holding then
        ClearPedTasks(cache.ped)
        busy = false
        return
    end

    -- their card (and everyone else's view of it) shows a ring filling up while you work
    TriggerServerEvent('nz_squads:reviving', target.id, option.time)

    -- hold mode: letting go of the key cancels
    local watcher
    if holdMode then
        watcher = true
        CreateThread(function()
            while watcher do
                if not holding then NHUD.cancelProgress() break end
                Wait(50)
            end
        end)
    end

    local ok = NHUD.progress({
        duration = option.time,
        label = ('%s %s'):format(option.label, target.name),
        icon = 'heart',
        useWhileDead = false,
        canCancel = true,
        -- CancelOnMove: walking away (over 1 m) stops the revive; otherwise movement is blocked while you work
        maxMove = R.CancelOnMove and 1.0 or nil,
        disable = { move = not R.CancelOnMove, car = true, combat = true },
    })
    watcher = false

    ClearPedTasks(cache.ped)
    if not ok then TriggerServerEvent('nz_squads:reviving', target.id, false) end

    if not ok then
        busy = false
        return Toast('Revive stopped', holdMode and not holding and 'You let go before it finished.' or 'You stopped before it finished.', 'error')
    end
    if #(GetEntityCoords(cache.ped) - startCoords) > 3.0 then
        busy = false
        TriggerServerEvent('nz_squads:reviving', target.id, false)
        return Toast('Revive stopped', 'You moved too far from them.', 'error')
    end

    local done, msg = lib.callback.await('nz_squads:revive', false, target.id, option.item or nil)
    if not done then
        TriggerServerEvent('nz_squads:reviving', target.id, false)
        Toast('Revive failed', msg or 'Try again.', 'error')
    end

    busy = false
end

local function startRevive()
    if busy or pickerOpen or not nearest then return end
    local options = lib.callback.await('nz_squads:reviveOptions', false) or {}

    if #options == 0 then
        return Toast('No supplies', 'You need a medical item to revive them.', 'error')
    end
    if #options == 1 then
        if R.Hold and not holding then return end -- let go while the item list loaded
        return doRevive(options[1], true)
    end

    pickerOpen = true
    SquadsFocus(true, true)
    NUI('revivePicker', { name = nearest.member.name, options = options })
end

RegisterNUICallback('sq_revivePick', function(data, cb)
    cb(1)
    pickerOpen = false
    if not MenuOpen then SquadsFocus(false, false) end
    if not data or data.index == nil then return end
    local options = data.options
    if options and options[data.index + 1] then
        CreateThread(function() doRevive(options[data.index + 1]) end)
    end
end)

-- ─── prompt loop (runs only while a squadmate is down) ─────
local function promptLoop()
    if prompting then return end
    prompting = true
    CreateThread(function()
        local showing = false
        while Squad and #downedMembers() > 0 do
            nearest = findNearest()
            local want = nearest ~= nil and not busy and not pickerOpen and not MenuOpen

            if want and not showing then
                showing = true
                NUI('revivePrompt', { name = nearest.member.name, key = R.Key, hold = R.Hold })
            elseif not want and showing then
                showing = false
                NUI('revivePrompt', false)
            end
            Wait(350)
        end
        nearest = nil
        if showing then NUI('revivePrompt', false) end
        prompting = false
    end)
end

AddEventHandler('nz_squads:client:changed', function(_, now)
    if now then promptLoop() end
end)

RegisterNetEvent('nz_squads:downed', function(_, state)
    if state then promptLoop() end
end)

-- G by default; lib.addKeybind lets players rebind it in the FiveM settings
lib.addKeybind({
    name = 'nz_squads_revive',
    description = 'Squads: revive a downed squadmate',
    defaultKey = R.Key,
    onPressed = function()
        holding = true
        if nearest and not busy and not pickerOpen and not MenuOpen then startRevive() end
    end,
    onReleased = function() holding = false end,
})
