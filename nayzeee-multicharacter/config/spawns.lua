-- ███████╗██████╗  █████╗ ██╗    ██╗███╗   ██╗    ██████╗  ██████╗ ██╗███╗   ██╗████████╗███████╗
-- ██╔════╝██╔══██╗██╔══██╗██║    ██║████╗  ██║    ██╔══██╗██╔═══██╗██║████╗  ██║╚══██╔══╝██╔════╝
-- ███████╗██████╔╝███████║██║ █╗ ██║██╔██╗ ██║    ██████╔╝██║   ██║██║██╔██╗ ██║   ██║   ███████╗
-- ╚════██║██╔═══╝ ██╔══██║██║███╗██║██║╚██╗██║    ██╔═══╝ ██║   ██║██║██║╚██╗██║   ██║   ╚════██║
-- ███████║██║     ██║  ██║╚███╔███╔╝██║ ╚████║    ██║     ╚██████╔╝██║██║ ╚████║   ██║   ███████║
-- ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═══╝    ╚═╝      ╚═════╝ ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

--[[
    id       unique id
    label    name in the list
    desc     small line under the name
    icon     Font Awesome icon (fa-solid) without the "fa-" prefix is fine too
    coords   vec4 where the player lands
    jobs     optional { jobname = minGrade } - only these jobs see the point
    newOnly  optional true - only shown to brand new characters
]]

Config.SpawnPoints = {
    { id = 'lsia',    label = 'Los Santos Airport', desc = 'Arrivals terminal',        icon = 'plane-arrival',  coords = vec4(-1037.64, -2737.76, 20.17, 327.0) },
    { id = 'legion',  label = 'Legion Square',      desc = 'Downtown Los Santos',      icon = 'city',           coords = vec4(195.17, -933.77, 30.69, 144.5) },
    { id = 'pier',    label = 'Del Perro Pier',     desc = 'Beachfront, Del Perro',    icon = 'water',          coords = vec4(-1686.61, -1068.28, 13.15, 50.0) },
    { id = 'vinewood',label = 'Vinewood Boulevard', desc = 'Uptown Vinewood',          icon = 'star',           coords = vec4(296.42, 181.63, 104.33, 160.0) },
    { id = 'sandy',   label = 'Sandy Shores',       desc = 'Blaine County',            icon = 'sun',            coords = vec4(1961.39, 3740.58, 32.34, 300.0) },
    { id = 'paleto',  label = 'Paleto Bay',         desc = 'Northern coast',           icon = 'tree',           coords = vec4(-160.12, 6329.39, 31.58, 315.0) },
    { id = 'mrpd',    label = 'Mission Row PD',     desc = 'On duty',                  icon = 'shield-halved',  coords = vec4(428.23, -984.28, 29.76, 3.5),   jobs = { police = 0 } },
    { id = 'pillbox', label = 'Pillbox Medical',    desc = 'On duty',                  icon = 'heart-pulse',    coords = vec4(298.06, -584.55, 43.26, 70.0),  jobs = { ambulance = 0 } },
}
