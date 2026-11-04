--[[
    NAYZEEE AMBULANCE - Crutches (client)

    Anyone with Config.Items.crutches can walk on crutches: use the item, the keybind 'nza_crutches'
    (Config.Splint.Crutches.key, unbound by default) or the command Config.Splint.Crutches.command.
    The server owns the on/off state (player state bag 'nzaCrutch'); this file
      - plays the crutch walk on the local player: NZA.Self.SetMoveOverride('crutch', Crutches.clipset), GTA's
        cane walk (client/core/self.lua keeps the clipset loaded and puts it back if something resets it),
        walk only, no sprint / jump / weapons (Crutches.blockControls), optional upper-body loop,
      - puts Config.Props.crutch in the hand of EVERY player whose bag says 'nzaCrutch' (local props, within
        Config.Splint.Props.range, hidden in vehicles). Crutches.count = 1: right hand (the hand the cane walk
        plants), 2: both hands. Crutches.hold:
          'follow'  attached to the ped and re-placed every frame: the grip stays on the hand bone
                    (Crutches.follow[side].bone + grip) and the crutch stays upright, leaning towards
                    follow[side].tip (ped axes), so it is held and moves with the walk whatever the
                    bone axes of the ped are
          'attach'  attached to the hand bone with Crutches.attach[side].pos / rot (rigid, classic)
      - fit tool (command Crutches.fitCommand, default /crutchfit, anyone on crutches): nudges the local
        crutch with the keyboard, shows the values on the crutch card, copies / prints to F8 the config line
        to paste into config/modules/splint.lua. The fitted values stay on that client until a restart.
      - adds the medic option nza_crutches_give 'Give crutches' (NZA.Treat 'crutches_give'),
      - feeds the crutch card (NZA.Splint.HudSet 'crutch': moving, steps, the leg to keep off the ground).
    Net event handled: nza:splint:crutch (on, silent)
    Callback used: nza:splint:crutch:toggle
    Lua API: NZA.Splint.CrutchesOn() → bool, NZA.Splint.ToggleCrutches(), NZA.Splint.CrutchFit(want|nil)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Splint = NZA.Splint or {}
local SP = NZA.Splint

local function C(section)
    local c = Config.Splint or {}
    return c[section] or {}
end

local function CR() return C('Crutches') end

local function L(key, ...)
    return NZA.L('splint.' .. key, ...)
end

local function toast(key, kind, ...)
    NZA.UI.Toast({ title = L('crutches'), message = L(key, ...), type = kind or 'info' })
end

local on = false
local gen = 0
local UNARMED = joaat('WEAPON_UNARMED')
local fit = nil          -- fit tool session (local player only), see FIT TOOL
local override = nil     -- { mode, right, left }: fitted values for the local player's crutch

function SP.CrutchesOn()
    return on
end

local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

-- ════════════════════════════════════════════════════════════════════════
-- HOLD SETTINGS
-- ════════════════════════════════════════════════════════════════════════

-- used when a config line is missing (an older config file): same values as the shipped config
local DEFAULT = {
    follow = {
        right = { bone = 28422, grip = vector3(0.0, 0.0, 0.0), tip = vector3(0.34, 0.14, -0.99), rot = vector3(0.0, 0.0, 0.0) },
        left  = { bone = 60309, grip = vector3(0.0, 0.0, 0.0), tip = vector3(-0.34, 0.14, -0.99), rot = vector3(0.0, 0.0, 0.0) },
    },
    attach = {
        right = { bone = 28422, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) },
        left  = { bone = 60309, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) },
    },
}
local FIELDS = { follow = { 'grip', 'tip', 'rot' }, attach = { 'pos', 'rot' } }
local SIDES_1, SIDES_2 = { 'right' }, { 'right', 'left' }

local function holdMode()
    return CR().hold == 'attach' and 'attach' or 'follow'
end

local function sideList()
    return (tonumber(CR().count) or 1) >= 2 and SIDES_2 or SIDES_1
end

local function swingOf()
    local s = tonumber(CR().swing)
    return s and clamp(s, 0.0, 1.0) or 0.5
end

local cfgCache = {}

-- the configured settings of one crutch, gaps filled from DEFAULT
local function configured(mode, side)
    local key = mode .. side
    if cfgCache[key] then return cfgCache[key] end
    local d = DEFAULT[mode][side]
    local t = CR()[mode]
    local s = type(t) == 'table' and type(t[side]) == 'table' and t[side] or {}
    local out = { bone = math.tointeger(tonumber(s.bone)) or d.bone }
    for _, f in ipairs(FIELDS[mode]) do out[f] = NZA.Util.vec(s[f]) or d[f] end
    cfgCache[key] = out
    return out
end

-- settings for a crutch; mine = the local player's (the fit tool's values win there)
local function settings(side, mine)
    local mode = holdMode()
    if mine and override and override.mode == mode and override[side] then return override[side] end
    return configured(mode, side)
end

-- ════════════════════════════════════════════════════════════════════════
-- PLACING THE CRUTCH
-- ════════════════════════════════════════════════════════════════════════

-- 'follow': grip on the hand bone, crutch upright and leaning towards its tip. Ped axes (bone 0 = the
-- ped itself): +X right, +Y forward, +Z up. The crutch's origin is the centre of its grip, its tube runs
-- down -Z (tip 0.86 m below the grip) and the grip points +Y.
local function followPose(ped, obj, s, swing)
    local hw = GetPedBoneCoords(ped, s.bone, 0.0, 0.0, 0.0)
    local h = GetOffsetFromEntityGivenWorldCoords(ped, hw.x, hw.y, hw.z)
    local gx, gy, gz = h.x + s.grip.x, h.y + s.grip.y, h.z + s.grip.z
    -- the tip aims at its spot; with swing it follows part of the hand's movement instead
    local dx = (s.tip.x - gx) * (1.0 - swing)
    local dy = (s.tip.y - gy) * (1.0 - swing)
    local dz = math.min(s.tip.z - gz, -0.25)
    -- +pitch (X) swings the tip forward, -roll (Y) swings it out to +X
    local pitch = clamp(math.deg(math.atan(dy, -dz)), -40.0, 40.0)
    local roll = clamp(-math.deg(math.atan(dx, math.sqrt(dy * dy + dz * dz))), -40.0, 40.0)
    AttachEntityToEntity(obj, ped, 0, gx, gy, gz, pitch + s.rot.x, roll + s.rot.y, s.rot.z,
        false, false, false, true, 2, true)
end

-- 'attach': fixed on the hand bone
local function attachPose(ped, obj, s)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, s.bone), s.pos.x, s.pos.y, s.pos.z, s.rot.x, s.rot.y, s.rot.z,
        false, false, false, true, 2, true)
end

-- ════════════════════════════════════════════════════════════════════════
-- LOCAL WALK
-- ════════════════════════════════════════════════════════════════════════

local walk = { dist = 0.0, side = nil, sideAt = 0, state = nil, moving = false }
local fitCard

-- the leg that should stay off the ground: a splinted leg, else a broken one ('l' | 'r' | nil)
local function injuredSide()
    local snap = NZA.Self.Get and NZA.Self.Get() or nil
    if type(snap) ~= 'table' then return nil end
    local function sideOf(region)
        if type(region) ~= 'string' or not region:find('_leg') then return nil end
        return region:sub(1, 1) == 'l' and 'l' or 'r'
    end
    local sp = type(snap.devices) == 'table' and snap.devices.splints or nil
    if type(sp) == 'table' then
        for k, v in pairs(sp) do
            local s = sideOf(type(k) == 'string' and k or v)
            if s then return s end
        end
    end
    for _, inj in ipairs(type(snap.injuries) == 'table' and snap.injuries or {}) do
        if inj.type == 'fracture' then
            local s = sideOf(inj.region)
            if s then return s end
        end
    end
    return nil
end

local function hud(state, moving)
    walk.state, walk.moving = state, moving == true
    if not SP.HudSet then return end
    if not state or (CR().hud == false and not fit) then SP.HudSet('crutch', nil) return end
    local key = CR().command and ('/' .. CR().command) or nil
    local now = GetGameTimer()
    if now > walk.sideAt then walk.side = injuredSide() walk.sideAt = now + 3000 end
    local sub = walk.side and L('hud_crutch_side_' .. walk.side) or state
    local card = {
        kind = 'crutch', title = L('hud_crutch'), sub = sub,
        state = state == L('hud_crutch_vehicle') and 'vehicle' or (moving and 'walk' or 'stand'),
        moving = moving == true, steps = math.floor(walk.dist / (tonumber(CR().stride) or 0.62)), side = walk.side,
        keys = key and { { keys = { key }, label = L('k_put_away') } } or {},
    }
    if fit and fitCard then
        local f = fitCard()
        card.title, card.sub, card.keys = f.title, f.sub, f.keys
    end
    SP.HudSet('crutch', card)
end

local function upperAnim(ped, play)
    local up = CR().upper
    if type(up) ~= 'table' or not up.dict then return end
    if play then
        if not IsEntityPlayingAnim(ped, up.dict, up.clip, 3) then
            NZA.Anim.Play(ped, up.dict, up.clip, { flag = 49 })
        end
    elseif IsEntityPlayingAnim(ped, up.dict, up.clip, 3) then
        StopAnimTask(ped, up.dict, up.clip, 2.0)
    end
end

local function startWalk()
    gen = gen + 1
    local my = gen
    NZA.Self.SetMoveOverride('crutch', CR().clipset or 'move_lester_CaneUp')
    walk.dist, walk.sideAt = 0.0, 0
    hud(L('hud_crutch_stand'), false)
    CreateThread(function()
        local blend = tonumber(CR().maxMoveBlend) or 1.0
        local rate = tonumber(CR().moveRate) or 0.86
        local block = CR().blockControls or {}
        local lastMoving = nil
        local nextHud = 0
        while on and gen == my do
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                SetPedMaxMoveBlendRatio(ped, blend)
                SetPedMoveRateOverride(ped, rate)
                for i = 1, #block do DisableControlAction(0, block[i], true) end
                DisablePlayerFiring(PlayerId(), true)
                if GetSelectedPedWeapon(ped) ~= UNARMED then SetCurrentPedWeapon(ped, UNARMED, true) end
                local speed = GetEntitySpeed(ped)
                local moving = speed > 0.3
                if moving then walk.dist = walk.dist + speed * GetFrameTime() end
                local now = GetGameTimer()
                if moving ~= lastMoving or (moving and now > nextHud) then
                    if moving ~= lastMoving then upperAnim(ped, moving) end
                    lastMoving = moving
                    nextHud = now + 400
                    hud(moving and L('hud_crutch_walk') or L('hud_crutch_stand'), moving)
                end
            elseif lastMoving ~= 'veh' then
                lastMoving = 'veh'
                upperAnim(ped, false)
                hud(L('hud_crutch_vehicle'), false)
            end
            Wait(0)
        end
    end)
end

local fitStop

local function stopWalk()
    gen = gen + 1
    if fitStop then fitStop(true) end
    NZA.Self.SetMoveOverride('crutch', nil)
    upperAnim(PlayerPedId(), false)
    hud(nil)
end

RegisterNetEvent('nza:splint:crutch', function(state, silent)
    state = state == true
    if state == on then return end
    on = state
    if on then
        startWalk()
        if not silent then toast('crutches_on', 'success') end
    else
        stopWalk()
        if not silent then toast('crutches_off', 'info') end
    end
    SP.RefreshCrutches()
end)

function SP.ToggleCrutches()
    if CR().enabled ~= false then
        if IsNuiFocused() or IsPauseMenuActive() then return end
        local r = lib.callback.await('nza:splint:crutch:toggle', false)
        if type(r) == 'table' and r.ok == false and r.msg then
            NZA.UI.Toast({ title = L('crutches'), message = r.msg, type = 'error' })
        end
    end
end

if CR().enabled ~= false then
    if lib and lib.addKeybind then
        lib.addKeybind({
            name = 'nza_crutches',
            description = L('key_crutches'),
            defaultKey = CR().key or '',
            onPressed = function() CreateThread(SP.ToggleCrutches) end,
        })
    end
    if CR().command then
        RegisterCommand(CR().command, function() CreateThread(SP.ToggleCrutches) end, false)
        TriggerEvent('chat:addSuggestion', '/' .. CR().command, L('cmd_crutches_help'), {})
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CRUTCH PROPS ON EVERY PLAYER THAT USES THEM
-- ════════════════════════════════════════════════════════════════════════

local held = {}       -- [ped] = { mode, count, ents = { [side] = entity } }
local posing = false

local function drop(ped)
    local h = held[ped]
    if not h then return end
    for _, obj in pairs(h.ents) do NZA.Props.Delete(obj) end
    held[ped] = nil
end

-- every frame while a 'follow' crutch is out: keep each grip in its hand
local function poseLoop()
    if posing then return end
    posing = true
    CreateThread(function()
        while next(held) ~= nil and holdMode() == 'follow' do
            local me = PlayerPedId()
            local swing = swingOf()
            for ped, h in pairs(held) do
                if h.mode == 'follow' and DoesEntityExist(ped) then
                    for side, obj in pairs(h.ents) do
                        if DoesEntityExist(obj) then followPose(ped, obj, settings(side, ped == me), swing) end
                    end
                end
            end
            Wait(0)
        end
        posing = false
    end)
end

local function spawnOne(ped, side, mine)
    local mode = holdMode()
    local s = settings(side, mine)
    local att
    if mode == 'attach' then
        att = { entity = ped, bone = s.bone, pos = s.pos, rot = s.rot, collision = false }
    else
        att = { entity = ped, bone = 0, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0), collision = false }
    end
    local obj = NZA.Props.Spawn(CR().prop or 'crutch', { attach = att },
        { group = 'splint_crutch', network = false, collision = false, fallbackKey = 'crutch', timeout = 4000 })
    if not obj or obj == 0 then return nil end
    if mode == 'follow' then followPose(ped, obj, s, swingOf()) end
    return obj
end

local function attach(ped)
    local sides = sideList()
    local h = { mode = holdMode(), count = #sides, ents = {} }
    local mine = ped == PlayerPedId()
    for _, side in ipairs(sides) do
        h.ents[side] = spawnOne(ped, side, mine)
    end
    held[ped] = h
    if h.mode == 'follow' then poseLoop() end
end

local function stillGood(ped, h)
    if h.mode ~= holdMode() or h.count ~= #sideList() then return false end
    for _, obj in pairs(h.ents) do
        if not DoesEntityExist(obj) or not IsEntityAttachedToEntity(obj, ped) then return false end
    end
    return true
end

local function tick()
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local range = tonumber(C('Props').range) or 45.0
    local seen = {}
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        local ply = Player(GetPlayerServerId(pl))
        local using = ply and ply.state and ply.state.nzaCrutch == true
        if pl == PlayerId() then using = using or on end
        if using and DoesEntityExist(ped) and #(GetEntityCoords(ped) - mc) <= range
            and not (CR().hideInVehicle ~= false and IsPedInAnyVehicle(ped, false)) and not IsEntityDead(ped) then
            seen[ped] = true
            local h = held[ped]
            if h and not stillGood(ped, h) then
                drop(ped)
                h = nil
            end
            if not h then attach(ped) end
        end
    end
    for ped in pairs(held) do
        if not seen[ped] then drop(ped) end
    end
end

-- one pass at a time (spawning waits for the model); a refresh during a pass runs it again after
local ticking, again = false, false
local function runTick()
    if ticking then again = true return end
    ticking = true
    repeat
        again = false
        local ok, err = pcall(tick)
        if not ok then NZA.Debug('splint crutch props: ' .. tostring(err)) end
    until not again
    ticking = false
end

function SP.RefreshCrutches()
    if CR().enabled == false then return end
    CreateThread(function()
        Wait(50)    -- a state bag handler runs before the new value is readable
        runTick()
    end)
end

-- anyone starting / stopping crutches shows up at once; the slow pass catches range / vehicles
AddStateBagChangeHandler('nzaCrutch', nil, function(bagName)
    if type(bagName) == 'string' and bagName:find('^player:') then SP.RefreshCrutches() end
end)

CreateThread(function()
    while true do
        if CR().enabled ~= false then runTick() end
        Wait(1000)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- FIT TOOL (/crutchfit): line the crutch up in game, paste the line into the config
-- ════════════════════════════════════════════════════════════════════════

-- GTA control ids (keyboard defaults). Shift / Space / Tab are already blocked while on crutches.
local MOVE_KEYS = {
    { id = 174, axis = 'x', dir = -1 }, { id = 175, axis = 'x', dir = 1 },    -- arrow left / right
    { id = 172, axis = 'y', dir = 1 },  { id = 173, axis = 'y', dir = -1 },   -- arrow up / down
    { id = 10,  axis = 'z', dir = 1 },  { id = 11,  axis = 'z', dir = -1 },   -- page up / page down
}
local K_NEXT, K_FINE, K_SIDE, K_COPY, K_RESET, K_DONE = 22, 21, 37, 191, 214, 194   -- space shift tab enter delete backspace
local OTHER_KEYS = { K_NEXT, K_FINE, K_SIDE, K_COPY, K_RESET, K_DONE }
local STEP_POS, STEP_ROT = 0.005, 1.0     -- metres / degrees per press (Shift: a fifth, held over 1.2 s: x5)

local function num(v, digits)
    local p = 10 ^ digits
    v = math.floor(v * p + 0.5) / p
    if math.abs(v) < 0.5 / p then v = 0.0 end
    return v
end

local function fmt(v, rot)
    return rot and ('%.1f'):format(num(v, 1)) or ('%.3f'):format(num(v, 3))
end

local function vecText(v, rot)
    return ('vec3(%s, %s, %s)'):format(fmt(v.x, rot), fmt(v.y, rot), fmt(v.z, rot))
end

local function configLine(mode, side, s)
    local head = side == 'left' and 'left  = ' or 'right = '
    if mode == 'attach' then
        return ('%s{ bone = %d, pos = %s, rot = %s },'):format(head, s.bone, vecText(s.pos), vecText(s.rot, true))
    end
    return ('%s{ bone = %d, grip = %s, tip = %s, rot = %s },'):format(head, s.bone, vecText(s.grip),
        vecText(s.tip), vecText(s.rot, true))
end

local function copyOf(s)
    local out = {}
    for k, v in pairs(s) do out[k] = v end
    return out
end

-- put the local crutch where the fit values say ('follow' is re-placed every frame anyway)
local function applyFit()
    if not fit or fit.mode ~= 'attach' then return end
    local me = PlayerPedId()
    local h = held[me]
    if not h or h.mode ~= 'attach' then return end
    for side, obj in pairs(h.ents) do
        if DoesEntityExist(obj) then attachPose(me, obj, fit.cfg[side]) end
    end
end

fitCard = function()
    local list = FIELDS[fit.mode]
    local field = list[fit.field]
    local v = fit.cfg[fit.side][field]
    local rot = field == 'rot'
    local function val(x) return fmt(x, rot) .. (rot and '°' or '') end
    local nextField = list[fit.field % #list + 1]
    local keys = {
        { keys = { '←', '→' }, label = L('fit_axis', 'X', val(v.x)) },
        { keys = { '↑', '↓' }, label = L('fit_axis', 'Y', val(v.y)) },
        { keys = { L('key_pgup'), L('key_pgdn') }, label = L('fit_axis', 'Z', val(v.z)) },
        { keys = { L('key_space') }, label = L('fit_next', L('fit_f_' .. nextField)) },
        { keys = { L('key_shift') }, label = L('fit_fine') },
    }
    if #sideList() > 1 then keys[#keys + 1] = { keys = { L('key_tab') }, label = L('fit_side') } end
    keys[#keys + 1] = { keys = { L('key_enter') }, label = L('fit_print') }
    keys[#keys + 1] = { keys = { L('key_del') }, label = L('fit_reset') }
    keys[#keys + 1] = { keys = { L('key_back') }, label = L('fit_done') }
    return { title = L('fit_title'), sub = L('fit_sub', L('fit_hand_' .. fit.side), L('fit_what_' .. field)), keys = keys }
end

local function fitToast(key, kind, ms)
    NZA.UI.Toast({ title = L('fit_title'), message = L(key), type = kind or 'info', duration = ms })
end

local function fitRefresh()
    applyFit()
    hud(walk.state or L('hud_crutch_stand'), walk.moving)
end

local function fitPrint()
    local lines = {}
    for _, side in ipairs(sideList()) do
        lines[#lines + 1] = configLine(fit.mode, side, fit.cfg[side])
    end
    print(('^3[%s]^7 %s'):format(tostring(CR().fitCommand or 'crutchfit'), L('fit_print_head', fit.mode)))
    for _, line in ipairs(lines) do print('            ' .. line) end
    local copied = false
    if lib and lib.setClipboard then
        copied = pcall(lib.setClipboard, table.concat(lines, '\n'))
    end
    fitToast(copied and 'fit_copied' or 'fit_printed', 'success', 8000)
end

local function fitReset()
    for _, side in ipairs(SIDES_2) do fit.cfg[side] = copyOf(configured(fit.mode, side)) end
    override.right, override.left = fit.cfg.right, fit.cfg.left
    fitToast('fit_reset_done', 'info')
    fitRefresh()
end

local function nudge(axis, dir, heldMs)
    local field = FIELDS[fit.mode][fit.field]
    local step = field == 'rot' and STEP_ROT or STEP_POS
    if IsDisabledControlPressed(0, K_FINE) then step = step / 5 end
    if heldMs > 1200 then step = step * 5 end
    local s = fit.cfg[fit.side]
    local v = s[field]
    local d = field == 'rot' and 1 or 3
    local x, y, z = v.x, v.y, v.z
    if axis == 'x' then x = x + step * dir elseif axis == 'y' then y = y + step * dir else z = z + step * dir end
    s[field] = vector3(num(x, d), num(y, d), num(z, d))
    fitRefresh()
end

local function fitLoop(my)
    while fit == my and on do
        for i = 1, #MOVE_KEYS do DisableControlAction(0, MOVE_KEYS[i].id, true) end
        for i = 1, #OTHER_KEYS do DisableControlAction(0, OTHER_KEYS[i], true) end
        local now = GetGameTimer()
        -- skip the first moment (the Enter that sent the chat command) and while a menu / chat has focus
        if now >= my.readyAt and not IsNuiFocused() and not IsPauseMenuActive() then
            for i = 1, #MOVE_KEYS do
                local k = MOVE_KEYS[i]
                if IsDisabledControlJustPressed(0, k.id) then
                    my.down[k.id], my.rep[k.id] = now, now + 300
                    nudge(k.axis, k.dir, 0)
                elseif my.down[k.id] and IsDisabledControlPressed(0, k.id) then
                    if now >= my.rep[k.id] then
                        my.rep[k.id] = now + 60
                        nudge(k.axis, k.dir, now - my.down[k.id])
                    end
                else
                    my.down[k.id] = nil
                end
            end
            if IsDisabledControlJustPressed(0, K_NEXT) then
                my.field = my.field % #FIELDS[my.mode] + 1
                fitRefresh()
            elseif IsDisabledControlJustPressed(0, K_SIDE) and #sideList() > 1 then
                my.side = my.side == 'right' and 'left' or 'right'
                fitRefresh()
            elseif IsDisabledControlJustPressed(0, K_COPY) then
                fitPrint()
            elseif IsDisabledControlJustPressed(0, K_RESET) then
                fitReset()
            elseif IsDisabledControlJustPressed(0, K_DONE) then
                fitStop()
                return
            end
        end
        Wait(0)
    end
end

fitStop = function(silent)
    if not fit then return end
    fit = nil
    -- the fitted values (override) stay on this client until the resource restarts
    if not silent then fitToast('fit_off', 'info', 6000) end
    hud(walk.state, walk.moving)
end

function SP.CrutchFit(want)
    if want == nil then want = fit == nil end
    if not want then
        if fitStop then fitStop() end
        return
    end
    if fit then return end
    if not on then
        fitToast('fit_need', 'error')
        return
    end
    local mode = holdMode()
    local s = { mode = mode, side = 'right', field = 1, cfg = {}, down = {}, rep = {}, readyAt = GetGameTimer() + 300 }
    for _, side in ipairs(SIDES_2) do
        local src = override and override.mode == mode and override[side] or configured(mode, side)
        s.cfg[side] = copyOf(src)
    end
    override = { mode = mode, right = s.cfg.right, left = s.cfg.left }
    fit = s
    fitToast('fit_on', 'info', 9000)
    fitRefresh()
    CreateThread(function() fitLoop(s) end)
end

if CR().enabled ~= false and CR().fitCommand then
    RegisterCommand(CR().fitCommand, function() SP.CrutchFit() end, false)
    TriggerEvent('chat:addSuggestion', '/' .. CR().fitCommand, L('cmd_fit_help'), {})
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDIC: GIVE CRUTCHES
-- ════════════════════════════════════════════════════════════════════════

if CR().enabled ~= false and CR().give ~= false and C('Interact').crutches ~= false then
    NZA.Interact.Add({
        name = 'nza_crutches_give', label = L('opt_crutches'), icon = (C('Interact').icons or {}).crutches or 'crutch',
        order = 52, perm = CR().givePerm or 'splint', npc = false, player = true,
        states = { alive = true, wounded = true }, distance = tonumber(C('Interact').distance) or 2.2,
        canInteract = function(_, _, st)
            if type(st) ~= 'table' or st.carried or st.bag then return false end
            if not Bridge or not Bridge.Inv or not Bridge.Inv.Has then return true end
            local name = Config.Items and Config.Items[CR().item or 'crutches']
            return name ~= nil and Bridge.Inv.Has(name, 1) ~= false
        end,
        onSelect = function(_, target)
            NZA.Treat.Do('crutches_give', target, {})
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and on then
        on = false
        stopWalk()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    fit = nil
    for ped in pairs(held) do drop(ped) end
    if on then
        on = false
        NZA.Self.SetMoveOverride('crutch', nil)
    end
end)
