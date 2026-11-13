-- =====================================================================
--  FILE 03 of 09 : Customers (shoppers), addresses, wishlist, reviews
-- ---------------------------------------------------------------------
--  Shoppers are kept SEPARATE from staff (`users`) on purpose:
--    * different login screen (storefront vs admin panel),
--    * guests can check out without ever setting a password,
--    * you never want a catalogue-editor and a buyer in the same table.
--  This is the "customer/user" panel (panel #4).
-- =====================================================================

-- USE truebellaa;
SET NAMES utf8mb4;

CREATE TABLE customers (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id         BIGINT UNSIGNED NOT NULL,
  public_id         CHAR(26)     NOT NULL,
  email             VARCHAR(190) NOT NULL,
  phone             VARCHAR(30)  NULL,
  password_hash     VARCHAR(255) NULL COMMENT 'NULL for guest checkout accounts',
  full_name         VARCHAR(150) NULL,
  preferred_locale  VARCHAR(10)  NULL COMMENT 'language they last chose',
  is_guest          TINYINT(1)   NOT NULL DEFAULT 0,
  email_verified_at TIMESTAMP    NULL,
  marketing_opt_in  TINYINT(1)   NOT NULL DEFAULT 0,
  status            ENUM('active','blocked') NOT NULL DEFAULT 'active',
  last_login_at     TIMESTAMP    NULL,
  created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at        TIMESTAMP    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_customers_public_id (public_id),
  UNIQUE KEY uq_customers_tenant_email (tenant_id, email),
  KEY idx_customers_tenant (tenant_id),
  CONSTRAINT fk_cust_tenant FOREIGN KEY (tenant_id)        REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_cust_locale FOREIGN KEY (preferred_locale) REFERENCES locales(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A customer can save several addresses (home, office...). Order rows keep
-- their OWN copy of the address (see 04) so editing this later never
-- rewrites the address a past order shipped to.
CREATE TABLE customer_addresses (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id    BIGINT UNSIGNED NOT NULL,
  customer_id  BIGINT UNSIGNED NOT NULL,
  label        VARCHAR(40)  NULL COMMENT 'Home / Office',
  first_name   VARCHAR(80)  NOT NULL,
  last_name    VARCHAR(80)  NOT NULL,
  phone        VARCHAR(30)  NOT NULL,
  line1        VARCHAR(200) NOT NULL,
  line2        VARCHAR(200) NULL,
  city         VARCHAR(100) NOT NULL,
  state        VARCHAR(100) NOT NULL,
  postal_code  VARCHAR(20)  NOT NULL,
  country_code CHAR(2)      NOT NULL DEFAULT 'IN',
  is_default_shipping TINYINT(1) NOT NULL DEFAULT 0,
  is_default_billing  TINYINT(1) NOT NULL DEFAULT 0,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_addr_customer (customer_id),
  KEY idx_addr_tenant (tenant_id),
  CONSTRAINT fk_addr_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  CONSTRAINT fk_addr_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Wishlist: a customer saving products for later.
CREATE TABLE wishlist_items (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  product_id  BIGINT UNSIGNED NOT NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_wishlist (customer_id, product_id),
  KEY idx_wishlist_tenant (tenant_id),
  CONSTRAINT fk_wish_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  CONSTRAINT fk_wish_product  FOREIGN KEY (product_id)  REFERENCES products(id)  ON DELETE CASCADE,
  CONSTRAINT fk_wish_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Newsletter signups (the footer form on the storefront).
CREATE TABLE newsletter_subscribers (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  email         VARCHAR(190) NOT NULL,
  customer_id   BIGINT UNSIGNED NULL COMMENT 'linked if they also have an account',
  locale_code   VARCHAR(10)  NULL,
  status        ENUM('subscribed','unsubscribed') NOT NULL DEFAULT 'subscribed',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  unsubscribed_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_news_tenant_email (tenant_id, email),
  CONSTRAINT fk_news_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE,
  CONSTRAINT fk_news_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Product reviews (the "4.8 (126 reviews)" on the product page).
CREATE TABLE product_reviews (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  product_id  BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NULL COMMENT 'NULL if the reviewer was removed',
  rating      TINYINT      NOT NULL COMMENT '1..5',
  title       VARCHAR(160) NULL,
  body        TEXT         NULL,
  status      ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_reviews_product (product_id, status),
  KEY idx_reviews_tenant (tenant_id),
  CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),
  CONSTRAINT fk_rev_product  FOREIGN KEY (product_id)  REFERENCES products(id)  ON DELETE CASCADE,
  CONSTRAINT fk_rev_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
  CONSTRAINT fk_rev_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
