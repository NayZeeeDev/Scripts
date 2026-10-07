-- Snatching + The Clash (client side). Input happens in the NUI, the server decides.

Snatch = { busy = false, clash = nil, profile = {} }

local CS = Config.Snatch

function PlayAnim(a, duration, ped)
    if not a or not a.dict then return end
    ped = ped or PlayerPedId()
    if not pcall(lib.requestAnimDict, a.dict, 1500) then return end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, duration or a.duration or -1, a.flag or 0, 0.0, false, false, false)
    RemoveAnimDict(a.dict)
end

local function faceEntity(ped, target)
    local a, b = GetEntityCoords(ped), GetEntityCoords(target)
    SetEntityHeading(ped, GetHeadingFromVector_2d(b.x - a.x, b.y - a.y))
end

local function pedOf(serverId)
    local p = GetPlayerFromServerId(serverId)
    if p == -1 then return 0 end
    return GetPlayerPed(p)
end
Snatch.PedOf = pedOf

local function canTarget(entity)
    if Snatch.busy or NUI.app then return false end
    if not CS.AllowInVehicle and (IsPedInAnyVehicle(PlayerPedId(), false) or IsPedInAnyVehicle(entity, false)) then return false end
    local m = ModelKey(GetEntityModel(entity))
    if not m or not ModelEnabled(m) then return false end
    return not IsBaldDrawable(m, GetPedDrawableVariation(entity, 2))
end
Snatch.CanTarget = canTarget

function Snatch.Request(entity)
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    if Config.IsInNoSnatchZone(GetEntityCoords(PlayerPedId())) then return CB.Notify(L('no_zone'), 'error') end
    local left = (Snatch.profile.cooldownUntil or 0) - Snatch.ServerNow()
    if left > 0 then return CB.Notify(L('cooldown', left), 'error') end
    local idx = NetworkGetPlayerIndexFromPed(entity)
    if idx == -1 then return end
    TriggerServerEvent('nz-wig:s:snatch', GetPlayerServerId(idx))
end

-- closest player roughly in front of us
local function closestInFront(range)
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local fwd = GetEntityForwardVector(me)
    local best, bestD
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= me then
            local c = GetEntityCoords(ped)
            local d = #(c - mc)
            if d <= range then
                local dir = (c - mc) / math.max(d, 0.001)
                if (dir.x * fwd.x + dir.y * fwd.y) > 0.2 and (not bestD or d < bestD) then best, bestD = ped, d end
            end
        end
    end
    return best
end
Snatch.ClosestInFront = closestInFront

local function commandSnatch()
    local ped = closestInFront(CS.Distance)
    if not ped then return CB.Notify(L('no_one_close'), 'error') end
    if not canTarget(ped) then return CB.Notify(L('cant_snatch'), 'error') end
    Snatch.Request(ped)
end

if CS.Command then
    RegisterCommand(CS.Command, commandSnatch, false)
    if CS.Keybind then
        RegisterKeyMapping(CS.Command, 'Snatch a wig', 'keyboard', CS.Keybind)
    end
end

-- server time offset so cooldowns line up
local offset = 0
function Snatch.ServerNow() return math.floor(GetCloudTimeAsInt() + offset) end

RegisterNetEvent('nz-wig:c:profile', function(p)
    Snatch.profile = p
    offset = (p.now or GetCloudTimeAsInt()) - GetCloudTimeAsInt()
end)

-- the clash ------------------------------------------------------------------------------

local function startLoop(role)
    local a = role == 'snatcher' and Config.Anims.SnatcherPull or Config.Anims.VictimHold
    if not a then return end
    if not pcall(lib.requestAnimDict, a.dict, 1500) then return end
    TaskPlayAnim(PlayerPedId(), a.dict, a.clip, 4.0, -4.0, -1, (a.flag or 49) | 1, 0.0, false, false, false)
    RemoveAnimDict(a.dict)
end

RegisterNetEvent('nz-wig:c:clashStart', function(d)
    if Snatch.clash then return end
    Snatch.clash = d
    Snatch.busy = true
    NUI.CloseApp()

    local me = PlayerPedId()
    local opp = pedOf(d.oppSrc)
    if opp ~= 0 and DoesEntityExist(opp) then faceEntity(me, opp) end
    FreezeEntityPosition(me, true)
    startLoop(d.role)

    NUI.Send('clash:start', d)
    NUI.Keys(true)
end)

RegisterNUICallback('clashHit', function(_, cb)
    if Snatch.clash then TriggerServerEvent('nz-wig:s:clashHit', Snatch.clash.id) end
    cb(1)
end)

RegisterNetEvent('nz-wig:c:clashTick', function(p)
    if Snatch.clash then NUI.Send('clash:tick', p) end
end)

RegisterNetEvent('nz-wig:c:clashEnd', function(r)
    local me = PlayerPedId()
    Snatch.clash = nil
    NUI.Keys(false)
    NUI.Send('clash:end', r)
    FreezeEntityPosition(me, false)
    ClearPedSecondaryTask(me)
    Snatch.busy = false
    if r.cancelled then return end

    if r.role == 'snatcher' then
        if r.win then
            PlayAnim(Config.Anims.Snatch)
            SetTimeout((Config.Anims.Snatch.duration or 900), function()
                PlayAnim(Config.Anims.Celebrate)
            end)
            if r.reveal then
                SetTimeout(450, function() NUI.Send('reveal', r.reveal) end)
            end
        elseif (r.ragdoll or 0) > 0 then
            SetTimeout(250, function()
                SetPedToRagdoll(PlayerPedId(), r.ragdoll, r.ragdoll, 0, false, false, false)
            end)
        end
    else
        if not r.win then
            SetTimeout(700, function() PlayAnim(Config.Anims.Victim) end)
        end
    end
end)

-- effects + announcements ------------------------------------------------------------------

RegisterNetEvent('nz-wig:c:fx', function(victimSrc)
    local fx = Config.Effects.Particles
    if not fx then return end
    local ped = pedOf(victimSrc)
    if ped == 0 or not DoesEntityExist(ped) then return end
    SetTimeout(600, function()
        if not pcall(lib.requestNamedPtfxAsset, fx.asset, 1500) then return end
        UseParticleFxAsset(fx.asset)
        StartParticleFxNonLoopedOnPedBone(fx.name, ped, 0.0, 0.0, 0.12, 0.0, 0.0, 0.0, GetPedBoneIndex(ped, 31086), fx.scale or 0.6, false, false, false)
        RemoveNamedPtfxAsset(fx.asset)
    end)
end)

RegisterNetEvent('nz-wig:c:banner', function(payload)
    NUI.Send('banner', payload)
end)

RegisterNetEvent('nz-wig:c:bountyOnYou', function(total)
    NUI.Send('toast', { title = L('title'), message = L('bounty_broadcast', total, 'you'), kind = 'warning', duration = 7000 })
end)

RegisterNetEvent('nz-wig:c:levelUp', function(level, title)
    NUI.Send('levelup', { level = level, title = title })
end)

-- target ---------------------------------------------------------------------------------

Snatch.TargetOptions = {
    {
        name = 'nzwig_snatch',
        label = CS.TargetLabel,
        icon = CS.TargetIcon,
        distance = CS.Distance,
        canInteract = canTarget,
        onSelect = function(entity) Snatch.Request(entity) end,
    },
}

function Snatch.Cleanup()
    if Snatch.clash then
        FreezeEntityPosition(PlayerPedId(), false)
        ClearPedSecondaryTask(PlayerPedId())
        Snatch.clash = nil
    end
end
