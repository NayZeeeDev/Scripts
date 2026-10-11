-- ═══════════════════════════════════════════════════════════
--  NAYZEEE MDT — schema
--  Run once. Safe to re-run (IF NOT EXISTS everywhere).
-- ═══════════════════════════════════════════════════════════

-- ── officers ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_officers` (
  `identifier`   VARCHAR(64) NOT NULL,
  `name`         VARCHAR(64) NOT NULL,
  `department`   VARCHAR(32) NOT NULL,
  `rank`         VARCHAR(48) DEFAULT NULL,
  `badge`        VARCHAR(24) DEFAULT NULL,
  `callsign`     VARCHAR(16) DEFAULT NULL,
  `on_duty`      TINYINT(1) NOT NULL DEFAULT 0,
  `status`       VARCHAR(16) NOT NULL DEFAULT 'available',
  `duty_seconds` INT(11) NOT NULL DEFAULT 0,
  `last_on`      BIGINT(20) DEFAULT NULL,
  `last_seen`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`),
  KEY `department` (`department`),
  KEY `on_duty` (`on_duty`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── citizens ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_citizens` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64) DEFAULT NULL,
  `citizen_id`   VARCHAR(32) NOT NULL,
  `first_name`   VARCHAR(48) NOT NULL,
  `last_name`    VARCHAR(48) NOT NULL,
  `dob`          VARCHAR(16) DEFAULT NULL,
  `gender`       VARCHAR(16) DEFAULT NULL,
  `phone`        VARCHAR(24) DEFAULT NULL,
  `job`          VARCHAR(48) DEFAULT NULL,
  `address`      VARCHAR(96) DEFAULT NULL,
  `height`       VARCHAR(16) DEFAULT NULL,
  `hair`         VARCHAR(24) DEFAULT NULL,
  `eyes`         VARCHAR(24) DEFAULT NULL,
  `mugshot`      VARCHAR(255) DEFAULT NULL,
  `licences`     LONGTEXT DEFAULT NULL,   -- json { drive: 'valid'|'suspended'|'revoked'|'none' }
  `flags`        LONGTEXT DEFAULT NULL,   -- json array of {label, tone, by, at}
  `fingerprint`  VARCHAR(48) DEFAULT NULL,
  `dna`          VARCHAR(48) DEFAULT NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `citizen_id` (`citizen_id`),
  KEY `identifier` (`identifier`),
  KEY `name` (`last_name`,`first_name`),
  KEY `phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── vehicles ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_vehicles` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `plate`        VARCHAR(16) NOT NULL,
  `model`        VARCHAR(48) DEFAULT NULL,
  `type`         VARCHAR(32) DEFAULT NULL,
  `colour`       VARCHAR(32) DEFAULT NULL,
  `vin`          VARCHAR(32) DEFAULT NULL,
  `owner_id`     VARCHAR(32) DEFAULT NULL,   -- nz_mdt_citizens.citizen_id
  `owner_name`   VARCHAR(96) DEFAULT NULL,
  `insurance`    VARCHAR(24) NOT NULL DEFAULT 'unknown',  -- valid|expired|none|unknown
  `registration` VARCHAR(24) NOT NULL DEFAULT 'valid',    -- valid|expired|revoked
  `stolen`       TINYINT(1) NOT NULL DEFAULT 0,
  `impounded`    TINYINT(1) NOT NULL DEFAULT 0,
  `flags`        LONGTEXT DEFAULT NULL,
  `photo`        VARCHAR(255) DEFAULT NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plate` (`plate`),
  KEY `owner_id` (`owner_id`),
  KEY `stolen` (`stolen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── weapons ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_weapons` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `serial`       VARCHAR(32) NOT NULL,
  `label`        VARCHAR(64) NOT NULL,
  `weapon_name`  VARCHAR(64) DEFAULT NULL,
  `owner_id`     VARCHAR(32) DEFAULT NULL,
  `owner_name`   VARCHAR(96) DEFAULT NULL,
  `status`       VARCHAR(24) NOT NULL DEFAULT 'registered', -- registered|stolen|seized|destroyed
  `flags`        LONGTEXT DEFAULT NULL,
  `registered_at`TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `serial` (`serial`),
  KEY `owner_id` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── properties ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_properties` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `label`       VARCHAR(96) NOT NULL,
  `address`     VARCHAR(128) NOT NULL,
  `type`        VARCHAR(32) NOT NULL DEFAULT 'residential',
  `owner_id`    VARCHAR(32) DEFAULT NULL,
  `owner_name`  VARCHAR(96) DEFAULT NULL,
  `coords`      VARCHAR(64) DEFAULT NULL,
  `flags`       LONGTEXT DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `owner_id` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── dispatch ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_dispatch` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `ref`         VARCHAR(24) NOT NULL,
  `type`        VARCHAR(32) NOT NULL,
  `title`       VARCHAR(96) NOT NULL,
  `code`        VARCHAR(16) DEFAULT NULL,
  `priority`    TINYINT(1) NOT NULL DEFAULT 3,
  `status`      VARCHAR(16) NOT NULL DEFAULT 'pending',  -- pending|assigned|onscene|closed
  `street`      VARCHAR(96) DEFAULT NULL,
  `postal`      VARCHAR(16) DEFAULT NULL,
  `x`           FLOAT DEFAULT NULL,
  `y`           FLOAT DEFAULT NULL,
  `z`           FLOAT DEFAULT NULL,
  `detail`      TEXT DEFAULT NULL,
  `caller`      VARCHAR(96) DEFAULT NULL,
  `caller_id`   VARCHAR(64) DEFAULT NULL,
  `plate`       VARCHAR(16) DEFAULT NULL,
  `departments` VARCHAR(128) DEFAULT NULL,
  `closed_by`   VARCHAR(96) DEFAULT NULL,
  `closed_note` VARCHAR(255) DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `closed_at`   TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ref` (`ref`),
  KEY `status` (`status`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_mdt_dispatch_units` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `dispatch_id` INT(11) NOT NULL,
  `identifier`  VARCHAR(64) NOT NULL,
  `name`        VARCHAR(96) NOT NULL,
  `callsign`    VARCHAR(16) DEFAULT NULL,
  `department`  VARCHAR(32) DEFAULT NULL,
  `status`      VARCHAR(16) NOT NULL DEFAULT 'enroute',
  `attached_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unit` (`dispatch_id`,`identifier`),
  CONSTRAINT `fk_units_dispatch` FOREIGN KEY (`dispatch_id`)
    REFERENCES `nz_mdt_dispatch` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── BOLOs ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_bolos` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `title`       VARCHAR(96) NOT NULL,
  `kind`        VARCHAR(24) NOT NULL DEFAULT 'vehicle',   -- vehicle|person|property
  `plate`       VARCHAR(16) DEFAULT NULL,
  `model`       VARCHAR(48) DEFAULT NULL,
  `citizen_id`  VARCHAR(32) DEFAULT NULL,
  `detail`      TEXT DEFAULT NULL,
  `priority`    TINYINT(1) NOT NULL DEFAULT 2,
  `status`      VARCHAR(16) NOT NULL DEFAULT 'active',    -- active|resolved|expired
  `issued_by`   VARCHAR(96) NOT NULL,
  `issuer_id`   VARCHAR(64) DEFAULT NULL,
  `resolved_by` VARCHAR(96) DEFAULT NULL,
  `expires_at`  BIGINT(20) DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `status` (`status`),
  KEY `plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── warrants ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_warrants` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `citizen_id`  VARCHAR(32) NOT NULL,
  `citizen_name`VARCHAR(96) NOT NULL,
  `type`        VARCHAR(24) NOT NULL DEFAULT 'arrest',
  `title`       VARCHAR(96) NOT NULL,
  `detail`      TEXT DEFAULT NULL,
  `charges`     LONGTEXT DEFAULT NULL,   -- json array of charge ids
  `status`      VARCHAR(16) NOT NULL DEFAULT 'active',   -- active|executed|expired|void
  `issued_by`   VARCHAR(96) NOT NULL,
  `issuer_id`   VARCHAR(64) DEFAULT NULL,
  `executed_by` VARCHAR(96) DEFAULT NULL,
  `expires_at`  BIGINT(20) DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `citizen_id` (`citizen_id`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── incidents ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_incidents` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `ref`          VARCHAR(24) NOT NULL,
  `title`        VARCHAR(96) NOT NULL,
  `detail`       TEXT DEFAULT NULL,
  `location`     VARCHAR(128) DEFAULT NULL,
  `status`       VARCHAR(16) NOT NULL DEFAULT 'open',    -- open|pending|closed
  `primary_id`   VARCHAR(32) DEFAULT NULL,
  `primary_name` VARCHAR(96) DEFAULT NULL,
  `total_fine`   INT(11) NOT NULL DEFAULT 0,
  `total_jail`   INT(11) NOT NULL DEFAULT 0,
  `created_by`   VARCHAR(96) NOT NULL,
  `creator_id`   VARCHAR(64) DEFAULT NULL,
  `closed_by`    VARCHAR(96) DEFAULT NULL,
  `dispatch_ref` VARCHAR(24) DEFAULT NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `closed_at`    TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ref` (`ref`),
  KEY `status` (`status`),
  KEY `primary_id` (`primary_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_mdt_incident_people` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `incident_id` INT(11) NOT NULL,
  `citizen_id`  VARCHAR(32) NOT NULL,
  `name`        VARCHAR(96) NOT NULL,
  `role`        VARCHAR(24) NOT NULL DEFAULT 'suspect',  -- suspect|victim|witness|officer
  `notes`       VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `person` (`incident_id`,`citizen_id`,`role`),
  CONSTRAINT `fk_people_incident` FOREIGN KEY (`incident_id`)
    REFERENCES `nz_mdt_incidents` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_mdt_incident_charges` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `incident_id` INT(11) NOT NULL,
  `citizen_id`  VARCHAR(32) NOT NULL,
  `charge_id`   VARCHAR(48) NOT NULL,
  `label`       VARCHAR(96) NOT NULL,
  `class`       VARCHAR(24) NOT NULL DEFAULT 'misdemeanor',
  `counts`      INT(11) NOT NULL DEFAULT 1,
  `fine`        INT(11) NOT NULL DEFAULT 0,
  `jail`        INT(11) NOT NULL DEFAULT 0,
  `reduced`     TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `incident_id` (`incident_id`),
  CONSTRAINT `fk_charges_incident` FOREIGN KEY (`incident_id`)
    REFERENCES `nz_mdt_incidents` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── evidence ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_evidence` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `ref`          VARCHAR(24) NOT NULL,
  `description`  VARCHAR(160) NOT NULL,
  `type`         VARCHAR(32) NOT NULL DEFAULT 'physical',
  `location`     VARCHAR(128) DEFAULT NULL,
  `locker`       VARCHAR(64) DEFAULT NULL,
  `incident_id`  INT(11) DEFAULT NULL,
  `collected_by` VARCHAR(96) NOT NULL,
  `status`       VARCHAR(24) NOT NULL DEFAULT 'in',       -- in|out|released|destroyed
  `holder`       VARCHAR(96) DEFAULT NULL,
  `photos`       LONGTEXT DEFAULT NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ref` (`ref`),
  KEY `incident_id` (`incident_id`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_mdt_evidence_chain` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `evidence_id` INT(11) NOT NULL,
  `action`      VARCHAR(32) NOT NULL,
  `actor`       VARCHAR(96) NOT NULL,
  `note`        VARCHAR(255) DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `evidence_id` (`evidence_id`),
  CONSTRAINT `fk_chain_evidence` FOREIGN KEY (`evidence_id`)
    REFERENCES `nz_mdt_evidence` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── notes (attach to any record type) ───────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_notes` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `subject`     VARCHAR(32) NOT NULL,   -- citizen|vehicle|weapon|property|incident|evidence|bolo|warrant
  `subject_id`  VARCHAR(48) NOT NULL,
  `body`        TEXT NOT NULL,
  `visibility`  VARCHAR(16) NOT NULL DEFAULT 'department', -- department|command|private
  `author`      VARCHAR(96) NOT NULL,
  `author_id`   VARCHAR(64) DEFAULT NULL,
  `department`  VARCHAR(32) DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `subject` (`subject`,`subject_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── announcements ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_announcements` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `title`       VARCHAR(96) NOT NULL,
  `body`        TEXT NOT NULL,
  `pinned`      TINYINT(1) NOT NULL DEFAULT 0,
  `department`  VARCHAR(32) DEFAULT NULL,   -- null = all departments
  `author`      VARCHAR(96) NOT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `department` (`department`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── audit ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `nz_mdt_audit` (
  `id`          INT(11) NOT NULL AUTO_INCREMENT,
  `actor`       VARCHAR(96) NOT NULL,
  `actor_id`    VARCHAR(64) DEFAULT NULL,
  `department`  VARCHAR(32) DEFAULT NULL,
  `action`      VARCHAR(48) NOT NULL,
  `subject`     VARCHAR(32) DEFAULT NULL,
  `subject_id`  VARCHAR(48) DEFAULT NULL,
  `detail`      VARCHAR(255) DEFAULT NULL,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `created_at` (`created_at`),
  KEY `actor_id` (`actor_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════
--  PHOTOS — screenshots attached to any record
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS `nz_mdt_photos` (
    `id`          INT NOT NULL AUTO_INCREMENT,
    `subject`     VARCHAR(24) NOT NULL,
    `subject_id`  VARCHAR(48) NOT NULL,
    `url`         VARCHAR(400) NOT NULL,
    `host_id`     VARCHAR(120) DEFAULT NULL,
    `description` VARCHAR(200) DEFAULT NULL,
    `is_avatar`   TINYINT(1) NOT NULL DEFAULT 0,
    `taken_by`    VARCHAR(90) DEFAULT NULL,
    `taker_id`    VARCHAR(60) DEFAULT NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `subject_idx` (`subject`, `subject_id`),
    KEY `avatar_idx` (`subject`, `subject_id`, `is_avatar`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════
--  ENTITY LINKS — two-way relationships between records
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS `nz_mdt_links` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `from_type`  VARCHAR(24) NOT NULL,
    `from_id`    VARCHAR(48) NOT NULL,
    `to_type`    VARCHAR(24) NOT NULL,
    `to_id`      VARCHAR(48) NOT NULL,
    `note`       VARCHAR(200) DEFAULT NULL,
    `linked_by`  VARCHAR(90) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `pair` (`from_type`, `from_id`, `to_type`, `to_id`),
    KEY `from_idx` (`from_type`, `from_id`),
    KEY `to_idx` (`to_type`, `to_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════
--  CAMERAS — placed CCTV
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS `nz_mdt_cameras` (
    `id`          INT NOT NULL AUTO_INCREMENT,
    `cam_id`      VARCHAR(40) NOT NULL,
    `label`       VARCHAR(90) NOT NULL,
    `model`       VARCHAR(60) NOT NULL DEFAULT 'prop_cctv_cam_01a',
    `x`           FLOAT NOT NULL,
    `y`           FLOAT NOT NULL,
    `z`           FLOAT NOT NULL,
    `rx`          FLOAT NOT NULL DEFAULT 0,
    `ry`          FLOAT NOT NULL DEFAULT 0,
    `rz`          FLOAT NOT NULL DEFAULT 0,
    `departments` TEXT DEFAULT NULL,
    `status`      ENUM('online','destroyed') NOT NULL DEFAULT 'online',
    `fixed`       TINYINT(1) NOT NULL DEFAULT 0,
    `placed_by`   VARCHAR(90) DEFAULT NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `cam_id` (`cam_id`),
    KEY `status_idx` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bulletins can expire on their own.
ALTER TABLE `nz_mdt_announcements`
  ADD COLUMN IF NOT EXISTS `expires_at` BIGINT(20) DEFAULT NULL;
