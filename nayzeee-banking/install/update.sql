-- ═══════════════════════════════════════════════════════════
--  NAYZEEE BANKING — patch an existing install
--
--  Run this once against a database that was created before the
--  newer columns existed. It is safe to run as many times as you
--  like: each step checks whether the column is already there and
--  skips it if so.
--
--  Works on MySQL 5.7, MySQL 8 and MariaDB. Do not import this on
--  a fresh install — install.sql already has everything.
-- ═══════════════════════════════════════════════════════════

-- A column is added only when INFORMATION_SCHEMA says it is
-- missing. "ADD COLUMN IF NOT EXISTS" is MariaDB-only; MySQL 8
-- rejects the whole statement, which silently leaves the database
-- half-migrated. This works everywhere.
DROP PROCEDURE IF EXISTS nz_bank_add_column;

DELIMITER //
CREATE PROCEDURE nz_bank_add_column(
    IN tbl  VARCHAR(64),
    IN col  VARCHAR(64),
    IN spec VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = tbl
          AND COLUMN_NAME  = col
    ) THEN
        SET @ddl = CONCAT('ALTER TABLE `', tbl, '` ADD COLUMN `', col, '` ', spec);
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END //
DELIMITER ;

-- ── Loan anti-churn ─────────────────────────────────────────
CALL nz_bank_add_column('nz_bank_loans', 'started_at',  'BIGINT(20) NOT NULL DEFAULT 0');
CALL nz_bank_add_column('nz_bank_loans', 'closed_at',   'BIGINT(20) NOT NULL DEFAULT 0');
CALL nz_bank_add_column('nz_bank_loans', 'last_credit', 'BIGINT(20) NOT NULL DEFAULT 0');
CALL nz_bank_add_column('nz_bank_loans', 'paid_count',  'INT(11) NOT NULL DEFAULT 0');

-- existing loans get a sensible start time rather than 1970
UPDATE `nz_bank_loans` SET `started_at` = UNIX_TIMESTAMP(`created_at`) WHERE `started_at` = 0;

-- ── Who a transfer went to ──────────────────────────────────
-- Feeds the phone app's "Recent" list.
CALL nz_bank_add_column('nz_bank_transactions', 'counterparty',      'VARCHAR(24) DEFAULT NULL');
CALL nz_bank_add_column('nz_bank_transactions', 'counterparty_name', 'VARCHAR(64) DEFAULT NULL');

-- ── Overdraft protection ────────────────────────────────────
CALL nz_bank_add_column('nz_bank_accounts', 'od_since', 'BIGINT(20) NOT NULL DEFAULT 0');
CALL nz_bank_add_column('nz_bank_accounts', 'od_fees',  'BIGINT(20) NOT NULL DEFAULT 0');
CALL nz_bank_add_column('nz_bank_settings', 'overdraft', 'TINYINT(1) NOT NULL DEFAULT 0');

-- ── Statements ──────────────────────────────────────────────
-- Statements read each row's running balance, which rows written
-- before that column existed do not carry. Nothing to migrate: a
-- statement covering a period from before this update opens at zero.

-- ── One personal and one savings account per player ─────────
-- Two requests racing on join could each open a personal account
-- with the starting money in it. The code now waits its turn, and
-- this key makes the database refuse a second one as well.
CALL nz_bank_add_column('nz_bank_accounts', 'uniq_key',
    'VARCHAR(80) GENERATED ALWAYS AS (CASE WHEN `type` IN (''personal'',''savings'') THEN CONCAT(`owner`, '':'', `type`) END) STORED');

-- The key is only added when no player already has two. Nothing is
-- merged or deleted for you: if this lists rows, move each player's
-- money into the oldest account (lowest id), delete the others, and
-- run this file again.
DROP PROCEDURE IF EXISTS nz_bank_add_unique;

DELIMITER //
CREATE PROCEDURE nz_bank_add_unique()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'nz_bank_accounts'
          AND INDEX_NAME   = 'uniq_key'
    ) THEN
        IF EXISTS (
            SELECT `uniq_key` FROM `nz_bank_accounts`
            WHERE `uniq_key` IS NOT NULL
            GROUP BY `uniq_key` HAVING COUNT(*) > 1
        ) THEN
            SELECT `owner`, `type`, COUNT(*) AS accounts,
                   GROUP_CONCAT(`id` ORDER BY `id`) AS ids,
                   GROUP_CONCAT(`balance` ORDER BY `id`) AS balances,
                   'merge into the first id, delete the rest, re-run update.sql' AS todo
            FROM `nz_bank_accounts`
            WHERE `uniq_key` IS NOT NULL
            GROUP BY `owner`, `type` HAVING COUNT(*) > 1;
        ELSE
            ALTER TABLE `nz_bank_accounts` ADD UNIQUE KEY `uniq_key` (`uniq_key`);
        END IF;
    END IF;
END //
DELIMITER ;

CALL nz_bank_add_unique();
DROP PROCEDURE IF EXISTS nz_bank_add_unique;

-- ── Saved payees ────────────────────────────────────────────
-- The resource also creates this on start; here for databases where it can't.
CREATE TABLE IF NOT EXISTS `nz_bank_payees` (
  `id`             INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`     VARCHAR(64) NOT NULL,
  `label`          VARCHAR(32) NOT NULL,
  `account_number` VARCHAR(24) NOT NULL,
  `last_used`      BIGINT(20) NOT NULL DEFAULT 0,
  `created_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `payee` (`identifier`, `account_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS nz_bank_add_column;

-- ── Check it worked ─────────────────────────────────────────
-- This should list six rows. If any are missing, the resource will
-- say so in the server console on start and switch that feature
-- off rather than breaking.
SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND (
    (TABLE_NAME = 'nz_bank_transactions' AND COLUMN_NAME IN ('counterparty','counterparty_name'))
 OR (TABLE_NAME = 'nz_bank_accounts'     AND COLUMN_NAME IN ('od_since','od_fees'))
 OR (TABLE_NAME = 'nz_bank_settings'     AND COLUMN_NAME = 'overdraft')
 OR (TABLE_NAME = 'nz_bank_loans'        AND COLUMN_NAME = 'paid_count')
  )
ORDER BY TABLE_NAME, COLUMN_NAME;
