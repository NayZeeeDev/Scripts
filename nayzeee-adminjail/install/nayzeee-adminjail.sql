-- NAYZEEE Admin Jail v2 — optional, the resource creates these tables on start.

CREATE TABLE IF NOT EXISTS `nayzeee_adminjail_active` (
    `identifier`     VARCHAR(80)  NOT NULL PRIMARY KEY,
    `name`           VARCHAR(100) NULL,
    `account`        VARCHAR(100) NULL,
    `reason`         VARCHAR(255) NULL,
    `admin`          VARCHAR(100) NULL,
    `location`       VARCHAR(50)  NOT NULL,
    `total`          INT          NOT NULL,
    `remaining`      INT          NOT NULL,
    `escapes`        INT          NOT NULL DEFAULT 0,
    `cycles`         INT          NOT NULL DEFAULT 0,
    `reduced`        INT          NOT NULL DEFAULT 0,
    `hour_start`     INT          NOT NULL DEFAULT 0,
    `hour_reduced`   INT          NOT NULL DEFAULT 0,
    `return_coords`  VARCHAR(100) NULL,
    `jailed_at`      INT          NOT NULL,
    `updated_at`     INT          NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nayzeee_adminjail_log` (
    `id`           INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `identifier`   VARCHAR(80)  NOT NULL,
    `name`         VARCHAR(100) NULL,
    `account`      VARCHAR(100) NULL,
    `reason`       VARCHAR(255) NULL,
    `admin`        VARCHAR(100) NULL,
    `location`     VARCHAR(50)  NULL,
    `total`        INT          NOT NULL DEFAULT 0,
    `served`       INT          NOT NULL DEFAULT 0,
    `escapes`      INT          NOT NULL DEFAULT 0,
    `cycles`       INT          NOT NULL DEFAULT 0,
    `reduced`      INT          NOT NULL DEFAULT 0,
    `outcome`      VARCHAR(20)  NOT NULL,
    `released_by`  VARCHAR(100) NULL,
    `jailed_at`    INT          NOT NULL,
    `released_at`  INT          NOT NULL,
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_name` (`name`),
    INDEX `idx_admin` (`admin`),
    INDEX `idx_jailed_at` (`jailed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
