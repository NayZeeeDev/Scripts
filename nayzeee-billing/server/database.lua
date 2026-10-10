--[[
    NAYZEEE BILLING - Database Auto-Initialization & Migrations
    Discord: discord.gg/nayzeeedev

    Tables are created / upgraded automatically on resource start (MySQL 5.7+, MySQL 8, MariaDB).
    Upgrading from 1.x keeps all existing invoices, companies and registers.
]]

DB = { ready = false }

local function columnInfo(tbl, column)
    return MySQL.single.await([[
        SELECT DATA_TYPE AS dataType FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tbl, column })
end

-- Portable "ADD COLUMN IF NOT EXISTS" (MySQL 8 doesn't support the MariaDB syntax)
local function ensureColumn(tbl, column, definition)
    if columnInfo(tbl, column) then return end
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, column, definition))
    print(('^3[NAYZEEE-BILLING]^7 Migrated: added %s.%s'):format(tbl, column))
end

local function ensureIndex(tbl, index, columns)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tbl, index })
    if (tonumber(exists) or 0) > 0 then return end
    MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `%s` (%s)'):format(tbl, index, columns))
end

CreateThread(function()
    print('^3[NAYZEEE-BILLING]^7 Initializing database...')

    -- ██╗███╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗███████╗
    -- ██║████╗  ██║██║   ██║██╔═══██╗██║██╔════╝██╔════╝██╔════╝
    -- ██║██╔██╗ ██║██║   ██║██║   ██║██║██║     █████╗  ███████╗
    -- ██║██║╚██╗██║╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ╚════██║
    -- ██║██║ ╚████║ ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████║
    -- ╚═╝╚═╝  ╚═══╝  ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_invoices` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `invoice_id` VARCHAR(20) NOT NULL UNIQUE,
            `company_id` VARCHAR(50) DEFAULT NULL,
            `sender_identifier` VARCHAR(60) NOT NULL,
            `sender_name` VARCHAR(100) NOT NULL,
            `sender_job` VARCHAR(50) DEFAULT NULL,
            `target_identifier` VARCHAR(60) NOT NULL,
            `target_name` VARCHAR(100) NOT NULL,
            `company_name` VARCHAR(100) DEFAULT 'Personal',
            `items` LONGTEXT NOT NULL,
            `notes` TEXT DEFAULT NULL,
            `subtotal` DECIMAL(15,2) DEFAULT 0,
            `tax` DECIMAL(15,2) DEFAULT 0,
            `discount` DECIMAL(15,2) DEFAULT 0,
            `total` DECIMAL(15,2) NOT NULL,
            `late_fee` DECIMAL(15,2) DEFAULT 0,
            `amount_paid` DECIMAL(15,2) DEFAULT 0,
            `tip` DECIMAL(15,2) DEFAULT 0,
            `status` VARCHAR(20) DEFAULT 'pending',
            `payment_method` VARCHAR(20) DEFAULT NULL,
            `register_id` VARCHAR(50) DEFAULT NULL,
            `cancel_reason` VARCHAR(255) DEFAULT NULL,
            `dispute_reason` VARCHAR(255) DEFAULT NULL,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            `paid_at` DATETIME DEFAULT NULL,
            `due_date` DATETIME DEFAULT NULL,
            INDEX `idx_sender` (`sender_identifier`),
            INDEX `idx_target` (`target_identifier`),
            INDEX `idx_status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- 1.x -> 2.0 migrations
    local status = columnInfo('nayzeee_billing_invoices', 'status')
    if status and status.dataType == 'enum' then
        MySQL.query.await("ALTER TABLE `nayzeee_billing_invoices` MODIFY `status` VARCHAR(20) DEFAULT 'pending'")
        print('^3[NAYZEEE-BILLING]^7 Migrated: invoice status enum -> varchar')
    end
    ensureColumn('nayzeee_billing_invoices', 'sender_job', 'VARCHAR(50) DEFAULT NULL AFTER `sender_name`')
    ensureColumn('nayzeee_billing_invoices', 'company_id', 'VARCHAR(50) DEFAULT NULL AFTER `invoice_id`')
    ensureColumn('nayzeee_billing_invoices', 'notes', 'TEXT DEFAULT NULL AFTER `items`')
    ensureColumn('nayzeee_billing_invoices', 'late_fee', 'DECIMAL(15,2) DEFAULT 0 AFTER `total`')
    ensureColumn('nayzeee_billing_invoices', 'amount_paid', 'DECIMAL(15,2) DEFAULT 0 AFTER `late_fee`')
    ensureColumn('nayzeee_billing_invoices', 'tip', 'DECIMAL(15,2) DEFAULT 0 AFTER `amount_paid`')
    ensureColumn('nayzeee_billing_invoices', 'register_id', 'VARCHAR(50) DEFAULT NULL AFTER `payment_method`')
    ensureColumn('nayzeee_billing_invoices', 'cancel_reason', 'VARCHAR(255) DEFAULT NULL AFTER `register_id`')
    ensureColumn('nayzeee_billing_invoices', 'dispute_reason', 'VARCHAR(255) DEFAULT NULL AFTER `cancel_reason`')
    ensureIndex('nayzeee_billing_invoices', 'idx_company', '`company_id`, `created_at`')
    ensureIndex('nayzeee_billing_invoices', 'idx_due', '`status`, `due_date`')

    -- Paid 1.x invoices had no amount_paid
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
            `invoice_id` VARCHAR(20) NOT NULL,
            `company_id` VARCHAR(50) DEFAULT NULL,
            `sender_identifier` VARCHAR(60) DEFAULT NULL,
            `payer_identifier` VARCHAR(60) NOT NULL,
            `payer_name` VARCHAR(100) DEFAULT NULL,
            `amount` DECIMAL(15,2) NOT NULL,
            `tip` DECIMAL(15,2) DEFAULT 0,
            `method` VARCHAR(20) DEFAULT 'bank',
            `kind` VARCHAR(20) DEFAULT 'payment',
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_invoice` (`invoice_id`),
            INDEX `idx_company_date` (`company_id`, `created_at`),
            INDEX `idx_sender_date` (`sender_identifier`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    --  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███╗   ██╗██╗███████╗███████╗
    -- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██╔════╝
    -- ██║     ██║   ██║██╔████╔██║██████╔╝███████║██╔██╗ ██║██║█████╗  ███████╗
    -- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║╚██╗██║██║██╔══╝  ╚════██║
    -- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║ ╚████║██║███████╗███████║
    --  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_companies` (
            `id` VARCHAR(50) PRIMARY KEY,
            `label` VARCHAR(100) NOT NULL,
            `short_name` VARCHAR(10) DEFAULT NULL,
            `logo` VARCHAR(255) DEFAULT NULL,
            `job` VARCHAR(50) DEFAULT NULL,
            `tax_rate` DECIMAL(5,4) DEFAULT 0.0800,
            `allow_discounts` TINYINT(1) DEFAULT 1,
            `categories` LONGTEXT,
            `products` LONGTEXT,
            `quick_bills` LONGTEXT,
            `settings` LONGTEXT,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    ensureColumn('nayzeee_billing_companies', 'quick_bills', 'LONGTEXT AFTER `products`')
    ensureColumn('nayzeee_billing_companies', 'settings', 'LONGTEXT AFTER `quick_bills`')

    -- ██████╗  █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗███████╗
    -- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔════╝
    -- ██████╔╝███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║   ███████╗
    -- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║   ╚════██║
    -- ██║     ██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║   ███████║
    -- ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_billing_pending_payouts` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `amount` DECIMAL(15,2) NOT NULL,
            `invoice_id` VARCHAR(20) NOT NULL,
            `payment_method` VARCHAR(20) DEFAULT 'bank',
            `requires_collection` TINYINT(1) DEFAULT 0,
            `reason` VARCHAR(100) DEFAULT NULL,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_identifier` (`identifier`),
            INDEX `idx_collection` (`requires_collection`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    ensureColumn('nayzeee_billing_pending_payouts', 'payment_method', "VARCHAR(20) DEFAULT 'bank' AFTER `invoice_id`")
    ensureColumn('nayzeee_billing_pending_payouts', 'requires_collection', 'TINYINT(1) DEFAULT 0 AFTER `payment_method`')
    ensureColumn('nayzeee_billing_pending_payouts', 'reason', 'VARCHAR(100) DEFAULT NULL AFTER `requires_collection`')

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
            `identifier` VARCHAR(60) DEFAULT NULL,
            `company_id` VARCHAR(50) DEFAULT NULL,
            `action` VARCHAR(50) NOT NULL,
            `data` LONGTEXT DEFAULT NULL,
            `timestamp` DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_action` (`action`),
            INDEX `idx_timestamp` (`timestamp`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    if columnInfo('nayzeee_billing_logs', 'player_name') and not columnInfo('nayzeee_billing_logs', 'player') then
        MySQL.query.await('ALTER TABLE `nayzeee_billing_logs` CHANGE COLUMN `player_name` `player` VARCHAR(100) NOT NULL')
    end
    ensureColumn('nayzeee_billing_logs', 'identifier', 'VARCHAR(60) DEFAULT NULL AFTER `player`')
    ensureColumn('nayzeee_billing_logs', 'company_id', 'VARCHAR(50) DEFAULT NULL AFTER `identifier`')

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
    ensureColumn('nayzeee_billing_registers', 'radius', 'DECIMAL(4,2) DEFAULT 2.00 AFTER `heading`')

    DB.ready = true
    TriggerEvent('nayzeee-billing:server:dbReady')
    print('^2[NAYZEEE-BILLING]^7 Database ready')
end)

function DB.Await()
    while not DB.ready do Wait(100) end
end
