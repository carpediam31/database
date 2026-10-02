-- =====================================================================
--  FILE 07 of 09 : Audit logs, price history, login/logout tracking
-- ---------------------------------------------------------------------
--  Requirement #6: "who, when, login/logout, price change — anything
--  anyone does — must show on the Admin panel."
--
--  Three tables:
--    * audit_logs          -> the universal "someone did something" log.
--                             One row per meaningful action, with a JSON
--                             snapshot of what changed (old vs new).
--    * auth_events         -> a focused login/logout/failed-login log so
--                             the Admin panel's "Login activity" screen is
--                             a single fast query.
--    * product_price_history-> a specialised, guaranteed price trail. A
--                             DB TRIGGER writes here automatically on ANY
--                             price change, even if a script forgets to.
--
--  HOW "who did it" reaches the trigger:
--    The FastAPI app runs, right after opening the DB connection:
--        SET @app_user_id = 42;         -- the logged-in staff id
--        SET @app_actor_ip = '1.2.3.4'; -- optional
--    The trigger reads @app_user_id. If the app didn't set it (e.g. a
--    migration script), it logs NULL = "system".
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- UNIVERSAL AUDIT LOG
-- actor_type tells you whether a staff user, a customer, or the system
-- did it. old_values / new_values are JSON so ANY table can be audited
-- with the same structure.
-- ---------------------------------------------------------------------
CREATE TABLE audit_logs (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id      BIGINT UNSIGNED NULL COMMENT 'NULL only for platform-level events',
  actor_type     ENUM('staff','customer','system') NOT NULL DEFAULT 'system',
  actor_id       BIGINT UNSIGNED NULL,
  actor_name     VARCHAR(150) NULL COMMENT 'snapshot, so log survives user deletion',
  action         VARCHAR(80)  NOT NULL COMMENT 'product.price_changed, order.status_changed, auth.login',
  entity_type    VARCHAR(60)  NULL COMMENT 'table/resource name e.g. product',
  entity_id      BIGINT UNSIGNED NULL,
  entity_label   VARCHAR(200) NULL COMMENT 'human label e.g. "Cross Pavé Pendant"',
  summary        VARCHAR(300) NULL COMMENT 'one-line description for the UI',
  old_values     JSON NULL,
  new_values     JSON NULL,
  ip_address     VARBINARY(16) NULL,
  user_agent     VARCHAR(255) NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_audit_tenant_time (tenant_id, created_at),
  KEY idx_audit_actor (actor_type, actor_id),
  KEY idx_audit_entity (entity_type, entity_id),
  KEY idx_audit_action (action),
  CONSTRAINT fk_audit_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- LOGIN / LOGOUT ACTIVITY
-- ---------------------------------------------------------------------
CREATE TABLE auth_events (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  actor_type  ENUM('staff','customer') NOT NULL,
  actor_id    BIGINT UNSIGNED NULL COMMENT 'NULL when a login fails on unknown email',
  email_tried VARCHAR(190) NULL,
  event       ENUM('login','logout','login_failed','password_reset','password_changed') NOT NULL,
  ip_address  VARBINARY(16) NULL,
  user_agent  VARCHAR(255) NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_authev_tenant_time (tenant_id, created_at),
  KEY idx_authev_actor (actor_type, actor_id),
  CONSTRAINT fk_authev_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PRICE HISTORY  (specialised, always-on trail for price changes)
-- ---------------------------------------------------------------------
CREATE TABLE product_price_history (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  variant_id  BIGINT UNSIGNED NOT NULL,
  product_id  BIGINT UNSIGNED NULL,
  old_price   DECIMAL(12,2) NULL,
  new_price   DECIMAL(12,2) NOT NULL,
  changed_by  BIGINT UNSIGNED NULL COMMENT 'staff user id or NULL = system',
  source      VARCHAR(40) NOT NULL DEFAULT 'trigger' COMMENT 'trigger | api | import',
  note        VARCHAR(255) NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_price_hist_variant (variant_id, created_at),
  KEY idx_price_hist_tenant_time (tenant_id, created_at),
  CONSTRAINT fk_pph_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE,
  CONSTRAINT fk_pph_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)          ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- TRIGGER: whenever a variant's price actually changes, record it.
-- Guarantees a price trail even if application code forgets to log.
-- Reads @app_user_id (set by the app) to attribute "who changed it".
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_variant_price_history
AFTER UPDATE ON product_variants
FOR EACH ROW
BEGIN
  IF NEW.price <> OLD.price THEN
    INSERT INTO product_price_history
      (tenant_id, variant_id, product_id, old_price, new_price, changed_by, source, note)
    VALUES
      (NEW.tenant_id, NEW.id, NEW.product_id, OLD.price, NEW.price,
       NULLIF(@app_user_id, 0), 'trigger',
       CONCAT('Price changed from ', OLD.price, ' to ', NEW.price));
  END IF;
END$$

DELIMITER ;
