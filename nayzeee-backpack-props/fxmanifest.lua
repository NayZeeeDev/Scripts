fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NAYZEEE Development'
description 'Bag models, textures and animations for nayzeee-backpack'
version '1.0.0'

-- Props only, no code. Kept apart from the script so restarting
-- nayzeee-backpack never makes players re-stream every model, and so
-- you can add bags here without touching the script.
--
-- ensure nayzeee-backpack-props BEFORE nayzeee-backpack

files {
    'stream/**/*.ytyp',
}

-- Every .ytyp in stream/ is registered automatically, so a new bag only
-- needs its .ydr / .ytd / .ytyp dropped into its own folder in stream/.
-- (On a very old server artifact without data_file globbing, add one
-- line per bag instead: data_file 'DLC_ITYP_REQUEST' 'stream/my_bag/my_bag.ytyp')
data_file 'DLC_ITYP_REQUEST' 'stream/**/*.ytyp'

-- Purse poses and the cash grab (.ycd) stream from stream/anims/ with no
-- extra lines.

dependency '/assetpacks' -- needed once the props are escrowed through Tebex

-- BzZz's licence: his props and animation are never escrowed
escrow_ignore {
    'stream/duffel/*',
    'stream/anims/nayzeee_grab_cash_01.ycd',
}
