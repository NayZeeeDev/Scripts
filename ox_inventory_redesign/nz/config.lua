--[[
    NZ Inventory UI - config
    Loaded on both client and server (see fxmanifest.lua).
]]

NZConfig = {}

-- Brand shown in the settings banner and the top-left corner of the inventory.
NZConfig.Brand = {
    name = 'NAYZEE',
    tagline = 'Inventory',
    logo = nil, -- a url or 'nui://ox_inventory/web/images/your_logo.png', nil = built in mark
}

-- Player card (avatar, name, wallet, bank, job) above the secondary inventory.
NZConfig.PlayerCard = {
    enabled = true,
    showBank = true,
    showJob = true,
    avatar = 'headshot', -- 'headshot' (ped mugshot) | 'none'
    currency = '$',
    walletItem = 'money', -- item counted for the wallet value
}

-- Custom "Send Item" popup with nearby players instead of ox's raycast give.
NZConfig.GiveMenu = {
    enabled = true,
    distance = 3.0,
    -- 'id' shows "Player 3", 'character' asks the server for the character name.
    -- Character names can be considered metagaming on strict RP servers.
    names = 'id',
}

-- Clothing panel (camera on the ped + toggles for each clothing piece).
NZConfig.Clothing = {
    enabled = true,
    playAnimation = true,
    camera = {
        fov = 38.0,
        -- offset from the ped the camera sits at, and the point it looks at
        offset = vec3(0.0, 2.6, 0.25),
        target = vec3(0.85, 0.0, 0.05), -- positive x pushes the ped to the right side of the screen
    },
    -- Drawable used when a piece is taken off. Adjust if your clothing packs differ.
    -- component = { male, female }  |  extra = additional components set together
    pieces = {
        mask   = { component = 1,  off = { 0, 0 } },
        neck   = { component = 7,  off = { 0, 0 } },
        vest   = { component = 9,  off = { 0, 0 } },
        bag    = { component = 5,  off = { 0, 0 } },
        pants  = { component = 4,  off = { 61, 15 } },
        shoes  = { component = 6,  off = { 34, 35 } },
        top    = { component = 11, off = { 15, 15 }, extra = { [8] = { 15, 14 }, [3] = { 15, 15 } } },
        hat      = { prop = 0 },
        glasses  = { prop = 1 },
        ears     = { prop = 2 },
        watch    = { prop = 6 },
        bracelet = { prop = 7 },
    },
}

-- Theme colours offered in Settings > Theme. The first one is the default accent.
NZConfig.Colors = { '#c4f82a', '#ff3b3b', '#1fd6f2', '#8a5cff', '#ff4fd8', '#ffb31a' }

-- Server-wide defaults for every player's settings. Players can still change
-- them from the settings menu; their choice is saved client side (KVP).
NZConfig.DefaultSettings = {
    layout = 'default',      -- 'default' | 'perspective'
    view = 'fullscreen',     -- 'fullscreen' | 'compact'
    font = 'default',        -- 'default' | 'roboto' | 'manrope' | 'montserrat' | 'inter'
    brand = true,
    accent = '#c4f82a',
    opacity = 90,
    hotbarStyle = 'normal',  -- 'normal' | 'hexagon'
    notifyStyle = 'default', -- 'default' | 'modern'
    slotShape = 'square',    -- 'square' | 'hexagon'
}

-- Item rarity: common, uncommon, rare, epic, legendary, mythic.
-- You can also add `rarity = 'epic'` to an item in data/items.lua or set
-- metadata.rarity on a specific item; those take priority over this table.
NZConfig.Rarity = {
    sprunk = 'uncommon',
    burger = 'epic',
    parachute = 'legendary',
    scrapmetal = 'rare',
    lockpick = 'uncommon',
    armour = 'rare',
    medikit = 'rare',
    WEAPON_PISTOL = 'common',
    WEAPON_CARBINERIFLE = 'epic',
    WEAPON_ASSAULTRIFLE = 'epic',
    WEAPON_HEAVYSNIPER = 'legendary',
    WEAPON_RPG = 'mythic',
}

-- Override any UI text (see web/src/store/strings.ts for every key).
NZConfig.Strings = {
    -- pocket = 'Pockets',
}

-- Optional: return your own player info (server side). Return nil to use the
-- built in framework detection.
---@param source number
---@return { name?: string, bank?: number, job?: string, grade?: string }?
NZConfig.GetPlayerInfo = nil
