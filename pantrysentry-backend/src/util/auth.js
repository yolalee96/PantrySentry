const jwt = require('jsonwebtoken');
const { ApiError } = require('./errors');

const JWT_SECRET = process.env.JWT_SECRET;
const TOKEN_EXPIRY = '24h';
const RESET_TOKEN_EXPIRY = '30m';
const RESET_TOKEN_PURPOSE = 'password_reset';

if (!JWT_SECRET) {
  // Fail loudly rather than silently signing tokens with a guessable
  // default — a missing secret in production would make every token
  // forgeable. Set JWT_SECRET in your .env locally and in Vercel's
  // environment variables for the deployed backend (any long random
  // string works, e.g. generate one with `openssl rand -hex 32`).
  console.error('FATAL: JWT_SECRET is not set. Add it to your .env (local) or Vercel project settings (deployed).');
}

function signToken(userId) {
  return jwt.sign({ sub: String(userId) }, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });
}

/** Applied globally in app.js to everything except /health and /auth/*.
 * Verifies the Bearer token and sets req.userId (a string) for every
 * route below it to use for authorization checks. */
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return next(new ApiError(401, 'Missing or invalid Authorization header.'));
  }
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub;
    next();
  } catch (err) {
    next(new ApiError(401, 'Session expired or invalid — please sign in again.'));
  }
}

/** Password-reset tokens are short-lived signed JWTs, NOT stored in the
 * database (the schema has no column for them, and this also sidesteps
 * needing shared persistent storage across serverless invocations —
 * everything needed to verify the token travels inside the token itself).
 * `pwv` is a short slice of the user's CURRENT password hash at
 * send-time — if the password changes (via this reset or any other way)
 * before the token is used, the slice won't match anymore and the token
 * is rejected, giving one-time-use behaviour without a database. */
function signResetToken(userId, currentPasswordHash) {
  return jwt.sign(
    { sub: String(userId), purpose: RESET_TOKEN_PURPOSE, pwv: currentPasswordHash.slice(-12) },
    JWT_SECRET,
    { expiresIn: RESET_TOKEN_EXPIRY }
  );
}

/** Throws ApiError(400) on any invalid/expired/wrong-purpose token.
 * Returns { userId, pwv }. Caller still needs to check pwv against the
 * CURRENT password hash themselves (see routes/auth.js). */
function verifyResetToken(token) {
  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (err) {
    throw new ApiError(400, 'This reset link is invalid or has expired. Please request a new one.');
  }
  if (payload.purpose !== RESET_TOKEN_PURPOSE) {
    throw new ApiError(400, 'This reset link is invalid.');
  }
  return { userId: payload.sub, pwv: payload.pwv };
}

module.exports = { signToken, requireAuth, signResetToken, verifyResetToken };
