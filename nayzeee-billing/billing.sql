-- ═══════════════════════════════════════════════════════════════════════════════
-- NAYZEEE BILLING 1.0.0 - Database schema reference
--
-- Tables are created and upgraded automatically on resource start (server/database.lua).
-- You do NOT need to run this file. older installs are upgraded in place.
-- ═══════════════════════════════════════════════════════════════════════════════

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
    `share` DECIMAL(15,2) DEFAULT 0,
    `vat_routed` DECIMAL(15,2) DEFAULT 0,
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_invoice` (`invoice_id`),
    INDEX `idx_company_date` (`company_id`, `created_at`),
    INDEX `idx_payer_date` (`payer_identifier`, `created_at`),
    INDEX `idx_sender_date` (`sender_identifier`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

CREATE TABLE IF NOT EXISTS `nayzeee_billing_members` (
    `society` VARCHAR(50) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `group_id` VARCHAR(40) NOT NULL,
    `grade` INT DEFAULT NULL,
    PRIMARY KEY (`society`, `identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_billing_meta` (
    `k` VARCHAR(80) PRIMARY KEY,
    `v` VARCHAR(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

CREATE TABLE IF NOT EXISTS `nayzeee_billing_registers` (
    `id` VARCHAR(50) PRIMARY KEY,
    `label` VARCHAR(100) NOT NULL,
    `company` VARCHAR(50) NOT NULL,
    `x` DECIMAL(10,2) NOT NULL,
    `y` DECIMAL(10,2) NOT NULL,
    `z` DECIMAL(10,2) NOT NULL,
    `heading` DECIMAL(5,1) DEFAULT 0,
    `radius` DECIMAL(4,2) DEFAULT 2.00,
    `model` VARCHAR(60) DEFAULT NULL,
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
