if not NAYZEEE_LOCK_OK then return end

local function ownerKey(ownerOrSrc)
    if type(ownerOrSrc) == 'number' then return GetPlayerName(ownerOrSrc) and Bridge.Owner(ownerOrSrc) or nil end
    return type(ownerOrSrc) == 'string' and ownerOrSrc ~= '' and ownerOrSrc or nil
end

-- Send a player back to character selection
exports('Relog', function(src) return Relog(src, true) end)

-- Is the player still in the selection / creation flow?
exports('InSelection', function(src)
    local s = Sessions[src]
    return s ~= nil and s.stage ~= 'playing'
end)

-- Character id the player is currently playing (nil in the lobby)
exports('GetActiveCharacter', function(src)
    local s = Sessions[src]
    return s and s.stage ~= 'select' and s.active or nil
end)

-- Total slots and where they come from
exports('GetSlots', function(src)
    local owner = Bridge.Owner(src)
    local total, info = Slots.Get(src, owner)
    return total, info
end)

-- Grant extra slots (e.g. from your own store script). Negative removes.
exports('AddSlots', function(ownerOrSrc, amount)
    local owner = ownerKey(ownerOrSrc)
    amount = math.floor(tonumber(amount) or 0)
    if not owner then return false end
    return DB.AddExtra(owner, amount)
end)

-- Set granted extra slots to an exact value
exports('SetSlots', function(ownerOrSrc, extra)
    local owner = ownerKey(ownerOrSrc)
    extra = math.floor(tonumber(extra) or -1)
    if not owner or extra < 0 then return false end
    DB.SetExtra(owner, extra)
    return true
end)

-- Total playtime in seconds for a character id (includes the running session)
exports('GetPlaytime', function(charId)
    local base = tonumber(MySQL.scalar.await('SELECT playtime FROM `multichar_characters` WHERE charid = ?', { charId })) or 0
    for _, s in pairs(Sessions) do
        if s.active == charId and s.loadedAt then base = base + (os.time() - s.loadedAt) end
    end
    return base
end)

-- Nationality / backstory / timestamps saved by this resource
exports('GetCharacterMeta', function(charId)
    return MySQL.single.await('SELECT nationality, backstory, favorite, disabled, created_at, last_played, playtime FROM `multichar_characters` WHERE charid = ?', { charId })
end)

-- Raw lobby prefs { theme, mood, pose, couplePose, weapon, pet, petName } (nil = never picked)
exports('GetCharacterPrefs', function(charId)
    local m = DB.Get(charId)
    return m and Characters.Prefs(m) or nil
end)

-- Squad / couple links for a character (CONTRACT §4.2, skins included)
exports('GetSquad', function(charId) return Squads.Get(charId) end)

-- Accepted couple partner charid (or nil)
exports('GetPartner', function(charId)
    return MySQL.scalar.await([[SELECT IF(sender = ?, target, sender) FROM `multichar_squads`
        WHERE (sender = ? OR target = ?) AND status = 'accepted' AND type = 'couple' LIMIT 1]], { charId, charId, charId })
end)
