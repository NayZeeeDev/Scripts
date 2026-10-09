-- ═══════════════════════════════════════════════════════════════
--  DATA MODEL - read this first
--
--  A BODY is "who is inside":
--    { victimId, identifier, name, npc, baggedAt, dna = { 'Name', ... },
--      resolved, where = { type = 'container'|'barrel'|'trunk', key = netId } }
--    victimId   = server id of the online victim (nil for NPCs / once released)
--    resolved   = true once the body was destroyed (CK / respawn already handled)
--
--  A body is always stored in exactly ONE of these places:
--    Containers[netId] = { obj, kind = 'bodybag'|'crate'|'coffin', body, carrier }
--    Barrels[netId]    = { obj, body, burning }
--    Trunks[vehNetId]  = { veh, items = { { kind, body }, ... } }      (server/trunk.lua)
--    Graves[netId]     = { obj, kind, body, cemetery, digger, date, dbId }
--  Placed EMPTY crates/coffins live in Empties[netId] = { obj, kind }.
-- ═══════════════════════════════════════════════════════════════
Containers    = {}
Empties       = {}
Barrels       = {}
Graves        = {}
Trunks        = {}
BaggedVictims = {}  -- victim server id -> body  (online victims only)

local Pending = {}  -- bodies currently being bagged (stops two players bagging the same body)
local Chopped = {}  -- victim server id -> true  (one dismemberment per death)

local function kindToItem(kind)
    return ({ crate = Config.Items.bodyCrate, coffin = Config.Items.coffin, barrel = Config.Items.burnBarrel })[kind]
end

function GetStage(body)
    local stage = { label = 'fresh' }
    if not Config.Decomposition.Enabled or not body.baggedAt then return stage end
    local mins = (os.time() - body.baggedAt) / 60
    for _, s in ipairs(Config.Decomposition.Stages) do
        if mins >= s.after then stage = s end
    end
    return stage
end

-- what a body looks like to whoever inspects it
function DescribeBody(body, forPolice)
    local stage = GetStage(body)
    local identifiable = not body.npc and not body.dismembered and not stage.unidentifiable
    return {
        name  = identifiable and body.name or nil,
        npc   = body.npc,
        stage = stage.label,
        dna   = (forPolice and Config.Evidence.PoliceSeeDna) and body.dna or nil,
    }
end

-- ═══════════════════════════════════════════════════════════════
--  BODY LIFECYCLE
-- ═══════════════════════════════════════════════════════════════
function AddDna(body, src)
    if not Config.Evidence.Enabled or not Config.Evidence.DnaOnBagging or not src then return end
    local name = GetCharName(src)
    for _, n in ipairs(body.dna) do if n == name then return end end
    body.dna[#body.dna + 1] = name
end

-- victim = { id, identifier, name, npc }
local function newBody(src, victim)
    local body = {
        victimId = victim.id, identifier = victim.identifier, name = victim.name, npc = victim.npc ~= nil,
        baggedAt = os.time(), dna = {},
    }
    AddDna(body, src)
    if body.victimId and not GetPlayerName(body.victimId) then body.victimId = nil end -- logged off mid-bagging
    if body.victimId then
        BaggedVictims[body.victimId] = body
        Player(body.victimId).state:set('nzBagged', true, true)
        TriggerClientEvent('nayzeee-bodybag:client:youGotBagged', body.victimId)
    end
    return body
end

-- The victim is FREE again (body taken out, bag destroyed, revived...)
function ReleaseBody(body)
    if not body then return end
    -- a freed victim is alive again: this body must never CK / respawn them later
    body.identifier = nil
    if not body.victimId then return end
    local id = body.victimId
    body.victimId = nil
    BaggedVictims[id] = nil
    Player(id).state:set('nzBagged', false, true)
    TriggerClientEvent('nayzeee-bodybag:client:released', id)
end

-- The body is GONE for good (burned, dissolved, buried, dumped, chopped)
-- -> CK or respawn the victim, exactly once per body.
function DestroyBody(body, method)
    if not body or body.resolved then return end
    body.resolved = true
    local victimId = body.victimId
    body.victimId = nil
    if victimId then
        BaggedVictims[victimId] = nil
        Player(victimId).state:set('nzBagged', false, true)
    end
    if body.npc or not body.identifier then return end

    if Config.CK.Enabled and Config.CK.OnDisposal == 'ck' then
        -- works even if the victim logged off - the character is CKed by identifier
        PerformCK(body.identifier, body.name, victimId, method, 'Body Disposal', false)
    elseif victimId then
        TriggerClientEvent('nayzeee-bodybag:client:forceRespawn', victimId, method)
    end
end

-- ═══════════════════════════════════════════════════════════════
--  CONTAINERS (bag / crate / coffin holding a body)
-- ═══════════════════════════════════════════════════════════════
function AddContainer(obj, netId, kind, body)
    Containers[netId] = { obj = obj, kind = kind, body = body }
    body.where = { type = 'container', key = netId }
    Entity(obj).state:set('nzBody', { kind = kind, stage = GetStage(body).label }, true)
end

-- removes it from the registry + world. Returns the container data.
function RemoveContainer(netId, keepProp)
    local c = Containers[netId]
    if not c then return nil end
    Containers[netId] = nil
    if c.carrier then TriggerClientEvent('nayzeee-bodybag:client:containerGone', c.carrier, netId) end
    if DoesEntityExist(c.obj) then
        if keepProp then
            Entity(c.obj).state:set('nzBody', nil, true)
        else
            DeleteEntity(c.obj)
        end
    end
    return c
end

-- a container someone ELSE is carrying can't be touched
local function canTouch(src, c)
    return c and (not c.carrier or c.carrier == src) and IsNearEntity(src, c.obj)
end

-- ═══════════════════════════════════════════════════════════════
--  WHICH BODY? - the client sends { player = serverId } or { npc = pedNetId }
-- ═══════════════════════════════════════════════════════════════
local function resolveBodyRef(src, ref)
    if type(ref) ~= 'table' then return nil end

    if ref.player then
        local id = tonumber(ref.player)
        if not id or id == src or not GetPlayerName(id) then return nil, 'Invalid body' end
        if BaggedVictims[id] or Pending['p' .. id] then return nil, 'Someone is already dealing with that body' end
        local ped = GetPlayerPed(id)
        if not IsNearEntity(src, ped) then return nil, 'You\'re too far away' end
        if Config.OnlyDeadBodies and Config.ServerDeathCheck and not IsPlayerDeadServer(id) then
            return nil, 'They\'re still breathing...'
        end
        local xVictim = ESX.GetPlayerFromId(id)
        if not xVictim then return nil, 'Invalid body' end
        return {
            key = 'p' .. id, id = id, identifier = xVictim.identifier, name = xVictim.getName(),
            coords = GetEntityCoords(ped), heading = GetEntityHeading(ped),
        }
    end

    if ref.npc and Config.AllowNPCBodies then
        local ped = EntityFromNet(ref.npc)
        if not ped or GetEntityType(ped) ~= 1 or IsPedAPlayer(ped) then return nil, 'Invalid body' end
        if Pending['n' .. ref.npc] then return nil, 'Someone is already dealing with that body' end
        if GetEntityHealth(ped) > 100 then return nil, 'They\'re still breathing...' end
        if not IsNearEntity(src, ped) then return nil, 'You\'re too far away' end
        return { key = 'n' .. ref.npc, npc = ped, coords = GetEntityCoords(ped), heading = GetEntityHeading(ped) }
    end
    return nil, 'Invalid body'
end

-- ═══════════════════════════════════════════════════════════════
--  BAGGING
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:bagBody', function(ref)
    local src = source
    if not HasItem(src, Config.Items.bodybag) then return Notify(src, 'You need a body bag', 'error') end
    local victim, err = resolveBodyRef(src, ref)
    if not victim then return Notify(src, err or 'Invalid body', 'error') end

    Pending[victim.key] = true
    if not exports.ox_inventory:RemoveItem(src, Config.Items.bodybag, 1) then
        Pending[victim.key] = nil
        return
    end
    local obj, netId = SpawnProp('bodybag', victim.coords, victim.heading)
    Pending[victim.key] = nil
    if not obj then
        exports.ox_inventory:AddItem(src, Config.Items.bodybag, 1)
        return Notify(src, 'Failed to place the bag', 'error')
    end

    if victim.npc and DoesEntityExist(victim.npc) then DeleteEntity(victim.npc) end
    AddContainer(obj, netId, 'bodybag', newBody(src, victim))
    Log(src, 'BAGGED', victim.name or 'Unknown local (NPC)')
end)

-- ═══════════════════════════════════════════════════════════════
--  EMPTY CRATES / COFFINS / BARRELS - deploy & pack up
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:deployContainer', function(kind, coords, heading)
    local src = source
    local item = kindToItem(kind)
    if not item or not HasItem(src, item) then return end
    if not IsNear(src, coords, 4.0) then return end
    if not exports.ox_inventory:RemoveItem(src, item, 1) then return end

    local obj, netId = SpawnProp(kind, coords, heading)
    if not obj then
        exports.ox_inventory:AddItem(src, item, 1)
        return Notify(src, 'Failed to place it', 'error')
    end

    if kind == 'barrel' then
        Barrels[netId] = { obj = obj, body = nil, burning = false }
        Entity(obj).state:set('nzBarrel', true, true)
    else
        Empties[netId] = { obj = obj, kind = kind }
        Entity(obj).state:set('nzEmpty', kind, true)
    end
    Log(src, 'DEPLOYED', kind)
end)

RegisterNetEvent('nayzeee-bodybag:server:pickupEmpty', function(netId)
    local src = source
    local e = Empties[netId]
    if not e or not IsNearEntity(src, e.obj) then return end
    Empties[netId] = nil
    if DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    exports.ox_inventory:AddItem(src, kindToItem(e.kind), 1)
end)

-- dead body STRAIGHT into a nearby empty crate/coffin (no bag needed)
RegisterNetEvent('nayzeee-bodybag:server:directLoad', function(ref, targetNetId)
    local src = source
    if not Config.DirectLoad.Enabled then return end
    local e = Empties[targetNetId]
    if not e or not IsNearEntity(src, e.obj) then return end
    local victim, err = resolveBodyRef(src, ref)
    if not victim then return Notify(src, err or 'Invalid body', 'error') end
    if #(victim.coords - GetEntityCoords(e.obj)) > Config.DirectLoad.Radius + 2.0 then
        return Notify(src, 'The crate is too far from the body', 'error')
    end

    Empties[targetNetId] = nil
    Entity(e.obj).state:set('nzEmpty', nil, true)
    if victim.npc and DoesEntityExist(victim.npc) then DeleteEntity(victim.npc) end
    AddContainer(e.obj, targetNetId, e.kind, newBody(src, victim))
    Log(src, 'DIRECT_LOADED', ('%s -> %s'):format(victim.name or 'NPC', e.kind))
end)

-- ═══════════════════════════════════════════════════════════════
--  CARRYING - the server decides who holds what (no two people
--  can pick up the same bag)
-- ═══════════════════════════════════════════════════════════════
lib.callback.register('nayzeee-bodybag:claimCarry', function(src, netId)
    local c = Containers[netId]
    if not c then return 'There\'s nothing to pick up' end
    if c.carrier and c.carrier ~= src then return 'Someone else is carrying that' end
    if not IsNearEntity(src, c.obj) then return 'You\'re too far away' end
    c.carrier = src
    AddDna(c.body, src)
    return true
end)

RegisterNetEvent('nayzeee-bodybag:server:releaseCarry', function(netId)
    local c = Containers[netId]
    if c and c.carrier == source then c.carrier = nil end
end)

-- carried bag -> placed empty crate/coffin
lib.callback.register('nayzeee-bodybag:loadContainer', function(src, targetNetId, bagNetId)
    local e, c = Empties[targetNetId], Containers[bagNetId]
    if not e or not c or c.kind ~= 'bodybag' or c.carrier ~= src then return false end
    if not IsNearEntity(src, e.obj) then return false end
    Empties[targetNetId] = nil
    RemoveContainer(bagNetId)
    Entity(e.obj).state:set('nzEmpty', nil, true)
    AddDna(c.body, src)
    AddContainer(e.obj, targetNetId, e.kind, c.body)
    Log(src, 'LOADED', ('%s -> %s'):format(c.body.name or 'NPC', e.kind))
    return true
end)

-- ═══════════════════════════════════════════════════════════════
--  REMOVE BODY (out of a bag / crate / coffin)
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:removeBody', function(netId)
    local src = source
    if not Config.RemoveBody.Enabled then return end
    local c = Containers[netId]
    if not canTouch(src, c) then return end

    RemoveContainer(netId)
    ReleaseBody(c.body)
    if Config.RemoveBody.RefundContainer and kindToItem(c.kind) then
        exports.ox_inventory:AddItem(src, kindToItem(c.kind), 1)
    end
    if Config.RemoveBody.RefundBag and c.kind == 'bodybag' then
        exports.ox_inventory:AddItem(src, Config.Items.bodybag, 1)
    end
    Log(src, 'REMOVED_BODY', c.body.name or 'NPC')
end)

-- ═══════════════════════════════════════════════════════════════
--  DISMEMBERMENT (loose player body only)
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:dismember', function(victimId, usedPowersaw)
    local src = source
    if not Config.Dismember.Enabled then return end
    victimId = tonumber(victimId)
    local saw = usedPowersaw and Config.Items.powersaw or Config.Items.woodsaw
    if not victimId or not HasItem(src, saw) then return end
    if Chopped[victimId] then return Notify(src, 'This body has already been dismembered.', 'error') end

    local victim, err = resolveBodyRef(src, { player = victimId })
    if not victim then return Notify(src, err or 'Invalid body', 'error') end

    Chopped[victimId] = true
    Player(victimId).state:set('nzChopped', true, true)

    local label = Config.Dismember.HeadlessJohnDoe and 'Unidentifiable remains' or ('Remains of ' .. victim.name)
    for _, y in ipairs(Config.Dismember.Yields) do
        exports.ox_inventory:AddItem(src, y.item, y.count, { description = label })
    end
    Notify(src, 'You collected the remains.', 'success')

    if Config.Dismember.Blood.Enabled then
        TriggerClientEvent('nayzeee-bodybag:client:bloodDecal', -1, victim.coords)
        SaveEvidence('blood', victim.coords, GetCharName(src), { victim = victim.name })
    end
    PoliceAlert(victim.coords, 'Screams Reported', 'Someone heard a power tool and screaming.', 'dismember')

    DestroyBody({ victimId = victimId, identifier = victim.identifier, name = victim.name, dismembered = true }, 'dismembered')
    if not (Config.CK.Enabled and Config.CK.OnDisposal == 'ck') then
        -- respawn mode: they come back as a new body, so it can be chopped again next death
        SetTimeout(15000, function()
            Chopped[victimId] = nil
            if GetPlayerName(victimId) then Player(victimId).state:set('nzChopped', nil, true) end
        end)
    end
    Log(src, 'DISMEMBERED', victim.name)
end)

-- ═══════════════════════════════════════════════════════════════
--  BURN BARREL
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:pickupBarrel', function(netId)
    local src = source
    local b = Barrels[netId]
    if not b or b.body or b.burning or not IsNearEntity(src, b.obj) then return end
    Barrels[netId] = nil
    if DoesEntityExist(b.obj) then DeleteEntity(b.obj) end
    exports.ox_inventory:AddItem(src, Config.Items.burnBarrel, 1)
end)

lib.callback.register('nayzeee-bodybag:barrelLoad', function(src, barrelNetId, bagNetId)
    local b, c = Barrels[barrelNetId], Containers[bagNetId]
    if not b or b.body or b.burning or not c or c.kind ~= 'bodybag' or c.carrier ~= src then return false end
    if not IsNearEntity(src, b.obj) then return false end
    RemoveContainer(bagNetId)
    AddDna(c.body, src)
    b.body = c.body
    c.body.where = { type = 'barrel', key = barrelNetId }
    Entity(b.obj).state:set('nzBody', { kind = 'barrel', stage = GetStage(c.body).label }, true)
    return true
end)

-- take the (bagged) body back out of an unlit barrel
RegisterNetEvent('nayzeee-bodybag:server:barrelUnload', function(netId)
    local src = source
    local b = Barrels[netId]
    if not b or not b.body or b.burning or not IsNearEntity(src, b.obj) then return end
    local body = b.body
    b.body = nil
    Entity(b.obj).state:set('nzBody', nil, true)

    local c = GetEntityCoords(b.obj)
    local obj, bagNetId = SpawnProp('bodybag', vector3(c.x + 1.0, c.y, c.z), 0.0)
    if not obj then
        ReleaseBody(body)
        return
    end
    AddContainer(obj, bagNetId, 'bodybag', body)
end)

RegisterNetEvent('nayzeee-bodybag:server:barrelLight', function(netId)
    local src = source
    local b = Barrels[netId]
    if not b or not b.body or b.burning or not IsNearEntity(src, b.obj) then return end
    if Config.Cremation.RequiresMatches then
        if not HasItem(src, Config.Items.matches) then return Notify(src, 'You need matches', 'error') end
        exports.ox_inventory:RemoveItem(src, Config.Items.matches, 1)
    end

    b.burning = true
    Entity(b.obj).state:set('nzBurning', true, true)
    TriggerClientEvent('nayzeee-bodybag:client:barrelFire', -1, netId, true, src)
    local coords = GetEntityCoords(b.obj)
    PoliceAlert(coords, 'Suspicious Fire', 'Thick black smoke and a horrible smell reported.', 'cremation')
    Log(src, 'CREMATION_START', b.body.name or 'NPC')

    SetTimeout(Config.Cremation.BurnTime, function()
        local bb = Barrels[netId]
        if not bb or not bb.burning then return end
        local body = bb.body
        bb.body, bb.burning = nil, false
        TriggerClientEvent('nayzeee-bodybag:client:barrelFire', -1, netId, false)
        if DoesEntityExist(bb.obj) then
            Entity(bb.obj).state:set('nzBody', nil, true)
            Entity(bb.obj).state:set('nzBurning', nil, true)
        end
        if not body then return end

        -- a little DNA can survive the fire - it's written on the remains
        local dna = SurvivingDna(body.dna, Config.Cremation.EvidenceDestroyed)
        local meta = #dna > 0 and { description = 'Traces of DNA: ' .. table.concat(dna, ', ') } or nil
        if GetPlayerName(src) then -- the lighter may have logged off during the burn
            for _, y in ipairs(Config.Cremation.Yields) do
                if math.random(100) <= (y.chance or 100) then
                    exports.ox_inventory:AddItem(src, y.item, y.count, meta)
                end
            end
            Notify(src, 'The fire died down. Only ashes remain.', 'success')
        end
        DestroyBody(body, 'cremated')
        Log(src, 'CREMATED', body.name or 'NPC')
    end)
end)

-- ═══════════════════════════════════════════════════════════════
--  ACID
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:acidDissolve', function(netId)
    local src = source
    local c = Containers[netId]
    if not canTouch(src, c) or c.carrier then return end
    if not HasItem(src, Config.Items.acid) then return Notify(src, 'You need acid', 'error') end
    exports.ox_inventory:RemoveItem(src, Config.Items.acid, 1)

    local coords = GetEntityCoords(c.obj)
    RemoveContainer(netId)
    DestroyBody(c.body, 'dissolved')
    Notify(src, 'The body dissolved into nothing. No evidence remains.', 'success')
    PoliceAlert(coords, 'Chemical Smell', 'Neighbours report a strong chemical smell.', 'acid')
    Log(src, 'ACID_DISSOLVED', c.body.name or 'NPC')
end)

-- ═══════════════════════════════════════════════════════════════
--  BURIAL / EXHUME
-- ═══════════════════════════════════════════════════════════════
local burialsThisRestart = { cemetery = 0, shallow = 0 }

local function inBlockedZone(coords)
    for _, zone in ipairs(Config.Burial.BlockedZones) do
        if #(coords - zone.coords) < zone.radius then return true end
    end
    return false
end

local function inCemetery(coords)
    local cem = Config.Burial.Cemetery
    return cem.Enabled and #(coords - cem.Coords) < cem.Radius
end

-- spawn a grave prop + register it (used by burial AND by restoring graves after a restart)
local function createGrave(coords, heading, info)
    local obj, netId = SpawnProp(info.cemetery and 'tombstone' or 'shallowGrave', coords, heading)
    if not obj then return nil end
    info.obj = obj
    Graves[netId] = info
    Entity(obj).state:set('nzGrave', {
        cemetery = info.cemetery, name = info.cemetery and info.body.name or nil,
        date = info.date, digger = info.digger,
    }, true)
    return netId
end

RegisterNetEvent('nayzeee-bodybag:server:bury', function(netId)
    local src = source
    local c = Containers[netId]
    if not canTouch(src, c) or c.carrier then return end
    if not HasItem(src, Config.Items.shovel) then return Notify(src, 'You need a shovel', 'error') end

    local coords = GetEntityCoords(c.obj)
    if inBlockedZone(coords) then return Notify(src, 'You can\'t dig here', 'error') end

    -- burial limits per server restart (0 = unlimited)
    local cemetery = inCemetery(coords)
    local limits = Config.Burial.BurialsPerRestart or {}
    if cemetery and (limits.Cemetery or 0) > 0 and burialsThisRestart.cemetery >= limits.Cemetery then
        return Notify(src, 'The grave is already occupied. It won\'t fit another.', 'error')
    elseif not cemetery and (limits.Shallow or 0) > 0 and burialsThisRestart.shallow >= limits.Shallow then
        return Notify(src, 'The ground has been disturbed too much already.', 'error')
    end

    RemoveContainer(netId)
    local key = cemetery and 'cemetery' or 'shallow'
    burialsThisRestart[key] = burialsThisRestart[key] + 1

    local gCoords, gHeading = coords, GetEntityHeading(c.obj)
    if cemetery and Config.Burial.Cemetery.Tombstone then
        gCoords  = Config.Burial.Cemetery.Tombstone.Coords
        gHeading = Config.Burial.Cemetery.Tombstone.Heading
    end

    local body = c.body
    local info = {
        kind = c.kind, body = body, cemetery = cemetery,
        digger = GetIdentifier(src), date = os.date('%m/%d/%Y'),
    }
    DestroyBody(body, 'buried')
    if not createGrave(gCoords, gHeading, info) then
        print('[nayzeee-bodybag] ^1grave prop failed to spawn - body was still buried^0')
    end

    MySQL.insert('INSERT INTO nayzeee_bodybag_graves (coords, heading, data, cemetery) VALUES (?, ?, ?, ?)', {
        json.encode({ x = gCoords.x, y = gCoords.y, z = gCoords.z }), gHeading,
        json.encode({ kind = c.kind, name = body.name, identifier = body.identifier, npc = body.npc,
            dna = body.dna, digger = info.digger, date = info.date }),
        cemetery and 1 or 0,
    }, function(id) info.dbId = id end)

    Notify(src, cemetery and 'They rest in peace... for now.' or 'The body is buried. Shallow graves get found.', 'success')
    if not cemetery then
        PoliceAlert(coords, 'Suspicious Digging', 'Someone was seen digging and burying something.', 'burial')
    end
    Log(src, 'BURIED', ('%s (%s)'):format(body.name or 'NPC', key))
end)

RegisterNetEvent('nayzeee-bodybag:server:exhume', function(netId)
    local src = source
    local g = Graves[netId]
    if not g or not IsNearEntity(src, g.obj) then return end
    if not HasItem(src, Config.Items.shovel) then return Notify(src, 'You need a shovel', 'error') end
    local police = IsPolice(src)
    if not (Config.Burial.PoliceCanExhume and police) and g.digger ~= GetIdentifier(src) then
        return Notify(src, 'You have no reason to dig here', 'error')
    end

    Graves[netId] = nil
    if g.dbId then MySQL.update('DELETE FROM nayzeee_bodybag_graves WHERE id = ?', { g.dbId }) end
    local coords = GetEntityCoords(g.obj)
    DeleteEntity(g.obj)

    -- time in the ground destroys some of the DNA
    g.body.dna = SurvivingDna(g.body.dna, Config.Burial.EvidenceDestroyed)

    local obj, newNetId = SpawnProp(g.kind or 'bodybag', coords, 0.0)
    if obj then AddContainer(obj, newNetId, g.kind or 'bodybag', g.body) end

    local d = DescribeBody(g.body, police)
    local msg = ('You dug up %s.'):format(d.name and ('the remains of ' .. d.name) or 'an unidentifiable body')
    if d.dna and #d.dna > 0 then msg = msg .. ' DNA traces: ' .. table.concat(d.dna, ', ') end
    Notify(src, msg, 'inform', 'Exhumed')
    Log(src, 'EXHUMED', g.body.name or 'NPC')
end)

-- shallow graves come back after a restart
AddEventHandler('nayzeee-bodybag:databaseReady', function()
    if not Config.Burial.PersistShallowGraves then return end
    if (Config.Burial.GraveLifetimeDays or 0) > 0 then
        MySQL.update.await('DELETE FROM nayzeee_bodybag_graves WHERE created < (NOW() - INTERVAL ? DAY)',
            { Config.Burial.GraveLifetimeDays })
    end
    local rows = MySQL.query.await('SELECT * FROM nayzeee_bodybag_graves WHERE cemetery = 0') or {}
    local restored = 0
    for _, row in ipairs(rows) do
        local coords = ToVec3(json.decode(row.coords or 'null'))
        local data = json.decode(row.data or '{}') or {}
        if coords then
            local info = {
                kind = data.kind or 'bodybag', cemetery = false, digger = data.digger, date = data.date, dbId = row.id,
                body = { name = data.name, identifier = data.identifier, npc = data.npc, dna = data.dna or {}, resolved = true,
                    -- oxmysql returns DATETIME as a ms timestamp -> old bodies keep rotting
                    baggedAt = type(row.created) == 'number' and math.floor(row.created / 1000) or nil },
            }
            if createGrave(coords, row.heading, info) then restored = restored + 1 end
        end
    end
    if restored > 0 then print(('[nayzeee-bodybag] restored %d shallow grave(s)'):format(restored)) end
end)

-- ═══════════════════════════════════════════════════════════════
--  WATER DUMP
-- ═══════════════════════════════════════════════════════════════
local function nearDumpZone(src)
    for _, zone in ipairs(Config.WaterDump.Zones) do
        if IsNear(src, zone.coords, (zone.radius or 4.0) + 4.0) then return true end
    end
    return false
end

lib.callback.register('nayzeee-bodybag:waterDump', function(src, netId)
    local c = Containers[netId]
    if not c or c.carrier ~= src then return false end
    if Config.WaterDump.RequireCrate and c.kind == 'bodybag' then return false end
    if not nearDumpZone(src) then return false end

    Containers[netId] = nil -- prop stays a few seconds so the throw + splash plays out
    local obj = c.obj
    SetTimeout(5000, function() if DoesEntityExist(obj) then DeleteEntity(obj) end end)

    local coords = GetPlayerCoords(src)
    DestroyBody(c.body, 'dumped')
    PoliceAlert(coords, 'Splash Reported', 'Someone threw something heavy into the water.', 'waterDump')

    if c.kind == 'bodybag' and Config.WaterDump.BagWashAshore.Enabled then
        local cfg = Config.WaterDump.BagWashAshore
        SetTimeout(math.random(cfg.MinMins, cfg.MaxMins) * 60000, function()
            local spot = cfg.Spots[math.random(#cfg.Spots)]
            PoliceAlert(spot, 'Anonymous Tip', 'A body bag washed ashore. Check the marked beach.')
            SaveEvidence('washed_ashore', spot, c.body.name or 'unknown',
                { dna = SurvivingDna(c.body.dna, Config.WaterDump.EvidenceDestroyed) })
        end)
        Notify(src, 'The bag drifted out into the water...', 'success')
        Log(src, 'WATER_DUMP_RAW', c.body.name or 'NPC')
    else
        Notify(src, 'It sank into the depths. Gone forever.', 'success')
        Log(src, 'WATER_DUMP_SUNK', c.body.name or 'NPC')
    end
    return true
end)

-- ═══════════════════════════════════════════════════════════════
--  INSPECT (bags, crates, coffins and barrels)
-- ═══════════════════════════════════════════════════════════════
lib.callback.register('nayzeee-bodybag:inspect', function(src, netId)
    local holder = Containers[netId] or Barrels[netId]
    if not holder or not holder.body or not IsNearEntity(src, holder.obj) then return nil end
    return DescribeBody(holder.body, IsPolice(src))
end)

-- ═══════════════════════════════════════════════════════════════
--  REVIVED WHILE BAGGED -> climb out
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:victimRevived', function()
    local src = source
    local body = BaggedVictims[src]
    if not Config.ReleaseOnRevive or not body or IsPlayerDeadServer(src) then return end

    local where = body.where or {}
    if where.type == 'barrel' and Barrels[where.key] and Barrels[where.key].burning then return end -- too late
    if where.type == 'container' then
        local c = RemoveContainer(where.key, true)
        if c and c.kind ~= 'bodybag' and DoesEntityExist(c.obj) then
            -- crate/coffin stays where it is, empty again
            Empties[where.key] = { obj = c.obj, kind = c.kind }
            Entity(c.obj).state:set('nzEmpty', c.kind, true)
        elseif c and DoesEntityExist(c.obj) then
            DeleteEntity(c.obj)
        end
    elseif where.type == 'barrel' then
        local b = Barrels[where.key]
        if b and b.body == body and not b.burning then
            b.body = nil
            Entity(b.obj).state:set('nzBody', nil, true)
        end
    elseif where.type == 'trunk' then
        RemoveFromTrunk(where.key, body)
    end
    ReleaseBody(body)
    Log(src, 'REVIVED_IN_BAG', body.name)
end)

-- ═══════════════════════════════════════════════════════════════
--  SYNC + WATCHDOG (one loop for everything, every 2s)
--  - keeps each victim's invisible ped next to their body (voice range!)
--  - frees victims whose prop got deleted by something else
-- ═══════════════════════════════════════════════════════════════
local function syncVictim(body, coords)
    if body and body.victimId then
        TriggerClientEvent('nayzeee-bodybag:client:syncToBag', body.victimId, coords)
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        for netId, c in pairs(Containers) do
            if not DoesEntityExist(c.obj) then
                Containers[netId] = nil
                Log(nil, 'ORPHANED', ('%s vanished, victim released'):format(c.kind))
                ReleaseBody(c.body)
                if c.carrier then Notify(c.carrier, 'The ' .. c.kind .. ' was destroyed.', 'error') end
            else
                syncVictim(c.body, GetEntityCoords(c.obj))
            end
        end
        for netId, b in pairs(Barrels) do
            if not DoesEntityExist(b.obj) then
                Barrels[netId] = nil
                ReleaseBody(b.body)
            elseif b.body then
                syncVictim(b.body, GetEntityCoords(b.obj))
            end
        end
        for netId, e in pairs(Empties) do
            if not DoesEntityExist(e.obj) then Empties[netId] = nil end
        end
        for netId, g in pairs(Graves) do
            if not DoesEntityExist(g.obj) then Graves[netId] = nil end
        end
        SyncTrunks(syncVictim)
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  DECOMPOSITION - stage updates + smell for anyone nearby
-- ═══════════════════════════════════════════════════════════════
if Config.Decomposition.Enabled then
    local lastSmell = {} -- player id -> os.time()

    local function smellAround(coords, radius)
        if not radius or radius <= 0 then return end
        local now = os.time()
        for _, id in ipairs(GetPlayers()) do
            local pid = tonumber(id)
            local pc = GetPlayerCoords(pid)
            if pc and #(pc - coords) < radius and now - (lastSmell[pid] or 0) >= Config.Decomposition.SmellCooldown then
                lastSmell[pid] = now
                TriggerClientEvent('nayzeee-bodybag:client:smell', pid)
            end
        end
    end

    AddEventHandler('playerDropped', function() lastSmell[source] = nil end)

    CreateThread(function()
        while true do
            Wait(30000)
            for _, c in pairs(Containers) do
                if DoesEntityExist(c.obj) then
                    local stage = GetStage(c.body)
                    local state = Entity(c.obj).state.nzBody
                    if not state or state.stage ~= stage.label then
                        Entity(c.obj).state:set('nzBody', { kind = c.kind, stage = stage.label }, true)
                    end
                    smellAround(GetEntityCoords(c.obj), stage.smellRadius)
                end
            end
            for _, b in pairs(Barrels) do
                if b.body and DoesEntityExist(b.obj) then smellAround(GetEntityCoords(b.obj), GetStage(b.body).smellRadius) end
            end
            for _, t in pairs(Trunks) do
                if DoesEntityExist(t.veh) then
                    for _, item in ipairs(t.items) do smellAround(GetEntityCoords(t.veh), GetStage(item.body).smellRadius) end
                end
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  CLEANUP - never leave a victim stuck in the dark
-- ═══════════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, c in pairs(Containers) do
        ReleaseBody(c.body)
        if DoesEntityExist(c.obj) then DeleteEntity(c.obj) end
    end
    for _, b in pairs(Barrels) do
        ReleaseBody(b.body)
        if DoesEntityExist(b.obj) then DeleteEntity(b.obj) end
    end
    for _, t in pairs(Trunks) do
        for _, item in ipairs(t.items) do ReleaseBody(item.body) end
        if DoesEntityExist(t.veh) then Entity(t.veh).state:set('nzTrunk', nil, true) end
    end
    for _, g in pairs(Graves) do
        if DoesEntityExist(g.obj) then DeleteEntity(g.obj) end
    end
    for _, e in pairs(Empties) do
        if DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Chopped[src] = nil
    -- a bagged victim logging off keeps their body in the bag (disposal still CKs them)
    local body = BaggedVictims[src]
    if body then
        body.victimId = nil
        BaggedVictims[src] = nil
    end
    for _, c in pairs(Containers) do
        if c.carrier == src then c.carrier = nil end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  ITEM USE (ox_inventory server exports - see README)
-- ═══════════════════════════════════════════════════════════════
local function useItem(itemName)
    return function(event, item, inventory)
        if event == 'usingItem' then
            TriggerClientEvent('nayzeee-bodybag:client:useItem', inventory.id, itemName)
            return false -- don't consume - the server removes it once it's actually placed
        end
    end
end

exports('useCrate',  useItem(Config.Items.bodyCrate))
exports('useCoffin', useItem(Config.Items.coffin))
exports('useBarrel', useItem(Config.Items.burnBarrel))
exports('useGasmask', function(event, item, inventory)
    if event == 'usingItem' then
        TriggerClientEvent('nayzeee-bodybag:client:toggleGasmask', inventory.id)
        return false
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  EXPORTS for other resources
-- ═══════════════════════════════════════════════════════════════
-- exports['nayzeee-bodybag']:IsBagged(serverId) -> true if that player is inside a bag/crate/trunk
exports('IsBagged', function(serverId) return BaggedVictims[tonumber(serverId)] ~= nil end)

-- exports['nayzeee-bodybag']:GetActiveCounts() -> { containers, barrels, trunks, graves }
exports('GetActiveCounts', function()
    local n = { containers = 0, barrels = 0, trunks = 0, graves = 0 }
    for _ in pairs(Containers) do n.containers = n.containers + 1 end
    for _, b in pairs(Barrels) do if b.body then n.barrels = n.barrels + 1 end end
    for _, t in pairs(Trunks) do n.trunks = n.trunks + #t.items end
    for _ in pairs(Graves) do n.graves = n.graves + 1 end
    return n
end)
