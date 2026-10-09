-- ═══════════════════════════════════════════════════════════
--  NAYZEEE BANKING — uninstall
--  Drops every table this resource created. There is no undo.
--  Take a database backup first.
-- ═══════════════════════════════════════════════════════════

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `nz_bank_card_charges`;
DROP TABLE IF EXISTS `nz_bank_cards`;
DROP TABLE IF EXISTS `nz_bank_transactions`;
DROP TABLE IF EXISTS `nz_bank_members`;
DROP TABLE IF EXISTS `nz_bank_scheduled`;
DROP TABLE IF EXISTS `nz_bank_bills`;
DROP TABLE IF EXISTS `nz_bank_loans`;
DROP TABLE IF EXISTS `nz_bank_credit`;
DROP TABLE IF EXISTS `nz_bank_settings`;
DROP TABLE IF EXISTS `nz_bank_payroll`;
DROP TABLE IF EXISTS `nz_bank_holdings`;
DROP TABLE IF EXISTS `nz_bank_market`;
DROP TABLE IF EXISTS `nz_bank_accounts`;

SET FOREIGN_KEY_CHECKS = 1;
