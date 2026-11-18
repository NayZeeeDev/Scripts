if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby actors (contract §6.2).
      slot 1      the selected character ('self') or the creation silhouette ('ghost')
      slots 2..4  accepted + visible squad links ('couple' always in slot 2, else 'squad')
      pet         the character's pet (Actors.pet)
    actor = { ped, slot, kind, char | other, link, mark (vec4), seat, weapon }

    Pose resolution per actor:
      couple pose (slot 1 + couple partner in slot 2)  -> Couple.Play, both unarmed, props cleared
      weapon (unless the pose has weapon = false)        -> weapon + class hold anim (Config.WeaponShowcase.holds)
      character pose (props attached)                    -> Config.Poses
      theme.poses[slot]                                  -> default
    In-flight themes (theme.seats): actors are attached to the vehicle and play the seat anim; an upper-body
    (flag 49) pose / weapon hold is layered on top, anything else loses to the seat anim. No couple pose there.
]]

Actors = { list = {}, pet = nil, char = nil, squad = nil, preview = {}, walking = false, seq = 0 }

local SQUAD_DEFAULT = {
    [2] = { offset = vec3(0.95, 0.15, 0.0), heading = -8.0 },
    [3] = { offset = vec3(-1.10, 0.45, 0.0), heading = 10.0 },
    [4] = { offset = vec3(2.00, 0.60, 0.0), heading = -14.0 },
}
local PET_DEFAULT = { offset = vec3(-0.55, 0.95, 0.0), heading = 15.0 }

local function seatOf(slot)
    local seats = Scene.theme and Scene.theme.seats
    return seats and seats[slot] or nil
end

-- ── marks & placement ────────────────────────────────────────────────────
function Actors.Mark(slot)
    local base = Scene.main
    if not base then return vec4(0.0, 0.0, 0.0, 0.0) end
    local seat = seatOf(slot)
    if seat and seat.attach then
        local veh = Scene.Vehicle(seat.attach.vehicle or 1)
        if veh then
            local o, r = seat.attach.offset or vec3(0.0, 0.0, 0.0), seat.attach.rotation or vec3(0.0, 0.0, 0.0)
            local p = GetOffsetFromEntityInWorldCoords(veh, o.x, o.y, o.z)
            return vec4(p.x, p.y, p.z, (GetEntityHeading(veh) + r.z) % 360.0)
        end
    end
    if slot == 1 then return base end
    local pl = (Scene.theme.slots and Scene.theme.slots[slot]) or SQUAD_DEFAULT[slot] or SQUAD_DEFAULT[2]
    return U.Snap(NZ.Place(base, pl))     -- ground snapped (contract §6.3)
end

local function place(a)
    local ped = a.ped
    if not DoesEntityExist(ped) then return end
    local seat = a.seat
    local veh = seat and seat.attach and Scene.Vehicle(seat.attach.vehicle or 1)
    if veh then
        local o, r = seat.attach.offset or vec3(0.0, 0.0, 0.0), seat.attach.rotation or vec3(0.0, 0.0, 0.0)
        FreezeEntityPosition(ped, false)
        if IsEntityAttached(ped) then DetachEntity(ped, false, false) end
        -- AttachEntityToEntity(ent, target, boneIndex 0 = root, offset, rotation, p9, useSoftPinning, collision, isPed, vertexIndex 2, fixedRot)
        AttachEntityToEntity(ped, veh, 0, o.x, o.y, o.z, r.x, r.y, r.z, false, false, false, false, 2, true)
        return
    end
    if IsEntityAttached(ped) then DetachEntity(ped, false, false) end
    local m = a.mark
    SetEntityCoordsNoOffset(ped, m.x, m.y, m.z, false, false, false)
    SetEntityHeading(ped, m.w)
    FreezeEntityPosition(ped, true)
end
Actors.Place = place

local function human(model, gender, skin, slot, kind)
    local mark = Actors.Mark(slot)
    local ped = U.Ped(Appearance.Model(model, gender), mark)
    if skin then Appearance.ApplyPed(ped, skin) else Appearance.Default(ped, gender) end
    local a = { ped = ped, slot = slot, kind = kind, mark = mark, seat = seatOf(slot) }
    place(a)
    return a
end

-- ── prefs (saved + live preview) ─────────────────────────────────────────
local function pref(a, key)
    if a.kind == 'self' then
        local pv = Actors.preview[key]
        if pv ~= nil then return pv end
        return a.char and a.char.prefs and a.char.prefs[key]
    elseif a.other then
        return a.other.prefs and a.other.prefs[key]
    end
end

local function poseFor(a)
    if a.kind ~= 'ghost' then
        local p = NZ.PoseById(pref(a, 'pose'))
        if p then return p end
    end
    local d = Scene.theme and Scene.theme.poses and Scene.theme.poses[a.slot]
    return NZ.PoseById(a.kind ~= 'ghost' and d or 'relaxed') or NZ.PoseById('relaxed') or Config.Poses[1]
end

-- Preview of the weapon picker: 'none' | 'auto' | WEAPON_X (only weapons the character may pick)
local function resolveWeapon(c, v)
    if v == false or v == 'none' or v == '' or not c then return nil end
    local list, pick = c.weapons or {}, nil
    if v == 'auto' then
        for _, cls in ipairs(Config.WeaponShowcase.priority or {}) do
            for _, w in ipairs(list) do
                if (w.class or NZ.WeaponClass(w.name)) == cls then pick = w break end
            end
            if pick then break end
        end
        pick = pick or list[1]
    else
        for _, w in ipairs(list) do
            if w.name and w.name:upper() == tostring(v):upper() then pick = w break end
        end
    end
    if not pick then return nil end
    -- The resolved showcase weapon carries the inventory components / tint
    if c.weapon and c.weapon.name and pick.name and c.weapon.name:upper() == pick.name:upper() then return c.weapon end
    return pick
end

local function weaponFor(a)
    if not Config.WeaponShowcase.enabled then return nil end
    if a.kind == 'self' then
        local pv = Actors.preview.weapon
        if pv ~= nil then return resolveWeapon(a.char, pv) end
        return a.char and a.char.weapon
    elseif a.other then
        return a.other.weapon
    end
end

-- ── weapons ──────────────────────────────────────────────────────────────
local groupClass
local function classOf(w, hash)
    local c = w.class or NZ.WeaponClass(w.name)
    if c then return c end
    if not groupClass then
        groupClass = {}
        for g, cls in pairs({ GROUP_PISTOL = 'pistol', GROUP_STUNGUN = 'pistol', GROUP_SMG = 'smg', GROUP_RIFLE = 'rifle',
            GROUP_SHOTGUN = 'shotgun', GROUP_SNIPER = 'sniper', GROUP_MG = 'mg', GROUP_MELEE = 'melee' }) do
            groupClass[U.Hash(joaat(g))] = cls
        end
    end
    return groupClass[U.Hash(GetWeapontypeGroup(hash))]
end

local function giveWeapon(a, w)
    if not w or not w.name then return nil end
    local ped = a.ped
    local hash = joaat(w.name)
    if not IsWeaponValid(hash) then return nil end
    RequestWeaponAsset(hash, 31, 0)          -- weapon model must be streamed or the ped holds nothing
    local deadline = GetGameTimer() + 2000
    while not HasWeaponAssetLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    GiveWeaponToPed(ped, hash, 0, false, true)
    -- The server may send several candidate hashes per attachment: only apply the ones this weapon takes
    for _, comp in ipairs(w.components or {}) do
        local ch = type(comp) == 'string' and (tonumber(comp) or joaat(comp)) or comp
        if ch and DoesWeaponTakeWeaponComponent(hash, ch) then GiveWeaponComponentToPed(ped, hash, ch) end
    end
    if w.tint then SetPedWeaponTintIndex(ped, hash, tonumber(w.tint) or 0) end
    SetCurrentPedWeapon(ped, hash, true)
    a.weapon = w.name
    return hash, classOf(w, hash)
end

local function upperBody(def)
    if not def or def.scenario then return false end
    local an = def.anim or (def.dict and def)
    return an and ((an.flag or 1) & 16) ~= 0 or false
end

-- Clears weapon + props (couple poses, holster)
function Actors.Strip(a)
    if not a or not DoesEntityExist(a.ped) then return end
    U.ClearProps(a.ped)
    RemoveAllPedWeapons(a.ped, true)
    a.weapon = nil
end

-- ── pose resolution ──────────────────────────────────────────────────────
function Actors.ApplyPose(a)
    if not a or not DoesEntityExist(a.ped) then return end
    local ped = a.ped
    Actors.Strip(a)
    local pose = poseFor(a)
    local w = a.kind ~= 'ghost' and weaponFor(a) or nil
    local armed = w and (not pose or pose.weapon ~= false)
    local holds = Config.WeaponShowcase.holds or {}

    if a.seat then
        -- Seat anim is the primary task; upper-body anims (flag 49 = loop | upper body | secondary) layer on top
        local layer
        if armed then
            local hash, class = giveWeapon(a, w)
            local hold = class and holds[class]
            if hash and hold and upperBody(hold) then layer = hold else Actors.Strip(a) end
        elseif upperBody(pose) then
            layer = pose
        end
        U.Pose(ped, a.seat.anim or poseFor({ kind = 'ghost', slot = a.slot }))
        if layer then
            local my = Actors.seq
            CreateThread(function()
                U.WaitPose(ped, a.seat.anim or {}, 1500)
                if Actors.seq ~= my or not DoesEntityExist(ped) then return end
                U.Pose(ped, layer, { keepTasks = true, keepProps = layer ~= pose })
            end)
        end
        return
    end

    if armed then
        local hash, class = giveWeapon(a, w)
        if hash then
            local hold = class and holds[class]
            if not (hold and U.Pose(ped, hold, { keepProps = true })) then ClearPedTasksImmediately(ped) end
            SetCurrentPedWeapon(ped, hash, true)
            return
        end
    end
    U.Pose(ped, pose)
end

local function couplePose()
    local main, partner = Actors.list[1], Actors.list[2]
    if not (main and partner and main.kind == 'self' and partner.kind == 'couple') then return nil end
    if not Config.Squad.couples or main.seat or partner.seat then return nil end
    local id = pref(main, 'couplePose')
    if not id or id == 'none' or id == '' then return nil end
    return NZ.CoupleById(id)
end

function Actors.HasCouple() return couplePose() ~= nil end

-- Re-pose everyone (or only slot 1 + its couple partner)
function Actors.Refresh(mainOnly)
    if Couple.active then Couple.Stop() end
    local cp = couplePose()
    local main, partner = Actors.list[1], Actors.list[2]
    if cp then
        place(main)
        Actors.Strip(main)
        Actors.Strip(partner)
        Couple.Play(main.ped, partner.ped, cp.id)
    end
    for slot, a in pairs(Actors.list) do
        if not (cp and (slot == 1 or slot == 2)) and (not mainOnly or slot == 1 or (slot == 2 and partner and partner.kind == 'couple')) then
            place(a)
            Actors.ApplyPose(a)
        end
    end
end

-- ── squad ────────────────────────────────────────────────────────────────
local function spawnSquad(squad)
    if not squad or not Config.Squad.enabled or not Actors.char then return end
    local links = {}
    for _, l in ipairs(squad.links or {}) do
        if l.other and l.visible ~= false and (l.status == nil or l.status == 'accepted') then links[#links + 1] = l end
    end
    table.sort(links, function(x, y)
        if (x.type == 'couple') ~= (y.type == 'couple') then return x.type == 'couple' end
        return (tonumber(x.slot) or 9) < (tonumber(y.slot) or 9)
    end)
    local taken, hasCouple = {}, Config.Squad.couples and links[1] and links[1].type == 'couple'
    for _, l in ipairs(links) do
        local isCouple = l.type == 'couple' and Config.Squad.couples
        local slot = isCouple and 2 or tonumber(l.slot)
        if not slot or slot < 2 or slot > 4 or taken[slot] or (slot == 2 and hasCouple and not isCouple) then
            slot = nil
            for s = (hasCouple and 3 or 2), 4 do
                if not taken[s] then slot = s break end
            end
        end
        if slot then
            taken[slot] = true
            local o = l.other
            local a = human(o.model, o.gender, o.skin, slot, isCouple and 'couple' or 'squad')
            a.other, a.link = o, l
            Actors.list[slot] = a
        end
    end
end

-- ── pet ──────────────────────────────────────────────────────────────────
local function petFor()
    local c = Actors.char
    if not c then return nil end
    local pv = Actors.preview.pet
    local name = Actors.preview.petName
    if pv ~= nil then
        if pv == false or pv == 'none' or pv == '' then return nil end
        local def = NZ.PetById(pv)
        if not def then return nil end
        return { def = def, model = def.model, name = name or (c.prefs and c.prefs.petName) or (c.pet and c.pet.name) or def.label }
    end
    if not c.pet then return nil end
    local def = NZ.PetById(c.pet.id) or { id = c.pet.id, label = c.pet.name, model = c.pet.model, kind = 'dog' }
    return { def = def, model = c.pet.model or def.model, name = name or c.pet.name or def.label }
end

function Actors.RemovePet()
    local p = Actors.pet
    if not p then return end
    pcall(PetBridge.Removed, p.ped)
    U.Delete(p.ped)
    Actors.pet = nil
end

function Actors.SpawnPet()
    Actors.RemovePet()
    if not Config.Pets.enabled or not Scene.theme or Scene.theme.pets == false then return end
    local info = petFor()
    if not info then return end
    local okModel, custom = pcall(PetBridge.Model, info.def, info.name)
    local hash = U.Model((okModel and custom) or info.model)
    if not hash then return end
    local base = Scene.main
    local at = NZ.Place(base, Scene.theme.pet or PET_DEFAULT)
    -- Animals don't have the human 1.0 m root: stand the model's lowest point on the floor
    local floor = U.Floor(at.x, at.y, at.z) or (base.z - (Config.Scene.footHeight or 1.0))
    local min = GetModelDimensions(hash)
    local mark = vec4(at.x, at.y, floor - min.z, at.w)
    local ped = U.Ped(hash, mark, 28)
    local okIdle, custom2 = pcall(PetBridge.Idle, ped, info.def)
    if not (okIdle and custom2) then
        local idles = Config.Pets.idles and Config.Pets.idles[info.def.kind or 'dog']
        if idles and #idles > 0 then
            local i = idles[math.random(1, #idles)]
            U.Pose(ped, { dict = i.dict, clip = i.clip, flag = i.flag or 1 })
        end
    end
    Actors.pet = { ped = ped, def = info.def, name = info.name, mark = mark }
    pcall(PetBridge.Spawned, ped, info.def, info.name)
end

-- ── public ───────────────────────────────────────────────────────────────
function Actors.Clear()
    Actors.seq = Actors.seq + 1
    Actors.walking = false
    if Couple and Couple.active then Couple.Stop() end
    for _, a in pairs(Actors.list) do U.Delete(a.ped) end
    Actors.list = {}
    Actors.RemovePet()
end

function Actors.Show(char, squad)
    Actors.Clear()
    Actors.char, Actors.squad, Actors.preview = char, squad, {}
    if not char or not Scene.main then return end
    local a = human(char.model, char.gender, char.skin, 1, 'self')
    a.char = char
    Actors.list[1] = a
    spawnSquad(squad)
    Actors.SpawnPet()
    Actors.Refresh()
    Lights.Refresh()
end

-- Walk-in start: behind the mark (or beside it) on the same floor and clear of vehicles / props
local function clearOf(p)
    local ents = {}
    for _, v in pairs(Scene.vehicles) do ents[#ents + 1] = v end
    for _, o in ipairs(Scene.props) do ents[#ents + 1] = o end
    for _, e in ipairs(ents) do
        if DoesEntityExist(e) then
            local min, max = GetModelDimensions(GetEntityModel(e))
            local l = GetOffsetFromEntityGivenWorldCoords(e, p.x, p.y, p.z)
            if l.x > min.x - 0.3 and l.x < max.x + 0.3 and l.y > min.y - 0.3 and l.y < max.y + 0.3 then return false end
        end
    end
    return true
end

local function walkStart(mark)
    local fwd, right = NZ.Fwd(mark.w), NZ.Right(mark.w)
    local d = Config.Scene.walkInDistance or 1.4
    local dirs = { -fwd, (-fwd - right) * 0.7071, (-fwd + right) * 0.7071, -right, right, (fwd * 0.6 - right * 0.8), (fwd * 0.6 + right * 0.8) }
    for _, dir in ipairs(dirs) do
        local p = vec3(mark.x + dir.x * d, mark.y + dir.y * d, mark.z)
        local root = U.Ground(p.x, p.y, p.z)
        if math.abs(root - mark.z) < 0.35 and clearOf(vec3(p.x, p.y, root)) then
            local v = vec3(p.x, p.y, root)
            return vec4(v.x, v.y, v.z, NZ.HeadingTo(v, vec3(mark.x, mark.y, mark.z)))
        end
    end
end

-- Switch the selected character on the same theme: the new one walks onto the mark.
-- Non-blocking for the walk (Actors.walking is true until the main ped stands posed on its mark).
function Actors.SwapMain(char, squad)
    Actors.Clear()
    local my = Actors.seq
    Actors.char, Actors.squad, Actors.preview = char, squad, {}
    if not char or not Scene.main then return end
    local a = human(char.model, char.gender, char.skin, 1, 'self')
    a.char = char
    Actors.list[1] = a
    local start = Config.Scene.walkIn and not a.seat and walkStart(a.mark)
    if start then
        FreezeEntityPosition(a.ped, false)
        SetEntityCollision(a.ped, true, true)
        SetEntityCoordsNoOffset(a.ped, start.x, start.y, start.z, false, false, false)
        SetEntityHeading(a.ped, start.w)
        Actors.walking = true
    end
    spawnSquad(squad)
    Actors.SpawnPet()
    for slot, s in pairs(Actors.list) do
        if slot ~= 1 and not (slot == 2 and couplePose()) then Actors.ApplyPose(s) end
    end
    Lights.Refresh()
    if not start then return Actors.Refresh(true) end

    CreateThread(function()
        local m = a.mark
        -- TaskGoStraightToCoord(ped, x, y, z, speed (1.0 = walk), timeout, targetHeading, distanceToSlide)
        TaskGoStraightToCoord(a.ped, m.x, m.y, m.z, 1.0, 6000, m.w, 0.2)
        local deadline = GetGameTimer() + 5000
        while Actors.seq == my and DoesEntityExist(a.ped) and GetGameTimer() < deadline do
            if U.Dist2D(GetEntityCoords(a.ped), m) < 0.25 then break end
            Wait(50)
        end
        if Actors.seq ~= my then return end
        Actors.walking = false
        Actors.Refresh(true)
    end)
end

-- Squad changed (links / slots / visibility): rebuild slots 2..4 only
function Actors.SetSquad(squad)
    Actors.squad = squad
    if Couple.active then Couple.Stop() end
    for slot = 2, 4 do
        local a = Actors.list[slot]
        if a then U.Delete(a.ped) Actors.list[slot] = nil end
    end
    if not Actors.char then return end
    spawnSquad(squad)
    Actors.Refresh()
    Lights.Refresh()
end

-- Saved prefs changed (server returned the updated Character)
function Actors.SetChar(char, key)
    if not Actors.char or not char or Actors.char.id ~= char.id then return end
    char.skin = char.skin or Actors.char.skin
    char.model = char.model or Actors.char.model
    Actors.char = char
    if Actors.list[1] then Actors.list[1].char = char end
    if key then Actors.preview[key] = nil end
    if key == 'pet' then
        Actors.SpawnPet()
    elseif key == 'petName' then
        if Actors.pet then Actors.pet.name = (char.pet and char.pet.name) or char.prefs.petName or Actors.pet.name end
    elseif key == 'pose' or key == 'couplePose' or key == 'weapon' then
        Actors.Refresh()
    end
end

-- Live preview on the selected actor (slot 1). value = nil reverts to the saved value.
function Actors.Preview(slot, key, value)
    if (slot or 1) ~= 1 or not Actors.char then return end
    Actors.preview[key] = value
    if key == 'pose' or key == 'couplePose' or key == 'weapon' then
        Actors.Refresh()
    elseif key == 'pet' then
        Actors.SpawnPet()
    elseif key == 'petName' and Actors.pet then
        Actors.pet.name = value or (Actors.char.pet and Actors.char.pet.name) or Actors.pet.def.label
    end
end

-- Creation silhouette on the main mark. opaque = gender picked (default look, full alpha)
function Actors.Ghost(gender, opaque)
    Actors.Clear()
    Actors.char, Actors.squad, Actors.preview = nil, nil, {}
    if not Scene.main then return nil end
    local model = gender == 'f' and `mp_f_freemode_01` or `mp_m_freemode_01`
    local a = human(model, gender, nil, 1, 'ghost')
    if not opaque then SetEntityAlpha(a.ped, Config.Scene.ghostAlpha or 120, false) end
    Actors.list[1] = a
    Actors.ApplyPose(a)
    Lights.Refresh()
    return a
end

-- Actor by cutscene target name: 'main' | 'partner' | 'pet' | slot number
function Actors.Target(name)
    if name == nil or name == 'main' then return Actors.list[1] and Actors.list[1].ped end
    if name == 'partner' then return Actors.list[2] and Actors.list[2].ped end
    if name == 'pet' then return Actors.pet and Actors.pet.ped end
    local n = tonumber(name)
    return n and Actors.list[n] and Actors.list[n].ped or nil
end
