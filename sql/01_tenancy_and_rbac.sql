-- =====================================================================
--  FILE 01 of 09 : Multi-tenancy, staff accounts & access control (RBAC)
-- ---------------------------------------------------------------------
--  This file answers three of your requirements:
--    (1) Multi-tenancy  -> the `tenants` table + tenant_id everywhere.
--    (2) The 4 panels    -> `roles` + `permissions` (Admin / Manager /
--                           Sales-Marketing / Customer).
--    (3) Multilingual    -> the global `locales` list + which locales a
--                           tenant has switched on (`tenant_locales`).
--
--  Mental model of "multi-tenant":
--    One database. Many jewellery brands ("tenants"). Every brand's rows
--    carry that brand's tenant_id, so Brand A can NEVER read Brand B's
--    products or orders — the app always filters `WHERE tenant_id = ?`.
-- =====================================================================

-- USE truebellaa;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- GLOBAL reference tables (shared by ALL tenants -> no tenant_id here).
-- ---------------------------------------------------------------------

-- Every language the platform can speak. Adding a language = one row.
CREATE TABLE locales (
  code          VARCHAR(10)  NOT NULL COMMENT 'BCP-47 code: en, hi, ta, bn, mr',
  english_name  VARCHAR(60)  NOT NULL COMMENT 'e.g. Hindi',
  native_name   VARCHAR(60)  NOT NULL COMMENT 'e.g. हिन्दी (shown in the switcher)',
  is_rtl        TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1 = right-to-left script',
  is_active     TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Currencies (INR today, but designed so a tenant could sell in USD later).
CREATE TABLE currencies (
  code           CHAR(3)     NOT NULL COMMENT 'ISO 4217: INR, USD',
  symbol         VARCHAR(8)  NOT NULL COMMENT '₹, $',
  name           VARCHAR(60) NOT NULL,
  decimal_digits TINYINT     NOT NULL DEFAULT 2,
  PRIMARY KEY (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The master catalog of permissions. These strings are the SAME for every
-- tenant; a role just picks which ones it grants. (Global on purpose.)
CREATE TABLE permissions (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code        VARCHAR(80)  NOT NULL COMMENT 'e.g. product.update, order.refund',
  category    VARCHAR(40)  NOT NULL COMMENT 'grouping for the admin UI',
  description VARCHAR(255) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permissions_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- TENANTS — the root of everything. One row per jewellery brand/store.
-- ---------------------------------------------------------------------
CREATE TABLE tenants (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id             CHAR(26)     NOT NULL COMMENT 'ULID shown externally',
  name                  VARCHAR(120) NOT NULL COMMENT 'e.g. TrueBellaa',
  slug                  VARCHAR(120) NOT NULL COMMENT 'url-safe: truebellaa',
  legal_name            VARCHAR(200) NULL,
  primary_domain        VARCHAR(190) NULL COMMENT 'truebellaa.com (for routing)',
  gstin                 VARCHAR(20)  NULL COMMENT 'India tax id, optional',
  support_email         VARCHAR(190) NULL,
  support_phone         VARCHAR(30)  NULL,
  default_locale_code   VARCHAR(10)  NOT NULL DEFAULT 'en',
  default_currency_code CHAR(3)      NOT NULL DEFAULT 'INR',
  status                ENUM('trial','active','suspended','closed') NOT NULL DEFAULT 'trial',
  created_at            TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at            TIMESTAMP    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tenants_public_id (public_id),
  UNIQUE KEY uq_tenants_slug (slug),
  UNIQUE KEY uq_tenants_domain (primary_domain),
  CONSTRAINT fk_tenants_locale   FOREIGN KEY (default_locale_code)   REFERENCES locales(code),
  CONSTRAINT fk_tenants_currency FOREIGN KEY (default_currency_code) REFERENCES currencies(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Which languages a specific tenant has enabled + which is their default.
CREATE TABLE tenant_locales (
  tenant_id   BIGINT UNSIGNED NOT NULL,
  locale_code VARCHAR(10)     NOT NULL,
  is_default  TINYINT(1)      NOT NULL DEFAULT 0,
  is_active   TINYINT(1)      NOT NULL DEFAULT 1,
  PRIMARY KEY (tenant_id, locale_code),
  CONSTRAINT fk_tloc_tenant FOREIGN KEY (tenant_id)   REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_tloc_locale FOREIGN KEY (locale_code) REFERENCES locales(code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Free-form per-tenant configuration (theme colour, Razorpay key id,
-- Shiprocket pickup location, etc.) kept as key/value so adding a setting
-- never needs a schema change. Secrets stay in a vault, NOT here.
CREATE TABLE tenant_settings (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  setting_key VARCHAR(120) NOT NULL,
  setting_val JSON         NULL,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tsettings (tenant_id, setting_key),
  CONSTRAINT fk_tsettings_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- STAFF (back-office) accounts. These are the people who log into the
-- Admin / Manager / Sales panels. Shoppers live in a SEPARATE table
-- (see 03_customers.sql) because staff and customers have totally
-- different lifecycles and login flows.
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  public_id     CHAR(26)     NOT NULL,
  email         VARCHAR(190) NOT NULL,
  phone         VARCHAR(30)  NULL,
  password_hash VARCHAR(255) NOT NULL COMMENT 'bcrypt/argon2 — NEVER plain text',
  full_name     VARCHAR(150) NOT NULL,
  status        ENUM('invited','active','disabled') NOT NULL DEFAULT 'invited',
  last_login_at TIMESTAMP    NULL,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at    TIMESTAMP    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_public_id (public_id),
  UNIQUE KEY uq_users_tenant_email (tenant_id, email),
  KEY idx_users_tenant (tenant_id),
  CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Roles are per-tenant so each brand can rename/customize them. The
-- three staff panels map to three seeded roles: admin, manager, sales.
CREATE TABLE roles (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  code        VARCHAR(40)  NOT NULL COMMENT 'admin | manager | sales',
  name        VARCHAR(80)  NOT NULL,
  description VARCHAR(255) NULL,
  is_system   TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1 = cannot be deleted',
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_tenant_code (tenant_id, code),
  CONSTRAINT fk_roles_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Which permissions each role grants (many-to-many).
CREATE TABLE role_permissions (
  role_id       BIGINT UNSIGNED NOT NULL,
  permission_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_rp_role FOREIGN KEY (role_id)       REFERENCES roles(id)       ON DELETE CASCADE,
  CONSTRAINT fk_rp_perm FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Which role(s) a staff user has (usually one, but many is allowed).
CREATE TABLE user_roles (
  user_id   BIGINT UNSIGNED NOT NULL,
  role_id   BIGINT UNSIGNED NOT NULL,
  tenant_id BIGINT UNSIGNED NOT NULL COMMENT 'denormalized for fast tenant filtering',
  PRIMARY KEY (user_id, role_id),
  KEY idx_user_roles_tenant (tenant_id),
  CONSTRAINT fk_ur_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_ur_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Refresh-token / session records for staff logins. Every login writes a
-- row here; logout sets revoked_at. This also powers "who is logged in"
-- and complements the audit log's login/logout events.
CREATE TABLE staff_sessions (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  user_id       BIGINT UNSIGNED NOT NULL,
  token_hash    CHAR(64)     NOT NULL COMMENT 'SHA-256 of the refresh token',
  ip_address    VARBINARY(16) NULL   COMMENT 'INET6_ATON() — works for IPv4 + IPv6',
  user_agent    VARCHAR(255) NULL,
  expires_at    TIMESTAMP    NOT NULL,
  revoked_at    TIMESTAMP    NULL,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_staff_sessions_token (token_hash),
  KEY idx_staff_sessions_user (user_id),
  CONSTRAINT fk_ss_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_ss_user   FOREIGN KEY (user_id)   REFERENCES users(id)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
