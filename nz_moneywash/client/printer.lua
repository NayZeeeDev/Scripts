--[[ Re-serial press — feed wet cash + paper, get fresh-serial uncut sheets ]]

Printer = {}

local A = Config.Anims

function Printer.load(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'idle' then return end
        local inItem = NZ.inputItem('printer')
        if not CBridge.hasItem(inItem) then
            return UI.toast('Nothing to press', ('You need %s.'):format(Config.ItemLabels[inItem] or inItem), 'error')
        end
        if not CBridge.hasItem(Config.Stages.printer.paperItem) then
            return UI.toast('No paper', ('The press needs %s.'):format(Config.ItemLabels[Config.Stages.printer.paperItem]), 'error')
        end
        U.alignPed(d, Config.Offsets.printer.ped)
        U.playPed(A.machine, 1)
        local ok = UI.progress('Threading paper & calibrating serial heads', 6000)
        U.stopPed()
        if not ok then return end
        local res = lib.callback.await('nzmw:printer:load', false, id)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Press running', ('%d roll(s) loaded · done in %s'):format(res.rolls, U.fmtTime(res.endsAt - U.now())), 'success')
    end)
end
