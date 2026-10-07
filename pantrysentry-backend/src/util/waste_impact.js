// Epic 8 — writes waste_impact_assessments rows, following the data
// team's rules (Database/Iteration 3/.../README.md, "Epic 8 Calculation
// Rules", and epic8_CO2e_calculation/README.md):
//
//   1. One assessment per DISCARD inventory transaction
//      (waste_impact_assessments.transaction_id is UNIQUE).
//   2. Convert the discarded quantity to kg with ONE direct
//      quantity_conversions row (no chaining — the data now has direct
//      l/ml/pcs/dozen -> kg rows for every product_reference):
//        a. product-specific row with is_assumed = 0 (measured)
//        b. product-specific row with is_assumed = 1 (assumed) — still
//           calculated, but flagged so the report says "based on
//           assumed values"
//        c. global row (reference_id NULL: g/kg/mg -> kg) — lowest priority
//      An item with no reference_id can't be converted -> EXCLUDED.
//   3. Use the active emission_factors row for the item's reference.
//   4. Snapshot the factor value/source/version so later factor updates
//      never rewrite historical numbers.
//   5. If either the factor or the conversion is missing, store
//      assessment_status = 'EXCLUDED' with a reason and NULL footprint.
//      Never guess, and never store 0 for "unknown".
//
// Assessments are created (a) straight after an item is discarded
// (routes/inventory.js) and (b) as a catch-up for any discard that
// doesn't have one yet — discards made before this existed, or if (a)
// failed — whenever the impact report is requested.

const { resolveReferenceIds } = require('./product_reference');
const { buildFactorMatcher } = require('./factor_matching');

// v2: factor chosen by the data team's food_type -> factor_name text
// matching (highest factor wins), product-reference factor as fallback.
const CALCULATION_METHOD_VERSION = 'epic8-v2: kg x factor, name match'; // column is VARCHAR(50)
const REASON_NO_REFERENCE = 'Missing emission factor (product not matched to reference data)';
const REASON_NO_FACTOR = 'Missing emission factor';
const UNAVAILABLE_MESSAGE = 'Environmental impact data is currently unavailable for this item.';
const REASON_NO_CONVERSION = 'Missing quantity conversion';
const BATCH_LIMIT = 500;

/** Units are compared case-insensitively: the Epic 8 data uses 'mL',
 * the recipe package uses 'ml', and older inventory rows are free text. */
function unitKey(u) {
  return String(u || '').trim().toLowerCase();
}

/**
 * Direct conversion of [quantity] [unit] to kg, following the data team's
 * priority (see header). [specificEdges] are the item's reference's rows,
 * [globalEdges] the reference_id NULL rows.
 * Edge: { conversionId, referenceId, fromUnit, toUnit, factor, isAssumed }
 * Returns { kg, conversionId, isAssumed, path } or null.
 */
function convertToKg(quantity, unit, specificEdges, globalEdges) {
  const q = Number(quantity);
  if (!Number.isFinite(q) || q <= 0) return null;
  const u = unitKey(unit);
  const direct = (edges) => edges
    .filter((e) => unitKey(e.fromUnit) === u && unitKey(e.toUnit) === 'kg')
    // is_assumed = 0 first; then the lowest id, so the choice is stable
    // if the same (reference, from, to) appears twice.
    .sort((a, b) => Number(a.isAssumed) - Number(b.isAssumed) || a.conversionId - b.conversionId)[0];
  const edge = direct(specificEdges) || direct(globalEdges);
  if (!edge) return null;
  return {
    kg: q * edge.factor,
    conversionId: edge.conversionId,
    isAssumed: edge.isAssumed,
    path: [u, 'kg'],
  };
}

function dateOnly(dbDateTime) {
  return String(dbDateTime).slice(0, 10);
}

/** The factor valid on [onDate] — newest valid_from wins. */
function pickFactor(rows, onDate) {
  const valid = rows.filter((f) =>
    (!f.valid_from || String(f.valid_from).slice(0, 10) <= onDate) &&
    (!f.valid_to || String(f.valid_to).slice(0, 10) >= onDate));
  if (valid.length === 0) return null;
  return valid.sort((a, b) =>
    String(b.valid_from || '').localeCompare(String(a.valid_from || '')) || Number(b.factor_id) - Number(a.factor_id))[0];
}

/**
 * Assesses DISCARD transactions of [teamId] that don't have an
 * assessment yet. Optional filters: { from, to } ('YYYY-MM-DD HH:MM:SS'
 * UTC) or { inventoryItemId }. Safe to call repeatedly and concurrently —
 * an already-assessed transaction is skipped by the UNIQUE key.
 * Returns the number of new assessments written.
 */
async function assessPendingDiscards(db, teamId, { from, to, inventoryItemId } = {}) {
  const filters = [];
  const params = [teamId];
  if (from && to) {
    filters.push('AND it.transaction_time BETWEEN ? AND ?');
    params.push(from, to);
  }
  if (inventoryItemId) {
    filters.push('AND it.inventory_item_id = ?');
    params.push(inventoryItemId);
  }
  const [pending] = await db.query(
    `SELECT it.transaction_id, it.inventory_item_id, it.quantity, it.transaction_time,
            ii.unit, ii.product_id, p.product_name, p.category_id
     FROM inventory_transactions it
     JOIN inventory_items ii ON ii.inventory_item_id = it.inventory_item_id
     JOIN products p ON p.product_id = ii.product_id
     LEFT JOIN waste_impact_assessments w ON w.transaction_id = it.transaction_id
     WHERE ii.team_id = ? AND it.transaction_type = 'DISCARD' AND w.assessment_id IS NULL
     ${filters.join(' ')}
     ORDER BY it.transaction_id
     LIMIT ${BATCH_LIMIT}`,
    params
  );
  if (pending.length === 0) return 0;

  const references = await resolveReferenceIds(db, pending.map((r) => ({
    productId: r.product_id, name: r.product_name, categoryId: r.category_id,
  })));
  const referenceIds = [...new Set([...references.values()].map((r) => r.referenceId))];

  // All active factors: the text matching looks across every food_type
  // and factor_name; the per-reference map is the fallback (step 3).
  const [allFactors] = await db.query(
    `SELECT factor_id, factor_name, reference_id, food_type, factor_kg_co2e_per_kg, source_name, source_version, valid_from, valid_to
     FROM emission_factors WHERE is_active = 1`
  );
  const factorsByRef = new Map();
  for (const f of allFactors) {
    if (f.reference_id === null || f.reference_id === undefined) continue;
    const key = Number(f.reference_id);
    if (!factorsByRef.has(key)) factorsByRef.set(key, []);
    factorsByRef.get(key).push(f);
  }
  const edgesByRef = new Map();
  // One matcher per discard date, over the factors valid on that date.
  const matcherByDate = new Map();
  const matcherFor = (onDate) => {
    if (!matcherByDate.has(onDate)) {
      matcherByDate.set(onDate, buildFactorMatcher(allFactors.filter((f) => pickFactor([f], onDate))));
    }
    return matcherByDate.get(onDate);
  };
  const [conversionRows] = await db.query(
    `SELECT conversion_id, reference_id, from_unit, to_unit, factor, is_assumed
     FROM quantity_conversions
     WHERE is_active = 1 AND LOWER(to_unit) = 'kg'
       AND (reference_id IS NULL${referenceIds.length > 0 ? ' OR reference_id IN (?)' : ''})`,
    referenceIds.length > 0 ? [referenceIds] : []
  );
  const genericEdges = [];
  for (const c of conversionRows) {
    const edge = {
      conversionId: Number(c.conversion_id),
      referenceId: c.reference_id === null ? null : Number(c.reference_id),
      fromUnit: c.from_unit,
      toUnit: c.to_unit,
      factor: Number(c.factor),
      isAssumed: Boolean(Number(c.is_assumed)),
    };
    if (!(edge.factor > 0)) continue;
    if (edge.referenceId === null) genericEdges.push(edge);
    else {
      if (!edgesByRef.has(edge.referenceId)) edgesByRef.set(edge.referenceId, []);
      edgesByRef.get(edge.referenceId).push(edge);
    }
  }

  let written = 0;
  for (const row of pending) {
    const ref = references.get(String(row.product_id)) || null;
    const referenceId = ref ? ref.referenceId : null;
    // Data team's rule: food_type match, then factor_name match (highest
    // factor wins), then (ours) the product reference's own factor.
    const onDate = dateOnly(row.transaction_time);
    const textMatch = matcherFor(onDate)(row.product_name);
    const refFactor = !textMatch && referenceId ? pickFactor(factorsByRef.get(referenceId) || [], onDate) : null;
    const factor = textMatch ? textMatch.row : refFactor;
    const factorMethod = textMatch ? textMatch.method : (refFactor ? 'reference' : null);
    // Product-specific conversions need a reference; without one, only the
    // global g/kg/mg rows apply (the factor no longer depends on a reference,
    // so an unmatched item weighed in grams can still be estimated).
    const conversion = convertToKg(row.quantity, row.unit, referenceId ? (edgesByRef.get(referenceId) || []) : [], genericEdges);

    let status = 'ASSESSED';
    let reason = null;
    if (!factor) {
      status = 'EXCLUDED';
      reason = REASON_NO_FACTOR;
    } else if (!conversion) {
      status = 'EXCLUDED';
      reason = REASON_NO_CONVERSION;
    }
    const factorValue = factor ? Number(factor.factor_kg_co2e_per_kg) : null;
    const notes = [
      ref ? `reference ${referenceId} matched by ${ref.method}` : 'no reference match',
      conversion ? `converted ${row.quantity} ${row.unit} -> ${conversion.kg.toFixed(6)} kg (conversion ${conversion.conversionId}${conversion.isAssumed ? ', assumed value' : ''})` : (referenceId ? `no ${row.unit} -> kg conversion for reference ${referenceId}` : 'not converted (no reference)'),
      factor ? `factor ${factorValue} kg CO2e/kg, food type ${factor.food_type || 'n/a'}, matched by ${factorMethod}`
        + (factorMethod === 'reference' ? '' : ' (highest factor among matches - conservative estimate)') : null,
    ].filter(Boolean).join('; ');

    const [result] = await db.query(
      `INSERT INTO waste_impact_assessments
         (team_id, inventory_item_id, transaction_id, product_id, reference_id, category_id,
          discarded_quantity, discarded_unit, converted_weight_kg, conversion_id, factor_id,
          factor_kg_co2e_per_kg_snapshot, factor_source_name_snapshot, factor_source_version_snapshot,
          calculation_method_version, footprint_kg_co2e, assessment_status, exclusion_reason,
          calculation_notes, discarded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE assessment_id = assessment_id`,
      [
        teamId, row.inventory_item_id, row.transaction_id, row.product_id, referenceId, row.category_id,
        row.quantity, row.unit || 'pcs',
        conversion ? Number(conversion.kg.toFixed(6)) : null,
        conversion ? conversion.conversionId : null,
        factor ? factor.factor_id : null,
        factorValue, factor ? factor.source_name : null, factor ? factor.source_version : null,
        CALCULATION_METHOD_VERSION,
        status === 'ASSESSED' ? Number((conversion.kg * factorValue).toFixed(6)) : null,
        status, reason, notes.slice(0, 1000), row.transaction_time,
      ]
    );
    if (result.affectedRows === 1) written += 1;
  }
  return written;
}

module.exports = {
  assessPendingDiscards,
  convertToKg,
  pickFactor,
  REASON_NO_CONVERSION,
  REASON_NO_FACTOR,
  REASON_NO_REFERENCE,
  UNAVAILABLE_MESSAGE,
};
