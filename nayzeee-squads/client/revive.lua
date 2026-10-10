-- Reviving a downed squadmate. Prompt via lib.showTextUI, item choice via lib context menu.
if not Config.Features.Revive then return end

local R = Config.Revive
local nearest, prompting, busy = nil, false, false

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

local function doRevive(target, option)
    if busy then return end
    busy = true
    lib.hideTextUI()

    local startCoords = GetEntityCoords(cache.ped)
    local ok = lib.progressBar({
        duration = option.time,
        label = ('%s · %s'):format(option.label, target.name),
        useWhileDead = false,
        canCancel = true,
        disable = { move = R.CancelOnMove, car = true, combat = true },
        anim = { dict = R.Animation.dict, clip = R.Animation.clip, flag = 1 },
    })

    if not ok then
        busy = false
        return Notify('Revive cancelled', 'error', 'revive', true)
    end
    if #(GetEntityCoords(cache.ped) - startCoords) > 3.0 then
        busy = false
        return Notify('You moved too far from them', 'error', 'revive', true)
    end

    local done, msg = lib.callback.await('nz_squads:revive', false, target.id, option.item or nil)
    if done then Notify(('You revived %s'):format(target.name), 'success', 'revive', true)
    else Notify(msg or 'Revive failed, try again', 'error', 'revive', true) end
    busy = false
end

local function startRevive()
    if busy or not nearest then return end
    local target = nearest.member
    local options = lib.callback.await('nz_squads:reviveOptions', false) or {}

    if #options == 0 then return Notify('You need a medical item to revive them', 'error', 'revive', true) end
    if #options == 1 then return doRevive(target, options[1]) end

    local items = {}
    for i = 1, #options do
        local o = options[i]
        items[#items + 1] = {
            title = o.label,
            description = ('%ds · restores %d%% health'):format(math.floor(o.time / 1000), o.health),
            icon = o.icon,
            onSelect = function() CreateThread(function() doRevive(target, o) end) end,
        }
    end
    lib.registerContext({ id = 'nz_squads_revive', title = ('Revive %s'):format(target.name), options = items })
    lib.showContext('nz_squads_revive')
end

-- ─── prompt loop (runs only while a squadmate is down) ─────
local function promptLoop()
    if prompting then return end
    prompting = true
    CreateThread(function()
        local showing = false
        while Squad and #downedMembers() > 0 do
            nearest = findNearest()
            local want = nearest ~= nil and not busy and not MenuOpen
            if want and not showing then
                showing = true
                lib.showTextUI(('[%s] Revive %s'):format(R.Key, nearest.member.name), { position = 'left-center', icon = 'kit-medical', iconColor = '#e5484d' })
            elseif not want and showing then
                showing = false
                lib.hideTextUI()
            end
            Wait(350)
        end
        nearest = nil
        if showing then lib.hideTextUI() end
        prompting = false
    end)
end

AddEventHandler('nz_squads:client:changed', function(_, now)
    if now then promptLoop() end
end)

RegisterNetEvent('nz_squads:downed', function(_, state)
    if state then promptLoop() end
end)

lib.addKeybind({
    name = 'nz_squads_revive',
    description = 'Squads: revive a downed squadmate',
    defaultKey = R.Key,
    onPressed = function()
        if nearest and not busy and not MenuOpen then startRevive() end
    end,
})
