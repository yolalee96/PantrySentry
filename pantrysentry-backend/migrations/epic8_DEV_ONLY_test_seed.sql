-- =====================================================================
-- DEV / TESTING ONLY — NOT the real mapping. Do not run on the live DB.
--
-- A handful of rows so the Epic 8 endpoint and Progress tab card can be
-- tested on a dev/branch database before the data team's real mapping
-- is ready. The factors are real OWID values, but which OWID entity
-- represents each PantryBuddy category, and every unit weight, are
-- placeholders. The data team's mapping replaces all of this.
--
-- To remove:  DELETE FROM unit_weight_reference WHERE basis_note LIKE 'DEV PLACEHOLDER%';
--             DELETE FROM emission_factor_reference WHERE mapping_note LIKE 'DEV PLACEHOLDER%';
-- =====================================================================

INSERT INTO emission_factor_reference (category_id, reference_id, owid_entity, kg_co2e_per_kg, mapping_method, mapping_note)
SELECT category_id, NULL, 'Eggs', 4.67, 'DIRECT', 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Eggs';
INSERT INTO emission_factor_reference (category_id, reference_id, owid_entity, kg_co2e_per_kg, mapping_method, mapping_note)
SELECT category_id, NULL, 'Milk', 3.15, 'REPRESENTATIVE', 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Dairy';
INSERT INTO emission_factor_reference (category_id, reference_id, owid_entity, kg_co2e_per_kg, mapping_method, mapping_note)
SELECT category_id, NULL, 'Poultry Meat', 9.87, 'REPRESENTATIVE', 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Meat';
INSERT INTO emission_factor_reference (category_id, reference_id, owid_entity, kg_co2e_per_kg, mapping_method, mapping_note)
SELECT category_id, NULL, 'Other Vegetables', 0.53, 'REPRESENTATIVE', 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Vegetables';

INSERT INTO unit_weight_reference (category_id, unit, kg_per_unit, basis_note)
SELECT category_id, 'pcs', 0.06, 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Eggs';
INSERT INTO unit_weight_reference (category_id, unit, kg_per_unit, basis_note)
SELECT category_id, 'bottle', 1.0, 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Dairy';
INSERT INTO unit_weight_reference (category_id, unit, kg_per_unit, basis_note)
SELECT category_id, 'pack', 0.5, 'DEV PLACEHOLDER' FROM product_categories WHERE category_name = 'Meat';
