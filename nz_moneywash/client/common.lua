--[[ Interactions shared by every machine + target option wiring ]]

Interact = {}
Common = {}

local A = Config.Anims

local zoneShape = {
    washer  = { z = 0.85, r = 0.42 }, -- tight: shop washers stand 0.87 m apart
    printer = { z = 1.00, r = 1.60 },
    cutter  = { z = 0.90, r = 0.95 },
    pallet  = { z = 0.45, r = 0.90 },
    counter = { z = 0.95, r = 0.70 },
}

local function collectAnim(d)
    if d.type == 'washer' then
        U.alignPed(d, Config.Offsets.washer.ped)
        U.playPed(A.throwCash)
        return 'Pulling the cash out of the drum', 3200
    elseif d.type == 'printer' then
        U.alignPed(d, Config.Offsets.printer.ped)
        U.playPed(A.machine, 1)
        return 'Pulling sheets off the tray', 3000
    end
    U.alignPed(d, Config.Offsets.cutter.ped)
    U.playPed(A.machine, 1)
    return 'Banding the stacks', 3000
end

function Common.collect(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'done' then return end
        local label, ms = collectAnim(d)
        local ok = UI.progress(label, ms)
        U.stopPed()
        if not ok then return end
        local res = lib.callback.await('nzmw:collect', false, id)
        if not res or not res.ok then return UI.err(res) end
        local b = res.batch
        UI.toast(Config.ItemLabels[res.item] or res.item, ('%s · %s · heat %d · Q%d%%'):format(
            b.serial, NZ.money(b.amount), b.heat, math.floor(b.quality * 100)), 'success', 7000)
    end)
end

function Common.unjam(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'jammed' then return end
        U.faceCoords(vec3(d.x, d.y, d.z))
        U.playPed(A.fix, 1)
        local kit = CBridge.hasItem(Config.Wear.repairItem)
        local easy = kit and Config.Wear.kitEasier
        local r = UI.await('timing', {
            mode = 'unjam', title = 'Clear the jam', rounds = 3,
            speed = easy and 0.9 or 1.25, zone = easy and 0.22 or 0.15,
        }, { cursor = false })
        U.stopPed()
        if type(r) ~= 'table' then return end
        local success = true
        for _, v in ipairs(r) do if v == 'miss' then success = false end end
        local res = lib.callback.await('nzmw:unjam', false, id, success)
        if not res or not res.ok then return UI.err(res) end
        if res.resumed then
            UI.toast('Back in business', 'The machine spins back up.', 'success')
        else
            UI.toast('Shredded', 'You tore some bills getting it loose. Try again.', 'error')
        end
    end)
end

function Common.pry(id)
    U.run(function()
        local d = Render.data(id)
        if not d then return end
        local res = lib.callback.await('nzmw:pry', false, id, 'start')
        if not res or not res.ok then return UI.err(res) end
        U.faceCoords(vec3(d.x, d.y, d.z))
        U.playPed(A.pry, 1)
        local ok = UI.progress('Prying the casing open', Config.Theft.duration)
        U.stopPed()
        if not ok then return end
        res = lib.callback.await('nzmw:pry', false, id, 'finish')
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Score', ('You ripped out %s.'):format(Config.ItemLabels[res.item] or res.item), 'success')
    end)
end

function Common.inspect(id)
    U.run(function()
        local res = lib.callback.await('nzmw:inspect', false, id)
        if not res or not res.ok then return UI.err(res) end
        res.serverNow = U.now()
        UI.await('inspect', res)
    end)
end

function Common.repair(id)
    U.run(function()
        local d = Render.data(id)
        if not d then return end
        U.faceCoords(vec3(d.x, d.y, d.z))
        U.playPed(A.fix, 1)
        local ok = UI.progress('Servicing bearings & belts', 8000)
        U.stopPed()
        if not ok then return end
        local res = lib.callback.await('nzmw:repair', false, id)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Serviced', 'Wear reset. Fewer jams ahead.', 'success')
    end)
end

function Common.scan(id)
    U.run(function()
        local d = Render.data(id)
        if not d then return end
        U.faceCoords(vec3(d.x, d.y, d.z))
        U.playPed(A.scan, 1)
        local ok = UI.progress('Sweeping UV over the machine', 2500)
        U.stopPed()
        if not ok then return end
        local res = lib.callback.await('nzmw:scan:station', false, id)
        if not res or not res.ok then return UI.err(res) end
        UI.await('scan', res)
    end)
end

function Common.pack(id)
    U.run(function()
        local ok = UI.progress('Unbolting the machine', 6000)
        if not ok then return end
        local res = lib.callback.await('nzmw:pack', false, id)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Packed up', 'The kit is back in your bag.', 'success')
    end)
end

function Common.seize(id)
    U.run(function()
        local ok = UI.progress('Tagging & seizing equipment', 7000)
        if not ok then return end
        local res = lib.callback.await('nzmw:seize', false, id)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Seized', res.seized > 0 and ('Equipment + %s in evidence.'):format(NZ.money(res.seized)) or 'Equipment seized.', 'success')
    end)
end

---------------------------------------------------------------------------------------------------
-- option builders
---------------------------------------------------------------------------------------------------
local function st(s) return s.data end
local function access(s) return U.hasAccess(s.data) end

local function typeOptions(s)
    local id = s.id
    local t = s.data.type
    if t == 'washer' then
        return {
            { name = 'open', label = 'Open the door', icon = 'fas fa-door-open',
              canInteract = function() return st(s).state == 'idle' and access(s) end,
              onSelect = function() Washer.open(id) end },
            { name = 'load', label = 'Load dirty cash', icon = 'fas fa-sack-dollar',
              canInteract = function() return st(s).state == 'open' and access(s) and U.lockMine(st(s)) end,
              onSelect = function() Washer.load(id) end },
            { name = 'close', label = 'Close the door', icon = 'fas fa-door-closed',
              canInteract = function() local x = st(s) return (x.state == 'open' or x.state == 'loaded') and access(s) and U.lockMine(x) end,
              onSelect = function() Washer.close(id) end },
            { name = 'program', label = 'Program the cycle', icon = 'fas fa-sliders',
              canInteract = function() return st(s).state == 'ready' and access(s) end,
              onSelect = function() Washer.program(id) end },
        }
    elseif t == 'printer' then
        return {
            { name = 'load', label = 'Feed the press', icon = 'fas fa-print',
              canInteract = function() return st(s).state == 'idle' and access(s) end,
              onSelect = function() Printer.load(id) end },
        }
    elseif t == 'counter' then
        return {
            { name = 'count_stacks', label = 'Count & strap stacks', icon = 'fas fa-money-bill-wave',
              canInteract = function() return st(s).state == 'idle' and access(s) and CBridge.hasItem(NZ.finalItem()) end,
              onSelect = function() CounterUI.start(id, 'stacks') end },
            { name = 'count_cash', label = 'Count my cash', icon = 'fas fa-wallet',
              canInteract = function() return st(s).state == 'idle' and access(s) end,
              onSelect = function() CounterUI.start(id, 'cash') end },
        }
    elseif t == 'pallet' then
        return {
            { name = 'take', label = 'Load into duffel bag', icon = 'fas fa-bag-shopping',
              canInteract = function() return st(s).state == 'done' and access(s) end,
              onSelect = function() PalletUI.take(id) end },
            { name = 'grab', label = 'Grab a stack', icon = 'fas fa-user-ninja',
              canInteract = function()
                  local x = st(s)
                  local open = not x.placed and (not x.access or (not x.access.jobs and not x.access.gangs and not x.access.items))
                  return Config.Pallet.theft and x.state == 'done' and (open or not access(s))
              end,
              onSelect = function() PalletUI.grab(id) end },
            { name = 'pseize', label = 'Seize the cash', icon = 'fas fa-handcuffs',
              canInteract = function() return st(s).state == 'done' and CBridge.isPolice() end,
              onSelect = function() PalletUI.seize(id) end },
        }
    elseif t == 'cutter' then
        return {
            { name = 'feed', label = 'Feed sheets', icon = 'fas fa-layer-group',
              canInteract = function() return st(s).state == 'idle' and access(s) end,
              onSelect = function() Cutter.feed(id) end },
            { name = 'cut', label = 'Work the blade', icon = 'fas fa-scissors',
              canInteract = function() return st(s).state == 'cutting' and access(s) and U.lockMine(st(s)) end,
              onSelect = function() Cutter.cut(id) end },
        }
    end
    return {}
end

local function commonOptions(s)
    local id = s.id
    local collectLabel = {
        washer = 'Unload wet cash', printer = 'Collect uncut sheets', cutter = 'Bundle the stacks',
    }
    return {
        { name = 'collect', label = collectLabel[s.data.type], icon = 'fas fa-hand-holding-dollar',
          canInteract = function() return st(s).state == 'done' and access(s) end,
          onSelect = function() Common.collect(id) end },
        { name = 'unjam', label = 'Clear the jam', icon = 'fas fa-wrench',
          canInteract = function() return st(s).state == 'jammed' and access(s) end,
          onSelect = function() Common.unjam(id) end },
        { name = 'pry', label = 'Pry it open', icon = 'fas fa-user-ninja',
          canInteract = function()
              local x = st(s)
              local open = not x.placed and (not x.access or (not x.access.jobs and not x.access.gangs and not x.access.items))
              return Config.Theft.enabled and x.type ~= 'cutter' and x.hasBatch
                  and (x.state == 'running' or x.state == 'done' or x.state == 'jammed')
                  and (open or not access(s)) and CBridge.hasAny(Config.Theft.items)
          end,
          onSelect = function() Common.pry(id) end },
        { name = 'inspect', label = 'Inspect machine', icon = 'fas fa-gauge-high',
          canInteract = function() return access(s) or CBridge.isPolice() end,
          onSelect = function() Common.inspect(id) end },
        { name = 'repair', label = 'Service machine', icon = 'fas fa-screwdriver-wrench',
          canInteract = function()
              local x = st(s)
              return (x.state == 'idle' or x.state == 'done') and (x.wear or 0) > 5 and access(s) and CBridge.hasItem(Config.Wear.repairItem)
          end,
          onSelect = function() Common.repair(id) end },
        { name = 'scan', label = 'UV scan machine', icon = 'fas fa-magnifying-glass-dollar',
          canInteract = function() return CBridge.isPolice() and CBridge.hasItem(Config.Heat.scannerItem) end,
          onSelect = function() Common.scan(id) end },
        { name = 'pack', label = 'Pack up equipment', icon = 'fas fa-box',
          canInteract = function() local x = st(s) return x.placed and x.state == 'idle' and x.owner == CBridge.getIdentifier() end,
          onSelect = function() Common.pack(id) end },
        { name = 'move', label = 'Move machine (admin)', icon = 'fas fa-up-down-left-right',
          canInteract = function() return U.isAdmin and st(s).state == 'idle' end,
          onSelect = function() if not Placement.active then CreateThread(function() Placement.run(s.data.type, { moveId = id }) end) end end },
        { name = 'reset', label = 'Reset to config spot (admin)', icon = 'fas fa-rotate-left',
          canInteract = function() return U.isAdmin and not st(s).placed and st(s).state == 'idle' end,
          onSelect = function()
              local res = lib.callback.await('nzmw:admin:reset', false, id)
              if not res or not res.ok then UI.err(res) else UI.toast('Reset', 'Back to its config position.', 'success') end
          end },
        { name = 'seize', label = 'Seize equipment', icon = 'fas fa-handcuffs',
          canInteract = function() return st(s).placed and CBridge.isPolice() end,
          onSelect = function() Common.seize(id) end },
    }
end

local function alive(s) return Render.get(s.id) == s end

function Interact.add(s)
    local d = s.data
    local shape = zoneShape[d.type] or { z = 0.9, r = 1.0 }
    local opts = typeOptions(s)
    local machineOnly = { collect = true, unjam = true, pry = true, repair = true }
    for _, o in ipairs(commonOptions(s)) do
        if not ((d.type == 'pallet' or d.type == 'counter') and machineOnly[o.name]) then opts[#opts + 1] = o end
    end
    -- never offer anything while another interaction is running
    for _, o in ipairs(opts) do
        local inner = o.canInteract
        o.canInteract = function() return not U.busy and not UI.isOpen() and alive(s) and inner() end
    end
    s.zone = Target.addZone('nzmw_' .. s.id, vec3(d.x, d.y, d.z + shape.z), shape.r, opts)
end

function Interact.remove(s)
    Target.removeZone(s.zone)
    s.zone = nil
end
