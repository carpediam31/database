-- =====================================================================
--  FILE 02 of 09 : Product catalog + MULTILINGUAL content
-- ---------------------------------------------------------------------
--  The multilingual pattern used here is "one translation table per
--  translatable thing". Example: a product's language-independent facts
--  (SKU, price, stock, images) live in `products`; its language-DEPENDENT
--  text (name, description, care notes) lives in `product_translations`,
--  one row per locale. To show a product in Hindi you read the product
--  row + the product_translation row WHERE locale_code='hi'. If that row
--  is missing, the app falls back to the tenant's default locale.
--
--  Why this pattern (and not "name_en, name_hi, name_ta" columns)?
--    * Adding a language = INSERT rows, never ALTER TABLE.
--    * Works for 2 languages or 20 with zero schema churn.
--    * Each translation is independently editable/auditable.
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- CATEGORIES  (Chains / Pendants / Bracelets). Self-referencing parent_id
-- lets you nest sub-categories later without a new table.
-- ---------------------------------------------------------------------
CREATE TABLE categories (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id  BIGINT UNSIGNED NOT NULL,
  parent_id  BIGINT UNSIGNED NULL,
  slug       VARCHAR(140) NOT NULL COMMENT 'url-safe, unique per tenant',
  position   INT          NOT NULL DEFAULT 0 COMMENT 'sort order in menus',
  is_active  TINYINT(1)   NOT NULL DEFAULT 1,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_categories_tenant_slug (tenant_id, slug),
  KEY idx_categories_tenant (tenant_id),
  KEY idx_categories_parent (parent_id),
  CONSTRAINT fk_cat_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)    ON DELETE CASCADE,
  CONSTRAINT fk_cat_parent FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Translated category name/description, one row per (category, locale).
CREATE TABLE category_translations (
  category_id BIGINT UNSIGNED NOT NULL,
  locale_code VARCHAR(10)  NOT NULL,
  name        VARCHAR(160) NOT NULL,
  description VARCHAR(500) NULL,
  PRIMARY KEY (category_id, locale_code),
  CONSTRAINT fk_cattr_cat    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,
  CONSTRAINT fk_cattr_locale FOREIGN KEY (locale_code) REFERENCES locales(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- ATTRIBUTES — the "axes" a product varies on: Metal and Length.
-- attribute -> has many attribute_values -> which combine into variants.
-- ---------------------------------------------------------------------
CREATE TABLE attributes (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id  BIGINT UNSIGNED NOT NULL,
  code       VARCHAR(40) NOT NULL COMMENT 'metal | length',
  position   INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uq_attributes_tenant_code (tenant_id, code),
  CONSTRAINT fk_attr_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE attribute_translations (
  attribute_id BIGINT UNSIGNED NOT NULL,
  locale_code  VARCHAR(10) NOT NULL,
  label        VARCHAR(80) NOT NULL COMMENT 'Metal / धातु , Length / लंबाई',
  PRIMARY KEY (attribute_id, locale_code),
  CONSTRAINT fk_attrtr_attr   FOREIGN KEY (attribute_id) REFERENCES attributes(id) ON DELETE CASCADE,
  CONSTRAINT fk_attrtr_locale FOREIGN KEY (locale_code)  REFERENCES locales(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE attribute_values (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  attribute_id BIGINT UNSIGNED NOT NULL,
  tenant_id    BIGINT UNSIGNED NOT NULL COMMENT 'denormalized for filtering',
  code         VARCHAR(40) NOT NULL COMMENT 'gold | silver | steel | 18in',
  hex_color    CHAR(7)     NULL COMMENT 'swatch colour for metals, e.g. #c9a24b',
  position     INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uq_attrval (attribute_id, code),
  KEY idx_attrval_tenant (tenant_id),
  CONSTRAINT fk_attrval_attr   FOREIGN KEY (attribute_id) REFERENCES attributes(id) ON DELETE CASCADE,
  CONSTRAINT fk_attrval_tenant FOREIGN KEY (tenant_id)    REFERENCES tenants(id)    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE attribute_value_translations (
  attribute_value_id BIGINT UNSIGNED NOT NULL,
  locale_code        VARCHAR(10) NOT NULL,
  label              VARCHAR(80) NOT NULL COMMENT 'Gold / सोना , 18" / 18 इंच',
  PRIMARY KEY (attribute_value_id, locale_code),
  CONSTRAINT fk_avtr_val    FOREIGN KEY (attribute_value_id) REFERENCES attribute_values(id) ON DELETE CASCADE,
  CONSTRAINT fk_avtr_locale FOREIGN KEY (locale_code)        REFERENCES locales(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PRODUCTS — language-INDEPENDENT facts only.
-- base_price is a display/fallback price; the real sellable price+stock
-- lives on each variant (SKU).
-- ---------------------------------------------------------------------
CREATE TABLE products (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id        BIGINT UNSIGNED NOT NULL,
  public_id        CHAR(26)     NOT NULL,
  category_id      BIGINT UNSIGNED NULL,
  slug             VARCHAR(160) NOT NULL,
  sku_prefix       VARCHAR(40)  NULL COMMENT 'base SKU, variants extend it',
  base_price       DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT 'display/fallback price',
  currency_code    CHAR(3)      NOT NULL DEFAULT 'INR',
  rating_avg       DECIMAL(3,2) NOT NULL DEFAULT 0 COMMENT 'cached from reviews',
  rating_count     INT          NOT NULL DEFAULT 0,
  status           ENUM('draft','active','archived') NOT NULL DEFAULT 'draft',
  published_at     TIMESTAMP    NULL,
  created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at       TIMESTAMP    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_products_public_id (public_id),
  UNIQUE KEY uq_products_tenant_slug (tenant_id, slug),
  KEY idx_products_tenant_status (tenant_id, status),
  KEY idx_products_category (category_id),
  CONSTRAINT fk_prod_tenant   FOREIGN KEY (tenant_id)     REFERENCES tenants(id)    ON DELETE CASCADE,
  CONSTRAINT fk_prod_category FOREIGN KEY (category_id)   REFERENCES categories(id) ON DELETE SET NULL,
  CONSTRAINT fk_prod_currency FOREIGN KEY (currency_code) REFERENCES currencies(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Translated marketing text, one row per (product, locale).
CREATE TABLE product_translations (
  product_id        BIGINT UNSIGNED NOT NULL,
  locale_code       VARCHAR(10)  NOT NULL,
  name              VARCHAR(200) NOT NULL,
  short_description VARCHAR(500) NULL,
  description       TEXT         NULL,
  care_instructions TEXT         NULL,
  meta_title        VARCHAR(200) NULL COMMENT 'SEO',
  meta_description  VARCHAR(300) NULL COMMENT 'SEO',
  PRIMARY KEY (product_id, locale_code),
  KEY idx_prodtr_name (name),
  CONSTRAINT fk_prodtr_prod   FOREIGN KEY (product_id)  REFERENCES products(id) ON DELETE CASCADE,
  CONSTRAINT fk_prodtr_locale FOREIGN KEY (locale_code) REFERENCES locales(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Product images (main + alternates). Images are language-independent.
CREATE TABLE product_images (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id          BIGINT UNSIGNED NOT NULL,
  product_id         BIGINT UNSIGNED NOT NULL,
  url                VARCHAR(500) NOT NULL COMMENT 'public URL the storefront/admin renders',
  alt_text           VARCHAR(200) NULL,
  position           INT NOT NULL DEFAULT 0,
  is_primary         TINYINT(1) NOT NULL DEFAULT 0,
  -- Media metadata, captured at upload time (see mileswebstorage_client.py).
  original_filename  VARCHAR(255) NULL COMMENT 'filename as uploaded from the admin panel',
  file_extension     VARCHAR(10)  NULL COMMENT 'jpg | png | webp | gif',
  file_size_bytes    INT UNSIGNED NULL,
  storage_provider   VARCHAR(20)  NOT NULL DEFAULT 'mileswebstorage' COMMENT 'mileswebstorage | local (dev fallback)',
  storage_path       VARCHAR(500) NULL COMMENT 'path on the storage backend (FTP path or local disk path)',
  uploaded_by        BIGINT UNSIGNED NULL COMMENT 'staff user who uploaded it',
  created_at         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_prodimg_product (product_id),
  KEY idx_prodimg_tenant (tenant_id),
  CONSTRAINT fk_prodimg_prod    FOREIGN KEY (product_id)  REFERENCES products(id) ON DELETE CASCADE,
  CONSTRAINT fk_prodimg_tenant  FOREIGN KEY (tenant_id)   REFERENCES tenants(id)  ON DELETE CASCADE,
  CONSTRAINT fk_prodimg_upload  FOREIGN KEY (uploaded_by) REFERENCES users(id)    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- VARIANTS — the actual purchasable SKUs. A variant is one specific
-- combination of attribute values (e.g. "Silver + 20 inch"). Price and
-- stock live HERE, so two lengths can have different prices/stock.
-- ---------------------------------------------------------------------
CREATE TABLE product_variants (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id      BIGINT UNSIGNED NOT NULL,
  product_id     BIGINT UNSIGNED NOT NULL,
  sku            VARCHAR(64)   NOT NULL COMMENT 'globally-unique stock code',
  price          DECIMAL(12,2) NOT NULL,
  compare_at_price DECIMAL(12,2) NULL COMMENT 'strike-through / MRP',
  cost_price     DECIMAL(12,2) NULL COMMENT 'internal, for margin reports',
  stock_on_hand  INT NOT NULL DEFAULT 0,
  stock_reserved INT NOT NULL DEFAULT 0 COMMENT 'held by open orders',
  stock_available INT AS (stock_on_hand - stock_reserved) VIRTUAL,
  weight_grams   INT NULL COMMENT 'used for shipping rate calc',
  is_default     TINYINT(1) NOT NULL DEFAULT 0,
  is_active      TINYINT(1) NOT NULL DEFAULT 1,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_variants_sku (sku),
  KEY idx_variants_product (product_id),
  KEY idx_variants_tenant (tenant_id),
  CONSTRAINT fk_var_prod   FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
  CONSTRAINT fk_var_tenant FOREIGN KEY (tenant_id)  REFERENCES tenants(id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Which attribute values make up a variant (Silver + 20in => 2 rows).
CREATE TABLE variant_attribute_values (
  variant_id         BIGINT UNSIGNED NOT NULL,
  attribute_value_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (variant_id, attribute_value_id),
  KEY idx_vav_value (attribute_value_id),
  CONSTRAINT fk_vav_variant FOREIGN KEY (variant_id)         REFERENCES product_variants(id)  ON DELETE CASCADE,
  CONSTRAINT fk_vav_value   FOREIGN KEY (attribute_value_id) REFERENCES attribute_values(id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only stock ledger: every +/- to stock is a row here. Lets you
-- answer "why is stock 3?" and feeds inventory audit on the admin panel.
CREATE TABLE inventory_movements (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  variant_id  BIGINT UNSIGNED NOT NULL,
  change_qty  INT NOT NULL COMMENT '+10 restock, -1 sale',
  reason      ENUM('restock','sale','return','adjustment','reservation','release') NOT NULL,
  reference   VARCHAR(80) NULL COMMENT 'e.g. order public_id',
  created_by  BIGINT UNSIGNED NULL COMMENT 'staff user id, NULL = system',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_invmov_variant (variant_id),
  KEY idx_invmov_tenant_time (tenant_id, created_at),
  CONSTRAINT fk_invmov_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)          ON DELETE CASCADE,
  CONSTRAINT fk_invmov_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
