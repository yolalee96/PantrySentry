const express = require('express');
const pool = require('../db');
const { avatarIdToKey } = require('../util/avatars');
const { ApiError, asyncHandler } = require('../util/errors');
const { assertMember, assertAdmin } = require('../util/household_access');

const router = express.Router();

function householdRowToJson(row) {
  return {
    id: String(row.team_id),
    name: row.team_name,
    createdAt: row.created_at,
  };
}

function memberRowToJson(row) {
  return {
    user: {
      id: String(row.user_id),
      name: row.display_name,
      email: row.email,
      avatarKey: avatarIdToKey(row.avatar_id),
    },
    role: row.role === 'ADMIN' ? 'admin' : 'member',
    status: row.status === 'ACTIVE' ? 'active' : 'inactive',
  };
}

function joinRequestRowToJson(row) {
  return {
    id: String(row.request_id),
    householdId: String(row.team_id),
    householdName: row.team_name,
    userId: String(row.user_id),
    userName: row.display_name,
    userAvatarKey: avatarIdToKey(row.avatar_id),
    status: row.status.toLowerCase(),
    requestedAt: row.requested_at,
    reviewedAt: row.reviewed_at,
    reviewedByUserId: row.reviewed_by ? String(row.reviewed_by) : null,
  };
}

// POST /households { name }  — AC 1.2.1. Creator is always req.userId
// (the authenticated caller), never trusted from the request body.
router.post('/households', asyncHandler(async (req, res) => {
  const { name } = req.body;
  if (!name) throw new ApiError(400, 'name is required.');

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [result] = await conn.query('INSERT INTO teams (team_name) VALUES (?)', [name]);
    await conn.query(
      'INSERT INTO team_members (team_id, user_id, role, status) VALUES (?, ?, \'ADMIN\', \'ACTIVE\')',
      [result.insertId, req.userId]
    );
    await conn.commit();
    const [rows] = await conn.query('SELECT * FROM teams WHERE team_id = ?', [result.insertId]);
    res.status(201).json(householdRowToJson(rows[0]));
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

// GET /households/:id — must be a member to view it.
router.get('/households/:id', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.id);
  const [rows] = await pool.query('SELECT * FROM teams WHERE team_id = ?', [req.params.id]);
  if (rows.length === 0) throw new ApiError(404, 'Household not found.');
  res.json(householdRowToJson(rows[0]));
}));

// GET /households/by-invite/:code — deliberately NOT membership-gated:
// this is how a non-member looks up a household before requesting to
// join it. Just needs to be signed in (requireAuth, applied globally).
router.get('/households/by-invite/:code', asyncHandler(async (req, res) => {
  const teamId = Number(req.params.code);
  if (!Number.isInteger(teamId)) {
    return res.status(404).json(null);
  }
  const [rows] = await pool.query('SELECT * FROM teams WHERE team_id = ?', [teamId]);
  if (rows.length === 0) return res.status(404).json(null);
  res.json(householdRowToJson(rows[0]));
}));

// GET /households/:id/members  — AC 1.2.2 / team_members join users
router.get('/households/:id/members', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.id);
  const [rows] = await pool.query(
    `SELECT tm.role, tm.status, u.user_id, u.display_name, u.email, u.avatar_id
     FROM team_members tm JOIN users u ON u.user_id = tm.user_id
     WHERE tm.team_id = ?`,
    [req.params.id]
  );
  res.json(rows.map(memberRowToJson));
}));

// POST /households/:id/leave — the authenticated user leaves this
// household. Uses req.userId only, never trusts a body param, so you
// can only ever remove your own membership, not someone else's.
//
// Deliberately does NOT block a sole admin from leaving a household
// that still has other members — there's no "promote another member to
// admin" feature yet, so a hard block would leave that person
// completely stuck with no way out. The frontend warns about this
// consequence in the confirmation dialog instead.
router.post('/households/:id/leave', asyncHandler(async (req, res) => {
  const [memberRows] = await pool.query(
    "SELECT 1 FROM team_members WHERE team_id = ? AND user_id = ? AND status = 'ACTIVE'",
    [req.params.id, req.userId]
  );
  if (memberRows.length === 0) {
    throw new ApiError(403, "You're not a member of this household.");
  }
  await pool.query(
    "UPDATE team_members SET status = 'INACTIVE' WHERE team_id = ? AND user_id = ?",
    [req.params.id, req.userId]
  );
  res.json({ ok: true });
}));

// POST /join-requests { inviteCode }  — AC 3.5.1 (revised). The
// requester is always req.userId, never trusted from the request body
// (otherwise anyone could submit a join request AS someone else).
router.post('/join-requests', asyncHandler(async (req, res) => {
  const { inviteCode } = req.body;
  const teamId = Number(inviteCode);
  if (!Number.isInteger(teamId)) {
    throw new ApiError(400, 'inviteCode is required.');
  }
  const userId = req.userId;

  const [teamRows] = await pool.query('SELECT * FROM teams WHERE team_id = ?', [teamId]);
  if (teamRows.length === 0) throw new ApiError(404, 'No household found for that invite code.');

  const [memberRows] = await pool.query(
    'SELECT 1 FROM team_members WHERE team_id = ? AND user_id = ?',
    [teamId, userId]
  );
  if (memberRows.length > 0) throw new ApiError(409, "You're already a member of this household.");

  // App-layer guard: MySQL can't express "one PENDING per (team,user)" as
  // a partial unique index — see schema.sql's README.
  const [pendingRows] = await pool.query(
    "SELECT 1 FROM join_requests WHERE team_id = ? AND user_id = ? AND status = 'PENDING'",
    [teamId, userId]
  );
  if (pendingRows.length > 0) {
    throw new ApiError(409, 'You already have a pending request for this household.');
  }

  const [result] = await pool.query(
    'INSERT INTO join_requests (team_id, user_id) VALUES (?, ?)',
    [teamId, userId]
  );
  const [rows] = await pool.query(
    `SELECT jr.*, t.team_name, u.display_name, u.avatar_id
     FROM join_requests jr
     JOIN teams t ON t.team_id = jr.team_id
     JOIN users u ON u.user_id = jr.user_id
     WHERE jr.request_id = ?`,
    [result.insertId]
  );
  res.status(201).json(joinRequestRowToJson(rows[0]));
}));

// GET /households/:id/join-requests?status=pending — admin-only: this is
// the review queue, not something a regular member should see.
router.get('/households/:id/join-requests', asyncHandler(async (req, res) => {
  await assertAdmin(req.userId, req.params.id);
  const status = (req.query.status || 'pending').toUpperCase();
  const [rows] = await pool.query(
    `SELECT jr.*, t.team_name, u.display_name, u.avatar_id
     FROM join_requests jr
     JOIN teams t ON t.team_id = jr.team_id
     JOIN users u ON u.user_id = jr.user_id
     WHERE jr.team_id = ? AND jr.status = ?`,
    [req.params.id, status]
  );
  res.json(rows.map(joinRequestRowToJson));
}));

// GET /join-requests/:id — for the requester's own "waiting" screen to
// poll. Restricted to the person who submitted it — nobody else should
// be able to watch someone else's pending request resolve.
router.get('/join-requests/:id', asyncHandler(async (req, res) => {
  const [rows] = await pool.query(
    `SELECT jr.*, t.team_name, u.display_name, u.avatar_id
     FROM join_requests jr
     JOIN teams t ON t.team_id = jr.team_id
     JOIN users u ON u.user_id = jr.user_id
     WHERE jr.request_id = ?`,
    [req.params.id]
  );
  if (rows.length === 0) throw new ApiError(404, 'Join request not found.');
  if (String(rows[0].user_id) !== req.userId) {
    throw new ApiError(403, "You can only view your own join requests.");
  }
  res.json(joinRequestRowToJson(rows[0]));
}));

// POST /join-requests/:id/approve — admin-only. reviewedByUserId is
// always req.userId, never trusted from the body.
router.post('/join-requests/:id/approve', asyncHandler(async (req, res) => {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rows] = await conn.query('SELECT * FROM join_requests WHERE request_id = ? FOR UPDATE', [req.params.id]);
    if (rows.length === 0) throw new ApiError(404, 'Join request not found.');
    const request = rows[0];
    if (request.status !== 'PENDING') throw new ApiError(409, 'This request has already been reviewed.');
    await assertAdmin(req.userId, request.team_id);

    await conn.query(
      "UPDATE join_requests SET status = 'APPROVED', reviewed_at = NOW(), reviewed_by = ? WHERE request_id = ?",
      [req.userId, req.params.id]
    );
    await conn.query(
      "INSERT INTO team_members (team_id, user_id, role, status) VALUES (?, ?, 'MEMBER', 'ACTIVE')",
      [request.team_id, request.user_id]
    );
    await conn.commit();
    res.json({ ok: true });
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

// POST /join-requests/:id/decline — admin-only.
router.post('/join-requests/:id/decline', asyncHandler(async (req, res) => {
  const [rows] = await pool.query('SELECT team_id, status FROM join_requests WHERE request_id = ?', [req.params.id]);
  if (rows.length === 0) throw new ApiError(404, 'Join request not found.');
  if (rows[0].status !== 'PENDING') throw new ApiError(409, 'This request has already been reviewed.');
  await assertAdmin(req.userId, rows[0].team_id);

  const [result] = await pool.query(
    "UPDATE join_requests SET status = 'DECLINED', reviewed_at = NOW(), reviewed_by = ? WHERE request_id = ? AND status = 'PENDING'",
    [req.userId, req.params.id]
  );
  if (result.affectedRows === 0) throw new ApiError(409, 'This request has already been reviewed.');
  res.json({ ok: true });
}));

// GET /users/:userId/households — restricted to querying your own
// membership only (can't look up someone else's households).
router.get('/users/:userId/households', asyncHandler(async (req, res) => {
  if (req.userId !== req.params.userId) throw new ApiError(403, "You can only view your own households.");
  const [rows] = await pool.query(
    `SELECT t.* FROM team_members tm
     JOIN teams t ON t.team_id = tm.team_id
     WHERE tm.user_id = ? AND tm.status = 'ACTIVE'
     ORDER BY tm.joined_at DESC`,
    [req.params.userId]
  );
  res.json(rows.map(householdRowToJson));
}));

// GET /users/:userId/join-requests?status=pending — same restriction.
router.get('/users/:userId/join-requests', asyncHandler(async (req, res) => {
  if (req.userId !== req.params.userId) throw new ApiError(403, "You can only view your own join requests.");
  const status = (req.query.status || 'pending').toUpperCase();
  const [rows] = await pool.query(
    `SELECT jr.*, t.team_name, u.display_name, u.avatar_id
     FROM join_requests jr
     JOIN teams t ON t.team_id = jr.team_id
     JOIN users u ON u.user_id = jr.user_id
     WHERE jr.user_id = ? AND jr.status = ?`,
    [req.params.userId, status]
  );
  res.json(rows.map(joinRequestRowToJson));
}));

module.exports = router;
module.exports.householdRowToJson = householdRowToJson;
