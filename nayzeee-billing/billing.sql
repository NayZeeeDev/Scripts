-- ═══════════════════════════════════════════════════════════════════════════════
-- NAYZEEE BILLING 2.0 - Database Schema Reference
-- Discord: discord.gg/nayzeeedev
--
-- NOTE: Tables are created AND migrated automatically on resource start
-- (server/database.lua). This file is for reference only - you do NOT need to run it.
-- Upgrading from 1.x keeps all invoices, companies and registers.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Invoices
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
    `status` VARCHAR(20) DEFAULT 'pending',      -- pending / partial / overdue / disputed / paid / cancelled / refunded
    `payment_method` VARCHAR(20) DEFAULT NULL,
    `register_id` VARCHAR(50) DEFAULT NULL,
    `cancel_reason` VARCHAR(255) DEFAULT NULL,
    `dispute_reason` VARCHAR(255) DEFAULT NULL,
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `paid_at` DATETIME DEFAULT NULL,
    `due_date` DATETIME DEFAULT NULL,
    INDEX `idx_sender` (`sender_identifier`),
    INDEX `idx_target` (`target_identifier`),
    INDEX `idx_status` (`status`),
    INDEX `idx_company` (`company_id`, `created_at`),
    INDEX `idx_due` (`status`, `due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Payment ledger (installments, tips, auto-collections, refunds)
CREATE TABLE IF NOT EXISTS `nayzeee_billing_payments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `invoice_id` VARCHAR(20) NOT NULL,
    `company_id` VARCHAR(50) DEFAULT NULL,
    `sender_identifier` VARCHAR(60) DEFAULT NULL,
    `payer_identifier` VARCHAR(60) NOT NULL,
    `payer_name` VARCHAR(100) DEFAULT NULL,
    `amount` DECIMAL(15,2) NOT NULL,             -- negative for refunds
    `tip` DECIMAL(15,2) DEFAULT 0,
    `method` VARCHAR(20) DEFAULT 'bank',
    `kind` VARCHAR(20) DEFAULT 'payment',        -- payment / autocollect / refund
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_invoice` (`invoice_id`),
    INDEX `idx_company_date` (`company_id`, `created_at`),
    INDEX `idx_sender_date` (`sender_identifier`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Companies created / edited in-game (override companies.lua)
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
    `settings` LONGTEXT,                         -- JSON: jobs, account, grades, commission, tips, webhook...
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Pending payouts (offline employees, cash awaiting bank-teller collection)
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

-- Activity log
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

-- Cash registers added in-game (/billingadmin > Registers)
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
