-- =====================================================================
--  FILE 11 : Editable email templates — Add-on
-- ---------------------------------------------------------------------
--  Transactional email copy used to be hard-coded in Python, so changing
--  a single word needed a developer and a redeploy. This table moves the
--  subject + HTML into the database so an Admin can edit them from the
--  admin panel (Settings -> Email templates), with the code falling back
--  to its built-in defaults if a row is missing or deactivated.
--
--  Placeholders are written as {{name}} and substituted at send time.
--  Each template's `variables` column documents which ones it supports,
--  so the editor UI can show the author exactly what's available.
--
--  Idempotent: safe to run more than once.
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS email_templates (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  code        VARCHAR(60)  NOT NULL COMMENT 'welcome | order_placed | payment_confirmed | order_shipped',
  name        VARCHAR(120) NOT NULL COMMENT 'label shown in the admin UI',
  description VARCHAR(255) NULL     COMMENT 'when this email goes out',
  subject     VARCHAR(255) NOT NULL,
  html_body   MEDIUMTEXT   NOT NULL,
  variables   JSON         NULL     COMMENT 'placeholder names this template supports',
  is_active   TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '0 = fall back to the built-in default',
  updated_by  BIGINT UNSIGNED NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_email_tpl (tenant_id, code),
  CONSTRAINT fk_emtpl_tenant FOREIGN KEY (tenant_id)  REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_emtpl_user   FOREIGN KEY (updated_by) REFERENCES users(id)   ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed the four transactional emails for every existing tenant.
INSERT IGNORE INTO email_templates (tenant_id, code, name, description, subject, html_body, variables)
SELECT t.id, 'welcome', 'Welcome email',
       'Sent when a customer creates an account',
       'Welcome to {{brand}}',
       CONCAT('<p>Hi {{customer_name}},</p>',
              '<p>Your account has been created. You can now track orders, save ',
              'favourites and check out faster next time.</p>'),
       JSON_ARRAY('brand', 'customer_name', 'customer_email')
FROM tenants t;

INSERT IGNORE INTO email_templates (tenant_id, code, name, description, subject, html_body, variables)
SELECT t.id, 'order_placed', 'Order received',
       'Sent immediately after checkout, before payment is confirmed',
       'Order received - {{order_number}}',
       CONCAT('<p>Hi {{customer_name}},</p>',
              '<p>Thank you - we have received your order <strong>{{order_number}}</strong> ',
              'for {{currency}} {{amount}}. We will email you again as soon as your ',
              'payment is confirmed.</p>',
              '<p style="color:#888;font-size:13px;">Order ID: {{order_public_id}}</p>'),
       JSON_ARRAY('brand', 'customer_name', 'order_number', 'order_public_id', 'amount', 'currency')
FROM tenants t;

INSERT IGNORE INTO email_templates (tenant_id, code, name, description, subject, html_body, variables)
SELECT t.id, 'payment_confirmed', 'Payment confirmed',
       'Sent once Razorpay confirms the payment',
       'Payment confirmed - {{order_number}}',
       CONCAT('<p>Hi {{customer_name}},</p>',
              '<p>Your payment for order <strong>{{order_number}}</strong> ',
              '({{currency}} {{amount}}) has been confirmed. We are preparing it ',
              'for shipment.</p>',
              '<p style="color:#888;font-size:13px;">Order ID: {{order_public_id}}</p>'),
       JSON_ARRAY('brand', 'customer_name', 'order_number', 'order_public_id', 'amount', 'currency')
FROM tenants t;

INSERT IGNORE INTO email_templates (tenant_id, code, name, description, subject, html_body, variables)
SELECT t.id, 'order_shipped', 'Order shipped',
       'Sent when a shipment is created and a tracking number exists',
       'Your order has shipped - {{order_number}}',
       CONCAT('<p>Hi {{customer_name}},</p>',
              '<p>Good news - order <strong>{{order_number}}</strong> is on its way.</p>',
              '<p>Courier: <strong>{{courier_name}}</strong><br>',
              'Tracking number: <strong>{{awb_code}}</strong></p>',
              '<p><a href="{{tracking_url}}">Track your parcel</a></p>'),
       JSON_ARRAY('brand', 'customer_name', 'order_number', 'order_public_id',
                  'courier_name', 'awb_code', 'tracking_url')
FROM tenants t;

-- Let the existing settings.manage permission gate this screen; it was
-- seeded in file 08 but had nothing behind it until now.
INSERT IGNORE INTO permissions (code, category, description) VALUES
  ('settings.manage', 'admin', 'Manage store settings');

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.code = 'admin' AND p.code = 'settings.manage';
