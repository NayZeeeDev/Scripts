--[[
    NAYZEEE RADIO - Alerts (client): emergency alerts, gunfire over an open mic, /radiorange

    EMERGENCY  'nzr:alerts:emergency' reaches everyone on the caller's frequency (muted radios
               too). It shows the alert card (NUI app 'alert', never takes focus), plays the
               alert tone and puts a flashing blip at the caller's position for
               Config.Emergency.blipTime seconds, named after the caller. The card shows itself
               (no 'open' needed) with the street and the distance to the caller. The keybind
               'Radio: route to the last emergency' (unbound by default) sets a waypoint on it.
    GUNFIRE    While the player transmits, shots are picked up the way an open mic would: the
               player's own every frame (IsPedShooting), and those of the peds around them,
               cached every 500 ms within Config.Gunfire.radius (players first, then NPCs when
               Config.Gunfire.npcs, 24 at most). Each shot gets a kind from the weapon group
               (pistol, smg, rifle, shotgun, sniper, heavy, or silenced when suppressed) and
               its distance; a batch goes to the server 150 ms after its first shot with every
               shot's dt (ms after that first shot). At most Config.Gunfire.maxPerSecond a second.
    RANGE      /radiorange (Config.Commands.range): two radius blips for 10 s around the player,
               where the active radio is clear (falloffStart of the range) and where it fades
               out (NZR.Signal.Range), plus a toast with both in km. In an operating seat of a
               car whose head unit is on, the car's range is shown instead.

      NZR.Alerts.WeaponKind(ped) → kind | nil      NZR.Alerts.KindOf(groupHash, silenced) → kind | nil
      NZR.Alerts.Record(ped, distance, now?) → bool   add one shot to the batch (dedupes a ped's frames)
      NZR.Alerts.Flush(now?, force?) → shots | nil   send the batch when it is 150 ms old (or forced)
      NZR.Alerts.NearbyPeds() → { ped, ... }        NZR.Alerts.UpdateCapture()   start / stop with TX
      NZR.Alerts.ShowRange() → bool                 NZR.Alerts.RouteToLast() → bool

    EVENTS SENT      nzr:alerts:shots (shots = { { dt, kind, d } }) (C→S)
    EVENTS HANDLED   nzr:alerts:emergency ({ talker, name, callsign, fkey, coords }) (S→C)
    NUI SENT         alert emergency { id, name, callsign, freq, label, time, street, distance (m) };
                     _core sfx { name = 'emergency' }
    COMMANDS         Config.Commands.range        KEYBIND  nzr_alertroute (lib.addKeybind, no default key)
    BUS              handles 'radio:changed' ('tx')
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Alerts = NZR.Alerts or {}
local A = NZR.Alerts

local FLUSH_MS = 150
local PED_SCAN_MS = 500
local MAX_PEDS = 24
local MAX_BATCH = 30
local SHOT_GAP_MS = 45          -- IsPedShooting can stay up for two frames of the same shot
local RANGE_SHOW_MS = 10000

local BLIP_SPRITE = 161          -- pulsing ring
local BLIP_COLOUR = 1            -- red
local RANGE_COLOUR_CLEAR = 15    -- cyan
local RANGE_COLOUR_EDGE = 3      -- blue

local KIND_GROUPS = {
    { 'GROUP_PISTOL', 'pistol' }, { 'GROUP_SMG', 'smg' }, { 'GROUP_RIFLE', 'rifle' }, { 'GROUP_MG', 'rifle' },
    { 'GROUP_SHOTGUN', 'shotgun' }, { 'GROUP_SNIPER', 'sniper' }, { 'GROUP_HEAVY', 'heavy' },
}
-- the same groups by value, in case GetHashKey is not what the game uses for a group
local KIND_HASHES = {
    [416676503] = 'pistol', [-957766203] = 'smg', [970310034] = 'rifle', [1159398588] = 'rifle',
    [860033945] = 'shotgun', [-1212426201] = 'sniper', [-1569042529] = 'heavy',
}

local kinds = nil                -- [signed group hash] = kind (built on first use)
local cap = { on = false, gen = 0, peds = {}, last = {}, batch = nil, times = {} }
local blips = {}                 -- [talker] = { blip, gen }
local blipGen = 0
local lastAlert = nil            -- { x, y, z, at }
local rangeBlips = {}
local rangeGen = 0

local function L(key, ...) return NZR.L('world.' .. key, ...) end
local function clamp(v, lo, hi) return NZR.Util.Clamp(v, lo, hi) end

local function signed(h)
    h = tonumber(h)
    if not h then return nil end
    h = math.floor(h) % 4294967296
    if h >= 2147483648 then h = h - 4294967296 end
    return h
end

local function gunCfg() return Config.Gunfire or {} end

local function toast(key, kind, ...)
    NZR.UI.Toast({ title = L('title_radio'), message = L(key, ...), type = kind or 'info' })
end

-- ════════════════════════════════════════════════════════════════════════
-- EMERGENCY
-- ════════════════════════════════════════════════════════════════════════

local function clockString()
    local ok, h, m = pcall(function() return GetClockHours(), GetClockMinutes() end)
    if not ok or not h then return nil end
    return ('%02d:%02d'):format(h, m)
end

local function labelOf(fkey)
    if not fkey then return nil end
    local labels = NZR.Radio.Labels and NZR.Radio.Labels() or NZR.Radio.State.labels or {}
    local e = labels[fkey]
    return type(e) == 'table' and e.label or nil
end

local function cleanText(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max or 48)
end

local function removeBlip(talker)
    local b = blips[talker]
    blips[talker] = nil
    if b and DoesBlipExist(b.blip) then RemoveBlip(b.blip) end
end

local function addBlip(talker, coords, who)
    removeBlip(talker)
    local blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    if not blip or blip == 0 then return end
    SetBlipSprite(blip, BLIP_SPRITE)
    SetBlipColour(blip, BLIP_COLOUR)
    SetBlipScale(blip, 1.2)
    SetBlipAsShortRange(blip, false)
    SetBlipFlashes(blip, true)
    pcall(SetBlipFlashInterval, blip, 300)
    pcall(SetBlipRouteColour, blip, BLIP_COLOUR)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('blip_emergency', who))
    EndTextCommandSetBlipName(blip)
    blipGen = blipGen + 1
    local gen = blipGen
    blips[talker] = { blip = blip, gen = gen }
    local secs = math.max(5, tonumber(Config.Emergency and Config.Emergency.blipTime) or 60)
    SetTimeout(secs * 1000, function()
        local b = blips[talker]
        if b and b.gen == gen then removeBlip(talker) end
    end)
end

local function streetAt(c)
    local ok, hash = pcall(GetStreetNameAtCoord, c.x + 0.0, c.y + 0.0, c.z + 0.0)
    if not ok or not hash or hash == 0 then return nil end
    local okN, name = pcall(GetStreetNameFromHashKey, hash)
    if okN and type(name) == 'string' and name ~= '' then return name end
    return nil
end

RegisterNetEvent('nzr:alerts:emergency', function(data)
    if type(data) ~= 'table' then return end
    local talker = tonumber(data.talker) or 0
    local fkey = data.fkey and NZR.Freq.Key(data.fkey) or nil
    local name = cleanText(data.name, 48)
    local callsign = cleanText(data.callsign, 16)
    local who = name or L('alert_unknown')
    if callsign then who = ('%s %s'):format(who, callsign) end

    local coords = Bridge.ToVec3(data.coords)
    NZR.UI.Send('alert', 'emergency', {
        id = talker, name = name or L('alert_unknown'), callsign = callsign, freq = fkey,
        label = labelOf(fkey), time = clockString(),
        street = coords and streetAt(coords) or nil,
        distance = coords and math.floor(#(GetEntityCoords(PlayerPedId()) - coords) + 0.5) or nil,
    })
    NZR.UI.Send('_core', 'sfx', { name = 'emergency' })

    if coords then
        addBlip(talker, coords, who)
        lastAlert = { x = coords.x, y = coords.y, z = coords.z, at = GetGameTimer() }
    end
end)

function A.RouteToLast()
    local a = lastAlert
    local secs = math.max(5, tonumber(Config.Emergency and Config.Emergency.blipTime) or 60)
    if not a or GetGameTimer() - a.at > secs * 1000 then return false end
    SetNewWaypoint(a.x, a.y)
    NZR.UI.Send('_core', 'sfx', { name = 'key' })
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- GUNFIRE
-- ════════════════════════════════════════════════════════════════════════

local function kindTable()
    if kinds then return kinds end
    kinds = {}
    for h, k in pairs(KIND_HASHES) do kinds[h] = k end
    for _, g in ipairs(KIND_GROUPS) do
        local h = signed(GetHashKey(g[1]))
        if h then kinds[h] = g[2] end
    end
    return kinds
end

-- Weapon group → the sound a listener hears. Melee, thrown, stun guns, petrol cans and
-- the like make no gunshot (nil).
function A.KindOf(group, silenced)
    local kind = kindTable()[signed(group) or 0]
    if not kind then return nil end
    if silenced and kind ~= 'heavy' then return 'silenced' end
    return kind
end

function A.WeaponKind(ped)
    local ok, weapon = pcall(GetSelectedPedWeapon, ped)
    if not ok or not weapon or weapon == 0 then return nil end
    local okG, group = pcall(GetWeapontypeGroup, weapon)
    if not okG or not group then return nil end
    local okS, silenced = pcall(IsPedCurrentWeaponSilenced, ped)
    return A.KindOf(group, okS and silenced == true)
end

local function allowRate(now)
    local max = math.max(1, math.floor(tonumber(gunCfg().maxPerSecond) or 20))
    local t = cap.times
    local keep = {}
    for i = 1, #t do
        if now - t[i] < 1000 then keep[#keep + 1] = t[i] end
    end
    cap.times = keep
    if #keep >= max then return false end
    keep[#keep + 1] = now
    return true
end

function A.Record(ped, distance, now, kind)
    now = now or GetGameTimer()
    local last = cap.last[ped]
    if last and now - last < SHOT_GAP_MS then return false end
    cap.last[ped] = now
    kind = kind or A.WeaponKind(ped)
    if not kind then return false end
    local b = cap.batch
    if b and #b.shots >= MAX_BATCH then return false end
    if not allowRate(now) then return false end
    if not b then
        b = { start = now, shots = {} }
        cap.batch = b
    end
    local radius = tonumber(gunCfg().radius) or 60.0
    b.shots[#b.shots + 1] = {
        dt = math.floor(now - b.start),
        kind = kind,
        d = math.floor(clamp(tonumber(distance) or 0.0, 0.0, radius) * 10 + 0.5) / 10,
    }
    return true
end

function A.Flush(now, force)
    local b = cap.batch
    if not b or #b.shots == 0 then return nil end
    now = now or GetGameTimer()
    if not force and now - b.start < FLUSH_MS then return nil end
    cap.batch = nil
    TriggerServerEvent('nzr:alerts:shots', b.shots)
    return b.shots
end

function A.NearbyPeds()
    local c = gunCfg()
    local radius = tonumber(c.radius) or 60.0
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local found, seen = {}, { [me] = true }
    local function consider(ped)
        if not ped or ped == 0 or seen[ped] or not DoesEntityExist(ped) then return end
        seen[ped] = true
        local d = #(GetEntityCoords(ped) - pos)
        if d <= radius then found[#found + 1] = { ped = ped, d = d } end
    end
    for _, pl in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pl)) end
    if c.npcs then
        for _, ped in ipairs(GetGamePool('CPed') or {}) do
            if not seen[ped] and not IsPedAPlayer(ped) and not IsEntityDead(ped) then consider(ped) end
        end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(#found, MAX_PEDS) do out[i] = found[i].ped end
    return out
end

local function startCapture()
    cap.on = true
    cap.gen = cap.gen + 1
    local gen = cap.gen
    cap.batch, cap.last, cap.peds = nil, {}, {}
    local function alive() return cap.on and cap.gen == gen end

    CreateThread(function()
        while alive() do
            cap.peds = A.NearbyPeds()
            -- forget the shot times of peds that left
            local keep = { [PlayerPedId()] = cap.last[PlayerPedId()] }
            for i = 1, #cap.peds do keep[cap.peds[i]] = cap.last[cap.peds[i]] end
            cap.last = keep
            Wait(PED_SCAN_MS)
        end
    end)

    CreateThread(function()
        while alive() do
            local now = GetGameTimer()
            local me = PlayerPedId()
            if IsPedShooting(me) then A.Record(me, 0.0, now) end
            local peds = cap.peds
            if #peds > 0 then
                local myPos = GetEntityCoords(me)
                for i = 1, #peds do
                    local p = peds[i]
                    if DoesEntityExist(p) and IsPedShooting(p) then A.Record(p, #(GetEntityCoords(p) - myPos), now) end
                end
            end
            A.Flush(now, false)
            Wait(0)
        end
        if cap.gen == gen then A.Flush(GetGameTimer(), true) end
    end)
end

function A.UpdateCapture()
    local S = NZR.Radio.State
    local want = gunCfg().enabled == true and S.tx and S.tx.active == true
    if want and not cap.on then
        startCapture()
    elseif not want and cap.on then
        cap.on = false
    end
    return cap.on
end

NZR.Bus.On('radio:changed', function(what)
    if what == 'tx' or what == 'reset' or what == 'dropped' then A.UpdateCapture() end
end)

-- ════════════════════════════════════════════════════════════════════════
-- /radiorange
-- ════════════════════════════════════════════════════════════════════════

local function clearRange()
    for i = 1, #rangeBlips do
        if DoesBlipExist(rangeBlips[i]) then RemoveBlip(rangeBlips[i]) end
    end
    rangeBlips = {}
end

local function radiusBlip(pos, radius, colour, alpha)
    local b = AddBlipForRadius(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, radius + 0.0)
    if not b or b == 0 then return end
    SetBlipColour(b, colour)
    SetBlipAlpha(b, alpha)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('range_blip'))
    EndTextCommandSetBlipName(b)
    rangeBlips[#rangeBlips + 1] = b
end

function A.ShowRange()
    local S = NZR.Radio.State
    local pos = GetEntityCoords(PlayerPedId())
    local kind, mult, name
    local V = NZR.Vehicle
    local cur = V and V.Current and V.Current() or nil
    local head = V and V.State and V.State() or nil
    if cur and cur.operator and head and head.on then
        kind, mult, name = 'vehicle', V.RangeMult(cur.veh), 'MV-90'
    elseif S.model then
        kind, mult = S.model, 1.0
        name = NZR.Firmware and NZR.Firmware.ModelCode and NZR.Firmware.ModelCode(S.model) or S.model
    else
        toast('range_none', 'error')
        return false
    end
    local reach = NZR.Signal.Range(kind, pos, mult)
    local start = clamp(tonumber(Config.Signal and Config.Signal.falloffStart) or 0.55, 0.0, 0.99)
    local clear = reach * start

    clearRange()
    radiusBlip(pos, reach, RANGE_COLOUR_EDGE, 70)
    radiusBlip(pos, clear, RANGE_COLOUR_CLEAR, 90)
    rangeGen = rangeGen + 1
    local gen = rangeGen
    SetTimeout(RANGE_SHOW_MS, function()
        if rangeGen == gen then clearRange() end
    end)
    toast('range_info', 'info', name, clear / 1000.0, reach / 1000.0)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- COMMANDS / KEYS / LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

local rangeCmd = Config.Commands and Config.Commands.range
if rangeCmd then
    RegisterCommand(rangeCmd, function()
        if not NZR.Radio.State.ready then return end
        A.ShowRange()
    end, false)
end

CreateThread(function()
    Wait(1000)
    if rangeCmd then TriggerEvent('chat:addSuggestion', '/' .. rangeCmd, L('cmd_range'), {}) end
    if Config.Emergency and Config.Emergency.enabled then
        pcall(lib.addKeybind, {
            name = 'nzr_alertroute',
            description = L('key_alertroute'),
            defaultKey = '',
            defaultMapper = 'keyboard',
            onPressed = function()
                if IsPauseMenuActive() then return end
                A.RouteToLast()
            end,
        })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    cap.on = false
    for talker in pairs(blips) do removeBlip(talker) end
    clearRange()
end)
