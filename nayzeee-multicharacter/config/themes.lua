-- ████████╗██╗  ██╗███████╗███╗   ███╗███████╗███████╗
-- ╚══██╔══╝██║  ██║██╔════╝████╗ ████║██╔════╝██╔════╝
--    ██║   ███████║█████╗  ██╔████╔██║█████╗  ███████╗
--    ██║   ██╔══██║██╔══╝  ██║╚██╔╝██║██╔══╝  ╚════██║
--    ██║   ██║  ██║███████╗██║ ╚═╝ ██║███████╗███████║
--    ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚══════╝╚══════╝

--[[
    LOBBY THEMES — the 3D scene a character stands in.

    Everything except `main` is RELATIVE to the main character, so you can move a whole scene by changing one line:
        offset  = vec3(right, forward, up)   metres, "forward" = the way the main character faces (towards the camera)
        heading = degrees added to the main character's heading
    You can always use absolute world coords instead: coords = vec4(x, y, z, heading)  (as printed by /mc_coords).

    Fields
      label / description / icon / category   shown in the theme switcher (category: lifestyle | luxury | fashion | tactical)
      palette        3 hex colours for the theme card art in the UI
      main           vec4 of the main character (z is snapped to the floor automatically)
      interior       true = pin + wait for the interior before spawning peds
      weather / hour / minute   world state while in this lobby (moods can override hour / timecycle)
      mood           default mood id (moods.lua). moods = { ids } limits the list, nil = all
      timecycle      { name, strength } base look for this theme (the mood's timecycle wins when it has one)
      slots          [2] couple anchor, [3] / [4] squad. { offset, heading }
      pet            { offset, heading }
      poses          default pose per slot when a character never picked one (poses.lua ids)
      props          { model, offset, heading, collision }
      vehicles       { model, offset, heading, color = { primary, secondary }, livery, extras, mods = true,
                       lights = true, doorsOpen = { 0 }, crew = { { model, seat } } }   -- vehicle 1, 2 ... in departure steps
      lights         { tint = { r, g, b }, scale = 1.0, rig = {...} (replace Config.Lighting.rig), extra = { light, ... } }
      cameras        override camera modes: start | squad | duo | body | face = { offset, lookAt, fov }
      ambience       { preset = 'city'|'rooftop'|'club'|'street'|'ocean'|'airport'|'helipad'|'garage', url = optional audio file }
      departure      cutscene before entering the world — see docs/CONTRACT.md §8 for every step type

    Coordinates were taken from Rockstar's own placements and public configs. Walk each scene once with /mc_lobby <id>
    (admin) and fine-tune with /mc_coords — every server's map mods differ.
]]

-- Shared layout for the squad around the main character (used by most themes)
local SQUAD = {
    [2] = { offset = vec3( 0.95,  0.15, 0.0), heading = -8.0 },     -- couple anchor, right beside you
    [3] = { offset = vec3(-1.10,  0.45, 0.0), heading =  10.0 },
    [4] = { offset = vec3( 2.00,  0.60, 0.0), heading = -14.0 },
}
local PET = { offset = vec3(-0.55, 0.95, 0.0), heading = 15.0 }

Config.LobbyThemes = {

    -- 1 ────────────────────────────────────────────────────────────────────────────────────────────
    supercar = {
        order = 1, label = 'Supercar · City Dusk', icon = 'car', category = 'luxury',
        description = 'Leaning on an exotic downtown as the city lights come on.',
        palette = { '#ff9a4d', '#5b2a86', '#0b0d1a' },
        main = vec4(244.44, -1009.74, 29.89, 71.9),                -- Legion Square, east kerb
        weather = 'CLEAR', hour = 20, minute = 10,
        mood = 'moody_dusk',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'lean_car', [2] = 'relaxed', [3] = 'crossed', [4] = 'phone' },
        vehicles = {
            { model = 't20', offset = vec3(0.30, -1.35, 0.0), heading = 270.0, color = { 12, 12 }, mods = true, lights = true },
        },
        cameras = {
            start = { offset = vec3(-4.5, 9.5, 2.4), lookAt = vec3(0.5, 0.0, 0.6), fov = 50.0 },
            squad = { offset = vec3( 0.6, 5.8, 0.55), lookAt = vec3(0.45, 0.0, 0.15), fov = 46.0 },
        },
        ambience = { preset = 'city' },
        departure = {
            duration = 9000, fadeAt = 7400,
            camera = {
                { offset = vec3( 1.8, 4.6, 0.9), lookAt = vec3(0.3, -1.0, 0.4), fov = 42.0, time = 0 },
                { offset = vec3(-3.2, 3.4, 1.1), lookAt = vec3(0.6, -1.4, 0.5), fov = 38.0, time = 3400 },
                { offset = vec3(-6.0, 2.0, 1.4), lookAt = vec3(9.0, -1.4, 0.5), fov = 34.0, time = 3200, follow = 'vehicle1' },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 350,  ['do'] = 'enterVehicle', vehicle = 1, seat = -1, speed = 1.2 },
                { at = 350,  ['do'] = 'petEnter',     vehicle = 1, seat = 0 },
                { at = 3700, ['do'] = 'lights',       vehicle = 1 },
                { at = 3900, ['do'] = 'engine',       vehicle = 1 },
                { at = 4700, ['do'] = 'drive',        vehicle = 1, to = vec3(42.0, -1.35, 0.0), speed = 10.0 },
            },
        },
    },

    -- 2 ────────────────────────────────────────────────────────────────────────────────────────────
    penthouse = {
        order = 2, label = 'Penthouse · Skyline', icon = 'building', category = 'luxury',
        description = 'A high-rise rooftop over the Vinewood skyline.',
        palette = { '#f5c56b', '#c2593a', '#14101c' },
        main = vec4(-885.82, -453.44, 124.26, 69.5),               -- Weazel Plaza rooftop (verify with /mc_lobby)
        weather = 'EXTRASUNNY', hour = 19, minute = 30,
        mood = 'golden_hour',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'relaxed', [2] = 'coffee', [3] = 'phone', [4] = 'crossed' },
        cameras = {
            start = { offset = vec3(-6.0, 8.0, 3.0), lookAt = vec3(0.4, 0.0, 0.8), fov = 52.0 },
            squad = { offset = vec3( 0.5, 5.4, 0.45), lookAt = vec3(0.45, 0.0, 0.2), fov = 46.0 },
        },
        ambience = { preset = 'rooftop' },
        departure = {
            duration = 8000, fadeAt = 6400,
            camera = {
                { offset = vec3(0.4, 4.0, 0.7), lookAt = vec3(0.0, 0.0, 0.5), fov = 40.0, time = 0 },
                { offset = vec3(2.6, 2.8, 1.2), lookAt = vec3(-1.5, -3.0, 0.4), fov = 36.0, time = 3600 },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 200,  ['do'] = 'anim', target = 'main', pose = 'phone', time = 2200 },
                { at = 2500, ['do'] = 'walkTo', to = vec3(-2.6, -6.5, 0.0), speed = 1.0 },
                { at = 2600, ['do'] = 'petFollow' },
            },
        },
    },

    -- 3 ────────────────────────────────────────────────────────────────────────────────────────────
    studio = {
        order = 3, label = 'Velvet Studio', icon = 'sparkles', category = 'fashion',
        description = 'Pink and violet neon — made for outfits, hair and detail.',
        palette = { '#ff5fa2', '#7b5cff', '#120a1a' },
        main = vec4(114.50, -1289.50, 28.26, 285.3),               -- Vanilla Unicorn floor, back to the stage
        interior = true,
        weather = 'CLEAR', hour = 23, minute = 0,
        mood = 'midnight_neon', moods = { 'midnight_neon', 'clean_studio', 'moody_dusk' },
        slots = {
            [2] = { offset = vec3( 0.90, 0.10, 0.0), heading = -8.0 },
            [3] = { offset = vec3(-1.00, 0.35, 0.0), heading = 10.0 },
            [4] = { offset = vec3( 1.85, 0.55, 0.0), heading = -14.0 },
        },
        pet = PET,
        poses = { [1] = 'model', [2] = 'model2', [3] = 'crossed', [4] = 'relaxed' },
        lights = {
            extra = {
                { type = 'point', offset = vec3(-1.4, -1.2, 1.8), color = { 255, 80, 170 }, range = 4.0, intensity = 4.5 },
                { type = 'point', offset = vec3( 1.6, -1.0, 1.6), color = { 110, 90, 255 }, range = 4.0, intensity = 4.0 },
            },
        },
        cameras = {
            start = { offset = vec3(-2.5, 6.0, 1.6), lookAt = vec3(0.3, 0.0, 0.7), fov = 50.0 },
            squad = { offset = vec3( 0.45, 4.6, 0.5), lookAt = vec3(0.4, 0.0, 0.25), fov = 48.0 },
        },
        ambience = { preset = 'club' },
        departure = {
            duration = 7500, fadeAt = 6000,
            camera = {
                { offset = vec3(0.0, 3.4, 0.8), lookAt = vec3(0.0, 0.0, 0.6), fov = 38.0, time = 0 },
                { offset = vec3(-1.6, 2.4, 1.1), lookAt = vec3(1.5, 4.0, 0.5), fov = 40.0, time = 3200 },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 200,  ['do'] = 'anim', target = 'main', pose = 'phone', time = 1800 },
                { at = 2100, ['do'] = 'walkTo', to = vec3(2.5, 6.0, 0.0), speed = 1.0 },
                { at = 2200, ['do'] = 'petFollow' },
            },
        },
    },

    -- 4 ────────────────────────────────────────────────────────────────────────────────────────────
    boutique = {
        order = 4, label = 'Vinewood Boutique', icon = 'shopping-bag', category = 'fashion',
        description = 'Outside the flagship stores on Portola Drive.',
        palette = { '#e8d3b0', '#8a6f4e', '#151210' },
        main = vec4(-718.00, -157.00, 37.40, 120.0),               -- Ponsonbys, Portola Drive sidewalk
        weather = 'EXTRASUNNY', hour = 18, minute = 45,
        mood = 'golden_hour',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'shopping', [2] = 'coffee', [3] = 'phone', [4] = 'relaxed' },
        vehicles = {
            { model = 'stretch', offset = vec3(-1.5, 3.6, 0.0), heading = 272.0, color = { 0, 0 }, lights = true,
              crew = { { model = 's_m_m_highsec_01', seat = -1 } } },
        },
        cameras = {
            start = { offset = vec3(-5.0, 8.5, 2.2), lookAt = vec3(0.4, 0.0, 0.8), fov = 50.0 },
            squad = { offset = vec3( 0.6, 5.2, 0.5), lookAt = vec3(0.45, 0.0, 0.2), fov = 46.0 },
        },
        ambience = { preset = 'street' },
        departure = {
            duration = 9500, fadeAt = 7900,
            camera = {
                { offset = vec3(2.2, 5.4, 1.0), lookAt = vec3(-0.6, 2.0, 0.4), fov = 42.0, time = 0 },
                { offset = vec3(3.0, 7.2, 1.4), lookAt = vec3(-1.5, 3.6, 0.5), fov = 36.0, time = 3600 },
                { offset = vec3(3.0, 7.2, 1.6), lookAt = vec3(-12.0, 3.6, 0.5), fov = 34.0, time = 3000, follow = 'vehicle1' },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 300,  ['do'] = 'enterVehicle', vehicle = 1, seat = 1, speed = 1.0 },
                { at = 300,  ['do'] = 'petEnter',     vehicle = 1, seat = 2 },
                { at = 3800, ['do'] = 'lights',       vehicle = 1 },
                { at = 4000, ['do'] = 'engine',       vehicle = 1 },
                { at = 5200, ['do'] = 'drive',        vehicle = 1, to = vec3(-40.0, 3.6, 0.0), speed = 7.0 },
            },
        },
    },

    -- 5 ────────────────────────────────────────────────────────────────────────────────────────────
    beach = {
        order = 5, label = 'Del Perro Sunset', icon = 'sun', category = 'lifestyle',
        description = 'End of the pier, the Pacific burning orange behind you.',
        palette = { '#ffb36b', '#e0576b', '#1a1430' },
        main = vec4(-1850.13, -1231.75, 13.02, 292.8),             -- Del Perro Pier, facing inland (sunset behind)
        weather = 'EXTRASUNNY', hour = 19, minute = 50,
        mood = 'golden_hour',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'lean_rail', [2] = 'relaxed', [3] = 'coffee', [4] = 'phone' },
        cameras = {
            start = { offset = vec3(-4.0, 9.0, 2.0), lookAt = vec3(0.3, -2.0, 1.0), fov = 50.0 },
            squad = { offset = vec3( 0.5, 5.6, 0.5), lookAt = vec3(0.45, 0.0, 0.25), fov = 46.0 },
        },
        ambience = { preset = 'ocean' },
        departure = {
            duration = 8000, fadeAt = 6400,
            camera = {
                { offset = vec3(0.0, 4.4, 0.8), lookAt = vec3(0.0, 0.0, 0.6), fov = 40.0, time = 0 },
                { offset = vec3(-2.2, 3.0, 1.4), lookAt = vec3(1.0, 8.0, 0.6), fov = 42.0, time = 3600 },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 200,  ['do'] = 'anim', target = 'main', pose = 'phone', time = 1800 },
                { at = 2100, ['do'] = 'walkTo', to = vec3(1.2, 9.0, 0.0), speed = 1.0 },
                { at = 2200, ['do'] = 'petFollow' },
            },
        },
    },

    -- 6 ────────────────────────────────────────────────────────────────────────────────────────────
    jet = {
        order = 6, label = 'Private Jet · LSIA', icon = 'plane', category = 'luxury',
        description = 'Wheels up from the executive apron at LSIA.',
        palette = { '#d9e2ec', '#5a7184', '#0c1117' },
        main = vec4(-1094.88, -3378.09, 12.99, 60.0),              -- LSIA south apron, beside Rockstar's Luxor spot
        weather = 'CLEAR', hour = 21, minute = 0,
        mood = 'clean_studio',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'relaxed', [2] = 'shopping', [3] = 'phone', [4] = 'crossed' },
        vehicles = {
            { model = 'luxor2', offset = vec3(-4.0, -6.5, 0.0), heading = 270.0, lights = true,
              crew = { { model = 's_m_m_pilot_01', seat = -1 }, { model = 's_m_m_pilot_01', seat = 0 } } },
        },
        props = {
            { model = 'prop_worklight_03b', offset = vec3(2.8, 1.6, 0.0), heading = 200.0 },
        },
        lights = {
            extra = {
                { type = 'spot', offset = vec3(3.5, 4.0, 4.5), target = vec3(0.0, 0.0, 0.5), color = { 235, 240, 255 }, range = 12.0, intensity = 6.0, radius = 35.0, falloff = 20.0 },
            },
        },
        cameras = {
            start = { offset = vec3(-7.0, 12.0, 3.0), lookAt = vec3(-2.0, -4.0, 1.5), fov = 50.0 },
            squad = { offset = vec3( 0.5, 6.2, 0.6), lookAt = vec3(0.4, 0.0, 0.4), fov = 48.0 },
        },
        ambience = { preset = 'airport' },
        departure = {
            duration = 11000, fadeAt = 9200,
            camera = {
                { offset = vec3(2.5, 5.0, 1.0), lookAt = vec3(-1.5, -3.0, 0.8), fov = 44.0, time = 0 },
                { offset = vec3(6.0, 9.0, 2.0), lookAt = vec3(-4.0, -6.5, 1.5), fov = 46.0, time = 4200 },
                { offset = vec3(6.0, 9.0, 2.6), lookAt = vec3(20.0, -6.5, 2.0), fov = 40.0, time = 4200, follow = 'vehicle1' },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 0,    ['do'] = 'doors',        vehicle = 1, open = { 0 } },
                { at = 300,  ['do'] = 'enterVehicle', vehicle = 1, seat = 1, speed = 1.0 },
                { at = 300,  ['do'] = 'petEnter',     vehicle = 1, seat = 2 },
                { at = 4300, ['do'] = 'doors',        vehicle = 1, close = true },
                { at = 4500, ['do'] = 'engine',       vehicle = 1 },
                { at = 4500, ['do'] = 'lights',       vehicle = 1 },
                { at = 6000, ['do'] = 'taxi',         vehicle = 1, to = vec3(60.0, -6.5, 0.0), speed = 9.0 },
            },
        },
    },

    -- 7 ────────────────────────────────────────────────────────────────────────────────────────────
    helipad = {
        order = 7, label = 'Tactical Helipad', icon = 'helicopter', category = 'tactical',
        description = 'Rotors idle, crew ready — La Puerta heliport.',
        palette = { '#8fb37a', '#3d4a35', '#0c0f0b' },
        main = vec4(-748.97, -1466.34, 5.39, 49.8),                -- Higgins Helitours pad
        weather = 'OVERCAST', hour = 21, minute = 30,
        mood = 'moody_dusk',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'tactical', [2] = 'tactical', [3] = 'crossed', [4] = 'guard' },
        vehicles = {
            { model = 'valkyrie', offset = vec3(0.6, -4.4, 0.0), heading = 270.0, lights = true,
              crew = { { model = 's_m_y_pilot_01', seat = -1 }, { model = 's_m_y_pilot_01', seat = 0 } } },
        },
        lights = {
            tint = { 220, 235, 210 },
            extra = {
                { type = 'point', offset = vec3(0.6, -4.4, 3.2), color = { 255, 60, 60 }, range = 6.0, intensity = 1.5 },
            },
        },
        cameras = {
            start = { offset = vec3(-6.5, 10.0, 3.0), lookAt = vec3(0.6, -3.0, 1.5), fov = 52.0 },
            squad = { offset = vec3( 0.5, 6.0, 0.55), lookAt = vec3(0.45, 0.0, 0.3), fov = 48.0 },
        },
        ambience = { preset = 'helipad' },
        departure = {
            duration = 12000, fadeAt = 10200,
            camera = {
                { offset = vec3(3.0, 5.5, 1.0), lookAt = vec3(0.6, -3.0, 0.9), fov = 44.0, time = 0 },
                { offset = vec3(7.0, 9.0, 1.2), lookAt = vec3(0.6, -4.4, 2.0), fov = 46.0, time = 4500 },
                { offset = vec3(7.0, 9.0, 1.4), lookAt = vec3(0.6, 10.0, 22.0), fov = 50.0, time = 4500, follow = 'vehicle1' },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 0,    ['do'] = 'rotors',       vehicle = 1 },
                { at = 300,  ['do'] = 'enterVehicle', vehicle = 1, seat = 1, speed = 1.6 },
                { at = 300,  ['do'] = 'petEnter',     vehicle = 1, seat = 2 },
                { at = 1500, ['do'] = 'ptfx',         asset = 'core', name = 'ent_amb_dust_motes', entity = 'vehicle1', offset = vec3(0.0, 0.0, -1.0), scale = 3.0 },
                { at = 6200, ['do'] = 'fly',          vehicle = 1, to = vec3(0.6, 40.0, 45.0), speed = 14.0 },
            },
        },
    },

    -- 8 ────────────────────────────────────────────────────────────────────────────────────────────
    garage = {
        order = 8, label = 'Street Tuner Garage', icon = 'wrench', category = 'lifestyle',
        description = 'Underground glow, a fresh build and the engine ticking.',
        palette = { '#3fe0ff', '#ff3d6e', '#090b12' },
        main = vec4(-206.40, -1297.22, 31.43, 90.0),               -- Benny's Original Motor Works lot
        weather = 'CLEAR', hour = 0, minute = 30,
        mood = 'midnight_neon',
        slots = SQUAD, pet = PET,
        poses = { [1] = 'lean_car', [2] = 'crossed', [3] = 'relaxed', [4] = 'phone' },
        vehicles = {
            { model = 'sultanrs', offset = vec3(0.20, -1.35, 0.0), heading = 270.0, color = { 145, 0 }, mods = true, lights = true },
        },
        lights = {
            extra = {
                { type = 'point', offset = vec3( 2.2, -2.5, 0.4), color = { 60, 220, 255 }, range = 5.0, intensity = 3.0 },
                { type = 'point', offset = vec3(-2.2, -2.5, 0.4), color = { 255, 60, 110 }, range = 5.0, intensity = 3.0 },
            },
        },
        cameras = {
            start = { offset = vec3(-4.0, 8.0, 1.6), lookAt = vec3(0.4, -1.0, 0.5), fov = 50.0 },
            squad = { offset = vec3( 0.6, 5.4, 0.4), lookAt = vec3(0.45, 0.0, 0.1), fov = 46.0 },
        },
        ambience = { preset = 'garage' },
        departure = {
            duration = 9000, fadeAt = 7400,
            camera = {
                { offset = vec3( 1.8, 4.4, 0.6), lookAt = vec3(0.2, -1.2, 0.4), fov = 42.0, time = 0 },
                { offset = vec3(-2.8, 3.2, 0.5), lookAt = vec3(0.2, -1.4, 0.4), fov = 38.0, time = 3400 },
                { offset = vec3(-6.0, 2.2, 0.8), lookAt = vec3(12.0, -1.4, 0.4), fov = 34.0, time = 3200, follow = 'vehicle1' },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },
                { at = 0,    ['do'] = 'holster' },
                { at = 350,  ['do'] = 'enterVehicle', vehicle = 1, seat = -1, speed = 1.2 },
                { at = 350,  ['do'] = 'petEnter',     vehicle = 1, seat = 0 },
                { at = 3700, ['do'] = 'lights',       vehicle = 1 },
                { at = 3900, ['do'] = 'engine',       vehicle = 1 },
                { at = 4800, ['do'] = 'drive',        vehicle = 1, to = vec3(36.0, -1.35, 0.0), speed = 9.0 },
            },
        },
    },

    -- 9 ────────────────────────────────────────────────────────────────────────────────────────────
    -- IN-FLIGHT: the lobby IS the helicopter. It flies a loop over the city with you sitting in the open door;
    -- Deploy = you jump, skydive, pull the chute, and arrive on the ground at your spawn already landed.
    skydive = {
        order = 9, label = 'Infil · Skydive', icon = 'wind', category = 'tactical',
        description = 'Riding the door of an infil chopper over Los Santos. Jump when ready.',
        palette = { '#a9c3d9', '#2f4a63', '#070b10' },
        main = vec4(-1650.0, -1450.0, 380.0, 50.0),               -- where the helicopter starts (over the ocean off Del Perro)
        weather = 'CLEAR', hour = 18, minute = 50,
        mood = 'golden_hour', moods = { 'golden_hour', 'moody_dusk', 'clean_studio' },
        pets = false,                                             -- no pets in the chopper

        -- The helicopter keeps flying this loop (crew pilot) while you're in the lobby
        flight = {
            vehicle  = 1,
            speed    = 16.0,                                      -- m/s
            altitude = 380.0,
            route    = {
                vec3(-1650.0, -1450.0, 380.0),
                vec3(-950.0,  -1350.0, 380.0),
                vec3(-700.0,  -800.0,  380.0),
                vec3(-1350.0, -650.0,  380.0),
            },
        },
        vehicles = {
            { model = 'valkyrie', offset = vec3(0.0, 0.0, 0.0), heading = 0.0, airborne = true, lights = true,
              crew = { { model = 's_m_y_pilot_01', seat = -1 }, { model = 's_m_y_pilot_01', seat = 0 } } },
        },

        -- Characters ride ATTACHED to the helicopter (vehicle-local offsets: right, forward, up from the heli's centre).
        -- Sitting in the left door with legs out like a Warzone infil. Tune with /mc_lobby skydive.
        seats = {
            [1] = { attach = { vehicle = 1, offset = vec3(-1.05,  0.45, 0.05), rotation = vec3(0.0, 0.0,  90.0) },
                    anim = { dict = 'amb@prop_human_seat_chair@male@generic@base', clip = 'base', flag = 1 } },
            [2] = { attach = { vehicle = 1, offset = vec3(-1.05, -0.35, 0.05), rotation = vec3(0.0, 0.0,  90.0) },
                    anim = { dict = 'amb@prop_human_seat_chair@male@generic@base', clip = 'base', flag = 1 } },
            [3] = { attach = { vehicle = 1, offset = vec3( 1.05,  0.45, 0.05), rotation = vec3(0.0, 0.0, -90.0) },
                    anim = { dict = 'amb@prop_human_seat_chair@male@generic@base', clip = 'base', flag = 1 } },
            [4] = { attach = { vehicle = 1, offset = vec3( 1.05, -0.35, 0.05), rotation = vec3(0.0, 0.0, -90.0) },
                    anim = { dict = 'amb@prop_human_seat_chair@male@generic@base', clip = 'base', flag = 1 } },
        },

        -- In flight every camera is attached to the helicopter: offsets are vehicle-local
        cameras = {
            attach = 'vehicle1',
            start = { offset = vec3(-9.0, 6.0, 2.5),  lookAt = vec3(0.0, 0.0, 0.0),  fov = 50.0 },
            squad = { offset = vec3(-4.6, 0.4, 0.7),  lookAt = vec3(-0.9, 0.1, 0.2), fov = 48.0 },
            body  = { offset = vec3(-3.0, 0.9, 0.4),  lookAt = vec3(-1.0, 0.45, 0.1), fov = 40.0 },
            face  = { offset = vec3(-2.1, 0.75, 0.75), lookAt = vec3(-1.05, 0.45, 0.6), fov = 34.0 },
        },
        lights = { scale = 0.8 },
        ambience = { preset = 'skydive' },
        departure = {
            duration = 13000, fadeAt = 11400, fadeTime = 1000,
            camera = {
                { attach = 'vehicle1', offset = vec3(-3.4, 1.2, 0.9), lookAt = vec3(-1.05, 0.45, 0.2), fov = 44.0, time = 0 },
                { attach = 'main',     offset = vec3(0.0, -4.2, 1.8), lookAt = vec3(0.0, 0.0, 0.0),   fov = 58.0, time = 1400 },
                { attach = 'main',     offset = vec3(0.0, -6.5, 3.5), lookAt = vec3(0.0, 0.0, -1.0),  fov = 62.0, time = 5000 },
            },
            steps = {
                { at = 0,    ['do'] = 'goodbye' },                -- squad gives a nod / wave
                { at = 0,    ['do'] = 'holster' },
                { at = 0,    ['do'] = 'sound', name = 'Whoosh_1s_L_to_R', set = 'MP_LOBBY_SOUNDS' },
                { at = 800,  ['do'] = 'jump' },                   -- detach + push off the door + freefall (TaskSkyDive)
                { at = 1300, ['do'] = 'squadJump', spacing = 450 },
                { at = 7600, ['do'] = 'parachute' },              -- chute opens, camera keeps chasing
            },
            -- Played on the ground the moment you arrive (skipped if the anim is missing on your build)
            arrival = { anim = { dict = 'move_fall@beastjump', clip = 'high_land_stand', flag = 0 }, time = 1600 },
        },
    },
}
