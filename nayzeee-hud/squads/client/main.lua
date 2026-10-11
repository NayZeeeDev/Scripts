-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- nayzeee-squads · client core
Squad    = nil      -- private squad data from the server
Chat     = {}
MenuOpen = false
Settings = {}

local KVP = 'nz_squads_settings'
local currentChannel = 0
local Strings = SquadsConfig.Strings
local adminMode = false

function Me() return cache.serverId end

function NUI(action, data)
    SendNUIMessage({ action = action, data = data })
end

function Toast(title, text, kind)
    Bridge.Notify(title, text, kind or 'info')
end

-- toasts raised by the menu itself, when a non-built-in system is chosen
RegisterNUICallback('sq_notify', function(data, cb)
    cb(1)
    Bridge.Notify(data.title, data.text, data.kind, data.duration)
end)

function Can(perm)
    return Squad and Squad.you and Squad.you.perms and Squad.you.perms[perm] == true
end

-- ─── settings ──────────────────────────────────────────────
local function loadSettings()
    local saved = GetResourceKvpString(KVP)
    local data = saved and json.decode(saved) or {}
    for k, v in pairs(SquadsConfig.DefaultSettings) do
        if data[k] == nil then data[k] = v end
    end
    Settings = data
end

local function saveSettings()
    SetResourceKvp(KVP, json.encode(Settings))
end

local function hexOf(r, g, b) return ('#%02x%02x%02x'):format(r, g, b) end

-- ─── voice ─────────────────────────────────────────────────
local radioSet, prevChannel = false, nil

--- The squad's radio channel. Temp squads use their own range so ids never collide.
local function squadChannel(sq)
    if sq.temporary then
        -- temporary squad ids sit in a very high range, so fold them into a small block
        return SquadsConfig.Voice.TempChannelBase + (sq.id % 1000)
    end
    return SquadsConfig.Voice.ChannelBase + sq.id
end

--- Puts the player on (or off) their squad's radio channel.
--- Auto-join can be forced on by the server, or left to each player's setting.
function ApplyRadio()
    local V = SquadsConfig.Voice
    if not V.Enabled or not SquadsConfig.Features.AutoRadio then return end
    if GetResourceState('pma-voice') ~= 'started' then return end

    local wants = Squad ~= nil and (V.AutoJoin and (not V.PlayerCanOptOut or Settings.radio))

    if wants then
        local target = squadChannel(Squad)
        if radioSet and currentChannel == target then return end
        if not radioSet then prevChannel = LocalPlayer.state.radioChannel or 0 end
        exports['pma-voice']:setRadioChannel(target)
        currentChannel = target
        radioSet = true
    elseif radioSet then
        -- hand them back whatever channel they were on before the squad took over
        local back = (V.RestoreOnLeave and prevChannel) or 0
        exports['pma-voice']:setRadioChannel(back)
        currentChannel, radioSet, prevChannel = back, false, nil
    end
end

-- ─── menu ──────────────────────────────────────────────────
local function openMenu(view)
    if MenuOpen or IsPauseMenuActive() or NHUD.focus then return end
    MenuOpen = true
    SquadsFocus(true, true)
    TriggerServerEvent('nz_squads:menuState', true)
    NUI('open', { squad = Squad, view = view })
    local list, invites, status = lib.callback.await('nz_squads:getList', false)
    NUI('list', { list = list or {}, invites = invites or {}, status = status })
end

local function closeMenu()
    if not MenuOpen then return end
    MenuOpen = false
    adminMode = false
    SquadsFocus(false, false)
    TriggerServerEvent('nz_squads:menuState', false)
    NUI('close')
end

RegisterCommand(SquadsConfig.Command, function() openMenu() end, false)
if SquadsConfig.OpenKey ~= '' then
    RegisterKeyMapping(SquadsConfig.Command, 'Open squads', 'keyboard', SquadsConfig.OpenKey)
end

RegisterNetEvent('nz_squads:openAdmin', function()
    adminMode = true
    NUI('adminUnlock', true)
    openMenu('admin')
end)

-- ─── NUI callbacks ─────────────────────────────────────────
RegisterNUICallback('sq_ready', function(_, cb)
    local pings = {}
    for key, def in pairs(SquadsConfig.Ping.Types) do
        pings[key] = { label = def.label, icon = def.icon, color = hexOf(def.color[1], def.color[2], def.color[3]) }
    end
    local permLabels = {}
    for i = 1, #SquadsConfig.RankPermOrder do
        local p = SquadsConfig.RankPermOrder[i]
        permLabels[#permLabels + 1] = { key = p.key, label = p.label }
    end
    cb({
        me = Me(),
        settings = Settings,
        squad = Squad,
        chat = Chat,
        config = {
            version = SquadsConfig.Version, maxMembers = SquadsConfig.MaxMembers, minMembers = SquadsConfig.MinMembers,
            nameMin = SquadsConfig.NameMin, nameMax = SquadsConfig.NameMax, tagMin = SquadsConfig.TagMin, tagMax = SquadsConfig.TagMax,
            chatMax = SquadsConfig.ChatMaxLength, maxRanks = SquadsConfig.MaxRanks, rankIcons = SquadsConfig.RankIcons,
            perms = permLabels, blipColors = SquadsConfig.BlipColors, tagColors = SquadsConfig.TagColors,
            pings = pings, wheel = SquadsConfig.Ping.Wheel, features = SquadsConfig.Features,
            voice = SquadsConfig.Voice.Enabled, defaults = SquadsConfig.DefaultSettings,
            tiers = SquadsConfig.Elo.Tiers, eloStart = SquadsConfig.Elo.Start,
            squadTypes = {
                temporary = SquadsConfig.SquadTypes.AllowTemporary,
                permanent = SquadsConfig.SquadTypes.AllowPermanent,
                default = SquadsConfig.SquadTypes.Default,
                tempHours = SquadsConfig.SquadTypes.TempMaxHours,
            },
            blipSprites = SquadsConfig.SquadBlip.Sprites,
            allyMax = SquadsConfig.Affiliations.MaxPerSquad,
            allyShareChat = SquadsConfig.Affiliations.ShareChat,
            nametag = SquadsConfig.Nametag,
            notify = Bridge.NotifySystem(),
            compass = SquadsConfig.Compass and SquadsConfig.Compass.Enabled or false,
            nicknames = { enabled = SquadsConfig.Nicknames.Enabled, max = SquadsConfig.Nicknames.MaxLength,
                          min = SquadsConfig.Nicknames.MinLength, temp = SquadsConfig.Nicknames.AllowInTemporary },
            autoRadio = SquadsConfig.Voice.AutoJoin and SquadsConfig.Voice.PlayerCanOptOut,
            weaponImages = Config and Config.WeaponImages or false,
            bleedOut = SquadsConfig.Revive.BleedOut or 0,
        },
    })
end)

RegisterNUICallback('sq_close', function(_, cb) closeMenu(); cb(1) end)

local function proxy(name, event, argsFn)
    RegisterNUICallback('sq_' .. name, function(data, cb)
        local ok, msg = lib.callback.await(event, false, argsFn(data or {}))
        cb({ ok = ok == true, msg = msg })
    end)
end

proxy('create',   'nz_squads:create',   function(d) return d end)
proxy('edit',     'nz_squads:edit',     function(d) return d end)
proxy('setRanks', 'nz_squads:setRanks', function(d) return d.ranks end)
proxy('disband',  'nz_squads:disband',  function() return nil end)
proxy('invite',   'nz_squads:invite',   function(d) return d.id end)
proxy('chat',     'nz_squads:chat',     function(d) return d.text end)
proxy('declineInvite', 'nz_squads:declineInvite', function(d) return d.id end)
proxy('readyCheck', 'nz_squads:readyCheck', function() return nil end)
proxy('allyRequest', 'nz_squads:allyRequest', function(d) return d.id end)
proxy('allyRemove',  'nz_squads:allyRemove',  function(d) return d.id end)

RegisterNUICallback('sq_allyRespond', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:allyRespond', false, data.id, data.accept == true)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_leave', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:leave', false, data and data.forget)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_kick', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:kick', false, data.identifier)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_setNick', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:setNick', false, data.nick, data.identifier)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_setRank', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:setRank', false, data.identifier, data.rank)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_transfer', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:transfer', false, data.identifier)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_join', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:join', false, data.id, data.password)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_checkName', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:checkName', false, data.name)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_refresh', function(_, cb)
    local list, invites, status = lib.callback.await('nz_squads:getList', false)
    cb({ list = list or {}, invites = invites or {}, status = status })
end)

RegisterNUICallback('sq_stats', function(_, cb)
    cb(lib.callback.await('nz_squads:stats', false) or { members = {}, active = {}, history = {} })
end)

RegisterNUICallback('sq_leaderboard', function(_, cb)
    cb(lib.callback.await('nz_squads:leaderboard', false) or { squads = {}, players = {}, persistent = false })
end)

RegisterNUICallback('sq_readyAnswer', function(data, cb)
    cb(1)
    lib.callback.await('nz_squads:readyAnswer', false, data.answer == true)
end)

RegisterNUICallback('sq_adminList', function(_, cb)
    cb(lib.callback.await('nz_squads:admin:list', false) or {})
end)

RegisterNUICallback('sq_adminAction', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:admin:action', false, data.action, data.squadId, data.target, data.value)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('sq_saveSettings', function(data, cb)
    local prev = Settings
    local next = {}
    for k, v in pairs(SquadsConfig.DefaultSettings) do
        if data[k] ~= nil then next[k] = data[k] else next[k] = prev[k] end
    end
    Settings = next
    saveSettings()
    TriggerEvent('nz_squads:client:settings', prev, Settings)
    if prev.radio ~= Settings.radio then ApplyRadio() end
    if prev.hudAccent ~= Settings.hudAccent or prev.hudStyle ~= Settings.hudStyle then
        NUI('squad', Squad)
    end
    NUI('settings', Settings) -- nayzeee-hud: settings are edited from /hud, keep the squads frame in sync
    cb(1)
end)

RegisterNUICallback('sq_shareWaypoint', function(_, cb)
    cb(1)
    if not Squad then return end
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return Toast('Waypoint', Strings.no_waypoint, 'error') end
    local c = GetBlipInfoIdCoord(blip)
    local z = GetHeightmapTopZForPosition(c.x, c.y)
    TriggerServerEvent('nz_squads:ping', { type = 'waypoint', x = c.x, y = c.y, z = z })
end)

RegisterNUICallback('sq_rally', function(data, cb)
    if data and data.clear then
        cb({ ok = lib.callback.await('nz_squads:rally', false, false) == true })
        return
    end
    local c = GetEntityCoords(cache.ped)
    local ok, msg = lib.callback.await('nz_squads:rally', false, { x = c.x, y = c.y, z = c.z })
    cb({ ok = ok == true, msg = msg })
end)

-- ─── server events ─────────────────────────────────────────
RegisterNetEvent('nz_squads:sync', function(data, reason)
    local prev = Squad
    Squad = data or nil
    if not Squad then
        Chat = {}
        if reason == 'closed' then Toast('Squad closed', Strings.closed, 'error') end
    end
    NUI('squad', Squad)
    TriggerEvent('nz_squads:client:changed', prev, Squad)
    if (prev and prev.id) ~= (Squad and Squad.id) then ApplyRadio() end
end)

RegisterNetEvent('nz_squads:history', function(history)
    Chat = history or {}
    NUI('chatHistory', Chat)
end)

RegisterNetEvent('nz_squads:chat', function(msg)
    Chat[#Chat + 1] = msg
    if #Chat > SquadsConfig.ChatHistory then table.remove(Chat, 1) end
    NUI('chat', { msg = msg, notify = Settings.chatNotify and msg.from ~= Me() })
    if Settings.chatNotify and not msg.system and msg.from ~= Me() then
        PlaySoundFrontend(-1, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET', true)
    end
end)

RegisterNetEvent('nz_squads:vitals', function(changed)
    if not Squad then return end
    Squad.vitals = Squad.vitals or {}
    for id, v in pairs(changed) do
        -- the server sends the weapon hash; the cards want its name (for the picture) and label
        if v.w ~= nil then v.w, v.wl = SquadWeapon(v.w) end
        -- vehicle model -> icon kind + name; false when on foot so the card drops it
        if v.vm ~= nil then v.vk, v.vn = SquadVehicle(v.vm) end
        Squad.vitals[id] = v
    end
    NUI('vitals', changed)
end)

RegisterNetEvent('nz_squads:downed', function(id, state)
    if not Squad then return end
    for i = 1, #Squad.members do
        if Squad.members[i].id == id then Squad.members[i].downed = state break end
    end
    NUI('downed', { id = id, state = state, since = 0 })
end)

RegisterNetEvent('nz_squads:invite', function(inv)
    NUI('invite', inv)
    Toast('Squad invite', ('%s invited you to %s. Open /%s to respond.'):format(inv.from, inv.name, SquadsConfig.Command), 'info')
    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
end)

RegisterNetEvent('nz_squads:list', function(list)
    if MenuOpen then NUI('listUpdate', list) end
end)

RegisterNetEvent('nz_squads:notify', function(text, kind)
    Toast('Squads', text, kind)
end)

RegisterNetEvent('nz_squads:killfeed', function(data)
    NUI('killfeed', data)
    if data.good then
        PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
    end
end)

RegisterNetEvent('nz_squads:matchResult', function(data)
    NUI('matchResult', data)
    PlaySoundFrontend(-1, data.result == 'win' and 'RANK_UP' or 'CHECKPOINT_MISSED', 'HUD_AWARDS', true)
end)

RegisterNetEvent('nz_squads:revived', function(data)
    NUI('revived', data)
end)

RegisterNetEvent('nz_squads:readyCheck', function(data)
    NUI('readyCheck', data)
    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
end)

RegisterNetEvent('nz_squads:readyResult', function(answers)
    NUI('readyResult', answers)
end)

-- ─── lifecycle ─────────────────────────────────────────────
loadSettings()

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('nz_squads:playerReady')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if MenuOpen then SquadsFocus(false, false) end
end)
