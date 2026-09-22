const express = require('express');
const bcrypt = require('bcryptjs');
const pool = require('../db');
const { avatarKeyToId, avatarIdToKey } = require('../util/avatars');
const { ApiError, asyncHandler } = require('../util/errors');
const { signToken, signResetToken, verifyResetToken } = require('../util/auth');
const { sendPasswordResetEmail } = require('../util/email');

const router = express.Router();

function userRowToJson(row) {
  return {
    id: String(row.user_id),
    name: row.display_name,
    email: row.email,
    avatarKey: avatarIdToKey(row.avatar_id),
  };
}

// POST /auth/signup { name, email, password, avatarKey }
router.post('/signup', asyncHandler(async (req, res) => {
  const { name, email, password, avatarKey } = req.body;
  if (!name || !email || !password) {
    throw new ApiError(400, 'name, email and password are required.');
  }
  const normalizedEmail = String(email).trim().toLowerCase();

  const [existing] = await pool.query('SELECT user_id FROM users WHERE email = ?', [normalizedEmail]);
  if (existing.length > 0) {
    throw new ApiError(409, 'An account already exists for that email.');
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const avatarId = avatarKeyToId(avatarKey) ?? 1;

  const [result] = await pool.query(
    'INSERT INTO users (email, password_hash, display_name, avatar_id) VALUES (?, ?, ?, ?)',
    [normalizedEmail, passwordHash, name, avatarId]
  );

  const [rows] = await pool.query('SELECT * FROM users WHERE user_id = ?', [result.insertId]);
  res.status(201).json({ ...userRowToJson(rows[0]), token: signToken(result.insertId) });
}));

// POST /auth/signin { email, password }
router.post('/signin', asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    throw new ApiError(400, 'email and password are required.');
  }
  const normalizedEmail = String(email).trim().toLowerCase();

  const [rows] = await pool.query('SELECT * FROM users WHERE email = ?', [normalizedEmail]);
  if (rows.length === 0) {
    throw new ApiError(401, 'Incorrect email or password.');
  }
  const match = await bcrypt.compare(password, rows[0].password_hash);
  if (!match) {
    throw new ApiError(401, 'Incorrect email or password.');
  }
  res.json({ ...userRowToJson(rows[0]), token: signToken(rows[0].user_id) });
}));

// POST /auth/forgot-password { email }
// Always returns 200 regardless of whether the email exists, to avoid
// leaking which addresses are registered. Sends a real email via Gmail
// SMTP containing a signed, 30-minute reset link — see util/email.js.
router.post('/forgot-password', asyncHandler(async (req, res) => {
  const { email } = req.body;
  if (!email) throw new ApiError(400, 'email is required.');
  const normalizedEmail = String(email).trim().toLowerCase();

  const [rows] = await pool.query('SELECT user_id, password_hash FROM users WHERE email = ?', [normalizedEmail]);
  if (rows.length > 0) {
    const resetToken = signResetToken(rows[0].user_id, rows[0].password_hash);
    await sendPasswordResetEmail(normalizedEmail, resetToken);
  }
  res.status(200).json({ ok: true });
}));

// POST /auth/reset-password { token, newPassword }
router.post('/reset-password', asyncHandler(async (req, res) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) throw new ApiError(400, 'token and newPassword are required.');
  if (newPassword.length < 8) throw new ApiError(400, 'Password must be at least 8 characters.');

  const { userId, pwv } = verifyResetToken(token);
  const [rows] = await pool.query('SELECT password_hash FROM users WHERE user_id = ?', [userId]);
  if (rows.length === 0) throw new ApiError(400, 'This reset link is invalid.');

  // The slice of the password hash at send-time must still match now —
  // if it doesn't, the password already changed since this link was
  // emailed (e.g. the link was already used once), so reject it. This
  // gives one-time-use behaviour without storing tokens anywhere.
  if (rows[0].password_hash.slice(-12) !== pwv) {
    throw new ApiError(400, 'This reset link has already been used. Please request a new one.');
  }

  const newHash = await bcrypt.hash(newPassword, 10);
  await pool.query('UPDATE users SET password_hash = ? WHERE user_id = ?', [newHash, userId]);
  res.json({ ok: true });
}));

module.exports = { router, userRowToJson };
