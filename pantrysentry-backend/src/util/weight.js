// Epic 8 — converts an inventory item's (quantity, unit) into kilograms,
// since every emission factor is expressed per kg of food (see
// Formula_CO2e.pdf, section 3: "All food quantities must be converted to
// kilograms before calculation").
//
// Three kinds of conversion, and the response reports which one was used
// for each item so the UI can be honest about how exact a figure is:
//   'mass'       — g / kg / mg. Exact.
//   'volume'     — mL / L. Approximate: assumes a density of 1 kg per
//                  litre (water). Close for milk, juice and most drinks;
//                  rougher for oils and syrups.
//   'unitWeight' — pcs / pack / box / bottle / can / dozen. Approximate:
//                  uses an average weight per unit for that category from
//                  the unit_weight_reference table (curated by the data
//                  team). If no row exists, the item can't be converted
//                  and is reported as excluded rather than guessed at.

const MASS_TO_KG = { kg: 1, g: 0.001, mg: 0.000001 };
const VOLUME_TO_LITRES = { l: 1, ml: 0.001 };
const ASSUMED_DENSITY_KG_PER_LITRE = 1.0;

// Spelling variants that may already exist in older rows (the unit field
// was free text before kUnitOptions became a dropdown).
const UNIT_ALIASES = {
  pc: 'pcs', piece: 'pcs', pieces: 'pcs', item: 'pcs', items: 'pcs',
  gram: 'g', grams: 'g', gm: 'g', gms: 'g',
  kilogram: 'kg', kilograms: 'kg', kgs: 'kg',
  milligram: 'mg', milligrams: 'mg',
  litre: 'l', litres: 'l', liter: 'l', liters: 'l', ltr: 'l',
  millilitre: 'ml', millilitres: 'ml', milliliter: 'ml', milliliters: 'ml',
  packs: 'pack', packet: 'pack', packets: 'pack',
  boxes: 'box', bottles: 'bottle', cans: 'can', tin: 'can', tins: 'can',
};

function normaliseUnit(unit) {
  const u = String(unit || 'pcs').trim().toLowerCase();
  return UNIT_ALIASES[u] || u;
}

/** Key for the unit-weight lookup map built from unit_weight_reference. */
function unitWeightKey(categoryId, unit) {
  return `${categoryId}|${normaliseUnit(unit)}`;
}

/**
 * Returns { kg, basis } or null if this (unit, category) can't be
 * converted. [unitWeights] is a Map of unitWeightKey -> kg per unit.
 */
function toKilograms(quantity, unit, categoryId, unitWeights) {
  const q = Number(quantity);
  if (!Number.isFinite(q) || q < 0) return null;
  const u = normaliseUnit(unit);

  if (MASS_TO_KG[u] !== undefined) {
    return { kg: q * MASS_TO_KG[u], basis: 'mass' };
  }
  if (VOLUME_TO_LITRES[u] !== undefined) {
    return { kg: q * VOLUME_TO_LITRES[u] * ASSUMED_DENSITY_KG_PER_LITRE, basis: 'volume' };
  }

  const direct = unitWeights.get(unitWeightKey(categoryId, u));
  if (direct !== undefined) {
    return { kg: q * direct, basis: 'unitWeight' };
  }
  // A dozen is just 12 pieces — fall back to the per-piece weight rather
  // than needing a separate 'dozen' row for every category.
  if (u === 'dozen') {
    const perPiece = unitWeights.get(unitWeightKey(categoryId, 'pcs'));
    if (perPiece !== undefined) return { kg: q * 12 * perPiece, basis: 'unitWeight' };
  }
  return null;
}

module.exports = { toKilograms, normaliseUnit, unitWeightKey, ASSUMED_DENSITY_KG_PER_LITRE };
