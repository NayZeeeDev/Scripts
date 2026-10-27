--[[
    Record shop (server)

    The shop sells every record in Records (vinyls.lua + /vinylimport). Where the player stands,
    the price, their money and the room in their pockets are all checked here: the UI only asks.

    Price / genre / description: Config.RecordShop.records[item] > the record's own (vinyls.lua, or an
    imported record's data) > Config.RecordShop.defaultPrice. A price of false keeps a record out.
]]
local cfg = Config.RecordShop
if not cfg or cfg.enabled == false then return end

local ACCOUNT = (cfg.currency == 'bank' or cfg.currency == 'item') and cfg.currency or 'cash'
local MONEY_ITEM = cfg.moneyItem or 'money'
local PREVIEW = cfg.preview or {}
local REACH = (cfg.interactDistance or 2.5) + 4.0     -- how far from the shopkeeper a shopper may stand

local sessions = {}      -- src -> { loc = location | nil (admin), admin = bool }
local adminOpen = {}     -- src -> true while an admin's /recordshop is pending
local lastBuy, lastPreview, resolving = {}, {}, {}
local known = {}         -- item -> whether the inventory has it (items don't change while running)

local function now() return GetGameTimer() end

---------------------------------------------------------------- catalogue
local function override(item) return cfg.records and cfg.records[item] or nil end

-- the config override first, then the record's own value
local function field(item, key)
    local o, r = override(item), Records[item]
    if o and o[key] ~= nil then return o[key] end
    if r then return r[key] end
end

-- price for an item, or false when it isn't sold
local function priceOf(item)
    local p = field(item, 'price')
    if p == nil then p = cfg.defaultPrice or 250 end
    if p == false then return false end
    p = math.floor(tonumber(p) or 0)
    return p >= 0 and p or false
end

local function text(v) return type(v) == 'string' and v ~= '' and v or nil end

local function forSale(item)
    if not Records[item] or priceOf(item) == false then return false end
    if known[item] == nil then
        known[item] = Bridge.ItemExists(item) and true or false
        if not known[item] then
            print(('^3[nayzeee-speaker] record shop: "%s" is not an item in your inventory, so it is not sold. Add it (see install/items.md).^7'):format(item))
        end
    end
    return known[item]
end

local SORTS = {
    album  = function(a, b) return a.album:lower() < b.album:lower() end,
    year   = function(a, b)
        if (a.year or 0) ~= (b.year or 0) then return (a.year or 0) > (b.year or 0) end
        return a.album:lower() < b.album:lower()
    end,
    price  = function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        return a.album:lower() < b.album:lower()
    end,
    artist = function(a, b)
        local x, y = a.artist:lower(), b.artist:lower()
        if x ~= y then return x < y end
        return (a.year or 0) < (b.year or 0)
    end,
}

-- printed on the back of the sleeve (2D shop)
local function titlesOf(rec)
    local out = {}
    for i = 1, math.min(#rec.titles, 24) do out[i] = rec.titles[i] end
    return out
end

-- everything on the shelves, plus the items whose cover is still being looked up
local function catalogue()
    local list, missing, seen = {}, {}, {}
    for item, rec in pairs(Records) do
        if forSale(item) then
            local cover = Vinyl.Cover(item)
            if not cover then missing[item] = true end
            local genre = text(field(item, 'genre'))
            list[#list + 1] = {
                item = item, artist = rec.artist ~= '' and rec.artist or 'Various', album = rec.album,
                year = rec.year, tracks = #rec.tracks, cover = cover, titles = titlesOf(rec),
                genre = genre, desc = text(field(item, 'description')), price = priceOf(item),
            }
            if genre then seen[genre] = true end
        end
    end
    table.sort(list, SORTS[cfg.sort or 'artist'] or SORTS.artist)

    -- genre chips: the configured order first, then anything else a record uses
    local genres, used = {}, {}
    for _, g in ipairs(cfg.genres or {}) do
        if seen[g] and not used[g] then genres[#genres + 1], used[g] = g, true end
    end
    local rest = {}
    for g in pairs(seen) do if not used[g] then rest[#rest + 1] = g end end
    table.sort(rest)
    for _, g in ipairs(rest) do genres[#genres + 1] = g end
    return list, genres, missing
end

local function owned(src)
    local names = {}
    for item in pairs(Records) do names[#names + 1] = item end
    return Bridge.CountItems(src, names)
end

local function wallet(src) return Bridge.GetMoney(src, ACCOUNT, MONEY_ITEM) end

-- covers that were still being looked up when the shop opened are sent on as they arrive
local function watchCovers(src, missing)
    if not next(missing) then return end
    CreateThread(function()
        for _ = 1, 20 do
            Wait(1000)
            if not sessions[src] then return end
            local found
            for item in pairs(missing) do
                local rec = Records[item]
                if rec and rec.cover then
                    found = found or {}
                    found[item], missing[item] = rec.cover, nil
                end
            end
            if found then TriggerClientEvent(RES .. ':client:shopCovers', src, found) end
            if not next(missing) then return end
        end
    end)
end

-- look the covers up in the background once, so the shelves are dressed before anyone walks in
CreateThread(function()
    Wait(10000)
    -- a list first: an import while this runs adds records, and pairs() can't take new keys mid-walk
    local items = {}
    for item in pairs(Records) do items[#items + 1] = item end
    for _, item in ipairs(items) do
        local rec = Records[item]
        if rec and not rec.cover and priceOf(item) then
            Vinyl.Cover(item)
            Wait(3000)          -- iTunes allows about 20 lookups a minute
        end
    end
end)

---------------------------------------------------------------- where the shopper is
local function atShop(src, s)
    s = s or sessions[src]
    if not s then return false end
    if s.admin then return true end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - s.loc.coords) <= REACH
end

---------------------------------------------------------------- open / close
-- where = location index, or 'admin' after /recordshop
NZ.RegisterCallback('shop:open', function(src, where)
    local s
    if where == 'admin' then
        if not adminOpen[src] or not Bridge.IsAdmin(src) then return nil, 'no_permission' end
        adminOpen[src] = nil
        s = { admin = true }
    else
        local loc = (cfg.locations or {})[tonumber(where) or 0]
        if not loc or not loc.coords then return nil, 'shop_far' end
        s = { loc = loc }
        if not atShop(src, s) then return nil, 'shop_far' end
    end
    if wallet(src) == nil then
        print('^3[nayzeee-speaker] record shop: no money system found (needs ESX, QBCore, Qbox or ox_inventory cash).^7')
        return nil, 'shop_no_money'
    end
    local items, genres, missing = catalogue()
    if #items == 0 then return nil, 'shop_empty' end
    sessions[src] = s
    watchCovers(src, missing)
    return {
        items = items, genres = genres, owned = owned(src), wallet = wallet(src),
        account = ACCOUNT, title = s.loc and s.loc.label or nil,
    }
end)

RegisterNetEvent(RES .. ':shop:closed', function()
    sessions[source] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    sessions[src], adminOpen[src] = nil, nil
    lastBuy[src], lastPreview[src], resolving[src] = nil, nil, nil
end)

---------------------------------------------------------------- buying
local function fail(reason) return { ok = false, reason = reason } end

NZ.RegisterCallback('shop:buy', function(src, item)
    if type(item) ~= 'string' or not atShop(src) then return fail('shop_far') end
    -- nothing below yields, so two buys can't interleave; the gap just stops double clicks
    local t = now()
    if lastBuy[src] and t - lastBuy[src] < 800 then return fail('shop_busy') end
    lastBuy[src] = t
    if not forSale(item) then return fail('shop_gone') end

    local price = priceOf(item)
    local have = wallet(src)
    if not have then return fail('shop_no_money') end
    if have < price then return fail(ACCOUNT == 'bank' and 'shop_broke_bank' or 'shop_broke') end
    local max = tonumber(cfg.maxCopies) or 0
    if max > 0 and Bridge.CountItem(src, item) >= max then return fail('shop_have') end
    if not Bridge.CanCarry(src, item, 1) then return fail('shop_full') end

    if not Bridge.RemoveMoney(src, ACCOUNT, price, MONEY_ITEM, 'record-shop') then return fail('shop_broke') end
    if not Bridge.AddItem(src, item, 1) then
        Bridge.AddMoney(src, ACCOUNT, price, MONEY_ITEM, 'record-shop-refund')   -- never keep money for nothing
        return fail('shop_full')
    end

    local rec = Records[item]
    Log('Record bought', ('**%s** (%s) bought `%s` — %s - %s for $%d (%s)'):format(
        GetPlayerName(src) or '?', src, item, rec.artist, rec.album, price, ACCOUNT))
    return { ok = true, wallet = wallet(src), owned = owned(src) }
end)

---------------------------------------------------------------- listening
-- the record's first track, resolved the way the turntable plays it (link, then search)
local function firstTrack(rec)
    local t = rec.tracks[1]
    if not t then return nil end
    local track
    if t.url then track = Tracks.FromSaved({ src = 'url', url = t.url })
    elseif t.id then track = Tracks.FromSaved({ id = t.id }) end
    if not track and t.search then
        track = Tracks.FromSaved({ search = t.search })
        if track and track.src == 'yt' and track.id then t.id = track.id end   -- instant next time
    end
    return track
end

NZ.RegisterCallback('shop:preview', function(src, item)
    if PREVIEW.enabled == false then return nil, 'shop_no_preview' end
    if type(item) ~= 'string' or not atShop(src) then return nil, 'shop_far' end
    local rec = Records[item]
    if not rec or not forSale(item) then return nil, 'shop_gone' end
    local t = now()
    if resolving[src] or (lastPreview[src] and t - lastPreview[src] < (PREVIEW.cooldown or 2.0) * 1000) then
        return nil, 'shop_slow'
    end
    lastPreview[src], resolving[src] = t, true
    local ok, track = pcall(firstTrack, rec)      -- searching can take a few seconds
    resolving[src] = nil
    if not ok or not track then return nil, 'shop_preview_fail' end
    return {
        mode = track.mode, src = track.src, id = track.id, url = track.url,
        title = rec.tracks[1].title or track.title, author = rec.artist,
        duration = tonumber(track.duration) or 0, thumb = Vinyl.Cover(item) or track.thumb,
    }
end)

---------------------------------------------------------------- testing
local command = cfg.command == nil and 'recordshop' or cfg.command
if command and command ~= '' then
    RegisterCommand(command, function(src)
        if src == 0 then return print('[speaker] /' .. command .. ' is for players in game') end
        if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
        adminOpen[src] = true
        TriggerClientEvent(RES .. ':client:shopOpen', src, 'admin')
    end, false)
end
