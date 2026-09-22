const express = require('express');
const pool = require('../db');
const { avatarKeyToId } = require('../util/avatars');
const { ApiError, asyncHandler } = require('../util/errors');
const { userRowToJson } = require('./auth');

const router = express.Router();

// GET /users/:id
router.get('/:id', asyncHandler(async (req, res) => {
  const [rows] = await pool.query('SELECT * FROM users WHERE user_id = ?', [req.params.id]);
  if (rows.length === 0) throw new ApiError(404, 'User not found.');
  res.json(userRowToJson(rows[0]));
}));

// PATCH /users/:id { name?, avatarKey? }  — AC 1.4.1
router.patch('/:id', asyncHandler(async (req, res) => {
  if (req.userId !== req.params.id) {
    throw new ApiError(403, 'You can only edit your own profile.');
  }
  const { name, avatarKey } = req.body;
  const updates = [];
  const params = [];
  if (name !== undefined) {
    updates.push('display_name = ?');
    params.push(name);
  }
  if (avatarKey !== undefined) {
    updates.push('avatar_id = ?');
    params.push(avatarKeyToId(avatarKey));
  }
  if (updates.length === 0) throw new ApiError(400, 'Nothing to update.');
  params.push(req.params.id);
  await pool.query(`UPDATE users SET ${updates.join(', ')} WHERE user_id = ?`, params);

  const [rows] = await pool.query('SELECT * FROM users WHERE user_id = ?', [req.params.id]);
  if (rows.length === 0) throw new ApiError(404, 'User not found.');
  res.json(userRowToJson(rows[0]));
}));

module.exports = router;
