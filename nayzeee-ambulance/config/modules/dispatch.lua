--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - DISPATCH, PAGER & EMS JOB MENU
    Discord: discord.gg/nayzeeedev

    Calls reach on-duty medics as a call card (top right), on the pager (needs the
    pager item) and on the paired phone. A call moves along by itself, and players see
    four phases on a progress ring:
      Paged         the call is waiting for a crew
      Rolling       a crew took it; GPS route to the call
      With patient  the crew got close to the call, then treats the patient
      To hospital   the patient is loaded (ambulance / stretcher); GPS route to the
                    nearest hospital. Once the crew is at the hospital the call closes
                    a few seconds later.

    Keys can be rebound by every player in Settings → Key Bindings → FiveM.
    Text is in locales/en/dispatch.lua.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Dispatch = {

    enabled = true,

    -- ═══════════════════════════════════════════════════════════════════════
    -- CALLS
    -- ═══════════════════════════════════════════════════════════════════════

    calls = {
        idPrefix       = 'C-',     -- call ids look like C-0012
        maxActive      = 60,       -- oldest unassigned calls are closed when there are more open calls than this
        unassignedTimeout = 900,   -- seconds an unanswered call stays open before it expires
        staleTimeout   = 2700,     -- seconds a call with units but no status change stays open
        closeAfterHospital = 15,   -- seconds after the crew reaches the hospital before the call closes by itself
        maxUnits       = 4,        -- units that may respond to one call (0 = no limit)
        autoAttach     = true,     -- a medic who treats a call patient without taking the call joins it
        realertOnDrop  = true,     -- page available units again when the last unit clears a call before reaching it
        upgradeOnArrest = true,    -- a call patient going into cardiac arrest makes the call P1
        closeWhenRecovered = true, -- close calls with no units when every patient is back on their feet
        mergeDuplicates = true,    -- a new call for a patient who already has an open call updates that call instead
        defaultCode    = '10-52',  -- used when a call has no code
        defaultType    = 'unknown',
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CALL PROGRESS (automatic)
    -- ═══════════════════════════════════════════════════════════════════════

    status = {
        auto           = true,     -- move calls along by themselves (rolling → with patient → to hospital)
        sceneRadius    = 35.0,     -- metres from the call that count as on scene
        hospitalRadius = 70.0,     -- metres from a hospital that count as at the hospital
        transportDistance = 60.0,  -- patient in a vehicle / bay / stretcher this far from the call counts as on the way to hospital (fallback when the transport module sends nothing)
        tick           = 1500,     -- ms between server checks (only runs while calls have units)
        etaSpeed       = 19.0,     -- average driving speed (m/s) used for ETAs (19 m/s ≈ 68 km/h)
        etaUpdate      = 10,       -- seconds between ETA updates sent to the patient's downed HUD
        -- Used only while no hospital was built in game (/nzadmin). Pillbox, Mount Zonah, Sandy Shores, Paleto.
        fallbackHospitals = {
            vector3(298.6, -584.5, 43.3),
            vector3(-449.5, -340.6, 34.5),
            vector3(1839.4, 3672.9, 34.3),
            vector3(-247.8, 6331.5, 32.4),
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- UNITS
    -- ═══════════════════════════════════════════════════════════════════════

    units = {
        callsignFormat = 'Unit %02d',   -- automatic callsign (server id) until a medic sets one
        callsignCommand = 'callsign',   -- /callsign 4-ADAM  (false = disabled)
        callsignMax    = 12,            -- max characters of a callsign
        outOfServiceAlerts = false,     -- 10-7 (out of service) units still get call cards
        showOffDutyInRoster = false,    -- list medics who are off duty on the board
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CALL CARD (top right HUD)
    -- ═══════════════════════════════════════════════════════════════════════

    card = {
        enabled     = true,
        popup       = false,       -- false = new calls arrive on the pager only (no call card pop-up);
                                   -- true  = the call card also pops up top right (respond / pass keys below)
        captions    = true,        -- the 911 recording plays with captions at the bottom centre
        respondKey  = 'E',         -- respond to the call on the card (works without the mouse)
        dismissKey  = 'BACK',      -- pass on the card (next call in the queue shows); BACK = Backspace (FiveM key names)
        timeout     = 30,          -- seconds a card stays before it dismisses itself
        queue       = 6,           -- max cards waiting in the queue
        sound       = true,        -- alert tone
        voice       = true,        -- play the call's voice recording (NPC calls)
        voiceVolume = 0.85,        -- 0.0 - 1.0
        activeStrip = true,        -- compact "your call" strip with the progress ring while you are on a call (hidden while the pager shows it)
        hideWhenDown = true,       -- no cards while you are wounded / dead yourself
        minPriority = 3,           -- show cards for priorities up to this (1 = P1 only)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PAGER (bottom right device, needs Config.Items.pager)
    -- ═══════════════════════════════════════════════════════════════════════

    pager = {
        enabled     = true,
        requireItem = true,        -- false = every on-duty medic has a pager
        key         = 'F7',        -- show / hide the pager (hold it in your hand, use the buttons)
        command     = 'pager',     -- /pager does the same (false = disabled)
        popup       = true,        -- the pager pops up by itself when a call comes in
        popupTime   = 12,          -- seconds it stays up after a call (unless you are using it)
        showWhileOnCall = true,    -- keep it on screen while you are assigned to a call
        beep        = true,        -- pager beeps (players can mute it in the pager menu)
        history     = 20,          -- calls kept in the pager history
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PHONE (call alerts as phone notifications through Bridge.Phone: yseries, lb-phone, qs, ...)
    -- ═══════════════════════════════════════════════════════════════════════

    phone = {
        alerts         = 'paired', -- 'paired' = medics who link their phone (pager SETUP or radial Calls ▸ Link phone)
                                   -- 'always' = every medic who gets the call card, no linking needed
                                   -- false    = no phone alerts
        linkNeedsPager = true,     -- linking needs the pager item (when pager.requireItem is on);
                                   -- false = any medic can link the phone from the radial
        mail           = false,    -- phones that get alerts also get an e-mail per call
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- DISPATCH BOARD (window: calls, units, map, log, hospital queue)
    -- ═══════════════════════════════════════════════════════════════════════

    board = {
        enabled     = true,
        command     = 'dispatch',  -- /dispatch opens the board (false = disabled)
        key         = false,       -- e.g. 'F9' (false = no default key, players can still bind it)
        assignPerm  = 'manage',    -- permission to assign other units / change priority / close any call
        refresh     = 2000,        -- ms between live refreshes while the board is open
        logLimit    = 60,          -- rows shown in the call log
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- EMS JOB MENU (radial)
    -- ═══════════════════════════════════════════════════════════════════════

    radial = {
        enabled     = true,
        key         = 'F6',        -- open / close the radial job menu
        command     = 'emsmenu',   -- /emsmenu does the same (false = disabled)
        dutyToggle  = true,        -- "Go on / off duty" segment
        dutyPointDistance = false, -- metres to a duty point (built in game) needed to change duty; false = anywhere
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PLAYER 911 & NPC CALLS
    -- ═══════════════════════════════════════════════════════════════════════

    player911 = {
        enabled   = true,
        command   = '911',         -- /911 <what happened>  (cooldown: Config.Bridge.phoneEmergency.cooldown)
        minLength = 3,             -- shortest accepted message
        maxLength = 200,
    },

    npcCalls = {
        defaultOn = false,         -- new medics receive NPC calls (off: they switch it on in the job menu → Dispatch → NPC calls)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MAP BLIPS
    -- ═══════════════════════════════════════════════════════════════════════

    blips = {
        enabled  = true,
        scale    = 0.95,
        flash    = 12,             -- seconds a new P1 call blip flashes
        route    = true,           -- GPS route to the call you respond to
        routeColour = 1,
        shortRange = false,
        -- sprite per call type (GTA blip ids, docs.fivem.net/docs/game-references/blips)
        sprites = {
            default  = 153,
            gunshot  = 110,
            shrapnel = 110,
            stab     = 153,
            burn     = 436,
            mva      = 225,
            fall     = 153,
            arrest   = 153,
            deceased = 310,
            overdose = 51,
            call     = 280,
        },
        -- colour per priority (GTA blip colour ids)
        colours = { [1] = 1, [2] = 47, [3] = 2 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- POLICE & EXTERNAL DISPATCH
    -- ═══════════════════════════════════════════════════════════════════════

    police = {
        enabled  = true,           -- tell on-duty police about violent calls (toast + blip)
        types    = { gunshot = true, shrapnel = true, stab = true },  -- call types that are mirrored
        all      = false,          -- true = every EMS call goes to police too
        blipTime = 240,            -- seconds the police blip stays
    },

    external = true,               -- also mirror calls to an external dispatch / MDT (needs Config.Bridge.externalDispatch = true)

    -- ═══════════════════════════════════════════════════════════════════════
    -- CALL LOG (database table nza_calls)
    -- ═══════════════════════════════════════════════════════════════════════

    log = {
        enabled  = true,
        keepDays = 30,             -- rows older than this are deleted on start (0 = keep forever)
    },
}
