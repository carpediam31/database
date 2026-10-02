-- =====================================================================
--  FILE 06 of 09 : Shipping & delivery (Shiprocket)
-- ---------------------------------------------------------------------
--  After an order is paid, the Manager panel creates a Shiprocket
--  shipment. Shiprocket returns an AWB (tracking number) + courier. As
--  the parcel moves, Shiprocket pushes tracking updates (webhooks) which
--  we append to `shipment_tracking_events` — that timeline is what the
--  customer sees on "Track my order".
-- =====================================================================

USE truebellaa;
SET NAMES utf8mb4;

CREATE TABLE shipments (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id             BIGINT UNSIGNED NOT NULL,
  order_id              BIGINT UNSIGNED NOT NULL,
  provider              VARCHAR(30)  NOT NULL DEFAULT 'shiprocket',
  shiprocket_order_id   VARCHAR(64)  NULL,
  shiprocket_shipment_id VARCHAR(64) NULL,
  awb_code              VARCHAR(64)  NULL COMMENT 'tracking number',
  courier_name          VARCHAR(80)  NULL COMMENT 'Delhivery, BlueDart...',
  courier_id            VARCHAR(40)  NULL,
  status                ENUM('pending','ready_to_ship','pickup_scheduled','shipped',
                             'in_transit','out_for_delivery','delivered','rto',
                             'cancelled','failed')
                        NOT NULL DEFAULT 'pending',
  tracking_url          VARCHAR(500) NULL,
  label_url             VARCHAR(500) NULL,
  manifest_url          VARCHAR(500) NULL,
  weight_grams          INT NULL,
  length_cm             DECIMAL(6,2) NULL,
  breadth_cm            DECIMAL(6,2) NULL,
  height_cm             DECIMAL(6,2) NULL,
  shipping_charge       DECIMAL(12,2) NULL,
  pickup_scheduled_at   TIMESTAMP NULL,
  expected_delivery_at  TIMESTAMP NULL,
  shipped_at            TIMESTAMP NULL,
  delivered_at          TIMESTAMP NULL,
  raw_response          JSON NULL,
  created_by            BIGINT UNSIGNED NULL COMMENT 'staff who created it',
  created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ship_order (order_id),
  KEY idx_ship_tenant_status (tenant_id, status),
  KEY idx_ship_awb (awb_code),
  CONSTRAINT fk_ship_order  FOREIGN KEY (order_id)   REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_ship_user   FOREIGN KEY (created_by) REFERENCES users(id)  ON DELETE SET NULL,
  CONSTRAINT fk_ship_tenant FOREIGN KEY (tenant_id)  REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only tracking timeline for a shipment.
CREATE TABLE shipment_tracking_events (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  shipment_id   BIGINT UNSIGNED NOT NULL,
  status        VARCHAR(60)  NOT NULL,
  status_detail VARCHAR(255) NULL,
  location      VARCHAR(120) NULL,
  occurred_at   TIMESTAMP    NULL COMMENT 'time reported by courier',
  raw_payload   JSON         NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_track_shipment (shipment_id),
  KEY idx_track_tenant (tenant_id),
  CONSTRAINT fk_track_shipment FOREIGN KEY (shipment_id) REFERENCES shipments(id) ON DELETE CASCADE,
  CONSTRAINT fk_track_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Idempotent store of Shiprocket webhooks (same pattern as payments).
CREATE TABLE shipping_webhook_events (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id         BIGINT UNSIGNED NULL,
  provider          VARCHAR(30)  NOT NULL DEFAULT 'shiprocket',
  event_id          VARCHAR(120) NOT NULL COMMENT 'dedupe key (awb+status if no id)',
  event_type        VARCHAR(80)  NULL,
  payload           JSON         NOT NULL,
  processing_status ENUM('received','processed','ignored','error') NOT NULL DEFAULT 'received',
  error_message     VARCHAR(255) NULL,
  received_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at      TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_swe_provider_event (provider, event_id),
  KEY idx_swe_tenant (tenant_id),
  CONSTRAINT fk_swe_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
