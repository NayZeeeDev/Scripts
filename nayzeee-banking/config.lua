--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
██████╗  █████╗ ███╗   ██╗██╗  ██╗██╗███╗   ██╗ ██████╗
██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██║████╗  ██║██╔════╝
██████╔╝███████║██╔██╗ ██║█████╔╝ ██║██╔██╗ ██║██║  ███╗
██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██║██║╚██╗██║██║   ██║
██████╔╝██║  ██║██║ ╚████║██║  ██╗██║██║ ╚████║╚██████╔╝
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

    BANKING SCRIPT - 1.0.0
    Discord: discord.gg/nayzeeedev

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.ServerName     = 'Los Santos'   -- Shown under the bank title in the UI
Config.Currency       = '$'            -- Currency symbol
Config.CurrencyRight  = false          -- true renders 1 500$ instead of $1 500
Config.Debug          = false          -- Debug prints in the server console
Config.Locale         = 'en'           -- File in locales/ for notifications and prompts

Config.Inventory = 'ox_inventory'      -- ox_inventory / qs-inventory / qb-inventory / esx
Config.MoneyItem = 'money'             -- Cash item name, ignored on 'esx'
Config.AccountPrefix = 'NZB'           -- Account numbers read NZB-PSL-A1B2C3D4

Config.Target         = 'ox_target'    -- ox_target / qb-target / none (key press)
Config.TargetDistance = 2.0            -- How close you have to be to interact
Config.OpenKey        = 'E'            -- Used when Target = 'none'

Config.Notify = 'ox_lib'               -- ox_lib / esx / custom
Config.CustomNotify = {                -- Only read when Notify = 'custom'
    event  = 'nayzeee-notify:client:notify',
    export = nil,                      -- { resource = 'nayzeee-notify', method = 'notify' }
}

-- Repaint the whole UI. Only the accent needs changing; the rest is
-- derived from it unless you set them.
Config.UI = {
    accent      = '#08afa2',   -- Primary colour, buttons, highlights, charts
    accentLight = '#0fd4c4',   -- Hover and glow
    accentDark  = '#067d74',   -- Button gradient base
    danger      = '#e5484d',   -- Negative amounts, close button, warnings
    background  = '#08090a',   -- Shell background
    panel       = '#0e1011',   -- Panel background

    -- The bank's name, in the title bar, the intro and on the ATM
    name = 'Fleeca Bank',

    -- YOUR LOGO
    --
    -- Two files in web/images/, made by tools/logo.py (change the name, letters
    -- or colours there and run it again, or drop in your own):
    --   mark = the badge on its own, for the title bar, the intro, the PIN pad,
    --          the ATM boot screen and the phone header
    --   logo = badge + name, for the wide spots: the ATM header, statements,
    --          the phone splash
    mark = 'mark.png',
    --
    -- Drop a PNG into web/images/ and name it here. That is all —
    -- it appears in the top left of the bank, on the ATM screen and
    -- in the phone app, and nothing else needs changing.
    --
    -- Transparent background, roughly 3:1, about 600x200 is plenty.
    -- If the file is not there the built-in wordmark is used instead,
    -- so this is safe to leave as it is.
    --
    -- A full URL works too, if you would rather host it elsewhere:
    --   'https://i.imgur.com/yourlogo.png'
    --   'nui://my-assets/images/logo.png'
    logo = 'logo.png',
}

-- Boot sequence when the bank UI opens
Config.Intro = {
    enabled  = true,
    duration = 1600,               -- How long the intro holds before the UI slides in
    tagline  = 'Secure Banking',   -- Line under the logo
}

Config.MaxSavedTransactions = 250      -- Rows kept per account, 0 = keep everything
Config.UpdateCheck = { enabled = false, url = '' } -- JSON endpoint returning { "version": "1.3.0" }

-- ██████╗ ██████╗  █████╗ ███╗   ██╗ ██████╗██╗  ██╗███████╗███████╗
-- ██╔══██╗██╔══██╗██╔══██╗████╗  ██║██╔════╝██║  ██║██╔════╝██╔════╝
-- ██████╔╝██████╔╝███████║██╔██╗ ██║██║     ███████║█████╗  ███████╗
-- ██╔══██╗██╔══██╗██╔══██║██║╚██╗██║██║     ██╔══██║██╔══╝  ╚════██║
-- ██████╔╝██║  ██║██║  ██║██║ ╚████║╚██████╗██║  ██║███████╗███████║
-- ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝

Config.SpawnPeds = true   -- false draws a marker instead of a teller

Config.Blip   = { enabled = true, sprite = 108, colour = 2, scale = 0.7, name = 'Bank' }
Config.Marker = { id = 2, scale = 0.5, color = { r = 8, g = 175, b = 162, a = 200 } }

-- Branches close overnight, ATMs never do. openHour = 22 with
-- closeHour = 6 works, the window just crosses midnight.
Config.WorkingHours = { enabled = false, openHour = 6, closeHour = 22 }

-- `coords` is where the teller stands and faces. The third-eye target sits
-- on that ped, so the interaction point is always exactly the ped.
Config.Banks = {
    { label = 'Fleeca Bank',  coords = vector4(149.43, -1042.33, 29.37, 341.65), ped = 'ig_bankman' },
    { label = 'Fleeca Bank',  coords = vector4(-1211.93, -331.92, 37.78, 28.03), ped = 'ig_bankman' },
    { label = 'Fleeca Bank',  coords = vector4(-2961.10, 482.95, 15.70, 89.70),  ped = 'ig_bankman' },
    { label = 'Fleeca Bank',  coords = vector4(313.82, -280.55, 54.16, 350.46),  ped = 'ig_bankman' },
    { label = 'Fleeca Bank',  coords = vector4(-351.39, -51.33, 49.04, 341.78),  ped = 'ig_bankman' },
    { label = 'Fleeca Bank',  coords = vector4(1174.94, 2708.28, 38.09, 187.29), ped = 'ig_bankman' },
    { label = 'Fleeca Bank',  coords = vector4(-437.07, -1691.89, 20.92, 151.59),ped = 'ig_bankman' },
    { label = 'Pacific Bank', coords = vector4(247.97, 224.72, 106.29, 162.74),  ped = 'ig_bankman' },
    { label = 'Paleto Bank',  coords = vector4(-111.11, 6470.14, 31.63, 140.34), ped = 'ig_bankman' },
}

--  █████╗ ████████╗███╗   ███╗███████╗
-- ██╔══██╗╚══██╔══╝████╗ ████║██╔════╝
-- ███████║   ██║   ██╔████╔██║███████╗
-- ██╔══██║   ██║   ██║╚██╔╝██║╚════██║
-- ██║  ██║   ██║   ██║ ╚═╝ ██║███████║
-- ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚══════╝

-- ATMs run a cut-down terminal: balance, deposit, withdraw, bills.
Config.ATM = {
    requireCard  = true,    -- An active card must exist on the account
    requirePin   = true,    -- Ask for the PIN
    pinEveryUse  = true,    -- false only asks once per session
    pinAttempts  = 3,       -- Wrong PINs before the card auto-blocks
    -- How close you must be for "Use ATM" to appear. ox_target draws its
    -- circle from further away than this, so a machine you cannot reach
    -- (the wall unit behind a Fleeca counter) glows with an empty menu.
    -- Raise it to make those usable, or drop prop_fleeca_atm from
    -- Config.ATMModels to stop targeting them at all.
    targetDistance = 2.5,

    withdrawFee  = 0.0,     -- 0.02 = 2% on ATM withdrawals
    maxWithdraw  = 25000,   -- Per transaction

    -- The card leaves the player's inventory while they are at the machine
    -- and is handed back when they walk away. Needs Cards.physicalItem.
    holdCard = true,

    -- How the PIN pad slides onto the screen
    padAnimation = 'vertical',    -- vertical / horizontal / none

    -- ── IN-WORLD SCREEN ──
    -- How long to wait on the server before the machine gives up and
    -- says so. A callback that dies would otherwise leave the screen
    -- on its spinner until the player walks away.
    timeoutSeconds = 10,

    -- The minimap follows the player, not the scripted camera, so it
    -- reads as wrong while you are stood at a machine.
    hideRadar = true,

    -- Everything else is switched off while the camera is locked, so
    -- nobody walks off mid-transaction. These stay live so the player
    -- can still reach their own things without leaving the machine.
    --   37 = TAB, which is the inventory on most setups
    -- Add your phone or anything else your server binds; find the ID
    -- with /atmkeys if you do not know it.
    allowControls = { 37 },

    -- The machine's own display becomes the interface.
    screen = {
        enabled = true,

        -- The DUI's own resolution.
        width   = 1024,
        height  = 820,

        -- 'texture' puts the page on the prop's own screen, where it
        -- sits in the bezel and lights up at night. 'draw' paints it
        -- as a flat panel in front instead — only worth it on a model
        -- whose screen texture name you do not know.
        mode = 'texture',

        -- These prop textures are atlases: the screen face is only a
        -- patch of the sheet, so drawing across the whole thing comes
        -- out squashed and offset. This is that patch, as a fraction
        -- of the texture. Set it live with /atmuv.
        island = { x = 0.0, y = 0.0, w = 1.0, h = 1.0 },

        -- Anything else on that sheet takes this colour — on the
        -- Fleeca wall unit, the lit sign above the machine.
        outside = '#000000',

        -- Where the camera looks, from the prop's own origin: the
        -- middle of the screen. Also where 'draw' mode paints.
        aim = vec3(0.0, -0.104, 1.018),

        -- 'draw' mode only
        size = 0.247,

        -- Where the player stands
        headingOffset = 0.0,
        playerDist    = 0.65,

        -- THE CAMERA
        -- The player looks around with the mouse, within limits, so
        -- they can move between the screen and the keypad the way
        -- they would at a real machine.
        -- Far enough back to see the whole machine at a glance, and
        -- aimed a little below the glass so the keypad is in frame
        -- from the start. The starting angle is worked out from these
        -- rather than set by hand, so moving the camera cannot leave
        -- it pointing somewhere else.
        camera = {
            back = 0.85,    -- metres out from the screen
            up   = 0.22,    -- metres above it
            side = -0.04,   -- metres left or right
            tilt = -0.06,   -- aim this far below the middle of the glass
            fov  = 46.0,

            sensitivity = 4.0,
            lookUp      = 20.0,   -- how far up from the start
            lookDown    = 46.0,   -- and down, to reach the keypad
            lookSide    = 26.0,   -- and left or right
        },

        -- Per-model overrides, merged over the defaults above.
        models = {
            [`prop_atm_01`]     = { modelName = 'prop_atm_01', screenTexture = 'prop_cashpoint_screen',
                                    lodVariants = true, playerDist = 0.8,
                                    aim = vec3(0.0, -0.118, 1.100), size = 0.235,
                                    island = { x = 0.0, y = 0.0, w = 1.0, h = 1.0 } },
            [`prop_atm_02`]     = { modelName = 'prop_atm_02', screenTexture = 'prop_cashpoint_screen',
                                    lodVariants = true,
                                    aim = vec3(-0.120, 0.090, 1.150), size = 0.247,
                                    island = { x = 0.0, y = 0.0, w = 1.0, h = 1.0 } },
            [`prop_atm_03`]     = { modelName = 'prop_atm_03', screenTexture = 'prop_cashpoint_screen',
                                    lodVariants = true,
                                    aim = vec3(-0.120, 0.075, 1.150), size = 0.247,
                                    island = { x = 0.0, y = 0.0, w = 1.0, h = 1.0 } },

            -- The Fleeca machine's screen is the emissive texture, and
            -- it sits in the lower-left of the sheet. If the page looks
            -- offset on your build, /atmuv fixes it in half a minute.
            [`prop_fleeca_atm`] = { modelName = 'prop_fleeca_atm', screenTexture = 'prop_fleece_emis',
                                    aim = vec3(-0.120, 0.095, 1.150), size = 0.247,
                                    island = { x = 0.004, y = 0.508, w = 0.492, h = 0.465 } },
        },
    },

    -- ═══════════════════════════════════════════════════════
    --  THE MACHINE'S OWN BUTTONS
    --
    --  The four keys down each side of the screen and the number pad,
    --  as points on the prop: x across, y depth, z up. Look at one and
    --  it lights up; click to press. proximity is how close to the
    --  middle of your view it has to be, as a share of screen height.
    --
    --  Run /atmbuttons once per model to set these exactly: look at a
    --  key, press ENTER, and it records where that key really is.
    -- ═══════════════════════════════════════════════════════
    buttons = {
        enabled   = true,
        proximity = 0.034,   -- share of screen height

        default = {
            side_l1 = vec3(-0.305, 0.090, 1.227),
            side_l2 = vec3(-0.305, 0.090, 1.171),
            side_l3 = vec3(-0.306, 0.090, 1.114),
            side_l4 = vec3(-0.307, 0.090, 1.057),
            side_r1 = vec3( 0.063, 0.090, 1.245),
            side_r2 = vec3( 0.064, 0.090, 1.189),
            side_r3 = vec3( 0.065, 0.090, 1.132),
            side_r4 = vec3( 0.066, 0.090, 1.075),

            pin_1 = vec3(-0.170, 0.000, 0.884),
            pin_2 = vec3(-0.142, 0.000, 0.884),
            pin_3 = vec3(-0.114, 0.000, 0.884),
            pin_4 = vec3(-0.170, -0.038, 0.874),
            pin_5 = vec3(-0.142, -0.038, 0.874),
            pin_6 = vec3(-0.114, -0.038, 0.874),
            pin_7 = vec3(-0.170, -0.076, 0.866),
            pin_8 = vec3(-0.142, -0.076, 0.866),
            pin_9 = vec3(-0.114, -0.076, 0.866),
            pin_clear = vec3(-0.170, -0.116, 0.860),
            pin_0     = vec3(-0.142, -0.116, 0.860),
            pin_enter = vec3(-0.114, -0.116, 0.860),
        },

        -- prop_atm_01 is the free-standing machine; its pad sits
        -- further forward and lower than the wall units.
        models = {
            [`prop_atm_01`] = {
                side_l1 = vec3(-0.190, -0.110, 1.140),
                side_l2 = vec3(-0.190, -0.115, 1.100),
                side_l3 = vec3(-0.190, -0.122, 1.060),
                side_l4 = vec3(-0.190, -0.129, 1.020),
                side_r1 = vec3( 0.084, -0.110, 1.140),
                side_r2 = vec3( 0.084, -0.115, 1.100),
                side_r3 = vec3( 0.084, -0.122, 1.060),
                side_r4 = vec3( 0.084, -0.129, 1.020),

                pin_1 = vec3(-0.088, -0.180, 0.890),
                pin_2 = vec3(-0.058, -0.180, 0.890),
                pin_3 = vec3(-0.028, -0.180, 0.890),
                pin_4 = vec3(-0.088, -0.202, 0.872),
                pin_5 = vec3(-0.058, -0.202, 0.872),
                pin_6 = vec3(-0.028, -0.202, 0.872),
                pin_7 = vec3(-0.088, -0.222, 0.856),
                pin_8 = vec3(-0.058, -0.222, 0.856),
                pin_9 = vec3(-0.028, -0.222, 0.856),
                pin_clear = vec3(-0.088, -0.244, 0.840),
                pin_0     = vec3(-0.058, -0.244, 0.840),
                pin_enter = vec3(-0.028, -0.244, 0.840),
            },
        },
    },

    -- ═══════════════════════════════════════════════════════
    --  THE KEYBOARD
    --
    --  The machine's own pad is the point, but the keyboard works too.
    --
    --  The number row is bound by key NAME through FiveM's own keybind
    --  system, so it needs nothing here and can be rebound in the
    --  game's settings under "ATM keypad". The control IDs below are a
    --  second route for anyone who prefers them — both end up in the
    --  same place and a duplicate press is dropped.
    --
    --  If a key does nothing on your build, find its ID with /atmkeys
    --  and put it here. Note the number row's IDs are not consistent
    --  between builds, which is exactly why the key names came first.
    -- ═══════════════════════════════════════════════════════
    keypad = {
        digits = {
            ['1'] = 157, ['2'] = 158, ['3'] = 159, ['4'] = 160, ['5'] = 161,
            ['6'] = 162, ['7'] = 163, ['8'] = 164, ['9'] = 165,
        },
        alternate = {},

        press     = 24,    -- left mouse, to push the button you are looking at
        backspace = 194,   -- BACKSPACE
        enter     = 191,   -- ENTER
        cancel    = 200,   -- ESC
    },

    -- ═══════════════════════════════════════════════════════
    --  WHAT COMES OUT OF THE MACHINE
    --
    --  Cash out of the dispenser on a withdrawal and back in on a
    --  deposit, the card into the reader, a statement from the receipt
    --  slot. Each slot is a point on the prop plus inner and outer,
    --  how deep the item sits at each end of its travel.
    --
    --  Place them with /atmslot.
    -- ═══════════════════════════════════════════════════════
    slots = {
        enabled      = true,
        cashProp     = 'prop_anim_cash_pile_01',
        receiptProp  = 'prop_fib_letter',

        default = {
            cash    = { x = -0.110, z = 0.930, inner = 0.060, outer = -0.140, rotation = 90.0 },
            card    = { x =  0.250, z = 1.190, inner = 0.180, outer = -0.060, rotation = 0.0 },
            receipt = { x =  0.170, z = 1.020, inner = 0.000, outer = -0.120, rotation = 0.0 },
        },

        models = {
            [`prop_atm_01`] = {
                cash    = { x = -0.050, z = 0.760, inner = -0.150, outer = -0.340, rotation = 90.0 },
                card    = { x =  0.200, z = 1.120, inner = 0.040, outer = -0.240, rotation = 0.0 },
                receipt = { x =  0.110, z = 0.960, inner = -0.180, outer = -0.300, rotation = 0.0 },
            },
        },
    },

    -- The character walks up, faces the machine and puts the card in
    -- before anything appears on screen.
    animation = {
        enabled  = true,
        cardProp = 'prop_cs_credit_card',   -- slid into the reader, nil for none
        insertMs = 1700,                    -- how long the insert takes
        idle     = true,                    -- keep an idle at the machine while the UI is open
    },
}

Config.ATMModels = { `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm` }

-- Cash only moves where the player really is. The server checks the distance on
-- every deposit and withdrawal, so a menu opened anywhere else can't move cash.
Config.Security = {
    branchRange = 12.0,   -- How far from a branch's teller (Config.Banks) still counts as inside
    atmRange    = 3.5,    -- How far from the machine an ATM session can start
}

--  █████╗  ██████╗ ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝██╔════╝
-- ███████║██║     ██║     ██║   ██║██║   ██║██╔██╗ ██║   ██║   ███████╗
-- ██╔══██║██║     ██║     ██║   ██║██║   ██║██║╚██╗██║   ██║   ╚════██║
-- ██║  ██║╚██████╗╚██████╗╚██████╔╝╚██████╔╝██║ ╚████║   ██║   ███████║
-- ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝

Config.Accounts = {
    startingBalance    = 2500,    -- Balance a new personal account opens with
    transferFee        = 0.0,     -- 0.01 = 1% on player to player transfers
    minTransfer        = 1,
    maxTransfer        = 5000000,
    allowNegative      = false,   -- Let accounts go below zero

    maxShared          = 3,       -- Shared accounts one player may own
    maxSharedMembers   = 8,       -- People on a shared account
    sharedCreationCost = 5000,
    savingsCreationCost= 0,
    numberChangeCost   = 250,     -- Reissue your own account number
    maxScheduled       = 5,       -- Standing orders per player

    -- Single withdrawal caps by account type, 0 = no cap
    withdrawLimits = { personal = 0, shared = 250000, society = 500000, savings = 0 },

    -- Jobs with a society account, and the grades that can reach it.
    -- true means every grade.
    societyAccess = {
        police     = { 'boss', 'chief', 'lieutenant' },
        ambulance  = { 'boss', 'chief' },
        mechanic   = true,
        realestate = true,
    },
}

--  ██████╗ █████╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝
-- ██║     ███████║██████╔╝██║  ██║███████╗
-- ██║     ██╔══██║██╔══██╗██║  ██║╚════██║
-- ╚██████╗██║  ██║██║  ██║██████╔╝███████║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝

Config.Cards = {
    enabled          = true,    -- false removes cards and the Cards tab entirely
    maxPerAccount    = 3,       -- Cards per account
    price            = 1000,    -- Cost to issue, overridden per card type below
    replacementPrice = 500,     -- Cost to replace a lost card
    pinChangePrice   = 0,       -- Cost to change a PIN
    limitResetHours  = 24,      -- Rolling window the spend limit resets on
    expiryMonths     = 24,      -- How long a card lasts

    physicalItem = false,       -- Give an inventory item per card type
    skinImages   = true,        -- ox_inventory: each card item shows its own style (card_<item>_<skin>.png
                                -- from install/images). Turn off if you add a skin without rendering its images.
    stealable    = true,        -- Cards can be taken off a player by other scripts

    -- Contactless: payments under the threshold skip the PIN
    express = { enabled = true, threshold = 2500 },

    -- Cards issued to one member of a shared account
    member = { maxPerMember = 1, limit = 2500 },

    -- Card styles. A new one needs .bcard.<name> in web/css/style.css and web/phone/style.css,
    -- and its item pictures from tools/cardicons.py (see install/items.md)
    skins = { 'teal', 'noir', 'chrome', 'crimson' },

    -- Spend limits a player can pick from on their own card
    limitOptions = { 1000, 5000, 25000, 50000, 100000 },
}

--  ██████╗ █████╗ ██████╗ ██████╗     ████████╗██╗   ██╗██████╗ ███████╗███████╗
-- ██╔════╝██╔══██╗██╔══██╗██╔══██╗    ╚══██╔══╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔════╝
-- ██║     ███████║██████╔╝██║  ██║       ██║    ╚████╔╝ ██████╔╝█████╗  ███████╗
-- ██║     ██╔══██║██╔══██╗██║  ██║       ██║     ╚██╔╝  ██╔═══╝ ██╔══╝  ╚════██║
-- ╚██████╗██║  ██║██║  ██║██████╔╝       ██║      ██║   ██║     ███████╗███████║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝        ╚═╝      ╚═╝   ╚═╝     ╚══════╝╚══════╝

-- 'kind' decides how a card behaves:
--   debit    - spends straight from the linked account
--   credit   - spends against a credit line, billed on a cycle
--   secured  - a credit line backed by a deposit the bank holds,
--              returned when the card closes
Config.CardTypes = {
    {
        id = 'debit', kind = 'debit', label = 'Debit Card',
        item = 'card_debit', price = 1000, minCredit = 0, dailyLimit = 5000,
        blurb = 'Spends from the account it is attached to.'
    },
    {
        id = 'secured', kind = 'secured', label = 'Secured Card',
        item = 'card_secured', price = 500, minCredit = 0,
        apr = 0.10, dailyLimit = 5000,
        deposit = { min = 2500, max = 50000, multiplier = 1.0 },
        blurb = 'Backed by a deposit you put up. Builds credit from nothing.'
    },
    {
        id = 'unsecured', kind = 'credit', label = 'Unsecured Card',
        item = 'card_credit', price = 1500, minCredit = 500,
        apr = 0.18, creditLimit = 15000, dailyLimit = 10000,
        blurb = 'A credit line with no deposit. Needs a decent score.'
    },
    {
        id = 'platinum', kind = 'credit', label = 'Platinum Credit',
        item = 'card_platinum', price = 5000, minCredit = 700,
        apr = 0.12, creditLimit = 75000, dailyLimit = 50000,
        blurb = 'The big line. Low rate, high ceiling, strict entry.'
    },
}

-- How credit and secured cards are billed
Config.CreditCards = {
    statementMinutes   = 120,   -- How often a statement is cut
    -- A card's apr is a yearly rate. Each statement charges apr / statementsPerYear
    -- on the carried balance, so 12 treats every statement as a month: 0.18 apr = 1.5%.
    statementsPerYear  = 12,
    dueMinutes         = 60,    -- Time to pay after a statement lands
    minPaymentPct      = 0.10,  -- Minimum payment as a share of the balance
    minPaymentFloor    = 250,   -- But never less than this
    lateFee            = 500,   -- Added when a statement goes unpaid
    missedBeforeFreeze = 3,     -- Missed statements before the card freezes
    closeRequiresZero  = true,  -- A card carrying a balance cannot be closed
}

--  ██████╗██████╗ ███████╗██████╗ ██╗████████╗
-- ██╔════╝██╔══██╗██╔════╝██╔══██╗██║╚══██╔══╝
-- ██║     ██████╔╝█████╗  ██║  ██║██║   ██║
-- ██║     ██╔══██╗██╔══╝  ██║  ██║██║   ██║
-- ╚██████╗██║  ██║███████╗██████╔╝██║   ██║
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝   ╚═╝

-- One place for everything that moves a credit score
Config.Credit = {
    starting = 300,
    min      = 0,
    max      = 850,

    loanOnTime   = 6,     -- Loan instalment paid on time
    loanLate     = -14,   -- Instalment missed
    loanCleared  = 25,    -- Loan paid off
    loanDefault  = -120,  -- Loan defaulted

    cardOnTime   = 8,     -- Card minimum paid on time
    cardLate     = -18,   -- Card statement missed
    cardFrozen   = -60,   -- Card frozen for repeated misses

    -- Running a credit line this hot costs you, checked at statement time
    highUtilisation = { threshold = 0.80, score = -6 },

    bands = {
        { min = 750, label = 'Excellent' },
        { min = 600, label = 'Good' },
        { min = 450, label = 'Fair' },
        { min = 300, label = 'Normal' },
        { min = 0,   label = 'Poor' },
    },
}

-- ███████╗ █████╗ ██╗   ██╗██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔════╝██╔══██╗██║   ██║██║████╗  ██║██╔════╝ ██╔════╝
-- ███████╗███████║██║   ██║██║██╔██╗ ██║██║  ███╗███████╗
-- ╚════██║██╔══██║╚██╗ ██╔╝██║██║╚██╗██║██║   ██║╚════██║
-- ███████║██║  ██║ ╚████╔╝ ██║██║ ╚████║╚██████╔╝███████║
-- ╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

Config.Savings = {
    enabled       = true,     -- false removes the Savings tab
    -- Paid every payoutMinutes on the balance, up to maxBalance. 0.001 every
    -- 60 min is about 2.4% a day of uptime. The old 0.02 compounded to 1.6x a day.
    interestRate  = 0.001,
    payoutMinutes = 60,
    maxBalance    = 5000000,  -- Cap on deposits, transfers in and interest
    withdrawFee   = 0.0,
    requireOnline = false,    -- true only pays interest to players who are logged in
}

-- ██╗      ██████╗  █████╗ ███╗   ██╗███████╗
-- ██║     ██╔═══██╗██╔══██╗████╗  ██║██╔════╝
-- ██║     ██║   ██║███████║██╔██╗ ██║███████╗
-- ██║     ██║   ██║██╔══██║██║╚██╗██║╚════██║
-- ███████╗╚██████╔╝██║  ██║██║ ╚████║███████║
-- ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝

Config.Loans = {
    enabled            = true,   -- false closes lending and removes the Loans tab
    maxActive          = 1,      -- Concurrent loans per player

    -- Anti-churn. Without these a player takes a loan, clears it instantly,
    -- and farms credit score for free.
    cooldownMinutes    = 120,    -- Wait after settling before borrowing again
    minHoldMinutes     = 60,     -- Clear it sooner than this and it does nothing for your credit
    minPaymentsForCredit = 2,    -- Instalments needed before clearing improves your score
    originationFee     = 0.02,   -- Taken off the top when the loan lands

    paymentIntervalMin = 60,     -- Minutes between instalments
    autoPay            = true,   -- Pull the instalment from the account automatically
    chargeOffline      = true,   -- false pauses instalments while the borrower is offline
    missedBeforeDefault= 3,
    defaultPenalty     = 0.25,   -- Added to the balance on default
    earlyPayoffDiscount= 0.10,   -- Interest knocked off for clearing it early
    blacklistOnDefault = true,   -- No new loans until the debt is settled

    tiers = {
        { id = 'standard', label = 'Standard', amount = 5000,  interest = 0.05, termDays = 30, minCredit = 300, payment = 175 },
        { id = 'premium',  label = 'Premium',  amount = 10000, interest = 0.10, termDays = 45, minCredit = 450, payment = 245 },
        { id = 'diamond',  label = 'Diamond',  amount = 20000, interest = 0.15, termDays = 60, minCredit = 600, payment = 384 },
        { id = 'platinum', label = 'Platinum', amount = 50000, interest = 0.20, termDays = 80, minCredit = 750, payment = 750 },
    },
}

-- ██████╗ ██╗██╗     ██╗     ███████╗
-- ██╔══██╗██║██║     ██║     ██╔════╝
-- ██████╔╝██║██║     ██║     ███████╗
-- ██╔══██╗██║██║     ██║     ╚════██║
-- ██████╔╝██║███████╗███████╗███████║
-- ╚═════╝ ╚═╝╚══════╝╚══════╝╚══════╝

Config.Bills = {
    enabled        = true,    -- false removes the Bills tab
    overdueMinutes = 2880,    -- 48h before a bill goes overdue
    latePenalty    = 0.15,    -- Added once it does
    maxAmount      = 500000,
    autoPay        = true,    -- Pay new bills straight away for players who switched auto-pay on in Settings

    -- Jobs allowed to bill someone from their society account
    issuers = { 'police', 'ambulance', 'mechanic', 'lawyer', 'realestate' },
}

-- ██████╗  █████╗ ██╗   ██╗██████╗  ██████╗ ██╗     ██╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔═══██╗██║     ██║
-- ██████╔╝███████║ ╚████╔╝ ██████╔╝██║   ██║██║     ██║
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██╔══██╗██║   ██║██║     ██║
-- ██║     ██║  ██║   ██║   ██║  ██║╚██████╔╝███████╗███████╗
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝

-- 'esx'  - leave wages to ESX. It already pays from the society account
--          every Config.PaycheckInterval and the money lands in this bank.
-- 'bank' - pay wages here instead. Bosses set a wage per grade from the
--          Society tab and direct deposit is honoured.
Config.Payroll = {
    mode    = 'esx',
    maxWage = 25000,   -- Highest wage a boss can set, 'bank' mode only
    minDuty = false,   -- Require a duty flag before paying
}

-- Players choose bank or cash for their wages, 'bank' mode only
Config.DirectDeposit = { enabled = true, defaultToBank = true, bonus = 0.0 }

-- ███╗   ███╗ █████╗ ██████╗ ██╗  ██╗███████╗████████╗
-- ████╗ ████║██╔══██╗██╔══██╗██║ ██╔╝██╔════╝╚══██╔══╝
-- ██╔████╔██║███████║██████╔╝█████╔╝ █████╗     ██║
-- ██║╚██╔╝██║██╔══██║██╔══██╗██╔═██╗ ██╔══╝     ██║
-- ██║ ╚═╝ ██║██║  ██║██║  ██║██║  ██╗███████╗   ██║
-- ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝

-- A market inside the bank. If nayzeee-trading is running it takes over
-- as the price source on its own, otherwise prices tick here.
Config.Market = {
    enabled     = true,      -- false removes the Investments tab
    tickMinutes = 5,         -- How often prices move
    tradeFee    = 0.01,      -- Charged on both sides of a trade
    minTrade    = 100,       -- Smallest order
    maxHolding  = 5000000,   -- Cap on one player's position per asset

    assets = {
        { id = 'BTC', label = 'Bitcoin',    start = 45000, volatility = 0.045, floor = 8000, ceiling = 250000 },
        { id = 'ETH', label = 'Ethereum',   start = 2800,  volatility = 0.050, floor = 400,  ceiling = 20000  },
        { id = 'LSX', label = 'LS Index',   start = 620,   volatility = 0.022, floor = 120,  ceiling = 4000   },
        { id = 'MZE', label = 'Maze Bank',  start = 145,   volatility = 0.030, floor = 20,   ceiling = 1200   },
        { id = 'PSQ', label = 'Pisswasser', start = 62,    volatility = 0.038, floor = 8,    ceiling = 600    },
    },
}

-- ███████╗ ██████╗  ██████╗██╗███████╗████████╗██╗   ██╗
-- ██╔════╝██╔═══██╗██╔════╝██║██╔════╝╚══██╔══╝╚██╗ ██╔╝
-- ███████╗██║   ██║██║     ██║█████╗     ██║    ╚████╔╝
-- ╚════██║██║   ██║██║     ██║██╔══╝     ██║     ╚██╔╝
-- ███████║╚██████╔╝╚██████╗██║███████╗   ██║      ██║
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚══════╝   ╚═╝      ╚═╝

-- Where society money lives in your framework. Our tables stay in sync
-- with it both ways, so nothing else has to be patched.
Config.Society = {
    autoDetect   = true,                 -- Probes the tables below on first sync
    table        = 'addon_account_data', -- addon_account_data / management_funds / bank_accounts
    jobColumn    = 'account_name',       -- account_name / job_name / job
    amountColumn = 'money',              -- money / amount / account_balance
    prefix       = 'society_',           -- What the job name is stored with
}

-- ███╗   ███╗██╗   ██╗██╗  ████████╗██╗     ██╗ ██████╗ ██████╗
-- ████╗ ████║██║   ██║██║  ╚══██╔══╝██║     ██║██╔═══██╗██╔══██╗
-- ██╔████╔██║██║   ██║██║     ██║   ██║     ██║██║   ██║██████╔╝
-- ██║╚██╔╝██║██║   ██║██║     ██║   ██║██   ██║██║   ██║██╔══██╗
-- ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║╚█████╔╝╚██████╔╝██████╔╝
-- ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝ ╚════╝  ╚═════╝ ╚═════╝

-- ESX only knows the job a player is clocked into. This resolves the
-- rest of the roster so a second job keeps its society access.
Config.MultiJob = {
    enabled  = true,     -- false uses the active ESX job only
    resource = 'auto',   -- auto / none / a resource name
    export   = nil,      -- Override the export name on that resource

    useDutyState      = true,   -- Use the multi-job resource's own duty state for payroll
    allowInactiveJobs = false,  -- Reach society accounts for jobs you are not clocked into
    payInactiveJobs   = false,  -- Payroll pays every job you hold, not just the active one

    -- Used when no export answers
    fallbackTable = { name = 'nayzeee_multijob', identifier = 'identifier', job = 'job', grade = 'grade' },
}

-- ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
-- ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
-- ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗
-- ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝
-- ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
-- ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝

-- Invoices from other creators' resources land in this bank instead of
-- their own tables. Event names drift between forks, so change them here
-- if a billing script is not coming through.
--
-- Each event is only picked up while the resource it is named after
-- (the part before the first ':') is NOT running. If it is running it
-- bills the player itself, and both of us answering would bill twice.
Config.Bridge = {
    events = {
        'esx_billing:sendBill',
        'okokBilling:createInvoiceSociety',
        'okokBilling:createInvoicePlayer',
        'qb-phone:server:sendNewMail',
        'lb-phone:invoice:create',
    },
    fallbackJob = 'government',  -- Issuer used when a server script does not name one

    -- When a player's client raises the bill (exports and server scripts
    -- are trusted), the sender must hold the billing job, that job must be
    -- in Config.Bills.issuers, and their grade must be at least this.
    minGrade    = 0,
    jobMinGrade = {},               -- Per job, overrides minGrade, e.g. { police = 1 }
    maxDistance = 15.0,             -- Metres from the person billed, 0 = anywhere

    -- Per player: seconds between bills, and most bills in a minute
    rateLimit = { gapSeconds = 5, perMinute = 6 },
}

-- ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██║  ██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝███████║██║   ██║██╔██╗ ██║█████╗
-- ██╔═══╝ ██╔══██║██║   ██║██║╚██╗██║██╔══╝
-- ██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- The banking app on the player's phone. lb-phone, qs-smartphone-pro,
-- okokPhone and the YSeries phones (yseries / yphone / yflip-phone) are
-- detected and registered automatically, including when the phone
-- starts or restarts after this script. If no supported phone is
-- running the app simply is not added and nothing else changes.
Config.Phone = {
    enabled      = true,
    resource     = 'auto',      -- 'auto' or one phone's resource name, e.g. 'qs-smartphone-pro'
    appName      = 'Banking',   -- Name shown on the home screen
    preinstalled = true,        -- false puts it in the app store instead
    price        = 0,           -- Cost in the store when not preinstalled

    -- Cash cannot be moved on the phone. Depositing and withdrawing
    -- need a machine or a teller, which is what keeps ATMs and
    -- branches worth walking to.
    nearbyRadius = 12.0,        -- How far "nearby" reaches, in metres
    maxRequest   = 25000,       -- Most one player can ask another for
    maxOpenRequests = 3,        -- Requests you can have waiting with one person
    requestMinutes  = 120,      -- How long they have before it goes overdue

    -- PHONE CONTACTS
    -- Paying somebody straight out of your contacts. The phone keeps
    -- its contacts in its own tables, so this reads them directly —
    -- which means the names below belong to the phone, not to this
    -- script, and they do change between phone versions.
    --
    -- The defaults are lb-phone's. If yours differ, correct them here.
    -- If the lookup fails the console says so once and the app falls
    -- back to nearby players and recent payees, which always work.
    contacts = {
        enabled       = true,
        contactsTable = 'phone_contacts',   -- table holding contacts
        contactOwner  = 'phone_number',     -- whose contact list the row is on
        contactNumber = 'number',           -- the number saved in the contact
        phonesTable   = 'phone_phones',     -- table mapping numbers to owners
        phoneNumber   = 'phone_number',     -- number column on that table
        phoneOwner    = 'id',               -- owner/identifier column on that table
    },
}

--  ██████╗ ██╗   ██╗███████╗██████╗ ██████╗ ██████╗  █████╗ ███████╗████████╗
-- ██╔═══██╗██║   ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
-- ██║   ██║██║   ██║█████╗  ██████╔╝██║  ██║██████╔╝███████║█████╗     ██║   
-- ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗██║  ██║██╔══██╗██╔══██║██╔══╝     ██║   
-- ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║██████╔╝██║  ██║██║  ██║██║        ██║   
--  ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   

-- When a payment would take a personal account below zero, two
-- things can save it, in this order: a sweep from the player's own
-- savings, then the overdraft line itself.
--
-- Both are opt-in by default. An account quietly going negative is
-- the kind of surprise players open tickets about.
Config.Overdraft = {
    enabled = true,
    optIn   = true,    -- false makes it always on, with no switch

    -- SAVINGS FIRST
    -- Covers the shortfall out of savings before any line is drawn
    -- on. It is the player's own money, so it costs nothing to use.
    savingsFirst = true,
    savingsFee   = 0.00,   -- 0.02 = 2% of what gets moved

    -- THE LINE
    limit        = 2500,   -- how far below zero an account may go
    blockAtLimit = true,   -- false lets it run past, which you probably do not want
    fee          = 35,     -- charged when the account goes overdrawn
    feePerUse    = false,  -- true charges on every payment while overdrawn

    -- Better credit earns a wider line, between minLimit and limit.
    scaleWithCredit = true,
    minLimit        = 500,

    -- INTEREST
    -- Charged on what is owed, only once the grace period is up.
    graceMinutes    = 60,
    interestRate    = 0.05,
    interestMinutes = 60,

    -- CREDIT SCORE
    creditPenalty = -8,    -- when the account first goes overdrawn
    creditReward  = 3,     -- when it comes back into the black
}

-- ███████╗████████╗ █████╗ ████████╗███████╗███╗   ███╗███████╗███╗   ██╗
-- ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝████╗ ████║██╔════╝████╗  ██║
-- ███████╗   ██║   ███████║   ██║   █████╗  ██╔████╔██║█████╗  ██╔██╗ ██║
-- ╚════██║   ██║   ██╔══██║   ██║   ██╔══╝  ██║╚██╔╝██║██╔══╝  ██║╚██╗██║
-- ███████║   ██║   ██║  ██║   ██║   ███████╗██║ ╚═╝ ██║███████╗██║ ╚████║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝
-- ████████╗███████╗
-- ╚══██╔══╝██╔════╝
--    ██║   ███████╗
--    ██║   ╚════██║
--    ██║   ███████║
--    ╚═╝   ╚══════╝

-- What the account opened at, what moved and where it went, and
-- every line behind it. Available in the bank UI, on the phone, and
-- out of the ATM's receipt slot.
Config.Statements = {
    enabled   = true,
    fee       = 0,        -- charged per statement, 0 for free
    maxRows   = 250,      -- lines on one statement
    atmPeriod = 'week',   -- what the ATM prints: day / week / month / all
}

-- ███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗ ███████╗
-- ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗██╔════╝
-- ███████╗██║   ██║██║   ██║██╔██╗ ██║██║  ██║███████╗
-- ╚════██║██║   ██║██║   ██║██║╚██╗██║██║  ██║╚════██║
-- ███████║╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝

-- Every sound file in web/sounds/ was made for this resource. They
-- are yours with it — no attribution, nothing licensed in from
-- anywhere else. Drop your own .ogg files in that folder and point
-- the names below at them to change any of it.
Config.Sounds = {
    enabled = true,
    volume  = 0.6,       -- overall, 0.0 to 1.0

    files = {
        key      = 'key',        -- a keypad press
        card     = 'card',       -- the card going into or out of the reader
        cash     = 'cash',       -- notes being counted
        dispense = 'dispense',   -- the shutter and the notes coming out
        approved = 'approved',   -- transaction went through
        declined = 'declined',   -- it did not
        receipt  = 'receipt',    -- a statement printing
    },
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

Config.Admin = {
    command     = 'bankadmin',
    ace         = 'nayzeee.banking',   -- add_ace group.admin nayzeee.banking allow
    allowGroups = { 'admin', 'superadmin' },
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Logs = {
    enabled = false,
    webhook = '',                 -- One Discord webhook for everything
    name    = 'NAYZEEE Banking',
    colour  = 561826,             -- Teal #08afa2
}
