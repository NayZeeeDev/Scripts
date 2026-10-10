-- The Wig Vault: one callback that feeds the whole tablet

local lbCache = { at = 0, data = nil }

local LB = { 'snatches', 'defends', 'best_streak', 'earned', 'bounty_earned', 'crafted' }

local function leaderboards()
    if lbCache.data and os.time() - lbCache.at < Config.Vault.LeaderboardCache then return lbCache.data end
    local n = Config.Vault.LeaderboardSize
    local data = {}
    for _, col in ipairs(LB) do
        local rows = DB.Leaderboard(col, n) or {}
        for _, r in ipairs(rows) do
            local _, lv = GetLevel(r.xp)
            r.title = lv.title
            r.online = ById[r.identifier] ~= nil
            r.identifier = nil
        end
        data[col] = rows
    end
    lbCache.at, lbCache.data = os.time(), data
    return data
end

lib.callback.register('nz-wig:vault', function(src)
    local P = GetP(src)
    if not P then return nil end
    local row = P.row
    local lvl, ldata = GetLevel(row.xp)
    local nextL = Config.Levels[lvl + 1]
    local perks = GetPerks(row.xp)

    Social.ExpireBounties()

    local catalog = {}
    for _, c in ipairs(DB.Catalog(P.id) or {}) do catalog[c.style] = { tier = c.tier, times = c.times, first = c.first_at } end
    local entries = Wigs.CatalogEntries(catalog)

    return {
        version = VERSION,
        now = os.time(),
        myModel = Hair.PedModelKey(src),
        me = {
            name = P.name,
            xp = row.xp, level = lvl, title = ldata.title,
            levelXp = ldata.xp, nextXp = nextL and nextL.xp or nil, nextTitle = nextL and nextL.title or nil,
            perks = perks,
            stats = {
                snatches = row.snatches, defends = row.defends, fails = row.fails, snatched = row.snatched,
                streak = row.streak, best_streak = row.best_streak, buzzes = row.buzzes, cuts = row.cuts,
                revenges = row.revenges, wigs_sold = row.wigs_sold, earned = row.earned,
                bounties_claimed = row.bounties_claimed, bounty_earned = row.bounty_earned, best_tier = row.best_tier,
                tackles = row.tackles or 0, ties = row.ties or 0, products = row.products or 0,
                crafted = row.crafted or 0, stolen_back = row.stolen_back or 0,
            },
            cooldownUntil = P.cooldownUntil or 0,
            glueUntil = row.glue_until or 0,
            passive = IsPassive(P),
            newUntil = IsNewPlayer(P) and (row.first_seen + Config.Protection.NewPlayerHours * 3600) or 0,
            bountyOnMe = Social.BountyOn(P.id),
            hair = Hair.State(P),
            kits = Inv.Count(src, Config.Items.Kit),
        },
        wigs = Wigs.List(src, perks.sell),
        catalog = catalog,
        catalogRewards = Config.CatalogRewards,
        catalogClaimed = row.catalog_rewards or 0,
        styles = entries,
        bounties = Social.Board(),
        revenge = Social.RevengeList(P),
        leaderboards = leaderboards(),
        feed = Social.Feed(),
        market = Market.Snapshot(),
        levels = Config.Levels,
        bountyCfg = { enabled = Config.Bounty.Enabled, min = Config.Bounty.Min, max = Config.Bounty.Max, fee = Config.Bounty.Fee, onlyRevenge = Config.Bounty.OnlyRevenge },
        trading = Config.Trading.Enabled,
        putOn = Config.Wig.PutOnOthers,
        hasMeta = Inv.HasMeta,
        appName = Config.Phone.Enabled and Config.Phone.AppName or nil,
    }
end)

-- players close enough to trade with / put a wig on
lib.callback.register('nz-wig:nearby', function(src, range)
    local ped = GetPlayerPed(src)
    if ped == 0 then return {} end
    range = math.min(tonumber(range) or Config.Trading.Range, Config.Trading.Range)
    local out = {}
    for _, s in ipairs(PlayersNear(GetEntityCoords(ped), range, src)) do
        local P = Players[s]
        if P then out[#out + 1] = { src = s, name = P.name, dist = math.floor(PedDistance(src, s) * 10) / 10, model = Hair.PedModelKey(s) } end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end)
