-- ═══════════════════════════════════════════════════════════
--  NAYZEEE BANKING — install
--  Run once. Safe to re-run; nothing is dropped or overwritten.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS `nz_bank_accounts` (
  `id`             INT(11) NOT NULL AUTO_INCREMENT,
  `account_number` VARCHAR(24) NOT NULL,
  `type`           ENUM('personal','shared','society','savings') NOT NULL DEFAULT 'personal',
  `owner`          VARCHAR(64) DEFAULT NULL,          -- identifier, or job name for society
  `label`          VARCHAR(64) NOT NULL,
  `balance`        BIGINT(20) NOT NULL DEFAULT 0,
  `od_since`       BIGINT(20) NOT NULL DEFAULT 0,
  `od_fees`        BIGINT(20) NOT NULL DEFAULT 0,
  `frozen`         TINYINT(1) NOT NULL DEFAULT 0,
  `meta`           LONGTEXT DEFAULT NULL,             -- json: interest, goals
  `created_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_number` (`account_number`),
  KEY `owner` (`owner`),
  KEY `type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_members` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `account_id`   INT(11) NOT NULL,
  `identifier`   VARCHAR(64) NOT NULL,
  `name`         VARCHAR(64) NOT NULL,
  `role`         ENUM('owner','manager','member') NOT NULL DEFAULT 'member',
  `can_deposit`  TINYINT(1) NOT NULL DEFAULT 1,
  `can_withdraw` TINYINT(1) NOT NULL DEFAULT 1,
  `can_transfer` TINYINT(1) NOT NULL DEFAULT 0,
  `added_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `member` (`account_id`,`identifier`),
  KEY `identifier` (`identifier`),
  CONSTRAINT `fk_members_account` FOREIGN KEY (`account_id`)
    REFERENCES `nz_bank_accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_cards` (
  `id`                INT(11) NOT NULL AUTO_INCREMENT,
  `account_id`        INT(11) NOT NULL,
  `card_number`       VARCHAR(24) NOT NULL,
  `card_type`         VARCHAR(24) NOT NULL DEFAULT 'debit',
  `kind`              ENUM('debit','credit','secured') NOT NULL DEFAULT 'debit',
  `holder`            VARCHAR(64) NOT NULL,
  `holder_identifier` VARCHAR(64) DEFAULT NULL,       -- set on a member card
  `pin`               VARCHAR(8) NOT NULL,
  `status`            ENUM('active','blocked','stolen') NOT NULL DEFAULT 'active',
  `daily_limit`       INT(11) NOT NULL DEFAULT 5000,
  `spent_today`       INT(11) NOT NULL DEFAULT 0,
  `spent_day`         DATE DEFAULT NULL,
  `spent_reset`       BIGINT(20) NOT NULL DEFAULT 0,  -- rolling limit window
  `express`           TINYINT(1) NOT NULL DEFAULT 0,
  `is_default`        TINYINT(1) NOT NULL DEFAULT 0,
  `skin`              VARCHAR(16) NOT NULL DEFAULT 'teal',
  `expires`           VARCHAR(8) NOT NULL,
  `credit_limit`      BIGINT(20) NOT NULL DEFAULT 0,
  `balance`           BIGINT(20) NOT NULL DEFAULT 0,  -- owed on a credit line
  `deposit`           BIGINT(20) NOT NULL DEFAULT 0,  -- held on a secured card
  `apr`               DECIMAL(5,3) NOT NULL DEFAULT 0,
  `statement_at`      BIGINT(20) NOT NULL DEFAULT 0,
  `due_at`            BIGINT(20) NOT NULL DEFAULT 0,
  `min_payment`       BIGINT(20) NOT NULL DEFAULT 0,
  `missed`            INT(11) NOT NULL DEFAULT 0,
  `created_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `card_number` (`card_number`),
  KEY `account_id` (`account_id`),
  CONSTRAINT `fk_cards_account` FOREIGN KEY (`account_id`)
    REFERENCES `nz_bank_accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_card_charges` (
  `id`            INT(11) NOT NULL AUTO_INCREMENT,
  `card_id`       INT(11) NOT NULL,
  `direction`     ENUM('charge','payment','interest','fee') NOT NULL DEFAULT 'charge',
  `amount`        BIGINT(20) NOT NULL,
  `balance_after` BIGINT(20) NOT NULL DEFAULT 0,
  `label`         VARCHAR(96) NOT NULL,
  `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `card_id` (`card_id`),
  CONSTRAINT `fk_charges_card` FOREIGN KEY (`card_id`)
    REFERENCES `nz_bank_cards` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_transactions` (
  `id`            INT(11) NOT NULL AUTO_INCREMENT,
  `account_id`    INT(11) NOT NULL,
  `category`      VARCHAR(16) NOT NULL DEFAULT 'deposit',
  `direction`     ENUM('in','out') NOT NULL,
  `amount`        BIGINT(20) NOT NULL,
  `balance_after` BIGINT(20) NOT NULL DEFAULT 0,
  `label`         VARCHAR(96) NOT NULL,
  `actor`         VARCHAR(64) DEFAULT NULL,
  `actor_name`    VARCHAR(64) DEFAULT NULL,
  `counterparty`      VARCHAR(24) DEFAULT NULL,
  `counterparty_name` VARCHAR(64) DEFAULT NULL,
  `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `account_id` (`account_id`),
  KEY `created_at` (`created_at`),
  CONSTRAINT `fk_tx_account` FOREIGN KEY (`account_id`)
    REFERENCES `nz_bank_accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_loans` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64) NOT NULL,
  `account_id`   INT(11) NOT NULL,
  `tier`         VARCHAR(24) NOT NULL,
  `principal`    BIGINT(20) NOT NULL,
  `total_owed`   BIGINT(20) NOT NULL,
  `remaining`    BIGINT(20) NOT NULL,
  `payment`      INT(11) NOT NULL,
  `interest`     DECIMAL(5,3) NOT NULL,
  `term_days`    INT(11) NOT NULL,
  `next_payment` BIGINT(20) NOT NULL,
  `started_at`   BIGINT(20) NOT NULL DEFAULT 0,   -- unix, for the minimum hold
  `closed_at`    BIGINT(20) NOT NULL DEFAULT 0,   -- unix, drives the cooldown
  `last_credit`  BIGINT(20) NOT NULL DEFAULT 0,   -- one credit gain per cycle
  `paid_count`   INT(11) NOT NULL DEFAULT 0,
  `missed`       INT(11) NOT NULL DEFAULT 0,
  `status`       ENUM('active','paid','defaulted') NOT NULL DEFAULT 'active',
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `identifier` (`identifier`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_credit` (
  `identifier` VARCHAR(64) NOT NULL,
  `score`      INT(11) NOT NULL DEFAULT 300,
  `on_time`    INT(11) NOT NULL DEFAULT 0,
  `late`       INT(11) NOT NULL DEFAULT 0,
  `defaults`   INT(11) NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_bills` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64) NOT NULL,          -- who owes
  `issuer_id`    INT(11) DEFAULT NULL,          -- society account that gets paid
  `issuer_label` VARCHAR(64) NOT NULL,
  `sender_name`  VARCHAR(64) DEFAULT NULL,
  `amount`       BIGINT(20) NOT NULL,
  `reason`       VARCHAR(128) NOT NULL,
  `status`       ENUM('pending','paid','overdue','void') NOT NULL DEFAULT 'pending',
  `due_at`       BIGINT(20) NOT NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `identifier` (`identifier`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_scheduled` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64) NOT NULL,
  `from_id`      INT(11) NOT NULL,
  `to_number`    VARCHAR(24) NOT NULL,
  `label`        VARCHAR(64) NOT NULL,
  `amount`       BIGINT(20) NOT NULL,
  `interval_min` INT(11) NOT NULL,
  `next_run`     BIGINT(20) NOT NULL,
  `failures`     INT(11) NOT NULL DEFAULT 0,
  `enabled`      TINYINT(1) NOT NULL DEFAULT 1,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `identifier` (`identifier`),
  KEY `next_run` (`next_run`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_settings` (
  `identifier`     VARCHAR(64) NOT NULL,
  `direct_deposit` TINYINT(1) NOT NULL DEFAULT 1,
  `auto_pay_bills` TINYINT(1) NOT NULL DEFAULT 0,
  `auto_pay_loans` TINYINT(1) NOT NULL DEFAULT 1,
  `notifications`  TINYINT(1) NOT NULL DEFAULT 1,
  `overdraft`      TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_payroll` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `job`          VARCHAR(64) NOT NULL,
  `grade`        INT(11) NOT NULL,
  `grade_label`  VARCHAR(64) NOT NULL,
  `amount`       INT(11) NOT NULL DEFAULT 0,
  `interval_min` INT(11) NOT NULL DEFAULT 60,
  `next_run`     BIGINT(20) NOT NULL DEFAULT 0,
  `enabled`      TINYINT(1) NOT NULL DEFAULT 1,
  `updated_by`   VARCHAR(64) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `job_grade` (`job`,`grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_market` (
  `asset`      VARCHAR(16) NOT NULL,
  `price`      DECIMAL(18,4) NOT NULL,
  `open_price` DECIMAL(18,4) NOT NULL,
  `history`    LONGTEXT DEFAULT NULL,
  `updated_at` BIGINT(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`asset`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_bank_holdings` (
  `id`         INT(11) NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  `asset`      VARCHAR(16) NOT NULL,
  `units`      DECIMAL(18,6) NOT NULL DEFAULT 0,
  `avg_price`  DECIMAL(18,4) NOT NULL DEFAULT 0,
  `realised`   BIGINT(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `holding` (`identifier`,`asset`),
  KEY `identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
