--[[
    NAYZEEE BILLING - Database setup & upgrades
    Tables are created and upgraded automatically (MySQL 5.7+, MySQL 8, MariaDB 10.2+).
    v1 / v2 installs keep every invoice.
]]

DB = { ready = false }

local function column(tbl, col)
    return MySQL.single.await([[SELECT DATA_TYPE AS t FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]], { tbl, col })
end

function DB.TableExists(tbl)
    return (tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?]], { tbl })) or 0) > 0
end

function DB.Columns(tbl)
    local out = {}
    for _, r in ipairs(MySQL.query.await([[SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?]], { tbl }) or {}) do out[r.c] = true end
    return out
end

local function ensureColumn(tbl, col, def)
    if column(tbl, col) then return end
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, col, def))
    print(('^3[NAYZEEE-BILLING]^7 Upgraded: %s.%s'):format(tbl, col))
end

local function ensureIndex(tbl, name, cols)
    local n = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?]], { tbl, name })
    if (tonumber(n) or 0) > 0 then return end
    MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `%s` (%s)'):format(tbl, name, cols))
end

CreateThread(function()
    -- ██╗███╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗███████╗
    -- ██║████╗  ██║██║   ██║██╔═══██╗██║██╔════╝██╔════╝██╔════╝
    -- ██║██╔██╗ ██║██║   ██║██║   ██║██║██║     █████╗  ███████╗
    -- ██║██║╚██╗██║╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ╚════██║
    -- ██║██║ ╚████║ ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████║
    -- ╚═╝╚═╝  ╚═══╝  ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_invoices` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `invoice_id` VARCHAR(24) NOT NULL UNIQUE,
            `company_id` VARCHAR(50) DEFAULT NULL,
            `sender_identifier` VARCHAR(64) NOT NULL,
            `sender_name` VARCHAR(100) NOT NULL,
            `sender_job` VARCHAR(50) DEFAULT NULL,
            `recipient_type` VARCHAR(10) DEFAULT 'citizen',
            `target_identifier` VARCHAR(64) NOT NULL,
            `target_society` VARCHAR(50) DEFAULT NULL,
            `target_name` VARCHAR(100) NOT NULL,
            `company_name` VARCHAR(100) DEFAULT 'Personal',
            `reason` VARCHAR(120) DEFAULT NULL,
            `items` LONGTEXT NOT NULL,
            `notes` TEXT DEFAULT NULL,
            `subtotal` DECIMAL(15,2) DEFAULT 0,
            `vat_rate` DECIMAL(6,4) DEFAULT 0,
            `tax` DECIMAL(15,2) DEFAULT 0,
            `discount` DECIMAL(15,2) DEFAULT 0,
            `total` DECIMAL(15,2) NOT NULL,
            `late_fee` DECIMAL(15,2) DEFAULT 0,
            `amount_paid` DECIMAL(15,2) DEFAULT 0,
            `tip` DECIMAL(15,2) DEFAULT 0,
            `status` VARCHAR(20) DEFAULT 'pending',
            `payment_method` VARCHAR(20) DEFAULT NULL,
            `paid_by_identifier` VARCHAR(64) DEFAULT NULL,
            `paid_by_name` VARCHAR(100) DEFAULT NULL,
            `register_id` VARCHAR(50) DEFAULT NULL,
            `cancel_reason` VARCHAR(255) DEFAULT NULL,
            `dispute_reason` VARCHAR(255) DEFAULT NULL,
            `import_source` VARCHAR(20) DEFAULT NULL,
            `import_id` VARCHAR(64) DEFAULT NULL,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            `paid_at` DATETIME DEFAULT NULL,
            `due_date` DATETIME DEFAULT NULL,
            INDEX `idx_sender` (`sender_identifier`),
            INDEX `idx_target` (`target_identifier`),
            INDEX `idx_status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- v1 / v2 upgrades
    local st = column('nayzeee_billing_invoices', 'status')
    if st and st.t == 'enum' then
        MySQL.query.await("ALTER TABLE `nayzeee_billing_invoices` MODIFY `status` VARCHAR(20) DEFAULT 'pending'")
    end
    MySQL.query.await('ALTER TABLE `nayzeee_billing_invoices` MODIFY `invoice_id` VARCHAR(24) NOT NULL')
    for _, c in ipairs({
        { 'company_id', 'VARCHAR(50) DEFAULT NULL' }, { 'sender_job', 'VARCHAR(50) DEFAULT NULL' },
        { 'recipient_type', "VARCHAR(10) DEFAULT 'citizen'" }, { 'target_society', 'VARCHAR(50) DEFAULT NULL' },
        { 'reason', 'VARCHAR(120) DEFAULT NULL' }, { 'notes', 'TEXT DEFAULT NULL' },
        { 'vat_rate', 'DECIMAL(6,4) DEFAULT 0' }, { 'late_fee', 'DECIMAL(15,2) DEFAULT 0' },
        { 'amount_paid', 'DECIMAL(15,2) DEFAULT 0' }, { 'tip', 'DECIMAL(15,2) DEFAULT 0' },
        { 'paid_by_identifier', 'VARCHAR(64) DEFAULT NULL' }, { 'paid_by_name', 'VARCHAR(100) DEFAULT NULL' },
        { 'register_id', 'VARCHAR(50) DEFAULT NULL' }, { 'cancel_reason', 'VARCHAR(255) DEFAULT NULL' },
        { 'dispute_reason', 'VARCHAR(255) DEFAULT NULL' }, { 'import_source', 'VARCHAR(20) DEFAULT NULL' },
        { 'import_id', 'VARCHAR(64) DEFAULT NULL' },
    }) do ensureColumn('nayzeee_billing_invoices', c[1], c[2]) end
    ensureIndex('nayzeee_billing_invoices', 'idx_company', '`company_id`, `created_at`')
    ensureIndex('nayzeee_billing_invoices', 'idx_target_society', '`target_society`, `status`')
    ensureIndex('nayzeee_billing_invoices', 'idx_due', '`status`, `due_date`')
    ensureIndex('nayzeee_billing_invoices', 'idx_import', '`import_source`, `import_id`')
    MySQL.query.await("UPDATE `nayzeee_billing_invoices` SET `amount_paid` = `total` WHERE `status` = 'paid' AND `amount_paid` = 0")

    -- ██████╗  █████╗ ██╗   ██╗███╗   ███╗███████╗███╗   ██╗████████╗███████╗
    -- ██╔══██╗██╔══██╗╚██╗ ██╔╝████╗ ████║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
    -- ██████╔╝███████║ ╚████╔╝ ██╔████╔██║█████╗  ██╔██╗ ██║   ██║   ███████╗
    -- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║   ╚════██║
    -- ██║     ██║  ██║   ██║   ██║ ╚═╝ ██║███████╗██║ ╚████║   ██║   ███████║
    -- ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_payments` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `invoice_id` VARCHAR(24) NOT NULL,
            `company_id` VARCHAR(50) DEFAULT NULL,
            `target_society` VARCHAR(50) DEFAULT NULL,
            `sender_identifier` VARCHAR(64) DEFAULT NULL,
            `payer_identifier` VARCHAR(64) NOT NULL,
            `payer_name` VARCHAR(100) DEFAULT NULL,
            `amount` DECIMAL(15,2) NOT NULL,
            `tip` DECIMAL(15,2) DEFAULT 0,
            `method` VARCHAR(20) DEFAULT 'bank',
            `kind` VARCHAR(20) DEFAULT 'payment',
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_invoice` (`invoice_id`),
            INDEX `idx_company_date` (`company_id`, `created_at`),
            INDEX `idx_payer_date` (`payer_identifier`, `created_at`),
            INDEX `idx_sender_date` (`sender_identifier`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    ensureColumn('nayzeee_billing_payments', 'target_society', 'VARCHAR(50) DEFAULT NULL')
    ensureIndex('nayzeee_billing_payments', 'idx_target_society_date', '`target_society`, `created_at`')

    -- ████████╗███████╗███╗   ███╗██████╗ ██╗      █████╗ ████████╗███████╗███████╗
    -- ╚══██╔══╝██╔════╝████╗ ████║██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
    --    ██║   █████╗  ██╔████╔██║██████╔╝██║     ███████║   ██║   █████╗  ███████╗
    --    ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
    --    ██║   ███████╗██║ ╚═╝ ██║██║     ███████╗██║  ██║   ██║   ███████╗███████║
    --    ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_templates` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `owner_type` VARCHAR(10) NOT NULL,
            `owner` VARCHAR(64) NOT NULL,
            `name` VARCHAR(60) NOT NULL,
            `icon` VARCHAR(30) DEFAULT 'file',
            `color` VARCHAR(20) DEFAULT 'teal',
            `items` LONGTEXT,
            `sort` INT DEFAULT 0,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_owner` (`owner_type`, `owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- ██████╗ ███████╗██████╗ ███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
    -- ██╔══██╗██╔════╝██╔══██╗████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
    -- ██████╔╝█████╗  ██████╔╝██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
    -- ██╔═══╝ ██╔══╝  ██╔══██╗██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
    -- ██║     ███████╗██║  ██║██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║███████║
    -- ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_groups` (
            `society` VARCHAR(50) NOT NULL,
            `group_id` VARCHAR(40) NOT NULL,
            `label` VARCHAR(40) NOT NULL,
            `access` VARCHAR(10) DEFAULT 'normal',
            `icon` VARCHAR(30) DEFAULT 'users',
            `color` VARCHAR(20) DEFAULT 'gray',
            `perms` LONGTEXT,
            `sort` INT DEFAULT 0,
            PRIMARY KEY (`society`, `group_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_members` (
            `society` VARCHAR(50) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `group_id` VARCHAR(40) NOT NULL,
            PRIMARY KEY (`society`, `identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_meta` (
            `k` VARCHAR(80) PRIMARY KEY,
            `v` VARCHAR(255) DEFAULT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- ██████╗  █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗███████╗
    -- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔════╝
    -- ██████╔╝███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║   ███████╗
    -- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║   ╚════██║
    -- ██║     ██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║   ███████║
    -- ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_pending_payouts` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(64) NOT NULL,
            `amount` DECIMAL(15,2) NOT NULL,
            `invoice_id` VARCHAR(24) NOT NULL,
            `payment_method` VARCHAR(20) DEFAULT 'bank',
            `requires_collection` TINYINT(1) DEFAULT 0,
            `reason` VARCHAR(100) DEFAULT NULL,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    ensureColumn('nayzeee_billing_pending_payouts', 'payment_method', "VARCHAR(20) DEFAULT 'bank'")
    ensureColumn('nayzeee_billing_pending_payouts', 'requires_collection', 'TINYINT(1) DEFAULT 0')
    ensureColumn('nayzeee_billing_pending_payouts', 'reason', 'VARCHAR(100) DEFAULT NULL')

    -- ██╗      ██████╗  ██████╗ ███████╗
    -- ██║     ██╔═══██╗██╔════╝ ██╔════╝
    -- ██║     ██║   ██║██║  ███╗███████╗
    -- ██║     ██║   ██║██║   ██║╚════██║
    -- ███████╗╚██████╔╝╚██████╔╝███████║
    -- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_logs` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `player` VARCHAR(100) NOT NULL,
            `identifier` VARCHAR(64) DEFAULT NULL,
            `company_id` VARCHAR(50) DEFAULT NULL,
            `action` VARCHAR(50) NOT NULL,
            `data` LONGTEXT DEFAULT NULL,
            `timestamp` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_action` (`action`),
            INDEX `idx_timestamp` (`timestamp`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    if column('nayzeee_billing_logs', 'player_name') and not column('nayzeee_billing_logs', 'player') then
        MySQL.query.await('ALTER TABLE `nayzeee_billing_logs` CHANGE COLUMN `player_name` `player` VARCHAR(100) NOT NULL')
    end
    ensureColumn('nayzeee_billing_logs', 'identifier', 'VARCHAR(64) DEFAULT NULL')
    ensureColumn('nayzeee_billing_logs', 'company_id', 'VARCHAR(50) DEFAULT NULL')
    ensureIndex('nayzeee_billing_logs', 'idx_identifier', '`identifier`, `id`')
    ensureIndex('nayzeee_billing_logs', 'idx_company', '`company_id`, `id`')

    -- ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗ ███████╗
    -- ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
    -- ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝███████╗
    -- ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗╚════██║
    -- ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║███████║
    -- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_registers` (
            `id` VARCHAR(50) PRIMARY KEY,
            `label` VARCHAR(100) NOT NULL,
            `company` VARCHAR(50) NOT NULL,
            `x` DECIMAL(10,2) NOT NULL,
            `y` DECIMAL(10,2) NOT NULL,
            `z` DECIMAL(10,2) NOT NULL,
            `heading` DECIMAL(5,1) DEFAULT 0,
            `radius` DECIMAL(4,2) DEFAULT 2.00,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    ensureColumn('nayzeee_billing_registers', 'radius', 'DECIMAL(4,2) DEFAULT 2.00')

    DB.ready = true
    print('^2[NAYZEEE-BILLING]^7 Database ready')
end)

function DB.Await()
    while not DB.ready do Wait(100) end
end

function DB.Meta(key, value)
    if value == nil then return MySQL.scalar.await('SELECT v FROM nayzeee_billing_meta WHERE k = ?', { key }) end
    MySQL.insert.await('INSERT INTO nayzeee_billing_meta (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { key, tostring(value) })
end
