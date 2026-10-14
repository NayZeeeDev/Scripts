--[[
    NAYZEEE AMBULANCE - Client core: compatibility with other scripts

    Other resources (HUDs, inventories, phones, radios, emote menus, police scripts) need to
    know whether the player is down. They get it without depending on our internals:

    Exports (exports['nayzeee-ambulance']:<name>()):
      isDead()          → bool   cardiac arrest or dead (cannot act at all)
      IsDead()          → bool   same as isDead
      isPlayerDead()    → bool   same as isDead
      GetDeathStatus()  → bool   same as isDead (esx_ambulancejob style)
      isDowned()        → bool   any state other than 'alive' (wounded, arrest, dead)
      isPlayerDowned()  → bool   same as isDowned
      isInLastStand()   → bool   wounded (downed but conscious)
      GetState()        → 'alive'|'wounded'|'arrest'|'dead'
      GetSelfSnapshot() → last self snapshot table (what the player knows about themself)

    Own player state bags (replicated) kept in sync with the patient state:
      isDead, dead           arrest or dead
      inLastStand, laststand wounded
      isDowned               not alive
    ESX: local events 'esx:onPlayerDeath' (on going down) and 'esx:onPlayerSpawn' (on
    revive) so es_extended's PlayerData.dead and the scripts listening to it stay correct.

    Revives never come from third-party client events ('hospital:client:Revive',
    'esx_ambulancejob:revive', ...): those are trivially triggered by cheats, so they are
    deliberately NOT handled here. Revives only arrive as 'nza:revived' from our server;
    admin menus should use the server revive (see the core-server docs).
]]

if not NAYZEEE_LOCK_OK then return end

local lastDowned = false

local function state()
    return NZA.Self and NZA.Self.State and NZA.Self.State() or 'alive'
end

local function flags(st)
    return {
        dead = st == 'arrest' or st == 'dead',
        lastStand = st == 'wounded',
        downed = st ~= 'alive',
    }
end

local function setBag(key, value)
    local bag = LocalPlayer.state
    if bag[key] ~= value then bag:set(key, value, true) end
end

local function isEsx()
    return Bridge and Bridge.Framework == 'esx'
end

local function apply(st)
    local f = flags(st)
    setBag('isDead', f.dead)
    setBag('dead', f.dead)
    setBag('inLastStand', f.lastStand)
    setBag('laststand', f.lastStand)
    setBag('isDowned', f.downed)

    if f.downed ~= lastDowned then
        lastDowned = f.downed
        if isEsx() then
            if f.downed then
                local ped = PlayerPedId()
                TriggerEvent('esx:onPlayerDeath', {
                    victimCoords = GetEntityCoords(ped),
                    killedByPlayer = false,
                    deathCause = GetPedCauseOfDeath(ped),
                })
            else
                TriggerEvent('esx:onPlayerSpawn')
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

local function isDead() return flags(state()).dead end
local function isDowned() return flags(state()).downed end

exports('isDead', isDead)
exports('IsDead', isDead)
exports('isPlayerDead', isDead)
exports('GetDeathStatus', isDead)
exports('isDowned', isDowned)
exports('isPlayerDowned', isDowned)
exports('isInLastStand', function() return state() == 'wounded' end)
exports('GetState', function() return state() end)
exports('GetSelfSnapshot', function() return NZA.Self and NZA.Self.Get and NZA.Self.Get() or nil end)

-- ════════════════════════════════════════════════════════════════════════
-- WIRING
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    apply(new)
end)

NZA.Bus.On('self:revived', function()
    apply(state())
end)

CreateThread(function()
    Wait(1000)
    -- first sync (resource restart while down, or a stale bag from a previous session)
    lastDowned = LocalPlayer.state.isDowned == true
    apply(state())
end)
