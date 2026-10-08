-----------------------------------------------------------------
-- Crew radio: while a warehouse has a contract or sale running,
-- its crew sits on a private voice channel (Base + warehouse id).
-----------------------------------------------------------------
Radio = {}
local R = Config.Radio

local active = {}    -- [wid] = { jobs = n, members = { [src] = true } }

local function channelOf(wid) return R.Base + wid end

local function enabledFor(w)
    if not R.Enabled or not w then return false end
    return Server.Prefs(w).radio ~= false
end

-- Who goes on the channel for this job
local function crewFor(w, runner)
    if R.Who == 'runner' then return { runner } end
    local ids = { [w.owner] = true }
    for _, a in ipairs(w.associates) do ids[a.identifier] = true end
    local origin = R.Who == 'nearby' and GetEntityCoords(GetPlayerPed(runner)) or nil
    local out = {}
    for src, st in pairs(Server.Players) do
        if st.identifier and ids[st.identifier] and GetPlayerPing(src) > 0 then
            local ok = src == runner or not origin or #(GetEntityCoords(GetPlayerPed(src)) - origin) <= R.Range
            if ok then out[#out + 1] = src end
        end
    end
    return out
end

local function join(src, wid)
    local ch = channelOf(wid)
    local handled = Bridge.RadioServer(src, ch, true)
    TriggerClientEvent('nz_cargo:radio', src, { join = true, channel = ch, display = handled })
end

local function leave(src, wid)
    local ch = channelOf(wid)
    local handled = Bridge.RadioServer(src, ch, false)
    TriggerClientEvent('nz_cargo:radio', src, { join = false, channel = ch, display = handled })
end

function Radio.Start(m)
    local w = m and m.wid and DB.Warehouses[m.wid]
    if not enabledFor(w) then return end
    local a = active[w.id]
    if not a then a = { jobs = 0, members = {} } active[w.id] = a end
    a.jobs = a.jobs + 1
    m.radio = w.id
    for _, src in ipairs(crewFor(w, m.src)) do
        if not a.members[src] then
            a.members[src] = true
            join(src, w.id)
        end
    end
end

function Radio.Stop(m)
    local wid = m and m.radio
    local a = wid and active[wid]
    m.radio = nil
    if not a then return end
    a.jobs = a.jobs - 1
    if a.jobs > 0 then return end
    for src in pairs(a.members) do
        if GetPlayerPing(src) > 0 then leave(src, wid) end
    end
    active[wid] = nil
end

AddEventHandler('playerDropped', function()
    local src = source
    for _, a in pairs(active) do a.members[src] = nil end
end)
