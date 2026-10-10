-- Team HUD feed: your own health and armour, who is talking, and pause-menu visibility.
-- One light loop, only while you're in a squad. Nothing is sent to the NUI unless it changed.
local running = false

local function healthPct(ped)
    local hp, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
    if max <= 100 then return hp > 0 and 100 or 0 end
    return math.floor(math.max(0, math.min(1, (hp - 100) / (max - 100))) * 100)
end

local function loop()
    if running then return end
    running = true
    CreateThread(function()
        local talking, paused = {}, nil
        local selfH, selfA = -1, -1

        while Squad and Config.Features.Hud do
            local p = IsPauseMenuActive() or IsHudHidden()
            if p ~= paused then
                paused = p
                NUI('hudHidden', p)
            end

            if Settings.hud and not p then
                local ped = cache.ped
                local h, a = healthPct(ped), GetPedArmour(ped)
                if h ~= selfH or a ~= selfA then
                    selfH, selfA = h, a
                    NUI('selfVitals', { h = h, a = a })
                end

                if Settings.hudTalking then
                    local diff, any = {}, false
                    for i = 1, #Squad.members do
                        local m = Squad.members[i]
                        if m.online and m.id then
                            local t
                            if m.id == Me() then
                                t = NetworkIsPlayerTalking(PlayerId())
                            else
                                local player = GetPlayerFromServerId(m.id)
                                t = player ~= -1 and NetworkIsPlayerTalking(player) or false
                            end
                            if talking[m.id] ~= t then
                                talking[m.id] = t
                                diff[tostring(m.id)] = t
                                any = true
                            end
                        end
                    end
                    if any then NUI('talking', diff) end
                end
            end
            Wait(300)
        end
        running = false
    end)
end

AddEventHandler('nz_squads:client:changed', function(_, now)
    if now then loop() end
end)
