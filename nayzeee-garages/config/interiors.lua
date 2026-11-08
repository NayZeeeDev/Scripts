--[[
  nayzeee-garages — GTA V interior profiles usable as garage interiors (shared, data only).

  The interior creator (admin panel > Interiors) lists these profiles. Picking one loads its
  IPLs / entity sets, teleports the admin to `coords` and fills in the profile's preset
  vehicle positions: a garage interior made from a profile works without placing anything.
  Admins can still move, remove or add positions, or build an interior from scratch.

  Config.IplProfiles[key] = {
    label          = 'Shown in the creator',
    coords         = vector4(x, y, z, heading) | nil   -- where players stand when they arrive (entry)
    interiorCoords = vector3(x, y, z) | nil            -- a point inside the interior (entity sets / interior id lookup)
    slots          = 10,                               -- vehicle capacity shown in the creator
    presets        = { vector4(x, y, z, heading), ... } | nil
                     -- default vehicle positions (z = a little above the floor: display
                     -- vehicles are put on the ground when they spawn)
    presetsFrom    = 'profile key' | nil
                     -- the same GTA interior model placed elsewhere: the creator derives this
                     -- profile's positions (and entry) from that profile's presets in game, from
                     -- the two interiors' own position and rotation
    ipls           = { 'ipl_name', ... },              -- RequestIpl names loaded with the interior
    entitySets     = { 'set_name', ... },              -- entity sets always activated
    options        = {                                 -- admin selectable variations
      { key = 'style', label = 'Style', default = 'a',
        choices = { { value = 'a', label = 'A', entitySets = { 'set_a' } }, ... } },
    },
  }

  Notes
  - Vanilla garages (2 / 6 / 10 cars) are part of the base map and always loaded.
  - DLC interiors require the matching game build (server.cfg `sv_enforceGameBuild`):
    Import/Export (CEO garages, vehicle warehouse) 944+, Los Santos Tuners 2372+.
  - Interior placements come from public map documentation (bob74_ipl). Default vehicle
    positions are the GTA Online parking spots as published by open-source garage / IPL
    resources (xnOnlineGarage, mh_garage, randol_carmeet), checked against those placements:
    every position lies inside its interior and the four CEO level 1 garages match one
    another (same model, rotated) within about a metre.
  - Interiors whose placement could not be verified (Arena War workshop, Agency vehicle
    workshop, Vinewood Car Club ...) are not listed. Add them here with `coords = nil` and
    use "Pick entry" in the creator while standing inside, or fill in verified coordinates.
]]

---------------------------------------------------------------------------------------
-- Garage interior behaviour (shared)
---------------------------------------------------------------------------------------
Config.InteriorOptions = {
  -- 'player': every player gets a private copy of the interior (own routing bucket) with
  --           only their own vehicles; nobody can be invited in.
  -- 'shared': one copy per garage owner (or per private group that stores its vehicles
  --           together): owners invite nearby players, group members visit together.
  instances = 'player',

  -- Camera ride when a player arrives inside.
  cinematic = {
    enabled = true,
    -- No camera path set in the creator: glide past the parked vehicles, then settle
    -- behind the player.
    auto = true,
    duration = 7500,    -- ms, 4000-12000 (the automatic path picks 6000-9000 from its length)
    skippable = true,   -- any key skips it
  },

  -- Vehicle card that floats above a display vehicle while the player walks next to it.
  vehicleTag = {
    enabled = true,
    distance = 5.0,     -- metres from the vehicle
  },
}

---------------------------------------------------------------------------------------
-- IPL profiles
---------------------------------------------------------------------------------------

-- Choice lists shared by every CEO office garage level (Import/Export).
local CEO_DECOR = {
  { value = 'decor_1', label = 'Decor 1', entitySets = { 'garage_decor_01' } },
  { value = 'decor_2', label = 'Decor 2', entitySets = { 'garage_decor_02' } },
  { value = 'decor_3', label = 'Decor 3', entitySets = { 'garage_decor_03' } },
  { value = 'decor_4', label = 'Decor 4', entitySets = { 'garage_decor_04' } },
}

local CEO_LIGHTING = {
  { value = 'lighting_1', label = 'Lighting 1', entitySets = { 'lighting_option01' } },
  { value = 'lighting_2', label = 'Lighting 2', entitySets = { 'lighting_option02' } },
  { value = 'lighting_3', label = 'Lighting 3', entitySets = { 'lighting_option03' } },
  { value = 'lighting_4', label = 'Lighting 4', entitySets = { 'lighting_option04' } },
  { value = 'lighting_5', label = 'Lighting 5', entitySets = { 'lighting_option05' } },
  { value = 'lighting_6', label = 'Lighting 6', entitySets = { 'lighting_option06' } },
  { value = 'lighting_7', label = 'Lighting 7', entitySets = { 'lighting_option07' } },
  { value = 'lighting_8', label = 'Lighting 8', entitySets = { 'lighting_option08' } },
  { value = 'lighting_9', label = 'Lighting 9', entitySets = { 'lighting_option09' } },
}

--- Floor numbering signs differ per garage level (suffix _n1 / _n2 / _n3).
local function ceoNumbering(level)
  local choices = { { value = 'none', label = 'None', entitySets = {} } }
  for style = 1, 9 do
    choices[#choices + 1] = {
      value = 'style_' .. style,
      label = 'Style ' .. style,
      entitySets = { ('numbering_style%02d_n%d'):format(style, level) },
    }
  end
  return choices
end

--- One CEO office garage. Each garage is its own interior with three decks; the presets
--- hold five parking spots per deck (GTA Online fits 6 / 7 / 7 per deck: admins can add the
--- rest in the creator). Level 1 garages carry their positions; levels 2 and 3 reuse the
--- level 1 layout of the nearest garage that does not overlap them (`from`), moved and
--- turned in game (see presetsFrom). Arcadius uses its own level 1 (~75 m away); in Maze
--- Bank Tower, Lom Bank and Maze Bank West the three garages are stacked or overlap, so
--- Maze Bank Tower uses Arcadius (~250 m) and Lom Bank / Maze Bank West use each other
--- (~210 m).
---@param extra table { coords = vector4, presets = {...} } | { from = 'profile key' }
local function ceoGarage(label, ipl, level, x, y, z, extra)
  return {
    label = label,
    coords = extra.coords or vector4(x, y, z, 0.0),
    interiorCoords = vector3(x, y, z),
    slots = 15,
    presets = extra.presets,
    presetsFrom = extra.from,
    ipls = { ipl },
    entitySets = {},
    options = {
      { key = 'decor', label = 'Decor', default = 'decor_1', choices = CEO_DECOR },
      { key = 'lighting', label = 'Lighting', default = 'lighting_1', choices = CEO_LIGHTING },
      { key = 'numbering', label = 'Floor numbers', default = 'style_1', choices = ceoNumbering(level) },
    },
  }
end

Config.IplProfiles = {
  -------------------------------------------------------------------------------------
  -- Vanilla apartment garages (base map, always loaded)
  -------------------------------------------------------------------------------------
  garage_2car = {
    label = 'Low-end garage (2 cars)',
    coords = vector4(178.716, -1005.483, -99.0, 92.59),
    interiorCoords = vector3(173.2903, -1003.6, -99.65707),
    slots = 2,
    presets = {
      vector4(175.121, -1004.431, -99.500, 175.95),
      vector4(171.809, -1004.498, -99.500, 180.00),
    },
    ipls = {},
    entitySets = {},
    options = {},
  },
  garage_6car = {
    label = 'Mid-range garage (6 cars)',
    coords = vector4(207.188, -999.216, -99.0, 89.84),
    interiorCoords = vector3(197.8153, -1002.293, -99.65749),
    slots = 6,
    presets = {
      vector4(193.949, -1004.425, -99.500, 355.96),
      vector4(197.500, -1004.425, -99.500, 355.96),
      vector4(201.060, -1004.425, -99.500, 355.96),
      vector4(204.620, -1004.425, -99.500, 355.96),
      vector4(192.926, -996.329, -99.500, 213.72),
      vector4(197.500, -996.329, -99.500, 213.72),
    },
    ipls = {},
    entitySets = {},
    options = {},
  },
  garage_10car = {
    label = 'High-end garage (10 cars)',
    coords = vector4(228.0, -1003.7, -99.0, 0.0),
    interiorCoords = vector3(229.9559, -981.7928, -99.66071),
    slots = 10,
    presets = {
      vector4(223.400, -1001.000, -99.500, 300.00),
      vector4(223.400, -996.000, -99.500, 300.00),
      vector4(223.400, -991.000, -99.500, 300.00),
      vector4(223.400, -986.000, -99.500, 300.00),
      vector4(223.400, -981.000, -99.500, 300.00),
      vector4(232.700, -1001.000, -99.500, 60.00),
      vector4(232.700, -996.000, -99.500, 60.00),
      vector4(232.700, -991.000, -99.500, 60.00),
      vector4(232.700, -986.000, -99.500, 60.00),
      vector4(232.700, -981.000, -99.500, 60.00),
    },
    ipls = {},
    entitySets = {},
    options = {},
  },

  -------------------------------------------------------------------------------------
  -- Import/Export (build 944+)
  -------------------------------------------------------------------------------------
  -- Upper room (office, car lift hatch, style sets) and the vehicle hall below it, where
  -- the parking spots are.
  vehicle_warehouse = {
    label = 'Vehicle warehouse (Import/Export)',
    coords = vector4(1003.44, -2998.087, -48.647, 124.32),
    interiorCoords = vector3(994.5925, -3002.594, -39.64699),
    slots = 10,
    presets = {
      vector4(1001.642, -2992.912, -48.717, 180.17),
      vector4(993.845, -2992.863, -48.717, 177.59),
      vector4(985.884, -2993.415, -48.715, 179.72),
      vector4(978.262, -2992.959, -48.717, 177.71),
      vector4(962.591, -2993.313, -48.717, 178.72),
      vector4(954.857, -2992.744, -48.717, 178.56),
      vector4(947.111, -2992.716, -48.718, 180.83),
      vector4(939.204, -2993.235, -48.718, 178.95),
      vector4(978.172, -3006.107, -48.813, 359.38),
      vector4(970.236, -3006.631, -48.813, 359.34),
    },
    ipls = {
      'imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_',
      'imp_impexp_interior_placement_interior_3_impexp_int_02_milo_',
    },
    entitySets = { 'car_floor_hatch' },
    options = {
      {
        key = 'style', label = 'Style', default = 'branded',
        choices = {
          { value = 'basic', label = 'Basic', entitySets = { 'basic_style_set' } },
          { value = 'branded', label = 'Branded', entitySets = { 'branded_style_set' } },
          { value = 'urban', label = 'Urban', entitySets = { 'urban_style_set' } },
        },
      },
    },
  },

  -- CEO office garages: three garages per office building.
  ceo_arcadius_garage_1 = ceoGarage('Arcadius Business Center garage (level 1)', 'imp_dt1_02_cargarage_a', 1, -191.0133, -579.1428, 135.0, {
    coords = vector4(-195.84, -583.03, 135.001, 300.05),
    presets = {
      vector4(-194.363, -575.547, 134.735, 242.11),
      vector4(-185.780, -573.545, 134.736, 205.67),
      vector4(-179.695, -573.091, 134.734, 165.81),
      vector4(-174.115, -577.454, 134.734, 113.13),
      vector4(-173.072, -584.026, 134.735, 74.85),
      vector4(-192.584, -578.216, 140.243, 239.71),
      vector4(-186.375, -573.096, 140.243, 204.93),
      vector4(-179.661, -573.200, 140.243, 167.36),
      vector4(-173.871, -576.998, 140.243, 118.63),
      vector4(-173.252, -583.906, 140.243, 72.34),
      vector4(-193.189, -579.176, 145.389, 253.13),
      vector4(-186.115, -572.963, 145.389, 204.01),
      vector4(-179.465, -572.676, 145.389, 167.50),
      vector4(-173.676, -577.355, 145.389, 115.26),
      vector4(-172.836, -584.024, 145.389, 76.93),
    },
  }),
  ceo_arcadius_garage_2 = ceoGarage('Arcadius Business Center garage (level 2)', 'imp_dt1_02_cargarage_b', 2, -117.4989, -568.1132, 135.0, { from = 'ceo_arcadius_garage_1' }),
  ceo_arcadius_garage_3 = ceoGarage('Arcadius Business Center garage (level 3)', 'imp_dt1_02_cargarage_c', 3, -136.078, -630.1852, 135.0, { from = 'ceo_arcadius_garage_1' }),

  ceo_maze_bank_garage_1 = ceoGarage('Maze Bank Tower garage (level 1)', 'imp_dt1_11_cargarage_a', 1, -84.2193, -823.0851, 221.0, {
    coords = vector4(-88.798, -822.32, 221.001, 212.97),
    presets = {
      vector4(-85.241, -818.236, 220.735, 215.57),
      vector4(-76.932, -819.936, 220.734, 176.22),
      vector4(-71.094, -822.319, 220.735, 140.83),
      vector4(-67.983, -828.686, 220.734, 94.57),
      vector4(-70.259, -836.058, 220.734, 45.08),
      vector4(-84.397, -819.849, 226.173, 211.01),
      vector4(-76.775, -819.621, 226.173, 171.16),
      vector4(-71.106, -823.038, 226.173, 136.97),
      vector4(-67.483, -828.406, 226.173, 92.51),
      vector4(-70.125, -835.750, 226.173, 49.92),
      vector4(-85.986, -820.655, 231.518, 217.09),
      vector4(-77.216, -820.093, 231.519, 178.56),
      vector4(-71.428, -822.091, 231.518, 133.96),
      vector4(-68.030, -828.646, 231.519, 88.11),
      vector4(-70.213, -835.071, 231.519, 48.27),
    },
  }),
  ceo_maze_bank_garage_2 = ceoGarage('Maze Bank Tower garage (level 2)', 'imp_dt1_11_cargarage_b', 2, -69.8627, -824.7498, 221.0, { from = 'ceo_arcadius_garage_1' }),
  ceo_maze_bank_garage_3 = ceoGarage('Maze Bank Tower garage (level 3)', 'imp_dt1_11_cargarage_c', 3, -80.4318, -813.2536, 221.0, { from = 'ceo_arcadius_garage_1' }),

  ceo_lom_bank_garage_1 = ceoGarage('Lom Bank garage (level 1)', 'imp_sm_13_cargarage_a', 1, -1581.112, -567.245, 85.5, {
    coords = vector4(-1585.668, -565.701, 85.501, 233.17),
    presets = {
      vector4(-1579.551, -563.312, 85.301, 179.80),
      vector4(-1573.875, -568.964, 85.299, 144.76),
      vector4(-1569.297, -574.578, 85.300, 102.23),
      vector4(-1569.644, -580.143, 85.300, 73.48),
      vector4(-1576.245, -584.803, 85.300, 15.82),
      vector4(-1581.187, -565.456, 90.673, 189.28),
      vector4(-1573.855, -568.735, 90.673, 146.75),
      vector4(-1570.023, -573.822, 90.673, 106.11),
      vector4(-1570.794, -581.499, 90.673, 56.23),
      vector4(-1576.841, -585.552, 90.673, 11.83),
      vector4(-1580.881, -566.047, 96.019, 188.52),
      vector4(-1573.570, -568.032, 96.019, 149.38),
      vector4(-1570.291, -574.173, 96.020, 104.54),
      vector4(-1570.660, -581.344, 96.019, 59.09),
      vector4(-1576.479, -585.461, 96.019, 8.95),
    },
  }),
  ceo_lom_bank_garage_2 = ceoGarage('Lom Bank garage (level 2)', 'imp_sm_13_cargarage_b', 2, -1568.739, -562.0455, 85.5, { from = 'ceo_maze_bank_west_garage_1' }),
  ceo_lom_bank_garage_3 = ceoGarage('Lom Bank garage (level 3)', 'imp_sm_13_cargarage_c', 3, -1563.557, -574.4314, 85.5, { from = 'ceo_maze_bank_west_garage_1' }),

  ceo_maze_bank_west_garage_1 = ceoGarage('Maze Bank West garage (level 1)', 'imp_sm_15_cargarage_a', 1, -1388.84, -478.7402, 56.1, {
    coords = vector4(-1393.037, -483.113, 56.101, 1.46),
    presets = {
      vector4(-1390.451, -478.069, 56.103, 253.21),
      vector4(-1383.994, -472.677, 56.102, 208.51),
      vector4(-1377.721, -471.979, 56.102, 168.88),
      vector4(-1372.022, -475.247, 56.102, 125.20),
      vector4(-1370.779, -483.416, 56.102, 72.13),
      vector4(-1390.497, -478.112, 61.222, 254.32),
      vector4(-1383.889, -472.780, 61.222, 205.66),
      vector4(-1377.089, -471.686, 61.222, 162.46),
      vector4(-1371.205, -476.295, 61.222, 110.95),
      vector4(-1370.706, -483.185, 61.222, 70.02),
      vector4(-1390.958, -477.979, 66.752, 256.88),
      vector4(-1384.084, -472.688, 66.752, 212.45),
      vector4(-1377.256, -471.610, 66.752, 162.16),
      vector4(-1371.306, -475.407, 66.752, 120.81),
      vector4(-1370.723, -483.336, 66.752, 70.79),
    },
  }),
  ceo_maze_bank_west_garage_2 = ceoGarage('Maze Bank West garage (level 2)', 'imp_sm_15_cargarage_b', 2, -1388.86, -478.7574, 48.1, { from = 'ceo_lom_bank_garage_1' }),
  ceo_maze_bank_west_garage_3 = ceoGarage('Maze Bank West garage (level 3)', 'imp_sm_15_cargarage_c', 3, -1374.682, -474.3586, 56.1, { from = 'ceo_lom_bank_garage_1' }),

  -------------------------------------------------------------------------------------
  -- Los Santos Tuners (build 2372+). Both interiors exist in the map files of that build;
  -- no extra IPL is needed for the rooms themselves.
  -------------------------------------------------------------------------------------
  tuner_car_meet = {
    label = 'LS Car Meet (Tuners)',
    coords = vector4(-2203.87, 1146.48, -23.26, 177.79),
    interiorCoords = vector3(-2000.0, 1113.211, -25.36243),
    slots = 20,
    presets = {
      vector4(-2165.869, 1082.985, -24.701, 89.86),
      vector4(-2165.794, 1089.566, -24.606, 92.74),
      vector4(-2165.591, 1096.143, -24.615, 90.99),
      vector4(-2165.858, 1099.124, -24.617, 90.38),
      vector4(-2165.714, 1113.013, -24.320, 84.78),
      vector4(-2165.733, 1116.056, -24.338, 92.45),
      vector4(-2165.556, 1122.993, -24.536, 86.24),
      vector4(-2157.588, 1085.964, -24.314, 270.58),
      vector4(-2157.666, 1088.977, -24.615, 269.28),
      vector4(-2157.414, 1092.661, -24.616, 273.08),
      vector4(-2157.489, 1099.388, -24.168, 269.77),
      vector4(-2157.516, 1112.608, -24.609, 275.95),
      vector4(-2157.769, 1119.500, -24.338, 87.79),
      vector4(-2157.618, 1122.988, -24.520, 294.54),
      vector4(-2177.767, 1082.607, -24.316, 269.65),
      vector4(-2178.015, 1092.904, -24.523, 90.00),
      vector4(-2177.442, 1103.559, -24.408, 285.10),
      vector4(-2177.862, 1112.456, -24.413, 279.00),
      vector4(-2177.996, 1115.811, -24.413, 270.00),
      vector4(-2177.909, 1126.199, -24.181, 270.50),
    },
    ipls = {},
    entitySets = {},
    options = {
      {
        key = 'lighting', label = 'Lighting', default = 'premium',
        choices = {
          { value = 'premium', label = 'Premium', entitySets = { 'entity_set_meet_lights' } },
          { value = 'budget', label = 'Budget', entitySets = { 'entity_set_meet_lights_cheap' } },
        },
      },
      {
        key = 'crowd', label = 'Crowd', default = 'off',
        choices = {
          { value = 'off', label = 'Empty', entitySets = {} },
          { value = 'on', label = 'Car meet crowd', entitySets = { 'entity_set_meet_crew' } },
        },
      },
    },
  },
  tuner_auto_shop = {
    label = 'Auto Shop (Tuners)',
    coords = vector4(-1357.67, 164.55, -99.19, 184.52),
    interiorCoords = vector3(-1350.0, 160.0, -100.0),
    slots = 10,
    presets = {
      vector4(-1329.425, 156.265, -99.265, 180.29),
      vector4(-1333.334, 156.395, -99.298, 179.72),
      vector4(-1337.506, 156.044, -99.161, 179.54),
      vector4(-1342.190, 155.810, -99.055, 181.39),
      vector4(-1342.291, 142.635, -99.367, 358.85),
      vector4(-1337.753, 142.599, -99.367, 358.44),
      vector4(-1333.205, 142.648, -99.487, 0.87),
      vector4(-1329.059, 142.627, -99.487, 359.96),
      vector4(-1324.629, 143.047, -99.178, 359.58),
      vector4(-1324.698, 149.480, -99.364, 88.76),
    },
    ipls = {},
    entitySets = { 'entity_set_car_lift_default' },
    options = {
      {
        key = 'style', label = 'Style', default = 'style_1',
        choices = {
          { value = 'style_1', label = 'Style 1', entitySets = { 'entity_set_style_1' } },
          { value = 'style_2', label = 'Style 2', entitySets = { 'entity_set_style_2' } },
          { value = 'style_3', label = 'Style 3', entitySets = { 'entity_set_style_3' } },
          { value = 'style_4', label = 'Style 4', entitySets = { 'entity_set_style_4' } },
          { value = 'style_5', label = 'Style 5', entitySets = { 'entity_set_style_5' } },
          { value = 'style_6', label = 'Style 6', entitySets = { 'entity_set_style_6' } },
          { value = 'style_7', label = 'Style 7', entitySets = { 'entity_set_style_7' } },
          { value = 'style_8', label = 'Style 8', entitySets = { 'entity_set_style_8' } },
          { value = 'style_9', label = 'Style 9', entitySets = { 'entity_set_style_9' } },
        },
      },
    },
  },
}
