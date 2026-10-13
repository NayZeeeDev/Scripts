-- ═══════════════════════════════════════════════════════════════════════════
-- NAYZEEE MULTIJOB - Database Installation
-- Tables auto-create on first start, run this manually ONLY if that fails
-- Version: 1.0.0 | Discord: discord.gg/nayzeeedev
-- ═══════════════════════════════════════════════════════════════════════════

-- Main jobs table
CREATE TABLE IF NOT EXISTS `nayzeee_multijob` (
    `identifier` VARCHAR(60) NOT NULL,
    `job` VARCHAR(50) NOT NULL,
    `grade` INT DEFAULT 0,
    `removeable` TINYINT(1) DEFAULT 1,
    `favorite` TINYINT(1) DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `job`),
    INDEX `idx_job` (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Statistics table
CREATE TABLE IF NOT EXISTS `nayzeee_multijob_stats` (
    `identifier` VARCHAR(60) NOT NULL,
    `job` VARCHAR(50) NOT NULL,
    `total_hours` FLOAT DEFAULT 0,
    `total_earnings` INT DEFAULT 0,
    `sessions` INT DEFAULT 0,
    `last_clocked` TIMESTAMP NULL,
    PRIMARY KEY (`identifier`, `job`),
    INDEX `idx_hours` (`total_hours`),
    INDEX `idx_earnings` (`total_earnings`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Activity logs table
CREATE TABLE IF NOT EXISTS `nayzeee_multijob_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(60) NOT NULL,
    `player_name` VARCHAR(100),
    `action` VARCHAR(50) NOT NULL,
    `job` VARCHAR(50),
    `details` TEXT,
    `admin_id` VARCHAR(60),
    `admin_name` VARCHAR(100),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_action` (`action`),
    INDEX `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shift history table
CREATE TABLE IF NOT EXISTS `nayzeee_multijob_shifts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(60) NOT NULL,
    `job` VARCHAR(50) NOT NULL,
    -- explicit DEFAULT stops MariaDB / MySQL 5.7 adding ON UPDATE CURRENT_TIMESTAMP
    `clock_in` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `clock_out` TIMESTAMP NULL,
    `duration_seconds` INT DEFAULT 0,
    `earnings` INT DEFAULT 0,
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_job` (`job`),
    INDEX `idx_open` (`clock_out`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Schedules table
CREATE TABLE IF NOT EXISTS `nayzeee_multijob_schedules` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(60) NOT NULL,
    `job` VARCHAR(50) NOT NULL,
    `grade` INT DEFAULT 0,
    `hour` INT NOT NULL,
    `minute` INT NOT NULL,
    `days` VARCHAR(20) NOT NULL,
    `enabled` TINYINT(1) DEFAULT 1,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Upgrading an older install? Run this once if shift clock-in times show the
-- same time as clock-out (the resource also does this itself on start):
-- ALTER TABLE `nayzeee_multijob_shifts` MODIFY `clock_in` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;
