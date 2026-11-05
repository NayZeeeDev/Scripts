-- ═══════════════════════════════════════════════════════════════
--  ACTION MENUS
--  Every object has ONE third-eye option that opens a menu here.
--  Every action shows what it does; if you can't do it yet it is
--  greyed out and tells you exactly what's missing.
-- ═══════════════════════════════════════════════════════════════

local LOCKED_COLOR = '#5c6670'

-- actions = { { title, description, icon, available = bool, reason = 'why not',
--               hidden = bool, metadata = {...}, onSelect = fn }, ... }
function ShowActions(id, title, actions, menu)
    local options = {}
    for _, a in ipairs(actions) do
        if not a.hidden then
            local ok = a.available ~= false
            options[#options + 1] = {
                title       = a.title,
                description = ok and a.description or ('Locked: ' .. (a.reason or 'not available')),
                icon        = a.icon,
                iconColor   = ok and Config.UI.Accent or LOCKED_COLOR,
                disabled    = not ok,
                readOnly    = a.readOnly,
                metadata    = a.metadata,
                arrow       = a.arrow,
                onSelect    = (ok and a.onSelect) and function() CreateThread(a.onSelect) end or nil,
            }
        end
    end
    if #options == 0 then options[1] = { title = 'Nothing to do here', icon = 'circle-info', disabled = true } end
    lib.registerContext({ id = id, title = title, menu = menu, options = options })
    lib.showContext(id)
end

local function seconds(ms) return ('%ds'):format(math.floor((ms or 0) / 1000)) end

local function sawAvailable()
    return HasItem(Config.Items.powersaw) or HasItem(Config.Items.woodsaw)
end

local function burialSpot(coords)
    for _, zone in ipairs(Config.Burial.BlockedZones) do
        if #(coords - zone.coords) < zone.radius then return 'blocked' end
    end
    local cem = Config.Burial.Cemetery
    if cem.Enabled and #(coords - cem.Coords) < cem.Radius then return 'cemetery' end
    return 'shallow'
end

local function coronerAction(coords)
    return {
        title = 'Call The Coroner', icon = 'phone',
        hidden = not (FuneralEnabled() and Config.Funeral.CoronerCalls.Enabled),
        description = 'The funeral home is told where to collect the body.',
        onSelect = function() CallCoroner(coords) end,
    }
end

-- ═══════════════════════════════════════════════════════════════
--  LOOSE DEAD BODY
-- ═══════════════════════════════════════════════════════════════
function OpenBodyMenu(ped)
    local isPlayer = IsPedAPlayer(ped)
    local sid = isPlayer and ServerIdOfPed(ped)
    local chopped = sid and Player(sid).state.nzChopped
    local coords = GetEntityCoords(ped)
    local empty = NearbyEmpty(coords)

    ShowActions('nz_body', isPlayer and 'Dead Body' or 'Dead Local', {
        { title = 'Place In Body Bag', icon = 'bag-shopping',
          description = 'Zip them in so you can carry, hide or dispose of the body.',
          metadata = { { label = 'Needs', value = ItemLabel(Config.Items.bodybag) }, { label = 'Time', value = seconds(Config.BagTime) } },
          available = HasItem(Config.Items.bodybag), reason = 'You need a body bag',
          onSelect = function() BagBody(ped) end },
        { title = 'Put In The Crate / Coffin Next To It', icon = 'box-open', hidden = not Config.DirectLoad.Enabled,
          description = 'Straight in - no bag needed.',
          metadata = { { label = 'Time', value = seconds(Config.LoadTime) } },
          available = empty ~= nil,
          reason = ('Place an empty crate or coffin within %.0fm of the body'):format(Config.DirectLoad.Radius),
          onSelect = function() DirectLoad(ped) end },
        { title = 'Dismember', icon = 'scissors', hidden = not isPlayer or not Config.Dismember.Enabled,
          description = 'You get the remains. Leaves blood everywhere. They can never be identified.',
          metadata = { { label = 'Needs', value = 'Power Saw or Wood Saw' } },
          available = sawAvailable() and not chopped,
          reason = chopped and 'Already dismembered' or 'You need a power saw or a wood saw',
          onSelect = function() DismemberBody(ped) end },
        coronerAction(coords),
    })
end

-- ═══════════════════════════════════════════════════════════════
--  BAG / CRATE / COFFIN
-- ═══════════════════════════════════════════════════════════════
local function openEmptyMenu(ent, kind)
    ShowActions('nz_empty', KindLabel(kind) .. '  •  empty', {
        { title = 'Load The Body You\'re Carrying', icon = 'box-archive',
          description = kind == 'crate' and 'Sealed crates sink for good when dumped in the water.'
              or 'A coffin can be buried - at the cemetery it gets a tombstone.',
          metadata = { { label = 'Time', value = seconds(Config.LoadTime) } },
          available = Carrying.kind == 'bodybag',
          reason = Carrying.entity and 'Only body bags go inside' or 'Carry a body bag here first (or third-eye a body next to it)',
          onSelect = function() LoadIntoPlaced(ent) end },
        { title = 'Pack It Up', icon = 'hand', description = 'Put the item back in your inventory.',
          available = not Carrying.entity, reason = 'Your hands are full',
          onSelect = function() PackUpEmpty(ent) end },
    })
end

function OpenContainerMenu(ent)
    local s = Entity(ent).state
    if s.nzEmpty then return openEmptyMenu(ent, s.nzEmpty) end
    local info = s.nzBody
    if not info then return end

    local kind = info.kind
    local coords = GetEntityCoords(ent)
    local spot = burialSpot(coords)
    local hands = Carrying.entity ~= nil
    local masked = IsMaskOn()

    ShowActions('nz_container', ('%s  •  %s'):format(KindLabel(kind), info.stage or 'fresh'), {
        { title = 'Pick Up', icon = 'hand',
          description = ('Carry it. Press [%s] while carrying to see where it can go.'):format(Config.CarryMenuKey),
          available = not hands, reason = 'Your hands are full',
          onSelect = function() StartCarrying(ent, kind) end },
        { title = 'Inspect', icon = 'magnifying-glass', description = 'Who is it, and what state is the body in?',
          onSelect = function() InspectBody(ent) end },
        { title = spot == 'cemetery' and 'Bury (Cemetery)' or 'Bury (Shallow Grave)', icon = 'trowel',
          description = spot == 'cemetery' and 'A tombstone with their name marks the grave.'
              or 'Leaves a dirt pile. Police can find it and dig it up.',
          metadata = { { label = 'Needs', value = ItemLabel(Config.Items.shovel) }, { label = 'Time', value = seconds(Config.Burial.DigTime) } },
          available = spot ~= 'blocked' and HasItem(Config.Items.shovel) and not hands,
          reason = spot == 'blocked' and 'The ground here is too hard - move somewhere else'
              or (hands and 'Put down what you are carrying' or 'You need a shovel'),
          onSelect = function() BuryContainer(ent) end },
        { title = 'Dissolve With Acid', icon = 'flask', hidden = kind ~= 'bodybag',
          description = masked and 'Gas mask on - you\'re protected. Nothing will be left.'
              or 'No gas mask on: the fumes will hurt you. Use your gas mask item first.',
          metadata = { { label = 'Needs', value = ItemLabel(Config.Items.acid) }, { label = 'Time', value = seconds(Config.Acid.DissolveTime) } },
          available = HasItem(Config.Items.acid) and not hands,
          reason = hands and 'Put down what you are carrying' or 'You need acid',
          onSelect = function() AcidDissolve(ent) end },
        { title = 'Take The Body Out', icon = 'person-falling', hidden = not Config.RemoveBody.Enabled,
          description = 'Opens it up. If the victim is a player, they are free again.',
          available = not hands, reason = 'Your hands are full',
          onSelect = function() RemoveBodyFrom(ent) end },
        coronerAction(coords),
    })
end

-- ═══════════════════════════════════════════════════════════════
--  BURN BARREL
-- ═══════════════════════════════════════════════════════════════
function OpenBarrelMenu(ent)
    local s = Entity(ent).state
    local full, burning, hands = s.nzBody ~= nil, s.nzBurning == true, Carrying.entity ~= nil
    local needsMatches = Config.Cremation.RequiresMatches

    ShowActions('nz_barrel', KindLabel('barrel') .. (burning and '  •  BURNING' or (full and '  •  loaded' or '  •  empty')), {
        { title = 'Load The Body You\'re Carrying', icon = 'box-archive',
          description = 'Drop the body bag inside, then light it.',
          available = not full and not burning and Carrying.kind == 'bodybag',
          reason = burning and 'It\'s burning' or (full and 'There\'s already a body inside' or 'Carry a body bag here first'),
          onSelect = function() LoadBarrel(ent) end },
        { title = 'Light It Up', icon = 'fire',
          description = ('Burns for %s. You get the ashes (and maybe a skull). Smoke can be reported.'):format(seconds(Config.Cremation.BurnTime)),
          metadata = needsMatches and { { label = 'Needs', value = ItemLabel(Config.Items.matches) } } or nil,
          available = full and not burning and (not needsMatches or HasItem(Config.Items.matches)),
          reason = burning and 'Already burning' or (not full and 'Load a body first' or 'You need matches'),
          onSelect = function() LightBarrel(ent) end },
        { title = 'Look Inside', icon = 'magnifying-glass', available = full and not burning,
          reason = burning and 'Too hot to look' or 'It\'s empty',
          onSelect = function() InspectBody(ent) end },
        { title = 'Take The Body Out', icon = 'person-falling', available = full and not burning and not hands,
          reason = burning and 'Too late - it\'s burning' or (not full and 'It\'s empty' or 'Your hands are full'),
          onSelect = function() UnloadBarrel(ent) end },
        { title = 'Pack Up The Barrel', icon = 'hand', available = not full and not burning and not hands,
          reason = burning and 'Wait for the fire to die' or (full and 'Take the body out first' or 'Your hands are full'),
          onSelect = function() PackUpBarrel(ent) end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  GRAVES + HEADSTONES
-- ═══════════════════════════════════════════════════════════════
function OpenGraveMenu(ent)
    local s = Entity(ent).state
    local m = s.nzMemorial
    if m then
        return ShowActions('nz_memorial', 'In Loving Memory', {
            { title = m.name or 'Unknown', icon = 'cross', readOnly = true,
              description = ('%s%s'):format(m.epitaph and m.epitaph ~= '' and ('"' .. m.epitaph .. '"  \n') or '', 'Laid to rest ' .. (m.died or '')),
              metadata = { { label = 'Respects paid', value = m.respects or 0 }, { label = 'Flowers laid', value = m.flowers or 0 } } },
            { title = 'Pay Your Respects', icon = 'hands-praying', description = 'Take a moment at the grave.',
              onSelect = function() PayRespects(ent, m.plot) end },
            { title = 'Lay Flowers', icon = 'seedling', description = 'Flowers are sold at the funeral home.',
              available = HasItem(Config.Items.flowers), reason = 'You need flowers',
              onSelect = function() LayFlowers(ent, m.plot) end },
            { title = 'Clear This Plot', icon = 'trash', hidden = not IsFuneralJob('ClearPlot'),
              description = 'Director only: removes the headstone and frees the plot.',
              onSelect = function()
                  if lib.alertDialog({ header = 'Clear plot?', content = ('Remove the headstone of **%s**?'):format(m.name or '?'),
                      centered = true, cancel = true }) == 'confirm' then
                      TriggerServerEvent('nayzeee-bodybag:server:memorialClear', m.plot)
                  end
              end },
        })
    end

    local g = s.nzGrave
    if not g then return end
    local me = ESX.GetPlayerData()
    local mine = me and me.identifier ~= nil and g.digger == me.identifier
    local allowed = mine or (Config.Burial.PoliceCanExhume and IsPoliceJob())
    ShowActions('nz_grave', g.cemetery and 'Grave' or 'Disturbed Earth', {
        { title = 'Look At The Grave', icon = 'magnifying-glass', onSelect = function() InspectGrave(ent) end,
          description = g.cemetery and 'Read the tombstone.' or 'Someone dug here recently...' },
        { title = 'Exhume', icon = 'trowel',
          description = 'Dig the body back up. It comes out in whatever it was buried in.',
          metadata = { { label = 'Needs', value = ItemLabel(Config.Items.shovel) }, { label = 'Time', value = seconds(Config.Burial.ExhumeTime) } },
          available = allowed and HasItem(Config.Items.shovel),
          reason = not allowed and 'Only whoever dug it (or the police) knows what\'s down there' or 'You need a shovel',
          onSelect = function() ExhumeGrave(ent) end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  [H] WHILE CARRYING - "what can I do RIGHT HERE?"
-- ═══════════════════════════════════════════════════════════════
function OpenCarryMenu()
    if not Carrying.entity then return end
    local me = GetEntityCoords(cache.ped)
    local kind = Carrying.kind
    local isBag = kind == 'bodybag'

    local empty = isBag and NearbyEmpty(me, 3.0)
    local barrel = isBag and FindNearbyObject(me, 3.0, function(s) return s.nzBarrel and not s.nzBody and not s.nzBurning end)
    local veh = TrunkVehicleNearMe()
    local canTrunk, trunkWhy = false, 'Stand at the back of a vehicle'
    if veh then canTrunk, trunkWhy = CanLoadTrunk(veh) end
    local cem = Config.Burial.Cemetery
    local atHole = cem.Enabled and #(me - cem.Coords) < 3.0
    local atDump = AtDumpZone()
    local funeral = FuneralEnabled()
    local atMorgue = funeral and #(me - Config.Funeral.Locations.Morgue) < 3.0
    local plot, plotState = nil, nil
    if funeral then plot, plotState = NearestPlot(me, 4.0) end

    ShowActions('nz_carry', 'Carrying: ' .. KindLabel(kind), {
        { title = 'Put It Down', icon = 'hand', description = ('Or just press [%s].'):format(Config.DropKey),
          onSelect = function() StopCarrying(true) end },
        { title = 'Load Into The Crate / Coffin Here', icon = 'box-archive',
          description = 'Seal the body bag inside the empty crate or coffin next to you.',
          available = empty ~= nil and empty ~= false,
          reason = not isBag and 'Only body bags fit inside' or 'No empty crate or coffin within 3m',
          onSelect = function() LoadIntoPlaced(empty) end },
        { title = 'Load Into The Burn Barrel Here', icon = 'fire',
          description = 'Then light it with matches.',
          available = barrel ~= nil and barrel ~= false,
          reason = not isBag and 'Only body bags fit in a barrel' or 'No empty burn barrel within 3m',
          onSelect = function() LoadBarrel(barrel) end },
        { title = 'Put In This Vehicle\'s Trunk', icon = 'car-rear', hidden = not Config.Trunk.Enabled,
          description = 'Drive the body somewhere else.',
          available = canTrunk, reason = trunkWhy,
          onSelect = function() PutInTrunk(veh) end },
        { title = 'Lower Into The Open Grave', icon = 'arrow-down', hidden = not cem.Enabled,
          description = 'Then bury it with a shovel - it gets a tombstone with their name.',
          available = atHole, reason = 'Go to the open grave at the cemetery',
          onSelect = PlaceInGraveHole },
        { title = 'Dump In The Water', icon = 'water',
          description = kind == 'bodybag' and 'Bags float and can wash ashore later. Crates sink for good.'
              or 'It sinks. Gone forever.',
          available = atDump and not (Config.WaterDump.RequireCrate and isBag),
          reason = (atDump and 'The bag would float - it needs a weighted crate')
              or 'Go to a dump spot (piers / docks - see /' .. Config.HelpCommand .. ')',
          onSelect = DumpCarried },
        { title = 'Store In The Morgue', icon = 'temperature-low', hidden = not (funeral and IsFuneralJob()),
          description = 'Log the body. You get paid. From the records you can hold a funeral.',
          available = atMorgue and IsFuneralJob('Morgue'), reason = 'Go to the morgue at the funeral home',
          onSelect = StoreInMorgue },
        { title = 'Place Casket On This Plot', icon = 'cross', hidden = not (funeral and IsFuneralJob('Service')),
          description = 'Start of a funeral service.',
          available = kind == 'coffin' and plot ~= nil and plotState == 'free',
          reason = kind ~= 'coffin' and 'You need to carry a coffin'
              or (plot and 'This plot is taken' or 'Stand at a free cemetery plot'),
          onSelect = function() PlaceCasket(plot) end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  TOOL TIPS - using a tool item explains how it works
-- ═══════════════════════════════════════════════════════════════
local toolTips = {
    [Config.Items.bodybag]  = 'Third-eye a dead body -> Handle Body -> Place In Body Bag.',
    [Config.Items.shovel]   = 'Third-eye a body bag, crate or coffin -> Bury. At the cemetery, lower it into the open grave first for a real tombstone.',
    [Config.Items.powersaw] = 'Third-eye a dead body -> Handle Body -> Dismember. Fast, but loud.',
    [Config.Items.woodsaw]  = 'Third-eye a dead body -> Handle Body -> Dismember. Slow but it works.',
    [Config.Items.acid]     = 'Put your gas mask ON first, then third-eye a body bag -> Dissolve With Acid.',
    [Config.Items.matches]  = 'Load a body into a burn barrel, then third-eye the barrel -> Light It Up.',
    [Config.Items.flowers]  = 'Third-eye a headstone at the cemetery -> Lay Flowers.',
}

RegisterNetEvent('nayzeee-bodybag:client:toolTip', function(item)
    Config.Notify(toolTips[item] or ('Type /%s to see how everything works.'):format(Config.HelpCommand), 'inform', ItemLabel(item))
end)

-- ═══════════════════════════════════════════════════════════════
--  /bodyhelp - THE IN-GAME GUIDE
-- ═══════════════════════════════════════════════════════════════
local function gpsTo(coords, label)
    return { title = 'Set GPS: ' .. label, icon = 'location-dot', description = 'Marks it on your map.',
        onSelect = function()
            SetNewWaypoint(coords.x, coords.y)
            Config.Notify('GPS set.', 'success')
        end }
end

local function nearestDump()
    local me, best, bestDist = GetEntityCoords(cache.ped), nil, math.huge
    for _, z in ipairs(Config.WaterDump.Zones) do
        local d = #(me - z.coords)
        if d < bestDist then best, bestDist = z.coords, d end
    end
    return best
end

local function ckSentence()
    if Config.CK.Enabled and Config.CK.OnDisposal == 'ck' then
        return 'On this server a destroyed body = that character is PERMANENTLY dead (CK).'
    end
    return 'On this server a destroyed body = the victim wakes up in hospital and forgets (NLR).'
end

local function guideSections()
    local I = Config.Items
    local sections = {
        { title = 'Start Here', icon = 'circle-info', steps = {
            'Everything works with third-eye. Each object has ONE option that opens its menu.',
            'Greyed-out actions tell you exactly what you are missing.',
            ('While carrying a body press [%s] to see what you can do where you stand. [%s] puts it down.'):format(Config.CarryMenuKey, Config.DropKey),
            ckSentence(),
        } },
        { title = 'Bag & Carry A Body', icon = 'bag-shopping', items = { I.bodybag }, steps = {
            'Third-eye a dead body -> Handle Body -> Place In Body Bag.',
            'Third-eye the bag -> Pick Up. Only one person can carry it.',
            'Going down or getting tackled makes you drop it.',
        } },
        { title = 'Crates & Coffins', icon = 'box', items = { I.bodyCrate, I.coffin }, steps = {
            'Use the item to place it on the ground.',
            'Carry a body bag to it and load it in - or put a body straight in from right next to it.',
            'Crates sink for good in the water. Coffins are for burials.',
        } },
        { title = 'Vehicle Trunks', icon = 'car-rear', hidden = not Config.Trunk.Enabled, steps = {
            ('Carry the body to the back of a car and press [%s] -> Put In This Vehicle\'s Trunk.'):format(Config.CarryMenuKey),
            ('Most cars fit %d. A hearse fits more.'):format(Config.Trunk.MaxBodies),
            'Third-eye the trunk -> Take Body Out. Locked cars stay shut (police can open them).',
        } },
        { title = 'Burn Barrel', icon = 'fire', items = { I.burnBarrel, I.matches }, steps = {
            'Use the burn barrel item to place it.',
            'Load a body bag in, then Light It Up with matches.',
            'You get ashes and maybe a skull. Smoke can get the police called.',
        } },
        { title = 'Acid', icon = 'flask', items = { I.acid, I.gasmask }, steps = {
            'USE your gas mask item to put it on (use it again to take it off).',
            'Third-eye a body bag -> Dissolve With Acid. Nothing is left.',
            'Without the mask the fumes hurt you.',
        } },
        { title = 'Burial', icon = 'trowel', items = { I.shovel }, steps = {
            'Third-eye a bag / crate / coffin -> Bury. Anywhere = a shallow grave police can find.',
            'At the cemetery: carry it to the open grave and press [' .. Config.CarryMenuKey .. '] -> Lower Into The Open Grave, then Bury. It gets a tombstone with their name.',
            'Only the digger or the police can exhume a grave.',
        }, gps = Config.Burial.Cemetery.Enabled and { Config.Burial.Cemetery.Coords, 'Cemetery' } or nil },
        { title = 'Water Dump', icon = 'water', steps = {
            ('Carry the body to a dump spot (%d on the map) and press [%s] -> Dump In The Water.'):format(#Config.WaterDump.Zones, Config.CarryMenuKey),
            'Crates sink forever. Bags can wash ashore later - and the police get a tip.',
        }, gps = nearestDump() and { nearestDump(), 'Nearest dump spot' } or nil },
        { title = 'Dismember', icon = 'scissors', hidden = not Config.Dismember.Enabled, items = { I.powersaw, I.woodsaw }, steps = {
            'Third-eye a dead player -> Handle Body -> Dismember (needs a power saw OR a wood saw).',
            'You get the remains. The body can never be identified. Blood stays at the scene.',
        } },
        { title = 'Evidence & Police', icon = 'dna', steps = {
            'Everyone who bags, carries or loads a body leaves DNA on it.',
            'Police can Inspect a body to see the DNA, search trunks and exhume graves.',
            'Some DNA survives fire, soil and water. Witnesses may call in what you do.',
            'Bodies rot over time, start to smell, and end up unidentifiable.',
        } },
        { title = 'If YOU Get Bagged', icon = 'eye-slash', steps = {
            'Your screen goes dark. A panel shows what is happening to your body.',
            'You can still use chat and push-to-talk - people nearby can hear you.',
            (Config.Victim.GiveUpAfter or 0) > 0
                and ('After %d minutes you can type /%s instead of waiting.'):format(Config.Victim.GiveUpAfter, Config.Victim.GiveUpCommand)
                or 'You wait until someone deals with your body.',
            Config.ReleaseOnRevive and 'If a medic or admin revives you, you climb out.' or nil,
        } },
    }
    if FuneralEnabled() then
        local L = Config.Funeral.Locations
        sections[#sections + 1] = { title = 'Funeral Home', icon = 'cross', items = { I.flowers }, steps = {
            'Anyone: Call The Coroner from a body\'s menu, buy coffins and flowers at the counter, pay respects at headstones.',
            'Staff: clock in -> take a hearse -> collect bodies -> carry them to the morgue and press [' .. Config.CarryMenuKey .. '].',
            'From the morgue records: death certificate, cremation (urn), or prepare a coffin.',
            'At a cemetery plot: Place Casket -> Begin Service -> Lower Casket = a permanent headstone.',
        }, gps = { L.Duty, 'Funeral Home' } }
    end
    return sections
end

local function openSection(sec)
    local options = {}
    for i, step in ipairs(sec.steps) do
        if step then options[#options + 1] = { title = ('%d.  %s'):format(i, step), readOnly = true } end
    end
    for _, item in ipairs(sec.items or {}) do
        local have = HasItem(item)
        options[#options + 1] = {
            title = ItemLabel(item), readOnly = true, icon = have and 'check' or 'xmark',
            iconColor = have and Config.UI.Accent or '#c0392b',
            description = have and 'You have this' or 'You don\'t have this',
        }
    end
    if sec.gps then options[#options + 1] = gpsTo(sec.gps[1], sec.gps[2]) end
    lib.registerContext({ id = 'nz_help_section', title = sec.title, menu = 'nz_help', options = options })
    lib.showContext('nz_help_section')
end

function OpenHelp()
    local options = {}
    for _, sec in ipairs(guideSections()) do
        if not sec.hidden then
            options[#options + 1] = { title = sec.title, icon = sec.icon, iconColor = Config.UI.Accent, arrow = true,
                onSelect = function() openSection(sec) end }
        end
    end
    lib.registerContext({ id = 'nz_help', title = Config.UI.Title .. '  •  How It Works', options = options })
    lib.showContext('nz_help')
end

RegisterCommand(Config.HelpCommand, OpenHelp, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.HelpCommand, 'How body disposal & the funeral home work')
