-- =====================================================================
--  TrueBellaa Commerce Platform — MySQL Schema
--  FILE 00 of 09 : Database creation + global conventions
-- ---------------------------------------------------------------------
--  Target engine : MySQL 8.0+  (also runs on MariaDB 10.5+)
--  Character set : utf8mb4 (full Unicode — required for Hindi / Tamil /
--                  Bengali / emoji). Collation utf8mb4_unicode_ci is
--                  chosen instead of the MySQL-8-only 0900 collation so
--                  the same files load on MariaDB too.
--
--  HOW TO RUN (in order):
--    mysql -u root -p < 00_database_and_settings.sql
--    mysql -u root -p < 01_tenancy_and_rbac.sql
--    ... 02 ... 03 ... up to 08_seed_truebellaa.sql
--  Or from inside the mysql shell:  SOURCE 00_database_and_settings.sql;
--
--  CONVENTIONS used across every file (so the schema stays predictable):
--    * Primary keys    : id  BIGINT UNSIGNED AUTO_INCREMENT  (fast joins)
--    * Public IDs      : public_id CHAR(26)  — a ULID we show to the
--                        outside world (URLs, invoices) so we never leak
--                        "how many orders exist" or expose a guessable id.
--    * Tenant scoping  : EVERY business table carries tenant_id so one
--                        database can safely hold many jewellery brands.
--    * Money           : DECIMAL(12,2) — never FLOAT (floats lose paise).
--    * Timestamps      : created_at / updated_at on almost every table.
--    * Soft delete     : deleted_at (NULL = alive) where history matters.
--    * Foreign keys    : always ON DELETE RESTRICT unless noted, so we
--                        never silently lose linked rows.
-- =====================================================================

-- Create the database (safe to re-run).
CREATE DATABASE IF NOT EXISTS truebellaa
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE truebellaa;

-- Make sure this session behaves strictly and predictably while loading.
SET NAMES utf8mb4;
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION';
SET SESSION time_zone = '+00:00';   -- store everything in UTC; convert in the app.
