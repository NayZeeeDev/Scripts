--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - PHARMACY, HEALTH INSURANCE & BILLING
    Discord: discord.gg/nayzeeedev

    Pharmacies are placed in game: /nzadmin → a department → Positions → Pharmacy.
    Every pharmacy position can have a pharmacist NPC (toggle it in the position editor).

    The pharmacy window has:
      Shop        the catalogue below (categories, search, cart, cash / bank)
      Insurance   buy / renew / switch a health insurance plan (gives an insurance card)
      Bills       medical bills the player could not pay at the time
      Stock/Sales staff with the 'pharmacy' permission: shelf levels, ordering and the sales log

    Billing (NZA.Billing.Charge) is used by every treatment, transport and respawn fee:
    insurance pays its share, the rest comes from the bank (or cash), the department
    society gets the money and the medic who treated gets Config.Billing.medicCut.
    When the patient can't pay, an unpaid bill is stored and paid later at a pharmacy.

    Item names are in config/items.lua (Config.Items). Text is in locales/en/pharmacy.lua.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Pharmacy = {

    enabled = true,

    -- ═══════════════════════════════════════════════════════════════════════
    -- POSITIONS (the 'pharmacy' point type)
    -- ═══════════════════════════════════════════════════════════════════════

    interact = {
        target   = true,      -- target option on the pharmacy position (ox_target, qb-target, ... or the built-in [E])
        prompt   = true,      -- our own "[E] Pharmacy" prompt when you stand at the counter (skipped when the
                              -- bridge already shows its built-in [E] prompt, so you never see two)
        key      = 38,        -- control for the prompt (38 = E)
        keyLabel = 'E',       -- what the prompt shows
        distance = 2.0,       -- metres from the position to open the pharmacy
        maxDistance = 4.0,    -- the window closes when you walk further than this
    },

    -- Check-in desks (placed by the check-in module) also take payments: "[H] Pay medical bills".
    -- The window opens in desk mode there (Bills + Insurance, no shop).
    desk = {
        enabled       = true,   -- show the prompt at check-in desks
        onlyWithBills = true,   -- only when the player has open bills (false = always, for insurance too)
        key           = 74,     -- control for the prompt (74 = H)
        keyLabel      = 'H',    -- what the prompt shows
        distance      = 2.6,    -- metres from the desk
    },

    -- Defaults for new positions (each position can change them in the position editor).
    pointDefaults = {
        npc       = true,     -- spawn a pharmacist NPC at the position
        staffOnly = false,    -- only on-duty members of the department can use it (staff supply counter)
        blip      = true,     -- map blip for this position
        insurance = true,     -- sell health insurance here
        bills     = true,     -- pay open bills here
    },

    npc = {
        enabled  = true,      -- spawn pharmacist NPCs at all positions (false = none, whatever the position says)
        models   = { 's_f_y_scrubs_01', 's_m_m_doctor_01' },  -- picked by position id, so a counter always has the same face
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT',       -- idle; '' = stand still
        greet    = { dict = 'gestures@m@standing@casual', clip = 'gesture_hello' },  -- played when you open the shop
        faceTime = 1200,      -- ms the pharmacist turns towards you
    },

    blip = {
        enabled    = true,    -- map blips for pharmacy positions (false = none, whatever the position says)
        sprite     = 51,      -- pill bottle
        colour     = 2,       -- green
        scale      = 0.75,
        shortRange = true,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SHOP
    -- ═══════════════════════════════════════════════════════════════════════

    payment = {
        cash = true,          -- allow paying with cash
        bank = true,          -- allow paying by card (bank)
        default = 'bank',     -- method selected when the window opens
    },

    tax           = 0.0,      -- sales tax on top of the order (0.05 = 5 %); 0 hides the line
    staffDiscount = 0.20,     -- on-duty medics of the shop's department pay this much less (0 = off)
    stackDiscounts = false,   -- false: insurance and staff discounts don't add up (the bigger one is used)
    maxLines      = 30,       -- different products per order
    maxQuantity   = 25,       -- default per-product limit for one order (a product can set its own 'limit')
    showRestricted = false,   -- show products you may not buy (locked, with the reason); false hides them

    income = {
        toSociety = true,     -- shop sales are paid into the department society (else Config.Billing.society)
        share     = 1.0,      -- fraction of each sale the society gets (the rest simply leaves the economy)
    },

    -- Shop categories in the order they appear. Labels: locales/en/pharmacy.lua ('pharmacy.cat_<id>').
    categories = {
        { id = 'medicines', icon = 'pill' },
        { id = 'dressings', icon = 'bandage' },
        { id = 'bones',     icon = 'bone' },
        { id = 'devices',   icon = 'kit' },
    },

    -- Products without their own 'category' use the item's category from config/items.lua
    -- (ItemDefs), mapped onto the shop categories above with this table.
    itemCategory = {
        medication = 'medicines',
        first_aid  = 'dressings',
        wound_care = 'dressings',
        fluids     = 'lines',
        airway     = 'airway',
        orthopedic = 'bones',
        equipment  = 'devices',
        surgery    = 'devices',
        documents  = 'devices',
    },

    --[[ The catalogue. One entry per product:
         item        Config.Items key (config/items.lua)              e.g. 'bandage'
         name        OR a raw inventory item name (for items that are not ours)
         price       price before the product discount
         discount    0..1 product discount (the old price is shown struck through)
         category    one of the categories above
         stock       false = unlimited, a number = shelf size managed by the department (restocked by
                     staff, auto restock below); stock is kept per department
         limit       max per order (default maxQuantity)
         perm        NZA permission needed (e.g. 'meds'): only on-duty medics with it may buy
         medicOnly   true = on-duty medics only
         jobs        { 'ambulance', 'police' } = only these framework jobs
         minGrade    minimum framework job grade (with jobs)
         license     framework licence needed (QBCore metadata.licences / ESX esx_license)
         featured    shown first in "All products"
         label / description   override the item's own text (config/items.lua → ItemDefs)       ]]
    -- A public shop: anyone can walk up and buy these (no job, no permission, always in stock).
    -- Drugs, IV / airway / bone kits and medic equipment are not sold here: medics get them from the
    -- medical bag (unlimited) and the Supply Officer (Config.Hospital.storage).
    products = {
        -- medicines
        { item = 'painkillers',    price = 40,   discount = 0.25, category = 'medicines', stock = false, featured = true },
        { item = 'antibiotics',    price = 120,                   category = 'medicines', stock = false },

        -- bleeding & dressings
        { item = 'bandage',        price = 25,   discount = 0.28, category = 'dressings', stock = false, featured = true },
        { item = 'tourniquet',     price = 60,   discount = 0.25, category = 'dressings', stock = false, featured = true },
        { item = 'gauze',          price = 15,                    category = 'dressings', stock = false },
        { item = 'dressing',       price = 20,                    category = 'dressings', stock = false },
        { item = 'burn_dressing',  price = 60,   discount = 0.25, category = 'dressings', stock = false },
        { item = 'iodine',         price = 10,                    category = 'dressings', stock = false },
        { item = 'saline',         price = 35,                    category = 'dressings', stock = false },

        -- bones & joints
        { item = 'ice_pack',       price = 20,   discount = 0.25, category = 'bones',     stock = false },
        { item = 'splint',         price = 180,  discount = 0.15, category = 'bones',     stock = false },
        { item = 'crutches',       price = 350,                   category = 'bones',     stock = false, limit = 1 },

        -- kit & devices
        { item = 'medkit',         price = 150,  discount = 0.25, category = 'devices',   stock = false, featured = true },
        { item = 'foil_blanket',   price = 30,                    category = 'devices',   stock = false },
        { item = 'wheelchair',     price = 2400,                  category = 'devices',   stock = false, limit = 1 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- STOCK (products with a number in 'stock')
    -- ═══════════════════════════════════════════════════════════════════════

    stock = {
        enabled   = true,     -- false = every product is unlimited
        orderCost = 0.45,     -- staff orders cost this fraction of the price per unit, paid by the department society
        orderMax  = 50,       -- units per order line
        fromInventory = true, -- staff can put items from their own inventory on the shelf
        autoRestock = {
            enabled  = true,  -- shelves refill a little by themselves (supplier delivery)
            interval = 45,    -- minutes between deliveries
            amount   = 0.25,  -- fraction of the shelf size added each delivery
            charge   = false, -- true = the society pays orderCost for delivered units (skipped when it can't)
        },
        lowAt     = 0.25,     -- shelf at or under this fraction shows "Low stock"
    },

    -- Staff view (permission 'pharmacy', own department; admins everywhere)
    staff = {
        perm      = 'pharmacy',
        salesLog  = 60,       -- sales shown in the sales log
        keepDays  = 30,       -- sales older than this are deleted from the database (0 = keep forever)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- HEALTH INSURANCE
    -- ═══════════════════════════════════════════════════════════════════════

    insurance = {
        enabled  = true,
        giveCard = true,      -- buying / renewing gives (or updates) Config.Items.insurance_card with the plan on it
        cardShowDistance = 3.0, -- using the card shows it to the nearest player within this many metres
        maxDays  = 90,        -- renewing stacks days up to this many days ahead
        prorate  = true,      -- switching plans credits the unused days of the current plan
        toSociety = true,     -- plan payments go to the department society of the pharmacy
        memberPrefix = 'HC-', -- member number prefix on the cover card / insurance_card item (HC-7KQ4-H2MX)

        --[[ Plans: id, price, days (real days), cover (0..1 of every medical bill: treatments,
             transport, respawn), pharmacy (0..1 discount in pharmacies), popular (badge).
             Labels: 'pharmacy.plan_<id>' and 'pharmacy.plan_<id>_desc' in the locale. ]]
        plans = {
            { id = 'basic',   price = 1500, days = 7,  cover = 0.40, pharmacy = 0.10, icon = 'shield' },
            { id = 'plus',    price = 3500, days = 14, cover = 0.65, pharmacy = 0.20, icon = 'shield-check', popular = true },
            { id = 'premium', price = 9000, days = 30, cover = 0.90, pharmacy = 0.35, icon = 'crown' },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (NZA.Billing.Charge - Config.Billing in config/config.lua holds the
    -- society, account and medic cut)
    -- ═══════════════════════════════════════════════════════════════════════

    billing = {
        useInsurance  = true,   -- insurance pays its cover share of every bill
        insurerPays   = true,   -- the covered share is also paid into the society (the insurer reimburses the hospital)
        otherAccount  = true,   -- try the other account (cash ↔ bank) when the first one is short
        unpaidBills   = true,   -- can't pay → an unpaid bill (pay later at a pharmacy); false = the bill is dropped
        maxUnpaid     = 25,     -- open bills per player (older ones are merged into the newest)
        lateMedicCut  = true,   -- paying an old bill still pays the medic cut (when the medic is online)
        notify        = true,   -- toast to the patient (and the medic's cut)
        autoCollect = {
            enabled  = false,   -- take open bills from the bank by themselves
            interval = 30,      -- minutes
            onLoad   = true,    -- also try when a player loads in
        },

        -- External billing: false | 'okokBilling' | 'esx_billing' | 'qb-phone' | 'jim-payments' | 'custom'
        -- Invoices are sent to that script instead of taking the money directly.
        external      = false,
        externalKinds = nil,    -- nil = every bill; or a list like { 'invoice', 'treatment' } (opts.kind)
        externalFallback = true, -- when the external script fails, charge directly
        externalSender = nil,   -- sender name on invoices (nil = the medic, or the locale's department name)
        -- 'custom': function(src, identifier, amount, reason, opts) return true end
        custom        = nil,
    },

    -- Medics can send a bill to a player (patient menu → Send bill)
    invoice = {
        enabled   = true,
        perm      = 'assess',   -- NZA permission (on duty)
        distance  = 4.0,
        max       = 15000,      -- highest amount on one bill
        cooldown  = 20,         -- seconds between bills to the same patient
        presets   = {           -- quick amounts in the bill window (reason keys: 'pharmacy.reason_<key>')
            { key = 'consult',   amount = 250 },
            { key = 'treatment', amount = 750 },
            { key = 'transport', amount = 500 },
            { key = 'surgery',   amount = 2500 },
        },
    },

    commands = {
        insurance = 'nzainsurance',  -- /nzainsurance [id] [plan|none] [days]  (ace nza.admin)
        bills     = 'nzabills',      -- /nzabills [id]  lists / clears open bills  (ace nza.admin)
    },

    rates = {
        open   = { 4, 5000 },   -- { calls, per ms }
        buy    = { 3, 5000 },
        action = { 8, 5000 },
    },
}
