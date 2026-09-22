const express = require('express');
const pool = require('../db');
const { avatarIdToKey } = require('../util/avatars');
const { CATEGORY_DB_NAMES, CATEGORY_DART_NAMES, STORAGE_DB_NAMES, STORAGE_DART_NAMES } = require('../util/enums');
const { assertMember, assertMemberForItem } = require('../util/household_access');
const { ApiError, asyncHandler } = require('../util/errors');

const router = express.Router();

const ITEM_SELECT = `
  SELECT ii.*, p.product_name, pc.category_name, st.storage_name,
         pir.median_package_price AS public_estimated_price,
         (SELECT it.user_id FROM inventory_transactions it
            WHERE it.inventory_item_id = ii.inventory_item_id
              AND it.transaction_type IN ('CONSUME', 'DISCARD', 'DONATE')
            ORDER BY it.transaction_time DESC LIMIT 1) AS resolved_by_user_id
  FROM inventory_items ii
  JOIN products p ON p.product_id = ii.product_id
  JOIN product_categories pc ON pc.category_id = p.category_id
  JOIN storage_types st ON st.storage_type_id = ii.storage_type_id
  LEFT JOIN product_reference pr ON pr.product_id = ii.product_id
  LEFT JOIN price_item_reference pir ON pir.reference_id = pr.reference_id
`;

function itemRowToJson(row) {
  const dispositionMap = { CONSUMED: 'consumed', DISCARDED: 'discarded', DONATED: 'donated' };
  return {
    id: String(row.inventory_item_id),
    householdId: String(row.team_id),
    name: row.product_name,
    quantity: Number(row.quantity),
    unit: row.unit || 'pcs',
    notes: row.notes,
    // User-entered purchase price (optional) — what they actually paid,
    // not a per-unit figure. Null until they type one in.
    price: row.price !== null && row.price !== undefined ? Number(row.price) : null,
    // Public fallback estimate from PriceCatcher data, when this product
    // has a mapped reference — used by the frontend only when the user
    // hasn't entered their own price (see price README's priority order).
    publicEstimatedPrice: row.public_estimated_price !== null && row.public_estimated_price !== undefined
      ? Number(row.public_estimated_price)
      : null,
    storageLocation: STORAGE_DART_NAMES[row.storage_name] ?? 'pantry',
    category: CATEGORY_DART_NAMES[row.category_name] ?? 'shelfStableFoods',
    useByDate: row.expiry_date,
    addedAt: row.entry_date,
    addedByUserId: String(row.created_by),
    // Who actually performed the consume/discard/donate action — distinct
    // from addedByUserId (whoever originally added it). Null until the
    // item is resolved. This is what "My Stats" consumed/wasted counts
    // should filter on — NOT addedByUserId, which only tells you who
    // bought/added it, not who ate or threw it out.
    resolvedByUserId: row.resolved_by_user_id !== null && row.resolved_by_user_id !== undefined
      ? String(row.resolved_by_user_id)
      : null,
    // status stays IN_STOCK for a partially/half-consumed item — only a
    // FULLY resolved item (fully consumed, discarded, donated) has a
    // disposition. consumedAmount can be present even while disposition
    // is still null (see the resolve endpoint below).
    disposition: dispositionMap[row.status] ?? null,
    discardReason: row.discard_reason,
    consumedAmount: row.consumed_amount,
    resolvedAt: row.checkout_date,
  };
}

async function findOrCreateProductId(conn, name, category) {
  const dbCategory = CATEGORY_DB_NAMES[category];
  if (!dbCategory) throw new ApiError(400, `Unknown category: ${category}`);
  const [catRows] = await conn.query('SELECT category_id FROM product_categories WHERE category_name = ?', [dbCategory]);
  if (catRows.length === 0) throw new ApiError(500, `Category not seeded: ${dbCategory}`);
  const categoryId = catRows[0].category_id;

  const [exact] = await conn.query(
    'SELECT product_id FROM products WHERE category_id = ? AND LOWER(product_name) = LOWER(?)',
    [categoryId, name]
  );
  if (exact.length > 0) return exact[0].product_id;

  const [partial] = await conn.query(
    'SELECT product_id FROM products WHERE category_id = ? AND LOWER(product_name) LIKE LOWER(?) LIMIT 1',
    [categoryId, `%${name}%`]
  );
  if (partial.length > 0) return partial[0].product_id;

  const [result] = await conn.query(
    'INSERT INTO products (category_id, product_name) VALUES (?, ?)',
    [categoryId, name]
  );
  return result.insertId;
}

async function findStorageTypeId(conn, storageLocation) {
  const dbStorage = STORAGE_DB_NAMES[storageLocation];
  if (!dbStorage) throw new ApiError(400, `Unknown storage location: ${storageLocation}`);
  const [rows] = await conn.query('SELECT storage_type_id FROM storage_types WHERE storage_name = ?', [dbStorage]);
  if (rows.length === 0) throw new ApiError(500, `Storage type not seeded: ${dbStorage}`);
  return rows[0].storage_type_id;
}

// GET /households/:householdId/inventory-items
router.get('/households/:householdId/inventory-items', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const [rows] = await pool.query(`${ITEM_SELECT} WHERE ii.team_id = ? ORDER BY ii.expiry_date ASC`, [req.params.householdId]);
  res.json(rows.map(itemRowToJson));
}));

// POST /households/:householdId/inventory-items
// { name, quantity, unit, notes, price, storageLocation, category, useByDate }
// addedByUserId is always req.userId, never trusted from the body.
router.post('/households/:householdId/inventory-items', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const { name, quantity, storageLocation, category, useByDate } = req.body;
  const unit = req.body.unit || 'pcs';
  const notes = req.body.notes || null;
  // Optional — what the user actually paid, not a per-unit figure.
  const price = req.body.price !== undefined && req.body.price !== null ? Number(req.body.price) : null;
  if (price !== null && (!Number.isFinite(price) || price < 0)) {
    throw new ApiError(400, 'price must be a non-negative number.');
  }
  if (!name || !quantity || !storageLocation || !category || !useByDate) {
    throw new ApiError(400, 'name, quantity, storageLocation, category, useByDate are required.');
  }
  const addedByUserId = req.userId;

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const productId = await findOrCreateProductId(conn, name, category);
    const storageTypeId = await findStorageTypeId(conn, storageLocation);

    const [result] = await conn.query(
      `INSERT INTO inventory_items
        (team_id, product_id, storage_type_id, created_by, quantity, unit, notes, price, purchase_date, expiry_date, expiry_date_source, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), ?, 'USER_INPUT', 'IN_STOCK')`,
      [req.params.householdId, productId, storageTypeId, addedByUserId, quantity, unit, notes, price, useByDate]
    );
    await conn.query(
      `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
       VALUES (?, ?, 'ADD', ?, 'Initial stock entry')`,
      [result.insertId, addedByUserId, quantity]
    );
    await conn.commit();

    const [rows] = await conn.query(`${ITEM_SELECT} WHERE ii.inventory_item_id = ?`, [result.insertId]);
    res.status(201).json(itemRowToJson(rows[0]));
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

// PUT /inventory-items/:id  — edit (name/quantity/storage/category/date/unit/notes/price)
router.put('/inventory-items/:id', asyncHandler(async (req, res) => {
  await assertMemberForItem(req.userId, req.params.id);
  const { name, quantity, unit, notes, price, storageLocation, category, useByDate } = req.body;
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [existingRows] = await conn.query(`${ITEM_SELECT} WHERE ii.inventory_item_id = ? FOR UPDATE`, [req.params.id]);
    if (existingRows.length === 0) throw new ApiError(404, 'Item not found.');

    const updates = [];
    const params = [];
    if (name !== undefined && category !== undefined) {
      const productId = await findOrCreateProductId(conn, name, category);
      updates.push('product_id = ?');
      params.push(productId);
    }
    if (storageLocation !== undefined) {
      updates.push('storage_type_id = ?');
      params.push(await findStorageTypeId(conn, storageLocation));
    }
    if (quantity !== undefined) {
      updates.push('quantity = ?');
      params.push(quantity);
    }
    if (unit !== undefined) {
      updates.push('unit = ?');
      params.push(unit);
    }
    if (notes !== undefined) {
      updates.push('notes = ?');
      params.push(notes || null);
    }
    if (price !== undefined) {
      const numericPrice = price === null ? null : Number(price);
      if (numericPrice !== null && (!Number.isFinite(numericPrice) || numericPrice < 0)) {
        throw new ApiError(400, 'price must be a non-negative number.');
      }
      updates.push('price = ?');
      params.push(numericPrice);
    }
    if (useByDate !== undefined) {
      updates.push('expiry_date = ?');
      params.push(useByDate);
    }

    if (updates.length > 0) {
      params.push(req.params.id);
      await conn.query(`UPDATE inventory_items SET ${updates.join(', ')} WHERE inventory_item_id = ?`, params);
    }
    await conn.commit();

    const [rows] = await conn.query(`${ITEM_SELECT} WHERE ii.inventory_item_id = ?`, [req.params.id]);
    res.json(itemRowToJson(rows[0]));
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

// Valid values the client can send for the subjective fields — validated
// server-side so bad/unexpected values can't get stored.
const VALID_DISCARD_REASONS = ['spoiled', 'expired_not_spoiled', 'quality_declined', 'overbought', 'forgot_about_it', 'other'];
const VALID_CONSUMED_AMOUNTS = ['partial', 'half', 'full'];

// POST /inventory-items/:id/resolve
// { disposition: 'consumed'|'discarded'|'donated', discardReason?, consumedAmount? }
// resolvedByUserId is always req.userId, never trusted from the body.
//
// IMPORTANT: a "consumed" disposition with consumedAmount 'partial' or
// 'half' does NOT actually resolve the item — it stays IN_STOCK and
// active in the inventory, just tagged with how much has been used so
// far (e.g. an opened carton of milk). Only 'full' (or discarded/
// donated) actually removes it from the active inventory. This can be
// called repeatedly on the same still-active item (partial -> half ->
// full) since the item never leaves IN_STOCK until the final call.
router.post('/inventory-items/:id/resolve', asyncHandler(async (req, res) => {
  await assertMemberForItem(req.userId, req.params.id);
  const { disposition, discardReason, consumedAmount } = req.body;
  if (!['consumed', 'discarded', 'donated'].includes(disposition)) {
    throw new ApiError(400, "disposition must be 'consumed', 'discarded', or 'donated'.");
  }
  if (discardReason !== undefined && discardReason !== null && !VALID_DISCARD_REASONS.includes(discardReason)) {
    throw new ApiError(400, `discardReason must be one of: ${VALID_DISCARD_REASONS.join(', ')}`);
  }
  if (consumedAmount !== undefined && consumedAmount !== null && !VALID_CONSUMED_AMOUNTS.includes(consumedAmount)) {
    throw new ApiError(400, `consumedAmount must be one of: ${VALID_CONSUMED_AMOUNTS.join(', ')}`);
  }
  const resolvedByUserId = req.userId;
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rows] = await conn.query('SELECT * FROM inventory_items WHERE inventory_item_id = ? FOR UPDATE', [req.params.id]);
    if (rows.length === 0) throw new ApiError(404, 'Item not found.');
    const item = rows[0];
    if (item.status !== 'IN_STOCK') throw new ApiError(409, 'This item has already been resolved.');

    const isPartialConsumption = disposition === 'consumed' && (consumedAmount === 'partial' || consumedAmount === 'half');

    if (isPartialConsumption) {
      // Item stays IN_STOCK — just record the marker, don't resolve it.
      await conn.query('UPDATE inventory_items SET consumed_amount = ? WHERE inventory_item_id = ?', [consumedAmount, req.params.id]);
      await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
         VALUES (?, ?, 'CONSUME', ?, ?)`,
        [req.params.id, resolvedByUserId, item.quantity, `Marked partially consumed (${consumedAmount})`]
      );
      await conn.commit();
      const [updatedRows] = await conn.query(`${ITEM_SELECT} WHERE ii.inventory_item_id = ?`, [req.params.id]);
      return res.json(itemRowToJson(updatedRows[0]));
    }

    const statusMap = { consumed: 'CONSUMED', discarded: 'DISCARDED', donated: 'DONATED' };
    const newStatus = statusMap[disposition];
    await conn.query(
      'UPDATE inventory_items SET status = ?, checkout_date = NOW(), discard_reason = ?, consumed_amount = ? WHERE inventory_item_id = ?',
      [newStatus, disposition === 'discarded' ? (discardReason || null) : null, disposition === 'consumed' ? (consumedAmount || 'full') : null, req.params.id]
    );

    if (disposition === 'consumed') {
      await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
         VALUES (?, ?, 'CONSUME', ?, 'Marked fully consumed')`,
        [req.params.id, resolvedByUserId, item.quantity]
      );
    } else if (disposition === 'discarded') {
      // Transaction-level discard_reason is a separate, auto-computed
      // timing classification (was it already past its expiry date?) —
      // distinct from the user's own stated reason stored on the item.
      const timingReason = item.expiry_date && new Date(item.expiry_date) < new Date() ? 'EXPIRED' : 'USER_DISCARDED';
      await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
         VALUES (?, ?, 'DISCARD', ?, ?, ?)`,
        [req.params.id, resolvedByUserId, item.quantity, discardReason ? `Marked discarded (${discardReason})` : 'Marked discarded', timingReason]
      );
    } else {
      await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
         VALUES (?, ?, 'DONATE', ?, 'Marked donated')`,
        [req.params.id, resolvedByUserId, item.quantity]
      );
    }
    await conn.commit();

    const [updatedRows] = await conn.query(`${ITEM_SELECT} WHERE ii.inventory_item_id = ?`, [req.params.id]);
    res.json(itemRowToJson(updatedRows[0]));
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

// DELETE /inventory-items/:id
router.delete('/inventory-items/:id', asyncHandler(async (req, res) => {
  await assertMemberForItem(req.userId, req.params.id);
  await pool.query('DELETE FROM inventory_items WHERE inventory_item_id = ?', [req.params.id]);
  res.status(204).send();
}));

module.exports = router;
