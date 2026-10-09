-- held props are LOCAL-ONLY (isNetwork=false) so anti-cheat can never delete them
local function heldProp(model, bone, offset, rot)
    if not IsModelInCdimage(model) then
        print('[nayzeee-bodybag] invalid prop model, skipping held prop')
        return nil
    end
    LoadModel(model)
    local c = GetEntityCoords(cache.ped)
    local obj = CreateObject(model, c.x, c.y, c.z, false, false, false)
    AttachEntityToEntity(obj, cache.ped, GetPedBoneIndex(cache.ped, bone or 28422),
        offset and offset.x or 0.0, offset and offset.y or 0.0, offset and offset.z or 0.0,
        rot and rot.x or 0.0, rot and rot.y or 0.0, rot and rot.z or 0.0,
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

-- long actions use the circle so they look different from quick ones
local function progressCircle(label, duration)
    return lib.progressCircle({
        duration = duration, label = label, position = 'bottom', useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
end

local function cleanup(prop)
    ClearPedTasks(cache.ped)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end

-- ═══════════════════════════════════════════════════════════════
--  DISMEMBERMENT
-- ═══════════════════════════════════════════════════════════════
function DismemberBody(victimPed)
    if IsBusy() then return end
    local victimId = ServerIdOfPed(victimPed)
    if not victimId then return end

    local hasPower = HasItem(Config.Items.powersaw)
    local tool = hasPower and Config.Dismember.Powersaw or Config.Dismember.Woodsaw
    local sawModel = hasPower and Config.Props.powersawProp or Config.Props.woodsawProp

    local alert = lib.alertDialog({
        header = 'Dismember Body',
        content = ('This is **permanent** for the body. Using: %s (%.0fs)\n\nBlood evidence will be left at the scene.')
            :format(hasPower and 'Power Saw' or 'Wood Saw', tool.Duration / 1000),
        centered = true, cancel = true,
    })
    if alert ~= 'confirm' then return end

    local saw = heldProp(sawModel, tool.PropOffset.Bone, tool.PropOffset.Offset, tool.PropOffset.Rot)
    PlayAnim(tool.Anim.Dict, tool.Anim.Clip, tool.Anim.Flag)
    local ok = progressCircle('Cutting up the body...', tool.Duration)
    cleanup(saw)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:dismember', victimId, hasPower) end
end

-- blood decal drawn on EVERY client so cops actually find the scene
RegisterNetEvent('nayzeee-bodybag:client:bloodDecal', function(coords)
    local cfg = Config.Dismember.Blood
    local found, gz = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    local z = found and gz or (coords.z - 0.98)
    AddDecal(cfg.DecalType or 1010, coords.x, coords.y, z + 0.03, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0,
        cfg.Size, cfg.Size, 0.294, 0.0, 0.0, 0.9, cfg.Duration, false, false, false)
end)

-- ═══════════════════════════════════════════════════════════════
--  BURN BARREL
-- ═══════════════════════════════════════════════════════════════
function LoadBarrel(barrelEnt)
    if IsBusy() or Carrying.kind ~= 'bodybag' then return end
    local bagNetId = Carrying.netId
    if not Progress('Loading body into barrel...', Config.LoadTime) then return end
    if lib.callback.await('nayzeee-bodybag:barrelLoad', false, NetOf(barrelEnt), bagNetId) then
        StopCarrying(false, true)
    else
        Config.Notify('Couldn\'t load it - get closer', 'error')
    end
end

function UnloadBarrel(barrelEnt)
    if IsBusy() then return end
    if not Progress('Pulling the body out...', Config.LoadTime) then return end
    TriggerServerEvent('nayzeee-bodybag:server:barrelUnload', NetOf(barrelEnt))
end

function LightBarrel(barrelEnt)
    if IsBusy() then return end
    PlayAnim('anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_crouch_checkingleaves_idle_01_inspector', 1)
    local ok = Progress('Striking the match...', 4000)
    ClearPedTasks(cache.ped)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:barrelLight', NetOf(barrelEnt)) end
end

-- the flames are a particle effect on every client; only the player who lit it
-- starts a real (synced) script fire, so there's one fire instead of one per player
local activeFires = {}
RegisterNetEvent('nayzeee-bodybag:client:barrelFire', function(netId, start, lighter)
    local ent = EntFromNet(netId)
    if start then
        if not ent then return end
        local c = GetEntityCoords(ent)
        lib.requestNamedPtfxAsset('core')
        UseParticleFxAssetNextCall('core')
        local fx = StartParticleFxLoopedOnEntity('fire_wrecked_train', ent, 0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.6, false, false, false)
        local fire = (lighter == cache.serverId) and StartScriptFire(c.x, c.y, c.z + 0.8, 1, false) or nil
        activeFires[netId] = { fx = fx, fire = fire }
    else
        local f = activeFires[netId]
        activeFires[netId] = nil
        if f then
            if f.fx then StopParticleFxLooped(f.fx, false) end
            if f.fire then RemoveScriptFire(f.fire) end
        end
        if ent then
            local c = GetEntityCoords(ent)
            StopFireInRange(c.x, c.y, c.z, 3.0)
            RemoveParticleFxFromEntity(ent)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  ACID DISSOLVE
-- ═══════════════════════════════════════════════════════════════
function AcidDissolve(bagEnt)
    if IsBusy() then return end
    local netId = NetOf(bagEnt)
    -- mask must actually be WORN, not just sitting in your inventory
    local hasMask = IsMaskOn()
    local requiresMask = Config.Acid.RequiresGasmask ~= false

    if requiresMask and hasMask then
        Config.Notify('Your gas mask filters out the toxic fumes.', 'inform')
    elseif requiresMask then
        local alert = lib.alertDialog({
            header = 'No Gas Mask On',
            content = HasItem(Config.Items.gasmask)
                and 'You have a gas mask but you\'re **not wearing it**. Use the item to put it on first.\n\nPour anyway and breathe the fumes?'
                or 'The fumes from hydrochloric acid are **toxic**. You will take damage without a gas mask.\n\nContinue anyway?',
            centered = true, cancel = true,
        })
        if alert ~= 'confirm' then return end
    end

    local can = heldProp(Config.Props.acidProp, 28422, vec3(0.1, 0.02, -0.03), vec3(65.0, 90.0, 0.0))
    PlayAnim('weapon@w_sp_jerrycan', 'fire', 49)

    local pouring = true
    if requiresMask and not hasMask then
        CreateThread(function()
            while pouring do
                Wait(Config.Acid.NoMaskDamageTick or 5000)
                -- the mask can be put on mid-pour from the inventory
                if pouring and not IsMaskOn() then
                    -- SetEntityHealth is reliable even where ApplyDamageToPed no-ops
                    local hp = GetEntityHealth(cache.ped)
                    SetEntityHealth(cache.ped, math.max(0, hp - (Config.Acid.NoMaskDamage or 25)))
                    Config.Notify('The fumes burn your lungs!', 'error')
                end
            end
        end)
    end

    local ok = progressCircle('Dissolving the body...', Config.Acid.DissolveTime)
    pouring = false
    cleanup(can)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:acidDissolve', netId) end
end

-- ═══════════════════════════════════════════════════════════════
--  BURIAL
-- ═══════════════════════════════════════════════════════════════
local function isBlocked(coords)
    for _, zone in ipairs(Config.Burial.BlockedZones) do
        if #(coords - zone.coords) < zone.radius then return true end
    end
    return false
end

function BuryContainer(containerEnt)
    if IsBusy() then return end
    local c = GetEntityCoords(containerEnt)
    if isBlocked(c) then return Config.Notify('You can\'t dig here', 'error') end

    local cem = Config.Burial.Cemetery
    local inCemetery = cem.Enabled and #(c - cem.Coords) < cem.Radius

    local shovel = heldProp(Config.Props.shovelProp, 28422, vec3(0.0, 0.0, 0.24), vec3(0.0, 0.0, 200.0))
    PlayAnim('random@burial', 'a_burial', 1)
    local ok = progressCircle(inCemetery and 'Digging a proper grave...' or 'Digging a shallow grave...', Config.Burial.DigTime)
    cleanup(shovel)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:bury', NetOf(containerEnt)) end
end

function InspectGrave(graveEnt)
    local g = Entity(graveEnt).state.nzGrave
    if not g then return end
    lib.registerContext({
        id = 'nz_grave', title = g.cemetery and 'Grave' or 'Disturbed Earth',
        options = {
            { title = g.cemetery and (g.name or 'Unknown') or 'Freshly dug soil...',
              description = g.cemetery and ('Rest in peace • %s'):format(g.date or '') or 'Someone buried something here.',
              icon = g.cemetery and 'cross' or 'trowel' },
        },
    })
    lib.showContext('nz_grave')
end

function ExhumeGrave(graveEnt)
    if IsBusy() then return end
    local shovel = heldProp(Config.Props.shovelProp, 28422, vec3(0.0, 0.0, 0.24), vec3(0.0, 0.0, 200.0))
    PlayAnim('random@burial', 'a_burial', 1)
    local ok = progressCircle('Exhuming the grave...', Config.Burial.ExhumeTime)
    cleanup(shovel)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:exhume', NetOf(graveEnt)) end
end

-- ═══════════════════════════════════════════════════════════════
--  DECOMPOSITION SMELL
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:client:smell', function()
    Config.Notify(Config.Decomposition.SmellNotify, 'inform')
end)

-- ═══════════════════════════════════════════════════════════════
--  POLICE ALERTS - notify + a rough search-area blip
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:client:policeAlert', function(coords, title, message)
    local cfg = Config.Dispatch
    Config.Notify(message, 'warning', title)
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)

    -- offset the circle so it's a search area, not the exact spot
    local r = math.floor((cfg.BlipRadius or 80.0) * 0.5)
    local x, y = coords.x + math.random(-r, r), coords.y + math.random(-r, r)

    local area = AddBlipForRadius(x, y, coords.z, cfg.BlipRadius or 80.0)
    SetBlipColour(area, cfg.BlipColour or 1)
    SetBlipAlpha(area, 90)

    local icon = AddBlipForCoord(x, y, coords.z)
    SetBlipSprite(icon, cfg.BlipSprite or 161)
    SetBlipColour(icon, cfg.BlipColour or 1)
    SetBlipScale(icon, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(title)
    EndTextCommandSetBlipName(icon)

    SetTimeout((cfg.BlipTime or 120) * 1000, function()
        RemoveBlip(area)
        RemoveBlip(icon)
    end)
end)
