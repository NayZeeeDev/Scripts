--[[
    Prison jumpsuit. The player's real outfit is stored in resource KVP on their own PC,
    keyed by sentence + character, so it survives reconnects, restarts and character swaps.
]]

Outfit = {}

local cfg = Config.Outfit
local KVP = 'nayzeee-adminjail:outfit'
local PROPS = { 0, 1, 2, 6, 7 }

local function gender(ped)
    local model = GetEntityModel(ped)
    if model == `mp_m_freemode_01` then return 'male' end
    if model == `mp_f_freemode_01` then return 'female' end
end

local function capture(ped)
    local out = { model = GetEntityModel(ped), comps = {}, props = {} }
    for c = 0, 11 do
        out.comps[#out.comps + 1] = { c, GetPedDrawableVariation(ped, c), GetPedTextureVariation(ped, c), GetPedPaletteVariation(ped, c) }
    end
    for i = 1, #PROPS do
        local p = PROPS[i]
        out.props[#out.props + 1] = { p, GetPedPropIndex(ped, p), GetPedPropTextureIndex(ped, p) }
    end
    return out
end

local function load()
    local raw = GetResourceKvpString(KVP)
    return raw and json.decode(raw) or nil
end

--- `key` identifies the sentence (jailedAt). Saves the real outfit once, then dresses the ped.
function Outfit.Apply(key)
    if not cfg.enabled then return end
    local ped = PlayerPedId()
    local g = gender(ped)
    if not g then return end

    key = ('%s:%s'):format(key, Bridge.CharId())
    local saved = load()
    if not saved or saved.key ~= key then
        SetResourceKvp(KVP, json.encode({ key = key, outfit = capture(ped) }))
    end

    for comp, v in pairs(cfg[g]) do
        SetPedComponentVariation(ped, comp, v[1], v[2] or 0, 0)
    end
    if cfg.clearProps then ClearAllPedProps(ped) end
end

function Outfit.Restore()
    if not cfg.enabled then return end
    local saved = load()
    if not saved then return end
    DeleteResourceKvp(KVP)

    local ped = PlayerPedId()
    local o = saved.outfit
    if not o or o.model ~= GetEntityModel(ped) then return end
    if not saved.key:find(':' .. Bridge.CharId(), 1, true) then return end

    for i = 1, #o.comps do
        local c = o.comps[i]
        SetPedComponentVariation(ped, c[1], c[2], c[3], c[4])
    end
    ClearAllPedProps(ped)
    for i = 1, #o.props do
        local p = o.props[i]
        if p[2] >= 0 then SetPedPropIndex(ped, p[1], p[2], p[3], true) end
    end
end
