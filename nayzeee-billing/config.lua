--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝

    NAYZEEE BILLING - 2.0.0
    Discord: discord.gg/nayzeeedev
]]

Config = {}

-- ███████╗██████╗  █████╗ ███╗   ███╗███████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
-- ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
-- █████╗  ██████╔╝███████║██╔████╔██║█████╗  ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
-- ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  ██║███╗██║██║   ██║██╔══██╗██╔═██╗
-- ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

Config.Framework = 'auto' -- 'auto' / 'esx' / 'qbcore' / 'qbox'
Config.Debug = false

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Command = 'billing'            -- Opens the billing tablet (everyone can open it to see/pay their bills)
Config.AdminCommand = 'billingadmin'  -- Opens the admin panel
Config.OpenKey = 'F6'                 -- Keybind for Config.Command (players can rebind in GTA settings). false to disable

Config.Currency = '$'
Config.DefaultTaxRate = 0.08          -- Used for personal invoices and companies without a taxRate
Config.MaxInvoiceAmount = 1000000

-- ██████╗ ██╗██╗     ██╗     ██╗███╗   ██╗ ██████╗
-- ██╔══██╗██║██║     ██║     ██║████╗  ██║██╔════╝
-- ██████╔╝██║██║     ██║     ██║██╔██╗ ██║██║  ███╗
-- ██╔══██╗██║██║     ██║     ██║██║╚██╗██║██║   ██║
-- ██████╔╝██║███████╗███████╗██║██║ ╚████║╚██████╔╝
-- ╚═════╝ ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Billing = {
    -- Who can create invoices
    AllowPersonalBilling = true,  -- Players without a billing company can send personal invoices (custom items only)
    AllowSelfBilling = false,     -- Allow billing yourself (handy for testing)
    RequireOnDuty = false,        -- QBCore/Qbox: employees must be on duty to bill as their company

    -- Proximity: target must be within this distance (meters) of the sender. false = anywhere
    MaxDistance = 10.0,
    -- Jobs allowed to bill players remotely / offline (e.g. police fines, hospital follow-ups)
    RemoteBillingJobs = { 'police', 'ambulance' },

    -- Offline billing: search the players/users table for characters that are not online
    OfflineBilling = true,

    -- Limits
    MaxItems = 30,                -- Max line items per invoice
    MaxQuantity = 100,            -- Max quantity per line item
    MaxNoteLength = 250,
    Cooldown = 3,                 -- Seconds between invoices per player (anti-spam)
    MaxPendingPerTarget = 15,     -- Max unpaid invoices a single player can have from the same company
}

-- ██╗███╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗███████╗
-- ██║████╗  ██║██║   ██║██╔═══██╗██║██╔════╝██╔════╝██╔════╝
-- ██║██╔██╗ ██║██║   ██║██║   ██║██║██║     █████╗  ███████╗
-- ██║██║╚██╗██║╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ╚════██║
-- ██║██║ ╚████║ ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████║
-- ╚═╝╚═╝  ╚═══╝  ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝

Config.Invoices = {
    DueDays = 3,                  -- Default days until an invoice is due (companies can override with dueDays)
    AllowCustomDueDays = true,    -- Senders can pick 1..MaxDueDays
    MaxDueDays = 14,

    -- Reference numbers players quote and search for
    -- 'company' = per-company counters: BS-000142, LSPD-000031 (prefix = company refPrefix or shortName)
    -- 'random'  = INV-7KQ2MZ4P
    ReferenceFormat = 'company',
    PersonalPrefix = 'INV',       -- prefix for personal invoices / invoices from other scripts
    ReferenceDigits = 6,
    InvoiceCommand = 'invoice',   -- /invoice BS-000142 opens that invoice. false to disable

    -- Disputes: recipients can dispute an invoice. The company's bosses get notified and resolve it
    AllowDisputes = true,

    -- Cancelling: senders can cancel their own unpaid invoices, bosses can cancel any company invoice
    SenderCanCancel = true,
    CancelWindowMinutes = 60,     -- Senders can only cancel within this window (bosses/admins always can). 0 = always
}

--  ██████╗ ██╗   ██╗███████╗██████╗ ██████╗ ██╗   ██╗███████╗
-- ██╔═══██╗██║   ██║██╔════╝██╔══██╗██╔══██╗██║   ██║██╔════╝
-- ██║   ██║██║   ██║█████╗  ██████╔╝██║  ██║██║   ██║█████╗
-- ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗██║  ██║██║   ██║██╔══╝
-- ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║██████╔╝╚██████╔╝███████╗
--  ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚══════╝

Config.Overdue = {
    Enabled = true,
    CheckInterval = 5,            -- Minutes between overdue checks
    LateFee = 0.10,               -- 10% one-time late fee added once an invoice becomes overdue (0 to disable)
    MaxLateFee = 50000,           -- Cap on the late fee

    -- Auto-collect: overdue invoices are automatically charged from the player's bank after X days
    AutoCollect = true,
    AutoCollectAfterDays = 2,     -- Days past the due date
    AutoCollectAllowNegative = false, -- false = only collect if they have the funds
}

-- ██████╗  █████╗ ██╗   ██╗███╗   ███╗███████╗███╗   ██╗████████╗███████╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝████╗ ████║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
-- ██████╔╝███████║ ╚████╔╝ ██╔████╔██║█████╗  ██╔██╗ ██║   ██║   ███████╗
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║   ╚════██║
-- ██║     ██║  ██║   ██║   ██║ ╚═╝ ██║███████╗██║ ╚████║   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

Config.Payment = {
    Methods = { bank = true, cash = true },

    -- Where does business/job invoice money go?
    -- 'society' = Goes to the company/job bank account (see Config.Banking)
    -- 'player'  = Goes directly to the employee who created the invoice
    BusinessPaymentDestination = 'society',

    -- Partial payments (pay invoices in installments)
    AllowPartial = true,
    MinPartialAmount = 50,

    -- Personal invoice payment handling (when no job/company)
    PersonalInvoice = {
        CashRequiresCollection = true, -- Cash payments must be collected at a bank teller
        CardGoesToBank = true,
    },

    -- Bank teller locations for collecting cash payments
    BankTellers = {
        { coords = vector3(149.56, -1042.09, 29.37) },
        { coords = vector3(-1212.98, -330.77, 37.79) },
        { coords = vector3(-2962.58, 482.63, 15.7) },
        { coords = vector3(313.82, -278.96, 54.16) },
        { coords = vector3(-351.23, -49.58, 49.04) },
        { coords = vector3(1175.07, 2706.41, 38.09) },
    },

    -- Employee commission on company invoices (companies can override with commission = 0.15)
    EmployeeCommission = {
        Enabled = true,
        Percentage = 0.10,      -- 10% of the paid amount
        ExcludeTax = true,      -- Commission is calculated on the amount minus tax
    },
}

-- ████████╗██╗██████╗ ███████╗
-- ╚══██╔══╝██║██╔══██╗██╔════╝
--    ██║   ██║██████╔╝███████╗
--    ██║   ██║██╔═══╝ ╚════██║
--    ██║   ██║██║     ███████║
--    ╚═╝   ╚═╝╚═╝     ╚══════╝

Config.Tips = {
    Enabled = true,
    Presets = { 0, 10, 15, 20 }, -- Tip % buttons shown when paying
    MaxPercent = 50,
    Recipient = 'employee',      -- 'employee' = employee who sent the invoice, 'society' = company account
}

-- ████████╗ █████╗ ██╗  ██╗
-- ╚══██╔══╝██╔══██╗╚██╗██╔╝
--    ██║   ███████║ ╚███╔╝
--    ██║   ██╔══██║ ██╔██╗
--    ██║   ██║  ██║██╔╝ ██╗
--    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝

Config.Tax = {
    -- Collected tax can be routed to a government account (via Config.Banking).
    -- false = tax stays with the company (1.x behaviour)
    Account = false,             -- e.g. 'government' / 'mayor' / 'doj'
    AccountLabel = 'City Treasury',
}

-- ██████╗  █████╗ ███╗   ██╗██╗  ██╗██╗███╗   ██╗ ██████╗
-- ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██║████╗  ██║██╔════╝
-- ██████╔╝███████║██╔██╗ ██║█████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██║██║╚██╗██║██║   ██║
-- ██████╔╝██║  ██║██║ ╚████║██║  ██╗██║██║ ╚████║╚██████╔╝
-- ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Banking = {
    -- Banking system used for society / company accounts.
    -- 'auto' detects in this order:
    -- nayzeee-banking, Renewed-Banking, okokBanking, fd_banking, qb-banking, qb-management, esx_addonaccount
    -- You can also set: 'custom' (see Custom below) or 'none' (society payments fall back to the employee)
    System = 'auto',

    -- Write statements / transaction history into the banking script when supported
    LogTransactions = true,

    -- nayzeee-banking (ESX / QBCore / Qbox). Company jobs must be listed in nayzeee-banking's
    -- Config.Accounts.societyAccess so their society account exists. If qb-banking / Renewed-Banking
    -- are still running next to it, 'auto' still picks nayzeee-banking (it keeps their balances in step).
    Nayzeee = {
        Resource = 'nayzeee-banking',
        -- Charge / pay personal bank money through nayzeee-banking so statements show
        -- "Invoice BS-000142 · Burgershot" under the Bill category, and payouts reach offline players instantly
        UsePersonalAccounts = true,
        BillCategory = 'bill',
    },

    -- ESX society accounts are usually prefixed: society_police
    EsxSocietyPrefix = 'society_',

    -- Custom banking (Config.Banking.System = 'custom')
    Custom = {
        AddMoney = function(account, amount, reason) return false end,
        RemoveMoney = function(account, amount, reason) return false end,
        GetBalance = function(account) return nil end,
    },
}

-- ██████╗  ██████╗ ███████╗███████╗
-- ██╔══██╗██╔═══██╗██╔════╝██╔════╝
-- ██████╔╝██║   ██║███████╗███████╗
-- ██╔══██╗██║   ██║╚════██║╚════██║
-- ██████╔╝╚██████╔╝███████║███████║
-- ╚═════╝  ╚═════╝ ╚══════╝╚══════╝

Config.Boss = {
    -- Grade checks: QBCore/Qbox use job.isboss, ESX uses grade_name == 'boss'.
    -- Companies can override with bossGrade = 3 (minimum grade level).
    CanManageCatalog = true,     -- Bosses can edit products / quick bills / categories for their company
    CanRefund = true,            -- Bosses can refund paid invoices (money comes out of the company account)
    CanResolveDisputes = true,
    ShowSocietyBalance = true,
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

-- Admin access: ACE permission OR one of the framework groups below
Config.AdminAce = 'nayzeee.billing.admin'   -- add_ace group.admin nayzeee.billing.admin allow
Config.AdminGroups = {
    'god',
    'admin',
    'superadmin',
    'dev',
    'developer',
    'owner',
}

-- ██████╗ ███████╗ ██████╗███████╗██╗██████╗ ████████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔════╝██║██╔══██╗╚══██╔══╝██╔════╝
-- ██████╔╝█████╗  ██║     █████╗  ██║██████╔╝   ██║   ███████╗
-- ██╔══██╗██╔══╝  ██║     ██╔══╝  ██║██╔═══╝    ██║   ╚════██║
-- ██║  ██║███████╗╚██████╗███████╗██║██║        ██║   ███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝╚══════╝╚═╝╚═╝        ╚═╝   ╚══════╝

Config.Receipts = {
    ShowOnPayment = true,
    FooterText = 'Thank you for your business!',
    GiveReceiptItem = true,
    ReceiptItemName = 'receipt', -- See README for the ox_inventory / qb item definition
}

--  ██████╗ █████╗ ███████╗██╗  ██╗    ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗
-- ██╔════╝██╔══██╗██╔════╝██║  ██║    ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗
-- ██║     ███████║███████╗███████║    ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝
-- ██║     ██╔══██║╚════██║██╔══██║    ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗
-- ╚██████╗██║  ██║███████║██║  ██║    ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

Config.CashRegister = {
    Enabled = true,

    -- Interaction Method: 'target' (ox_target / qb-target) or 'textui' (ox_lib)
    InteractionMethod = 'target',

    TextUI = {
        EmployeeText = '[E] Use Register',
        CustomerText = '[E] View Order',
        Key = 38, -- E
    },

    Target = {
        EmployeeIcon = 'fa-solid fa-cash-register',
        EmployeeLabel = 'Use Register',
        CustomerIcon = 'fa-solid fa-receipt',
        CustomerLabel = 'View Order',
    },

    MaxCustomerDistance = 5.0,   -- Customer must be this close to the register to be rung up
    DeclineCancelsInvoice = true, -- If the customer declines at the register, the invoice is cancelled
    DismissKey = 'BACK',         -- Key mapping to leave the counter / hide the customer display (players can rebind)

    Blip = {
        Enabled = false,
        Sprite = 52,
        Color = 2,
        Scale = 0.6,
    },

    Debug = false,
}

-- ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
-- ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝███████╗
-- ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝

-- Cash registers defined by coords. Admins can also add registers in-game (/billingadmin > Registers)
Config.CashRegisters = {
    {
        id = 'burgershot_counter1',
        label = 'Burgershot Counter',
        company = 'burgershot',      -- Must match a company ID in companies.lua
        coords = vector3(197.4236, -850.7531, 30.9602),
        radius = 2.0,
    },
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

Config.Notifications = {
    -- 'ox_lib' / 'esx' / 'qb' / 'okokNotify' / 'mythic' / 'custom'
    System = 'ox_lib',
    EnableSounds = true,
    CustomFunction = function(title, message, notifType) end,
}

-- ██╗    ██╗███████╗██████╗ ██╗  ██╗ ██████╗  ██████╗ ██╗  ██╗███████╗
-- ██║    ██║██╔════╝██╔══██╗██║  ██║██╔═══██╗██╔═══██╗██║ ██╔╝██╔════╝
-- ██║ █╗ ██║█████╗  ██████╔╝███████║██║   ██║██║   ██║█████╔╝ ███████╗
-- ██║███╗██║██╔══╝  ██╔══██╗██╔══██║██║   ██║██║   ██║██╔═██╗ ╚════██║
-- ╚███╔███╔╝███████╗██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║  ██╗███████║
--  ╚══╝╚══╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

Config.Logging = {
    Enabled = true,
    DiscordWebhook = '',         -- Global webhook. Companies can also have their own `webhook`
    DiscordTitle = 'NAYZEEE Billing',
    DiscordColor = 571298,       -- #08afa2
}

--  ██████╗ █████╗ ████████╗███████╗ ██████╗  ██████╗ ██████╗ ██╗███████╗███████╗
-- ██╔════╝██╔══██╗╚══██╔══╝██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝██╔════╝
-- ██║     ███████║   ██║   █████╗  ██║  ███╗██║   ██║██████╔╝██║█████╗  ███████╗
-- ██║     ██╔══██║   ██║   ██╔══╝  ██║   ██║██║   ██║██╔══██╗██║██╔══╝  ╚════██║
-- ╚██████╗██║  ██║   ██║   ███████╗╚██████╔╝╚██████╔╝██║  ██║██║███████╗███████║
--  ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝

Config.DefaultCategories = {
    { id = 'food', label = 'Food', icon = 'fa-utensils' },
    { id = 'drinks', label = 'Drinks', icon = 'fa-glass-water' },
    { id = 'services', label = 'Services', icon = 'fa-wrench' },
    { id = 'other', label = 'Other', icon = 'fa-box' },
}

-- ██╗███╗   ███╗ █████╗  ██████╗ ███████╗███████╗
-- ██║████╗ ████║██╔══██╗██╔════╝ ██╔════╝██╔════╝
-- ██║██╔████╔██║███████║██║  ███╗█████╗  ███████╗
-- ██║██║╚██╔╝██║██╔══██║██║   ██║██╔══╝  ╚════██║
-- ██║██║ ╚═╝ ██║██║  ██║╚██████╔╝███████╗███████║
-- ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝

-- Item image path. 'auto' picks ox_inventory / qb-inventory / qs-inventory / ps-inventory
Config.ImagePath = 'auto' -- or e.g. 'nui://ox_inventory/web/images/%s.png'
