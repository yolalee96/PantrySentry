const express = require('express');
const pool = require('../db');
const { CATEGORY_DART_NAMES } = require('../util/enums');
const { assertMember } = require('../util/household_access');
const { ApiError, asyncHandler } = require('../util/errors');
const { foldPlural } = require('../util/product_reference');

const router = express.Router();

// Epic 7 — food donation, on the data team's tables:
//   donation_centres / donation_centre_accepted_foods   (static, 27 centres)
//   donation_records / donation_record_items            (runtime)
//
// Data team rules (epic7_donation_data/README.md, Database README):
//   - A PENDING donation changes nothing in the inventory and writes no
//     transaction. Stock only moves when the donation is COMPLETED: one
//     DONATE transaction per delivered item, quantity reduced, item marked
//     DONATED when nothing is left. CANCELLED changes nothing.
//   - Donated food is never consumed or wasted food, and never gets a
//     waste_impact_assessments row.
//   - Accepted-food lists are evidence-based and may be missing or
//     incomplete — "not on the list" is NOT "not accepted", so it's shown
//     as a warning, never a block. Free-text donation_requirements are
//     shown as written and confirmed by the user (declaration_agreed),
//     never interpreted by code.
// Our own checks (block regardless of centre): expired food can't be
// donated, and an item can't be promised beyond what's in stock across
// all of the household's pending donations.

const FULLY_USED_THRESHOLD = 0.01; // same "effectively finished" rule as the rest of the app
const EARTH_RADIUS_KM = 6371;
const CONDITIONS = ['Sealed / unopened', 'Opened, in good condition', 'Fresh, in good condition'];
const ORG_TYPES = {
  CARE_HOME: 'careHome', NGO: 'ngo', FOOD_BANK: 'foodBank', COMMUNITY_CENTRE: 'communityCentre',
  RELIGIOUS_ORG: 'religiousOrg', PANTRY_DROP_OFF: 'pantryDropOff', COMMUNITY_FRIDGE: 'communityFridge', OTHER: 'other',
};
// Common short names for Malaysian areas, so "penang" finds centres
// stored under "Pulau Pinang", "kl" finds "Kuala Lumpur", and so on.
const AREA_ALIASES = {
  penang: ['pulau pinang'], 'pulau pinang': ['penang'], kl: ['kuala lumpur'], pj: ['petaling jaya'],
  jb: ['johor bahru'], n9: ['negeri sembilan'], 'negri sembilan': ['negeri sembilan'], malacca: ['melaka'],
  kk: ['kota kinabalu'], 'kota kinabalu': ['kk'],
};
const STATUS_OUT = { PENDING: 'pending', COMPLETED: 'completed', CANCELLED: 'cancelled' };

function haversineKm(lat1, lng1, lat2, lng2) {
  const rad = (d) => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

function round(n, dp = 2) {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
}

function todayFrom(query) {
  const t = query.today;
  if (t === undefined) return new Date().toISOString().slice(0, 10);
  if (typeof t !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(t)) throw new ApiError(400, 'today must be YYYY-MM-DD.');
  return t;
}

function parseIdList(value) {
  if (value === undefined || value === '') return [];
  const ids = String(value).split(',').map((s) => s.trim()).filter(Boolean);
  if (ids.length > 50 || ids.some((id) => !/^\d+$/.test(id))) throw new ApiError(400, 'Invalid item list.');
  return [...new Set(ids)];
}

/** Inventory items of the household, with category and how much of each
 * is already promised to the household's PENDING donations (optionally
 * ignoring one donation, when that donation is being edited). */
async function loadItems(db, householdId, ids, { excludeDonationId = null, lock = false } = {}) {
  if (ids.length === 0) return new Map();
  const [rows] = await db.query(
    `SELECT ii.inventory_item_id, ii.team_id, ii.quantity, ii.unit, ii.status, ii.expiry_date,
            p.product_name, p.category_id, pc.category_name
     FROM inventory_items ii
     JOIN products p ON p.product_id = ii.product_id
     JOIN product_categories pc ON pc.category_id = p.category_id
     WHERE ii.inventory_item_id IN (?)${lock ? ' FOR UPDATE' : ''}`,
    [ids]
  );
  const [reserved] = await db.query(
    `SELECT dri.inventory_item_id, SUM(dri.quantity) AS reserved
     FROM donation_record_items dri
     JOIN donation_records dr ON dr.donation_id = dri.donation_id
     WHERE dr.team_id = ? AND dr.status = 'PENDING' AND dri.inventory_item_id IN (?)
       ${excludeDonationId ? 'AND dr.donation_id <> ?' : ''}
     GROUP BY dri.inventory_item_id`,
    excludeDonationId ? [householdId, ids, excludeDonationId] : [householdId, ids]
  );
  const reservedById = new Map(reserved.map((r) => [String(r.inventory_item_id), Number(r.reserved)]));
  const map = new Map();
  for (const r of rows) {
    if (String(r.team_id) !== String(householdId)) continue;
    const quantity = Number(r.quantity);
    const reservedQty = reservedById.get(String(r.inventory_item_id)) || 0;
    map.set(String(r.inventory_item_id), {
      id: String(r.inventory_item_id),
      name: r.product_name,
      categoryId: Number(r.category_id),
      category: CATEGORY_DART_NAMES[r.category_name] ?? 'shelfStableFoods',
      quantity,
      unit: r.unit || 'pcs',
      status: r.status,
      expiryDate: r.expiry_date ? String(r.expiry_date).slice(0, 10) : null,
      reservedQuantity: round(reservedQty, 3),
      availableToDonate: round(Math.max(0, quantity - reservedQty), 3),
    });
  }
  return map;
}

/**
 * How well one centre's accepted-food list covers one inventory item:
 *   'listed'    — a listed food matches the item by name ("Rice" for Rice)
 *   'similar'   — only other foods of the same category are listed
 *                 ("Biscuits" for Potato chips) — worth checking first
 *   'notListed' — the centre has a list, but nothing in this category
 *   'noList'    — the centre has no verified accepted-food list
 */
function checkItem(item, accepted) {
  if (accepted.length === 0) return { inventoryItemId: item.id, result: 'noList', matchedFood: null };
  const inCategory = accepted.filter((a) => a.categoryId === item.categoryId);
  if (inCategory.length === 0) return { inventoryItemId: item.id, result: 'notListed', matchedFood: null };
  const name = foldPlural(item.name);
  const byName = inCategory.find((a) => {
    const food = foldPlural(a.itemName);
    return food === name || name.includes(food) || food.includes(name);
  });
  return byName
    ? { inventoryItemId: item.id, result: 'listed', matchedFood: byName.itemName }
    : { inventoryItemId: item.id, result: 'similar', matchedFood: inCategory.map((a) => a.itemName).slice(0, 3).join(', ') };
}

function centreToJson(c, accepted, origin, items) {
  const distanceKm = origin && c.latitude !== null && c.longitude !== null
    ? round(haversineKm(origin.lat, origin.lng, Number(c.latitude), Number(c.longitude)), 1)
    : null;
  const checks = items.map((i) => checkItem(i, accepted));
  return {
    id: String(c.centre_id),
    name: c.name,
    type: ORG_TYPES[c.organisation_type] || 'other',
    description: c.description || null,
    requirements: c.donation_requirements ? String(c.donation_requirements).trim() : null,
    addressLine1: c.address_line1,
    city: c.city || null,
    state: c.state || null,
    postcode: c.postcode || null,
    latitude: c.latitude === null ? null : Number(c.latitude),
    longitude: c.longitude === null ? null : Number(c.longitude),
    phone: c.phone || null,
    email: c.email || null,
    websiteUrl: c.website_url || null,
    operatingHours: c.operating_hours || null,
    sourceUrl: c.verification_source_url || null,
    distanceKm,
    acceptedFoods: accepted.map((a) => ({ category: a.category, itemName: a.itemName, notes: a.notes })),
    itemChecks: checks,
    listedItemCount: checks.filter((ch) => ch.result === 'listed').length,
    similarItemCount: checks.filter((ch) => ch.result === 'similar').length,
  };
}

async function loadCentres(db, centreIds = null) {
  const [centres] = await db.query(
    `SELECT * FROM donation_centres WHERE is_active = 1${centreIds ? ' AND centre_id IN (?)' : ''}`,
    centreIds ? [centreIds] : []
  );
  if (centres.length === 0) return { centres, acceptedByCentre: new Map() };
  const [accepted] = await db.query(
    `SELECT af.centre_id, af.category_id, af.item_name, af.notes, pc.category_name
     FROM donation_centre_accepted_foods af
     JOIN product_categories pc ON pc.category_id = af.category_id
     WHERE af.is_active = 1 AND af.centre_id IN (?)
     ORDER BY af.need_id`,
    [centres.map((c) => c.centre_id)]
  );
  const acceptedByCentre = new Map();
  for (const a of accepted) {
    const key = String(a.centre_id);
    if (!acceptedByCentre.has(key)) acceptedByCentre.set(key, []);
    acceptedByCentre.get(key).push({
      categoryId: Number(a.category_id),
      category: CATEGORY_DART_NAMES[a.category_name] ?? 'shelfStableFoods',
      itemName: a.item_name,
      notes: a.notes || null,
    });
  }
  return { centres, acceptedByCentre };
}

// GET /households/:householdId/donation-centres?lat=&lng=&q=&itemIds=1,2,3
//
// User Story 7.1. With lat/lng: distances, nearest first (AC 7.1.6/7.1.7).
// With q: centres whose name, address, city, state or postcode match the
// area typed (AC 7.1.5). With itemIds: each centre is checked against
// those items and centres listing more of them come first (then nearest).
router.get('/households/:householdId/donation-centres', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  let origin = null;
  if (req.query.lat !== undefined || req.query.lng !== undefined) {
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw new ApiError(400, 'Invalid location.');
    }
    origin = { lat, lng };
  }
  const q = typeof req.query.q === 'string' ? req.query.q.trim().toLowerCase().slice(0, 100) : '';
  const itemIds = parseIdList(req.query.itemIds);
  const itemsMap = await loadItems(pool, req.params.householdId, itemIds);
  const items = itemIds.map((id) => itemsMap.get(id)).filter(Boolean);

  const { centres, acceptedByCentre } = await loadCentres(pool);
  let list = centres;
  if (q) {
    const terms = [q, ...(AREA_ALIASES[q] || [])];
    list = centres.filter((c) => [c.name, c.address_line1, c.city, c.state, c.postcode]
      .some((f) => f && terms.some((t) => String(f).toLowerCase().includes(t))));
  }
  const out = list.map((c) => centreToJson(c, acceptedByCentre.get(String(c.centre_id)) || [], origin, items));
  out.sort((a, b) =>
    // Most of the chosen items covered (by name or category) first, then
    // nearest — a nearby centre that takes the same kinds of food beats
    // a distant one whose list happens to name the item exactly.
    (items.length > 0 ? (b.listedItemCount + b.similarItemCount) - (a.listedItemCount + a.similarItemCount) : 0) ||
    ((a.distanceKm ?? Infinity) - (b.distanceKm ?? Infinity)) ||
    a.name.localeCompare(b.name));
  res.json({ centres: out });
}));

// GET /households/:householdId/donation-items?today=YYYY-MM-DD&excludeDonationId=
// Items that can be donated: in stock, not expired, something left after
// other pending donations. Used by the "Donate food" item picker.
// excludeDonationId: when editing that donation, its own amounts don't
// count as "already promised".
router.get('/households/:householdId/donation-items', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const today = todayFrom(req.query);
  const [rows] = await pool.query(
    "SELECT inventory_item_id FROM inventory_items WHERE team_id = ? AND status = 'IN_STOCK'",
    [req.params.householdId]
  );
  const exclude = req.query.excludeDonationId;
  if (exclude !== undefined && !/^\d+$/.test(String(exclude))) throw new ApiError(400, 'Invalid donation.');
  const items = await loadItems(pool, req.params.householdId, rows.map((r) => String(r.inventory_item_id)),
    { excludeDonationId: exclude || null });
  res.json({
    items: [...items.values()]
      .map((i) => ({ ...i, isExpired: Boolean(i.expiryDate && i.expiryDate < today) }))
      .sort((a, b) => (a.expiryDate || '9999').localeCompare(b.expiryDate || '9999') || a.name.localeCompare(b.name)),
  });
}));

/** Validates the items of a new or edited donation and returns rows to insert. */
async function validateDonationItems(conn, householdId, rawItems, today, excludeDonationId) {
  if (!Array.isArray(rawItems) || rawItems.length === 0) throw new ApiError(400, 'Choose at least one item to donate.');
  if (rawItems.length > 50) throw new ApiError(400, 'Too many items in one donation.');
  const wanted = rawItems.map((it) => ({
    inventoryItemId: String(it && it.inventoryItemId),
    quantity: Number(it && it.quantity),
    condition: it && typeof it.condition === 'string' ? it.condition.trim() : '',
  }));
  if (wanted.some((w) => !/^\d+$/.test(w.inventoryItemId))) throw new ApiError(400, 'Invalid inventory item.');
  if (new Set(wanted.map((w) => w.inventoryItemId)).size !== wanted.length) {
    throw new ApiError(400, 'Each item can only appear once in a donation.');
  }
  const items = await loadItems(conn, householdId, wanted.map((w) => w.inventoryItemId), { excludeDonationId, lock: true });
  return wanted.map((w) => {
    const item = items.get(w.inventoryItemId);
    if (!item || item.status !== 'IN_STOCK') throw new ApiError(409, 'One of the items is no longer in your inventory. Refresh and try again.');
    // Our own rule — never donate expired food.
    if (item.expiryDate && item.expiryDate < today) throw new ApiError(400, `${item.name} has expired and can't be donated.`);
    // AC 7.2.4
    if (!Number.isFinite(w.quantity) || w.quantity <= 0) throw new ApiError(400, `Enter a quantity above 0 for ${item.name}.`);
    if (w.quantity > item.availableToDonate + 1e-9) {
      const reservedNote = item.reservedQuantity > 0 ? ` (${item.reservedQuantity} ${item.unit} is already in other pending donations)` : '';
      throw new ApiError(400, `You can donate at most ${item.availableToDonate} ${item.unit} of ${item.name}${reservedNote}.`);
    }
    // AC 7.2.5
    if (!CONDITIONS.includes(w.condition)) throw new ApiError(400, `Choose the condition of ${item.name}.`);
    return { ...w, quantity: round(w.quantity, 2), unit: item.unit, expiryDate: item.expiryDate };
  });
}

async function insertItems(conn, donationId, rows) {
  for (const r of rows) {
    await conn.query(
      `INSERT INTO donation_record_items (donation_id, inventory_item_id, quantity, unit, \`condition\`, expiry_date_at_donation)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [donationId, r.inventoryItemId, r.quantity, r.unit, r.condition, r.expiryDate]
    );
  }
}

async function withTransaction(fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    conn.release();
  }
}

async function loadDonations(where, params) {
  const [records] = await pool.query(
    `SELECT dr.*, dc.name AS centre_name, dc.address_line1, dc.city, dc.phone, dc.operating_hours
     FROM donation_records dr
     JOIN donation_centres dc ON dc.centre_id = dr.centre_id
     WHERE ${where}
     ORDER BY dr.created_at DESC, dr.donation_id DESC`,
    params
  );
  if (records.length === 0) return [];
  const [items] = await pool.query(
    `SELECT dri.*, p.product_name, ii.quantity AS current_quantity, ii.status AS item_status
     FROM donation_record_items dri
     JOIN inventory_items ii ON ii.inventory_item_id = dri.inventory_item_id
     JOIN products p ON p.product_id = ii.product_id
     WHERE dri.donation_id IN (?)
     ORDER BY dri.donation_item_id`,
    [records.map((r) => r.donation_id)]
  );
  const itemsByDonation = new Map();
  for (const it of items) {
    const key = String(it.donation_id);
    if (!itemsByDonation.has(key)) itemsByDonation.set(key, []);
    itemsByDonation.get(key).push({
      id: String(it.donation_item_id),
      inventoryItemId: String(it.inventory_item_id),
      name: it.product_name,
      quantity: Number(it.quantity),
      unit: it.unit,
      condition: it.condition,
      expiryDate: it.expiry_date_at_donation ? String(it.expiry_date_at_donation).slice(0, 10) : null,
      delivered: it.transaction_id !== null,
      itemStillInStock: it.item_status === 'IN_STOCK',
      currentQuantity: Number(it.current_quantity),
    });
  }
  return records.map((r) => ({
    id: String(r.donation_id),
    status: STATUS_OUT[r.status],
    centre: { id: String(r.centre_id), name: r.centre_name, addressLine1: r.address_line1, city: r.city, phone: r.phone, operatingHours: r.operating_hours },
    createdByUserId: String(r.user_id),
    declarationAgreed: Boolean(Number(r.declaration_agreed)),
    notes: r.notes,
    createdAt: r.created_at,
    completedAt: r.donated_at,
    items: itemsByDonation.get(String(r.donation_id)) || [],
  }));
}

/** Loads a donation of this household and locks it; 404/403 otherwise. */
async function lockDonation(conn, donationId, userId) {
  if (!/^\d+$/.test(String(donationId))) throw new ApiError(404, 'Donation not found.');
  const [rows] = await conn.query('SELECT * FROM donation_records WHERE donation_id = ? FOR UPDATE', [donationId]);
  if (rows.length === 0) throw new ApiError(404, 'Donation not found.');
  await assertMember(userId, rows[0].team_id);
  return rows[0];
}

// POST /households/:householdId/donations
// { centreId, items: [{ inventoryItemId, quantity, condition }], declarationAgreed, notes?, today? }
// Creates a PENDING donation. Inventory is NOT changed (data team rule).
router.post('/households/:householdId/donations', asyncHandler(async (req, res) => {
  const householdId = String(req.params.householdId);
  await assertMember(req.userId, householdId);
  const { centreId, items, declarationAgreed, notes } = req.body || {};
  const today = todayFrom(req.body || {});
  if (!/^\d+$/.test(String(centreId))) throw new ApiError(400, 'Choose a donation centre.');
  if (declarationAgreed !== true) {
    throw new ApiError(400, 'Please confirm the food meets the centre\'s requirements and is safe to eat.');
  }
  const cleanNotes = typeof notes === 'string' && notes.trim() ? notes.trim().slice(0, 500) : null;

  const donationId = await withTransaction(async (conn) => {
    const [centre] = await conn.query('SELECT centre_id FROM donation_centres WHERE centre_id = ? AND is_active = 1', [centreId]);
    if (centre.length === 0) throw new ApiError(404, 'That donation centre is no longer available.');
    const rows = await validateDonationItems(conn, householdId, items, today, null);
    const [result] = await conn.query(
      `INSERT INTO donation_records (team_id, centre_id, user_id, status, declaration_agreed, notes)
       VALUES (?, ?, ?, 'PENDING', 1, ?)`,
      [householdId, centreId, req.userId, cleanNotes]
    );
    await insertItems(conn, result.insertId, rows);
    return result.insertId;
  });
  const [donation] = await loadDonations('dr.donation_id = ?', [donationId]);
  res.status(201).json(donation);
}));

// GET /households/:householdId/donations?status=pending|completed
// AC 7.3.1 — the donations created by this user.
router.get('/households/:householdId/donations', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const status = req.query.status;
  const statusDb = { pending: 'PENDING', completed: 'COMPLETED' }[status];
  if (status !== undefined && status !== 'all' && !statusDb) throw new ApiError(400, 'Invalid status filter.');
  // Cancelled donations leave the list (AC 7.3.7).
  const donations = await loadDonations(
    `dr.team_id = ? AND dr.user_id = ? AND ${statusDb ? 'dr.status = ?' : "dr.status <> 'CANCELLED'"}`,
    statusDb ? [req.params.householdId, req.userId, statusDb] : [req.params.householdId, req.userId]
  );
  res.json({ donations });
}));

// PUT /donations/:id — AC 7.3.6, edit a PENDING donation (items, quantities, conditions, notes).
router.put('/donations/:id', asyncHandler(async (req, res) => {
  const { items, notes } = req.body || {};
  const today = todayFrom(req.body || {});
  await withTransaction(async (conn) => {
    const record = await lockDonation(conn, req.params.id, req.userId);
    if (String(record.user_id) !== String(req.userId)) throw new ApiError(403, 'Only the person who created this donation can edit it.');
    if (record.status !== 'PENDING') throw new ApiError(409, 'Only pending donations can be edited.');
    const rows = await validateDonationItems(conn, String(record.team_id), items, today, record.donation_id);
    await conn.query('DELETE FROM donation_record_items WHERE donation_id = ?', [record.donation_id]);
    await insertItems(conn, record.donation_id, rows);
    if (notes !== undefined) {
      await conn.query('UPDATE donation_records SET notes = ? WHERE donation_id = ?',
        [typeof notes === 'string' && notes.trim() ? notes.trim().slice(0, 500) : null, record.donation_id]);
    }
  });
  const [donation] = await loadDonations('dr.donation_id = ?', [req.params.id]);
  res.json(donation);
}));

// POST /donations/:id/cancel — AC 7.3.7. Inventory is not touched.
router.post('/donations/:id/cancel', asyncHandler(async (req, res) => {
  await withTransaction(async (conn) => {
    const record = await lockDonation(conn, req.params.id, req.userId);
    if (String(record.user_id) !== String(req.userId)) throw new ApiError(403, 'Only the person who created this donation can cancel it.');
    if (record.status !== 'PENDING') throw new ApiError(409, 'Only pending donations can be cancelled.');
    await conn.query("UPDATE donation_records SET status = 'CANCELLED' WHERE donation_id = ?", [record.donation_id]);
  });
  res.json({ ok: true });
}));

// POST /donations/:id/complete
// { items: [{ donationItemId, deliveredQuantity }] }
// AC 7.3.8 / 7.3.9. deliveredQuantity 0 = that item wasn't handed over.
// The donation row is locked and must still be PENDING, so a repeated
// request can never deduct twice.
router.post('/donations/:id/complete', asyncHandler(async (req, res) => {
  const delivered = Array.isArray(req.body && req.body.items) ? req.body.items : null;
  if (!delivered || delivered.length === 0) throw new ApiError(400, 'Confirm the delivered quantity of each item.');

  await withTransaction(async (conn) => {
    const record = await lockDonation(conn, req.params.id, req.userId);
    if (String(record.user_id) !== String(req.userId)) throw new ApiError(403, 'Only the person who created this donation can complete it.');
    if (record.status !== 'PENDING') throw new ApiError(409, 'This donation has already been completed or cancelled.');

    const [lines] = await conn.query('SELECT * FROM donation_record_items WHERE donation_id = ?', [record.donation_id]);
    const deliveredById = new Map();
    for (const d of delivered) {
      const qty = Number(d && d.deliveredQuantity);
      if (!Number.isFinite(qty) || qty < 0) throw new ApiError(400, 'Delivered quantities must be 0 or more.');
      deliveredById.set(String(d && d.donationItemId), qty);
    }
    if (lines.some((l) => !deliveredById.has(String(l.donation_item_id)))) {
      throw new ApiError(400, 'Confirm the delivered quantity for every item (0 if it wasn\'t handed over).');
    }
    if (lines.every((l) => deliveredById.get(String(l.donation_item_id)) === 0)) {
      throw new ApiError(400, 'At least one item must have been delivered. Cancel the donation instead if nothing was handed over.');
    }

    const [stock] = await conn.query(
      `SELECT ii.inventory_item_id, ii.quantity, ii.unit, ii.status, p.product_name
       FROM inventory_items ii JOIN products p ON p.product_id = ii.product_id
       WHERE ii.inventory_item_id IN (?) FOR UPDATE`,
      [lines.map((l) => l.inventory_item_id)]
    );
    const stockById = new Map(stock.map((s) => [String(s.inventory_item_id), s]));

    for (const line of lines) {
      const qty = round(deliveredById.get(String(line.donation_item_id)), 2);
      if (qty === 0) {
        // Not handed over: drop it from the completed donation, stock untouched.
        await conn.query('DELETE FROM donation_record_items WHERE donation_item_id = ?', [line.donation_item_id]);
        continue;
      }
      const item = stockById.get(String(line.inventory_item_id));
      if (!item || item.status !== 'IN_STOCK') {
        throw new ApiError(409, `${item ? item.product_name : 'An item'} is no longer in stock (it may have been used or removed). Edit the donation first.`);
      }
      const available = Number(item.quantity);
      if (qty > available + 1e-9) {
        throw new ApiError(400, `Only ${available} ${item.unit || 'pcs'} of ${item.product_name} is in stock.`);
      }
      const remaining = round(Math.max(0, available - qty), 3);
      const fullyGone = remaining <= FULLY_USED_THRESHOLD;
      const donatedQty = fullyGone ? available : qty;

      // AC 7.3.9 — one DONATE transaction per item; stock reduced once.
      const [tx] = await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
         VALUES (?, ?, 'DONATE', ?, ?)`,
        [line.inventory_item_id, req.userId, donatedQty, `Donated (donation #${record.donation_id})${fullyGone ? '' : ` — ${remaining} ${item.unit || 'pcs'} left`}`]
      );
      if (fullyGone) {
        // Same status flow as "Mark as donated" (Iteration 2): DONATED, not consumed or wasted.
        await conn.query(
          "UPDATE inventory_items SET status = 'DONATED', checkout_date = NOW() WHERE inventory_item_id = ?",
          [line.inventory_item_id]
        );
        await conn.query(
          `UPDATE reminders SET status = 'CANCELLED', cancelled_at = NOW()
           WHERE inventory_item_id = ? AND status IN ('PENDING', 'TRIGGERED')`,
          [line.inventory_item_id]
        );
      } else {
        await conn.query('UPDATE inventory_items SET quantity = ? WHERE inventory_item_id = ?', [remaining, line.inventory_item_id]);
      }
      await conn.query(
        'UPDATE donation_record_items SET quantity = ?, transaction_id = ? WHERE donation_item_id = ?',
        [donatedQty, tx.insertId, line.donation_item_id]
      );
    }
    await conn.query("UPDATE donation_records SET status = 'COMPLETED', donated_at = NOW() WHERE donation_id = ?", [record.donation_id]);
  });
  const [donation] = await loadDonations('dr.donation_id = ?', [req.params.id]);
  res.json(donation);
}));

// Clear message instead of a generic 500 if the Epic 7 tables are missing.
router.use((err, req, res, next) => {
  if (err && (err.code === 'ER_NO_SUCH_TABLE' || err.errno === 1146)) {
    console.error('Epic 7 table missing:', err.sqlMessage || err.message);
    return next(new ApiError(503, 'Donations are not set up yet (database tables missing).'));
  }
  return next(err);
});

module.exports = router;
module.exports._internal = { checkItem, haversineKm, CONDITIONS };
