fx_version 'cerulean'
game 'gta5'

name 'nayzeee-radio-props'
author 'NAYZEEE'
description 'NAYZEEE Radio - the streamed props (handheld, field and tactical radios with their keys, LED inserts, jammers) used by nayzeee-radio'
version '1.0.0'

-- Only models live in this resource. Restarting nayzeee-radio (a config change, an update)
-- leaves them alone: players keep them loaded and cached instead of downloading and
-- re-registering every model again. Start this resource before nayzeee-radio.
--
-- Every nzr_*.ydr in stream/ streams on its own (textures are embedded in each drawable);
-- the one ytyp below registers their archetypes. How the files are made: stream/README.md.
files {
    'stream/nzr_props.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/nzr_props.ytyp'
