const express = require('express');
const pool = require('../db');
const { asyncHandler } = require('../util/errors');
const { assertMember } = require('../util/household_access');

const router = express.Router();

// schema.sql has no dedicated "activity log" table — this feed is derived
// from inventory_transactions (ADD/CONSUME/DISCARD) plus team_members
// (join events), matching what AC 3.7.1 needs without adding a new table.
// NOTE: item "edited"/"removed" actions have no transaction_type in the
// schema, so they don't appear here — only add/consume/discard/join do.

// GET /households/:householdId/activity
router.get('/households/:householdId/activity', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const [txnRows] = await pool.query(
    `SELECT it.transaction_id, it.transaction_type, it.transaction_time,
            u.user_id, u.display_name, p.product_name
     FROM inventory_transactions it
     JOIN inventory_items ii ON ii.inventory_item_id = it.inventory_item_id
     JOIN products p ON p.product_id = ii.product_id
     JOIN users u ON u.user_id = it.user_id
     WHERE ii.team_id = ?`,
    [req.params.householdId]
  );

  const [joinRows] = await pool.query(
    `SELECT tm.team_id, tm.user_id, tm.joined_at, u.display_name
     FROM team_members tm JOIN users u ON u.user_id = tm.user_id
     WHERE tm.team_id = ?`,
    [req.params.householdId]
  );

  const actionMap = { ADD: 'added', CONSUME: 'consumed', DISCARD: 'discarded', DONATE: 'donated' };
  const txnEntries = txnRows.map((row) => ({
    id: `txn-${row.transaction_id}`,
    householdId: String(req.params.householdId),
    actingUserId: String(row.user_id),
    actingUserName: row.display_name,
    action: actionMap[row.transaction_type] ?? 'added',
    itemName: row.product_name,
    timestamp: row.transaction_time,
  }));

  const joinEntries = joinRows.map((row) => ({
    id: `join-${row.team_id}-${row.user_id}`,
    householdId: String(row.team_id),
    actingUserId: String(row.user_id),
    actingUserName: row.display_name,
    action: 'joined',
    itemName: '',
    timestamp: row.joined_at,
  }));

  const combined = [...txnEntries, ...joinEntries].sort(
    (a, b) => new Date(b.timestamp) - new Date(a.timestamp)
  );
  res.json(combined);
}));

module.exports = router;
