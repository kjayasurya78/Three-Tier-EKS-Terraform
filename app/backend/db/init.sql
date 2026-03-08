-- H&M Fashion Clone — PostgreSQL Schema Initialisation
-- This script runs automatically on first boot via Docker entrypoint or k8s init container

-- ── Extensions ───────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Users ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  name          VARCHAR(100) NOT NULL,
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role          VARCHAR(20) DEFAULT 'customer' CHECK (role IN ('customer','admin')),
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW()
);

-- ── Products ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
  id             SERIAL PRIMARY KEY,
  name           VARCHAR(200) NOT NULL,
  description    TEXT,
  price          NUMERIC(10,2) NOT NULL,
  original_price NUMERIC(10,2),
  category       VARCHAR(50) NOT NULL,
  sizes          TEXT[] DEFAULT ARRAY['XS','S','M','L','XL'],
  image_url      TEXT,
  stock          INTEGER DEFAULT 100,
  created_at     TIMESTAMP DEFAULT NOW()
);

-- ── Orders ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS orders (
  id               SERIAL PRIMARY KEY,
  user_id          INTEGER REFERENCES users(id) ON DELETE SET NULL,
  total_amount     NUMERIC(10,2) NOT NULL,
  shipping_address TEXT,
  phone            VARCHAR(20),
  status           VARCHAR(30) DEFAULT 'pending' CHECK (status IN ('pending','confirmed','shipped','delivered','cancelled')),
  created_at       TIMESTAMP DEFAULT NOW()
);

-- ── Order Items ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS order_items (
  id         SERIAL PRIMARY KEY,
  order_id   INTEGER REFERENCES orders(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
  quantity   INTEGER NOT NULL CHECK (quantity > 0),
  size       VARCHAR(5),
  price      NUMERIC(10,2) NOT NULL
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_products_category  ON products(category);
CREATE INDEX IF NOT EXISTS idx_orders_user_id     ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order  ON order_items(order_id);

-- ── Seed Products ─────────────────────────────────────────────────────────────
INSERT INTO products (name, description, price, original_price, category, sizes)
VALUES
  ('Slim Fit Cotton T-Shirt',         'Classic crew-neck tee in 100% organic cotton.', 599,  799,  'tops',    ARRAY['XS','S','M','L','XL','XXL']),
  ('Floral Wrap Dress',               'Lightweight viscose wrap dress with floral print.',1499, 1999, 'dresses', ARRAY['XS','S','M','L','XL']),
  ('Slim Fit Chinos',                 'Stretch chino in slim fit with five-pocket styling.',1299,1699,'pants',   ARRAY['S','M','L','XL','XXL']),
  ('Oversized Denim Jacket',          'Classic denim jacket with raw-edge hem.',2499, 2999, 'jackets', ARRAY['XS','S','M','L','XL']),
  ('Canvas Sneakers',                 'Casual lace-up sneakers in canvas.',1199, NULL,  'shoes',   ARRAY['38','39','40','41','42','43','44']),
  ('Leather Tote Bag',                'Spacious faux-leather tote with zip closure.',1799, 2299, 'bags',    ARRAY['ONE']),
  ('Striped Linen Shirt',             'Relaxed-fit linen shirt with a classic striped pattern.',1099,1399,'tops',ARRAY['XS','S','M','L','XL','XXL']),
  ('High-Waist Wide-Leg Trousers',    'Wide-leg trousers in a breathable woven fabric.',1599,1999,'pants',   ARRAY['XS','S','M','L','XL']),
  ('Cable-Knit Sweater',              'Soft cable-knit sweater in a relaxed silhouette.',1899,2499,'tops',    ARRAY['XS','S','M','L','XL','XXL']),
  ('Pleated Midi Skirt',              'Flowy pleated midi skirt with an elasticated waist.',999, 1299, 'dresses', ARRAY['XS','S','M','L','XL']),
  ('Puffer Jacket',                   'Lightweight quilted puffer jacket with hood.',2999, 3999, 'jackets', ARRAY['XS','S','M','L','XL','XXL']),
  ('Slip-On Loafers',                 'Classic slip-on loafers in faux suede.',1399, NULL,  'shoes',   ARRAY['38','39','40','41','42','43','44']),
  ('Ribbed Bodycon Dress',            'Stretchy ribbed-knit bodycon dress.',1199,1499,'dresses',ARRAY['XS','S','M','L','XL']),
  ('Cargo Shorts',                    'Relaxed cargo shorts with multiple pockets.',899,  1199, 'pants',   ARRAY['S','M','L','XL','XXL']),
  ('Crossbody Bag',                   'Compact crossbody bag with adjustable strap.',1299, 1699, 'bags',    ARRAY['ONE'])
ON CONFLICT DO NOTHING;
