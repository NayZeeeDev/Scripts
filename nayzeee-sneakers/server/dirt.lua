--[[
    Dirt and wear on the pair you're wearing, and cleaning a pair with a kit.

    The client measures how far you walk and what you walk on, and reports every
    Config.Dirt.Sync seconds. The server caps each report by the time since the
    last one, so nobody can send a marathon in one tick.
]]

local DIRT = Config.Dirt
local CLEAN = Config.Cleaning
local lastTick = {}     -- [src] = os.time() of the last report
local cleaning = {}     -- [src] = { slot, serial, started, minTime, stages }

local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

-- the most a report can add, given the worst ground, sprinting in the rain
local function maxMult()
    local g = 1.0
    for _, v in pairs(DIRT.Ground) do g = math.max(g, v) end
    return g * DIRT.Sprint * DIRT.Rain
end

lib.callback.register('nayzeee-sneakers:wearTick', function(src, km, dirt, swam)
    if not DIRT.Enabled then return nil end
    local id = Bridge.GetIdentifier(src)
    local worn = id and Wear.Get(id)
    if not worn then return nil end

    local now = os.time()
    local elapsed = math.max(1, now - (lastTick[src] or (now - DIRT.Sync)))
    lastTick[src] = now
    km = math.max(0.0, math.min(tonumber(km) or 0.0, elapsed * 0.012))      -- 12 m/s at most
    dirt = math.max(0.0, math.min(tonumber(dirt) or 0.0, km * DIRT.PerKm * maxMult() + (swam and DIRT.Swim or 0.0)))

    local meta = worn.meta
    local before = meta.condition
    meta.km = math.floor(((tonumber(meta.km) or 0.0) + km) * 100 + 0.5) / 100   -- km kept to 2 decimals
    meta.dirt = round1(math.min(100.0, (tonumber(meta.dirt) or 0.0) + dirt))
    meta.condition = Shared.WearCondition(meta.km, meta.condition)
    Wear.Set(id, worn)
    return { dirt = meta.dirt, km = meta.km, condition = meta.condition, changed = meta.condition ~= before }
end)

AddEventHandler('playerDropped', function()
    lastTick[source] = nil
    cleaning[source] = nil
end)

--------------------------------------------------------------------------------
-- Cleaning
--------------------------------------------------------------------------------

--- The pair at `slot`, or the same pair (by serial) if it moved
local function findPair(src, slot, serial)
    local it = Inv.GetSlot(src, slot)
    if it and it.name == Config.Items.shoes and it.metadata.serial == serial then return it end
    for _, p in ipairs(Inv.List(src, Config.Items.shoes)) do
        if p.metadata.serial == serial then return p end
    end
end

lib.callback.register('nayzeee-sneakers:cleanStart', function(src, slot)
    local it = Inv.GetSlot(src, slot)
    if not it or it.name ~= Config.Items.shoes or not Config.Shoes[it.metadata.shoe] then return false end
    if (tonumber(it.metadata.dirt) or 0) <= 0 then
        Bridge.Notify(src, Config.Text.alreadyClean, 'inform')
        return false
    end
    if not Inv.Find(src, Config.Items.cleaningKit) then
        Bridge.Notify(src, Config.Text.noKit, 'error')
        return false
    end
    local total = 0
    for _, s in ipairs(CLEAN.Stages) do total = total + s.time end
    cleaning[src] = { slot = slot, serial = it.metadata.serial, started = GetGameTimer(), minTime = total * 0.85 }
    return true, CLEAN.Stages
end)

lib.callback.register('nayzeee-sneakers:cleanCancel', function(src)
    cleaning[src] = nil
    return true
end)

lib.callback.register('nayzeee-sneakers:cleanFinish', function(src, results)
    local s = cleaning[src]
    cleaning[src] = nil
    if not s or GetGameTimer() - s.started < s.minTime then return false end

    local pair = findPair(src, s.slot, s.serial)
    local kit = Inv.Find(src, Config.Items.cleaningKit)
    if not pair or not kit then return false end

    local missed = 0
    results = type(results) == 'table' and results or {}
    for i, st in ipairs(CLEAN.Stages) do
        if st.check and results[i] ~= true then missed = missed + 1 end
    end

    local meta = Items.Clean(pair.metadata)
    local before = tonumber(meta.dirt) or 0
    meta.dirt = math.min(before, math.max(0, before - CLEAN.Power) + missed * CLEAN.MissedSpot)
    if not Inv.SetMetadata(src, pair.slot, Config.Items.shoes, Items.Decorate(meta, false)) then return false end

    local uses = (tonumber(kit.metadata and kit.metadata.uses) or CLEAN.Uses) - 1
    if uses <= 0 then
        Inv.Remove(src, Config.Items.cleaningKit, 1, kit.slot)
        Bridge.Notify(src, Config.Text.kitEmpty, 'warning')
    else
        Inv.SetMetadata(src, kit.slot, Config.Items.cleaningKit, { uses = uses, description = Config.Text.kitUses:format(uses) })
    end
    XP.Add(src, CLEAN.XP)
    Stats.Add(src, { cleaned = 1 })
    return true, math.floor(meta.dirt), math.max(0, uses)
end)

-- Using a cleaning kit picks which pair to clean
CreateThread(function()
    Inv.RegisterUsable(Config.Items.cleaningKit, function(src)
        TriggerClientEvent('nayzeee-sneakers:client:useKit', src)
    end)
end)

-- /sneakerdirt [amount]: set the dirt on the pair you're wearing (testing)
RegisterCommand(Config.Commands.dirt, function(src, args)
    if src == 0 or not Bridge.IsAdmin(src) then return end
    local id = Bridge.GetIdentifier(src)
    local worn = id and Wear.Get(id)
    if not worn then return Bridge.Notify(src, Config.Text.notWearing, 'error') end
    worn.meta.dirt = math.max(0, math.min(100, tonumber(args[1]) or 50))
    Wear.Set(id, worn)
    TriggerClientEvent('nayzeee-sneakers:client:wornMeta', src, worn.meta)
    Bridge.Notify(src, ('Dirt set to %d%%'):format(worn.meta.dirt), 'success')
end, false)
