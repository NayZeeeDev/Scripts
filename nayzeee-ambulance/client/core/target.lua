--[[
    NAYZEEE AMBULANCE - Client core: patient targets & the interaction registry

    Targets (ARCHITECTURE §4.4) - how the client names a patient when talking to the server:
        { kind = 'player', sid = serverId }  |  { kind = 'npc', net = netId }

      NZA.Target.FromEntity(ent, any)  → target | nil  (ped of a player, NPC ped with an 'nza'
                                         state bag (any = true: every networked NPC), or a
                                         body bag prop whose state bag 'nzaBag' holds a target)
      NZA.Target.Entity(target)        → ped entity or 0 (also accepts an entity number)
      NZA.Target.State(entOrTarget)    → state bag summary (§4.3) or nil
      NZA.Target.Self()                → own target
      NZA.Target.IsSelf(target) / Same(a, b) / Key(target) / Distance(target)

    Interactions (§11) - ONE global registration through the Bridge for players, NPC peds
    and body bag props. Modules add options; this file rebuilds the bridge options from the
    registry (debounced) and filters every option at runtime by: own state (downed players
    see nothing unless opt.whileDown), self/player/npc/bag flags, permission (NZA.Perm),
    patient state (opt.states), distance (default 2.0 m) and opt.canInteract. Options are
    sorted by order.

      NZA.Interact.Add({ name, label, icon, order, perm, states, self, npc, player, bag,
                         distance, whileDown, description, faIcon,
                         canInteract = fn(entity, target, stateBag) → bool,
                         onSelect = fn(entity, target) })
      NZA.Interact.Remove(name)  NZA.Interact.Get(name)  NZA.Interact.All()
      NZA.Interact.Options(entity) → filtered, sorted options for that entity
      NZA.Interact.Open(entity?)   ox_lib context menu with the same options (self if nil)
      NZA.Interact.OpenNearby()    looks for the patient in front of you, else yourself

    onSelect always runs in its own thread, so it may await callbacks (NZA.Proc.Run etc.).
    Keybind: 'nza_interact' (ox_lib, unbound by default - players bind it in Settings → Key
    Bindings → FiveM). Command: Config.Commands.interact (default 'nzainteract', false = off).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Target = NZA.Target or {}
NZA.Interact = NZA.Interact or {}
local T = NZA.Target
local I = NZA.Interact

local CACHE_MS = 250
local DEFAULT_DISTANCE = 2.0
local BAG_SCAN_MS = 1500
local BAG_RANGE = 40.0

-- ════════════════════════════════════════════════════════════════════════
-- TARGETS
-- ════════════════════════════════════════════════════════════════════════

local function ownSid()
    return cache.serverId or GetPlayerServerId(PlayerId())
end

local function networked(ent)
    return NetworkGetEntityIsNetworked(ent)
end

local function bagTarget(ent)
    if not networked(ent) then return nil end
    local b = Entity(ent).state.nzaBag
    if type(b) ~= 'table' then return nil end
    if b.kind == 'player' and tonumber(b.sid) then return { kind = 'player', sid = tonumber(b.sid) } end
    if b.kind == 'npc' and tonumber(b.net) then return { kind = 'npc', net = tonumber(b.net) } end
    return nil
end

function T.Self()
    return { kind = 'player', sid = ownSid() }
end

function T.FromEntity(ent, any)
    if type(ent) ~= 'number' or ent == 0 or not DoesEntityExist(ent) then return nil end
    if IsEntityAPed(ent) then
        if IsPedAPlayer(ent) then
            if ent == PlayerPedId() then return T.Self() end
            local idx = NetworkGetPlayerIndexFromPed(ent)
            if not idx or idx == -1 then return nil end
            return { kind = 'player', sid = GetPlayerServerId(idx) }
        end
        if not networked(ent) then return nil end
        if not any and Entity(ent).state.nza == nil then return nil end
        return { kind = 'npc', net = NetworkGetNetworkIdFromEntity(ent) }
    end
    return bagTarget(ent)
end

function T.Entity(target)
    if type(target) == 'number' then
        return (target ~= 0 and DoesEntityExist(target)) and target or 0
    end
    if type(target) ~= 'table' then return 0 end
    if target.kind == 'player' then
        local sid = tonumber(target.sid)
        if not sid then return 0 end
        if sid == ownSid() then return PlayerPedId() end
        local idx = GetPlayerFromServerId(sid)
        if not idx or idx == -1 then return 0 end
        local ped = GetPlayerPed(idx)
        return (ped ~= 0 and DoesEntityExist(ped)) and ped or 0
    elseif target.kind == 'npc' then
        local net = tonumber(target.net)
        if not net or not NetworkDoesNetworkIdExist(net) then return 0 end
        local ent = NetworkGetEntityFromNetworkId(net)
        return (ent ~= 0 and DoesEntityExist(ent)) and ent or 0
    end
    return 0
end

function T.State(x)
    if type(x) == 'number' then
        local ent = x
        if ent == 0 or not DoesEntityExist(ent) then return nil end
        if IsEntityAPed(ent) then
            if IsPedAPlayer(ent) then
                if ent == PlayerPedId() then return LocalPlayer.state.nza end
                local idx = NetworkGetPlayerIndexFromPed(ent)
                if not idx or idx == -1 then return nil end
                return Player(GetPlayerServerId(idx)).state.nza
            end
            if not networked(ent) then return nil end
            return Entity(ent).state.nza
        end
        local t = bagTarget(ent)
        return t and T.State(t) or nil
    elseif type(x) == 'table' then
        if x.kind == 'player' then
            local sid = tonumber(x.sid)
            if not sid then return nil end
            if sid == ownSid() then return LocalPlayer.state.nza end
            return Player(sid).state.nza
        elseif x.kind == 'npc' then
            local ent = T.Entity(x)
            if ent == 0 then return nil end
            return Entity(ent).state.nza
        end
    end
    return nil
end

function T.IsSelf(target)
    return type(target) == 'table' and target.kind == 'player' and tonumber(target.sid) == ownSid()
end

function T.Key(target)
    if type(target) ~= 'table' then return nil end
    if target.kind == 'player' then return 'player:' .. tostring(target.sid) end
    if target.kind == 'npc' then return 'npc:' .. tostring(target.net) end
    return nil
end

function T.Same(a, b)
    local ka, kb = T.Key(a), T.Key(b)
    return ka ~= nil and ka == kb
end

function T.Distance(target)
    local ent = T.Entity(target)
    if ent == 0 then return math.huge end
    return #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ent))
end

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRY
-- ════════════════════════════════════════════════════════════════════════

local registry = {}
local sortedCache = nil
local rebuildToken = 0
local registered = { player = {}, ped = {} }
local bags = {}            -- [entity] = { names }
local bagOptionsCache = nil

local function normaliseStates(states)
    if type(states) ~= 'table' then return nil end
    local out = {}
    for k, v in pairs(states) do
        if type(k) == 'number' then out[v] = true elseif v then out[k] = true end
    end
    return out
end

local function sorted()
    if sortedCache then return sortedCache end
    local list = {}
    for _, opt in pairs(registry) do list[#list + 1] = opt end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    sortedCache = list
    return list
end

-- per-entity lookup cache: target systems call canInteract every frame for every option
local lookups = {}
local function lookup(entity)
    local now = GetGameTimer()
    local c = lookups[entity]
    if c and now - c.at < CACHE_MS then return c end
    c = { at = now, target = T.FromEntity(entity), state = T.State(entity) }
    lookups[entity] = c
    return c
end

local function selfDown()
    return NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive'
end

-- Guided care (Config.Care.guided): on other people the third eye only keeps the care
-- options (opt.guided, client/core/care.lua) and the moving / utility options listed in
-- NZA.Care.AlwaysShow. Every other option is still in 'More...' (I.Open(entity, true)).
local function guidedHidden(opt, entity, me)
    if opt.guided then return false end
    if entity == me then return false end
    if not IsEntityAPed(entity) then return false end      -- body bag props keep their options
    local C = Config.Care
    if type(C) ~= 'table' or C.guided == false then return false end
    -- only medics get the short version (civilians keep their few first-aid options)
    if not (NZA.Perm and NZA.Perm('assess')) then return false end
    local Care = NZA.Care
    if Care and Care.AlwaysShow and Care.AlwaysShow(opt.name) then return false end
    return true
end

local function allowed(opt, entity, distance, all)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if not opt.whileDown and selfDown() then return false end
    local me = PlayerPedId()
    if not all and guidedHidden(opt, entity, me) then return false end
    local isPed = IsEntityAPed(entity)
    if entity == me then
        if not opt.self then return false end
    elseif not isPed then
        if not opt.bag then return false end
    elseif IsPedAPlayer(entity) then
        if opt.player == false then return false end
    else
        if opt.npc == false then return false end
    end
    if opt.perm and not NZA.Perm(opt.perm) then return false end
    local info = lookup(entity)
    if not info.target then return false end
    local st = (type(info.state) == 'table' and info.state.st) or 'alive'
    if opt.states and not opt.states[st] then return false end
    if distance == nil and entity ~= me then
        distance = #(GetEntityCoords(me) - GetEntityCoords(entity))
    end
    if distance and distance > (opt.distance or DEFAULT_DISTANCE) + 0.05 then return false end
    if opt.canInteract then
        local ok, res = pcall(opt.canInteract, entity, info.target, info.state)
        if not ok then
            NZA.Debug('canInteract failed', opt.name, res)
            return false
        end
        if not res then return false end
    end
    return true
end

local function runSelect(opt, entity)
    if type(entity) == 'table' then entity = entity.entity end
    CreateThread(function()
        if not entity or not DoesEntityExist(entity) then return end
        local target = T.FromEntity(entity)
        if not target then return end
        lookups[entity] = nil
        local ok, err = pcall(opt.onSelect, entity, target)
        if not ok then NZA.Warn(('interaction "%s" failed: %s'):format(opt.name, tostring(err))) end
    end)
end

-- kind = 'player' | 'ped' | 'bag': which registration this copy belongs to. Some target
-- scripts also run global ped options on player peds; the kind check keeps each option
-- from showing twice on the same entity.
local function bridgeOption(opt, kind)
    return {
        name = opt.name,
        label = opt.label,
        icon = opt.icon,
        order = opt.order,
        distance = opt.distance or DEFAULT_DISTANCE,
        canInteract = function(entity, distance)
            if type(entity) == 'table' then entity = entity.entity end
            if not entity or entity == 0 then return false end
            if kind == 'ped' and IsEntityAPed(entity) and IsPedAPlayer(entity) then return false end
            if kind == 'player' and not (IsEntityAPed(entity) and IsPedAPlayer(entity)) then return false end
            return allowed(opt, entity, distance)
        end,
        onSelect = function(entity)
            runSelect(opt, entity)
        end,
    }
end

local function names(list)
    local out = {}
    for i = 1, #list do out[i] = list[i].name end
    return out
end

local function targetApi()
    return Bridge and Bridge.Target or nil
end

local function bagOptions()
    if bagOptionsCache then return bagOptionsCache end
    local list = {}
    for _, opt in ipairs(sorted()) do
        if opt.bag then list[#list + 1] = bridgeOption(opt, 'bag') end
    end
    bagOptionsCache = list
    return list
end

local function registerBag(entity)
    local api = targetApi()
    if not api or not api.Entity then return end
    local opts = bagOptions()
    if #opts == 0 then return end
    local ok = pcall(api.Entity, entity, opts)
    if ok then bags[entity] = names(opts) end
end

local function unregisterBag(entity)
    local api = targetApi()
    local list = bags[entity]
    bags[entity] = nil
    -- also when the prop is already gone: the bridge keeps a per-entity registry
    if api and api.RemoveEntity and list then
        pcall(api.RemoveEntity, entity, list)
    end
end

local function rebuild()
    local api = targetApi()
    if not api then
        NZA.Warn('Bridge.Target missing - patient interactions are only available through the interact menu')
        return
    end
    if #registered.player > 0 and api.RemovePlayer then pcall(api.RemovePlayer, registered.player) end
    if #registered.ped > 0 and api.RemovePed then pcall(api.RemovePed, registered.ped) end
    registered.player, registered.ped = {}, {}

    local playerOpts, pedOpts = {}, {}
    for _, opt in ipairs(sorted()) do
        if opt.player ~= false then playerOpts[#playerOpts + 1] = bridgeOption(opt, 'player') end
        if opt.npc ~= false then pedOpts[#pedOpts + 1] = bridgeOption(opt, 'ped') end
    end
    if #playerOpts > 0 and api.Player then
        local ok, err = pcall(api.Player, playerOpts)
        if ok then registered.player = names(playerOpts) else NZA.Warn('Bridge.Target.Player failed: ' .. tostring(err)) end
    end
    if #pedOpts > 0 and api.Ped then
        local ok, err = pcall(api.Ped, pedOpts)
        if ok then registered.ped = names(pedOpts) else NZA.Warn('Bridge.Target.Ped failed: ' .. tostring(err)) end
    end

    -- body bags carry their own per-entity registration
    bagOptionsCache = nil
    for entity in pairs(bags) do
        unregisterBag(entity)
        if DoesEntityExist(entity) then registerBag(entity) end
    end
end

local function scheduleRebuild()
    sortedCache = nil
    bagOptionsCache = nil
    rebuildToken = rebuildToken + 1
    local token = rebuildToken
    SetTimeout(300, function()
        if token ~= rebuildToken then return end
        rebuild()
    end)
end

function I.Add(opt)
    if type(opt) ~= 'table' or type(opt.name) ~= 'string' or type(opt.onSelect) ~= 'function' then
        NZA.Warn('NZA.Interact.Add needs { name = string, onSelect = function }')
        return false
    end
    opt.order = tonumber(opt.order) or 50
    opt.label = opt.label or opt.name
    opt.states = normaliseStates(opt.states)
    registry[opt.name] = opt
    scheduleRebuild()
    return true
end

function I.Remove(name)
    if registry[name] == nil then return false end
    registry[name] = nil
    scheduleRebuild()
    return true
end

function I.Get(name)
    return registry[name]
end

function I.All()
    return sorted()
end

-- all = true: every option that applies, also the ones guided care keeps off the third eye
function I.Options(entity, all)
    local out = {}
    if not entity or entity == 0 or not DoesEntityExist(entity) then return out end
    local me = PlayerPedId()
    local dist = entity == me and 0.0 or #(GetEntityCoords(me) - GetEntityCoords(entity))
    lookups[entity] = nil
    for _, opt in ipairs(sorted()) do
        if allowed(opt, entity, dist, all) then out[#out + 1] = opt end
    end
    return out
end

-- one option's rules for one entity (all = ignore guided care), and running it like a target click
function I.Allowed(opt, entity, all)
    if type(opt) == 'string' then opt = registry[opt] end
    if type(opt) ~= 'table' then return false end
    return allowed(opt, entity, nil, all)
end

function I.Run(opt, entity)
    if type(opt) == 'string' then opt = registry[opt] end
    if type(opt) ~= 'table' or not opt.onSelect then return false end
    runSelect(opt, entity)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- CONTEXT MENU (keyboard users, self-treatment)
-- ════════════════════════════════════════════════════════════════════════

local function menuTitle(entity)
    if entity == PlayerPedId() then return NZA.L('core_client.interact.self') end
    local st = T.State(entity)
    if type(st) == 'table' and st.name then return st.name end
    if IsEntityAPed(entity) and IsPedAPlayer(entity) then
        local idx = NetworkGetPlayerIndexFromPed(entity)
        if idx and idx ~= -1 then return GetPlayerName(idx) end
    end
    return NZA.L('core_client.interact.patient')
end

-- ox_lib wants a Font Awesome name ('heart-pulse'); the bridge maps NAYZEEE icon names
local function faName(opt)
    if opt.faIcon then return opt.faIcon end
    local icon = opt.icon
    if type(icon) ~= 'string' or icon == '' then return nil end
    if Bridge and Bridge.FaIcon then
        local ok, cls = pcall(Bridge.FaIcon, icon)
        if ok and type(cls) == 'string' then
            return cls:match('fa%-([%w%-]+)$') or icon
        end
    end
    return icon
end

function I.Open(entity, all)
    entity = entity or PlayerPedId()
    local list = I.Options(entity, all)
    if #list == 0 then
        NZA.UI.Toast({ type = 'info', message = NZA.L('core_client.interact.none') })
        return false
    end
    local options = {}
    for i, opt in ipairs(list) do
        options[i] = {
            title = opt.label,
            description = opt.description,
            icon = faName(opt),
            onSelect = function() runSelect(opt, entity) end,
        }
    end
    lib.registerContext({ id = 'nza_interact', title = all and NZA.L('core_client.interact.more_title', menuTitle(entity)) or menuTitle(entity), options = options })
    lib.showContext('nza_interact')
    return true
end

local function patientInFront()
    local me = PlayerPedId()
    local hit, ent = lib.raycast.cam(1 | 2 | 4 | 8 | 16, 4, 4.0)
    if hit and ent and ent ~= 0 and ent ~= me and DoesEntityExist(ent) and T.FromEntity(ent) then
        return ent
    end
    local coords = GetEntityCoords(me)
    local best, bestDist = nil, 2.5
    local _, playerPed, playerCoords = lib.getClosestPlayer(coords, 2.5, false)
    if playerPed and playerPed ~= 0 then
        local d = #(coords - playerCoords)
        if d < bestDist then best, bestDist = playerPed, d end
    end
    local ped, pedCoords = lib.getClosestPed(coords, 2.5)
    if ped and ped ~= 0 and T.FromEntity(ped) then
        local d = #(coords - pedCoords)
        if d < bestDist then best, bestDist = ped, d end
    end
    return best
end

function I.OpenNearby()
    if lib.getOpenContextMenu and lib.getOpenContextMenu() == 'nza_interact' then
        lib.hideContext(false)
        return
    end
    local ent = patientInFront()
    if ent and #I.Options(ent) > 0 then return I.Open(ent) end
    return I.Open(PlayerPedId())
end

lib.addKeybind({
    name = 'nza_interact',
    description = NZA.L('core_client.interact.keybind'),
    defaultKey = '',
    onPressed = function()
        if IsPauseMenuActive() or IsNuiFocused() then return end
        I.OpenNearby()
    end,
})

do
    local cmd = Config.Commands and Config.Commands.interact
    if cmd == nil then cmd = 'nzainteract' end
    if cmd then
        RegisterCommand(cmd, function() I.OpenNearby() end, false)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- BODY BAG PROPS (per-entity registration while near)
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1000)
    while true do
        local anyBag = false
        for _, opt in pairs(registry) do
            if opt.bag then anyBag = true break end
        end
        local model = Config.Props and Config.Props.bodybag
        if anyBag and model then
            local hash = GetHashKey(model)
            local coords = GetEntityCoords(PlayerPedId())
            local seen = {}
            for _, obj in ipairs(GetGamePool('CObject')) do
                if GetEntityModel(obj) == hash and #(coords - GetEntityCoords(obj)) < BAG_RANGE then
                    seen[obj] = true
                    if not bags[obj] then registerBag(obj) end
                end
            end
            for obj in pairs(bags) do
                if not seen[obj] then unregisterBag(obj) end
            end
        end
        -- drop stale lookups
        local now = GetGameTimer()
        for ent, c in pairs(lookups) do
            if now - c.at > 5000 then lookups[ent] = nil end
        end
        Wait(BAG_SCAN_MS)
    end
end)

-- first registration once every module had the chance to add its options
CreateThread(function()
    Wait(1000)
    scheduleRebuild()
end)

-- permissions / own state changed: drop cached lookups so menus update at once
CreateThread(function()
    Wait(0)
    NZA.Bus.On('staff:changed', function() lookups = {} end)
    NZA.Bus.On('self:state', function() lookups = {} end)
end)
