-- =====================================================================
--  FILE 09 of 09 : Convenience VIEWS for the admin panels
-- ---------------------------------------------------------------------
--  Views are saved queries. They don't store data — they just give the
--  backend a clean, ready-made shape to read from, so common screens need
--  one simple SELECT instead of a big JOIN every time.
-- =====================================================================

-- USE truebellaa;
SET NAMES utf8mb4;

-- Storefront/admin product list: product + English name + default
-- variant price + primary image + category. (For other languages, the
-- app swaps the join to product_translations WHERE locale_code = ?.)
CREATE OR REPLACE VIEW v_active_products AS
SELECT
  p.id                AS product_id,
  p.tenant_id,
  p.public_id,
  p.slug,
  pt.name             AS name_en,
  c.slug              AS category_slug,
  p.base_price,
  p.rating_avg,
  p.rating_count,
  dv.sku              AS default_sku,
  dv.price            AS default_price,
  dv.stock_available  AS default_stock,
  img.url             AS primary_image,
  p.status
FROM products p
LEFT JOIN product_translations pt
       ON pt.product_id = p.id AND pt.locale_code = 'en'
LEFT JOIN categories c
       ON c.id = p.category_id
LEFT JOIN product_variants dv
       ON dv.product_id = p.id AND dv.is_default = 1
LEFT JOIN product_images img
       ON img.product_id = p.id AND img.is_primary = 1
WHERE p.deleted_at IS NULL;

-- Low-stock alert list for the Manager panel.
CREATE OR REPLACE VIEW v_low_stock AS
SELECT
  v.tenant_id,
  v.id            AS variant_id,
  v.sku,
  v.product_id,
  v.stock_on_hand,
  v.stock_reserved,
  v.stock_available
FROM product_variants v
WHERE v.is_active = 1
  AND v.stock_available <= 2;

-- Unified "recent activity" feed for the Admin panel: every audited
-- action PLUS every login/logout, newest first.
CREATE OR REPLACE VIEW v_recent_activity AS
SELECT
  tenant_id,
  created_at,
  actor_type,
  actor_id,
  action                       AS event,
  CONCAT_WS(' ', summary)      AS detail
FROM audit_logs
UNION ALL
SELECT
  tenant_id,
  created_at,
  actor_type,
  actor_id,
  CONCAT('auth.', event)       AS event,
  CONCAT_WS(' ', email_tried)  AS detail
FROM auth_events;
