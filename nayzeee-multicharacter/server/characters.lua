if not NAYZEEE_LOCK_OK then return end

--[[
    Character list for the lobby (CONTRACT §4.1): framework rows + our meta/prefs + resolved weapon + resolved pet.
    prefs.theme / prefs.mood are always concrete ids (saved -> job auto theme -> default), the rest stay raw.
]]

Characters = {}

local S = Config.Scene

-- ── theme / mood resolution ───────────────────────────────────────────────
function Characters.Theme(saved, jobName)
    if saved and S.playerPick and NZ.Theme(saved) then return saved end
    local auto = jobName and S.autoByJob and S.autoByJob[jobName]
    if auto and NZ.Theme(auto) then return auto end
    if NZ.Theme(S.defaultTheme) then return S.defaultTheme end
    return NZ.ThemeIds()[1]
end

function Characters.MoodAllowed(themeId, mood)
    if not NZ.MoodById(mood) then return false end
    local th = NZ.Theme(themeId)
    if th and th.moods then
        for _, id in ipairs(th.moods) do if id == mood then return true end end
        return false
    end
    return true
end

function Characters.Mood(themeId, saved)
    if saved and S.playerPick and Characters.MoodAllowed(themeId, saved) then return saved end
    local th = NZ.Theme(themeId)
    if th and th.mood and NZ.MoodById(th.mood) then return th.mood end
    return Config.Moods[1] and Config.Moods[1].id
end

-- ── helpers ───────────────────────────────────────────────────────────────
local function ageOf(iso)
    local y, m, d = (iso or ''):match('^(%d+)-(%d+)-(%d+)')
    if not y then return nil end
    return Validate.Age(tonumber(y), tonumber(m), tonumber(d))
end

local function valid(fn, id) return (id and fn(id)) and id or nil end

-- Raw prefs from a meta row (ids that no longer exist in config are dropped)
function Characters.Prefs(m)
    m = m or {}
    return {
        theme      = m.theme,
        mood       = m.mood,
        pose       = valid(NZ.PoseById, m.pose),
        couplePose = valid(NZ.CoupleById, m.couple_pose),
        weapon     = m.weapon,
        pet        = valid(NZ.PetById, m.pet),
        petName    = m.pet_name,
    }
end

function Characters.Name(c) return c and ((c.firstname or '') .. ' ' .. (c.lastname or '')) or '?' end

-- Resolved pet for a character (or nil)
local function resolvePet(prefs, allowed)
    if not Config.Pets.enabled or not prefs.pet then return nil end
    local ok = false
    for _, id in ipairs(allowed) do if id == prefs.pet then ok = true break end end
    if not ok then return nil end
    local p = NZ.PetById(prefs.pet)
    local name = Config.Pets.names and prefs.petName or nil
    return { id = p.id, model = p.model, name = name or p.label }
end

-- c = normalised framework character, m = multichar_characters row, src = owner (ace pets), total = unlocked slots
function Characters.Build(c, m, src, total)
    m = m or {}
    local prefs = Characters.Prefs(m)
    prefs.theme = Characters.Theme(m.theme, c.job and c.job.name)
    prefs.mood = Characters.Mood(prefs.theme, m.mood)

    local pets = PetBridge.Allowed(src, c.id)
    return {
        id          = c.id,
        slot        = c.slot,
        firstname   = c.firstname,
        lastname    = c.lastname,
        name        = Characters.Name(c),
        dob         = c.dob,
        age         = ageOf(c.dob),
        gender      = c.gender,
        nationality = m.nationality or c.nationality,
        height      = c.height,
        backstory   = m.backstory,
        phone       = c.phone,
        job         = c.job,
        cash        = c.cash,
        bank        = c.bank,
        lastPlayed  = tonumber(m.last_played),
        playtime    = tonumber(m.playtime) or 0,
        createdAt   = tonumber(m.created_at),
        favorite    = NZ.Truthy(m.favorite),
        disabled    = NZ.Truthy(m.disabled),
        locked      = (c.slot or 1) > (total or 0),
        model       = c.model,
        skin        = c.skin,
        prefs       = prefs,
        weapon      = Weapons.Resolve(c.id, prefs.weapon, c.raw),
        weapons     = Weapons.List(c.id, c.raw),
        pet         = resolvePet(prefs, pets),
        pets        = pets,
    }
end

-- Build the lobby list for a player. Returns list (sorted by slot), raw map[id] = normalised framework char
function Characters.List(src, owner, total)
    local rows = Bridge.Fetch(src, owner)
    local ids, raw = {}, {}
    for i = 1, #rows do
        ids[#ids + 1] = rows[i].id
        raw[rows[i].id] = rows[i]
    end
    local meta = DB.Prefs(ids)

    local out = {}
    for i = 1, #rows do
        local c = rows[i]
        local m = meta[c.id]
        if not m then
            DB.Ensure(c.id, owner)
            m = {}
        end
        out[#out + 1] = Characters.Build(c, m, src, total)
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out, raw
end

-- Owner of a character id from our table (admin commands / exports)
function Characters.OwnerOf(charId)
    return MySQL.scalar.await('SELECT owner FROM `multichar_characters` WHERE charid = ?', { charId })
end
