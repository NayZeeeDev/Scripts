--[[
  nayzeee-garages — GTA V interior profiles usable as garage interiors (shared, data only).

  The interior creator (admin panel > Interiors) lists these profiles. Picking one loads its
  IPLs / entity sets and, when `coords` is known, teleports the admin there to place the
  entry point, the camera path and the vehicle slots.

  Config.IplProfiles[key] = {
    label          = 'Shown in the creator',
    coords         = vector4(x, y, z, heading) | nil   -- quick teleport target (nil = hidden from quick teleport)
    interiorCoords = vector3(x, y, z) | nil            -- a point inside the interior (entity sets / interior id lookup)
    slots          = 10,                               -- typical vehicle capacity of the interior
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
  - Coordinates are interior placements from public map documentation. After a quick
    teleport always pick the entry point yourself in the creator.
  - Interiors whose placement could not be verified (Arena War workshop, Agency vehicle
    workshop, Vinewood Car Club ...) are not listed. Add them here with `coords = nil` and
    use "Pick entry" in the creator while standing inside, or fill in verified coordinates.
]]

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

--- One CEO office garage level. Each level is its own interior holding 20 vehicles.
local function ceoGarage(label, ipl, level, x, y, z)
  return {
    label = label,
    coords = vector4(x, y, z, 0.0),
    interiorCoords = vector3(x, y, z),
    slots = 20,
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
    coords = vector4(173.2903, -1003.6, -99.65707, 0.0),
    interiorCoords = vector3(173.2903, -1003.6, -99.65707),
    slots = 2,
    ipls = {},
    entitySets = {},
    options = {},
  },
  garage_6car = {
    label = 'Mid-range garage (6 cars)',
    coords = vector4(197.8153, -1002.293, -99.65749, 0.0),
    interiorCoords = vector3(197.8153, -1002.293, -99.65749),
    slots = 6,
    ipls = {},
    entitySets = {},
    options = {},
  },
  garage_10car = {
    label = 'High-end garage (10 cars)',
    coords = vector4(229.9559, -981.7928, -99.66071, 0.0),
    interiorCoords = vector3(229.9559, -981.7928, -99.66071),
    slots = 10,
    ipls = {},
    entitySets = {},
    options = {},
  },

  -------------------------------------------------------------------------------------
  -- Import/Export (build 944+)
  -------------------------------------------------------------------------------------
  vehicle_warehouse = {
    label = 'Vehicle warehouse (Import/Export)',
    coords = vector4(994.5925, -3002.594, -39.64699, 0.0),
    interiorCoords = vector3(994.5925, -3002.594, -39.64699),
    slots = 40,
    ipls = { 'imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_' },
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

  -- CEO office garages: three levels per office building.
  ceo_arcadius_garage_1 = ceoGarage('Arcadius Business Center garage (level 1)', 'imp_dt1_02_cargarage_a', 1, -191.0133, -579.1428, 135.0),
  ceo_arcadius_garage_2 = ceoGarage('Arcadius Business Center garage (level 2)', 'imp_dt1_02_cargarage_b', 2, -117.4989, -568.1132, 135.0),
  ceo_arcadius_garage_3 = ceoGarage('Arcadius Business Center garage (level 3)', 'imp_dt1_02_cargarage_c', 3, -136.078, -630.1852, 135.0),

  ceo_maze_bank_garage_1 = ceoGarage('Maze Bank Tower garage (level 1)', 'imp_dt1_11_cargarage_a', 1, -84.2193, -823.0851, 221.0),
  ceo_maze_bank_garage_2 = ceoGarage('Maze Bank Tower garage (level 2)', 'imp_dt1_11_cargarage_b', 2, -69.8627, -824.7498, 221.0),
  ceo_maze_bank_garage_3 = ceoGarage('Maze Bank Tower garage (level 3)', 'imp_dt1_11_cargarage_c', 3, -80.4318, -813.2536, 221.0),

  ceo_lom_bank_garage_1 = ceoGarage('Lom Bank garage (level 1)', 'imp_sm_13_cargarage_a', 1, -1581.112, -567.245, 85.5),
  ceo_lom_bank_garage_2 = ceoGarage('Lom Bank garage (level 2)', 'imp_sm_13_cargarage_b', 2, -1568.739, -562.0455, 85.5),
  ceo_lom_bank_garage_3 = ceoGarage('Lom Bank garage (level 3)', 'imp_sm_13_cargarage_c', 3, -1563.557, -574.4314, 85.5),

  ceo_maze_bank_west_garage_1 = ceoGarage('Maze Bank West garage (level 1)', 'imp_sm_15_cargarage_a', 1, -1388.84, -478.7402, 56.1),
  ceo_maze_bank_west_garage_2 = ceoGarage('Maze Bank West garage (level 2)', 'imp_sm_15_cargarage_b', 2, -1388.86, -478.7574, 48.1),
  ceo_maze_bank_west_garage_3 = ceoGarage('Maze Bank West garage (level 3)', 'imp_sm_15_cargarage_c', 3, -1374.682, -474.3586, 56.1),

  -------------------------------------------------------------------------------------
  -- Los Santos Tuners (build 2372+). Both interiors exist in the map files of that build;
  -- no extra IPL is needed for the rooms themselves.
  -------------------------------------------------------------------------------------
  tuner_car_meet = {
    label = 'LS Car Meet (Tuners)',
    coords = vector4(-2000.0, 1113.211, -25.36243, 0.0),
    interiorCoords = vector3(-2000.0, 1113.211, -25.36243),
    slots = 20,
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
    coords = vector4(-1350.0, 160.0, -100.0, 0.0),
    interiorCoords = vector3(-1350.0, 160.0, -100.0),
    slots = 4,
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
