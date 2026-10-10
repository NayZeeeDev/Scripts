-- Blips, nametags, relations, rally points and target invites. Loops only run while in a squad.
local Blips = {}   -- [serverId] = { blip, mode, ped, sig }
local Tags  = {}   -- [serverId] = { tag, ped, sig }
local relHash
local boost = false
local blipLoop, tagLoop = false, false
local rallyBlip

local NT = Config.Nametag
local AF = Config.Affiliations

local function memberPed(id)
    local player = GetPlayerFromServerId(id)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    return ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

local function isDowned(m)
    if m.downed then return true end
    local v = Squad and Squad.vitals and Squad.vitals[tostring(m.id)]
    return v ~= nil and v.h == 0
end

--- Everyone the player should see: their squad, plus allies when server and player allow it.
local function visibleMembers(forBlips)
    local out = {}
    if not Squad then return out end
    local me = Me()

    for i = 1, #Squad.members do
        local m = Squad.members[i]
        if m.online and m.id ~= me then
            out[#out + 1] = { id = m.id, name = m.name, rankName = m.rankName, downed = isDowned(m),
                              tag = Squad.tag, color = Squad.blipColor, sprite = Squad.blipSprite, ally = false }
        end
    end

    local shareOk = forBlips and AF.ShareBlips or (not forBlips and AF.ShareTags)
    local playerOk = forBlips and Settings.blipAllies or Settings.tagAllies
    if Config.Features.Affiliations and shareOk and playerOk and Squad.allyMembers then
        for sid, a in pairs(Squad.allyMembers) do
            local id = tonumber(sid)
            if id and id ~= me then
                out[#out + 1] = { id = id, name = a.name, rankName = a.rankName, downed = false, tag = a.tag,
                                  color = a.blipColor, sprite = a.blipSprite, ally = true, squadName = a.squad }
            end
        end
    end
    return out
end

-- ─── blips ─────────────────────────────────────────────────
local function removeBlip(id)
    local b = Blips[id]
    if b and DoesBlipExist(b.blip) then RemoveBlip(b.blip) end
    Blips[id] = nil
end

local function clearBlips() for id in pairs(Blips) do removeBlip(id) end end

local function blipColorFor(m)
    if Config.Features.SquadBlips and Settings.blipUseSquad and m.color then return m.color end
    return Settings.blipColor
end

local function blipSpriteFor(m)
    if not Config.Features.SquadBlips then return 1 end
    if m.ally then return Config.SquadBlip.AllySprite end
    return m.sprite or Config.SquadBlip.DefaultSprite
end

local function styleBlip(blip, m, entity)
    SetBlipSprite(blip, m.downed and 274 or blipSpriteFor(m))
    SetBlipColour(blip, m.downed and 1 or blipColorFor(m))
    SetBlipScale(blip, Config.SquadBlip.Scale)
    SetBlipCategory(blip, 7)
    SetBlipAsShortRange(blip, false)
    ShowHeadingIndicatorOnBlip(blip, entity and not m.downed)
    SetBlipAlpha(blip, m.ally and 190 or 255)

    local label = m.name
    if m.ally then label = ('%s [%s]'):format(m.name, m.squadName or 'Ally')
    elseif m.tag then label = ('[%s] %s'):format(m.tag, m.name) end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

local function updateBlips()
    local seen = {}
    local members = visibleMembers(true)

    for i = 1, #members do
        local m = members[i]
        seen[m.id] = true
        local sig = ('%s|%s|%s|%s|%s'):format(m.name, m.downed and 1 or 0, blipColorFor(m), blipSpriteFor(m), m.ally and 1 or 0)
        local rec, ped = Blips[m.id], memberPed(m.id)

        if ped then
            if not rec or rec.mode ~= 'entity' or rec.ped ~= ped then
                removeBlip(m.id)
                rec = { blip = AddBlipForEntity(ped), mode = 'entity', ped = ped, sig = sig }
                Blips[m.id] = rec
                styleBlip(rec.blip, m, true)
            end
        elseif not m.ally then
            local v = Squad.vitals and Squad.vitals[tostring(m.id)]
            if v and v.x then
                if not rec or rec.mode ~= 'coord' then
                    removeBlip(m.id)
                    rec = { blip = AddBlipForCoord(v.x + 0.0, v.y + 0.0, v.z + 0.0), mode = 'coord', sig = sig }
                    Blips[m.id] = rec
                    styleBlip(rec.blip, m, false)
                else
                    SetBlipCoords(rec.blip, v.x + 0.0, v.y + 0.0, v.z + 0.0)
                end
            elseif rec then
                removeBlip(m.id); rec = nil
            end
        elseif rec then
            removeBlip(m.id); rec = nil
        end

        if rec and rec.sig ~= sig then
            rec.sig = sig
            styleBlip(rec.blip, m, rec.mode == 'entity')
        end
    end

    for id in pairs(Blips) do
        if not seen[id] then removeBlip(id) end
    end
end

local function startBlips()
    if blipLoop or not Config.Features.Blips then return end
    blipLoop = true
    CreateThread(function()
        while Squad and Settings.blips do
            updateBlips()
            Wait(1000)
        end
        clearBlips()
        blipLoop = false
    end)
end

-- ─── nametags ──────────────────────────────────────────────
local TAG_NAME, TAG_CREW, TAG_HEALTH, TAG_BIGTEXT = 0, 1, 2, 3

local function removeTag(id)
    local t = Tags[id]
    if t and IsMpGamerTagActive(t.tag) then RemoveMpGamerTag(t.tag) end
    Tags[id] = nil
end

local function clearTags() for id in pairs(Tags) do removeTag(id) end end

local function buildTag(ped, m)
    local showTag    = NT.Tag and Settings.tagSquadTag and m.tag ~= nil and m.tag ~= ''
    local showRole   = NT.Role and Settings.tagRole and m.rankName ~= nil
    local showHealth = NT.Health and Settings.tagHealth
    local name = (NT.Name and Settings.tagName ~= false) and m.name or ' '
    local crew = showTag and m.tag or ''

    local tag = CreateFakeMpGamerTag(ped, name, false, false, crew, 0)
    local colour = m.ally and Config.TagColors[3][2] or Settings.tagColor

    SetMpGamerTagVisibility(tag, TAG_NAME, true)
    SetMpGamerTagColour(tag, TAG_NAME, colour)
    if showTag then
        SetMpGamerTagVisibility(tag, TAG_CREW, true)
        SetMpGamerTagColour(tag, TAG_CREW, colour)
    end
    if showHealth then
        SetMpGamerTagVisibility(tag, TAG_HEALTH, true)
        SetMpGamerTagHealthBarColour(tag, m.downed and 6 or colour)
    end
    if showRole then
        SetMpGamerTagBigText(tag, m.ally and ('%s · %s'):format(m.squadName or 'Ally', m.rankName) or m.rankName)
        SetMpGamerTagVisibility(tag, TAG_BIGTEXT, true)
        SetMpGamerTagColour(tag, TAG_BIGTEXT, colour)
    end
    SetMpGamerTagAlpha(tag, TAG_NAME, m.ally and 200 or 255)
    return tag
end

local function startTags()
    if tagLoop or not Config.Features.Tags then return end
    tagLoop = true
    CreateThread(function()
        while Squad and Settings.tags do
            local myCoords = GetEntityCoords(cache.ped)
            local range = Config.TagDistance * (boost and Config.TagBoostMultiplier or 1.0)
            local members, seen = visibleMembers(false), {}

            for i = 1, #members do
                local m = members[i]
                local ped = memberPed(m.id)
                if ped and #(GetEntityCoords(ped) - myCoords) <= range then
                    seen[m.id] = true
                    local sig = ('%s|%s|%s|%s|%s|%s%s%s%s'):format(
                        m.name, m.tag or '', m.rankName or '', m.downed and 1 or 0, Settings.tagColor,
                        Settings.tagName and 1 or 0, Settings.tagSquadTag and 1 or 0,
                        Settings.tagRole and 1 or 0, Settings.tagHealth and 1 or 0)
                    local t = Tags[m.id]
                    if not t or t.ped ~= ped or t.sig ~= sig or not IsMpGamerTagActive(t.tag) then
                        removeTag(m.id)
                        Tags[m.id] = { tag = buildTag(ped, m), ped = ped, sig = sig }
                    end
                end
            end
            for id in pairs(Tags) do
                if not seen[id] then removeTag(id) end
            end
            Wait(400)
        end
        clearTags()
        tagLoop = false
    end)
end

if Config.Features.Tags and Config.TagBoost then
    lib.addKeybind({
        name = 'nz_squads_tagboost',
        description = 'Squads: extend nametag distance (hold)',
        defaultMapper = Config.TagBoostMapper,
        defaultKey = Config.TagBoostKey,
        onPressed = function() boost = true end,
        onReleased = function() boost = false end,
    })
end

-- ─── rally point ───────────────────────────────────────────
local function clearRally()
    if rallyBlip and DoesBlipExist(rallyBlip) then RemoveBlip(rallyBlip) end
    rallyBlip = nil
end

local function setRally(rally)
    clearRally()
    if not rally then return end
    local colour = Squad and Squad.blipColor or Config.Rally.BlipColor
    rallyBlip = AddBlipForCoord(rally.x + 0.0, rally.y + 0.0, rally.z + 0.0)
    SetBlipSprite(rallyBlip, Config.Rally.Blip)
    SetBlipColour(rallyBlip, colour)
    SetBlipScale(rallyBlip, 1.0)
    SetBlipAsShortRange(rallyBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('Rally - %s'):format(rally.by or ''))
    EndTextCommandSetBlipName(rallyBlip)
    if Config.Rally.Route then
        SetBlipRoute(rallyBlip, true)
        SetBlipRouteColour(rallyBlip, colour)
    end
end

RegisterNetEvent('nz_squads:rally', function(rally)
    setRally(rally)
    if rally then
        Notify(('%s marked a rally point'):format(rally.by or 'A squadmate'), 'inform', 'rally')
        if not Settings.quiet then PlaySoundFrontend(-1, 'Waypoint_Set', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
    else
        Notify(Config.Strings.rally_clear, 'inform', 'rally')
    end
end)

-- ─── relations ─────────────────────────────────────────────
local function applyRelations()
    if not Config.Features.Relations then return end
    local ped = cache.ped
    if Squad then
        local key = ('NZSQUAD_%d'):format(Squad.id)
        if Config.Features.Affiliations and AF.Friendly and Squad.allies and #Squad.allies > 0 then
            local ids = { Squad.id }
            for i = 1, #Squad.allies do ids[#ids + 1] = Squad.allies[i].id end
            table.sort(ids)
            key = 'NZALLY_' .. table.concat(ids, '_')
        end
        local _, hash = AddRelationshipGroup(key)
        relHash = hash
        SetRelationshipBetweenGroups(0, hash, hash)
        SetPedRelationshipGroupHash(ped, hash)
        SetCanAttackFriendly(ped, false, false)
    elseif relHash then
        SetPedRelationshipGroupHash(ped, `PLAYER`)
        SetCanAttackFriendly(ped, true, false)
        relHash = nil
    end
end

lib.onCache('ped', function(ped)
    if not Squad or not relHash then return end
    SetTimeout(0, function()
        SetPedRelationshipGroupHash(ped, relHash)
        SetCanAttackFriendly(ped, false, false)
    end)
end)

-- ─── target invites ────────────────────────────────────────
if Config.Features.TargetInvite and GetResourceState('ox_target') == 'started' then
    exports.ox_target:addGlobalPlayer({
        {
            name = 'nz_squads_invite',
            icon = 'fa-solid fa-user-plus',
            label = 'Invite to squad',
            distance = 3.0,
            canInteract = function(entity)
                if not Squad or not Can('invite') then return false end
                local player = NetworkGetPlayerIndexFromPed(entity)
                if player == -1 then return false end
                local id = GetPlayerServerId(player)
                if id == Me() then return false end
                for i = 1, #Squad.members do
                    if Squad.members[i].id == id then return false end
                end
                return true
            end,
            onSelect = function(data)
                local player = NetworkGetPlayerIndexFromPed(data.entity)
                if player == -1 then return end
                local ok, msg = lib.callback.await('nz_squads:invite', false, GetPlayerServerId(player))
                Notify(msg or (ok and 'Invite sent' or 'Could not invite'), ok and 'success' or 'error', 'invite', true)
            end,
        },
    })
end

-- ─── wiring ────────────────────────────────────────────────
local function allySignature(sq)
    if not sq or not sq.allies then return '' end
    local ids = {}
    for i = 1, #sq.allies do ids[i] = sq.allies[i].id end
    table.sort(ids)
    return table.concat(ids, ',')
end

AddEventHandler('nz_squads:client:changed', function(prev, now)
    local allyChanged = allySignature(prev) ~= allySignature(now)
    if (prev and prev.id) ~= (now and now.id) or allyChanged then applyRelations() end

    if now then
        if Settings.blips then startBlips() end
        if Settings.tags then startTags() end
        if (prev and prev.tag) ~= now.tag or (prev and prev.blipColor) ~= now.blipColor
            or (prev and prev.blipSprite) ~= now.blipSprite or allyChanged then
            clearTags(); clearBlips()
        end
        if (prev and prev.rally and prev.rally.at) ~= (now.rally and now.rally.at) then setRally(now.rally) end
    else
        clearRally()
    end
end)

AddEventHandler('nz_squads:client:settings', function(prev, now)
    if not Squad then return end
    if now.blips and not prev.blips then startBlips() end
    if now.tags and not prev.tags then startTags() end
    if now.blipColor ~= prev.blipColor or now.blipUseSquad ~= prev.blipUseSquad or now.blipAllies ~= prev.blipAllies then clearBlips() end
    if now.tagColor ~= prev.tagColor or now.tagName ~= prev.tagName or now.tagSquadTag ~= prev.tagSquadTag
        or now.tagRole ~= prev.tagRole or now.tagHealth ~= prev.tagHealth or now.tagAllies ~= prev.tagAllies then clearTags() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    clearTags()
    clearRally()
    if relHash then
        SetPedRelationshipGroupHash(cache.ped, `PLAYER`)
        SetCanAttackFriendly(cache.ped, true, false)
    end
end)
