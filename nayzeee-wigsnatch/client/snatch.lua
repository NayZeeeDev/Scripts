-- Snatching + the minigames (client side). Input happens in the NUI, the server decides.

Snatch = { busy = false, clash = nil, profile = {} }

local CS = Config.Snatch

local function canTarget(entity)
    if Snatch.busy or NUI.app then return false end
    if not CS.AllowInVehicle and (IsPedInAnyVehicle(PlayerPedId(), false) or IsPedInAnyVehicle(entity, false)) then return false end
    local m = ModelKey(GetEntityModel(entity))
    if not m or not ModelEnabled(m) then return false end
    return not IsBaldDrawable(m, GetPedDrawableVariation(entity, 2))
end
Snatch.CanTarget = canTarget

local function canStealBack(entity)
    if Snatch.busy or NUI.app or not Config.StealBack.Enabled then return false end
    local sid = ServerIdOf(entity)
    for _, s in ipairs(Snatch.profile.stealBack or {}) do
        if s == sid then return true end
    end
    return false
end

-- server time offset so cooldowns line up
local offset = 0
function Snatch.ServerNow() return math.floor(GetCloudTimeAsInt() + offset) end

function Snatch.Request(entity)
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    if Config.IsInNoSnatchZone(GetEntityCoords(PlayerPedId())) then return CB.Notify(L('no_zone'), 'error') end
    local left = (Snatch.profile.cooldownUntil or 0) - Snatch.ServerNow()
    if left > 0 then return CB.Notify(L('cooldown', left), 'error') end
    local sid = ServerIdOf(entity)
    if sid then TriggerServerEvent('nz-wig:s:snatch', sid) end
end

local function commandSnatch()
    local ped = ClosestInFront(CS.Distance)
    if not ped then return CB.Notify(L('no_one_close'), 'error') end
    if not canTarget(ped) and not canStealBack(ped) then return CB.Notify(L('cant_snatch'), 'error') end
    Snatch.Request(ped)
end

if CS.Command then
    RegisterCommand(CS.Command, commandSnatch, false)
    if CS.Keybind then
        RegisterKeyMapping(CS.Command, 'Snatch a wig', 'keyboard', CS.Keybind)
    end
end

RegisterNetEvent('nz-wig:c:profile', function(p)
    Snatch.profile = p
    offset = (p.now or GetCloudTimeAsInt()) - GetCloudTimeAsInt()
end)

-- the minigame -------------------------------------------------------------------------------

local function startLoop(role)
    LoopAnim(role == 'snatcher' and Config.Anims.SnatcherPull or Config.Anims.VictimHold)
end

RegisterNetEvent('nz-wig:c:clashStart', function(d)
    if Snatch.clash then return end
    Snatch.clash = d
    Snatch.busy = true
    NUI.CloseApp()

    local me = PlayerPedId()
    local opp = PedOf(d.oppSrc)
    if opp ~= 0 and DoesEntityExist(opp) then FaceEntity(me, opp) end
    if not LocalPlayer.state[ST.held] and not LocalPlayer.state[ST.tied] then
        FreezeEntityPosition(me, true)
        startLoop(d.role)
    end

    NUI.Send('clash:start', d)
    NUI.Keys(true)
end)

RegisterNUICallback('clashHit', function(d, cb)
    if Snatch.clash then TriggerServerEvent('nz-wig:s:clashHit', Snatch.clash.id, d and d.token) end
    cb(1)
end)

RegisterNetEvent('nz-wig:c:clashTick', function(p)
    if Snatch.clash then NUI.Send('clash:tick', p) end
end)

RegisterNetEvent('nz-wig:c:clashSeq', function(s)
    if Snatch.clash then NUI.Send('clash:seq', s) end
end)

RegisterNetEvent('nz-wig:c:clashEnd', function(r)
    local me = PlayerPedId()
    local was = Snatch.clash
    Snatch.clash = nil
    NUI.Keys(false)
    NUI.Send('clash:end', r)
    if not LocalPlayer.state[ST.held] and not LocalPlayer.state[ST.tied] then
        FreezeEntityPosition(me, false)
        ClearPedSecondaryTask(me)
    end
    Snatch.busy = false
    if r.cancelled then return end

    if r.role == 'snatcher' then
        if r.win then
            PlayAnim(Config.Anims.Snatch)
            Reaction('snatcher_win', Config.Anims.Snatch.duration or 900)
            if r.reveal then
                SetTimeout(450, function() NUI.Send('reveal', r.reveal) end)
            end
        elseif (r.ragdoll or 0) > 0 and was then
            SetTimeout(250, function()
                SetPedToRagdoll(PlayerPedId(), r.ragdoll, r.ragdoll, 0, false, false, false)
            end)
        else
            Reaction('snatcher_lose', 300)
        end
    end
end)

-- effects + announcements ------------------------------------------------------------------

RegisterNetEvent('nz-wig:c:fx', function(victimSrc)
    local p = Config.Effects.Particles
    if not p then return end
    local ped = PedOf(victimSrc)
    if ped == 0 or not DoesEntityExist(ped) then return end
    SetTimeout(600, function()
        if not pcall(lib.requestNamedPtfxAsset, p.asset, 1500) then return end
        UseParticleFxAssetNextCall(p.asset)
        StartParticleFxNonLoopedOnPedBone(p.name, ped, 0.0, 0.0, 0.12, 0.0, 0.0, 0.0, GetPedBoneIndex(ped, 31086), p.scale or 0.6, false, false, false)
        RemoveNamedPtfxAsset(p.asset)
    end)
end)

RegisterNetEvent('nz-wig:c:banner', function(payload)
    local pref = Prefs.Get('banners')
    if pref == 'none' or (pref == 'city' and not payload.city) then return end
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
        canInteract = function(e) return canTarget(e) and not canStealBack(e) end,
        onSelect = function(entity) Snatch.Request(entity) end,
    },
}
if Config.StealBack.Enabled then
    Snatch.TargetOptions[#Snatch.TargetOptions + 1] = {
        name = 'nzwig_stealback',
        label = Config.StealBack.Label,
        icon = Config.StealBack.Icon,
        distance = CS.Distance,
        canInteract = canStealBack,
        onSelect = function(entity) Snatch.Request(entity) end,
    }
end

function Snatch.Cleanup()
    if Snatch.clash then
        FreezeEntityPosition(PlayerPedId(), false)
        ClearPedSecondaryTask(PlayerPedId())
        Snatch.clash = nil
    end
end
