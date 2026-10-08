--[[ Heist tablet: open/close + every NUI -> server bridge ]]

Menu = { open_ = false }

function Menu.open(tab)
    if Menu.open_ or UI.focus then return end
    if IsPauseMenuActive() or IsEntityDead(cache.ped) then return end
    local ok, data = lib.callback.await('nzh:menu:open', false)
    if not ok then return UI.notify(data or locale('no_permission'), 'error') end
    Menu.open_ = true
    UI.setFocus(true)
    data.tab = tab
    data.serverId = cache.serverId
    UI.send('menu', { open = true, data = data })

    -- resume a market delivery that survived a reconnect
    if not Market.pending then
        CreateThread(function()
            local m = lib.callback.await('nzh:market:data', false)
            if m and m.order and not Market.pending then Market.deliver(m.order.remaining) end
        end)
    end

    -- tablet prop + anim while open
    CreateThread(function()
        lib.requestAnimDict('amb@code_human_in_bus_passenger_idles@female@tablet@base')
        local tablet = Props.attach(cache.ped, 'prop_cs_tablet', 60309, vec3(0.03, 0.002, -0.0), vec3(10.0, 160.0, 0.0))
        TaskPlayAnim(cache.ped, 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base', 3.0, 3.0, -1, 49, 0, false, false, false)
        while Menu.open_ do Wait(250) end
        StopAnimTask(cache.ped, 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base', 1.0)
        if tablet and DoesEntityExist(tablet) then DeleteEntity(tablet) end
    end)
end

function Menu.close()
    if not Menu.open_ then return end
    Menu.open_ = false
    UI.send('menu', { open = false })
    UI.setFocus(false)
    TriggerServerEvent('nzh:menu:closed')
end

RegisterNetEvent('nzh:menu:open', function()
    if GetInvokingResource() then return end
    Menu.open()
end)

if Config.Menu.command then
    RegisterCommand(Config.Menu.command, function() Menu.open() end, false)
end

if Config.Menu.key then
    lib.addKeybind({
        name = 'nzh_tablet', description = 'Open heist tablet', defaultKey = Config.Menu.key,
        onPressed = function() Menu.open() end,
    })
end

--[[ NUI -> server callbacks. Each maps a NUI callback name to a server callback + argument builder. ]]
local bridge = {
    ['heists:list']         = { 'nzh:heist:list' },
    ['heist:start']         = { 'nzh:heist:start', function(d) return d.id end },
    ['heist:stop']          = { 'nzh:heist:stop' },
    ['crew:get']            = { 'nzh:crew:get' },
    ['crew:invite']         = { 'nzh:crew:invite', function(d) return tonumber(d.target) end },
    ['crew:kick']           = { 'nzh:crew:kick', function(d) return tonumber(d.target) end },
    ['crew:promote']        = { 'nzh:crew:promote', function(d) return tonumber(d.target) end },
    ['crew:leave']          = { 'nzh:crew:leave' },
    ['crew:ready']          = { 'nzh:crew:ready', function(d) return d.state == true end },
    ['crew:respond']        = { 'nzh:crew:respond', function(d) return d.accept == true end },
    ['profile:nickname']    = { 'nzh:profile:nickname', function(d) return d.nickname end },
    ['profile:avatar']      = { 'nzh:profile:avatar', function(d) return d.avatar end },
    ['profile:leaderboard'] = { 'nzh:profile:leaderboard' },
    ['profile:history']     = { 'nzh:profile:history' },
    ['chat:history']        = { 'nzh:chat:history' },
    ['chat:send']           = { 'nzh:chat:send', function(d) return d.text end },
    ['market:data']         = { 'nzh:market:data' },
    ['market:buy']          = { 'nzh:market:buy', function(d) return d.cart, d.account end },
    ['fence:data']          = { 'nzh:fence:data' },
    ['fence:sell']          = { 'nzh:fence:sell', function(d) return d.name, tonumber(d.amount) end },
}

for name, b in pairs(bridge) do
    RegisterNUICallback(name, function(data, cb)
        local a, b2 = lib.callback.await(b[1], false, b[2] and b[2](data or {}))
        -- callbacks either return (ok, data) or a single data table
        local ok, res
        if type(a) == 'table' and b2 == nil then ok, res = true, a else ok, res = a == true, b2 end
        if name == 'market:buy' and ok and type(res) == 'table' and res.seconds then
            Market.deliver(res.seconds)
        elseif name == 'heist:start' and ok then
            SetTimeout(250, Menu.close)
        end
        if name == 'crew:respond' then Menu.invite = nil end
        cb({ ok = ok, data = res })
    end)
end

RegisterNUICallback('menu:close', function(_, cb)
    cb(1)
    Menu.close()
end)

RegisterNUICallback('heist:gps', function(data, cb)
    cb(1)
    if data and data.x then SetNewWaypoint(data.x + 0.0, data.y + 0.0) end
end)

--[[ server -> NUI ]]
RegisterNetEvent('nzh:crew:update', function(state)
    if GetInvokingResource() then return end
    UI.send('crew', state)
end)

RegisterNetEvent('nzh:chat:message', function(msg)
    if GetInvokingResource() then return end
    UI.send('chat', msg)
end)

--[[ invites: popup + Y / N hotkeys while the tablet is closed ]]
Menu.invite = nil

RegisterNetEvent('nzh:crew:invited', function(data)
    if GetInvokingResource() then return end
    Menu.invite = data
    UI.send('invite', data)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
    CreateThread(function()
        local endAt = GetGameTimer() + data.timeout * 1000
        while Menu.invite == data and GetGameTimer() < endAt do
            if not UI.focus then
                if IsControlJustReleased(0, 246) then -- Y
                    Menu.invite = nil
                    lib.callback.await('nzh:crew:respond', false, true)
                elseif IsControlJustReleased(0, 306) then -- N
                    Menu.invite = nil
                    lib.callback.await('nzh:crew:respond', false, false)
                end
            end
            Wait(0)
        end
        if Menu.invite == data then Menu.invite = nil end
        UI.send('invite', false)
    end)
end)

--[[ /nzhcoords - copy your position as vec4 (for tuning heist locations) ]]
RegisterCommand('nzhcoords', function()
    local c, h = GetEntityCoords(cache.ped), GetEntityHeading(cache.ped)
    local s = ('vec4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, h)
    lib.setClipboard(s)
    print(s)
    UI.notify('Copied ' .. s, 'success')
end, false)
