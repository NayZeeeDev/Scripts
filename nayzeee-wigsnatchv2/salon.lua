-- ███████╗ █████╗ ██╗      ██████╗ ███╗   ██╗
-- ██╔════╝██╔══██╗██║     ██╔═══██╗████╗  ██║
-- ███████╗███████║██║     ██║   ██║██╔██╗ ██║
-- ╚════██║██╔══██║██║     ██║   ██║██║╚██╗██║
-- ███████║██║  ██║███████╗╚██████╔╝██║ ╚████║
-- ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
--
-- Doing hair: braids, cornrows, twists, locs, sew-ins, step by step in first person.
-- The stylist picks a style from the Style Book, the client accepts (and pays, if there's a price),
-- sits down, and every step of the style is played out on their head: parting with a rat-tail comb,
-- gel, cornrows stitch by stitch, braiding, feeding in hair, twisting, sewing wefts, spraying, irons.
-- When it's done the client gets the style for real, on their own ped, for everyone to see.
--
-- HOW THE STYLES SHOW IN PERSON
-- Every style is one of your hairstyles (hand-picked from your clothing packs, or base game), per model:
-- /wigstudio > pick the hairstyle > "Salon look" > pick the style. Box braids from your braid pack, a sew-in
-- from a long body wave, and so on. A style with no look for the client's model can't be started.
-- While the style is done, that hairstyle goes on for real, on the client's head, piece by piece: hairkit
-- (the 3D wigs tool) cuts it into slices (nape first, crown last) when you link it, and every row sewn /
-- braid finished puts the next slice on. At the end the slices make way for the hairstyle itself.
-- A sew-in starts with the braid down: the client's hair goes to cornrows (Cornrows below), the mesh wig
-- cap goes over them, and the wefts go on row by row.

Config.Salon = {
    Enabled        = true,
    Label          = 'Do Hair',
    Icon           = 'fa-solid fa-wand-magic-sparkles',
    Range          = 1.8,
    RequestTimeout = 30,
    MaxMinutes     = 25,            -- A session ends on its own after this long
    MinTime        = 0.6,           -- Anti-cheat: a move can't be done faster than this share of its normal time

    -- What the client pays the stylist (the stylist sets the price in the Style Book, 0 = free).
    -- The money is held when the client says yes, and goes to the stylist when the style is done.
    Payment = { Account = 'cash', MaxPrice = 5000 },

    -- How long a style lasts. days in each style below x DayMinutes, scaled by quality (50% at 0, 100% at 100).
    -- 1440 = real days. Set 60 to make a "day" an hour. false = styles stay until taken down / cut / snatched.
    DayMinutes = 1440,

    -- Chairs the client sits in (the closest one in ChairRange). Without one they stand.
    ChairRange = 2.2,
    SitScenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER',
    Chairs = {
        [`v_ilev_hd_chair`]       = { z = 0.5, h = 180.0 },   -- barber shop chairs
        [`v_serv_bs_barbchair`]   = { z = 0.5, h = 180.0 },
        [`v_serv_bs_barbchair2`]  = { z = 0.5, h = 180.0 },
        [`v_serv_bs_barbchair3`]  = { z = 0.5, h = 180.0 },
        [`v_serv_bs_barbchair5`]  = { z = 0.5, h = 180.0 },
        [`prop_chair_01a`]        = { z = 0.5, h = 180.0 },
        [`prop_chair_01b`]        = { z = 0.5, h = 180.0 },
        [`prop_chair_02`]         = { z = 0.5, h = 180.0 },
        [`prop_chair_04a`]        = { z = 0.5, h = 180.0 },
        [`prop_chair_08`]         = { z = 0.5, h = 180.0 },
        [`prop_off_chair_01`]     = { z = 0.5, h = 180.0 },
        [`prop_off_chair_04`]     = { z = 0.5, h = 180.0 },
        [`prop_bar_stool_01`]     = { z = 0.75, h = 180.0 },
        [`prop_stool_01`]         = { z = 0.6, h = 180.0 },
    },

    Camera = { Fov = 40.0, Dist = 0.82, MinDist = 0.42, MaxDist = 1.4, Height = 0.02 },
    -- the stylist, as others see them (if the first doesn't exist on your build, Fallback is used)
    Anim     = { dict = 'misshair_shop@hair_dressers', clip = 'keeper_idle_b' },
    Fallback = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' },
    SoundRange = 10.0,

    XP = { PerLevel = 12, Perfect = 20 },  -- XP for a style = its level x PerLevel x quality, + Perfect at 95%+

    -- Hair colours for extension hair (braiding hair, bundles). rgb is matched to the closest GTA hair colour.
    -- tip = an ombre: the root colour fades into the tip colour (GTA hair highlight).
    Shades = {
        { id = '1',    label = '1 Jet Black',     rgb = '#0b0b0c' },
        { id = '1B',   label = '1B Off Black',    rgb = '#1d1814' },
        { id = '2',    label = '2 Darkest Brown', rgb = '#2c1d15' },
        { id = '4',    label = '4 Medium Brown',  rgb = '#4b2d1e' },
        { id = '30',   label = '30 Auburn',       rgb = '#7c3117' },
        { id = '350',  label = '350 Copper',      rgb = '#b2531f' },
        { id = '27',   label = '27 Honey Blonde', rgb = '#c48e4f' },
        { id = '613',  label = '613 Platinum',    rgb = '#e7d6ad' },
        { id = '99J',  label = '99J Burgundy',    rgb = '#5b1727' },
        { id = 'grey', label = 'Silver Grey',     rgb = '#9b9b9b' },
        { id = 'red',  label = 'Red',             rgb = '#c0222c' },
        { id = 'pink', label = 'Pink',            rgb = '#e35b9f' },
        { id = 'purple', label = 'Purple',        rgb = '#6a3bb5' },
        { id = 'blue', label = 'Blue',            rgb = '#2f5fd6' },
        { id = 'T1B/27',  label = 'Ombre 1B / 27',  rgb = '#1d1814', tip = '27' },
        { id = 'T1B/30',  label = 'Ombre 1B / 30',  rgb = '#1d1814', tip = '30' },
        { id = 'T1B/613', label = 'Ombre 1B / 613', rgb = '#1d1814', tip = '613' },
        { id = 'T1B/pink', label = 'Ombre 1B / Pink', rgb = '#1d1814', tip = 'pink' },
        { id = 'T1B/blue', label = 'Ombre 1B / Blue', rgb = '#1d1814', tip = 'blue' },
    },

    -- Extension hair, sold at the Hair Supply. Every pack carries its colour, length and texture.
    Hair = {
        braid_hair   = { label = 'Braiding Hair',   kind = 'Pre-stretched Kanekalon', lengths = { 18, 24, 30, 36 }, shades = true },
        marley_hair  = { label = 'Marley Hair',     kind = 'Marley wrapping hair',    lengths = { 18, 24 },         shades = true },
        bulk_hair    = { label = 'Curly Bulk Hair', kind = 'Human bulk hair',         lengths = { 14, 18, 22 },     shades = true, textures = { 'Water Wave', 'Deep Wave' } },
        crochet_hair = { label = 'Crochet Hair',    kind = 'Crochet hair',            lengths = { 18, 24 },         shades = true, textures = { 'Water Wave', 'Bohemian Curl' } },
        locs_hair    = { label = 'Faux Locs',       kind = 'Pre-looped locs',         lengths = { 18, 24, 30 },     shades = true, textures = { 'Distressed', 'Butterfly' } },
        weave_bundle = { label = 'Weave Bundle',     kind = '100% human hair weft',    lengths = { 14, 18, 22, 26, 30 }, shades = true, textures = { 'Straight', 'Body Wave', 'Deep Wave', 'Kinky Curly' } },
    },

    -- Everything a step can have in hand. The nz_sty_* props ship in stream/: tools lie along the hand like the
    -- clippers, tubs / cans / bottles stand upright in it. Tweak pos / rot if your animations hold them differently. item = what the stylist needs (false = nothing),
    -- use = true: one is used up per style (products), false: a tool you keep.
    -- prop = what others see in the stylist's hand.
    Tools = {
        hands        = { label = 'Hands',            item = false },
        rat_comb     = { label = 'Rat-tail Comb',    item = 'rat_comb',     use = false, prop = { model = `nz_sty_comb`,   bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) } },
        paddle_brush = { label = 'Paddle Brush',     item = 'paddle_brush', use = false, prop = { model = `nz_sty_brush`,  bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) } },
        edge_brush   = { label = 'Edge Brush',       item = 'edge_brush',   use = false, prop = { model = `nz_sty_edge`,   bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) } },
        c_needle     = { label = 'C-Needle',         item = 'c_needle',     use = false, prop = { model = `nz_sty_needle`, bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) } },
        crochet_hook = { label = 'Crochet Hook',     item = 'crochet_hook', use = false, prop = { model = `nz_sty_hook`,   bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) } },
        flat_iron    = { label = 'Flat Iron',        item = 'flat_iron',    use = false, prop = { model = `nz_sty_iron`,   bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) }, sound = 'sizzle' },
        curl_wand    = { label = 'Curling Wand',     item = 'curl_wand',    use = false, prop = { model = `nz_sty_wand`,   bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) }, sound = 'sizzle' },
        blow_dryer   = { label = 'Blow Dryer',       item = 'blow_dryer',   use = false, prop = { model = `nz_sty_dryer`,  bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) }, sound = 'dryer' },
        shears       = { label = 'Styling Shears',   item = 'scissors',     use = false, prop = { model = `prop_cs_scissors`, bone = 57005, pos = vec3(0.12, 0.04, 0.01), rot = vec3(-80.0, 0.0, 0.0) }, sound = 'snip' },
        braid_gel    = { label = 'Braiding Gel',     item = 'braid_gel',    use = true,  prop = { model = `nz_sty_gel`,    bone = 28422, pos = vec3(0.0, 0.0, -0.03), rot = vec3(0.0, 0.0, 0.0) } },
        edge_control = { label = 'Edge Control',     item = 'edge_control', use = true,  prop = { model = `nz_sty_tin`,    bone = 28422, pos = vec3(0.0, 0.0, -0.03), rot = vec3(0.0, 0.0, 0.0) } },
        mousse       = { label = 'Foam Mousse',      item = 'mousse',       use = true,  prop = { model = `nz_sty_mousse`, bone = 28422, pos = vec3(0.0, 0.0, -0.03), rot = vec3(0.0, 0.0, 0.0) }, sound = 'spray' },
        heat_protect = { label = 'Heat Protectant',  item = 'heat_protect', use = true,  prop = { model = `nz_sty_spray`,  bone = 28422, pos = vec3(0.0, 0.0, -0.03), rot = vec3(0.0, 0.0, 0.0) }, sound = 'spray' },
        shine_spray  = { label = 'Shine Spray',      item = 'shine_spray',  use = true,  prop = { model = `nz_sty_spray`,  bone = 28422, pos = vec3(0.0, 0.0, -0.03), rot = vec3(0.0, 0.0, 0.0) }, sound = 'spray' },
        moisturizer  = { label = 'Moisturizer',      item = 'moisturizer',  use = true,  prop = { model = `nz_sty_spray`,  bone = 28422, pos = vec3(0.0, 0.0, -0.03), rot = vec3(0.0, 0.0, 0.0) }, sound = 'spray' },
        elastics     = { label = 'Hair Elastics',    item = 'elastics',     use = true },
        bobby_pins   = { label = 'Bobby Pins',       item = 'bobby_pins',   use = true },
        hair_beads   = { label = 'Beads & Cuffs',    item = 'hair_beads',   use = true },
        wig_cap      = { label = 'Mesh Weaving Cap', item = 'wig_cap',      use = true },
        wig_thread   = { label = 'Weaving Thread',   item = 'wig_thread',   use = true },
        lace_closure = { label = 'Lace Closure',     item = 'lace_closure', use = true },
        hot_water    = { label = 'Hot Water',        item = false },
        -- the extension hair the style uses, in hand
        hair         = { label = 'Extension Hair',   item = false, prop = { model = `nz_sty_pack`, bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(90.0, 0.0, 0.0) } },
    },

    -- The braid down under a sew-in: GTA's own cornrows. Female 25 is Pinched Cornrows and male 8 is
    -- Cornrows on most game builds; check the number in /wigstudio and put yours here (or link the
    -- "cornrows" look there, which wins over this).
    Cornrows = { f = { d = 25, t = 0 }, m = { d = 8, t = 0 } },
    -- In-between looks you can link in /wigstudio like the styles
    Looks = {
        cornrows = 'Cornrows: the braid down under a sew-in',
    },

    -- How props sit on a head (slices, the wig cap, clips): attached to the head bone (SKEL_Head) turned
    -- from the ped's axes into the bone's. If they sit wrong on your build, /salonalign (admins) lets you
    -- nudge it live with the arrow keys and prints the values to put here.
    Attach = { pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 90.0, 0.0) },
    -- The pieces that go on the head while working (props in stream/)
    Pieces = {
        cap  = `nz_sty_capon`,   -- the mesh wig cap, over the cornrows
        clip = `nz_sty_clip`,    -- sectioning clips
        pin  = `nz_sty_pin`,     -- bobby pins
    },
}

-- The Beauty Supply: braiding hair, bundles, products and tools for the salon. Same store window as the
-- Hair Supply. Hair packs are bought in a shade, length and texture (perInch = extra per inch over the shortest).
Config.BeautySupply = {
    Enabled    = true,
    Label      = 'Beauty Supply',
    Ped        = `a_f_y_hipster_02`,
    Coords     = vector4(128.6, -1712.0, 29.29, 140.0),  -- On Carson Ave by Herr Kutz in Davis; move it anywhere
    Blip       = { sprite = 71, colour = 8, scale = 0.75 },  -- false = no blip
    Accounts   = { 'cash', 'bank' },
    MaxPerItem = 25,
    Categories = {
        { id = 'hair',    label = 'Hair',    icon = 'bundle' },
        { id = 'styling', label = 'Styling', icon = 'drop' },
        { id = 'tools',   label = 'Tools',   icon = 'scissors' },
    },
    Items = {
        braid_hair   = { label = 'Braiding Hair',   price = 8,  perInch = 0.5, variants = true, cat = 'hair', desc = 'Pre-stretched Kanekalon. Box braids, knotless, cornrows.' },
        marley_hair  = { label = 'Marley Hair',     price = 9,  perInch = 0.5, variants = true, cat = 'hair', desc = 'Wrapping hair for faux locs.' },
        bulk_hair    = { label = 'Curly Bulk Hair', price = 14, perInch = 1,   variants = true, cat = 'hair', desc = 'Water or deep wave curls for boho braids.' },
        crochet_hair = { label = 'Crochet Hair',    price = 12, perInch = 0.5, variants = true, cat = 'hair', desc = 'Water wave or bohemian curl for passion twists.' },
        locs_hair    = { label = 'Faux Locs',       price = 16, perInch = 1,   variants = true, cat = 'hair', desc = 'Pre-looped distressed or butterfly locs.', level = 3 },
        weave_bundle = { label = 'Weave Bundle',    price = 45, perInch = 3,   variants = true, cat = 'hair', desc = '100% human hair weft for sew-ins.', level = 4 },
        braid_gel    = { label = 'Braiding Gel',    price = 12, cat = 'styling', desc = 'Firm hold for clean parts and neat roots.' },
        edge_control = { label = 'Edge Control',    price = 10, cat = 'styling', desc = 'Smooth roots, laid edges.' },
        mousse       = { label = 'Foam Mousse',     price = 14, cat = 'styling', desc = 'Sets braids, defines curls.' },
        moisturizer  = { label = 'Moisturizer',     price = 10, cat = 'styling', desc = 'Preps natural hair before braiding.' },
        heat_protect = { label = 'Heat Protectant', price = 16, cat = 'styling', desc = 'Before the flat iron, always.' },
        shine_spray  = { label = 'Shine Spray',     price = 12, cat = 'styling', desc = 'The finishing shine.' },
        elastics     = { label = 'Hair Elastics',   price = 4,  cat = 'styling', desc = 'For braid ends and bubbles.' },
        bobby_pins   = { label = 'Bobby Pins',      price = 4,  cat = 'styling', desc = 'Pins buns and tucked ends.' },
        hair_beads   = { label = 'Beads & Cuffs',   price = 9,  cat = 'styling', desc = 'Wooden and gold beads for braid ends.' },
        rat_comb     = { label = 'Rat-tail Comb',   price = 15, cat = 'tools', desc = 'Parts clean sections. Use it on someone to open the Style Book.', max = 2 },
        paddle_brush = { label = 'Paddle Brush',    price = 25, cat = 'tools', desc = 'Brush and detangle.', max = 2 },
        edge_brush   = { label = 'Edge Brush',      price = 8,  cat = 'tools', desc = 'Lays baby hairs.', max = 2 },
        c_needle     = { label = 'C-Needle',        price = 6,  cat = 'tools', desc = 'For sew-ins and tacking cornrows.', max = 5 },
        crochet_hook = { label = 'Crochet Hook',    price = 8,  cat = 'tools', desc = 'Latches hair in at the root.', max = 2 },
        scissors     = { label = 'Styling Shears',  price = 35, cat = 'tools', desc = 'Trims and layers. Cuts hair too.', max = 1 },
        blow_dryer   = { label = 'Blow Dryer',      price = 95, cat = 'tools', desc = 'Dry and stretch before braiding.', max = 1, level = 2 },
        flat_iron    = { label = 'Flat Iron',       price = 120, cat = 'tools', desc = 'Blends leave-out. Mind the heat.', max = 1, level = 4 },
        curl_wand    = { label = 'Curling Wand',    price = 110, cat = 'tools', desc = 'Curls for leave-out and ends.', max = 1, level = 3 },
        wig_cap      = { label = 'Mesh Weaving Cap', price = 15, cat = 'tools', desc = 'Goes over the braid down for a sew-in.' },
        wig_thread   = { label = 'Weaving Thread',  price = 5,  cat = 'tools', desc = 'For sewing the wefts down.' },
    },
}

-- ███████╗████████╗██╗   ██╗██╗     ███████╗███████╗
-- ██╔════╝╚══██╔══╝╚██╗ ██╔╝██║     ██╔════╝██╔════╝
-- ███████╗   ██║    ╚████╔╝ ██║     █████╗  ███████╗
-- ╚════██║   ██║     ╚██╔╝  ██║     ██╔══╝  ╚════██║
-- ███████║   ██║      ██║   ███████╗███████╗███████║
-- ╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚══════╝╚══════╝
--
-- Every style: id, label, cat (the Style Book tab), level (stylist level needed), days (how long it lasts),
-- hair = { item, n } extension hair it needs (ext = true: optional, the stylist picks natural or extensions),
-- options = optional parts the stylist can turn on, and steps.
-- Each step is the text the stylist reads, played out as one or more moves:
--
--   a = 'trace'   follow the dotted line on the head (parting, cutting lace, laying edges)
--   a = 'cornrow' braid along a row against the scalp: A / D stitch by stitch, keep the cursor on the braid
--   a = 'braid'   braid a hanging or laid braid: press the strand keys on the beat
--                 seq tokens: R / L = right / left strand OVER the middle, r / l = UNDER (Dutch),
--                 +R = pick up loose hair first, FR = feed in extension hair first, CR = leave a curl out,
--                 A / B = fishtail pieces, D = drop the bottom strand (waterfall)
--   a = 'dab'     click each spot (gel, pins, elastics, beads, clips, snips) - mark = what appears
--   a = 'sew'     needle in (click), pull the thread through (flick up), stitch by stitch along the track
--   a = 'sweep'   hold and cover the area (sprays, mousse, blow dryer). heat = don't stay on one spot
--   a = 'stroke'  hold and drag from root to tip along each strand (brushing, flat iron)
--   a = 'circle'  hold and turn around the spot (twists, buns, wrapping locs, scrunching)
--   a = 'drag'    drag the hair from one spot to another (gathering, puffing bubbles, the cap, the lace)
--   a = 'hold'    hold and let go inside the green band (dipping ends, threading the needle)
-- geo = where (see shared/salon.lua), tool = what's in hand (Config.Salon.Tools), from / limit = part of the geo,
-- opt = only when that option is picked ('ext' = only when extension hair is used).

Config.SalonCats = {
    { id = 'braids',   label = 'Braids',          icon = 'braid' },
    { id = 'box',      label = 'Box & Knotless',  icon = 'grid' },
    { id = 'cornrows', label = 'Cornrows',        icon = 'rows' },
    { id = 'twists',   label = 'Twists & Locs',   icon = 'twist' },
    { id = 'weaves',   label = 'Sew-ins',         icon = 'needle' },
}

Config.SalonStyles = {
    -- 1 ----------------------------------------------------------------------------------------------------
    {
        id = 'three_strand', label = 'Classic Three-Strand Braid', cat = 'braids', level = 1, days = 1,
        desc = 'The one everyone learns first. Natural hair only.',
        steps = {
            { text = 'Brush hair smooth and divide it into three equal sections (left, middle, right).', moves = {
                { a = 'stroke', geo = 'strand:back:3:1.3', tool = 'paddle_brush', n = 2 },
                { a = 'drag', geo = 'drag:sections', tool = 'hands' } } },
            { text = 'Cross the right strand over the middle strand so it becomes the new middle.', moves = {
                { a = 'braid', geo = 'strand:back:1:1.4', seq = { 'R' }, stitches = 1 } } },
            { text = 'Cross the left strand over the new middle strand.', moves = {
                { a = 'braid', seq = { 'L' }, stitches = 1, cont = true } } },
            { text = 'Repeat alternating right-over-middle and left-over-middle down to the ends.', moves = {
                { a = 'braid', seq = { 'R', 'L' }, stitches = 12, cont = true } } },
            { text = 'Secure the bottom with a hair elastic.', moves = {
                { a = 'dab', geo = 'points:ends:1:1.45', tool = 'elastics', mark = 'elastic' } } },
        },
    },
    -- 2 ----------------------------------------------------------------------------------------------------
    {
        id = 'french', label = 'French Braid', cat = 'braids', level = 1, days = 2,
        desc = 'Laid flat from the crown down. Natural hair, or one pack for extra length.',
        hair = { item = 'braid_hair', n = 1, ext = true },
        steps = {
            { text = 'Gather a medium section of hair at the top crown and split it into three equal strands.', moves = {
                { a = 'drag', geo = 'drag:gather:crown', tool = 'hands', limit = 3 } } },
            { text = 'Cross the right strand over the middle, then the left over the middle.', moves = {
                { a = 'braid', geo = 'rows:back:1', seq = { 'R', 'L' }, stitches = 2 } } },
            { text = 'Gather a small section of loose hair from the right side, add it to the right strand, and cross over the middle.', moves = {
                { a = 'braid', seq = { '+R' }, stitches = 1, cont = true } } },
            { text = 'Gather a small section of loose hair from the left side, add it to the left strand, and cross over the middle.', moves = {
                { a = 'braid', seq = { '+L' }, stitches = 1, cont = true } } },
            { text = 'Repeat down the head until all hair is incorporated, finish as a three-strand braid, and tie off.', moves = {
                { a = 'braid', seq = { '+R', '+L' }, stitches = 8, cont = true, feed = true },
                { a = 'braid', geo = 'strand:nape:1:1.2', seq = { 'R', 'L' }, stitches = 6 },
                { a = 'dab', geo = 'points:ends:1:1.25', tool = 'elastics', mark = 'elastic' } } },
        },
    },
    -- 3 ----------------------------------------------------------------------------------------------------
    {
        id = 'dutch', label = 'Dutch Braid', cat = 'braids', level = 2, days = 3,
        desc = 'An inside-out French braid that sits raised on top. Natural, or fed in with 2 packs.',
        hair = { item = 'braid_hair', n = 2, ext = true },
        steps = {
            { text = 'Gather a section of hair at the crown and divide it into three equal strands.', moves = {
                { a = 'drag', geo = 'drag:gather:crown', tool = 'hands', limit = 3 } } },
            { text = 'Cross the right strand UNDER the middle strand, then the left strand UNDER the middle.', moves = {
                { a = 'braid', geo = 'rows:back:1', seq = { 'r', 'l' }, stitches = 2 } } },
            { text = 'Gather loose hair from the right, combine with the right strand (feeding in extension hair if purchased), and cross UNDER the middle.', moves = {
                { a = 'braid', seq = { '+r' }, stitches = 1, cont = true, feed = true } } },
            { text = 'Gather loose hair from the left, combine with the left strand, and cross UNDER the middle.', moves = {
                { a = 'braid', seq = { '+l' }, stitches = 1, cont = true, feed = true } } },
            { text = 'Repeat down the head so the braid sits raised on top, finish to the ends, and secure.', moves = {
                { a = 'braid', seq = { '+r', '+l' }, stitches = 8, cont = true, feed = true },
                { a = 'braid', geo = 'strand:nape:1:1.3', seq = { 'r', 'l' }, stitches = 6 },
                { a = 'dab', geo = 'points:ends:1:1.35', tool = 'elastics', mark = 'elastic' } } },
        },
    },
    -- 4 ----------------------------------------------------------------------------------------------------
    {
        id = 'fishtail', label = 'Fishtail Braid', cat = 'braids', level = 2, days = 1,
        desc = 'Two halves and a lot of thin pieces. Natural hair only.',
        steps = {
            { text = 'Pull hair back and divide it into two equal halves (left and right).', moves = {
                { a = 'drag', geo = 'drag:gather:ponytail', tool = 'paddle_brush', limit = 4 },
                { a = 'drag', geo = 'drag:two', tool = 'hands' } } },
            { text = 'Take a thin piece from the far outside edge of the left section and cross it over into the inside of the right section.', moves = {
                { a = 'braid', geo = 'strand:back:1:1.4', strands = 2, seq = { 'A' }, stitches = 1 } } },
            { text = 'Take a thin piece from the far outside edge of the right section and cross it over into the inside of the left section.', moves = {
                { a = 'braid', strands = 2, seq = { 'B' }, stitches = 1, cont = true } } },
            { text = 'Alternate thin outer pieces from side to side down to the ends and tie off.', moves = {
                { a = 'braid', strands = 2, seq = { 'A', 'B' }, stitches = 16, cont = true },
                { a = 'dab', geo = 'points:ends:1:1.45', tool = 'elastics', mark = 'elastic' } } },
        },
    },
    -- 5 ----------------------------------------------------------------------------------------------------
    {
        id = 'box_braids', label = 'Box Braids', cat = 'box', level = 2, days = 14,
        desc = 'Square parts, extension hair looped at the root, braided all the way down.',
        hair = { item = 'braid_hair', n = 5 },
        steps = {
            { text = 'Prep hair with moisturizer and use a rat-tail comb to part clean, square-shaped sections across the scalp.', moves = {
                { a = 'sweep', geo = 'zone:all', tool = 'moisturizer' },
                { a = 'trace', geo = 'part:grid:3:3', tool = 'rat_comb' } } },
            { text = 'Apply braiding gel at the base of one square and split the natural hair into three strands.', moves = {
                { a = 'dab', geo = 'points:grid:3:3', tool = 'braid_gel', mark = 'gel' } } },
            { text = 'Loop a piece of selected extension hair around the root so it merges with the three natural strands.', moves = {
                { a = 'circle', geo = 'points:grid:1:3', tool = 'hair', turns = 1, dir = 'cw' } } },
            { text = 'Braid tightly at the base and continue braiding down to the ends.', moves = {
                { a = 'braid', geo = 'strand:back:1:1.9', seq = { 'R', 'L' }, stitches = 14 } } },
            { text = 'Dip the synthetic ends in hot water to seal and finish with mousse.', moves = {
                { a = 'hold', tool = 'hot_water', band = { 0.62, 0.82 } },
                { a = 'sweep', geo = 'zone:ends', tool = 'mousse' } } },
        },
    },
    -- 6 ----------------------------------------------------------------------------------------------------
    {
        id = 'knotless', label = 'Knotless Braids', cat = 'box', level = 3, days = 14,
        desc = 'No knot at the root: natural hair first, then extension hair fed in thin, then thicker.',
        hair = { item = 'braid_hair', n = 5 },
        steps = {
            { text = 'Part hair into clean square or triangle sections using a rat-tail comb and braiding gel.', moves = {
                { a = 'trace', geo = 'part:grid:3:3', tool = 'rat_comb' },
                { a = 'dab', geo = 'points:grid:3:3', tool = 'braid_gel', mark = 'gel' } } },
            { text = 'Split one natural section into three strands and braid natural hair for 2 to 3 stitches without extensions.', moves = {
                { a = 'braid', geo = 'strand:back:1:1.9', seq = { 'R', 'L' }, stitches = 3 } } },
            { text = 'Feed a very thin piece of extension hair into the braid between your thumb and index finger as you stitch.', moves = {
                { a = 'braid', seq = { 'FR', 'L' }, stitches = 2, cont = true, feed = 'thin' } } },
            { text = 'Gradually feed in slightly thicker pieces of extension hair every few stitches to build fullness.', moves = {
                { a = 'braid', seq = { 'R', 'L', 'FR', 'L' }, stitches = 8, cont = true, feed = 'grow' } } },
            { text = 'Braid all the way down, dip ends in hot water to seal, and apply mousse.', moves = {
                { a = 'braid', seq = { 'R', 'L' }, stitches = 4, cont = true },
                { a = 'hold', tool = 'hot_water', band = { 0.62, 0.82 } },
                { a = 'sweep', geo = 'zone:ends', tool = 'mousse' } } },
        },
    },
    -- 7 ----------------------------------------------------------------------------------------------------
    {
        id = 'cornrows', label = 'Cornrows (Straight Backs)', cat = 'cornrows', level = 1, days = 7,
        desc = 'Straight rows from the hairline to the nape. Natural, or fed in with 2 to 3 packs.',
        hair = { item = 'braid_hair', n = 2, ext = true },
        steps = {
            { text = 'Part a straight, narrow row from the front hairline to the nape of the neck and apply braiding gel.', moves = {
                { a = 'trace', geo = 'rows:all:5', tool = 'rat_comb' },
                { a = 'dab', geo = 'points:hairline:5', tool = 'braid_gel', mark = 'gel' } } },
            { text = 'Pick up a small triangle at the front hairline and split into three tiny strands.', moves = {
                { a = 'dab', geo = 'points:hairline:5', tool = 'hands', mark = 'pick' } } },
            { text = 'Braid underhand right against the scalp, picking up small amounts of hair from the row with every stitch (feeding in extension hair if used).', moves = {
                { a = 'cornrow', geo = 'rows:all:5', stitches = 8, feed = true } } },
            { text = 'Keep tension even until reaching the nape, finish braiding the tail, and secure.', moves = {
                { a = 'dab', geo = 'points:rows:5', tool = 'elastics', mark = 'elastic' } } },
        },
    },
    -- 8 ----------------------------------------------------------------------------------------------------
    {
        id = 'stitch', label = 'Stitch Braids', cat = 'cornrows', level = 4, days = 7,
        desc = 'Cornrows with crisp horizontal stitch lines between every plait.',
        hair = { item = 'braid_hair', n = 3 },
        steps = {
            { text = 'Part a vertical row down the scalp and coat the section in firm-hold braiding gel.', moves = {
                { a = 'trace', geo = 'rows:all:4', tool = 'rat_comb' },
                { a = 'sweep', geo = 'zone:top', tool = 'braid_gel' } } },
            { text = 'Begin braiding a cornrow at the front hairline for two or three stitches.', moves = {
                { a = 'cornrow', geo = 'rows:all:4', stitches = 2, limit = 1 } } },
            { text = 'Use a pinky fingernail or rat-tail comb tip to slice a crisp, horizontal line across the row.', moves = {
                { a = 'dab', geo = 'rows:all:4', every = 5, tool = 'rat_comb', mark = 'slice', limit = 4 } } },
            { text = 'Smooth that horizontal slice with gel and feed it cleanly into the underhand braid alongside extension hair.', moves = {
                { a = 'cornrow', geo = 'rows:all:4', stitches = 3, feed = true, limit = 1 } } },
            { text = 'Repeat the horizontal slicing and feeding motion all the way down so clean "stitch" lines show between each plait.', moves = {
                { a = 'cornrow', geo = 'rows:all:4', stitches = 7, feed = true, slice = true } } },
        },
    },
    -- 9 ----------------------------------------------------------------------------------------------------
    {
        id = 'fulani', label = 'Fulani Braids', cat = 'cornrows', level = 4, days = 14,
        desc = 'A center cornrow, side rows, braids in the back, forward braids at the ears and beads.',
        hair = { item = 'braid_hair', n = 4 },
        uses = { 'hair_beads' },
        steps = {
            { text = 'Part hair horizontally from ear to ear, separating the front half from the back half.', moves = {
                { a = 'trace', geo = 'part:ear2ear', tool = 'rat_comb' } } },
            { text = 'Install individual box braids or knotless braids in the back half.', moves = {
                { a = 'braid', geo = 'strand:back:3:1.8', seq = { 'R', 'L' }, stitches = 6 } } },
            { text = 'In the front half, braid a center cornrow down the middle flanked by straight-back cornrows on each side.', moves = {
                { a = 'cornrow', geo = 'rows:front:3', stitches = 6, feed = true } } },
            { text = 'Leave out two thin sections near the ears and braid them forward-facing down toward the jawline.', moves = {
                { a = 'braid', geo = 'strand:ears:2:0.9', seq = { 'R', 'L' }, stitches = 5 } } },
            { text = 'Slide chosen beads or cuffs onto the ends and secure with small rubber bands.', moves = {
                { a = 'dab', geo = 'points:ends:5:1.8', tool = 'hair_beads', mark = 'bead' } } },
        },
    },
    -- 10 ---------------------------------------------------------------------------------------------------
    {
        id = 'boho', label = 'Boho / Goddess Braids', cat = 'box', level = 5, days = 10,
        desc = 'Knotless braids with curly pieces left out all the way down.',
        hair = { item = 'braid_hair', n = 5 },
        extra = { item = 'bulk_hair', n = 2 },
        steps = {
            { text = 'Part hair into knotless or box sections and begin braiding with standard braiding hair.', moves = {
                { a = 'trace', geo = 'part:grid:2:3', tool = 'rat_comb' },
                { a = 'braid', geo = 'strand:back:1:1.9', seq = { 'R', 'L' }, stitches = 4 } } },
            { text = 'Two inches from the root, insert a loose strand of curly bulk hair into the braid and leave it hanging out.', moves = {
                { a = 'braid', seq = { 'CR', 'L' }, stitches = 2, cont = true } } },
            { text = 'Continue braiding the main strands down while pulling out a new curly strand every few inches.', moves = {
                { a = 'braid', seq = { 'R', 'L', 'R', 'CL' }, stitches = 12, cont = true } } },
            { text = 'Leave the ends curly, apply curl mousse, and scrunch to define the bohemian waves.', moves = {
                { a = 'sweep', geo = 'zone:ends', tool = 'mousse' },
                { a = 'circle', geo = 'points:ends:4:1.9', tool = 'hands', turns = 1, dir = 'alt' } } },
        },
    },
    -- 11 ---------------------------------------------------------------------------------------------------
    {
        id = 'lemonade', label = 'Lemonade Braids', cat = 'cornrows', level = 3, days = 7,
        desc = 'Side-swept cornrows from a deep side part. Big in 27 honey blonde or 1 jet black.',
        hair = { item = 'braid_hair', n = 4 },
        steps = {
            { text = 'Create a deep side part on either the left or right side of the head.', moves = {
                { a = 'trace', geo = 'part:side_l', tool = 'rat_comb' } } },
            { text = 'Part curved, sweeping rows moving horizontally/diagonally from the side part across the head toward the opposite ear.', moves = {
                { a = 'trace', geo = 'rows:all:4:curve_l', tool = 'rat_comb' } } },
            { text = 'Apply braiding gel and feed-in extension hair as you stitch each curved cornrow closely along the scalp.', moves = {
                { a = 'dab', geo = 'rows:all:4:curve_l', every = 16, tool = 'braid_gel', mark = 'gel' },
                { a = 'cornrow', geo = 'rows:all:4:curve_l', stitches = 7, feed = true } } },
            { text = 'Braid all rows down past the shoulder on one side and seal the ends in hot water.', moves = {
                { a = 'braid', geo = 'strand:right:2:1.8', seq = { 'R', 'L' }, stitches = 6 },
                { a = 'hold', tool = 'hot_water', band = { 0.62, 0.82 } } } },
        },
    },
    -- 12 ---------------------------------------------------------------------------------------------------
    {
        id = 'passion', label = 'Passion Twists', cat = 'twists', level = 4, days = 14,
        desc = 'Two-strand twists with water wave hair, curly all the way to the tips.',
        hair = { item = 'crochet_hair', n = 6 },
        steps = {
            { text = 'Part hair into square sections and apply gel at the roots.', moves = {
                { a = 'trace', geo = 'part:grid:2:3', tool = 'rat_comb' },
                { a = 'dab', geo = 'points:grid:2:3', tool = 'braid_gel', mark = 'gel' } } },
            { text = 'Attach the wavy extension hair at the root using either the rubber-band method or a crochet latch hook.', moves = {
                { a = 'circle', geo = 'points:grid:1:3', tool = 'crochet_hook', turns = 1, dir = 'cw' } } },
            { text = 'Divide the natural hair and wavy extensions into two equal halves.', moves = {
                { a = 'drag', geo = 'drag:two', tool = 'hands' } } },
            { text = 'Twist each strand individually in the same direction while twisting the two strands around each other in the opposite direction (two-strand twist).', moves = {
                { a = 'circle', geo = 'points:length:5:1.7', tool = 'hands', turns = 1, dir = 'alt' } } },
            { text = 'Twist all the way down to the curly tips and apply mousse for frizz-free shine.', moves = {
                { a = 'circle', geo = 'points:ends:3:1.8', tool = 'hands', turns = 1, dir = 'cw' },
                { a = 'sweep', geo = 'zone:ends', tool = 'mousse' } } },
        },
    },
    -- 13 ---------------------------------------------------------------------------------------------------
    {
        id = 'senegalese', label = 'Senegalese Twists', cat = 'twists', level = 3, days = 14,
        desc = 'Smooth rope twists in silky braiding hair.',
        hair = { item = 'braid_hair', n = 6 },
        steps = {
            { text = 'Part hair into clean box sections and apply edge control to smooth the roots.', moves = {
                { a = 'trace', geo = 'part:grid:2:3', tool = 'rat_comb' },
                { a = 'dab', geo = 'points:grid:2:3', tool = 'edge_control', mark = 'gel' } } },
            { text = 'Split the natural section into two equal strands and loop a piece of silky braiding hair at the base.', moves = {
                { a = 'drag', geo = 'drag:two', tool = 'hands' },
                { a = 'circle', geo = 'points:grid:1:3', tool = 'hair', turns = 1, dir = 'cw' } } },
            { text = 'Twist both strands tightly to the right while wrapping them over each other to the left.', moves = {
                { a = 'circle', geo = 'points:length:6:1.8', tool = 'hands', turns = 1, dir = 'alt' } } },
            { text = 'Keep tension uniform down to the bottom for a smooth, rope-like finish and dip ends in hot water.', moves = {
                { a = 'stroke', geo = 'strand:back:3:1.8', tool = 'hands', n = 1 },
                { a = 'hold', tool = 'hot_water', band = { 0.62, 0.82 } } } },
        },
    },
    -- 14 ---------------------------------------------------------------------------------------------------
    {
        id = 'faux_locs', label = 'Faux Locs / Butterfly Locs', cat = 'twists', level = 5, days = 21,
        desc = 'Braided down, then wrapped in Marley hair, looped for butterfly locs and palm-rolled.',
        hair = { item = 'locs_hair', n = 6 },
        extra = { item = 'marley_hair', n = 2 },
        steps = {
            { text = 'Part hair into square sections and braid each section down into a basic three-strand braid (or attach pre-looped locs with a crochet hook).', moves = {
                { a = 'trace', geo = 'part:grid:2:3', tool = 'rat_comb' },
                { a = 'braid', geo = 'strand:back:1:1.7', seq = { 'R', 'L' }, stitches = 6 } } },
            { text = 'Take a strand of Marley or Water Wave wrapping hair and secure it at the root of the braid.', moves = {
                { a = 'dab', geo = 'points:grid:1:3', tool = 'hair', mark = 'wrap' } } },
            { text = 'Wrap the hair neatly around the braid moving downward (using your thumb to create loops if making Butterfly Locs).', moves = {
                { a = 'circle', geo = 'points:length:6:1.6', tool = 'hair', turns = 1, dir = 'cw' } } },
            { text = 'Once at the bottom, wrap slightly back upward for an inch and palm-roll the loc to seal the end.', moves = {
                { a = 'circle', geo = 'points:ends:3:1.7', tool = 'hands', turns = 2, dir = 'alt' } } },
        },
    },
    -- 15 ---------------------------------------------------------------------------------------------------
    {
        id = 'halo', label = 'Halo Braid (Crown Braid)', cat = 'braids', level = 3, days = 3,
        desc = 'One Dutch braid all the way around the head like a crown.',
        hair = { item = 'braid_hair', n = 2, ext = true },
        uses = { 'bobby_pins' },
        steps = {
            { text = 'Part hair down the center or slightly off-center and brush smooth.', moves = {
                { a = 'trace', geo = 'part:center', tool = 'rat_comb' },
                { a = 'stroke', geo = 'rows:all:3', tool = 'paddle_brush', n = 1 } } },
            { text = 'Start a Dutch braid behind one ear, curving upward along the front hairline like a headband.', moves = {
                { a = 'braid', geo = 'rows:all:1:halo', seq = { '+r', '+l' }, stitches = 8, feed = true } } },
            { text = 'Continue curving the braid around the opposite side of the head and down toward the nape of the neck.', moves = {
                { a = 'braid', seq = { '+r', '+l' }, stitches = 8, cont = true, feed = true } } },
            { text = 'Braid all remaining hair into the circle until you reach your starting point behind the ear.', moves = {
                { a = 'braid', seq = { '+r', '+l' }, stitches = 6, cont = true } } },
            { text = 'Finish the tail as a regular braid, tuck the ends underneath the crown, and secure with bobby pins.', moves = {
                { a = 'braid', seq = { 'R', 'L' }, stitches = 3, cont = true },
                { a = 'dab', geo = 'points:perimeter:5', tool = 'bobby_pins', mark = 'pin' } } },
        },
    },
    -- 16 ---------------------------------------------------------------------------------------------------
    {
        id = 'space_buns', label = 'Space Buns with Feed-In Braids', cat = 'cornrows', level = 3, days = 3,
        desc = 'Feed-in cornrows up to two buns. Fun colours like pink, blonde or a two-tone ombre.',
        hair = { item = 'braid_hair', n = 2 },
        uses = { 'bobby_pins' },
        steps = {
            { text = 'Part hair cleanly down the middle from forehead to nape into two equal halves (left and right).', moves = {
                { a = 'trace', geo = 'part:center', tool = 'rat_comb' } } },
            { text = 'On the left half, braid 3 to 5 upward feed-in cornrows directed straight toward the top crown of the head.', moves = {
                { a = 'cornrow', geo = 'rows:left:4:up', stitches = 6, feed = true } } },
            { text = 'Gather the braided tails at the crown into a high ponytail, twist the hair around the base into a round bun, and pin securely.', moves = {
                { a = 'drag', geo = 'drag:gather:bun_l', tool = 'hands', limit = 3 },
                { a = 'circle', geo = 'point:bun_l', tool = 'hands', turns = 2, dir = 'cw' },
                { a = 'dab', geo = 'point:bun_l', tool = 'bobby_pins', mark = 'pin' } } },
            { text = 'Repeat the exact same upward cornrows and top bun on the right half.', moves = {
                { a = 'cornrow', geo = 'rows:right:4:up', stitches = 6, feed = true },
                { a = 'drag', geo = 'drag:gather:bun_r', tool = 'hands', limit = 3 },
                { a = 'circle', geo = 'point:bun_r', tool = 'hands', turns = 2, dir = 'ccw' },
                { a = 'dab', geo = 'point:bun_r', tool = 'bobby_pins', mark = 'pin' } } },
        },
    },
    -- 17 ---------------------------------------------------------------------------------------------------
    {
        id = 'bubble', label = 'Bubble Braid', cat = 'braids', level = 1, days = 1,
        desc = 'A sleek ponytail puffed into bubbles all the way down.',
        hair = { item = 'braid_hair', n = 1, ext = true },
        uses = { 'elastics' },
        steps = {
            { text = 'Gather hair into a sleek high, mid, or low ponytail (or twin pigtails) and secure with a hair tie.', moves = {
                { a = 'drag', geo = 'drag:gather:ponytail', tool = 'paddle_brush' },
                { a = 'dab', geo = 'point:ponytail', tool = 'elastics', mark = 'elastic' } } },
            { text = 'Place a second elastic 2 to 3 inches below the first base elastic.', moves = {
                { a = 'dab', geo = 'points:length:4:1.5', tool = 'elastics', mark = 'elastic', limit = 1 } } },
            { text = 'Gently tug the hair between the two elastics outward with your fingers to puff it into a round "bubble" shape.', moves = {
                { a = 'drag', geo = 'drag:puff', tool = 'hands', limit = 1 } } },
            { text = 'Repeat placing elastics and puffing out sections down the entire length.', moves = {
                { a = 'dab', geo = 'points:length:4:1.5', tool = 'elastics', mark = 'elastic', from = 2 },
                { a = 'drag', geo = 'drag:puff', tool = 'hands', from = 2 } } },
        },
    },
    -- 18 ---------------------------------------------------------------------------------------------------
    {
        id = 'waterfall', label = 'Waterfall Braid', cat = 'braids', level = 3, days = 1,
        desc = 'A braid around the head with strands falling through it. Best on curled or wavy hair.',
        steps = {
            { text = 'Take a small section near the front hairline and divide into three strands.', moves = {
                { a = 'dab', geo = 'point:temple_l', tool = 'hands', mark = 'pick' } } },
            { text = 'Cross the top strand over the middle, then the bottom strand over the middle.', moves = {
                { a = 'braid', geo = 'rows:all:1:halo', seq = { 'R', 'L' }, stitches = 2 } } },
            { text = 'Pick up a new section from the top, add to the top strand, and cross over the middle.', moves = {
                { a = 'braid', seq = { '+R' }, stitches = 1, cont = true } } },
            { text = 'Let the bottom strand drop straight down freely, pick up a brand-new strand next to it, and repeat around the head.', moves = {
                { a = 'braid', seq = { 'D', '+R', 'L' }, stitches = 12, cont = true } } },
        },
    },
    -- 19 ---------------------------------------------------------------------------------------------------
    {
        id = 'sew_in', label = 'Traditional Sew-In Weave', cat = 'weaves', level = 5, days = 21,
        desc = 'The full install: braid down, cap, closure, wefts sewn track by track, then blended and styled.',
        hair = { item = 'weave_bundle', n = 3 },
        uses = { 'wig_cap', 'wig_thread' },
        options = {
            leaveout = 'Natural leave-out at the top',
            closure  = 'Lace closure at the front (uses a Lace Closure)',
        },
        steps = {
            -- PHASE 1: CORNROW FOUNDATION (THE BRAID DOWN)
            { phase = 'Cornrow foundation (the braid down)',
              text = 'Wash, blow-dry, and detangle natural hair completely.', moves = {
                { a = 'sweep', geo = 'zone:all', tool = 'blow_dryer' },
                { a = 'stroke', geo = 'strand:back:3:1.2', tool = 'paddle_brush', n = 2 } } },
            { text = '(Optional Leave-Out) Part and clip away a small horseshoe section at the top crown/parting area if doing a natural leave-out sew-in.', opt = 'leaveout', moves = {
                { a = 'trace', geo = 'part:horseshoe', tool = 'rat_comb' },
                { a = 'dab', geo = 'point:top', tool = 'hands', mark = 'clip' } } },
            { text = 'Apply braiding gel and braid the rest of the natural hair into tight, flat, uniform cornrows running straight back or in a circular beehive pattern against the scalp.', moves = {
                { a = 'sweep', geo = 'zone:back', tool = 'braid_gel' },
                { a = 'cornrow', geo = 'rows:all:6', stitches = 6, base = 'cornrows' } } },
            { text = 'Sew or pin the loose ends of the cornrows flat against the head so there are no lumps.', moves = {
                { a = 'dab', geo = 'points:rows:6', tool = 'c_needle', mark = 'tack' } } },
            -- PHASE 2: WIG CAP & CLOSURE PLACEMENT
            { phase = 'Wig cap & closure placement',
              text = 'Stretch the breathable mesh wig cap over the entire braided foundation (pulling it behind any leave-out hair).', moves = {
                { a = 'drag', geo = 'drag:cap', tool = 'wig_cap' } } },
            { text = 'Use a curved needle and thread to tack the perimeter of the wig cap securely onto the outer cornrows so it cannot slip.', moves = {
                { a = 'sew', geo = 'points:perimeter:10', tool = 'c_needle' } } },
            { text = 'If using a lace closure or frontal, position it at the front hairline, cut off excess lace, and sew the edges down tightly onto the front cornrows.', opt = 'closure', moves = {
                { a = 'drag', geo = 'drag:lace', tool = 'lace_closure' },
                { a = 'trace', geo = 'part:lace', tool = 'shears' },
                { a = 'sew', geo = 'points:hairline:6', tool = 'c_needle' } } },
            -- PHASE 3: THE SEW-IN PROCESS (INSTALLING BUNDLES)
            { phase = 'The sew-in (installing bundles)',
              text = 'Thread the curved C-needle with double-knotted weaving thread.', moves = {
                { a = 'hold', tool = 'c_needle', band = { 0.7, 0.84 }, n = 2 } } },
            { text = 'Starting at the nape (bottom back) of the neck, place the first hair weft track horizontally from ear to ear.', moves = {
                { a = 'trace', geo = 'track:5', tool = 'hair', limit = 1 } } },
            { text = 'Push the curved needle through the weft, catch the wig cap and the underlying cornrow underneath, pull the thread through, and loop it to lock the stitch.', moves = {
                { a = 'sew', geo = 'track:5', tool = 'c_needle', stitches = 2, limit = 1 } } },
            { text = 'Repeat tight lock-stitches every half-inch across the entire track until reaching the opposite ear.', moves = {
                { a = 'sew', geo = 'track:5', tool = 'c_needle', stitches = 8, limit = 1, cont = true } } },
            { text = 'Fold the weft track neatly at the end (the "fold-over method" instead of cutting the track to prevent shedding) and begin sewing the next row slightly above the previous one.', moves = {
                { a = 'hold', tool = 'hair', band = { 0.55, 0.75 } },
                { a = 'trace', geo = 'track:5', tool = 'hair', from = 2, limit = 1 },
                { a = 'sew', geo = 'track:5', tool = 'c_needle', stitches = 6, from = 2, limit = 1 } } },
            { text = 'Continue sewing tracks row-by-row upward until reaching the crown or closure, tie a triple knot, and cut the thread.', moves = {
                { a = 'trace', geo = 'track:5', tool = 'hair', from = 3 },
                { a = 'sew', geo = 'track:5', tool = 'c_needle', stitches = 5, from = 3 },
                { a = 'hold', tool = 'c_needle', band = { 0.6, 0.78 }, n = 3 },
                { a = 'dab', geo = 'point:crown', tool = 'shears', mark = 'snip' } } },
            -- PHASE 4: BLENDING & STYLING
            { phase = 'Blending & styling',
              text = 'Unclip any leave-out natural hair at the top, apply heat protectant, and flat-iron or curl it so it blends seamlessly over the top weft tracks.', opt = 'leaveout', moves = {
                { a = 'sweep', geo = 'zone:leave', tool = 'heat_protect' },
                { a = 'stroke', geo = 'strand:top:3:1.4', tool = 'flat_iron', n = 2, heat = true } } },
            { text = 'Trim/layer the ends with styling shears, lay baby hairs with edge control, and finish with shine spray.', uses = { 'edge_control', 'shine_spray' }, moves = {
                { a = 'dab', geo = 'points:ends:6:1.7', tool = 'shears', mark = 'snip' },
                { a = 'trace', geo = 'part:edges', tool = 'edge_brush' },
                { a = 'sweep', geo = 'zone:all', tool = 'shine_spray' } } },
        },
    },
}
