-- =====================================================================
--  FILE 08 of 09 : Seed data for the TrueBellaa tenant
-- ---------------------------------------------------------------------
--  Loads: languages, currencies, permissions, the TrueBellaa brand,
--  its 3 roles + an admin login, attributes, categories, and all 12
--  products (English + Hindi) with variants. Safe to run once on a
--  fresh database.  Passwords here are placeholder bcrypt hashes — the
--  real app will replace them on first login.
-- =====================================================================

-- USE truebellaa;
SET NAMES utf8mb4;   -- CRITICAL: makes multi-language text load correctly
                     -- even if your mysql client defaults to latin1.

-- Load fast + all-or-nothing.
SET @app_user_id = 0;   -- 0 = system, so the price trigger logs 'system' during seed
START TRANSACTION;

-- ---- Languages (global) ----
INSERT INTO locales (code, english_name, native_name, is_rtl, is_active) VALUES
  ('en', 'English', 'English', 0, 1),
  ('hi', 'Hindi', 'हिन्दी', 0, 1),
  ('ta', 'Tamil', 'தமிழ்', 0, 1),
  ('bn', 'Bengali', 'বাংলা', 0, 1),
  ('mr', 'Marathi', 'मराठी', 0, 1);

-- ---- Currencies (global) ----
INSERT INTO currencies (code, symbol, name, decimal_digits) VALUES
  ('INR', '₹', 'Indian Rupee', 2),
  ('USD', '$', 'US Dollar', 2);

-- ---- Permission catalog (global) ----
INSERT INTO permissions (code, category, description) VALUES
  ('product.view', 'catalog', 'View products'),
  ('product.create', 'catalog', 'Create products'),
  ('product.update', 'catalog', 'Edit products'),
  ('product.delete', 'catalog', 'Delete products'),
  ('product.price_update', 'catalog', 'Change product prices'),
  ('product.image_upload', 'catalog', 'Upload/attach product images'),
  ('category.manage', 'catalog', 'Manage categories'),
  ('inventory.manage', 'catalog', 'Adjust stock'),
  ('order.view', 'orders', 'View orders'),
  ('order.update_status', 'orders', 'Move orders through fulfilment'),
  ('order.cancel', 'orders', 'Cancel orders'),
  ('order.refund', 'orders', 'Issue refunds'),
  ('shipment.create', 'shipping', 'Create Shiprocket shipments'),
  ('shipment.view', 'shipping', 'View shipments / tracking'),
  ('customer.view', 'customers', 'View customers'),
  ('customer.update', 'customers', 'Edit customers'),
  ('customer.block', 'customers', 'Block/unblock customers'),
  ('coupon.manage', 'marketing', 'Create/manage coupons'),
  ('newsletter.manage', 'marketing', 'Manage newsletter list'),
  ('review.moderate', 'marketing', 'Approve/reject reviews'),
  ('payment.view', 'payments', 'View payments'),
  ('user.manage', 'admin', 'Manage staff users'),
  ('role.manage', 'admin', 'Manage roles & permissions'),
  ('settings.manage', 'admin', 'Manage store settings'),
  ('audit.view', 'admin', 'View audit logs'),
  ('report.view', 'admin', 'View reports & dashboards');

-- ---- The TrueBellaa brand (tenant #1) ----
INSERT INTO tenants
  (public_id, name, slug, legal_name, primary_domain, support_email,
   default_locale_code, default_currency_code, status)
VALUES
  ('TENANT00000100000000000000', 'TrueBellaa', 'truebellaa', 'TrueBellaa Jewellery Pvt Ltd',
   'truebellaa.com', 'care@truebellaa.com', 'en', 'INR', 'active');
SET @tenant_id = LAST_INSERT_ID();

-- Enable all five languages for TrueBellaa; English is the default.
INSERT INTO tenant_locales (tenant_id, locale_code, is_default, is_active) VALUES
  (@tenant_id, 'en', 1, 1),
  (@tenant_id, 'hi', 0, 1),
  (@tenant_id, 'ta', 0, 1),
  (@tenant_id, 'bn', 0, 1),
  (@tenant_id, 'mr', 0, 1);

-- ---- Roles for the 3 staff panels ----
INSERT INTO roles (tenant_id, code, name, description, is_system) VALUES
  (@tenant_id, 'admin',   'Administrator',       'Full access to everything',            1),
  (@tenant_id, 'manager', 'Operations Manager',  'Catalogue, orders, shipping, refunds',  1),
  (@tenant_id, 'sales',   'Marketing & Sales',   'Coupons, reviews, newsletter, customers',1);
SET @role_admin   = (SELECT id FROM roles WHERE tenant_id=@tenant_id AND code='admin');
SET @role_manager = (SELECT id FROM roles WHERE tenant_id=@tenant_id AND code='manager');
SET @role_sales   = (SELECT id FROM roles WHERE tenant_id=@tenant_id AND code='sales');

-- Admin gets every permission.
INSERT INTO role_permissions (role_id, permission_id) SELECT @role_admin, id FROM permissions;
-- Manager permissions.
INSERT INTO role_permissions (role_id, permission_id) SELECT @role_manager, id FROM permissions WHERE code IN ('product.view','product.create','product.update','product.delete','product.price_update','product.image_upload','category.manage','inventory.manage','order.view','order.update_status','order.cancel','order.refund','shipment.create','shipment.view','customer.view','customer.update','payment.view','review.moderate','audit.view','report.view');
-- Marketing/Sales permissions. (product.image_upload is deliberately left
-- out here — an Admin can grant it from Permissions.jsx if Sales should be
-- able to add product photos without full create/edit rights.)
INSERT INTO role_permissions (role_id, permission_id) SELECT @role_sales, id FROM permissions WHERE code IN ('product.view','coupon.manage','newsletter.manage','review.moderate','customer.view','order.view','report.view');

-- ---- Staff logins (password is a placeholder hash — reset on first use) ----
INSERT INTO users (tenant_id, public_id, email, full_name, password_hash, status) VALUES
  (@tenant_id, 'USER0000010000000000000000', 'admin@truebellaa.com',   'Store Admin',   '$2b$12$abcdefghijklmnopqrstuuT0oh0Placeholder0Hash0Replace00', 'active'),
  (@tenant_id, 'USER0000020000000000000000', 'manager@truebellaa.com', 'Ops Manager',   '$2b$12$abcdefghijklmnopqrstuuT0oh0Placeholder0Hash0Replace00', 'active'),
  (@tenant_id, 'USER0000030000000000000000', 'sales@truebellaa.com',   'Marketing Lead','$2b$12$abcdefghijklmnopqrstuuT0oh0Placeholder0Hash0Replace00', 'active');
SET @user_admin   = (SELECT id FROM users WHERE tenant_id=@tenant_id AND email='admin@truebellaa.com');
SET @user_manager = (SELECT id FROM users WHERE tenant_id=@tenant_id AND email='manager@truebellaa.com');
SET @user_sales   = (SELECT id FROM users WHERE tenant_id=@tenant_id AND email='sales@truebellaa.com');
INSERT INTO user_roles (user_id, role_id, tenant_id) VALUES
  (@user_admin, @role_admin, @tenant_id),
  (@user_manager, @role_manager, @tenant_id),
  (@user_sales, @role_sales, @tenant_id);

-- ---- Attributes: Metal and Length ----
INSERT INTO attributes (tenant_id, code, position) VALUES
  (@tenant_id, 'metal', 1),
  (@tenant_id, 'length', 2);
SET @attr_metal  = (SELECT id FROM attributes WHERE tenant_id=@tenant_id AND code='metal');
SET @attr_length = (SELECT id FROM attributes WHERE tenant_id=@tenant_id AND code='length');

INSERT INTO attribute_translations (attribute_id, locale_code, label) VALUES
  (@attr_metal, 'en', 'Metal'),
  (@attr_metal, 'hi', 'धातु'),
  (@attr_metal, 'ta', 'உலோகம்'),
  (@attr_metal, 'bn', 'ধাতু'),
  (@attr_metal, 'mr', 'धातू'),
  (@attr_length, 'en', 'Length'),
  (@attr_length, 'hi', 'लंबाई'),
  (@attr_length, 'ta', 'நீளம்'),
  (@attr_length, 'bn', 'দৈর্ঘ্য'),
  (@attr_length, 'mr', 'लांबी');

-- Metal values (with swatch colours matching the frontend).
INSERT INTO attribute_values (attribute_id, tenant_id, code, hex_color, position) VALUES
  (@attr_metal, @tenant_id, 'gold', '#c9a24b', 1),
  (@attr_metal, @tenant_id, 'silver', '#c4c4c4', 2),
  (@attr_metal, @tenant_id, 'steel', '#8a8f96', 3);

-- Length values.
INSERT INTO attribute_values (attribute_id, tenant_id, code, position) VALUES
  (@attr_length, @tenant_id, '16in', 1),
  (@attr_length, @tenant_id, '18in', 2),
  (@attr_length, @tenant_id, '20in', 3),
  (@attr_length, @tenant_id, '22in', 4),
  (@attr_length, @tenant_id, '24in', 5),
  (@attr_length, @tenant_id, '7in', 6),
  (@attr_length, @tenant_id, '8in', 7),
  (@attr_length, @tenant_id, 'onesize', 8);

-- Value translations (metals in all 5 languages, lengths in EN + HI).
INSERT INTO attribute_value_translations (attribute_value_id, locale_code, label) VALUES
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold'), 'en', 'Gold'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold'), 'hi', 'सोना'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold'), 'ta', 'தங்கம்'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold'), 'bn', 'সোনা'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold'), 'mr', 'सोने'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver'), 'en', 'Silver'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver'), 'hi', 'चांदी'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver'), 'ta', 'வெள்ளி'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver'), 'bn', 'রূপা'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver'), 'mr', 'चांदी'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel'), 'en', 'Steel'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel'), 'hi', 'स्टील'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel'), 'ta', 'எஃகு'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel'), 'bn', 'ইস্পাত'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel'), 'mr', 'स्टील'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='16in'), 'en', '16"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='16in'), 'hi', '16 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in'), 'en', '18"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in'), 'hi', '18 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in'), 'en', '20"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in'), 'hi', '20 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in'), 'en', '22"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in'), 'hi', '22 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='24in'), 'en', '24"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='24in'), 'hi', '24 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='7in'), 'en', '7"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='7in'), 'hi', '7 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='8in'), 'en', '8"'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='8in'), 'hi', '8 इंच'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='onesize'), 'en', 'One size'),
  ((SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='onesize'), 'hi', 'एक ही आकार');

-- ---- Categories ----
INSERT INTO categories (tenant_id, slug, position, is_active) VALUES
  (@tenant_id, 'chains', 1, 1),
  (@tenant_id, 'pendants', 2, 1),
  (@tenant_id, 'bracelets', 3, 1);
SET @cat_chains = (SELECT id FROM categories WHERE tenant_id=@tenant_id AND slug='chains');
SET @cat_pendants = (SELECT id FROM categories WHERE tenant_id=@tenant_id AND slug='pendants');
SET @cat_bracelets = (SELECT id FROM categories WHERE tenant_id=@tenant_id AND slug='bracelets');
INSERT INTO category_translations (category_id, locale_code, name) VALUES
  (@cat_chains, 'en', 'Chains'),
  (@cat_chains, 'hi', 'चेन'),
  (@cat_chains, 'ta', 'சங்கிலிகள்'),
  (@cat_chains, 'bn', 'চেইন'),
  (@cat_chains, 'mr', 'साखळ्या'),
  (@cat_pendants, 'en', 'Pendants'),
  (@cat_pendants, 'hi', 'पेंडेंट'),
  (@cat_pendants, 'ta', 'பதக்கங்கள்'),
  (@cat_pendants, 'bn', 'পেন্ডেন্ট'),
  (@cat_pendants, 'mr', 'पेंडंट'),
  (@cat_bracelets, 'en', 'Bracelets'),
  (@cat_bracelets, 'hi', 'ब्रेसलेट'),
  (@cat_bracelets, 'ta', 'கடகங்கள்'),
  (@cat_bracelets, 'bn', 'ব্রেসলেট'),
  (@cat_bracelets, 'mr', 'ब्रेसलेट');

-- ---- Products (language-independent facts) ----
INSERT INTO products (tenant_id, public_id, category_id, slug, sku_prefix, base_price, currency_code, rating_avg, rating_count, status, published_at) VALUES
  (@tenant_id, 'PRODUCT0000010000000000000', @cat_pendants, 'eagle-statement-pendant', 'TB-001', 208.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000020000000000000', @cat_chains, 'herringbone-gold-chain', 'TB-002', 214.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000030000000000000', @cat_chains, 'faceted-bar-link-necklace', 'TB-003', 218.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000040000000000000', @cat_pendants, 'triangle-onyx-pendant', 'TB-004', 233.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000050000000000000', @cat_bracelets, 'cuban-link-bracelet', 'TB-005', 208.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000060000000000000', @cat_chains, 'rope-steel-chain', 'TB-006', 228.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000070000000000000', @cat_pendants, 'black-dog-tag-pendant', 'TB-007', 238.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000080000000000000', @cat_pendants, 'compass-medallion-pendant', 'TB-008', 208.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000090000000000000', @cat_pendants, 'lightning-bolt-pendant', 'TB-009', 214.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000100000000000000', @cat_pendants, 'cross-pave-pendant', 'TB-010', 225.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000110000000000000', @cat_bracelets, 'twisted-bangle-bracelet', 'TB-011', 219.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP),
  (@tenant_id, 'PRODUCT0000120000000000000', @cat_chains, 'box-chain-necklace', 'TB-012', 228.00, 'INR', 4.80, 126, 'active', CURRENT_TIMESTAMP);

SET @p1 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='eagle-statement-pendant');
SET @p2 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='herringbone-gold-chain');
SET @p3 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='faceted-bar-link-necklace');
SET @p4 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='triangle-onyx-pendant');
SET @p5 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='cuban-link-bracelet');
SET @p6 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='rope-steel-chain');
SET @p7 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='black-dog-tag-pendant');
SET @p8 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='compass-medallion-pendant');
SET @p9 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='lightning-bolt-pendant');
SET @p10 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='cross-pave-pendant');
SET @p11 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='twisted-bangle-bracelet');
SET @p12 = (SELECT id FROM products WHERE tenant_id=@tenant_id AND slug='box-chain-necklace');

-- Product text in English + Hindi (add ta/bn/mr rows the same way).
INSERT INTO product_translations (product_id, locale_code, name, short_description, description, care_instructions) VALUES
  (@p1, 'en', 'Eagle Statement Pendant', 'Hand-finished silver-tone pendant.', 'A refined eagle statement pendant in skin-safe silver tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p1, 'hi', 'ईगल स्टेटमेंट पेंडेंट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Silver टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p2, 'en', 'Herringbone Gold Chain', 'Hand-finished gold-tone chain.', 'A refined herringbone gold chain in skin-safe gold tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p2, 'hi', 'हेरिंगबोन गोल्ड चेन', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Gold टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p3, 'en', 'Faceted Bar Link Necklace', 'Hand-finished gold-tone chain.', 'A refined faceted bar link necklace in skin-safe gold tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p3, 'hi', 'फेसटेड बार लिंक नेकलेस', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Gold टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p4, 'en', 'Triangle Onyx Pendant', 'Hand-finished silver-tone pendant.', 'A refined triangle onyx pendant in skin-safe silver tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p4, 'hi', 'ट्रायंगल ओनिक्स पेंडेंट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Silver टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p5, 'en', 'Cuban Link Bracelet', 'Hand-finished gold-tone bracelet.', 'A refined cuban link bracelet in skin-safe gold tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p5, 'hi', 'क्यूबन लिंक ब्रेसलेट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Gold टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p6, 'en', 'Rope Steel Chain', 'Hand-finished steel-tone chain.', 'A refined rope steel chain in skin-safe steel tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p6, 'hi', 'रोप स्टील चेन', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Steel टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p7, 'en', 'Black Dog Tag Pendant', 'Hand-finished steel-tone pendant.', 'A refined black dog tag pendant in skin-safe steel tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p7, 'hi', 'ब्लैक डॉग टैग पेंडेंट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Steel टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p8, 'en', 'Compass Medallion Pendant', 'Hand-finished silver-tone pendant.', 'A refined compass medallion pendant in skin-safe silver tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p8, 'hi', 'कम्पास मेडलियन पेंडेंट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Silver टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p9, 'en', 'Lightning Bolt Pendant', 'Hand-finished silver-tone pendant.', 'A refined lightning bolt pendant in skin-safe silver tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p9, 'hi', 'लाइटनिंग बोल्ट पेंडेंट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Silver टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p10, 'en', 'Cross Pavé Pendant', 'Hand-finished silver-tone pendant.', 'A refined cross pavé pendant in skin-safe silver tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p10, 'hi', 'क्रॉस पावे पेंडेंट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Silver टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p11, 'en', 'Twisted Bangle Bracelet', 'Hand-finished gold-tone bracelet.', 'A refined twisted bangle bracelet in skin-safe gold tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p11, 'hi', 'ट्विस्टेड बैंगल ब्रेसलेट', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Gold टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।'),
  (@p12, 'en', 'Box Chain Necklace', 'Hand-finished silver-tone chain.', 'A refined box chain necklace in skin-safe silver tone. Tarnish-resistant, hypoallergenic and finished by hand — built to layer and made for everyday wear.', 'Wipe with a soft dry cloth after wear. Avoid perfume, chlorine and moisture. Store flat in the pouch provided.'),
  (@p12, 'hi', 'बॉक्स चेन नेकलेस', 'हस्तनिर्मित आभूषण', 'त्वचा-सुरक्षित Silver टोन में एक परिष्कृत आभूषण। हाथ से तैयार, हाइपोएलर्जेनिक और रोज़ पहनने योग्य।', 'मुलायम सूखे कपड़े से पोंछें। इत्र और नमी से बचाएं।');

-- Product images (main + alternate), matching the frontend paths.
INSERT INTO product_images (tenant_id, product_id, url, alt_text, position, is_primary) VALUES
  (@tenant_id, @p1, '/images/products/eagle-statement-pendant.jpg', 'Eagle Statement Pendant', 1, 1),
  (@tenant_id, @p1, '/images/products/eagle-statement-pendant-alt.jpg', 'Eagle Statement Pendant alternate', 2, 0),
  (@tenant_id, @p2, '/images/products/herringbone-gold-chain.jpg', 'Herringbone Gold Chain', 1, 1),
  (@tenant_id, @p2, '/images/products/herringbone-gold-chain-alt.jpg', 'Herringbone Gold Chain alternate', 2, 0),
  (@tenant_id, @p3, '/images/products/faceted-bar-link-necklace.jpg', 'Faceted Bar Link Necklace', 1, 1),
  (@tenant_id, @p3, '/images/products/faceted-bar-link-necklace-alt.jpg', 'Faceted Bar Link Necklace alternate', 2, 0),
  (@tenant_id, @p4, '/images/products/triangle-onyx-pendant.jpg', 'Triangle Onyx Pendant', 1, 1),
  (@tenant_id, @p4, '/images/products/triangle-onyx-pendant-alt.jpg', 'Triangle Onyx Pendant alternate', 2, 0),
  (@tenant_id, @p5, '/images/products/cuban-link-bracelet.jpg', 'Cuban Link Bracelet', 1, 1),
  (@tenant_id, @p5, '/images/products/cuban-link-bracelet-alt.jpg', 'Cuban Link Bracelet alternate', 2, 0),
  (@tenant_id, @p6, '/images/products/rope-steel-chain.jpg', 'Rope Steel Chain', 1, 1),
  (@tenant_id, @p6, '/images/products/rope-steel-chain-alt.jpg', 'Rope Steel Chain alternate', 2, 0),
  (@tenant_id, @p7, '/images/products/black-dog-tag-pendant.jpg', 'Black Dog Tag Pendant', 1, 1),
  (@tenant_id, @p7, '/images/products/black-dog-tag-pendant-alt.jpg', 'Black Dog Tag Pendant alternate', 2, 0),
  (@tenant_id, @p8, '/images/products/compass-medallion-pendant.jpg', 'Compass Medallion Pendant', 1, 1),
  (@tenant_id, @p8, '/images/products/compass-medallion-pendant-alt.jpg', 'Compass Medallion Pendant alternate', 2, 0),
  (@tenant_id, @p9, '/images/products/lightning-bolt-pendant.jpg', 'Lightning Bolt Pendant', 1, 1),
  (@tenant_id, @p9, '/images/products/lightning-bolt-pendant-alt.jpg', 'Lightning Bolt Pendant alternate', 2, 0),
  (@tenant_id, @p10, '/images/products/cross-pave-pendant.jpg', 'Cross Pavé Pendant', 1, 1),
  (@tenant_id, @p10, '/images/products/cross-pave-pendant-alt.jpg', 'Cross Pavé Pendant alternate', 2, 0),
  (@tenant_id, @p11, '/images/products/twisted-bangle-bracelet.jpg', 'Twisted Bangle Bracelet', 1, 1),
  (@tenant_id, @p11, '/images/products/twisted-bangle-bracelet-alt.jpg', 'Twisted Bangle Bracelet alternate', 2, 0),
  (@tenant_id, @p12, '/images/products/box-chain-necklace.jpg', 'Box Chain Necklace', 1, 1),
  (@tenant_id, @p12, '/images/products/box-chain-necklace-alt.jpg', 'Box Chain Necklace alternate', 2, 0);

-- ---- Variants (one purchasable SKU per length) ----
INSERT INTO product_variants (tenant_id, product_id, sku, price, stock_on_hand, is_default, is_active) VALUES
  (@tenant_id, @p1, 'TB-001-SI-18IN', 208.00, 2, 1, 1),
  (@tenant_id, @p1, 'TB-001-SI-20IN', 208.00, 2, 0, 1),
  (@tenant_id, @p1, 'TB-001-SI-22IN', 208.00, 2, 0, 1),
  (@tenant_id, @p2, 'TB-002-GO-16IN', 214.00, 1, 1, 1),
  (@tenant_id, @p2, 'TB-002-GO-18IN', 214.00, 1, 0, 1),
  (@tenant_id, @p2, 'TB-002-GO-20IN', 214.00, 1, 0, 1),
  (@tenant_id, @p3, 'TB-003-GO-18IN', 218.00, 2, 1, 1),
  (@tenant_id, @p3, 'TB-003-GO-20IN', 218.00, 2, 0, 1),
  (@tenant_id, @p4, 'TB-004-SI-20IN', 233.00, 2, 1, 1),
  (@tenant_id, @p4, 'TB-004-SI-22IN', 233.00, 2, 0, 1),
  (@tenant_id, @p5, 'TB-005-GO-7IN', 208.00, 2, 1, 1),
  (@tenant_id, @p5, 'TB-005-GO-8IN', 208.00, 2, 0, 1),
  (@tenant_id, @p6, 'TB-006-ST-20IN', 228.00, 1, 1, 1),
  (@tenant_id, @p6, 'TB-006-ST-22IN', 228.00, 1, 0, 1),
  (@tenant_id, @p6, 'TB-006-ST-24IN', 228.00, 1, 0, 1),
  (@tenant_id, @p7, 'TB-007-ST-22IN', 238.00, 1, 1, 1),
  (@tenant_id, @p7, 'TB-007-ST-24IN', 238.00, 1, 0, 1),
  (@tenant_id, @p8, 'TB-008-SI-20IN', 208.00, 1, 1, 1),
  (@tenant_id, @p8, 'TB-008-SI-22IN', 208.00, 1, 0, 1),
  (@tenant_id, @p9, 'TB-009-SI-18IN', 214.00, 3, 1, 1),
  (@tenant_id, @p9, 'TB-009-SI-20IN', 214.00, 3, 0, 1),
  (@tenant_id, @p10, 'TB-010-SI-20IN', 225.00, 2, 1, 1),
  (@tenant_id, @p10, 'TB-010-SI-22IN', 225.00, 2, 0, 1),
  (@tenant_id, @p11, 'TB-011-GO-ONESIZE', 219.00, 2, 1, 1),
  (@tenant_id, @p12, 'TB-012-SI-18IN', 228.00, 2, 1, 1),
  (@tenant_id, @p12, 'TB-012-SI-20IN', 228.00, 2, 0, 1),
  (@tenant_id, @p12, 'TB-012-SI-22IN', 228.00, 2, 0, 1);

-- Link each variant to its metal + length attribute values.
INSERT INTO variant_attribute_values (variant_id, attribute_value_id)
  SELECT (SELECT id FROM product_variants WHERE sku='TB-001-SI-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-001-SI-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-001-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-001-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-001-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-001-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-002-GO-16IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-002-GO-16IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='16in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-002-GO-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-002-GO-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-002-GO-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-002-GO-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-003-GO-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-003-GO-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-003-GO-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-003-GO-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-004-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-004-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-004-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-004-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-005-GO-7IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-005-GO-7IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='7in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-005-GO-8IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-005-GO-8IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='8in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-006-ST-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-006-ST-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-006-ST-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-006-ST-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-006-ST-24IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-006-ST-24IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='24in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-007-ST-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-007-ST-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-007-ST-24IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='steel')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-007-ST-24IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='24in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-008-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-008-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-008-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-008-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-009-SI-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-009-SI-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-009-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-009-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-010-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-010-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-010-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-010-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-011-GO-ONESIZE'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='gold')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-011-GO-ONESIZE'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='onesize')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-012-SI-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-012-SI-18IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='18in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-012-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-012-SI-20IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='20in')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-012-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_metal AND code='silver')
  UNION ALL
  SELECT (SELECT id FROM product_variants WHERE sku='TB-012-SI-22IN'), (SELECT id FROM attribute_values WHERE attribute_id=@attr_length AND code='22in');

-- ---- One demo customer (so orders can be tested) ----
INSERT INTO customers (tenant_id, public_id, email, phone, full_name, preferred_locale,
   is_guest, marketing_opt_in, status) VALUES
  (@tenant_id, 'CUST0000010000000000000000', 'riya@example.com', '+919000000000', 'Riya Sharma', 'hi', 0, 1, 'active');

COMMIT;

-- Quick sanity check after loading:
SELECT (SELECT COUNT(*) FROM products)          AS products,
       (SELECT COUNT(*) FROM product_variants)  AS variants,
       (SELECT COUNT(*) FROM product_translations) AS translations,
       (SELECT COUNT(*) FROM role_permissions)   AS role_perms;
