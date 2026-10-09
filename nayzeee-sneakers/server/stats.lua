--[[
    Per-character stats and reputation, the daily hype board, and Discord logs.

    Other scripts:
        exports['nayzeee-sneakers']:GetRep(src)
        exports['nayzeee-sneakers']:AddRep(src, amount)
        exports['nayzeee-sneakers']:GetStats(src)   -- { rep, sold, earned, caught, fakesSold, made, cleaned }
]]

Stats = {}

local function key(id) return 'stats:' .. id end
local BLANK = { rep = 0, sold = 0, earned = 0, caught = 0, fakesSold = 0, made = 0, cleaned = 0 }

local function load(id)
    local s = json.decode(GetResourceKvpString(key(id)) or '{}') or {}
    for k, v in pairs(BLANK) do if s[k] == nil then s[k] = v end end
    return s
end

function Stats.Get(src)
    local id = Bridge.GetIdentifier(src)
    return id and load(id) or load('')
end

--- Add to any number of stats at once: Stats.Add(src, { sold = 1, earned = 450 })
function Stats.Add(src, changes)
    local id = Bridge.GetIdentifier(src)
    if not id then return end
    local s = load(id)
    for k, v in pairs(changes) do
        s[k] = (s[k] or 0) + v
        if k == 'rep' then s.rep = math.max(0, math.min(Config.Rep.Max, s.rep)) end
    end
    SetResourceKvp(key(id), json.encode(s))
    return s
end

function Stats.Rep(src) return Stats.Get(src).rep end

exports('GetRep', Stats.Rep)
exports('AddRep', function(src, amount) local s = Stats.Add(src, { rep = tonumber(amount) or 0 }) return s and s.rep end)
exports('GetStats', Stats.Get)

-- /sneakerrep [id] [amount]
RegisterCommand(Config.Commands.rep, function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    local amount = tonumber(args[2])
    local s = amount and Stats.Add(target, { rep = amount })
    local rep = s and s.rep or Stats.Rep(target)
    local msg = ('Player %d has %d rep'):format(target, rep)
    if src == 0 then print(msg) else Bridge.Notify(src, msg, 'inform') end
end, false)

--------------------------------------------------------------------------------
-- Hype: a demand multiplier per shoe model that rerolls every Config.Hype.Hours
--------------------------------------------------------------------------------

Hype = {}
local H = Config.Hype
local board

local function reroll()
    board = { at = os.time(), mult = {} }
    for id, m in pairs(Config.ShoeModels) do
        if not m.hidden then
            board.mult[id] = math.floor((H.Range[1] + math.random() * (H.Range[2] - H.Range[1])) * 100 + 0.5) / 100
        end
    end
    SetResourceKvp('hype', json.encode(board))
end

function Hype.Get(modelId)
    if not H.Enabled then return 1.0 end
    if not board then
        local raw = GetResourceKvpString('hype')
        board = raw and json.decode(raw) or nil
    end
    if not board or os.time() - (board.at or 0) > H.Hours * 3600 then reroll() end
    return board.mult[modelId] or 1.0
end

--- { { model, label, mult, image }, ... } hottest first
function Hype.Board()
    local out = {}
    for id, m in pairs(Config.ShoeModels) do
        if not m.hidden then
            local first
            for letter in pairs(m.colourways) do if not first or letter < first then first = letter end end
            out[#out + 1] = { model = id, label = m.label, mult = Hype.Get(id), image = ('nzs_%s_%s'):format(id, first or 'a') }
        end
    end
    table.sort(out, function(a, b) return a.mult > b.mult end)
    return out
end

--------------------------------------------------------------------------------
-- Discord logs   Config.Logs
--------------------------------------------------------------------------------

Logs = {}

--- fields = { { 'Name', 'value' }, ... }
function Logs.Send(title, fields, color)
    local L = Config.Logs
    if not L.Webhook or L.Webhook == '' then return end
    local list = {}
    for _, f in ipairs(fields or {}) do list[#list + 1] = { name = f[1], value = tostring(f[2]), inline = true } end
    PerformHttpRequest(L.Webhook, function() end, 'POST', json.encode({
        username = L.Name,
        embeds = { { title = title, color = color or L.Color, fields = list, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end

--- "Name (id)" for logs
function Logs.Who(src)
    return ('%s (%d)'):format(Bridge.GetName(src), src)
end
