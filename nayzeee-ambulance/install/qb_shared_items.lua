--[[
    NAYZEEE AMBULANCE - QBCore shared items
    Built from config/items.lua. If you rename an item there, rename it here too.

    qb-core:   paste the entries into qb-core/shared/items.lua (QBShared.Items)
    qs-inventory / codem-inventory / tgiann-inventory / ps-inventory /
    lj-inventory use the same item format: paste into their item list.
    Copy html/img/items/*.png into the inventory image folder
    (qb-inventory/html/images, see install/README.md for the others).
]]

return {

    -- FIRST AID
    ['bandage'] = { name = 'bandage', label = 'Bandage', weight = 50, type = 'item', image = 'bandage.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Elastic roll for dressing cuts and slowing a bleed.' },
    ['foil_blanket'] = { name = 'foil_blanket', label = 'Foil Blanket', weight = 60, type = 'item', image = 'foil_blanket.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Keeps a patient warm and fights hypothermia.' },
    ['ice_pack'] = { name = 'ice_pack', label = 'Ice Pack', weight = 200, type = 'item', image = 'ice_pack.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Instant cold pack for sprains and swelling.' },
    ['medikit'] = { name = 'medikit', label = 'Medkit', weight = 600, type = 'item', image = 'medikit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Complete first-aid kit for patching yourself up.' },
    ['tourniquet'] = { name = 'tourniquet', label = 'Tourniquet', weight = 150, type = 'item', image = 'tourniquet.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Windlass strap that stops heavy bleeding from a limb.' },

    -- WOUND CARE
    ['burn_dressing'] = { name = 'burn_dressing', label = 'Burn Dressing', weight = 60, type = 'item', image = 'burn_dressing.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Sterile hydrogel dressing that cools and covers burns.' },
    ['gauze'] = { name = 'gauze', label = 'Gauze', weight = 20, type = 'item', image = 'gauze.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Sterile gauze for packing wounds and soaking up blood.' },
    ['iodine_swab'] = { name = 'iodine_swab', label = 'Iodine Swab', weight = 10, type = 'item', image = 'iodine_swab.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Antiseptic swab to disinfect skin before cutting.' },
    ['sterile_dressing'] = { name = 'sterile_dressing', label = 'Sterile Dressing', weight = 40, type = 'item', image = 'sterile_dressing.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Adhesive sterile dressing for closed wounds.' },
    ['suture_kit'] = { name = 'suture_kit', label = 'Suture Kit', weight = 120, type = 'item', image = 'suture_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Needle, thread and tools to close a wound.' },

    -- MEDICATION
    ['adrenaline'] = { name = 'adrenaline', label = 'Adrenaline 1 mg', weight = 20, type = 'item', image = 'adrenaline.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For cardiac arrest, every 3-5 minutes.' },
    ['antibiotics'] = { name = 'antibiotics', label = 'Antibiotics', weight = 30, type = 'item', image = 'antibiotics.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Treats and prevents wound infection.' },
    ['lidocaine'] = { name = 'lidocaine', label = 'Lidocaine 2%', weight = 30, type = 'item', image = 'lidocaine.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Local anaesthetic for numbing a wound.' },
    ['morphine'] = { name = 'morphine', label = 'Morphine', weight = 20, type = 'item', image = 'morphine.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Strong pain relief. Watch the breathing.' },
    ['naloxone'] = { name = 'naloxone', label = 'Naloxone', weight = 20, type = 'item', image = 'naloxone.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Reverses opioid overdose.' },
    ['painkillers'] = { name = 'painkillers', label = 'Painkillers', weight = 30, type = 'item', image = 'painkillers.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Fast-acting pain relief tablets.' },
    ['txa'] = { name = 'txa', label = 'TXA 1 g', weight = 30, type = 'item', image = 'txa.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Tranexamic acid. Helps clots hold.' },

    -- FLUIDS
    ['blood_bag'] = { name = 'blood_bag', label = 'Blood Bag', weight = 550, type = 'item', image = 'blood_bag.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A labelled unit of donated blood.' },
    ['empty_blood_bag'] = { name = 'empty_blood_bag', label = 'Empty Blood Bag', weight = 40, type = 'item', image = 'empty_blood_bag.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Collection bag for blood donation.' },
    ['io_kit'] = { name = 'io_kit', label = 'IO Needle Set', weight = 60, type = 'item', image = 'io_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Needle set for the intraosseous drill.' },
    ['iv_kit'] = { name = 'iv_kit', label = 'IV Kit', weight = 80, type = 'item', image = 'iv_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Cannula, line and fittings for IV access.' },
    ['saline'] = { name = 'saline', label = 'Saline', weight = 250, type = 'item', image = 'saline.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Sterile 0.9% saline for flushing wounds.' },
    ['saline_bag'] = { name = 'saline_bag', label = 'Saline 500 ml', weight = 550, type = 'item', image = 'saline_bag.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Bag of 0.9% saline for infusion.' },

    -- ORTHOPEDIC
    ['cervical_collar'] = { name = 'cervical_collar', label = 'Cervical Collar', weight = 300, type = 'item', image = 'cervical_collar.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Keeps the neck still after a spinal injury.' },
    ['crutches'] = { name = 'crutches', label = 'Crutches', weight = 1500, type = 'item', image = 'crutches.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Walk with a broken leg.' },
    ['pelvic_binder'] = { name = 'pelvic_binder', label = 'Pelvic Binder', weight = 700, type = 'item', image = 'pelvic_binder.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Compresses a broken pelvis to slow internal bleeding.' },
    ['plaster_cast'] = { name = 'plaster_cast', label = 'Plaster Cast', weight = 500, type = 'item', image = 'plaster_cast.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Hospital cast for a set fracture.' },
    ['splint'] = { name = 'splint', label = 'Splint', weight = 400, type = 'item', image = 'splint.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Mouldable splint for a broken arm or leg.' },

    -- AIRWAY
    ['bvm'] = { name = 'bvm', label = 'Bag Valve Mask', weight = 400, type = 'item', image = 'bvm.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Breathe for a patient during CPR.' },
    ['decompression_needle'] = { name = 'decompression_needle', label = 'Decompression Needle', weight = 30, type = 'item', image = 'decompression_needle.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Relieves a tension pneumothorax.' },
    ['intubation_kit'] = { name = 'intubation_kit', label = 'Intubation Kit', weight = 700, type = 'item', image = 'intubation_kit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Video laryngoscope, tube and cuff syringe.' },
    ['oxygen_mask'] = { name = 'oxygen_mask', label = 'Oxygen Mask', weight = 300, type = 'item', image = 'oxygen_mask.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'High-flow oxygen for low saturation.' },

    -- SURGERY
    ['angio_kit'] = { name = 'angio_kit', label = 'Angiography Kit', weight = 500, type = 'item', image = 'angio_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Sheath, guide wire and catheter.' },
    ['chest_drain_kit'] = { name = 'chest_drain_kit', label = 'Chest Drain Kit', weight = 600, type = 'item', image = 'chest_drain_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Scalpel, clamp and tube to drain the chest.' },
    ['contrast_dye'] = { name = 'contrast_dye', label = 'Contrast Dye', weight = 120, type = 'item', image = 'contrast_dye.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Shows vessels on the fluoroscopy screen.' },
    ['embolization_coil'] = { name = 'embolization_coil', label = 'Embolization Coil', weight = 20, type = 'item', image = 'embolization_coil.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Plugs a bleeding vessel from the inside.' },
    ['graft_kit'] = { name = 'graft_kit', label = 'Skin Graft Kit', weight = 1200, type = 'item', image = 'graft_kit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Dermatome, mesher and skin stapler.' },
    ['surgical_kit'] = { name = 'surgical_kit', label = 'Surgical Kit', weight = 900, type = 'item', image = 'surgical_kit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Probe, scalpel, forceps and suction for removing projectiles.' },

    -- EQUIPMENT
    ['bodybag'] = { name = 'bodybag', label = 'Body Bag', weight = 1200, type = 'item', image = 'bodybag.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For transporting the deceased to the morgue.' },
    ['defibrillator'] = { name = 'defibrillator', label = 'Defibrillator', weight = 2500, type = 'item', image = 'defibrillator.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Portable monitor and defibrillator.' },
    ['ems_pager'] = { name = 'ems_pager', label = 'EMS Pager', weight = 100, type = 'item', image = 'ems_pager.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Receives dispatch calls. Pair it with your phone.' },
    ['medbag'] = { name = 'medbag', label = 'Medical Bag', weight = 1500, type = 'item', image = 'medbag.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Rolling bag that stores your supplies on scene.' },
    ['stethoscope'] = { name = 'stethoscope', label = 'Stethoscope', weight = 200, type = 'item', image = 'stethoscope.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Listen to the heart and lungs.' },
    ['trauma_kit'] = { name = 'trauma_kit', label = 'Trauma Kit', weight = 6000, type = 'item', image = 'trauma_kit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Field resuscitation case: monitor, binder, IO drill, IV stand.' },
    ['wheelchair'] = { name = 'wheelchair', label = 'Wheelchair', weight = 8000, type = 'item', image = 'wheelchair.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Folding wheelchair.' },

    -- DOCUMENTS
    ['insurance_card'] = { name = 'insurance_card', label = 'Insurance Card', weight = 1, type = 'item', image = 'insurance_card.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Proof of health insurance.' },
    ['triage_ticket'] = { name = 'triage_ticket', label = 'Queue Pass', weight = 1, type = 'item', image = 'triage_ticket.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Hospital queue pass. The waiting-area board calls its code.' },
    ['xray_film'] = { name = 'xray_film', label = 'X-ray Film', weight = 50, type = 'item', image = 'xray_film.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Read it on a lightbox.' },
}
