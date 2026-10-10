--[[ Guillotine — feed sheets, then a timing minigame per cut (moneycut_a → b → c) ]]

Cutter = {}

local A, O = Config.Anims, Config.Offsets.cutter

function Cutter.feed(id)
    local fed = false
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'idle' then return end
        local inItem = NZ.inputItem('cutter')
        if not CBridge.hasItem(inItem) then
            return UI.toast('Nothing to cut', ('You need %s.'):format(Config.ItemLabels[inItem] or inItem), 'error')
        end
        U.alignPed(d, O.ped)
        U.playPed(A.machine, 1)
        local ok = UI.progress('Squaring the sheets on the bed', 3000)
        U.stopPed()
        if not ok then return end
        local res = lib.callback.await('nzmw:cutter:feed', false, id)
        if not res or not res.ok then return UI.err(res) end
        -- wait for the synced state so the minigame starts on the right round
        local t = GetGameTimer() + 2000
        while GetGameTimer() < t and Render.data(id) and Render.data(id).state ~= 'cutting' do Wait(50) end
        fed = true
    end)
    if fed then Cutter.cut(id) end
end

function Cutter.cut(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'cutting' then return end
        U.alignPed(d, O.ped)
        local total = Config.Stages.cutter.cuts
        local results = {}
        for round = (d.cut or 0) + 1, total do
            local r = UI.await('timing', {
                mode = 'cut', title = 'Guillotine', round = round, total = total, rounds = 1,
                speed = 1.0 + (round - 1) * 0.35, zone = 0.20 - (round - 1) * 0.03,
            }, { cursor = false })
            local result = type(r) == 'table' and r[1] or nil
            if not result then
                UI.toast('Paused', 'The sheets stay on the bed. Come back to finish.', 'info')
                return
            end
            U.playPed(A.cutting, 48)
            Wait(A.cutting.bladeAt)
            local res = lib.callback.await('nzmw:cutter:cut', false, id, result)
            if not res or not res.ok then U.stopPed() return UI.err(res) end
            results[#results + 1] = result
            Wait(A.cutting.bladeUp + 350)
            if res.done then
                local perfect = 0
                for _, r in ipairs(results) do if r == 'perfect' then perfect = perfect + 1 end end
                UI.toast('Stacks banded', ('%d perfect cut(s) · quality %d%%'):format(perfect, math.floor((res.quality or 1) * 100)), 'success')
                break
            end
        end
    end)
end
