-- Squad ranks: renameable, reorderable, each with its own permissions.
-- Rank 1 is the lowest; the highest index is the owner and always holds every permission.
Ranks = {}

Ranks.Perms = {}
for i = 1, #Config.RankPermOrder do Ranks.Perms[i] = Config.RankPermOrder[i].key end

function Ranks.Default()
    local out = {}
    for i = 1, #Config.DefaultRanks do
        local r = Config.DefaultRanks[i]
        local perms = {}
        for k, v in pairs(r.perms) do perms[k] = v end
        out[i] = { name = r.name, icon = r.icon, perms = perms }
    end
    return out
end

function Ranks.Owner(sq) return #sq.ranks end

function Ranks.Name(sq, level)
    local r = sq.ranks[level]
    return r and r.name or 'Member'
end

function Ranks.Icon(sq, level)
    local r = sq.ranks[level]
    return r and r.icon or 'fa-user'
end

--- The owner rank always passes.
function Ranks.Can(sq, level, perm)
    if not level then return false end
    if level >= #sq.ranks then return true end
    local r = sq.ranks[level]
    return (r and r.perms and r.perms[perm]) == true
end

function Ranks.Clamp(sq, level)
    level = tonumber(level) or 1
    if level < 1 then return 1 end
    if level > #sq.ranks then return #sq.ranks end
    return math.floor(level)
end

--- Validates a rank list coming from the UI. Returns ok, cleanList|error.
function Ranks.Validate(list)
    if type(list) ~= 'table' then return false, 'Invalid ranks' end
    local n = #list
    if n < 2 then return false, 'Keep at least two ranks' end
    if n > Config.MaxRanks then return false, ('You can have at most %d ranks'):format(Config.MaxRanks) end

    local seen, out = {}, {}
    for i = 1, n do
        local r = list[i]
        if type(r) ~= 'table' or type(r.name) ~= 'string' then return false, 'Every rank needs a name' end

        local name = r.name:gsub('^%s+', ''):gsub('%s+$', '')
        if #name < 2 or #name > 18 then return false, 'Rank names are 2 to 18 characters' end
        if not name:match("^[%w%s%-_'%.]+$") then return false, 'Rank names use letters, numbers and - _ . only' end

        local low = name:lower()
        if seen[low] then return false, 'Two ranks cannot share a name' end
        seen[low] = true

        local perms = {}
        if type(r.perms) == 'table' then
            for j = 1, #Ranks.Perms do
                local p = Ranks.Perms[j]
                if r.perms[p] == true then perms[p] = true end
            end
        end

        local icon = 'fa-user'
        if type(r.icon) == 'string' then
            for j = 1, #Config.RankIcons do
                if Config.RankIcons[j] == r.icon then icon = r.icon break end
            end
        end
        out[i] = { name = name, icon = icon, perms = perms }
    end
    return true, out
end
