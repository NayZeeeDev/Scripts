--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - CHECK-IN, WAITING ROOM, AI DOCTOR & BED REST
    Discord: discord.gg/nayzeeedev

    Place the positions in game (/nzadmin → your department → Positions):
      Check-in Desk   where the receptionist sits / stands, facing the patients.
                      Each desk can set its own ticket letter (A, B, ...) in the manager.
      Waiting Room TV the live board (beds and who is called to them, the queue,
                      ambulances on the way).
                      Put it against a wall, or tick "existing" to take over a TV that is
                      already in the map (one of tv.existingModels).
      Bed             the hospital module's beds - the queue assigns them, the AI doctor
                      treats patients in them and every bed shows the bed rest HUD.

    Patients take a ticket (A-001, A-002 ... per department per day), staff with the
    'checkin' permission call them to a free bed. With nobody on duty the AI doctor
    takes over.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Checkin = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- CHECK-IN DESK
    -- ═══════════════════════════════════════════════════════════════════════

    desk = {
        promptDistance = 2.6,     -- metres from the desk point where "[E] Check in" shows
        key            = 'E',     -- shown in the prompt
        control        = 38,      -- INPUT_PICKUP (E)
        staffKey       = 'G',     -- staff: open the reception queue at the desk
        staffControl   = 47,      -- INPUT_DETONATE (G)
        leaveKey       = 'X',     -- patients: hold at the desk to leave the queue (shown in the prompt)
        leaveControl   = 73,      -- INPUT_VEH_DUCK (X); false = no leave prompt (target option only)
        leaveHold      = 1.0,     -- seconds to hold it
        target         = true,    -- also add target options (ox_target, qb-target...) on the desk
        perm           = 'checkin', -- staff permission for the queue, calling patients, marking them treated
        requireInjury  = true,    -- only players with something to treat get a ticket
        allowDowned    = true,    -- downed (wounded) players may check in when they reach the desk
        cooldown       = 15,      -- seconds between two check-ins of the same player
        prefix         = 'A',     -- default ticket letter (each desk can override it in the manager)
        digits         = 3,       -- A-001
        giveItem       = true,    -- hand out Config.Items.triage_ticket (ticket number in the metadata)
        takeBack       = true,    -- the ticket item is taken back when the visit ends
        receiptTime    = 14,      -- seconds the paper receipt stays on screen (0 = until you walk away)
        ticketHud      = true,    -- small "A-014 · 2 ahead" chip at the top of the screen while you wait
        printSound     = true,    -- thermal printer sound when the receipt prints
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RECEPTIONIST (NPC behind every desk, spawned only on your screen)
    -- ═══════════════════════════════════════════════════════════════════════

    receptionist = {
        enabled       = true,
        models        = { 's_f_y_scrubs_01', 'a_f_y_business_02', 's_m_m_doctor_01', 'a_f_y_business_04' },
        sitScenario   = 'PROP_HUMAN_SEAT_COMPUTER',  -- desks set "pose" to sit or stand in the manager
        standScenario = 'WORLD_HUMAN_CLIPBOARD',
        spawnDistance = 45.0,     -- the ped exists while you are this close
        talk          = true,     -- the receptionist answers with a subtitle
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- QUEUE
    -- ═══════════════════════════════════════════════════════════════════════

    queue = {
        expire        = 7200,     -- seconds a ticket may wait before it is dropped
        offlineGrace  = 300,      -- seconds an offline patient keeps their place
        noShow        = 240,      -- seconds a called patient has to reach the bed (then: no-show)
        estimate      = { 4, 8, 12 }, -- minutes per patient ahead for the estimated wait (P1, P2, P3 tickets)
        maxServing    = 3,        -- called / in-treatment tickets shown on the bed tiles of the board
        keepServing   = 120,      -- seconds a ticket stays on the board after the patient reached the bed
        autoTreatment = true,     -- the ticket turns "In treatment" when the patient lies on the assigned bed
        doneOnLeave   = true,     -- a staff-called ticket closes as treated when the patient leaves the bed healed
        restore       = true,     -- reload today's open tickets after a restart (they wait again)
        history       = 40,       -- closed tickets kept in the reception window's "Today" list
        notify = {
            toast  = true,        -- toast to on-duty staff: "New patient A-014 · P2 Urgent"
            sound  = true,        -- pager beep with the toast
            pager  = true,        -- also a line on the EMS pager (when the dispatch module offers NZA.Dispatch.Page)
            phone  = 'paired',    -- phone notification: true | false | 'paired' (only medics whose pager is paired)
            scope  = 'department',-- 'department' = staff of that hospital, 'all' = every medic with the permission
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- AI DOCTOR (treats checked-in patients when nobody is there to do it)
    -- ═══════════════════════════════════════════════════════════════════════

    ai = {
        enabled      = true,
        noStaff      = true,      -- take patients while no medic of the department is on duty
        noStaffDelay = 12,        -- seconds after check-in before the AI calls them (time to read the ticket)
        waitTimeout  = 600,       -- also take patients nobody called within this many seconds (0 = never)
        criticalTimeout = 0,      -- P1 (immediate) tickets: take them after this many seconds even with staff
                                  -- on duty (0 = off, waitTimeout applies; bleeding out takes about 300 s)
        staffPerm    = 'checkin', -- on-duty medics with this permission count as staff (nil = any medic)
        travel       = 'walk',    -- 'walk' (waypoint, lie down on the bed yourself) | 'teleport' (fade into the bed)
        downedTeleport = true,    -- downed patients are always moved into the bed
        doctorPed    = true,      -- a doctor NPC stands by the bed during the treatment
        doctorModels = { 's_m_m_doctor_01', 's_f_y_scrubs_01' },
        doctorScenario = 'CODE_HUMAN_MEDIC_TIME_OF_DEATH', -- doctor writing notes (assessment, discharge)
        doctorWork   = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }, -- hands at work over the bed
        cinematic    = true,      -- slow camera shots around the bed ([C] switches to your normal camera)
        shotTime     = 8,         -- seconds per camera shot
        cameraKey    = 'C',
        cameraControl = 26,       -- INPUT_LOOK_BEHIND (C)
        getUpHold    = 1.5,       -- seconds to hold the get-up key to stop the treatment
        summaryTime  = 9,         -- seconds the "treatment complete" card stays before you stand up

        -- seconds per step (one step per injury, plus assessment / resus / transfusion / discharge)
        times = {
            assess = 8, discharge = 8, resus = 16, transfusion = 14,
            gunshot = 24, shrapnel = 20, stab = 20, laceration = 14, abrasion = 8,
            contusion = 7, fracture = 22, burn = 18, internal = 28,
            perSeverity = 4,      -- extra seconds per severity level above 1
        },
        scale    = 1.0,           -- multiply every step time (0.5 = twice as fast)
        minTime  = 20,            -- the whole treatment never takes less ...
        maxTime  = 240,           -- ... or more than this (seconds)
        transfuseBelow = 0.80,    -- blood volume under this fraction adds a transfusion step
        heal     = 100,           -- heal points applied to every injury at the end (100 = fully healed)
        revive   = true,          -- downed patients are brought back during the first step

        -- bill (insurance from NZA.Insurance applies; paid to Config.Billing.society)
        billing  = true,
        prices = {
            base = 150, resus = 400, transfusion = 220,
            gunshot = 320, shrapnel = 240, stab = 260, laceration = 120, abrasion = 60,
            contusion = 40, fracture = 300, burn = 260, internal = 480,
            perSeverity = 0.25,   -- +25 % per severity level above 1
        },
        requirePayment = false,   -- true: the AI only calls patients who can pay the estimated bill
        account  = 'bank',        -- 'bank' | 'cash' (used when the billing module is not installed)
        fallbackCash = true,      -- try cash when the bank can't pay
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BED REST HUD (every hospital bed: rest timer, healing ×4, get up)
    -- ═══════════════════════════════════════════════════════════════════════

    rest = {
        enabled       = true,
        getUpKey      = 'X',      -- shown on the HUD (beds you lie in through the queue)
        getUpControl  = 73,       -- INPUT_VEH_DUCK (X)
        poll          = 4,        -- seconds between recovery updates from the server
        hideBedPrompt = true,     -- hide the hospital module's small "[X] Get up" prompt while the HUD shows it
        zOffset       = 0.0,      -- lift the body above the bed point (when Config.Hospital.bed has none)
        exitSide      = 1.1,      -- metres to the side you stand up to
        dict          = 'anim@gangops@morgue@table@',  -- lying animation (Config.Hospital.bed wins when set)
        clip          = 'body_search',
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- WAITING ROOM TV (DUI board)
    -- ═══════════════════════════════════════════════════════════════════════

    tv = {
        enabled       = true,
        width         = 1280,     -- browser size of the board (16:9)
        height        = 720,
        drawDistance  = 28.0,     -- the board runs while you are this close (released further away)
        linger        = 15,       -- seconds the board browser stays alive after you leave
        refresh       = 8,        -- seconds between board refreshes (calls and check-ins push at once)
        chime         = true,     -- soft chime when a number is called and you are near a board
        chimeDistance = 22.0,
        arriving      = 150.0,    -- ambulances closer than this show "Arriving"
        etaSpeed      = 19.0,     -- m/s for ambulance ETAs (Config.Dispatch.status.etaSpeed wins when set)
        maxWaiting    = 7,        -- tickets shown in the triage lanes on the board (all lanes together)
        maxIncoming   = 3,        -- crews shown in the en-route column
        -- native TVs: "existing" boards and the fallback model draw into the model's render target
        existingModels = { 'prop_tv_flat_01', 'prop_tv_flat_02', 'prop_tv_flat_02b', 'prop_tv_flat_03',
                           'prop_tv_flat_03b', 'prop_tv_flat_michael', 'prop_trev_tv_01', 'prop_tv_03' },
        renderTargets = {
            prop_tv_flat_01 = 'tvscreen', prop_tv_flat_02 = 'tvscreen', prop_tv_flat_02b = 'tvscreen',
            prop_tv_flat_03 = 'tvscreen', prop_tv_flat_03b = 'tvscreen', prop_tv_flat_michael = 'tvscreen',
            prop_trev_tv_01 = 'tvscreen', prop_tv_03 = 'tvscreen',
        },
        existingRadius = 3.0,     -- metres around the TV point to look for an existing TV
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MISC
    -- ═══════════════════════════════════════════════════════════════════════

    clock  = 'game',              -- times on tickets and boards: 'game' (in-game clock) | 'real' (your PC clock)
    radial = true,                -- "Call next patient" and "Reception queue" in the EMS radial (Dispatch submenu)
    rates  = { actions = 12, window = 10000 }, -- per player: max requests per window (ms)
}
