--[[
    NAYZEEE AMBULANCE - Constants

    Body regions, injury types, conditions, blood types, heart rhythms, permission keys
    and the GTA bone → region map. These are facts the whole resource agrees on; tuning
    numbers live in config/*.lua.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Const = NZA.Const or {}
local C = NZA.Const

-- ════════════════════════════════════════════════════════════════════════
-- BODY REGIONS (15)
-- group  = one of the 8 groups on the examination body map
-- xray   = which X-ray view shows this region
-- lethal = how dangerous wounds here are (scales bleed + arrest risk)
-- ════════════════════════════════════════════════════════════════════════

C.Regions = {
    { name = 'head',        label = 'Head',            group = 'head',    side = nil, limb = false, xray = 'head',    lethal = 1.6, tourniquet = false, splint = false },
    { name = 'face',        label = 'Face',            group = 'head',    side = nil, limb = false, xray = 'head',    lethal = 1.1, tourniquet = false, splint = false },
    { name = 'neck',        label = 'Neck',            group = 'neck',    side = nil, limb = false, xray = 'neck',    lethal = 1.7, tourniquet = false, splint = 'collar' },
    { name = 'chest',       label = 'Chest',           group = 'chest',   side = nil, limb = false, xray = 'chest',   lethal = 1.5, tourniquet = false, splint = false },
    { name = 'back',        label = 'Back',            group = 'chest',   side = nil, limb = false, xray = 'chest',   lethal = 1.2, tourniquet = false, splint = false },
    { name = 'abdomen',     label = 'Abdomen',         group = 'abdomen', side = nil, limb = false, xray = 'abdomen', lethal = 1.4, tourniquet = false, splint = false },
    { name = 'pelvis',      label = 'Pelvis',          group = 'abdomen', side = nil, limb = false, xray = 'abdomen', lethal = 1.3, tourniquet = false, splint = 'binder' },
    { name = 'l_upper_arm', label = 'Left upper arm',  group = 'l_arm',   side = 'l', limb = 'arm', xray = 'l_arm',   lethal = 0.8, tourniquet = true,  splint = 'arm' },
    { name = 'l_lower_arm', label = 'Left forearm',    group = 'l_arm',   side = 'l', limb = 'arm', xray = 'l_arm',   lethal = 0.6, tourniquet = true,  splint = 'arm' },
    { name = 'r_upper_arm', label = 'Right upper arm', group = 'r_arm',   side = 'r', limb = 'arm', xray = 'r_arm',   lethal = 0.8, tourniquet = true,  splint = 'arm' },
    { name = 'r_lower_arm', label = 'Right forearm',   group = 'r_arm',   side = 'r', limb = 'arm', xray = 'r_arm',   lethal = 0.6, tourniquet = true,  splint = 'arm' },
    { name = 'l_upper_leg', label = 'Left thigh',      group = 'l_leg',   side = 'l', limb = 'leg', xray = 'l_leg',   lethal = 1.0, tourniquet = true,  splint = 'leg' },
    { name = 'l_lower_leg', label = 'Left lower leg',  group = 'l_leg',   side = 'l', limb = 'leg', xray = 'l_leg',   lethal = 0.6, tourniquet = true,  splint = 'leg' },
    { name = 'r_upper_leg', label = 'Right thigh',     group = 'r_leg',   side = 'r', limb = 'leg', xray = 'r_leg',   lethal = 1.0, tourniquet = true,  splint = 'leg' },
    { name = 'r_lower_leg', label = 'Right lower leg', group = 'r_leg',   side = 'r', limb = 'leg', xray = 'r_leg',   lethal = 0.6, tourniquet = true,  splint = 'leg' },
}

C.Region = {}
for i, r in ipairs(C.Regions) do
    r.index = i
    C.Region[r.name] = r
end

-- The 8 groups shown on the examination body map, in display order
C.Groups = {
    { name = 'head',    label = 'Head',      regions = { 'head', 'face' } },
    { name = 'neck',    label = 'Neck',      regions = { 'neck' } },
    { name = 'chest',   label = 'Chest',     regions = { 'chest', 'back' } },
    { name = 'abdomen', label = 'Abdomen',   regions = { 'abdomen', 'pelvis' } },
    { name = 'l_arm',   label = 'Left Arm',  regions = { 'l_upper_arm', 'l_lower_arm' } },
    { name = 'r_arm',   label = 'Right Arm', regions = { 'r_upper_arm', 'r_lower_arm' } },
    { name = 'l_leg',   label = 'Left Leg',  regions = { 'l_upper_leg', 'l_lower_leg' } },
    { name = 'r_leg',   label = 'Right Leg', regions = { 'r_upper_leg', 'r_lower_leg' } },
}
C.Group = {}
for _, g in ipairs(C.Groups) do C.Group[g.name] = g end

-- The 8 X-ray views
C.XrayViews = { 'head', 'neck', 'chest', 'abdomen', 'l_arm', 'r_arm', 'l_leg', 'r_leg' }

-- ════════════════════════════════════════════════════════════════════════
-- GTA PED BONE → REGION
-- Spine2/3 hits are 'chest' from the front and 'back' from behind; the damage
-- code flips them using the attacker direction.
-- ════════════════════════════════════════════════════════════════════════

C.BoneToRegion = {
    [31086] = 'head',  [12844] = 'head',  [65068] = 'face',  [39317] = 'neck',  [35731] = 'neck',
    [24818] = 'chest', [24817] = 'chest', [64729] = 'chest', [10706] = 'chest',
    [24816] = 'abdomen', [23553] = 'abdomen', [57597] = 'pelvis', [11816] = 'pelvis', [0] = 'abdomen',
    [45509] = 'l_upper_arm', [5232] = 'l_upper_arm', [22711] = 'l_upper_arm',
    [61163] = 'l_lower_arm', [61007] = 'l_lower_arm', [18905] = 'l_lower_arm', [36029] = 'l_lower_arm', [60309] = 'l_lower_arm',
    [26610] = 'l_lower_arm', [4089] = 'l_lower_arm', [4090] = 'l_lower_arm', [26611] = 'l_lower_arm', [26612] = 'l_lower_arm',
    [40269] = 'r_upper_arm', [37119] = 'r_upper_arm', [2992] = 'r_upper_arm',
    [28252] = 'r_lower_arm', [43810] = 'r_lower_arm', [57005] = 'r_lower_arm', [6286] = 'r_lower_arm', [28422] = 'r_lower_arm',
    [58866] = 'r_lower_arm', [64016] = 'r_lower_arm', [64017] = 'r_lower_arm', [58867] = 'r_lower_arm', [58868] = 'r_lower_arm',
    [58271] = 'l_upper_leg', [23639] = 'l_upper_leg', [46078] = 'l_lower_leg',
    [63931] = 'l_lower_leg', [14201] = 'l_lower_leg', [2108] = 'l_lower_leg', [57717] = 'l_lower_leg', [65245] = 'l_lower_leg',
    [51826] = 'r_upper_leg', [6442] = 'r_upper_leg', [16335] = 'r_lower_leg',
    [36864] = 'r_lower_leg', [52301] = 'r_lower_leg', [20781] = 'r_lower_leg', [24806] = 'r_lower_leg', [35502] = 'r_lower_leg',
}

-- Bone to attach things to / aim cameras at, per region
C.RegionBone = {
    head = 31086, face = 31086, neck = 39317, chest = 24818, back = 24818, abdomen = 23553, pelvis = 11816,
    l_upper_arm = 45509, l_lower_arm = 61163, r_upper_arm = 40269, r_lower_arm = 28252,
    l_upper_leg = 58271, l_lower_leg = 63931, r_upper_leg = 51826, r_lower_leg = 36864,
}

-- Joints at each end of a limb segment (proximal → distal), used by the splint minigame
C.LimbJoints = {
    l_upper_arm = { 45509, 61163 }, l_lower_arm = { 61163, 18905 },
    r_upper_arm = { 40269, 28252 }, r_lower_arm = { 28252, 57005 },
    l_upper_leg = { 58271, 63931 }, l_lower_leg = { 63931, 14201 },
    r_upper_leg = { 51826, 36864 }, r_lower_leg = { 36864, 52301 },
}

-- ════════════════════════════════════════════════════════════════════════
-- INJURY TYPES (9)
-- bleed = base mL/min by severity 1..4, pain = base pain by severity 1..4
-- ════════════════════════════════════════════════════════════════════════

C.InjuryTypes = {
    gunshot    = { label = 'Gunshot wound',      short = 'GSW',        icon = 'crosshair', bleed = { 12, 40, 110, 240 }, pain = { 45, 60, 75, 90 }, retained = 0.55, contamination = 30 },
    shrapnel   = { label = 'Shrapnel wound',     short = 'Shrapnel',   icon = 'burst',     bleed = { 6, 20, 60, 140 },   pain = { 35, 50, 65, 80 }, retained = 0.85, contamination = 55 },
    stab       = { label = 'Stab wound',         short = 'Stab',       icon = 'knife',     bleed = { 10, 35, 90, 200 },  pain = { 40, 55, 70, 85 }, retained = 0,    contamination = 25 },
    laceration = { label = 'Deep laceration',    short = 'Laceration', icon = 'cut',       bleed = { 2, 6, 18, 45 },     pain = { 20, 35, 50, 65 }, retained = 0,    contamination = 45 },
    abrasion   = { label = 'Abrasion',           short = 'Abrasion',   icon = 'scrape',    bleed = { 0.5, 1.5, 4, 8 },   pain = { 15, 25, 35, 45 }, retained = 0,    contamination = 70 },
    contusion  = { label = 'Contusion',          short = 'Contusion',  icon = 'bruise',    bleed = { 0, 0, 0, 0 },       pain = { 15, 25, 40, 55 }, retained = 0,    contamination = 0 },
    fracture   = { label = 'Fracture',           short = 'Fracture',   icon = 'bone',      bleed = { 0, 2, 15, 60 },     pain = { 50, 65, 80, 95 }, retained = 0,    contamination = 0 },
    burn       = { label = 'Burn',               short = 'Burn',       icon = 'flame',     bleed = { 0, 0.5, 2, 5 },     pain = { 40, 60, 80, 70 }, retained = 0,    contamination = 40 },
    internal   = { label = 'Internal bleeding',  short = 'Internal',   icon = 'drop',      bleed = { 20, 60, 140, 260 }, pain = { 30, 45, 60, 70 }, retained = 0,    contamination = 0 },
}
C.InjuryOrder = { 'gunshot', 'shrapnel', 'stab', 'laceration', 'abrasion', 'contusion', 'fracture', 'burn', 'internal' }
C.SeverityLabel = { 'Minor', 'Moderate', 'Serious', 'Critical' }

-- ════════════════════════════════════════════════════════════════════════
-- CONDITIONS (whole-body problems, not tied to a single wound)
-- ════════════════════════════════════════════════════════════════════════

C.Conditions = {
    haemothorax  = { label = 'Haemothorax',        fix = 'chestdrain' },  -- { side = 'left'|'right', ml = 0.. }
    pneumothorax = { label = 'Pneumothorax',       fix = 'chestdrain' },  -- { side, tension = bool }
    tamponade    = { label = 'Cardiac tamponade',  fix = 'pericardio' },  -- { ml }
    concussion   = { label = 'Concussion',         fix = 'rest' },        -- { grade = 1..3 }
    hypoxia      = { label = 'Hypoxia',            fix = 'airway' },      -- { cause = 'drowning'|'smoke'|'airway', water = mL }
    airway       = { label = 'Airway compromise',  fix = 'airway' },      -- { kind = 'obstructed'|'swelling'|'unconscious' }
    overdose     = { label = 'Overdose',           fix = 'meds' },        -- { drug = 'opioid'|'stimulant'|'alcohol', amount = 0..100 }
    arrest       = { label = 'Cardiac arrest',     fix = 'cpr' },         -- { rhythm, since }
    hypothermia  = { label = 'Hypothermia',        fix = 'warm' },        -- { temp }
    infection    = { label = 'Wound infection',    fix = 'meds' },        -- { region, level }
    spinal       = { label = 'Spinal injury',      fix = 'collar' },      -- { level = 'cervical'|'thoracic' }
}

-- ════════════════════════════════════════════════════════════════════════
-- BLOOD TYPES
-- ════════════════════════════════════════════════════════════════════════

C.BloodTypes = { 'O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+' }
C.BloodFrequency = { ['O+'] = 38, ['A+'] = 34, ['B+'] = 9, ['O-'] = 7, ['A-'] = 6, ['AB+'] = 3, ['B-'] = 2, ['AB-'] = 1 }
-- canReceive[recipient][donor] = true
C.CanReceive = {
    ['O-']  = { ['O-'] = true },
    ['O+']  = { ['O-'] = true, ['O+'] = true },
    ['A-']  = { ['O-'] = true, ['A-'] = true },
    ['A+']  = { ['O-'] = true, ['O+'] = true, ['A-'] = true, ['A+'] = true },
    ['B-']  = { ['O-'] = true, ['B-'] = true },
    ['B+']  = { ['O-'] = true, ['O+'] = true, ['B-'] = true, ['B+'] = true },
    ['AB-'] = { ['O-'] = true, ['A-'] = true, ['B-'] = true, ['AB-'] = true },
    ['AB+'] = { ['O-'] = true, ['O+'] = true, ['A-'] = true, ['A+'] = true, ['B-'] = true, ['B+'] = true, ['AB-'] = true, ['AB+'] = true },
}

-- ════════════════════════════════════════════════════════════════════════
-- HEART RHYTHMS
-- ════════════════════════════════════════════════════════════════════════

C.Rhythms = {
    sinus    = { label = 'Sinus rhythm',          short = 'SINUS' },
    stach    = { label = 'Sinus tachycardia',     short = 'S.TACH' },
    sbrady   = { label = 'Sinus bradycardia',     short = 'S.BRADY' },
    afib     = { label = 'Atrial fibrillation',   short = 'AFIB' },
    vf       = { label = 'Ventricular fibrillation', short = 'VF' },
    vt       = { label = 'Pulseless VT',          short = 'VT' },
    pea      = { label = 'PEA',                   short = 'PEA' },
    asystole = { label = 'Asystole',              short = 'ASYSTOLE' },
}
C.Shockable = { vf = true, vt = true }

-- ════════════════════════════════════════════════════════════════════════
-- STATES, TRIAGE, AVPU
-- ════════════════════════════════════════════════════════════════════════

C.States = { alive = true, wounded = true, arrest = true, dead = true }
C.Triage = {
    [1] = { code = 'P1', label = 'Critical', colour = '#e5484d' },
    [2] = { code = 'P2', label = 'Urgent',   colour = '#e5a50a' },
    [3] = { code = 'P3', label = 'Standard', colour = '#08afa2' },
}
C.AVPU = { A = 'Alert', V = 'Responds to voice', P = 'Responds to pain', U = 'Unresponsive' }

-- ════════════════════════════════════════════════════════════════════════
-- PERMISSIONS (department grades grant these)
-- ════════════════════════════════════════════════════════════════════════

C.Perms = {
    { key = 'assess',     label = 'Assess patients',            desc = 'Examine, pulse, breathing, stethoscope' },
    { key = 'basic',      label = 'Basic first aid',            desc = 'Bandage, tourniquet, ice pack, painkillers' },
    { key = 'cpr',        label = 'CPR',                        desc = 'Chest compressions and rescue breaths' },
    { key = 'defib',      label = 'Defibrillator',              desc = 'Analyse rhythm and shock' },
    { key = 'iv',         label = 'IV / IO access',             desc = 'Cannulas, IO drill, fluids' },
    { key = 'blood',      label = 'Blood products',             desc = 'Transfusions and the blood bank' },
    { key = 'binder',     label = 'Pelvic binder',              desc = 'Field resuscitation of pelvic bleeds' },
    { key = 'splint',     label = 'Splints & collars',          desc = 'Splint fractures, cervical collar' },
    { key = 'suture',     label = 'Wound closure',              desc = 'Irrigate, anaesthetise, suture, dress' },
    { key = 'burn',       label = 'Burn care',                  desc = 'Cool, debride and dress burns' },
    { key = 'graft',      label = 'Skin grafts',                desc = 'Dermatome, mesh and staple grafts' },
    { key = 'airway',     label = 'Airway',                     desc = 'BVM, oxygen and intubation' },
    { key = 'ultrasound', label = 'Ultrasound',                 desc = 'eFAST scans' },
    { key = 'chestdrain', label = 'Chest drain',                desc = 'Drain haemo/pneumothorax' },
    { key = 'pericardio', label = 'Pericardiocentesis',         desc = 'Drain cardiac tamponade' },
    { key = 'xray',       label = 'Radiology',                  desc = 'Take and read X-rays' },
    { key = 'surgery',    label = 'Surgery',                    desc = 'Bullet and fragment extraction' },
    { key = 'angio',      label = 'Angiography',                desc = 'Find and coil internal bleeds' },
    { key = 'meds',       label = 'Medication',                 desc = 'Morphine, adrenaline, naloxone, antibiotics' },
    { key = 'transport',  label = 'Transport',                  desc = 'Stretcher, wheelchair, ambulance bay' },
    { key = 'bodybag',    label = 'Body bags & morgue',         desc = 'Bag and process the deceased' },
    { key = 'checkin',    label = 'Front desk',                 desc = 'Process check-in tickets' },
    { key = 'pharmacy',   label = 'Pharmacy staff',             desc = 'Restock and run the pharmacy' },
    { key = 'manage',     label = 'Department manager',         desc = 'Staff, grades, permissions, easy mode' },
}
C.Perm = {}
for _, p in ipairs(C.Perms) do C.Perm[p.key] = p end

-- ════════════════════════════════════════════════════════════════════════
-- DISPATCH STATUSES (pager chain)
-- ════════════════════════════════════════════════════════════════════════

C.CallStatus = {
    { code = 'DSP', label = 'Dispatched' },
    { code = 'ENR', label = 'En route' },
    { code = 'SCN', label = 'On scene' },
    { code = 'TRN', label = 'Transporting' },
    { code = 'HSP', label = 'At hospital' },
}
