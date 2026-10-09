-----------------------------------------------------------------
-- Jewellery isn't clothing
--
-- Chains chainkit converted from a clothing pack are sold at the
-- jewelry store now, so they can't be put on in a clothing store.
--   illenium-appearance: the addon in install/illenium-appearance
--     asks IsJewelleryDrawable before it sets any accessory (menu,
--     saved outfits, outfit codes, skin loading) and tells the player
--   anything else: Enforce takes it back off within ~2 seconds
-----------------------------------------------------------------

Appearance = {}

local cfg = Config.Appearance or {}
local blockColl = {}
for _, c in ipairs(cfg.BlockCollections or {}) do blockColl[string.lower(c)] = true end

--- Is accessory drawable `drawable` on `ped` a jewellery chain?
function Appearance.blocked(ped, drawable)
    if not cfg.BlockClothingChains or not drawable or drawable <= 0 then return false end
    if drawable == (Config.Snatch.ClothingNone or 0) then return false end
    local key, coll = Clothing.keyFor(ped, drawable)
    if not key then return false end
    if coll and blockColl[coll] then return true end
    local d = Chains.def(key)
    return d ~= nil and d.origin == 'server'
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
if cfg.BlockClothingChains and cfg.Enforce then
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
