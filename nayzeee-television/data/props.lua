--[[
    NAYZEEE TELEVISION — prop library
    ─────────────────────────────────────────────────────────────
    Every model here can be placed as a TV, used by admins as a
    permanent screen, or "claimed" when it already exists in an MLO.

    • Models that are not in the game build your server runs are
      detected at runtime and hidden automatically (admin menu →
      Library → Verify shows which ones).
    • The picture is auto-fitted to the model's front face. If a
      prop needs fine tuning, use admin menu → Calibrator. Your
      tuning is saved to data/calibration.json and shared with all
      players instantly — no restart.
    • To add a CUSTOM streamed TV prop: stream the .ydr/.ytyp from
      any resource, then add a line to Props.Custom below.

    Entry: { model, label, category, [overrides] }
    overrides: range, aspect, hd, style, rt (render target), tilt, screen = { x, y, z, w, h, face, tilt }
]]

Props = {}

-- Defaults per category. range = metres the audio carries.
Props.Categories = {
    flat      = { label = 'Flat Screens',    range = 20.0, aspect = 16/9, style = 'flat'    },
    crt       = { label = 'Retro CRT',       range = 16.0, aspect = 4/3,  style = 'crt'     },
    monitor   = { label = 'Monitors',        range = 10.0, aspect = 16/9, style = 'monitor' },
    laptop    = { label = 'Laptops',         range = 8.0,  aspect = 16/10,style = 'laptop', tilt = -14.0 },
    tablet    = { label = 'Tablets',         range = 6.0,  aspect = 4/3,  style = 'tablet'  },
    cinema    = { label = 'Cinema & Walls',  range = 100.0,aspect = 16/9, style = 'cinema', hd = true },
    facility  = { label = 'Facility Walls',  range = 35.0, aspect = 16/9, style = 'flat'    },
    arcade    = { label = 'Arcade & Casino', range = 9.0,  aspect = 3/4,  style = 'arcade', tilt = -16.0 },
    signage   = { label = 'Signage',         range = 60.0, aspect = 16/9, style = 'cinema', hd = true },
    custom    = { label = 'Custom Props',    range = 20.0, aspect = 16/9, style = 'flat'    },
}

Props.List = {
    -- ═════════ FLAT SCREENS ═════════
    { 'prop_tv_flat_01',            'Flat Screen TV',          'flat', { rt = 'tvscreen' } },
    { 'prop_tv_flat_01_screen',     'Flat Screen (panel)',     'flat', { rt = 'tvscreen' } },
    { 'prop_tv_flat_02',            'Flat Screen TV II',       'flat', { rt = 'tvscreen' } },
    { 'prop_tv_flat_02b',           'Flat Screen TV II b',     'flat', { rt = 'tvscreen' } },
    { 'prop_tv_flat_03',            'Compact Flat TV',         'flat', { range = 14.0, rt = 'tvscreen' } },
    { 'prop_tv_flat_03b',           'Compact Flat TV b',       'flat', { range = 14.0, rt = 'tvscreen' } },
    { 'prop_tv_flat_michael',       'Large Flat TV',           'flat', { range = 26.0, rt = 'tvscreen' } },
    { 'prop_trev_tv_01',            'Trailer Flat TV',         'flat', { rt = 'tvscreen' } },
    { 'des_tvsmash_start',          'Living Room TV',          'flat', { rt = 'tvscreen' } },
    { 'ex_prop_ex_tv_flat_01',      'Executive Flat TV',       'flat', { range = 24.0, rt = 'ex_tvscreen' } },
    { 'sm_prop_smug_tv_flat_01',    'Hangar Flat TV',          'flat', { rt = 'tv_flat_01' } },
    { 'xm_prop_x17_tv_flat_01',     'Facility Flat TV',        'flat', { rt = 'tv_flat_01' } },
    { 'xm_prop_x17_tv_flat_02',     'Facility Flat TV II',     'flat', { rt = 'tv_flat_02' } },
    { 'xm_prop_x17_tv_ceiling_01',  'Ceiling TV',              'flat' },
    { 'ch_prop_ch_tv_rt_01a',       'Arcade Lounge TV',        'flat' },
    { 'vw_prop_vw_tv_rt_01a',       'Penthouse TV',            'flat', { range = 24.0 } },
    { 'sf_prop_sf_tv_flat_scr_01a', 'Studio Flat Screen',      'flat' },
    { 'h4_prop_h4_tv_screen_01a',   'Island Lounge Screen',    'flat' },
    { 'gr_prop_gr_trailer_tv',      'Bunker Trailer TV',       'flat' },
    { 'gr_prop_gr_trailer_tv_02',   'Bunker Trailer TV II',    'flat' },
    { 'apa_mp_h_str_avunitm_01',    'AV Unit — Medium',        'flat' },
    { 'apa_mp_h_str_avunitm_03',    'AV Unit — Medium III',    'flat' },
    { 'apa_mp_h_str_avunitl_01_b',  'AV Unit — Large',         'flat', { range = 24.0 } },
    { 'apa_mp_h_str_avunitl_04',    'AV Unit — Large IV',      'flat', { range = 24.0 } },
    { 'apa_mp_h_str_avunits_01',    'AV Unit — Small',         'flat' },
    { 'apa_mp_h_str_avunits_04',    'AV Unit — Small IV',      'flat' },
    { 'hei_heist_str_avunitl_03',   'Heist AV Unit — Large',   'flat', { range = 24.0 } },
    { 'hei_heist_str_avunits_01',   'Heist AV Unit — Small',   'flat' },
    { 'hei_heist_str_avunitl_01',   'Heist AV Unit — Large A', 'flat', { range = 24.0 } },
    { 'prop_cs_tv_stand',           'TV on Stand',             'flat', { rt = 'tvscreen' } },

    -- ═════════ RETRO CRT ═════════
    { 'prop_tv_01',                 'Old CRT TV',              'crt' },
    { 'prop_tv_02',                 'Portable CRT',            'crt', { range = 10.0 } },
    { 'prop_tv_03',                 'Classic CRT TV',          'crt', { rt = 'tvscreen' } },
    { 'prop_tv_03_overlay',         'Classic CRT (overlay)',   'crt', { rt = 'tvscreen' } },
    { 'prop_tv_04',                 'Wood Cabinet CRT',        'crt' },
    { 'prop_tv_05',                 'Grey CRT',                'crt' },
    { 'prop_tv_06',                 'Box CRT',                 'crt' },
    { 'prop_tv_07',                 'Bedside CRT',             'crt' },
    { 'prop_tv_test',               'Test Pattern CRT',        'crt' },
    { 'prop_tv_cabinet_03',         'CRT Cabinet III',         'crt' },
    { 'prop_tv_cabinet_04',         'CRT Cabinet IV',          'crt' },
    { 'prop_tv_cabinet_05',         'CRT Cabinet V',           'crt' },
    { 'prop_cctv_mon_02',           'CCTV Monitor',            'crt', { range = 8.0 } },

    -- ═════════ MONITORS ═════════
    { 'prop_monitor_01a',           'Desktop Monitor',         'monitor' },
    { 'prop_monitor_01b',           'Desktop Monitor b',       'monitor' },
    { 'prop_monitor_01c',           'Desktop Monitor c',       'monitor' },
    { 'prop_monitor_01d',           'Desktop Monitor d',       'monitor' },
    { 'prop_monitor_02',            'Office Monitor',          'monitor' },
    { 'prop_monitor_03b',           'Slim Monitor',            'monitor' },
    { 'prop_monitor_w_large',       'Wide Monitor',            'monitor', { range = 12.0 } },
    { 'prop_monitor_li',            'Lifeinvader Monitor',     'monitor' },
    { 'prop_ld_monitor_01',         'Display Monitor',         'monitor' },
    { 'prop_monitor_04a',           'Monitor Panel',           'monitor' },
    { 'prop_dyn_pc',                'Desktop PC',              'monitor', { aspect = 4/3 } },
    { 'prop_dyn_pc_02',             'Desktop PC II',           'monitor', { aspect = 4/3 } },
    { 'prop_pc_01a',                'Office PC',               'monitor', { aspect = 4/3 } },
    { 'prop_pc_02a',                'Office PC II',            'monitor', { aspect = 4/3 } },
    { 'prop_trailer_monitor_01',    'Trailer Monitor',         'monitor' },
    { 'hei_prop_hei_monitor_police_01','Police Monitor',       'monitor' },
    { 'ex_prop_monitor_01_ex',      'Executive Monitor',       'monitor' },
    { 'sm_prop_smug_monitor_01',    'Hangar Monitor',          'monitor' },
    { 'xm_prop_x17_computer_01',    'Facility Computer',       'monitor' },
    { 'xm_prop_x17_computer_02',    'Facility Computer II',    'monitor' },
    { 'gr_prop_gr_trailer_monitor_01','Bunker Monitor',        'monitor' },
    { 'gr_prop_gr_trailer_monitor_02','Bunker Monitor II',     'monitor' },
    { 'gr_prop_gr_trailer_monitor_03','Bunker Monitor III',    'monitor' },
    { 'ba_prop_battle_club_computer_01','Club Computer',       'monitor' },
    { 'ba_prop_battle_club_computer_02','Club Computer II',    'monitor' },
    { 'ch_prop_ch_monitor_01a',     'Arcade Office Monitor',   'monitor' },

    -- ═════════ LAPTOPS ═════════
    { 'prop_laptop_01a',            'Laptop',                  'laptop' },
    { 'prop_laptop_jimmy',          'Gaming Laptop',           'laptop' },
    { 'prop_laptop_lester',         'Hacker Laptop',           'laptop' },
    { 'prop_laptop_lester2',        'Hacker Laptop II',        'laptop' },
    { 'p_laptop_02_s',              'Slim Laptop',             'laptop' },
    { 'hei_prop_hst_laptop',        'Heist Laptop',            'laptop' },
    { 'bkr_prop_clubhouse_laptop_01a','Clubhouse Laptop',      'laptop' },
    { 'bkr_prop_clubhouse_laptop_01b','Clubhouse Laptop II',   'laptop' },
    { 'ex_prop_ex_laptop_01a',      'Executive Laptop',        'laptop' },
    { 'gr_prop_gr_laptop_01a',      'Bunker Laptop',           'laptop' },
    { 'gr_prop_gr_laptop_01b',      'Bunker Laptop II',        'laptop' },
    { 'gr_prop_gr_laptop_01c',      'Bunker Laptop III',       'laptop' },
    { 'ba_prop_club_laptop_dj',     'DJ Laptop',               'laptop' },
    { 'ba_prop_club_laptop_dj_02',  'DJ Laptop II',            'laptop' },
    { 'xm_prop_x17_laptop_avon',    'Facility Laptop',         'laptop' },
    { 'xm_prop_x17_laptop_lester_01','Facility Laptop II',     'laptop' },
    { 'xm_prop_x17_laptop_mrsr',    'Facility Laptop III',     'laptop' },
    { 'h4_prop_h4_laptop_01a',      'Island Laptop',           'laptop' },
    { 'imp_prop_impexp_laptop_01a', 'Import Laptop',           'laptop' },
    { 'sf_prop_sf_laptop_01a',      'Studio Laptop',           'laptop' },
    { 'tr_prop_tr_laptop_jimmy',    'Tuner Laptop',            'laptop' },
    { 'ch_prop_laptop_01a',         'Arcade Laptop',           'laptop' },

    -- ═════════ TABLETS ═════════
    { 'prop_cs_tablet',             'Tablet',                  'tablet' },
    { 'prop_cs_tablet_02',          'Tablet II',               'tablet' },
    { 'hei_prop_dlc_tablet',        'Heist Tablet',            'tablet' },
    { 'ch_prop_ch_tablet_01a',      'Arcade Tablet',           'tablet' },

    -- ═════════ CINEMA, PROJECTORS & BIG WALLS ═════════
    { 'v_ilev_cin_screen',          'Cinema Screen',           'cinema', { aspect = 2.39, rt = 'cinscreen' } },
    { 'v_ilev_mm_screen',           'Projector Screen',        'cinema', { range = 30.0 } },
    { 'v_ilev_mm_screen2',          'Projector Screen II',     'cinema', { range = 30.0 } },
    { 'v_ilev_lest_bigscreen',      'Big Screen',              'cinema', { range = 35.0 } },
    { 'prop_huge_display_01',       'Huge Display',            'cinema', { range = 80.0, rt = 'big_disp' } },
    { 'prop_huge_display_02',       'Huge Display II',         'cinema', { range = 80.0, rt = 'big_disp' } },
    { 'xs_prop_arena_bigscreen_01', 'Arena Big Screen',        'cinema', { range = 140.0 } },
    { 'xs_prop_arena_screen_tv_01', 'Arena Screen TV',         'cinema', { range = 60.0 } },
    { 'sf_prop_sf_tv_studio_01a',   'Studio Wall',             'cinema', { range = 40.0 } },
    { 'ba_prop_club_screens_01',    'Club Screens',            'cinema', { range = 60.0 } },
    { 'ba_prop_club_screens_02',    'Club Screens II',         'cinema', { range = 60.0 } },
    { 'ba_prop_battle_club_screen_01','Club Screen',           'cinema', { range = 50.0 } },
    { 'ba_prop_battle_club_screen_02','Club Screen II',        'cinema', { range = 50.0 } },
    { 'ba_prop_battle_club_screen_03','Club Screen III',       'cinema', { range = 50.0 } },
    { 'h4_prop_club_screens_01',    'Island Club Screens',     'cinema', { range = 60.0 } },
    { 'vw_prop_vw_cinema_tv_01',    'Penthouse Cinema',        'cinema', { range = 40.0 } },
    { 'xm_prop_x17_screens_02a',    'Command Screens',         'cinema', { range = 40.0 } },
    { 'xm_prop_x17_screens_02b',    'Command Screens II',      'cinema', { range = 40.0 } },
    { 'xm_prop_x17_tv_ceiling_scn_01','Ceiling Screen',        'cinema', { range = 30.0 } },
    { 'xm_prop_x17_tv_ceiling_scn_02','Ceiling Screen II',     'cinema', { range = 30.0 } },

    -- ═════════ SIGNAGE ═════════
    { 'prop_x17dlc_monitor_wall_01a',    'Monitor Wall',          'signage', { rt = 'prop_x17dlc_monitor_wall_01a' } },
    { 'xm_prop_x17dlc_monitor_wall_01a', 'Facility Monitor Wall', 'signage', { rt = 'prop_x17dlc_monitor_wall_01a' } },

    -- ═════════ FACILITY WALL PANELS ═════════
    { 'xm_prop_x17_tv_scrn_01',     'Facility Panel 01',       'facility' },
    { 'xm_prop_x17_tv_scrn_02',     'Facility Panel 02',       'facility' },
    { 'xm_prop_x17_tv_scrn_03',     'Facility Panel 03',       'facility' },
    { 'xm_prop_x17_tv_scrn_04',     'Facility Panel 04',       'facility' },
    { 'xm_prop_x17_tv_scrn_05',     'Facility Panel 05',       'facility' },
    { 'xm_prop_x17_tv_scrn_06',     'Facility Panel 06',       'facility' },
    { 'xm_prop_x17_tv_scrn_07',     'Facility Panel 07',       'facility' },
    { 'xm_prop_x17_tv_scrn_08',     'Facility Panel 08',       'facility' },
    { 'xm_prop_x17_tv_scrn_09',     'Facility Panel 09',       'facility' },
    { 'xm_prop_x17_tv_scrn_10',     'Facility Panel 10',       'facility' },
    { 'xm_prop_x17_tv_scrn_11',     'Facility Panel 11',       'facility' },
    { 'xm_prop_x17_tv_scrn_12',     'Facility Panel 12',       'facility' },
    { 'xm_prop_x17_tv_scrn_13',     'Facility Panel 13',       'facility' },
    { 'xm_prop_x17_tv_scrn_14',     'Facility Panel 14',       'facility' },
    { 'xm_prop_x17_tv_scrn_15',     'Facility Panel 15',       'facility' },
    { 'xm_prop_x17_tv_scrn_16',     'Facility Panel 16',       'facility' },
    { 'xm_prop_x17_tv_scrn_17',     'Facility Panel 17',       'facility' },
    { 'xm_prop_x17_tv_scrn_18',     'Facility Panel 18',       'facility' },
    { 'xm_prop_x17_tv_scrn_19',     'Facility Panel 19',       'facility' },

    -- ═════════ ARCADE CABINETS ═════════
    { 'prop_arcade_01',             'Arcade Cabinet',          'arcade' },
    { 'prop_arcade_02',             'Arcade Cabinet II',       'arcade' },
    { 'ch_prop_arcade_degenatron_01a','Retro Cabinet — Degen', 'arcade' },
    { 'ch_prop_arcade_invade_01a',  'Cabinet — Invade',        'arcade' },
    { 'ch_prop_arcade_monkey_01a',  'Cabinet — Monkey',        'arcade' },
    { 'ch_prop_arcade_penetrator_01a','Cabinet — Penetrator',  'arcade' },
    { 'ch_prop_arcade_space_01a',   'Cabinet — Space',         'arcade' },
    { 'ch_prop_arcade_street_01a',  'Cabinet — Street',        'arcade' },
    { 'ch_prop_arcade_street_01b',  'Cabinet — Street b',      'arcade' },
    { 'ch_prop_arcade_street_01c',  'Cabinet — Street c',      'arcade' },
    { 'ch_prop_arcade_street_01d',  'Cabinet — Street d',      'arcade' },
    { 'ch_prop_arcade_street_02b',  'Cabinet — Street e',      'arcade' },
    { 'ch_prop_arcade_wizard_01a',  'Cabinet — Wizard',        'arcade' },
    { 'ch_prop_arcade_race_01a',    'Racing Cabinet',          'arcade', { aspect = 4/3 } },
    { 'ch_prop_arcade_race_01b',    'Racing Cabinet b',        'arcade', { aspect = 4/3 } },
    { 'ch_prop_arcade_race_02a',    'Racing Cabinet II',       'arcade', { aspect = 4/3 } },
    { 'ch_prop_arcade_gun_01a',     'Light Gun Cabinet',       'arcade', { aspect = 4/3 } },
    { 'ch_prop_arcade_love_01a',    'Love Meter Cabinet',      'arcade' },
    { 'ch_prop_arcade_fortune_01a', 'Fortune Cabinet',         'arcade' },

    -- ═════════ CASINO ═════════
    { 'vw_prop_casino_slot_01a',    'Slot Machine 01',         'arcade' },
    { 'vw_prop_casino_slot_02a',    'Slot Machine 02',         'arcade' },
    { 'vw_prop_casino_slot_03a',    'Slot Machine 03',         'arcade' },
    { 'vw_prop_casino_slot_04a',    'Slot Machine 04',         'arcade' },
    { 'vw_prop_casino_slot_05a',    'Slot Machine 05',         'arcade' },
    { 'vw_prop_casino_slot_06a',    'Slot Machine 06',         'arcade' },
    { 'vw_prop_casino_slot_07a',    'Slot Machine 07',         'arcade' },
    { 'vw_prop_casino_slot_08a',    'Slot Machine 08',         'arcade' },
}

-- Your own streamed props go here (same format).
Props.Custom = {
    -- { 'my_custom_tv_85in', '85" OLED Wall TV', 'custom', { range = 28.0, screen = { x = 0.0, y = -0.04, z = 1.1, w = 1.88, h = 1.06, face = '-y' } } },
}

-- ─── build lookup tables (do not edit) ─────────────────────────
Props.ByModel = {}
Props.Ordered = {}

local function add(entry)
    local model, label, cat, ov = entry[1], entry[2], entry[3], entry[4] or {}
    local base = Props.Categories[cat] or Props.Categories.flat
    local def = {
        model  = model,
        hash   = GetHashKey(model),
        label  = label,
        cat    = cat,
        range  = ov.range  or base.range,
        aspect = ov.aspect or base.aspect,
        style  = ov.style  or base.style,
        hd     = ov.hd == nil and (base.hd or false) or ov.hd,
        screen = ov.screen,
        rt     = ov.rt,                       -- built-in render target (pixel-perfect, see Config.Render.Prefer)
        tilt   = ov.tilt or base.tilt,        -- screen pitch in degrees (laptops / arcade cabinets lean back)
    }
    Props.ByModel[model] = def
    Props.ByModel[def.hash] = def
    -- entity natives may hand back the unsigned form of a hash
    Props.ByModel[def.hash % 4294967296] = def
    Props.ByModel[def.hash >= 2147483648 and def.hash - 4294967296 or def.hash] = def
    Props.Ordered[#Props.Ordered + 1] = def
end

for _, e in ipairs(Props.List) do add(e) end
for _, e in ipairs(Props.Custom) do add(e) end

function Props.Get(modelOrHash)
    return Props.ByModel[modelOrHash]
end
