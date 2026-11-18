--[[ Interaction: target systems or the built-in NAYZEEE key prompt ]]

Interact = { prompt = nil }

local K = Config.Interact.Keys

local function tvOptions(tv)
    local opts = {
        { label = _L('prompt_open'), icon = 'fas fa-tv', action = function() Panel.open(tv) end },
        { label = _L('prompt_remote'), icon = 'fas fa-gamepad', action = function() Remote.openVirtual(tv) end },
    }
    if not tv.permanent then
        opts[#opts + 1] = { label = _L('prompt_pickup'), icon = 'fas fa-hand', action = function() NZ.call('pickup', tv.id) end }
    end
    return opts
end

NZ.on('spawned', function(tv)
    if tv._entity and tv._entity ~= 0 and Bridge.target ~= 'none' then
        local id = tv.id
        tv._targeted = Bridge.addEntityTarget(tv._entity, (function()
            local list = {}
            for _, o in ipairs(tvOptions(tv)) do
                list[#list + 1] = { label = o.label, icon = o.icon, action = function() local t = NZ.tvs[id] if t then o.action(t) end end }
            end
            return list
        end)())
    end
end)

NZ.on('despawned', function(tv)
    if tv._targeted and tv._entity and tv._entity ~= 0 then Bridge.removeEntityTarget(tv._entity) end
    tv._targeted = nil
end)

local function showPrompt(p)
    local key = p and (p.id .. p.mode) or nil
    if key == Interact.prompt then return end
    Interact.prompt = key
    if not p then
        SendNUIMessage({ type = 'prompt', show = false })
        return
    end
    SendNUIMessage({ type = 'prompt', show = true, title = p.title, sub = p.sub, keys = p.keys })
end

local function statusLine(tv)
    if not tv.power then return 'Standby' end
    if tv.media then
        local m = tv.media
        return (m.paused and 'Paused · ' or (m.live and 'Live · ' or 'Playing · ')) .. (m.title or Utils.fallbackTitle(m))
    end
    return 'Home screen'
end

CreateThread(function()
    while true do
        local sleep = 400
        if NZ.ready and not Panel.isOpen and not Placement.active and not Remote.uiOpen then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local promptFor

            -- remote props first
            local remoteTv = Remote.nearestProp(pc)
            if remoteTv then
                sleep = 0
                promptFor = { id = remoteTv.id, mode = 'remote', title = remoteTv.label, sub = 'TV remote',
                    keys = { { key = 'E', label = _L('prompt_take_remote') } } }
                if IsControlJustReleased(0, K.Open) then Remote.take(remoteTv) end
            elseif Bridge.target == 'none' then
                local tv = NZ.target(Config.Interact.Distance + 1.0)
                if tv and tv._entity then
                    local c = NZ.center(tv)
                    if #(pc - c) <= Config.Interact.Distance + 0.8 then
                        sleep = 0
                        local keys = {
                            { key = 'E', label = _L('prompt_open') },
                            { key = 'G', label = _L('prompt_remote') },
                        }
                        if not tv.permanent then keys[#keys + 1] = { key = 'H', label = _L('prompt_pickup') } end
                        promptFor = { id = tv.id, mode = 'tv' .. (tv.power and '1' or '0') .. tostring(tv.media and tv.media.key), title = tv.label, sub = statusLine(tv), keys = keys }
                        if IsControlJustReleased(0, K.Open) then Panel.open(tv)
                        elseif IsControlJustReleased(0, K.Remote) then Remote.openVirtual(tv)
                        elseif IsControlJustReleased(0, K.Pickup) and not tv.permanent then NZ.call('pickup', tv.id) end
                    end
                end
            end
            showPrompt(promptFor)
        else
            showPrompt(nil)
        end
        Wait(sleep)
    end
end)
