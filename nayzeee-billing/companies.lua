--  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███╗   ██╗██╗███████╗███████╗
-- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██╔════╝
-- ██║     ██║   ██║██╔████╔██║██████╔╝███████║██╔██╗ ██║██║█████╗  ███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║╚██╗██║██║██╔══╝  ╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║ ╚████║██║███████╗███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝

--[[
    Company options
    ───────────────────────────────────────────────────────────────
    label            Display name
    shortName        Short tag shown on chips / receipts
    job              Job name that bills as this company (or jobs = { 'job1', 'job2' })
    account          Bank/society account name (defaults to the job name)
    minGrade         Minimum job grade to create invoices (default 0)
    bossGrade        Minimum grade with boss access (default: framework isboss / grade_name 'boss')
    taxRate          0.08 = 8%
    allowDiscounts   Employees can apply discounts
    maxDiscount      Max discount % (default 100)
    allowCustomItems Employees can add custom line items (name + price). Catalog prices are always enforced
    allowTips        Customers can tip on payment
    commission       Overrides Config.Payment.EmployeeCommission.Percentage (0 to disable)
    dueDays          Overrides Config.Invoices.DueDays
    webhook          Discord webhook for this company only

    Edits made in /billingadmin (or by bosses) are stored in the database and override this file.
]]

Config.Companies = {
    -- ══════════════════════════════════════════════════════════════
    -- BURGERSHOT
    -- ══════════════════════════════════════════════════════════════
    ['burgershot'] = {
        label = 'Burgershot',
        shortName = 'BS',
        job = 'burgershot',
        taxRate = 0.08,
        allowDiscounts = true,
        maxDiscount = 50,
        allowCustomItems = false,
        allowTips = true,

        categories = {
            { id = 'burgers', label = 'Burgers', icon = 'fa-burger' },
            { id = 'sides', label = 'Sides', icon = 'fa-bowl-food' },
            { id = 'drinks', label = 'Drinks', icon = 'fa-mug-hot' },
            { id = 'combos', label = 'Combos', icon = 'fa-plate-wheat' },
        },

        products = {
            { id = 'bleeder', name = 'Bleeder Burger', price = 8.99, category = 'burgers', image = 'burger' },
            { id = 'moneyshot', name = 'Money Shot Burger', price = 12.99, category = 'burgers', image = 'burger' },
            { id = 'fries', name = 'Fries', price = 3.99, category = 'sides', image = 'fries' },
            { id = 'soda', name = 'E-Cola', price = 2.49, category = 'drinks', image = 'cola' },
            { id = 'water', name = 'Water', price = 1.99, category = 'drinks', image = 'water' },
        },

        quickBills = {
            { id = 'combo1', label = 'Bleeder Combo', amount = 12.99, description = 'Burger + Fries + Drink' },
            { id = 'combo2', label = 'Money Shot Combo', amount = 16.99, description = 'Premium Burger + Fries + Drink' },
        },
    },

    -- ██████╗  ██████╗ ██╗     ██╗ ██████╗███████╗
    -- ██╔══██╗██╔═══██╗██║     ██║██╔════╝██╔════╝
    -- ██████╔╝██║   ██║██║     ██║██║     █████╗
    -- ██╔═══╝ ██║   ██║██║     ██║██║     ██╔══╝
    -- ██║     ╚██████╔╝███████╗██║╚██████╗███████╗
    -- ╚═╝      ╚═════╝ ╚══════╝╚═╝ ╚═════╝╚══════╝
    ['police'] = {
        label = 'Los Santos Police Department',
        shortName = 'LSPD',
        job = 'police',
        taxRate = 0,
        allowDiscounts = false,
        allowCustomItems = true,
        allowTips = false,
        commission = 0.05,
        dueDays = 7,

        categories = {
            { id = 'fines', label = 'Traffic Fines', icon = 'fa-car' },
            { id = 'citations', label = 'Citations', icon = 'fa-file-lines' },
            { id = 'impound', label = 'Impound Fees', icon = 'fa-warehouse' },
            { id = 'other', label = 'Other', icon = 'fa-box' },
        },

        products = {
            -- Traffic Fines
            { id = 'fine_speeding', name = 'Speeding Violation', price = 500, category = 'fines' },
            { id = 'fine_running_red', name = 'Running Red Light', price = 350, category = 'fines' },
            { id = 'fine_illegal_parking', name = 'Illegal Parking', price = 200, category = 'fines' },
            { id = 'fine_reckless', name = 'Reckless Driving', price = 2500, category = 'fines' },
            { id = 'fine_dui', name = 'DUI/DWI', price = 5000, category = 'fines' },
            { id = 'fine_evading', name = 'Evading Police', price = 7500, category = 'fines' },

            -- Citations
            { id = 'cite_jaywalking', name = 'Jaywalking', price = 100, category = 'citations' },
            { id = 'cite_disturbance', name = 'Public Disturbance', price = 500, category = 'citations' },
            { id = 'cite_trespassing', name = 'Trespassing', price = 750, category = 'citations' },

            -- Impound
            { id = 'impound_standard', name = 'Standard Impound', price = 500, category = 'impound' },
            { id = 'impound_evidence', name = 'Evidence Hold', price = 1500, category = 'impound' },
            { id = 'impound_storage', name = 'Storage Fee (per day)', price = 100, category = 'impound' },
        },

        quickBills = {
            { id = 'speeding_quick', label = 'Speeding Ticket', amount = 500, description = 'Standard speeding violation' },
            { id = 'dui_quick', label = 'DUI Fine', amount = 5000, description = 'Driving under influence' },
        },
    },

    -- ███╗   ███╗███████╗ ██████╗██╗  ██╗ █████╗ ███╗   ██╗██╗ ██████╗
    -- ████╗ ████║██╔════╝██╔════╝██║  ██║██╔══██╗████╗  ██║██║██╔════╝
    -- ██╔████╔██║█████╗  ██║     ███████║███████║██╔██╗ ██║██║██║
    -- ██║╚██╔╝██║██╔══╝  ██║     ██╔══██║██╔══██║██║╚██╗██║██║██║
    -- ██║ ╚═╝ ██║███████╗╚██████╗██║  ██║██║  ██║██║ ╚████║██║╚██████╗
    -- ╚═╝     ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝ ╚═════╝
    ['mechanic'] = {
        label = 'Los Santos Customs',
        shortName = 'LSC',
        job = 'mechanic',
        taxRate = 0.08,
        allowDiscounts = true,
        maxDiscount = 25,
        allowCustomItems = true,
        allowTips = true,

        categories = {
            { id = 'repairs', label = 'Repairs', icon = 'fa-wrench' },
            { id = 'service', label = 'Service', icon = 'fa-oil-can' },
            { id = 'parts', label = 'Parts', icon = 'fa-gears' },
            { id = 'upgrades', label = 'Upgrades', icon = 'fa-gauge-high' },
            { id = 'other', label = 'Other', icon = 'fa-box' },
        },

        products = {
            -- Repairs
            { id = 'repair_basic', name = 'Basic Repair', price = 500, category = 'repairs' },
            { id = 'repair_full', name = 'Full Repair', price = 1500, category = 'repairs' },
            { id = 'repair_engine', name = 'Engine Repair', price = 2500, category = 'repairs' },
            { id = 'repair_bodywork', name = 'Bodywork Repair', price = 1000, category = 'repairs' },
            { id = 'repair_window', name = 'Window Replacement', price = 300, category = 'repairs' },

            -- Service
            { id = 'service_oil', name = 'Oil Change', price = 150, category = 'service' },
            { id = 'service_tune', name = 'Tune-Up', price = 350, category = 'service' },
            { id = 'service_inspection', name = 'Inspection', price = 100, category = 'service' },
            { id = 'service_wash', name = 'Full Detail Wash', price = 200, category = 'service' },

            -- Parts
            { id = 'part_tire', name = 'Tire Replacement', price = 250, category = 'parts' },
            { id = 'part_battery', name = 'Battery Replacement', price = 400, category = 'parts' },
            { id = 'part_brakes', name = 'Brake Pads', price = 350, category = 'parts' },

            -- Upgrades
            { id = 'upgrade_engine', name = 'Engine Upgrade', price = 5000, category = 'upgrades' },
            { id = 'upgrade_turbo', name = 'Turbo Installation', price = 7500, category = 'upgrades' },
            { id = 'upgrade_suspension', name = 'Suspension Upgrade', price = 3000, category = 'upgrades' },
        },

        quickBills = {
            { id = 'quick_fix', label = 'Quick Fix', amount = 500, description = 'Basic vehicle repair' },
        },
    },

    -- ███████╗███╗   ███╗███████╗
    -- ██╔════╝████╗ ████║██╔════╝
    -- █████╗  ██╔████╔██║███████╗
    -- ██╔══╝  ██║╚██╔╝██║╚════██║
    -- ███████╗██║ ╚═╝ ██║███████║
    -- ╚══════╝╚═╝     ╚═╝╚══════╝
    ['ambulance'] = {
        label = 'Pillbox Medical Center',
        shortName = 'PMC',
        job = 'ambulance',
        taxRate = 0,
        allowDiscounts = true,
        maxDiscount = 100,
        allowCustomItems = true,
        allowTips = false,
        dueDays = 7,

        categories = {
            { id = 'emergency', label = 'Emergency Services', icon = 'fa-truck-medical' },
            { id = 'treatment', label = 'Treatment', icon = 'fa-stethoscope' },
            { id = 'surgery', label = 'Surgery', icon = 'fa-scissors' },
            { id = 'pharmacy', label = 'Pharmacy', icon = 'fa-pills' },
            { id = 'other', label = 'Other', icon = 'fa-box' },
        },

        products = {
            -- Emergency
            { id = 'ems_response', name = 'Emergency Response', price = 500, category = 'emergency' },
            { id = 'ems_transport', name = 'Ambulance Transport', price = 750, category = 'emergency' },
            { id = 'ems_revive', name = 'Emergency Resuscitation', price = 2500, category = 'emergency' },

            -- Treatment
            { id = 'treat_exam', name = 'Medical Examination', price = 200, category = 'treatment' },
            { id = 'treat_bandage', name = 'Wound Treatment', price = 150, category = 'treatment' },
            { id = 'treat_fracture', name = 'Fracture Treatment', price = 500, category = 'treatment' },
            { id = 'treat_burns', name = 'Burn Treatment', price = 400, category = 'treatment' },
            { id = 'treat_blood', name = 'Blood Transfusion', price = 1000, category = 'treatment' },

            -- Surgery
            { id = 'surgery_minor', name = 'Minor Surgery', price = 2500, category = 'surgery' },
            { id = 'surgery_major', name = 'Major Surgery', price = 7500, category = 'surgery' },
            { id = 'surgery_bullet', name = 'Bullet Extraction', price = 3000, category = 'surgery' },

            -- Pharmacy
            { id = 'rx_painkillers', name = 'Painkillers', price = 100, category = 'pharmacy' },
            { id = 'rx_antibiotics', name = 'Antibiotics', price = 150, category = 'pharmacy' },
            { id = 'rx_bandages', name = 'Bandages (pack)', price = 50, category = 'pharmacy' },
        },

        quickBills = {
            { id = 'treatment_quick', label = 'Standard Treatment', amount = 1000, description = 'Standard medical treatment' },
        },
    },
}
