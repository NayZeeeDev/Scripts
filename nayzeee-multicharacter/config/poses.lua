-- ██████╗  ██████╗ ███████╗███████╗███████╗
-- ██╔══██╗██╔═══██╗██╔════╝██╔════╝██╔════╝
-- ██████╔╝██║   ██║███████╗█████╗  ███████╗
-- ██╔═══╝ ██║   ██║╚════██║██╔══╝  ╚════██║
-- ██║     ╚██████╔╝███████║███████╗███████║
-- ╚═╝      ╚═════╝ ╚══════╝╚══════╝╚══════╝

--[[
    SOLO POSES — picked per character in the lobby (Customize > Pose). Saved in the database.

    anim      { dict, clip, flag }      flag 1 = loop full body, 49 = loop upper body only
    scenario  'WORLD_HUMAN_...'          alternative to anim (starts instantly, no walk-in)
    props     { { model, bone, pos = vec3, rot = vec3 } }   handheld props (bone ids: 28422 right hand, 60309 left hand)
    category  lifestyle | luxury | fashion | tactical  (UI filter)
    weapon    false = this pose hides the showcase weapon (props need free hands)

    Prop placements are tuned for the freemode peds; nudge pos / rot if a prop floats on your add-on peds.
]]

Config.Poses = {
    { id = 'relaxed',   label = 'Relaxed',        icon = 'user',        category = 'lifestyle',
      anim = { dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss', flag = 1 } },

    { id = 'crossed',   label = 'Arms Crossed',   icon = 'shield',      category = 'lifestyle',
      anim = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', clip = 'idle_a', flag = 1 } },

    { id = 'model',     label = 'Model Pose',     icon = 'sparkles',    category = 'fashion',
      anim = { dict = 'mini@strip_club@idles@bouncer@base', clip = 'base', flag = 1 } },

    { id = 'model2',    label = 'Editorial',      icon = 'camera',      category = 'fashion',
      anim = { dict = 'anim@amb@nightclub@peds@', clip = 'rcmme_amanda1_stand_loop_cop', flag = 1 } },

    { id = 'lean_car',  label = 'Lean on Car',    icon = 'car',         category = 'luxury',
      anim = { dict = 'amb@world_human_leaning@male@wall@back@foot_up@idle_a', clip = 'idle_a', flag = 1 } },

    { id = 'lean_rail', label = 'Lean on Rail',   icon = 'waves',       category = 'lifestyle',
      anim = { dict = 'amb@prop_human_bum_shopping_cart@male@base', clip = 'base', flag = 1 } },

    { id = 'phone',     label = 'Checking Phone', icon = 'smartphone',  category = 'lifestyle', weapon = false,
      anim = { dict = 'cellphone@', clip = 'cellphone_text_read_base', flag = 49 },
      props = { { model = 'prop_npc_phone_02', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) } } },

    { id = 'coffee',    label = 'Iced Coffee',    icon = 'coffee',      category = 'lifestyle', weapon = false,
      anim = { dict = 'amb@world_human_drinking@coffee@male@idle_a', clip = 'idle_c', flag = 49 },
      props = { { model = 'p_amb_coffeecup_01', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) } } },

    { id = 'shopping',  label = 'Shopping Bags',  icon = 'shopping-bag', category = 'luxury', weapon = false,
      anim = { dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 49 },
      props = {
          { model = 'vw_prop_casino_shopping_bag_01a', bone = 28422, pos = vec3(0.24, 0.03, -0.04), rot = vec3(0.0, -90.0, 10.0) },
          { model = 'vw_prop_casino_shopping_bag_01a', bone = 60309, pos = vec3(0.24, 0.03, 0.04), rot = vec3(0.0, -90.0, -10.0) },
      } },

    { id = 'smoke',     label = 'Smoking',        icon = 'flame',       category = 'lifestyle', weapon = false,
      scenario = 'WORLD_HUMAN_SMOKING' },

    { id = 'tactical',  label = 'Tactical Stance', icon = 'crosshair',  category = 'tactical',
      anim = { dict = 'anim@heists@heist_corona@team_idles@male_a', clip = 'idle', flag = 1 } },

    { id = 'guard',     label = 'On Guard',       icon = 'shield-check', category = 'tactical',
      anim = { dict = 'anim@amb@nightclub@peds@', clip = 'rcmme_amanda1_stand_loop_cop', flag = 1 } },

    { id = 'flex',      label = 'Flex',           icon = 'dumbbell',    category = 'lifestyle', weapon = false,
      scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },

    { id = 'sit',       label = 'Sit Down',       icon = 'armchair',    category = 'lifestyle', weapon = false,
      anim = { dict = 'amb@world_human_picnic@male@base', clip = 'base', flag = 1 } },
}

--  ██████╗ ██████╗ ██╗   ██╗██████╗ ██╗     ███████╗███████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██║     ██╔════╝██╔════╝
-- ██║     ██║   ██║██║   ██║██████╔╝██║     █████╗  ███████╗
-- ██║     ██║   ██║██║   ██║██╔═══╝ ██║     ██╔══╝  ╚════██║
-- ╚██████╗╚██████╔╝╚██████╔╝██║     ███████╗███████╗███████║
--  ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚══════╝╚══════╝╚══════╝

--[[
    COUPLE ANIMATIONS — available when a linked Partner stands in slot 2. Picked from the Couple Poses menu.

    pedA   the selected character (stays on the main mark)
    pedB   the partner. offset = vec3(right, forward, up) from pedA, rotation = vec3(0, 0, heading delta)
           attach = true glues pedB to pedA (AttachEntityToEntity) for tight embraces that must never drift
    Both peds are unarmed and their props are cleared while a couple pose plays.

    Drop your own paired animations in the empty template at the bottom.
]]

Config.CoupleAnimations = {
    { id = 'embrace',      label = 'Embrace',        icon = 'heart',
      pedA = { dict = 'misscarsteal2chad_goodbye', clip = 'chad_armsaround_chad', flag = 1 },
      pedB = { dict = 'misscarsteal2chad_goodbye', clip = 'chad_armsaround_girl', flag = 1,
               offset = vec3(0.05, 0.55, 0.0), rotation = vec3(0.0, 0.0, 180.0), attach = true } },

    { id = 'kiss',         label = 'Kiss',           icon = 'heart-handshake',
      pedA = { dict = 'mp_ped_interaction', clip = 'kisses_guy_a', flag = 1 },
      pedB = { dict = 'mp_ped_interaction', clip = 'kisses_guy_b', flag = 1,
               offset = vec3(0.0, 1.0, 0.0), rotation = vec3(0.0, 0.0, 180.0), attach = true } },

    { id = 'side_by_side', label = 'Side by Side',   icon = 'users',
      pedA = { dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss', flag = 1 },
      pedB = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', clip = 'idle_a', flag = 1,
               offset = vec3(0.62, -0.05, 0.0), rotation = vec3(0.0, 0.0, -6.0) } },

    { id = 'back_to_back', label = 'Back to Back',   icon = 'repeat',
      pedA = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', clip = 'idle_a', flag = 1 },
      pedB = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', clip = 'idle_a', flag = 1,
               offset = vec3(0.12, -0.42, 0.0), rotation = vec3(0.0, 0.0, 165.0) } },

    { id = 'lean_together', label = 'Lean Together', icon = 'car',
      pedA = { dict = 'amb@world_human_leaning@male@wall@back@foot_up@idle_a', clip = 'idle_a', flag = 1 },
      pedB = { dict = 'amb@world_human_leaning@female@wall@back@hand_up@idle_a', clip = 'idle_a', flag = 1,
               offset = vec3(0.72, 0.0, 0.0), rotation = vec3(0.0, 0.0, 0.0) } },

    { id = 'forehead',     label = 'Forehead Lean',  icon = 'smile',
      pedA = { dict = 'misscarsteal2chad_goodbye', clip = 'chad_armsaround_chad', flag = 1 },
      pedB = { dict = 'misscarsteal2chad_goodbye', clip = 'chad_armsaround_girl', flag = 1,
               offset = vec3(0.02, 0.48, 0.0), rotation = vec3(0.0, 0.0, 180.0), attach = true } },

    -- Template — fill in and uncomment:
    -- { id = 'holding_hands', label = 'Holding Hands', icon = 'hand',
    --   pedA = { dict = 'your@dict', clip = 'your_clip_a', flag = 1 },
    --   pedB = { dict = 'your@dict', clip = 'your_clip_b', flag = 1, offset = vec3(0.55, 0.0, 0.0), rotation = vec3(0.0, 0.0, 0.0) } },
}

-- Played by partners / squad when the main character leaves (departure 'goodbye' step)
Config.GoodbyeAnim = { dict = 'friends@frj@ig_1', clip = 'wave_a', flag = 48 }
