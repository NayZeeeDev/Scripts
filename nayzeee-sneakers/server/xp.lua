--[[
    Built-in XP, saved per character. Crafting gives XP now; selling will too.

    Other scripts:
        exports['nayzeee-sneakers']:GetXP(src)
        exports['nayzeee-sneakers']:GetLevel(src)
        exports['nayzeee-sneakers']:AddXP(src, amount)
]]

XP = {}

local function key(id) return 'xp:' .. id end

function XP.Get(src)
    local id = Bridge.GetIdentifier(src)
    return id and GetResourceKvpInt(key(id)) or 0
end

function XP.Level(src)
    return (Shared.LevelFor(XP.Get(src)))
end

--- Adds XP and tells the player. Returns new total, new level, levelled up.
function XP.Add(src, amount)
    local id = Bridge.GetIdentifier(src)
    if not id then return 0, 1, false end
    local before = GetResourceKvpInt(key(id))
    local after = math.max(0, before + math.floor(amount))
    SetResourceKvpInt(key(id), after)
    local oldLevel = Shared.LevelFor(before)
    local level, from, to = Shared.LevelFor(after)
    TriggerClientEvent('nayzeee-sneakers:client:xp', src, { xp = after, level = level, from = from, to = to, gained = after - before, levelUp = level > oldLevel })
    return after, level, level > oldLevel
end

exports('GetXP', XP.Get)
exports('GetLevel', XP.Level)
exports('AddXP', function(src, amount) return XP.Add(src, tonumber(amount) or 0) end)

-- /sneakerxp [id] [amount]   (negative takes XP away)
RegisterCommand(Config.Commands.xp, function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    local amount = tonumber(args[2])
    local msg
    if amount then
        local total, level = XP.Add(target, amount)
        msg = ('Player %d now has %d XP (level %d)'):format(target, total, level)
    else
        msg = ('Player %d has %d XP (level %d)'):format(target, XP.Get(target), XP.Level(target))
    end
    if src == 0 then print(msg) else Bridge.Notify(src, msg, 'inform') end
end, false)
