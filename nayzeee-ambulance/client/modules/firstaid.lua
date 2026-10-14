--[[
    NAYZEEE AMBULANCE - First aid (client): helpers, first aid items, worn devices,
    patient options, examination routes and EMS radial entries.

    Files of this module
      client/modules/firstaid.lua        (this)
      client/modules/firstaid_treat.lua  the 'treat' NUI app runner: stop bleeding, tourniquet,
                                         collar, medication panel, first aid kit chooser

    Client API (NZA.Firstaid)
      FA.UseItem(key, entity?, target?, injuryId?)   use a first aid item on yourself (no target) or a
                                                      patient: preview → progress + anim → NZA.Treat.Do
      FA.Start.bleed / tq / collar / meds / kit / oxygen / tqOff / collarOff / foilOff (firstaid_treat.lua)
      FA.NearestPatient(range) → entity, target      FA.Bag(entity) → 'nzaFa' state bag or nil
      FA.Lying(entity) → bool                         FA.NeedsPack(inj) / FA.Plan(inj) (mirror of the server)

    Registers
      NZA.Interact.Add  nza_fa_stopbleed nza_fa_tq nza_fa_tqoff nza_fa_meds nza_fa_collar nza_fa_collaroff
                        nza_fa_oxygen nza_fa_oxygenoff nza_fa_foil nza_fa_foiloff nza_fa_kit   (order 40-49)
      NZA.ExamRoutes    stopbleed tourniquet collar ice painrelief morphine burndressing
      NZA.RadialItems   fa_stopbleed fa_tourniquet fa_meds fa_kit (parent 'patient')
    Net events: nza:firstaid:use (S→C, itemKey)   nza:firstaid:agitated (S→C, netId)
    Worn props: every client renders tourniquets, cervical collars, oxygen masks and foil blankets
    on patients within Config.Firstaid.Props.range from the 'nza' and 'nzaFa' state bags.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Firstaid = NZA.Firstaid or {}
NZA.Firstaid.Start = NZA.Firstaid.Start or {}
local FA = NZA.Firstaid

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

function FA.Cfg(section)
    local c = Config.Firstaid or {}
    if section then return c[section] or {} end
    return c
end

function FA.L(key, ...) return NZA.L('firstaid.' .. key, ...) end
local L = FA.L

function FA.Toast(message, kind, title)
    if NZA.UI and NZA.UI.Toast then
        NZA.UI.Toast({ type = kind or 'info', title = title, message = message })
    end
end

local busy = nil
function FA.Busy() return busy end
function FA.SetBusy(name) busy = name end

local itemKeys = nil
function FA.ItemLabel(name)
    if not name then return '' end
    if not itemKeys then
        itemKeys = {}
        for key, item in pairs(Config.Items or {}) do itemKeys[item] = key end
    end
    local key = itemKeys[name]
    local def = key and Config.ItemDefs and Config.ItemDefs[key]
    if def and def.label then return def.label end
    if Bridge and Bridge.Inv and Bridge.Inv.Label then
        local ok, l = pcall(Bridge.Inv.Label, name)
        if ok and type(l) == 'string' and l ~= '' then return l end
    end
    return name
end

function FA.ItemCount(name)
    if not name then return 0 end
    if Bridge and Bridge.Inv then
        if Bridge.Inv.Count then
            local ok, n = pcall(Bridge.Inv.Count, name)
            if ok and tonumber(n) then return tonumber(n) end
        end
        if Bridge.Inv.Has then
            local ok, has = pcall(Bridge.Inv.Has, name, 1)
            if ok then return has and 1 or 0 end
        end
    end
    return 0
end

function FA.ItemImage(name)
    if name and Bridge and Bridge.Inv and Bridge.Inv.Image then
        local ok, img = pcall(Bridge.Inv.Image, name)
        if ok and type(img) == 'string' and img ~= '' then return img end
    end
    return nil
end

-- 'nzaFa' state bag of a patient ped (oxygen, foil, tourniquet positions)
function FA.Bag(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if IsPedAPlayer(entity) then
        local idx = NetworkGetPlayerIndexFromPed(entity)
        if not idx or idx == -1 then return nil end
        return Player(GetPlayerServerId(idx)).state.nzaFa
    end
    if not NetworkGetEntityIsNetworked(entity) then return nil end
    return Entity(entity).state.nzaFa
end

function FA.Lying(entity)
    if not entity or entity == 0 then return false end
    local st = NZA.Target.State(entity)
    local s = type(st) == 'table' and st.st or 'alive'
    if s ~= 'alive' then return true end
    return IsPedRagdoll(entity) or IsPedFatallyInjured(entity) or IsEntityDead(entity)
end

-- nearest patient (player or NPC with an 'nza' state bag) within range
function FA.NearestPatient(range)
    range = range or FA.Cfg('Radial').range or 3.0
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestD = nil, range
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= me and DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d < bestD then best, bestD = ped, d end
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d < bestD and Entity(ped).state.nza then best, bestD = ped, d end
        end
    end
    if not best then return nil end
    local target = NZA.Target.FromEntity(best)
    if not target then return nil end
    return best, target
end

local function has(list, v)
    if type(list) ~= 'table' then return false end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end
FA.Has = has

-- mirror of the server rules (server/modules/firstaid.lua) for the examination buttons
function FA.NeedsPack(inj)
    local sb = FA.Cfg('StopBleed')
    local minSev = (sb.pack or {})[inj.type]
    if minSev and (tonumber(inj.severity) or 1) >= minSev then return true end
    if (tonumber(inj.depth) or 0) >= (sb.packDepth or 15) and (inj.type == 'gunshot' or inj.type == 'stab'
        or inj.type == 'shrapnel' or inj.type == 'laceration') then
        return true
    end
    return false
end

function FA.Plan(inj)
    local sb = FA.Cfg('StopBleed')
    if not has(sb.types, inj.type) then return nil end
    local t = inj.treat or {}
    local steps = 0
    local pack = FA.NeedsPack(inj) and not t.packed
    if pack then steps = steps + 1 end
    if not t.bandaged and not t.dressed and not t.sutured then steps = steps + 1 end
    if steps == 0 then return nil end
    return { pack = pack }
end

local UPPER = { l_lower_arm = 'l_upper_arm', r_lower_arm = 'r_upper_arm', l_lower_leg = 'l_upper_leg', r_lower_leg = 'r_upper_leg' }
function FA.TqCovers(snap, region)
    local tq = snap and snap.devices and snap.devices.tourniquet
    if type(tq) ~= 'table' then return false end
    if tq[region] then return true end
    local up = UPPER[region]
    return up ~= nil and tq[up] ~= nil
end

-- the snapshot carries absolute server timestamps (os.time) for active medicines
function FA.MedActive(snap, name)
    local e = snap and snap.meds and tonumber(snap.meds[name])
    return e ~= nil and e > GetCloudTimeAsInt()
end

function FA.Target(entity, target)
    if type(target) == 'table' then return target end
    return NZA.Target.FromEntity(entity)
end

-- ════════════════════════════════════════════════════════════════════════
-- FIRST AID ITEMS (inventory use on yourself, or 'First aid…' on a patient)
-- ════════════════════════════════════════════════════════════════════════

FA.ItemActions = {
    bandage = 'fa_bandage', medkit = 'fa_medkit', painkillers = 'fa_painkillers',
    ice_pack = 'fa_ice', burn_dressing = 'fa_burn', foil_blanket = 'fa_foil',
}

local KNEEL = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 }

function FA.UseItem(key, entity, target, injuryId)
    if busy then
        FA.Toast(L('err_busy'), 'error')
        return false
    end
    if NZA.Proc and NZA.Proc.Active and NZA.Proc.Active() then
        FA.Toast(L('err_busy'), 'error')
        return false
    end
    local ic = FA.Cfg('Items')[key] or {}
    local action = FA.ItemActions[key]
    local item = Config.Items and Config.Items[key]
    if ic.enabled == false or not action or not item then return false end
    local me = PlayerPedId()
    local isSelf = target == nil or NZA.Target.IsSelf(target)
    if isSelf then
        target = NZA.Target.Self()
        entity = me
    elseif not entity or entity == 0 then
        entity = NZA.Target.Entity(target)
    end
    if FA.ItemCount(item) < 1 then
        FA.Toast(L('err_need_item', FA.ItemLabel(item)), 'error')
        return false
    end
    -- what would it do? (the server answers with the same rules it applies)
    local okCall, info = pcall(lib.callback.await, 'nza:firstaid:kit', false, target)
    if okCall and type(info) == 'table' and type(info.items) == 'table' then
        for _, e in ipairs(info.items) do
            if e.key == key and not e.usable then
                FA.Toast(e.text or L('err_failed'), 'error', FA.ItemLabel(item))
                return false
            end
        end
    end

    busy = 'item'
    local down = NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown()
    local anim
    if isSelf then
        anim = (not down) and ic.anim or nil
    else
        TaskTurnPedToFaceEntity(me, entity, 600)
        Wait(500)
        anim = FA.Lying(entity) and KNEEL or FA.Cfg('Items').othersAnim
    end
    local okBar = lib.progressBar({
        duration = tonumber(ic.duration) or 4000,
        label = L('use_' .. key),
        useWhileDead = false, canCancel = true, allowRagdoll = false,
        disable = { move = true, car = not isSelf, combat = true, sprint = true },
        anim = anim and { dict = anim.dict, clip = anim.clip, flag = anim.flag or 49 } or nil,
    })
    busy = nil
    if not okBar then
        FA.Toast(L('cancelled'), 'error')
        return false
    end
    if not isSelf and (not DoesEntityExist(entity) or #(GetEntityCoords(me) - GetEntityCoords(entity)) > 3.5) then
        FA.Toast(L('err_too_far'), 'error')
        return false
    end
    local ok = NZA.Treat.Do(action, target, { injury = injuryId })
    return ok
end

RegisterNetEvent('nza:firstaid:use', function(key)
    if type(key) ~= 'string' or not FA.ItemActions[key] then return end
    CreateThread(function() FA.UseItem(key) end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- NALOXONE: the NPC wakes up agitated
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:firstaid:agitated', function(net)
    net = tonumber(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return end
    local ped = NetworkGetEntityFromNetworkId(net)
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsPedAPlayer(ped) then return end
    CreateThread(function()
        local deadline = GetGameTimer() + 1500
        while not NetworkHasControlOfEntity(ped) and GetGameTimer() < deadline do
            NetworkRequestControlOfEntity(ped)
            Wait(50)
        end
        if not NetworkHasControlOfEntity(ped) then return end
        local a = FA.Cfg('Meds').agitated or {}
        ClearPedTasks(ped)
        TaskTurnPedToFaceEntity(ped, PlayerPedId(), 800)
        Wait(800)
        if a.dict and a.clip and pcall(lib.requestAnimDict, a.dict, 2000) then
            TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, tonumber(a.duration) or 6000, 49, 0.0, false, false, false)
            RemoveAnimDict(a.dict)
        end
        PlayPedAmbientSpeechNative(ped, 'GENERIC_SHOCKED_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- WORN PROPS (tourniquet, collar, oxygen mask, foil blanket) from state bags
-- ════════════════════════════════════════════════════════════════════════

local CHAIN = {
    l_arm = { 45509, 61163, 18905 }, r_arm = { 40269, 28252, 57005 },
    l_leg = { 58271, 63931, 14201 }, r_leg = { 51826, 36864, 52301 },
}
FA.Chain = CHAIN

-- region → { chain, seg ('upper'|'lower'), limb ('arm'|'leg'), upper, lower }
function FA.LimbOf(region)
    if type(region) ~= 'string' then return nil end
    local side, seg, kind = region:match('^([lr])_(%a+)_(%a+)$')
    if not side or (kind ~= 'arm' and kind ~= 'leg') then return nil end
    return {
        chain = CHAIN[side .. '_' .. kind], seg = seg, limb = kind,
        upper = side .. '_upper_' .. kind, lower = side .. '_lower_' .. kind,
    }
end

local missingModel = {}
local function modelFor(key)
    if not key or key == false then return nil end
    if missingModel[key] then return nil end
    local name = (Config.Props and Config.Props[key]) or key
    local fallback = Config.PropFallbacks and Config.PropFallbacks[key]
    if IsModelInCdimage(GetHashKey(name)) then return key end
    if fallback and IsModelInCdimage(GetHashKey(fallback)) then return key end
    missingModel[key] = true
    NZA.Debug('firstaid: no model for worn prop', key)
    return nil
end

-- attach position for a tourniquet: fraction along the segment bone (X runs along the bone)
function FA.TqAttach(ped, region, pos)
    local limb = FA.LimbOf(region)
    if not limb then return nil end
    local seg, frac = limb.seg, nil
    if type(pos) == 'table' then
        seg = pos.s == 'lower' and 'lower' or (pos.s == 'upper' and 'upper' or seg)
        frac = tonumber(pos.f)
    end
    local def = (FA.Cfg('Props').tourniquet or {}).default or {}
    frac = frac or (seg == 'upper' and (def.upper or 0.22) or (def.lower or 0.3))
    local a = seg == 'upper' and limb.chain[1] or limb.chain[2]
    local b = seg == 'upper' and limb.chain[2] or limb.chain[3]
    local len = #(GetPedBoneCoords(ped, a, 0.0, 0.0, 0.0) - GetPedBoneCoords(ped, b, 0.0, 0.0, 0.0))
    if len < 0.05 or len > 1.0 then len = seg == 'upper' and 0.42 or 0.4 end
    return { bone = a, pos = vector3(math.max(0.04, math.min(0.96, frac)) * len, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) }
end

local worn = {}   -- [key] = { entity, ped }

local function wantedFor(ped, bag, fa, out)
    if type(bag) == 'table' then
        local tq = type(bag.tq) == 'table' and bag.tq or {}
        local pos = type(fa) == 'table' and type(fa.tq) == 'table' and fa.tq or {}
        for region in pairs(tq) do out['tq:' .. region] = { what = 'tq', region = region, pos = pos[region] } end
        if bag.collar then out.collar = { what = 'collar' } end
    end
    if type(fa) == 'table' then
        if fa.o2 then out.o2 = { what = 'o2' } end
        if fa.foil then out.foil = { what = 'foil' } end
    end
end

local function spawnWorn(ped, want)
    local P = FA.Cfg('Props')
    if want.what == 'tq' then
        local key = modelFor((P.tourniquet or {}).prop or 'tourniquet_worn')
        if not key then return 0 end
        local at = FA.TqAttach(ped, want.region, want.pos)
        if not at then return 0 end
        return NZA.Props.Spawn(key, { attach = { entity = ped, bone = at.bone, pos = at.pos, rot = at.rot, collision = false } },
            { group = 'firstaid_worn', collision = false })
    end
    local def = want.what == 'collar' and P.collar or want.what == 'o2' and P.oxygen or P.foil
    if type(def) ~= 'table' or not def.prop then return 0 end
    local key = modelFor(def.prop)
    if not key then return 0 end
    return NZA.Props.Spawn(key, { attach = { entity = ped, bone = def.bone or 24818, pos = def.pos, rot = def.rot, collision = false } },
        { group = 'firstaid_worn', collision = false })
end

local function clearWorn(id)
    local w = worn[id]
    if not w then return end
    worn[id] = nil
    if w.entity and w.entity ~= 0 then NZA.Props.Delete(w.entity) end
end

CreateThread(function()
    Wait(2000)
    while true do
        local range = tonumber(FA.Cfg('Props').range) or 45.0
        local me = PlayerPedId()
        local pos = GetEntityCoords(me)
        local want = {}
        local function consider(ped, bag, fa)
            if not DoesEntityExist(ped) or #(GetEntityCoords(ped) - pos) > range then return end
            local list = {}
            wantedFor(ped, bag, fa, list)
            for k, v in pairs(list) do
                v.ped = ped
                want[ped .. ':' .. k .. ':' .. (v.pos and json.encode(v.pos) or '')] = v
            end
        end
        for _, pl in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(pl)
            local st = Player(GetPlayerServerId(pl)).state
            local bag, fa = st.nza, st.nzaFa
            if bag or fa then consider(ped, bag, fa) end
        end
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
                local st = Entity(ped).state
                local bag = st.nza
                if bag then consider(ped, bag, st.nzaFa) end
            end
        end
        -- the tourniquet being placed in our own minigame has its own temporary prop
        local skip = FA.TqPlacing and FA.TqPlacing() or nil
        for id, w in pairs(worn) do
            if not want[id] or not DoesEntityExist(w.ped) or (w.entity ~= 0 and not DoesEntityExist(w.entity)) then clearWorn(id) end
        end
        for id, v in pairs(want) do
            if not worn[id] and not (skip and skip.ped == v.ped and v.what == 'tq') then
                local ok, ent = pcall(spawnWorn, v.ped, v)
                worn[id] = { entity = ok and ent or 0, ped = v.ped }
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(worn) do clearWorn(id) end
    if NZA.Props and NZA.Props.Clear then NZA.Props.Clear('firstaid_worn') end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT OPTIONS (order band 40 = treatment)
-- ════════════════════════════════════════════════════════════════════════

local function notPlaced(st)
    return not (type(st) == 'table' and (st.bag or st.carried))
end

local function start(name, ...)
    local args = { ... }
    return function(entity, target)
        local fn = FA.Start[name]
        if fn then fn(entity, target, table.unpack(args)) end
    end
end

do
    local ic = FA.Cfg('Interact')
    local icons = ic.icons or {}
    local dist = ic.distance or 2.2
    local LIVE = { alive = true, wounded = true, arrest = true }
    local ALL = { alive = true, wounded = true, arrest = true, dead = true }
    local sb, tc, cc, oc, fc, mc = FA.Cfg('StopBleed'), FA.Cfg('Tourniquet'), FA.Cfg('Collar'), FA.Cfg('Oxygen'), FA.Cfg('Foil'), FA.Cfg('Meds')

    if ic.stopBleed ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_stopbleed', label = L('opt_stopbleed'), icon = icons.stopBleed or 'drop', order = 40,
            perm = sb.perm or 'basic', states = LIVE, distance = dist,
            canInteract = function(_, _, st) return notPlaced(st) and type(st) == 'table' and (tonumber(st.bleed) or 0) >= (ic.minBleed or 1) end,
            onSelect = start('bleed'),
        })
    end
    if ic.tourniquet ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_tq', label = L('opt_tq'), icon = icons.tourniquet or 'clamp', order = 41,
            perm = tc.perm or 'basic', states = LIVE, distance = dist,
            canInteract = function(_, _, st) return notPlaced(st) and type(st) == 'table' and (tonumber(st.bleed) or 0) >= (ic.tqBleed or 2) end,
            onSelect = start('tq'),
        })
        NZA.Interact.Add({
            name = 'nza_fa_tqoff', label = L('opt_tq_off'), icon = icons.tqOff or 'clamp', order = 48,
            perm = tc.removePerm or 'basic', states = ALL, distance = dist,
            canInteract = function(_, _, st) return type(st) == 'table' and type(st.tq) == 'table' and next(st.tq) ~= nil and not st.bag end,
            onSelect = start('tqOff'),
        })
    end
    if ic.meds ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_meds', label = L('opt_meds'), icon = icons.meds or 'syringe', order = 43,
            perm = mc.perm or 'meds', states = LIVE, distance = dist,
            canInteract = function(_, _, st) return notPlaced(st) end,
            onSelect = start('meds'),
        })
    end
    if ic.collar ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_collar', label = L('opt_collar'), icon = icons.collar or 'collar', order = 44,
            perm = cc.perm or 'splint', states = LIVE, distance = dist,
            canInteract = function(_, _, st) return notPlaced(st) and not (type(st) == 'table' and st.collar) end,
            onSelect = start('collar'),
        })
        NZA.Interact.Add({
            name = 'nza_fa_collaroff', label = L('opt_collar_off'), icon = icons.collarOff or 'collar', order = 49,
            perm = cc.perm or 'splint', states = ALL, distance = dist,
            canInteract = function(_, _, st) return type(st) == 'table' and st.collar == true and not st.bag end,
            onSelect = start('collarOff'),
        })
    end
    if ic.oxygen ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_oxygen', label = L('opt_oxygen'), icon = icons.oxygen or 'wind', order = 45,
            perm = oc.perm or 'airway', states = LIVE, distance = dist,
            canInteract = function(entity, _, st)
                local fa = FA.Bag(entity)
                return notPlaced(st) and not (type(fa) == 'table' and fa.o2) and not (type(st) == 'table' and st.intub)
            end,
            onSelect = start('oxygen', true),
        })
        NZA.Interact.Add({
            name = 'nza_fa_oxygenoff', label = L('opt_oxygen_off'), icon = icons.oxygen or 'wind', order = 49,
            perm = oc.perm or 'airway', states = ALL, distance = dist,
            canInteract = function(entity) local fa = FA.Bag(entity); return type(fa) == 'table' and fa.o2 == true end,
            onSelect = start('oxygen', false),
        })
    end
    if ic.foil ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_foil', label = L('opt_foil'), icon = icons.foil or 'blanket', order = 46,
            perm = fc.perm, states = LIVE, distance = dist,
            canInteract = function(entity, _, st)
                local fa = FA.Bag(entity)
                return notPlaced(st) and not (type(fa) == 'table' and fa.foil)
                    and FA.ItemCount(Config.Items and Config.Items[fc.item or 'foil_blanket']) > 0
            end,
            onSelect = function(entity, target) FA.UseItem('foil_blanket', entity, target) end,
        })
        NZA.Interact.Add({
            name = 'nza_fa_foiloff', label = L('opt_foil_off'), icon = icons.foil or 'blanket', order = 49,
            perm = fc.perm, states = ALL, distance = dist,
            canInteract = function(entity) local fa = FA.Bag(entity); return type(fa) == 'table' and fa.foil == true end,
            onSelect = start('foilOff'),
        })
    end
    if ic.kit ~= false then
        NZA.Interact.Add({
            name = 'nza_fa_kit', label = L('opt_kit'), icon = icons.kit or 'medkit', order = 47,
            perm = 'basic', states = LIVE, distance = dist,
            canInteract = function(_, _, st) return notPlaced(st) end,
            onSelect = start('kit'),
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- EXAMINATION ROUTES ('Injuries to treat' card, assess module)
-- ════════════════════════════════════════════════════════════════════════

NZA.ExamRoutes = NZA.ExamRoutes or {}

local function entityOf(target) return NZA.Target.Entity(target) end
local function itemsOf(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = Config.Items and Config.Items[key]
        if name then out[name] = n end
    end
    return out
end

do
    local sb, tc, cc = FA.Cfg('StopBleed'), FA.Cfg('Tourniquet'), FA.Cfg('Collar')
    local ii = FA.Cfg('Items')
    local mc = FA.Cfg('Meds')

    table.insert(NZA.ExamRoutes, {
        id = 'stopbleed', label = L('route_stopbleed'), icon = 'drop', perm = sb.perm or 'basic', order = 10,
        types = sb.types, items = itemsOf(((sb.items or {}).wrap) or { bandage = 1 }),
        available = function(inj, snap)
            local bleed = tonumber(inj.bleed) or 0
            if bleed < 0.5 and FA.TqCovers(snap, inj.region) then bleed = tonumber(inj.bleedBase) or 0 end
            if inj.type == 'abrasion' and bleed < (sb.abrasionMin or 2) then return false end
            if bleed < (sb.minBleed or 0.5) then return false end
            local plan = FA.Plan(inj)
            if not plan then return false, L('route_dressed') end
            if plan.pack then
                for name, n in pairs(itemsOf((sb.items or {}).pack or { gauze = 1 })) do
                    if FA.ItemCount(name) < n then return false, L('route_need_gauze', FA.ItemLabel(name)) end
                end
            end
            return true
        end,
        run = function(target, inj) FA.Start.bleed(entityOf(target), target, inj.id) end,
    })

    table.insert(NZA.ExamRoutes, {
        id = 'tourniquet', label = L('route_tq'), icon = 'clamp', perm = tc.perm or 'basic', order = 12,
        types = { 'gunshot', 'shrapnel', 'stab', 'laceration', 'fracture' },
        regions = { 'l_upper_arm', 'l_lower_arm', 'r_upper_arm', 'r_lower_arm', 'l_upper_leg', 'l_lower_leg', 'r_upper_leg', 'r_lower_leg' },
        items = itemsOf({ [tc.item or 'tourniquet'] = 1 }),
        available = function(inj, snap)
            if FA.TqCovers(snap, inj.region) then return false, L('route_has_tq') end
            if (tonumber(inj.bleed) or 0) < (tc.minBleed or 15) then return false end
            return true
        end,
        run = function(target, inj) FA.Start.tq(entityOf(target), target, inj.id) end,
    })

    table.insert(NZA.ExamRoutes, {
        id = 'collar', label = L('route_collar'), icon = 'collar', perm = cc.perm or 'splint', order = 14,
        regions = { 'neck' }, items = itemsOf({ [cc.item or 'cervical_collar'] = 1 }),
        available = function(inj, snap)
            if snap and snap.devices and snap.devices.collar then return false, L('route_has_collar') end
            return true
        end,
        run = function(target) FA.Start.collar(entityOf(target), target) end,
    })

    if (ii.ice_pack or {}).enabled ~= false then
        table.insert(NZA.ExamRoutes, {
            id = 'ice', label = L('route_ice'), icon = 'snow', perm = 'basic', order = 30,
            types = { 'contusion' }, items = itemsOf({ ice_pack = 1 }),
            available = function(inj)
                if inj.treat and inj.treat.cooled then return false, L('route_cooled') end
                return true
            end,
            run = function(target, inj) FA.UseItem('ice_pack', entityOf(target), target, inj.id) end,
        })
    end

    if (ii.burn_dressing or {}).enabled ~= false then
        local bc = ii.burn_dressing or {}
        table.insert(NZA.ExamRoutes, {
            id = 'burndressing', label = L('route_burn'), icon = 'flame', perm = 'basic', order = 34,
            types = { 'burn' }, items = itemsOf({ burn_dressing = 1 }),
            available = function(inj)
                local t = inj.treat or {}
                if t.dressed or t.grafted then return false end
                local deg = inj.burn and tonumber(inj.burn.degree) or 1
                if deg > (bc.maxDegree or 2) or (tonumber(inj.severity) or 1) > (bc.maxSeverity or 2) then return false end
                return true
            end,
            run = function(target, inj) FA.UseItem('burn_dressing', entityOf(target), target, inj.id) end,
        })
    end

    if (ii.painkillers or {}).enabled ~= false then
        table.insert(NZA.ExamRoutes, {
            id = 'painrelief', label = L('route_pain'), icon = 'pill', perm = 'basic', order = 40,
            items = itemsOf({ painkillers = 1 }),
            available = function(inj, snap)
                if (tonumber(inj.pain) or 0) < 25 then return false end
                if FA.MedActive(snap, 'painkillers') or FA.MedActive(snap, 'morphine') then return false, L('route_on_pain') end
                local avpu = snap and snap.vitals and snap.vitals.avpu or 'A'
                if avpu ~= 'A' and avpu ~= 'V' then return false, L('err_cant_swallow') end
                return true
            end,
            run = function(target) FA.UseItem('painkillers', entityOf(target), target) end,
        })
    end

    table.insert(NZA.ExamRoutes, {
        id = 'morphine', label = L('route_morphine'), icon = 'syringe', perm = mc.perm or 'meds', order = 41,
        items = itemsOf({ morphine = 1 }),
        available = function(inj, snap)
            if (tonumber(inj.pain) or 0) < 40 then return false end
            if FA.MedActive(snap, 'morphine') then return false, L('route_on_morphine') end
            return true
        end,
        run = function(target) FA.Start.meds(entityOf(target), target, 'morphine') end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- EMS RADIAL (Patient)
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

local function radial(id, label, icon, order, perm, name)
    table.insert(NZA.RadialItems, {
        id = id, parent = 'patient', label = label, icon = icon, order = order, perm = perm,
        canShow = function()
            if FA.Cfg('Radial').enabled == false then return false end
            return FA.NearestPatient() ~= nil
        end,
        onSelect = function()
            CreateThread(function()
                local ent, target = FA.NearestPatient()
                if not ent then
                    FA.Toast(L('err_nobody'), 'error')
                    return
                end
                local fn = FA.Start[name]
                if fn then fn(ent, target) end
            end)
        end,
    })
end

do
    radial('fa_stopbleed', L('opt_stopbleed'), 'drop', 40, FA.Cfg('StopBleed').perm or 'basic', 'bleed')
    radial('fa_tourniquet', L('opt_tq'), 'clamp', 41, FA.Cfg('Tourniquet').perm or 'basic', 'tq')
    radial('fa_meds', L('opt_meds'), 'syringe', 43, FA.Cfg('Meds').perm or 'meds', 'meds')
    radial('fa_kit', L('opt_kit'), 'medkit', 47, 'basic', 'kit')
end
