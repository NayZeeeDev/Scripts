if not NAYZEEE_LOCK_OK then return end

Characters = {}

-- Build the character list for a player: framework rows + our meta + custom fields + partner previews
function Characters.List(src, owner, total)
    local list = Bridge.Fetch(src, owner)
    local ids = {}
    for i = 1, #list do ids[#ids + 1] = list[i].id end
    local meta = DB.Meta(ids)

    -- partner previews need the partner's own framework row
    local partnerIds, partnerMap = {}, {}
    for _, m in pairs(meta) do
        if m.partner then partnerIds[#partnerIds + 1] = m.partner end
    end
    if #partnerIds > 0 then
        for _, p in ipairs(Characters.FetchByIds(partnerIds)) do partnerMap[p.id] = p end
    end

    local out = {}
    for i = 1, #list do
        local c = list[i]
        local m = meta[c.id]
        if not m then
            DB.Ensure(c.id, owner)
            m = {}
        end
        local partner
        if m.partner and partnerMap[m.partner] then
            local p = partnerMap[m.partner]
            partner = { id = p.id, name = p.firstname .. ' ' .. p.lastname, type = m.partner_type or 'friend', skin = p.skin, model = p.model, gender = p.gender }
        end

        local custom = {}
        for _, f in ipairs(Config.Characters.custom or {}) do
            local ok, v = pcall(f.fn, c)
            if ok and v ~= nil then custom[#custom + 1] = { label = f.label, icon = f.icon, value = tostring(v) } end
        end

        out[#out + 1] = {
            id          = c.id,
            slot        = c.slot,
            firstname   = c.firstname,
            lastname    = c.lastname,
            dob         = c.dob,
            gender      = c.gender,
            height      = tonumber(m.height) or c.height,
            nationality = m.nationality or c.nationality,
            job         = c.job,
            jobLabel    = c.jobLabel,
            gradeLabel  = c.gradeLabel,
            cash        = c.cash,
            bank        = c.bank,
            phone       = c.phone,
            playtime    = tonumber(m.playtime) or 0,
            lastPlayed  = tonumber(m.last_played),
            createdAt   = tonumber(m.created_at),
            backstory   = m.backstory,
            pose        = m.pose,
            favorite    = NZ.Truthy(m.favorite),
            disabled    = NZ.Truthy(m.disabled),
            locked      = c.slot > total,
            partner     = partner,
            custom      = custom,
            skin        = c.skin,
            model       = c.model,
            hasPosition = c.position ~= nil,
        }
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out, list
end

-- Minimal fetch by id (used for partner previews). Works on both frameworks.
function Characters.FetchByIds(ids)
    local out = {}
    if #ids == 0 then return out end
    local q = ('?,'):rep(#ids):sub(1, -2)
    if NZ.IsESX then
        local rows = MySQL.query.await(('SELECT identifier, firstname, lastname, sex, skin FROM users WHERE identifier IN (%s)'):format(q), ids) or {}
        for _, r in ipairs(rows) do
            local g = (r.sex == 'f' or r.sex == 'F') and 'f' or 'm'
            local skin = NZ.Decode(r.skin)
            out[#out + 1] = { id = r.identifier, firstname = r.firstname or '', lastname = r.lastname or '', gender = g, skin = skin, model = Bridge.SkinModel(skin, g) }
        end
    else
        local rows = MySQL.query.await(('SELECT citizenid, charinfo FROM players WHERE citizenid IN (%s)'):format(q), ids) or {}
        local skins = {}
        if Bridge.TableExists('playerskins', 'citizenid') then
            for _, s in ipairs(MySQL.query.await(('SELECT citizenid, model, skin FROM playerskins WHERE active = 1 AND citizenid IN (%s)'):format(q), ids) or {}) do
                skins[s.citizenid] = s
            end
        end
        for _, r in ipairs(rows) do
            local ci = NZ.Decode(r.charinfo) or {}
            local g = (ci.gender == 1 or ci.gender == '1') and 'f' or 'm'
            local s = skins[r.citizenid]
            local skin = s and NZ.Decode(s.skin)
            if skin and s.model and not skin.model then skin.model = tonumber(s.model) or s.model end
            out[#out + 1] = { id = r.citizenid, firstname = ci.firstname or '', lastname = ci.lastname or '', gender = g, skin = skin, model = (s and s.model) or Bridge.SkinModel(skin, g) }
        end
    end
    return out
end

-- Owner of a character id straight from the database (for admin commands)
function Characters.OwnerOf(charId)
    return MySQL.scalar.await('SELECT owner FROM nayzeee_multichar WHERE charid = ?', { charId })
end
