-- =====================================================================
--  FILE 12 : Email OTP verification for customer accounts — Add-on
-- ---------------------------------------------------------------------
--  Customers used to be created straight from a form, so anyone could
--  register with somebody else's email address. Now a 6-digit code is
--  emailed and must be entered before the account is created (and the
--  same mechanism doubles as passwordless sign-in).
--
--  Security notes baked into this schema:
--    * code_hash, never the code itself — a database leak must not hand
--      an attacker working OTPs.
--    * attempts + max_attempts  -> stops brute-forcing a 6-digit code.
--    * expires_at               -> short-lived codes.
--    * consumed_at              -> a code works exactly once.
--
--  Idempotent: safe to run more than once.
-- =====================================================================

-- USE truebellaa;
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS email_otps (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  email         VARCHAR(190) NOT NULL,
  purpose       ENUM('register','login') NOT NULL DEFAULT 'register',
  code_hash     CHAR(64)     NOT NULL COMMENT 'SHA-256 of the 6-digit code — never the code',
  attempts      TINYINT      NOT NULL DEFAULT 0,
  max_attempts  TINYINT      NOT NULL DEFAULT 5,
  expires_at    TIMESTAMP    NOT NULL,
  consumed_at   TIMESTAMP    NULL COMMENT 'set the moment it is used — single use',
  ip_address    VARBINARY(16) NULL,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_otp_lookup (tenant_id, email, purpose, consumed_at),
  KEY idx_otp_expiry (expires_at),
  CONSTRAINT fk_otp_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The email that carries the code. Editable from the admin panel like the
-- other transactional emails (Admin -> Email Templates).
INSERT IGNORE INTO email_templates (tenant_id, code, name, description, subject, html_body, variables)
SELECT t.id, 'otp_verify', 'Verification code',
       'Sent when a customer requests a code to create an account or sign in',
       'Your {{brand}} verification code: {{otp_code}}',
       CONCAT('<p>Hi,</p>',
              '<p>Your verification code is:</p>',
              '<p style="font-size:30px;letter-spacing:9px;font-weight:bold;margin:22px 0;">{{otp_code}}</p>',
              '<p>It expires in {{expires_minutes}} minutes. If you did not request ',
              'this, you can safely ignore this email - nobody can access your ',
              'account without the code.</p>'),
       JSON_ARRAY('brand', 'otp_code', 'expires_minutes', 'customer_email')
FROM tenants t;
