--[[
    NAYZEEE RADIO - Routing (server): transmissions, listeners, signal quality, leak

    Decides who hears a talker, how (reception mode) and how well (quality q). The client
    only says "I am keying up on this device"; the frequency comes from the server record
    or the vehicle's head unit state, and every listener, mode and q is worked out here
    from server-side positions (OneSync).

    LISTENERS of a talker on fkey (one record per listener, best mode wins: radio > car > leak,
    the better q inside a mode)
      radio  powered radios with fkey in a slot (not the talker; muted ones only for an emergency)
      car    everyone inside a vehicle whose head unit is on and tuned to fkey (not muted,
             not the talker's own vehicle)
      leak   players within Config.Leak.vehicle of such a vehicle (src = its net id), and
             players within Config.Leak.handheld of a 'radio' listener who has no earpiece in
             (src = that listener's server id)
    q comes from NZR.Signal.Quality with both sides' model, range, jam resistance and water
    state (a vehicle side uses Config.Vehicles.range x its range multiplier). Listeners below
    Config.Signal.tiers.poor still get 'nzr:rx:start' (they hear the carrier breaking up)
    but are not voice targets.

    A transmission stays up while something holds it: ptt (nzr:tx:start → nzr:tx:stop),
    handsfree (nzr:radio:handsfree) or an emergency hot mic (Config.Emergency.hotMic s).
    While any transmission is live the coords cache is refreshed and every talker is
    re-resolved each Config.Signal.refresh ms.

    TRANSMISSION (NZR.Routing.active[src], also rec.tx)
      { fkey, slot, device = 'handheld' | 'vehicle', veh, vnet, since, name, callsign,
        ptt, handsfree, emergency, forcedUntil, targets = { [id] = true }, listeners = { [id] = info } }

    API
      NZR.Routing.Start(src, device, opts?)  → ok, reason   opts = { ptt, handsfree, emergency,
                                               duration (ms, emergency), silent (no tx:denied) }
      NZR.Routing.Release(src, holder)       holder = 'ptt' | 'handsfree' | 'emergency'; stops when nothing holds it
      NZR.Routing.Stop(src, why?)            end it now (why = 'drop' sends nothing to the talker)
      NZR.Routing.Update(src)                re-check and re-resolve one talker now
      NZR.Routing.Touch(fkey|nil)            Update every talker on fkey (nil = all)
      NZR.Routing.Get(src) → transmission | nil      NZR.Routing.IsTalking(src) → bool
      NZR.Routing.Listeners(src) → { [id] = info }   NZR.Routing.Resolve(src, tx) → listeners
      NZR.Routing.RefreshCoords(force?)      → { [id] = { pos, ped, veh } }  (≤ 200 ms old unless forced)
      NZR.Routing.SideOf(id)                 → NZR.Signal side of a player's handheld
      NZR.Routing.TalkerSide(src, tx)        → side of a live transmission
      NZR.Routing.VehicleOf(src)             → veh, vnet, nzr_vradio | nil   (operating seat, head unit on and tuned)

    Events handled (C→S)
      nzr:tx:start (device)   nzr:tx:stop ()
    Events sent (S→C)
      nzr:tx:targets (ids)            talker: full voice target list, on start and on change
                                      (an empty list when the server ends the transmission)
      nzr:tx:denied (reason)          talker: 'nosignal' | 'nofreq' | 'cooldown'
      nzr:rx:start (talker, info)     info = { fkey, slot, mode, q, srcType, src, name, callsign, emergency }
      nzr:rx:update (talker, info)    mode / source / emergency changed or |Δq| > 0.05
      nzr:rx:stop (talker, q)         q = the last quality (sizes the squelch tail)
    Bus (emitted): radio:talking (src, fkey, on)
    Bus (listens): radio:joined / radio:left (src, fkey) (power on / off arrives as these),
                   radio:changed (src), vehicles:changed (fkeyOld, fkeyNew), jammers:changed (),
                   player:dropped (src)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Routing = NZR.Routing or {}
local RT = NZR.Routing
local Core = NZR.Core
local Sig = NZR.Signal

RT.active = RT.active or {}
RT.coords = RT.coords or {}

local MODE_RANK = { radio = 3, car = 2, leak = 1 }
local DQ = 0.05                 -- quality change that is worth an rx:update
local COORDS_MAX_AGE = 200      -- ms a coords cache is good for outside the refresh loop
local coordsAt = -100000

local function tiers()
    return (Config.Signal and Config.Signal.tiers) or { clear = 0.75, weak = 0.45, poor = 0.15 }
end

local function round3(n)
    return math.floor(n * 1000 + 0.5) / 1000
end

-- ════════════════════════════════════════════════════════════════════════
-- COORDS CACHE (server-side positions, once per tick for everyone)
-- ════════════════════════════════════════════════════════════════════════

function RT.RefreshCoords(force)
    local now = GetGameTimer()
    if not force and now - coordsAt < COORDS_MAX_AGE then return RT.coords end
    coordsAt = now
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local ped = id and GetPlayerPed(id)
        if ped and ped ~= 0 then
            local veh = GetVehiclePedIsIn(ped, false)
            out[id] = { pos = GetEntityCoords(ped), ped = ped, veh = (veh and veh ~= 0) and veh or nil }
        end
    end
    RT.coords = out
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- SIDES (one end of a link for NZR.Signal.Quality)
-- ════════════════════════════════════════════════════════════════════════

function RT.SideOf(id)
    local rec = NZR.Radio.players[id]
    local c = RT.coords[id]
    return Sig.Side((rec and rec.model) or 'handheld', c and c.pos, { underwater = rec and rec.underwater })
end

-- A car aerial is not affected by the driver's swim, and it is not jam resistant.
local function vehicleSide(veh, pos)
    return Sig.Side('vehicle', pos, { rangeMult = NZR.Vehicles.RangeMult(veh), resist = 0.0, waterproof = true })
end

function RT.TalkerSide(src, tx)
    if tx.device == 'vehicle' then
        local pos = (tx.veh and DoesEntityExist(tx.veh)) and GetEntityCoords(tx.veh) or (RT.coords[src] and RT.coords[src].pos)
        return vehicleSide(tx.veh, pos)
    end
    return RT.SideOf(src)
end

-- ════════════════════════════════════════════════════════════════════════
-- VEHICLE DEVICE
-- ════════════════════════════════════════════════════════════════════════

function RT.VehicleOf(src)
    if not (Config.Vehicles and Config.Vehicles.enabled ~= false) then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if not NZR.Vehicles.Seated(src, veh) then return nil end
    local st = NZR.Vehicles.State(veh)
    if type(st) ~= 'table' or not st.on or not NZR.Freq.Key(st.f) then return nil end
    return veh, NetworkGetNetworkIdFromEntity(veh), st
end

-- ════════════════════════════════════════════════════════════════════════
-- LISTENER RESOLUTION
-- ════════════════════════════════════════════════════════════════════════

local function better(cur, mode, q)
    if not cur then return true end
    local a, b = MODE_RANK[mode], MODE_RANK[cur.mode]
    if a ~= b then return a > b end
    return q > cur.q
end

function RT.Resolve(src, tx)
    local coords = RT.coords
    local jammers = NZR.Jammers and NZR.Jammers.List() or nil
    local talker = RT.TalkerSide(src, tx)
    local out = {}

    local function offer(id, mode, q, slot, srcType, srcId)
        if id == src or not coords[id] then return end
        if better(out[id], mode, q) then
            out[id] = { mode = mode, q = q, slot = slot, srcType = srcType, src = srcId }
        end
    end

    -- radios tuned to the channel
    local radios = {}
    for id, slot in pairs(NZR.Radio.members[tx.fkey] or {}) do
        local rec = NZR.Radio.players[id]
        if id ~= src and rec and rec.power and coords[id] and (not rec.muted or tx.emergency) then
            local q = Sig.Quality(talker, RT.SideOf(id), jammers)
            offer(id, 'radio', q, slot)
            radios[#radios + 1] = { id = id, q = q, earpiece = rec.earpiece == true }
        end
    end

    -- radio cars tuned to the channel: occupants hear the head unit, people around the outside speaker
    local leakCfg = Config.Leak or {}
    local carLeak = tonumber(leakCfg.vehicle) or 0.0
    local ownVeh = coords[src] and coords[src].veh
    for veh, entry in pairs(NZR.Vehicles.Tuned(tx.fkey)) do
        if veh ~= ownVeh and veh ~= tx.veh and (not entry.state.mute or tx.emergency) then
            local vpos = GetEntityCoords(veh)
            local q = Sig.Quality(talker, vehicleSide(veh, vpos), jammers)
            for id, c in pairs(coords) do
                if c.veh == veh then
                    offer(id, 'car', q)
                elseif carLeak > 0.0 and Sig.Distance(c.pos, vpos) <= carLeak then
                    offer(id, 'leak', q, nil, 'vehicle', entry.vnet)
                end
            end
        end
    end

    -- handhelds without an earpiece are heard by whoever stands next to them
    local handLeak = tonumber(leakCfg.handheld) or 0.0
    if handLeak > 0.0 then
        for _, r in ipairs(radios) do
            if not r.earpiece then
                local p = coords[r.id].pos
                for id, c in pairs(coords) do
                    if id ~= r.id and Sig.Distance(c.pos, p) <= handLeak then
                        offer(id, 'leak', r.q, nil, 'player', r.id)
                    end
                end
            end
        end
    end

    for _, info in pairs(out) do
        info.fkey = tx.fkey
        info.q = round3(info.q)
        info.name = tx.name
        info.callsign = tx.callsign
        info.emergency = tx.emergency == true
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- APPLY (diff against what the clients were told)
-- ════════════════════════════════════════════════════════════════════════

local function apply(src, tx, fresh)
    local old = tx.listeners
    for id, info in pairs(fresh) do
        local prev = old[id]
        if not prev then
            TriggerClientEvent('nzr:rx:start', id, src, info)
        elseif prev.mode ~= info.mode or prev.src ~= info.src or prev.slot ~= info.slot
            or prev.emergency ~= info.emergency or prev.callsign ~= info.callsign
            or math.abs(prev.q - info.q) > DQ then
            TriggerClientEvent('nzr:rx:update', id, src, info)
        else
            -- keep the q the client knows, so a slow drift still crosses DQ at some point
            fresh[id] = prev
        end
    end
    for id, prev in pairs(old) do
        if not fresh[id] then TriggerClientEvent('nzr:rx:stop', id, src, prev.q) end
    end
    tx.listeners = fresh

    local poor = tiers().poor or 0.15
    local targets, list, changed = {}, {}, tx.first == true
    for id, info in pairs(fresh) do
        if info.q >= poor then
            targets[id] = true
            list[#list + 1] = id
            if not tx.targets[id] then changed = true end
        end
    end
    if not changed then
        for id in pairs(tx.targets) do
            if not targets[id] then
                changed = true
                break
            end
        end
    end
    tx.targets = targets
    tx.first = nil
    if changed then
        table.sort(list)
        TriggerClientEvent('nzr:tx:targets', src, list)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- START / RELEASE / STOP
-- ════════════════════════════════════════════════════════════════════════

local function deny(src, reason, opts)
    if not (opts and opts.silent) then TriggerClientEvent('nzr:tx:denied', src, reason) end
    return false, reason
end

local function talkerJam(src, device, rec)
    local c = RT.coords[src]
    if not c then return 0.0 end
    local resist = 0.0
    if device ~= 'vehicle' and rec and rec.model then
        local m = Config.Radios.Models[rec.model]
        resist = m and m.jamResist or 0.0
    end
    return Sig.Jam(c.pos, NZR.Jammers and NZR.Jammers.List() or nil, resist)
end

local function blockJam()
    return tonumber(Config.Signal and Config.Signal.txBlockJam) or 0.92
end

-- Where would this talker transmit right now? → fkey, slot, veh, vnet | nil
local function txSource(src, device, rec)
    if device == 'vehicle' then
        local veh, vnet, st = RT.VehicleOf(src)
        if not veh then return nil end
        return NZR.Freq.Key(st.f), nil, veh, vnet
    end
    if not rec or not rec.power or not rec.model then return nil end
    local f = rec.slots[rec.txSlot]
    if not f then return nil end
    return NZR.Freq.Key(f), rec.txSlot
end

function RT.Start(src, device, opts)
    opts = opts or {}
    src = tonumber(src)
    if not src or not Core.Online(src) then return false, 'nofreq' end
    if device ~= 'vehicle' then device = 'handheld' end
    RT.RefreshCoords()

    local rec = NZR.Radio.players[src]
    local fkey, slot, veh, vnet = txSource(src, device, rec)
    if not fkey then return deny(src, 'nofreq', opts) end

    local tx = RT.active[src]
    if tx and (tx.fkey ~= fkey or tx.device ~= device) then
        RT.Stop(src, 'switch')
        tx = nil
    end

    -- an emergency always keys up; the jam still shows in every listener's q
    if not opts.emergency and not tx and talkerJam(src, device, rec) >= blockJam() then
        return deny(src, 'nosignal', opts)
    end

    local now = GetGameTimer()
    local duration = math.max(0, tonumber(opts.duration) or 0)

    if tx then
        if opts.handsfree then tx.handsfree = true end
        if opts.emergency then
            tx.emergency = true
            tx.forcedUntil = now + duration
            RT.Update(src)
        end
        if not opts.handsfree and not opts.emergency then tx.ptt = true end
        return true
    end

    tx = {
        fkey = fkey, slot = slot, device = device, veh = veh, vnet = vnet, since = now,
        name = (rec and rec.name) or Core.Name(src), callsign = rec and rec.callsign or nil,
        ptt = not opts.handsfree and not opts.emergency,
        handsfree = opts.handsfree == true,
        emergency = opts.emergency == true,
        forcedUntil = opts.emergency and (now + duration) or nil,
        targets = {}, listeners = {}, first = true,
    }
    RT.active[src] = tx
    if rec then rec.tx = tx end
    apply(src, tx, RT.Resolve(src, tx))
    NZR.Bus.Emit('radio:talking', src, fkey, true)
    if opts.emergency and rec then NZR.Radio.Push(src) end
    return true
end

function RT.Stop(src, why)
    local tx = RT.active[src]
    if not tx then return false end
    RT.active[src] = nil
    local rec = NZR.Radio.players[src]
    if rec and rec.tx == tx then rec.tx = nil end
    if rec and tx.handsfree then rec.handsfree = false end

    for id, info in pairs(tx.listeners) do
        TriggerClientEvent('nzr:rx:stop', id, src, info.q)
    end
    if why ~= 'drop' then
        TriggerClientEvent('nzr:tx:targets', src, {})
        if why == 'nosignal' then TriggerClientEvent('nzr:tx:denied', src, 'nosignal') end
    end
    NZR.Bus.Emit('radio:talking', src, tx.fkey, false)
    -- the client asked for this one and knows; anything else is news to it
    if rec and why ~= 'drop' and why ~= 'release' then NZR.Radio.Push(src) end
    return true
end

function RT.Release(src, holder)
    local tx = RT.active[src]
    if not tx then return false end
    if holder == 'emergency' then
        tx.forcedUntil = nil
        tx.emergency = false
    elseif holder == 'handsfree' then
        tx.handsfree = false
    else
        tx.ptt = false
    end
    if not tx.ptt and not tx.handsfree and not tx.forcedUntil then
        local rec = NZR.Radio.players[src]
        RT.Stop(src, 'release')
        if rec and holder ~= 'ptt' then NZR.Radio.Push(src) end
        return true
    end
    if holder == 'emergency' then
        RT.Update(src)
        if NZR.Radio.players[src] then NZR.Radio.Push(src) end
    end
    return true
end

function RT.Get(src)
    return RT.active[tonumber(src) or -1]
end

function RT.IsTalking(src)
    return RT.active[tonumber(src) or -1] ~= nil
end

function RT.Listeners(src)
    local tx = RT.active[tonumber(src) or -1]
    return tx and tx.listeners or {}
end

-- ════════════════════════════════════════════════════════════════════════
-- REFRESH
-- ════════════════════════════════════════════════════════════════════════

-- Is the transmission still possible as it was started? → ok, why
local function stillValid(src, tx, now)
    if not Core.Online(src) then return false, 'drop' end
    local rec = NZR.Radio.players[src]
    local fkey, slot, veh = txSource(src, tx.device, rec)
    if fkey ~= tx.fkey or (tx.device == 'handheld' and slot ~= tx.slot) or (tx.device == 'vehicle' and veh ~= tx.veh) then
        return false, 'source'
    end
    if not tx.emergency and talkerJam(src, tx.device, rec) >= blockJam() then
        return false, 'nosignal'
    end
    return true
end

local function tick(src, tx, now)
    if tx.forcedUntil and now >= tx.forcedUntil then
        RT.Release(src, 'emergency')
        if RT.active[src] ~= tx then return end
    end
    local ok, why = stillValid(src, tx, now)
    if not ok then
        RT.Stop(src, why)
        return
    end
    apply(src, tx, RT.Resolve(src, tx))
end

function RT.Update(src)
    local tx = RT.active[src]
    if not tx then return end
    RT.RefreshCoords()
    tick(src, tx, GetGameTimer())
end

function RT.Touch(fkey)
    if not next(RT.active) then return end
    local ids = {}
    for src, tx in pairs(RT.active) do
        if fkey == nil or tx.fkey == fkey then ids[#ids + 1] = src end
    end
    if #ids == 0 then return end
    RT.RefreshCoords()
    local now = GetGameTimer()
    for _, src in ipairs(ids) do
        local tx = RT.active[src]
        if tx then tick(src, tx, now) end
    end
end

CreateThread(function()
    while true do
        if next(RT.active) then
            RT.RefreshCoords(true)
            local now = GetGameTimer()
            local ids = {}
            for src in pairs(RT.active) do ids[#ids + 1] = src end
            for _, src in ipairs(ids) do
                local tx = RT.active[src]
                if tx then tick(src, tx, now) end
            end
            Wait(math.max(250, math.floor(tonumber(Config.Signal and Config.Signal.refresh) or 1000)))
        else
            Wait(250)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- NET EVENTS (C→S)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nzr:tx:start', function(device)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if device ~= 'vehicle' then device = 'handheld' end
    if not Core.Rate('nzr:tx:start', src, 8, 2000) then
        TriggerClientEvent('nzr:tx:denied', src, 'cooldown')
        return
    end
    RT.Start(src, device, { ptt = true })
end)

RegisterNetEvent('nzr:tx:stop', function()
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if not Core.Rate('nzr:tx:stop', src, 12, 2000) then return end
    RT.Release(src, 'ptt')
end)

-- ════════════════════════════════════════════════════════════════════════
-- BUS
-- ════════════════════════════════════════════════════════════════════════

NZR.Bus.On('radio:joined', function(_, fkey) RT.Touch(fkey) end)
NZR.Bus.On('radio:left', function(_, fkey) RT.Touch(fkey) end)
NZR.Bus.On('radio:changed', function() RT.Touch(nil) end)
NZR.Bus.On('jammers:changed', function() RT.Touch(nil) end)
NZR.Bus.On('vehicles:changed', function(old, new)
    if old then RT.Touch(old) end
    if new and new ~= old then RT.Touch(new) end
    -- a talker using that car may have lost it
    for src, tx in pairs(RT.active) do
        if tx.device == 'vehicle' and (tx.fkey == old or tx.fkey == new) then RT.Update(src) end
    end
end)

NZR.Bus.On('player:dropped', function(src)
    RT.Stop(src, 'drop')
    for _, tx in pairs(RT.active) do
        tx.listeners[src] = nil
        tx.targets[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    for src, tx in pairs(RT.active) do
        for id, info in pairs(tx.listeners) do TriggerClientEvent('nzr:rx:stop', id, src, info.q) end
        TriggerClientEvent('nzr:tx:targets', src, {})
    end
    RT.active = {}
end)
