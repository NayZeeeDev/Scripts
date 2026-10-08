--[[ Animation presets + scripted scenes used by heist actions ]]

Anim = {}

Anim.presets = {
    search    = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', flag = 1, duration = 5000, label = 'Searching...' },
    grab      = { dict = 'mp_take_money_mg', clip = 'stand_cash_in_bag_loop', flag = 1, duration = 4500, label = 'Grabbing...' },
    hack      = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', clip = 'base', flag = 49, duration = 2500, label = 'Connecting...',
                  prop = { model = 'prop_cs_tablet', bone = 60309, pos = vec3(0.03, 0.002, -0.0), rot = vec3(10.0, 160.0, 0.0) } },
    laptop    = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 1, duration = 3000, label = 'Booting exploit...' },
    keypad    = { dict = 'anim@heists@keypad@', clip = 'idle_a', flag = 1, duration = 2000, label = 'Wiring keypad...' },
    drill     = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle', flag = 1, duration = 3000, label = 'Drilling...',
                  prop = { model = 'hei_prop_heist_drill', bone = 57005, pos = vec3(0.14, 0.0, -0.01), rot = vec3(90.0, -90.0, 180.0) } },
    lockpick  = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49, duration = 2500, label = 'Picking lock...' },
    safecrack = { dict = 'mini@safe_cracking', clip = 'dial_turn_anti_fast_1', flag = 1, duration = 2500, label = 'Cracking...' },
    cut       = { dict = 'amb@world_human_welding@male@base', clip = 'base', flag = 1, duration = 8000, label = 'Cutting...',
                  prop = { model = 'prop_weld_torch', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) } },
    repair    = { dict = 'mini@repair', clip = 'fixing_a_player', flag = 1, duration = 6000, label = 'Sabotaging...' },
    rope      = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1, duration = 4000, label = 'Tying rope...' },
    pickup    = { dict = 'random@domestic', clip = 'pickup_low', flag = 0, duration = 1300, label = 'Picking up...' },
    plant     = { dict = 'weapons@projectile@sticky_bomb', clip = 'plant_vertical', flag = 0, duration = 1800, label = 'Planting...' },
    open      = { dict = 'mini@safe_cracking', clip = 'door_open_succeed_stand', flag = 0, duration = 1800, label = 'Opening...' },
}

function Anim.face(coords)
    local ped = cache.ped
    TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 800)
    Wait(800)
    ClearPedTasks(ped)
end

--- Runs a preset with the progress bar. `speed` (level perk) shortens it.
function Anim.run(name, opts)
    opts = opts or {}
    local p = Anim.presets[name] or Anim.presets.search
    local duration = math.floor((opts.duration or p.duration) / (opts.speed or 1.0))
    if opts.coords then Anim.face(opts.coords) end
    return UI.progress({
        label = opts.label or p.label,
        duration = duration,
        anim = { dict = p.dict, clip = p.clip, flag = p.flag },
        prop = p.prop,
        canCancel = opts.canCancel,
    })
end

local function ptfx(asset, name, coords, scale, looped, duration)
    lib.requestNamedPtfxAsset(asset, 5000)
    UseParticleFxAsset(asset)
    if looped then
        local fx = StartParticleFxLoopedAtCoord(name, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, scale or 1.0, false, false, false, false)
        SetTimeout(duration or 5000, function() StopParticleFxLooped(fx, false) end)
        return fx
    end
    StartParticleFxNonLoopedAtCoord(name, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, scale or 1.0, false, false, false)
end
Anim.ptfx = ptfx

--- Thermite: plant, burn for `burn` ms, cover eyes. Returns true when planted.
function Anim.thermite(coords, heading, burn)
    local ped = cache.ped
    Anim.face(coords)
    if not Anim.run('plant', { label = 'Placing thermite...', duration = 2500 }) then return false end
    local charge = Props.spawn('thermite_' .. GetGameTimer(), 'hei_prop_heist_thermite', coords, heading or GetEntityHeading(ped), { collision = false })
    PlaySoundFromCoord(-1, 'IDLE_BEEP', coords.x, coords.y, coords.z, 'EPSILONISM_04_SOUNDSET', false, 0, false)
    Wait(1200)
    ptfx('scr_ornate_heist', 'scr_heist_ornate_thermal_burn', coords + vec3(0.0, 0.0, 0.05), 1.0, true, burn or 9000)
    lib.requestAnimDict('anim@heists@ornate_bank@thermal_charge')
    TaskPlayAnim(ped, 'anim@heists@ornate_bank@thermal_charge', 'cover_eyes_loop', 3.0, 3.0, -1, 49, 0, false, false, false)
    Wait(burn or 9000)
    StopAnimTask(ped, 'anim@heists@ornate_bank@thermal_charge', 'cover_eyes_loop', 1.0)
    if charge and DoesEntityExist(charge) then DeleteEntity(charge) end
    return true
end

--- C4: plant, back off, boom. Damage scale 0 so nobody dies from the breach itself.
function Anim.c4(coords, fuse)
    if not Anim.run('plant', { coords = coords, label = 'Planting C4...' }) then return false end
    local bomb = Props.spawn('c4_' .. GetGameTimer(), 'prop_bomb_01', coords, GetEntityHeading(cache.ped), { collision = false })
    UI.notify(locale('c4_planted', math.floor((fuse or 6000) / 1000)), 'warning')
    local t = GetGameTimer()
    while GetGameTimer() - t < (fuse or 6000) do
        PlaySoundFromCoord(-1, 'Beep_Red', coords.x, coords.y, coords.z, 'DLC_HEIST_HACKING_SNAKE_SOUNDS', false, 0, false)
        Wait(800)
    end
    AddExplosion(coords.x, coords.y, coords.z, 2, 0.0, true, false, 1.0)
    if bomb and DoesEntityExist(bomb) then DeleteEntity(bomb) end
    return true
end

function Anim.hasSmashWeapon()
    local weapon = GetSelectedPedWeapon(cache.ped)
    if weapon == joaat('WEAPON_UNARMED') then return false end
    local group = GetWeapontypeGroup(weapon)
    for i = 1, #Config.Gameplay.smashWeapons do
        if group == joaat(Config.Gameplay.smashWeapons[i]) then return true end
    end
    return false
end

--- Smash a display case / register
function Anim.smash(coords, speed)
    local ped = cache.ped
    Anim.face(coords)
    lib.requestAnimDict('missheist_jewel')
    TaskPlayAnim(ped, 'missheist_jewel', 'smash_case', 8.0, -8.0, -1, 2, 0, false, false, false)
    Wait(math.floor(1800 / (speed or 1.0)))
    PlaySoundFromCoord(-1, 'Glass_Smash', coords.x, coords.y, coords.z, '', false, 0, false)
    ptfx('scr_jewelheist', 'scr_jewel_cab_smash', coords, 1.0)
    Wait(math.floor(2600 / (speed or 1.0)))
    ClearPedTasks(ped)
    return not IsEntityDead(ped)
end

--- Trolley: grab loop with a cash pile in hand, synced through ped tasks
function Anim.trolley(coords, kind, speed)
    Anim.face(coords)
    local hand = kind == 'gold' and 'hei_prop_heist_gold_bar' or (kind == 'diamond' and 'ch_prop_vault_dimaondbox_01a' or 'hei_prop_heist_cash_pile')
    return UI.progress({
        label = kind == 'gold' and 'Loading gold...' or (kind == 'diamond' and 'Bagging diamonds...' or 'Grabbing cash...'),
        duration = math.floor(14000 / (speed or 1.0)),
        anim = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab', flag = 1 },
        prop = { model = hand, bone = 60309, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
    })
end

--- Heist bag on the back while a heist runs
local bagApplied
function Anim.bag(state)
    local ped = cache.ped
    if state and not bagApplied then
        bagApplied = { GetPedDrawableVariation(ped, 5), GetPedTextureVariation(ped, 5) }
        SetPedComponentVariation(ped, 5, 45, 0, 0)
    elseif not state and bagApplied then
        SetPedComponentVariation(ped, 5, bagApplied[1], bagApplied[2], 0)
        bagApplied = nil
    end
end
