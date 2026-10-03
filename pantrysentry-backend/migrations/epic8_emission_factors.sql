-- =====================================================================
-- Epic 8 — Environmental Impact: reference tables (PROPOSED)
--
-- NON-DESTRUCTIVE: CREATE TABLE IF NOT EXISTS only. Safe to run against
-- the live database. Do NOT fold this into the full rebuild script and
-- run that instead (see Iteration 2 lesson learned).
--
-- The backend route (src/routes/environmental_impact.js) reads exactly
-- these table and column names. If the data team changes any of them,
-- the two SELECTs in loadReferenceData() need the same change.
-- =====================================================================

-- One emission factor per PantryBuddy category (reference_id NULL),
-- plus optional product-specific overrides (reference_id set) — e.g. a
-- separate beef factor so beef isn't averaged in with chicken under
-- "Meat". The backend uses a product override first, then falls back to
-- the category row.
--
-- NOTE: MySQL/TiDB unique keys allow multiple NULLs, so the unique key
-- below does NOT stop two category-level rows (reference_id NULL) for the
-- same category. Keep exactly one per category; the backend uses
-- whichever it reads last if there are duplicates.
CREATE TABLE IF NOT EXISTS emission_factor_reference (
  emission_factor_id INT AUTO_INCREMENT PRIMARY KEY,
  category_id        INT NOT NULL,
  reference_id       INT NULL,
  owid_entity        VARCHAR(120) NOT NULL,    -- e.g. 'Poultry Meat', or 'Weighted: Milk 60% / Cheese 40%'
  kg_co2e_per_kg     DECIMAL(8,3) NOT NULL,    -- kg CO2e per kg of food
  mapping_method     VARCHAR(20) NOT NULL,     -- 'DIRECT' | 'REPRESENTATIVE' | 'WEIGHTED_AVERAGE'
  mapping_note       VARCHAR(500) NULL,        -- the justification, for the report
  source_name        VARCHAR(200) NOT NULL DEFAULT 'Poore & Nemecek (2018), via Our World in Data',
  source_url         VARCHAR(300) NULL DEFAULT 'https://ourworldindata.org/grapher/ghg-per-kg-poore',
  UNIQUE KEY uq_ef_category_reference (category_id, reference_id),
  CONSTRAINT fk_ef_category  FOREIGN KEY (category_id)  REFERENCES product_categories (category_id),
  CONSTRAINT fk_ef_reference FOREIGN KEY (reference_id) REFERENCES product_reference (reference_id)
);

-- Average weight of one 'pcs' / 'pack' / 'box' / 'bottle' / 'can' per
-- category, so count-based quantities can be converted to kg. Mass units
-- (g/kg/mg) need no row; volume units (mL/L) are converted in the backend
-- assuming 1 kg per litre. 'dozen' falls back to 12 x the 'pcs' weight
-- if it has no row of its own.
--
-- unit values must be lowercase: 'pcs', 'pack', 'box', 'bottle', 'can'.
-- An item whose unit has no row here is left out of the total and shown
-- as "couldn't be estimated", not guessed.
CREATE TABLE IF NOT EXISTS unit_weight_reference (
  unit_weight_id INT AUTO_INCREMENT PRIMARY KEY,
  category_id    INT NOT NULL,
  unit           VARCHAR(20) NOT NULL,
  kg_per_unit    DECIMAL(8,4) NOT NULL,
  basis_note     VARCHAR(500) NULL,            -- where the average weight came from
  UNIQUE KEY uq_unit_weight (category_id, unit),
  CONSTRAINT fk_uw_category FOREIGN KEY (category_id) REFERENCES product_categories (category_id)
);
