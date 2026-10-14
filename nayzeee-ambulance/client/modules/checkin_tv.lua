--[[
    NAYZEEE AMBULANCE - Check-in (client): waiting room TV board (DUI)

    Position type 'tv' (NZA.Points.RegisterType): the Config.Props.tv_board screen on a wall, or
    an existing map TV (point data "existing" = true: the nearest Config.Checkin.tv.existingModels
    object within existingRadius takes the board). The board is a DUI browser
    (html/dui/tv.html, Config.Checkin.tv.width × height) that:
      - replaces Config.PropScreens.tv_board (txd / tex) on the NAYZEEE screen model
        (CreateDui → CreateRuntimeTxd → CreateRuntimeTextureFromDuiHandle → AddReplaceTexture), or
      - is drawn every frame into the native TV's render target (Config.Checkin.tv.renderTargets)
        for the fallback / existing TV models.
    Only the nearest board within tv.drawDistance runs; leaving releases the subscription at once
    and the browser after tv.linger seconds. Live data: callback 'nza:checkin:tv' (subscribe) and
    net event 'nza:checkin:board' (pushes on every check-in, call and every tv.refresh seconds).
    A soft chime plays (in the board browser, volume by distance) when a number is called.

    DUI messages (SendDuiMessage JSON): init { locale, clock, w, h } · board { board, mine, title,
    clock } · chime { volume } · standby {}
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Checkin = NZA.Checkin or {}
NZA.CheckinC = NZA.CheckinC or {}
local K = NZA.CheckinC

local RT_TXD = 'nza_checkin_tv'

local boards = {}        -- [pointId] = { point, entity }
local Dui = { obj = nil, handle = nil, txd = nil, tex = nil, n = 0, gen = 0, ready = false,
              replaced = nil, rt = nil, rtName = nil, hospital = nil, point = nil, lastServing = {} }
local current = nil      -- { id, hospital, mode = 'replace'|'rt', entity, model }

local function cfg(key, default)
    local s = Config.Checkin and Config.Checkin.tv
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end

local function L(key, ...) return NZA.L('checkin.' .. key, ...) end

local function call(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok or type(res) ~= 'table' then return { ok = false } end
    return res
end

local function clockData()
    if K.Clock then return K.Clock() end
    return { mode = (Config.Checkin and Config.Checkin.clock) or 'game', h = GetClockHours(), m = GetClockMinutes(), msPerMin = 2000 }
end

-- ════════════════════════════════════════════════════════════════════════
-- MODELS
-- ════════════════════════════════════════════════════════════════════════

local screenHash = nil
local rtByHash = nil

local function hashes()
    if rtByHash then return end
    screenHash = Config.Props and Config.Props.tv_board and joaat(Config.Props.tv_board) or nil
    rtByHash = {}
    for model, rt in pairs(cfg('renderTargets', {}) or {}) do rtByHash[joaat(model)] = { name = rt, model = model } end
end

local function existingTv(point)
    local c = point.coords
    local radius = tonumber(cfg('existingRadius', 3.0)) or 3.0
    local best, bestD = 0, math.huge
    for _, m in ipairs(cfg('existingModels', {}) or {}) do
        local obj = GetClosestObjectOfType(c.x + 0.0, c.y + 0.0, c.z + 0.0, radius, joaat(m), false, false, false)
        if obj and obj ~= 0 and DoesEntityExist(obj) then
            local d = #(GetEntityCoords(obj) - vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0))
            if d < bestD then best, bestD = obj, d end
        end
    end
    return best
end

-- → entity, mode ('replace' | 'rt'), rt info
local function screenOf(b)
    hashes()
    local ent = b.entity
    if b.point.data and b.point.data.existing then
        ent = existingTv(b.point)
        if ent == 0 then return nil end
    end
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local model = GetEntityModel(ent)
    if screenHash and model == screenHash then return ent, 'replace' end
    local rt = rtByHash[model]
    if rt then return ent, 'rt', rt end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- DUI
-- ════════════════════════════════════════════════════════════════════════

local function send(msg)
    if Dui.obj and Dui.ready then SendDuiMessage(Dui.obj, json.encode(msg)) end
end

local function unlinkScreen()
    if Dui.replaced then
        RemoveReplaceTexture(Dui.replaced.txd, Dui.replaced.tex)
        Dui.replaced = nil
    end
    if Dui.rtName then
        if IsNamedRendertargetRegistered(Dui.rtName) then ReleaseNamedRendertarget(Dui.rtName) end
        Dui.rtName, Dui.rt = nil, nil
    end
end

local function destroyDui()
    unlinkScreen()
    if Dui.obj then
        DestroyDui(Dui.obj)
        Dui.obj, Dui.handle, Dui.ready = nil, nil, false
    end
end

local function ensureDui()
    if Dui.obj then return true end
    local url = ('nui://%s/html/dui/tv.html'):format(GetCurrentResourceName())
    local w = math.floor(tonumber(cfg('width', 1280)) or 1280)
    local h = math.floor(tonumber(cfg('height', 720)) or 720)
    local ok, obj = pcall(CreateDui, url, w, h)
    if not ok or not obj then return false end
    Dui.obj = obj
    Dui.handle = GetDuiHandle(obj)
    if not Dui.txd then Dui.txd = CreateRuntimeTxd(RT_TXD) end
    Dui.n = Dui.n + 1
    Dui.tex = 'board' .. Dui.n
    CreateRuntimeTextureFromDuiHandle(Dui.txd, Dui.tex, Dui.handle)
    local t = GetGameTimer()
    while not IsDuiAvailable(obj) and GetGameTimer() - t < 5000 do Wait(50) end
    Wait(400)   -- the page script needs a moment to attach its message listener
    if Dui.obj ~= obj then return false end
    Dui.ready = true
    send({ type = 'init', locale = NZA.LocaleTable('checkin'), clock = clockData(), w = w, h = h })
    return true
end

local function linkScreen(cur)
    unlinkScreen()
    if cur.mode == 'replace' then
        local scr = Config.PropScreens and Config.PropScreens.tv_board
        if type(scr) == 'table' and scr.txd and scr.tex then
            AddReplaceTexture(scr.txd, scr.tex, RT_TXD, Dui.tex)
            Dui.replaced = { txd = scr.txd, tex = scr.tex }
        end
    elseif cur.mode == 'rt' and cur.rt then
        local name = cur.rt.name
        if not IsNamedRendertargetRegistered(name) then RegisterNamedRendertarget(name, false) end
        local hash = joaat(cur.rt.model)
        if not IsNamedRendertargetLinked(hash) then LinkNamedRendertarget(hash) end
        Dui.rtName = name
        Dui.rt = GetNamedRendertargetRenderId(name)
        local gen = Dui.gen
        CreateThread(function()
            while Dui.rtName == name and Dui.gen == gen and Dui.rt do
                SetTextRenderId(Dui.rt)
                SetScriptGfxDrawOrder(4)
                SetScriptGfxDrawBehindPausemenu(true)
                DrawSprite(RT_TXD, Dui.tex, 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
                SetTextRenderId(GetDefaultScriptRendertargetRenderId())
                SetScriptGfxDrawBehindPausemenu(false)
                Wait(0)
            end
        end)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- BOARD DATA
-- ════════════════════════════════════════════════════════════════════════

local function mineCode()
    local m = NZA.Checkin.Mine and NZA.Checkin.Mine() or nil
    return m and m.hospital == (current and current.hospital) and m.code or nil
end

local function pushBoard(board)
    if not current or type(board) ~= 'table' then return end
    local pt = boards[current.id] and boards[current.id].point
    local title = pt and pt.data and type(pt.data.title) == 'string' and pt.data.title ~= '' and pt.data.title or nil
    -- chime for newly called numbers
    local called, fresh = {}, false
    for _, s in ipairs(board.serving or {}) do
        if s.status == 'called' then
            local key = tostring(s.code) .. ':' .. tostring(s.at)
            called[key] = true
            if Dui.lastServing.init and not Dui.lastServing[key] then fresh = true end
        end
    end
    called.init = true
    Dui.lastServing = called
    send({ type = 'board', board = board, mine = mineCode(), title = title, clock = clockData() })
    if fresh and cfg('chime', true) ~= false and pt then
        local me = GetEntityCoords(PlayerPedId())
        local d = #(me - vector3(pt.coords.x + 0.0, pt.coords.y + 0.0, pt.coords.z + 0.0))
        local maxD = tonumber(cfg('chimeDistance', 22.0)) or 22.0
        if d <= maxD then send({ type = 'chime', volume = math.max(0.15, 1.0 - d / maxD) }) end
    end
end

RegisterNetEvent('nza:checkin:board', function(hospital, board)
    if current and current.hospital == hospital then pushBoard(board) end
end)

-- own ticket changed: re-highlight it on the board
RegisterNetEvent('nza:checkin:mine', function()
    if current and Dui.ready then
        SetTimeout(100, function() send({ type = 'mine', mine = mineCode() }) end)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SELECTION LOOP
-- ════════════════════════════════════════════════════════════════════════

local function release()
    if not current then return end
    local hospital = current.hospital
    current = nil
    Dui.gen = Dui.gen + 1
    unlinkScreen()
    send({ type = 'standby' })
    CreateThread(function() call('nza:checkin:tv', hospital, false) end)
    local gen = Dui.gen
    SetTimeout(math.floor(math.max(0, tonumber(cfg('linger', 15)) or 15) * 1000), function()
        if Dui.gen == gen and not current then destroyDui() end
    end)
end

local function select(b, ent, mode, rt)
    Dui.gen = Dui.gen + 1
    current = { id = b.point.id, hospital = b.point.hospital, mode = mode, entity = ent, rt = rt }
    Dui.lastServing = {}
    if not ensureDui() then current = nil return end
    if not current or current.id ~= b.point.id then return end
    linkScreen(current)
    local res = call('nza:checkin:tv', b.point.hospital, true)
    if current and current.id == b.point.id and res.ok then pushBoard(res.board) end
end

CreateThread(function()
    while true do
        local sleep = 1500
        if cfg('enabled', true) ~= false and next(boards) then
            sleep = 1000
            local me = GetEntityCoords(PlayerPedId())
            local maxD = tonumber(cfg('drawDistance', 28.0)) or 28.0
            local best, bestD, bestEnt, bestMode, bestRt = nil, math.huge, nil, nil, nil
            for _, b in pairs(boards) do
                local c = b.point.coords
                local d = #(me - vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0))
                if d <= maxD and d < bestD then
                    local ent, mode, rt = screenOf(b)
                    if ent then best, bestD, bestEnt, bestMode, bestRt = b, d, ent, mode, rt end
                end
            end
            if best then
                if not current or current.id ~= best.point.id or current.entity ~= bestEnt then
                    if current then release() end
                    select(best, bestEnt, bestMode, bestRt)
                end
            elseif current then
                release()
            end
        elseif current then
            release()
        end
        Wait(sleep)
    end
end)

-- in-game clock: keep the board's minutes in step
CreateThread(function()
    while true do
        Wait(15000)
        if current and Dui.ready then send({ type = 'clock', clock = clockData() }) end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- POSITION TYPE
-- ════════════════════════════════════════════════════════════════════════

NZA.Points.RegisterType('tv', {
    label = L('type_tv'), icon = 'monitor', prop = 'tv_board', needsHeading = true, radius = 1.0,
    desc = L('type_tv_desc'), distance = 2.0,
    data = { existing = false, title = '' },
    onSpawn = function(point, entity)
        if entity and point.data and point.data.existing then
            -- the map's own TV shows the board: the placed screen only marks the spot
            SetEntityVisible(entity, false, false)
            SetEntityCollision(entity, false, false)
        end
        boards[point.id] = { point = point, entity = entity }
    end,
    onRemove = function(point)
        boards[point.id] = nil
        if current and current.id == point.id then release() end
    end,
})

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    current = nil
    Dui.gen = Dui.gen + 1
    destroyDui()
end)
