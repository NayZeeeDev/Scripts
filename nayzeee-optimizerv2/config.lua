--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗  
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝  
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
                                                                
    NAYZEEE OPTIMIZER - 1.1.0
    Discord: discord.gg/nayzeeedev
]]

Config = {}

--[[ 
     ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ █████╗ ███╗   ██╗██████╗ ███████╗
    ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝
    ██║     ██║   ██║██╔████╔██║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████╗
    ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║╚════██║
    ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝███████║
     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
]]

Config.Command = 'optimizer'           -- Command to open menu (/optimizer)
Config.Key = 'F7'                      -- Keybind to open menu
Config.DisableKeybind = false          -- Set true to disable keybind

--[[ 
    ██████╗ ███████╗███████╗ █████╗ ██╗   ██╗██╗  ████████╗███████╗
    ██╔══██╗██╔════╝██╔════╝██╔══██╗██║   ██║██║  ╚══██╔══╝██╔════╝
    ██║  ██║█████╗  █████╗  ███████║██║   ██║██║     ██║   ███████╗
    ██║  ██║██╔══╝  ██╔══╝  ██╔══██║██║   ██║██║     ██║   ╚════██║
    ██████╔╝███████╗██║     ██║  ██║╚██████╔╝███████╗██║   ███████║
    ╚═════╝ ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚══════╝
]]

Config.DefaultSettings = {
    -- Performance Optimizations
    optimizePeds = false,
    optimizeVehicles = false,
    optimizeObjects = false,
    removeParticles = false,
    
    -- Visual Optimizations
    optimizeShadows = false,
    optimizeLights = false,
    lowTextures = false,
    disableDecals = false,
    disableBloodStains = false,
    disableFireEffects = false,
    
    -- World Optimizations
    disableRain = false,
    disableWind = false,
    clearBrokenGlass = false,
    cleanPedEffects = false,
    
    -- Advanced Optimizations
    clearUnnecessary = false,
    entityCleanup = false,
    ultraMode = false,
    
    -- Display
    showFPS = false,

    -- Last preset the player applied ('' = custom). Persisted so the
    -- Potato timecycle and the header label survive a reconnect.
    activePreset = '',

    -- Player opt-out for the anonymous client telemetry that feeds the
    -- server owner's Health page (FPS + per-resource load). See Config.Health.
    shareTelemetry = true,

    -- First-run setup. false until the player completes (or skips) the wizard.
    setupDone = false,

    -- Last hardware scan, so the Graphics tab stays populated between sessions.
    specGpu = '',
    specThreads = 0,
    specRam = '',
    specWidth = 0,
    specHeight = 0,
    specHz = 0,
    specTier = '',
    specGuessed = false,
    
    -- Frame cap target the player has chosen (0 = uncapped).
    -- Stated intent only — see Config.Background.frameCap; a script cannot
    -- apply a frame cap in FiveM.
    frameCapTarget = 0,
    
    -- Kill Effects
    killEnabled = false,
    killMarker = false,
    killScreen = false,
    killFx = 'DeathFailOut',
    killSoundEnabled = false,
    killSoundId = 'hitmarker',
    killSoundVolume = 50,
    
    -- Hit Effects
    hitEnabled = false,
    hitScreen = false,
    hitFx = 'FocusIn',
    hitParticle = false,
    hitParticleId = 'impact',
    hitSoundEnabled = false,
    hitSoundId = 'tick',
    hitSoundVolume = 50,
}

--[[ 
    ██████╗ ██████╗ ███████╗███████╗███████╗████████╗███████╗
    ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    ██████╔╝██████╔╝█████╗  ███████╗█████╗     ██║   ███████╗
    ██╔═══╝ ██╔══██╗██╔══╝  ╚════██║██╔══╝     ██║   ╚════██║
    ██║     ██║  ██║███████╗███████║███████╗   ██║   ███████║
    ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝
]]

Config.Presets = {
    ['quality'] = {
        optimizePeds = false,
        optimizeVehicles = false,
        optimizeObjects = false,
        removeParticles = false,
        optimizeShadows = false,
        optimizeLights = false,
        lowTextures = false,
        disableDecals = false,
        disableBloodStains = false,
        disableFireEffects = false,
        disableRain = false,
        disableWind = false,
        clearBrokenGlass = false,
        cleanPedEffects = false,
        clearUnnecessary = false,
        entityCleanup = false,
        ultraMode = false,
    },
    ['balanced'] = {
        optimizePeds = true,
        optimizeVehicles = true,
        optimizeObjects = true,
        removeParticles = true,
        optimizeShadows = false,
        optimizeLights = true,
        lowTextures = false,
        disableDecals = true,
        disableBloodStains = false,
        disableFireEffects = false,
        disableRain = false,
        disableWind = false,
        clearBrokenGlass = true,
        cleanPedEffects = true,
        clearUnnecessary = true,
        entityCleanup = true,
        ultraMode = false,
    },
    ['performance'] = {
        optimizePeds = true,
        optimizeVehicles = true,
        optimizeObjects = true,
        removeParticles = true,
        optimizeShadows = true,
        optimizeLights = true,
        lowTextures = true,
        disableDecals = true,
        disableBloodStains = true,
        disableFireEffects = false,
        disableRain = true,
        disableWind = true,
        clearBrokenGlass = true,
        cleanPedEffects = true,
        clearUnnecessary = true,
        entityCleanup = true,
        ultraMode = true,
    },
    ['potato'] = {
        optimizePeds = true,
        optimizeVehicles = true,
        optimizeObjects = true,
        removeParticles = true,
        optimizeShadows = true,
        optimizeLights = true,
        lowTextures = true,
        disableDecals = true,
        disableBloodStains = true,
        disableFireEffects = true,
        disableRain = true,
        disableWind = true,
        clearBrokenGlass = true,
        cleanPedEffects = true,
        clearUnnecessary = true,
        entityCleanup = true,
        ultraMode = true,
    },
    ['streaming'] = {
        optimizePeds = true,
        optimizeVehicles = false,
        optimizeObjects = true,
        removeParticles = false,
        optimizeShadows = false,
        optimizeLights = true,
        lowTextures = false,
        disableDecals = true,
        disableBloodStains = false,
        disableFireEffects = false,
        disableRain = false,
        disableWind = false,
        clearBrokenGlass = true,
        cleanPedEffects = true,
        clearUnnecessary = true,
        entityCleanup = true,
        ultraMode = false,
    },
    ['shooter'] = {
        optimizePeds = true,
        optimizeVehicles = true,
        optimizeObjects = true,
        removeParticles = true,
        optimizeShadows = true,
        optimizeLights = true,
        lowTextures = false,
        disableDecals = true,
        disableBloodStains = true,
        disableFireEffects = true,
        disableRain = true,
        disableWind = true,
        clearBrokenGlass = true,
        cleanPedEffects = true,
        clearUnnecessary = true,
        entityCleanup = true,
        ultraMode = false,
    },
}

--[[ 
    ██╗   ██╗ █████╗ ██╗     ██╗   ██╗███████╗███████╗
    ██║   ██║██╔══██╗██║     ██║   ██║██╔════╝██╔════╝
    ██║   ██║███████║██║     ██║   ██║█████╗  ███████╗
    ╚██╗ ██╔╝██╔══██║██║     ██║   ██║██╔══╝  ╚════██║
     ╚████╔╝ ██║  ██║███████╗╚██████╔╝███████╗███████║
      ╚═══╝  ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝╚══════╝
]]

Config.DensityMultiplier = 0.3
Config.UltraDensityMultiplier = 0.1
Config.PotatoDensityMultiplier = 0.0
Config.LODScale = 0.4
Config.UltraLODScale = 0.2
Config.PotatoLODScale = 0.1
Config.LightCutoffDistance = 2.0
Config.ShadowScale = 0.1
Config.ParticleRemoveRange = 30.0
Config.EntityCleanupDistance = 200.0
Config.CleanupInterval = 2000

--[[ 
    ██╗  ██╗██╗██╗     ██╗         ███████╗███████╗███████╗███████╗ ██████╗████████╗███████╗
    ██║ ██╔╝██║██║     ██║         ██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    █████╔╝ ██║██║     ██║         █████╗  █████╗  █████╗  █████╗  ██║        ██║   ███████╗
    ██╔═██╗ ██║██║     ██║         ██╔══╝  ██╔══╝  ██╔══╝  ██╔══╝  ██║        ██║   ╚════██║
    ██║  ██╗██║███████╗███████╗    ███████╗██║     ██║     ███████╗╚██████╗   ██║   ███████║
    ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝    ╚══════╝╚═╝     ╚═╝     ╚══════╝ ╚═════╝   ╚═╝   ╚══════╝
]]

Config.KillEffect = {
    screenDuration = 1000,   -- How long screen FX plays (ms)
    markerDuration = 3.0,    -- How long marker stays visible (seconds)
    markerSpeed    = 0.02,   -- Upward float speed
    markerScale    = 0.5,    -- Marker size
    markerColor    = { r = 255, g = 0, b = 0, a = 200 },
}

Config.HitEffect = {
    screenDuration = 500,    -- How long hit screen FX plays (ms)
    particleDuration = 800,  -- How long particle effect stays (ms)
}

-- Hit particle effects (dict + name must be valid GTA V PTFX)
-- Add or remove entries here to customize available particles
Config.HitParticles = {
    { id = 'impact',   label = 'Impact',   dict = 'scr_martin1',     name = 'scr_sol1_sniper_impact' },
    { id = 'electric', label = 'Electric',  dict = 'core',            name = 'ent_dst_elec_crackle' },
    { id = 'sparks',   label = 'Sparks',    dict = 'des_firedept',    name = 'des_firedept_sparks' },
    { id = 'flare',    label = 'Flare',     dict = 'core',            name = 'proj_flare_fuse' },
    { id = 'smoke',    label = 'Smoke',     dict = 'core',            name = 'exp_grd_bzgas_smoke' },
    { id = 'blood',    label = 'Blood',     dict = 'core',            name = 'blood_stab' },
}

Config.HitParticleScale = 1.0

-- Available screen effects for kill/hit
Config.ScreenFX = {
    'DeathFailOut',
    'FocusIn',
    'FocusOut',
    'RampageOut',
    'SwitchHUDIn',
    'MinigameEndNeutral',
    'MinigameEndTrevor',
    'CamPushInFranklin',
    'DrugsMichaelAliensFightIn',
    'SuccessFranklin',
    'SuccessMichael',
    'SuccessTrevor',
}

-- Available kill sounds
Config.KillSounds = {
    'hitmarker', 'headshot', 'eliminated', 'takedown', 'frag', 'noscope',
    'collateral', 'multikill', 'unstoppable', 'godlike', 'domination', 'rampage',
    'killingspree', 'savage', 'brutal', 'lethal', 'execution', 'finisher',
}

-- Available hit sounds
Config.HitSounds = {
    'tick', 'pop', 'crack', 'thud', 'snap',
    'ping', 'click', 'tap', 'punch', 'impact',
}

Config.MaxKillSoundVolume = 100
Config.MaxHitSoundVolume  = 100

--[[ 
    ███████╗██████╗ ███████╗    ██████╗ ██╗███████╗██████╗ ██╗      █████╗ ██╗   ██╗
    ██╔════╝██╔══██╗██╔════╝    ██╔══██╗██║██╔════╝██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝
    █████╗  ██████╔╝███████╗    ██║  ██║██║███████╗██████╔╝██║     ███████║ ╚████╔╝ 
    ██╔══╝  ██╔═══╝ ╚════██║    ██║  ██║██║╚════██║██╔═══╝ ██║     ██╔══██║  ╚██╔╝  
    ██║     ██║     ███████║    ██████╔╝██║███████║██║     ███████╗██║  ██║   ██║   
    ╚═╝     ╚═╝     ╚══════╝    ╚═════╝ ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   
]]

Config.FPSPosition = { x = 0.01, y = 0.01 }
Config.FPSScale = 0.4
Config.FPSColor = { r = 8, g = 175, b = 162 }

--[[ 
    ██╗   ██╗██╗     ██████╗ ██████╗ ██╗      ██████╗ ██████╗ ███████╗
    ██║   ██║██║    ██╔════╝██╔═══██╗██║     ██╔═══██╗██╔══██╗██╔════╝
    ██║   ██║██║    ██║     ██║   ██║██║     ██║   ██║██████╔╝███████╗
    ██║   ██║██║    ██║     ██║   ██║██║     ██║   ██║██╔══██╗╚════██║
    ╚██████╔╝██║    ╚██████╗╚██████╔╝███████╗╚██████╔╝██║  ██║███████║
     ╚═════╝ ╚═╝     ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
]]

Config.UI = {
    -- Server owners: change these to match your brand. Applied live to the
    -- menu as CSS variables — no need to touch style.css.
    -- Accent
    Primary     = '#08afa2',   -- main accent (active states, highlights)
    PrimaryHi   = '#0fd4c4',   -- lighter accent (gradients, glow)
    PrimaryLo   = '#067d74',   -- darker accent (gradients)

    -- Status
    Danger      = '#e5484d',   -- Close button, Ultra Mode
    DangerLo    = '#b8262b',
    Amber       = '#e5a50a',   -- warnings

    -- Surfaces (dark to light)
    Base        = '#08090a',   -- window background
    Panel       = '#0e1011',   -- panel background
    Raise       = '#15181a',   -- hover / raised elements
    Inset       = '#0b0c0d',   -- rows, inputs, status bar

    -- Text
    Text        = '#f2f4f5',   -- primary text
    TextMuted   = '#9ea5aa',   -- secondary text
    TextDim     = '#63696d',   -- labels, descriptions
}

--[[ 
    ██████╗  █████╗  ██████╗██╗  ██╗ ██████╗ ██████╗  ██████╗ ██╗   ██╗███╗   ██╗██████╗ 
    ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝ ██╔══██╗██╔═══██╗██║   ██║████╗  ██║██╔══██╗
    ██████╔╝███████║██║     █████╔╝ ██║  ███╗██████╔╝██║   ██║██║   ██║██╔██╗ ██║██║  ██║
    ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔══██╗██║   ██║██║   ██║██║╚██╗██║██║  ██║
    ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝
    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ 
    
    Background optimizations run automatically for ALL players.
    Server owners configure these — players don't toggle them.
    These fix common issues like muddy textures, texture pop-in,
    and performance degradation as player count / resources increase.
]]

Config.Background = {
    enabled = true,                -- Master toggle for all background optimizations
    
    -- TEXTURE STREAMING FIX
    -- Fixes muddy/blurry textures by anchoring GTA's HD texture streaming area
    -- to the player. Set once on load, then re-anchored only after the player
    -- travels (re-applying it on a timer causes visible texture pop).
    textureStreamFix = true,
    hdRadius = 150.0,              -- Radius around player to force HD textures (meters)
    textureRefreshInterval = 10,   -- How often to CHECK whether to re-anchor (seconds)
                                   -- Re-anchors only after moving 60% of hdRadius
    
    -- ENTITY POOL MANAGEMENT
    -- Monitors vehicle and ped pool counts, cleaning the farthest ambient
    -- entities when approaching GTA's limits. Prevents pool overflow crashes
    -- as player count and resource count grow. Mission entities and entities
    -- this client doesn't own are always skipped.
    entityPoolMonitor = true,
    maxVehicles = 180,             -- Start cleaning ambient vehicles above this count (GTA limit ~256)
    maxPeds = 180,                 -- Start cleaning ambient peds above this count (GTA limit ~256)
    -- maxObjects: no longer used. Object pool cleanup is intentionally not performed:
    -- the object pool contains map props and MLO furniture, and deleting from
    -- it caused props to vanish and repopulate (severe location flicker).
    poolCheckInterval = 15,        -- How often to check pools (seconds)
    
    -- ASSET MEMORY CLEANUP
    -- Releases VEHICLE model memory for vehicles far from the player, so GTA
    -- can reclaim it for nearby high-res textures. Object models are never
    -- released — doing so makes map props unload and re-stream repeatedly.
    assetCleanup = true,
    assetCleanupRange = 300.0,     -- Release VEHICLE models beyond this distance
                                   -- (object models are never released — see note)
    assetCleanupInterval = 30,     -- How often to run cleanup (seconds)
    
    -- AMBIENT POPULATION SCALING
    -- Automatically reduces ambient ped/vehicle spawns when many real players are nearby
    -- Prevents FPS drops in populated areas (e.g. city center with 20+ players)
    ambientScaling = true,
    ambientScalePerPlayer = 0.05,  -- Reduce ambient density by this per nearby player (0.05 = 5%)
    ambientMinScale = 0.2,         -- Never go below this density (0.0 = none, 1.0 = full)
    ambientDetectRange = 200.0,    -- Range to count nearby players
    
    -- GARBAGE COLLECTION
    -- Schedules Lua garbage collection during low-activity moments
    luaGC = true,
    gcInterval = 60,               -- How often to run GC (seconds)
    
    -- CPU LOAD REDUCTION
    -- Cuts CPU-heavy background simulation to lower temps and free headroom.
    -- The GPU renders frames, but the CPU simulates AI, physics, and ragdolls —
    -- these settings reduce that simulation load for things players can't see.
    cpu = {
        enabled = true,
        
        -- AI population budget (0-3, GTA default 3)
        -- Controls how many peds/vehicles get FULL AI simulation (pathfinding,
        -- decision making). Lower = less CPU on AI. 2 is nearly invisible visually.
        populationBudget = true,
        pedBudget = 2,
        vehicleBudget = 2,
        
        -- Dynamic budget scaling — drops budget further when many players nearby
        -- (real players replace the need for ambient AI anyway)
        dynamicBudget = true,      -- 4+ nearby players -> budget 2, 8+ -> budget 1
        
        -- Ragdoll physics limiting
        -- Ragdoll is one of the heaviest CPU computations in GTA. This disables
        -- ragdoll-on-collision for ambient peds beyond the range (nearby peds
        -- and all players keep full ragdoll — combat is unaffected)
        ragdollLimiting = true,
        ragdollRange = 60.0,       -- Full ragdoll within this range
        
        -- Entity LOD distance reduction
        -- Lowers the detail/simulation LOD of distant ambient vehicles
        entityLodScaling = true,
        lodApplyBeyond = 150.0,    -- Apply to vehicles beyond this distance
        lodDistance = 200,         -- LOD distance value to set
        
        cpuCheckInterval = 12,     -- How often the CPU thread runs (seconds)
    },
    
    -- IDLE / AFK THROTTLING
    -- When the player stops giving input or alt-tabs, aggressively cut render
    -- and simulation load. Big thermal win — players leave FiveM running for
    -- hours doing nothing while the GPU renders full scenes at full rate.
    idle = {
        enabled = true,
        afkSeconds = 600,          -- No input for this long = AFK
        afkLodScale = 0.1,         -- LOD scale while AFK
        afkDensity = 0.0,          -- Ambient density while AFK
        throttleOnUnfocused = true,-- Also throttle while the pause menu is open.
                                   -- NOTE: GTA exposes no true window-focus native,
                                   -- so a genuine alt-tab is caught by afkSeconds
                                   -- instead (no input registers while unfocused).
    },
    
    -- ADAPTIVE AUTO-OPTIMIZER
    -- Watches the player's own FPS and escalates optimization automatically
    -- when it drops, then eases back off when it recovers. Self-tuning.
    adaptive = {
        enabled = true,
        checkInterval = 10,        -- How often to evaluate FPS (seconds)
        lowFpsThreshold = 45,      -- Below this = escalate optimization
        recoverFpsThreshold = 70,  -- Above this = ease back off
        maxLevel = 3,              -- Escalation levels (1 = mild, 3 = aggressive)
        notifyPlayer = true,       -- Show a notice when it kicks in
    },
    
    -- LONG SESSION MAINTENANCE
    -- Combats the gradual degradation players feel after hours of play.
    -- Heavy reclaim pass on an interval + optional break advisories.
    session = {
        enabled = true,
        reclaimInterval = 30,      -- Heavy cleanup pass every N minutes
        advisories = true,         -- Show break/thermal advisory notices
        advisoryHours = { 2, 4, 6 },-- Hours at which to show an advisory
        fpsCapAdvisory = true,     -- Warn once if FPS is running uncapped very high
        fpsCapThreshold = 200,     -- Sustained FPS above this triggers the advisory
    },

    -- FIX TEXTURES BUTTON
    -- The reload teleports the player 1500m up for ~1 second and makes them
    -- invincible while textures re-stream. Most anticheats read that as
    -- noclip + godmode. Whitelist the resource in your anticheat, or disable
    -- the button here. Config.Conflicts also warns the player in the menu
    -- when a known anticheat is running.
    textureFix = {
        enabled = true,
    },

    -- FIRST-RUN SETUP + HARDWARE DETECTION
    -- On first open the player is offered a choice: let the Optimizer read
    -- their hardware and recommend a profile, or pick their own settings.
    --
    -- Detection runs in the NUI (Chromium), which exposes the real GPU string
    -- via WebGL, plus CPU threads, memory, resolution and refresh rate.
    setup = {
        enabled = true,          -- false = never show the wizard
        allowAutoDetect = true,  -- false = manual choice only
        allowSkip = true,        -- false = player must pick one of the options
    },

    -- GAME GRAPHICS RECOMMENDATIONS
    -- NOTE: a FiveM resource CANNOT change GTA's own graphics settings. Those
    -- live in settings.xml under the player's Documents folder, outside any
    -- resource's reach. The Graphics tab therefore shows recommended values
    -- for the player to apply in ESC -> Settings -> Graphics themselves.
    graphicsTab = {
        enabled = true,
    },

    -- FRAME CAP HELPER
    -- IMPORTANT: FiveM exposes no native or convar that lets a script set a
    -- frame cap. Every working method is external (GPU driver, GTA's own
    -- Frame Limiter, or a ReShade add-on). This section therefore powers an
    -- in-menu guide rather than enforcing anything — it reads the player's
    -- live FPS, compares it to their chosen target and shows exact steps.
    -- Anything claiming to cap FPS from Lua does not work.
    frameCap = {
        enabled = true,
        targets = { 60, 75, 90, 120, 144, 165, 240 },
        defaultTarget = 0,         -- 0 = Uncapped. Purely the player's stated
                                   -- intent; used to tailor the guide and to
                                   -- silence the uncapped advisory once set.
        overshootMargin = 25,      -- Flag as "not capped" if FPS exceeds the
                                   -- chosen target by more than this
    },
}

--[[ 
    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ 
    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
    ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
    
    Server-side performance monitoring.
    NOTE: for deep sync/network hitch attribution with automatic profiler
    capture, pair this with nayzeee-hitchwatch. This section covers ongoing
    health tracking, trends, and leak detection.
]]

Config.Server = {
    enabled = true,

    -- Tick timing uses GetGameTimer() (wall clock in ms). os.clock() was
    -- used before: on Linux that is CPU time, so hitches were never seen.
    
    -- TICK MONITORING
    -- Measures this resource's own timer drift as a proxy for main-thread stall
    tickMonitor = true,
    tickInterval = 1000,           -- Expected tick interval (ms)
    hitchThreshold = 150,          -- Drift above this (ms) counts as a hitch
    severeHitchThreshold = 500,    -- Drift above this is logged as severe
    
    -- MEMORY LEAK DETECTION
    -- On Linux this reads the real process RSS from /proc/self/statm.
    -- On Windows FiveM exposes no process memory API to Lua, so it falls
    -- back to this resource's own Lua heap and is labelled as such.
    memoryMonitor = true,
    memoryInterval = 60,           -- Sample memory every N seconds
    memorySamples = 30,            -- Keep this many samples for trend analysis
    leakGrowthMB = 100,            -- Flag if memory grows this much across the window
    
    -- PLAYER COUNT CORRELATION
    -- Records hitch counts against player count to find the breaking point
    playerCorrelation = true,
    
    -- REPORTING
    reportInterval = 15,           -- Console health summary every N minutes
    discordWebhook = '',           -- Optional webhook for alerts (leave empty to disable)
    alertCooldown = 300,           -- Min seconds between Discord alerts
}


--[[ 
    ██╗███╗   ███╗██████╗  █████╗  ██████╗████████╗
    ██║████╗ ████║██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
    ██║██╔████╔██║██████╔╝███████║██║        ██║   
    ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║        ██║   
    ██║██║ ╚═╝ ██║██║     ██║  ██║╚██████╗   ██║   
    ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝   ╚═╝   

    Badges shown on every toggle row so players know what they are trading.
    fps    = how much frame rate the option typically gives back
    visual = how noticeable the change is
    Values: 'none' | 'low' | 'medium' | 'high'
]]

Config.Impact = {
    optimizePeds       = { fps = 'high',   visual = 'medium' },
    optimizeVehicles   = { fps = 'high',   visual = 'medium' },
    optimizeObjects    = { fps = 'low',    visual = 'low'    },
    removeParticles    = { fps = 'medium', visual = 'low'    },
    optimizeShadows    = { fps = 'high',   visual = 'high'   },
    optimizeLights     = { fps = 'medium', visual = 'medium' },
    lowTextures        = { fps = 'high',   visual = 'high'   },
    disableDecals      = { fps = 'low',    visual = 'low'    },
    disableBloodStains = { fps = 'low',    visual = 'low'    },
    disableFireEffects = { fps = 'medium', visual = 'medium' },
    disableRain        = { fps = 'medium', visual = 'medium' },
    disableWind        = { fps = 'low',    visual = 'low'    },
    clearBrokenGlass   = { fps = 'low',    visual = 'none'   },
    cleanPedEffects    = { fps = 'low',    visual = 'low'    },
    clearUnnecessary   = { fps = 'none',   visual = 'none'   },
    entityCleanup      = { fps = 'medium', visual = 'low'    },
    ultraMode          = { fps = 'high',   visual = 'high'   },
    showFPS            = { fps = 'none',   visual = 'none'   },
}

--[[ 
    ██╗      ██████╗  ██████╗██╗  ██╗███████╗
    ██║     ██╔═══██╗██╔════╝██║ ██╔╝██╔════╝
    ██║     ██║   ██║██║     █████╔╝ ███████╗
    ██║     ██║   ██║██║     ██╔═██╗ ╚════██║
    ███████╗╚██████╔╝╚██████╗██║  ██╗███████║
    ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝

    Server owners: force a setting to a value for every player. Locked rows
    show a padlock in the menu and cannot be changed by toggles, presets,
    imports or exports. Example for an RP server that syncs weather:

        Config.Locked = { disableRain = false, disableWind = false }
]]

Config.Locked = {
    -- disableRain = false,
    -- disableWind = false,
    -- entityCleanup = false,
}

--[[ 
     █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
    ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
    ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
    ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
    ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
    ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

    Admins see the Health tab (server + client performance tracker) and can
    push presets to players. Grant the ace in server.cfg:

        add_ace group.admin optimizer.admin allow

    Console commands (server console / txAdmin):
        optimizerhealth                    full health report
        optimizerscan [frames]             profiler deep scan (default 500 frames)
        optimizerprobe status|install|remove   per-resource probe management
        optimizerpreset <id|all> <preset>  push a preset to a player or everyone
        optimizerreset                     reset monitoring counters
]]

Config.Admin = {
    ace = 'optimizer.admin',
    -- In-game command for admins: /optimizerpreset <id|all> <preset>
    presetCommand = 'optimizerpreset',
}

--[[ 
     ██████╗ ██████╗ ███╗   ██╗███████╗██╗     ██╗ ██████╗████████╗███████╗
    ██╔════╝██╔═══██╗████╗  ██║██╔════╝██║     ██║██╔════╝╚══██╔══╝██╔════╝
    ██║     ██║   ██║██╔██╗ ██║█████╗  ██║     ██║██║        ██║   ███████╗
    ██║     ██║   ██║██║╚██╗██║██╔══╝  ██║     ██║██║        ██║   ╚════██║
    ╚██████╗╚██████╔╝██║ ╚████║██║     ███████╗██║╚██████╗   ██║   ███████║
     ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚══════╝╚═╝ ╚═════╝   ╚═╝   ╚══════╝

    When one of the listed resources is running, the affected row shows an
    amber warning with the message. Add your own resource names freely.
]]

Config.Conflicts = {
    {
        settings  = { 'disableRain', 'disableWind' },
        resources = { 'qb-weathersync', 'qbx_weathersync', 'cd_easytime', 'vSync', 'weathersync',
                      'av_weather', 'Renewed-Weathersync', 'esx_weathersync', 'wasabi_weather' },
        message   = 'A weather sync script is running. Weather may flicker while this is on.',
    },
    {
        actions   = { 'fixTextures' },
        resources = { 'FiveGuard', 'fiveguard', 'WaveShield', 'waveshield', 'ReaperV4', 'FiniAC',
                      'ElectronAC', 'ntac', 'anticheat', 'ac', 'ox_anticheat' },
        message   = 'An anticheat is running. Fix Textures teleports you briefly and may be flagged. Ask an admin before using it.',
    },
    {
        settings  = { 'entityCleanup' },
        resources = { 'qb-vehiclekeys', 'qbx_vehiclekeys', 'esx_vehiclelock', 'MrNewbVehicleKeys', 'wasabi_carlock' },
        message   = 'Parked player vehicles that are not flagged as mission entities can be removed by this.',
    },
}

--[[ 
    ██████╗ ███████╗███╗   ██╗ ██████╗██╗  ██╗
    ██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║
    ██████╔╝█████╗  ██╔██╗ ██║██║     ███████║
    ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══██║
    ██████╔╝███████╗██║ ╚████║╚██████╗██║  ██║
    ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝
]]

Config.Benchmark = {
    duration  = 30,    -- seconds of frames recorded
    countdown = 3,     -- seconds after the menu closes before recording starts
}

--[[ 
    ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
    ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
    ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
    ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
    ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
     ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

    Point url at a JSON file you host, e.g. a raw GitHub file:
        { "version": "1.1.0", "url": "https://...", "notes": "What changed" }
    Leave url empty to disable. Result is printed to the console and shown
    to admins on the Health tab.
]]

Config.UpdateCheck = {
    enabled  = true,
    url      = '',
    interval = 360,    -- minutes between checks
}

--[[ 
    ██╗  ██╗███████╗ █████╗ ██╗  ████████╗██╗  ██╗
    ██║  ██║██╔════╝██╔══██╗██║  ╚══██╔══╝██║  ██║
    ███████║█████╗  ███████║██║     ██║   ███████║
    ██╔══██║██╔══╝  ██╔══██║██║     ██║   ██╔══██║
    ██║  ██║███████╗██║  ██║███████╗██║   ██║  ██║
    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝

    PERFORMANCE TRACKER (server owners / developers)

    Every resource gets a grade: Excellent, Good, OK, Poor, Bad, plus a
    verdict: Healthy, Monitor, Edit recommended, Edit required, Remove or
    replace. Three data sources feed it:

    1. PROBE (Config.Probe) — a small file loaded into each resource via
       shared_script. It times that resource's own threads, event handlers,
       NUI callbacks, commands and exports, and reads its Lua memory. Works
       on the server AND on every client. Lua resources only.
    2. DEEP SCAN — the built-in FXServer profiler, run on demand with
       `optimizerscan`. Covers every resource (JS/C# too) on the server.
    3. CLIENT TELEMETRY — clients send their FPS and their probe table every
       clientReportInterval seconds so the Health tab can show which
       resources cost frame time across ALL players, not just the admin.

    Thresholds below are per-resource load. Client: ms per frame (same scale
    as resmon). Server: % of main-thread time.
]]

Config.Health = {
    enabled = true,

    clientTelemetry       = true,   -- players can opt out in the menu (shareTelemetry)
    clientReportInterval  = 60,     -- seconds between client reports
    clientSampleSeconds   = 5,      -- frame-time sampling window per report (for 1% lows)
    maxResourcesPerReport = 40,     -- cap per client report (worst first)
    requestCooldown       = 3,      -- seconds between Health tab refreshes per admin

    thresholds = {
        -- Client load, ms per frame (resmon scale)
        clientMs   = { excellent = 0.05, good = 0.15, ok = 0.40, poor = 1.00 },
        -- Server load, % of main thread time
        serverPct  = { excellent = 0.50, good = 2.00, ok = 5.00, poor = 10.0 },
        -- Server tick health, hitches per hour
        hitchRate  = { excellent = 2,    good = 10,   ok = 30,   poor = 90 },
        -- Client frame health, 1% low FPS
        clientLow  = { excellent = 90,   good = 60,   ok = 45,   poor = 30 },

        -- Hint triggers (warn / severe)
        peakSliceMs      = { warn = 5,   severe = 50  },  -- one slice blocked this long
        perFrameLoops    = { warn = 3,   severe = 8   },  -- threads waking every frame
        eventsPerSecond  = { warn = 50,  severe = 200 },  -- handler invocations per second
        memoryGrowthMBph = { warn = 10,  severe = 50  },  -- Lua heap growth per hour
    },

    scan = {
        frames  = 500,   -- default profiler frames for `optimizerscan`
        timeout = 60,    -- seconds to wait for the recording + file
    },
}

Config.Probe = {
    enabled        = true,
    reportInterval = 5,       -- seconds between probe reports (per resource)

    -- Add the probe line to every resource manifest when this resource
    -- starts. Takes effect for each resource on its next (re)start. Nothing
    -- is restarted automatically. A backup of each manifest is written as
    -- fxmanifest.lua.optimizer-backup. `optimizerprobe remove` reverts.
    autoInstall    = false,
    -- Also install into resources that start later (new scripts you add).
    autoInstallNew = false,

    -- Never touched by the installer. System resources, txAdmin and
    -- build tools belong here.
    exclude = {
        'nayzeee-optimizerv2', 'monitor', 'hardcap', 'sessionmanager', 'spawnmanager',
        'mapmanager', 'baseevents', 'basic-gamemode', 'fivem', 'fivem-map-skater',
        'fivem-map-hipster', 'rconlog', 'webadmin', 'yarn', 'webpack', 'chat',
        'chat-theme-gtao', 'playernames', 'runcode', 'D305-Protection',
    },
}
