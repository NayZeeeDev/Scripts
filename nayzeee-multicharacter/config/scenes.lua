-- ███████╗ ██████╗███████╗███╗   ██╗███████╗███████╗
-- ██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝██╔════╝
-- ███████╗██║     █████╗  ██╔██╗ ██║█████╗  ███████╗
-- ╚════██║██║     ██╔══╝  ██║╚██╗██║██╔══╝  ╚════██║
-- ███████║╚██████╗███████╗██║ ╚████║███████╗███████║
-- ╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝

--[[
    Each scene is a place where the characters stand.

    id        unique id (used by Config.Scene.pick and the Settings scene picker)
    label     name shown in Settings
    anchor    where the (invisible) player ped waits during selection - keep it close to the positions so the area streams in
    weather / hour / minute   forced while in selection (players can override in Settings)
    timecycle optional timecycle modifier + strength
    intro     optional camera the intro glide starts from { coords, pointAt, fov } - leave out for an automatic zoom-in
    overview  camera that shows the whole lineup   { coords, pointAt OR rot, fov }
    positions one per character on a page. More slots than positions = pages (the lineup swaps with a quick fade).
        coords    vec4 (entity coords + heading, as printed by /mc_coords)
        anim      { dict, clip, flag } or { scenario } - default pose for this spot
        lockPose  true = keep this anim even if the player picked another pose (seated spots etc.)
        ground    false = never snap this spot to the floor (Config.Scene.snapToGround). Seated (lockPose) spots
                  keep their own height unless they are clearly sunk; set ground = true to always snap them.
        groundOffset  optional height tweak after snapping, e.g. 0.05
        camera    optional focus camera override { coords, pointAt, fov }. Leave out to auto-frame the ped.
    props     { model, coords = vec4 }
    vehicles  { model, coords = vec4, color = {primary, secondary}, lights = true, doors = { 0, 1 } (open doors) }

    Use /mc_coords in game (admin) to copy your position and the gameplay camera to the clipboard.
]]

Config.Scenes = {
    {
        id = 'penthouse',
        label = 'Penthouse',
        anchor  = vec4(-595.1445, -710.9232, 113.0053, 255.1106),
        weather = 'EXTRASUNNY', hour = 21, minute = 0,
        overview = { coords = vec3(-586.2933, -706.5692, 114.0051), rot = vec3(-3.0022, 0.0, 123.6820), fov = 57.0 },
        positions = {
            { coords = vec4(-596.7833, -707.2360, 114.3052, 262.1913), anim = { dict = 'timetable@ron@ig_3_couch', clip = 'base' }, lockPose = true },
            { coords = vec4(-600.9791, -709.5421, 116.8003, 274.6356), anim = { dict = 'anim@amb@nightclub@peds@', clip = 'rcmme_amanda1_stand_loop_cop' } },
            { coords = vec4(-591.6877, -713.9263, 113.0053, 318.3587), anim = { dict = 'timetable@ron@ig_5_p3', clip = 'ig_5_p3_base' }, lockPose = true },
            { coords = vec4(-595.1445, -710.9232, 113.0053, 255.1106), anim = { dict = 'anim@heists@prison_heistig1_p1_guard_checks_bus', clip = 'loop' } },
        },
        props = {},
        vehicles = {},
    },
    {
        id = 'shore',
        label = 'Paleto Shore',
        anchor  = vec4(66.0174, 7188.3491, 1.4332, 59.7735),
        weather = 'SMOG', hour = 23, minute = 0,
        overview = { coords = vec3(34.9546, 7199.9526, 10.2047), pointAt = vec3(64.20, 7189.60, 1.50), fov = 36.0 },
        positions = {
            { coords = vec4(67.7456, 7194.3882, 1.5501, 42.4638),  anim = { dict = 'missdocksshowoffcar@idle_a', clip = 'idle_b_5' },
              camera = { coords = vec3(64.6069, 7200.0630, 2.8786), pointAt = vec3(67.60, 7194.40, 1.75), fov = 26.0 } },
            { coords = vec4(66.0174, 7188.3491, 1.4332, 59.7735),  anim = { dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss' },
              camera = { coords = vec3(61.9422, 7192.1289, 2.8725), pointAt = vec3(66.00, 7188.40, 1.65), fov = 26.0 } },
            { coords = vec4(59.7110, 7183.2471, 1.6228, 322.9862), anim = { scenario = 'WORLD_HUMAN_AA_COFFEE' },
              camera = { coords = vec3(60.7500, 7188.7920, 2.8235), pointAt = vec3(59.75, 7183.30, 1.85), fov = 26.0 } },
        },
        props = {
            { model = 'xm_prop_base_tripod_lampb', coords = vec4(69.9330, 7188.8125, 1.1861, 274.8404) },
            { model = 'xm_prop_base_tripod_lampb', coords = vec4(67.5469, 7186.2432, 1.2403, 179.5323) },
        },
        vehicles = {},
    },
    {
        id = 'rooftop',
        label = 'Rooftop (solo)',
        anchor  = vec4(-885.82, -453.44, 124.26, 69.5),
        weather = 'EXTRASUNNY', hour = 22, minute = 0,
        timecycle = { name = 'int_carrier_stair', strength = 1.0 },
        intro    = { coords = vec3(-892.56, -450.19, 124.86), pointAt = vec3(-885.82, -453.44, 125.00), fov = 50.0 },
        overview = { coords = vec3(-889.04, -450.63, 124.46), pointAt = vec3(-885.82, -453.44, 125.06), fov = 18.0 },
        positions = {
            { coords = vec4(-885.82, -453.44, 124.26, 69.5), anim = { dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss' } },
        },
        props = {},
        vehicles = {},
    },
}
