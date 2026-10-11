if not NAYZEEE_LOCK_OK then return end

-- Send a player back to character selection
exports('Relog', function(src) return Relog(src, true) end)

-- Is the player still in the selection / creation flow?
exports('InSelection', function(src)
    local s = Sessions[src]
    return s ~= nil and s.stage ~= 'playing'
end)

-- Total slots and where they come from
exports('GetSlots', function(src)
    local owner = Bridge.Owner(src)
    local total, info = Slots.Get(src, owner)
    return total, info
end)

-- Grant extra slots (e.g. from your own store script)
exports('AddSlots', function(ownerOrSrc, amount)
    local owner = type(ownerOrSrc) == 'number' and Bridge.Owner(ownerOrSrc) or ownerOrSrc
    if not owner then return false end
    DB.SetExtra(owner, math.max(0, DB.Extra(owner) + math.floor(amount)), 'export')
    return true
end)

-- Total playtime in seconds for a character id (includes the running session)
exports('GetPlaytime', function(charId)
    local base = tonumber(MySQL.scalar.await('SELECT playtime FROM nayzeee_multichar WHERE charid = ?', { charId })) or 0
    for _, s in pairs(Sessions) do
        if s.active == charId and s.loadedAt then base = base + (os.time() - s.loadedAt) end
    end
    return base
end)

-- Backstory / nationality / height saved by this resource
exports('GetCharacterMeta', function(charId)
    return MySQL.single.await('SELECT nationality, height, backstory, pose, created_at, last_played, playtime FROM nayzeee_multichar WHERE charid = ?', { charId })
end)
