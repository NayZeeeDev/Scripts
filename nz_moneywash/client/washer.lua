--[[ Washer — open, load, close, program (WIWANG panel), collect ]]

Washer = {}

local A, O = Config.Anims, Config.Offsets.washer

function Washer.open(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'idle' then return end
        U.alignPed(d, O.ped)
        U.playPed(A.openDoor)
        Wait(A.openDoor.doorAt)
        local res = lib.callback.await('nzmw:washer:open', false, id)
        if not res or not res.ok then U.stopPed() return UI.err(res) end
        Wait(A.openDoor.total - A.openDoor.doorAt)
    end)
end

function Washer.load(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'open' then return end
        local sources = lib.callback.await('nzmw:dirtySources', false) or {}
        if #sources == 0 then
            return UI.toast('Empty pockets', 'You are not carrying any dirty money.', 'error')
        end
        local cfg = Config.Stages.washer
        local pick = UI.await('load', {
            station = d.label, op = d.opLabel, sources = sources,
            min = cfg.min, max = cfg.max, wear = d.wear,
            baseTime = cfg.baseTime, perThousand = cfg.perThousand,
            rate = (GlobalState['nzmw:market'] or {}).rate,
        })
        if not pick or not pick.source or not pick.amount then return end

        U.alignPed(d, O.ped)
        U.playPed(A.throwCash)
        if not UI.progress('Emptying the duffel into the drum', A.throwCash.total) then
            U.stopPed()
            return UI.toast('Stopped', 'You stuff the cash back in the bag.', 'info')
        end
        local res = lib.callback.await('nzmw:washer:load', false, id, pick.source, pick.amount)
        if not res or not res.ok then U.stopPed() return UI.err(res) end
        local b = res.batch
        UI.toast('Batch ' .. b.serial, ('%s loaded · %s'):format(NZ.money(b.amount), b.dyeLabel), 'success', 7000)
    end)
end

function Washer.close(id)
    U.run(function()
        local d = Render.data(id)
        if not d or (d.state ~= 'open' and d.state ~= 'loaded') then return end
        U.alignPed(d, O.ped)
        U.playPed(A.closeDoor)
        Wait(A.closeDoor.doorAt)
        local res = lib.callback.await('nzmw:washer:shut', false, id)
        if not res or not res.ok then U.stopPed() return UI.err(res) end
        Wait(A.closeDoor.total - A.closeDoor.doorAt)
    end)
end

function Washer.program(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'ready' then return end
        local info = lib.callback.await('nzmw:washer:info', false, id)
        if not info or not info.ok then return UI.err(info) end
        info.station = d.label
        info.temps = Config.Wash.temps
        info.dyeBands = Config.Wash.dyeBands
        info.penalty = { one = Config.Wash.penaltyOneOff, two = Config.Wash.penaltyTwoOff }
        info.alert = { base = Config.Heat.alertBase, perHeat = Config.Heat.alertPerHeat }
        info.heatDrop = Config.Stages.washer.heatDrop
        info.solventBonus = Config.Wash.solventBonus
        info.serverNow = U.now()
        local prog = UI.await('program', info)
        if not prog then return end

        U.alignPed(d, O.ped)
        U.playPed(A.startWash)
        Wait(math.floor(U.animMs(A.startWash, 2500) * 0.8))
        local res = lib.callback.await('nzmw:washer:start', false, id, prog.temp, prog.spin, prog.solvent)
        if not res or not res.ok then U.stopPed() return UI.err(res) end
        UI.toast('Cycle started', ('%s · %s spin · done in %s'):format(
            Config.Wash.temps[prog.temp].label, Config.Wash.spins[prog.spin].label, U.fmtTime(res.endsAt - U.now())), 'success')
    end)
end
