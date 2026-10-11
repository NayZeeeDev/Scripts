--[[
    Bay claiming. A mechanic reserves a bay; it shows their name and (optionally) only they can work in it.
    Claims live in memory and are mirrored to GlobalState.nzBays = { [shop] = { ['1'] = { name, id } } }.
    They are freed on disconnect, when the mechanic loses the job, or by a manager.
]]

local B = Config.Bays
local claims = {}          -- [shop] = { [bay] = { id, name, src } }

local function publish()
    local out = {}
    for shop, list in pairs(claims) do
        for bay, c in pairs(list) do
            out[shop] = out[shop] or {}
            out[shop][tostring(bay)] = { name = c.name, sid = c.src }
        end
    end
    GlobalState.nzBays = out
end

local function countFor(identifier)
    local n = 0
    for _, list in pairs(claims) do for _, c in pairs(list) do if c.id == identifier then n = n + 1 end end end
    return n
end

local function view(src, shop)
    local s = Config.Shops[shop]
    local me = Bridge.GetIdentifier(src)
    local out = {}
    for i in ipairs(s.bays or {}) do
        local c = (claims[shop] or {})[i]
        out[i] = { bay = i, name = c and c.name or nil, mine = c ~= nil and c.id == me, avatar = c and Avatars.Of(c.id) or nil }
    end
    return {
        enabled = NZ.BayClaims(shop), bays = out, max = B.MaxPerMechanic, manager = Core.HasShopRank(src, shop, 'manager'),
        canClaim = Core.HasShopRank(src, shop, B.MinRank),
    }
end

lib.callback.register('nayzeee-tuning:bays', function(src)
    local shop = Tablet.RankOf(src)
    if not shop then return false, L('no_permission') end
    return true, view(src, shop)
end)

lib.callback.register('nayzeee-tuning:bayClaim', function(src, bay, shopId)
    if not Core.Throttle(src, 'bay', 800) then return false, L('slow_down') end
    local shop = shopId or Tablet.RankOf(src)
    bay = math.floor(tonumber(bay) or 0)
    if not shop or not NZ.BayClaims(shop) or not Core.HasShopRank(src, shop, B.MinRank) then return false, L('no_permission') end
    local s = Config.Shops[shop]
    if not s.bays[bay] then return false end
    claims[shop] = claims[shop] or {}
    local id = Bridge.GetIdentifier(src)
    local c = claims[shop][bay]
    if c then return false, c.id == id and L('bay_yours') or L('bay_taken', c.name) end
    if countFor(id) >= B.MaxPerMechanic then return false, L('bay_limit', B.MaxPerMechanic) end
    claims[shop][bay] = { id = id, name = Bridge.GetName(src), src = src }
    publish()
    return true, view(src, shop)
end)

lib.callback.register('nayzeee-tuning:bayRelease', function(src, bay, shopId)
    local shop = shopId or Tablet.RankOf(src)
    bay = math.floor(tonumber(bay) or 0)
    if not shop or not claims[shop] or not claims[shop][bay] then return false end
    local c = claims[shop][bay]
    local mine = c.id == Bridge.GetIdentifier(src)
    if not mine and not (B.ManagersUseAny and Core.HasShopRank(src, shop, 'manager')) then return false, L('no_permission') end
    claims[shop][bay] = nil
    if not mine and c.src then Core.Notify(c.src, L('bay_freed_by', Bridge.GetName(src), bay), 'inform') end
    publish()
    return true, view(src, shop)
end)

local function dropAll(pred)
    local changed = false
    for shop, list in pairs(claims) do
        for bay, c in pairs(list) do
            if pred(shop, c) then list[bay] = nil changed = true end
        end
    end
    if changed then publish() end
end

AddEventHandler('playerDropped', function()
    local src = source
    dropAll(function(_, c) return c.src == src end)
end)

-- lost the job / shop removed in the editor / claims switched off
CreateThread(function()
    GlobalState.nzBays = {}
    while true do
        Wait(60000)
        dropAll(function(shop, c)
            return not Config.Shops[shop] or not NZ.BayClaims(shop) or not GetPlayerName(c.src) or not Core.IsEmployee(c.src, shop)
        end)
    end
end)
