--[[
    NAYZEEE RADIO - Voice (client): Mumble TX / RX, radio submixes, dropouts, leak, audio cues

    pma-voice stays in charge of proximity and phone calls; its own radio is never used.
    Talking adds the listeners the server picked to Mumble voice target 1 (pma-voice's
    target, it only clears target channels on its own) and holds the voice control down.
    Receiving sets a volume override and a radio submix per talker, sized by the link
    quality the server measured; weak links drop out in short bursts, lost ones only
    hiss. Everything set here is put back when a talker stops and when the resource stops.

      NZR.Voice.Ptt(down, device) → bool   PTT edge ('handheld' | 'vehicle'); the local gate is
                                           NZR.Radio.API.CanTalk
      NZR.Voice.HotMic(device, ms)         the emergency open mic (the server runs the TX)
      NZR.Voice.Update()                   re-evaluate who opens the mic (PTT / hands-free / hot mic)
      NZR.Voice.IsTalking() → bool         NZR.Voice.Rx() → { [talker] = info }
      NZR.Voice.ClearRx()                  stop every reception (power off)
      NZR.Voice.StopAll()                  drop the mic and every reception, restore Mumble
      NZR.Voice.Submix(tier) → id          'clear' | 'weak' | 'poor' | 'speaker'

    Who sends what: PTT press / release always send nzr:tx:start / nzr:tx:stop (the server
    keeps the transmission while hands-free or the hot mic still hold it). Hands-free and the
    emergency hot mic are started by the server (nzr:radio:handsfree / nzr:alerts:emergency);
    the client then only does its half (targets, voice control, chirps, LEDs, animation).

    EVENTS SENT      nzr:tx:start (device), nzr:tx:stop (C→S)
    EVENTS HANDLED   nzr:tx:targets (ids), nzr:tx:denied (reason), nzr:rx:start (talker, info),
                     nzr:rx:update (talker, info), nzr:rx:stop (talker, q),
                     nzr:rx:shots (talker, shots, q) (S→C)
    NUI SENT         '_core' sfx { name = tx_start | tx_end | rx_start | rx_end | squelch | error, q?, volume? }
                     '_core' rx { active, worstQ, lost, gain }   (hiss bed, only on change)
                     '_core' gunfire { shots, q, volume }
    BUS              handles 'radio:changed', 'radio:power'; emits 'radio:rx' (talker, info, 'start'|'update'|'stop'),
                     'radio:notice' (reason, device)
    STATE            NZR.Radio.State.tx / .rx (through NZR.Radio.SetTx / Changed)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Voice = NZR.Voice or {}
local V = NZR.Voice

local VOICE_TARGET = 1          -- pma-voice's voice target
local READD_MS = 250            -- pma-voice clears target players when a call changes
local RX_TICK_MS = 100
local RX_TICK_FAST_MS = 50      -- while a weak link may drop out
local DROP_CHECK_MS = 150

local tx = {
    active = false, device = nil, ptt = false, pttDevice = nil, sent = false,
    targets = {}, hotUntil = 0, hotDevice = nil, animToken = nil, loop = false,
}
local rx = {}                   -- [talker] = { info, vol, sub, dropUntil, nextDrop, at }
local rxLoop = false
local lastRxMsg = nil
local submixes = nil
local myId = nil

local function S() return NZR.Radio.State end
local function API() return NZR.Radio.API end

local function me()
    if not myId then myId = GetPlayerServerId(PlayerId()) end
    return myId
end

local function sfx(name, extra)
    local data = { name = name }
    if extra then for k, v in pairs(extra) do data[k] = v end end
    NZR.UI.Send('_core', 'sfx', data)
end

local function clicksOn()
    return S().clicks ~= false
end

local function tiers()
    return (Config.Signal and Config.Signal.tiers) or { clear = 0.75, weak = 0.45, poor = 0.15 }
end

local function tierOf(q)
    if NZR.Signal and NZR.Signal.Tier then
        local ok, t = pcall(NZR.Signal.Tier, q)
        if ok and type(t) == 'string' then return t end
    end
    local t = tiers()
    if q >= t.clear then return 'clear' elseif q >= t.weak then return 'weak' elseif q >= t.poor then return 'poor' end
    return 'lost'
end

-- ════════════════════════════════════════════════════════════════════════
-- SUBMIXES (created once per session; GTA has no way to free them)
-- ════════════════════════════════════════════════════════════════════════

local PAN = { left = { 1.0, 0.15 }, center = { 1.0, 1.0 }, right = { 0.15, 1.0 } }

local function ensureSubmixes()
    if submixes then return submixes end
    submixes = {}
    local pan = PAN[(Config.Audio and Config.Audio.pan) or 'center'] or PAN.center
    for _, tier in ipairs({ 'clear', 'weak', 'poor', 'speaker' }) do
        local ok, id = pcall(CreateAudioSubmix, 'nzr_' .. tier)
        if ok and id and id ~= -1 then
            SetAudioSubmixEffectRadioFx(id, 0)
            SetAudioSubmixEffectParamInt(id, 0, GetHashKey('default'), 1)
            for k, v in pairs((Config.Audio and Config.Audio.Submix and Config.Audio.Submix[tier]) or {}) do
                SetAudioSubmixEffectParamFloat(id, 0, GetHashKey(k), (tonumber(v) or 0) + 0.0)
            end
            SetAudioSubmixOutputVolumes(id, 0, pan[1], pan[2], 0.0, 0.0, 1.0, 1.0)
            AddAudioSubmixOutput(id, 0)
            submixes[tier] = id
        else
            NZR.Warn('could not create audio submix nzr_' .. tier)
        end
    end
    return submixes
end

function V.Submix(tier)
    return ensureSubmixes()[tier]
end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

-- pma-voice call partners share Player(id).state.callChannel (> 0)
local function isCallPartner(id)
    local mine = LocalPlayer.state.callChannel
    if not mine or mine == 0 then return false end
    local ok, theirs = pcall(function() return Player(id).state.callChannel end)
    return ok and theirs == mine
end

local function callVolume()
    local ok, v = pcall(function() return exports['pma-voice']:getCallVolume() end)
    v = ok and tonumber(v) or nil
    if not v then return 0.5 end
    return math.max(0.0, math.min(1.0, v / 100))
end

local function pedOfServerId(id)
    local pl = GetPlayerFromServerId(id)
    if not pl or pl == -1 then return 0 end
    return GetPlayerPed(pl)
end

local function vehicleOfNet(net)
    net = tonumber(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return 0 end
    local veh = NetToVeh(net)
    if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
    return 0
end

local function doorsShut(veh)
    if NZR.Vehicle and NZR.Vehicle.DoorsShut then
        local ok, shut = pcall(NZR.Vehicle.DoorsShut, veh)
        if ok then return shut == true end
    end
    for door = 0, 5 do
        if GetVehicleDoorAngleRatio(veh, door) > 0.05 then return false end
    end
    return true
end

local function smoothstep(a, b, x)
    return NZR.Util.Smoothstep(a, b, x)
end

-- ════════════════════════════════════════════════════════════════════════
-- TX
-- ════════════════════════════════════════════════════════════════════════

local function addTargets()
    for id in pairs(tx.targets) do MumbleAddVoiceTargetPlayerByServerId(VOICE_TARGET, id) end
end

local function removeTargets()
    for id in pairs(tx.targets) do
        if not isCallPartner(id) then MumbleRemoveVoiceTargetPlayerByServerId(VOICE_TARGET, id) end
    end
    tx.targets = {}
end

local function talkAnimAllowed()
    local ped = PlayerPedId()
    return not S().raised and tx.device ~= 'vehicle' and not IsPedInAnyVehicle(ped, false)
        and not IsPedRagdoll(ped) and not IsEntityDead(ped)
end

local function startTalkAnim()
    if tx.animToken or not talkAnimAllowed() then return end
    local a = Config.Radios.Talk and Config.Radios.Talk.anim
    if not a or not a.dict or not a.clip then return end
    local ok, token = NZR.Anim.Play(PlayerPedId(), a.dict, a.clip, { flag = 49, blendIn = 4.0, blendOut = -4.0 })
    if ok then tx.animToken = token end
end

local function stopTalkAnim()
    if not tx.animToken then return end
    NZR.Anim.Stop(PlayerPedId(), { token = tx.animToken })
    tx.animToken = nil
end

local function txLoop()
    if tx.loop then return end
    tx.loop = true
    CreateThread(function()
        local nextReadd, nextCheck = 0, 0
        while tx.active do
            -- the voice control held down: Mumble transmits whatever the player's voice mode is
            SetControlNormal(0, 249, 1.0)
            SetControlNormal(1, 249, 1.0)
            SetControlNormal(2, 249, 1.0)
            local now = GetGameTimer()
            if now >= nextReadd then
                addTargets()
                nextReadd = now + READD_MS
            end
            if now >= nextCheck then
                nextCheck = now + 250
                if not Config.Radios.Talk.whileDead and API().IsDead() then
                    tx.ptt, tx.hotUntil = false, 0
                    if S().handsfree then API().Handsfree(false) end
                    V.Update()
                elseif tx.ptt and IsPauseMenuActive() then
                    -- the key release is swallowed while the pause menu is open
                    tx.ptt = false
                    V.Update()
                elseif tx.hotUntil > 0 and now >= tx.hotUntil then
                    tx.hotUntil = 0
                    V.Update()
                end
                if tx.active and tx.animToken then
                    local a = Config.Radios.Talk.anim
                    if not talkAnimAllowed() then
                        stopTalkAnim()
                    elseif not IsEntityPlayingAnim(PlayerPedId(), a.dict, a.clip, 3) then
                        tx.animToken = nil
                        startTalkAnim()
                    end
                elseif tx.active and not tx.animToken then
                    startTalkAnim()
                end
            end
            Wait(0)
        end
        tx.loop = false
    end)
end

local function startLocal(device)
    tx.active = true
    tx.device = device
    if clicksOn() then sfx('tx_start') end
    NZR.Radio.SetTx(true, device)
    addTargets()
    startTalkAnim()
    txLoop()
end

local function stopLocal()
    if not tx.active then return end
    tx.active = false
    removeTargets()
    stopTalkAnim()
    if clicksOn() then sfx('tx_end') end
    NZR.Radio.SetTx(false)
    tx.device = nil
end

-- One place decides who opens the mic and what the server is told.
function V.Update()
    local st = S()
    local now = GetGameTimer()
    if tx.ptt and tx.pttDevice ~= 'vehicle' and not st.power then tx.ptt = false end
    local hf = st.handsfree == true and st.power == true and st.slots[st.txSlot] ~= nil
    local hot = tx.hotUntil > now
    local want = tx.ptt or hf or hot

    -- The server keeps one transmission per talker while anything holds it (PTT, hands-free,
    -- the emergency hot mic). It starts hands-free and the hot mic itself, so only the PTT
    -- edges are sent from here: releasing PTT never ends a transmission something else holds.
    if tx.ptt and not tx.sent then
        TriggerServerEvent('nzr:tx:start', tx.pttDevice or 'handheld')
        tx.sent = true
    elseif not tx.ptt and tx.sent then
        TriggerServerEvent('nzr:tx:stop')
        tx.sent = false
    end

    local device = tx.ptt and tx.pttDevice or (hot and tx.hotDevice) or 'handheld'
    if want and not tx.active then
        startLocal(device)
    elseif not want and tx.active then
        stopLocal()
    elseif want and tx.device ~= device then
        tx.device = device
        NZR.Radio.SetTx(true, device)
    end
end

local function deny(reason, device)
    if reason == 'dead' or reason == 'power' then return end
    sfx('error')
    NZR.Bus.Emit('radio:notice', reason, device)
end

function V.Ptt(down, device)
    device = device == 'vehicle' and 'vehicle' or 'handheld'
    if down then
        if tx.ptt then return true end
        local ok, reason = API().CanTalk(device)
        if not ok then
            deny(reason, device)
            return false
        end
        tx.ptt, tx.pttDevice = true, device
    else
        if not tx.ptt then return true end
        tx.ptt = false
    end
    V.Update()
    return true
end

function V.HotMic(device, ms)
    tx.hotUntil = GetGameTimer() + math.max(0, tonumber(ms) or 0)
    tx.hotDevice = device == 'vehicle' and 'vehicle' or 'handheld'
    V.Update()
end

function V.IsTalking()
    return tx.active
end

RegisterNetEvent('nzr:tx:targets', function(ids)
    local fresh = {}
    if type(ids) == 'table' then
        for _, id in pairs(ids) do
            id = tonumber(id)
            if id and id ~= me() then fresh[id] = true end
        end
    end
    for id in pairs(tx.targets) do
        if not fresh[id] and not isCallPartner(id) then MumbleRemoveVoiceTargetPlayerByServerId(VOICE_TARGET, id) end
    end
    tx.targets = fresh
    -- a list that lands after the key was released must not open a channel to anyone
    if tx.active then addTargets() else removeTargets() end
end)

RegisterNetEvent('nzr:tx:denied', function(reason)
    local device = tx.device or tx.pttDevice or 'handheld'
    tx.ptt, tx.sent, tx.hotUntil = false, false, 0
    if reason == 'cooldown' then S().emergencyUntil = 0 end
    if S().handsfree then API().Handsfree(false) end
    stopLocal()
    deny(type(reason) == 'string' and reason or 'nosignal', device)
end)

-- ════════════════════════════════════════════════════════════════════════
-- RX
-- ════════════════════════════════════════════════════════════════════════

local function tierGain(q)
    local t = tierOf(q)
    if t == 'clear' then return 1.0 elseif t == 'weak' then return 0.92 elseif t == 'poor' then return 0.8 end
    return 0.0
end

local function sourcePos(info)
    if info.srcType == 'vehicle' then
        local veh = vehicleOfNet(info.src)
        if veh ~= 0 then return GetEntityCoords(veh), veh end
        return nil
    end
    local id = tonumber(info.src)
    if id then
        local ped = id == me() and PlayerPedId() or pedOfServerId(id)
        if ped ~= 0 and DoesEntityExist(ped) then return GetEntityCoords(ped), nil end
    end
    return nil
end

-- → volume override (nil = leave the talker alone), submix id (nil = none)
local function targetMix(talker, r, now, ped, myPos)
    local info = r.info
    local st = S()
    local q = tonumber(info.q) or 0.0
    local t = tiers()
    if q < t.poor then return nil, nil end
    -- mute is the handheld's: a car speaker or someone else's radio next to you still plays
    if st.muted and info.mode == 'radio' and not info.emergency then return 0.0, nil end

    -- close enough to hear in person (and not shut in another car): pma-voice has it
    local tped = pedOfServerId(talker)
    if tped ~= 0 and DoesEntityExist(tped) then
        local d = #(GetEntityCoords(tped) - myPos)
        if d < ((Config.Audio and Config.Audio.nearSkip) or 4.0) then
            local tv, mv = GetVehiclePedIsIn(tped, false), GetVehiclePedIsIn(ped, false)
            if tv == mv or (tv == 0 and mv == 0) then return nil, nil end
        end
    end

    local vol, sub
    local mode = info.mode
    if mode == 'car' then
        local veh = info.srcType == 'vehicle' and vehicleOfNet(info.src) or 0
        if veh == 0 then veh = GetVehiclePedIsIn(ped, false) end
        local vr = veh ~= 0 and Entity(veh).state.nzr_vradio or nil
        if type(vr) == 'table' and vr.mute then return 0.0, nil end
        local v = type(vr) == 'table' and tonumber(vr.v) or 1.0
        vol = (Config.Vehicles.carVolume or 0.75) * v
        sub = V.Submix('speaker')
    elseif mode == 'leak' then
        local pos, veh = sourcePos(info)
        if not pos then return 0.0, nil end
        local radius = info.srcType == 'vehicle' and (Config.Leak.vehicle or 12.0) or (Config.Leak.handheld or 2.2)
        if radius <= 0 then return 0.0, nil end
        vol = (Config.Leak.volume or 0.55) * (1.0 - smoothstep(0.0, radius, #(myPos - pos)))
        if veh and doorsShut(veh) then vol = vol * (Config.Leak.doorsShut or 0.55) end
        sub = V.Submix('speaker')
    else
        vol = (st.volume or 60) / 100 * tierGain(q)
        sub = V.Submix(tierOf(q))
    end

    -- a weak link breaks up: short holes in the audio, more of them the weaker it is
    if q < t.weak then
        if now >= r.nextDrop then
            r.nextDrop = now + DROP_CHECK_MS
            if math.random() < (t.weak - q) / t.weak * 0.55 then
                r.dropUntil = now + math.random(60, 220)
            end
        end
        if now < r.dropUntil then vol = 0.0 end
    end
    return math.max(0.0, math.min(1.0, vol)), sub
end

local function apply(talker, r, vol, sub)
    if vol == nil then
        if r.vol ~= nil then
            MumbleSetVolumeOverrideByServerId(talker, -1.0)
            r.vol = nil
        end
    elseif r.vol == nil or math.abs(r.vol - vol) > 0.01 then
        MumbleSetVolumeOverrideByServerId(talker, vol + 0.0)
        r.vol = vol
    end
    if sub ~= r.sub then
        MumbleSetSubmixForServerId(talker, sub or -1)
        r.sub = sub
    end
end

local function restore(talker, r)
    if isCallPartner(talker) then
        -- pma-voice runs the call: give the volume back, leave its submix alone
        MumbleSetVolumeOverrideByServerId(talker, callVolume() + 0.0)
        return
    end
    MumbleSetVolumeOverrideByServerId(talker, -1.0)
    if r.sub ~= nil then MumbleSetSubmixForServerId(talker, -1) end
end

local function audible(info)
    return not S().muted or info.mode ~= 'radio' or info.emergency == true
end

local function pushRxStatus()
    local active, worst = 0, 1.0
    for _, r in pairs(rx) do
        if audible(r.info) then
            active = active + 1
            worst = math.min(worst, tonumber(r.info.q) or 0.0)
        end
    end
    local msg
    if active == 0 then
        msg = { active = 0, worstQ = 1.0, lost = false, gain = 0.0 }
    else
        worst = math.floor(worst * 100 + 0.5) / 100
        local hiss = (Config.Audio and Config.Audio.hiss) or 0.35
        msg = { active = active, worstQ = worst, lost = worst < tiers().poor,
            gain = math.floor((1.0 - worst) ^ 1.6 * hiss * 1000 + 0.5) / 1000 }
    end
    local sig = ('%d|%.2f|%s|%.3f'):format(msg.active, msg.worstQ, tostring(msg.lost), msg.gain)
    if sig == lastRxMsg then return end
    lastRxMsg = sig
    NZR.UI.Send('_core', 'rx', msg)
end

local function mixAll()
    local ped = PlayerPedId()
    local myPos = GetEntityCoords(ped)
    local now = GetGameTimer()
    local fast = false
    local weak = tiers().weak
    for talker, r in pairs(rx) do
        local vol, sub = targetMix(talker, r, now, ped, myPos)
        apply(talker, r, vol, sub)
        if (tonumber(r.info.q) or 0) < weak then fast = true end
    end
    return fast
end

local function startRxLoop()
    if rxLoop then return end
    rxLoop = true
    CreateThread(function()
        while next(rx) ~= nil do
            local fast = mixAll()
            Wait(fast and RX_TICK_FAST_MS or RX_TICK_MS)
        end
        rxLoop = false
        pushRxStatus()
    end)
end

local function publishRx()
    local st = S()
    local out = {}
    for talker, r in pairs(rx) do out[talker] = r.info end
    st.rx = out
    NZR.Radio.Changed('rx')
end

local function cleanInfo(talker, info)
    info = type(info) == 'table' and info or {}
    local out = {}
    for k, v in pairs(info) do out[k] = v end
    out.talker = talker
    out.q = math.max(0.0, math.min(1.0, tonumber(info.q) or 0.0))
    out.fkey = info.fkey and NZR.Freq.Key(info.fkey) or nil
    out.mode = (info.mode == 'car' or info.mode == 'leak') and info.mode or 'radio'
    return out
end

local function soundVolume(info)
    if info.mode == 'leak' then return (Config.Leak.volume or 0.55) * 0.6 end
    if info.mode == 'car' then return Config.Vehicles.carVolume or 0.75 end
    return nil
end

RegisterNetEvent('nzr:rx:start', function(talker, info)
    talker = tonumber(talker)
    if not talker or talker == me() then return end
    info = cleanInfo(talker, info)
    local old = rx[talker]
    info.at = old and old.info.at or GetGameTimer()
    rx[talker] = { info = info, vol = old and old.vol, sub = old and old.sub, dropUntil = 0, nextDrop = 0 }
    if not old and audible(info) and clicksOn() then
        local v = soundVolume(info)
        sfx('rx_start', v and { volume = v } or nil)
    end
    mixAll()
    publishRx()
    pushRxStatus()
    startRxLoop()
    NZR.Bus.Emit('radio:rx', talker, info, old and 'update' or 'start')
end)

RegisterNetEvent('nzr:rx:update', function(talker, info)
    talker = tonumber(talker)
    local r = talker and rx[talker]
    if not r then
        if talker then TriggerEvent('nzr:rx:start', talker, info) end
        return
    end
    local fresh = cleanInfo(talker, info)
    fresh.at = r.info.at
    r.info = fresh
    publishRx()
    pushRxStatus()
    NZR.Bus.Emit('radio:rx', talker, fresh, 'update')
end)

local function stopRx(talker, q, quiet)
    local r = rx[talker]
    if not r then return end
    rx[talker] = nil
    restore(talker, r)
    if not quiet and audible(r.info) then
        q = tonumber(q) or tonumber(r.info.q) or 1.0
        local v = soundVolume(r.info)
        if Config.Audio and Config.Audio.squelch ~= false then sfx('squelch', { q = q, volume = v }) end
        if clicksOn() then sfx('rx_end', v and { volume = v } or nil) end
    end
    NZR.Bus.Emit('radio:rx', talker, r.info, 'stop')
end

RegisterNetEvent('nzr:rx:stop', function(talker, q)
    talker = tonumber(talker)
    if not talker then return end
    stopRx(talker, q, false)
    publishRx()
    pushRxStatus()
end)

RegisterNetEvent('nzr:rx:shots', function(talker, shots, q)
    if type(shots) ~= 'table' then return end
    local r = rx[tonumber(talker) or -1]
    if r and not audible(r.info) then return end
    NZR.UI.Send('_core', 'gunfire', { shots = shots, q = tonumber(q) or 1.0, volume = (S().volume or 60) / 100 })
end)

function V.Rx()
    return rx
end

function V.ClearRx()
    if next(rx) == nil then return end
    for talker in pairs(rx) do stopRx(talker, nil, true) end
    publishRx()
    pushRxStatus()
end

function V.StopAll()
    tx.ptt, tx.hotUntil = false, 0
    if tx.sent then
        TriggerServerEvent('nzr:tx:stop')
        tx.sent = false
    end
    stopLocal()
    V.ClearRx()
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE HOOKS
-- ════════════════════════════════════════════════════════════════════════

NZR.Bus.On('radio:power', function(on)
    if not on then
        tx.hotUntil = 0
        V.Update()
        V.ClearRx()
    end
end)

NZR.Bus.On('radio:changed', function(what)
    if what == 'handsfree' or what == 'record' or what == 'power' or what == 'txslot' or what == 'dropped' or what == 'reset' then
        V.Update()
        if what == 'dropped' or what == 'reset' then V.StopAll() end
    elseif what == 'raised' then
        if S().raised then
            -- the raised pose replaces the talk animation (interact.lua plays its own)
            tx.animToken = nil
        elseif tx.active then
            startTalkAnim()
        end
    elseif what == 'mute' then
        pushRxStatus()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    if tx.active or tx.sent then TriggerServerEvent('nzr:tx:stop') end
    tx.active = false
    for id in pairs(tx.targets) do
        if not isCallPartner(id) then MumbleRemoveVoiceTargetPlayerByServerId(VOICE_TARGET, id) end
    end
    tx.targets = {}
    stopTalkAnim()
    for talker, r in pairs(rx) do restore(talker, r) end
    rx = {}
end)
