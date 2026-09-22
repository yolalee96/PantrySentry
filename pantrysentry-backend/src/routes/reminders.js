const express = require('express');
const pool = require('../db');
const { ApiError, asyncHandler } = require('../util/errors');
const { assertMember } = require('../util/household_access');

const router = express.Router();

// NOTE: schema.sql's reminders table has no column tracking whether the
// lead time was a preset or custom value (that's UI provenance only) —
// this API doesn't persist wasCustomLeadTime; it's always returned false.
function reminderRowToJson(row) {
  return {
    id: String(row.reminder_id),
    itemId: String(row.inventory_item_id),
    householdId: String(row.team_id),
    createdByUserId: String(row.created_by),
    leadTimeDays: row.lead_time_days,
    wasCustomLeadTime: false,
    triggered: row.status === 'TRIGGERED',
    triggeredAt: row.status === 'TRIGGERED' ? row.reminder_at : null,
  };
}

// POST /reminders { itemId, householdId, leadTimeDays }
// createdByUserId is always req.userId, never trusted from the body.
router.post('/reminders', asyncHandler(async (req, res) => {
  const { itemId, householdId, leadTimeDays } = req.body;
  if (!itemId || !householdId || !leadTimeDays) {
    throw new ApiError(400, 'itemId, householdId, leadTimeDays are required.');
  }
  await assertMember(req.userId, householdId);
  const createdByUserId = req.userId;

  const [itemRows] = await pool.query('SELECT expiry_date FROM inventory_items WHERE inventory_item_id = ?', [itemId]);
  if (itemRows.length === 0) throw new ApiError(404, 'Item not found.');
  if (!itemRows[0].expiry_date) throw new ApiError(409, 'This item has no expiry date set.');

  const [result] = await pool.query(
    `INSERT INTO reminders (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
     VALUES (?, ?, ?, ?, DATE_ADD(DATE_SUB(?, INTERVAL ? DAY), INTERVAL 9 HOUR))`,
    [itemId, householdId, createdByUserId, leadTimeDays, itemRows[0].expiry_date, leadTimeDays]
  );
  const [rows] = await pool.query('SELECT * FROM reminders WHERE reminder_id = ?', [result.insertId]);
  res.status(201).json(reminderRowToJson(rows[0]));
}));

// GET /households/:householdId/reminders
router.get('/households/:householdId/reminders', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const [rows] = await pool.query(
    "SELECT * FROM reminders WHERE team_id = ? AND status <> 'CANCELLED'",
    [req.params.householdId]
  );
  res.json(rows.map(reminderRowToJson));
}));

// POST /reminders/:id/mark-triggered
router.post('/reminders/:id/mark-triggered', asyncHandler(async (req, res) => {
  const [rows] = await pool.query('SELECT team_id FROM reminders WHERE reminder_id = ?', [req.params.id]);
  if (rows.length === 0) throw new ApiError(404, 'Reminder not found.');
  await assertMember(req.userId, rows[0].team_id);
  await pool.query("UPDATE reminders SET status = 'TRIGGERED' WHERE reminder_id = ? AND status = 'PENDING'", [req.params.id]);
  res.json({ ok: true });
}));

// POST /reminders/:id/cancel
// Was a known gap since Iteration 1 (schema.sql's CANCELLED status had no
// route) — needed so turning a reminder off during an edit actually
// removes it, instead of the old reminder silently staying active.
router.post('/reminders/:id/cancel', asyncHandler(async (req, res) => {
  const [rows] = await pool.query('SELECT team_id FROM reminders WHERE reminder_id = ?', [req.params.id]);
  if (rows.length === 0) throw new ApiError(404, 'Reminder not found.');
  await assertMember(req.userId, rows[0].team_id);
  await pool.query("UPDATE reminders SET status = 'CANCELLED', cancelled_at = NOW() WHERE reminder_id = ? AND status = 'PENDING'", [req.params.id]);
  res.json({ ok: true });
}));

module.exports = router;
