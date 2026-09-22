const express = require('express');
const cors = require('cors');
require('dotenv').config();

const { router: authRouter } = require('./routes/auth');
const usersRouter = require('./routes/users');
const householdsRouter = require('./routes/households');
const inventoryRouter = require('./routes/inventory');
const remindersRouter = require('./routes/reminders');
const activityRouter = require('./routes/activity');
const shelfLifeRouter = require('./routes/shelf_life');
const recognitionRouter = require('./routes/recognition');
const { ApiError } = require('./util/errors');
const { requireAuth } = require('./util/auth');

const app = express();
app.use(cors());
// Default express.json() limit is 100kb — far too small for a base64-
// encoded photo upload (a compressed ~150KB JPEG becomes ~200KB as
// base64). Recognition routes already separately cap the decoded image
// at 6MB (see decodeImageBody in recognition.js) — this just needs to be
// comfortably above that once base64-inflated, not the actual real limit.
app.use(express.json({ limit: '10mb' }));

app.get('/health', (req, res) => res.json({ ok: true }));

// Public — no token needed to sign up, sign in, or request a password reset.
app.use('/auth', authRouter);

// Everything below this line requires a valid Bearer token (see
// util/auth.js) — req.userId is then available to every route handler,
// and individual routes further check household membership/admin role
// where relevant (see util/household_access.js).
app.use(requireAuth);

app.use('/users', usersRouter);
// These routers define their own full paths internally (mixing
// /households/:id/... with /join-requests/... etc.), so they're all
// mounted at root rather than under a shared prefix.
app.use('/', householdsRouter);
app.use('/', inventoryRouter);
app.use('/', activityRouter);
app.use('/', remindersRouter);
app.use('/', shelfLifeRouter);
app.use('/', recognitionRouter);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: `No route for ${req.method} ${req.path}` });
});

// Central error handler — ApiError carries its own status code; anything
// else (e.g. a raw mysql2 error) becomes a 500 without leaking internals.
app.use((err, req, res, next) => {
  if (err instanceof ApiError) {
    return res.status(err.statusCode).json({ error: err.message });
  }
  console.error(err);
  res.status(500).json({ error: 'Internal server error.' });
});

module.exports = app;
