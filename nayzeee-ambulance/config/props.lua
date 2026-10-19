--[[
    NAYZEEE AMBULANCE - Prop models

    Every custom prop is streamed from stream/ (built by tools/props). Swap any of
    them for your own model by changing the name here. 'fallback' models are native
    GTA props used when a custom model fails to load.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Props = {
    -- field resuscitation
    kitcase_closed   = 'nz_amb_kitcase_closed',   -- trauma kit case, closed (carried)
    kitcase_open     = 'nz_amb_kitcase_open',     -- open case with foam inserts
    monitor          = 'nz_amb_monitor',          -- portable patient monitor (screen is a DUI/NUI overlay)
    defib            = 'nz_amb_defib',            -- monitor / defibrillator unit
    binder_flat      = 'nz_amb_binder_flat',      -- pelvic binder laid flat on the ground
    binder_worn      = 'nz_amb_binder_worn',      -- binder wrapped around the pelvis (attach to SKEL_Pelvis)
    iodrill          = 'nz_amb_iodrill',          -- intraosseous drill
    ivstand          = 'nz_amb_ivstand',          -- tripod IV stand
    ivbag_saline     = 'nz_amb_ivbag_saline',
    bloodbag_0       = 'nz_amb_bloodbag_0',       -- blood bag fill states (donation / transfusion)
    bloodbag_25      = 'nz_amb_bloodbag_25',
    bloodbag_50      = 'nz_amb_bloodbag_50',
    bloodbag_75      = 'nz_amb_bloodbag_75',
    bloodbag_100     = 'nz_amb_bloodbag_100',
    pressure_infuser = 'nz_amb_infuser',          -- pressure bag + gauge
    sharps           = 'nz_amb_sharps',           -- sharps bin
    tourniquet_worn  = 'nz_amb_tourniquet',       -- tourniquet strap (attach to limb bone)

    -- hand-held
    pager            = 'nz_amb_pager',
    syringe          = 'nz_amb_syringe',
    stethoscope      = 'nz_amb_stethoscope',
    laryngoscope     = 'nz_amb_laryngoscope',
    us_probe         = 'nz_amb_us_probe',
    bvm              = 'nz_amb_bvm',              -- bag-valve mask (face mask + bag)
    suction          = 'nz_amb_suction',          -- portable suction unit with canister
    ett              = 'nz_amb_ett',              -- endotracheal tube with holder

    -- orthopedic
    crutch           = 'nz_amb_crutch',
    splint_leg       = 'nz_amb_splint_leg',
    splint_arm       = 'nz_amb_splint_arm',
    collar           = 'nz_amb_collar',
    oxygen_mask      = 'nz_amb_o2mask',           -- worn non-rebreather mask + reservoir bag (attach to SKEL_Head)
    foil_blanket     = 'nz_amb_foil',             -- worn rescue blanket wrapped around the torso (attach to SKEL_Spine3)

    -- transport
    stretcher        = 'nz_amb_stretcher',
    stretcher_low    = 'nz_amb_stretcher_low',    -- the same cot lowered (scissor lift folded), swapped in while lowered
    medbag           = 'nz_amb_medbag_red',       -- medic bag: nz_amb_medbag_red | _orange | _green | _magenta
    wheelchair       = 'prop_wheelchair_01',      -- native
    bodybag          = 'xm_prop_body_bag',        -- native (Doomsday DLC)

    -- hospital equipment (placed with the in-game builder)
    xray_table       = 'nz_amb_xray_table',       -- table + floor rail
    xray_tube        = 'nz_amb_xray_tube',        -- tube stand that slides along the rail to the imaged body part
    lightbox         = 'nz_amb_lightbox',         -- film viewer on a stand
    us_cart          = 'nz_amb_us_cart',          -- ultrasound cart
    injector         = 'nz_amb_injector',         -- contrast power injector on a tray
    injector_plunger = 'nz_amb_injector_plunger', -- moving syringe plunger + ram (always spawned with the injector)
    contrast_button  = 'nz_amb_contrast_button',  -- pedestal with the big red button
    angio_monitor    = 'nz_amb_angio_monitor',    -- boom-mounted fluoroscopy monitor
    donation_chair   = 'nz_amb_donation_chair',
    blood_mixer      = 'nz_amb_blood_mixer',      -- collection scale / mixer
    tv_board         = 'nz_amb_tv_board',         -- waiting room screen (texture replaced by a DUI)
    surgery_tray     = 'nz_amb_surgery_tray',
    bay_shell        = 'nz_amb_bay_shell',        -- ambulance treatment bay interior
}

-- Texture dictionary + texture name that a DUI replaces at runtime
Config.PropScreens = {
    tv_board      = { txd = 'nz_amb_tv_board',      tex = 'nz_amb_screen' },
    monitor       = { txd = 'nz_amb_monitor',       tex = 'nz_amb_screen' },
    angio_monitor = { txd = 'nz_amb_angio_monitor', tex = 'nz_amb_screen' },
    us_cart       = { txd = 'nz_amb_us_cart',       tex = 'nz_amb_screen' },
    defib         = { txd = 'nz_amb_defib',         tex = 'nz_amb_screen' },
    pager         = { txd = 'nz_amb_pager',         tex = 'nz_amb_screen' },
    lightbox      = { txd = 'nz_amb_lightbox',      tex = 'nz_amb_screen' },   -- the film being read
    blood_mixer   = { txd = 'nz_amb_blood_mixer',   tex = 'nz_amb_screen' },   -- live mL counter
    bay_shell     = { txd = 'nz_amb_bay_shell',     tex = 'nz_amb_screen' },   -- treatment bay wall monitor
}

-- Native models used if a custom one is missing
Config.PropFallbacks = {
    kitcase_closed = 'xm_prop_x17_bag_med_01a',
    kitcase_open   = 'xm_prop_x17_bag_med_01a',
    medbag         = 'xm_prop_x17_bag_med_01a',
    monitor        = 'prop_laptop_01a',
    defib          = 'prop_ld_case_01',
    ivstand        = 'v_med_cor_emblmtable',
    stretcher      = 'v_med_emptybed',
    stretcher_low  = 'v_med_emptybed',
    tv_board       = 'prop_tv_flat_01',
    syringe        = 'prop_syringe_01',
    pager          = 'prop_cs_phone_01',
    crutch         = 'prop_cs_walking_stick',
    bvm            = 'prop_cs_mask',
    suction        = 'prop_ld_case_01',
    xray_table     = 'v_med_emptybed',
    donation_chair = 'v_med_emptybed',
    us_cart        = 'prop_laptop_01a',
    angio_monitor  = 'prop_tv_flat_01',
    lightbox       = 'prop_tv_flat_01',
    surgery_tray   = 'v_med_cor_emblmtable',
    injector       = 'v_med_cor_emblmtable',
}
