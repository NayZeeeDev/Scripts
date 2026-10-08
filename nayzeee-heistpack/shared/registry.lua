--[[
    Heist registry: loads every config/heists/<id>.lua listed in Config.Heists.

    HEIST DEFINITION
    ----------------
    label, description, category ('small'|'medium'|'major'), icon (ui icon key)
    level, police, members = { min, max }, cooldown (min, global), playerCooldown (min)
    timeLimit (min, 0 = none), simultaneous (crews at once on different locations)
    locationMode = 'random' | 'select'   -- 'select': the crew picks by driving to any marked location
    selectLabel  = 'Go to any marked store'
    requiredItems = { { name, count, label } }      -- someone in the crew must carry them
    rewards = { xp = 300, money = { min, max } }    -- completion bonus (split by crew)
    escape = 150.0                                  -- auto final stage: get this far from loc.center (false = none)
    briefing = { 'step', ... }
    loot = { key = { { item, min, max, chance } } } -- item 'money' follows Config.Money
    locations = { { label, center = vec3, doors = { id = door }, ... } }
    stages = function(loc, heist) return { stage, ... } end

    STAGE  { id, task, blip = { coords, label, sprite?, radius?, route? }, spawn = {...}, nodes = {...}, complete = 'all'|n, noise = bool }
    SPAWN  { guards = { { coords, model?, weapon?, group? } }, vehicles = { { key, model, coords, type?, locked?, unlockFlag?, driver?, route?, crew? } },
             peds = { { key, model, coords, scenario?, anim? } }, objects = { { key, model, coords } } }
    NODE   { id, type, label, coords, ... }  - see client/heist/nodes.lua for every type
    DOOR   { model | models, coords, radius?, kind = 'vault'|'gate', delta? (vault open rotation) }
]]

Heists = { defs = {}, order = {} }

local DEFAULTS = {
    enabled = true,
    category = 'small',
    icon = 'mask',
    level = 1,
    police = 0,
    cooldown = 0,
    playerCooldown = 5,
    timeLimit = 0,
    simultaneous = 1,
    locationMode = 'random',
    escape = 150.0,
    requiredItems = {},
    briefing = {},
    loot = {},
}

for i = 1, #Config.Heists do
    local id = Config.Heists[i]
    local ok, def = pcall(lib.load, 'config.heists.' .. id)
    if not ok or type(def) ~= 'table' then
        print(('^1[%s] failed to load heist "%s": %s^7'):format(GetCurrentResourceName(), id, tostring(def)))
    else
        for k, v in pairs(DEFAULTS) do
            if def[k] == nil then def[k] = v end
        end
        def.id = id
        def.members = def.members or { min = 1, max = 4 }
        def.rewards = def.rewards or { xp = 100 }
        if def.enabled then
            Heists.defs[id] = def
            Heists.order[#Heists.order + 1] = id
        end
    end
end

--- Public, serialisable summary for the tablet
function Heists.summary(id)
    local d = Heists.defs[id]
    if not d then return nil end
    local items = {}
    for i = 1, #d.requiredItems do
        local it = d.requiredItems[i]
        items[i] = { name = it.name, count = it.count or 1, label = it.label or it.name }
    end
    local money = d.rewards.money
    return {
        id = id,
        label = d.label,
        description = d.description,
        category = d.category,
        icon = d.icon,
        image = d.image,
        level = d.level,
        police = d.police,
        members = d.members,
        cooldown = d.cooldown,
        playerCooldown = d.playerCooldown,
        timeLimit = d.timeLimit,
        xp = d.rewards.xp or 0,
        money = type(money) == 'table' and money or (money and { money, money }) or nil,
        requiredItems = items,
        briefing = d.briefing,
        locations = #d.locations,
    }
end
