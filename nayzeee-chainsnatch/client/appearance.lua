-----------------------------------------------------------------
-- Jewellery isn't clothing
--
-- The chains listed in Config.Appearance.Block are sold at the
-- jewelry store, so they can't be put on in a clothing store.
--   illenium-appearance: the addon in install/illenium-appearance
--     asks IsJewelleryDrawable before it sets any accessory (menu,
--     saved outfits, outfit codes, skin loading) and tells the player
--   anything else: Enforce takes it back off within ~2 seconds
-----------------------------------------------------------------

Appearance = {}

local cfg = Config.Appearance or {}

-- Config.Appearance.Block -> fast lookups
local keys, whole, some = {}, {}, {}
for _, b in ipairs(cfg.Block or {}) do
    if type(b) == 'string' then
        keys[string.lower(b)] = true
    elseif type(b) == 'table' and type(b.collection) == 'string' then
        local c = string.lower(b.collection)
        if type(b.drawables) == 'table' and #b.drawables > 0 then
            some[c] = some[c] or {}
            for _, n in ipairs(b.drawables) do some[c][tonumber(n)] = true end
        else
            whole[c] = true
        end
    end
end
local anything = next(keys) or next(whole) or next(some)

--- Is accessory drawable `drawable` on `ped` one of the chains listed in Config.Appearance.Block?
function Appearance.blocked(ped, drawable)
    if not anything or not drawable or drawable <= 0 then return false end
    if drawable == (Config.Snatch.ClothingNone or 0) then return false end
    local key, coll = Clothing.keyFor(ped, drawable)
    if not key then return false end
    if keys[key] then return true end
    if coll and whole[coll] then return true end
    local n = tonumber(key:match('|(%d+)$'))
    return coll ~= nil and n ~= nil and some[coll] ~= nil and some[coll][n] == true
end

local last = 0
function Appearance.notify()
    if GetGameTimer() - last < 2500 then return end
    last = GetGameTimer()
    CB.Notify(Config.Text.jewellery_only, 'warning', 5000)
end

exports('IsJewelleryDrawable', function(ped, drawable)
    return Appearance.blocked(ped or PlayerPedId(), tonumber(drawable) or -1)
end)
exports('NotifyJewellery', Appearance.notify)

-- any other clothing script
if anything and cfg.Enforce then
    CreateThread(function()
        while true do
            Wait(2000)
            local ped = PlayerPedId()
            if Appearance.blocked(ped, GetPedDrawableVariation(ped, 7)) then
                SetPedComponentVariation(ped, 7, Config.Snatch.ClothingNone or 0, 0, 0)
                Appearance.notify()
            end
        end
    end)
end
