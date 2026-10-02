# TrueBellaa — Database Design & Documentation

**Project:** TrueBellaa fine-jewellery commerce platform
**This document covers:** Phase 1 — the database (schema + design decisions).
**Backend (FastAPI) is Phase 2** and is described at the end so you can see how the two fit together.
**Database engine:** MySQL 8.0+ (the `.sql` files also load on MariaDB 10.5+).

> New to databases? Read this top-to-bottom once. Every big word is explained the first time it appears. You do **not** need to memorise anything — the goal is that you understand *why* each table exists, so you can explain it to your client with confidence.

---

## 0. How to read this package

You received these files:

| File | What it is |
|------|-----------|
| `TrueBellaa_Database_Design.md` | **This document** — the full explanation. |
| `TrueBellaa_ER_Diagram.mermaid` | A picture of how the tables connect (open it in any Mermaid viewer, or it renders right in this chat). |
| `sql/00 … 09_*.sql` | The actual database, split into 10 ordered files you run on MySQL. |

To build the database, you run the SQL files **in number order** (00 first, 09 last). Section 12 shows the exact commands. Everything in this package has been **loaded and tested on a real MySQL-compatible server** — the orders, payments, price-change tracking and multi-language lookups were all executed successfully before delivery.

---

## 1. The big picture (in plain English)

TrueBellaa sells jewellery online. A shopper browses chains, pendants and bracelets, picks a length, adds to a bag, pays with Razorpay, and the parcel ships through Shiprocket. Behind the storefront, four kinds of people log in to four **panels**:

1. **Admin** — the owner. Sees everything, including the audit log ("who did what").
2. **Manager** — runs day-to-day operations: products, stock, orders, shipping, refunds.
3. **Marketing / Sales** — coupons, reviews, the newsletter, customer lists.
4. **Customer** — the shopper on the storefront.

On top of that, the client asked for five things that shape the whole design. Here is how each one is solved, so you can point to it directly:

| Requirement | How the database delivers it | Where |
|---|---|---|
| **Multi-tenancy** (many jewellery brands on one platform) | Every business table carries a `tenant_id`. One database safely holds many brands, each fully isolated. | all files |
| **Separate read & write databases** | The schema is written so the app can send *writes* to a primary DB and *reads* to replicas. Design + routing rules in §8. | §8 |
| **Multi-lingual** (English + Hindi + regional) | A "translation table" pattern: facts live once, text lives once per language. Add a language by inserting rows, never by changing tables. | `02` |
| **Audit logs** (login/logout, price changes, everything) | A universal `audit_logs` table, a focused `auth_events` table, and an always-on `product_price_history` trigger. | `07` |
| **Razorpay + Shiprocket** | Dedicated `payments` / `shipments` tables plus idempotent webhook tables so a repeated callback never double-charges or double-ships. | `05`, `06` |

---

## 2. Twelve core concepts (learn these once)

### 2.1 What "multi-tenant" means
A **tenant** is one brand/store. **Multi-tenant** means one system serves many tenants at the same time, while keeping each one's data private.

Think of an apartment building. One building (one database), many flats (tenants). Everyone shares the plumbing and lift (the tables, the code), but you can only enter *your* flat (your rows). The "key" that opens only your flat is the **`tenant_id`** column that sits on every business table. The application always adds `WHERE tenant_id = <the logged-in brand>` to every query, so Brand A can never see Brand B's products, orders or customers.

We chose this approach ("**shared database, shared schema, discriminator column**") over the alternatives on purpose:

| Strategy | What it is | Why we did / didn't pick it |
|---|---|---|
| Separate database per tenant | Each brand gets its own MySQL database | Strongest isolation, but painful to run migrations and reports across hundreds of brands. |
| Separate schema per tenant | One server, one schema per brand | Same operational pain at scale. |
| **Shared schema + `tenant_id`** ✅ | One set of tables, a `tenant_id` column marks ownership | **Simplest to operate, cheapest to scale, easiest to report on. The standard way SaaS platforms start.** |

Global reference data that is the *same* for everyone (the list of languages, the list of currencies, the master list of permission names) lives in tables **without** a `tenant_id`, because it isn't owned by any one brand.

### 2.2 Primary key vs public id
Every table has an `id` (a `BIGINT` number that counts up: 1, 2, 3…). It's fast for the database to join on, but we never show it to the outside world — if order URLs were `/order/1`, `/order/2`, anyone could guess how many orders exist and read others'. So important tables also get a **`public_id`**: a 26-character random-looking code (a **ULID**) that we put in URLs and invoices. Internal joins use `id`; the outside world sees `public_id`.

### 2.3 Money is never a decimal-float
Prices use `DECIMAL(12,2)` — exact to the paisa. We never use `FLOAT`/`DOUBLE` for money, because floats round in surprising ways (`0.1 + 0.2` isn't exactly `0.3`). `DECIMAL(12,2)` holds values up to 9,999,999,999.99 with two exact decimal places.

### 2.4 Translation tables (how multi-lingual works)
A product has two kinds of information:

* **Language-independent facts** — SKU, price, stock, images. Same in every language. These live in `products` / `product_variants`.
* **Language-dependent text** — name, description, care notes. Different per language. These live in `product_translations`, **one row per language**.

To show a product in Hindi, the app reads the product row **plus** the `product_translations` row where `locale_code = 'hi'`. If that Hindi row doesn't exist yet, it falls back to the tenant's default language. Adding Tamil later is just *inserting rows* — you never touch the table structure. This is why we did **not** use columns like `name_en`, `name_hi`, `name_ta`: that would force a schema change for every new language and get ugly fast.

### 2.5 Variants and SKUs
A **product** is the idea ("Cross Pavé Pendant"). A **variant** is a specific thing you can actually buy and count in stock — "Cross Pavé Pendant, Silver, 20 inch". Each variant has its own **SKU** (a unique stock code) and its own **price and stock**, because a 24-inch chain can legitimately cost more than an 18-inch one. Your frontend already thinks this way (length pills + metal swatches); variants make it real in the database.

### 2.6 Snapshots (why orders copy data)
When an order is placed, it must **freeze** what was true that day. If the product's name or price changes next month, or the customer edits their address, **past orders must not change** — an invoice is a historical record. So `order_items` copy the product name, variant label and price *into the order*, and the order copies the shipping address. We still keep a link back to the live product for reports, but the frozen copy is what the invoice shows.

### 2.7 Role-Based Access Control (RBAC) — the 4 panels
Instead of hard-coding "if admin then…", we use three small tables: **roles** (Admin, Manager, Sales), **permissions** (a master list like `product.price_update`, `order.refund`), and **role_permissions** (which role is allowed which permission). A staff member is linked to a role via **user_roles**. To change what a Manager can do, you tick/untick permissions — no code change. Customers are *not* in this system; they're ordinary shoppers with their own table.

### 2.8 Staff vs customers are different tables
`users` = back-office staff (Admin/Manager/Sales). `customers` = shoppers. They're separate because they log in through different screens, have different rules (a guest can check out with no password; a staff member never can), and you never want a catalogue editor and a buyer mixed in one table.

### 2.9 Audit log
An **audit log** answers "who did what, when". Every meaningful action writes one row: the actor, the action (`product.price_changed`), the thing affected, a before/after snapshot, the time, and the IP. The Admin panel reads this to show activity. Logins and logouts get their own focused table too, so the "login activity" screen is one fast query.

### 2.10 Idempotency (safe webhooks)
Razorpay and Shiprocket call your server ("**webhooks**") to say "payment captured" or "parcel delivered". The internet being what it is, they sometimes send the **same** message twice. **Idempotency** means "processing it twice does no extra harm". We store every webhook with a **unique event id**; if the same id arrives again, we recognise it and skip it. That's why `payment_webhook_events` and `shipping_webhook_events` exist.

### 2.11 Read vs write database
A busy store does far more *reading* (people browsing) than *writing* (people buying). MySQL lets you run one **primary** database that accepts writes, and one or more **replica** copies that only serve reads, automatically kept in sync. The schema here is designed so the app can split traffic this way. Full rules in §8.

### 2.12 Indexes
An **index** is like the index at the back of a book: it lets the database jump straight to the rows you want instead of reading every row. We add indexes on the columns we filter and join by most (`tenant_id`, `status`, foreign keys, `created_at`). They make reads fast; we don't over-add them because each one slightly slows writes.

---

## 3. The data model, group by group

The database is 30+ tables. They fall into eight groups. You do not need to hold all of them in your head — think in groups.

### Group A — Tenancy & Access  (`01_tenancy_and_rbac.sql`)
The foundation: brands, staff, and who-can-do-what.

| Table | Purpose (one line) |
|---|---|
| `tenants` | One row per jewellery brand. The root of everything. |
| `locales` | Global list of languages the platform can speak (en, hi, ta, bn, mr). |
| `currencies` | Global list of currencies (INR, USD). |
| `tenant_locales` | Which languages a given brand has switched on, and which is default. |
| `tenant_settings` | Per-brand config as key/value (theme colour, Razorpay key id, Shiprocket pickup). |
| `users` | Back-office **staff** accounts (Admin / Manager / Sales). |
| `roles` | The named roles for a brand (admin, manager, sales). |
| `permissions` | Master list of every action that can be permitted. |
| `role_permissions` | Which permissions each role grants. |
| `user_roles` | Which role(s) a staff member has. |
| `staff_sessions` | Active staff login sessions / refresh tokens (feeds "who's logged in"). |

### Group B — Catalog & Languages  (`02_catalog.sql`)
The products and everything that describes them, in every language.

| Table | Purpose |
|---|---|
| `categories` | Chains, Pendants, Bracelets (can nest via `parent_id`). |
| `category_translations` | Category names in each language. |
| `attributes` | The axes a product varies on: **Metal**, **Length**. |
| `attribute_translations` | The words "Metal"/"Length" in each language. |
| `attribute_values` | The choices: Gold/Silver/Steel, 16"/18"/20"… (with swatch colours). |
| `attribute_value_translations` | "Gold" → "सोना", `18"` → "18 इंच", etc. |
| `products` | Language-independent product facts (slug, base price, rating, status). |
| `product_translations` | Name / description / care notes per language. |
| `product_images` | Main + alternate images. |
| `product_variants` | The real sellable SKUs, each with its own price & stock. |
| `variant_attribute_values` | Which metal + length make up each variant. |
| `inventory_movements` | Append-only stock ledger: every +/- to stock, with a reason. |

### Group C — Customers  (`03_customers.sql`)

| Table | Purpose |
|---|---|
| `customers` | Shoppers (panel #4). Guests allowed (no password). |
| `customer_addresses` | Saved addresses (home/office). |
| `wishlist_items` | Saved-for-later products. |
| `newsletter_subscribers` | The footer newsletter signups. |
| `product_reviews` | Ratings + reviews (the "4.8 (126 reviews)" on the product page). |

### Group D — Cart & Orders  (`04_orders.sql`)

| Table | Purpose |
|---|---|
| `carts` | A work-in-progress bag (one active per customer/guest). |
| `cart_items` | Lines inside a cart. |
| `coupons` | Discount codes the Marketing panel manages. |
| `orders` | The order header: totals + a **frozen** copy of the shipping address. |
| `order_items` | Order lines with **frozen** product name/price. |
| `order_status_history` | Every status change (paid → shipped → delivered), by whom. |
| `coupon_redemptions` | Each time a coupon was actually used. |

### Group E — Payments (Razorpay)  (`05_payments_razorpay.sql`)

| Table | Purpose |
|---|---|
| `payments` | One row per payment attempt: Razorpay ids, amount, status, method. |
| `payment_refunds` | Full/partial refunds. |
| `payment_webhook_events` | Every Razorpay callback, stored once (idempotency). |

### Group F — Shipping (Shiprocket)  (`06_shipping_shiprocket.sql`)

| Table | Purpose |
|---|---|
| `shipments` | The parcel: AWB (tracking no.), courier, status, label. |
| `shipment_tracking_events` | The tracking timeline the customer sees. |
| `shipping_webhook_events` | Every Shiprocket callback, stored once (idempotency). |

### Group G — Audit & History  (`07_audit_and_history.sql`)

| Table | Purpose |
|---|---|
| `audit_logs` | Universal "who did what" log with before/after JSON. |
| `auth_events` | Login / logout / failed-login records. |
| `product_price_history` | Guaranteed price trail, filled automatically by a trigger. |

### Group H — Helper Views  (`09_views_and_helpers.sql`)
Saved queries that give the panels a clean shape to read from:
`v_active_products` (product list with price + image + English name), `v_low_stock` (Manager alert), `v_recent_activity` (Admin feed combining audit + logins).

---

## 4. The picture (ER diagram)

Open `TrueBellaa_ER_Diagram.mermaid`. It shows the core tables and how they connect. Read the crow's-foot lines as "one-to-many": `TENANTS ||--o{ PRODUCTS` means *one tenant has many products*. The audit and webhook tables are left out of the picture on purpose to keep it readable — they attach to the same tenants/orders you already see.

---

## 5. Data flows — follow the data step by step

These narratives are the heart of the "explain the flow" request. Each one traces exactly which tables are touched, in order.

### 5.1 A customer browses the shop in Hindi
1. The app knows the brand from the domain → it has the `tenant_id`.
2. It reads `tenant_locales` to confirm Hindi (`hi`) is enabled for this brand.
3. It lists products: `products` (filtered by `tenant_id`, `status='active'`) joined to `product_translations WHERE locale_code='hi'` for the names, joined to the default `product_variants` for price and to the primary `product_images` for the photo. (The `v_active_products` view already packages most of this.)
4. If a product has no Hindi row yet, the app falls back to the brand's default language. Nothing breaks.

### 5.2 Add to bag → checkout → pay with Razorpay
1. **Add to bag:** the app finds or creates a `carts` row for this customer/guest, then inserts/updates a `cart_items` row for the chosen **variant** (metal + length) with the current price copied in.
2. **Checkout form** (your existing screen: email, phone, name, address, city, PIN, state) is validated by the app.
3. **Create the order shell:** an `orders` row is written with `status='pending_payment'`, the money totals, and a **frozen copy** of the shipping address; `order_items` are copied from the cart with frozen names/prices. Stock is *reserved* (a `reservation` row in `inventory_movements`, `stock_reserved` bumped) so two people can't buy the last piece.
4. **Ask Razorpay to create an order:** the backend calls Razorpay, gets a `razorpay_order_id`, and writes a `payments` row (`status='created'`).
5. **Customer pays** on the Razorpay widget. The browser returns a `razorpay_payment_id` + a **signature**.
6. **Verify + capture:** the backend recomputes the signature to prove the callback is genuine, then sets the `payments` row to `status='captured'`, sets `signature_verified=1`, and moves the `orders` row to `status='paid'` with `placed_at=now`. Reserved stock becomes a real `sale` in `inventory_movements`.
7. **Webhook safety net:** Razorpay *also* POSTs a webhook. It's stored in `payment_webhook_events` keyed by its unique event id. If that id was already processed, it's ignored — so a duplicate callback can never mark the order paid twice.
8. **Confirmation:** the customer sees the success screen with the `order_number`.

### 5.3 Fulfilment → Shiprocket shipment → tracking
1. A **Manager** opens the paid order and clicks "Create shipment" (needs the `shipment.create` permission).
2. The backend calls Shiprocket; a `shipments` row is written with the `awb_code` (tracking number), `courier_name` and `status='ready_to_ship'`. The order moves to `status='processing'` → `shipped`, and that change is recorded in `order_status_history`.
3. As the parcel moves, Shiprocket sends webhooks. Each is stored once in `shipping_webhook_events`, then appended to `shipment_tracking_events` (status, location, time).
4. The customer's "Track order" page just reads `shipment_tracking_events` newest-first. When Shiprocket reports delivery, the shipment and order flip to `delivered`.

### 5.4 Admin changes a price (audit in action)
1. An **Admin/Manager** (with `product.price_update`) edits a variant's price.
2. Right after opening its DB connection, the backend runs `SET @app_user_id = <that staff id>;`.
3. The `UPDATE product_variants … SET price = …` fires. A **database trigger** automatically writes a `product_price_history` row: old price, new price, **who** (from `@app_user_id`), and when. This happens **even if the app code forgets to log** — it's a guarantee at the database level.
4. The app additionally writes an `audit_logs` row (`action='product.price_changed'`) with a human summary. The Admin panel's activity feed shows it instantly.
   *(Verified live: changing SKU `TB-010-SI-20IN` from ₹225 → ₹249 produced a history row attributed to the admin user.)*

### 5.5 Staff login / logout
On login, the app writes an `auth_events` row (`event='login'`, IP, device) and a `staff_sessions` row. On logout it writes `event='logout'` and revokes the session. Failed logins write `event='login_failed'` with the email that was tried — useful for spotting attacks. The Admin "who logged in and when" screen reads `auth_events` (and the combined `v_recent_activity` view shows logins next to every other action).

### 5.6 Adding a new language (say Tamil) — zero schema change
Enable it for the brand (`tenant_locales`), then insert Tamil rows into the `*_translations` tables for whatever you want translated. No `ALTER TABLE`, no downtime. Untranslated items simply fall back to the default language.

### 5.7 Onboarding a second brand (multi-tenancy in action)
Insert one `tenants` row, its `tenant_locales`, its three `roles` with permissions, and an admin `users` row. From then on, that brand's staff log in and see only their own data. *(Verified live: two brands — TrueBellaa and a second "Aurora Gems" — both hold a product with the slug `cross-pave-pendant` at different prices, with zero collision.)*

---

## 6. Read/write split — the "separate databases" requirement (§ detail)

**The shape:** one **primary** MySQL server takes all writes (checkout, price edits, order updates). One or more **read replicas** are exact copies kept in sync by MySQL replication, and they serve read-heavy traffic (browsing the catalogue, product pages, search).

**Why it's the best approach for customer handling here:** customers overwhelmingly *read* (thousands of catalogue views) and only occasionally *write* (a checkout). Sending all those reads to replicas keeps the primary free to handle orders quickly, and you scale reads by simply adding more replicas — without touching the primary.

**The one catch — "replication lag":** a replica can be a fraction of a second behind the primary. So right after a customer *writes* something they must immediately *see* (their brand-new order on the confirmation page, an admin who just edited a price), you must **read from the primary**, not a replica. This is called **read-your-own-writes**.

**Practical routing rules the backend follows:**

| Traffic | Send to |
|---|---|
| Catalogue browse, product pages, search, listings | **Replica** |
| Checkout, payments, order/stock/price updates, all admin writes | **Primary** |
| Reading data you *just* wrote (order confirmation, "save & view") | **Primary** |
| Reports/dashboards (heavy, can tolerate slight lag) | **Replica** |

Section 9 shows how a few lines of FastAPI/SQLAlchemy config make this automatic. For **day one you can point both at a single database** and split later — the schema and code don't change, you just add a replica connection string when traffic grows. Nothing about the tables needs to change to turn this on.

---

## 7. Scalability — how this grows without a rewrite

* **Tenant + status indexes.** The hot queries (`WHERE tenant_id = ? AND status = ?`) are indexed, so performance stays flat as rows grow.
* **Read replicas** (§6) absorb browse traffic; add more as you grow.
* **Append-only ledgers** (`inventory_movements`, `*_tracking_events`, `audit_logs`) only ever get inserts, which MySQL loves, and they give you perfect history.
* **Big log tables can be partitioned or archived by month.** `audit_logs` and webhook tables grow forever; when they get large you move old months to cold storage or use MySQL partitioning — no app change.
* **Caching later.** Product/catalogue reads can be cached in Redis in front of the replicas for another big jump, when needed.
* **Variants model real inventory.** Per-SKU stock means you can add sizes, metals or warehouses without redesign (a `warehouse_id` on `inventory_movements` is the natural next step).
* **`public_id` everywhere important** means you can shard or move data later without exposing internal counters.

Right-sized advice: **do not** run replicas, Redis, or partitioning on launch day. The design *allows* all of them; turn each on when a real bottleneck shows up. Starting simple is a feature.

---

## 8. Security notes (short but important)

* **Passwords** are stored only as a **hash** (bcrypt or Argon2) in `password_hash` — never plain text. The seed uses a placeholder hash.
* **We never store card numbers or CVV.** Razorpay handles card data; we only keep their reference ids and status.
* **Webhook signatures** from Razorpay/Shiprocket are verified before we trust a callback (`signature_verified`).
* **Tenant isolation** is enforced by the app always filtering on `tenant_id`. In the backend this is centralised (one place adds the filter) so a developer can't forget it. Optionally, MySQL row-level views can add a second layer.
* **Secrets** (API keys) belong in environment variables / a vault, **not** in the database. `tenant_settings` may hold *public* ids (like a Razorpay key id) but not secrets.

---

## 9. Phase 2 preview — the FastAPI backend & your "JPA for Python"

You asked for Java's JPA idea — *write the backend once, swap the database without rewriting code*. Python's equivalent is **SQLAlchemy** (the ORM) plus **Alembic** (migrations), and it's arguably cleaner than JPA. Here's the mapping so you can reassure the client:

| Java / JPA | Python / FastAPI equivalent | Role |
|---|---|---|
| JPA / Hibernate | **SQLAlchemy ORM** | Turns tables into Python classes; you write Python, it writes SQL. Swap MySQL→Postgres by changing one connection URL. |
| `@Entity` classes | SQLAlchemy models | One class per table. |
| JPA Repository | **Repository pattern** (thin classes) | `ProductRepository.get(id)` etc. — keeps SQL out of your route handlers. |
| Flyway / Liquibase | **Alembic** | Versioned schema migrations, so DB changes are tracked in git. |
| `persistence.xml` | Two SQLAlchemy **engines** | One bound to the primary (writes), one to the replica (reads) — this is exactly how §6's read/write split is wired. |

Sketch of the read/write split in code (Phase 2 — shown here only so you see how the DB design and the backend meet):

```python
# One engine for writes (primary), one for reads (replica).
write_engine = create_engine(PRIMARY_URL, pool_pre_ping=True)
read_engine  = create_engine(REPLICA_URL, pool_pre_ping=True)

# A request that only reads uses the read session; anything that writes,
# or must read-its-own-write, uses the write session. Because SQLAlchemy
# hides the SQL, switching databases later is a URL change, not a rewrite
# — that is the "JPA" guarantee you wanted.
```

Multi-tenancy in the backend is centralised: a dependency reads the brand from the request and every query automatically gets `WHERE tenant_id = ?`, so no developer can leak another brand's data by accident. When Phase 2 starts, this document's table groups map one-to-one onto SQLAlchemy models.

---

## 10. Running the SQL

```bash
# From the folder that contains the sql/ directory:
mysql -u root -p < sql/00_database_and_settings.sql
mysql -u root -p < sql/01_tenancy_and_rbac.sql
mysql -u root -p < sql/02_catalog.sql
mysql -u root -p < sql/03_customers.sql
mysql -u root -p < sql/04_orders.sql
mysql -u root -p < sql/05_payments_razorpay.sql
mysql -u root -p < sql/06_shipping_shiprocket.sql
mysql -u root -p < sql/07_audit_and_history.sql
mysql -u root -p < sql/08_seed_truebellaa.sql
mysql -u root -p < sql/09_views_and_helpers.sql
```

Order matters — later files reference tables created by earlier ones. After loading, the seed prints a quick count (12 products, 27 variants, etc.) so you know it worked. The seed creates the **TrueBellaa** brand, three staff logins (`admin@`, `manager@`, `sales@` — placeholder passwords), all 12 products from your frontend with English + Hindi text, and one demo customer.

---

## 11. What's deliberately left for later (so scope is clear)

These are easy to add on the same foundation when the client wants them, and are **not** built yet: tax/GST breakdown per line, gift wrapping, multi-warehouse stock, returns/RMA workflow, loyalty points, and full translations for Tamil/Bengali/Marathi product text (the *structure* supports all five languages today; only English + Hindi product text is seeded). None of these require redesigning existing tables.

---

*Prepared for the TrueBellaa project — Phase 1 (database). When you're ready, Phase 2 builds the FastAPI backend directly on top of these tables.*
