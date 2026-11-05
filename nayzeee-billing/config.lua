--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝

    NAYZEEE BILLING - 1.0.0
    Discord: discord.gg/nayzeeedev

    Societies live in societies.lua, invoice presets in presets.lua,
    every player-facing text in locales/<lang>.json.
]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Framework = 'auto'      -- 'auto' / 'esx' / 'qbcore' / 'qbox' / 'custom' (bridge/framework/custom.lua)
Config.Locale = 'en'           -- locales/<Locale>.json
Config.Currency = '$'
Config.CurrencyPosition = 'before' -- 'before' ($100) or 'after' (100€)
Config.Debug = false

-- Keymapping (players can rebind in Settings > Key Bindings > FiveM)
Config.Keybind = {
    Enabled = true,
    Command = 'billing',
    Key = 'F7',
    Description = 'Open billing',
}

Config.AdminCommand = 'billingadmin'  -- opens billing on the Inspect page

-- ██╗███╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗███████╗
-- ██║████╗  ██║██║   ██║██╔═══██╗██║██╔════╝██╔════╝██╔════╝
-- ██║██╔██╗ ██║██║   ██║██║   ██║██║██║     █████╗  ███████╗
-- ██║██║╚██╗██║╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ╚════██║
-- ██║██║ ╚████║ ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████║
-- ╚═╝╚═╝  ╚═══╝  ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝

Config.Invoices = {
    MaxAmount = 1000000,
    MaxItems = 25,
    MaxQuantity = 100,
    MaxNoteLength = 250,
    MaxDistance = 10.0,           -- recipients must be this close (citizen invoices). false = anywhere
    DueDays = 7,                  -- default; societies can override with dueDays
    AllowCustomDueDays = true,
    MaxDueDays = 30,
    Cooldown = 3,                 -- seconds between invoices per player
    MaxOpenPerRecipient = 15,     -- open invoices one sender (person or society) can have on one recipient

    -- References: <PREFIX>-<8 random characters>, e.g. LSPD-7KQ2MZ4P.
    -- The random part keeps "pay by reference" safe: references can't be guessed.
    PersonalPrefix = 'INV',

    AllowDisputes = true,
    SenderCancelMinutes = 60,     -- senders can cancel their own unpaid invoice within this window (managers/admins always). 0 = always
}

-- ██████╗ ███████╗██████╗ ███████╗ ██████╗ ███╗   ██╗ █████╗ ██╗
-- ██╔══██╗██╔════╝██╔══██╗██╔════╝██╔═══██╗████╗  ██║██╔══██╗██║
-- ██████╔╝█████╗  ██████╔╝███████╗██║   ██║██╔██╗ ██║███████║██║
-- ██╔═══╝ ██╔══╝  ██╔══██╗╚════██║██║   ██║██║╚██╗██║██╔══██║██║
-- ██║     ███████╗██║  ██║███████║╚██████╔╝██║ ╚████║██║  ██║███████╗
-- ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝

Config.Personal = {
    Enabled = true,               -- anyone can send personal invoices
    AllowCustomItems = true,      -- custom reasons / amounts
    AllowSocietyRecipients = true,-- citizens can bill configured societies (e.g. a contractor billing the police)
    VAT = false,                  -- add VAT to personal invoices
    CashRequiresCollection = false, -- cash payments to a personal sender must be collected at a bank teller
}

-- ██████╗  █████╗ ██╗   ██╗███╗   ███╗███████╗███╗   ██╗████████╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝████╗ ████║██╔════╝████╗  ██║╚══██╔══╝
-- ██████╔╝███████║ ╚████╔╝ ██╔████╔██║█████╗  ██╔██╗ ██║   ██║
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║
-- ██║     ██║  ██║   ██║   ██║ ╚═╝ ██║███████╗██║ ╚████║   ██║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝

Config.Payment = {
    Methods = { bank = true, cash = true },
    AllowPartial = true,          -- installments
    MinPartialAmount = 50,
    PayByReference = true,        -- anyone with the reference can pay it from their own cash/bank

    -- Where society invoice money goes: 'society' (bank account) or 'employee' (issuer)
    SocietyDestination = 'society',

    -- Bank tellers where personal cash payments are collected (when CashRequiresCollection)
    BankTellers = {
        vector3(149.56, -1042.09, 29.37),
        vector3(-1212.98, -330.77, 37.79),
        vector3(-2962.58, 482.63, 15.7),
        vector3(313.82, -278.96, 54.16),
        vector3(-351.23, -49.58, 49.04),
        vector3(1175.07, 2706.41, 38.09),
    },
}

-- ██╗   ██╗ █████╗ ████████╗
-- ██║   ██║██╔══██╗╚══██╔══╝
-- ██║   ██║███████║   ██║
-- ╚██╗ ██╔╝██╔══██║   ██║
--  ╚████╔╝ ██║  ██║   ██║
--   ╚═══╝  ╚═╝  ╚═╝   ╚═╝

Config.VAT = {
    Enabled = true,
    Rate = 0.08,                  -- 8%. Societies can override with vat = 0.25 or vat = false
    Society = false,              -- route collected VAT to this society account, e.g. 'government'. false = stays with the issuer
}

-- ██████╗ ███████╗██╗   ██╗███████╗███╗   ██╗██╗   ██╗███████╗    ███████╗██╗  ██╗ █████╗ ██████╗ ███████╗
-- ██╔══██╗██╔════╝██║   ██║██╔════╝████╗  ██║██║   ██║██╔════╝    ██╔════╝██║  ██║██╔══██╗██╔══██╗██╔════╝
-- ██████╔╝█████╗  ██║   ██║█████╗  ██╔██╗ ██║██║   ██║█████╗      ███████╗███████║███████║██████╔╝█████╗
-- ██╔══██╗██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██║   ██║██╔══╝      ╚════██║██╔══██║██╔══██║██╔══██╗██╔══╝
-- ██║  ██║███████╗ ╚████╔╝ ███████╗██║ ╚████║╚██████╔╝███████╗    ███████║██║  ██║██║  ██║██║  ██║███████╗
-- ╚═╝  ╚═╝╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

-- Share of society invoice revenue (excluding VAT) paid to the employee who issued it
Config.RevenueShare = {
    Enabled = true,
    Percent = 0.10,               -- societies can override with revenueShare = 0.15
}

-- ████████╗██╗██████╗ ███████╗
-- ╚══██╔══╝██║██╔══██╗██╔════╝
--    ██║   ██║██████╔╝███████╗
--    ██║   ██║██╔═══╝ ╚════██║
--    ██║   ██║██║     ███████║
--    ╚═╝   ╚═╝╚═╝     ╚══════╝

Config.Tips = {
    Enabled = true,               -- on society invoices (societies can disable with allowTips = false)
    Presets = { 0, 10, 15, 20 },
    MaxPercent = 50,
    Recipient = 'employee',       -- 'employee' or 'society'
}

--  ██████╗ ██╗   ██╗███████╗██████╗ ██████╗ ██╗   ██╗███████╗
-- ██╔═══██╗██║   ██║██╔════╝██╔══██╗██╔══██╗██║   ██║██╔════╝
-- ██║   ██║██║   ██║█████╗  ██████╔╝██║  ██║██║   ██║█████╗
-- ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗██║  ██║██║   ██║██╔══╝
-- ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║██████╔╝╚██████╔╝███████╗
--  ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚══════╝

Config.Overdue = {
    Enabled = true,
    CheckInterval = 5,            -- minutes
    LateFee = 0.10,               -- one-time fee when an invoice expires (0 = off)
    MaxLateFee = 25000,

    -- 'flag'    = mark overdue only
    -- 'collect' = charge the recipient's bank automatically (society recipients: their society account)
    Mode = 'collect',
    CollectAfterDays = 2,         -- days past due before collecting
    IncludeOffline = true,        -- also collect from offline characters (framework bridge / banking)
    AllowNegative = false,        -- false = only collect when they can cover it
}

-- ██████╗  █████╗ ███╗   ██╗██╗  ██╗██╗███╗   ██╗ ██████╗
-- ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██║████╗  ██║██╔════╝
-- ██████╔╝███████║██╔██╗ ██║█████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██║██║╚██╗██║██║   ██║
-- ██████╔╝██║  ██║██║ ╚████║██║  ██╗██║██║ ╚████║╚██████╔╝
-- ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.BankingIntegration = 'auto'
--[[
    'auto' picks the first started:
      1. nayzeee-banking       5. qb-management (qb-banking adapter)
      2. qb-banking            6. ESX shared accounts ('framework', when es_extended runs)
      3. okokBanking           7. wasabi_banking
      4. Renewed-Banking       8. none
    Or set one: 'nayzeee-banking' / 'qb-banking' / 'okokBanking' / 'Renewed-Banking' / 'qb-management'
                'framework' / 'wasabi_banking' / 'fd_banking' / 'custom' / 'none'

    Personal invoices never need a banking resource. Society invoices need a society backend.
]]

Config.Banking = {
    EsxSocietyPrefix = 'society_',
    LogTransactions = true,       -- write statements where the banking script supports it

    -- nayzeee-banking: charge personal bank money through its ledger (labelled "Invoice LSPD-7KQ2MZ4P")
    NayzeeePersonalAccounts = true,

    -- Config.BankingIntegration = 'custom'
    Custom = {
        AddMoney = function(society, amount, reason) return false end,
        RemoveMoney = function(society, amount, reason) return false end,
        GetBalance = function(society) return nil end,
    },
}

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

Config.Items = {
    -- Physical invoice handed to online citizen recipients. Using it opens the paper invoice (pay from there)
    Invoice = { Enabled = true, Name = 'billing_invoice', RemoveWhenPaid = true },
    -- Receipt handed to whoever pays
    Receipt = { Enabled = true, Name = 'billing_receipt' },
    -- "Print invoice" from the row menu gives the viewer a copy of the invoice item
    AllowPrint = true,
}

-- ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
-- ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝███████╗
-- ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝

Config.Registers = {
    Enabled = true,
    InteractionMethod = 'target', -- 'target' (ox_target / qb-target) or 'textui'
    MaxCustomerDistance = 5.0,
    DeclineCancelsInvoice = true,
    LeaveKey = 'BACK',            -- customer key to leave the counter (rebindable)
    TextUI = { EmployeeText = '[E] Use register', CustomerText = '[E] View order', Key = 38 },
    Target = {
        EmployeeIcon = 'fa-solid fa-cash-register', EmployeeLabel = 'Use register',
        CustomerIcon = 'fa-solid fa-receipt', CustomerLabel = 'View order',
    },
    Blip = { Enabled = false, Sprite = 52, Color = 2, Scale = 0.6 },
    Debug = false,

    -- Registers from config (admins can also add them in-game: Inspect > Registers)
    List = {
        { id = 'burgershot_counter1', label = 'Burgershot Counter', society = 'burgershot', coords = vector3(197.42, -850.75, 30.96), radius = 2.0 },
    },
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

Config.Admin = {
    Ace = 'nayzeee.billing.admin',      -- add_ace group.admin nayzeee.billing.admin allow
    Groups = { 'god', 'admin', 'superadmin', 'owner', 'dev', 'developer' },
    AllowDelete = true,                 -- delete single invoice records
    AllowClearIdentifier = true,        -- delete every record involving an identifier
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

Config.Notify = {
    System = 'ox_lib',            -- 'ox_lib' / 'esx' / 'qb' / 'okokNotify' / 'mythic' / 'custom'
    Sounds = true,
    Custom = function(title, message, kind) end,
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Logs = {
    Enabled = true,
    System = 'discord',           -- 'discord' / 'ox_lib' (lib.logger) / 'custom' / 'none'
    Webhook = '',                 -- default webhook
    Webhooks = {                  -- per event, falls back to Webhook
        invoice_created = '', invoice_paid = '', invoice_cancelled = '', invoice_refunded = '',
        invoice_disputed = '', invoice_collected = '', admin = '',
    },
    Name = 'NAYZEEE Billing',
    Color = 571298,
    Custom = function(event, source, data) end,
}

-- ██╗   ██╗██╗
-- ██║   ██║██║
-- ██║   ██║██║
-- ██║   ██║██║
-- ╚██████╔╝██║
--  ╚═════╝ ╚═╝

Config.UI = {
    -- Every colour in the interface comes from here (hex)
    Colors = {
        accent = '#08afa2',       -- teal
        accentHi = '#0fd4c4',
        accentLo = '#067d74',
        chartReceived = '#079a8e',-- weekly summary: money in (validated pair for colour-blind readers)
        chartPaid = '#5b8def',    -- weekly summary: money out
        danger = '#e5484d',
        warning = '#e5a50a',
        success = '#2fbf71',
        background = '#08090a',
        panel = '#0e1011',
    },
    Title = 'Billing',
    Brand = 'NAYZEEE',
    PageSize = 8,                 -- rows per table page
    ShowClock = true,
}

--  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ████████╗
-- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗╚══██╔══╝
-- ██║     ██║   ██║██╔████╔██║██████╔╝███████║   ██║
-- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║   ██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║   ██║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝   ╚═╝

Config.Compat = {
    -- Accept esx_billing:sendBill and the esx_billing:getBills / payBill callbacks (when esx_billing isn't running).
    -- If nayzeee-banking is installed, remove 'esx_billing:sendBill' from its Config.Bridge.events.
    EsxBilling = true,
}

-- ██╗███╗   ███╗██████╗  ██████╗ ██████╗ ████████╗
-- ██║████╗ ████║██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝
-- ██║██╔████╔██║██████╔╝██║   ██║██████╔╝   ██║
-- ██║██║╚██╔╝██║██╔═══╝ ██║   ██║██╔══██╗   ██║
-- ██║██║ ╚═╝ ██║██║     ╚██████╔╝██║  ██║   ██║
-- ╚═╝╚═╝     ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝

-- One-off imports: run `billingimport <system>` in the server console.
-- Systems: esx_billing, okokBilling, qb-phone. Already imported rows are skipped.
Config.Import = {
    Enabled = true,
}
