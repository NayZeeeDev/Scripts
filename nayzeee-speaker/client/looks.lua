--[[
    Looks: the speaker props restyled while the resource runs. Nothing in stream/ is changed: textures
    of the pack's own dictionary (nayzeee_audio_texture) are swapped for images in html/looks/, and
    swapped back when the resource stops.

      * colours / designs (Config.Looks.textures, logo, record): set once at start, nothing runs per frame
      * RGB lights (Config.Looks.rgb): the props' light strips become a small page (html/looks/rgb.html).
        It only exists while one of those speakers is near you, and in 'music' mode it follows the
        loudest speaker you can hear. 'static' needs no page at all.
        The Carry Cube and Roll Bar take their strip ('emissive4') from the pack's shared dictionary, so
        theirs always changes. The other speakers keep their light inside the model itself; those are
        tried under the model's name (rgb.builtIn) and stay as they are if the game doesn't allow it.
      * the record on the old turntable: while an album is on the nearest one, its record shows that
        album's cover as the label (html/looks/label.html). The record console upgrade has its own
        label (client/turntable.lua) in its own dictionary, so the two never meet.
    Players can turn the RGB lights off for themselves in the player's Settings tab.
]]
local C = Config.Looks
if type(C) ~= 'table' or C.enabled == false then return end

local TXD = 'nayzeee_audio_texture'     -- the prop pack's dictionary (the textures we swap)
local RT = 'nzspk_looks'                -- ours, made at runtime
local DIR = 'html/looks/'
local RUN = tostring(GetGameTimer() % 1000000)   -- page textures get fresh names on every start
local CONSOLE_NAME = (Config.Turntable and Config.Turntable.consoleModel) or 'nayzeee_console'
local CONSOLE = joaat(CONSOLE_NAME) & 0xFFFFFFFF   -- compared unsigned: hashes come back signed or not

local R = type(C.rgb) == 'table' and C.rgb or {}
local RGB_ON = C.rgb ~= false and R.enabled ~= false
local MODES = { rainbow = true, fade = true, pulse = true, static = true, music = true }
local STRIP_W, STRIP_H = 256, 32                 -- the original strip's size
local NEAR = tonumber(R.distance) or 60.0        -- the page starts when a speaker is this close
local FAR = NEAR + 10.0                          -- and stops when the last one is further than this
local REC_ON = C.recordArt ~= false
local REC_NEAR, REC_PX, REC_GRACE = 30.0, 512, 5000
local DUI_WAIT, DUI_RETRY = 5000, 30000          -- wait for a page to come up; after one didn't, try again later

local warned = {}
local function warn(msg)
    if warned[msg] then return end
    warned[msg] = true
    print(('^3[%s] Config.Looks: %s^7'):format(RES, msg))
end

local function clamp(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return v < lo and lo or (v > hi and hi or v)
end

---------------------------------------------------------------- swapping
local txd = nil
local made = {}         -- runtime texture name -> true
local static = {}       -- texture -> runtime texture of its configured look (what it falls back to)
local active = {}       -- 'dictionary/texture' -> { dictionary, texture, runtime texture it shows now }
local stopped = false

local function dict()
    if not txd then txd = CreateRuntimeTxd(RT) end
    return txd
end

-- show `name` (a texture in our dictionary) in place of `tex` of dictionary `from`; nil = the original.
-- `guard`: a dictionary that may not exist (a model's built-in one), so the calls can't stop this file
local function swap(from, tex, name, guard)
    local k = from .. '/' .. tex
    local cur = active[k]
    if stopped or (cur and cur[3]) == name then return end
    if cur then
        if guard then pcall(RemoveReplaceTexture, from, tex) else RemoveReplaceTexture(from, tex) end
    end
    active[k] = name and { from, tex, name } or nil
    if name then
        if guard then pcall(AddReplaceTexture, from, tex, RT, name) else AddReplaceTexture(from, tex, RT, name) end
    end
end

local function point(tex, name) swap(TXD, tex, name) end
local function settle(tex) point(tex, static[tex]) end

-- html/looks/<tex>/<variant>.png as a texture in our dictionary, or nil (with a warning) when it can't be
local function image(tex, variant)
    if type(variant) ~= 'string' then
        warn(('%s = %s: the look must be a name in quotes (or \'original\')'):format(tex, tostring(variant)))
        return nil
    end
    variant = variant:lower()
    if not tex:match('^[%l%d_]+$') or not variant:match('^[%l%d_]+$') then
        warn(('%s = \'%s\': names are lowercase letters, numbers and _'):format(tex, variant))
        return nil
    end
    local file = DIR .. tex .. '/' .. variant .. '.png'
    if not LoadResourceFile(RES, file) then
        warn(('%s = \'%s\': there is no %s (see html/looks/library.json for the looks there are)'):format(tex, variant, file))
        return nil
    end
    local name = tex .. '__' .. variant
    if not made[name] then
        CreateRuntimeTextureFromImage(dict(), name, file)
        made[name] = true
    end
    return name
end

-- every configured look, once
local function applyStatic()
    local want = {}
    if type(C.textures) == 'table' then
        for tex, v in pairs(C.textures) do
            if type(tex) == 'string' then want[tex:lower()] = v end
        end
    elseif C.textures ~= nil then
        warn('textures must be a table: { sp1 = \'teal\', ... }')
    end
    -- logo / record: true = the NAYZEEE one, a name = that look, false = the pack's own
    for key, tex in pairs({ logo = 'brands', record = 'record' }) do
        local v = C[key]
        if v ~= nil then want[tex] = v == true and 'nayzeee' or v end
    end
    for tex, v in pairs(want) do
        if v ~= false and v ~= 'original' then
            static[tex] = image(tex, v)
            settle(tex)
        end
    end
end

---------------------------------------------------------------- pages (DUI)
local seq = 0

-- a page as a texture in our dictionary: returns the DUI and the texture name, or nil
local function newPage(url, w, h)
    local dui = CreateDui(url, w, h)
    if not dui then return nil end
    local t = GetGameTimer()
    while not IsDuiAvailable(dui) and GetGameTimer() - t < DUI_WAIT and not stopped do Wait(50) end
    if stopped or not IsDuiAvailable(dui) then
        DestroyDui(dui)
        return nil
    end
    seq = seq + 1
    local name = ('page_%s_%d'):format(RUN, seq)
    CreateRuntimeTextureFromDuiHandle(dict(), name, GetDuiHandle(dui))
    return dui, name
end

local function enc(s)
    return (tostring(s):gsub('[^%w%-%._~]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

---------------------------------------------------------------- RGB lights
local MODE = R.mode or 'rainbow'
if not MODES[MODE] then
    warn(('rgb.mode = \'%s\' is not one of rainbow | fade | pulse | static | music: using rainbow'):format(tostring(MODE)))
    MODE = 'rainbow'
end
local SPEED = clamp(R.speed, 0.05, 5.0) or 1.0
local BRIGHT = clamp(R.brightness, 0.0, 1.0) or 1.0
local SAT = clamp(R.saturation, 0.0, 1.0) or 1.0
local COLORS = {}
for _, c in ipairs(type(R.colors) == 'table' and R.colors or {}) do
    local hex = type(c) == 'string' and c:match('^#?(%x%x%x%x%x%x)$')
    if hex then COLORS[#COLORS + 1] = hex:lower() else warn(('rgb.colors: \'%s\' is not a colour like \'#08afa2\''):format(tostring(c))) end
end
if #COLORS == 0 then COLORS = { '08afa2', '7b2ff7', 'ff2d75' } end

-- where each prop's light lives (read from the models by the asset tools). emissive4 is in the pack's
-- shared dictionary: library.json says which props use it (the Carry Cube and Roll Bar). The rest are
-- built into the model; they are swapped under the model's name, which may not reach them.
local LIGHTS = { { from = TXD, tex = 'emissive4', models = { 'nayzeee_audio_e', 'nayzeee_audio_f' } } }
do
    local lib = LoadResourceFile(RES, DIR .. 'library.json')
    local ok, data = pcall(json.decode, lib or '')
    local e4 = ok and type(data) == 'table' and type(data.textures) == 'table' and data.textures.emissive4
    local used = type(e4) == 'table' and e4.usedBy
    if type(used) == 'table' and #used > 0 then LIGHTS[1].models = used end
end
if R.builtIn ~= false then
    for _, l in ipairs({ { 'nayzeee_audio_a', 'rgb' }, { 'nayzeee_audio_b', 'emissive' }, { 'nayzeee_audio_c', 'emissive2' },
                         { 'nayzeee_audio_d', 'emissive3' }, { 'nayzeee_audio_h', 'rgb' } }) do
        LIGHTS[#LIGHTS + 1] = { from = l[1], tex = l[2], models = { l[1] }, guard = true }
    end
end
local STRIP = {}        -- models with a light the page drives
for _, l in ipairs(LIGHTS) do
    for _, m in ipairs(l.models) do STRIP[m] = true end
end
STRIP[CONSOLE_NAME] = nil

-- every light shows `name`, or (nil) its own look: emissive4's static look from textures, else the original
local function lights(name)
    for _, l in ipairs(LIGHTS) do
        swap(l.from, l.tex, name or (l.from == TXD and static[l.tex] or nil), l.guard)
    end
end

local rgb = { dui = nil, music = false, plain = nil, failAt = nil }

local function rgbUrl()
    return ('nui://%s/%srgb.html?mode=%s&w=%d&h=%d&s=%.2f&b=%.2f&sat=%.2f&c=%s'):format(
        RES, DIR, MODE, STRIP_W, STRIP_H, SPEED, BRIGHT, SAT, table.concat(COLORS, ','))
end

-- 'static' is one colour: a tiny texture filled once, no page needed
local function plainStrip()
    if rgb.plain then return rgb.plain end
    local hex = COLORS[1]
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    local v = math.max(r, g, b)
    r, g, b = v - (v - r) * SAT, v - (v - g) * SAT, v - (v - b) * SAT     -- towards white, like the page does
    local function px(c) return math.floor(c * BRIGHT * 255 + 0.5) end
    local name = ('strip_%s_%d_%d'):format(hex, math.floor(BRIGHT * 100 + 0.5), math.floor(SAT * 100 + 0.5))
    local tex = CreateRuntimeTexture(dict(), name, 16, 4)
    for y = 0, 3 do
        for x = 0, 15 do SetRuntimeTexturePixel(tex, x, y, px(r), px(g), px(b), 255) end
    end
    CommitRuntimeTexture(tex)
    rgb.plain = name
    return name
end

local function setMusic(on)
    if rgb.music == on then return end
    rgb.music = on
    SendNUIMessage({ action = 'looks:level', on = on })
end

local function dropRgb()
    if not rgb.dui then return end
    lights(nil)                         -- back to the strips' own look before the page goes away
    DestroyDui(rgb.dui)
    rgb.dui = nil
    setMusic(false)
end

local function dist2(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function modelOf(e)
    if e.model then return e.model end
    local cfg = e.item and Config.Boomboxes[e.item]
    return cfg and cfg.model
end

-- is one of the speakers with the light strip within `range` of me (placed or carried, not a car)?
local function stripNear(me, range)
    local r2 = range * range
    for _, e in pairs(Emitters) do
        if e.kind == 'boombox' and STRIP[modelOf(e) or ''] then
            local pos
            if e.state == 'placed' and e.coords then
                pos = e.coords
            elseif e.state == 'carried' then
                local _, p = LocateEmitter(e)
                pos = p
            end
            if pos and dist2(pos, me) <= r2 then return true end
        end
    end
    return false
end

local function updateRgb(me)
    local on = RGB_ON and Settings.rgb ~= false
    if MODE == 'static' then
        lights(on and plainStrip() or nil)
        return
    end
    if not on then return dropRgb() end
    local near = stripNear(me, rgb.dui and FAR or NEAR)
    if not near then return dropRgb() end
    if not rgb.dui then
        if rgb.failAt and GetGameTimer() - rgb.failAt < DUI_RETRY then return end
        local dui, name = newPage(rgbUrl(), STRIP_W, STRIP_H)
        if not dui then rgb.failAt = GetGameTimer() return end
        if stopped then DestroyDui(dui) return end
        rgb.dui = dui
        lights(name)
    end
    setMusic(MODE == 'music')
end

-- the NUI's level of the loudest speaker you hear (about ten times a second, only while asked for)
RegisterNUICallback('looksLevel', function(data, cb)
    cb(1)
    if rgb.dui and rgb.music and type(data) == 'table' then
        SendDuiMessage(rgb.dui, ('{"t":"level","v":%.3f}'):format(clamp(data.v, 0.0, 1.0) or 0.0))
    end
end)

-- the NUI asks once it has loaded: whether to show the RGB switch, and whether to send levels
RegisterNUICallback('looks', function(_, cb)
    cb({ rgb = RGB_ON, level = rgb.music })
end)

---------------------------------------------------------------- the old turntable's record
local rec = { dui = nil, tex = nil, id = nil, key = nil, idleAt = nil, failAt = nil }

local function isOldDeck(e)
    if e.kind ~= 'boombox' or e.state ~= 'placed' or not e.coords then return false end
    local cfg = e.item and Config.Boomboxes[e.item]
    if not (e.turntable or (cfg and cfg.vinyl == true)) then return false end
    if modelOf(e) == CONSOLE_NAME then return false end
    local ent = LocateEmitter(e)
    return ent ~= nil and (GetEntityModel(ent) & 0xFFFFFFFF) ~= CONSOLE
end

-- the nearest old turntable (the current one keeps it unless another is clearly closer)
local function nearestDeck(me)
    local best, bestD, curD
    local lim = REC_NEAR * REC_NEAR
    for id, e in pairs(Emitters) do
        if e.kind == 'boombox' and e.state == 'placed' and e.coords then
            local d = dist2(e.coords, me)
            if d <= lim and isOldDeck(e) then
                d = math.sqrt(d)
                if id == rec.id then curD = d end
                if not bestD or d < bestD then best, bestD = id, d end
            end
        end
    end
    if curD and best ~= rec.id and bestD > curD - 2.0 then best = rec.id end
    return best
end

local function recUrl(vin)
    local n = type(vin.tracks) == 'table' and #vin.tracks or 0
    return ('nui://%s/%slabel.html?size=%d&n=%d&cover=%s&album=%s&artist=%s'):format(
        RES, DIR, REC_PX, n, enc(vin.cover), enc(vin.album or ''), enc(vin.artist or ''))
end

local function dropRecord()
    if not rec.dui then return end
    settle('record')
    DestroyDui(rec.dui)
    rec.dui, rec.tex, rec.key, rec.idleAt = nil, nil, nil, nil
end

local function updateRecord(me)
    local vin
    if REC_ON and not Settings.streamer then
        rec.id = nearestDeck(me)
        local e = rec.id and Emitters[rec.id]
        vin = e and e.vinyl
        if vin and not (type(vin.cover) == 'string' and vin.cover:match('^https?://')) then vin = nil end
    else
        rec.id = nil
    end
    local t = GetGameTimer()
    if not vin then
        -- the plain record right away; the page itself goes a little later (a record swap brings it back)
        settle('record')
        if rec.dui then
            rec.idleAt = rec.idleAt or t
            if t - rec.idleAt > REC_GRACE then dropRecord() end
        end
        return
    end
    rec.idleAt = nil
    local url = recUrl(vin)
    if not rec.dui then
        if rec.failAt and t - rec.failAt < DUI_RETRY then return end
        local dui, name = newPage(url, REC_PX, REC_PX)
        if not dui then rec.failAt = GetGameTimer() return end
        if stopped then DestroyDui(dui) return end
        rec.dui, rec.tex, rec.key = dui, name, url
    elseif rec.key ~= url then
        rec.key = url
        SetDuiUrl(rec.dui, url)
    end
    point('record', rec.tex)
end

---------------------------------------------------------------- run
CreateThread(function()
    applyStatic()
    if not RGB_ON and not REC_ON then return end
    while not stopped do
        local me = GetEntityCoords(PlayerPedId())
        updateRgb(me)
        if not stopped then updateRecord(me) end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    stopped = true
    for _, a in pairs(active) do pcall(RemoveReplaceTexture, a[1], a[2]) end
    active = {}
    if rgb.dui then DestroyDui(rgb.dui) end
    if rec.dui then DestroyDui(rec.dui) end
    rgb.dui, rec.dui = nil, nil
end)
