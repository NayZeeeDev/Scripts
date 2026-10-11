--[[ Performance lab: real, timed runs with a leaderboard per test and per model. ]]

PerfTest = { running = false }

local TESTS = {}
for _, t in ipairs(Config.PerfTest.Tests) do TESTS[t.id] = t end
local toUnit = Config.PerfTest.Units == 'kmh' and 3.6 or 2.236936

local function hud(d) UI.Send('hud:perf', d) end

function PerfTest.Start(testId)
    if not Config.PerfTest.Enabled or PerfTest.running then return end
    local test = TESTS[testId]
    if not test then return Notify(L('perf_unknown'), 'error') end
    local veh = cache.vehicle
    if not veh or cache.seat ~= -1 then return Notify(L('must_drive'), 'error') end

    PerfTest.running = true
    CreateThread(function()
        local label = VehUtil.Label(veh)
        local startAt, dist, lastHud = nil, 0.0, 0
        local deadline = GetGameTimer() + Config.PerfTest.Timeout * 1000
        local lastPos = GetEntityCoords(veh)
        local armed = test.kind ~= 'brake'
        local result

        if test.kind ~= 'brake' and GetEntitySpeed(veh) > 0.5 then
            hud({ show = true, label = test.label, state = L('perf_stop_first') })
            while GetEntitySpeed(veh) > 0.5 and GetGameTimer() < deadline and cache.vehicle == veh do Wait(100) end
        end
        hud({ show = true, label = test.label, state = test.kind == 'brake' and L('perf_reach', test.target, Config.PerfTest.Units) or L('perf_ready') })

        while GetGameTimer() < deadline and cache.vehicle == veh and cache.seat == -1 do
            local now = GetGameTimer()
            local speed = GetEntitySpeed(veh)
            local unitSpeed = speed * toUnit

            if test.kind == 'brake' then
                if not armed and unitSpeed >= test.target then
                    armed = true
                    hud({ show = true, label = test.label, state = L('perf_brake_now') })
                end
                if armed and not startAt and GetControlNormal(0, 72) > 0.5 then startAt = now end
                if startAt and speed < 0.4 then result = (now - startAt) / 1000 break end
            else
                if not startAt and speed > 0.4 then startAt = now lastPos = GetEntityCoords(veh) end
                if startAt then
                    local pos = GetEntityCoords(veh)
                    dist = dist + #(pos - lastPos)
                    lastPos = pos
                    if (test.kind == 'speed' and unitSpeed >= test.target) or (test.kind == 'distance' and dist >= test.target) then
                        result = (now - startAt) / 1000
                        break
                    end
                end
            end

            if startAt and now - lastHud > 50 then
                lastHud = now
                hud({ show = true, label = test.label, time = (now - startAt) / 1000, speed = math.floor(unitSpeed), units = Config.PerfTest.Units,
                    progress = test.kind == 'distance' and dist / test.target or (test.kind == 'speed' and unitSpeed / test.target or nil) })
            end
            Wait(0)
        end

        PerfTest.running = false
        if not result then
            hud({ show = false })
            return Notify(L('perf_aborted'), 'error')
        end
        hud({ show = true, label = test.label, time = result, final = true, units = Config.PerfTest.Units })
        local ok, res = lib.callback.await('nayzeee-tuning:perfSubmit', false, testId, result, VehToNet(veh), label)
        if ok then
            hud({ show = true, label = test.label, time = result, final = true, rank = res.rank, pb = res.pb, units = Config.PerfTest.Units })
        else
            Notify(res or L('perf_rejected'), 'error')
        end
        Wait(6000)
        hud({ show = false })
    end)
end

if Config.PerfTest.Enabled then
    RegisterCommand(Config.PerfTest.Command, function(_, args)
        PerfTest.Start(args[1] or Config.PerfTest.Tests[1].id)
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. Config.PerfTest.Command, 'Start a timed performance run', {
        { name = 'test', help = 'zero60 | zero100 | quarter | half | brake60' },
    })
end

UI.On('perfStart', function(d)
    if Menu.open then Menu.Close(false) end
    SetTimeout(600, function() PerfTest.Start(d.test) end)
    return true
end)
