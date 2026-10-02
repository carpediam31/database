-- =====================================================================
--  FILE 10 : Product image uploads (MilesWeb file storage) — Add-on
-- ---------------------------------------------------------------------
--  Adds to what 02_catalog.sql already created:
--    * product_images gets media metadata (size, extension, storage path,
--      who uploaded it) so the admin panel can show that next to every
--      image, not just its URL.
--    * a new `product.image_upload` permission, granted to Admin + Manager
--      by default. Give it to Sales too from the admin panel's
--      Roles & Permissions screen (Permissions.jsx) — no SQL needed for
--      that, it's exactly what that screen is for.
--
--  Safe to run on a database that already executed files 00-09: every
--  statement below is idempotent (checks INFORMATION_SCHEMA / uses
--  INSERT IGNORE) so re-running this file is a no-op the second time.
--  If you are provisioning a BRAND NEW database, running 00-09 is enough
--  — 02_catalog.sql already has these columns baked in — this file only
--  exists to upgrade an existing install.
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

-- ---- product_images: add media metadata columns if missing ----------
SET @col_exists := (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'product_images' AND COLUMN_NAME = 'file_size_bytes'
);
SET @sql := IF(@col_exists = 0, '
  ALTER TABLE product_images
    ADD COLUMN original_filename VARCHAR(255) NULL COMMENT ''filename as uploaded from the admin panel'' AFTER is_primary,
    ADD COLUMN file_extension    VARCHAR(10)  NULL COMMENT ''jpg | png | webp | gif'' AFTER original_filename,
    ADD COLUMN file_size_bytes   INT UNSIGNED NULL AFTER file_extension,
    ADD COLUMN storage_provider  VARCHAR(20)  NOT NULL DEFAULT ''mileswebstorage'' COMMENT ''mileswebstorage | local (dev fallback)'' AFTER file_size_bytes,
    ADD COLUMN storage_path      VARCHAR(500) NULL COMMENT ''path on the storage backend (FTP path or local disk path)'' AFTER storage_provider,
    ADD COLUMN uploaded_by       BIGINT UNSIGNED NULL COMMENT ''staff user who uploaded it'' AFTER storage_path,
    ADD COLUMN created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER uploaded_by
', 'SELECT ''product_images already has media columns, skipping'' AS note');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Rows that existed BEFORE this migration (seed data, images added by hand)
-- are not on MilesWeb — they just inherited the column default. Label them
-- honestly, so tooling that migrates "our" uploads can tell them apart.
-- An upload through the app always writes storage_path; these never have one.
UPDATE product_images
   SET storage_provider = 'seed'
 WHERE storage_path IS NULL
   AND storage_provider = 'mileswebstorage';

SET @fk_exists := (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'product_images' AND CONSTRAINT_NAME = 'fk_prodimg_upload'
);
SET @sql := IF(@fk_exists = 0, '
  ALTER TABLE product_images
    ADD CONSTRAINT fk_prodimg_upload FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE SET NULL
', 'SELECT ''fk_prodimg_upload already exists, skipping'' AS note');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- new permission: uploading/attaching images to a product --------
INSERT IGNORE INTO permissions (code, category, description) VALUES
  ('product.image_upload', 'catalog', 'Upload/attach product images');

-- Admin already gets every permission automatically in most seed scripts,
-- but do it explicitly here too in case this file runs standalone.
INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.code IN ('admin', 'manager') AND p.code = 'product.image_upload';

-- Sales is NOT granted this by default — an Admin can flip it on for the
-- Sales/Marketing role from Permissions.jsx whenever they want sales staff
-- to be able to add product photos.
