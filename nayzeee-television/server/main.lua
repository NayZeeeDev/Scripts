--[[ NAYZEEE TELEVISION — server core: registry, RPC, clock ]]

TV = { list = {}, calibration = {} }
RPC = {}

local PERSIST = {
    'id', 'label', 'model', 'kind', 'coords', 'heading', 'pitch', 'roll', 'wall', 'owner', 'ownerName', 'permanent',
    'perms', 'locked', 'group', 'range', 'aspect', 'style', 'hd', 'volume', 'settings', 'remote', 'defaultUrl',
    'autoplay', 'loop', 'item', 'created',
}
if Config.Sync.PersistState then
    PERSIST[#PERSIST + 1] = 'history'
    PERSIST[#PERSIST + 1] = 'queue'
end

-- screens whose queue / history changed get written in batches
local dirty = {}
function TV.touch(tv) if Config.Sync.PersistState then dirty[tv.id] = true end end

function TV.now() return GetGameTimer() end

-- ─── serialisation ─────────────────────────────────────────────
function TV.public(tv)
    local o = {}
    for k, v in pairs(tv) do
        if k ~= 'owner' and k ~= 'perms' and k ~= 'uiBy' then o[k] = v end
    end
    local p = tv.perms or {}
    o.perms = { public = p.public == true, restricted = (next(p.jobs or {}) or next(p.gangs or {}) or p.ace) and true or false }
    o.hasOwner = tv.owner ~= nil
    return o
end

function TV.record(tv)
    local r = {}
    for _, k in ipairs(PERSIST) do r[k] = tv[k] end
    return r
end

function TV.shouldPersist(tv)
    return tv.permanent or Config.PlayerScreens.Persist
end

function TV.save(tv)
    if TV.shouldPersist(tv) then Storage.saveScreen(TV.record(tv)) end
end

--- Send changed fields to everyone.
function TV.patch(tv, fields)
    local p, cleared = {}, {}
    for _, k in ipairs(fields) do
        if k == 'perms' then p.perms = TV.public(tv).perms
        elseif tv[k] == nil then cleared[#cleared + 1] = k
        else p[k] = tv[k] end
    end
    TriggerClientEvent('nztv:patch', -1, tv.id, p, cleared)
end

-- ─── create / remove ───────────────────────────────────────────
function TV.create(def)
    local prop = def.model and Props.Get(def.model) or nil
    local tv = {
        id        = def.id or Utils.id(8),
        label     = def.label or (prop and prop.label) or 'Screen',
        model     = def.model,
        kind      = def.kind or 'prop',                       -- prop | existing | wall
        coords    = { x = def.coords.x + 0.0, y = def.coords.y + 0.0, z = def.coords.z + 0.0 },
        heading   = (def.heading or 0.0) + 0.0,
        pitch     = def.pitch and (def.pitch + 0.0) or nil,
        roll      = def.roll and (def.roll + 0.0) or nil,
        wall      = def.wall,                                 -- { w, h } for wall screens
        owner     = def.owner,
        ownerName = def.ownerName,
        permanent = def.permanent == true,
        perms     = Utils.copy(def.perms or Config.DefaultPermissions),
        locked    = def.locked == true,
        group     = def.group,
        range     = (def.range or (prop and prop.range) or 20.0) + 0.0,
        aspect    = def.aspect or (prop and prop.aspect) or (16 / 9),
        style     = def.style or (prop and prop.style) or 'flat',
        hd        = def.hd or (prop and prop.hd) or false,
        volume    = def.volume or Config.Audio.Volume01,
        settings  = def.settings or { picture = 'standard', fit = 'contain', ambient = true, osd = true },
        sleepAt   = nil,
        remote    = def.remote,
        defaultUrl= def.defaultUrl,
        autoplay  = def.autoplay == true,
        loop      = def.loop == true,
        item      = def.item,
        created   = def.created or os.time(),
        -- runtime
        power     = def.power == true,
        muted     = false,
        media     = nil,
        queue     = Config.Sync.PersistState and def.queue or {},
        history   = Config.Sync.PersistState and def.history or {},
        channel   = 0,
        ui        = { page = 'home' },
        uiSeq     = 0,
    }
    TV.list[tv.id] = tv
    return tv
end

function TV.spawn(tv)
    TV.save(tv)
    TriggerClientEvent('nztv:add', -1, TV.public(tv))
end

function TV.remove(id)
    local tv = TV.list[id]
    if not tv then return end
    TV.list[id] = nil
    Storage.deleteScreen(id)
    TriggerClientEvent('nztv:remove', -1, id)
end

function TV.get(id) return id and TV.list[id] or nil end

--- Members of a link group (or just the TV itself).
function TV.members(tv)
    if not tv.group then return { tv } end
    local out = {}
    for _, t in pairs(TV.list) do if t.group == tv.group then out[#out + 1] = t end end
    return out
end

-- ─── RPC plumbing ──────────────────────────────────────────────
local rate = {}

RegisterNetEvent('nztv:rpc', function(reqId, name, ...)
    local src = source
    local now = GetGameTimer()
    local r = rate[src]
    if not r or now - r.t > 1000 then r = { t = now, n = 0 } rate[src] = r end
    r.n = r.n + 1
    if r.n > 40 then return end

    local fn = RPC[name]
    if not fn then return TriggerClientEvent('nztv:rpc', src, reqId, nil, 'unknown') end
    local ok, res, err = pcall(fn, src, ...)
    if not ok then
        print(('^1[nayzeee-television] rpc %s failed: %s^7'):format(name, res))
        return TriggerClientEvent('nztv:rpc', src, reqId, nil, 'error')
    end
    TriggerClientEvent('nztv:rpc', src, reqId, res, err)
end)

AddEventHandler('playerDropped', function()
    local src = source
    rate[src] = nil
    for _, tv in pairs(TV.list) do
        if tv.remoteHolder == src then
            tv.remoteHolder = nil
            TV.patch(tv, { 'remoteHolder' })
        end
    end
end)

-- ─── boot / clock ──────────────────────────────────────────────
RPC.time = function() return TV.now() end

RPC.boot = function(src)
    local out = {}
    for _, tv in pairs(TV.list) do out[#out + 1] = TV.public(tv) end
    return {
        tvs = out,
        now = TV.now(),
        calibration = TV.calibration,
        channels = Channels.list,
        plex = Channels.plexEnabled(),
        search = (ServerConfig.YouTubeApiKey or '') ~= '',
        admin = Perms.isAdmin(src),
        me = src,
    }
end

-- ─── start-up ──────────────────────────────────────────────────
local function startDefaultMedia(tv)
    if tv.autoplay and tv.defaultUrl then
        tv.power = true
        Media.play(tv, tv.defaultUrl, nil, { silent = true, by = 'Autoplay' })
    end
end

AddEventHandler('nztv:bridgeReady', function()
    Storage.init()
    TV.calibration = Storage.loadCalibration()
    local n, loaded = 0, {}
    for _, rec in ipairs(Storage.loadScreens()) do
        if rec.coords then
            loaded[#loaded + 1] = TV.create(rec)
            n = n + 1
        end
    end
    -- autoplay once every screen exists, and only from a group's leader
    for _, tv in ipairs(loaded) do
        if not tv.group or Media.leader(tv) == tv then startDefaultMedia(tv) end
    end
    print(('^2[nayzeee-television]^7 loaded ^5%d^7 screens'):format(n))
    TriggerClientEvent('nztv:client:reboot', -1)
end)

-- Playback clock: advance queues / playlists / loops even when nobody is near.
CreateThread(function()
    while true do
        Wait(1000)
        local now = TV.now()
        for _, tv in pairs(TV.list) do
            local m = tv.media
            if m and not m.paused and not m.live and m.duration and m.duration > 0 then
                if (now - m.startedAt) / 1000 >= m.duration + 0.75 then
                    -- only the group leader drives the group
                    if not tv.group or Media.leader(tv) == tv then Media.ended(tv) end
                end
            end
            if tv.sleepAt and now >= tv.sleepAt then
                tv.sleepAt = nil
                Media.powerOff(tv)
            end
            if tv.remoteHolder and not GetPlayerName(tv.remoteHolder) then
                tv.remoteHolder = nil
                TV.patch(tv, { 'remoteHolder' })
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(15000)
        for id in pairs(dirty) do
            local tv = TV.list[id]
            if tv then TV.save(tv) end
        end
        dirty = {}
    end
end)

-- Exports for other resources
exports('GetScreens', function() return TV.list end)
exports('PlayOnScreen', function(id, url) local tv = TV.get(id) if tv then return Media.play(tv, url, nil, { by = 'Server' }) end end)
exports('StopScreen', function(id) local tv = TV.get(id) if tv then Media.stop(tv) end end)
exports('useItem', function(event, item, inventory, slot)
    -- ox_inventory: server = { export = 'nayzeee-television.useItem' }
    if event ~= 'usingItem' then return end
    local src = inventory and inventory.id
    if not src then return false end
    local meta
    local ok, s = pcall(function() return exports.ox_inventory:GetSlot(src, slot) end)
    if ok and s then meta = s.metadata end
    Items.use(src, item.name, meta)
    return false
end)
