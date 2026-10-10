--[[ Pure product math, shared by client (previews) and server (truth). ]]

Mix = {}

--- effects after mixing `ingredient` into a product with `effects` (new table, input untouched)
function Mix.apply(effects, ingredient)
    local ing = Config.Ingredients[ingredient]
    if not ing then return nil end
    local have, out = {}, {}
    for i = 1, #effects do have[effects[i]] = true end

    -- replacements are decided against the original list, then applied in order
    for i = 1, #effects do
        local e = effects[i]
        local to = ing.rules[e]
        if to and not have[to] then
            have[e] = nil
            have[to] = true
            out[#out + 1] = to
        else
            out[#out + 1] = e
        end
    end

    if not have[ing.effect] and #out < Config.Mixing.maxEffects then
        out[#out + 1] = ing.effect
    end
    return out
end

function Mix.multiplier(effects)
    local m = 0.0
    for i = 1, #effects do
        local e = Config.Effects[effects[i]]
        if e then m = m + e.mult end
    end
    return m
end

--- market value of one unit
function Mix.value(base, effects)
    local s = Config.Strains[base]
    if not s then return 0 end
    return math.floor(s.price * (1.0 + Mix.multiplier(effects)) + 0.5)
end

--- stable identity of a recipe result: same strain + same effects = same product
function Mix.key(base, effects)
    local list = {}
    for i = 1, #effects do list[i] = effects[i] end
    table.sort(list)
    return base .. ':' .. table.concat(list, ',')
end
