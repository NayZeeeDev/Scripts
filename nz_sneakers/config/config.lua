Config = {}

Config.Debug = false

-- 'auto' picks whatever is running. Override if you run more than one.
Config.Framework = 'auto'   -- 'auto' | 'qbx' | 'qb' | 'esx'
Config.Inventory = 'auto'   -- 'auto' | 'ox' | 'qb' | 'custom'
                            -- 'qb' also covers ps-inventory and lj-inventory.
                            -- 'custom' uses bridge/custom/inventory.lua for anything else.

-- 'nui' uses the script's own notifications (same style as its menus)
Config.Notify = 'nui'       -- 'nui' | 'ox' | 'framework'

-- Close-up camera + animations while packing, unboxing and putting shoes on
Config.FirstPerson = true

-- Players can only wear shoes made for their ped (male / female freemode)
Config.GenderLock = true

-- Ace for admin commands and picking up anyone's box:
--   add_ace group.admin nz_sneakers.admin allow
Config.AdminAce = 'nz_sneakers.admin'

Config.Items = {
    shoes = 'nz_shoes',              -- a loose pair
    boxed = 'nz_shoebox',            -- a pair in its box
    emptyBox = 'nz_shoebox_empty',   -- an empty box
}

Config.Box = {
    base = `nzs_box`,
    lid = `nzs_box_lid`,
    hinge = vector3(0.0, -0.14, 0.15),   -- matches the 33 x 28 x 15 cm box
    floor = 0.0045,                      -- where the shoes rest inside
    openAngle = 105.0,
    openTime = 550,
    closeTime = 500,
    streamDistance = 40.0,
    interactDistance = 1.6,
    maxPerPlayer = 4,
    anyoneCanPickUp = false,             -- false = only the player who placed it (or admins)
    cleanupOnDrop = true,                -- remove a player's placed boxes when they leave
}

-- The shoes floating in and out of the box
Config.Float = {
    height = 0.42,     -- how far above the box they start / finish
    inTime = 1500,
    outTime = 1200,
}

Config.Wear = {
    takeOffCommand = 'shoesoff',
    reapplyDelay = 3000,     -- ms after spawning before worn shoes are put back on (lets your clothing script load first)
    -- what players wear after taking shoes off if nothing was recorded
    barefoot = {
        male = { drawable = 34, texture = 0 },
        female = { drawable = 35, texture = 0 },
    },
}

Config.Commands = {
    give = 'givesneakers',       -- /givesneakers [id] [shoe] [size] [fake 0/1] [boxed 0/1]
    giveBox = 'giveshoebox',     -- /giveshoebox [id] [amount]
}

Config.Text = {
    open = 'Open lid',
    close = 'Close lid',
    takeOut = 'Take shoes out',
    putIn = 'Put shoes in',
    pickUp = 'Pick up box',
    inspect = 'Inspect',
    wear = 'Put them on',
    boxUp = 'Box them up',
    cancel = 'Cancel',
    choosePair = 'Which pair?',
    noShoes = 'You have no shoes to put in',
    noEmptyBox = 'You need an empty shoe box',
    boxLimit = 'You already have the max number of boxes out',
    boxBusy = 'Hang on, the box is busy',
    noSpace = 'You have no room for that',
    notYours = 'That is not your box',
    wrongGender = 'These are not made for your character',
    notFreemode = 'Only freemode characters can wear these',
    noClothing = 'This shoe has no clothing set up yet (config/shoes.lua)',
    putOn = 'Shoes on',
    tookOff = 'Shoes off',
    notWearing = 'You are not wearing any boxed shoes',
    modelMissing = 'Shoe box model is not streamed. Check nz_sneakers/stream',
    inspectHint = 'Hold LMB and drag to turn · scroll to zoom · Backspace to put them away',
}
