--[[
    NAYZEEE AMBULANCE - Items

    Config.Items maps the key the script uses → the item name in your inventory.
    Rename an item here if your server already has it under another name
    (e.g. Config.Items.bandage = 'firstaid_bandage'). Never edit the keys.

    Config.ItemDefs is used to build the install files in install/
    (ox_inventory, qb-core shared items, ESX SQL). Images are in html/img/items/.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Items = {
    -- first aid
    bandage          = 'bandage',
    gauze            = 'gauze',
    tourniquet       = 'tourniquet',
    ice_pack         = 'ice_pack',
    medkit           = 'medikit',
    painkillers      = 'painkillers',
    burn_dressing    = 'burn_dressing',
    dressing         = 'sterile_dressing',
    foil_blanket     = 'foil_blanket',

    -- wound care & surgery
    suture_kit       = 'suture_kit',
    saline           = 'saline',             -- 0.9% saline syringe / bottle for irrigation
    lidocaine        = 'lidocaine',
    iodine           = 'iodine_swab',
    surgical_kit     = 'surgical_kit',       -- probe, scalpel, forceps, suction
    graft_kit        = 'graft_kit',          -- dermatome, mesher, stapler

    -- fluids & IV
    iv_kit           = 'iv_kit',             -- cannula, line and fittings
    io_kit           = 'io_kit',             -- IO needle set for the drill
    saline_bag       = 'saline_bag',         -- 500 ml bag for infusion
    blood_bag        = 'blood_bag',          -- metadata: type, ml, serial, donor, expires
    empty_blood_bag  = 'empty_blood_bag',
    txa              = 'txa',

    -- medication
    morphine         = 'morphine',
    adrenaline       = 'adrenaline',
    naloxone         = 'naloxone',
    antibiotics      = 'antibiotics',

    -- orthopedic
    splint           = 'splint',
    cervical_collar  = 'cervical_collar',
    pelvic_binder    = 'pelvic_binder',
    cast             = 'plaster_cast',

    -- airway & chest
    bvm              = 'bvm',
    oxygen_mask      = 'oxygen_mask',
    intubation_kit   = 'intubation_kit',
    chest_drain_kit  = 'chest_drain_kit',
    decomp_needle    = 'decompression_needle',

    -- angiography
    angio_kit        = 'angio_kit',          -- sheath, wire, catheter
    contrast         = 'contrast_dye',
    coil             = 'embolization_coil',

    -- equipment
    stethoscope      = 'stethoscope',
    defibrillator    = 'defibrillator',
    trauma_kit       = 'trauma_kit',         -- field resuscitation case (monitor, binder, IO drill, IV stand)
    pager            = 'ems_pager',
    medbag           = 'medbag',
    wheelchair       = 'wheelchair',
    crutches         = 'crutches',
    bodybag          = 'bodybag',

    -- documents
    xray_film        = 'xray_film',          -- metadata: patient, region, findings, taken
    triage_ticket    = 'triage_ticket',
    insurance_card   = 'insurance_card',
}

-- category: first_aid | medication | wound_care | fluids | orthopedic | equipment | airway | surgery | documents
Config.ItemDefs = {
    bandage         = { label = 'Bandage',             weight = 50,   stack = true,  category = 'first_aid',  description = 'Elastic roll for dressing cuts and slowing a bleed.' },
    gauze           = { label = 'Gauze',               weight = 20,   stack = true,  category = 'wound_care', description = 'Sterile gauze for packing wounds and soaking up blood.' },
    tourniquet      = { label = 'Tourniquet',          weight = 150,  stack = true,  category = 'first_aid',  description = 'Windlass strap that stops heavy bleeding from a limb.' },
    ice_pack        = { label = 'Ice Pack',            weight = 200,  stack = true,  category = 'first_aid',  description = 'Instant cold pack for sprains and swelling.' },
    medkit          = { label = 'Medkit',              weight = 600,  stack = true,  category = 'first_aid',  description = 'Complete first-aid kit for patching yourself up.' },
    painkillers     = { label = 'Painkillers',         weight = 30,   stack = true,  category = 'medication', description = 'Fast-acting pain relief tablets.' },
    burn_dressing   = { label = 'Burn Dressing',       weight = 60,   stack = true,  category = 'wound_care', description = 'Sterile hydrogel dressing that cools and covers burns.' },
    dressing        = { label = 'Sterile Dressing',    weight = 40,   stack = true,  category = 'wound_care', description = 'Adhesive sterile dressing for closed wounds.' },
    foil_blanket    = { label = 'Foil Blanket',        weight = 60,   stack = true,  category = 'first_aid',  description = 'Keeps a patient warm and fights hypothermia.' },
    suture_kit      = { label = 'Suture Kit',          weight = 120,  stack = true,  category = 'wound_care', description = 'Needle, thread and tools to close a wound.' },
    saline          = { label = 'Saline',              weight = 250,  stack = true,  category = 'fluids',     description = 'Sterile 0.9% saline for flushing wounds.' },
    lidocaine       = { label = 'Lidocaine 2%',        weight = 30,   stack = true,  category = 'medication', description = 'Local anaesthetic for numbing a wound.' },
    iodine          = { label = 'Iodine Swab',         weight = 10,   stack = true,  category = 'wound_care', description = 'Antiseptic swab to disinfect skin before cutting.' },
    surgical_kit    = { label = 'Surgical Kit',        weight = 900,  stack = false, category = 'surgery',    description = 'Probe, scalpel, forceps and suction for removing projectiles.' },
    graft_kit       = { label = 'Skin Graft Kit',      weight = 1200, stack = false, category = 'surgery',    description = 'Dermatome, mesher and skin stapler.' },
    iv_kit          = { label = 'IV Kit',              weight = 80,   stack = true,  category = 'fluids',     description = 'Cannula, line and fittings for IV access.' },
    io_kit          = { label = 'IO Needle Set',       weight = 60,   stack = true,  category = 'fluids',     description = 'Needle set for the intraosseous drill.' },
    saline_bag      = { label = 'Saline 500 ml',       weight = 550,  stack = true,  category = 'fluids',     description = 'Bag of 0.9% saline for infusion.' },
    blood_bag       = { label = 'Blood Bag',           weight = 550,  stack = false, category = 'fluids',     description = 'A labelled unit of donated blood.' },
    empty_blood_bag = { label = 'Empty Blood Bag',     weight = 40,   stack = true,  category = 'fluids',     description = 'Collection bag for blood donation.' },
    txa             = { label = 'TXA 1 g',             weight = 30,   stack = true,  category = 'medication', description = 'Tranexamic acid. Helps clots hold.' },
    morphine        = { label = 'Morphine',            weight = 20,   stack = true,  category = 'medication', description = 'Strong pain relief. Watch the breathing.' },
    adrenaline      = { label = 'Adrenaline 1 mg',     weight = 20,   stack = true,  category = 'medication', description = 'For cardiac arrest, every 3-5 minutes.' },
    naloxone        = { label = 'Naloxone',            weight = 20,   stack = true,  category = 'medication', description = 'Reverses opioid overdose.' },
    antibiotics     = { label = 'Antibiotics',         weight = 30,   stack = true,  category = 'medication', description = 'Treats and prevents wound infection.' },
    splint          = { label = 'Splint',              weight = 400,  stack = true,  category = 'orthopedic', description = 'Mouldable splint for a broken arm or leg.' },
    cervical_collar = { label = 'Cervical Collar',     weight = 300,  stack = true,  category = 'orthopedic', description = 'Keeps the neck still after a spinal injury.' },
    pelvic_binder   = { label = 'Pelvic Binder',       weight = 700,  stack = true,  category = 'orthopedic', description = 'Compresses a broken pelvis to slow internal bleeding.' },
    cast            = { label = 'Plaster Cast',        weight = 500,  stack = true,  category = 'orthopedic', description = 'Hospital cast for a set fracture.' },
    bvm             = { label = 'Bag Valve Mask',      weight = 400,  stack = false, category = 'airway',     description = 'Breathe for a patient during CPR.' },
    oxygen_mask     = { label = 'Oxygen Mask',         weight = 300,  stack = true,  category = 'airway',     description = 'High-flow oxygen for low saturation.' },
    intubation_kit  = { label = 'Intubation Kit',      weight = 700,  stack = false, category = 'airway',     description = 'Video laryngoscope, tube and cuff syringe.' },
    chest_drain_kit = { label = 'Chest Drain Kit',     weight = 600,  stack = true,  category = 'surgery',    description = 'Scalpel, clamp and tube to drain the chest.' },
    decomp_needle   = { label = 'Decompression Needle',weight = 30,   stack = true,  category = 'airway',     description = 'Relieves a tension pneumothorax.' },
    angio_kit       = { label = 'Angiography Kit',     weight = 500,  stack = true,  category = 'surgery',    description = 'Sheath, guide wire and catheter.' },
    contrast        = { label = 'Contrast Dye',        weight = 120,  stack = true,  category = 'surgery',    description = 'Shows vessels on the fluoroscopy screen.' },
    coil            = { label = 'Embolization Coil',   weight = 20,   stack = true,  category = 'surgery',    description = 'Plugs a bleeding vessel from the inside.' },
    stethoscope     = { label = 'Stethoscope',         weight = 200,  stack = false, category = 'equipment',  description = 'Listen to the heart and lungs.' },
    defibrillator   = { label = 'Defibrillator',       weight = 2500, stack = false, category = 'equipment',  description = 'Portable monitor and defibrillator.' },
    trauma_kit      = { label = 'Trauma Kit',          weight = 6000, stack = false, category = 'equipment',  description = 'Field resuscitation case: monitor, binder, IO drill, IV stand.' },
    pager           = { label = 'EMS Pager',           weight = 100,  stack = false, category = 'equipment',  description = 'Receives dispatch calls. Pair it with your phone.' },
    medbag          = { label = 'Medical Bag',         weight = 1500, stack = false, category = 'equipment',  description = 'Rolling bag that stores your supplies on scene.' },
    wheelchair      = { label = 'Wheelchair',          weight = 8000, stack = false, category = 'equipment',  description = 'Folding wheelchair.' },
    crutches        = { label = 'Crutches',            weight = 1500, stack = false, category = 'orthopedic', description = 'Walk with a broken leg.' },
    bodybag         = { label = 'Body Bag',            weight = 1200, stack = true,  category = 'equipment',  description = 'For transporting the deceased to the morgue.' },
    xray_film       = { label = 'X-ray Film',          weight = 50,   stack = false, category = 'documents',  description = 'Read it on a lightbox.' },
    triage_ticket   = { label = 'Queue Pass',          weight = 1,    stack = false, category = 'documents',  description = 'Hospital queue pass. The waiting-area board calls its code.' },
    insurance_card  = { label = 'Insurance Card',      weight = 1,    stack = false, category = 'documents',  description = 'Proof of health insurance.' },
}
