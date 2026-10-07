const express = require('express');
const pool = require('../db');
const { CATEGORY_DART_NAMES } = require('../util/enums');
const { assertMember } = require('../util/household_access');
const { ApiError, asyncHandler } = require('../util/errors');
const { normaliseUnit } = require('../util/weight');
const { assessPendingDiscards, REASON_NO_CONVERSION } = require('../util/waste_impact');
const { PETROL_KG_CO2E_PER_LITRE, PETROL_SOURCE_NAME, petrolLitresFor } = require('../util/equivalents');

const router = express.Router();

// Epic 8 — Environmental Impact Insights.
//
// Total CO2e = Σ (Q_i × EF_i)
//   Q_i  = quantity of wasted item i, converted to kg (util/weight.js)
//   EF_i = lifecycle emission factor for item i, kg CO2e per kg
//          (Poore & Nemecek 2018, via Our World in Data)
// No GWP multiplier: the factors are already in CO2e (see
// Formula_CO2e.pdf, section 2).
//
// Calculated here on the server rather than in Flutter, so the figures
// come from one place, and the reference data never has to be shipped
// to the client.
//
// "Wasted" means status = DISCARDED only, with checkout_date as the
// moment it happened — the same definition the Progress tab's "Wasted"
// count uses, so the two numbers always describe the same set of items.
// Donated items are not waste and are never counted.
//
// Data (built by the data team, Iteration 3 schema):
//   emission_factors         — OWID factors per product_reference row
//   quantity_conversions     — unit -> kg conversions (generic + per product)
//   waste_impact_assessments — one row per DISCARD transaction, with the
//                              conversion and factor used snapshotted
// This route makes sure every discard in the requested span has an
// assessment (util/waste_impact.js), then reports from those rows, so the
// numbers shown always match what's stored and auditable in the DB.
// Items the data can't cover are EXCLUDED (never counted as 0) and shown
// as "couldn't be estimated".

const MAX_RANGE_DAYS = 366;
const MAX_TREND_PERIODS = 6; // e.g. 4 weeks or 4 months on screen; 6 allows a little headroom
const DAY_MS = 24 * 60 * 60 * 1000;

function parseInstant(value, name) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new ApiError(400, `${name} is required (ISO 8601 date-time).`);
  }
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) throw new ApiError(400, `${name} must be an ISO 8601 date-time.`);
  return d;
}

/** JS Date -> 'YYYY-MM-DD HH:MM:SS' in UTC, matching how DATETIME
 * columns are stored (and returned, with dateStrings: true). */
function toDbDateTime(d) {
  return d.toISOString().slice(0, 19).replace('T', ' ');
}

/** DATETIME string from mysql2 (dateStrings: true, no timezone marker,
 * genuinely UTC) -> JS Date. */
function fromDbDateTime(s) {
  if (s instanceof Date) return s;
  const normalised = String(s).includes('T') ? String(s) : String(s).replace(' ', 'T');
  return new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(normalised) ? normalised : `${normalised}Z`);
}

function round(n, dp = 3) {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
}

const MASS_UNITS = new Set(['g', 'kg', 'mg']);
const VOLUME_UNITS = new Set(['ml', 'l']);

/** How the weight was obtained, for the UI's "approximate" note. */
function weightBasisFor(unit) {
  const u = normaliseUnit(unit);
  if (MASS_UNITS.has(u)) return 'mass';
  if (VOLUME_UNITS.has(u)) return 'volume';
  return 'unitWeight';
}

function isMissingTable(err) {
  return err && (err.code === 'ER_NO_SUCH_TABLE' || err.errno === 1146);
}

// GET /households/:householdId/environmental-impact
//   ?start=<ISO>&end=<ISO>        the selected period (inclusive)
//   &trendStarts=<ISO>,<ISO>,...  optional: start instants of the earlier
//                                 periods to show in the trend, oldest
//                                 first, all before `start`. Each runs
//                                 until the next one starts; the last
//                                 runs until `start`. The client sends
//                                 these (rather than the server working
//                                 them out) because calendar weeks/months
//                                 are in the user's local timezone.
//
// The last trend period is also "the previous period" used for the
// headline comparison.
router.get('/households/:householdId/environmental-impact', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);

  const start = parseInstant(req.query.start, 'start');
  const end = parseInstant(req.query.end, 'end');
  if (end < start) throw new ApiError(400, 'end must be after start.');
  if (end - start > MAX_RANGE_DAYS * DAY_MS) throw new ApiError(400, `The period can be at most ${MAX_RANGE_DAYS} days.`);

  const trendStarts = req.query.trendStarts === undefined || req.query.trendStarts === ''
    ? []
    : String(req.query.trendStarts).split(',').map((v, i) => parseInstant(v, `trendStarts[${i}]`));
  if (trendStarts.length > MAX_TREND_PERIODS - 1) {
    throw new ApiError(400, `trendStarts can have at most ${MAX_TREND_PERIODS - 1} entries.`);
  }
  for (let i = 0; i < trendStarts.length; i++) {
    const next = i + 1 < trendStarts.length ? trendStarts[i + 1] : start;
    if (!(trendStarts[i] < next)) throw new ApiError(400, 'trendStarts must be in ascending order and before start.');
  }
  const earliest = trendStarts.length > 0 ? trendStarts[0] : start;
  if (end - earliest > (MAX_RANGE_DAYS + 40) * DAY_MS) {
    throw new ApiError(400, 'The trend covers too long a time span.');
  }

  // Periods oldest -> newest; the last one is the selected period.
  const periods = [
    ...trendStarts.map((s, i) => ({
      start: s,
      end: new Date((i + 1 < trendStarts.length ? trendStarts[i + 1] : start).getTime() - 1),
    })),
    { start, end },
  ].map((p) => ({ ...p, kgCo2e: 0, hasActivity: false, wasted: 0, assessed: 0 }));

  // Assess any discard in the whole span that doesn't have an assessment
  // yet. 'pendingData' only if the Epic 8 tables/data aren't there.
  try {
    const [factorCheck] = await pool.query('SELECT 1 FROM emission_factors WHERE is_active = 1 LIMIT 1');
    if (factorCheck.length === 0) return res.json({ status: 'pendingData' });
    await assessPendingDiscards(pool, req.params.householdId, { from: toDbDateTime(earliest), to: toDbDateTime(end) });
  } catch (err) {
    if (isMissingTable(err)) return res.json({ status: 'pendingData' });
    throw err;
  }

  // Resolved items of any kind, only to tell "no activity at all" apart
  // from "a real zero-waste period", so a comparison is never made
  // against an empty period.
  const [activityRows] = await pool.query(
    `SELECT checkout_date FROM inventory_items
     WHERE team_id = ? AND status IN ('CONSUMED', 'DISCARDED', 'DONATED')
       AND checkout_date BETWEEN ? AND ?`,
    [req.params.householdId, toDbDateTime(earliest), toDbDateTime(end)]
  );
  for (const row of activityRows) {
    const t = fromDbDateTime(row.checkout_date);
    const period = periods.find((p) => t >= p.start && t <= p.end);
    if (period) period.hasActivity = true;
  }

  const [rows] = await pool.query(
    `SELECT w.inventory_item_id, w.discarded_quantity, w.discarded_unit, w.converted_weight_kg,
            w.factor_kg_co2e_per_kg_snapshot, w.footprint_kg_co2e, w.assessment_status,
            w.exclusion_reason, w.discarded_at, w.calculation_notes, qc.is_assumed, ef.food_type,
            p.product_name, pc.category_name
     FROM waste_impact_assessments w
     LEFT JOIN products p ON p.product_id = w.product_id
     LEFT JOIN product_categories pc ON pc.category_id = w.category_id
     LEFT JOIN emission_factors ef ON ef.factor_id = w.factor_id
     LEFT JOIN quantity_conversions qc ON qc.conversion_id = w.conversion_id
     WHERE w.team_id = ? AND w.discarded_at BETWEEN ? AND ?`,
    [req.params.householdId, toDbDateTime(earliest), toDbDateTime(end)]
  );

  const current = periods[periods.length - 1];
  const items = [];
  const byCategory = new Map();

  for (const row of rows) {
    const discardedAt = fromDbDateTime(row.discarded_at);
    const period = periods.find((p) => discardedAt >= p.start && discardedAt <= p.end);
    if (!period) continue;
    period.hasActivity = true;
    const assessed = row.assessment_status === 'ASSESSED';
    const kgCo2e = assessed ? Number(row.footprint_kg_co2e) : null;
    period.wasted += 1;
    if (assessed) {
      period.kgCo2e += kgCo2e;
      period.assessed += 1;
    }
    if (period !== current) continue;

    const category = CATEGORY_DART_NAMES[row.category_name] ?? 'shelfStableFoods';
    const kgWasted = row.converted_weight_kg === null ? null : Number(row.converted_weight_kg);
    const status = assessed
      ? 'estimated'
      : (row.exclusion_reason === REASON_NO_CONVERSION ? 'unknownWeight' : 'noFactor');
    items.push({
      id: String(row.inventory_item_id),
      name: row.product_name || 'Item',
      category,
      quantity: Number(row.discarded_quantity),
      unit: row.discarded_unit || 'pcs',
      resolvedAt: row.discarded_at,
      status,
      kgWasted: kgWasted === null ? null : round(kgWasted),
      weightBasis: kgWasted === null ? null : weightBasisFor(row.discarded_unit),
      // From the conversion row actually used (quantity_conversions.is_assumed).
      weightIsAssumed: Boolean(Number(row.is_assumed)),
      emissionFactor: row.factor_kg_co2e_per_kg_snapshot === null ? null : Number(row.factor_kg_co2e_per_kg_snapshot),
      factorEntity: row.food_type || null,
      // How the factor was chosen: 'food_type' / 'factor_name' (data team's
      // text matching, highest factor among matches) or 'reference'.
      factorSource: ((String(row.calculation_notes || '').match(/matched by (food_type|factor_name|reference)/) || [])[1])
        || (row.factor_kg_co2e_per_kg_snapshot === null ? null : 'reference'),
      weightEnteredByUser: /weight entered by user/.test(String(row.calculation_notes || '')),
      kgCo2e: kgCo2e === null ? null : round(kgCo2e),
    });

    if (!assessed) continue;
    const c = byCategory.get(category) || { category, kgCo2e: 0, kgWasted: 0, itemCount: 0 };
    c.kgCo2e += kgCo2e;
    c.kgWasted += kgWasted;
    c.itemCount += 1;
    byCategory.set(category, c);
  }

  const estimated = items.filter((i) => i.status === 'estimated');
  const total = current.kgCo2e;
  const previous = periods.length > 1 ? periods[periods.length - 2] : null;
  const now = new Date();
  const unknownOnly = (p) => p.wasted > 0 && p.assessed === 0;

  res.json({
    status: 'ready',
    totalKgCo2e: round(total),
    totalKgWasted: round(estimated.reduce((sum, i) => sum + i.kgWasted, 0)),
    // null = nothing meaningful to compare against (no resolved items in
    // one of the two periods) — the same rule that fixed the Iteration 2
    // "400% more waste" bug. Compared as an absolute kg difference, not a
    // percentage, so a near-zero previous period can't blow it up.
    // Also null when either period had waste that couldn't be estimated
    // at all — its 0 would be "unknown", not "no impact".
    previousTotalKgCo2e: previous && previous.hasActivity && current.hasActivity && !unknownOnly(previous) && !unknownOnly(current)
      ? round(previous.kgCo2e) : null,
    // The selected period hasn't finished yet (e.g. "this week" on a
    // Wednesday) — the UI says "so far" so a half-finished week isn't
    // presented as an improvement over a full one.
    isPeriodInProgress: end > now,
    petrolEquivalent: {
      litres: round(petrolLitresFor(total), 2),
      kgCo2ePerLitre: PETROL_KG_CO2E_PER_LITRE,
      sourceName: PETROL_SOURCE_NAME,
    },
    wastedItemCount: items.length,
    estimatedItemCount: estimated.length,
    excludedCounts: {
      noFactor: items.filter((i) => i.status === 'noFactor').length,
      unknownWeight: items.filter((i) => i.status === 'unknownWeight').length,
    },
    // True when any counted item's kg came from an assumed conversion
    // (is_assumed = 1, e.g. a typical piece weight) — the report then says
    // the figure is "based on assumed values".
    hasApproximateWeights: estimated.some((i) => i.weightIsAssumed),
    byCategory: [...byCategory.values()]
      .map((c) => ({ ...c, kgCo2e: round(c.kgCo2e), kgWasted: round(c.kgWasted) }))
      .sort((a, b) => b.kgCo2e - a.kgCo2e),
    trend: periods.map((p) => ({
      start: p.start.toISOString(),
      end: p.end.toISOString(),
      // null = waste happened but none of it could be estimated (shown as
      // "–", never as a 0 bar).
      kgCo2e: unknownOnly(p) ? null : round(p.kgCo2e),
      hasActivity: p.hasActivity,
      isComplete: p.end <= now,
    })),
    items: items.sort((a, b) => (b.kgCo2e ?? -1) - (a.kgCo2e ?? -1)),
  });
}));

// PUT /households/:householdId/environmental-impact/items/:inventoryItemId/weight  { weightKg }
//
// For a discard whose unit couldn't be converted to kg (e.g. "1 pack"):
// the user enters the actual discarded weight, and that discard is
// counted with the factor already chosen for it. Only works on EXCLUDED
// "missing quantity conversion" rows, so a computed figure is never
// overwritten. The note records that the weight came from the user.
router.put('/households/:householdId/environmental-impact/items/:inventoryItemId/weight', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const weightKg = Number(req.body && req.body.weightKg);
  if (!Number.isFinite(weightKg) || weightKg <= 0 || weightKg > 1000) {
    throw new ApiError(400, 'Enter a weight between 0 and 1000 kg.');
  }
  const [rows] = await pool.query(
    `SELECT assessment_id, factor_kg_co2e_per_kg_snapshot, calculation_notes FROM waste_impact_assessments
     WHERE team_id = ? AND inventory_item_id = ? AND assessment_status = 'EXCLUDED' AND exclusion_reason = ?
     ORDER BY assessment_id DESC LIMIT 1`,
    [req.params.householdId, req.params.inventoryItemId, REASON_NO_CONVERSION]
  );
  if (rows.length === 0) throw new ApiError(404, 'This item doesn\'t need a weight (it\'s already counted or can\'t be estimated).');
  const row = rows[0];
  if (row.factor_kg_co2e_per_kg_snapshot === null) throw new ApiError(409, 'This item has no emission factor, so a weight won\'t help.');
  const footprint = weightKg * Number(row.factor_kg_co2e_per_kg_snapshot);
  await pool.query(
    `UPDATE waste_impact_assessments
     SET converted_weight_kg = ?, conversion_id = NULL, footprint_kg_co2e = ?, assessment_status = 'ASSESSED',
         exclusion_reason = NULL, calculation_notes = ?
     WHERE assessment_id = ? AND assessment_status = 'EXCLUDED'`,
    [Number(weightKg.toFixed(6)), Number(footprint.toFixed(6)),
      `${row.calculation_notes || ''}; weight entered by user: ${weightKg} kg`.slice(0, 1000), row.assessment_id]
  );
  res.json({ ok: true, kgCo2e: round(footprint) });
}));

module.exports = router;
module.exports._internal = { fromDbDateTime, toDbDateTime, weightBasisFor };
