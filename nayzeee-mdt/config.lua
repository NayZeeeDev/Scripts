Config = {}

-- ═══════════════════════════════════════════════════════════
--  GENERAL
-- ═══════════════════════════════════════════════════════════
Config.Locale        = 'en'
Config.Debug         = false
Config.Currency      = '$'
Config.Notify        = 'ox_lib'          -- 'ox_lib' | 'esx'
Config.OpenCommand   = 'mdt'
Config.OpenKey       = 'F6'              -- set to false to disable the keybind
Config.PanicCommand  = 'panic'
Config.PanicKey      = false             -- e.g. 'F9'
Config.DispatchKey   = 'F10'             -- toggles the on-screen dispatch card

-- ═══════════════════════════════════════════════════════════
--  ON-SCREEN DISPATCH CARD
--  One call at a time, paged with the keyboard, no cursor.
--  It never steals focus, so players keep driving while reading.
-- ═══════════════════════════════════════════════════════════
Config.Widget = {
    enabled     = true,
    position    = 'top-left',   -- 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'
    autoShow    = true,         -- pop up on a new call
    autoHide    = 25,           -- seconds of no activity before it fades (0 keeps it up)
    maxCalls    = 10,           -- how many calls it pages through
    showClosed  = false,

    -- Control names go to RegisterKeyMapping, so players can rebind them.
    keys = {
        prev   = { command = 'dispatchprev',   key = 'LEFT',  label = 'Previous' },
        next   = { command = 'dispatchnext',   key = 'RIGHT', label = 'Next'     },
        accept = { command = 'dispatchaccept', key = 'U',     label = 'Respond'  }
    },

    -- Responding attaches you to the call and drops a route.
    routeOnAccept = true
}

-- ═══════════════════════════════════════════════════════════
--  TABLET
--  The MDT runs as a tablet: lock screen, home screen, app
--  windows and a taskbar. Officers change wallpaper, size and
--  alerts themselves from the Settings app on the tablet.
-- ═══════════════════════════════════════════════════════════
Config.Tablet = {
    -- hold a tablet prop and play the reading animation while it is out
    prop          = true,
    model         = 'prop_cs_tablet',
    dict          = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
    anim          = 'base',
    bone          = 60309,                       -- left hand
    offset        = vec3(0.03, 0.002, -0.0),
    rotation      = vec3(10.0, 160.0, 0.0),
    propInVehicle = false,                       -- skip the prop while seated in a vehicle

    -- 'first'  = lock screen the first time it comes out each session
    -- 'always' = every time it comes out
    -- 'never'  = straight to the home screen
    lockScreen    = 'first',

    -- block opening while dead, cuffed or ragdolling
    blockWhenDown = true,

    -- wallpaper officers start with, and the ones they can pick from.
    -- `file` is a path inside web/ or a full https link.
    wallpaper     = 'nayzeee',
    wallpapers    = {
        { id = 'nayzeee', label = 'NAYZEEE',    file = 'img/wallpaper.svg' },
        { id = 'hex',     label = 'Hex grid',   file = 'img/wallpaper-grid.svg' },
        { id = 'city',    label = 'Los Santos', file = 'https://r2.fivemanage.com/CWDuI3yLS4av0OWnTLNNl/image/background1.png' }
    }
}

-- ═══════════════════════════════════════════════════════════
--  RADIO CODES  (the 10-Codes app on the tablet)
-- ═══════════════════════════════════════════════════════════
Config.TenCodes = {
    { code = '10-1',  label = 'Unable to copy, change location' },
    { code = '10-2',  label = 'Signal good' },
    { code = '10-4',  label = 'Acknowledged' },
    { code = '10-6',  label = 'Busy' },
    { code = '10-7',  label = 'Out of service' },
    { code = '10-8',  label = 'In service' },
    { code = '10-9',  label = 'Repeat' },
    { code = '10-10', label = 'Fight in progress' },
    { code = '10-11', label = 'Traffic stop' },
    { code = '10-15', label = 'Suspect in custody' },
    { code = '10-19', label = 'Return to station' },
    { code = '10-20', label = 'Location' },
    { code = '10-23', label = 'Arrived on scene' },
    { code = '10-26', label = 'ETA' },
    { code = '10-28', label = 'Plate check' },
    { code = '10-29', label = 'Warrant check' },
    { code = '10-32', label = 'Person with a gun' },
    { code = '10-38', label = 'Stopping a suspicious vehicle' },
    { code = '10-41', label = 'Beginning tour of duty' },
    { code = '10-42', label = 'Ending tour of duty' },
    { code = '10-50', label = 'Vehicle accident' },
    { code = '10-52', label = 'Ambulance needed' },
    { code = '10-55', label = 'Intoxicated driver' },
    { code = '10-71', label = 'Shooting' },
    { code = '10-78', label = 'Need assistance' },
    { code = '10-80', label = 'Pursuit in progress' },
    { code = '10-97', label = 'In route' },
    { code = '10-99', label = 'Officer needs emergency help' },
    { code = 'Code 1', label = 'Routine — no lights or sirens' },
    { code = 'Code 2', label = 'Urgent — no sirens' },
    { code = 'Code 3', label = 'Emergency — lights and sirens' },
    { code = 'Code 4', label = 'No further assistance needed' }
}

-- ═══════════════════════════════════════════════════════════
--  DEPARTMENTS
--  Each ESX job name maps to a department. `title` and `sub`
--  drive the header lockup. `rank` maps grade -> permission set.
-- ═══════════════════════════════════════════════════════════
Config.Departments = {
    police = {
        label    = 'Los Santos Police Department',
        short    = 'LSPD',
        sub      = 'Mobile Data Terminal',
        blipColour = 38,
        callsignPrefix = 'L',
        emergencyNumber = '911'
    },
    sheriff = {
        label    = 'Los Santos County Sheriff',
        short    = 'LSSD',
        sub      = 'Mobile Data Terminal',
        blipColour = 46,
        callsignPrefix = 'S',
        emergencyNumber = '911'
    },
    sasp = {
        label    = 'San Andreas State Police',
        short    = 'SASP',
        sub      = 'Mobile Data Terminal',
        blipColour = 5,
        callsignPrefix = 'A',
        emergencyNumber = '911'
    },
    ambulance = {
        label    = 'Los Santos Medical Services',
        short    = 'LSMS',
        sub      = 'Mobile Data Terminal',
        blipColour = 1,
        callsignPrefix = 'M',
        emergencyNumber = '911',
        medical  = true          -- medical departments see a reduced record set
    },
    doj = {
        label    = 'Department of Justice',
        short    = 'DOJ',
        sub      = 'Records Terminal',
        blipColour = 4,
        callsignPrefix = 'J',
        emergencyNumber = '911'
    }
}

-- ═══════════════════════════════════════════════════════════
--  PERMISSIONS
--  Every action in the MDT is gated by one of these keys.
--  A rank inherits nothing — list every permission it should hold.
--  '*' grants everything.
-- ═══════════════════════════════════════════════════════════
Config.Permissions = {
    -- viewing
    'view.dispatch', 'view.bolo', 'view.warrant', 'view.incident', 'view.charge',
    'view.evidence', 'view.citizen', 'view.vehicle', 'view.weapon', 'view.property',
    'view.officer', 'view.camera', 'view.announcement', 'view.audit',
    -- creating / editing
    'dispatch.create', 'dispatch.assign', 'dispatch.close',
    'bolo.create', 'bolo.edit', 'bolo.resolve',
    'warrant.create', 'warrant.edit', 'warrant.execute',
    'incident.create', 'incident.edit', 'incident.close', 'incident.reopen',
    'evidence.create', 'evidence.edit', 'evidence.checkout',
    'citizen.create', 'citizen.edit', 'citizen.note', 'citizen.licence',
    'vehicle.create', 'vehicle.edit', 'vehicle.flag',
    'weapon.create', 'weapon.edit', 'weapon.flag',
    'property.create', 'property.edit',
    'officer.callsign', 'officer.edit',
    'announcement.create',
    -- destructive
    'incident.delete', 'bolo.delete', 'warrant.delete', 'evidence.delete',
    'citizen.delete', 'vehicle.delete', 'weapon.delete', 'property.delete',
    'charge.manage', 'officer.manage',
    -- photos, links and cameras
    'photo.take', 'photo.delete', 'photo.avatar',
    'link.create', 'link.remove',
    'camera.place', 'camera.manage'
}

-- Grade name (from job_grades.name) -> permissions.
-- The `default` block applies to any grade not listed for that department.
Config.Ranks = {
    police = {
        default = {
            'view.dispatch', 'view.bolo', 'view.warrant', 'view.incident', 'view.charge',
            'view.evidence', 'view.citizen', 'view.vehicle', 'view.weapon', 'view.property',
            'view.officer', 'view.announcement',
            'dispatch.create', 'dispatch.assign', 'dispatch.close',
            'bolo.create', 'bolo.resolve',
            'incident.create', 'incident.edit',
            'evidence.create', 'evidence.checkout',
            'citizen.note', 'vehicle.flag', 'weapon.flag',
            'officer.callsign',
            'view.camera', 'photo.take', 'link.create'
        },
        sergeant = {
            'view.dispatch', 'view.bolo', 'view.warrant', 'view.incident', 'view.charge',
            'view.evidence', 'view.citizen', 'view.vehicle', 'view.weapon', 'view.property',
            'view.officer', 'view.camera', 'view.announcement',
            'dispatch.create', 'dispatch.assign', 'dispatch.close',
            'bolo.create', 'bolo.edit', 'bolo.resolve',
            'warrant.create', 'warrant.execute',
            'incident.create', 'incident.edit', 'incident.close',
            'evidence.create', 'evidence.edit', 'evidence.checkout',
            'citizen.create', 'citizen.edit', 'citizen.note', 'citizen.licence',
            'vehicle.create', 'vehicle.edit', 'vehicle.flag',
            'weapon.create', 'weapon.edit', 'weapon.flag',
            'property.create', 'property.edit',
            'officer.callsign', 'announcement.create',
            'photo.take', 'photo.delete', 'photo.avatar',
            'link.create', 'link.remove', 'camera.place'
        },
        lieutenant = { '*' },
        captain    = { '*' },
        chief      = { '*' },
        boss       = { '*' }
    },
    sheriff = {
        default    = { 'view.dispatch', 'view.bolo', 'view.warrant', 'view.incident', 'view.charge',
                       'view.evidence', 'view.citizen', 'view.vehicle', 'view.weapon', 'view.officer',
                       'view.announcement', 'dispatch.create', 'dispatch.assign', 'dispatch.close',
                       'bolo.create', 'bolo.resolve', 'incident.create', 'incident.edit',
                       'evidence.create', 'citizen.note', 'officer.callsign' },
        boss       = { '*' }
    },
    sasp = {
        default    = { 'view.dispatch', 'view.bolo', 'view.warrant', 'view.incident', 'view.charge',
                       'view.citizen', 'view.vehicle', 'view.officer', 'view.announcement',
                       'dispatch.create', 'dispatch.assign', 'dispatch.close',
                       'bolo.create', 'incident.create', 'officer.callsign' },
        boss       = { '*' }
    },
    ambulance = {
        default    = { 'view.dispatch', 'view.incident', 'view.citizen', 'view.officer',
                       'view.announcement', 'dispatch.assign', 'dispatch.close',
                       'incident.create', 'citizen.note', 'officer.callsign' },
        boss       = { 'view.dispatch', 'view.incident', 'view.citizen', 'view.officer',
                       'view.announcement', 'view.audit', 'dispatch.create', 'dispatch.assign',
                       'dispatch.close', 'incident.create', 'incident.edit', 'incident.close',
                       'citizen.create', 'citizen.edit', 'citizen.note',
                       'officer.callsign', 'officer.manage', 'announcement.create' }
    },
    doj = {
        default    = { 'view.bolo', 'view.warrant', 'view.incident', 'view.charge', 'view.evidence',
                       'view.citizen', 'view.vehicle', 'view.weapon', 'view.property',
                       'view.announcement', 'warrant.create', 'warrant.edit' },
        boss       = { '*' }
    }
}

-- ═══════════════════════════════════════════════════════════
--  DISPATCH
-- ═══════════════════════════════════════════════════════════
Config.Dispatch = {
    enabled          = true,
    idPrefix         = 'DISP',
    autoCloseMinutes = 45,        -- pending calls auto-close after this (0 = never)
    maxActive        = 60,        -- oldest calls drop off the board past this
    blipDuration     = 300,       -- seconds a dispatch blip stays on the map
    blipRadius       = 90.0,      -- radius blip size in units
    soundOnAlert     = true,
    widgetOnAlert    = true,      -- pop the compact widget when a call comes in
    maxUnitsPerCall  = 8,
    -- which departments hear which call. '*' = everyone on duty.
    routing = {
        crime    = { 'police', 'sheriff', 'sasp' },
        medical  = { 'ambulance' },
        fire     = { 'ambulance' },
        traffic  = { 'police', 'sheriff', 'sasp' },
        civil    = { 'police', 'sheriff' },
        panic    = { '*' }
    }
}

-- Call types. `code` is the response code shown on the board.
-- `priority`: 1 = critical (red), 2 = high (amber), 3 = routine (teal)
Config.CallTypes = {
    { id = 'shooting',    label = 'Shooting',           group = 'crime',   priority = 1, code = '10-71', icon = 'shield',  blip = 313, colour = 1 },
    { id = 'gunshot',     label = 'Gun shot',           group = 'crime',   priority = 1, code = '10-13', icon = 'shield',  blip = 313, colour = 1 },
    { id = 'store',       label = 'Store robbery',      group = 'crime',   priority = 1, code = '10-90', icon = 'cash',    blip = 500, colour = 1 },
    { id = 'ammo',        label = 'Ammunation robbery', group = 'crime',   priority = 1, code = '10-90', icon = 'cash',    blip = 110, colour = 1 },
    { id = 'bank',        label = 'Bank robbery',       group = 'crime',   priority = 1, code = '10-90', icon = 'cash',    blip = 108, colour = 1 },
    { id = 'jewelry',     label = 'Jewelry heist',      group = 'crime',   priority = 1, code = '10-90', icon = 'cash',    blip = 617, colour = 1 },
    { id = 'carjack',     label = 'Carjacking',         group = 'crime',   priority = 1, code = '10-31', icon = 'car',     blip = 523, colour = 1 },
    { id = 'theft',       label = 'Vehicle theft',      group = 'crime',   priority = 2, code = '10-31', icon = 'car',     blip = 523, colour = 47 },
    { id = 'assault',     label = 'Assault',            group = 'crime',   priority = 2, code = '10-10', icon = 'warn',    blip = 310, colour = 47 },
    { id = 'domestic',    label = 'Domestic violence',  group = 'civil',   priority = 2, code = '10-16', icon = 'speaker', blip = 280, colour = 47 },
    { id = 'disturbance', label = 'Disturbance',        group = 'civil',   priority = 3, code = '10-16', icon = 'speaker', blip = 280, colour = 3 },
    { id = 'drugs',       label = 'Drug activity',      group = 'crime',   priority = 2, code = '10-60', icon = 'warn',    blip = 51,  colour = 47 },
    { id = 'burglary',    label = 'Burglary',           group = 'crime',   priority = 2, code = '10-62', icon = 'house',   blip = 40,  colour = 47 },
    { id = 'suspicious',  label = 'Suspicious person',  group = 'crime',   priority = 3, code = '10-66', icon = 'user',    blip = 280, colour = 3 },
    { id = 'traffic',     label = 'Traffic collision',  group = 'traffic', priority = 2, code = '10-50', icon = 'car',     blip = 380, colour = 47 },
    { id = 'pursuit',     label = 'Pursuit in progress',group = 'traffic', priority = 1, code = '10-80', icon = 'car',     blip = 523, colour = 1 },
    { id = 'speeding',    label = 'Reckless driver',    group = 'traffic', priority = 3, code = '10-55', icon = 'car',     blip = 326, colour = 3 },
    { id = 'medical',     label = 'Medical emergency',  group = 'medical', priority = 1, code = '10-52', icon = 'cross',   blip = 153, colour = 1 },
    { id = 'down',        label = 'Person down',        group = 'medical', priority = 1, code = '10-52', icon = 'cross',   blip = 153, colour = 1 },
    { id = 'fire',        label = 'Structure fire',     group = 'fire',    priority = 1, code = '10-70', icon = 'warn',    blip = 436, colour = 1 },
    { id = 'panic',       label = 'Panic button',       group = 'panic',   priority = 1, code = '10-99', icon = 'alert',   blip = 303, colour = 1 },
    { id = 'backup',      label = 'Officer needs help', group = 'panic',   priority = 1, code = '10-78', icon = 'alert',   blip = 303, colour = 1 },
    { id = 'other',       label = 'Other',              group = 'crime',   priority = 3, code = '10-00', icon = 'flag',    blip = 280, colour = 3 }
}

-- Unit status shown on the board and roster
Config.UnitStatus = {
    { id = 'available', label = 'Available',   tone = 'teal'  },
    { id = 'enroute',   label = 'En route',    tone = 'amber' },
    { id = 'onscene',   label = 'On scene',    tone = 'amber' },
    { id = 'busy',      label = 'Busy',        tone = 'red'   },
    { id = 'break',     label = 'On break',    tone = 'off'   }
}

-- ═══════════════════════════════════════════════════════════
--  PANIC BUTTON
-- ═══════════════════════════════════════════════════════════
Config.Panic = {
    enabled       = true,
    cooldown      = 30,           -- seconds between activations
    autoBlip      = true,
    followOfficer = true,         -- blip tracks the officer for the duration
    followSeconds = 3,            -- how often the moving blip is updated
    duration      = 120,          -- seconds the panic blip lives
    sound         = true,
    autoDispatch  = true          -- also creates a dispatch entry
}

-- Backup request from the tablet home screen and the dispatch board.
-- Puts a priority call at the officer's position for their own department.
Config.Backup = {
    enabled     = true,
    requirePerm = false,          -- true = needs dispatch.create, false = anyone on the roster
    cooldown    = 20              -- seconds between requests per officer
}

-- ═══════════════════════════════════════════════════════════
--  LIVE MAP
-- ═══════════════════════════════════════════════════════════
Config.Map = {
    enabled        = true,
    updateSeconds  = 4,           -- how often officer positions are pushed
    showOffDuty    = false,
    showCallers    = true,        -- put a marker where the call came from
    unitBlips      = true,        -- show other on-duty units on the game map
    blipSeconds    = 6,           -- how often those unit blips move (players without the tablet open)

    -- Which map art the dispatch board opens with. Officers can switch
    -- between them from the board itself; this is just the default.
    -- 'atlas' | 'midnight' | 'satellite' | 'grid'
    style          = 'midnight',
    allowStyleSwitch = true,

    styles = {
        { id = 'atlas',     label = 'Atlas',     file = 'img/atlas.webp'     },
        { id = 'midnight',  label = 'Midnight',  file = 'img/midnight.webp'  },
        { id = 'satellite', label = 'Satellite', file = 'img/satellite.webp' },
        { id = 'grid',      label = 'Grid',      file = false                }
    },

    -- World-space bounds that translate game coords into map pixels.
    -- Calibrated against the shipped art — all three line up on these.
    -- If your pins sit slightly off, nudge these rather than the images:
    -- widen minX/maxX to pull pins toward the centre horizontally,
    -- widen minY/maxY to pull them toward the centre vertically.
    bounds = { minX = -6235.0, maxX = 6435.0, minY = -4510.0, maxY = 8810.0 }
}

-- ═══════════════════════════════════════════════════════════
--  BOLOs & WARRANTS
-- ═══════════════════════════════════════════════════════════
Config.Bolo = {
    enabled        = true,
    expireHours    = 72,          -- 0 = never expire
    alertOnPlate   = true,        -- ALPR match pushes an alert to the issuer
    maxActive      = 40
}

Config.Warrant = {
    enabled        = true,
    expireDays     = 30,          -- 0 = never expire
    alertOnLookup  = true,        -- looking up a wanted citizen flags the officer
    types = {
        { id = 'arrest', label = 'Arrest warrant' },
        { id = 'search', label = 'Search warrant' },
        { id = 'bench',  label = 'Bench warrant'  },
        { id = 'seize',  label = 'Seizure warrant'}
    }
}

-- ═══════════════════════════════════════════════════════════
--  INCIDENTS & CHARGES
-- ═══════════════════════════════════════════════════════════
Config.Incident = {
    idPrefix       = 'INC',
    statsDays      = 30,          -- window the dashboard figures are drawn from
    maxCharges     = 25,
    maxCitizens    = 10,
    maxEvidence    = 20,
    autoFine       = true,        -- total fine is summed from the charges
    autoJail       = true,
    -- push the fine to a billing system when the incident closes
    billOnClose    = false,
    -- 'esx_billing' = an unpaid bill in the ESX billing table, paid to the department society
    -- 'bank'        = taken straight from the citizen's bank (they must be online)
    -- 'export'      = call billExport below with (nil, identifier, department, amount, label, officer)
    billMode       = 'esx_billing',
    billExport     = { resource = 'nayzeee-banking', method = 'createBill' },
    -- send the jail time to your jail resource
    jailOnClose    = false,
    jailEvent      = 'esx_jail:sendToJail'
}

-- Penal code. `class` drives the colour; `fine` in dollars, `jail` in months.
-- Servers usually replace this wholesale — the UI reads it live from here.
Config.Charges = {
    -- Infractions
    { id = 'speeding_1',   label = 'Speeding (1-15 over)',        class = 'infraction', category = 'Traffic',   fine = 250,   jail = 0,  points = 1 },
    { id = 'speeding_2',   label = 'Speeding (16-25 over)',       class = 'infraction', category = 'Traffic',   fine = 500,   jail = 0,  points = 2 },
    { id = 'speeding_3',   label = 'Speeding (26+ over)',         class = 'misdemeanor',category = 'Traffic',   fine = 1000,  jail = 5,  points = 3 },
    { id = 'no_licence',   label = 'Driving without a licence',   class = 'misdemeanor',category = 'Traffic',   fine = 750,   jail = 5,  points = 2 },
    { id = 'reckless',     label = 'Reckless driving',            class = 'misdemeanor',category = 'Traffic',   fine = 1200,  jail = 10, points = 4 },
    { id = 'evading',      label = 'Evading a peace officer',     class = 'felony',     category = 'Traffic',   fine = 4000,  jail = 30, points = 6 },
    { id = 'dui',          label = 'Driving under the influence', class = 'misdemeanor',category = 'Traffic',   fine = 2500,  jail = 20, points = 6 },
    { id = 'illegal_park', label = 'Illegal parking',             class = 'infraction', category = 'Traffic',   fine = 150,   jail = 0,  points = 0 },

    { id = 'trespass',     label = 'Criminal trespass',           class = 'misdemeanor',category = 'Property',  fine = 800,   jail = 5 },
    { id = 'vandalism',    label = 'Vandalism',                   class = 'misdemeanor',category = 'Property',  fine = 1000,  jail = 10 },
    { id = 'burglary',     label = 'Burglary',                    class = 'felony',     category = 'Property',  fine = 5000,  jail = 45 },
    { id = 'grand_theft',  label = 'Grand theft auto',            class = 'felony',     category = 'Property',  fine = 6000,  jail = 50 },
    { id = 'petty_theft',  label = 'Petty theft',                 class = 'misdemeanor',category = 'Property',  fine = 600,   jail = 5 },
    { id = 'arson',        label = 'Arson',                       class = 'felony',     category = 'Property',  fine = 9000,  jail = 70 },

    { id = 'assault',      label = 'Assault',                     class = 'misdemeanor',category = 'Persons',   fine = 2000,  jail = 20 },
    { id = 'agg_assault',  label = 'Aggravated assault',          class = 'felony',     category = 'Persons',   fine = 6500,  jail = 55 },
    { id = 'battery',      label = 'Battery',                     class = 'misdemeanor',category = 'Persons',   fine = 2500,  jail = 25 },
    { id = 'kidnapping',   label = 'Kidnapping',                  class = 'felony',     category = 'Persons',   fine = 12000, jail = 90 },
    { id = 'manslaughter', label = 'Manslaughter',                class = 'felony',     category = 'Persons',   fine = 20000, jail = 140 },
    { id = 'murder',       label = 'Murder',                      class = 'felony',     category = 'Persons',   fine = 35000, jail = 240 },
    { id = 'attempt_murder',label= 'Attempted murder',            class = 'felony',     category = 'Persons',   fine = 18000, jail = 120 },

    { id = 'poss_1',       label = 'Possession, class A',         class = 'misdemeanor',category = 'Narcotics', fine = 1500,  jail = 15 },
    { id = 'poss_2',       label = 'Possession with intent',      class = 'felony',     category = 'Narcotics', fine = 5000,  jail = 45 },
    { id = 'traffick',     label = 'Drug trafficking',            class = 'felony',     category = 'Narcotics', fine = 15000, jail = 100 },
    { id = 'manufacture',  label = 'Manufacturing narcotics',     class = 'felony',     category = 'Narcotics', fine = 12000, jail = 90 },

    { id = 'ccw',          label = 'Carrying a concealed weapon', class = 'misdemeanor',category = 'Weapons',   fine = 2000,  jail = 20 },
    { id = 'unreg_weapon', label = 'Unregistered firearm',        class = 'felony',     category = 'Weapons',   fine = 5000,  jail = 40 },
    { id = 'illegal_weapon',label= 'Possession of a class 3 weapon',class='felony',     category = 'Weapons',   fine = 10000, jail = 80 },
    { id = 'brandish',     label = 'Brandishing a firearm',       class = 'misdemeanor',category = 'Weapons',   fine = 3000,  jail = 25 },

    { id = 'resist',       label = 'Resisting arrest',            class = 'misdemeanor',category = 'Justice',   fine = 1500,  jail = 15 },
    { id = 'obstruct',     label = 'Obstruction of justice',      class = 'misdemeanor',category = 'Justice',   fine = 2000,  jail = 20 },
    { id = 'false_report', label = 'Filing a false report',       class = 'misdemeanor',category = 'Justice',   fine = 2500,  jail = 20 },
    { id = 'bribery',      label = 'Bribery of a public official',class = 'felony',     category = 'Justice',   fine = 8000,  jail = 60 },
    { id = 'accessory',    label = 'Accessory after the fact',    class = 'felony',     category = 'Justice',   fine = 4000,  jail = 35 },
    { id = 'contempt',     label = 'Contempt of court',           class = 'misdemeanor',category = 'Justice',   fine = 2000,  jail = 20 },

    { id = 'disorderly',   label = 'Disorderly conduct',          class = 'infraction', category = 'Public',    fine = 400,   jail = 0 },
    { id = 'public_intox', label = 'Public intoxication',         class = 'infraction', category = 'Public',    fine = 500,   jail = 5 },
    { id = 'loitering',    label = 'Loitering',                   class = 'infraction', category = 'Public',    fine = 250,   jail = 0 },
    { id = 'harassment',   label = 'Harassment',                  class = 'misdemeanor',category = 'Public',    fine = 1200,  jail = 10 }
}

Config.ChargeClasses = {
    infraction  = { label = 'Infraction',  tone = 'teal'  },
    misdemeanor = { label = 'Misdemeanor', tone = 'amber' },
    felony      = { label = 'Felony',      tone = 'red'   }
}

-- ═══════════════════════════════════════════════════════════
--  EVIDENCE
-- ═══════════════════════════════════════════════════════════
Config.Evidence = {
    enabled  = true,
    idPrefix = 'EV',
    types = {
        { id = 'weapon',     label = 'Weapon',     icon = 'shield' },
        { id = 'narcotics',  label = 'Narcotics',  icon = 'flask'  },
        { id = 'digital',    label = 'Digital',    icon = 'screen' },
        { id = 'physical',   label = 'Physical',   icon = 'box'    },
        { id = 'biological', label = 'Biological', icon = 'flask'  },
        { id = 'vehicle',    label = 'Vehicle',    icon = 'car'    },
        { id = 'currency',   label = 'Currency',   icon = 'cash'   },
        { id = 'document',   label = 'Document',   icon = 'file'   }
    },
    lockers = {
        'Evidence Locker A-05', 'Evidence Locker B-12', 'Evidence Locker C-03',
        'Evidence Locker D-08', 'Digital Evidence Lab', 'Bio Evidence Lab',
        'Vehicle Impound Lot C', 'Secure Evidence Vault'
    },
    -- photos are stored as URLs; hook your own screenshot uploader here
    screenshot = {
        enabled  = false,
        resource = 'screenshot-basic',
        webhook  = ''
    }
}

-- ═══════════════════════════════════════════════════════════
--  BULLETINS
-- ═══════════════════════════════════════════════════════════
Config.Announcement = {
    maxActive  = 20,   -- live bulletins before command has to clear one
    expireDays = 7     -- 0 keeps them up until someone removes them
}

-- ═══════════════════════════════════════════════════════════
--  REGISTRIES
-- ═══════════════════════════════════════════════════════════
Config.Registry = {
    -- pull citizens straight from the ESX users table on first lookup
    autoImportCitizens = true,
    autoImportVehicles = true,
    -- ESX owned_vehicles table name; change if you renamed it
    vehiclesTable      = 'owned_vehicles',
    -- vehicles are matched by plate; trim whitespace on lookup
    trimPlates         = true,
    -- weapons come from ox_inventory metadata when a serial is present
    weaponSerialKey    = 'serial',
    licences = {
        { id = 'drive',   label = 'Driver licence'   },
        { id = 'weapon',  label = 'Firearm licence'  },
        { id = 'pilot',   label = 'Pilot licence'    },
        { id = 'boat',    label = 'Boating licence'  },
        { id = 'hunting', label = 'Hunting licence'  },
        { id = 'fishing', label = 'Fishing licence'  }
    },
    -- ESX property/housing resource table, if you run one
    propertiesTable    = nil        -- e.g. 'properties'
}

-- ═══════════════════════════════════════════════════════════
--  CAMERAS  (fixed CCTV points shown in the Cameras page)
-- ═══════════════════════════════════════════════════════════
Config.Cameras = {
    enabled = true,

    -- Officers with `camera.place` can drop cameras in the world and view
    -- through them from the MDT. Placed cameras live in the database.
    placeable     = true,
    spawnDistance = 40.0,    -- metres — props spawn/despawn around this
    checkSeconds  = 2,       -- how often the spawn sweep runs
    viewDistance  = 0.0,     -- 0 = view any camera; otherwise must be within this many metres
    maxPerDept    = 40,      -- cap on placed cameras per department

    -- Cameras can be shot out and repaired by anyone with `camera.manage`.
    destructible  = true,
    repairSeconds = 8,

    models = {
        { model = 'prop_cctv_cam_01a',     label = 'Standard CCTV',        offset = vec3(0.0, 0.0, -0.10), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_01b',     label = 'Standard CCTV B',      offset = vec3(0.0, 0.0, -0.10), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_02a',     label = 'Wall mounted',         offset = vec3(0.0, 0.0, -0.15), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_03a',     label = 'Dome',                 offset = vec3(0.0, 0.0, -0.20), rot = vec3(-15.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_04a',     label = 'Modern security',      offset = vec3(0.0, 0.0, -0.10), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_05a',     label = 'PTZ',                  offset = vec3(0.0, 0.0, -0.10), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_06a',     label = 'Outdoor',              offset = vec3(0.0, 0.0, -0.10), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'prop_cctv_cam_07a',     label = 'High security',        offset = vec3(0.0, 0.0, -0.10), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'hei_prop_bank_cctv_01', label = 'Bank CCTV',            offset = vec3(0.0, 0.0, -0.15), rot = vec3(-10.0, 0.0, 180.0) },
        { model = 'hei_prop_bank_cctv_02', label = 'Bank dome',            offset = vec3(0.0, 0.0, -0.20), rot = vec3(-15.0, 0.0, 180.0) }
    },

    -- Fixed cameras that always exist, seeded into the database on first start.
    points = {
        { id = 'cam_pacific',  label = 'Pacific Standard Bank',  coords = vector3(255.0, 220.0, 101.0),   heading = 160.0 },
        { id = 'cam_fleeca_a', label = 'Fleeca — Legion Square', coords = vector3(150.0, -1040.0, 29.0),  heading = 340.0 },
        { id = 'cam_247_a',    label = '24/7 — Grove Street',    coords = vector3(25.0, -1345.0, 29.0),   heading = 265.0 },
        { id = 'cam_ammu_a',   label = 'Ammu-Nation — Little Seoul', coords = vector3(-662.0, -935.0, 21.0), heading = 180.0 },
        { id = 'cam_lspd',     label = 'Mission Row lobby',      coords = vector3(441.0, -982.0, 30.0),   heading = 90.0  },
        { id = 'cam_impound',  label = 'Impound lot',            coords = vector3(408.0, -1630.0, 29.0),  heading = 230.0 }
    }
}

-- ═══════════════════════════════════════════════════════════
--  PHOTOS
--  In-game screenshots attached to any record. Needs
--  screenshot-basic. Pick one upload host below.
-- ═══════════════════════════════════════════════════════════
Config.Photos = {
    enabled   = false,                 -- turn on once a host is configured
    resource  = 'screenshot-basic',
    maxPer    = 8,                     -- photos per record
    quality   = 0.85,

    -- 'fivemanage' | 'discord' | 'custom'
    host = 'discord',

    fivemanage = {
        apiKey = ''                    -- https://fivemanage.com
    },

    discord = {
        -- A plain Discord webhook. Simple, free, no account needed.
        webhook = ''
    },

    custom = {
        -- Any endpoint that accepts a multipart upload and returns JSON
        -- containing a URL. `field` is the JSON key holding the link.
        url     = '',
        field   = 'url',
        headers = {}
    },

    -- Records a photo can be attached to.
    subjects = { 'citizen', 'vehicle', 'weapon', 'property', 'incident', 'evidence', 'bolo', 'officer' }
}

-- ═══════════════════════════════════════════════════════════
--  RECORD LINKS
--  Any record can be linked to any other. Links are two-way:
--  link a vehicle to an incident and the incident shows it too.
-- ═══════════════════════════════════════════════════════════
Config.Links = {
    enabled = true,
    maxPer  = 30,
    types = {
        { id = 'citizen',  label = 'Citizen',  icon = 'user'   },
        { id = 'vehicle',  label = 'Vehicle',  icon = 'car'    },
        { id = 'weapon',   label = 'Weapon',   icon = 'shield' },
        { id = 'property', label = 'Property', icon = 'house'  },
        { id = 'incident', label = 'Incident', icon = 'file'   },
        { id = 'evidence', label = 'Evidence', icon = 'box'    },
        { id = 'warrant',  label = 'Warrant',  icon = 'warn'   },
        { id = 'bolo',     label = 'BOLO',     icon = 'bell'   }
    }
}

-- ═══════════════════════════════════════════════════════════
--  PREMADE DISPATCHES
--  Templates other resources fire with one export call:
--    exports['nayzeee-mdt']:premade('store_robbery', { street = '...' })
-- ═══════════════════════════════════════════════════════════
-- `type` must be an id from Config.CallTypes — it decides the code, blip and who hears it.
Config.Premade = {
    store_robbery   = { type = 'store',      title = 'Store robbery in progress',    detail = 'Suspects robbing a convenience store, a weapon may be involved.', priority = 1 },
    bank_robbery    = { type = 'bank',       title = 'Bank robbery in progress',     detail = 'Multiple suspects, armed and dangerous.',                        priority = 1 },
    jewellery       = { type = 'jewelry',    title = 'Jewellery store alarm',        detail = 'Smash and grab reported, suspects may still be on scene.',       priority = 1 },
    house_alarm     = { type = 'burglary',   title = 'Residential alarm',            detail = 'Alarm activated, possible break-in.',                            priority = 2 },
    vehicle_theft   = { type = 'theft',      title = 'Vehicle theft in progress',    detail = 'Suspect taking a vehicle.',                                      priority = 2 },
    shots_fired     = { type = 'gunshot',    title = 'Shots fired',                  detail = 'Gunshots reported in the area.',                                 priority = 1 },
    officer_down    = { type = 'backup',     title = 'Officer down',                 detail = 'Officer requires immediate assistance.',                         priority = 1 },
    drug_deal       = { type = 'drugs',      title = 'Suspicious activity',          detail = 'Possible narcotics transaction in progress.',                    priority = 3 },
    street_race     = { type = 'speeding',   title = 'Illegal street racing',        detail = 'Multiple vehicles racing, reckless driving reported.',           priority = 2 },
    assault_report  = { type = 'assault',    title = 'Assault in progress',          detail = 'Physical altercation between multiple people.',                  priority = 2 },
    vandalism       = { type = 'disturbance',title = 'Vandalism in progress',        detail = 'Property damage being reported.',                                priority = 3 },
    hostage         = { type = 'shooting',   title = 'Hostage situation',            detail = 'Armed suspects holding hostages. Requesting immediate backup.',  priority = 1 },
    atm_tamper      = { type = 'suspicious', title = 'ATM tampering',                detail = 'Subject reported interfering with an ATM.',                      priority = 3 },
    carjacking      = { type = 'carjack',    title = 'Carjacking',                   detail = 'Vehicle taken from the driver by force.',                        priority = 1 },
    medical         = { type = 'medical',    title = 'Medical emergency',            detail = 'Caller reports a person needing urgent medical help.',           priority = 1 },
    fire            = { type = 'fire',       title = 'Structure fire',               detail = 'Smoke and flames reported from a building.',                     priority = 1 }
}

-- ═══════════════════════════════════════════════════════════
--  AUTOMATIC ALERTS
-- ═══════════════════════════════════════════════════════════
Config.Alerts = {
    -- Fires a shots-fired call when a civilian discharges a weapon.
    -- Silenced weapons and on-duty department members are ignored.
    shotsFired = {
        enabled        = true,
        cooldown       = 900,     -- seconds before the same player triggers another
        areaCooldown   = 90,      -- seconds before the same block of the map alerts again
        ignoreJobs     = true,    -- never alert on department members shooting
        requireWitness = true,    -- only report when a ped actually heard it
        ignoredWeapons = {        -- never report these
            'weapon_stungun', 'weapon_stungun_mp', 'weapon_flaregun', 'weapon_petrolcan',
            'weapon_fireextinguisher', 'weapon_snowball', 'weapon_ball', 'weapon_musket',
            'weapon_hazardcan', 'weapon_fertilizercan'
        }
    },

    -- Fires when a vehicle is hotwired near a witness, if your theft
    -- script calls the export. Left here so the cooldown is configurable.
    vehicleTheft = {
        enabled  = false,
        cooldown = 300
    }
}

-- Jobs that never see the MDT even if they somehow reach it.
Config.IgnoredJobs = {
    'taxi', 'mechanic', 'cardealer', 'realestateagent',
    'ballas', 'vagos', 'families', 'lostmc'
}

-- Staff who can reach the admin panel regardless of job.
Config.StaffGroups = { 'superadmin', 'admin', 'god', 'mod' }

-- ═══════════════════════════════════════════════════════════
--  ALPR  (automatic plate reader — feeds BOLO and warrant hits)
-- ═══════════════════════════════════════════════════════════
Config.ALPR = {
    enabled       = true,
    onlyInVehicle = true,
    onlyOnDuty    = true,
    scanRadius    = 25.0,
    scanSeconds   = 3,
    cooldown      = 45,           -- seconds before the same plate re-alerts
    checkBolo     = true,
    checkStolen   = true,
    checkWarrants = true          -- alerts when the registered owner is wanted
}

-- ═══════════════════════════════════════════════════════════
--  DUTY
-- ═══════════════════════════════════════════════════════════
Config.Duty = {
    enabled        = true,
    command        = 'duty',
    trackTime      = true,
    -- an officer must be on duty to open the MDT
    requireForMDT  = false,
    -- clock out automatically after this many minutes idle (0 = never)
    idleMinutes    = 0,
    -- notify the department when someone clocks in / out
    announce       = true
}

-- ═══════════════════════════════════════════════════════════
--  MDT ACCESS POINTS  (desks, terminals, in-vehicle)
-- ═══════════════════════════════════════════════════════════
Config.Access = {
    anywhere       = true,        -- open from anywhere with the key/command
    inVehicleOnly  = false,       -- true forces the MDT to be a car terminal

    -- Require an inventory item to open. Works with ox_inventory,
    -- qs-inventory and plain ESX item counts.
    item = {
        enabled = false,
        name    = 'mdt_tablet',
        consume = false           -- true uses the item up on each open
    },

    terminals = {
        { coords = vector3(441.5, -979.2, 30.7), label = 'Mission Row terminal' },
        { coords = vector3(-448.6, 6012.5, 31.7), label = 'Paleto Bay terminal' },
        { coords = vector3(1853.4, 3689.5, 34.3), label = 'Sandy Shores terminal' }
    },
    target         = 'ox_target'  -- 'ox_target' | 'none'
}

-- ═══════════════════════════════════════════════════════════
--  LOGS
-- ═══════════════════════════════════════════════════════════
Config.Logs = {
    enabled = false,
    name    = 'NAYZEEE MDT',
    colour  = 561826,             -- teal #08afa2
    webhooks = {
        dispatch    = '',
        bolo        = '',
        warrant     = '',
        incident    = '',
        evidence    = '',
        records     = '',
        duty        = '',
        panic       = '',
        admin       = ''
    }
}

-- Every write is written to the audit table regardless of the webhook setting.
Config.Audit = {
    enabled    = true,
    keepDays   = 30,
    pageSize   = 20
}

-- ═══════════════════════════════════════════════════════════
--  WEAPON LIST  (the dropdown on the firearm registry)
-- ═══════════════════════════════════════════════════════════
Config.WeaponList = {
    -- Pistols
    { name = 'weapon_pistol',             label = 'Pistol' },
    { name = 'weapon_pistol_mk2',         label = 'Pistol Mk II' },
    { name = 'weapon_combatpistol',       label = 'Combat Pistol' },
    { name = 'weapon_appistol',           label = 'AP Pistol' },
    { name = 'weapon_pistol50',           label = 'Pistol .50' },
    { name = 'weapon_snspistol',          label = 'SNS Pistol' },
    { name = 'weapon_snspistol_mk2',      label = 'SNS Pistol Mk II' },
    { name = 'weapon_heavypistol',        label = 'Heavy Pistol' },
    { name = 'weapon_vintagepistol',      label = 'Vintage Pistol' },
    { name = 'weapon_marksmanpistol',     label = 'Marksman Pistol' },
    { name = 'weapon_revolver',           label = 'Heavy Revolver' },
    { name = 'weapon_revolver_mk2',       label = 'Heavy Revolver Mk II' },
    { name = 'weapon_doubleaction',       label = 'Double Action Revolver' },
    { name = 'weapon_ceramicpistol',      label = 'Ceramic Pistol' },
    { name = 'weapon_navyrevolver',       label = 'Navy Revolver' },
    { name = 'weapon_gadgetpistol',       label = 'Perico Pistol' },
    { name = 'weapon_stungun',            label = 'Stun Gun' },
    { name = 'weapon_flaregun',           label = 'Flare Gun' },
    -- SMGs
    { name = 'weapon_microsmg',           label = 'Micro SMG' },
    { name = 'weapon_smg',                label = 'SMG' },
    { name = 'weapon_smg_mk2',            label = 'SMG Mk II' },
    { name = 'weapon_assaultsmg',         label = 'Assault SMG' },
    { name = 'weapon_combatpdw',          label = 'Combat PDW' },
    { name = 'weapon_machinepistol',      label = 'Machine Pistol' },
    { name = 'weapon_minismg',            label = 'Mini SMG' },
    { name = 'weapon_raycarbine',         label = 'Unholy Hellbringer' },
    -- Shotguns
    { name = 'weapon_pumpshotgun',        label = 'Pump Shotgun' },
    { name = 'weapon_pumpshotgun_mk2',    label = 'Pump Shotgun Mk II' },
    { name = 'weapon_sawnoffshotgun',     label = 'Sawed-Off Shotgun' },
    { name = 'weapon_assaultshotgun',     label = 'Assault Shotgun' },
    { name = 'weapon_bullpupshotgun',     label = 'Bullpup Shotgun' },
    { name = 'weapon_musket',             label = 'Musket' },
    { name = 'weapon_heavyshotgun',       label = 'Heavy Shotgun' },
    { name = 'weapon_dbshotgun',          label = 'Double Barrel Shotgun' },
    { name = 'weapon_autoshotgun',        label = 'Sweeper Shotgun' },
    { name = 'weapon_combatshotgun',      label = 'Combat Shotgun' },
    -- Rifles
    { name = 'weapon_assaultrifle',       label = 'Assault Rifle' },
    { name = 'weapon_assaultrifle_mk2',   label = 'Assault Rifle Mk II' },
    { name = 'weapon_carbinerifle',       label = 'Carbine Rifle' },
    { name = 'weapon_carbinerifle_mk2',   label = 'Carbine Rifle Mk II' },
    { name = 'weapon_advancedrifle',      label = 'Advanced Rifle' },
    { name = 'weapon_specialcarbine',     label = 'Special Carbine' },
    { name = 'weapon_specialcarbine_mk2', label = 'Special Carbine Mk II' },
    { name = 'weapon_bullpuprifle',       label = 'Bullpup Rifle' },
    { name = 'weapon_bullpuprifle_mk2',   label = 'Bullpup Rifle Mk II' },
    { name = 'weapon_compactrifle',       label = 'Compact Rifle' },
    { name = 'weapon_militaryrifle',      label = 'Military Rifle' },
    { name = 'weapon_heavyrifle',         label = 'Heavy Rifle' },
    { name = 'weapon_tacticalrifle',      label = 'Service Carbine' },
    -- Snipers & LMGs
    { name = 'weapon_sniperrifle',        label = 'Sniper Rifle' },
    { name = 'weapon_heavysniper',        label = 'Heavy Sniper' },
    { name = 'weapon_heavysniper_mk2',    label = 'Heavy Sniper Mk II' },
    { name = 'weapon_marksmanrifle',      label = 'Marksman Rifle' },
    { name = 'weapon_marksmanrifle_mk2',  label = 'Marksman Rifle Mk II' },
    { name = 'weapon_mg',                 label = 'MG' },
    { name = 'weapon_combatmg',           label = 'Combat MG' },
    { name = 'weapon_combatmg_mk2',       label = 'Combat MG Mk II' },
    { name = 'weapon_gusenberg',          label = 'Gusenberg Sweeper' },
    -- Melee
    { name = 'weapon_knife',              label = 'Knife' },
    { name = 'weapon_nightstick',         label = 'Nightstick' },
    { name = 'weapon_hammer',             label = 'Hammer' },
    { name = 'weapon_bat',                label = 'Baseball Bat' },
    { name = 'weapon_crowbar',            label = 'Crowbar' },
    { name = 'weapon_golfclub',           label = 'Golf Club' },
    { name = 'weapon_bottle',             label = 'Broken Bottle' },
    { name = 'weapon_dagger',             label = 'Antique Cavalry Dagger' },
    { name = 'weapon_hatchet',            label = 'Hatchet' },
    { name = 'weapon_knuckle',            label = 'Knuckle Dusters' },
    { name = 'weapon_machete',            label = 'Machete' },
    { name = 'weapon_flashlight',         label = 'Flashlight' },
    { name = 'weapon_switchblade',        label = 'Switchblade' },
    { name = 'weapon_poolcue',            label = 'Pool Cue' },
    { name = 'weapon_wrench',             label = 'Pipe Wrench' },
    { name = 'weapon_battleaxe',          label = 'Battle Axe' },
    { name = 'weapon_stone_hatchet',      label = 'Stone Hatchet' }
}
