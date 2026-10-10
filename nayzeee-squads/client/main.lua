-- nayzeee-squads · client core
Squad    = nil      -- private squad data from the server
Chat     = {}
MenuOpen = false
Settings = {}

local KVP = 'nz_squads_settings'
local Strings = Config.Strings
local N = Config.Notify
local adminMode = false
local Profile = nil

function Me() return cache.serverId end

function NUI(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- ─── notifications (ox_lib only) ───────────────────────────
--- kind: 'inform' | 'success' | 'error' | 'warning'. `force` ignores the player's quiet setting.
function Notify(text, kind, icon, force)
    if Settings.quiet and not force then return end
    lib.notify({
        title = N.Title, description = text, type = kind or 'inform',
        duration = N.Duration, position = N.Position,
        icon = (icon and (N.Icons[icon] or icon)) or N.Icon,
    })
end

function Can(perm)
    return Squad ~= nil and Squad.you ~= nil and Squad.you.perms ~= nil and Squad.you.perms[perm] == true
end

-- ─── settings ──────────────────────────────────────────────
local function loadSettings()
    local saved = GetResourceKvpString(KVP)
    local ok, data = pcall(json.decode, saved or '')
    data = (ok and type(data) == 'table') and data or {}
    for k, v in pairs(Config.DefaultSettings) do
        if data[k] == nil then data[k] = v end
    end
    Settings = data
end

local function saveSettings()
    SetResourceKvp(KVP, json.encode(Settings))
end

local function hexOf(r, g, b) return ('#%02x%02x%02x'):format(r, g, b) end

-- ─── voice ─────────────────────────────────────────────────
local radioSet, prevChannel, currentChannel = false, nil, 0

local function squadChannel(sq)
    if sq.temporary then return Config.Voice.TempChannelBase + (sq.id % 1000) end
    return Config.Voice.ChannelBase + sq.id
end

function ApplyRadio()
    local V = Config.Voice
    if not V.Enabled or not Config.Features.AutoRadio then return end
    if GetResourceState('pma-voice') ~= 'started' then return end

    local wants = Squad ~= nil and (V.AutoJoin and (not V.PlayerCanOptOut or Settings.radio))
    if wants then
        local target = squadChannel(Squad)
        if radioSet and currentChannel == target then return end
        if not radioSet then prevChannel = LocalPlayer.state.radioChannel or 0 end
        exports['pma-voice']:setRadioChannel(target)
        currentChannel, radioSet = target, true
    elseif radioSet then
        local back = (V.RestoreOnLeave and prevChannel) or 0
        exports['pma-voice']:setRadioChannel(back)
        currentChannel, radioSet, prevChannel = back, false, nil
    end
end

-- ─── menu ──────────────────────────────────────────────────
local function openMenu(view)
    if MenuOpen or IsPauseMenuActive() then return end
    MenuOpen = true
    SetNuiFocus(true, true)
    TriggerServerEvent('nz_squads:menuState', true)
    NUI('open', { squad = Squad, view = view })
    local list, invites, status, mine = lib.callback.await('nz_squads:getList', false)
    NUI('list', { list = list or {}, invites = invites or {}, status = status, myRequests = mine or {} })
    Profile = lib.callback.await('nz_squads:profile', false)
    if Profile then NUI('profile', Profile) end
end

local function closeMenu()
    if not MenuOpen then return end
    MenuOpen = false
    adminMode = false
    SetNuiFocus(false, false)
    TriggerServerEvent('nz_squads:menuState', false)
    NUI('close')
end
CloseMenu = closeMenu

RegisterCommand(Config.Command, function() openMenu() end, false)
if Config.OpenKey ~= '' then
    RegisterKeyMapping(Config.Command, 'Open squads', 'keyboard', Config.OpenKey)
end

RegisterNetEvent('nz_squads:openAdmin', function()
    adminMode = true
    NUI('adminUnlock', true)
    openMenu('admin')
end)

-- ─── NUI callbacks ─────────────────────────────────────────
RegisterNUICallback('ready', function(_, cb)
    local pings = {}
    for key, def in pairs(Config.Ping.Types) do
        pings[key] = { label = def.label, icon = def.icon, color = hexOf(def.color[1], def.color[2], def.color[3]) }
    end
    local permLabels = {}
    for i = 1, #Config.RankPermOrder do
        permLabels[#permLabels + 1] = { key = Config.RankPermOrder[i].key, label = Config.RankPermOrder[i].label }
    end
    local blipHex = {}
    for id, hex in pairs(Config.BlipHex) do blipHex[tostring(id)] = hex end
    cb({
        me = Me(),
        settings = Settings,
        squad = Squad,
        chat = Chat,
        config = {
            version = Config.Version, maxMembers = Config.MaxMembers, minMembers = Config.MinMembers,
            nameMin = Config.NameMin, nameMax = Config.NameMax, tagMin = Config.TagMin, tagMax = Config.TagMax,
            descriptionMax = Config.DescriptionMax, motdMax = Config.MotdMax,
            chatMax = Config.ChatMaxLength, maxRanks = Config.MaxRanks, rankIcons = Config.RankIcons,
            perms = permLabels, tagColors = Config.TagColors, blipHex = blipHex, squadBlipColors = Config.SquadBlipColors,
            pings = pings, wheel = Config.Ping.Wheel, features = Config.Features,
            voice = Config.Voice.Enabled, defaults = Config.DefaultSettings,
            tiers = Config.Elo.Tiers, eloStart = Config.Elo.Start,
            squadTypes = {
                temporary = Config.SquadTypes.AllowTemporary, permanent = Config.SquadTypes.AllowPermanent,
                default = Config.SquadTypes.Default, tempHours = Config.SquadTypes.TempMaxHours,
            },
            blipSprites = Config.SquadBlip.Sprites,
            allyMax = Config.Affiliations.MaxPerSquad,
            nametag = Config.Nametag,
            compass = Config.Features.Compass,
            nicknames = { enabled = Config.Nicknames.Enabled, max = Config.Nicknames.MaxLength,
                          min = Config.Nicknames.MinLength, temp = Config.Nicknames.AllowInTemporary },
            requests = { enabled = Config.JoinRequests.Enabled, messageMax = Config.JoinRequests.MessageMax },
            autoRadio = Config.Voice.AutoJoin and Config.Voice.PlayerCanOptOut,
            prompts = { accept = Config.Prompts.AcceptKey, decline = Config.Prompts.DeclineKey },
            reviveKey = Config.Revive.Key,
            commands = Config.Commands,
            command = Config.Command,
        },
    })
end)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb(1) end)

local function proxy(name, event, argsFn)
    RegisterNUICallback(name, function(data, cb)
        local ok, msg = lib.callback.await(event, false, argsFn(data or {}))
        cb({ ok = ok == true, msg = msg })
    end)
end

proxy('create',        'nz_squads:create',        function(d) return d end)
proxy('edit',          'nz_squads:edit',          function(d) return d end)
proxy('setRanks',      'nz_squads:setRanks',      function(d) return d.ranks end)
proxy('disband',       'nz_squads:disband',       function() return nil end)
proxy('invite',        'nz_squads:invite',        function(d) return d.id end)
proxy('chat',          'nz_squads:chat',          function(d) return d.text end)
proxy('declineInvite', 'nz_squads:declineInvite', function(d) return d.id end)
proxy('readyCheck',    'nz_squads:readyCheck',    function() return nil end)
proxy('allyRequest',   'nz_squads:allyRequest',   function(d) return d.id end)
proxy('allyRemove',    'nz_squads:allyRemove',    function(d) return d.id end)
proxy('setMotd',       'nz_squads:setMotd',       function(d) return d.motd end)
proxy('kick',          'nz_squads:kick',          function(d) return d.identifier end)
proxy('transfer',      'nz_squads:transfer',      function(d) return d.identifier end)
proxy('cancelRequest', 'nz_squads:cancelRequest', function(d) return d.id end)

local function proxy2(name, event, a, b)
    RegisterNUICallback(name, function(data, cb)
        data = data or {}
        local ok, msg = lib.callback.await(event, false, data[a], data[b])
        cb({ ok = ok == true, msg = msg })
    end)
end

proxy2('allyRespond',    'nz_squads:allyRespond',    'id', 'accept')
proxy2('setNick',        'nz_squads:setNick',        'nick', 'identifier')
proxy2('setRank',        'nz_squads:setRank',        'identifier', 'rank')
proxy2('join',           'nz_squads:join',           'id', 'password')
proxy2('requestJoin',    'nz_squads:requestJoin',    'id', 'message')
proxy2('respondRequest', 'nz_squads:respondRequest', 'identifier', 'accept')

RegisterNUICallback('leave', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:leave', false, data and data.forget == true)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('checkName', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:checkName', false, data.name)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('refresh', function(_, cb)
    local list, invites, status, mine = lib.callback.await('nz_squads:getList', false)
    cb({ list = list or {}, invites = invites or {}, status = status, myRequests = mine or {} })
end)

RegisterNUICallback('stats', function(_, cb)
    cb(lib.callback.await('nz_squads:stats', false) or { members = {}, active = {}, history = {} })
end)

RegisterNUICallback('leaderboard', function(_, cb)
    cb(lib.callback.await('nz_squads:leaderboard', false) or { squads = {}, players = {}, persistent = false })
end)

RegisterNUICallback('readyAnswer', function(data, cb)
    cb(1)
    AnswerReady(data and data.answer == true)
end)

RegisterNUICallback('adminList', function(_, cb)
    cb(lib.callback.await('nz_squads:admin:list', false) or {})
end)

RegisterNUICallback('adminAction', function(data, cb)
    local ok, msg = lib.callback.await('nz_squads:admin:action', false, data.action, data.squadId, data.target, data.value)
    cb({ ok = ok == true, msg = msg })
end)

RegisterNUICallback('notify', function(data, cb)
    cb(1)
    if data and data.text then Notify(data.text, data.kind, data.icon, true) end
end)

RegisterNUICallback('saveSettings', function(data, cb)
    local prev = Settings
    local nextS = {}
    for k, v in pairs(Config.DefaultSettings) do
        if data[k] ~= nil then nextS[k] = data[k] else nextS[k] = prev[k] end
    end
    Settings = nextS
    saveSettings()
    TriggerEvent('nz_squads:client:settings', prev, Settings)
    if prev.radio ~= Settings.radio then ApplyRadio() end
    cb(1)
end)

RegisterNUICallback('shareWaypoint', function(_, cb)
    cb(1)
    if not Squad then return end
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return Notify(Strings.no_waypoint, 'error', 'ping', true) end
    local c = GetBlipInfoIdCoord(blip)
    local z = GetHeightmapTopZForPosition(c.x, c.y)
    TriggerServerEvent('nz_squads:ping', { type = 'waypoint', x = c.x, y = c.y, z = z })
end)

RegisterNUICallback('rally', function(data, cb)
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
        if reason == 'closed' then Notify(Strings.closed, 'error', nil, true) end
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
    if #Chat > Config.ChatHistory then table.remove(Chat, 1) end
    NUI('chat', msg)
    if msg.system or msg.from == Me() then return end
    if Settings.chatNotify and not MenuOpen then Notify(('%s: %s'):format(msg.name, msg.text), 'inform', 'chat') end
    if Settings.chatSound and not Settings.quiet then PlaySoundFrontend(-1, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET', true) end
end)

RegisterNetEvent('nz_squads:vitals', function(changed)
    if not Squad then return end
    Squad.vitals = Squad.vitals or {}
    for id, v in pairs(changed) do Squad.vitals[id] = v end
    NUI('vitals', changed)
end)

RegisterNetEvent('nz_squads:downed', function(id, state)
    if not Squad then return end
    for i = 1, #Squad.members do
        if Squad.members[i].id == id then Squad.members[i].downed = state break end
    end
    NUI('downed', { id = id, state = state })
end)

RegisterNetEvent('nz_squads:list', function(list)
    if MenuOpen then NUI('listUpdate', list) end
end)

RegisterNetEvent('nz_squads:requestNotify', function(text)
    if Settings.requestNotify then Notify(text, 'inform', 'request') end
end)

RegisterNetEvent('nz_squads:killfeed', function(data)
    if not Settings.killfeed then return end
    NUI('killfeed', data)
    if data.good and not Settings.quiet then PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true) end
end)

RegisterNetEvent('nz_squads:matchResult', function(data)
    if not Settings.matchBanner then return end
    NUI('matchResult', data)
    if not Settings.quiet then PlaySoundFrontend(-1, data.result == 'win' and 'RANK_UP' or 'CHECKPOINT_MISSED', 'HUD_AWARDS', true) end
end)

-- ─── lifecycle ─────────────────────────────────────────────
loadSettings()

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('nz_squads:playerReady')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if MenuOpen then SetNuiFocus(false, false) end
end)
