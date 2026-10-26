fx_version 'cerulean'
game 'gta5'

name 'nayzeee-ambulance-props'
author 'NAYZEEE'
description 'NAYZEEE Ambulance - the streamed props (stretchers, beds, devices, bags) used by nayzeee-ambulance'
version '1.0.0'

-- Only models live in this resource. Restarting nayzeee-ambulance (a config change, an update)
-- leaves them alone: players keep them loaded and cached instead of downloading and
-- re-registering every model again. Start this resource before nayzeee-ambulance.
files {
    'stream/nz_amb_props.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/nz_amb_props.ytyp'
