-- ███████╗ ██████╗  ██████╗██╗███████╗████████╗██╗███████╗███████╗
-- ██╔════╝██╔═══██╗██╔════╝██║██╔════╝╚══██╔══╝██║██╔════╝██╔════╝
-- ███████╗██║   ██║██║     ██║█████╗     ██║   ██║█████╗  ███████╗
-- ╚════██║██║   ██║██║     ██║██╔══╝     ██║   ██║██╔══╝  ╚════██║
-- ███████║╚██████╔╝╚██████╗██║███████╗   ██║   ██║███████╗███████║
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚══════╝   ╚═╝   ╚═╝╚══════╝╚══════╝

--[[
    Every job that can bill as a society (and be billed as one) is listed here.
    Key = job name.

    label          Display name
    short          Short tag (chips, reference prefix e.g. LSPD-7KQ2MZ4P)
    jobs           Extra jobs that bill as this society (optional)
    account        Society bank account name (default: the job name)
    sendGrade      Lowest grade that can send invoices as the society
    manageGrade    Lowest grade with full management (also: framework boss)
    billable       Other people / societies can send invoices to this society (default true)
    vat            VAT rate override (0.25) or false for VAT-exempt
    revenueShare   Employee share override (0.15) or false
    allowCustom    Custom reasons / amounts (default true)
    allowTips      Tips on this society's invoices (default true)
    dueDays        Default days until due
    color          Accent for chips (hex, optional)

    Permission groups (Permissions page) start from the grades above:
      grade >= manageGrade (or framework boss) -> manager, grade >= sendGrade -> sales, below -> limited.
    Managers then assign employees to any group and change what each group can do, in-game.
]]

Config.Societies = {
    ['police'] = {
        label = 'Los Santos Police Department',
        short = 'LSPD',
        sendGrade = 0,
        manageGrade = 3,
        vat = false,
        revenueShare = 0.05,
        allowTips = false,
        dueDays = 7,
        color = '#5b8def',
    },

    ['ambulance'] = {
        label = 'Pillbox Medical Center',
        short = 'PMC',
        sendGrade = 0,
        manageGrade = 3,
        vat = false,
        allowTips = false,
        dueDays = 7,
        color = '#e5484d',
    },

    ['mechanic'] = {
        label = 'Los Santos Customs',
        short = 'LSC',
        sendGrade = 0,
        manageGrade = 3,
        color = '#e5a50a',
    },

    ['cardealer'] = {
        label = 'Premium Deluxe Motorsport',
        short = 'PDM',
        sendGrade = 0,
        manageGrade = 3,
        vat = 0.25,
        revenueShare = 0.05,
        dueDays = 3,
        color = '#08afa2',
    },

    ['burgershot'] = {
        label = 'Burgershot',
        short = 'BS',
        sendGrade = 0,
        manageGrade = 3,
        dueDays = 1,
        color = '#e5a50a',
    },

    ['government'] = {
        label = 'City Treasury',
        short = 'GOV',
        sendGrade = 2,
        manageGrade = 4,
        vat = false,
        revenueShare = false,
    },
}

-- ██████╗ ███████╗██████╗ ███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝██╔══██╗████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝█████╗  ██████╔╝██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
-- ██╔═══╝ ██╔══╝  ██╔══██╗██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
-- ██║     ███████╗██║  ██║██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Permission keys, grouped the way the Permissions page shows them
Config.PermissionSections = {
    { id = 'invoices', label = 'Invoices', perms = {
        { key = 'view_received', label = 'View received invoices' },
        { key = 'view_sent', label = 'View sent invoices' },
        { key = 'create', label = 'Create invoices' },
        { key = 'cancel', label = 'Cancel invoices' },
        { key = 'print', label = 'Print invoices' },
        { key = 'refund', label = 'Refund invoices' },
        { key = 'disputes', label = 'Resolve disputes' },
    } },
    { id = 'templates', label = 'Templates', perms = {
        { key = 'templates_view', label = 'View templates' },
        { key = 'templates_create', label = 'Create templates' },
        { key = 'templates_edit', label = 'Edit templates' },
        { key = 'templates_delete', label = 'Delete templates' },
    } },
    { id = 'management', label = 'Management', perms = {
        { key = 'overview', label = 'View overview & balance' },
        { key = 'activity', label = 'View activity logs' },
        { key = 'permissions', label = 'Manage permissions' },
        { key = 'pay', label = 'Pay invoices from the society account' },
        { key = 'inspect', label = 'Inspect players & societies' },
        { key = 'register', label = 'Use cash registers' },
    } },
}

local function all() local t = {} for _, s in ipairs(Config.PermissionSections) do for _, p in ipairs(s.perms) do t[p.key] = true end end return t end

-- Default groups for every society (managers edit them per society in-game)
-- access: full / high / normal / limited (badge colour)
Config.PermissionGroups = {
    { id = 'manager', label = 'Manager', access = 'full', icon = 'shield', color = 'blue', perms = all() },
    { id = 'finance', label = 'Finance', access = 'high', icon = 'chevrons', color = 'cyan', perms = {
        view_received = true, view_sent = true, create = true, cancel = true, print = true, refund = true, disputes = true,
        templates_view = true, overview = true, activity = true, pay = true, inspect = true, register = true } },
    { id = 'sales', label = 'Sales', access = 'normal', icon = 'chevron', color = 'violet', perms = {
        view_sent = true, create = true, print = true, templates_view = true, register = true } },
    { id = 'limited', label = 'Limited', access = 'limited', icon = 'users', color = 'amber', perms = {
        templates_view = true, register = true } },
}

-- Group an employee starts in (until a manager assigns one): grade >= manageGrade -> 'manager',
-- grade >= sendGrade -> 'sales', otherwise 'limited'
Config.DefaultGroups = { manage = 'manager', send = 'sales', other = 'limited' }
