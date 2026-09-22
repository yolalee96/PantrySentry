const pool = require('../db');
const { ApiError } = require('./errors');

/** Throws 403 unless userId is an ACTIVE member of householdId. Returns
 * their role ('ADMIN'|'MEMBER') so callers needing an admin check don't
 * have to query twice. */
async function assertMember(userId, householdId) {
  const [rows] = await pool.query(
    "SELECT role FROM team_members WHERE team_id = ? AND user_id = ? AND status = 'ACTIVE'",
    [householdId, userId]
  );
  if (rows.length === 0) throw new ApiError(403, "You're not a member of this household.");
  return rows[0].role;
}

async function assertAdmin(userId, householdId) {
  const role = await assertMember(userId, householdId);
  if (role !== 'ADMIN') throw new ApiError(403, 'Only a household admin can do this.');
}

/** For routes keyed by inventory_item_id rather than team_id directly —
 * looks up which household the item belongs to, then checks membership.
 * Returns the item's team_id (as callers usually need it anyway). */
async function assertMemberForItem(userId, inventoryItemId) {
  const [rows] = await pool.query('SELECT team_id FROM inventory_items WHERE inventory_item_id = ?', [inventoryItemId]);
  if (rows.length === 0) throw new ApiError(404, 'Item not found.');
  await assertMember(userId, rows[0].team_id);
  return rows[0].team_id;
}

module.exports = { assertMember, assertAdmin, assertMemberForItem };
