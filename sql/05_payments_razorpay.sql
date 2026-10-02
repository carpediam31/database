-- =====================================================================
--  FILE 05 of 09 : Payments (Razorpay)
-- ---------------------------------------------------------------------
--  Razorpay flow this models:
--   1. Backend calls Razorpay "create order" -> get razorpay_order_id.
--      We store a `payments` row (status='created').
--   2. Customer pays on the Razorpay widget -> we get razorpay_payment_id
--      + signature. Backend VERIFIES the signature, then marks 'captured'.
--   3. Razorpay also POSTs a webhook. We store every webhook in
--      `payment_webhook_events` with a UNIQUE event id so the same event
--      can never be processed twice (idempotency).
--   4. Refunds (full/partial) live in `payment_refunds`.
--
--  We NEVER store card numbers/CVV — Razorpay handles that. We only keep
--  their reference ids + status.
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

CREATE TABLE payments (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id          BIGINT UNSIGNED NOT NULL,
  order_id           BIGINT UNSIGNED NOT NULL,
  provider           VARCHAR(30)  NOT NULL DEFAULT 'razorpay',
  razorpay_order_id  VARCHAR(64)  NULL COMMENT 'rzp order id (order_XXXX)',
  razorpay_payment_id VARCHAR(64) NULL COMMENT 'rzp payment id (pay_XXXX)',
  razorpay_signature VARCHAR(255) NULL COMMENT 'HMAC we verified',
  amount             DECIMAL(12,2) NOT NULL,
  currency_code      CHAR(3)      NOT NULL DEFAULT 'INR',
  status             ENUM('created','authorized','captured','failed','refunded','partially_refunded')
                     NOT NULL DEFAULT 'created',
  method             VARCHAR(30)  NULL COMMENT 'upi | card | netbanking | wallet',
  signature_verified TINYINT(1)   NOT NULL DEFAULT 0,
  error_code         VARCHAR(80)  NULL,
  error_description  VARCHAR(255) NULL,
  raw_response       JSON         NULL COMMENT 'full gateway payload for debugging',
  authorized_at      TIMESTAMP    NULL,
  captured_at        TIMESTAMP    NULL,
  created_at         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_payments_rzp_payment (razorpay_payment_id),
  KEY idx_payments_order (order_id),
  KEY idx_payments_tenant_status (tenant_id, status),
  KEY idx_payments_rzp_order (razorpay_order_id),
  CONSTRAINT fk_pay_order  FOREIGN KEY (order_id)  REFERENCES orders(id)  ON DELETE CASCADE,
  CONSTRAINT fk_pay_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE payment_refunds (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id          BIGINT UNSIGNED NOT NULL,
  payment_id         BIGINT UNSIGNED NOT NULL,
  razorpay_refund_id VARCHAR(64)  NULL,
  amount             DECIMAL(12,2) NOT NULL,
  status             ENUM('pending','processed','failed') NOT NULL DEFAULT 'pending',
  reason             VARCHAR(255) NULL,
  initiated_by       BIGINT UNSIGNED NULL COMMENT 'staff user who issued it',
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at       TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_refund_rzp (razorpay_refund_id),
  KEY idx_refund_payment (payment_id),
  KEY idx_refund_tenant (tenant_id),
  CONSTRAINT fk_ref_payment FOREIGN KEY (payment_id)   REFERENCES payments(id) ON DELETE CASCADE,
  CONSTRAINT fk_ref_user    FOREIGN KEY (initiated_by) REFERENCES users(id)    ON DELETE SET NULL,
  CONSTRAINT fk_ref_tenant  FOREIGN KEY (tenant_id)    REFERENCES tenants(id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Every webhook Razorpay sends is logged here BEFORE we act on it. The
-- UNIQUE(provider,event_id) means a retried/duplicate webhook is ignored.
CREATE TABLE payment_webhook_events (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id          BIGINT UNSIGNED NULL COMMENT 'resolved after parsing',
  provider           VARCHAR(30)  NOT NULL DEFAULT 'razorpay',
  event_id           VARCHAR(120) NOT NULL COMMENT 'x-razorpay-event-id',
  event_type         VARCHAR(80)  NULL COMMENT 'payment.captured, refund.processed',
  signature_verified TINYINT(1)   NOT NULL DEFAULT 0,
  payload            JSON         NOT NULL,
  processing_status  ENUM('received','processed','ignored','error') NOT NULL DEFAULT 'received',
  error_message      VARCHAR(255) NULL,
  received_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at       TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pwe_provider_event (provider, event_id),
  KEY idx_pwe_tenant (tenant_id),
  CONSTRAINT fk_pwe_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
