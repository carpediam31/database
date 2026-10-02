-- =====================================================================
--  FILE 04 of 09 : Carts, Orders, Order items, Coupons
-- ---------------------------------------------------------------------
--  KEY IDEA — "snapshots". An order must remember what was true the day
--  it was placed. If a product's name, price or the customer's address
--  changes next month, past orders must NOT change. So order_items copy
--  the name/price/variant text, and the order copies the shipping
--  address. We link back to the live product too (for reports), but the
--  copied values are what the invoice shows.
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- CARTS — a work-in-progress basket. One active cart per customer (or per
-- guest session token). Turns into an order at checkout.
-- ---------------------------------------------------------------------
CREATE TABLE carts (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  customer_id   BIGINT UNSIGNED NULL COMMENT 'NULL while guest, filled on login',
  session_token CHAR(36)     NULL COMMENT 'anonymous guest basket id',
  currency_code CHAR(3)      NOT NULL DEFAULT 'INR',
  status        ENUM('active','converted','abandoned') NOT NULL DEFAULT 'active',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_carts_customer (customer_id),
  KEY idx_carts_tenant_status (tenant_id, status),
  KEY idx_carts_session (session_token),
  CONSTRAINT fk_cart_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE,
  CONSTRAINT fk_cart_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE cart_items (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  cart_id     BIGINT UNSIGNED NOT NULL,
  variant_id  BIGINT UNSIGNED NOT NULL,
  quantity    INT NOT NULL DEFAULT 1,
  unit_price  DECIMAL(12,2) NOT NULL COMMENT 'price snapshot when added',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cart_variant (cart_id, variant_id),
  KEY idx_cartitems_tenant (tenant_id),
  CONSTRAINT chk_cartitems_qty CHECK (quantity > 0),
  CONSTRAINT fk_ci_cart    FOREIGN KEY (cart_id)    REFERENCES carts(id)            ON DELETE CASCADE,
  CONSTRAINT fk_ci_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE RESTRICT,
  CONSTRAINT fk_ci_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)          ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- COUPONS — managed by the Marketing/Sales panel.
-- ---------------------------------------------------------------------
CREATE TABLE coupons (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id       BIGINT UNSIGNED NOT NULL,
  code            VARCHAR(40) NOT NULL COMMENT 'FESTIVE10',
  discount_type   ENUM('percent','fixed') NOT NULL,
  discount_value  DECIMAL(12,2) NOT NULL COMMENT '10 = 10% or ₹10',
  min_order_total DECIMAL(12,2) NULL,
  max_discount    DECIMAL(12,2) NULL COMMENT 'cap for percent coupons',
  usage_limit     INT NULL COMMENT 'total redemptions allowed, NULL = unlimited',
  per_customer_limit INT NULL,
  times_used      INT NOT NULL DEFAULT 0,
  starts_at       TIMESTAMP NULL,
  ends_at         TIMESTAMP NULL,
  is_active       TINYINT(1) NOT NULL DEFAULT 1,
  created_by      BIGINT UNSIGNED NULL COMMENT 'staff user',
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_coupons_tenant_code (tenant_id, code),
  CONSTRAINT fk_coupon_tenant FOREIGN KEY (tenant_id)  REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_coupon_user   FOREIGN KEY (created_by) REFERENCES users(id)  ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- ORDERS — the header. Money columns are all filled at checkout time.
-- The shipping address is COPIED here (snapshot), not just referenced.
-- ---------------------------------------------------------------------
CREATE TABLE orders (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id        BIGINT UNSIGNED NOT NULL,
  public_id        CHAR(26)     NOT NULL COMMENT 'internal ULID',
  order_number     VARCHAR(20)  NOT NULL COMMENT 'human code e.g. TB100231',
  customer_id      BIGINT UNSIGNED NULL,
  cart_id          BIGINT UNSIGNED NULL,
  coupon_id        BIGINT UNSIGNED NULL,
  locale_code      VARCHAR(10)  NOT NULL DEFAULT 'en' COMMENT 'language at purchase',
  currency_code    CHAR(3)      NOT NULL DEFAULT 'INR',
  status           ENUM('pending_payment','paid','processing','shipped',
                        'delivered','cancelled','refunded','returned')
                   NOT NULL DEFAULT 'pending_payment',
  -- money (all in the order currency)
  subtotal         DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_total   DECIMAL(12,2) NOT NULL DEFAULT 0,
  shipping_total   DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_total        DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total      DECIMAL(12,2) NOT NULL DEFAULT 0,
  -- contact + shipping snapshot (from checkout form)
  contact_email    VARCHAR(190) NOT NULL,
  contact_phone    VARCHAR(30)  NOT NULL,
  ship_first_name  VARCHAR(80)  NOT NULL,
  ship_last_name   VARCHAR(80)  NOT NULL,
  ship_line1       VARCHAR(200) NOT NULL,
  ship_line2       VARCHAR(200) NULL,
  ship_city        VARCHAR(100) NOT NULL,
  ship_state       VARCHAR(100) NOT NULL,
  ship_postal_code VARCHAR(20)  NOT NULL,
  ship_country_code CHAR(2)     NOT NULL DEFAULT 'IN',
  customer_note    VARCHAR(500) NULL,
  placed_at        TIMESTAMP    NULL COMMENT 'set when payment confirmed',
  created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_orders_public_id (public_id),
  UNIQUE KEY uq_orders_tenant_number (tenant_id, order_number),
  KEY idx_orders_tenant_status (tenant_id, status),
  KEY idx_orders_customer (customer_id),
  KEY idx_orders_placed (tenant_id, placed_at),
  CONSTRAINT fk_order_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE,
  CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
  CONSTRAINT fk_order_cart     FOREIGN KEY (cart_id)     REFERENCES carts(id)     ON DELETE SET NULL,
  CONSTRAINT fk_order_coupon   FOREIGN KEY (coupon_id)   REFERENCES coupons(id)   ON DELETE SET NULL,
  CONSTRAINT fk_order_currency FOREIGN KEY (currency_code) REFERENCES currencies(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ORDER ITEMS — one row per line, with the product facts COPIED in.
CREATE TABLE order_items (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id      BIGINT UNSIGNED NOT NULL,
  order_id       BIGINT UNSIGNED NOT NULL,
  product_id     BIGINT UNSIGNED NULL COMMENT 'live link, may become NULL if deleted',
  variant_id     BIGINT UNSIGNED NULL,
  product_name   VARCHAR(200) NOT NULL COMMENT 'SNAPSHOT of name at purchase',
  variant_label  VARCHAR(160) NULL    COMMENT 'SNAPSHOT e.g. "Silver / 20 inch"',
  sku            VARCHAR(64)  NULL,
  unit_price     DECIMAL(12,2) NOT NULL,
  quantity       INT NOT NULL,
  line_total     DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_orderitems_order (order_id),
  KEY idx_orderitems_tenant (tenant_id),
  CONSTRAINT chk_orderitems_qty CHECK (quantity > 0),
  CONSTRAINT fk_oi_order   FOREIGN KEY (order_id)   REFERENCES orders(id)           ON DELETE CASCADE,
  CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES products(id)         ON DELETE SET NULL,
  CONSTRAINT fk_oi_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL,
  CONSTRAINT fk_oi_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)          ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Every status change is recorded — this is the order's own mini audit
-- trail (who moved it from "paid" to "shipped" and when).
CREATE TABLE order_status_history (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  order_id    BIGINT UNSIGNED NOT NULL,
  from_status VARCHAR(30) NULL,
  to_status   VARCHAR(30) NOT NULL,
  note        VARCHAR(300) NULL,
  changed_by  BIGINT UNSIGNED NULL COMMENT 'staff user, NULL = system/webhook',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_osh_order (order_id),
  KEY idx_osh_tenant (tenant_id),
  CONSTRAINT fk_osh_order  FOREIGN KEY (order_id)   REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_osh_user   FOREIGN KEY (changed_by) REFERENCES users(id)  ON DELETE SET NULL,
  CONSTRAINT fk_osh_tenant FOREIGN KEY (tenant_id)  REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Records each time a coupon was actually used on an order.
CREATE TABLE coupon_redemptions (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  coupon_id   BIGINT UNSIGNED NOT NULL,
  order_id    BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NULL,
  amount      DECIMAL(12,2) NOT NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_credemp_coupon (coupon_id),
  KEY idx_credemp_tenant (tenant_id),
  CONSTRAINT fk_cr_coupon   FOREIGN KEY (coupon_id)   REFERENCES coupons(id)   ON DELETE CASCADE,
  CONSTRAINT fk_cr_order    FOREIGN KEY (order_id)    REFERENCES orders(id)    ON DELETE CASCADE,
  CONSTRAINT fk_cr_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
  CONSTRAINT fk_cr_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
