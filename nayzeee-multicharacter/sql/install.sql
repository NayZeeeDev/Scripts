-- nayzeee-multicharacter creates these tables by itself on first start.
-- Run this file only if your database user can not CREATE TABLE.

CREATE TABLE IF NOT EXISTS `nayzeee_multichar` (
    `charid`       VARCHAR(80)  NOT NULL,
    `owner`        VARCHAR(80)  NOT NULL,
    `playtime`     INT UNSIGNED NOT NULL DEFAULT 0,
    `last_played`  INT UNSIGNED NULL DEFAULT NULL,
    `created_at`   INT UNSIGNED NULL DEFAULT NULL,
    `nationality`  VARCHAR(48)  NULL DEFAULT NULL,
    `height`       SMALLINT UNSIGNED NULL DEFAULT NULL,
    `backstory`    TEXT         NULL DEFAULT NULL,
    `pose`         VARCHAR(32)  NULL DEFAULT NULL,
    `favorite`     TINYINT(1)   NOT NULL DEFAULT 0,
    `disabled`     TINYINT(1)   NOT NULL DEFAULT 0,
    `partner`      VARCHAR(80)  NULL DEFAULT NULL,
    `partner_type` VARCHAR(12)  NULL DEFAULT NULL,
    PRIMARY KEY (`charid`),
    INDEX `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_multichar_slots` (
    `owner` VARCHAR(80) NOT NULL,
    `extra` TINYINT NOT NULL DEFAULT 0,
    `note`  VARCHAR(128) NULL DEFAULT NULL,
    PRIMARY KEY (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_multichar_redeem` (
    `tid`         VARCHAR(80) NOT NULL,
    `owner`       VARCHAR(80) NOT NULL,
    `slots`       TINYINT     NOT NULL DEFAULT 0,
    `redeemed_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`tid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
